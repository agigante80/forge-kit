#!/usr/bin/env bash
# Contract test for review-sizing/assets/size-review.sh (#278).
#
# The script decides whether a /full-review round runs all five phases or code-reviewer alone, so
# every wrong answer in one direction is a security-relevant change reviewed without the security
# phase. The cases pin each of the nine rules at its edge, and the precedence between them, in
# throwaway repos where the diff IS the input. STREAMS ARE THE CONTRACT: one line on stdout and
# exit 0, or nothing on stdout and exit 2.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-review/skills/review-sizing/assets/size-review.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REPO="$T/repo"

# fresh: a repo whose `base` tag is one commit holding a seed file; changes go in a second commit.
fresh() {
  rm -rf "$REPO"; git init --quiet -b main "$REPO"
  ( cd "$REPO"; git config user.email t@t.invalid; git config user.name t
    printf 'seed\n' > seed; git add seed; git commit --quiet -m base; git tag base ) >/dev/null 2>&1
}
# lines <path> <n>: a new text file of n lines.
lines() { mkdir -p "$REPO/$(dirname "$1")"; seq 1 "$2" > "$REPO/$1"; }
commit() { ( cd "$REPO"; git add -A; git commit --quiet -m change ) >/dev/null 2>&1; }
sens() { printf '%b' "$1" > "$REPO/sensitive"; }

