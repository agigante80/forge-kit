#!/usr/bin/env bash
# Which documents a range of commits made stale, as a check rather than a reading (#247).
#
# "Sometimes we forget to update the docs" is the maintainer's own description of the failure, and
# this repository has the receipts: two phases swept stale counts by hand across README.md and
# CLAUDE.md, and one guard's first draft claimed 22 guards and 34 suites and was wrong on both.
# Every one of those was found by a person reading, which is the method this kit exists to replace.
#
# THE QUESTION IS MECHANICAL, and stating it that way is the whole script: for each claim a
# document makes about a path, is the last commit that touched THAT LINE older than a commit in the
# range that touched the path? It is a question about one line's age and one path's history, never
# a judgement about prose.
#
# IT REPORTS, IT NEVER FAILS. Exit 0 whether or not rows were printed; exit 2 only when it could
# not run. That is check-ticket-mechanics.sh's posture and it is here for the same reason: a
# heuristic that fails a build gets argued with and then switched off, and everywhere else in this
# tree exit 1 already means "blocked". The callers count ROWS. Which caller runs it is decided by
# the phase review and the roadmap reassessment, not here.
#
# THE RESIDUAL LIMIT, stated rather than discovered. The line-level rule survives an unrelated edit
# to the document, which a document-level rule would not. It does NOT survive a REFLOW that rewraps
# the exact line carrying a claim: rewrapping updates that line's last-touched commit without
# anyone having verified the claim, so the row is suppressed and the claim reads as fresh. Commit
# 1b5c744 in this repository, which is this script's own motivating commit, is exactly such a
# reflow. Narrower than the document-level failure, not eliminated.
#
# THE EXEMPTIONS HAVE THEIR OWN LIMITS, stated here beside the reflow one. An entry is keyed on a
# SUBSTRING of a line, so it says nothing about WHY that line is exempt beyond the reason a human
# wrote above it, and nothing checks that the reason is still true. An anchor can also go stale
# silently in one direction only: if the line is edited so the anchor no longer matches, the entry
# is reported stale on the next run, but if the line is edited so it stops being a mere mention and
# becomes a real claim while still containing the anchor, the row stays suppressed and nothing says
# so. That is the same shape as the reflow limit: the check sees text, not meaning.
#
# A GENERATED REGION IS SOMEBODY ELSE'S JOB. Claims inside the three marker regions are excluded by
# MARKER and not by document, because update-component-index.py --check already owns them and a
# second opinion on the same bytes is a duplicate failure. A path named both inside a region and in
# ordinary prose is reported for the prose line only.
#
# A COMPONENT NAME RESOLVES THROUGH THE CATALOGUE, never through a fourth definition of what a
# component path is. forge-adapt-catalogue.sh --tsv is the one definition and update-component-index.py
# already shells out to it for the same reason.
#
# Portability: bash 3.2 and BSD userland. No bash-4 expansions, no associative arrays, no
# `readlink -f`, no `grep -P`, no GNU `timeout`, and no `date -d`, since every time comparison here
# is on the integer seconds git already reports.
#
# Usage: check-doc-drift.sh --range <base>..<head> --docs <doc>[,<doc>...] [--root <dir>]
# Rows:  <document><TAB><line><TAB><claim><TAB><sha>

set -uo pipefail

RANGE=""
DOCS=""
ROOT=""
ALLOW=""
PROG="check-doc-drift"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --range) RANGE="${2-}"; shift 2 || die "--range needs a value" ;;
    --docs)  DOCS="${2-}";  shift 2 || die "--docs needs a value" ;;
    --root)  ROOT="${2-}";  shift 2 || die "--root needs a value" ;;
    --allow-file) ALLOW="${2-}"; shift 2 || die "--allow-file needs a value" ;;
    -h|--help) sed -n '1,40p' "$0"; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -n "$RANGE" ] || die "a commit range is required: --range <base>..<head>"
[ -n "$DOCS" ]  || die "at least one document is required: --docs <doc>[,<doc>...]"

if [ -n "$ROOT" ]; then
  cd "$ROOT" 2>/dev/null || die "no such directory: $ROOT"
fi
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"

# The range must RESOLVE. A range naming an object this repository does not have would otherwise
# enumerate nothing and every document would read clean, which is the one answer a check like this
# must never give by accident.
git rev-list --max-count=1 "$RANGE" >/dev/null 2>&1 || die "cannot resolve the range '$RANGE'"

