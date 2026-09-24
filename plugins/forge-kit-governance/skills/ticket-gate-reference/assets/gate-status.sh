#!/usr/bin/env bash
# gate-status-version: 2
# gate-status.sh <issue-number>                 is the body's gate verdict current or stale?
# gate-status.sh <issue-number> --fingerprint   the hash of the body outside every region
# gate-status.sh <issue-number> --unstamp       remove the Judged line (gate Step 1)
# gate-status.sh <issue-number> --stamp         move the verdict to the top and record the hash (Step 6, last)
# gate-status.sh <issue-number> --mark-stale    mark a stale verdict STALE (the issues:edited workflow)
#
# WHY (#284). Later sessions read a ticket's BODY, not its comments, so the gate's `gate-verdict`
# block is what they act on. It used to go stale the moment the author folded the required changes
# into the ticket: the block still said NEEDS-WORK with every item unchecked, and a reader redid
# finished work. It also sat at the bottom, below every section a reader had already acted on.
#
# THE FINGERPRINT is `sha256:<16 hex>` of the body with every `<!-- <name>:start -->` ...
# `<!-- <name>:end -->` region removed (every prefix, not only the gate's), CR and trailing blanks
# stripped from every line, runs of blank lines collapsed to one, and blank lines at the start and
# the end dropped. So it moves when an AUTHOR section changes and never when any writer's region
# changes, is placed, or is moved: the stamp's own move to the top leaves it unchanged. A decision
# written only inside a `brief-*` region therefore does not make the verdict stale, deliberately:
# it is not a change to what the ticket asks for until its author folds it into a section.
#
# An UNPAIRED marker (a start with no end, or an end with no start) refuses with exit 2, the
# splice's 103 shape, rather than hashing to the end of the body and calling that an answer.
#
# STATES, one line on stdout, exit 0: `ungated`, `unrecorded round <R>` (a verdict with no Judged
# line: gated before #284, mid-run, or ended early), `current round <R> <VERDICT>`,
# `stale round <R> <VERDICT>`. Exit 2 with NOTHING on stdout when the body cannot be read, since a
# state that cannot be computed must never read as `current`.
#
# THE ORDER OF WRITES IS THE CONTRACT. Every gate write is an `issues: edited` event, so the gate
# must never leave a stamped verdict in place while it changes author text: `--unstamp` at Step 1
# makes the verdict `unrecorded` for the whole run, `--mark-stale` leaves an unrecorded verdict
# alone, and `--stamp` comes last, after every author write. `--stamp` records the fingerprint of
# the body it STARTED from, never a later one: when the body moves under a write (rc 102) it retries
# once only if the author sections are still what it started from, because a change that arrives
# now is a human's or another writer's and the gate never reviewed it. Anything else exits 1 and
# leaves the verdict `unrecorded`, which is honest. `--mark-stale` never retries: on 102 or 103 it prints a
# notice and exits 0 sending nothing, because the next edit event checks again and a marker pair it
# does not understand is not one to guess about.
#
# THE BLOCK IS A DISPLAY, NEVER AN AUTHORITY. Anyone who can edit the issue can write a block that
# reads `current ... PASS`, since the fingerprint is a hash of public text and not a signature. No
# component may treat this script's output as readiness; the review comment is the record.
#
# It writes only `gate-*` regions, with prefix `gate`, through forge-lib.sh's region primitives, so
# #248's disjointness contract holds. It never prints a comment author.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Resolved exactly as count-gate-rounds.sh resolves it: beside this script (a forge-adapt install),
# then across plugin groups (a source checkout), else FORGE_LIB. Absent all three, REFUSE.
LIB="${FORGE_LIB:-}"
if [ -z "$LIB" ]; then
  if [ -f "$HERE/forge-lib.sh" ]; then LIB="$HERE/forge-lib.sh"
  elif [ -f "$HERE/../../../../forge-kit-devops/skills/forge-host/assets/forge-lib.sh" ]; then
    LIB="$HERE/../../../../forge-kit-devops/skills/forge-host/assets/forge-lib.sh"
  fi
fi
[ -n "$LIB" ] && [ -f "$LIB" ] || {
  echo "gate-status: forge-lib.sh not found beside this script (or via FORGE_LIB); refusing." >&2
  exit 2
}

usage() { echo "gate-status: usage: gate-status.sh <issue-number> [--fingerprint|--unstamp|--stamp|--mark-stale]" >&2; }

