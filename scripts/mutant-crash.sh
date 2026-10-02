# mutant-crash.sh: one crash classification for the mutant harnesses (#360).
# SOURCED by test-gate-status.sh, test-check-contributor-docs.sh, test-forge-adapt-tier-diff.sh,
# test-measure-dispatch-cost.sh, test-check-private-leaks.sh, test-gate-env.sh, test-phase-env.sh,
# test-phase-review-snapshot.sh, test-cdpath.sh, test-component-size.sh and test-mutant-crash.sh;
# one definition, so they cannot drift apart. test-forge-lib.sh's #319 ledger keeps its own
# positive predicate (mc_cleanly_dry), and #414 extends this list to the rest of the class.
# This file is not a suite and holds no ok/bad rows.
#
# #330 ruled that a crash is not a kill: a mutant is credited as killed only when it ran and failed
# the assertion it targets. A harness calls one of the two functions below AFTER its case has run
# and BEFORE it decides survived or dies; a non-empty reason is printed as the FAIL line
# `mutant <name> crashed (<reason>)` and nothing else, whatever the case returned.
#
# MUTANT_CRASH_RE, the stderr signature: a bash location (`: line N: `), an awk diagnostic, `syntax
# error`, `command not found`, or a Python traceback head. It is applied ONLY as
# `grep -E -e "$MUTANT_CRASH_RE" <log>`, never as an awk dynamic regex: as an awk string the `\(` of
# the Traceback alternative fails the match in gawk and BWK awk, and gawk warns on stderr.
#
# mutant_crash_reason <build> <stderr-log> [<liveness command> [args...]]: prints one line naming
# the first signal that fired, or nothing. In order: (1) the build does not parse (`bash -n`, or
# Python compile() for a .py build); (2) a line of <stderr-log> matches MUTANT_CRASH_RE, quoted;
# (3) the liveness command, when given, returns non-zero. It never reads the case's exit code,
# because genuine kills end in rc 2 or 124 as well.
#
# mutant_crash_reason_live <build> <liveness command> [args...]: for a harness whose case stderr
# cannot be the log (a genuine kill that IS a bash diagnostic). It runs the liveness command once,
# its stderr in a private temp log, and reports what mutant_crash_reason reports for that log and
# that run's verdict.
#
# A liveness command never pipes into an early-exit reader such as `grep -q` under pipefail (a
# match returns 141, #413); it captures the output and matches it with `case` or `grep -c`.
#
# STATED LIMIT: some crashes are indistinguishable from a real kill. A crash that leaves no
# signature, still parses, and happens only on the mutated path passes the liveness run, which
# does not reach that path, so it still reads as a kill. A script-written error message (a `die`)
# is deliberately not a signature.

MUTANT_CRASH_RE=': line [0-9]+: |(^|[/ ])[gmn]?awk: |syntax error|command not found|^Traceback \(most recent call last\):'

mutant_crash_reason() {
  local build="$1" log="$2" diag line
  shift 2
  case "$build" in
    *.py) diag=$(python3 -c 'import sys
try:
    compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")
except SyntaxError as e:
    print("%s: line %s: %s" % (sys.argv[1], e.lineno, e.msg)); sys.exit(1)' "$build" 2>&1) ;;
    *) diag=$(bash -n "$build" 2>&1) ;;
  esac
  if [ "$?" != 0 ]; then
    diag="${diag%%$'\n'*}"
    echo "the build does not parse: ${diag:-no diagnostic}"; return 0
  fi
  if [ -s "$log" ]; then
    line=$(grep -m1 -E -e "$MUTANT_CRASH_RE" "$log")
    if [ -n "$line" ]; then echo "a crash signature on stderr: $line"; return 0; fi
  fi
  if [ "$#" -gt 0 ] && ! "$@" >/dev/null 2>&1; then
    echo "the liveness run failed"
  fi
  return 0
}

mutant_crash_reason_live() {
  local build="$1" log verdict=true
  shift
  log=$(mktemp) || { echo "the liveness log could not be created"; return 0; }
  "$@" >/dev/null 2>"$log" || verdict=false
  mutant_crash_reason "$build" "$log" "$verdict"
  rm -f "$log"
}
