#!/usr/bin/env bash
# Contract test for validate-plugins.sh (#169, #173).
#
# WHY THIS SUITE EXISTS AT ALL. validate-plugins.sh has been the kit's structural gate since the
# beginning and had NO contract test, which scripts/test-producer-stamps.sh already noted when it
# declined to extend it. Two tickets then needed to add rules to it in the same week, so the suite
# is created here rather than deferred again: this repo's record is that an untested guard grows
# rules nobody can prove fire.
#
# WHAT IT DRIVES. The script as a subprocess against throwaway trees, one per case. Each tree is a
# minimal marketplace (a marketplace.json plus one or more plugin.json files) with no components in
# it, so the marker rule has nothing to say and the case under test is the only thing that can fail.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/validate-plugins.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1' in output)"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required by validate-plugins.sh and by this test"; exit 2; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# One tree per case, built from scratch so no case can inherit another's state.
tree() {
  rm -rf "$T/tree"; mkdir -p "$T/tree/.claude-plugin"
  cat > "$T/tree/.claude-plugin/marketplace.json" <<'M'
{ "name": "forge-kit", "owner": { "name": "probe" },
  "plugins": [
    { "name": "forge-kit-alpha", "source": "./plugins/forge-kit-alpha", "description": "a" },
    { "name": "forge-kit-beta",  "source": "./plugins/forge-kit-beta",  "description": "b" } ] }
M
}
plugin() {  # plugin <group> <extra-json-fields-or-empty>
  mkdir -p "$T/tree/plugins/$1/.claude-plugin"
  printf '{ "name": "%s", "version": "0.1.0", "description": "d"%s }\n' "$1" "${2:+, $2}" \
    > "$T/tree/plugins/$1/.claude-plugin/plugin.json"
}
out=""; rc=0
run() { out=$(cd "$T/tree" && bash "$SCRIPT" 2>&1); rc=$?; }

echo "== the baseline tree passes, so a later failure is the rule under test =="
tree; plugin forge-kit-alpha; plugin forge-kit-beta
run
expect "a well-formed tree with no dependencies passes" 0 "$rc"

echo "== a resolvable dependency passes (#169) =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-beta@forge-kit"]'; plugin forge-kit-beta
run
expect "a dependency listed in marketplace.json passes" 0 "$rc"

echo "== an unresolvable dependency fails, naming both sides (#169) =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-nonesuch@forge-kit"]'; plugin forge-kit-beta
run
expect "a dependency absent from marketplace.json fails" 1 "$rc"
contains "forge-kit-nonesuch" "$out" "and names the missing plugin"
contains "forge-kit-alpha" "$out" "and names the group that declared it"

echo "== the object shape fails, because the CLI itself rejects it (#169) =="
# Probed on 2.1.267: `dependencies: {"x": "^0.1.0"}` fails `claude plugin validate` with
# `dependencies: Invalid input`. A guard laxer than the thing it protects is worse than none.
tree; plugin forge-kit-alpha '"dependencies": {"forge-kit-beta": "^0.1.0"}'; plugin forge-kit-beta
run
expect "an object rather than an array fails" 1 "$rc"
contains "array" "$out" "and says the shape must be an array"

echo "== a malformed identifier fails =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-beta"]'; plugin forge-kit-beta
run
expect "an identifier with no @marketplace fails" 1 "$rc"
contains "plugin@marketplace" "$out" "and names the shape it wanted"

echo "== the name match is exact, not a substring =="
# A substring match would resolve a typo'd 'forge-kit-alph' against 'forge-kit-alpha' and report a
# broken declaration as healthy, which is the one thing this check exists to prevent.
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-alph@forge-kit"]'; plugin forge-kit-beta
run
expect "a prefix of a real plugin name fails" 1 "$rc"
contains "forge-kit-alph@" "$out" "and names the identifier it could not resolve"

echo "== a foreign marketplace is reported as unverifiable, not failed =="
# The one honest limit: this script can only resolve names in the marketplace it is standing in.
# Failing a legitimate cross-marketplace dependency would be a guard inventing a violation.
tree; plugin forge-kit-alpha '"dependencies": ["someone-else@their-marketplace"]'; plugin forge-kit-beta
run
expect "a dependency on another marketplace does not fail the build" 0 "$rc"
contains "their-marketplace" "$out" "but is reported, so it is not silently trusted"

echo "== an empty dependencies array is fine =="
tree; plugin forge-kit-alpha '"dependencies": []'; plugin forge-kit-beta
run
expect "an empty array passes" 0 "$rc"

echo ""
echo "test-validate-plugins: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
