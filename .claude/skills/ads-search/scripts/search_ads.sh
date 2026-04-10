#!/usr/bin/env bash
# search_ads.sh — query the NASA ADS / SciX search API.
#
# Terms come from any combination of --term flags, --terms-file, positional
# args after `--`, or stdin. There is no default terms list.
#
# Auth: ADS_API_TOKEN env var, or --token flag, or ADS_API_TOKEN=... in a
# .env.local file found in the current directory or any parent.
#
# Output: JSONL (one paper per line) to stdout by default, or to --out PATH.
# Progress and a short summary are written to stderr. Pass --table to also
# print a human-readable table to stderr; with --table and no --out, results
# are buffered in $TMPDIR and streamed to stdout at the end (no repo files).

set -euo pipefail

# ---------- defaults ----------
TERMS=()
TERMS_FILE=""
START_DATE=""
END_DATE=""
NO_DATE=0
DATABASE="astronomy"
MATCH_FIELD="abs"
REFEREED=0
MAX_RESULTS=200
ROWS=200
SORT="date desc"
FIELDS="bibcode,title,first_author,pubdate,doi,abstract"
OUT=""
TOKEN_OVERRIDE=""
DRY_RUN=0
TABLE=0
QUIET=0

BASE_URL="https://api.adsabs.harvard.edu/v1/search/query"
Q_BUDGET=900  # ADS caps q at 1000 chars; leave slack for the enclosing parens

usage() {
  cat <<'EOF'
Usage: search_ads.sh [options] [-- term1 term2 ...]

Terms (any combination; all are merged and deduped):
  --term STRING, -t STRING   Add a search term (repeatable)
  --terms-file PATH          Read terms from a file (# comments and blanks skipped)
  -- term1 term2 ...         Trailing positional terms after `--`
  (stdin)                    If no terms are given any other way, reads from stdin

Filters:
  --start YYYY-MM            pubdate lower bound
  --end YYYY-MM              pubdate upper bound (default: current month)
  --no-date                  Omit the pubdate filter
  --database NAME            astronomy | physics | general | all  (default: astronomy)
  --refereed                 Restrict to refereed articles
  --match FIELD              abs | title | abstract | full | body  (default: abs)

Result control:
  --max N                    Max unique results to return (default: 200)
  --rows N                   Page size, max 2000 (default: 200)
  --sort STRING              Sort spec (default: "date desc")
  --fields LIST              Comma-separated fl fields
                             (default: bibcode,title,first_author,pubdate,doi,abstract)

Output:
  --out PATH                 Write JSONL to PATH instead of stdout
  --table                    Also print a summary table (to stderr)
  --quiet                    Suppress progress messages

Auth & debugging:
  --token TOKEN              Override ADS_API_TOKEN
  --dry-run                  Print the URLs without calling the API
  -h, --help                 Show this help

Examples:
  search_ads.sh --start 2020-01 --end 2024-12 -- "dual AGN" "binary SMBH"
  search_ads.sh --terms-file terms.txt --database astronomy --refereed
  echo "JWST exoplanet atmosphere" | search_ads.sh --start 2023-01
EOF
}

# ---------- arg parsing ----------
POSITIONAL_TERMS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--term)     TERMS+=("$2"); shift 2 ;;
    --terms-file)  TERMS_FILE="$2"; shift 2 ;;
    --start)       START_DATE="$2"; shift 2 ;;
    --end)         END_DATE="$2"; shift 2 ;;
    --no-date)     NO_DATE=1; shift ;;
    --database)    DATABASE="$2"; shift 2 ;;
    --refereed)    REFEREED=1; shift ;;
    --match)       MATCH_FIELD="$2"; shift 2 ;;
    --max)         MAX_RESULTS="$2"; shift 2 ;;
    --rows)        ROWS="$2"; shift 2 ;;
    --sort)        SORT="$2"; shift 2 ;;
    --fields)      FIELDS="$2"; shift 2 ;;
    --out)         OUT="$2"; shift 2 ;;
    --table)       TABLE=1; shift ;;
    --quiet)       QUIET=1; shift ;;
    --token)       TOKEN_OVERRIDE="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; POSITIONAL_TERMS=("$@"); break ;;
    -*)            echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)             POSITIONAL_TERMS+=("$1"); shift ;;
  esac
done

log() { (( QUIET )) || printf '%s\n' "$*" >&2; }

