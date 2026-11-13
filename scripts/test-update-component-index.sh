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
mkdir -p "$FIX/scripts" "$FIX/docs" "$FIX/plugins/fix-alpha/agents" "$FIX/plugins/fix-alpha/.claude-plugin" \
         "$FIX/plugins/fix-beta/hooks" "$FIX/plugins/fix-beta/.claude-plugin"
cp "$HERE/forge-adapt-catalogue.sh" "$FIX/scripts/"

cat > "$FIX/plugins/fix-alpha/.claude-plugin/plugin.json" <<'J'
{ "name": "fix-alpha", "version": "1.2.3", "description": "fixture",
  "dependencies": ["fix-beta@forge-kit"] }
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

# Since #588 the three public regions live in three files: the short catalogue in README.md, the
# per-group reference in docs/plugins.md and the full inventory in docs/components.md.
IDX="$FIX/docs/components.md"
REF="$FIX/docs/plugins.md"
mk_docs() {
  printf 'intro\n\n<!-- plugin-catalogue:start -->\n<!-- plugin-catalogue:end -->\n\noutro\n' \
    > "$FIX/README.md"
  printf 'intro\n\n<!-- plugin-reference:start -->\n<!-- plugin-reference:end -->\n\noutro\n' \
    > "$REF"
  printf 'intro\n\n<!-- component-index:start -->\n<!-- component-index:end -->\n\noutro\n' \
    > "$IDX"
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
grep -q 'alpha-agent' "$IDX" && ok "component name rendered" || bad "component name rendered"
grep -q 'v7' "$IDX" && ok "component marker version rendered" || bad "component marker version rendered"
grep -q 'Does the alpha thing for tests.' "$IDX" \
  && ok "frontmatter description rendered" || bad "frontmatter description rendered"
grep -q 'Second sentence must be dropped' "$IDX" \
  && bad "only the first sentence is kept" || ok "only the first sentence is kept"
grep -q 'Beta hook docstring.' "$IDX" \
  && ok "python docstring used when there is no frontmatter" \
  || bad "python docstring used when there is no frontmatter"
grep -q 'beta-hook-version' "$IDX" \
  && bad "the version marker is never used as a description" \
  || ok "the version marker is never used as a description"
grep -q '1.2.3' "$FIX/CLAUDE.md" && ok "plugin.json semver rendered in the group table" \
  || bad "plugin.json semver rendered in the group table"
grep -q 'Do not hand-edit' "$IDX" && ok "generated regions carry a do-not-edit notice" \
  || bad "generated regions carry a do-not-edit notice"

# --- 3b. word counts (issue #97): present for prose types, blank for code -----------------------
grep -qE '\| Words \|' "$IDX" && ok "the index has a Words column" \
  || bad "the index has a Words column"
# alpha-agent's body is short; the count must be a real number, not blank or zero.
awk -F'|' '/alpha-agent/ {gsub(/ /,"",$6); if ($6 ~ /^[0-9]+$/ && $6+0 > 0) found=1} END {exit !found}' \
  "$IDX" && ok "a prose component carries a numeric word count" \
  || bad "a prose component carries a numeric word count"
awk -F'|' '/beta-hook/ {gsub(/ /,"",$6); if ($6 == "") found=1} END {exit !found}' \
  "$IDX" && ok "a hook's word count cell is blank (code is not word-counted)" \
  || bad "a hook's word count cell is blank"

# --- 4. idempotent: a second run changes nothing -----------------------------------------------
before=$(cat "$FIX/README.md" "$REF" "$IDX" "$FIX/CLAUDE.md")
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
after=$(cat "$FIX/README.md" "$REF" "$IDX" "$FIX/CLAUDE.md")
[ "$before" = "$after" ] && ok "generation is idempotent" || bad "generation is idempotent"

# --- 5. a hand-edit inside the region must be caught -------------------------------------------
sed -i 's/alpha-agent/alpha-AGENT-hand-edited/' "$IDX"
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -ne 0 ] && ok "--check catches a hand-edited region" || bad "--check catches a hand-edited region"
# The report names the REGION, not only the file (#311): a file can carry two, and a bare file
# name cannot say which is stale. Stdout is asserted, since that is where the report is printed,
# and the pre-push hook quotes it.
out="$(python3 "$GEN" --check --root "$FIX" 2>/dev/null)"
grep -q 'STALE region(s): docs/components.md (component-index)$' <<< "$out" \
  && ok "--check names the stale region as file and id, and only that one" \
  || bad "--check names the stale region as file and id, and only that one ($out)"
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
# Two stale regions in the SAME file are two distinct entries, in REGIONS order. The fixture's
# README gains a second region for this case only; mk_docs below puts it back to one.
printf 'x\n\n<!-- plugin-catalogue:start -->\n<!-- plugin-catalogue:end -->\n\n<!-- plugin-reference:start -->\n<!-- plugin-reference:end -->\n' \
  > "$FIX/README.md"