case "${1-}" in
  ''|*[!0-9]*) usage; exit 2 ;;
esac
ISSUE="$1"; MODE="${2-state}"
[ $# -le 2 ] || { usage; exit 2; }
case "$MODE" in
  state|--fingerprint|--unstamp|--stamp|--mark-stale) ;;
  *) echo "gate-status: unrecognised option '$MODE'" >&2; usage; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "gate-status: jq is required" >&2; exit 2; }
if command -v sha256sum >/dev/null 2>&1; then HASH="sha256sum"
elif command -v shasum >/dev/null 2>&1; then HASH="shasum -a 256"
else echo "gate-status: neither sha256sum nor shasum is available" >&2; exit 2; fi

# shellcheck source=/dev/null
. "$LIB"

body_of() {
  local raw
  raw="$(forge_issue_view "$ISSUE")" || return 2
  printf '%s' "$raw" | jq -e 'has("body")' >/dev/null 2>&1 || return 2
  printf '%s' "$raw" | jq -r '.body // ""'
}

fingerprint() {  # body on stdin
  local h
  h="$(awk '
    function norm(l) { sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); return l }
    { n = norm($0) }
    n ~ /^<!-- [^ \t]+:start -->$/ { if (inside) { bad = 1; exit 3 } inside = 1; next }
    n ~ /^<!-- [^ \t]+:end -->$/   { if (!inside) { bad = 1; exit 3 } inside = 0; next }
    inside { next }
    n == "" { if (seen) pend = 1; next }
    { if (pend) print ""; pend = 0; seen = 1; print n }
    END { if (bad || inside) exit 3 }
  ' | $HASH | cut -c1-16)" || return 2
  [ -n "$h" ] || return 2
  printf 'sha256:%s\n' "$h"
}

region() { forge_body_region_get "$ISSUE" "$1"; }

# A write that retries once on 102 (the body moved since it was read), and only while the author
# sections still hash to $FP0, the body the gate judged. A retry past a real author edit would
# stamp text nobody reviewed as current.
FP0=""
write_retry() {  # write_retry <region> <content> [top]
  local rc=0 now
  forge_body_region_set "$ISSUE" gate "$1" "$2" "${3-}" || rc=$?
  if [ "$rc" = 102 ] && [ -n "$FP0" ]; then
    now="$(body_of | fingerprint)" || return 1
    [ "$now" = "$FP0" ] || { echo "gate-status: issue #$ISSUE: an author section changed during the stamp; leaving the verdict unrecorded" >&2; return 1; }
    rc=0; forge_body_region_set "$ISSUE" gate "$1" "$2" "${3-}" || rc=$?
  fi
  return "$rc"
}

# A bare `Full review:` line is the pre-v60 pointer (#285): a gate agent copying an old block keeps
# it and the stamp would add a second. Anchored, so an item that MENTIONS it mid-line survives; the
# required-changes and alternatives regions never carry one, so the clause is inert there.
strip_stamp() {  # verdict content on stdin: drop the Judged, Stale and bare pointer lines and the STALE mark
  awk '/^Judged body: sha256:/ { next } /^\*\*Stale:\*\*/ { next } /^Full review: / { next }
       /^### / { sub(/: STALE[ \t]*$/, "") } { print }'
}

body="$(body_of)" || { echo "gate-status: could not read the body of issue #$ISSUE" >&2; exit 2; }
if [ "$MODE" != --fingerprint ] && ! printf '%s\n' "$body" | fingerprint >/dev/null; then
  echo "gate-status: issue #$ISSUE has an unpaired region marker; refusing" >&2; exit 2
fi

if [ "$MODE" = --fingerprint ]; then
  printf '%s\n' "$body" | fingerprint || { echo "gate-status: could not hash issue #$ISSUE" >&2; exit 2; }
  exit 0
fi

verdict="$(region gate-verdict)" || { echo "gate-status: could not read gate-verdict of issue #$ISSUE" >&2; exit 2; }

