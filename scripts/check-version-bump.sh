#!/usr/bin/env bash
# Fail if a component changed since <base-ref> without bumping its <name>-version marker
# (or a new component ships without a marker). The CI / range-based counterpart of
# .githooks/pre-commit (which checks the staged set locally).
# Usage: check-version-bump.sh <base-ref>   e.g. origin/main
set -uo pipefail
base="${1:-origin/main}"

ver_of() { grep -oP '[a-z0-9-]+-version: \d+' | grep -v '^template-version' | head -1 | grep -oP ': \K\d+'; }

files=$(git diff --name-only --diff-filter=AM "$base"...HEAD \
  | grep -E '^plugins/[^/]+/(agents|commands)/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$|^plugins/[^/]+/hooks/[^/]+\.(py|sh)$' || true)
[ -z "$files" ] && { echo "no component changes vs $base"; exit 0; }

violations=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  new_ver=$(git show "HEAD:$f" 2>/dev/null | ver_of)
  if git cat-file -e "$base:$f" 2>/dev/null; then
    old_ver=$(git show "$base:$f" 2>/dev/null | ver_of)
    if [ -z "$new_ver" ]; then
      echo "  ✗ $f — version marker missing or removed"; violations=$((violations + 1))
    elif [ "$new_ver" = "$old_ver" ]; then
      echo "  ✗ $f — changed but still v$new_ver (bump the <name>-version marker)"; violations=$((violations + 1))
    fi
  elif [ -z "$new_ver" ]; then
    echo "  ✗ $f — new component without a version marker"; violations=$((violations + 1))
  fi
done <<< "$files"

if [ "$violations" -gt 0 ]; then
  echo ""; echo "forge-kit: $violations component change(s) need a version-marker bump."; exit 1
fi
echo "all changed components bumped their marker"
