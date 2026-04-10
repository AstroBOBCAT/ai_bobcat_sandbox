# ADS / SciX query syntax cookbook

A compact reference for building ADS queries that go beyond what `scripts/search_ads.sh` exposes as flags. Read this when the user asks for something the script's flags don't cover — specific authors, journals, citation filters, exclusions, wildcards, or big-query bibcode lookups.

Canonical docs: https://ui.adsabs.harvard.edu/help/api/ and https://ui.adsabs.harvard.edu/help/search/search-syntax

## The endpoint

```
GET https://api.adsabs.harvard.edu/v1/search/query
Header: Authorization: Bearer <token>
```

Parameters:
- **`q`** *(required)* — the main query. UTF-8, URL-encoded, **max 1000 chars**.
- **`fq`** — filter query. Same syntax as `q`, but cached and scoped to the main result set (faster). May appear multiple times; multiple `fq`s are ANDed.
- **`fl`** — comma-separated list of fields to return. Default is `id` only, so always set this.
- **`rows`** — page size, default 10, **max 2000**.
- **`start`** — offset for pagination.
- **`sort`** — e.g. `date desc`, `citation_count desc`, `read_count desc`, `first_author asc`. Cannot sort on multivalued fields like `author`.

## Fielded search

Prefix a term with `field:` to scope it. Common searchable fields:

| Field | What it matches |
|---|---|
| `abs` | Unified title + abstract + keywords (the default for topical searches) |
| `title` | Title only |
| `abstract` | Abstract only |
| `author` | Any author (array) |
| `first_author` | First author only |
| `aff` | Affiliation string |
| `bibcode` | Canonical ADS bibcode (e.g. `2023ApJ...945...12S`) |
| `bibstem` | Journal abbreviation (e.g. `ApJ`, `MNRAS`, `A&A`, `Nature`) |
| `year` | Publication year (integer) |
| `pubdate` | Publication date as `YYYY-MM-DD` (DD is always `00`) |
| `doi` | DOI |
| `identifier` | Alt identifiers (bibcodes, DOIs, arXiv ids) |
| `arxiv_class` | arXiv category, e.g. `astro-ph.HE` |
| `keyword` | Keywords assigned to the record |
| `full` | All metadata fields |
| `body` | Full article text (searchable only, not returnable via `fl`) |

Examples:

```
q=title:"dual AGN"
q=author:"kocevski, d"
q=first_author:"Pfeifle, R"
q=bibstem:ApJ year:2023
q=arxiv_class:astro-ph.HE abs:"pulsar timing"
```

## Phrases, boolean operators, grouping

Double-quote multi-word phrases; URL-encode the quotes as `%22`.

```
"dual AGN"                # exact phrase
"dual AGN" OR "binary SMBH"
("dual AGN" OR "binary SMBH") AND year:2023
"binary black hole" -merger     # exclude "merger"
"transiting exoplanet" +JWST    # require "JWST"
```

Default operator between bare terms is `AND`. `OR` and `AND` must be uppercase. Use `-term` or `NOT term` to exclude, `+term` to require.

Wildcards are supported for most fields: `exoplan*`, `agn*`.

## Date filters

Two equivalent idioms, use whichever is clearer:

```
pubdate:[2020-01 TO 2024-12]
pubdate:[2013-07 TO *]
pubdate:2023-02                 # exact month
year:2023
year:[2020 TO 2024]
```

Open-ended ranges use `*` on either side.

## Useful filter queries (`fq`)

`fq` takes the same syntax as `q` but is faster and cacheable. Use it for anything that narrows the result set without contributing to relevance ranking:

```
fq=database:astronomy           # or physics / general
fq=property:refereed            # peer-reviewed only
fq=property:openaccess
fq=property:notrefereed
fq=doctype:article              # or review, proceedings, book, thesis, abstract, inbook, eprint, software
fq=bibstem:ApJ
fq=citation_count:[100 TO *]
```

