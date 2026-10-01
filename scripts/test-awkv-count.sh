#!/usr/bin/env bash
# Contract test for scripts/awkv-count.sh (#405): the zero-`awk -v` count and the no-operand rule
# the eight #259 asset suites share. Each shape the helper's header names is a fixture here.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
. "$HERE/awkv-count.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cnt() { printf '%s\n' "$@" > "$T/f.sh"; awkv_count "$T/f.sh"; }
ops() { printf '%s\n' "$@" > "$T/f.sh"; awk_operand_lines "$T/f.sh" | cut -d: -f1 | paste -sd' ' -; }

echo "== the zero-awk -v count =="
expect "a plain awk counts 0" 0 "$(cnt "awk '{print}' < f")"
expect "awk -v counts 1" 1 "$(cnt "awk -v x=1 '{print x}'")"
expect "-F'|' -v counts 1 (the old [^|] pattern missed it)" 1 "$(cnt "awk -F'|' -v x=1 '{print x}'")"
expect "a -v on an awk \\ continuation line counts 1" 1 "$(cnt 'x=$(awk \' "  -v x=1 '{print x}')")"
expect "\"\$AWK\" -v counts 1" 1 "$(cnt "\"\$AWK\" -v x=1 '{print x}'")"
expect "\${MY_AWK} -v counts 1" 1 "$(cnt "\${MY_AWK} -v x=1 '{print x}'")"
expect "-v'x=1' counts 1" 1 "$(cnt "awk -v'x=1' '{print x}'")"
expect "-vx=1 counts 1" 1 "$(cnt "awk -vx=1 '{print x}'")"
expect "--assign x=1 counts 1" 1 "$(cnt "gawk --assign x=1 '{print x}'")"
expect "--assign=x=1 counts 1" 1 "$(cnt "mawk --assign=x=1 '{print x}'")"
expect "nawk -v counts 1" 1 "$(cnt "nawk -v x=1 '{print x}'")"
expect "the accepted over-count: awk ...; grep -v on one line counts 1" 1 "$(cnt "awk '{print}' f; grep -v foo g")"
expect "a comment line never counts" 0 "$(cnt "# awk -v x=1 is banned")"
expect "grep -v with no awk counts 0" 0 "$(cnt "grep -v foo g")"
expect "a word holding awk (awkward, awk_x) counts 0" 0 "$(cnt "awkward -v x" "awk_x -v y")"

echo "== the no-operand rule =="
expect "awk '{print}' \"\$f\" is flagged" 1 "$(ops "awk '{print}' \"\$f\"")"
expect "a multi-line program closed by ' \"\$f\" is flagged on its closing line" 3 "$(ops "awk '" "  {print}" "' \"\$f\"")"
expect "and one closed by }' \"\$f\"" 2 "$(ops "awk '{" "}' \"\$f\"")"
expect "awk -F'\\t' '{print}' \"\$f\" is flagged (the -F span is skipped)" 1 "$(ops "awk -F'\\t' '{print}' \"\$f\"")"
expect "awk -F '\\t' '{print}' \"\$f\" is flagged too" 1 "$(ops "awk -F '\\t' '{print}' \"\$f\"")"
expect "awk '{print}' < \"\$f\" is not" "" "$(ops "awk '{print}' < \"\$f\"")"
expect "awk -F'\\t' '{print}' < \"\$f\" is not" "" "$(ops "awk -F'\\t' '{print}' < \"\$f\"")"
expect "awk '...' x; printf '%s' \"\$y\" is not (only the first span after awk is read)" "" "$(ops "awk '{print}' x; printf '%s' \"\$y\"")"
expect "a comment is never read" "" "$(ops "# awk '{print}' \"\$f\"")"
expect "the accepted limit: a program in a variable is not read" "" "$(ops "awk \"\$PROG\" \"\$f\"")"

echo ""
echo "awkv-count tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
