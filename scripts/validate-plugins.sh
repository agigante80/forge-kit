#!/usr/bin/env bash
# Structural validation for the forge-kit marketplace. Runs in CI and locally.
# Checks (current tree, no git diff needed):
#   1. each plugin.json is valid JSON with name + description + semver version
#   2. marketplace.json is valid JSON and every plugin source resolves to a plugin.json
#   3. every component (agent/command/skill/hook/shell asset) carries a <name>-version marker
# Exit 1 on any violation. This is the forge-kit analogue of `claude plugin validate`.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

err=0
fail() { echo "  ✗ $1"; err=1; }
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+([-+].+)?$'

# 1. plugin.json
for pj in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$pj" ] || continue
  if ! jq -e . "$pj" >/dev/null 2>&1; then fail "$pj: invalid JSON"; continue; fi
  [ -n "$(jq -r '.name // empty' "$pj")" ]        || fail "$pj: missing name"
  [ -n "$(jq -r '.description // empty' "$pj")" ] || fail "$pj: missing description"
  ver=$(jq -r '.version // empty' "$pj")
  if [ -z "$ver" ]; then fail "$pj: missing version"
  elif ! echo "$ver" | grep -qE "$SEMVER"; then fail "$pj: version '$ver' is not semver"; fi
done

# 2. marketplace.json integrity
MP=.claude-plugin/marketplace.json
if jq -e . "$MP" >/dev/null 2>&1; then
  jq -e '(.plugins | type == "array") and (.plugins | length > 0)' "$MP" >/dev/null 2>&1 \
    || fail "$MP: .plugins must be a non-empty array"
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    [ -f "${src#./}/.claude-plugin/plugin.json" ] || fail "marketplace.json: source '$src' has no plugin.json"
  done < <(jq -r '.plugins[].source' "$MP")
else
  fail "$MP: invalid or missing JSON"
fi

# 3. component version markers (ignores body template-version references)
#
# THE ENFORCED PATH SET. Exactly ONE directory level deep: `plugins/<group>/agents/x.md` is a
# component, `plugins/<group>/agents/references/x.md` is not. This string is byte-identical to the
# pattern in scripts/check-version-bump.sh and .githooks/pre-commit, and scripts/test-component-paths.sh
# fails if the three drift apart or if the catalogue's glob stops agreeing with them.
#
# It used to be a set of `find -path '*/agents/*.md'` globs (issue #112). In `find -path`, unlike a
# shell glob, `*` CROSSES `/`, so those matched at any depth: a nested reference file would have been
# required to carry a version marker that the catalogue could never see and nothing would ever
# compare. Using the same ERE the other two guards use removes the dialect difference entirely.
COMPONENT_RE='^plugins/[^/]+/(agents|commands)/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$|^plugins/[^/]+/hooks/[^/]+\.(py|sh)$|^plugins/[^/]+/skills/[^/]+/assets/[^/]+\.sh$'
ver_of() { grep -oP '[a-z0-9-]+-version: \d+' | grep -v '^template-version' | head -1; }
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ -n "$(ver_of < "$f")" ] || fail "$f: missing <name>-version marker"
done < <(find plugins -type f -regextype posix-extended -regex "$COMPONENT_RE")

if [ "$err" -ne 0 ]; then echo ""; echo "forge-kit: plugin validation FAILED."; exit 1; fi
echo "forge-kit: plugin validation passed."
