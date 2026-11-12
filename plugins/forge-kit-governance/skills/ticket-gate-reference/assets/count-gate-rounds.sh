#!/usr/bin/env bash
# count-gate-rounds-version: 4
# count-gate-rounds.sh <issue-number> [--body FILE]
# count-gate-rounds.sh <issue-number> --memory [--body FILE]
#
# Default mode prints the round number THIS gate run should use: the rounds already run, plus one.
# Exit 0 on an answer; exit 2 when the count cannot run, printing NOTHING on stdout, because a
# count that cannot run must never look like round 1.
#
# WHERE THE COUNT COMES FROM (v4, #581). The gate posts NO comment: its review lives in the body,
# in the gate-owned `gate-verdict` and `gate-review` regions, replaced every round (the previous
# round is in the forge's edit history). Each region's heading carries the round it was written
# in, `### Gate verdict (round N)` / `### Gate review (round N)`, and that heading is the primary
# source: rounds run = the highest N found inside those two regions. A second source covers every
# ticket gated BEFORE this change, whose reviews are comments: the number of comments whose FIRST
# line is `## Ticket Readiness Review - #<ISSUE>` for THIS issue, exactly (a synthesis-void or
# clarification comment, a quoted heading on a later line and a sibling ticket's review are not
# rounds). Rounds run = the MAX of the two, so a migrated ticket needs no conversion. A voided
# round (Step 0c) still counts: the same run writes its verdict. A clarification stop (Step 1.5)
# carries no round heading and so is not a round.
#
# WHY NOT ONLY THE BODY. #192 moved the count out of the body because an ordinary body edit
# (the author answering the review, Step 0c rewriting the ticket) can erase the region, and a count
# that restarts at 1 never reaches a caller's trip wire. #581 moved it back because the maintainer
# ruled that nothing of the gate may live in a comment. The residual case, stated honestly: an
# author who deletes the gate regions of a ticket that has NO legacy review comments resets the
# count to round 1, and nothing in the forge's data can tell this script otherwise. It is not
# silent: when the body still carries a gate trace (a `Judged body:` stamp, or a gate-verdict,
# gate-required-changes or gate-alternatives region) but no round heading, and no legacy comment
# backs a count, one stderr line says the count may have been reset. The trace test costs nothing
# and the warning is advisory, the answer does not change. The scan reads the region lines
# themselves and is not fence-aware, so never quote a gate region marker as example text.
#
# --body FILE is the body the gate already fetched; without it the body is read with
# forge_issue_view. A body that cannot be read exits 2, like a comment listing that cannot.
#
# It never prints an author. The listing carries `user.login` beside every body, and a failing
# hook's stderr is exactly the text that gets pasted into the next ticket.
#
# --MEMORY MODE (#196, #581). Restores the prior blocking items, body first:
#   1. the body's `gate-required-changes` region: its unchecked `- [ ] ` lines. (The old
#      `gate-items` marker pair cannot live in a body region: markers do not nest, and the
#      fingerprint refuses a body that nests them.)
#   2. else a body whose `gate-verdict` region says `**Verdict:** PASS`: nothing to carry forward.
#   3. else the LATEST legacy review comment, as before: the gate wrapped its checklist in a
#      `gate-items` marker pair. That scan is NOT fence-aware: it matches the marker lines wherever
#      they occur, including inside a fenced block that quotes one, because no regex over a posted
#      comment can tell a line that delimits from a line that is quoted; two start lines are
#      refused rather than guessed at.
#
# | exit | stdout            | meaning                                          |
# |------|-------------------|---------------------------------------------------|
# | 0    | one item per line | memory restored                                  |
# | 0    | nothing           | the latest review was a PASS                     |
# | 3    | nothing           | no machine-readable list found                   |
# | 3    | nothing           | more than one `gate-items` start marker in a legacy comment (malformed) |
# | 2    | nothing           | could not run (transport), unchanged             |
#
# THE ISSUE NUMBER MUST COME FIRST (`--help`/`-h` excepted). This is what lets an unrecognised
# option, including a stale caller passing `--memory` before the issue number, fail the same way a
# stale v1 script answering `<N> --memory` already fails: exit 2, empty stdout, usage on stderr.
# Reversed, `--memory <N>` against a stale v1 copy exits 0 and prints a round number, which the
# memory contract would misread as one restored item. Every caller today, `ticket-gate.md:193` and
# this suite, already puts the issue number first.
set -uo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

