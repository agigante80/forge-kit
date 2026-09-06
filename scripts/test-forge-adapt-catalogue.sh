#!/usr/bin/env bash
# Contract test for forge-adapt-catalogue.sh, run against this repo (which IS a forge-kit library).
# Guards the exact regressions LLM executors kept reintroducing: SKILL.md-instead-of-name and a
# non-zero exit on a hookless group.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$HERE/forge-adapt-catalogue.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

out=$(bash "$SCRIPT" "$ROOT"); rc=$?

[ "$rc" -eq 0 ] && ok "exits 0 (hookless groups do not fail)" || bad "exits 0 (got rc=$rc)"

# Binds to a DIGIT, not a bare "v": "vnone" starts with v, so the old `| v` form was satisfied by
# the very failure it existed to detect (issue #95). Every version assertion below does the same.
printf '%s\n' "$out" | grep -qP '^skill: adapt \| v[0-9]+' \
  && ok "skills print their DIRECTORY name and a real marker (skill: adapt)" \
  || bad "skills print their directory name and a real marker"

if printf '%s\n' "$out" | grep -q 'SKILL.md'; then
  bad "no row prints SKILL.md as the name"
else
  ok "no row prints SKILL.md as the name"
fi

printf '%s\n' "$out" | grep -qP '^subagent: ticket-gate \| v[0-9]+' \
  && ok "a known agent appears with its marker (ticket-gate)" \
  || bad "a known agent appears with its marker"

printf '%s\n' "$out" | grep -qP '^skill: api-design-principles \| v[0-9]+' \
  && ok "a known skill appears with its marker" \
  || bad "a known skill appears with its marker"

printf '%s\n' "$out" | grep -qP '^hook: block-dashes \| v[0-9]+' \
  && ok "a known hook appears with its marker (block-dashes)" \
  || bad "a known hook appears with its marker"

# Versioned shell assets (issue #64): the catalogue must list them, or drift/refresh has no
# forge-kit-side version to compare an installed scripts/forge-lib.sh against.
printf '%s\n' "$out" | grep -qP '^asset: forge-lib \| v[0-9]+' \
  && ok "a versioned shell asset appears with its marker (forge-lib)" \
  || bad "a versioned shell asset appears with its marker (forge-lib)"

# No row may print "vnone". The catalogue walks exactly the five path shapes that
# validate-plugins.sh requires a <name>-version marker on, so every row it prints has a marker in
# its file by construction; a "vnone" therefore means the catalogue FAILED TO READ a marker that is
# provably there, never that the component is genuinely unversioned. That is what issue #95 was:
# skills/adapt/SKILL.md carries "forge-adapt-version" while the row name is its directory, "adapt".
if printf '%s\n' "$out" | grep -q '| vnone$'; then
  bad "no row prints vnone ($(printf '%s\n' "$out" | grep -c '| vnone$') found)"
else
  ok "no row prints vnone (every catalogued file carries a marker by construction)"
fi

# Missing/absent library arg is a graceful exit 0 (read-only, no crash).
bash "$SCRIPT" /nonexistent-forge-kit >/dev/null 2>&1 && ok "missing library dir exits 0" || bad "missing library dir exits 0"

echo ""
echo "forge-adapt-catalogue tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