out=""; err=""; rc=0
run() {
  out=$(cd "$REPO" && bash "$SRC" "$@" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
}
one() { expect "$1" "$2" "$out"; expect "$1: exit 0" 0 "$rc"; }

echo "== size decides when nothing sensitive is touched =="
fresh; for i in 1 2 3 4 5; do lines "f$i" 60; done; commit; sens ''
run --base base --sensitive-file sensitive
one "5 files and 300 lines is exactly at both thresholds" "scoped: 5 files, 300 lines, no sensitive path"
fresh; for i in 1 2 3 4 5 6; do lines "f$i" 20; done; commit; sens ''
run --base base --sensitive-file sensitive
one "6 files is one over the file threshold" "full: 6 files exceeds 5"
fresh; for i in 1 2 3 4; do lines "f$i" 60; done; lines f5 61; commit; sens ''
run --base base --sensitive-file sensitive
one "301 lines is one over the line threshold" "full: 301 lines exceeds 300"
fresh; commit; sens ''
run --base base --sensitive-file sensitive
one "an empty range is scoped" "scoped: 0 files, 0 lines, no sensitive path"
fresh; lines a.txt 5; lines b.txt 5; commit; sens ''
run --base base --sensitive-file sensitive
one "2 text files and 10 lines" "scoped: 2 files, 10 lines, no sensitive path"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && ok "stdout is exactly one line" || bad "stdout is exactly one line"

echo "== a sensitive path forces full =="
fresh; lines docs/x.md 3; commit; sens 'plugins/*/hooks/*\n'
run --base base --sensitive-file sensitive
one "a file outside the declared pattern is scoped" "scoped: 1 files, 3 lines, no sensitive path"
fresh; lines plugins/forge-kit-governance/hooks/block-dashes.py 3; commit
( cd "$REPO"; git tag base -f; mkdir -p scripts
  git mv plugins/forge-kit-governance/hooks/block-dashes.py scripts/block-dashes.py
  git commit --quiet -m move ) >/dev/null 2>&1
sens 'plugins/*/hooks/*\n'
run --base base --sensitive-file sensitive
one "a rename OUT of a sensitive directory still matches on its old side" \
  "full: sensitive path plugins/forge-kit-governance/hooks/block-dashes.py"
fresh; lines plugins/g/hooks/deep/x.py 1; commit; sens 'plugins/*/hooks/*\n'
run --base base --sensitive-file sensitive
one "a pattern's * crosses / (the #112 trap in reverse, stated in the skill)" "full: sensitive path plugins/g/hooks/deep/x.py"
fresh; lines plugins/g/hooks/x.py 1; commit; sens '# a comment\n\n   plugins/*/hooks/*   \n'
run --base base --sensitive-file sensitive
one "comments and blank lines are ignored and a pattern is trimmed" "full: sensitive path plugins/g/hooks/x.py"
fresh; lines plugins/g/hooks/x.py 1; commit; sens '# plugins/*/hooks/*\n\n'
run --base base --sensitive-file sensitive
one "a commented-out pattern declares nothing" "scoped: 1 files, 1 lines, no sensitive path"

# A comment read as a pattern can only match a path that itself starts with #, so that is the path.
fresh; lines '#x' 1; commit; sens '#*\n'
run --base base --sensitive-file sensitive
one "a comment line is never a pattern" "scoped: 1 files, 1 lines, no sensitive path"
# Both sides of a rename count, which is what --no-renames buys; with rename detection on, -z emits
# a three-field record and the old path would count once, or not parse at all.
fresh; lines docs/a.md 3; commit
( cd "$REPO"; git tag base -f; git mv docs/a.md docs/b.md; git commit --quiet -m move ) >/dev/null 2>&1
sens ''
run --base base --sensitive-file sensitive
one "a rename counts as both of its paths" "scoped: 2 files, 6 lines, no sensitive path"

echo "== the sensitive-path file: missing is full, empty is a declaration =="
fresh; lines a 1; commit
run --base base --sensitive-file nope
one "a missing file is the fail-safe full" "full: no sensitive-path set declared (nope)"
sens ''
run --base base --sensitive-file sensitive
one "an empty file declares nothing sensitive" "scoped: 1 files, 1 lines, no sensitive path"
run --base base
one "the default file name is .full-review-sensitive" "full: no sensitive-path set declared (.full-review-sensitive)"

echo "== an unreadable line count is never small =="
fresh; lines a.txt 5; lines b.txt 5; printf '\000\001\002' > "$REPO/img.png"; commit; sens ''
run --base base --sensitive-file sensitive
one "a binary file forces full" "full: unknown line count in img.png"

echo "== the previous round decides which phases return =="
fresh; lines a 4; commit; sens ''
run --base base --sensitive-file sensitive --prior-finders 1A
one "only code-reviewer found something" "scoped: 1 files, 4 lines, no sensitive path"
run --base base --sensitive-file sensitive --prior-finders 1A,2A
one "the security phase found something" "full: prior-round finding from 2A"
run --base base --sensitive-file sensitive --prior-finders unknown
one "no prior report is never small" "full: prior-round finding from unknown"

echo "== precedence =="
fresh; lines plugins/forge-kit-governance/hooks/block-dashes.py 3; commit; sens 'plugins/*/hooks/*\n'
run --base base --sensitive-file sensitive --full
one "--full outranks a sensitive path" "full: forced by --full"
fresh; lines docs/x.md 3; commit; sens 'plugins/*/hooks/*\n'
run --base base --sensitive-file sensitive --full
one "--full outranks a small range" "full: forced by --full"
run --base base --sensitive-file sensitive
one "the same range without flags is scoped" "scoped: 1 files, 3 lines, no sensitive path"
run --base base --sensitive-file sensitive --unattended
one "--unattended outranks a small range" "full: unattended caller"
run --base no-such-ref --full
one "--full decides without touching a bad base" "full: forced by --full"
run --base no-such-ref --unattended
one "--unattended decides without touching a bad base" "full: unattended caller"
run --sensitive-file sensitive
one "no --base is an unmeasurable target" "full: unmeasurable target"
run --base no-such-ref
expect "a bad base refuses before a missing sensitive file is read" 2 "$rc"

echo "== a range that cannot be measured refuses =="
fresh; lines a 1; commit; sens ''
run --base no-such-ref --sensitive-file sensitive
expect "an unresolvable base exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "no-such-ref" "$err" "and names the ref on stderr"
run --bogus
expect "an unknown argument exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
run --base
expect "a flag with no value exits 2" 2 "$rc"

echo ""
echo "size-review tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