state_of() {
  local round word judged now
  if [ -z "$verdict" ]; then echo ungated; return 0; fi
  round="$(printf '%s\n' "$verdict" | sed -n 's/^### Gate verdict (round \([^)]*\)).*/\1/p' | head -1)"
  word="$(printf '%s\n' "$verdict" | sed -n 's/^\*\*Verdict:\*\* *\([A-Za-z-]*\).*/\1/p' | head -1)"
  judged="$(printf '%s\n' "$verdict" | sed -n 's/^Judged body: \(sha256:[0-9a-f]*\).*/\1/p' | head -1)"
  [ -n "$round" ] || round=unknown
  [ -n "$word" ] || word=unknown
  if [ -z "$judged" ]; then echo "unrecorded round $round"; return 0; fi
  now="$(printf '%s\n' "$body" | fingerprint)" || return 2
  if [ "$now" = "$judged" ]; then echo "current round $round $word"; else echo "stale round $round $word"; fi
}

case "$MODE" in
  state)
    st="$(state_of)" || { echo "gate-status: could not hash issue #$ISSUE" >&2; exit 2; }
    echo "$st"; exit 0 ;;

  --unstamp)
    printf '%s\n' "$verdict" | grep -q '^Judged body: sha256:' || exit 0
    write_retry gate-verdict "$(printf '%s\n' "$verdict" | grep -v '^Judged body: sha256:')" || {
      echo "gate-status: could not unstamp issue #$ISSUE" >&2; exit 1; }
    exit 0 ;;

  --stamp)
    [ -n "$verdict" ] || { echo "gate-status: issue #$ISSUE has no gate-verdict to stamp" >&2; exit 1; }
    FP0="$(printf '%s\n' "$body" | fingerprint)" || exit 2
    clean="$(printf '%s\n' "$verdict" | strip_stamp)"
    # Each moved to the top in turn, so they end up verdict, required changes, alternatives.
    for r in gate-alternatives gate-required-changes; do
      c="$(region "$r")" || { echo "gate-status: could not read $r of issue #$ISSUE" >&2; exit 2; }
      [ -z "$c" ] && continue
      write_retry "$r" "$(printf '%s\n' "$c" | strip_stamp)" top || {
        echo "gate-status: could not move $r of issue #$ISSUE" >&2; exit 1; }
    done
    write_retry gate-verdict "$clean" top || { echo "gate-status: could not move gate-verdict of issue #$ISSUE" >&2; exit 1; }
    fp="$(body_of | fingerprint)" || { echo "gate-status: could not re-read issue #$ISSUE" >&2; exit 1; }
    [ "$fp" = "$FP0" ] || { echo "gate-status: issue #$ISSUE: an author section changed during the stamp; leaving the verdict unrecorded" >&2; exit 1; }
    url="$(forge_issue_comments "$ISSUE" 2>/dev/null | jq -r --arg h "## Ticket Readiness Review - #$ISSUE" \
      '[.[]? | select(((.body // "") | split("\n")[0] | rtrimstr("\r")) == $h)] | last | .html_url // empty' 2>/dev/null)"
    write_retry gate-verdict "$clean
Judged body: $fp. Full review: ${url:-no review comment found}." || {
      echo "gate-status: could not stamp issue #$ISSUE" >&2; exit 1; }
    exit 0 ;;

  --mark-stale)
    st="$(state_of)" || { echo "gate-status: could not hash issue #$ISSUE" >&2; exit 2; }
    case "$st" in stale*) ;; *) exit 0 ;; esac
    mark() {  # mark <region> <content>: heading gets ": STALE"; the verdict also gets the Stale line
      local out rc=0
      printf '%s\n' "$2" | sed -n '/^### /{p;q;}' | grep -q ': STALE[[:space:]]*$' && return 0
      out="$(printf '%s\n' "$2" | GS_ADD="$3" awk '
        BEGIN { first = 1; add = ENVIRON["GS_ADD"] }
        /^### / && first { first = 0; sub(/[ \t]+$/, ""); print $0 ": STALE"; if (add != "") print add; next }
        { print }')"
      forge_body_region_set "$ISSUE" gate "$1" "$out" || rc=$?
      case "$rc" in
        0) return 0 ;;
        102|103) echo "gate-status: issue #$ISSUE: $1 not marked (rc $rc); the next edit checks again" >&2; return 0 ;;
        *) echo "gate-status: could not mark $1 of issue #$ISSUE (rc $rc)" >&2; return 1 ;;
      esac
    }
    fail=0
    mark gate-verdict "$verdict" "**Stale:** the sections outside this block changed after this verdict; re-run /gate-ticket $ISSUE before acting on it." || fail=1
    req="$(region gate-required-changes)" || exit 2
    [ -z "$req" ] || mark gate-required-changes "$req" "" || fail=1
    exit "$fail" ;;
esac
