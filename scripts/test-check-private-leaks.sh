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

echo "== a list INSIDE the repository is the disclosure it exists to prevent =="
# The precondition #99 wanted forge-adapt to enforce, enforced where it can actually be checked.
# The default list path is under the home directory and can never be tracked by a project repo, so
# a project .gitignore entry would guard nothing. Pointing --list at a path in the repo can.
TRACKED="$WORK/repo/names.txt"
printf 'acme-migration\n' > "$TRACKED"
( cd "$WORK/repo" && git add names.txt ) >/dev/null 2>&1
printf 'the acme-migration repo\n' > "$WORK/repo/hit.md"
( cd "$WORK/repo" && "$SCRIPT" --list names.txt hit.md ) >/dev/null 2>"$WORK/err.txt"
expect "a TRACKED list refuses the run" 2 "$?"
contains "tracked" "$(cat "$WORK/err.txt")" "and says the list is tracked"
contains "git rm --cached" "$(cat "$WORK/err.txt")" "and says exactly how to fix it"
( cd "$WORK/repo" && git rm -q --cached names.txt ) >/dev/null 2>&1
( cd "$WORK/repo" && "$SCRIPT" --list names.txt hit.md ) >/dev/null 2>&1
expect "an untracked list in the same directory is fine" 1 "$?"

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
# The list must hold a token the script ACTUALLY contains, or this passes with the self-skip
# deleted. "private-name" is the rule label the script prints, so it is in its own source.
printf 'acme-migration\nprivate-name\n' > "$WORK/selfhit-list"
grep -qF 'private-name' "$SCRIPT" && ok "the self-skip case uses a token the script contains" \
  || bad "the self-skip case uses a token the script contains"
"$SCRIPT" --list "$WORK/selfhit-list" "$SCRIPT" >/dev/null 2>&1
expect "the scanner never reports itself" 0 "$?"
# ...including in --staged, where the file being read is a temp blob rather than the script.
SELFREPO="$WORK/selfrepo"; mkdir -p "$SELFREPO/scripts"
( cd "$SELFREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t
  printf 'x\n' > seed.md && git add seed.md && git commit -qm seed ) >/dev/null 2>&1
cp "$SCRIPT" "$SELFREPO/scripts/check-private-leaks.sh"
printf 'acme-migration\nnorthstar\nprivate-name\n' > "$WORK/selflist"
( cd "$SELFREPO" && git add scripts \
  && ./scripts/check-private-leaks.sh --list "$WORK/selflist" --staged ) >/dev/null 2>&1
expect "--staged does not report the scanner's own source" 0 "$?"

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

echo "== --help states the scanner's own reach =="
# The generic --help checks for this asset (synopsis, exit contract, no hardcoded line range) live
# in the public suite's loop and are not repeated here. This section pins what is this scanner's
# own statement about itself: the grep -a sentence #198 added, by its shared core (#199), and the
# history limit with its pointer past it (#200), each needle occurring exactly once in --help.
h="$("$SCRIPT" --help 2>&1)"
contains 'pass `grep -a` over a `git cat-file --batch` stream' "$h" \
  "check-private-leaks.sh --help states the grep -a rule for scanning the store by hand"
# #191 replaced the "never looks at history" limit with the opt-in mode; these pin what the header
# now claims: the tree modes still never look, --history reads the publishable history, it redacts
# names inside the path, and it is never a hook.
contains 'tree modes never look at history' "$h" "check-private-leaks.sh --help states that the tree modes never look at history"
contains 'reads the publishable history' "$h" "check-private-leaks.sh --help states what --history reads"
contains 'redacted inside the printed PATH' "$h" "check-private-leaks.sh --help states that names in a path are redacted"
contains 'never wired into a hook' "$h" "check-private-leaks.sh --help states that --history is never a hook"