TMP="$(mktemp -d)" || die "cannot create a temporary directory"
trap 'rm -rf "$TMP"' EXIT

# --- the exemptions, keyed on the TEXT of a claim and never on its line number ------------------
#
# The noise this answers is a per-LINE property, so a per-PATH filter cannot express it: in this
# repository's own README both noisy paths carry mentions AND claims. An in-document marker was the
# first choice and is UNPLACEABLE here: it must sit on its own line, because an end-of-line marker
# changes the claim line's content and `git blame` then re-dates it, suppressing the row for the
# wrong reason; and every suppression site is a mid-sentence continuation line, where an HTML
# comment interrupts the paragraph under CommonMark, or a table row where no marker can go.
#
# So an entry names a SUBSTRING of the claiming line. That survives the line moving, which a line
# number does not: this check blames HEAD, so inserting any line renumbers every row below it.
#
#   # the reason, required, on one or more comment lines immediately above
#   mention <document> <path> <anchor, the rest of the line>
#
# An anchor matching NO line in its document is STALE: reported, exit 0. That is a property of the
# DOCUMENT and not of the range, deliberately, because a rule phrased as "matches no row" would
# call a live entry stale on any range where its path did not change.
# An anchor matching MORE THAN ONE line REFUSES: an ambiguous exemption is one nobody can reason
# about. An unknown key, a missing field or an entry with no reason REFUSES for the same reason
# every allow-file in this tree does.

[ -n "$ALLOW" ] || ALLOW=".doc-drift-allow"
: > "$TMP/suppress"
if [ -f "$ALLOW" ]; then
  _n=0; _reason=0
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    _n=$((_n + 1))
    case "$_ln" in
      '') _reason=0; continue ;;
      '#'*) _reason=1; continue ;;
    esac
    [ "$_reason" = 1 ] || die "$ALLOW line $_n: an entry needs a reason on a comment line above it"
    _key="${_ln%% *}"
    [ "$_key" = mention ] || die "$ALLOW line $_n: unknown key '$_key' (only 'mention' is defined)"
    _rest="${_ln#* }"; [ "$_rest" != "$_ln" ] || die "$ALLOW line $_n: entry is missing its document"
    _doc="${_rest%% *}"
    _rest="${_rest#* }"; [ "$_rest" != "$_doc" ] || die "$ALLOW line $_n: entry is missing its path"
    _path="${_rest%% *}"
    _anchor="${_rest#* }"; [ "$_anchor" != "$_path" ] || die "$ALLOW line $_n: entry is missing its anchor"
    if ! git cat-file -e "HEAD:$_doc" 2>/dev/null; then
      printf '%s: %s line %d: stale, document %s is absent at HEAD\n' "$PROG" "$ALLOW" "$_n" "$_doc" >&2
      continue
    fi
    _hits="$(git show "HEAD:$_doc" 2>/dev/null | LC_ALL=C grep -nF -- "$_anchor" | cut -d: -f1)"
    _c="$(printf '%s\n' "$_hits" | grep -c . || true)"
    if [ "$_c" = 0 ]; then
      printf '%s: %s line %d: stale, no line of %s contains that anchor\n' "$PROG" "$ALLOW" "$_n" "$_doc" >&2
      continue
    fi
    [ "$_c" = 1 ] || die "$ALLOW line $_n: the anchor matches more than one line of $_doc (lines $(printf '%s' "$_hits" | tr '\n' ' ')); lengthen it"
    printf '%s\t%s\t%s\n' "$_doc" "$_hits" "$_path" >> "$TMP/suppress"
  done < "$ALLOW"
fi

# --- what the range changed, and when ---------------------------------------------------------
# git log is newest-first, so the FIRST commit a path appears under is its newest in this range.
git log --pretty=format:'C %H %ct' --name-only "$RANGE" 2>/dev/null \
  | awk '
      $1 == "C" { sha = $2; ct = $3; next }
      NF == 0 { next }
      { if (!($0 in seen)) { seen[$0] = 1; printf "%s\t%s\t%s\n", $0, sha, ct } }
    ' > "$TMP/changed" || die "cannot read the log for '$RANGE'"

