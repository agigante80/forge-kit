#!/usr/bin/env bash
# Contract test for update-component-index.py (issue #96), run against a throwaway fixture tree
# rather than this repo, so a real component landing here can never make the suite pass or fail
# for the wrong reason.
#
# The contract: the generated regions are a function of the plugins/ tree, --check exits non-zero
# when they are not, and the error tells you which file and how to fix it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
GEN="$HERE/update-component-index.py"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

# --- fixture forge-kit tree -------------------------------------------------------------------
mkdir -p "$FIX/scripts" "$FIX/plugins/fix-alpha/agents" "$FIX/plugins/fix-alpha/.claude-plugin" \
         "$FIX/plugins/fix-beta/hooks" "$FIX/plugins/fix-beta/.claude-plugin"
cp "$HERE/forge-adapt-catalogue.sh" "$FIX/scripts/"

cat > "$FIX/plugins/fix-alpha/.claude-plugin/plugin.json" <<'J'
{ "name": "fix-alpha", "version": "1.2.3", "description": "fixture" }
J
cat > "$FIX/plugins/fix-beta/.claude-plugin/plugin.json" <<'J'
{ "name": "fix-beta", "version": "0.4.0", "description": "fixture" }
J

cat > "$FIX/plugins/fix-alpha/agents/alpha-agent.md" <<'M'
---
name: alpha-agent
description: Does the alpha thing for tests. Second sentence must be dropped.
---

<!-- alpha-agent-version: 7 -->
body
M

cat > "$FIX/plugins/fix-beta/hooks/beta-hook.py" <<'M'
#!/usr/bin/env python3
# beta-hook-version: 2
"""Beta hook docstring. Trailing sentence dropped."""
M

mk_docs() {
  printf 'intro\n\n<!-- plugin-catalogue:start -->\n<!-- plugin-catalogue:end -->\n\n<!-- component-index:start -->\n<!-- component-index:end -->\n\noutro\n' \
    > "$FIX/README.md"
  printf 'intro\n\n<!-- plugin-groups:start -->\n<!-- plugin-groups:end -->\n\noutro\n' \
    > "$FIX/CLAUDE.md"
}
mk_docs

# --- 1. a stale (empty) region must FAIL --check, before anything is generated ------------------
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -ne 0 ] && ok "--check fails on an ungenerated region" || bad "--check fails on an ungenerated region"

# --- 2. generate, then --check must pass -------------------------------------------------------
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -eq 0 ] && ok "--check passes right after generating" || bad "--check passes right after generating"

# --- 3. content actually rendered --------------------------------------------------------------
grep -q 'alpha-agent' "$FIX/README.md" && ok "component name rendered" || bad "component name rendered"
grep -q 'v7' "$FIX/README.md" && ok "component marker version rendered" || bad "component marker version rendered"
grep -q 'Does the alpha thing for tests.' "$FIX/README.md" \
  && ok "frontmatter description rendered" || bad "frontmatter description rendered"
grep -q 'Second sentence must be dropped' "$FIX/README.md" \
  && bad "only the first sentence is kept" || ok "only the first sentence is kept"
grep -q 'Beta hook docstring.' "$FIX/README.md" \
  && ok "python docstring used when there is no frontmatter" \
  || bad "python docstring used when there is no frontmatter"
grep -q 'beta-hook-version' "$FIX/README.md" \
  && bad "the version marker is never used as a description" \
  || ok "the version marker is never used as a description"
grep -q '1.2.3' "$FIX/CLAUDE.md" && ok "plugin.json semver rendered in the group table" \
  || bad "plugin.json semver rendered in the group table"
grep -q 'Do not hand-edit' "$FIX/README.md" && ok "generated regions carry a do-not-edit notice" \
  || bad "generated regions carry a do-not-edit notice"

# --- 3b. word counts (issue #97): present for prose types, blank for code -----------------------
grep -qE '\| Words \|' "$FIX/README.md" && ok "the index has a Words column" \
  || bad "the index has a Words column"
# alpha-agent's body is short; the count must be a real number, not blank or zero.
awk -F'|' '/alpha-agent/ {gsub(/ /,"",$6); if ($6 ~ /^[0-9]+$/ && $6+0 > 0) found=1} END {exit !found}' \
  "$FIX/README.md" && ok "a prose component carries a numeric word count" \
  || bad "a prose component carries a numeric word count"
awk -F'|' '/beta-hook/ {gsub(/ /,"",$6); if ($6 == "") found=1} END {exit !found}' \
  "$FIX/README.md" && ok "a hook's word count cell is blank (code is not word-counted)" \
  || bad "a hook's word count cell is blank"

