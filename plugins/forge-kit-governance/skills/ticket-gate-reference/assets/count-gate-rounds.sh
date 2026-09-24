#!/usr/bin/env bash
# count-gate-rounds-version: 2
# count-gate-rounds.sh <issue-number> [--body FILE]
# count-gate-rounds.sh <issue-number> --memory [--body FILE]
#
# Default mode prints the round number THIS gate run should use: the number of review comments
# already posted on the issue, plus one. Exit 0 on an answer; exit 2 when the count cannot run,
# printing NOTHING on stdout, because a count that cannot run must never look like round 1.
#
# WHY COMMENTS AND NOT THE BODY (#192). The gate writes a `gate-verdict` region into the issue body
# carrying the round number, and an ordinary body edit erases it: the author rewriting a ticket in
# response to the review, or Step 0c rewriting it to synthesise sections, both by design. The gate
# then read a body with no region and concluded it had never run. That is not slow-but-harmless:
# the delta rows of the round table never engage, and a caller's trip wire, which stops a loop when
# two consecutive rounds find defects in the previous fix, cannot fire if the loop cannot count. A
# stopping rule that cannot fire is worse than one that is absent, because it is believed in.
#
# A posted review comment survives a body edit, so the comments are the source and the body block
# is a PROJECTION of the count. With --body, a block that disagrees is reported on stderr and
# ignored; the answer never changes. A deleted review comment therefore lowers the count, and a
# 0c-voided round still counts, since its comment was posted: the trip wire counts rounds run,
# not verdicts kept.
#
# WHAT COUNTS. A comment whose FIRST line is `## Ticket Readiness Review - #<N>` for THIS issue
# number, exactly. A synthesis-void or clarification comment has a different first line; a
# remediation note quoting the heading carries it on a later line; a review pasted from a sibling
# ticket names a different number. None of those is a round.
#
# It never prints an author. The listing carries `user.login` beside every body, and a failing
# hook's stderr is exactly the text that gets pasted into the next ticket.
#
# --MEMORY MODE (#196). Restores the prior blocking items from the LATEST such comment, when the
# gate's own `gate-required-changes` body region is absent (an erasure #192 above already explains).
# The gate is the sole author of that comment, so it wraps the checklist in a `gate-items` marker
# pair rather than parsing its own prose; Step 6 emits the empty pair on a PASS round. The scan is
# NOT fence-aware: it matches the marker lines themselves wherever they occur in the comment,
# including inside a fenced block that merely quotes one as example text, because no regex over a
# posted comment can tell a line that delimits from a line that is quoted. That is why a comment
# carrying two `gate-items:start` lines, real or quoted, is refused rather than guessed at.
#
# | exit | stdout            | meaning                                          |
# |------|-------------------|---------------------------------------------------|
# | 0    | one item per line | memory restored                                  |
# | 0    | nothing           | the latest review was a PASS (empty marker pair) |
# | 3    | nothing           | no machine-readable list found                   |
# | 3    | nothing           | more than one `gate-items` start marker (malformed) |
# | 2    | nothing           | could not run (transport), unchanged             |
#
# THE ISSUE NUMBER MUST COME FIRST (`--help`/`-h` excepted). This is what lets an unrecognised
# option, including a stale caller passing `--memory` before the issue number, fail the same way a
# stale v1 script answering `<N> --memory` already fails: exit 2, empty stdout, usage on stderr.
# Reversed, `--memory <N>` against a stale v1 copy exits 0 and prints a round number, which the
# memory contract would misread as one restored item. Every caller today, `ticket-gate.md:193` and
# this suite, already puts the issue number first.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

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
listing="$(forge_issue_comments "$ISSUE")" || {
  echo "count-gate-rounds: forge_issue_comments $ISSUE failed; the round cannot be counted." >&2
  exit 2
}

if [ "$MEMORY" = 1 ]; then
  latest="$(printf '%s' "$listing" | jq -r --arg h "## Ticket Readiness Review - #$ISSUE" \
    '[.[]? | select(((.body // "") | split("\n")[0] | rtrimstr("\r")) == $h)] | last | .body // ""' 2>/dev/null)"
  [ $? -eq 0 ] || { echo "count-gate-rounds: forge_issue_comments $ISSUE returned something that is not a comment list." >&2; exit 2; }

  if [ -z "$latest" ]; then
    echo "count-gate-rounds: no '## Ticket Readiness Review - #$ISSUE' comment found; no review to restore memory from" >&2
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

count="$(printf '%s' "$listing" | jq -r --arg h "## Ticket Readiness Review - #$ISSUE" \
  '[.[]? | select(((.body // "") | split("\n")[0] | rtrimstr("\r")) == $h)] | length' 2>/dev/null)"
case "$count" in
  ''|*[!0-9]*) echo "count-gate-rounds: forge_issue_comments $ISSUE returned something that is not a comment list." >&2; exit 2 ;;
esac

if [ -n "$BODY" ] && [ -f "$BODY" ]; then
  said="$(grep -m1 -o '^### Gate verdict (round [0-9][0-9]*)' "$BODY" 2>/dev/null | grep -o '[0-9]*' || true)"
  if [ -n "$said" ] && [ "$said" -ne "$count" ]; then
    echo "count-gate-rounds: body block says round $said, comments say $count; the comments win." >&2
  fi
fi

echo $((count + 1))
