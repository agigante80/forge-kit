#!/usr/bin/env bash
# Contract test for check-private-leaks.sh, the identity half of the leak guard (#156, from #99).
#
# WHY NO REAL PRIVATE NAME IS EVER NEEDED TO TEST THIS. The whole point of the component is that
# the list of names lives outside the repository, so a suite that needed one to run would have to
# put one in the repository. Every case here builds a throwaway list in a temp directory.
#
# THE THREE CASES THAT ARE THE REASON THIS IS A SCRIPT AND NOT PROSE. A missing list must exit 0
# and say so, because a guard that blocks every fresh clone gets uninstalled. The owning account's
# name must be dropped with a warning, because it is in the repository's own clone URL and a list
# containing it refuses every commit that touches the README. And a two-character entry must refuse
# the run, because it matches nearly every file and turns the guard into noise its owner then
# switches off. All three fail in the direction of the guard being REMOVED, which is the only
# failure mode that matters for something nobody is forced to keep.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh"
TEMPLATE="$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/private-names.txt.template"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0; failed=0
ok()  { printf '  ok: %s\n' "$1"; passed=$((passed+1)); }
bad() { printf '  FAIL: %s\n' "$1"; failed=$((failed+1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# Case insensitive: the assertion is that the reason was ANNOUNCED, not how it was capitalised.
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in '$2')"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

cat > "$WORK/list" <<'LIST'
# one name per line; comments and blanks ignored

acme-migration
NorthStar
LIST

OUT=""; ERR=""
# scan_line <content> [flags...] -> echoes exit code, sets OUT and ERR
scan_line() {
  local content="$1"; shift
  printf '%s\n' "$content" > "$WORK/sample.txt"
  OUT="$("$SCRIPT" --list "$WORK/list" "$@" "$WORK/sample.txt" 2>"$WORK/err.txt")"
  local rc=$?; ERR="$(cat "$WORK/err.txt")"; echo $rc
}
trips() { local rc; rc="$(scan_line "$@")"; [ "$rc" = "1" ] && echo yes || echo no; }

echo "== matching =="
expect "a listed name is found"                yes "$(trips 'see the acme-migration repo')"
expect "matching is case insensitive"          yes "$(trips 'see the ACME-Migration repo')"
expect "a name embedded in a path is found"    yes "$(trips '/srv/northstar/build.log')"
expect "an unlisted name is not found"         no  "$(trips 'see the public-thing repo')"
expect "a comment in the list is not a name"   no  "$(trips 'one name per line')"

echo "== the report redacts what it found =="
printf 'x\nthe acme-migration repo\n' > "$WORK/sample.txt"
OUT="$("$SCRIPT" --list "$WORK/list" "$WORK/sample.txt" 2>/dev/null)"
expect "a finding exits 1" 1 "$?"
expect "the report names file, line, rule and a REDACTED name" \
  "$WORK/sample.txt:2: private-name: ac************" "$OUT"
OUT="$("$SCRIPT" --list "$WORK/list" --show-names "$WORK/sample.txt" 2>/dev/null)"
expect "--show-names prints it in full" \
  "$WORK/sample.txt:2: private-name: acme-migration" "$OUT"

echo "== the list is absent, which must not block anyone =="
"$SCRIPT" --list "$WORK/no-such-list" "$WORK/sample.txt" >/dev/null 2>"$WORK/err.txt"
expect "an absent list exits 0" 0 "$?"
contains "no private-name list" "$(cat "$WORK/err.txt")" "and says so, loudly, on stderr"

echo "== list entries that would make the guard useless =="
printf 'ab\n' > "$WORK/short-list"
"$SCRIPT" --list "$WORK/short-list" "$WORK/sample.txt" >/dev/null 2>"$WORK/err.txt"
expect "a two-character entry refuses the run" 2 "$?"
contains "too short" "$(cat "$WORK/err.txt")" "and explains why"

echo "== the owning account name is dropped, not obeyed =="
REPO="$WORK/repo"; mkdir -p "$REPO"
( cd "$REPO"
  git init -q .
  git config user.email t@t.invalid && git config user.name t
  git remote add origin https://github.com/acmeowner/forge-thing.git
) >/dev/null 2>&1
printf 'acmeowner\nacme-migration\n' > "$WORK/owner-list"
printf 'clone from github.com/acmeowner/forge-thing\n' > "$REPO/README.md"
OUT="$( cd "$REPO" && "$SCRIPT" --list "$WORK/owner-list" README.md 2>"$WORK/err.txt" )"
expect "the owner name does not fire on the README" 0 "$?"
contains "owning account" "$(cat "$WORK/err.txt")" "and the drop is announced on stderr"
printf 'the acme-migration repo\n' > "$REPO/other.md"
( cd "$REPO" && "$SCRIPT" --list "$WORK/owner-list" other.md ) >/dev/null 2>&1
expect "the rest of the list still works" 1 "$?"

echo "== what is not scanned =="
printf 'acme-migration\n' > "$WORK/skipme.png"
"$SCRIPT" --list "$WORK/list" "$WORK/skipme.png" >/dev/null 2>&1
expect "a binary suffix is skipped" 0 "$?"
printf 'acme-migration\n' > "$WORK/yarn.lock"
"$SCRIPT" --list "$WORK/list" "$WORK/yarn.lock" >/dev/null 2>&1
expect "a lockfile is skipped" 0 "$?"
printf 'acme-migration\n\000\000bin\n' > "$WORK/blob.dat"
"$SCRIPT" --list "$WORK/list" "$WORK/blob.dat" >/dev/null 2>"$WORK/err.txt"
expect "a null-byte file is treated as binary and skipped" 0 "$?"
expect "and it produces no stderr warnings" "" "$(cat "$WORK/err.txt")"
"$SCRIPT" --list "$WORK/list" "$SCRIPT" >/dev/null 2>&1
expect "the scanner never reports itself" 0 "$?"

echo "== git modes =="
# A SECOND repo, whose tracked content is clean. The owner repo above deliberately holds a tracked
# hit, which would make "--all ignores an untracked file" pass for the wrong reason.
REPO="$WORK/repo2"; mkdir -p "$REPO"
( cd "$REPO"
  git init -q . && git config user.email t@t.invalid && git config user.name t
  printf 'clean\n' > tracked.md && git add tracked.md && git commit -qm base
) >/dev/null 2>&1
BASE="$(cd "$REPO" && git rev-parse HEAD)"
printf 'the acme-migration repo\n' > "$REPO/untracked.md"
( cd "$REPO" && "$SCRIPT" --list "$WORK/list" --all ) >/dev/null 2>&1
expect "--all ignores an untracked file" 0 "$?"
( cd "$REPO" && git add untracked.md && "$SCRIPT" --list "$WORK/list" --staged ) >/dev/null 2>&1
expect "--staged reports staged content" 1 "$?"
( cd "$REPO" && git commit -qm add >/dev/null )
( cd "$REPO" && "$SCRIPT" --list "$WORK/list" --all ) >/dev/null 2>&1
expect "--all reports it once committed" 1 "$?"
( cd "$REPO" && "$SCRIPT" --list "$WORK/list" --range "$BASE" ) >/dev/null 2>&1
expect "--range reports a file changed since the base" 1 "$?"
( cd "$REPO" && "$SCRIPT" --list "$WORK/list" --range HEAD ) >/dev/null 2>&1
expect "--range over an empty range is clean" 0 "$?"
( cd "$REPO" && "$SCRIPT" --list "$WORK/list" --range deadbeefdeadbeefdeadbeefdeadbeefdeadbeef ) >/dev/null 2>&1
expect "--range refuses a base ref that does not exist" 2 "$?"
"$SCRIPT" --nonsense "$WORK/sample.txt" >/dev/null 2>&1
expect "an unknown flag refuses the run" 2 "$?"

echo "== the shipped asset is a component =="
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SCRIPT" \
  && ok "carries a version marker" || bad "carries a version marker"

echo "== the list template carries both hard-won rules =="
[ -f "$TEMPLATE" ] && ok "a list template ships" || bad "a list template ships"
if [ -f "$TEMPLATE" ]; then
  grep -qi 'owning account\|account name that owns' "$TEMPLATE" \
    && ok "it warns off the owning account name" || bad "it warns off the owning account name"
  grep -qi 'untracked\|never be committed\|not tracked' "$TEMPLATE" \
    && ok "it says the list stays untracked" || bad "it says the list stays untracked"
fi

echo ""
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
