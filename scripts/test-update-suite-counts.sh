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

echo "== an absent doc is skipped loudly, and a doc named explicitly is refused =="
# CLAUDE.md stopped being published on 2026-09-16, so it is absent from every CI checkout: the
# default target being gone must be a loud skip and exit 0, never a traceback and never a silent
# pass that looks like agreement. A doc the CALLER named is different: that is a mistake worth an
# exit 2, because the caller expected the file to be there.
NODOC="$FIX/empty-root"; mkdir -p "$NODOC/scripts"
out="$(python3 "$GEN" --root "$NODOC" --check 2>&1)"; rc=$?
expect "an absent default doc exits 0" 0 "$rc"
contains "not in this checkout" "$out" "and says what it skipped"
out="$(python3 "$GEN" --doc "$NODOC/missing.md" --root "$NODOC" --check 2>&1)"; rc=$?
expect "a doc named on the command line and missing is refused (exit 2)" 2 "$rc"
contains "no such doc" "$out" "naming it"
lacks "Traceback" "$out" "without a traceback"

echo "== --changed narrows the run to the suites a push touched (#218) =="
# Every claim is checked by RUNNING its suite, which is 93 s for the twelve in this repository, so
# a git hook can only afford the ones the range touched. A sentinel file per suite is what proves
# which ran: wall time would flake on a loaded machine, the failure #219 is already about.
SENT="$FIX/sent"; mkdir -p "$SENT"
cat > "$FIX/scripts/test-sent-a.sh" <<'SA'
#!/usr/bin/env bash
: > "$SENTDIR/a.ran"
echo "a tests: 4 passed, 0 failed"
SA
cat > "$FIX/scripts/test-sent-b.sh" <<'SB'
#!/usr/bin/env bash
: > "$SENTDIR/b.ran"
echo "b tests: 6 passed, 0 failed"
SB
chmod +x "$FIX/scripts/test-sent-a.sh" "$FIX/scripts/test-sent-b.sh"
printf -- '- `scripts/test-sent-a.sh`, 4 tests.\n- `scripts/test-sent-b.sh`, 6 tests.\n' > "$DOC"
rm -f "$SENT"/*.ran
out="$(SENTDIR="$SENT" run --check --changed scripts/test-sent-a.sh 2>&1)"; rc=$?
expect "--changed with one path exits 0 when that claim is current" 0 "$rc"
[ -f "$SENT/a.ran" ] && ok "the named suite ran" || bad "the named suite ran"
[ -f "$SENT/b.ran" ] && bad "and the other did not" || ok "and the other did not"
rm -f "$SENT"/*.ran
out="$(SENTDIR="$SENT" run --check --changed docs/roadmap.md 2>&1)"; rc=$?
expect "--changed with no counted suite exits 0" 0 "$rc"
contains "no counted suite changed" "$out" "and says so"
ls "$SENT"/*.ran >/dev/null 2>&1 && bad "and runs nothing" || ok "and runs nothing"
rm -f "$SENT"/*.ran
out="$(SENTDIR="$SENT" run --check --changed ./scripts/test-sent-a.sh scripts/test-sent-b.sh 2>&1)"; rc=$?
expect "--changed takes several paths, dotted or plain" 0 "$rc"
{ [ -f "$SENT/a.ran" ] && [ -f "$SENT/b.ran" ]; } && ok "and runs exactly those" || bad "and runs exactly those"
printf -- '- `scripts/test-sent-a.sh`, 99 tests.\n- `scripts/test-sent-b.sh`, 6 tests.\n' > "$DOC"
out="$(SENTDIR="$SENT" run --check --changed scripts/test-sent-a.sh 2>&1)"; rc=$?
expect "--changed still fails a stale claim it covers" 1 "$rc"
contains "test-sent-a.sh" "$out" "naming it"
out="$(SENTDIR="$SENT" run --check --changed scripts/test-sent-b.sh 2>&1)"; rc=$?
expect "and ignores a stale claim it does not cover, which is the point of the filter" 0 "$rc"

echo "== a doc shaped like this repository's own: every claim is seen, and nothing is run =="
# This used to read $ROOT/CLAUDE.md and skip when it was absent, which made the suite's OWN total
# environment-dependent: 48 cases in a CI checkout, 52 on a machine that has the doc (#218). A
# suite whose count depends on a file that is in no checkout cannot state a stable count, and that
# count is itself one of the twelve claims the generator checks. So the cases below always run,
# against the real doc where it exists and against a fixture carrying the same shapes where it does
# not: the wrapped claim, the .py suite, and a dozen claims in one file.
# Both branches emit exactly one line, so the suite's own total is the same either way, which is
# the whole point of this section.
REALDOC="$ROOT/CLAUDE.md"
if [ -f "$REALDOC" ]; then
  ok "(this repository's own CLAUDE.md) the parser reads the real prose"
fi
if [ ! -f "$REALDOC" ]; then
  REALDOC="$FIX/realish.md"
  {
    printf -- '- **`closing-sessions/scripts/memory.py`** (`scripts/test-closing-sessions-memory.py`, 12 tests): prose.\n'
    printf -- '   - **`leak-guard/assets/check-private-leaks.sh`** (`scripts/test-check-private-leaks.sh`, 127\n     tests, in CI): a claim that wraps between the digits and the word.\n'
    for i in 1 2 3 4 5 6 7 8 9 10; do
      printf -- '- `scripts/test-fixture-%s.sh`, %s tests, in CI.\n' "$i" "$i"
    done
  } > "$REALDOC"
  ok "(no CLAUDE.md here) the same cases run against a fixture carrying its shapes"
fi
out="$(python3 "$GEN" --list --doc "$REALDOC" --root "$ROOT" 2>&1)"; rc=$?
expect "--list on the doc exits 0" 0 "$rc"
contains "scripts/test-check-private-leaks.sh" "$out" "the wrapped claim on line 130 is found"
contains "scripts/test-closing-sessions-memory.py" "$out" "the python suite is a claim"
n="$(printf '%s\n' "$out" | grep -c 'scripts/test-')"
[ "$n" -ge 11 ] && ok "at least the eleven claims the ticket counted ($n)" || bad "at least the eleven claims the ticket counted (got $n)"
# Every listed path must exist, but only when the doc IS this repository's: a fixture names
# suites that deliberately do not exist, and asserting otherwise would test the fixture.
if [ "$REALDOC" = "$ROOT/CLAUDE.md" ]; then
  missing=0
  for p in $(printf '%s\n' "$out" | grep -o 'scripts/test-[a-z0-9-]*\.[a-z]*' | sort -u); do [ -f "$ROOT/$p" ] || missing=$((missing + 1)); done
  expect "every claimed suite exists in the tree" 0 "$missing"
else
  ok "(fixture doc) the suite-exists check belongs to the real doc"
fi

echo
echo "update-suite-counts tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
