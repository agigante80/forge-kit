#!/usr/bin/env bash
# Contract test for check-private-leaks.sh, the identity half of the leak guard (#156, from #99).
#
# WHY NO REAL PRIVATE NAME IS EVER NEEDED TO TEST THIS. The whole point of the component is that
# the list of names lives outside the repository, so a suite that needed one to run would have to
# put one in the repository. Every case here builds a throwaway list in a temp directory.
#
# THE THREE CASES THAT ARE THE REASON THIS IS A SCRIPT AND NOT PROSE. A missing list must exit 0
# and say so, because a guard that blocks every fresh clone gets uninstalled. The owning account's
# name must be dropped with a warning when origin is a PUBLIC forge and the mode is a tree mode,
# because there it is in the public clone URL and a list containing it refuses every commit that
# touches the README (#209: on a private origin, and under --history, the list is obeyed). And a two-character entry must refuse
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
lacks()    { if grep -qF -- "$1" <<< "$2"; then bad "$3 (found '$1')"; else ok "$3"; fi; }
contains() { if grep -qiF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in '$2')"; fi; }

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

echo "== the allow-file skips paths, honouring only skip (Task 3, forge-kit) =="
# Same .leak-guard-allow the public half reads. This half honours only `skip`; root/prefix/email
# are the public half's keys and must be ignored here rather than refused, so one file serves both.
cat > "$WORK/allow" <<'ALLOW'
# comment lines and blank lines are ignored

root ~/forge-kit
prefix /home/runner/
email a.gigante@gmail.com
skip pnpm-lock.yaml
ALLOW
ALLOWREPO="$WORK/allow-repo"; mkdir -p "$ALLOWREPO"
( cd "$ALLOWREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t
  printf 'acme-migration@1.2.3\n' > pnpm-lock.yaml
  printf 'the acme-migration repo\n' > leak.md
  git add -A && git commit -qm seed ) >/dev/null 2>&1
OUT="$( cd "$ALLOWREPO" && "$SCRIPT" --list "$WORK/list" --all --allow-file "$WORK/allow" 2>"$WORK/err.txt" )"; rc=$?
lacks "pnpm-lock.yaml" "$OUT" "a skip <glob> path is not reported"
contains "leak.md" "$OUT" "an unskipped finding is still reported"
expect "and the run exits 1 on the surviving finding" 1 "$rc"
expect "root/prefix/email are ignored rather than refused: no stderr" "" "$(cat "$WORK/err.txt")"

printf 'x\n' > "$WORK/sample2.txt"
"$SCRIPT" --list "$WORK/list" --allow-file "$WORK/no-such-allow" "$WORK/sample2.txt" >/dev/null 2>"$WORK/err.txt"
expect "a missing allow-file dies rather than scanning" 2 "$?"
contains "allow-file not found" "$(cat "$WORK/err.txt")" "and the message says so"

printf 'bogus key\n' > "$WORK/bad-allow"
"$SCRIPT" --list "$WORK/list" --allow-file "$WORK/bad-allow" "$WORK/sample2.txt" >/dev/null 2>"$WORK/err.txt"
expect "an unknown allow-file key refuses the run" 2 "$?"
contains "unknown key" "$(cat "$WORK/err.txt")" "and names the offending key"

cat > "$WORK/blank-allow" <<'ALLOW2'
# just a comment


skip pnpm-lock.yaml
ALLOW2
OUT="$( cd "$ALLOWREPO" && "$SCRIPT" --list "$WORK/list" --all --allow-file "$WORK/blank-allow" 2>"$WORK/err.txt" )"; rc=$?
lacks "pnpm-lock.yaml" "$OUT" "comment and blank lines in the allow-file are ignored, and skip still applies"
expect "and it still exits 1 on the remaining finding" 1 "$rc"
expect "with no stderr complaint about the comment or blank lines" "" "$(cat "$WORK/err.txt")"

"$SCRIPT" --list "$WORK/list" --allow-file >/dev/null 2>"$WORK/err.txt"
expect "--allow-file as the last argument dies rather than silently no-opping" 2 "$?"
contains "needs a path" "$(cat "$WORK/err.txt")" "and says so"

echo "== allow-file and name-list trims use one ASCII byte list in every locale (#403) =="
# A `[[:space:]]` trim followed the caller's locale: under UTF-8 it took an edge U+2003 off a `skip`
# glob, and off a list name, which then matched differently by locale. Now the allow-file keeps the
# character (the C verdict), and a list name carrying a non-ASCII space at an edge is refused.
utf8loc=""
for l in $(locale -a 2>/dev/null); do
  [ "$(LC_ALL=$l locale charmap 2>/dev/null)" = UTF-8 ] && { utf8loc=$l; break; }
done
EMSP=$'\xe2\x80\x83'
# trim_mutant <unique fragment of the target line> <out>: restore `[[:space:]]` on that line only.
# Echoes how many lines it changed, so the ledger proves the sed hit exactly one site.
BL="[!\$' \\t\\n\\v\\f\\r']"
trim_mutant() {
  local l hits=0
  while IFS= read -r l || [ -n "$l" ]; do
    if [[ "$l" == *"$1"* && "$l" == *"$BL"* ]]; then l="${l//"$BL"/[![:space:]]}"; hits=$((hits+1)); fi
    printf '%s\n' "$l"
  done < "$SCRIPT" > "$2"; chmod +x "$2"; echo "$hits"
}
# arow <allow line> <script> <locale> -> "rc|leak.md reported?" for a --all run over ALLOWREPO
arow() {
  printf '%s\n' "$1" > "$WORK/t403-allow"
  local out rc
  out="$( cd "$ALLOWREPO" && LC_ALL=$3 "$2" --list "$WORK/list" --all --allow-file "$WORK/t403-allow" 2>"$WORK/err.txt" )"; rc=$?
  case "$out" in *leak.md*) echo "$rc|leak" ;; *) echo "$rc|-" ;; esac
}
# nrow <list content> <script> <locale> -> rc of a scan of one line naming acme-migration
nrow() {
  printf '%s\n' "$1" > "$WORK/t403-list"; printf 'see the acme-migration repo\n' > "$WORK/t403-s.txt"
  LC_ALL=$3 "$2" --list "$WORK/t403-list" "$WORK/t403-s.txt" >/dev/null 2>"$WORK/err.txt"; echo $?
}
locs="C"; [ -n "$utf8loc" ] && locs="C $utf8loc"
for L in $locs; do
  expect "allow 'skip leak.md<EMSP>' keeps the character, so leak.md is still reported under $L" "1|leak" "$(arow "skip leak.md$EMSP" "$SCRIPT" "$L")"
  expect "allow '<EMSP>skip leak.md' is an unknown key under $L" "2|-" "$(arow "${EMSP}skip leak.md" "$SCRIPT" "$L")"
  contains "unknown key" "$(cat "$WORK/err.txt")" "and names the unknown key under $L"
  expect "an allow line of only <EMSP> has no value under $L" "2|-" "$(arow "$EMSP" "$SCRIPT" "$L")"
  contains "entry has no value" "$(cat "$WORK/err.txt")" "and says so under $L"
  expect "an ASCII control row: '<TAB>skip leak.md<SPACE>' still parses and skips under $L" "0|-" "$(arow "$(printf '\tskip leak.md ')" "$SCRIPT" "$L")"
  for spec in "acme-migration$EMSP|trailing U+2003" "${EMSP}acme-migration|leading U+2003" "$EMSP|a line of only U+2003" \
              $'acme-migration\xc2\xa0|trailing U+00A0' $'\xe3\x80\x80acme-migration|leading U+3000'; do
    expect "list name with ${spec#*|} is refused under $L" 2 "$(nrow "${spec%|*}" "$SCRIPT" "$L")"
    contains "list:1: this name begins or ends with a non-ASCII whitespace" "$(cat "$WORK/err.txt")" "and the refusal names the line under $L (${spec#*|})"
    lacks "acme" "$(cat "$WORK/err.txt")" "and does not echo the name under $L (${spec#*|})"
  done
  expect "an ASCII control row: list '<TAB>acme-migration<SPACE>' still matches under $L" 1 "$(nrow "$(printf '\tacme-migration ')" "$SCRIPT" "$L")"
