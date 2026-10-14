#!/usr/bin/env bash
# check-review-rule.sh: fail if the review-lows rule stops having exactly one home (#495).
#
# THE DEFECT THIS STOPS. The rule for Low findings was restated in code-reviewer, /full-review and
# the overnight pipeline, so changing it meant finding every copy, and the copies were missed.
# The rule now lives once, in the review-lows skill, and every place that names it carries the
# same rule id comment `<!-- rule: review-lows v<N> -->`. This keeps that true:
#   1. the canonical skill carries exactly one rule id, and every anchor phrase of check 4;
#   2. each declared pointer below carries it, every id comment in it at the canonical version;
#   3. any other tracked file under plugins/ or docs/ that carries the id has the canonical version;
#   4. the rule's own anchor phrases appear under plugins/ in the canonical skill only (matched
#      case-insensitively with whitespace collapsed, so a wrapped restatement is still found);
#   5. every review-lows row of forge-adapt's retired-rules.tsv is below the canonical version, so
#      the data file can never retire the rule that is current.
# Bump the id in the skill and every pointer together when the rule text changes meaning.
#
# Usage: check-review-rule.sh [--root <checkout>]
# Exit 0 consistent, 1 a check failed (each named with its file), 2 an error.
set -uo pipefail

die() { echo "check-review-rule: $1" >&2; exit 2; }

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

ID="review-lows"
CANON="plugins/forge-kit-review/skills/review-lows/SKILL.md"
POINTERS="plugins/forge-kit-review/agents/code-reviewer.md
plugins/forge-kit-review/commands/full-review.md
plugins/forge-kit-governance/skills/working-overnight/references/pipeline.md
docs/guides/review-loop.md"
ANCHORS="roughly 15 minutes
could really hit"
TSV="plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv"

failed=0
flag() { echo "check-review-rule: $1"; failed=1; }
# versions of every rule id comment for $ID in a file, one per line
ids() { grep -oE "<!-- rule: $ID v[0-9]+ -->" -- "$1" | sed -E 's/.* v([0-9]+) -->/\1/'; }

[ -f "$ROOT/$CANON" ] || die "missing the canonical rule $CANON"
[ -f "$ROOT/$TSV" ] || die "missing $TSV"
files=$(git -C "$ROOT" ls-files -- plugins docs 2>/dev/null) || die "cannot list tracked files under $ROOT"

# 1. one id in the canonical home
canon_ids=$(ids "$ROOT/$CANON")
n=$(printf '%s' "$canon_ids" | grep -c . | tr -d ' ')
[ "$n" -eq 1 ] || { flag "$CANON: must carry exactly one '<!-- rule: $ID v<N> -->' comment (found $n)"; exit 1; }
V="$canon_ids"

# 1b. the anchors are phrases of the canonical text: once one is reworded out of it, check 4
# matches nothing anywhere and passes forever, so a missing anchor fails here.
canon_flat=$(tr -s '[:space:]' ' ' < "$ROOT/$CANON")
while IFS= read -r a; do
  grep -qiF -- "$a" <<< "$canon_flat" || flag "$CANON: anchor '$a' is missing; name a phrase the rule still uses in ANCHORS"
done <<< "$ANCHORS"

# 2. declared pointers
while IFS= read -r p; do
  if [ ! -f "$ROOT/$p" ]; then flag "$p: declared pointer is missing"; continue; fi
  got=$(ids "$ROOT/$p")
  if [ -z "$got" ]; then flag "$p: declared pointer carries no rule id for $ID (expected v$V)"; continue; fi
  for m in $got; do [ "$m" = "$V" ] || flag "$p: rule id $ID v$m, canonical is v$V"; done
done <<< "$POINTERS"

# 3. every other carrier under plugins/ or docs/; 4. anchors outside the canonical home
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ "$p" = "$CANON" ] && continue
  [ -f "$ROOT/$p" ] && [ ! -L "$ROOT/$p" ] || continue
  if ! grep -qxF -- "$p" <<< "$POINTERS"; then
    for m in $(ids "$ROOT/$p"); do [ "$m" = "$V" ] || flag "$p: rule id $ID v$m, canonical is v$V"; done
  fi
  case "$p" in
    plugins/*)
      flat=$(tr -s '[:space:]' ' ' < "$ROOT/$p")
      while IFS= read -r a; do
        if grep -qiF -- "$a" <<< "$flat"; then flag "$p: restates '$a' from $CANON; point at the skill instead"; fi
      done <<< "$ANCHORS" ;;
  esac
done <<< "$files"

# 5. the data file retires only older versions
while IFS=$'\t' read -r rid rver _; do
  [ "$rid" = "$ID" ] || continue
  case "$rver" in ''|*[!0-9]*) flag "$TSV: $ID row has a non-numeric version '$rver'"; continue ;; esac
  [ "$rver" -lt "$V" ] || flag "$TSV: retires $ID v$rver, but the canonical rule is v$V"
done < <(grep -v '^#' "$ROOT/$TSV")

if [ "$failed" -ne 0 ]; then exit 1; fi
echo "check-review-rule: $ID v$V has one home and every pointer agrees."
exit 0
