#!/usr/bin/env bash
# Contract test for resolve-range-base.sh (#158).
#
# WHY THIS IS A SCRIPT AND NOT A YAML EXPRESSION. The obvious fix for #158 is to add `push` to the
# range guards' trigger and pass `github.event.before`. That is one line and it is wrong in two
# shapes the ticket names: `before` is the all-zeroes SHA when a ref is created, and it points at an
# object that may be unreachable after a force push. Both would make the guards pass VACUOUSLY,
# which leaves the claim true on paper and false in fact, and that is worse than the honest gap
# #158 describes.
#
# Driven against throwaway repos, because the subject is refs and reachability. Every case asserts
# either a resolvable base or a LOUD refusal; nothing here may quietly succeed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/scripts/resolve-range-base.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ZERO=0000000000000000000000000000000000000000

REPO="$T/repo"
git init --quiet -b main "$REPO"
( cd "$REPO"
  git config user.email t@t.invalid; git config user.name t
  printf 'one\n'   > f; git add f; git commit --quiet -m c1
  printf 'two\n'  >> f; git add f; git commit --quiet -m c2
  printf 'three\n'>> f; git add f; git commit --quiet -m c3
  git branch develop
) >/dev/null 2>&1
C1=$(cd "$REPO" && git rev-parse HEAD~2)
C2=$(cd "$REPO" && git rev-parse HEAD~1)

out=""; err=""; both=""; rc=0
# STREAMS ARE THE CONTRACT: the ref on stdout and nothing else, every explanation on stderr. A
# caller in CI substitutes stdout straight into a guard invocation, so a note leaking into it would
# be passed as a git rev.
run() {
  err="$(mktemp "$T/err.XXXXXX")"
  out=$(cd "$REPO" && env "$@" bash "$SRC" 2>"$err"); rc=$?
  err="$(cat "$err")"; both="$out
$err"
}

echo "== pull_request keeps the behaviour it already had =="
( cd "$REPO" && git update-ref refs/remotes/origin/main HEAD~1 ) 2>/dev/null
run EVENT_NAME=pull_request BASE_REF=main DEFAULT_BRANCH=main REF_NAME=feature
expect "a pull request resolves to origin/<base_ref>" 0 "$rc"
expect "and names it" "origin/main" "$out"

echo "== an ordinary push resolves to the previous tip =="
run EVENT_NAME=push BEFORE="$C2" DEFAULT_BRANCH=main REF_NAME=main
expect "an ordinary push resolves" 0 "$rc"
expect "to github.event.before" "$C2" "$out"

echo "== a created ref has no previous tip, and must not read as clean =="
# The all-zeroes SHA is what GitHub sends when a ref is created. Treating it as a base would make
# `git diff $ZERO...HEAD` fail, and treating a failure as "nothing changed" is the vacuous pass.
run EVENT_NAME=push BEFORE="$ZERO" DEFAULT_BRANCH=main REF_NAME=feature
expect "a created branch falls back to the default branch" 0 "$rc"
expect "which is a real, answerable range" "origin/main" "$out"

run EVENT_NAME=push BEFORE="$ZERO" DEFAULT_BRANCH=main REF_NAME=main
expect "creating the DEFAULT branch itself has no base and refuses" 2 "$rc"
contains "no base" "$err" "and says why"

echo "== a force push may have discarded the previous tip =="
# A SHA that does not resolve is the force-push case. Falling back to the default branch is not a
# vacuous pass: "does this branch bump what it changed against main" is the same question a pull
# request asks, and it is answerable.
run EVENT_NAME=push BEFORE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef DEFAULT_BRANCH=main REF_NAME=develop
expect "an unresolvable before falls back to the default branch" 0 "$rc"
expect "and names it" "origin/main" "$out"
contains "could not be resolved" "$err" "and says the fallback happened, loudly"

# Force-pushing the default branch is precisely when the check is most wanted and least available.
run EVENT_NAME=push BEFORE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef DEFAULT_BRANCH=main REF_NAME=main
expect "force-pushing the default branch refuses rather than passing" 2 "$rc"
contains "force" "$err" "and names the cause"

echo "== the fallback must exist to be used =="
( cd "$REPO" && git update-ref -d refs/remotes/origin/main ) 2>/dev/null
run EVENT_NAME=push BEFORE="$ZERO" DEFAULT_BRANCH=main REF_NAME=feature
expect "an absent fallback refuses rather than emitting an unusable ref" 2 "$rc"
( cd "$REPO" && git update-ref refs/remotes/origin/main "$C2" ) 2>/dev/null

echo "== streams: stdout carries the ref and nothing else =="
run EVENT_NAME=push BEFORE="$ZERO" DEFAULT_BRANCH=main REF_NAME=main
expect "a refusal writes NOTHING to stdout" "" "$out"
[ -n "$err" ] && ok "and explains itself on stderr" || bad "and explains itself on stderr"

# The fallback path both prints a ref AND explains. The explanation must not reach stdout, or CI
# would pass a sentence to git as a revision.
run EVENT_NAME=push BEFORE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef DEFAULT_BRANCH=main REF_NAME=develop
expect "a noisy success still writes only the ref to stdout" "origin/main" "$out"
contains "could not be resolved" "$err" "with the note on stderr"

echo "== usage =="
run EVENT_NAME=nonsense DEFAULT_BRANCH=main REF_NAME=main
expect "an unknown event refuses" 2 "$rc"

echo ""
echo "resolve-range-base tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