done
expect "a two-line list refuses at the U+2003-only line, not as a 3-byte name" 2 "$(nrow "$(printf 'acme-migration\n%s' "$EMSP")" "$SCRIPT" C)"
contains "list:2:" "$(cat "$WORK/err.txt")" "and names line 2"
# One mutant per site, each with a row that kills it alone.
M=$WORK/m403
expect "mutant ledger (#403): the allow leading trim is one line" 1 "$(trim_mutant 'line="${line#"' "$M-al.sh")"
expect "mutant ledger (#403): the allow trailing trim is one line" 1 "$(trim_mutant 'line="${line%"' "$M-at.sh")"
expect "mutant ledger (#403): the name leading trim is one line" 1 "$(trim_mutant 'n="${n#"' "$M-nl.sh")"
expect "mutant ledger (#403): the name trailing trim is one line" 1 "$(trim_mutant 'n="${n%"' "$M-nt.sh")"
# Refusal deleted: the for-loop over UNI_EDGE_WS through its own `  done`.
awk 'BEGIN{d=0} /for ws in "\$\{UNI_EDGE_WS\[@\]\}"/{d=1; next} d&&/^  done$/{d=0; next} d{next} {print}' < "$SCRIPT" > "$M-nr.sh"; chmod +x "$M-nr.sh"
cmp -s "$SCRIPT" "$M-nr.sh" && bad "mutant ledger (#403): the refusal-deleted mutant did not apply" || ok "mutant ledger (#403): the refusal-deleted mutant differs"
expect "mutant (#403, refusal deleted): a trailing-U+2003 name is kept and misses under C" 0 "$(nrow "acme-migration$EMSP" "$M-nr.sh" C)"
if [ -n "$utf8loc" ]; then
  expect "mutant (#403, allow leading trim): '<EMSP>skip leak.md' is accepted under $utf8loc" "0|-" "$(arow "${EMSP}skip leak.md" "$M-al.sh" "$utf8loc")"
  expect "mutant (#403, allow trailing trim): 'skip leak.md<EMSP>' skips leak.md under $utf8loc" "0|-" "$(arow "skip leak.md$EMSP" "$M-at.sh" "$utf8loc")"
  expect "mutant (#403, name leading trim): '<EMSP>acme-migration' is trimmed and matches under $utf8loc" 1 "$(nrow "${EMSP}acme-migration" "$M-nl.sh" "$utf8loc")"
  expect "mutant (#403, name trailing trim): 'acme-migration<EMSP>' is trimmed and matches under $utf8loc" 1 "$(nrow "acme-migration$EMSP" "$M-nt.sh" "$utf8loc")"
else
  ok "no UTF-8 locale installed on this machine: the #403 UTF-8 parity rows and trim mutants were not run"
fi

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
# ...and in --head, where the file is read as a HEAD blob (the public suite's twin is the "#375" case).
( cd "$SELFREPO" && git commit -qm add >/dev/null 2>&1 \
  && ./scripts/check-private-leaks.sh --list "$WORK/selflist" --head ) >/dev/null 2>&1
expect "--head does not report the scanner's own source (#375)" 0 "$?"

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
# MUTANTS RUN AGAINST THESE SECTIONS (2026-09-14), on a scratch copy, each confirmed applied. Killed:
# the r<0 gate replaced by a shape test (run below); path redaction disabled; evidence redaction
# disabled; the label split at the first @; path-only lines reported; the
# diffMerges override dropped; the unreadable-object refusal removed; the --orphans content test
# applied to every object; the longest-first sort removed. Re-run 2026-09-16 (#210): the
# enumeration reverted to --branches --tags --remotes (the refs/original case fails); the path map
# alone reverted (the pathmap case fails); --exclude placed after --all (the stash case fails). The reader and selection code is the public half's,
# whose suite carries the rest of the mutants.
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
# A name in the PATH is not itself a finding (the tree modes never report a path), so a three-line
# clean file under a listed directory reports nothing, and a one-hit file reports exactly one line.
( cd "$HREPO" && printf 'one\ntwo\nthree\n' > clients/secretproj/clean.md && printf 'a\nb secretproj\nc\n' > clients/secretproj/one.md \
  && git add clients && git commit -qm more ) >/dev/null 2>&1
hrun --history; rc=$RC
n="$(printf '%s\n' "$OUT" | grep -c 'clean.md@')";  expect "a clean file under a listed directory reports no line" 0 "$n"
n="$(printf '%s\n' "$OUT" | grep -c 'one.md@')";    expect "a file with one hit under it reports exactly one line" 1 "$n"
contains "clients/se********/one.md@$(hoid HEAD:clients/secretproj/one.md):2: private-name: se********" "$OUT" "at line 2, both redacted"
# npm-style scoped directories put an @ in the path; the oid follows the LAST @.
printf 'acme\n' > "$WORK/hlist2"
( cd "$HREPO" && mkdir -p packages/@acme/core && printf 'export const acme = 1\n' > packages/@acme/core/index.js && git add packages && git commit -qm scoped ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist2" --history 2>/dev/null )"; rc=$?
expect "a listed name under an @scope path is reported" 1 "$rc"
contains "packages/@ac**/core/index.js@$(hoid HEAD:packages/@acme/core/index.js):1: private-name: ac**" "$OUT" "with the name redacted in the path despite the @"
# A list holding a name and a longer name built on it: one finding per occurrence, the longer one,
# and the path redacts the whole longer name rather than leaking its suffix.
printf 'secret\nsecretproj\n' > "$WORK/hlist3"
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist3" --history 2>/dev/null )"; rc=$?
n="$(printf '%s\n' "$OUT" | grep -c 'one.md@')"; expect "nested names report one finding for one occurrence" 1 "$n"
contains "clients/se********/one.md@" "$OUT" "and the path redacts the longer name whole"
lacks() { if grep -qF -- "$1" <<< "$2"; then bad "$3 (found '$1')"; else ok "$3"; fi; }
lacks "se****proj" "$OUT" "never its suffix"

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

# Task 3 review: the allow-file's `skip` globs must reach history mode too, since the weekly
# sweep runs --history and a name permanently stuck in an old commit (a test fixture, a
# generated lockfile) has no OTHER way to be silenced without weakening the list itself.
# Neither file below is a lockfile skip_by_name already exempts, so a pass here proves the
# allow-file's SKIP_PATHS did the work, not the built-in lockfile list.
mkrepo history-skip
( cd "$HREPO" && printf 'secretproj\n' > fixture.txt && printf 'secretproj too\n' > other.md \
  && git add fixture.txt other.md && git commit -qm add \
  && git rm -q fixture.txt other.md && git commit -qm remove ) >/dev/null 2>&1
printf 'skip fixture.txt\n' > "$WORK/hskipallow"
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist" --history --allow-file "$WORK/hskipallow" 2>/dev/null )"; rc=$?
lacks "fixture.txt@" "$OUT" "a name in a skipped path from an OLD commit is not reported under --history --allow-file"
contains "other.md@" "$OUT" "the same name in an unskipped historical path is still reported"
expect "and the run exits 1 on the surviving finding" 1 "$rc"

echo "== --history: every ref a mirror push sends (#210) =="
# Mirrors the public suite's section with a listed name. The enumeration code is DUPLICATED from
# the public half, not shared (#206), so the public suite's mutants cannot see a regression in
# this file: the pathmap fixture below is what fails when this file's log -m line is reverted.
mkrepo original
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md && git commit -qm leak \
  && git update-ref refs/original/refs/heads/scrubbed HEAD && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
hrun --history; expect "a name reachable only from refs/original (a filter-branch backup) is reported" 1 "$RC"
contains "leak.md@" "$OUT" "at its path"
( cd "$HREPO" && git update-ref -d refs/original/refs/heads/scrubbed ) >/dev/null 2>&1
hrun --history; expect "with the backup ref deleted it is unreachable and not reported" 0 "$RC"
hrun --history --orphans; expect "and --orphans still reaches it" 1 "$RC"

mkrepo notes
( cd "$HREPO" && git notes add -m 'secretproj' HEAD ) >/dev/null 2>&1
hrun --history; expect "a name only in refs/notes/commits is reported" 1 "$RC"

mkrepo detached
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md && git commit -qm leak \
  && B="$(git symbolic-ref HEAD)" && git checkout -q --detach && git update-ref -d "$B" ) >/dev/null 2>&1
hrun --history; expect "a name reachable only from a detached HEAD is reported" 1 "$RC"

mkrepo blobref
( cd "$HREPO" && o="$(printf 'secretproj\n' | git hash-object -w --stdin)" && git update-ref refs/misc/raw "$o" ) >/dev/null 2>&1
hrun --history; expect "a ref pointing straight at a blob is reported" 1 "$RC"

mkrepo stash
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md && git stash push -q ) >/dev/null 2>&1
( cd "$HREPO" && git rev-parse -q --verify refs/stash >/dev/null ) && ok "the fixture holds a stash entry" || bad "the fixture holds a stash entry"
hrun --history; expect "a name only in refs/stash is not reported: no push sends it" 0 "$RC"
hrun --history --orphans; expect "--orphans reaches the stash" 1 "$RC"

# The path map must walk the same set: the blob's current name is skipped (.png) and only the
# refs/original walk knows it was once leak.md (review round 1 on #210: reverting this file's
# log -m line alone passed the suite until this case existed).
mkrepo pathmap
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md && git commit -qm leak \
  && git mv leak.md leak.png && git commit -qm png && git update-ref refs/original/refs/heads/scrubbed HEAD \
  && git reset -q --hard HEAD~2 ) >/dev/null 2>&1
hrun --history; expect "a blob skipped by its current name is read for its historical one, through refs/original" 1 "$RC"
contains "leak.md@" "$OUT" "at the historical path"
h="$("$SCRIPT" --help 2>&1)"
contains "filter-branch" "$h" "--help names filter-branch's refs/original"
contains "mirror" "$h" "and the mirror push"

mkrepo shared-src
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n ) >/dev/null 2>&1
git clone -q --shared "$HREPO" "$WORK/hist-shared" >/dev/null 2>&1
HREPO="$WORK/hist-shared"
hrun --history; rc=$RC; expect "a --shared clone is refused" 2 "$rc"
contains "alternates" "$ERR" "naming the alternates file"
hrun --history n.md; rc=$RC; expect "--history with a path is refused" 2 "$rc"
hrun --orphans; rc=$RC;        expect "--orphans without --history is refused" 2 "$rc"
hrun --history --staged; rc=$RC; expect "--history --staged is refused rather than scanning the index" 2 "$rc"
HREPO="$WORK/hist-shared-src"
OUT="$( cd "$HREPO" && GIT_ALTERNATE_OBJECT_DIRECTORIES=/nonexistent "$SCRIPT" --list "$WORK/hlist" --history 2>"$WORK/herr.txt" )"; rc=$?
expect "GIT_ALTERNATE_OBJECT_DIRECTORIES set is refused" 2 "$rc"
OUT="$( cd "$HREPO" && GIT_OBJECT_DIRECTORY="$WORK/hist-shared/.git/objects" "$SCRIPT" --list "$WORK/hlist" --history 2>"$WORK/herr.txt" )"; rc=$?
expect "GIT_OBJECT_DIRECTORY set is refused" 2 "$rc"
( cd "$HREPO" && git config uploadpack.allowFilter true )
git clone -q --filter=blob:none "file://$HREPO" "$WORK/hist-partial" >/dev/null 2>&1
HREPO="$WORK/hist-partial"
hrun --history; rc=$RC; expect "a partial clone is refused" 2 "$rc"
contains "partial clone" "$ERR" "and says so"
mkrepo selfid
( cd "$HREPO" && mkdir old && cp "$SCRIPT" old/check-private-leaks.sh && git add old && git commit -qm old ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a past copy of the scanner at another path is not reported (its source names the list)" 0 "$rc"
mkrepo replace
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n && leaky="$(git rev-parse HEAD)" \
  && git rm -q n.md && git commit -qm clean && git replace "$leaky" HEAD ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a commit hidden by git replace is still scanned" 1 "$rc"
# The same store shapes the public suite pins, mirrored here because the two scripts drift apart
# once forge-adapt copies one of them.
mkrepo p-corrupt
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n \
  && o="$(git rev-parse HEAD:n.md)" && f=".git/objects/${o:0:2}/${o:2}" && rm -f "$f" && printf 'garbage' > "$f" ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a corrupt loose object refuses the scan" 2 "$rc"
mkrepo p-remote
( cd "$HREPO" && git init -q --bare "$WORK/hist-pbare" && git remote add origin "$WORK/hist-pbare" \
  && git checkout -q -b wip && printf 'secretproj\n' > wip.md && git add wip.md && git commit -qm wip \
  && git push -q origin wip && { git checkout -q master 2>/dev/null || git checkout -q main; } && git branch -q -D wip ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a name on a branch deleted locally but pushed is reported" 1 "$rc"
mkrepo p-cfg
( cd "$HREPO" && printf 'base\n' > f.txt && git add f.txt && git commit -qm base && printf 'secretproj\n' > aaa.lock && git add aaa.lock && git commit -qm lock \
  && git checkout -q -b side && printf 'side\n' > f.txt && git commit -qam side \
  && { git checkout -q master 2>/dev/null || git checkout -q main; }; printf 'main\n' > f.txt && git commit -qam main
  git merge -q --no-commit side >/dev/null 2>&1; cp aaa.lock zzz.md; git add f.txt zzz.md && git commit -qm merged; git config log.diffMerges off ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "with log.diffMerges=off the merge-only twin is still reported" 1 "$rc"
mkrepo p-newline
( cd "$HREPO" && printf 'x\n' > "$(printf 'weird\nname.txt')" && git add . && git commit -qm weird ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a path containing a newline refuses the scan" 2 "$rc"
mkrepo p-widen
( cd "$HREPO" && printf '#!/usr/bin/env bash\n# check-private-leaks-version: 3\n#\nsecretproj\n' > quoting.md && git add quoting.md && git commit -qm q ) >/dev/null 2>&1
hrun --history --orphans; rc=$RC; expect "--orphans still reports a reachable document quoting the marker" 1 "$rc"
mkrepo p-bare
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n ) >/dev/null 2>&1
git clone -q --bare "$HREPO" "$WORK/hist-pbare2" >/dev/null 2>&1
HREPO="$WORK/hist-pbare2"
hrun --history; rc=$RC; expect "a bare repository is scanned" 1 "$rc"

echo "== --history: the mutant proves the byte counting is load-bearing =="
mkrepo forged
( cd "$HREPO" && printf '0000000000000000000000000000000000000000 blob 999999\nsecretproj\n' > forged.md && git add forged.md && git commit -qm forged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "the name after a forged header is reported" 1 "$rc"
contains "forged.md@$(hoid HEAD:forged.md):2:" "$OUT" "at line 2"
MUT="$WORK/mutant-private.sh"
. "$ROOT/scripts/mutant-crash.sh"
# pl_live: the build, run without --history on the same repository, still finds the name (#360).
pl_live() { local o; o="$( CDPATH= cd -- "$HREPO" && "$MUT" --list "$WORK/hlist" 2>/dev/null )"; case "$o" in *"forged.md:2:"*) return 0 ;; esac; return 1; }
# pl_mutant <label> <sed expr> [<gone pattern>]: the build must miss the name without crashing; a
# gone pattern is the applied check, a line of the script the edit must have removed.
pl_mutant() {
  local mout why
  sed "$2" "$SCRIPT" > "$MUT"; chmod +x "$MUT"
  if [ -n "${3:-}" ]; then
    grep -q -e "$3" "$MUT" && bad "the mutant no longer carries the r<0 gate" || ok "the mutant no longer carries the r<0 gate"
  fi
  mout="$( CDPATH= cd -- "$HREPO" && "$MUT" --list "$WORK/hlist" --history 2>"$WORK/pl-err.log" )"
  why=$(mutant_crash_reason "$MUT" "$WORK/pl-err.log" pl_live)
  if [ -n "$why" ]; then bad "mutant $1 crashed ($why)"
  elif [ -z "$mout" ]; then ok "the mutant misses the name (prints no finding)"
  else bad "the mutant misses the name (prints no finding) (got '$mout')"; fi
}
pl_mutant r-lt-0 's/^r < 0 {$/NF == 3 \&\& length($1) == 40 \&\& $3 ~ \/^[0-9]+$\/ {/' '^r < 0 {$'
# Crash control (#360): an exit 127 build is never a miss. pl_mutant runs in $( ), so its rows stay
# out of the total.
sed '1a\
exit 127' "$SCRIPT" > "$WORK/crash-private.sh"
crash_ok=1
cmp -s "$WORK/crash-private.sh" "$SCRIPT" && crash_ok=0
cap=$(pl_mutant crash-control '1a\
exit 127')
case "$cap" in *"misses the name"*) crash_ok=0 ;; *"FAIL: mutant crash-control crashed ("*) ;; *) crash_ok=0 ;; esac
[ "$crash_ok" = 1 ] && ok "crash control (#360): private-leaks reports a crashing mutant as crashed, never as a miss" \
  || bad "crash control (#360): private-leaks credited or missed a crashing mutant"


echo "== the tree modes fail closed (#208) =="
# MUTANTS RUN AGAINST THIS SECTION AND THE NEXT (2026-09-16), on a scratch copy, each confirmed
# applied. Killed: --no-renames dropped; T dropped from the diff filter; the unreadable-file check
# removed; the drop applied in --history; the host allowlist dropped; the port stripped before the
# userinfo; the scp form keeping user@ in the host; the warning printing the name whole.
mkrepo p-rename
( cd "$HREPO" && for i in $(seq 1 20); do echo "line $i"; done > a.md && git add a.md && git commit -qm twenty \
  && git mv a.md b.md && printf 'secretproj\n' >> b.md && git add b.md ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a renamed-and-edited file is reported by --staged" 1 "$rc"
contains "b.md:21: private-name: se********" "$OUT" "at its new name and line"
mkrepo p-type
( cd "$HREPO" && ln -s seed.md link.md && git add link.md && git commit -qm link && rm link.md && printf 'secretproj\n' > link.md && git add link.md ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a symlink replaced by a file naming a listed name is reported" 1 "$rc"
mkrepo p-gitlink
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md \
  && git update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,sub ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a staged gitlink beside a staged name: reported, never a refusal" 1 "$rc"
( cd "$HREPO" && c="$(git commit-tree -m 'secretproj in a message' "$(git write-tree)")" \
  && git update-index --add --cacheinfo 160000,"$c",present ) >/dev/null 2>&1
hrun --staged; rc=$RC; lacks "present:" "$OUT" "a gitlink whose commit is present is not scanned as a file"
mkrepo p-listshown
( cd "$HREPO" && printf 'secretproj\n' > n.md && git add n.md && git commit -qm n ) >/dev/null 2>&1
mkdir -p "$WORK/fakehome/.claude"; printf 'ab\n' > "$WORK/fakehome/.claude/short"
err="$( cd "$HREPO" && HOME="$WORK/fakehome" "$SCRIPT" --list "$WORK/fakehome/.claude/short" --all 2>&1 >/dev/null )"
contains "~/.claude/short:1:" "$err" "a message names the list under the home directory as ~ (bash 5 and 3.2 alike)"
lacks "$WORK/fakehome" "$err" "and never the expanded path"
mkrepo p-nowrite
( cd "$HREPO" && head -c 3000 /dev/zero | tr '\0' a > big.md && printf '\nsecretproj\n' >> big.md && git add big.md ) >/dev/null 2>&1
( cd "$HREPO" && ulimit -f 1 && "$SCRIPT" --list "$WORK/hlist" --staged </dev/null >"$WORK/pwout.txt" 2>"$WORK/pwerr.txt"; echo $? > "$WORK/pwrc.txt" ) 2>/dev/null
expect "a blob the scanner cannot write refuses --staged" 2 "$(cat "$WORK/pwrc.txt")"
contains "could not read big.md" "$(cat "$WORK/pwerr.txt")" "naming the file"
lacks "$ROOT" "$(cat "$WORK/pwerr.txt")" "and never the script's path"
mkrepo p-rangerename
( cd "$HREPO" && for i in $(seq 1 20); do echo "line $i"; done > a.md && git add a.md && git commit -qm twenty \
  && git mv a.md b.md && printf 'secretproj\n' >> b.md && git add b.md && git commit -qm renamed ) >/dev/null 2>&1
hrun --range HEAD~1; rc=$RC; expect "a renamed-and-edited file is reported by --range" 1 "$rc"
mkrepo p-symlink
( cd "$HREPO" && ln -s /srv/secretproj/data link && git add link && git commit -qm link ) >/dev/null 2>&1
hrun --all; rc=$RC; expect "a tracked symlink's text is scanned under --all" 1 "$rc"
mkrepo p-stage
( cd "$HREPO" && printf 'secretproj\n' > '0:x' && git add -- '0:x' ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a staged path shaped 0:x is reported" 1 "$rc"
contains "0:x:1:" "$OUT" "at its path"
mkrepo p-dashes
( cd "$HREPO" && printf 'secretproj\n' > ./-v && printf 'secretproj\n' > ./- && git add -- -v - && git commit -qm dashes ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist" --all </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "files named -v and - are scanned" 1 "$rc"
contains "-v:1:" "$OUT" "the -v file"
contains "-:1:" "$OUT" "the - file too"
mkrepo p-notmp
( cd "$HREPO" && printf 'secretproj\n' > leak.md && git add leak.md && git commit -qm leak ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && TMPDIR="$WORK/does-not-exist" "$SCRIPT" --list "$WORK/hlist" --all </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "mktemp failure refuses --all, the pre-push hook's mode (it exited 0 at v9)" 2 "$rc"
contains "cannot create a temp directory" "$(cat "$WORK/herr.txt")" "and says so"
if [ "$(id -u)" -ne 0 ]; then
  ( cd "$HREPO" && chmod 000 leak.md )
  hrun --all; rc=$RC; expect "a tracked file the scanner cannot open refuses --all" 2 "$rc"
  contains "could not read leak.md" "$ERR" "naming the file"
  ( cd "$HREPO" && chmod 644 leak.md )
else
  ok "unreadable-file case skipped: running as root"
fi

echo "== --head: HEAD's committed tree, never the working tree (#375) =="
# The pre-push hook's mode. MUTANTS RUN AGAINST THIS SECTION, each on a scratch copy with `cmp -s`
# proving the edit applied, each killed: the read taken from the worktree file; `HEAD:./$f` reduced
# to `HEAD:$f` (killed by G1); the unborn-HEAD refusal removed; the `ls-tree` pre-check removed; the
# `--head takes no paths` refusal removed; the 160000 gitlink mode admitted. Fresh repo per case
# (mkrepo), so none leans on another's tree or leaves it dirty. C1, C2 and C6 use the NON-EMPTY list
# $WORK/hlist: the scanner exits 0 on an empty or missing list before it looks at the work tree.
NEWMODES='one mode only: --all, --staged, --range, --head or --history'
hcommit() {  # hcommit <file> <content-printf-format>: write, add, commit in HREPO
  ( cd "$HREPO" && printf "$2" > "$1" && git add -- "$1" && git commit -qm "add $1" ) >/dev/null 2>&1
}
mkrepo h-clean
hrun --head; rc=$RC; expect "--head over a clean HEAD exits 0" 0 "$rc"
[ -z "$OUT" ] && ok "with no output" || bad "with no output (got '$OUT')"
mkrepo h-masked
hcommit leak.md 'work on secretproj today\n'
printf 'edited out\n' > "$HREPO/leak.md"
hrun --head; rc=$RC; expect "--head reports a committed name masked by an uncommitted fix" 1 "$rc"
contains "leak.md:1: private-name: se********" "$OUT" "as a redacted private-name finding"
hrun --all; rc=$RC; expect "(the defect: --all reads the working tree and reports the same state clean)" 0 "$rc"
mkrepo h-uncommitted
printf 'secretproj\n' >> "$HREPO/seed.md"
hrun --head; rc=$RC; expect "--head ignores an uncommitted-only name (never published)" 0 "$rc"
( cd "$HREPO" && git add seed.md && git commit -qm leak ) >/dev/null 2>&1
hrun --head; rc=$RC; expect "the same edit, committed, is reported" 1 "$rc"
mkrepo h-deleted
hcommit gone.md 'secretproj\n'
rm -f "$HREPO/gone.md"
hrun --head; rc=$RC; expect "a committed name in a file deleted in the worktree is still reported" 1 "$rc"
hrun --all; rc=$RC; expect "(the defect: --all skips the deleted file)" 0 "$rc"
mkrepo h-deleted-clean
hcommit fine.md 'nothing here\n'
rm -f "$HREPO/fine.md"
hrun --head; rc=$RC; expect "a clean file deleted in the worktree exits 0" 0 "$rc"
[ -z "$OUT" ] && ok "with no output" || bad "with no output (got '$OUT')"
mkrepo h-renamed
hcommit a.md 'secretproj\n'
mv "$HREPO/a.md" "$HREPO/b.md"
hrun --head; rc=$RC; expect "a file renamed in the worktree and not committed is found under its old name" 1 "$rc"
contains "a.md:1:" "$OUT" "at the committed path"
mkrepo h-binary
( cd "$HREPO" && printf '\0secretproj\n' > blob.dat && git add blob.dat && git commit -qm bin ) >/dev/null 2>&1
hrun --head; rc=$RC; expect "a binary file (NUL bytes) is skipped, as under --all" 0 "$rc"
mkrepo h-symlink
( cd "$HREPO" && ln -s /srv/secretproj/data link && git add link && git commit -qm link ) >/dev/null 2>&1
hrun --head; rc=$RC; expect "a tracked symlink is scanned as its link text, the parity of --all" 1 "$rc"
contains "link:1: private-name: se********" "$OUT" "at the link's path, redacted"
mkrepo h-gitlink
( cd "$HREPO" && c="$(git commit-tree -m 'secretproj in a message' "$(git write-tree)")" \
  && git update-index --add --cacheinfo 160000,"$c",present && git commit -qm gitlink ) >/dev/null 2>&1
hrun --head; rc=$RC; expect "a committed gitlink is skipped, never read and never a refusal" 0 "$rc"

echo "== --head: the refusals, each with its own message =="
mkdir -p "$WORK/h-nogit"
OUT="$( cd "$WORK/h-nogit" && GIT_CEILING_DIRECTORIES="$WORK" "$SCRIPT" --list "$WORK/hlist" --head 2>"$WORK/herr.txt" )"; rc=$?
expect "C1: --head outside a git work tree refuses" 2 "$rc"
contains "check-private-leaks: not inside a git work tree (pass explicit paths to scan without git)" "$(cat "$WORK/herr.txt")" "and says so"
mkdir -p "$WORK/h-unborn"; ( cd "$WORK/h-unborn" && git init -q . ) >/dev/null 2>&1
OUT="$( cd "$WORK/h-unborn" && "$SCRIPT" --list "$WORK/hlist" --head 2>"$WORK/herr.txt" )"; rc=$?
expect "C2: --head on an unborn HEAD refuses, it never reports clean" 2 "$rc"
contains "check-private-leaks: HEAD not found: no commits yet, so --head has nothing to scan" "$(cat "$WORK/herr.txt")" "and names the cause"
mkrepo h-modes
hrun --head --all; rc=$RC; expect "C3: --head with --all refuses" 2 "$rc"
contains "$NEWMODES" "$ERR" "and lists every mode, --head included"
contains "check-private-leaks: one mode only" "$ERR" "under the private scanner's own prefix"
hrun --all --head; rc=$RC; expect "and in the other order" 2 "$rc"
contains "$NEWMODES" "$ERR" "with the same text"
mkrepo h-leak
hcommit leak.md 'secretproj\n'
hrun --head; rc=$RC; expect "C4: a HEAD carrying one listed name exits 1, so the mode ran rather than returning early" 1 "$rc"
contains "leak.md:1: private-name: se********" "$OUT" "and prints the redacted finding"
hrun --head leak.md; rc=$RC; expect "C5: --head with an explicit path refuses (paths would silently replace the mode)" 2 "$rc"
contains "check-private-leaks: --head takes no paths" "$ERR" "and says so"
SHIM="$WORK/h-shim"; mkdir -p "$SHIM"
REALGIT="$(command -v git)"
printf '#!/bin/sh\n[ "$1" = ls-tree ] && exit 1\nexec "%s" "$@"\n' "$REALGIT" > "$SHIM/git"; chmod +x "$SHIM/git"
OUT="$( cd "$HREPO" && PATH="$SHIM:$PATH" "$SCRIPT" --list "$WORK/hlist" --head 2>"$WORK/herr.txt" )"; rc=$?
expect "C6: a failing tree listing refuses, it never reports clean" 2 "$rc"
contains "could not list HEAD's tree" "$(cat "$WORK/herr.txt")" "and says so"

echo "== --head: it reads each blob relative to the directory it runs from (G, gate round 2) =="
mkrepo h-sub
( cd "$HREPO" && printf 'clean\n' > README.md && mkdir sub && printf 'secretproj\n' > sub/README.md \
  && git add -A && git commit -qm sub ) >/dev/null 2>&1
OUT="$( cd "$HREPO/sub" && "$SCRIPT" --list "$WORK/hlist" --head 2>"$WORK/herr.txt" )"; rc=$?
expect "G1: from sub/, a sub/README.md naming a listed name is reported, never judged by the clean root README.md" 1 "$rc"
contains "README.md:1: private-name" "$OUT" "as a private-name finding for README.md"
mkrepo h-sub-clean
( cd "$HREPO" && printf 'clean\n' > README.md && mkdir sub && printf 'also clean\n' > sub/README.md \
  && git add -A && git commit -qm sub ) >/dev/null 2>&1
OUT="$( cd "$HREPO/sub" && "$SCRIPT" --list "$WORK/hlist" --head 2>"$WORK/herr.txt" )"; rc=$?
expect "G2: clean README.md files at the root and in sub/ exit 0" 0 "$rc"
[ -z "$OUT" ] && ok "with no output" || bad "with no output (got '$OUT')"

echo "== --head fails closed, the way the other tree modes do (#208) =="
mkrepo h-notmp
hcommit leak.md 'secretproj\n'
OUT="$( cd "$HREPO" && TMPDIR="$WORK/does-not-exist" "$SCRIPT" --list "$WORK/hlist" --head </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "mktemp failure refuses --head" 2 "$rc"
contains "cannot create a temp directory" "$(cat "$WORK/herr.txt")" "and says so"
mkrepo h-nowrite
( cd "$HREPO" && head -c 3000 /dev/zero | tr '\0' a > big.md && printf '\nsecretproj\n' >> big.md \
  && git add big.md && git commit -qm big ) >/dev/null 2>&1
( cd "$HREPO" && ulimit -f 1 && "$SCRIPT" --list "$WORK/hlist" --head </dev/null >"$WORK/wout.txt" 2>"$WORK/werr.txt"; echo $? > "$WORK/wrc.txt" ) 2>/dev/null
expect "a blob the scanner cannot write refuses --head" 2 "$(cat "$WORK/wrc.txt")"
contains "could not read big.md" "$(cat "$WORK/werr.txt")" "naming the file"
lacks "$ROOT" "$(cat "$WORK/werr.txt")" "and never the script's path"

echo "== --head in a partial clone (#384) =="
# Not refused (unlike --history): git fetches the missing blobs lazily. A reachable promisor remote
# scans clean and fetches them; with lazy fetch off, which is what an unreachable remote looks like,
# the read fails and the scan exits 2 naming the file rather than reporting clean.
PCSRC="$WORK/pc-src"; rm -rf "$PCSRC"; mkdir -p "$PCSRC"
( cd "$PCSRC" && git init -q . && git config user.email t@t.invalid && git config user.name t \
  && git config uploadpack.allowFilter true && printf 'clean\n' > a.md && git add a.md \
  && git commit -qm a ) >/dev/null 2>&1
pc_clone() {  # pc_clone <name>: a blobless clone with the one blob missing; sets PCLONE
  PCLONE="$WORK/pc-$1"; rm -rf "$PCLONE"
  git clone -q --no-checkout --filter=blob:none "file://$PCSRC" "$PCLONE" >/dev/null 2>&1
}
pc_missing() { git -C "$PCLONE" rev-list --objects --missing=print --all 2>/dev/null | grep -c '^?'; }
pc_clone ok
expect "the blobless clone starts with one missing blob" 1 "$(pc_missing)"
( cd "$PCLONE" && "$SCRIPT" --list "$WORK/hlist" --head ) >/dev/null 2>&1; rc=$?
expect "--head in a partial clone with a reachable remote exits 0" 0 "$rc"
expect "and has fetched the missing blob lazily" 0 "$(pc_missing)"
pc_clone offline
# GIT_NO_LAZY_FETCH=1 stops git fetching a missing blob from the promisor remote (honoured by git
# 2.45.0 and by the 2.39.4 and later security releases that carry it, and by distro builds that
# backport it, whatever version string they report). On a git without it the lazy fetch from the
# file:// remote succeeds, the scan exits 0, and the exit-2 expectation below FAILS LOUDLY. That is
# the signal to use a newer git: never loosen the expectation to make an older git green.
OUT="$( cd "$PCLONE" && GIT_NO_LAZY_FETCH=1 "$SCRIPT" --list "$WORK/hlist" --head 2>&1 )"; rc=$?
expect "--head with lazy fetch unavailable exits 2" 2 "$rc"
contains "check-private-leaks: could not read a.md" "$OUT" "naming the file"

echo "== --head: the mutants, each applied (cmp -s) and each killed =="
# #414: the four kills a crash can satisfy are classified first. hm_kill <name> runs
# scripts/mutant-crash.sh (sourced above, #360) on $HMUT against hm_live and, on a reason, prints
# `mutant <name> crashed (<reason>)` and returns 1, so the kill line never runs. Each case captures
# its status in rc on the line that runs the build, because hm_kill overwrites $?.
mkrepo hm-live
( CDPATH= cd -- "$HREPO" && git rm -q seed.md && printf 'clean\n' > a.md && git add a.md \
  && git commit -q --amend -m a ) >/dev/null 2>&1
HMLIVE="$HREPO"
# hm_live <build>: in a one-commit repository holding a clean a.md, --head with the suite's list
# (never the developer's default one) exits 0 with empty stdout.
hm_live() { local o; o="$( CDPATH= cd -- "$HMLIVE" && "$1" --list "$WORK/hlist" --head )" || return 1; [ -z "$o" ]; }
hm_kill() {  # hm_kill <name>: 0 when $HMUT is live; else the crashed FAIL and 1
  local why; why=$(mutant_crash_reason_live "$HMUT" hm_live "$HMUT")
  [ -z "$why" ] && return 0
  bad "mutant $1 crashed ($why)"; return 1
}
hm_c2() {  # hm_c2 <name>: the C2 case (an unborn HEAD) on $HMUT, then its kill
  OUT="$( CDPATH= cd -- "$WORK/h-unborn" && "$HMUT" --list "$WORK/hlist" --head 2>&1 )"; rc=$?
  hm_kill "$1" || return 0
  lacks "HEAD not found" "$OUT" "mutant: without the unborn-HEAD refusal the C2 message is gone"
}
hm_c5() {  # hm_c5 <name>: the C5 case (--head with a path, over a committed name) on $HMUT, then its kill
  mkrepo hm-paths; hcommit leak.md 'secretproj\n'
  ( CDPATH= cd -- "$HREPO" && "$HMUT" --list "$WORK/hlist" --head leak.md ) >/dev/null 2>&1; rc=$?
  hm_kill "$1" || return 0
  [ "$rc" != 2 ] && ok "mutant: without the refusal --head with a path no longer exits 2 (C5 fails it)" \
    || bad "mutant: without the refusal --head with a path no longer exits 2"
}
head_mutant() {  # head_mutant <name> <sed script>: scratch copy in $HMUT; returns 1 when the edit changed nothing
  HMUT="$WORK/mutant-head-$1.sh"; sed "$2" "$SCRIPT" > "$HMUT"; chmod +x "$HMUT"
  if cmp -s "$HMUT" "$SCRIPT"; then bad "mutant ledger ($1): the edit changed nothing"; return 1; fi
  ok "mutant ledger ($1): the scratch copy differs from the scanner"
}
if head_mutant worktree-read 's|^    head)   {.*$|    head)   scanfile="$f" ;;|'; then
  mkrepo hm-masked; hcommit leak.md 'secretproj\n'; printf 'edited out\n' > "$HREPO/leak.md"
  ( cd "$HREPO" && "$HMUT" --list "$WORK/hlist" --head ) >/dev/null 2>&1
  expect "mutant: reading the worktree file instead of HEAD misses the masked name (the masked case fails it)" 0 "$?"
fi
if head_mutant no-dot-slash 's|"HEAD:\./\$f"|"HEAD:$f"|'; then
  mkrepo hm-sub
  ( cd "$HREPO" && printf 'clean\n' > README.md && mkdir sub && printf 'secretproj\n' > sub/README.md \
    && git add -A && git commit -qm sub ) >/dev/null 2>&1
  ( cd "$HREPO/sub" && "$HMUT" --list "$WORK/hlist" --head ) >/dev/null 2>&1
  expect "mutant: HEAD:\$f without ./ reads the ROOT README.md and reports clean (G1 fails it)" 0 "$?"
fi
if head_mutant no-unborn-check 's|^        \|\| die "HEAD not found: no commits yet.*$|        \|\| true|'; then
  hm_c2 no-unborn-check
fi
if head_mutant read-error-swallowed '/^    head)/s/|| die "could not read \$f"/|| true/'; then
  pc_clone offline-mut
  OUT="$( cd "$PCLONE" && GIT_NO_LAZY_FETCH=1 "$HMUT" --list "$WORK/hlist" --head 2>&1 )"; rc=$?
  hm_kill read-error-swallowed && { [ "$rc" != 2 ] && ok "mutant: without the read failure a missing blob no longer exits 2 (the lazy-fetch case fails it)" \
    || bad "mutant: without the read failure a missing blob no longer exits 2"; }
fi
if head_mutant no-precheck 's|^      git ls-tree -r -z HEAD >/dev/null 2>&1 .*$|      :|'; then
  ( cd "$HREPO" && PATH="$SHIM:$PATH" "$HMUT" --list "$WORK/hlist" --head ) >/dev/null 2>&1
  expect "mutant: without the ls-tree pre-check a failing listing reads as clean (C6 fails it)" 0 "$?"
fi
if head_mutant no-paths-refusal 's|^\[ "\$MODE" != head \].*$|:|'; then
  hm_c5 no-paths-refusal
fi
if head_mutant gitlink-admitted 's/100644|100755|120000/100644|100755|120000|160000/'; then
  mkrepo hm-gitlink
  ( cd "$HREPO" && git update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,sub \
    && git commit -qm gitlink ) >/dev/null 2>&1
  ( cd "$HREPO" && "$SCRIPT" --list "$WORK/hlist" --head ) >/dev/null 2>&1
  expect "(the real scanner skips an absent-commit gitlink)" 0 "$?"
  ( cd "$HREPO" && "$HMUT" --list "$WORK/hlist" --head ) >/dev/null 2>&1; rc=$?
  hm_kill gitlink-admitted && expect "mutant: admitting 160000 makes a gitlink a refusal (the gitlink case fails it)" 2 "$rc"
fi
# Crash control (#414): an exit 127 scanner prints no `HEAD not found`, the C2 kill's evidence.
# head_mutant and hm_c2 run in $( ), so this adds one row, and the capture is not echoed.
cap=$(head_mutant crash-control '1a\
exit 127' && hm_c2 crash-control)
crash_ok=1
cmp -s "$WORK/mutant-head-crash-control.sh" "$SCRIPT" && crash_ok=0
case "$cap" in *"C2 message is gone"*) crash_ok=0 ;; *"FAIL: mutant crash-control crashed (the liveness run failed)"*) ;; *) crash_ok=0 ;; esac
[ "$crash_ok" = 1 ] && ok "crash control: hm_kill reports a crashing scanner as crashed, never as a kill" \
  || bad "crash control: hm_kill credited or missed a crashing scanner"
# Survivor control (#414): a plain copy of the scanner is live and still refuses --head with a path
# (exit 2), so the C5 kill, which reads the case's own rc and never hm_kill's 0, must not credit it.
cap=$(HMUT="$WORK/mutant-head-survivor.sh"; cp "$SCRIPT" "$HMUT"; hm_c5 survivor-control)
surv_ok=1
cmp -s "$WORK/mutant-head-survivor.sh" "$SCRIPT" || surv_ok=0
case "$cap" in *"ok: mutant: without the refusal"*) surv_ok=0 ;; *"FAIL: mutant: without the refusal --head with a path no longer exits 2"*) ;; *) surv_ok=0 ;; esac
[ "$surv_ok" = 1 ] && ok "survivor control: a live build that still exits 2 is not credited on no-paths-refusal" \
  || bad "survivor control: a live build that still exits 2 was credited on no-paths-refusal"