# forge-lib.sh beside this script is the forge-adapt install shape; the fallback reaches across
# plugin groups, which is the shape of a source checkout. Absent both, REFUSE.
LIB="${FORGE_LIB:-}"
if [ -z "$LIB" ]; then
  if [ -f "$HERE/forge-lib.sh" ]; then LIB="$HERE/forge-lib.sh"
  elif [ -f "$HERE/../../../../forge-kit-devops/skills/forge-host/assets/forge-lib.sh" ]; then
    LIB="$HERE/../../../../forge-kit-devops/skills/forge-host/assets/forge-lib.sh"
  fi
fi
[ -n "$LIB" ] && [ -f "$LIB" ] || {
  echo "count-gate-rounds: forge-lib.sh not found beside this script (or via FORGE_LIB)." >&2
  echo "  It is the forge transport, so the comments cannot be listed. Refusing rather than" >&2
  echo "  reporting round 1." >&2
  exit 2
}

usage() { echo "count-gate-rounds: usage: count-gate-rounds.sh <issue-number> [--memory] [--body FILE]" >&2; }
print_help() { awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

ISSUE=""; BODY=""; MEMORY=0

if [ $# -eq 0 ]; then usage; exit 2; fi
case "$1" in
  --help|-h) print_help; exit 0 ;;
  ''|*[!0-9]*) usage; exit 2 ;;
  *) ISSUE="$1"; shift ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --memory) MEMORY=1 ;;
    --body) shift; [ $# -gt 0 ] || { echo "count-gate-rounds: --body needs a path" >&2; exit 2; }; BODY="$1" ;;
    --help|-h) print_help; exit 0 ;;
    -*) echo "count-gate-rounds: unrecognised option '$1'" >&2; usage; exit 2 ;;
    *) echo "count-gate-rounds: unexpected argument '$1'" >&2; usage; exit 2 ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || { echo "count-gate-rounds: jq is required" >&2; exit 2; }

# shellcheck source=/dev/null
. "$LIB"

# Only the exit code and the payload leave this block. The transport's own stderr is let through
# (it names the failure), but nothing from the comment payload is echoed except what the two modes
# below deliberately print.
# The body: --body FILE when the caller has already fetched it, else the forge. A stub library
# without forge_issue_view yields an empty body, which is the pre-#581 behaviour.
if [ -n "$BODY" ] && [ -f "$BODY" ]; then
  bodytext="$(cat -- "$BODY")"
elif declare -F forge_issue_view >/dev/null 2>&1; then
  raw="$(forge_issue_view "$ISSUE")" || { echo "count-gate-rounds: forge_issue_view $ISSUE failed; the round cannot be counted." >&2; exit 2; }
  bodytext="$(printf '%s' "$raw" | jq -er '.body // ""' 2>/dev/null)" || { echo "count-gate-rounds: forge_issue_view $ISSUE returned something that is not an issue." >&2; exit 2; }
else
  bodytext=""
fi

# region_of <name>: the lines between `<!-- <name>:start -->` and `<!-- <name>:end -->`, CR and
# trailing blanks tolerated on the marker lines (forge-lib's grammar). Not fence-aware, see above.
region_of() {
  printf '%s\n' "$bodytext" | awk -v r="$1" '
    function norm(l) { sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); return l }
    BEGIN { s = "<!-- " r ":start -->"; e = "<!-- " r ":end -->" }
    { n = norm($0) }
    n == s { inside = 1; next }
    n == e { inside = 0; next }
    inside { print n }'
}
has_region() { [ "$(printf '%s\n' "$bodytext" | tr -d '\r' | grep -c "^<!-- $1:start -->[[:space:]]*\$")" -gt 0 ]; }

listing="$(forge_issue_comments "$ISSUE")" || {
  echo "count-gate-rounds: forge_issue_comments $ISSUE failed; the round cannot be counted." >&2
  exit 2
}
H="## Ticket Readiness Review - #$ISSUE"

