# Parameter Guide — extract-smbh-binaries

Authoritative per-parameter extraction rules for the `extract-smbh-binaries` skill. The skill's SKILL.md gives the workflow; this file gives the *contents*. Read it before your first extraction on a given paper — the error-type formats and evidence-category enums are easy to get wrong from memory.

**Table of contents**

1. Core rule: extract, don't compute
2. Error types (for asterisked parameters)
3. Field-by-field rules
4. Evidence categories (fixed enums)
5. Unit conventions
6. Multi-model papers (use Range)
7. Worked snippets

---

## 1. Core rule: extract, don't compute

Every value must be traceable to a specific sentence, table cell, or figure in the paper. The only transformations you may apply are *representations* of the same quantity:

- Linear mass → `log10(M☉)`
- Natural log → base-10 log
- Calendar date → MJD
- Years → days, seconds → Hz, parsecs ↔ kpc, arcseconds ↔ radians
- Hz ↔ days (P = 1/f)

You may **not**:

- Compute total mass from M1 + M2 (or vice versa) unless the paper itself prints the total
- Derive chirp mass from component masses
- Compute q from M1 and M2 unless the paper prints q
- Convert a "dual AGN projected separation in kpc" to a semi-major axis
- Fill in "typical" values because the paper is silent

If the paper doesn't state it, leave the key out (or set it to `null`).

If it's close to the line — e.g., the paper says "we adopt the M–σ relation" and you can see the black-hole mass in a table — it's still the paper's number. Record it with `note: "from M–σ relation"` on the measured-value object and a mention in `caveats`.

---

## 2. Error types

Asterisked parameters are stored as `measuredValue` objects with `{value, error, error_type, unit, note}`. The `error` field's format depends on `error_type`:

| `error_type`     | Meaning                                                                                                                                      | `error` field format                                |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------|
| `Assumed`        | Value is assumed to make other model params tractable (e.g. circular orbit, e = 0, or a fixed inclination).                                  | `null`                                               |
| `Lower limit`    | Paper states the value as a lower bound (`M > 10⁹ M☉`).                                                                                      | bare number = the limit itself (no `>` sign)        |
| `Upper limit`    | Paper states the value as an upper bound (`e < 0.1`).                                                                                        | bare number = the limit itself (no `<` sign)        |
| `Gaussian`       | Standard ± symmetric uncertainty (`9.2 ± 0.3`).                                                                                              | bare number = the 1σ                                |
| `Two sided`      | Skewed or asymmetric errors (`9.2 ₋0.1 ⁺0.4`).                                                                                               | string `"(-0.1,+0.4)"` — negative first, comma, positive. No spaces, explicit signs. |
| `Range`          | Paper gives a range, e.g., "between 8.5 and 9.7" or several model variants spanning 8.5–9.7.                                                 | record `value` = mean of the range; `error` = bare number = half-width. Or `"(-low,+high)"` string if the range is asymmetric about the mean. |
| `Representative` | Single number with no quoted error; also used for values pulled from another paper, or values from a scaling relation quoted without errors. | `null`                                               |

### Picking between `Gaussian` and `Two sided`

If the paper prints `σ = 0.3` or `± 0.3`, it's Gaussian. If it prints `₋0.1 ⁺0.4` (LaTeX `^{+0.4}_{-0.1}`) — even if one side happens to equal the other — it's Two sided. Preserve the reporting style.

### Picking between `Range` and `Two sided`

- *Two sided* is for asymmetric statistical uncertainty on a single best-fit value.
- *Range* is for (a) the paper says "between X and Y" without picking a best fit, or (b) the paper gives several model variants (different spin priors, accretion rates, binary/single fits) and each yields a different value. In case (b), the candidate is still *one* candidate — use Range over the span of model outputs and note the model variation in `caveats`.

### Picking `Assumed` vs `Representative`

- *Assumed* is for values the authors explicitly set to make the model go (`e = 0` for a circular orbit, `i = 60°` as a fiducial viewing angle).
- *Representative* is for values the authors report in passing with no error — typical for masses taken from someone else's paper or estimated from scaling relations without quoted uncertainty.

---

## 3. Field-by-field rules

### `source_standard_name` (string, no error)

