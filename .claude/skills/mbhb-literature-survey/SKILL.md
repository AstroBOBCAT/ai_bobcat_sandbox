---
name: mbhb-literature-survey
description: End-to-end literature survey for supermassive black hole binary (MBHB / SMBHB) candidate papers on NASA ADS. Searches using a canonical MBHB + recoil term list, classifies each hit as relevant or not using a set of domain-specific rules, and buckets accepted papers into New model / Large list / Refute previous system. Use this skill whenever the user asks for MBHB, SMBHB, binary supermassive black hole, dual AGN, dual quasar, quasar pair, or recoiling SMBH candidate papers over a date range, wants a literature survey of the MBHB field, asks "what's new in binary SMBH candidates", wants to identify or categorize SMBHB candidate papers from ADS, or hands you a date window and asks for a survey of binary/dual supermassive black hole work — even if they don't mention "ADS" or "survey" by name.
allowed-tools: Bash(./.claude/skills/ads-search/scripts/search_ads.sh:*), Bash(.claude/skills/ads-search/scripts/search_ads.sh:*), Bash(./.claude/skills/ads-search/scripts/fetch_paper.sh:*), Bash(.claude/skills/ads-search/scripts/fetch_paper.sh:*), Bash(jq:*), Bash(mktemp:*), Bash(mkdir:*), Bash(date:*), Read, Write, Edit
---

# mbhb-literature-survey

End-to-end literature survey for **supermassive** black hole binary (MBHB / SMBHB) candidate papers on NASA ADS. Given a date window, this skill:

1. **Searches** ADS using the canonical MBHB + recoil term list bundled in `references/search_terms.txt`.
2. **Classifies** each returned paper as relevant or irrelevant by reading the abstract against the domain rules.
3. **Categorizes** accepted papers into New model / Large list / Refute previous system.
4. **Writes** a classification JSONL and a markdown summary to the user's chosen output directory (default `$TMPDIR/mbhb-survey/`).
5. **Offers** to fetch PDFs + extracted text for any subset the user wants to read.

This skill sits on top of the generic `ads-search` skill — it reuses `search_ads.sh` for querying ADS and `fetch_paper.sh` for downloading, and contributes the MBHB-specific term list, relevance rules, and categorization.

## When this applies

Use this skill whenever the user is looking for binary supermassive black hole candidate papers — phrased as MBHB / SMBHB / binary SMBH / dual AGN / dual quasar / quasar pair / recoiling SMBH / SMBHB survey / "what's new in binary black hole candidates" / etc. Assume SMBHB unless the user explicitly says stellar-mass.

Don't use this skill for:
- **Generic ADS searches** on non-MBHB topics — use `ads-search` directly.
- **Stellar-mass** LIGO/Virgo/KAGRA BBH work with no SMBH component.
- **Pure PTA stochastic-background theory** with no individual source (these are intentionally rejected by the classification rules).

## Workflow

### Step 1 — Ask for a date window if it's missing

A literature survey's scope matters. If the user hasn't given a window (`"find MBHB papers"` with no timeframe), ask whether they want the last few months, the last year, or a longer retrospective before running anything. Don't guess — running the wrong window burns ADS quota and floods your context with irrelevant hits.

### Step 2 — Run the search

Use `search_ads.sh` with the bundled term list. Key details:

- **Term list**: pass `--terms-file .claude/skills/mbhb-literature-survey/references/search_terms.txt`. This is the canonical MBHB + recoil list (adapted from Pfeifle et al. 2025 with additions).
- **Both preprints and refereed**: do **not** pass `--refereed`. The most recent MBHB candidate claims typically land on arXiv first, and we want them.
- **Output directory**: default to `$TMPDIR/mbhb-survey/`. If the user passed a path, use that. Never write inside the repo unless the user explicitly asks.
- **Include the table** (`--table`) so the user gets an immediate stderr summary of what came back.

```bash
OUT_DIR="${OUT_DIR:-$TMPDIR/mbhb-survey}"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)
HITS="$OUT_DIR/hits_${STAMP}.jsonl"

.claude/skills/ads-search/scripts/search_ads.sh \
  --terms-file .claude/skills/mbhb-literature-survey/references/search_terms.txt \
  --start YYYY-MM --end YYYY-MM \
  --table \
  --out "$HITS"
```

If the user wants extra one-off terms on top of the canonical list, add them with `--term "extra phrase"` rather than editing `search_terms.txt`. Edit the file itself only if they explicitly want to add a term to the canonical list for *future* surveys.

### Step 3 — Classify each paper

You (Claude) are the classifier. Read the JSONL, apply the rules below to each abstract, and decide accept/reject plus a category. No separate classifier script — abstracts are short and the rules benefit from judgment.

**ACCEPT if any of these apply:**

- The paper **proposes a new interpretation of a specific SMBH binary candidate**. This can be:
  - A **reinterpretation** of a known system (new data, new model, revisited analysis), or
  - A **newly identified candidate** that the paper is the first to flag.
  - The bar is *propose*, not merely *mention*. Passing references to existing candidates don't count.
