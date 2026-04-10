# ai_bobcat_sandbox

A working repo for building a catalog of binary supermassive black hole (SMBH) candidates from the astronomy literature, using Claude Code as the research assistant.

The workflow is literature-search → paper-fetch → candidate-extraction → validated JSON catalog. Each step is wrapped in a Claude Code *skill* that lives under `.claude/skills/` so that a fresh session can reproduce it without you re-explaining the rules.

## Repo layout

```
.
├── .claude/
│   └── skills/
│       ├── ads-search/               # query NASA ADS / SciX + fetch paper PDFs
│       └── extract-smbh-binaries/    # turn a paper into structured candidate JSON
├── papers/                           # fetched papers (PDF + .txt extract)
├── candidates/                       # per-paper candidate catalog (JSON, one file per bibcode)
├── CLAUDE.md                         # guidance Claude reads on every session
└── README.md                         # this file
```

`papers/` and `candidates/` are the only directories Claude writes into during normal use. `papers/` gets populated by `ads-search`'s fetcher; `candidates/` gets populated by `extract-smbh-binaries`.

## Prerequisites

- **Claude Code** — `brew install --cask claude` or see https://claude.com/claude-code
- **curl**, **jq**, **pdftotext**, **pdftoppm** — `brew install jq poppler` covers all four on macOS
- **Python 3** — for the candidates validator (stdlib only, no extra deps)
- **ADS/SciX API token** — generate at https://scixplorer.org → Account → Customize Settings → API Token → Generate New Token, then drop it into a gitignored `.env.local` at the repo root:
  ```
  ADS_API_TOKEN=your-token-here
  ```

## The skills

### 1. `ads-search` — find and fetch papers

Queries the NASA ADS / SciX literature database and optionally downloads PDFs + arXiv LaTeX source. Handles URL encoding, chunking long query lists, pagination, and dedup by bibcode.

**Trigger it by asking Claude something like:**
- "Find papers on binary SMBH candidates from 2020–2024"
- "Run my search_terms.txt through ADS, refereed only"
- "Pull the PDFs for the first five bibcodes"

**Or run the script directly from the repo root:**

```bash
# Ad-hoc query
.claude/skills/ads-search/scripts/search_ads.sh \
  --start 2020-01 --end 2024-12 --refereed \
  -- "dual AGN" "binary SMBH" "recoiling black hole"

# From a term list file, with a summary table
.claude/skills/ads-search/scripts/search_ads.sh \
  --terms-file search_terms.txt \
  --start 2020-01 --end 2024-12 \
  --out /tmp/results.jsonl --table

# Fetch a subset of papers (PDF + LaTeX source) into ./papers/
jq -r .bibcode /tmp/results.jsonl \
  | .claude/skills/ads-search/scripts/fetch_paper.sh --what both --dir ./papers
```

Results are JSONL (one paper per line) suitable for piping into `jq`. Fetched PDFs are auto-extracted to sibling `.txt` files via `pdftotext -layout` so downstream tools can grep/parse them.

**What it won't do:** read or summarize specific papers. That's the next skill.

See `.claude/skills/ads-search/SKILL.md` for the full flag reference and query-syntax guide.

### 2. `extract-smbh-binaries` — build structured candidate entries

Reads a binary-SMBH-candidate paper (PDF, text, or pasted into chat) and produces a JSON record conforming to a fixed catalog schema. One file per paper at `./candidates/<bibcode>.json`, containing a paper-level header and a list of candidate entries — one entry per distinct binary SMBH candidate the paper describes.

The skill is **extractive**, not generative. Every recorded value is traceable to a specific sentence, table row, or figure in the paper. Representation-level unit conversions (linear → log10, years → days, Hz ↔ period) are allowed; derived physics (computing chirp mass from M1/M2, splitting a total mass across M1/M2 using q) is not.

**Trigger it by asking Claude something like:**
- "Extract the binary candidate from papers/2026arXiv260406059T"
- "How many binary SMBH candidates does this paper describe?"
- "Build catalog entries for all the sources in Graham+2015"

**What Claude does under the hood:**

1. Calls `scripts/prepare_paper.sh <path-or-stem>` to flatten the PDF into plain text and render each page to a 150 dpi PNG (workspace lives in `$TMPDIR`, never in the repo).
2. Reads the full text end-to-end. For periods read off light curves, dual nuclei seen on VLBI images, or values otherwise buried in figures, reads the page PNGs multimodally.
3. Counts *distinct astrophysical candidates* (not controls, not purely theoretical toys, not population forecasts).
4. Fills in only parameters the paper actually states. Unreported fields stay blank.
5. Writes `./candidates/<bibcode>.json` using the schema in `references/schema.json`. Refuses to overwrite an existing file without explicit consent.
6. Runs `scripts/validate_candidates.py` and fixes any errors before reporting done.

