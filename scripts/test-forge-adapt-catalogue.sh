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

# owasp-api-security rather than api-design-principles: the latter was retired with the whole
# forge-kit-backend group in #178, and a test pinned to a component that no longer exists tells you
# nothing about the catalogue.
printf '%s\n' "$out" | grep -qP '^skill: owasp-api-security \| v[0-9]+' \
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

# --tsv mode (issue #96): a second consumer (update-component-index.py) needs the file PATH, which
# the default rows do not carry. It is a mode on THIS script rather than a second walk elsewhere,
# so "what counts as a component" keeps exactly one definition.
tsv=$(bash "$SCRIPT" --tsv "$ROOT"); trc=$?

[ "$trc" -eq 0 ] && ok "--tsv exits 0" || bad "--tsv exits 0 (got rc=$trc)"

if printf '%s\n' "$tsv" | grep -q '^=== '; then
  bad "--tsv emits no === group === headers"
else
  ok "--tsv emits no === group === headers"
fi

# Every row: exactly 5 tab-separated fields, and the last one is a file that exists.
tsv_rows=$(printf '%s\n' "$tsv" | grep -c .)
tsv_ok=$(printf '%s\n' "$tsv" | awk -F'\t' 'NF==5' | wc -l)
[ "$tsv_rows" -gt 0 ] && [ "$tsv_rows" -eq "$tsv_ok" ] \
  && ok "--tsv rows all have 5 fields ($tsv_rows rows)" \
  || bad "--tsv rows all have 5 fields ($tsv_ok of $tsv_rows)"

missing=$(printf '%s\n' "$tsv" | awk -F'\t' 'NF==5 {print $5}' | while read -r f; do [ -f "$f" ] || echo "$f"; done)
[ -z "$missing" ] && ok "--tsv path field points at a real file" \
  || bad "--tsv path field points at a real file (missing: $(printf '%s' "$missing" | head -1))"

# The version field is bare digits here (no "v" prefix), and never "none" for the same
# reason the default mode never prints vnone.
if printf '%s\n' "$tsv" | awk -F'\t' 'NF==5 && $4 !~ /^[0-9]+$/' | grep -q .; then
  bad "--tsv version field is bare digits"
else
  ok "--tsv version field is bare digits"
fi

# Both modes must describe the SAME component set, or the two consumers disagree about what
# forge-kit contains, which is the drift #96 exists to remove.
text_n=$(printf '%s\n' "$out" | grep -c '^[a-z]*: ')
[ "$text_n" -eq "$tsv_rows" ] \
  && ok "--tsv and default mode agree on component count ($text_n)" \
  || bad "--tsv and default mode agree on count (text=$text_n tsv=$tsv_rows)"

# Missing/absent library arg is a graceful exit 0 (read-only, no crash).
bash "$SCRIPT" /nonexistent-forge-kit >/dev/null 2>&1 && ok "missing library dir exits 0" || bad "missing library dir exits 0"

echo ""
echo "forge-adapt-catalogue tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
