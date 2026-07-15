#!/usr/bin/env bash
# Assert every work issue-template shares one template-version marker (lockstep).
#
# Divergence is exactly what makes ticket-gate's version check mis-fire across ticket
# types (it reads one template's version and compares every ticket against it), so this
# is the mechanical anti-drift lock. Templates that carry no marker (e.g. contribution.yml)
# are exempt by design.
#
# Usage: check-template-lockstep.sh [ISSUE_TEMPLATE_DIR]
#   With no argument, resolves the first existing of
#   .forgejo/ISSUE_TEMPLATE, .gitea/ISSUE_TEMPLATE, .github/ISSUE_TEMPLATE (host-aware).
set -uo pipefail

# Resolve relative default dirs against the repo root, but honour an explicit dir arg
# (which the tests pass as an absolute path) as-is.
if [ "$#" -eq 0 ]; then
  cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
fi

resolve_dir() {
  local d
  for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE; do
    [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

DIR="${1:-$(resolve_dir || true)}"
if [ -z "${DIR:-}" ] || [ ! -d "$DIR" ]; then
  echo "check-template-lockstep: no ISSUE_TEMPLATE directory found; nothing to check."
  exit 0
fi

# First template-version marker per file (positional-first, matching the ver_of discipline
# the other guards use: the marker is the first template-version string in the file).
tver() { grep -oP 'template-version: \K\d+' "$1" | head -1; }

declare -A versions=()
seen=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  v=$(tver "$f")
  [ -n "$v" ] || continue          # no marker -> exempt (e.g. contribution.yml)
  versions["$f"]=$v
  seen=$((seen + 1))
done < <(find "$DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "$seen" -lt 2 ]; then
  echo "check-template-lockstep: fewer than 2 versioned templates in $DIR; nothing to lock."
  exit 0
fi

uniq_vers=$(printf '%s\n' "${versions[@]}" | sort -un)
if [ "$(printf '%s\n' "$uniq_vers" | wc -l)" -eq 1 ]; then
  echo "check-template-lockstep: all $seen templates in $DIR at template-version $uniq_vers."
  exit 0
fi

echo "check-template-lockstep: template-version DRIFT in $DIR (expected one shared version):"
while IFS= read -r f; do
  echo "  v${versions[$f]}  $f"
done < <(printf '%s\n' "${!versions[@]}" | sort)
echo ""
echo "All work templates must share one template-version. Bump the laggards to match."
exit 1
