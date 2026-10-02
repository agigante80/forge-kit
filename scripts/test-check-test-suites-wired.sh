#!/usr/bin/env bash
# Contract test for check-test-suites-wired.sh (issue #348).
#
# THE DEFECT IT GUARDS. The repo's policy is that every scripts/test-* suite runs in CI, and
# #344 found one with no validate.yml step. The guard enforces the policy; this suite pins the
# guard's match rule, its enumeration and its three exit codes.
#
# "TRACKED" IS PART OF THE CONTRACT. Every fixture except the non-checkout one is built in a
# mktemp directory with `git init` and `git add`, so enumeration goes through the real
# guard_tracked_files path rather than an assumption about it. Fixture paths are mktemp paths,
# never a home path, because the leak guard scans every tracked file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$HERE/check-test-suites-wired.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# Fixtures outside a checkout must stay outside one even when TMPDIR is inside this repo (#362).
export GIT_CEILING_DIRECTORIES="$T"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in: $2)"; fi; }
lacks()    { if grep -qF -- "$1" <<< "$2"; then bad "$3 ('$1' present in: $2)"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

n=0
out=""; rc=0
# fresh <suite>...: a new git checkout with those suites tracked and no validate.yml yet.
fresh() {
  n=$((n + 1)); D="$T/f$n"
  mkdir -p "$D/scripts" "$D/.github/workflows"
  git -C "$D" init -q
  local s
  for s in "$@"; do
    printf '#!/bin/sh\n' > "$D/scripts/$s"
    git -C "$D" add -- "scripts/$s"
  done
  return 0
}
# yml: write validate.yml from stdin
yml() { cat > "$D/.github/workflows/validate.yml"; }
run() { out=$(bash "$SCRIPT" "${1-$D}" 2>&1); rc=$?; }

echo "== wired and unwired =="
fresh test-a.sh test-b.sh
yml <<'M'
steps:
  - name: a
    run: bash scripts/test-a.sh
  - name: b
    run: bash scripts/test-b.sh
M
run
expect "all wired exits 0" 0 "$rc"
lacks "scripts/test-" "$(printf '%s' "$out" | grep -v 'all wired')" "and names no unwired path"

fresh test-a.sh test-b.sh
yml <<'M'
steps:
  - run: bash scripts/test-a.sh
M
run
expect "one unwired exits 1" 1 "$rc"
contains "scripts/test-b.sh" "$out" "and names the unwired suite"
lacks "scripts/test-a.sh" "$out" "and not the wired one"

fresh test-a.sh test-b.sh test-c.sh
yml <<'M'
  - run: bash scripts/test-a.sh
M
run
expect "two unwired exits 1" 1 "$rc"
contains "scripts/test-b.sh" "$out" "the first unwired is named"
contains "scripts/test-c.sh" "$out" "the second unwired is named too, not just the first"

echo "== what counts as a step =="
fresh test-example.sh
yml <<'M'
  # run: bash scripts/test-example.sh
M
run
expect "a comment is not a step" 1 "$rc"
contains "scripts/test-example.sh" "$out" "and the suite is named"

fresh test-example.py
yml <<'M'
  # run: python3 scripts/test-example.py
  - name: echo run: python3 scripts/test-example.py
M
run
expect "a python3 comment or mid-line mention is not a step" 1 "$rc"
contains "scripts/test-example.py" "$out" "and the suite is named"

fresh test-example.sh
yml <<'M'
  - run: bash scripts/test-example.sh.bak
M
run
expect ".bak does not wire the suite" 1 "$rc"
contains "scripts/test-example.sh" "$out" "and the suite is named"

fresh test-example.sh
yml <<'M'
  # run: bash scripts/test-example.sh
  - run: bash scripts/test-example.sh.bak
M
run
expect "comment plus .bak together still unwired" 1 "$rc"

fresh test-example.py
yml <<'M'
  - run: python3 scripts/test-example.py
M
run
expect "python3 wires a .py suite" 0 "$rc"

fresh test-example.sh
yml <<'M'
  - run: python3 scripts/test-example.sh
M
run
expect "python3 does not wire a .sh suite" 1 "$rc"
contains "scripts/test-example.sh" "$out" "and the suite is named"

fresh test-example.py
yml <<'M'
  - run: bash scripts/test-example.py
M
run
expect "bash does not wire a .py suite" 1 "$rc"
contains "scripts/test-example.py" "$out" "and the suite is named"

fresh test-a.sh
yml <<'M'
  - run: bash scripts/test-a.sh;x
M
run
expect "a token with a trailing ;x is a different string" 1 "$rc"

fresh test-foo.sh test-foo-bar.sh
yml <<'M'
  - run: bash scripts/test-foo.sh
M
run
expect "a name prefix does not wire the longer suite" 1 "$rc"
contains "scripts/test-foo-bar.sh" "$out" "the longer name is reported"
lacks "scripts/test-foo.sh" "$out" "the shorter, wired name is not"

fresh test-foo.sh test-foo-bar.sh
yml <<'M'
  - run: bash scripts/test-foo-bar.sh
M
run
expect "a longer step does not wire the shorter suite" 1 "$rc"
contains "scripts/test-foo.sh" "$out" "the shorter name is reported"

fresh test-example.sh
yml <<'M'
  - run: bash scripts/test-example.sh --flag
M
run
expect "a trailing argument still wires (first token equals the basename)" 0 "$rc"

fresh test-example.sh
yml <<'M'
    - run: bash scripts/test-example.sh # a trailing note
M
run
expect "indentation, the list dash and a trailing note still wire" 0 "$rc"

fresh test-example.sh
printf -- '-   run: bash scripts/test-example.sh\t--flag\r\n' | yml
run
expect "several spaces after the dash and a tab after the token still wire" 0 "$rc"

fresh test-example.sh
printf -- '  - run: bash scripts/test-example.sh\r\n' | yml
run
expect "a CRLF line with nothing between the token and the CR still wires" 0 "$rc"

fresh test-example.sh
printf -- '  - run: bash scripts/test-example.sh' | yml
run
expect "a last line with no trailing newline still wires" 0 "$rc"

echo "== the guard pins its own locale =="
# The suite runs the guard under C.UTF-8 on purpose: with no pin in the guard, a U+3000 after the
# path would end the token and the line would count as wired.
if grep -qiE '^c\.utf-?8$' <<< "$(locale -a 2>/dev/null)"; then
  fresh test-a.sh
  printf -- '  - run: bash scripts/test-a.sh\xe3\x80\x80x\n' | yml
  out=$(LC_ALL=C.UTF-8 bash "$SCRIPT" "$D" 2>&1); rc=$?
  expect "a U+3000 after the path does not end the token, even when the caller runs C.UTF-8" 1 "$rc"
  contains "  x scripts/test-a.sh" "$out" "and the suite is named"
  fresh test-a.sh
  printf -- '  - run: bash scripts/test-a.sh # note\n' | yml
  out=$(LC_ALL=C.UTF-8 bash "$SCRIPT" "$D" 2>&1); rc=$?
  expect "a space-delimited token still wires under C.UTF-8" 0 "$rc"
else
  echo "  skip: no C.UTF-8 locale on this machine"
fi

echo "== refused shapes (accepted limits, each a false failure never a false pass) =="
fresh test-example.sh
yml <<'M'
  - run: "bash scripts/test-example.sh"
M
run
expect "a quoted value does not wire" 1 "$rc"
contains "scripts/test-example.sh" "$out" "and the suite is named"

fresh test-example.sh
yml <<'M'
  - run: bash ./scripts/test-example.sh
M
run
expect "a ./scripts path does not wire" 1 "$rc"

fresh test-example.sh
yml <<'M'
  - run: |
      bash scripts/test-example.sh
M
run
expect "a run: | block does not wire" 1 "$rc"
contains "scripts/test-example.sh" "$out" "and the suite is named"

fresh test-a.sh test-b.sh
yml <<'M'
  - run: bash scripts/test-a.sh && bash scripts/test-b.sh
M
run
expect "a compound command wires only the first suite" 1 "$rc"
contains "scripts/test-b.sh" "$out" "the second is reported"
lacks "scripts/test-a.sh" "$out" "the first is not"

echo "== what is a suite =="
fresh test-a.sh
mkdir -p "$D/scripts/sub" "$D/docs"
printf 'x\n' > "$D/docs/test-x.sh"                   # tracked, outside scripts/
printf 'x\n' > "$D/test-y.py"                        # tracked, at the root
printf 'x\n' > "$D/scripts/test-orphan.sh"            # untracked, never git-added
printf 'x\n' > "$D/scripts/sub/test-nested.sh"        # tracked but nested
printf 'x\n' > "$D/scripts/test-notes.txt"            # tracked, wrong extension
printf 'x\n' > "$D/scripts/test-a.sh.bak"             # tracked, wrong extension
printf 'x\n' > "$D/scripts/check-thing.sh"            # tracked, not test-*
git -C "$D" add docs/test-x.sh test-y.py scripts/sub/test-nested.sh scripts/test-notes.txt scripts/test-a.sh.bak scripts/check-thing.sh
yml <<'M'
  - run: bash scripts/test-a.sh
M
run
expect "untracked, nested, wrong-extension and non-test files are not suites" 0 "$rc"
lacks "orphan" "$out" "the untracked suite is not reported"
lacks "nested" "$out" "the nested suite is not reported"
lacks "notes" "$out" "the .txt is not reported"
lacks ".bak" "$out" "the .bak is not reported"
lacks "test-x" "$out" "a tracked docs/test-x.sh is not reported"
lacks "test-y" "$out" "a tracked root test-y.py is not reported"

fresh test-a.sh
mkdir -p "$D/scripts/sub"; printf 'x\n' > "$D/scripts/sub/test-nested.sh"
git -C "$D" add scripts/sub/test-nested.sh
yml <<'M'
  - run: bash scripts/test-a.sh
M
run
expect "a tracked nested suite is never demanded wired" 0 "$rc"

fresh test-a.py
yml <<'M'
  - run: python3 scripts/test-a.py
M
run
expect "a .py suite alone is enough, the zero-suite refusal does not fire" 0 "$rc"

echo "== unusable input exits 2 =="
fresh test-example.sh
rm -f "$D/.github/workflows/validate.yml"
run
expect "missing validate.yml exits 2, never 0" 2 "$rc"
contains "validate.yml" "$out" "and stderr names validate.yml"
lacks "all wired" "$out" "and reports no success"

fresh test-example.sh
mkdir "$D/.github/workflows/validate.yml"
run
expect "validate.yml that is a directory exits 2" 2 "$rc"

if [ "$(id -u)" -ne 0 ]; then
  fresh test-example.sh
  yml <<'M'
  - run: bash scripts/test-example.sh
M
  chmod 000 "$D/.github/workflows/validate.yml"
  run
  expect "an unreadable validate.yml exits 2, never 0" 2 "$rc"
  contains "validate.yml" "$out" "and stderr names validate.yml"
  chmod 644 "$D/.github/workflows/validate.yml"
else
  ok "unreadable validate.yml skipped (running as root)"
fi

fresh
yml <<'M'
  - run: bash scripts/test-example.sh
M
run
expect "zero suites exits 2, never vacuous" 2 "$rc"
contains "no suites found" "$out" "and stderr says so"

fresh
printf 'x\n' > "$D/scripts/test-orphan.sh"
mkdir -p "$D/scripts/sub"; printf 'x\n' > "$D/scripts/sub/test-nested.sh"
git -C "$D" add scripts/sub/test-nested.sh
yml <<'M'
  - run: bash scripts/test-orphan.sh
M
run
expect "only untracked and nested suites exits 2" 2 "$rc"
contains "no suites found" "$out" "and stderr says so"

fresh test-a.sh
yml < /dev/null
run
expect "an empty validate.yml leaves the suite unwired, exit 1" 1 "$rc"

fresh test-a.sh
printf '\000\377\376\200\r\n\001run: bash scripts/\377\000\n\303(\n' > "$D/.github/workflows/validate.yml"
run
expect "a binary validate.yml reports the suite unwired, exit 1" 1 "$rc"
contains "have no step" "$out" "and it is the finding, not a crash"
if grep -qE ': line [0-9]+: ' <<< "$out"; then bad "no shell error line in the output ($out)"; else ok "no shell error line in the output"; fi

fresh
rmdir "$D/scripts"
yml <<'M'
x
M
run
expect "a root with no scripts/ directory exits 2" 2 "$rc"

out=$(bash "$SCRIPT" "$T/not-a-dir" 2>&1); rc=$?
expect "a nonexistent root exits 2" 2 "$rc"
contains "not a directory" "$out" "and stderr says it is not a directory"

printf 'x\n' > "$T/a-file"
out=$(bash "$SCRIPT" "$T/a-file" 2>&1); rc=$?
expect "a root that is a file exits 2" 2 "$rc"
contains "not a directory" "$out" "and stderr says it is not a directory"

echo "== outside a git checkout =="
D="$T/plain"; mkdir -p "$D/scripts" "$D/.github/workflows"
printf 'x\n' > "$D/scripts/test-a.sh"
printf 'x\n' > "$D/scripts/test-b.py"
mkdir -p "$D/scripts/sub"; printf 'x\n' > "$D/scripts/sub/test-nested.sh"
printf 'x\n' > "$D/scripts/test-a.sh.bak"
yml <<'M'
  - run: bash scripts/test-a.sh
  - run: python3 scripts/test-b.py
M
run
expect "the walk fallback finds the suites and exits 0" 0 "$rc"
yml <<'M'
  - run: bash scripts/test-a.sh
M
run
expect "the walk fallback reports an unwired suite" 1 "$rc"
contains "scripts/test-b.py" "$out" "and names it"
lacks "nested" "$out" "the walk does not descend"
lacks ".bak" "$out" "the walk ignores a wrong extension"

# A symlinked suite is a suite on the walk path as in a checkout; a dangling link is not.
D="$T/plainlnk"; mkdir -p "$D/scripts" "$D/.github/workflows"
printf 'x\n' > "$D/scripts/test-a.sh"; printf 'x\n' > "$D/real-a.sh"
ln -s ../real-a.sh "$D/scripts/test-link.sh"
yml <<'M'
  - run: bash scripts/test-a.sh
M
run
expect "an unwired symlinked suite is reported on the walk path" 1 "$rc"
contains "  x scripts/test-link.sh" "$out" "and named"
ln -s ../nonexistent "$D/scripts/test-dangle.sh"
yml <<'M'
  - run: bash scripts/test-a.sh
  - run: bash scripts/test-link.sh
M
run
expect "a dangling symlink is not a suite" 0 "$rc"
lacks "test-dangle" "$out" "and appears nowhere in the output"

echo "== the root is resolved physically once =="
fresh test-a.sh test-b.sh
yml <<'M'
  - run: bash scripts/test-a.sh
M
out=$(cd "$D" && bash "$SCRIPT" . 2>&1); rc=$?
expect "a relative root finds the suites (checkout path)" 1 "$rc"
contains "scripts/test-b.sh" "$out" "and names the unwired one"
ln -s "$D" "$T/link$n"
out=$(bash "$SCRIPT" "$T/link$n" 2>&1); rc=$?
expect "a symlinked root finds the suites (checkout path)" 1 "$rc"
contains "scripts/test-b.sh" "$out" "and names the unwired one"
out=$(bash "$SCRIPT" "$D/scripts/.." 2>&1); rc=$?
expect "a root spelled with .. finds the suites" 1 "$rc"

mkdir -p "$T/plainrel/scripts" "$T/plainrel/.github/workflows"
printf 'x\n' > "$T/plainrel/scripts/test-a.sh"
printf '  - run: bash scripts/test-a.sh\n' > "$T/plainrel/.github/workflows/validate.yml"
out=$(cd "$T/plainrel" && bash "$SCRIPT" . 2>&1); rc=$?
expect "a relative root works on the walk path too" 0 "$rc"
ln -s "$T/plainrel" "$T/plainlink"
out=$(bash "$SCRIPT" "$T/plainlink" 2>&1); rc=$?
expect "a symlinked root works on the walk path too" 0 "$rc"

echo "== default root is the script's own checkout, not the cwd =="
out=$(cd "$T" && bash "$SCRIPT" 2>&1); rc=$?
expect "no argument from an unrelated cwd checks this repository" 0 "$rc"
contains "all wired" "$out" "and says so"

echo "== data is never evaluated =="
fresh 'test-$(touch PWNED1).sh' 'test-semi;touch PWNED2.sh' 'test-a b.sh'
yml <<M
  - run: bash scripts/test-\$(touch $T/PWNED3).sh
  - run: bash scripts/\$(touch $T/PWNED4)
  - run: bash scripts/\`touch $T/PWNED5\`
M
( cd "$D" && bash "$SCRIPT" "$D" >/dev/null 2>&1 )
rc=$?
expect "hostile names and lines still yield a defined exit code" 1 "$rc"
leftover=""
for p in "$D/PWNED1" "$D/PWNED2.sh" "$T/PWNED3" "$T/PWNED4" "$T/PWNED5"; do [ -e "$p" ] && leftover="$leftover $p"; done
expect "and nothing was executed" "" "$leftover"

echo "== this repository passes =="
# The regression case: every tracked suite here is wired, this guard's own included.
out=$(bash "$SCRIPT" "$REPO" 2>&1); rc=$?
expect "the real tree has every suite wired" 0 "$rc"

echo ""
echo "check-test-suites-wired tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
