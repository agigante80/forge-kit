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
  # Each group's hand-written usage section sits below the region (#594); the generator refuses a
  # group without one, so every fixture docs/plugins.md carries both.
  printf 'intro\n\n<!-- plugin-reference:start -->\n<!-- plugin-reference:end -->\n\n### Using fix-alpha\n\n### Using fix-beta\n' \
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
printf '\n### Using fix-alpha\n\n### Using fix-beta\n' >> "$REF"
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
# The README is the short form only: no inventory table, which lives in docs/components.md (#588).
grep -q 'alpha-agent\|| Words |' "$FIX/README.md" \
  && bad "the README carries no component inventory" || ok "the README carries no component inventory"

# --- #594: a group description is refused, never cut ------------------------------------------
# A cut description was the defect (six of seven README rows ended in an ellipsis), so an overlong
# or multi-sentence one fails BOTH modes, names the group and the rule, and rewrites nothing.
set_desc() {
  python3 - "$FIX" "$1" <<'PY2'
import json, sys, os
p = os.path.join(sys.argv[1], "plugins/fix-alpha/.claude-plugin/plugin.json")
d = json.load(open(p)); d["description"] = sys.argv[2]
json.dump(d, open(p, "w"))
PY2
}
refused() {   # $1 description, $2 label, $3 text the report must carry
  mk_docs; python3 "$GEN" --root "$FIX" >/dev/null 2>&1
  set_desc "$1"
  local before; before=$(cat "$FIX/README.md" "$REF" "$IDX")
  for mode in --check ""; do
    out="$(python3 "$GEN" $mode --root "$FIX" 2>&1)"; rc=$?
    [ "$rc" -eq 1 ] && grep -qF "fix-alpha: $3" <<< "$out" \
      && ok "$2 fails ${mode:-the rewrite}, naming the group" \
      || bad "$2 fails ${mode:-the rewrite}, naming the group (rc $rc: $out)"
  done
  [ "$(cat "$FIX/README.md" "$REF" "$IDX")" = "$before" ] \
    && ok "and $2 rewrites no region" || bad "and $2 rewrites no region"
  grep -q '…' "$FIX/README.md" && bad "and no ellipsis reaches the README" || ok "and no ellipsis reaches the README"
}
refused "$(printf 'x%.0s' $(seq 400))" "a 400-character description" "description is 400 characters, over the 120-character cap"
refused "$(printf 'x%.0s' $(seq 121))" "a 121-character description" "description is 121 characters, over the 120-character cap"
refused "Short first sentence. A second one." "a two-sentence description" "description is longer than one sentence"
# At the cap is allowed, and is printed whole in both pages.
set_desc "$(printf 'y%.0s' $(seq 120))"
python3 "$GEN" --root "$FIX" >/dev/null 2>&1; rc=$?
row=$(grep '^| \[`fix-alpha`\]' "$FIX/README.md" | head -1)
[ "$rc" -eq 0 ] && grep -q "| y\{120\} |$" <<< "$row" && grep -qx 'y\{120\}' "$REF" \
  && ok "a 120-character description is printed whole in the README and the reference" \
  || bad "a 120-character description is printed whole (rc $rc, row: $row)"
# One sentence containing an abbreviation is still one sentence: the detector is _first_sentence.
set_desc "Reviews code, e.g. diffs, and files tickets."
python3 "$GEN" --root "$FIX" >/dev/null 2>&1 \
  && ok "an abbreviation inside one sentence is not a second sentence" \
  || bad "an abbreviation inside one sentence is not a second sentence"
set_desc "fixture"
mk_docs
python3 "$GEN" --root "$FIX" >/dev/null 2>&1

# --- #594: each group section links its hand-written usage section, which must exist ------------
ref=$(sed -n '/plugin-reference:start/,/plugin-reference:end/p' "$REF")
for g in fix-alpha fix-beta; do
  sect=$(awk -v h="### $g" '$0 == h {on=1; next} /^### / {on=0} on' <<< "$ref")
  grep -qF -- "- **Using it:** [prerequisites, first use, opt-in hooks, removal](#using-$g)" <<< "$sect" \
    && ok "the $g section links its usage section" \
    || bad "the $g section links its usage section"
done
sed -i '/^### Using fix-beta$/d' "$REF"
before=$(cat "$FIX/README.md" "$REF" "$IDX")
for mode in --check ""; do
  out="$(python3 "$GEN" $mode --root "$FIX" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && grep -qF "fix-beta: docs/plugins.md has no '### Using fix-beta' section" <<< "$out" \
    && ! grep -q 'fix-alpha: docs/plugins.md' <<< "$out" \
    && ok "a missing usage section fails ${mode:-the rewrite}, naming only that group" \
    || bad "a missing usage section fails ${mode:-the rewrite}, naming only that group (rc $rc: $out)"
done
[ "$(cat "$FIX/README.md" "$REF" "$IDX")" = "$before" ] \
  && ok "and a missing usage section rewrites no region" || bad "and a missing usage section rewrites no region"
# The heading must be the whole line: a mention in prose is not the section.
printf 'See ### Using fix-beta for details.\n' >> "$REF"
python3 "$GEN" --check --root "$FIX" >/dev/null 2>&1 \
  && bad "a mention of the heading inside a line does not count as the section" \
  || ok "a mention of the heading inside a line does not count as the section"
mk_docs
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
( cd "$FIX/.." && python3 "$GEN" --root "$(basename "$FIX")" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "a relative --root run exits 0" || bad "a relative --root run exits 0 (rc $rc)"
( cd "$FIX/.." && python3 "$GEN" --check --root "$(basename "$FIX")" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "and --check with the same relative --root is clean" \
  || bad "and --check with the same relative --root is clean (rc $rc)"
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
