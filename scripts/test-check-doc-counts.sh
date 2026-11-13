#!/usr/bin/env bash
# Contract test for check-doc-counts.sh (#595, #572 WP7).
#
# THE FAILURE IT EXISTS FOR. Hand-written counts in the public docs ("seven plugin groups",
# "Eight groups", "the five work templates", "292 plugins") went stale past review, one by one.
# The guard fails the build on an undated count of the kit's contents; these cases pin what it reads,
# what it skips, what dates a count and what an exception must say. Every case runs the script as a
# subprocess against a throwaway tree; the last one runs it on this repository.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-doc-counts.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks()    { if grep -qF -- "$1" <<< "$2"; then bad "$3 ('$1' in output)"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

out=""; rc=0
# stdin is closed: a guard that fell through to reading stdin would hang the suite instead of failing it
run() { out=$(bash "$SCRIPT" "$T/tree" 2>&1 </dev/null); rc=$?; }
# fresh: an empty tree holding only README.md with the given body
fresh() { rm -rf "$T/tree"; mkdir -p "$T/tree"; printf '%s\n' "$@" > "$T/tree/README.md"; }
put() { mkdir -p "$T/tree/$(dirname "$1")"; f="$1"; shift; printf '%s\n' "$@" > "$T/tree/$f"; }

echo "== an undated inventory count fails, named by file and line =="
fresh "# forge-kit" "" "Intro line." "forge-kit ships as seven plugin groups, each installed independently."
run
expect "exit 1" 1 "$rc"
contains "README.md:4: seven plugin" "$out" "names file, line and the count"

echo "== a digit count fails, and so does a digit count of lines =="
fresh "# x" "" "The official marketplace has 292 plugins." "The files are about 240 lines apart."
run
expect "exit 1" 1 "$rc"
contains "README.md:3: 292 plugins" "$out" "digits before a noun"
contains "README.md:4: 240 lines" "$out" "digits before a digits-only noun"

echo "== 'one' is never a count, and a number word before a digits-only noun is not either =="
fresh "# x" "" "Copy one template by name." "A citation must sit within two lines of an anchor."
run
expect "exit 0" 0 "$rc"

echo "== an ISO date in the same section dates the count =="
fresh "# x" "" "## Measured" "" "Measured 2026-10-01." "" "The marketplace had 292 plugins."
run
expect "exit 0" 0 "$rc"

echo "== a date in a DIFFERENT section does not =="
fresh "# x" "" "## Earlier" "" "Measured 2026-10-01." "" "## Later" "" "The marketplace has 292 plugins."
run
expect "exit 1" 1 "$rc"
contains "README.md:9: 292 plugins" "$out" "the later section's count is named"

echo "== a dotted tool version alone does not date a section =="
fresh "# x" "" "A group at 0.1.0 is normal, and the seven groups move independently."
run
expect "exit 1" 1 "$rc"
contains "seven groups" "$out" "an example version is not a date"

echo "== fenced code and generated regions are skipped =="
fresh "# x" "" '```' "seven plugin groups" '```' "" "<!-- plugin-catalogue:start -->" "seven plugin groups" "<!-- plugin-catalogue:end -->" "" "Clean prose."
run
expect "exit 0" 0 "$rc"

echo "== the region skip ends at its end marker =="
fresh "# x" "" "<!-- r:start -->" "seven plugin groups" "<!-- r:end -->" "and then five templates."
run
expect "exit 1" 1 "$rc"
contains "README.md:6: five templates" "$out" "a count after the region is read"
lacks "README.md:4:" "$out" "the count inside the region is not"

echo "== the fence skip ends at its closing fence =="
fresh "# x" "" '```' "seven plugin groups" '```' "and then five templates."
run
expect "exit 1" 1 "$rc"
contains "README.md:6: five templates" "$out" "a count after the fence is read"

echo "== docs/, docs/guides/ and plugins/*/hooks/README.md are read =="
fresh "# x"
put docs/a.md "Three groups declare a dependency."
put docs/guides/b.md "Copy the five work templates."
put plugins/g/hooks/README.md "The four hand-rolled hooks."
run
expect "exit 1" 1 "$rc"
contains "docs/a.md:1: Three groups" "$out" "docs/*.md"
contains "docs/guides/b.md:1: five work templates" "$out" "docs/guides/*.md"
contains "plugins/g/hooks/README.md:1: four hand-rolled hooks" "$out" "plugins/*/hooks/README.md"