- The paper **places new limits** on one or more specific SMBHB candidates or on the SMBHB population — new data, new CW (continuous-wave / individual-source PTA) upper limits, etc.

**REJECT if any of these apply:**

- **Theory-only / formalism** with no application to any specific source.
- **Undermassive**: the paper is about black holes with M < 10⁵ M☉ — stellar-mass LIGO/Virgo/KAGRA work, IMBH-only studies. The survey is about *supermassive* BHs; anything that never crosses 10⁵ M☉ is out.
- **No new contribution**: the paper only discusses past work without proposing a new model, candidate, or limit.
- **Pure stochastic background**: PTA papers that only constrain or discuss the SGWB without touching individual sources/candidates. Individual-source ("single-source" / "targeted" / "CW") PTA papers *are* relevant — it's SGWB-only that's out.

**Close calls**: read `references/identifying_relevant_papers.md` for the full rules and edge-case guidance before classifying borderline papers.

**Bias toward recall**: when a paper is genuinely ambiguous from the abstract alone, lean ACCEPT and put the ambiguity in the `reason` field. It's cheaper for the user to reject a borderline paper on their own read than to miss a real candidate.

### Step 4 — Categorize accepted papers

Each accepted paper goes into exactly one bucket:

- **New model** — proposes a new interpretation or mechanism for a specific candidate (or small set of candidates).
- **Large list** — catalog / survey paper presenting many candidates at once. Dual/offset quasar surveys at kpc scales count here, as do systematic radio/optical SMBHB searches.
- **Refute previous system** — argues a previously claimed SMBHB candidate is *not* actually a binary.

Rejected papers don't get a category — they're just `relevant: false` with a one-line reason.

### Step 5 — Write outputs

Write two sibling files in `$OUT_DIR`:

**a) `classified_<stamp>.jsonl`** — one line per paper:

```
{"bibcode": "...", "title": "...", "first_author": "...", "pubdate": "YYYY-MM-00", "relevant": true, "category": "New model", "reason": "Proposes a new SMBHB interpretation for the periodic signal in Q J0158-4325"}
{"bibcode": "...", "title": "...", "first_author": "...", "pubdate": "YYYY-MM-00", "relevant": false, "category": null, "reason": "Theory-only PTA formalism, no individual source"}
```

**b) `summary_<stamp>.md`** — markdown report using this template:

```markdown
# MBHB literature survey — <start> → <end>

**<total> total hits • <accepted> accepted • <rejected> rejected**

## New model (<n>)

| Bibcode | First author | Title | Why |
|---|---|---|---|
| 2026arXiv... | Yan | An equal mass ratio SMBHB in Q J0158-4325 | Proposes an SMBHB origin for the periodic signal |
| ... | | | |

## Large list (<n>)

| Bibcode | First author | Title | Why |
|---|---|---|---|
| ... | | | |

## Refute previous system (<n>)

| Bibcode | First author | Title | Why |
|---|---|---|---|
| ... | | | |

## Rejected — why (summary counts)

- **Theory-only / formalism**: N
- **Undermassive (stellar-mass or IMBH)**: N
- **Stochastic-background only**: N
- **No new claim**: N
```

Then print the markdown summary to the user in the chat (or a tightened version of it) so they can see results immediately without opening the file.

### Step 6 — Offer, don't auto-fetch, PDFs

After showing the summary, ask which papers the user wants to read in full. For any selected subset, pipe bibcodes into `fetch_paper.sh`:

```bash
echo "<bibcode-1> <bibcode-2> ..." | tr ' ' '\n' \
  | .claude/skills/ads-search/scripts/fetch_paper.sh --dir "$OUT_DIR"
```

`fetch_paper.sh` will download the PDF and auto-extract a plain `.txt` sibling (via `pdftotext`) into the same directory — the `.txt` is much easier to grep/jq/regex when you later want to pull numbers or find specific sources. **Don't auto-fetch everything** — most surveys return dozens of accepted papers, and the user typically only wants a handful.

## Output directory rule

Default to `$TMPDIR/mbhb-survey/`. If the user passes an explicit path, use it. **Never write survey results (JSONL, markdown, PDFs) inside the repo working copy unless the user explicitly tells you to.** The same rule applies to every downstream tool the skill invokes — `search_ads.sh --out` should point outside the repo, and `fetch_paper.sh --dir` should point outside the repo.

## Incremental vs. comprehensive surveys

The user's date window drives the scope. Common patterns:

- **"What's new since I last checked"** — a short window (last 1–3 months). Use this as the default cadence for ongoing monitoring.
- **"Everything in the last year"** — broader retrospective, useful for writing reviews or proposals.
- **Longer historical pulls** — occasionally, e.g. for a retrospective on a specific source.

The term list and rules don't change between these modes; only `--start` and `--end` do.