The primary formal name used for the source in the paper. Examples: `SDSS J0159+0033`, `OJ 287`, `PG 1302-102`, `NGC 4151`, `PSR B1913+16`. Prefer the most commonly cataloged name. If the paper introduces a new internal designation and *also* refers to the object by a standard catalog name, use the standard catalog name here and put the internal designation in `source_nickname`.

### `source_nickname` (string, no error)

Any informal or paper-specific name, if different from the standard name. Examples: `"Spikey"` for ZTF19aailpwl, `"the OJ 287 system"`, `"Source A"` in a multi-object table. If the paper uses only the standard name, leave this blank.

### `ra_j2000`, `dec_j2000` (string, no error)

J2000 equatorial coordinates. Sexagesimal or decimal-degree string — match the paper's format. If the paper only gives Galactic coordinates or a source name with no coordinates, leave blank; do not look up an external catalog.

### `redshift` (number, no error)

Cosmological redshift. Plain number. Not an asterisked parameter; no error structure.

If the paper reports `z ± δz`, just record `z` as the number and drop the uncertainty — this field is deliberately simple. Flag the uncertainty in `caveats` if it's large enough to matter for the candidate's interpretation.

### `eccentricity` (measuredValue, unit: dimensionless)

Orbital eccentricity, 0 ≤ e < 1. If the paper says "we assume a circular orbit", record `value: 0`, `error_type: "Assumed"`. If the paper gives an upper limit, record `error_type: "Upper limit"` with the limit in `error`.

### `log_m1`, `log_m2` (measuredValue, unit: `log10(Msun)`)

`log_m1` is the **larger** mass, `log_m2` is the **smaller** mass. Always store as log10 in solar masses (expected range ~5 to ~12). Convert linear masses to log10 when necessary — that's a representation conversion, not new physics.

**Do not** split a quoted `M_total` between `log_m1` and `log_m2` using q. Record `log_total_mass` directly and leave `log_m1`/`log_m2` blank unless the paper prints them separately.

For mass values pulled from scaling relations without quoted errors, use `error_type: "Representative"` and set `note: "from M–σ relation"` (or whichever relation) on the measured-value object.

### `log_total_mass` (measuredValue, unit: `log10(Msun)`)

Total mass of the system, log10(M☉). This is the field to use when the paper says "the black hole mass is ..." in a binary context — that language usually means the total mass of the binary (or the mass of the single black hole if the binary hypothesis fails). Note the provenance (dynamical, virial, scaling relation, etc.) in `caveats`.

### `log_chirp_mass`, `log_reduced_mass` (measuredValue, unit: `log10(Msun)`)

Chirp mass `Mc = (M1·M2)^(3/5) / (M1+M2)^(1/5)` and reduced mass `μ = M1·M2/(M1+M2)`. Only record if the paper *explicitly prints* them. Do not compute them from M1/M2.

### `q` (measuredValue, unit: dimensionless)

Mass ratio, `q = M2/M1` with the convention 0 < q ≤ 1. If the paper uses the opposite convention (q > 1), invert to stay in (0, 1]. Record the inversion in `caveats`.

### `inclination_deg` (measuredValue, unit: `deg`)

Orbital inclination, 0–90°. If a paper quotes an inclination > 90° (e.g., `120°`), fold it to `180° - i` = 60° — these are degenerate by symmetry and we restrict to the 0–90° range.

### `semi_major_axis_pc` (measuredValue, unit: `pc`)

Binary orbit's semi-major axis in the source rest frame. Convert AU / gravitational radii / light-days / pc as needed. If the paper gives a semi-major axis in gravitational radii (`a = 1000 r_g`), you *may* convert *only if* the paper also prints a mass you can use for the conversion — and even then, note the conversion in `caveats` and cite which mass you used.

### `semi_major_axis_date_mjd` (measuredValue, unit: `MJD`)

Date on which the semi-major axis was measured/inferred, as MJD. For most binary candidates the orbit evolves slowly enough that this is roughly the midpoint of the relevant observing campaign. It's OK to approximate from a figure and mark `error_type: "Range"` with the campaign span.

### `separation_pc` (measuredValue, unit: `pc`)

