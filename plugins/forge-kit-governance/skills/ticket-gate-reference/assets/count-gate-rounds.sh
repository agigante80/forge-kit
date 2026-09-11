#!/usr/bin/env bash
# count-gate-rounds-version: 1
# count-gate-rounds.sh <issue-number> [--body FILE]
#
# Prints the round number THIS gate run should use: the number of review comments already posted
# on the issue, plus one. Exit 0 on an answer; exit 2 when the count cannot run, printing NOTHING
# on stdout, because a count that cannot run must never look like round 1.
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

ISSUE=""; BODY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; [ $# -gt 0 ] || { echo "count-gate-rounds: --body needs a path" >&2; exit 2; }; BODY="$1" ;;
    --help|-h) awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) ISSUE="$1" ;;
  esac
  shift
done
case "$ISSUE" in
  ''|*[!0-9]*) echo "count-gate-rounds: usage: count-gate-rounds.sh <issue-number> [--body FILE]" >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "count-gate-rounds: jq is required" >&2; exit 2; }

# shellcheck source=/dev/null
. "$LIB"

# Only the exit code and the count leave this block. The transport's own stderr is let through
# (it names the failure), but nothing from the payload is echoed.
listing="$(forge_issue_comments "$ISSUE")" || {
  echo "count-gate-rounds: forge_issue_comments $ISSUE failed; the round cannot be counted." >&2
  exit 2
}
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
