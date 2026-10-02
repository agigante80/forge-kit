#!/usr/bin/env bash
# Contract test for check-pipe-grep-q.sh (#413): the SIGPIPE mechanism the guard exists for, fixture
# repositories with tracked scripts (the forms that pass, the pipes that fail, the file set, the
# accepted limits), the repository itself, this suite's own source, and guard mutants the fixture
# rows must catch.
#
# THIS FILE IS INSIDE THE GUARD'S FILE SET, and the guard has no allow mechanism. So every fixture
# line that must hold a pipe into `grep -q` spells the bar through `$P` below, and no line of this
# source holds a literal bar before `grep -q`. The self-check section proves it.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
G="$HERE/check-pipe-grep-q.sh"
P='|'
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

# fix <path> <content>...: a fresh fixture repo tracking <path> with one line per argument.
fix() { F="$T/f.$RANDOM$RANDOM"; mkdir -p "$F/$(dirname "$1")"; local p="$1"; shift
  printf '%s\n' "$@" > "$F/$p"; git -C "$F" init -q; git -C "$F" add -A; }
run() { out=$(bash "${GUARD:-$G}" --root "$F" 2>"$T/err"); rc=$?; }
# expect <label> <rc> <rows...>: rc and the exact `path:line` prefixes of stdout, in order.
expect() { local label="$1" want="$2"; shift 2; local got
  got=$(printf '%s\n' "$out" | sed -n 's/^\([^:]*:[0-9]*\):.*/\1/p' | paste -sd' ' -)
  [ "$rc" = "$want" ] && [ "$got" = "$*" ] && ok "$label" || bad "$label (rc $rc, rows '$got', want rc $want '$*')"; }

echo "== the mechanism: a pipe into grep -q under pipefail can lose a match =="
# Deterministic, no load needed: the producer writes past the pipe buffer after the match, so it is
# still writing when grep -q exits. A child bash does not inherit pipefail, hence -o pipefail.
# Assumes SIGPIPE is not ignored on entry (with it ignored, the pipe half exits 1, still not 0).
bash -o pipefail -c "{ echo MATCH; head -c 200000 /dev/zero; } $P grep -q MATCH" 2>/dev/null; rc=$?
[ "$rc" = 141 ] && ok "the pipe form reports a present match as rc 141 (SIGPIPE)" || bad "the pipe form: rc $rc, want 141"
bash -o pipefail -c "grep -q MATCH <<< \"MATCH\$(head -c 200000 /dev/zero | tr '\\0' x)\""; rc=$?
[ "$rc" = 0 ] && ok "the here-string form finds the same match (rc 0)" || bad "the here-string form: rc $rc, want 0"

echo "== the forms that pass =="
fix scripts/a.sh '#!/bin/bash' 'grep -q x <<< "$y"' '[[ $y == *x* ]]' 'a || grep -q x' "# printf x $P grep -q x" "printf x $P grep -c x"
run; expect "a here-string, [[ ]], an or-list, a comment line and a grep -c pipe pass" 0
[ -z "$out" ] && ok "and stdout is empty" || bad "stdout not empty: $out"
POS="$F"

echo "== the pipes that fail =="
L2="printf '%s' \"\$y\" $P grep -q x && echo hit"
L3="echo \"\$y\" $P grep --quiet x"
L4="jq -r .body f $P grep -qiE x"
L5="  $P grep -E -q x"
L6="if ! printf x $P grep -q x; then :; fi"
fix scripts/a.sh '#!/bin/bash' "$L2" "$L3" "$L4" "$L5" "$L6"
run; expect "printf, echo, jq, a leading continuation and a pipe after ! each fail, naming the line" 1 \
  scripts/a.sh:2 scripts/a.sh:3 scripts/a.sh:4 scripts/a.sh:5 scripts/a.sh:6
want=$(printf 'scripts/a.sh:%s: %s\n' 2 "$L2" 3 "$L3" 4 "$L4" 5 "$L5" 6 "$L6")
[ "$out" = "$want" ] && ok "each row is the path:line: prefix followed by the line text" || bad "rows: '$out' want '$want'"
[ -s "$T/err" ] && ok "and stderr says what to write instead" || bad "stderr is empty"
NEG="$F"
fix scripts/s.sh '#!/bin/bash' "printf x${P}grep -q x" "printf x $P  grep -Fq x" "x=\$(printf x $P grep -q x)" "a $P sed s/a/b/ $P grep -qx b"
run; expect "no spaces, two spaces, inside \$( ) and after a longer pipeline are all flagged" 1 scripts/s.sh:2 scripts/s.sh:3 scripts/s.sh:4 scripts/s.sh:5

echo "== the accepted limits, as the header states them =="
fix scripts/l.sh '#!/bin/bash' "printf x $P \\" "  grep -q x" "printf x $P grep --fixed-strings -q x" "printf x $P \"\$GREP\" -q x"
run; expect "a pipe split over a continued line, a long option before -q and a grep through a variable are not seen" 0
fix scripts/l.sh '#!/bin/bash' "echo hi  # printf x $P grep -q x"
run; expect "a trailing comment that spells the construct is flagged" 1 scripts/l.sh:2

