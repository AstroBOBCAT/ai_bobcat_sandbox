---
name: extract-smbh-binaries
description: Extract structured binary supermassive black hole (SMBH) candidate models from astrophysics papers — source names, coordinates, masses, orbital parameters, and the observational evidence that makes each source a binary candidate. Use this skill whenever the user wants to read a paper and pull out binary SMBH candidate parameters, count how many distinct binary black hole candidates a paper describes, tabulate candidates from the literature, populate a binary candidate catalog/database, or build candidate entries from a PDF / text extract / paper already sitting in ./papers/. Trigger even when the user doesn't explicitly say "SMBH" or "binary model" — requests like "extract the candidate from this paper", "how many binaries are in Smith+24", or "make catalog entries for all the sources this paper discusses" all apply. Also trigger on phrases like "binary black hole candidate", "SMBHB candidate", "MBHB candidate", "dual AGN candidate with orbital parameters", "OJ 287 binary model", or any request to distill binary BH candidate reporting into structured records. Do not use for general literature search (use ads-search instead) or free-form paper summarization.
allowed-tools: Bash(./.claude/skills/extract-smbh-binaries/scripts/prepare_paper.sh:*), Bash(.claude/skills/extract-smbh-binaries/scripts/prepare_paper.sh:*), Bash(./.claude/skills/extract-smbh-binaries/scripts/validate_candidates.py:*), Bash(.claude/skills/extract-smbh-binaries/scripts/validate_candidates.py:*), Bash(pdftotext:*), Bash(pdftoppm:*), Bash(mkdir:*), Bash(ls:*), Bash(test:*), Read, Write, Edit, Glob, Grep
---

# extract-smbh-binaries

Turn a binary-SMBH-candidate paper into a structured JSON record that conforms to a fixed catalog schema. The output is one JSON file per paper at `./candidates/<bibcode>.json`, containing a paper-level header and a list of candidate entries — one entry per distinct binary SMBH candidate the paper describes.

This skill is *extractive*, not generative. Every parameter you record must be traceable to a specific statement, table row, or figure in the paper. The rest of this document explains how to walk that line: what "distinct candidate" means, how to map paper claims onto the schema, and when to leave fields blank.

## When this skill applies

Use it whenever the user wants structured binary-candidate data pulled out of a paper, including:

- "Extract the binary model(s) from this paper"
- "How many binary SMBH candidates does X+YY describe?"
- "Build a candidate entry for the source reported in papers/2026arXiv260406059T"
- "Tabulate the masses, periods, and evidence types for the candidates in this PDF"
- Any request to populate or update `./candidates/` from a paper

Don't use it for: literature search (that's `ads-search`), free-form paper summarization, or computing new physics from the paper's data.

## The workflow at a glance

1. **Locate the paper.** Resolve the user's input to a PDF and/or text file and a bibcode-shaped stem.
2. **Prepare it.** Call `scripts/prepare_paper.sh` once — it gives you a flat text extract plus a directory of per-page PNGs you can load with `Read` to see figures and tables multimodally.
3. **Read the whole paper.** Read the text file end-to-end first. Figures/tables in the PNGs are a second pass, not a substitute.
4. **Identify candidates.** Count the *distinct astrophysical objects* the paper frames as binary SMBH candidates. Do not inflate the count with control sources, comparison AGN, or theoretical toy models.
5. **Build one candidate entry per distinct object**, filling in only parameters the paper actually states. Leave everything else blank.
6. **Write `./candidates/<bibcode>.json`.** Refuse to overwrite an existing file unless the user passed `--force` or explicitly confirms.
7. **Validate.** Run `scripts/validate_candidates.py <path>` and fix any reported errors before reporting done.
8. **Report** to the user: how many candidates, their standard names, a one-line summary of each, and the output path.

## Step 1 — locate the paper

Accept any of:

- A path to a `.pdf` file
- A path to a `.txt` file (plain text, usually from `pdftotext -layout`)
- A bare stem/bibcode (e.g. `2026arXiv260406059T`), which you'll resolve against `./papers/<stem>.{pdf,txt}`
- Raw paper text pasted into the conversation — in this case, skip `prepare_paper.sh` and work directly from the pasted text; there will be no page images

The bibcode you write into the output JSON should be the paper's ADS bibcode when it's available (from the filename stem, a "bibcode: ..." line in the text, or the ADS page). If you can't find one, fall back to a stable stem like the arXiv ID. Flag the choice in your report so the user can correct it.

