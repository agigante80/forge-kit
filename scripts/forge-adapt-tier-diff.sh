#!/usr/bin/env bash
# forge-adapt-tier-diff.sh: which tier keys an installed copy holds differently from forge-kit (#281).
#
#   forge-adapt-tier-diff.sh <installed> <catalogue>
#
# A copied component is rewritten by a model for its project, and the only guard on that rewrite is
# the version marker, which says nothing about the tier. So `refresh <name>` could not tell a
# project that runs a role cheaper on purpose from one whose rewrite quietly dropped `model: opus`
# from a security agent. This prints each difference, one line per key, in the fixed order below:
#
#   tier: <key> local=<value> forge-kit=<value> (kept)
#
# An absent key reads `-`. Equal keys print nothing. `(kept)` is the policy, not a question: a tier
# is a decision, the project's copy keeps its own, and refresh reports the upstream value beside it
# rather than merging it. It reads files, not agents, so skills and commands are covered too, which
# forge-adapt-agent-skills.sh never sees.
#
# FRONTMATTER ONLY, through guard-lib.sh's component_frontmatter_field: line 1 must be exactly `---`
# and a closing `---` must follow, so a `model:` in a body example is never read as the tier.
# Exit 0 whether or not it printed anything; exit 2 with NOTHING on stdout when either file is
# unreadable or has no frontmatter, so a caller copying stdout into a report never copies an error.
set -uo pipefail

# The key set is #253's. One array, so narrowing it is a one-line change the suite's order case sees.
TIER_KEYS=(model effort context agent background)

. "$(dirname "$0")/guard-lib.sh"

[ $# -eq 2 ] || { echo "usage: forge-adapt-tier-diff.sh <installed> <catalogue>" >&2; exit 2; }

for f in "$1" "$2"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "forge-adapt-tier-diff: cannot read $f" >&2; exit 2; }
  awk 'NR==1 && $0 != "---" { exit 1 } NR>1 && $0 == "---" { closed = 1; exit }
       END { exit !closed }' "$f" \
    || { echo "forge-adapt-tier-diff: $f has no frontmatter" >&2; exit 2; }
done

for k in "${TIER_KEYS[@]}"; do
  a=$(component_frontmatter_field "$1" "$k"); b=$(component_frontmatter_field "$2" "$k")
  [ "$a" = "$b" ] || echo "tier: $k local=${a:--} forge-kit=${b:--} (kept)"
done
exit 0