echo "== history directories are not read =="
fresh "# x"
put docs/plans/p.md "thirty closed phases"
put docs/superpowers/s.md "seven plugin groups"
put docs/changelog-detail/v1.md "eleven files"
run
expect "exit 0" 0 "$rc"

echo "== an issue reference, a version and a clause-ending number are not counts =="
fresh "# x" "" "This rot happened in PRs #74 and #75, where component markers moved." "See #178 groups." "Claude Code 2.1.310 hooks."
run
expect "exit 0" 0 "$rc"

echo "== a word ending its clause ends the look-ahead =="
fresh "# x" "" "We kept two of them; templates came later."
run
expect "exit 0" 0 "$rc"

echo "== a table cell boundary ends the look-ahead =="
fresh "# x" "" "| run | 25 s | reference |"
run
expect "exit 0" 0 "$rc"

echo "== an exception with a reason passes, on the line or the line above =="
fresh "# x" "" "The four states a group can be in. <!-- doc-count: defines the four states listed next -->" "<!-- doc-count: a definition, the list follows -->" "The three version levels."
run
expect "exit 0" 0 "$rc"

echo "== an exception with no reason fails =="
fresh "# x" "" "<!-- doc-count: -->" "The three version levels."
run
expect "exit 1" 1 "$rc"
contains "README.md:3: doc-count exception has no reason" "$out" "an empty reason is named"

echo "== a count wrapped across a hard line break fails, named at the number's line =="
fresh "# x" "" "It is version-locked to the five work" "templates by the lockstep guard." \
  "Duplicated across three" "guards and changed together."
run
expect "exit 1" 1 "$rc"
contains "README.md:3: five work templates" "$out" "number and noun split one word in"
contains "README.md:5: three guards" "$out" "number last on its line, noun first on the next"

echo "== a count found on its own line is reported once, not again from the carry =="
fresh "# x" "" "There are seven plugin groups" "in this kit."
run
expect "one hit" 1 "$(grep -c 'seven plugin' <<< "$out")"

echo "== a blank line, a heading or a table row ends the carry =="
fresh "# x" "" "We read three" "" "guards in a new paragraph." "Then two" "## Hooks" "Also four" "| hooks | x |"
run
expect "exit 0" 0 "$rc"

echo "== a new list item takes no carry from the item above =="
fresh "# x" "" "- Fix issue 5" "- Hook the thing" "* item 7" "* Agents run" "1. Step 2" "2. Tests pass" "3) Step 4" "4) Guards hold"
run
expect "exit 0" 0 "$rc"
fresh "# x" "" "- A list item wrapping its five" "  work templates onto a second line"
run
expect "a wrapped list item still carries" 1 "$rc"

echo "== a heading or a table row carries nothing out =="
fresh "# x" "" "## Phase 2" "Tests run here." "| a | 3" "guards wait"
run
expect "exit 0" 0 "$rc"

echo "== a clause break before the wrap ends the carry =="
fresh "# x" "" "We counted three." "Guards are listed elsewhere."
run
expect "exit 0" 0 "$rc"

echo "== an exempted line carries nothing into the next =="
fresh "# x" "" "Pick the three <!-- doc-count: a rule, not an inventory -->" "guards that apply."
run
expect "exit 0" 0 "$rc"
fresh "# x" "" "Pick the three" "Text <!-- doc-count: a rule, not an inventory -->" "covered by it." "guards that apply."
run
expect "a carry does not jump the exempted lines" 0 "$rc"

echo "== a missing root exits 2 =="
out=$(bash "$SCRIPT" "$T/nope" 2>&1 </dev/null); rc=$?
expect "exit 2" 2 "$rc"

echo "== a root with no markdown exits 2 =="
rm -rf "$T/tree"; mkdir -p "$T/tree"
run
expect "exit 2" 2 "$rc"

echo "== this repository passes =="
out=$(bash "$SCRIPT" "$ROOT" 2>&1 </dev/null); rc=$?
expect "exit 0" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out"

echo
echo "check-doc-counts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
