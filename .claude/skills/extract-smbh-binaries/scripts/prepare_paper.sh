#!/usr/bin/env bash
#
# prepare_paper.sh — prepare a paper for binary-SMBH candidate extraction.
#
# Given a path to a .pdf / .txt file, or a bare bibcode/stem, produces:
#   - a flat text extract (via `pdftotext -layout`)
#   - per-page PNGs at 150 dpi (via `pdftoppm`)
#
# Writes into $TMPDIR/smbh-prep/<stem>/ by default (never into the repo).
# Idempotent: reuses existing outputs.
#
# Stdout (one key=value per line):
#   STEM=<filename stem>
#   TEXT=<path to .txt extract>
#   IMAGES=<directory containing page-NN.png files>
#   PAGES=<number of rendered page PNGs>
#
# Progress/errors go to stderr.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: prepare_paper.sh <path-or-stem> [--workspace DIR] [--dpi N]

Accepts:
  - /path/to/paper.pdf          — PDF; extracts text and renders pages
  - /path/to/paper.txt          — plain text; will look for a sibling .pdf to render pages
  - 2026arXiv260406059T         — bare stem; resolved against ./papers/<stem>.{pdf,txt}

Options:
  --workspace DIR   Override workspace directory. Default: \$TMPDIR/smbh-prep/<stem>/
  --dpi N           DPI for page PNG rendering. Default: 150
  -h, --help        Show this help

Writes TEXT, IMAGES, PAGES, STEM paths to stdout for the caller to consume.
EOF
}

INPUT=""
WORKSPACE=""
DPI=150

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --dpi) DPI="$2"; shift 2 ;;
    --) shift; INPUT="${1:-}"; shift || true ;;
    -*)
      echo "error: unknown flag '$1'" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -z "$INPUT" ]]; then
        INPUT="$1"
        shift
      else
        echo "error: unexpected extra argument '$1'" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "error: no input given" >&2
  usage
  exit 2
fi

# ---- Tool presence checks (just warn if renderer is missing; text-only is OK) ----
if ! command -v pdftotext >/dev/null 2>&1; then
  echo "warning: pdftotext not found — will only work if a .txt already exists" >&2
fi
if ! command -v pdftoppm >/dev/null 2>&1; then
  echo "warning: pdftoppm not found — page images will not be rendered" >&2
fi

# ---- Resolve input to PDF and/or TXT, and pick a stem ----
PDF=""
TXT_IN=""
STEM=""

if [[ -f "$INPUT" ]]; then
  case "$INPUT" in
    *.pdf|*.PDF)
      PDF="$INPUT"
      STEM="$(basename "${INPUT%.*}")"
      SIBLING_TXT="${INPUT%.*}.txt"
      [[ -f "$SIBLING_TXT" ]] && TXT_IN="$SIBLING_TXT"
      ;;
    *.txt|*.TXT)
      TXT_IN="$INPUT"
      STEM="$(basename "${INPUT%.*}")"
      SIBLING_PDF="${INPUT%.*}.pdf"
      [[ -f "$SIBLING_PDF" ]] && PDF="$SIBLING_PDF"
      ;;
    *)
      echo "error: '$INPUT' exists but is not a .pdf or .txt file" >&2
      exit 2
      ;;
  esac
else
  # If it looks like a filesystem path, report it as missing directly —
  # don't fall through to the bare-stem lookup, which would give a
  # misleading "looked in ./papers/" error.
  case "$INPUT" in
    */*|*.pdf|*.PDF|*.txt|*.TXT)
      echo "error: file not found: '$INPUT'" >&2
      exit 2
      ;;
  esac
  # Treat as a bare stem and try ./papers/
  STEM="$(basename "$INPUT")"
  if [[ -f "./papers/${STEM}.pdf" ]]; then PDF="./papers/${STEM}.pdf"; fi
  if [[ -f "./papers/${STEM}.txt" ]]; then TXT_IN="./papers/${STEM}.txt"; fi
  if [[ -z "$PDF" && -z "$TXT_IN" ]]; then
    echo "error: could not resolve '$INPUT' to a .pdf or .txt (looked in ./papers/)" >&2
    exit 2
  fi
fi

if [[ -z "$STEM" ]]; then
  echo "error: could not derive a stem from '$INPUT'" >&2
  exit 2
fi

# ---- Set up the workspace ----
if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="${TMPDIR:-/tmp}/smbh-prep/${STEM}"
fi
mkdir -p "$WORKSPACE"
IMG_DIR="$WORKSPACE/pages"
mkdir -p "$IMG_DIR"

TXT_OUT="$WORKSPACE/${STEM}.txt"

# ---- Text extraction ----
if [[ -n "$TXT_IN" ]]; then
  # Prefer an already-extracted .txt. Only copy if different to avoid
  # clobbering edits the user may have made in the workspace.
  if [[ ! -f "$TXT_OUT" ]]; then
    cp "$TXT_IN" "$TXT_OUT"
  fi
elif [[ -n "$PDF" ]]; then
  if [[ ! -s "$TXT_OUT" ]]; then
    echo "info: extracting text from $PDF -> $TXT_OUT" >&2
    pdftotext -layout "$PDF" "$TXT_OUT"
  fi
else
  echo "error: no text source available" >&2
  exit 2
fi

# ---- Page rendering ----
PAGE_COUNT=0
if [[ -n "$PDF" && -f "$PDF" ]] && command -v pdftoppm >/dev/null 2>&1; then
  # Only render if the image directory is empty
  if ! compgen -G "$IMG_DIR/page-*.png" >/dev/null; then
    echo "info: rendering $PDF pages at ${DPI} dpi -> $IMG_DIR/page-NN.png" >&2
    pdftoppm -png -r "$DPI" "$PDF" "$IMG_DIR/page"
  fi
  PAGE_COUNT=$(compgen -G "$IMG_DIR/page-*.png" | wc -l | tr -d ' ')
fi

# ---- Output ----
echo "STEM=$STEM"
echo "TEXT=$TXT_OUT"
echo "IMAGES=$IMG_DIR"
echo "PAGES=$PAGE_COUNT"