echo "== the owner drop applies only where its rationale is true (#209) =="
own() {  # own <origin-url> <list-name> <mode...>: fresh repo naming the listed name in README; OUT/ERR/RC
  mkrepo "own-$RANDOM"; printf '%s\n' "$2" > "$WORK/ownlist"
  ( cd "$HREPO" && git remote add origin "$1" && printf 'about %s here\n' "$2" > README.md && git add README.md && git commit -qm readme ) >/dev/null 2>&1
  shift 2; OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/ownlist" "$@" 2>"$WORK/herr.txt" )"; RC=$?; ERR="$(cat "$WORK/herr.txt")"
}
own 'git@forgejo.example.internal:acme-secret-org/repo.git' acme-secret-org --history
expect "a listed owner on a private forge origin is reported by --history" 1 "$RC"; lacks "dropping" "$ERR" "with no dropping warning"
own 'git@forgejo.example.internal:acme-secret-org/repo.git' acme-secret-org --all
expect "and by --all: the drop is for public forges only" 1 "$RC"; lacks "dropping" "$ERR" "no warning"
own 'https://forgejo.example.internal:3000/acme-secret-org/repo.git' acme-secret-org --all
expect "a private https origin with a port: reported" 1 "$RC"
own 'git@github.com:acme-secret-org/repo.git' acme-secret-org --all
expect "a github.com origin in a tree mode: the documented drop" 0 "$RC"; contains "dropping" "$ERR" "with the warning"
lacks "acme-secret-org" "$ERR" "and the name redacted in it"
own 'git@github.com:acme-secret-org/repo.git' acme-secret-org --history
expect "a github.com origin in --history: never dropped" 1 "$RC"
own 'ssh://git@github.com:2222/acme-secret-org/repo.git' 2222 --all
expect "a listed 2222 with a port-carrying URL is reported (v9 took the port for the owner)" 1 "$RC"; lacks "dropping" "$ERR" "no drop"
own 'ssh://git@github.com:2222/acme-secret-org/repo.git' acme-secret-org --all
expect "and the owner behind the port is still the owner on github.com" 0 "$RC"
own '../acme-secret-org/repo.git' acme-secret-org --all
expect "a relative-path origin yields no owner: the listed folder name is reported" 1 "$RC"
own 'https://git:git@github.com/acme-secret-org/repo.git' acme-secret-org --all
expect "userinfo is stripped before the port: github.com is still the host" 0 "$RC"
own 'https://evil.internal/x/y?z=@github.com/acme-secret-org/repo.git' acme-secret-org --all
expect "github.com in the path or query is not the host" 1 "$RC"
own 'https://github.com.evil.internal/acme-secret-org/repo.git' acme-secret-org --all
expect "a look-alike host is not github.com" 1 "$RC"
own 'https://evil.internal?@github.com/acme-secret-org/repo.git' acme-secret-org --all
expect "a query before the first slash does not move the host (the authority ends at / ? or #)" 1 "$RC"
own 'https://evil.internal#@github.com/acme-secret-org/repo.git' acme-secret-org --all
expect "nor a fragment" 1 "$RC"

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

