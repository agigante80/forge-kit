#!/usr/bin/env bash
# Contract test for THE ENFORCED PATH SET (issue #112).
#
# Four consumers decide "is this file a component": scripts/validate-plugins.sh (find -regex),
# scripts/check-version-bump.sh and .githooks/pre-commit (grep -E), and
# scripts/forge-adapt-catalogue.sh (shell globs). They cannot share one implementation, because a
# glob is not a regex, so this test is the thing that keeps them agreeing.
#
# The rule: exactly ONE directory level deep. plugins/<g>/agents/x.md is a component;
# plugins/<g>/agents/references/x.md is not. Before #112, find -path matched at any depth (its `*`
# crosses `/`, a shell glob's does not), so a nested file was required to carry a version marker
# that the catalogue could never see and nothing would ever compare.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

extract_re() { grep -oE "\^plugins/\[\^/\]\+.*\\\$" "$1" | head -1; }

# --- 1. the three regex consumers carry a byte-identical pattern -------------------------------
re_validate=$(extract_re "$ROOT/scripts/validate-plugins.sh")
re_bump=$(extract_re "$ROOT/scripts/check-version-bump.sh")
re_hook=$(extract_re "$ROOT/.githooks/pre-commit")

[ -n "$re_validate" ] && ok "validate-plugins.sh carries an extractable path regex" \
  || bad "validate-plugins.sh carries an extractable path regex"
[ -n "$re_bump" ] && [ "$re_bump" = "$re_validate" ] \
  && ok "check-version-bump.sh matches validate-plugins.sh byte for byte" \
  || bad "check-version-bump.sh matches validate-plugins.sh byte for byte"
[ -n "$re_hook" ] && [ "$re_hook" = "$re_validate" ] \
  && ok ".githooks/pre-commit matches validate-plugins.sh byte for byte" \
  || bad ".githooks/pre-commit matches validate-plugins.sh byte for byte"

# validate-plugins.sh must actually USE the regex, not merely mention it.
grep -q 'find plugins -type f -regextype posix-extended -regex "\$COMPONENT_RE"' \
  "$ROOT/scripts/validate-plugins.sh" \
  && ok "validate-plugins.sh drives find from that regex" \
  || bad "validate-plugins.sh drives find from that regex"

# --- fixture: one valid component per type, plus a nested decoy for each shape ------------------
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/scripts" "$FIX/.claude-plugin" \
         "$FIX/plugins/g/.claude-plugin" \
         "$FIX/plugins/g/agents/references" \
         "$FIX/plugins/g/commands/sub" \
         "$FIX/plugins/g/hooks" \
         "$FIX/plugins/g/skills/s/assets/nested"
cp "$ROOT/scripts/forge-adapt-catalogue.sh" "$ROOT/scripts/validate-plugins.sh" "$FIX/scripts/"
printf '{ "name": "g", "version": "1.0.0", "description": "fixture" }\n' \
  > "$FIX/plugins/g/.claude-plugin/plugin.json"
printf '{ "plugins": [ { "name": "g", "source": "./plugins/g" } ] }\n' \
  > "$FIX/.claude-plugin/marketplace.json"

# real components (one level, each with a marker)
printf '<!-- a-version: 1 -->\n'      > "$FIX/plugins/g/agents/a.md"
printf '<!-- c-version: 1 -->\n'      > "$FIX/plugins/g/commands/c.md"
printf '<!-- s-version: 1 -->\n'      > "$FIX/plugins/g/skills/s/SKILL.md"
printf '# h-version: 1\n'             > "$FIX/plugins/g/hooks/h.py"
printf '# lib-version: 1\n'           > "$FIX/plugins/g/skills/s/assets/lib.sh"

# DECOYS: nested one level deeper, deliberately carrying NO marker. Each is the shape a future
# split would create, and none of them is a component.
printf 'reference prose, no marker\n' > "$FIX/plugins/g/agents/references/lens.md"
printf 'nested command, no marker\n'  > "$FIX/plugins/g/commands/sub/deep.md"
printf 'nested asset, no marker\n'    > "$FIX/plugins/g/skills/s/assets/nested/deep.sh"

# --- 2. validate-plugins.sh must PASS: the decoys are not components ---------------------------
out=$(cd "$FIX" && bash scripts/validate-plugins.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "validate-plugins.sh ignores nested files (no marker demanded)" \
  || bad "validate-plugins.sh ignores nested files (rc=$rc: $(printf '%s' "$out" | head -1))"

# --- 3. the catalogue lists exactly the five real components -----------------------------------
names=$(cd "$FIX" && bash scripts/forge-adapt-catalogue.sh --tsv . | awk -F'\t' '{print $3}' | sort | tr '\n' ' ')
[ "$names" = "a c h lib s " ] && ok "the catalogue lists exactly the five real components" \
  || bad "the catalogue lists exactly the five real components (got: $names)"

# --- 4. the regex and the catalogue agree on the SAME set --------------------------------------
via_re=$(cd "$FIX" && find plugins -type f -regextype posix-extended -regex "$re_validate" | sort)
via_cat=$(cd "$FIX" && bash scripts/forge-adapt-catalogue.sh --tsv . | awk -F'\t' '{print $5}' \
            | sed 's|^\./||' | sort)
[ "$via_re" = "$via_cat" ] \
  && ok "the regex and the catalogue glob select an identical file set" \
  || bad "the regex and the catalogue glob select an identical file set"

# --- 5. every decoy is rejected by the regex ---------------------------------------------------
decoys_matched=$(printf '%s\n' \
  "plugins/g/agents/references/lens.md" \
  "plugins/g/commands/sub/deep.md" \
  "plugins/g/skills/s/assets/nested/deep.sh" | grep -cE "$re_validate" || true)
[ "$decoys_matched" -eq 0 ] && ok "the regex rejects all three nested decoys" \
  || bad "the regex rejects all three nested decoys ($decoys_matched matched)"

# --- 6. and every real component is accepted ---------------------------------------------------
reals_matched=$(printf '%s\n' \
  "plugins/g/agents/a.md" "plugins/g/commands/c.md" "plugins/g/skills/s/SKILL.md" \
  "plugins/g/hooks/h.py" "plugins/g/skills/s/assets/lib.sh" | grep -cE "$re_validate" || true)
[ "$reals_matched" -eq 5 ] && ok "the regex accepts all five real component shapes" \
  || bad "the regex accepts all five real component shapes ($reals_matched of 5)"

echo ""
echo "component-path tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
