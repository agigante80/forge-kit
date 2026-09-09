#!/usr/bin/env bash
# Contract test for check-reference-depth.sh (#175).
#
# THE RULE, AND WHY IT IS MECHANICAL RATHER THAN STYLISTIC. Anthropic's skill-authoring guidance:
# "Keep references one level deep from SKILL.md. All reference files should link directly from
# SKILL.md to ensure agents read complete files when needed." The reason given is a concrete
# failure, not a preference: an agent meeting a reference INSIDE another reference may preview it
# with something like `head -100` rather than reading it whole, so it acts on half a file and
# nothing reports that it did.
#
# THE CASE THAT MATTERS MOST is the backtick one. This kit names references in prose backticks,
# never as markdown links. A guard that recognised only `[x](references/x.md)` would report every
# reference in the tree as an orphan, pass its own tests if those tests used link syntax, and be
# deleted by the first person who ran it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-reference-depth.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1' in output)"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
fresh() { rm -rf "$T/tree"; mkdir -p "$T/tree/plugins"; }
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$T/tree" 2>&1); rc=$?; }

S=plugins/g/skills/s

echo "== a reference named in prose backticks is reachable =="
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
Consult `references/api.md` before answering.
M
mk "$T/tree/$S/references/api.md" <<'M'
reference body
M
run
expect "a backticked reference passes" 0 "$rc"

echo "== a markdown link is reachable too =="
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
See [the API notes](references/api.md).
M
mk "$T/tree/$S/references/api.md" <<'M'
reference body
M
run
expect "a markdown-linked reference passes" 0 "$rc"

echo "== an orphan fails, naming the skill and the file =="
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
This skill names nothing.
M
mk "$T/tree/$S/references/orphan.md" <<'M'
nobody points here
M
run
expect "an unlinked reference fails" 1 "$rc"
contains "orphan.md" "$out" "and names the orphan"
contains "$S" "$out" "and names the skill that owns it"

echo "== every orphan is named, not just the first =="
# A guard that stops at the first finding turns one fix into several runs, which is how a guard
# gets a reputation for being annoying and then gets skipped.
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
This skill names nothing.
M
mk "$T/tree/$S/references/one.md" <<'M'
a
M
mk "$T/tree/$S/references/two.md" <<'M'
b
M
run
expect "two orphans still fail" 1 "$rc"
contains "one.md" "$out" "and the first is named"
contains "two.md" "$out" "and the second is named too"

echo "== reachability is measured from SKILL.md and nowhere else =="
# The forgejo.md case, and the reason the guard exists: a file whose only pointer lives inside
# another reference is exactly the nested shape the guidance describes.
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
Start with `references/adopting.md`.
M
mk "$T/tree/$S/references/adopting.md" <<'M'
Mind the differences in `references/nested.md`.
M
mk "$T/tree/$S/references/nested.md" <<'M'
one hop too far
M
run
expect "a reference reachable only from another reference fails" 1 "$rc"
contains "nested.md" "$out" "and names it"
lacks "adopting.md" "$out" "while the directly named one is not reported"

echo "== siblings may cross-link, as long as both are named by SKILL.md =="
# The release-automation near-miss. The rule is about REACHABILITY, not about forbidding
# cross-links, and a guard that failed this case would be wrong.
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
Read `references/a.md` and `references/b.md`.
M
mk "$T/tree/$S/references/a.md" <<'M'
see `references/b.md` for the tag-derived case
M
mk "$T/tree/$S/references/b.md" <<'M'
b
M
run
expect "cross-linked siblings both named by SKILL.md pass" 0 "$rc"

echo "== agents, assets and scripts are out of scope =="
# agents/ has no references/ and never will (#124: the loader claims every .md beneath agents/ at
# any depth), so inventing a violation there would send the fixer at a constraint they cannot
# satisfy. assets/ and scripts/ are executed or copied, not read into context.
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
names nothing
M
mk "$T/tree/plugins/g/agents/references/lens.md" <<'M'
not a skill reference
M
mk "$T/tree/$S/assets/thing.md" <<'M'
an asset
M
mk "$T/tree/$S/scripts/helper.md" <<'M'
a script directory
M
run
expect "nothing outside skills/*/references/ is judged" 0 "$rc"

echo "== a non-markdown file in references/ is ignored =="
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
names nothing
M
mk "$T/tree/$S/references/data.json" <<'M'
{}
M
run
expect "a non-.md reference is ignored" 0 "$rc"

echo "== a skill with no references/ directory is silent =="
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
a skill on its own
M
run
expect "a skill with no references passes" 0 "$rc"

echo "== a references/ directory with no SKILL.md beside it is an error, not a pass =="
# A reference whose owner is missing cannot be reachable from anything. Reporting clean here would
# be the vacuous pass this repo keeps finding in guards that cannot run.
fresh
mk "$T/tree/$S/references/lonely.md" <<'M'
no SKILL.md beside me
M
run
expect "a reference with no owning SKILL.md fails" 1 "$rc"
contains "lonely.md" "$out" "and names it"

echo "== paths are repo-relative =="
# check-public-leaks.sh runs against this tree, and an absolute path in a build log is what that
# scanner exists to catch.
fresh
mk "$T/tree/$S/SKILL.md" <<'M'
names nothing
M
mk "$T/tree/$S/references/orphan.md" <<'M'
x
M
run
lacks "$T" "$out" "no absolute path appears in the report"

echo "== this repository passes =="
# The regression test that keeps the three findings this guard was written for fixed.
out=$(bash "$SCRIPT" "$ROOT" 2>&1); rc=$?
expect "the real tree has no orphaned references" 0 "$rc"

echo ""
echo "reference-depth tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