## Step 2 — prepare the paper

Run from the repo root:

```bash
.claude/skills/extract-smbh-binaries/scripts/prepare_paper.sh <path-or-stem>
```

The script prints four lines to stdout:

```
STEM=<filename stem>
TEXT=<path to .txt>
IMAGES=<directory containing page-NN.png files>
PAGES=<number of page images>
```

Under the hood it:

- Copies/creates a plain-text extract via `pdftotext -layout` (idempotent — reuses an existing `.txt`)
- Renders each PDF page to a 150 dpi PNG via `pdftoppm` into `$TMPDIR/smbh-prep/<stem>/pages/`
- Is safe to re-run; it won't redo work that's already done

If only a `.txt` is available and no PDF, `PAGES=0` and you'll work text-only. That's fine for papers where all the important numbers are in the table body — but flag it in the caveats for any candidate whose parameters could only be read from a figure.

## Step 3 — read the whole paper

Use `Read` on the `TEXT=` path. Don't try to skim — binary candidate papers often bury the crucial number (period, mass ratio, eccentricity) in a single sentence in a model subsection, or in a footnote after a table. A partial read almost guarantees missed fields.

When the text is ambiguous or a number is clearly being read off a figure (periodograms, light curves with fitted sinusoids, VLBI images with dual nuclei, spectra with double-peaked lines), `Read` the relevant page PNG from `IMAGES=` and look directly. This is the reason we render pages — use it.

## Step 4 — identify the distinct candidates

A "distinct candidate" is a *specific astrophysical object* the paper claims could be hosting a binary SMBH. It is **not**:

- A population-level forecast ("PTAs should detect ~50 binaries by 2030")
- A control galaxy used only to contrast with the candidate
- A purely theoretical toy model with no tie to a real object
- A reference to someone else's prior candidate that the current paper isn't actually modelling

It **is**:

- Any named source the paper reports new evidence for, new parameters for, or refits with a new model
- Any object the paper argues is a binary on the basis of its own analysis, even if the evidence is weak or contested
- Each object in a multi-candidate catalog paper — write a separate candidate entry for each, not one entry for the whole catalog

**Edge cases:**

- A paper may revisit an old candidate *and* propose a new one; that's two distinct candidates.
- A paper may fit the same source with several competing models (different spins, accretion rates, inclination priors). That is still **one** candidate — the differing model assumptions become *ranges* on the affected parameters (see `references/parameter_guide.md` §Error types → Range).
- If the paper is explicit that a source is *not* a binary (e.g. a rejection paper), do not create a candidate entry for it. That's the opposite of what this skill is for.

Before moving on, decide the count and write it down internally. It should match `candidates.length` in the output JSON.

## Step 5 — build each candidate entry

The authoritative per-parameter rules, unit conventions, error-type definitions, and evidence-type enums live in `references/parameter_guide.md`. Read it before your first extraction — the spec is dense and you'll get the error formats wrong without it. The machine-readable schema lives in `references/schema.json`.

Top-level structure of the output file:

```json
{
  "bibcode": "2026arXiv260406059T",
  "paper": {
    "title": "...",
    "authors": ["Last1, F.", "Last2, F."],
    "source_file": "papers/2026arXiv260406059T.pdf",
    "extracted_on": "2026-04-10"
  },
  "candidate_count": 2,
  "candidates": [
    { ...candidate object... },
    { ...candidate object... }
  ]
}
```

Each candidate object has the fields listed in `references/schema.json`. Asterisked parameters from the spec are represented as objects:

```json
"log_total_mass": {
  "value": 9.2,
  "error": 0.3,
  "error_type": "Gaussian",
  "unit": "log10(Msun)"
}
```

If the paper doesn't report a parameter, **omit the key** (or set it to `null`). Do not guess, do not compute, do not fall back to "typical" values. The one exception is straightforward *representation* conversions: natural-log → log10, M☉ → log10(M☉), calendar date → MJD, years → days, Hz → days, parsecs ↔ kpc. Those are format changes, not new physics. If a paper states `M = 3×10⁹ M☉`, you may record `log_total_mass.value = 9.48`. If a paper states `P = 12 years`, you may record `orbital_period_days.value = 4383`. Everywhere else — including "derived" quantities the paper didn't actually print — leave it blank.

### Evidence types

