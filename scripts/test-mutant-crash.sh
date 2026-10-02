#!/usr/bin/env bash
# Contract test for scripts/mutant-crash.sh (#360): the one crash classification the mutant
# harnesses share. Each signal the helper's header names is a fixture here, with the inputs that
# must give nothing beside it.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
starts() { case "$3" in "$2"*) ok "$1" ;; *) bad "$1 (expected '$2...', got '$3')" ;; esac; }
. "$HERE/mutant-crash.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '#!/usr/bin/env bash\necho fine\n' > "$T/ok.sh"
printf 'print("fine")\n' > "$T/ok.py"
: > "$T/empty.log"
log() { printf '%s\n' "$1" > "$T/err.log"; mutant_crash_reason "$T/ok.sh" "$T/err.log"; }

echo "== the parse check =="
printf '#!/usr/bin/env bash\nfi fi\necho fine\n' > "$T/bad.sh"
starts "a fi fi bash build gives the reason bash -n rejects" "the build does not parse: $T/bad.sh: line 2: syntax error" \
  "$(mutant_crash_reason "$T/bad.sh" "$T/empty.log")"
printf 'def (:\n    pass\n' > "$T/bad.py"
starts "a .py build with def (: gives a parse reason" "the build does not parse: $T/bad.py: line 1: " \
  "$(mutant_crash_reason "$T/bad.py" "$T/empty.log")"
expect "a parsing bash build gives nothing" "" "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log")"
expect "a parsing .py build gives nothing" "" "$(mutant_crash_reason "$T/ok.py" "$T/empty.log")"
starts "the parse check comes before the log" "the build does not parse: " \
  "$(printf 'x.sh: line 3: foo: command not found\n' > "$T/err.log"; mutant_crash_reason "$T/bad.sh" "$T/err.log")"

echo "== the stderr signature =="
expect "a bash location quotes its line" "a crash signature on stderr: x.sh: line 3: foo: command not found" \
  "$(log 'x.sh: line 3: foo: command not found')"
expect "a BWK awk diagnostic quotes its line" "a crash signature on stderr: awk: syntax error at source line 1" \
  "$(log 'awk: syntax error at source line 1')"
expect "a mawk diagnostic quotes its line" "a crash signature on stderr: mawk: line 1: syntax error" \
  "$(log 'mawk: line 1: syntax error')"
expect "a Python traceback head quotes its line" "a crash signature on stderr: Traceback (most recent call last):" \
  "$(log 'Traceback (most recent call last):')"
expect "a gawk diagnostic behind a path quotes its line" "a crash signature on stderr: /usr/bin/gawk: cmd. line:1: oops" \
  "$(log '/usr/bin/gawk: cmd. line:1: oops')"
expect "the first matching line is the one quoted" "a crash signature on stderr: b: command not found" \
  "$(printf 'plain\nb: command not found\nc: line 9: x\n' > "$T/err.log"; mutant_crash_reason "$T/ok.sh" "$T/err.log")"
expect "a script-written message (a die) gives nothing" "" "$(log 'check-contributor-docs: could not read f')"
expect "a word ending in awk is not an awk diagnostic" "" "$(log 'gawkish: hello')"
expect "an indented Traceback is not a traceback head" "" "$(log '  Traceback (most recent call last):')"
expect "an empty log gives nothing" "" "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log")"
expect "a missing log gives nothing" "" "$(mutant_crash_reason "$T/ok.sh" "$T/no-such.log")"

echo "== the liveness run =="
expect "a liveness command false gives the liveness reason" "the liveness run failed" \
  "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log" false)"
expect "a liveness command true gives nothing" "" "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log" true)"
expect "the liveness command gets its arguments" "" "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log" test a = a)"
expect "and fails on them" "the liveness run failed" "$(mutant_crash_reason "$T/ok.sh" "$T/empty.log" test a = b)"
expect "the log comes before the liveness run" "a crash signature on stderr: syntax error" \
  "$(printf 'syntax error\n' > "$T/err.log"; mutant_crash_reason "$T/ok.sh" "$T/err.log" false)"
expect "the case's exit code is never read (rc 2 after a die gives nothing)" "" \
  "$(sh -c 'echo "cd: could not read f" >&2; exit 2' 2> "$T/err.log"; mutant_crash_reason "$T/ok.sh" "$T/err.log" true)"

echo "== mutant_crash_reason_live =="
live_diag() { echo 'x.sh: line 3: foo: command not found' >&2; return 0; }
live_die()  { echo 'phase: could not read f' >&2; return 0; }
live_out()  { echo 'x.sh: line 3: foo: command not found'; return 0; }
expect "a liveness run writing a bash diagnostic and exiting 0 gives a stderr reason" \
  "a crash signature on stderr: x.sh: line 3: foo: command not found" "$(mutant_crash_reason_live "$T/ok.sh" live_diag)"
expect "one writing phase: could not read f and exiting 0 gives nothing" "" "$(mutant_crash_reason_live "$T/ok.sh" live_die)"
expect "a signature on stdout is not read" "" "$(mutant_crash_reason_live "$T/ok.sh" live_out)"
expect "false gives the liveness reason" "the liveness run failed" "$(mutant_crash_reason_live "$T/ok.sh" false)"
starts "an unparsable build is reported before the liveness run" "the build does not parse: " \
  "$(mutant_crash_reason_live "$T/bad.sh" true)"
mkdir "$T/own"; TMPDIR="$T/own" mutant_crash_reason_live "$T/ok.sh" live_diag >/dev/null
expect "mutant_crash_reason_live leaves no temp log behind" "" "$(ls -A "$T/own")"
expect "a temp directory that does not exist is reported, never read as alive" "the liveness log could not be created" \
  "$(TMPDIR="$T/none" mutant_crash_reason_live "$T/ok.sh" true 2>/dev/null)"

echo "== the pattern =="
# Applied with grep -E only: as an awk string the \( of the Traceback alternative fails the match.
expect "MUTANT_CRASH_RE matches each of the five alternatives through grep -E" 5 \
  "$(printf '%s\n' 'a: line 1: b' 'awk: x' 'syntax error' 'command not found' 'Traceback (most recent call last):' \
     | grep -c -E -e "$MUTANT_CRASH_RE")"

echo ""
echo "mutant-crash tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
