#!/usr/bin/env bash
# check-rules.sh: fail if a registered rule stops having exactly one home, or if a rule version
# was bumped without retiring the wording it replaced.
#
# THE DEFECT THIS STOPS. A rule restated in several components drifts: changing it meant finding
# every copy, and copies were missed (#495). Each rule now lives once, in the home named by
# scripts/rules.tsv, and every place that names it carries the rule id comment
# `<!-- rule: <id> v<N> -->`. Then the review-lows v2 wording went unretired for a whole version:
# nothing forced the retired-rules.tsv rows that let forge-adapt drift find a project's stale copy.
# For every row of rules.tsv this keeps true:
#   1. the home carries exactly one id comment for the rule, and every anchor phrase of check 4;
#   2. each declared pointer carries the id, every id comment in it at the home's version;
#   3. any other tracked file under plugins/ or docs/ that carries the id has the home's version;
#   4. the rule's anchor phrases appear under plugins/ in the home only (matched
#      case-insensitively with whitespace collapsed, so a wrapped restatement is still found);
#   5. every row for the id in forge-adapt's retired-rules.tsv is below the home's version, so the
#      data file can never retire the rule that is current;
#   6. every version below the home's has at least one retired-rules.tsv row, so a bump that
#      forgets to retire the old wording fails here instead of leaving downstream copies unflagged.
# And across the tree:
#   7. every rule id comment under plugins/ or docs/ names a registered rule: a new rule is a row
#      in rules.tsv, not an id comment nothing checks.
# An id with retired-rules.tsv rows and no rules.tsv row (gate-committee) is retired for good.
# Bump the id in the home and every pointer together when the rule text changes meaning, and add
# the retired phrasings of the old version to retired-rules.tsv in the same commit.
#
# Usage: check-rules.sh [--root <checkout>]
# Exit 0 consistent, 1 a check failed (each named with its file), 2 an error.
set -uo pipefail

die() { echo "check-rules: $1" >&2; exit 2; }

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

REG="scripts/rules.tsv"
TSV="plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv"

failed=0
flag() { echo "check-rules: $1"; failed=1; }
# versions of every rule id comment for id $1 in file $2, one per line
ids() { grep -oE "<!-- rule: $1 v[0-9]+ -->" -- "$2" | sed -E 's/.* v([0-9]+) -->/\1/'; }

[ -f "$ROOT/$REG" ] || die "missing the rule registry $REG"
[ -f "$ROOT/$TSV" ] || die "missing $TSV"
files=$(git -C "$ROOT" ls-files -- plugins docs 2>/dev/null) || die "cannot list tracked files under $ROOT"
rows=$(grep -v '^#' "$ROOT/$REG" | grep -v '^[[:space:]]*$')
retired=$(grep -v '^#' "$ROOT/$TSV")
registered=""
ok_rules=""

while IFS=$'\t' read -r ID CANON POINTERS ANCHORS extra; do
  [ -n "$ID" ] || continue
  if [ -n "$extra" ] || [ -z "$ANCHORS" ]; then flag "$REG: row '$ID' must have exactly four tab-separated columns"; continue; fi
  case "$ID" in *[!a-z0-9-]*) flag "$REG: rule id '$ID' must be lowercase letters, digits and dashes"; continue ;; esac
  if grep -qxF -- "$ID" <<< "$registered"; then flag "$REG: rule id '$ID' is registered twice; a rule has one home"; continue; fi
  registered="$registered$ID"$'\n'
  if [ ! -f "$ROOT/$CANON" ]; then flag "$CANON: the home of $ID is missing"; continue; fi
  pointers=$(tr ' ' '\n' <<< "$POINTERS" | grep -v '^$')
  anchors=$(tr '|' '\n' <<< "$ANCHORS" | grep -v '^$')
  before=$failed; failed=0

  # 1. one id in the home
  canon_ids=$(ids "$ID" "$ROOT/$CANON")
  n=$(printf '%s' "$canon_ids" | grep -c . | tr -d ' ')
  if [ "$n" -ne 1 ]; then
    flag "$CANON: must carry exactly one '<!-- rule: $ID v<N> -->' comment (found $n)"; continue
  fi
  V="$canon_ids"

  # 1b. the anchors are phrases of the home's text: once one is reworded out of it, check 4
  # matches nothing anywhere and passes forever, so a missing anchor fails here.
  canon_flat=$(tr -s '[:space:]' ' ' < "$ROOT/$CANON")
  while IFS= read -r a; do
    grep -qiF -- "$a" <<< "$canon_flat" || flag "$CANON: anchor '$a' of $ID is missing; name a phrase the rule still uses in $REG"
  done <<< "$anchors"

  # 2. declared pointers
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -f "$ROOT/$p" ]; then flag "$p: declared pointer of $ID is missing"; continue; fi
    got=$(ids "$ID" "$ROOT/$p")
    if [ -z "$got" ]; then flag "$p: declared pointer carries no rule id for $ID (expected v$V)"; continue; fi
    for m in $got; do [ "$m" = "$V" ] || flag "$p: rule id $ID v$m, canonical is v$V"; done
  done <<< "$pointers"

  # 3. every other carrier under plugins/ or docs/; 4. anchors outside the home
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$p" = "$CANON" ] && continue
    [ -f "$ROOT/$p" ] && [ ! -L "$ROOT/$p" ] || continue
    if ! grep -qxF -- "$p" <<< "$pointers"; then
      for m in $(ids "$ID" "$ROOT/$p"); do [ "$m" = "$V" ] || flag "$p: rule id $ID v$m, canonical is v$V"; done
    fi
    case "$p" in
      plugins/*)
        flat=$(tr -s '[:space:]' ' ' < "$ROOT/$p")
        while IFS= read -r a; do
          if grep -qiF -- "$a" <<< "$flat"; then flag "$p: restates '$a' from $CANON; point at the rule's home instead"; fi
        done <<< "$anchors" ;;
    esac
  done <<< "$files"

  # 5. the data file retires only older versions; 6. and every older version is retired
  seen=""
  while IFS=$'\t' read -r rid rver _; do
    [ "$rid" = "$ID" ] || continue
    case "$rver" in ''|*[!0-9]*) flag "$TSV: $ID row has a non-numeric version '$rver'"; continue ;; esac
    [ "$rver" -lt "$V" ] || flag "$TSV: retires $ID v$rver, but the canonical rule is v$V"
    seen="$seen$rver"$'\n'
  done <<< "$retired"
  k=1
  while [ "$k" -lt "$V" ]; do
    grep -qxF -- "$k" <<< "$seen" || flag "$TSV: no row retires $ID v$k; list its phrasings so forge-adapt drift finds a copy still at v$k"
    k=$((k + 1))
  done

  [ "$failed" -eq 0 ] && ok_rules="$ok_rules $ID v$V"
  [ "$before" -ne 0 ] && failed=1
done <<< "$rows"

# 7. no id comment names an unregistered rule
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -f "$ROOT/$p" ] && [ ! -L "$ROOT/$p" ] || continue
  for rid in $(grep -oE '<!-- rule: [^ ]+ v[0-9]+ -->' -- "$ROOT/$p" | sed -E 's/<!-- rule: ([^ ]+) v.*/\1/' | sort -u); do
    grep -qxF -- "$rid" <<< "$registered" || flag "$p: rule id '$rid' is not registered in $REG; add its row or drop the comment"
  done
done <<< "$files"

if [ "$failed" -ne 0 ]; then exit 1; fi
echo "check-rules: every registered rule has one home and every pointer agrees:$ok_rules."
exit 0
