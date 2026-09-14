#!/usr/bin/env bash
# Contract test for update-suite-counts.py (issue #201), run against a throwaway doc and stub
# suites rather than this repo's real ones, so a real suite growing here can never make this
# suite pass or fail for the wrong reason. The one case that reads this repository uses --list,
# which parses and runs nothing: the generator is never run inside its own test.
#
# The contract: each `scripts/test-X`, N tests claim in the doc is compared with the total the
# suite PRINTS (pass plus fail, from the combined stdout+stderr stream, in any of the three shapes
# the tree uses); --check exits 1 naming each stale claim; rewrite mode changes only the number;
# and a suite that is missing or prints no recognisable total REFUSES (exit 2, nothing written),
# because a generator that writes 0 where it could not read is the drift it exists to end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
GEN="$HERE/update-suite-counts.py"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in '$2')"; fi; }
lacks()    { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/scripts"
DOC="$FIX/doc.md"

# Stub suites, one per output shape the tree uses today. Each first prints a line that ITSELF
# matches a summary shape (a nested suite's total, which test-pre-commit-hook.sh really does
# echo), so the reader has to take the LAST matching line rather than the first.
stub() {  # stub <name> <printf-format...>: writes an executable stub that prints the given lines
  local name="$1"; shift
  { echo '#!/usr/bin/env bash'; echo 'echo "  nested: 999 passed, 0 failed"'; printf 'printf "%%s\\n" "%s"\n' "$@"; } > "$FIX/scripts/$name"
  chmod +x "$FIX/scripts/$name"
}
stub test-a.sh 'a tests: 7 passed, 0 failed'
stub test-b.sh 'passed: 45  failed: 0'
# The unittest shape: on STDERR, stdout empty, the way python -m unittest reports.
cat > "$FIX/scripts/test-c.py" <<'PY'
import sys
sys.stderr.write("Ran 12 tests in 0.03s\n\nOK\n")
PY
# The validate-plugins shape: a label with no word "tests" in it.
stub test-d.sh 'test-d: 28 passed, 0 failed'
# A failing suite still reports its size.
stub test-e.sh 'e tests: 3 passed, 2 failed'

run() { python3 "$GEN" --doc "$DOC" --root "$FIX" "$@"; }

echo "== a claim is compared with the suite's printed total =="
printf -- '- `scripts/test-a.sh`, 7 tests, in CI.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "--check exits 0 on a current claim" 0 "$rc"
contains "current" "$out" "and says so"
printf -- '- `scripts/test-a.sh`, 5 tests, in CI.\n' > "$DOC"
cp "$DOC" "$FIX/before"
out="$(run --check 2>&1)"; rc=$?
expect "--check exits 1 on a stale claim" 1 "$rc"
contains "test-a.sh" "$out" "names the suite"
contains "5" "$out" "names the stated number"
contains "7" "$out" "and the printed one"
cmp -s "$DOC" "$FIX/before" && ok "--check writes nothing" || bad "--check writes nothing"

echo "== the anchor is the , N tests directly after the path =="
printf -- '- (`scripts/test-b.sh`, 43\n  tests, in CI) wraps like CLAUDE.md line 130.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "a claim wrapping between the digits and tests is found" 1 "$rc"
contains "43" "$out" "stated 43"
contains "45" "$out" "printed 45"
printf -- '- (`scripts/test-a.sh`, 30 tests, in CI): the 24 downstream tests were blind to it.\n' > "$DOC"
out="$(run 2>&1)"; rc=$?
expect "rewrite exits 0" 0 "$rc"
contains '`scripts/test-a.sh`, 7 tests' "$(cat "$DOC")" "the anchored number is rewritten"
contains "24 downstream tests" "$(cat "$DOC")" "a later N tests in the same bullet is prose and untouched"
printf -- '- `scripts/test-a.sh` is covered in CI. Nothing else.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "a suite named with no count is left alone" 0 "$rc"
printf -- '- `scripts/test-a.sh`, 7 testsuites agree.\n' > "$DOC"
out="$(run --list 2>&1)"
lacks "test-a.sh" "$out" "a number followed by a longer word than tests is not a claim"
printf -- '- `scripts/test-a.sh`,\n  7 tests, wrapping between the comma and the digits.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "a wrap between the comma and the digits is also found" 0 "$rc"
printf -- 'Run `scripts/test-a.sh`, 7 tests. Then `scripts/test-e.sh`, 5 tests.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "two claims on one line are both found (a failing suite counts pass plus fail)" 0 "$rc"

echo "== a summary is read from the combined stream, in any of three shapes =="
printf -- '- `scripts/test-c.py`, 12 tests, unittest on stderr.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "unittest's Ran N tests on stderr with empty stdout reads as 12" 0 "$rc"
printf -- '- `scripts/test-d.sh`, 28 tests, a label without the word tests.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "the validate-plugins label shape reads as 28" 0 "$rc"
printf -- '- `scripts/test-c.py`, 11 tests.\n' > "$DOC"
out="$(run 2>&1)"; rc=$?
expect "rewrite corrects the stderr-reported suite" 0 "$rc"
contains "12 tests" "$(cat "$DOC")" "to 12"
printf '#!/usr/bin/env bash\necho "something else entirely"\n' > "$FIX/scripts/test-f.sh"; chmod +x "$FIX/scripts/test-f.sh"
printf -- '- `scripts/test-f.sh`, 4 tests.\n' > "$DOC"
cp "$DOC" "$FIX/before"
out="$(run 2>&1)"; rc=$?
expect "a suite printing no recognisable total refuses with exit 2" 2 "$rc"
contains "test-f.sh" "$out" "and names it"
cmp -s "$DOC" "$FIX/before" && ok "and writes nothing" || bad "and writes nothing"
lacks "0 tests" "$(cat "$DOC")" "never a zero"

echo "== rewrite is minimal and idempotent =="
printf -- '- `scripts/test-a.sh`, 5 tests.\n- `scripts/test-b.sh`, 45 tests.\n' > "$DOC"
cp "$DOC" "$FIX/before"
out="$(run 2>&1)"; rc=$?
expect "first rewrite exits 0" 0 "$rc"
changed="$(diff "$FIX/before" "$DOC" | grep -c '^>')"
expect "exactly one line changed" 1 "$changed"
contains '`scripts/test-a.sh`, 7 tests.' "$(cat "$DOC")" "differing only in the number"
cp "$DOC" "$FIX/after1"
run >/dev/null 2>&1
cmp -s "$DOC" "$FIX/after1" && ok "second run is byte-identical" || bad "second run is byte-identical"
printf -- '- `scripts/test-absent.sh`, 5 tests.\n' > "$DOC"
cp "$DOC" "$FIX/before"
out="$(run 2>&1)"; rc=$?
expect "a suite absent under --root refuses with exit 2" 2 "$rc"
contains "test-absent.sh" "$out" "and names it"
cmp -s "$DOC" "$FIX/before" && ok "and writes nothing" || bad "and writes nothing"

echo "== the path read from prose is an input, not a command =="
# The claim's path is matched by an anchored pattern and resolved under --root/scripts; anything
# else is not a claim. A traversal or a shell metacharacter must never reach a subprocess.
printf -- '- `scripts/test-../../x.sh`, 5 tests.\n- `scripts/test-a.sh; touch pwned`, 5 tests.\n' > "$DOC"
out="$(run --list 2>&1)"; rc=$?
expect "--list finds no claim in a traversal or a metacharacter path" 0 "$rc"
lacks "pwned" "$out" "neither is listed"
[ -e "$FIX/pwned" ] && bad "nothing was executed" || ok "nothing was executed"
grep -q 'shell=True' "$GEN" && bad "the generator never uses shell=True" || ok "the generator never uses shell=True"
# A path that passes the pattern can still lead outside scripts/ by symlink; that is refused.
printf '#!/usr/bin/env bash\ntouch "%s/pwned"\necho "x: 1 passed, 0 failed"\n' "$FIX" > "$FIX/outside.sh"
chmod +x "$FIX/outside.sh"; ln -s "$FIX/outside.sh" "$FIX/scripts/test-linked.sh"
printf -- '- `scripts/test-linked.sh`, 1 tests.\n' > "$DOC"
out="$(run --check 2>&1)"; rc=$?
expect "a suite that resolves outside scripts/ refuses with exit 2" 2 "$rc"
[ -e "$FIX/pwned" ] && bad "and was not run" || ok "and was not run"

echo "== --list parses and runs nothing =="
printf -- '- `scripts/test-a.sh`, 5 tests.\n- `scripts/test-absent.sh`, 9 tests.\n' > "$DOC"
out="$(run --list 2>&1)"; rc=$?
expect "--list exits 0 even when a named suite is absent" 0 "$rc"
contains "test-a.sh" "$out" "lists the first claim"
contains "test-absent.sh" "$out" "and the second, since nothing was run"
lines="$(printf '%s\n' "$out" | grep -c 'scripts/test-')"
expect "one line per claim" 2 "$lines"

echo "== the real doc: the parser sees every claim CLAUDE.md makes, and runs nothing =="
# Reads this repository through --list only. The claims are the eleven the ticket counted; a
# twelfth appearing here is a doc edit, which is what this case is for.
out="$(python3 "$GEN" --list --doc "$ROOT/CLAUDE.md" --root "$ROOT" 2>&1)"; rc=$?
expect "--list on CLAUDE.md exits 0" 0 "$rc"
contains "scripts/test-check-private-leaks.sh" "$out" "the wrapped claim on line 130 is found"
contains "scripts/test-closing-sessions-memory.py" "$out" "the python suite is a claim"
n="$(printf '%s\n' "$out" | grep -c 'scripts/test-')"
[ "$n" -ge 11 ] && ok "at least the eleven claims the ticket counted ($n)" || bad "at least the eleven claims the ticket counted (got $n)"
# Every listed path must exist: a claim naming a suite that is not there would fail --check.
missing=0
for p in $(printf '%s\n' "$out" | grep -o 'scripts/test-[a-z0-9-]*\.[a-z]*' | sort -u); do [ -f "$ROOT/$p" ] || missing=$((missing + 1)); done
expect "every claimed suite exists in the tree" 0 "$missing"

echo
echo "update-suite-counts tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
