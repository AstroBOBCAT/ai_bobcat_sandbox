---
name: ads-search
description: Query the NASA ADS / SciX literature database for astronomy, astrophysics, and physics papers matching a set of search terms, optionally filtered by publication date, subject area (astronomy/physics/general), or refereed status. Use this skill whenever the user wants to find papers on ADS/SciX, do a literature search in astronomy or astrophysics, look up recent papers on a topic like "dual AGN" or "JWST exoplanets", build a bibliography from a list of keywords, or pull results programmatically from ADS — even if they don't explicitly say "ADS". Also use it when the user mentions searching adsabs, SciX, NASA ADS, scixplorer, or when they have a list of search terms and a date range and want to run them.
allowed-tools: Bash(curl:*), Bash(jq:*), Bash(./.claude/skills/ads-search/scripts/search_ads.sh:*), Bash(.claude/skills/ads-search/scripts/search_ads.sh:*), Bash(./.claude/skills/ads-search/scripts/fetch_paper.sh:*), Bash(.claude/skills/ads-search/scripts/fetch_paper.sh:*), Read, Write, Edit
---

# ads-search

A skill for querying the NASA ADS / SciX search API from the shell, so the user can find papers matching a set of terms over a date range without writing API code.

The skill wraps a single bash script — `scripts/search_ads.sh` — that handles authentication, URL encoding, chunking long queries, paginating results, and deduping by bibcode. Your job is to construct the right query for the user's question and invoke the script with the right flags.

## When this skill applies

Use it whenever the user wants to pull papers from ADS/SciX programmatically. That includes:

- "Find papers on X between 2020 and 2024"
- "Run this list of search terms through ADS"
- "Look up recent refereed work on Y in astronomy"
- "Build a bibliography for topic Z"
- Any mention of *ADS*, *adsabs*, *SciX*, *scixplorer*, *NASA ADS*

Don't use it for reading or summarizing a specific known paper, for general astronomy questions that don't require a literature pull, or for non-literature tasks.

## Prerequisites

- `curl` and `jq` must be installed (`brew install jq` on macOS).
- An ADS/SciX API token must be available. Resolution order:
  1. `--token` flag
  2. `ADS_API_TOKEN` environment variable
  3. `ADS_API_TOKEN=...` line in a `.env.local` file in the current directory or any parent directory
- Rate limits: 5000 regular queries per day, 100 "big queries" per day.

If the user doesn't have a token yet, tell them to generate one at https://scixplorer.org → Account → Customize Settings → API Token → Generate New Token, then put `ADS_API_TOKEN=...` in `.env.local` at the project root (gitignore it).

## How to run the script

From the project root:

```bash
.claude/skills/ads-search/scripts/search_ads.sh [options] [-- term1 term2 ...]
```

Terms come from any combination of:
- `--term "string"` / `-t "string"` (repeatable)
- `--terms-file path.txt` (one term per line; `#` comments and blanks skipped)
- Positional args after `--`
- stdin (one term per line) if none of the above are given

By default the script writes JSONL (one paper per line) to stdout. Pass `--out path.jsonl` to redirect to a file. Progress and a short summary go to stderr.

**Do not write results inside the repo.** The default (stdout) is fine for most calls; if the user wants results on disk, pass `--out` with a path under `$TMPDIR`, `~/`, or another location outside the working copy. `--table` works fine without `--out` — the script buffers to `$TMPDIR` and streams the JSONL to stdout at the end, so no files land in the project directory.

### Common invocations

```bash
# Ad-hoc query with inline terms
.claude/skills/ads-search/scripts/search_ads.sh \
  --start 2020-01 --end 2024-12 --refereed \
  -- "dual AGN" "binary SMBH" "recoiling black hole"

# Use an existing term list file
.claude/skills/ads-search/scripts/search_ads.sh \
  --terms-file search_terms.txt \
  --start 2020-01 --end 2024-12 \
  --out results.jsonl --table

# Broaden to full-text search across all ADS databases
.claude/skills/ads-search/scripts/search_ads.sh \
  --database all --match full --max 500 \
  -- "tidal disruption event"

# Pipe terms in
cat my_terms.txt | .claude/skills/ads-search/scripts/search_ads.sh --start 2023-01
```