**The extracted model per candidate includes:**

- Source standard name + nickname, J2000 coordinates, redshift
- Masses (log10 M☉): `m1`, `m2`, `total_mass`, `chirp_mass`, `reduced_mass`
- Orbital parameters: eccentricity, mass ratio `q` (constrained to (0, 1]), inclination (0–90°), semi-major axis (pc), separation (pc), period (days, Earth frame), frequency (Hz, Earth frame)
- Period epoch and semi-major axis date (MJD)
- Evidence: a list of `{type, note, waveband}` tuples drawn from a fixed enum (emission line variability, continuum flux periodicity, dual nuclei, helical jets, gravitational waves, etc.)
- Summary notes, caveats, and a student-project idea

Asterisked "measured" parameters carry an `error` + `error_type` drawn from a fixed set: `Assumed`, `Lower limit`, `Upper limit`, `Gaussian`, `Two sided` (string format `"(-x,+y)"`), `Range`, `Representative`.

**Running the scripts directly** (Claude does this for you; shown here for debugging):

```bash
# Prepare a paper — writes nothing into the repo, prints workspace paths
.claude/skills/extract-smbh-binaries/scripts/prepare_paper.sh papers/2026arXiv260406059T.pdf
# → STEM=, TEXT=, IMAGES=, PAGES= on stdout

# Validate an extracted catalog file
.claude/skills/extract-smbh-binaries/scripts/validate_candidates.py candidates/2026arXiv260406059T.json
```

The validator is pure stdlib Python 3 and checks:

- Required top-level and per-candidate keys
- Enum values for `evidence.type`, `evidence.waveband`, `error_type`
- Mass log10 values in the plausible [5, 12] range
- `inclination_deg` in [0, 90], `q` in (0, 1], `eccentricity` in [0, 1)
- `candidate_count` matches `candidates.length`
- Two-sided errors formatted as `"(-x,+y)"` strings

Exit code 0 means clean. Errors go to stderr.

**Reference files** to read when you want the full spec:

- `.claude/skills/extract-smbh-binaries/references/schema.json` — JSON Schema (draft-07) for the output file
- `.claude/skills/extract-smbh-binaries/references/parameter_guide.md` — per-parameter extraction rules, error-type definitions with worked examples, evidence-category enums, unit conventions

## A typical end-to-end session

```
you> Find recent refereed papers on binary SMBH candidates from 2023 onward.
Claude> [runs ads-search, shows you a table of 40 bibcodes]

you> Grab the top 5 into ./papers/.
Claude> [runs fetch_paper.sh on the chosen bibcodes, writes .pdf + .txt pairs]

you> Extract candidates from all of them.
Claude> [for each paper: runs prepare_paper.sh, reads text + figures, writes
         candidates/<bibcode>.json, validates, reports candidate count + summary]

you> Any of these have conflicting mass estimates worth flagging?
Claude> [grep/read candidates/*.json, answer from the extracted data]
```

Each intermediate artifact is committed to git (PDFs, text extracts, JSON), so re-running a session is cheap and reproducible.

## Why skills, not one big prompt

The two skills are deliberately independent. `ads-search` doesn't know anything about binary candidates; it's a general ADS literature-pull tool you could use for any astronomy project. `extract-smbh-binaries` doesn't know anything about ADS; it only needs a path to a paper. Composing them is the user's (or Claude's) job, and that's the point — each skill stays small, testable, and replaceable.

If you want to add another extraction pipeline (say, "extract-tde-candidates"), it slots in alongside `extract-smbh-binaries` without touching either existing skill.

## Adding more skills

New skills go in `.claude/skills/<skill-name>/` with the same shape as the existing two:

```
<skill-name>/
├── SKILL.md            # frontmatter (name, description, allowed-tools) + body
├── references/         # schemas, long-form docs Claude loads on demand
└── scripts/            # executable helpers invoked from SKILL.md
```

The `description` field in the frontmatter is the primary mechanism by which Claude decides whether to invoke a skill, so it's worth making it specific about both *what* the skill does and *when* to use it. See the existing skills for the style.

## Contributing

- Keep secrets (ADS tokens, personal API keys) in `.env.local` — it's gitignored.
- When you edit a skill, verify `scripts/*.sh` and `scripts/*.py` still run standalone before committing — they're the contract the skill's prose relies on.
- When you add a new extraction schema, put both the JSON Schema *and* the narrative parameter guide in `references/`. The schema is for machines, the guide is for Claude and humans.
