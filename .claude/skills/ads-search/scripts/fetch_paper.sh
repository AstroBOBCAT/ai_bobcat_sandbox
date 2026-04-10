#!/usr/bin/env bash
# fetch_paper.sh — download PDF and/or arXiv LaTeX source for a list of
# ADS bibcodes.
#
# Input: bibcodes on stdin (one per line) OR as positional args.
# Output: files written under --dir (default: $TMPDIR/ads-papers). The
# default is outside the repo so nothing gets committed by accident.
#
# PDFs are fetched via ADS's link_gateway redirector, which tries the
# arXiv preprint first. LaTeX source is fetched directly from
# https://arxiv.org/e-print/<id>, which requires an arXiv identifier —
# so the script first asks ADS for the paper's `identifier` field.
#
# Auth for the identifier lookup reuses the same ADS_API_TOKEN resolution
# as search_ads.sh (--token, env, or .env.local walking upward).

set -euo pipefail

DIR=""
WHAT="pdf"   # pdf | latex | both
TOKEN_OVERRIDE=""
QUIET=0
NO_TEXT=0
BIBS=()

usage() {
  cat <<'EOF'
Usage: fetch_paper.sh [options] [bibcode ...]

Reads bibcodes from positional args or stdin. Writes files under --dir.

Each fetched PDF is also extracted to a sibling .txt via pdftotext -layout,
unless --no-text is passed or pdftotext is unavailable. Plain text is much
easier to grep/jq/regex than PDF, so this is on by default.

Options:
  --dir PATH       Output directory (default: $TMPDIR/ads-papers, never the repo)
  --what KIND      pdf | latex | both  (default: pdf)
  --no-text        Do not run pdftotext on fetched PDFs
  --token TOKEN    Override ADS_API_TOKEN (only needed for --what latex/both)
  --quiet          Suppress progress on stderr
  -h, --help       Show this help

Examples:
  echo 2026ApJ...999..107F | fetch_paper.sh
  jq -r .bibcode results.jsonl | fetch_paper.sh --what both --dir ~/papers
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)    DIR="$2"; shift 2 ;;
    --what)   WHAT="$2"; shift 2 ;;
    --no-text) NO_TEXT=1; shift ;;
    --token)  TOKEN_OVERRIDE="$2"; shift 2 ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)       echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)        BIBS+=("$1"); shift ;;
  esac
done

if (( ${#BIBS[@]} == 0 )) && [[ ! -t 0 ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    BIBS+=("$line")
  done
fi

(( ${#BIBS[@]} > 0 )) || { echo "no bibcodes provided (pass as args or stdin)" >&2; exit 1; }

case "$WHAT" in pdf|latex|both) ;; *) echo "--what must be pdf|latex|both" >&2; exit 2 ;; esac

DIR="${DIR:-${TMPDIR:-/tmp}/ads-papers}"
mkdir -p "$DIR"

log() { (( QUIET )) || printf '%s\n' "$*" >&2; }

# Check once whether pdftotext is available; if not, silently disable text
# extraction. Only relevant when we're actually fetching PDFs.
HAVE_PDFTOTEXT=0
if command -v pdftotext >/dev/null 2>&1; then
  HAVE_PDFTOTEXT=1
elif (( ! NO_TEXT )) && [[ "$WHAT" != "latex" ]]; then
  log "note: pdftotext not found — skipping text extraction (install poppler to enable)"
fi

# Only load the ADS token if we need to resolve arXiv IDs for LaTeX source.
TOKEN=""
if [[ "$WHAT" != "pdf" ]]; then
  TOKEN="${TOKEN_OVERRIDE:-${ADS_API_TOKEN:-}}"
  if [[ -z "$TOKEN" ]]; then
    dir="$PWD"
    while [[ "$dir" != "/" ]]; do
      if [[ -f "$dir/.env.local" ]]; then
        tok=$(grep -E '^[[:space:]]*ADS_API_TOKEN=' "$dir/.env.local" \
              | tail -n1 | sed -E 's/^[[:space:]]*ADS_API_TOKEN=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
        if [[ -n "$tok" ]]; then TOKEN="$tok"; break; fi
      fi
      dir=$(dirname "$dir")
    done
  fi
  [[ -n "$TOKEN" ]] || { echo "ADS_API_TOKEN not found (needed for --what latex/both)" >&2; exit 1; }
fi

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

arxiv_id_for() {
  local bib="$1"
  local q="bibcode:\"$bib\""
  local url="https://api.adsabs.harvard.edu/v1/search/query?q=$(urlenc "$q")&fl=identifier&rows=1"
  curl -sS -H "Authorization: Bearer ${TOKEN}" "$url" \
    | jq -r '.response.docs[0].identifier // [] | map(select(test("^arXiv:"; "i"))) | .[0] // empty' \
    | sed 's/^arXiv://I'
}

fetch_pdf() {
  local bib="$1"
  local out="$DIR/${bib}.pdf"
  local url="https://ui.adsabs.harvard.edu/link_gateway/${bib}/EPRINT_PDF"
  log "  pdf  -> $out"
  if ! curl -sSL --fail -A "Mozilla/5.0 ads-search skill" -o "$out" "$url"; then
    log "    (EPRINT_PDF failed; trying PUB_PDF)"
    url="https://ui.adsabs.harvard.edu/link_gateway/${bib}/PUB_PDF"
    if ! curl -sSL --fail -A "Mozilla/5.0 ads-search skill" -o "$out" "$url"; then
      log "    !! pdf fetch failed for $bib"
      rm -f "$out"
      return 1
    fi
  fi

  # Auto-extract plain text alongside the PDF. pdftotext -layout preserves
  # column structure, which is useful for section/table parsing later.
  if (( ! NO_TEXT )) && (( HAVE_PDFTOTEXT )); then
    local txt="$DIR/${bib}.txt"
    if pdftotext -layout "$out" "$txt" 2>/dev/null; then
      log "  text -> $txt"
    else
      log "    !! pdftotext failed for $bib"
      rm -f "$txt"
    fi
  fi
}

fetch_latex() {
  local bib="$1"
  local aid
  aid=$(arxiv_id_for "$bib" || true)
  if [[ -z "$aid" ]]; then
    log "    !! no arXiv ID on record for $bib — skipping latex"
    return 1
  fi
  local out="$DIR/${bib}.tar.gz"
  local url="https://arxiv.org/e-print/${aid}"
  log "  latex-> $out  (arXiv:$aid)"
  if ! curl -sSL --fail -A "Mozilla/5.0 ads-search skill" -o "$out" "$url"; then
    log "    !! latex fetch failed for $bib ($aid)"
    rm -f "$out"
    return 1
  fi
}

log "Output dir: $DIR"
log "Mode: $WHAT    Papers: ${#BIBS[@]}"

for bib in "${BIBS[@]}"; do
  log "[$bib]"
  case "$WHAT" in
    pdf)   fetch_pdf "$bib" || true ;;
    latex) fetch_latex "$bib" || true ;;
    both)  fetch_pdf "$bib" || true; fetch_latex "$bib" || true ;;
  esac
done

log "Done. Files in: $DIR"