### Flags at a glance

| Flag | Purpose | Default |
|---|---|---|
| `--term` / `-t` | Add one term (repeatable) | — |
| `--terms-file PATH` | Read terms from a file | — |
| `--start YYYY-MM` | Pubdate lower bound | (none) |
| `--end YYYY-MM` | Pubdate upper bound | current month |
| `--no-date` | Omit pubdate filter entirely | off |
| `--database` | `astronomy` / `physics` / `general` / `all` | `astronomy` |
| `--refereed` | Restrict to refereed articles | off |
| `--match` | `abs` / `title` / `abstract` / `full` / `body` | `abs` |
| `--max N` | Max unique results to return | 200 |
| `--rows N` | Per-page size (ADS max 2000) | 200 |
| `--sort` | Sort spec | `"date desc"` |
| `--fields` | Comma-separated `fl` fields | `bibcode,title,first_author,pubdate,doi,abstract` |
| `--out PATH` | Write JSONL to file (should be outside the repo) | stdout |
| `--table` | Also print a summary table to stderr (buffers via `$TMPDIR` if no `--out`) | off |
| `--dry-run` | Show URLs without calling the API | off |
| `--token` | Override token | (env/.env.local) |
| `--quiet` | Suppress progress on stderr | off |

Use `--dry-run` first when you're unsure about a query — it prints the final `q`, `fq`, and URL so you can sanity-check before burning quota.

## How to choose query options

The key decisions when translating a user request into flags:

### 1. Match field (`--match`)

- **`abs` (default)** — searches title + abstract + keywords as a unified field. This is the right default for almost all topical searches: tight enough to avoid papers that merely cite the topic, broad enough to catch papers genuinely about it.
- **`title`** — tightest. Use when you want only papers whose titles explicitly name the topic (good for surveys, reviews, high-precision bibliographies).
- **`abstract`** — searches abstract only (excludes title/keywords). Rarely preferred over `abs`.
- **`full`** — searches the entire record including metadata fields. Broader recall.
- **`body`** — full text of the article body where ADS has it. Highest recall, but noisy (matches reference lists and passing mentions). Use only when the user explicitly wants full-text search.

### 2. Database filter (`--database`)

ADS organizes records into three databases: `astronomy`, `physics`, and `general`. By default all three are searched; the script restricts to `astronomy` because the most common use case is astrophysics literature. Switch to:
- `physics` for high-energy / nuclear / gravitational-wave work that may be filed there instead.
- `general` for planetary or space-science sources.
- `all` to disable the filter entirely (broadest recall).

### 3. Date range (`--start` / `--end`)

Use `YYYY-MM` format. ADS `pubdate` is stored as `YYYY-MM-00`, so month-level granularity is the finest that matters. For "recent papers" with no specified window, a 3- or 5-year lookback is a reasonable default — confirm with the user if they care about older work.

### 4. Refereed (`--refereed`)

Adds `fq=property:refereed`. Use it whenever the user wants peer-reviewed work only (e.g., for building a formal bibliography). Leave it off to include arXiv preprints and conference proceedings.

### 5. How many results (`--max`)

Default 200 is enough for most exploratory searches. Bump to 500–1000 for comprehensive pulls, or down to 20–50 for quick "what's new" scans.

## Inspecting results

The script emits JSONL — one JSON object per paper — so it pipes cleanly into `jq`:

```bash
# Titles + bibcodes only
jq -r '[.bibcode, (.title // [""])[0]] | @tsv' results.jsonl

# Count papers per year
jq -r '.pubdate[:4]' results.jsonl | sort | uniq -c | sort -rn

# Filter down to papers whose abstracts mention "gravitational wave"
jq -c 'select((.abstract // "") | test("gravitational wave"; "i"))' results.jsonl
```

ADS returns `title` as an array (usually one element) — always index with `[0]` or use `// [""]` to guard against missing titles.

## Fetching PDFs and LaTeX source

**Fetching is a separate, opt-in second step — never do it as part of the initial search.** The normal flow is:

