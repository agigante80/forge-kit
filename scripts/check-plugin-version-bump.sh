#!/usr/bin/env bash
# Fail if a plugin GROUP changed since <base-ref> without bumping its plugin.json semver
# (issue #79). The plugin.json version is the unit-of-install version the marketplace reads
# for updates; component <name>-version markers are enforced separately by
# check-version-bump.sh, and PRs #74/#75 proved the two can silently diverge (five marker
# bumps across three groups, zero plugin bumps, nothing flagged it).
#
# Same contract family as check-version-bump.sh: reads committed blobs via `git show`, not
# the worktree; fails CLOSED on a missing base ref. Diff filter is ADMR (not AMR): a DELETED
# component is meaningless to the per-file marker guard but is a change to the group and
# warrants a bump here.
# Usage: check-plugin-version-bump.sh <base-ref>   e.g. origin/main
set -uo pipefail
base="${1:-origin/main}"

if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "check-plugin-version-bump: base ref '$base' not found; cannot verify plugin bumps." >&2
  exit 1
fi

groups=$(git diff --name-only --diff-filter=ADMR "$base"...HEAD | grep -oE '^plugins/[^/]+' | sort -u || true)
[ -z "$groups" ] && { echo "no plugin group changes vs $base"; exit 0; }

violations=0
while IFS= read -r g; do
  [ -n "$g" ] || continue
  pj="$g/.claude-plugin/plugin.json"
  new=$(git show "HEAD:$pj" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
  if [ -z "$new" ]; then
    # A group whose plugin.json vanished entirely is a group removal; git show fails for the
    # whole group's files too, so only flag when the group still has files at HEAD.
    if git ls-tree -d --name-only "HEAD" "$g" 2>/dev/null | grep -q .; then
      echo "  ✗ $g: missing or unreadable $pj at HEAD"; violations=$((violations + 1))
    fi
    continue
  fi
  if git cat-file -e "$base:$pj" 2>/dev/null; then
    old=$(git show "$base:$pj" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
    if [ -n "$old" ]; then
      if [ "$new" = "$old" ]; then
        echo "  ✗ $g: files changed but plugin.json still v$new (bump the semver)"
        violations=$((violations + 1))
      else
        hi=$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -1)
        if [ "$hi" != "$new" ]; then
          echo "  ✗ $g: plugin.json went BACKWARD ($old -> $new)"
          violations=$((violations + 1))
        fi
      fi
    fi
  fi
  # No plugin.json at base = a new group; validate-plugins.sh owns its structure/semver.
done <<< "$groups"

if [ "$violations" -gt 0 ]; then
  echo ""; echo "forge-kit: $violations plugin group(s) need a plugin.json version bump."; exit 1
fi
echo "all changed plugin groups bumped plugin.json"
