# Identifying relevant MBHB papers

Criteria for deciding whether an ADS search hit is a relevant paper for the supermassive black hole binary (MBHB) candidate literature survey, and how to categorize it once accepted.

## Workflow

1. **Search ADS** for key terms in `"fulltext"` (see `../references/search_terms.txt` for the canonical MBHB + recoil term list).
2. **Read the abstract** to decide if the paper is relevant.
3. **Apply the relevance rules** below.
4. **Categorize** the accepted paper into one of the four buckets.

## Relevance rules — ACCEPT if any of these apply

A paper is relevant if it does at least one of the following:

- **Proposes a new interpretation of a binary SMBH candidate.** Note the bar is *propose*, not merely *discuss* — passing mention of an existing candidate isn't enough.
  - This can take two forms:
    - **Reinterpretation** of a known system (e.g. revisiting a claimed candidate with new data or a new model).
    - **Newly identified candidate** that the paper is the first to flag.
- **Places new limits** on SMBHBs. Typically a "limit paper" — new data or new continuous-wave (CW, i.e. individual-source PTA) upper limits on SMBHB populations or on specific candidates.

## Relevance rules — REJECT if any of these apply

- **Theory-only development** with no application to any specific source. (Pure formalism, simulations without an observational target, etc.)
- **Undermassive systems.** Black holes with M < 10⁵ M☉ — e.g. purely LIGO / stellar-mass BBHs, IMBH-only work. The survey is about *supermassive* BH binaries; reject anything that never crosses the 10⁵ M☉ threshold.
- **Only discuss past work** without proposing a new model, presenting a new candidate, or placing new limits. Review papers that don't add anything on top of the existing literature fall here.

## Categorization (after acceptance)

Once a paper passes the relevance check, drop it into exactly one of:

- **New model** — proposes a new interpretation or mechanism for a specific candidate (or small set of candidates).
- **Large list** — catalog or survey paper presenting many candidates at once (e.g. a dual-AGN survey result, a targeted SMBHB search over a sky region).
- **Refute previous system** — argues that a previously claimed SMBHB candidate is *not* actually a binary (e.g. shows the periodicity can be explained without a binary, or reanalyzes data to null the detection).
- **Irrelevant** — retained in the schema for bookkeeping, even though these papers were rejected at the relevance step.

## Edge cases / judgment calls

- **Mixed-topic papers**: if a paper is primarily about something else (e.g. a TDE delay-time distribution) but contains a section proposing an SMBHB interpretation for specific sources, accept it and categorize by the SMBHB claim.
- **PTA stochastic background papers**: reject unless they also place limits on or discuss specific individual SMBHB sources/candidates. Stochastic-only constraints are not enough on their own.
- **Dual AGN / quasar pair surveys at kpc scales**: accept as "Large list" — these are the progenitor population even though they're not resolved as gravitationally bound binaries yet.
- **Undermassive borderline**: if the paper mixes SMBH and stellar-mass work, accept only if it meaningfully discusses the ≥ 10⁵ M☉ regime.