Multiple `fq`s are ANDed:

```
&fq=database:astronomy&fq=property:refereed&fq=year:[2020 TO 2024]
```

## Commonly returned fields (`fl`)

```
fl=bibcode,title,author,first_author,pubdate,year,doi,abstract,citation_count,read_count,bibstem,keyword,arxiv_class,identifier
```

Note: `title` and `author` are returned as **arrays**. Always index with `[0]` or `// [""]`:

```jq
jq -r '(.title // [""])[0]'
jq -r '(.author // []) | join("; ")'
```

## Sorting

```
sort=date desc                # newest first (machine-readable date field)
sort=citation_count desc      # most-cited first
sort=read_count desc          # most-read in the last 90 days
sort=bibcode asc              # alphabetical
```

`pubdate` is a string field and not useful for sorting; use `date` instead.

## Pagination

```
rows=200&start=0
rows=200&start=200
```

Keep bumping `start` by `rows` until `start >= numFound`. Max `rows` is 2000.

## Big query (bibcode lookup)

When you have a list of bibcodes you want to hydrate (e.g., from a citation export), use the `bigquery` endpoint. It accepts up to 2000 bibcodes per request and counts against a separate 100-requests-per-day quota.

```
POST https://api.adsabs.harvard.edu/v1/search/bigquery?q=*:*&fl=bibcode,title&rows=2000
Header: Authorization: Bearer <token>
Header: Content-Type: big-query/csv
Body:
  bibcode
  2011ApJ...737..103S
  2023ApJ...945...12S
  ...
```

Notes:
- The `q=*:*` is required. Use `q=*:*` unless you want to further narrow the bibcode list.
- Default `rows` is still 10 — set it to the number of bibcodes you want back.

## PDF downloads

```
GET https://ui.adsabs.harvard.edu/link_gateway/<bibcode>/EPRINT_PDF   # arXiv
GET https://ui.adsabs.harvard.edu/link_gateway/<bibcode>/PUB_PDF      # publisher
```

Use `curl -L -o output.pdf` to follow the redirect. Still needs the `Authorization: Bearer` header.

## URL-encoding cheat sheet

Needed when hand-crafting curl requests:

| Char | Encoded |
|---|---|
| space | `+` or `%20` |
| `"` | `%22` |
| `:` | `%3A` (optional — ADS accepts raw `:` too) |
| `[` | `%5B` |
| `]` | `%5D` |
| `,` | `%2C` |

In shell, the easiest robust encoder is `jq -rn --arg v "$s" '$v|@uri'`.

## Highlighting (snippets with search terms bolded)

```
&hl=true
&hl.fl=abstract,title
&hl.snippets=4
&hl.fragsize=100
```

Returned under `.highlighting.<id>` in the response. Useful when you want to show the user *why* a paper matched.

## Rate limits

- **Regular queries:** 5000 per day per token.
- **Big queries:** 100 per day per token.
- **q length:** 1000 characters (post-encoding is not what's measured — the pre-encoded length matters).

If a search might brush against the limit (hundreds of terms, many chunks, or repeated daily runs), consider caching results and using `fq` aggressively to cut down the work.

## Quick recipes

```bash
# Most-cited astronomy papers on a topic in the last 5 years
q=abs:"fast radio burst" &fq=database:astronomy &fq=year:[2020 TO 2024] \
&sort=citation_count+desc &rows=50

# Refereed ApJ papers by a specific first author
q=first_author:"Pfeifle,+R" &fq=bibstem:ApJ &fq=property:refereed \
&sort=date+desc

# All papers that cite or are cited by a specific bibcode — use the /search/resolver endpoint
# (separate endpoint, not documented here)

# Find papers tagged with a specific arXiv category in the last year
q=arxiv_class:astro-ph.HE &fq=pubdate:[2024-01 TO *] &sort=date+desc
```
