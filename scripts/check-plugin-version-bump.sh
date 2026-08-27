#!/usr/bin/env bash
# Fail if a plugin GROUP changed without bumping its plugin.json semver (issue #79). The
# plugin.json version is the unit-of-install version the marketplace reads for updates;
# component <name>-version markers are enforced separately by check-version-bump.sh, and
# PRs #74/#75 proved the two can silently diverge (five marker bumps across three groups,
# zero plugin bumps, nothing flagged it).
#
# ONE implementation, two surfaces (the review of PR #82 found the hand-copied hook
# section diverging from this script on day one):
#   check-plugin-version-bump.sh <base-ref>   range mode: <base>...HEAD (CI)
#   check-plugin-version-bump.sh --staged     index-vs-HEAD mode (.githooks/pre-commit)
#
# Contract, shared with check-version-bump.sh: committed blobs via `git show` (range mode
# never reads the worktree), fail CLOSED on a missing base ref. Diffs run with
# --no-renames: rename detection folds the source file's D into an R that names only the
# destination, which would exempt the SOURCE group from its bump; with renames split back
# into A+D, both groups count. Filter ADM: a deleted component is meaningless to the
# per-file marker guard but is a change to its group. Deleting a whole group is allowed
# (nothing left to bump). Group detection requires a real directory segment
# (`plugins/<group>/...`); a loose file directly under plugins/ is not a group and is
# ignored by design. Requires jq (exits 2 loudly if absent, never a silent pass).
set -uo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "check-plugin-version-bump: jq is required and not installed." >&2; exit 2; }

SEMVER='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'

# _semver_gt <new> <old>: succeed iff new > old. Release cores compare via sort -V; equal
# cores follow semver precedence where the bare release outranks any of its pre-releases
# (sort -V alone gets that backward: it puts 0.2.0-rc1 AFTER 0.2.0). Two pre-releases of
# one core fall back to sort -V, adequate for rc1/rc2-style tags. Build metadata (+) is
# treated like a pre-release rather than ignored: stricter than pure semver, never looser.
_semver_gt() {
  local new="$1" old="$2" ncore ocore
  [ "$new" = "$old" ] && return 1
  ncore="${new%%[-+]*}"; ocore="${old%%[-+]*}"
  if [ "$ncore" = "$ocore" ]; then
    [ "$new" = "$ncore" ] && return 0          # new is the bare release: outranks pre-releases
    [ "$old" = "$ocore" ] && return 1          # old is the bare release: new pre-release is below it
    [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -1)" = "$new" ]
  else
    [ "$(printf '%s\n%s\n' "$ocore" "$ncore" | sort -V | tail -1)" = "$ncore" ]
  fi
}

if [ "${1:-}" = "--staged" ]; then
  changed=$(git diff --cached --name-only --no-renames --diff-filter=ADM)
  show_new()     { git show ":$1" 2>/dev/null; }
  show_old()     { git show "HEAD:$1" 2>/dev/null; }
  old_exists()   { git cat-file -e "HEAD:$1" 2>/dev/null; }
  group_alive()  { git ls-files -- "$1" | grep -q .; }   # index state = post-commit truth
  label="staged"
else
  base="${1:-origin/main}"
  if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
    echo "check-plugin-version-bump: base ref '$base' not found; cannot verify plugin bumps." >&2
    exit 1
  fi
  changed=$(git diff --name-only --no-renames --diff-filter=ADM "$base"...HEAD)
  show_new()     { git show "HEAD:$1" 2>/dev/null; }
  show_old()     { git show "$base:$1" 2>/dev/null; }
  old_exists()   { git cat-file -e "$base:$1" 2>/dev/null; }
  group_alive()  { git ls-tree -d --name-only HEAD "$1" 2>/dev/null | grep -q .; }
  label="vs $base"
fi

groups=$(printf '%s\n' "$changed" | grep -oE '^plugins/[^/]+/' | sed 's:/$::' | sort -u || true)
[ -z "$groups" ] && { echo "no plugin group changes ($label)"; exit 0; }

violations=0
while IFS= read -r g; do
  [ -n "$g" ] || continue
  pj="$g/.claude-plugin/plugin.json"
  new=$(show_new "$pj" | jq -r '.version // empty' 2>/dev/null)
  if [ -z "$new" ]; then
    # No readable version on the new side: fine only when the whole group is gone.
    if group_alive "$g"; then
      echo "  ✗ $g: missing or unreadable $pj"; violations=$((violations + 1))
    fi
    continue
  fi
  if ! printf '%s\n' "$new" | grep -qE "$SEMVER"; then
    echo "  ✗ $g: plugin.json version '$new' is not semver"; violations=$((violations + 1))
    continue
  fi
  if old_exists "$pj"; then
    old=$(show_old "$pj" | jq -r '.version // empty' 2>/dev/null)
    # An unreadable OLD version cannot be compared; validate-plugins.sh owns current-tree
    # structure, so only the comparison is skipped, never the semver check above.
    if [ -n "$old" ]; then
      if [ "$new" = "$old" ]; then
        echo "  ✗ $g: files changed but plugin.json still v$new (bump the semver)"
        violations=$((violations + 1))
      elif ! _semver_gt "$new" "$old"; then
        echo "  ✗ $g: plugin.json went BACKWARD ($old -> $new)"
        violations=$((violations + 1))
      fi
    fi
  fi
  # No plugin.json on the old side = a new group; validate-plugins.sh owns its structure.
done <<< "$groups"

if [ "$violations" -gt 0 ]; then
  echo ""; echo "forge-kit: $violations plugin group(s) need a plugin.json version bump."; exit 1
fi
echo "all changed plugin groups bumped plugin.json"