echo "== no awk -v in the shipped asset, and a backslash TMPDIR still finds a leak (#259) =="
# #405: the zero-`awk -v` rule and the no-operand rule, one definition in scripts/awkv-count.sh.
. "$ROOT/scripts/awkv-count.sh"; awkv_checks check-private-leaks.sh "$SCRIPT" "$WORK"
# The temp paths come from mktemp -d under the caller's TMPDIR. Under -v a TMPDIR named `t\tx`
# (backslash, t) read back with a TAB, every getline failed, and --history reported CLEAN.
mkdir -p "$WORK/tA" "$WORK/t\\tx"
[ -d "$WORK/t\\tx" ] && ok "#259: the backslash TMPDIR fixture exists (fixture sanity)" || bad "#259: no backslash TMPDIR fixture"
mkrepo bs-leak
( cd "$HREPO" && printf 'work on secretproj today\n' > notes.md && git add notes.md && git commit -qm add ) >/dev/null 2>&1
TMPDIR="$WORK/tA" hrun --history; expect "#259: control TMPDIR: the committed name is reported" 1 "$RC"
TMPDIR="$WORK/t\\tx" hrun --history; expect "#259: backslash TMPDIR: the committed name is still reported" 1 "$RC"
contains "notes.md@" "$OUT" "#259: and the finding names the file"
mkrepo bs-clean
TMPDIR="$WORK/t\\tx" hrun --history; expect "#259: backslash TMPDIR over a clean history exits 0" 0 "$RC"
expect "#259: and reports nothing" "" "$OUT"
# #405: a RELATIVE TMPDIR named name=value. Every temp path then reads `x=y/...`, which awk took for
# an assignment when it came as an operand; through a redirect it is a file like any other.
mkrepo eq-leak
( cd "$HREPO" && printf 'work on secretproj today\n' > notes.md && git add notes.md && git commit -qm add ) >/dev/null 2>&1
TMPDIR="$WORK/tA" hrun --history; abs_rc=$RC; abs_out=$OUT
mkdir -p "$HREPO/x=y"
TMPDIR='x=y' hrun --history
expect "#405: a relative TMPDIR named x=y exits as an absolute one does ($abs_rc)" "$abs_rc" "$RC"
expect "#405: and reports the same rows" "$abs_out" "$OUT"
contains "notes.md@" "$OUT" "#405: and the finding is reported"

echo ""
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