# --- component names, resolved by the one definition of what a component is --------------------
: > "$TMP/names"
CAT="$(dirname "$0")/forge-adapt-catalogue.sh"
if [ -f "$CAT" ] && [ -d plugins ]; then
  bash "$CAT" --tsv . 2>/dev/null \
    | awk -F'\t' 'NF >= 5 { p = $5; sub(/^\.\//, "", p); printf "%s\t%s\n", $3, p }' \
    > "$TMP/names" || : > "$TMP/names"
fi

# --- the marker regions somebody else owns ------------------------------------------------------
REGION_IDS="plugin-catalogue component-index plugin-groups"

found=0
OLDIFS=$IFS
IFS=,
set -f
for doc in $DOCS; do
  set +f
  IFS=$OLDIFS
  [ -n "$doc" ] || continue

  if ! git cat-file -e "HEAD:$doc" 2>/dev/null; then
    if [ -e "$doc" ]; then
      die "'$doc' is untracked, so it has no commit history and staleness has no meaning for it"
    fi
    die "'$doc' is absent from the repository at HEAD"
  fi

  git show "HEAD:$doc" > "$TMP/text" 2>/dev/null || die "cannot read '$doc' at HEAD"

  # One blame per document, never one `git log -L` per claim. Measured on this tree: 0.032s for a
  # whole file against about 25ms per claim, which is seconds for a document carrying a hundred of
  # them, and a check that costs seconds is a check that gets bypassed.
  git blame --porcelain HEAD -- "$doc" 2>/dev/null \
    | awk '
        $1 ~ /^[0-9a-f]+$/ && length($1) == 40 && NF >= 3 { sha = $1; ln = $3; next }
        $1 == "committer-time" { ct[sha] = $2; next }
        /^\t/ { printf "%d\t%s\t%s\n", ln, sha, ct[sha] }
      ' > "$TMP/blame" || die "cannot blame '$doc' at HEAD"

  rows="$(
    awk -v doc="$doc" -v regions="$REGION_IDS" -F'\t' '
      FILENAME == ARGV[1] { csha[$1] = $2; cct[$1] = $3; next }
      FILENAME == ARGV[2] { npath[$1] = $2; next }
      FILENAME == ARGV[3] { bsha[$1] = $2; bct[$1] = $3; next }
      FILENAME == ARGV[4] { sup[$1 SUBSEP $2 SUBSEP $3] = 1; next }
      {
        line = FNR
        # A marker region is entered and left by its own comment, and both delimiter lines are
        # inside it. Keyed on the three ids this tree generates, never on "any marker".
        n = split(regions, rid, " ")
        for (i = 1; i <= n; i++) {
          if (index($0, "<!-- " rid[i] ":start -->")) inregion = 1
          if (index($0, "<!-- " rid[i] ":end -->"))   { print_after = 1 }
        }
        if (inregion) { if (print_after) { inregion = 0; print_after = 0 } next }
        print_after = 0

        rest = $0
        while (match(rest, /`[^`]+`/)) {
          tok = substr(rest, RSTART + 1, RLENGTH - 2)
          rest = substr(rest, RSTART + RLENGTH)
          path = ""
          if (tok in csha) path = tok
          else if (tok in npath && npath[tok] in csha) path = npath[tok]
          if (path == "") continue
          if (!(line in bsha)) continue
          # No sha comparison. A line whose last commit IS the commit that changed the path
          # carries the timestamp of that same commit, so the age test below decides the
          # same-commit case as well. A separate equality branch looked like a second rule and
          # was unreachable by any input, which is the dead code this tree keeps finding.
          if (bct[line] + 0 >= cct[path] + 0) continue    # the line is no older than the change
          if ((doc SUBSEP line SUBSEP path) in sup) continue
          key = line "\t" tok
          if (key in done) continue
          done[key] = 1
          printf "%s\t%d\t%s\t%s\n", doc, line, tok, csha[path]
        }
      }
    ' "$TMP/changed" "$TMP/names" "$TMP/blame" "$TMP/suppress" "$TMP/text"
  )"

  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
    found=$((found + $(printf '%s\n' "$rows" | grep -c .)))
  fi

  IFS=,
  set -f
done
set +f
IFS=$OLDIFS

printf '%s: %d suspected stale claim(s) across the documents given.\n' "$PROG" "$found" >&2
exit 0