if [ "$MEMORY" = 1 ]; then
  if has_region gate-required-changes; then
    region_of gate-required-changes | sed -n 's/^- \[ \] //p'
    exit 0
  fi
  if [ "$(region_of gate-verdict | grep -c '^\*\*Verdict:\*\* *PASS')" -gt 0 ]; then
    echo "count-gate-rounds: the body's latest verdict is a PASS; nothing to carry forward" >&2
    exit 0
  fi

  latest="$(printf '%s' "$listing" | jq -r --arg h "$H" \
    '[.[]? | select(((.body // "") | split("\n")[0] | rtrimstr("\r")) == $h)] | last | .body // ""' 2>/dev/null)"
  [ $? -eq 0 ] || { echo "count-gate-rounds: forge_issue_comments $ISSUE returned something that is not a comment list." >&2; exit 2; }

  if [ -z "$latest" ]; then
    echo "count-gate-rounds: no gate-required-changes region in the body and no '$H' comment; no review to restore memory from" >&2
    exit 3
  fi

  # A norm() local to this script, not forge-lib's, because the shared _FORGE_AWK_MARKER is a
  # private implementation detail of forge-lib.sh and this script's own test stub does not carry
  # it. The grammar (trim CR, trim trailing blanks) is the same one forge-lib's region splicer uses.
  extracted="$(printf '%s\n' "$latest" | awk '
    function norm(l) { sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); return l }
    BEGIN { s = "<!-- gate-items:start -->"; e = "<!-- gate-items:end -->" }
    { n = norm($0)
      if (n == s) { nstart++; si = NR }
      if (n == e) { nend++; ei = NR }
      line[NR] = $0
    }
    END {
      if (nstart == 0 && nend == 0) exit 12
      if (nstart > 1) {
        printf("count-gate-rounds: latest review comment carries %d gate-items start markers (malformed); refusing\n", nstart) > "/dev/stderr"
        exit 13
      }
      if (nend > 1) {
        printf("count-gate-rounds: latest review comment carries %d gate-items end markers (malformed); refusing\n", nend) > "/dev/stderr"
        exit 13
      }
      if (nstart != nend) {
        print "count-gate-rounds: latest review comment carries an unterminated gate-items pair; refusing" > "/dev/stderr"
        exit 13
      }
      if (si > ei) {
        print "count-gate-rounds: latest review comment carries a gate-items pair in reversed order; refusing" > "/dev/stderr"
        exit 13
      }
      for (i = si + 1; i < ei; i++) print line[i]
      exit 0
    }
  ')"
  awk_rc=$?

  case "$awk_rc" in
    12)
      raw_count="$(printf '%s\n' "$latest" | grep -c '^- \[ \] ' || true)"
      echo "count-gate-rounds: latest review comment carries no gate-items marker; saw $raw_count '- [ ] ' line(s) it cannot claim as memory" >&2
      exit 3
      ;;
    13) exit 3 ;;
    0)  ;;
    *)  echo "count-gate-rounds: could not parse the latest review comment" >&2; exit 2 ;;
  esac

  items="$(printf '%s\n' "$extracted" | sed -n 's/^- \[ \] //p')"
  if [ -z "$items" ]; then
    echo "count-gate-rounds: latest review was a PASS; nothing to carry forward" >&2
    exit 0
  fi
  printf '%s\n' "$items"
  exit 0
fi

legacy="$(printf '%s' "$listing" | jq -r --arg h "$H" \
  '[.[]? | select(((.body // "") | split("\n")[0] | rtrimstr("\r")) == $h)] | length' 2>/dev/null)"
case "$legacy" in
  ''|*[!0-9]*) echo "count-gate-rounds: forge_issue_comments $ISSUE returned something that is not a comment list." >&2; exit 2 ;;
esac

# The highest round heading inside the two regions that carry one. A heading outside them (an
# author quoting one) does not count.
marker=0
for r in gate-verdict gate-review; do
  m="$(region_of "$r" | sed -n 's/^### Gate \(verdict\|review\) (round \([0-9][0-9]*\)).*/\2/p' | sort -n | tail -1)"
  [ -n "$m" ] && [ "$((10#$m))" -gt "$marker" ] && marker=$((10#$m))
done

done_rounds=$legacy
[ "$marker" -gt "$done_rounds" ] && done_rounds=$marker

if [ "$done_rounds" -eq 0 ]; then
  trace=0
  [ "$(printf '%s\n' "$bodytext" | grep -c '^Judged body: sha256:')" -gt 0 ] && trace=1
  for r in gate-verdict gate-required-changes gate-alternatives; do
    has_region "$r" && trace=1
  done
  [ "$trace" = 1 ] && echo "count-gate-rounds: the body carries gate output but no round heading and no review comment backs a count; the count may have been reset by an edit that removed the gate regions (reporting round 1)" >&2
fi

echo $((done_rounds + 1))
