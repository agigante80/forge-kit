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
# ONE EXEMPTION, and it is the narrowest possible: a line that also contains `sed` is the
# substitution command itself, the one command whose whole purpose is to name the placeholder. Any
# other command mentioning it still fails.
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

status=0
while IFS= read -r f; do
  awk -v F="${f#"$ROOT"/}" '
    /^[[:space:]]*```/ { fenced = !fenced; next }
    fenced && /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/ {
      # The substitution command is the one legitimate live use.
      if ($0 ~ /sed/) next
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
  n=$(find "$ROOT" -regextype posix-extended -regex "$COMPONENT_RE" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "check-live-placeholders: $n component(s), no install-time placeholders in commands."
fi
exit "$status"