cp "$FIX/README.md" "$REF"
out="$(python3 "$GEN" --check --root "$FIX" 2>/dev/null)"
grep -q 'STALE region(s): README.md (plugin-catalogue), docs/plugins.md (plugin-reference)$' <<< "$out" \
  && ok "--check lists stale regions across files in REGIONS order" \
  || bad "--check lists stale regions across files in REGIONS order ($out)"
mk_docs
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
grep -q 'gamma-skill' "$IDX" \
  && ok "regenerating picks up the new component" || bad "regenerating picks up the new component"
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1
[ $? -eq 0 ] && ok "--check green again after regenerating" || bad "--check green again after regenerating"

# --- 7. a missing marker pair is a clear error, not a silent no-op ------------------------------
printf 'no markers here\n' > "$IDX"
err=$(python3 "$GEN" --root "$FIX" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a missing marker region exits non-zero" || bad "a missing marker region exits non-zero"
grep -q 'component-index' <<< "$err" \
  && ok "the missing-marker error names the region" || bad "the missing-marker error names the region"

# --- the plugin catalogue: the README's user-facing group table ---------------------------------
# It exists because the install command for a group was written down NOWHERE, so a user who wanted
# one group had to read plugin.json to find its name. Generated rather than hand-written for the
# same reason as every other region here: a hand-maintained command is a copy of a string that rots.
mk_docs   # the missing-marker case above left README.md without its regions
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
cat=$(sed -n '/plugin-catalogue:start/,/plugin-catalogue:end/p' "$FIX/README.md")
grep -q 'claude plugin install fix-alpha@forge-kit' <<< "$cat" \
  && ok "the catalogue carries a copy-pasteable install command per group" \
  || bad "the catalogue carries a copy-pasteable install command per group"
ref=$(sed -n '/plugin-reference:start/,/plugin-reference:end/p' "$REF")
grep -q '1.2.3' <<< "$ref" \
  && ok "the reference carries the group's plugin.json semver, which is the unit of install" \
  || bad "the reference carries the group's plugin.json semver"
grep -q 'fixture' <<< "$cat" \
  && ok "and the group's own description, so the table says what you would get" \
  || bad "and the group's own description"
[ "$(printf '%s' "$cat" | grep -c '^| \[`fix-')" = "2" ] \
  && ok "one row per group, no more and no less" \
  || bad "one row per group (got $(printf '%s' "$cat" | grep -c '^| \[`fix-'))"
grep -qF '| [`fix-alpha`](docs/plugins.md#fix-alpha) |' <<< "$cat" \
  && ok "each catalogue row links to its group's section of docs/plugins.md" \
  || bad "each catalogue row links to its group's section of docs/plugins.md"

# A description longer than the cap is truncated rather than breaking the table across lines.
python3 - "$FIX" <<'PY2'
import json, sys, os
p = os.path.join(sys.argv[1], "plugins/fix-alpha/.claude-plugin/plugin.json")
d = json.load(open(p)); d["description"] = "x" * 400
json.dump(d, open(p, "w"))
PY2
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
row=$(grep '^| \[`fix-alpha`\]' "$FIX/README.md" | head -1)
[ -n "$row" ] && [ "${#row}" -lt 400 ] \
  && ok "an overlong description is truncated in the README, not spilled into the table" \
  || bad "an overlong description is truncated (row is ${#row} chars, empty means the row vanished)"
grep -q '…' <<< "$row" && ok "and the truncation is marked" || bad "and the truncation is marked"
# #588: the reference page is where the whole description lives, so it is never cut there.
grep -qx 'x\{400\}' "$REF" \
  && ok "the reference prints the whole description, uncut" \
  || bad "the reference prints the whole description, uncut"
python3 - "$FIX" <<'PY2'
import json, sys, os
p = os.path.join(sys.argv[1], "plugins/fix-alpha/.claude-plugin/plugin.json")
d = json.load(open(p)); d["description"] = "fixture"
json.dump(d, open(p, "w"))
PY2
python3 "$GEN" --root "$FIX" >/dev/null 2>&1

# --- #588: the reference page, the links and the required targets ------------------------------
mk_docs
python3 "$GEN" --root "$FIX" >/dev/null 2>&1
ref=$(sed -n '/plugin-reference:start/,/plugin-reference:end/p' "$REF")
for g in fix-alpha fix-beta; do
  grep -qx "### $g" <<< "$ref" && grep -qF "[\`$g\`](#$g)" <<< "$ref" \
    && ok "the reference has a $g section and its overview row links to it" \
    || bad "the reference has a $g section and its overview row links to it"
done
grep -qF '| [`fix-alpha`](#fix-alpha) | 1.2.3 | `claude plugin install fix-alpha@forge-kit` | [`fix-beta`](#fix-beta) |' <<< "$ref" \
  && ok "a declared dependency renders as a link to that group, its @marketplace dropped" \
  || bad "a declared dependency renders as a link to that group, its @marketplace dropped"
grep -qF '| [`fix-beta`](#fix-beta) | 0.4.0 | `claude plugin install fix-beta@forge-kit` | nothing |' <<< "$ref" \
  && ok "a group with no dependency says nothing" \
  || bad "a group with no dependency says nothing"
grep -qF -- '- **Agent:** [`alpha-agent`](../plugins/fix-alpha/agents/alpha-agent.md)' <<< "$ref" \
  && ok "the reference lists each component under its group, linked to its source" \
  || bad "the reference lists each component under its group, linked to its source"
grep -qF '[`beta-hook`](../plugins/fix-beta/hooks/beta-hook.py)' "$IDX" \
  && ok "the inventory links each component to its source, relative to docs/" \
  || bad "the inventory links each component to its source, relative to docs/"
# Every link the generator writes resolves from the page it is written into.
unresolved=0
for page in "$IDX" "$REF"; do
  while IFS= read -r l; do
    [ -e "$(dirname "$page")/$l" ] || { unresolved=$((unresolved + 1)); echo "    unresolved: $l"; }
  done < <(grep -oP '\]\(\K\.\./[^)#]+' "$page")
done
[ "$unresolved" -eq 0 ] && ok "every generated source link resolves from its page" \
  || bad "every generated source link resolves from its page ($unresolved unresolved)"
# The links are relative: the generating machine's own path never reaches a published page.
grep -qF "$FIX" "$FIX/README.md" "$REF" "$IDX" \
  && bad "no generated region carries the absolute root path" \
  || ok "no generated region carries the absolute root path"
# The same holds with a RELATIVE --root, the form a contributor types.
( cd "$FIX/.." && python3 "$GEN" --root "$(basename "$FIX")" >/dev/null 2>&1 )
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1 \
  && ok "a relative --root renders the same links as an absolute one" \
  || bad "a relative --root renders the same links as an absolute one"

# A required target that is absent FAILS, in both modes, naming the file. Skipping it would let a
# moved or deleted public page leave the inventory unpublished with CI green.
for target in README.md docs/plugins.md docs/components.md; do
  mk_docs; python3 "$GEN" --root "$FIX" >/dev/null 2>&1
  rm -f "$FIX/$target"
  for mode in --check ""; do
    out="$(python3 "$GEN" $mode --root "$FIX" 2>&1)"; rc=$?
    [ "$rc" -eq 1 ] && grep -qF "required target(s) missing: $target" <<< "$out" \
      && ok "an absent $target fails ${mode:-the rewrite} and is named" \
      || bad "an absent $target fails ${mode:-the rewrite} and is named (rc $rc: $out)"
  done
  [ -e "$FIX/$target" ] && bad "and the run does not create $target" || ok "and the run does not create $target"
done
mk_docs; python3 "$GEN" --root "$FIX" >/dev/null 2>&1

# The real tree: each published page carries its region, and the README's catalogue links resolve.
for pair in README.md:plugin-catalogue docs/plugins.md:plugin-reference docs/components.md:component-index; do
  grep -q "${pair#*:}:start" "$ROOT/${pair%%:*}" \
    && ok "the real ${pair%%:*} carries the ${pair#*:} region" \
    || bad "the real ${pair%%:*} carries the ${pair#*:} region"
done

# --- an absent target doc is skipped, loudly, and is never a failure ---------------------------
# CLAUDE.md stopped being published on 2026-09-16 (assistant instructions are local working state),
# so it is absent from every CI checkout and present on a maintainer's machine. Dying on the
# absence would fail every build over a file the repository has decided not to carry; skipping
# silently would let the local region rot with nothing saying so. Last, because it deletes the
# fixture's copy.
rm -f "$FIX/CLAUDE.md"
out="$(python3 "$GEN" --check --root "$FIX" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "an absent target doc leaves --check green" || bad "an absent target doc leaves --check green (rc $rc)"
grep -q 'skipped: CLAUDE.md' <<< "$out" && ok "and the skip is named" || bad "and the skip is named"
grep -q 'Traceback' <<< "$out" && bad "with no traceback" || ok "with no traceback"
out="$(python3 "$GEN" --root "$FIX" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "and a rewrite run skips it too" || bad "and a rewrite run skips it too"
[ -f "$FIX/CLAUDE.md" ] && bad "without creating the file" || ok "without creating the file"
grep -q 'alpha-agent' "$IDX" && ok "the public regions are still generated" || bad "the public regions are still generated"

# --- #447: the kit's two once-bare commands describe themselves, not their marker -------------
for c in plugins/forge-kit-governance/commands/gate-ticket.md plugins/forge-kit-devops/commands/ci-health.md; do
  d="$(python3 - "$GEN" "$ROOT/$c" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gen", sys.argv[1]); gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)
print(gen._frontmatter_description(open(sys.argv[2], encoding="utf-8").read()) or "")
PY
)"
  case "$d" in ""|*-version:*) bad "$(basename "$c") has a frontmatter description, not its marker (got '$d')" ;;
    *) ok "$(basename "$c") has a frontmatter description, not its marker (#447)" ;; esac
done

echo ""
echo "update-component-index tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
