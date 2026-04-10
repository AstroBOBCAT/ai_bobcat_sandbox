#!/usr/bin/env python3
"""
validate_candidates.py — validate an SMBH binary candidates JSON file.

Usage:
    validate_candidates.py <path-to-candidates.json> [<more-paths>...]

Validates each file against the shape described in references/schema.json.
Stdlib-only (no jsonschema dependency) so it runs anywhere Python 3 does.

Exit codes:
    0  all files valid
    1  one or more files had errors
    2  bad invocation

Errors print to stderr; a single-line summary per file prints to stdout.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# ---- Enums (mirror references/schema.json) ----

ALLOWED_ERROR_TYPES = {
    None,
    "Assumed",
    "Lower limit",
    "Upper limit",
    "Gaussian",
    "Two sided",
    "Range",
    "Representative",
}

ALLOWED_EVIDENCE_TYPES = {
    "emission_line_variability",
    "emission_line_snapshot",
    "continuum_flux_variations",
    "spatially_resolved_offset_or_dual_active_nucleus",
    "pc_scale_jet_features",
    "large_scale_jet_features",
    "galaxy_features",
    "gravitational_wave_emission",
    "broad_band_SED",
}

ALLOWED_WAVEBANDS = {None, "gamma-ray", "x-ray", "UV", "optical", "IR", "radio"}

# Asterisked measurement fields — each, if present, must be a measuredValue object.
MEASURED_FIELDS = [
    "eccentricity",
    "log_m1",
    "log_m2",
    "log_total_mass",
    "log_chirp_mass",
    "log_reduced_mass",
    "q",
    "inclination_deg",
    "semi_major_axis_pc",
    "semi_major_axis_date_mjd",
    "separation_pc",
    "period_epoch_mjd",
    "orbital_frequency_hz",
    "orbital_period_days",
]

# Mass fields get a sanity-range check (log10 Msun, 5..12)
LOG_MASS_FIELDS = {
    "log_m1",
    "log_m2",
    "log_total_mass",
    "log_chirp_mass",
    "log_reduced_mass",
}

# All top-level candidate keys the schema allows (used only to warn on typos).
CANDIDATE_KEYS = {
    "source_standard_name",
    "source_nickname",
    "ra_j2000",
    "dec_j2000",
    "redshift",
    "evidence",
    "summary_notes",
    "caveats",
    "extension_project",
} | set(MEASURED_FIELDS)

TOP_LEVEL_KEYS = {"bibcode", "paper", "candidate_count", "candidates"}


class Issues:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, path: str, msg: str) -> None:
        self.errors.append(f"{path}: {msg}")

    def warn(self, path: str, msg: str) -> None:
        self.warnings.append(f"{path}: {msg}")


def _is_number(x: Any) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def _validate_measured(field: str, obj: Any, path: str, issues: Issues) -> None:
    """Validate a measuredValue sub-object."""
    if obj is None:
        return  # absent / null is fine
    if not isinstance(obj, dict):
        issues.err(path, f"{field} must be an object or null, got {type(obj).__name__}")
        return
    if "value" not in obj:
        issues.err(path, f"{field}.value is required")
    err_type = obj.get("error_type", None)
    if err_type not in ALLOWED_ERROR_TYPES:
        issues.err(
            path,
            f"{field}.error_type={err_type!r} not in {sorted(t for t in ALLOWED_ERROR_TYPES if t)}",
        )
    # Cross-field: Assumed/Representative → error should be null
    if err_type in {"Assumed", "Representative"}:
        if obj.get("error") not in (None, ""):
            issues.warn(
                path, f"{field}.error should be null when error_type={err_type!r}"
            )
    # Two sided → error should be a string shaped like (-x,+y)
    if err_type == "Two sided":
        err = obj.get("error")
        if not isinstance(err, str) or not (err.startswith("(") and err.endswith(")") and "," in err):
            issues.warn(
                path,
                f'{field}.error should look like "(-x,+y)" when error_type="Two sided", got {err!r}',
            )
    # Mass sanity range
    if field in LOG_MASS_FIELDS:
        val = obj.get("value")
        if _is_number(val) and not (4.0 <= val <= 12.5):
            issues.err(
                path,
                f"{field}.value={val} is outside the plausible log10(Msun) range [5,12] — unit mistake?",
            )
    if field == "inclination_deg":
        val = obj.get("value")
        if _is_number(val) and not (0.0 <= val <= 90.0):
            issues.err(
                path,
                f"{field}.value={val} is outside the allowed range [0,90] — fold to (180-i) if needed",
            )
    if field == "q":
        val = obj.get("value")
        if _is_number(val) and not (0.0 < val <= 1.0):
            issues.err(
                path,
                f"{field}.value={val} is outside (0,1]; if the paper uses M1/M2 > 1, invert",
            )
    if field == "eccentricity":
        val = obj.get("value")
        if _is_number(val) and not (0.0 <= val < 1.0):
            issues.err(
                path,
                f"{field}.value={val} is outside [0,1) for a bound orbit",
            )


def _validate_evidence(ev_list: Any, path: str, issues: Issues) -> None:
    if not isinstance(ev_list, list):
        issues.err(path, f"evidence must be a list, got {type(ev_list).__name__}")
        return
    if len(ev_list) == 0:
        issues.err(path, "evidence must contain at least one entry")
        return
    for i, ev in enumerate(ev_list):
        ep = f"{path}.evidence[{i}]"
        if not isinstance(ev, dict):
            issues.err(ep, f"entry must be an object, got {type(ev).__name__}")
            continue
        t = ev.get("type")
        if t not in ALLOWED_EVIDENCE_TYPES:
            issues.err(ep, f"type={t!r} not in {sorted(ALLOWED_EVIDENCE_TYPES)}")
        wb = ev.get("waveband", None)
        if wb not in ALLOWED_WAVEBANDS:
            issues.err(
                ep,
                f"waveband={wb!r} not in {sorted(w for w in ALLOWED_WAVEBANDS if w)}",
            )


def _validate_candidate(cand: Any, path: str, issues: Issues) -> None:
    if not isinstance(cand, dict):
        issues.err(path, f"candidate must be an object, got {type(cand).__name__}")
        return

    if not cand.get("source_standard_name"):
        issues.err(path, "source_standard_name is required and must be non-empty")

    # Flag unknown keys (likely typos)
    for k in cand.keys():
        if k not in CANDIDATE_KEYS:
            issues.warn(path, f"unknown candidate field {k!r}")

    # Measured fields
    for field in MEASURED_FIELDS:
        if field in cand:
            _validate_measured(field, cand[field], path, issues)

    # Redshift is a plain number (not measured)
    if "redshift" in cand and cand["redshift"] is not None and not _is_number(cand["redshift"]):
        issues.err(
            path,
            f"redshift must be a number or null, got {type(cand['redshift']).__name__}",
        )

    # Evidence
    if "evidence" not in cand:
        issues.err(path, "evidence is required")
    else:
        _validate_evidence(cand["evidence"], path, issues)


def validate_file(path: Path) -> Issues:
    issues = Issues()
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        issues.err(str(path), "file not found")
        return issues
    except json.JSONDecodeError as e:
        issues.err(str(path), f"invalid JSON: {e}")
        return issues

    if not isinstance(data, dict):
        issues.err(str(path), f"top-level must be an object, got {type(data).__name__}")
        return issues

    for k in data.keys():
        if k not in TOP_LEVEL_KEYS:
            issues.warn(str(path), f"unknown top-level field {k!r}")

    if not data.get("bibcode"):
        issues.err(str(path), "bibcode is required and must be non-empty")

    candidates = data.get("candidates")
    if not isinstance(candidates, list):
        issues.err(str(path), "candidates is required and must be a list")
        return issues

    if "candidate_count" in data:
        cc = data["candidate_count"]
        if not isinstance(cc, int) or cc < 0:
            issues.err(str(path), f"candidate_count must be a non-negative int, got {cc!r}")
        elif cc != len(candidates):
            issues.err(
                str(path),
                f"candidate_count={cc} does not match candidates.length={len(candidates)}",
            )

    for i, cand in enumerate(candidates):
        _validate_candidate(cand, f"{path}.candidates[{i}]", issues)

    return issues


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: validate_candidates.py <path-to-candidates.json> [<more-paths>...]",
            file=sys.stderr,
        )
        return 2

    any_errors = False
    for arg in argv[1:]:
        path = Path(arg)
        issues = validate_file(path)
        for w in issues.warnings:
            print(f"warning: {w}", file=sys.stderr)
        for e in issues.errors:
            print(f"error: {e}", file=sys.stderr)
        status = "ok" if not issues.errors else "FAIL"
        print(
            f"{path}: {status} "
            f"({len(issues.errors)} error(s), {len(issues.warnings)} warning(s))"
        )
        if issues.errors:
            any_errors = True

    return 1 if any_errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