# --- 4. idempotent: a second run changes nothing -----------------------------------------------
before=$(cat "$FIX/README.md" "$FIX/CLAUDE.md")
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
after=$(cat "$FIX/README.md" "$FIX/CLAUDE.md")
[ "$before" = "$after" ] && ok "generation is idempotent" || bad "generation is idempotent"

# --- 5. a hand-edit inside the region must be caught -------------------------------------------
sed -i 's/alpha-agent/alpha-AGENT-hand-edited/' "$FIX/README.md"
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -ne 0 ] && ok "--check catches a hand-edited region" || bad "--check catches a hand-edited region"
python3 "$GEN" --root "$FIX" >/dev/null 2>&1

# --- 6. a NEW component makes the region stale, and regenerating picks it up --------------------
mkdir -p "$FIX/plugins/fix-beta/skills/gamma-skill"
cat > "$FIX/plugins/fix-beta/skills/gamma-skill/SKILL.md" <<'M'
---
name: gamma-skill
description: A newly added fixture skill.
---

<!-- gamma-skill-version: 1 -->
M
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -ne 0 ] && ok "a new component makes --check fail" || bad "a new component makes --check fail"
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
grep -q 'gamma-skill' "$FIX/README.md" \
  && ok "regenerating picks up the new component" || bad "regenerating picks up the new component"
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -eq 0 ] && ok "--check green again after regenerating" || bad "--check green again after regenerating"

# --- 7. a missing marker pair is a clear error, not a silent no-op ------------------------------
printf 'no markers here\n' > "$FIX/README.md"
err=$(python3 "$GEN" --root "$FIX" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a missing marker region exits non-zero" || bad "a missing marker region exits non-zero"
printf '%s' "$err" | grep -q 'component-index' \
  && ok "the missing-marker error names the region" || bad "the missing-marker error names the region"

# --- the plugin catalogue: the README's user-facing group table ---------------------------------
# It exists because the install command for a group was written down NOWHERE, so a user who wanted
# one group had to read plugin.json to find its name. Generated rather than hand-written for the
# same reason as every other region here: a hand-maintained command is a copy of a string that rots.
mk_docs   # the missing-marker case above left README.md without its regions
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
cat=$(sed -n '/plugin-catalogue:start/,/plugin-catalogue:end/p' "$FIX/README.md")
printf '%s' "$cat" | grep -q 'claude plugin install fix-alpha@forge-kit' \
  && ok "the catalogue carries a copy-pasteable install command per group" \
  || bad "the catalogue carries a copy-pasteable install command per group"
printf '%s' "$cat" | grep -q '1.2.3' \
  && ok "and the group's plugin.json semver, which is the unit of install" \
  || bad "and the group's plugin.json semver"
printf '%s' "$cat" | grep -q 'fixture' \
  && ok "and the group's own description, so the table says what you would get" \
  || bad "and the group's own description"
[ "$(printf '%s' "$cat" | grep -c '^| `fix-')" = "2" ] \
  && ok "one row per group, no more and no less" \
  || bad "one row per group (got $(printf '%s' "$cat" | grep -c '^| `fix-'))"

# A description longer than the cap is truncated rather than breaking the table across lines.
python3 - "$FIX" <<'PY2'
import json, sys, os
p = os.path.join(sys.argv[1], "plugins/fix-alpha/.claude-plugin/plugin.json")
d = json.load(open(p)); d["description"] = "x" * 400
json.dump(d, open(p, "w"))
PY2
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
row=$(grep '^| `fix-alpha`' "$FIX/README.md" | head -1)
[ -n "$row" ] && [ "${#row}" -lt 400 ] \
  && ok "an overlong description is truncated, not spilled into the table" \
  || bad "an overlong description is truncated (row is ${#row} chars, empty means the row vanished)"
printf '%s' "$row" | grep -q '…' && ok "and the truncation is marked" || bad "and the truncation is marked"
python3 - "$FIX" <<'PY2'
import json, sys, os
p = os.path.join(sys.argv[1], "plugins/fix-alpha/.claude-plugin/plugin.json")
d = json.load(open(p)); d["description"] = "fixture"
json.dump(d, open(p, "w"))
PY2
python3 "$GEN" --root "$FIX" >/dev/null 2>&1

# The real README must carry the region, or the section this test protects is not on the page.
grep -q 'plugin-catalogue:start' "$ROOT/README.md" \
  && ok "the real README carries the catalogue region" \
  || bad "the real README carries the catalogue region"

echo ""
echo "update-component-index tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