`evidence` is a list. A single candidate often has more than one kind of evidence (e.g., a periodic light curve *and* a double-peaked broad line). Record each as its own object with `type`, `note`, and `waveband`. The enums are frozen — see `references/parameter_guide.md` §Evidence categories for the allowed values and the subcategory "notes" that go with each type.

## Step 6 — write the output file

The output lives at `./candidates/<bibcode>.json` relative to the repo root. Create `./candidates/` if it doesn't exist.

**Overwrite protection.** If `./candidates/<bibcode>.json` already exists, do not overwrite it. Instead, show the user the existing file (at minimum the `paper.extracted_on` and `candidate_count` fields) and ask whether to overwrite, merge, or abort. Do not assume — the user may have hand-edited the existing entry, and clobbering it silently would destroy work. If the user's initial request explicitly said "force", "overwrite", or "redo", that counts as consent and you can skip the prompt.

Writing into the repo is intentional and differs from the `ads-search` skill's "no writes inside the repo" rule — `./candidates/` is the project's catalog and lives in git.

Use the `Write` tool to emit the JSON with two-space indentation and UTF-8. Do not use shell heredocs.

## Step 7 — validate

Run:

```bash
.claude/skills/extract-smbh-binaries/scripts/validate_candidates.py ./candidates/<bibcode>.json
```

The validator checks:

- Required top-level keys (`bibcode`, `candidates`)
- Each candidate has a `source_standard_name` and at least one `evidence` entry
- All `evidence.type` values are in the allowed enum
- All `evidence.waveband` values are in the allowed enum
- All `error_type` values are in the allowed enum
- Asterisked measurement objects have a `value` key
- Mass log10 values fall in [5, 12] (a sanity check — outside that range is almost certainly a unit mistake)
- `inclination_deg` is in [0, 90]
- `q` is in (0, 1]
- `candidate_count` matches `candidates.length`

Exit code 0 means clean. Any errors are printed to stderr; fix them and rerun until clean.

## Step 8 — report to the user

After a successful validation, tell the user:

1. The output path
2. The candidate count and each candidate's `source_standard_name` (+ nickname if different)
3. A one-line summary per candidate drawn from its `summary_notes`
4. Any parameters you left blank because the paper didn't report them, grouped so the user can see at a glance what's missing
5. Any caveats you recorded (especially figure-derived values, model ambiguities, or unit conversions you applied)

Keep this report tight — the user will open the JSON file to see the full thing.

## Reference files

- **`references/parameter_guide.md`** — full per-parameter extraction rules, including the fixed evidence-type/evidence-note/waveband lists, error-type definitions with examples, unit conventions, and edge cases. **Read this before your first extraction.**
- **`references/schema.json`** — JSON Schema (draft-07) for the output file. Use it as the source of truth for field names, enums, and types.

## Scripts

- **`scripts/prepare_paper.sh`** — PDF → text + page-image preparation (idempotent, writes to `$TMPDIR`, never into the repo).
- **`scripts/validate_candidates.py`** — stdlib-only validator for the output JSON.

## Common pitfalls

- **Confusing total mass with M1.** Papers often say "the black hole mass is 3×10⁹ M☉" in a binary context — that's the total mass, not M1. When in doubt, record it under `log_total_mass` and note the ambiguity in `caveats`. Do not split a total mass across `log_m1` and `log_m2` yourself.
- **Recording "typical" values.** If a paper says "we assume e = 0 for simplicity", that is an `eccentricity` entry with `value: 0` and `error_type: "Assumed"` — not a blank. If a paper says nothing about eccentricity, leave it blank — don't fill in 0 because circular orbits are common.
- **Double-counting evidence.** "The light curve shows periodic brightening consistent with a binary orbit" is *one* evidence entry (`continuum_flux_variations` / "Continuous light curve variation with periodicity" / optical or whatever band), not three.
- **Over-trusting the abstract.** The abstract often reports a headline number with no error bar. The detailed body of the paper almost always has the error. Prefer the body. If the paper really only quotes a single number with no error, use `error_type: "Representative"`.
- **Missing the second candidate.** Multi-candidate papers are easy to under-count when you see the first candidate's detailed model and move on. Search the text for repeated "candidate" / "source" / "object" / table-row patterns before finalizing the count.
- **Bibcode drift.** If the filename stem and the ADS bibcode disagree (e.g., an arXiv stem for a paper that's since been published), use the published ADS bibcode in the JSON and put the arXiv ID in `paper.source_file`. Flag the choice in your report.
