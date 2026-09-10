#!/usr/bin/env bash
# What forge-adapt should do with one component, given what the user already has installed (#179).
#
#   forge-adapt-neighbour-disposition.sh <component-name> [--installed FILE]
#
# Prints ONE tab-separated line, which forge-adapt prints back to the user:
#   recommend<TAB><reason or empty>
#   caveat<TAB><what the user should know before choosing>
#   suppress<TAB><why forge-kit defers, naming what owns it instead>
#
# Exit 0 when it decided. It does not fail: an absent record is an absent neighbour, not an error.
#
# WHY A SCRIPT. #72 put the superpowers half in adapt/SKILL.md as prose, and that file has been on
# a size ratchet since #150, so the second half could not go there. The #149 lever applies for the
# usual second reason too: a rule in prose cannot be tested, and this one decides what a user is
# told they already have.
#
# THE BOUNDARY IT IMPLEMENTS. Decision #69: superpowers owns the INNER loop (how work happens),
# forge-kit the OUTER (what must be true before and after). Where the two touch, forge-kit gives
# way. The neighbour marketplaces are different: they ship TOOLS rather than a process, so a
# counterpart there is usually a `caveat` (you have two, here is the difference) rather than a
# `suppress`.
#
# NAME MATCHING IS NOT ENOUGH, and this is the mistake #177 already refused to make. `code-reviewer`
# exists on three sides as three genuinely different agents. Suppressing ours because a name matches
# would hand the user less than they had. Every row below is a judgement about the pair, not about
# the string.
#
# WHAT IT CANNOT SEE. The install record can be project-scoped to another repository, disabled in
# settings, or stale after an uninstall. forge-adapt's own rule stands and is stated in the skill:
# the in-session skills and agents listing is AUTHORITATIVE IN BOTH DIRECTIONS where it is visible,
# and this record is the fallback proxy for a session that has no listing.
set -uo pipefail

INSTALLED="${HOME}/.claude/plugins/installed_plugins.json"
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --installed) INSTALLED="$2"; shift 2 ;;
    -*) echo "forge-adapt-neighbour-disposition: unknown option '$1'" >&2; exit 2 ;;
    *) NAME="$1"; shift ;;
  esac
done
[ -n "$NAME" ] || { echo "forge-adapt-neighbour-disposition: a component name is required" >&2; exit 2; }

# A missing or unreadable record means no neighbours, not a broken run. That file is written by
# another tool and this kit does not own its schema, so a parse failure must never take forge-adapt
# down with it.
have() {
  [ -f "$INSTALLED" ] || return 1
  grep -q "\"$1@" "$INSTALLED" 2>/dev/null
}

say() { printf '%s\t%s\n' "$1" "$2"; exit 0; }

case "$NAME" in
  code-simplifier)
    have superpowers && say suppress \
      "superpowers owns the inner loop (#69), and this agent's proactive post-change edits sit OUTSIDE the review loop's bad-fix accounting. Install it only if you ask for it knowingly."
    have code-simplifier && say caveat \
      "code-simplifier@claude-plugins-official ships an agent of the same name and a different design. You would carry both."
    ;;
  closing-sessions)
    have superpowers && say caveat \
      "Recommended alongside superpowers, with the split stated: the project memory store is the shareable canon, the private journal is the personal layer. Do not write the same note into both."
    ;;
  code-reviewer)
    have superpowers && say caveat \
      "Recommended alongside superpowers, which prefers a fresh subagent with crafted context over session history. Adapt the dispatch shape to match."
    have pr-review-toolkit && say caveat \
      "pr-review-toolkit@claude-plugins-official ships a different code-reviewer. Ours runs under the bounded iteration contract; theirs is a PR-time toolkit. Pick one per task rather than running both."
    have feature-dev && say caveat \
      "feature-dev@claude-plugins-official ships a code-reviewer too, 199 lines apart from ours. You would carry both."
    ;;
  architect-review)
    have superpowers && say caveat \
      "Recommended alongside superpowers, using its dispatch shape: a fresh subagent with crafted context, never session history."
    ;;
  security-auditor)
    have claude-security && say caveat \
      "claude-security@claude-plugins-official is a multi-agent scanner and a different tool from this lens. Ours is what ticket-gate dispatches on a security label; keep it if you use the gate."
    ;;
  full-review)
    have comprehensive-review && say caveat \
      "comprehensive-review@claude-code-workflows shares an ancestor with this command. Ours added the bounded ITERATION CONTRACT (round accounting, the trip wire, bad-fix injection) which theirs has none of. That is the reason to keep ours."
    ;;
  mutation-sweep|ticket-gate|gate-ticket|working-overnight|decision-brief|leak-guard|privacy-regime|roadmap-phases|phase|release|release-automation|forge-host|github-to-forgejo|dep-auditor|health-check|ci-health|find-dead-code|adapt|coding-standards-auditor|api-security-tester|owasp-api-security|ticket-gate-reference)
    say recommend "Outer loop: no neighbour ships a counterpart."
    ;;
esac

say recommend ""