# ---------- preflight ----------
command -v jq   >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

# Token: --token > env > .env.local search upward
TOKEN="${TOKEN_OVERRIDE:-${ADS_API_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env.local" ]]; then
      # shellcheck disable=SC1090
      tok=$(grep -E '^[[:space:]]*ADS_API_TOKEN=' "$dir/.env.local" \
            | tail -n1 | sed -E 's/^[[:space:]]*ADS_API_TOKEN=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
      if [[ -n "$tok" ]]; then TOKEN="$tok"; break; fi
    fi
    dir=$(dirname "$dir")
  done
fi
if (( ! DRY_RUN )) && [[ -z "$TOKEN" ]]; then
  echo "ADS_API_TOKEN not found. Set it in the environment, pass --token, or put" >&2
  echo "ADS_API_TOKEN=... in a .env.local file in the current directory or a parent." >&2
  exit 1
fi

# ---------- gather terms ----------
# 1. --terms-file
if [[ -n "$TERMS_FILE" ]]; then
  [[ -f "$TERMS_FILE" ]] || { echo "terms file not found: $TERMS_FILE" >&2; exit 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    TERMS+=("$line")
  done < "$TERMS_FILE"
fi
# 2. Positional after `--` or trailing bare args
if (( ${#POSITIONAL_TERMS[@]} > 0 )); then
  TERMS+=("${POSITIONAL_TERMS[@]}")
fi
# 3. stdin fallback if we still have nothing and stdin is piped
if (( ${#TERMS[@]} == 0 )) && [[ ! -t 0 ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    TERMS+=("$line")
  done
fi

(( ${#TERMS[@]} > 0 )) || { echo "no search terms provided (use --term, --terms-file, positional, or stdin)" >&2; exit 1; }

# Dedupe terms (case-insensitive) while preserving order.
# Uses a flat temp file rather than an associative array to stay compatible
# with macOS's system bash 3.2 (no `declare -A`).
_SEEN_TERMS_FILE=$(mktemp)
UNIQUE_TERMS=()
for t in "${TERMS[@]}"; do
  key=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
  if ! grep -qxF -- "$key" "$_SEEN_TERMS_FILE" 2>/dev/null; then
    printf '%s\n' "$key" >> "$_SEEN_TERMS_FILE"
    UNIQUE_TERMS+=("$t")
  fi
done
rm -f "$_SEEN_TERMS_FILE"
TERMS=("${UNIQUE_TERMS[@]}")

# ---------- default dates ----------
if (( ! NO_DATE )); then
  if [[ -z "$END_DATE" ]]; then
    END_DATE=$(date +%Y-%m)
  fi
fi

# ---------- build fq filters ----------
urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

FQ_PARTS=()
[[ "$DATABASE" != "all" ]] && FQ_PARTS+=("database:${DATABASE}")
(( REFEREED )) && FQ_PARTS+=("property:refereed")
if (( ! NO_DATE )); then
  if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    FQ_PARTS+=("pubdate:[${START_DATE} TO ${END_DATE}]")
  elif [[ -n "$START_DATE" ]]; then
    FQ_PARTS+=("pubdate:[${START_DATE} TO *]")
  elif [[ -n "$END_DATE" ]]; then
    FQ_PARTS+=("pubdate:[* TO ${END_DATE}]")
  fi
fi

FQ_QS=""
for f in "${FQ_PARTS[@]}"; do
  FQ_QS+="&fq=$(urlenc "$f")"
done

# ---------- chunk terms so q stays under Q_BUDGET ----------
CHUNKS=()
current=""
for t in "${TERMS[@]}"; do
  # escape any internal double quotes in the term
  esc=${t//\"/\\\"}
  piece="${MATCH_FIELD}:\"${esc}\""
  if [[ -z "$current" ]]; then
    candidate="$piece"
  else
    candidate="${current} OR ${piece}"
  fi
  wrapped_len=$(( ${#candidate} + 2 ))  # for wrapping parens
  if (( wrapped_len > Q_BUDGET )) && [[ -n "$current" ]]; then
    CHUNKS+=("$current")
    current="$piece"
  else
    current="$candidate"
  fi
done
[[ -n "$current" ]] && CHUNKS+=("$current")

log "Terms: ${#TERMS[@]}  Chunks: ${#CHUNKS[@]}  Match: ${MATCH_FIELD}  Filters: ${FQ_PARTS[*]:-none}  Max: ${MAX_RESULTS}"

# ---------- execute queries ----------
# If --table was requested without --out, buffer to a tempfile so the table can
# be rendered at the end; the buffer is streamed to stdout and deleted. Nothing
# is ever written inside the repo unless the user explicitly set --out.
BUFFER=""
if [[ -z "$OUT" ]] && (( TABLE )); then
  BUFFER=$(mktemp "${TMPDIR:-/tmp}/ads-search.XXXXXX.jsonl")
fi

if [[ -n "$OUT" ]]; then
  : > "$OUT"
fi
emit() {
  if [[ -n "$OUT" ]]; then
    printf '%s\n' "$1" >> "$OUT"
  elif [[ -n "$BUFFER" ]]; then
    printf '%s\n' "$1" >> "$BUFFER"
  else
    printf '%s\n' "$1"
  fi
}

SEEN=$(mktemp); trap 'rm -f "$SEEN" "$TMPRESP" "$BUFFER"' EXIT
TMPRESP=$(mktemp)

written=0
for i in "${!CHUNKS[@]}"; do
  chunk="${CHUNKS[$i]}"
  q="(${chunk})"
  start=0

  while (( written < MAX_RESULTS )); do
    page_rows=$(( MAX_RESULTS - written ))
    (( page_rows > ROWS )) && page_rows=$ROWS

    url="${BASE_URL}?q=$(urlenc "$q")${FQ_QS}&fl=$(urlenc "$FIELDS")&rows=${page_rows}&start=${start}&sort=$(urlenc "$SORT")"

    if (( DRY_RUN )); then
      log "[dry-run] chunk $((i+1))/${#CHUNKS[@]} start=${start}"
      log "  q:   $q"
      log "  fq:  ${FQ_PARTS[*]:-}"
      log "  url: $url"
      break
    fi

    http_code=$(curl -sS -o "$TMPRESP" -w '%{http_code}' \
                     -H "Authorization: Bearer ${TOKEN}" "$url" || true)
    if [[ "$http_code" != "200" ]]; then
      echo "ADS API HTTP $http_code on chunk $((i+1)) start=$start" >&2
      head -c 1000 "$TMPRESP" >&2; echo >&2
      exit 1
    fi
    if ! jq -e '.response.docs' >/dev/null 2>&1 < "$TMPRESP"; then
      echo "Unexpected response on chunk $((i+1)) start=$start:" >&2
      head -c 1000 "$TMPRESP" >&2; echo >&2
      exit 1
    fi

    num_found=$(jq -r '.response.numFound' < "$TMPRESP")
    num_docs=$(jq -r '.response.docs | length' < "$TMPRESP")
    (( num_docs == 0 )) && break

    while IFS= read -r doc; do
      bib=$(jq -r '.bibcode // empty' <<<"$doc")
      [[ -z "$bib" ]] && continue
      if ! grep -qxF -- "$bib" "$SEEN"; then
        echo "$bib" >> "$SEEN"
        emit "$doc"
        written=$(( written + 1 ))
        (( written >= MAX_RESULTS )) && break
      fi
    done < <(jq -c '.response.docs[]' < "$TMPRESP")

    start=$(( start + num_docs ))
    (( start >= num_found )) && break
  done
done

(( DRY_RUN )) && exit 0

log ""
log "Found ${written} unique papers${OUT:+ (written to $OUT)}"

if (( TABLE )); then
  src="${OUT:-$BUFFER}"
  if [[ -n "$src" && -s "$src" ]]; then
    {
      printf '\n%-22s  %-4s  %-24s  %s\n' "BIBCODE" "YEAR" "FIRST AUTHOR" "TITLE"
      printf '%-22s  %-4s  %-24s  %s\n' "----------------------" "----" "------------------------" "-----"
      jq -r '[.bibcode, ((.pubdate // "----")[:4]), (.first_author // ""), ((.title // [""])[0])] | @tsv' "$src" \
        | awk -F'\t' '{
            fa = substr($3, 1, 24);
            ti = substr($4, 1, 80);
            printf "%-22s  %-4s  %-24s  %s\n", $1, $2, fa, ti
          }'
    } >&2
  fi
fi

# If we buffered for --table, stream the JSONL to stdout now (tempfile is
# removed by the EXIT trap).
if [[ -n "$BUFFER" && -s "$BUFFER" ]]; then
  cat "$BUFFER"
fi