echo "== the file set =="
fix scripts/test-x.sh '#!/bin/bash' "printf x $P grep -q x"
run; expect "a test suite is in scope" 1 scripts/test-x.sh:2
fix .githooks/pre-push '#!/bin/sh' "printf x $P grep -q x"
run; expect "a hook is in scope" 1 .githooks/pre-push:2
fix plugins/p/skills/s/assets/a.sh '#!/bin/sh' "printf x $P grep -q x"
run; expect "a shipped asset is in scope" 1 plugins/p/skills/s/assets/a.sh:2
fix scripts/sub/n.sh '#!/bin/sh' "printf x $P grep -q x"
run; expect "a script nested below scripts/ is out of scope" 0
fix docs/a.md "printf x $P grep -q x"
run; expect "a doc is out of scope" 0
fix scripts/ok.sh '#!/bin/sh' 'echo hi'; printf '%s\n' "printf x $P grep -q x" > "$F/scripts/untracked.sh"
run; expect "an untracked file never counts" 0

echo "== the arguments =="
F="$T/missing"; run; [ "$rc" = 2 ] && ok "--root naming a missing directory exits 2" || bad "--root missing: rc $rc"
out=$(bash "$G" --root 2>/dev/null); rc=$?; [ "$rc" = 2 ] && ok "--root with no value exits 2" || bad "--root with no value: rc $rc"
out=$(bash "$G" --bogus 2>/dev/null); rc=$?; [ "$rc" = 2 ] && ok "an unknown argument exits 2" || bad "unknown argument: rc $rc"
mkdir -p "$T/nogit"; F="$T/nogit"; run; [ "$rc" = 2 ] && ok "a directory outside any checkout exits 2" || bad "outside a checkout: rc $rc"

echo "== the repository and this suite =="
F="$ROOT"; run; [ "$rc" = 0 ] && [ -z "$out" ] && ok "the repository itself is clean, this suite included" || bad "the repository: rc $rc: $out"
F="$T/self"; mkdir -p "$F/scripts"; cp "$HERE/test-check-pipe-grep-q.sh" "$F/scripts/"; git -C "$F" init -q; git -C "$F" add -A
run; [ "$rc" = 0 ] && [ -z "$out" ] && ok "this suite's own source, tracked in a fixture, has no flagged line" || bad "self-check: rc $rc: $out"
printf '%s\n' "printf x $P grep -q x" >> "$F/scripts/test-check-pipe-grep-q.sh"; git -C "$F" add -A
n=$(wc -l < "$F/scripts/test-check-pipe-grep-q.sh" | tr -d ' ')
run; expect "and the same fixture with one pipe appended is flagged, so the self-check can fail" 1 "scripts/test-check-pipe-grep-q.sh:$n"

echo "== mutants =="
cp "$HERE/guard-lib.sh" "$T/"
# mut <old> <new>: the guard with the literal text <old> replaced by <new>, as $T/g-mut.sh.
mut() { local g; g=$(cat "$G"); [[ $g == *"$1"* ]] || return 1; printf '%s\n' "${g//"$1"/"$2"}" > "$T/g-mut.sh"; }
# killed <label> <fixture> <rows...>: the mutant must run (rc 0 or 1) and NOT give the fixture's
# correct rows; a mutant that crashes is reported as crashed, never as killed (#360).
killed() { local label="$1"; F="$2"; shift 2; GUARD="$T/g-mut.sh" run
  local got; got=$(printf '%s\n' "$out" | sed -n 's/^\([^:]*:[0-9]*\):.*/\1/p' | paste -sd' ' -)
  if [ "$rc" != 0 ] && [ "$rc" != 1 ]; then bad "mutant crashed, not killed: $label (rc $rc)"
  elif [ "$got" != "$*" ]; then ok "mutant: $label (rows '$got')"; else bad "mutant survived: $label (rc $rc, rows '$got')"; fi; }
if mut '[[:space:]]+(-[A-Za-z]*q|--quiet)' ''; then
  killed "with the -q test removed the grep -c pipe is flagged, so the passing row catches it" "$POS"
else bad "mutant: the -q test is not in the guard"; fi
if mut '(-[A-Za-z]*q|--quiet)' '(--quiet)'; then
  killed "with the -q cluster no longer matched the negative fixture loses rows, so its row catches it" "$NEG" \
    scripts/a.sh:2 scripts/a.sh:3 scripts/a.sh:4 scripts/a.sh:5 scripts/a.sh:6
else bad "mutant: the -q cluster is not in the guard"; fi
if mut '(.*[^|])?' '(.*)?'; then
  killed "with the || exclusion removed, a || grep -q x is flagged, so the passing row catches it" "$POS"
else bad "mutant: the || exclusion is not in the guard"; fi
if mut '[^#[:space:]]' '[^[:space:]]'; then
  killed "with the comment skip removed, the comment line is flagged, so the passing row catches it" "$POS"
else bad "mutant: the comment skip is not in the guard"; fi

echo ""
echo "check-pipe-grep-q tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