For *spatially resolved* candidates (dual AGN, resolved imaging), the projected separation on the sky in parsecs. Not the same as `semi_major_axis_pc`. A resolved dual AGN will usually have `separation_pc` set and `semi_major_axis_pc` blank (no orbital fit); a compact binary with a fitted model will have `semi_major_axis_pc` set and `separation_pc` blank.

### `period_epoch_mjd` (measuredValue, unit: `MJD`)

The date of the observed data from which the period/frequency was derived — **not** the publication date of the paper. For a light curve spanning many years, record the midpoint of the data used, with `error_type: "Range"` and half-width = half the span. If the paper only plots the data on a figure, it's OK to estimate from the figure axis and say so in `caveats`.

### `orbital_frequency_hz` (measuredValue, unit: `Hz`)

Orbital frequency in the **Earth (observer) reference frame**, not the source rest frame. If the paper reports only the rest-frame frequency with a redshift, you may apply `f_obs = f_rest / (1+z)` as a representation conversion. Flag the conversion in `caveats`.

### `orbital_period_days` (measuredValue, unit: `days`)

Orbital period in the **Earth (observer) frame**, in days. Convert from years/months/seconds as needed. If both period and frequency are reported, record both; they're not redundant for error propagation.

### `summary_notes` (string, no error)

One short paragraph. What is this source? What's the headline evidence? Anything quirky about the analysis that a future reader should know? 2–5 sentences is the right scale — not an abstract, not a one-liner.

### `caveats` (string, no error)

Uncertainty in the interpretation of the recorded parameters. Examples:

- "log_total_mass is from the M–σ relation, not dynamical."
- "orbital_period_days read off Fig. 4 rather than quoted in the text."
- "Authors fit the light curve with both a circular (P = 5.2 yr) and eccentric (P = 5.0 yr, e = 0.3) model; recorded as a Range on orbital_period_days and eccentricity."
- "q convention inverted from the paper's M1/M2 > 1 definition to keep q in (0, 1]."

### `extension_project` (string, no error)

A class-project idea scoped to a student following up on this paper. A few sentences. Mark undergrad or grad. Good examples: "Undergrad: extend the CRTS+ZTF light curve with LSST DR1 data and refit the period to test whether the claimed periodicity persists in the new epoch"; "Grad: reanalyze the VLBI data with a jet-precession model and compare the required precession rate against the orbital decay prediction from GW emission at the reported separation."

Leave blank if nothing natural comes to mind. Don't force it.

---

## 4. Evidence categories