echo "== --history: names in the publishable history, redacted in path and evidence =="
HREPO=""
mkrepo() {  # mkrepo <name>: a fresh repository; sets HREPO
  HREPO="$WORK/hist-$1"; rm -rf "$HREPO"; mkdir -p "$HREPO"
  ( cd "$HREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t \
    && printf 'seed\n' > seed.md && git add seed.md && git commit -qm seed ) >/dev/null 2>&1
}
hrun() {  # hrun [flags]: output in OUT, stderr in ERR, exit code in RC (variables, not echo: a
          # caller's $(...) would run this in a subshell and lose OUT)
  OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist" "$@" 2>"$WORK/herr.txt" )"; RC=$?; ERR="$(cat "$WORK/herr.txt")"
}
hoid() { ( cd "$HREPO" && git rev-parse "$1" ); }
printf 'secretproj\n' > "$WORK/hlist"

mkrepo names
( cd "$HREPO" && printf 'work on secretproj today\n' > notes.md && git add notes.md && git commit -qm add \
  && git rm -q notes.md && git commit -qm remove ) >/dev/null 2>&1
hrun --all; rc=$RC;     expect "a name committed then deleted is invisible to --all" 0 "$rc"
hrun --history; rc=$RC; expect "and --history finds it" 1 "$rc"
contains "notes.md@$(hoid HEAD~1:notes.md):1: private-name: se********" "$OUT" "at <path>@<oid>:<line>, redacted"
hrun --history --show-names; rc=$RC; expect "--show-names still reports" 1 "$rc"
contains "notes.md@$(hoid HEAD~1:notes.md):1: private-name: secretproj" "$OUT" "the name whole"

mkrepo inpath
( cd "$HREPO" && mkdir -p clients/secretproj && printf 'about SecretProj\n' > clients/secretproj/notes.md \
  && git add clients && git commit -qm add ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a name inside the PATH is reported" 1 "$rc"
contains "clients/se********/notes.md@$(hoid HEAD:clients/secretproj/notes.md):1: private-name: Se********" "$OUT" "and redacted in the path as well as the evidence"
hrun --history --show-names; rc=$RC
contains "clients/secretproj/notes.md@" "$OUT" "--show-names lifts the path redaction too"

mkrepo message
( cd "$HREPO" && git commit -q --allow-empty --author='secretproj bot <bot@t.invalid>' -m 'clean subject' -m 'clean body' ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a listed name on the author line is not reported" 0 "$rc"
( cd "$HREPO" && git commit -q --allow-empty -m 'mention secretproj here' ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a listed name in a commit message is reported" 1 "$rc"
contains "commit@$(hoid HEAD):" "$OUT" "as commit@<oid>"

mkrepo orphan
( cd "$HREPO" && printf 'secretproj\n' > oops.md && git add oops.md && git commit -qm oops \
  && git rm -q oops.md && git commit -q --amend --allow-empty -m fixed ) >/dev/null 2>&1
hrun --history; rc=$RC;           expect "an amended-away name is not in the publishable set" 0 "$rc"
hrun --history --orphans; rc=$RC; expect "--orphans reaches it" 1 "$rc"
contains "blob@" "$OUT" "labelled blob@<oid>"

mkrepo shared-src
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n ) >/dev/null 2>&1
git clone -q --shared "$HREPO" "$WORK/hist-shared" >/dev/null 2>&1
HREPO="$WORK/hist-shared"
hrun --history; rc=$RC; expect "a --shared clone is refused" 2 "$rc"
contains "alternates" "$ERR" "naming the alternates file"
hrun --history n.md; rc=$RC; expect "--history with a path is refused" 2 "$rc"
hrun --orphans; rc=$RC;        expect "--orphans without --history is refused" 2 "$rc"

echo "== --history: the mutant proves the byte counting is load-bearing =="
mkrepo forged
( cd "$HREPO" && printf '0000000000000000000000000000000000000000 blob 999999\nsecretproj\n' > forged.md && git add forged.md && git commit -qm forged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "the name after a forged header is reported" 1 "$rc"
contains "forged.md@$(hoid HEAD:forged.md):2:" "$OUT" "at line 2"
MUT="$WORK/mutant-private.sh"
sed 's/^r < 0 {$/NF == 3 \&\& length($1) == 40 \&\& $3 ~ \/^[0-9]+$\/ {/' "$SCRIPT" > "$MUT"; chmod +x "$MUT"
grep -q '^r < 0 {$' "$MUT" && bad "the mutant no longer carries the r<0 gate" || ok "the mutant no longer carries the r<0 gate"
( cd "$HREPO" && "$MUT" --list "$WORK/hlist" --history ) >/dev/null 2>&1
expect "the mutant misses the name (exit 0)" 0 "$?"

echo "== --init writes the list template, and never over an existing list =="
# The template lives INSIDE the script rather than beside it as a .txt. forge-adapt installs a
# skill's `assets/*.sh` and nothing else, so a separate template file would never reach a project,
# and the user would be told to copy a file that was not installed. One asset, one marker, and no
# second copy of the same text to drift.
TEMPLATE="$WORK/new-list.txt"
"$SCRIPT" --init --list "$TEMPLATE" >/dev/null 2>&1
expect "--init exits 0" 0 "$?"
[ -f "$TEMPLATE" ] && ok "and writes the file" || bad "and writes the file"
contains "owning account" "$(cat "$TEMPLATE" 2>/dev/null)" "it warns off the owning account name"
contains "untracked" "$(cat "$TEMPLATE" 2>/dev/null)" "it says the list stays untracked"
printf 'mine\n' > "$TEMPLATE"
"$SCRIPT" --init --list "$TEMPLATE" >/dev/null 2>&1
expect "--init refuses to overwrite an existing list" 2 "$?"
expect "and leaves it untouched" "mine" "$(cat "$TEMPLATE")"

echo ""
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
