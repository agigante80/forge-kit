#!/usr/bin/env bash
# check-live-placeholders.sh: no component may carry an install-time placeholder in a command (#163).
#
# WHY IT MATTERS. A component that resolves what it needs at RUNTIME is correct in every project and
# can be installed once, by enabling its plugin group. A component with a value baked in at INSTALL
# time is pinned to one project and forces a per-project copy, which is the copy-and-mutate path
# CLAUDE.md already calls the origin of every hook bug in this repo's history.
#
# The kit had exactly one such placeholder, `{{GITHUB_REPO}}`, with six live uses across two files,
# while `forge_repo` already derived owner/repo from the git remote at runtime elsewhere in those
# same files. This guard is what stops a seventh appearing.
#
# PROSE IS ALLOWED, AND THAT IS THE WHOLE DIFFICULTY. The manual-install path has to be
# documentable, and a guard forbidding the explanation would forbid the reason. So the rule is
# positional: a placeholder inside a FENCED CODE BLOCK is a command and is refused; one in prose,
# including an inline code span, is documentation and is fine.
#
# ONE EXEMPTION, and it is the narrowest possible: a line whose command IS `sed`, the one command
# whose whole purpose is to name the placeholder. Word-anchored, because an unanchored match
# exempted any line containing "used", "based", "parsed" or "closed" (review round 1).
#
# NO SCOPE EXEMPTS A COMPONENT. Round 1 of review added one for `scope: project`, reasoning that a
# component declared as needing a per-project rewrite could carry a placeholder. Round 2 found the
# hole under it: since #163 there IS no substitution machinery, and forge-adapt-install-plan.sh
# emits `copy` without substituting anything, so the exemption produced a component installed with a
# live, unsubstituted placeholder. The remedy was wrong, not the rule.
#
# Scanned over the marker-enforced path set, one directory deep, because that is what a component
# IS in this repo (see the enforced path set in CLAUDE.md). Nested reference files are not
# components and are not scanned.
set -uo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  TOP="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-live-placeholders: not a git checkout and no root given" >&2; exit 2; }
  ROOT="$TOP/plugins"
fi
[ -d "$ROOT" ] || { echo "check-live-placeholders: '$ROOT' is not a directory" >&2; exit 2; }

COMPONENT_RE='.*/plugins/[^/]+/(agents|commands)/[^/]+\.md|.*/plugins/[^/]+/skills/[^/]+/SKILL\.md'

# shellcheck source=guard-lib.sh
. "$(dirname "$0")/guard-lib.sh"

status=0
seen=0
while IFS= read -r f; do
  seen=$((seen + 1))
  awk -v F="${f#"$ROOT"/}" '
    /^[[:space:]]*```/ { fenced = !fenced; next }
    fenced && /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/ {
      # The substitution command is the one legitimate live use. Word-anchored: an unanchored
      # match exempted "used", "based", "parsed" and "closed" (review round 1).
      if ($0 ~ /(^|[^A-Za-z0-9_])sed[[:space:]]/) next
      match($0, /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/)
      printf("%s:%d: live placeholder %s inside a command\n", F, NR, substr($0, RSTART, RLENGTH))
      hits = 1
    }
    END {
      # An unclosed fence would put every following line "inside" a block and turn prose into
      # violations. Refused rather than guessed at, which is also the honest answer: the file
      # cannot be classified.
      if (fenced) { printf("%s: unclosed code fence; cannot tell command from prose\n", F); exit 2 }
      exit hits ? 1 : 0
    }' "$f"
  rc=$?
  [ "$rc" -eq 2 ] && { status=2; continue; }
  [ "$rc" -eq 1 ] && [ "$status" -eq 0 ] && status=1
done < <(find "$ROOT" -regextype posix-extended -regex "$COMPONENT_RE" -type f 2>/dev/null | sort)

# Finding nothing is not the same as finding nothing wrong. A broken root or a COMPONENT_RE
# regression would otherwise report success, which is the vacuous pass check-template-dir-order.sh
# already refuses.
if [ "$seen" -eq 0 ]; then
  echo "check-live-placeholders: no components found under $ROOT. Nothing was checked." >&2
  exit 2
fi

if [ "$status" -eq 1 ]; then
  echo ""
  echo "check-live-placeholders: a component carries an install-time placeholder in a command."
  echo "Resolve it at runtime instead (forge_repo derives owner/repo from the git remote), so the"
  echo "component is correct in every project and can be installed once rather than copied."
  echo "A placeholder in PROSE is fine; this is only about commands."
elif [ "$status" -eq 2 ]; then
  echo ""
  echo "check-live-placeholders: a file could not be classified (see above). Nothing was checked in it."
else
  # $seen, not a fresh count: a recount would claim a clean result for files the scan skipped.
  echo "check-live-placeholders: $seen component(s), no install-time placeholders in commands."
fi
exit "$status"