`evidence` is a list of one or more `{type, note, waveband}` objects. The `type` values are frozen. The `note` values below are the allowed subcategories for each type — match them roughly (the validator doesn't enforce the note enum, only the type enum, so paraphrases are OK as long as the intent is clear).

### `emission_line_variability`
Time-varying emission lines interpreted as supporting binary behavior.
- Broad-line velocity shifts
- Narrow-line velocity shifts
- Other BLR/NLR (e.g. sudden appearance of additional line feature)

### `emission_line_snapshot`
Single-epoch emission-line abnormalities interpreted as supporting binary behavior.
- Multiple narrow-line peaks
- Multiple broad-line peaks
- Other abnormal BLR (e.g. asymmetries)
- Other abnormal NLR

### `continuum_flux_variations`
Time-varying flux variations interpreted as supporting binary behavior.
- Continuous light curve variation with periodicity
- Discrete bursts with periodicity
- Correlated multi-band variations

### `spatially_resolved_offset_or_dual_active_nucleus`
Data implying two spatially resolved black holes.
- Dual nuclei
- Active nucleus offset from photometric or kinematic center

### `pc_scale_jet_features`
High-resolution, parsec-scale jet features interpreted as supporting binary behavior.
- Helical structure
- Time-resolved helical outflow
- CSO/CSS source

### `large_scale_jet_features`
Large-scale features in a radio jet interpreted as supporting binary behavior.
- X/S/Z/helical shaped sources
- Spatial periodicity

### `galaxy_features`
Features in the host galaxy interpreted as supporting binary behavior.
- Morphological: tidal tails, asymmetry, dual stellar core
- Flat-cored galaxy / light deficit
- Enhanced tidal disruption rates
- Very massive galaxy
- Other secondary merger indicators (heightened star formation, ULIRG, etc.)

### `gravitational_wave_emission`
- PTA: GW memory
- PTA: Continuous waves
- Space: GW memory
- Space: Continuous waves

### `broad_band_SED`
A broad-band spectral energy distribution interpreted as supporting binary behavior. Usually no subcategory — leave `note` blank or put a short description.

### Waveband enum

Allowed values for `evidence.waveband`: `gamma-ray`, `x-ray`, `UV`, `optical`, `IR`, `radio`. Use `null` only when the evidence genuinely spans all bands (e.g., a cross-band correlation analysis) — in that case, prefer to record *multiple* evidence entries, one per band.

---

## 5. Unit conventions (canonical units — the schema assumes these)

| Field                      | Canonical unit    |
|----------------------------|-------------------|
| `log_m1`, `log_m2`, `log_total_mass`, `log_chirp_mass`, `log_reduced_mass` | `log10(Msun)` |
| `q`, `eccentricity`        | dimensionless     |
| `inclination_deg`          | degrees (0–90)    |
| `semi_major_axis_pc`, `separation_pc` | parsecs   |
| `semi_major_axis_date_mjd`, `period_epoch_mjd` | MJD days |
| `orbital_frequency_hz`     | Hz (Earth frame)  |
| `orbital_period_days`      | days (Earth frame)|

If the paper uses a different unit, convert to the canonical unit when you record the value. That's representation, not physics.

---

## 6. Multi-model papers

If a paper fits the same candidate with several theoretical variants (different spin priors, different accretion rates, circular vs eccentric fits, etc.), it's still **one candidate**. For parameters that change across the variants, use `error_type: "Range"` spanning the variant outputs:

```json
"log_total_mass": {
  "value": 9.1,
  "error": 0.2,
  "error_type": "Range",
  "unit": "log10(Msun)",
  "note": "span across three model variants (fiducial / high-spin / low-accretion)"
}
```

Mention the model variation explicitly in `caveats` so a downstream reader knows the Range reflects model assumption spread, not statistical uncertainty.

---

## 7. Worked snippets

**Paper says**: "We fit the V-band light curve with a sinusoid of period P = 5.2 ± 0.1 years."

```json
"orbital_period_days": {
  "value": 1899,
  "error": 37,
  "error_type": "Gaussian",
  "unit": "days"
}
```

Conversion: 5.2 yr × 365.25 = 1899.3 days; 0.1 yr × 365.25 ≈ 37 days.

**Paper says**: "The total mass inferred from the M–σ relation is ~3 × 10⁹ M☉."

```json
"log_total_mass": {
  "value": 9.48,
  "error": null,
  "error_type": "Representative",
  "unit": "log10(Msun)",
  "note": "from M–σ relation"
}
```

Also: add `"caveats": "log_total_mass is from the M–σ relation, not dynamical. No uncertainty quoted."`

**Paper says**: "We adopt e = 0 for simplicity."

```json
"eccentricity": {
  "value": 0,
  "error": null,
  "error_type": "Assumed",
  "unit": ""
}
```

**Paper says**: "The mass ratio lies in the range 0.1–0.4, with a best-fit value of 0.25."

```json
"q": {
  "value": 0.25,
  "error": "(-0.15,+0.15)",
  "error_type": "Range",
  "unit": ""
}
```

**Paper says**: "log(M/M☉) = 9.2 ⁺⁰·⁴ ₋₀·₁"

```json
"log_total_mass": {
  "value": 9.2,
  "error": "(-0.1,+0.4)",
  "error_type": "Two sided",
  "unit": "log10(Msun)"
}
```

**Paper says**: "The broad Hβ line shows a velocity shift of 500 km/s between 2005 and 2015."

```json
"evidence": [
  {
    "type": "emission_line_variability",
    "note": "Broad-line velocity shifts",
    "waveband": "optical"
  }
]
```

**Paper says**: "VLBI imaging at 43 GHz reveals two compact cores separated by 7.3 pc."

```json
"separation_pc": {
  "value": 7.3,
  "error": null,
  "error_type": "Representative",
  "unit": "pc"
},
"evidence": [
  {
    "type": "spatially_resolved_offset_or_dual_active_nucleus",
    "note": "Dual nuclei",
    "waveband": "radio"
  }
]
```