1. Run `search_ads.sh` and show the user the result table.
2. Let the user pick which papers they actually want to read (by bibcode, title keyword, author, "the first 5", etc.).
3. *Only then* pipe that subset of bibcodes into `fetch_paper.sh`.

Don't auto-fetch everything a search returned — 200 PDFs is a lot of bytes and a lot of the time the user only wants a handful.

Once you have a set of bibcodes (from the user's selection), the companion script `scripts/fetch_paper.sh` downloads the preprint PDF and/or the arXiv LaTeX source tarball:

```bash
# Single paper, PDF only (default), into $TMPDIR/ads-papers/
echo 2026ApJ...999..107F | .claude/skills/ads-search/scripts/fetch_paper.sh

# PDF + LaTeX for everything in a JSONL result set, into ~/papers
jq -r .bibcode /tmp/results.jsonl \
  | .claude/skills/ads-search/scripts/fetch_paper.sh --what both --dir ~/papers
```

It defaults to writing under `$TMPDIR/ads-papers/` so nothing lands in the repo — pass `--dir` to choose somewhere else, but never point it inside the working copy.

Each fetched PDF is auto-extracted to a sibling `.txt` via `pdftotext -layout`, since plain text is much easier to grep/jq/regex for downstream extraction (section parsing, pulling numerical values, finding specific objects) than the PDF itself. Pass `--no-text` to skip extraction; if `pdftotext` isn't installed the script logs a note and continues with just the PDF.

Under the hood it uses:

- **PDF** — ADS's link gateway, which redirects to the best available source (arXiv preprint first, then publisher):
  - `https://ui.adsabs.harvard.edu/link_gateway/<bibcode>/EPRINT_PDF`
  - `https://ui.adsabs.harvard.edu/link_gateway/<bibcode>/PUB_PDF` (fallback; often paywalled)
- **LaTeX** — ADS only stores a pointer, not the source, so the script first queries ADS for the `identifier` field to find the arXiv ID, then grabs the source tarball from `https://arxiv.org/e-print/<id>`. Almost every astro paper has an arXiv version.

Papers that only exist behind a publisher paywall with no arXiv copy will fail the fetch; the script logs the failure and continues.

## Going beyond the script

The script covers the common case (term list + date range + subject filter). If the user asks for something fancier — specific authors, a particular journal, citation counts, wildcard prefixes, big-query (bibcode lookup), PDF downloads, exclusion terms — read `references/query_syntax.md` for the full ADS / Solr query grammar. You can then either:

- **Stay within the script**: pass a raw query with `-t` (since `-t` values are embedded inside `match_field:"..."`, this is only useful for phrase matching, not field-qualified queries).
- **Build a custom query yourself**: construct your own `q` and `fq`, URL-encode, and `curl` the endpoint directly. The script is a convenience wrapper, not a jailer — for one-off advanced queries, calling the API directly with curl+jq is fine.

## Common pitfalls

- **`q` is capped at 1000 characters.** The script auto-chunks long term lists into multiple requests and dedupes by bibcode, but extremely long lists (hundreds of terms) can be slow and may benefit from being narrowed first.
- **Acronym collisions.** Terms like `SBHB`, `MBMB`, or `"Continuous-wave source"` will match papers on unrelated gravitational-wave sources or pulsar timing. When a user's term list contains these, warn them that results may be noisy, and consider adding an `AND` clause or switching to `--match title` for tighter precision.
- **Phrase matching is on by default.** Everything passed as a term is wrapped in double quotes, so multi-word terms are treated as exact phrases. If the user wants AND semantics across words (e.g., `"dual" AND "AGN"` as separate tokens), they should pass the raw boolean expression via a custom curl call.
- **Title is an array.** When post-processing JSONL, use `(.title // [""])[0]`, not `.title`.
- **Date filter is `pubdate`, not `date`.** `pubdate` is the human-readable publication date; `date` is a separate machine-readable field useful only for sorting.

## Token safety

Never echo the token to the chat or commit it. The script reads it from the environment or `.env.local`; don't paste it onto the command line (it would end up in shell history). If the user doesn't have `.env.local` gitignored, add it before helping them create one.
