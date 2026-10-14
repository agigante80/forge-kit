#!/usr/bin/env bash
# check-retired-rules.sh: fail if forge-kit's own tracked tree still states a retired rule (#495).
#
# THE DEFECT THIS STOPS. review-lows v1 ("every Low is ticketed") was replaced in the maintainer's
# own instructions, yet code-reviewer, /full-review and the overnight pipeline kept stating it, and
# every project that installed them inherited it. Nothing looked. This runs forge-adapt's own
# stale-rules.sh matcher (--files-from) over every tracked text file, so the kit fails on exactly
# what it would report in a downstream project, with the same paragraph matching and opt-out.
#
# EXEMPTIONS, each a whole file named here with its reason; never a directory, and never anything
# under plugins/ beyond the data file, or the guard would stop guarding the components:
#   plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv   the data: it IS the phrasings
#   scripts/test-forge-adapt-stale-rules.sh                          fixture text quotes them
#   scripts/test-check-retired-rules.sh                              fixture text quotes them
#   CHANGELOG.md                                                     history quotes what it retires
# A single deliberate quote anywhere else carries the word `retired-rule-quote` on its line.
#
# Usage: check-retired-rules.sh [--root <checkout>]
# Exit 0 clean, 1 a hit (each printed as `<path>:<line>: retired rule <id>`), 2 an error.
set -uo pipefail

die() { echo "check-retired-rules: $1" >&2; exit 2; }

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || die "--root needs a value"; ROOT="$2"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
if [ -z "$ROOT" ]; then
  ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || die "not a git checkout; pass --root"
fi
ROOT="$(CDPATH= cd -P -- "$ROOT" 2>/dev/null && pwd -P)" || die "no such directory '$ROOT'"

SCANNER="plugins/forge-kit-adapt/skills/adapt/assets/stale-rules.sh"

EXEMPT="plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv
scripts/test-forge-adapt-stale-rules.sh
scripts/test-check-retired-rules.sh
CHANGELOG.md"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-retired-rules.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# Tracked files, from the index: a listing failure must never read as an empty, clean tree. A
# symlink is a pointer whose target is tracked and scanned itself; `grep -I` drops a binary (and an
# empty file, which states nothing). An UNREADABLE file stays in the list on purpose: the scanner
# reports it not-scanned and exits 3, which fails here, where skipping it would be a false clean.
git -C "$ROOT" ls-files > "$WORK/all" 2>"$WORK/err" || die "cannot list tracked files: $(head -1 "$WORK/err")"
: > "$WORK/list"
while IFS= read -r p; do
  if printf '%s\n' "$EXEMPT" | grep -qxF -- "$p"; then continue; fi
  [ -L "$ROOT/$p" ] && continue
  [ -e "$ROOT/$p" ] || continue
  grep -Iq . -- "$ROOT/$p" 2>/dev/null; [ "$?" -eq 1 ] && continue
  printf '%s\n' "$p" >> "$WORK/list"
done < "$WORK/all"
[ -s "$WORK/list" ] || die "no tracked text files to scan under $ROOT"

(CDPATH= cd -- "$ROOT" && bash "$SCANNER" --kit "$ROOT" --files-from "$WORK/list") > "$WORK/out" 2>"$WORK/err"
rc=$?
case "$rc" in
  0|1) ;;
  3) die "the scan was incomplete: $(grep '^not-scanned' "$WORK/out" | head -3 | tr '\t' ' ')" ;;
  *) die "the scanner failed ($rc): $(head -1 "$WORK/err")" ;;
esac

awk -F '\t' '$1 == "stale-rule" { printf "%s:%s: retired rule %s\n", $3, $4, $5 }' "$WORK/out"
files=$(awk -F '\t' '$1 == "summary" { print $2 }' "$WORK/out")
if [ "$rc" -eq 1 ]; then
  echo "check-retired-rules: a retired rule is still stated above. Replace it with the current rule, or mark a deliberate quote with retired-rule-quote." >&2
  exit 1
fi
echo "check-retired-rules: ${files:-0} tracked files, no retired rule."
exit 0
