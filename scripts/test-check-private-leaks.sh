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
LIB="$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/leak-lib.sh"
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
[ -f "$LIB" ] || { echo "missing library: $LIB"; exit 1; }

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
# The scanner ALONE (#206): the tree modes and the hooks must not need leak-lib.sh beside it.
[ ! -f "$SELFREPO/scripts/leak-lib.sh" ] && ok "the installed-project copy has no leak-lib.sh beside it" \
  || bad "the installed-project copy has no leak-lib.sh beside it"
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
# An explicit prefix comparison, never `contains`: a leak-lib: line quoting the name would satisfy
# that too, and the point is that the library refuses through THIS scanner's die (#206).
case "$ERR" in check-private-leaks:*) ok "and the refusal carries this scanner's own prefix (#206)" ;;
  *) bad "and the refusal carries this scanner's own prefix (#206) (got '$ERR')" ;; esac
hrun --history n.md; rc=$RC; expect "--history with a path is refused" 2 "$rc"
hrun --orphans; rc=$RC;        expect "--orphans without --history is refused" 2 "$rc"
hrun --history --staged; rc=$RC; expect "--history --staged is refused rather than scanning the index" 2 "$rc"
# The store-shape refusals (GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_OBJECT_DIRECTORY, partial clone,
# replace, corrupt object, deleted pushed branch, log.diffMerges, newline path, the --orphans
# widening, bare) were mirrored here by hand in #191 round 2 because the two scanners carried two
# copies of the history reader. Since #206 that reader is ONE file, leak-lib.sh, so they run once,
# in the public suite. The --shared refusal above stays as the proof that `die` reaches the library
# with THIS scanner's prefix; selfid below stays because it exercises this scanner's own SELF.
mkrepo selfid
( cd "$HREPO" && mkdir old && cp "$SCRIPT" old/check-private-leaks.sh && git add old && git commit -qm old ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a past copy of the scanner at another path is not reported (its source names the list)" 0 "$rc"

echo "== redact: the bash copy is linear, the awk copy is left alone on purpose (#217) =="
# The bash redact serves the owner warning, the tree modes and the list refusals, so it is
# exercised here on the function itself (length 0 is unreachable through the CLI: an empty `=`
# line dies with a fixed message first). The awk redact has no timed case: the grep -aiF
# pre-filter before it stalls first at every size, so a bounded 256 KB case would fail even on a
# correct fix. Its ledger pins the decision recorded in the scanner header, not behaviour.
RFN="$(sed -n '/^char_len() {/,/^}/p;/^redact() {/,/^}/p' "$SCRIPT")"
rshow() { LC_ALL="$1" bash -c "$RFN"'; for n in "" a ab abc "$(printf "jos\303\251")"; do printf "[%s]" "$(redact "$n")"; done' 2>&1; }
expect "redact keeps a two-character prefix at lengths 0 to 3 and a multibyte name (C, characters since #416)" \
  "[][a][ab][ab*][jo**]" "$(rshow C)"
R217U="$(locale -a 2>/dev/null | grep -i 'utf' | head -1)"
if [ -n "$R217U" ]; then
  expect "and under a UTF-8 locale the multibyte name masks characters, as before" \
    "[][a][ab][ab*][jo**]" "$(rshow "$R217U")"   # the same string as the C row above: parity (#416)
else
  ok "(skipped, no UTF-8 locale on this machine) the multibyte redact case"
fi
expect "the bash redact guards k <= 0 before slicing" 1 "$(grep -cF 'if [ "$k" -le 0 ]; then printf' "$SCRIPT")"
expect "the bash redact builds its mask by doubling" 1 "$(grep -cF 's="$s$s"' "$SCRIPT")"
expect "the awk redact keeps its per-byte loop (ledger)" 1 "$(grep -cF 'o = o "*"' "$SCRIPT")"
expect "and the header records why, and that the ledger pins a decision" 1 "$(grep -cF 'pins this DECISION, not behaviour' "$SCRIPT")"
MUTAWK="$WORK/mutant-awk-redact.sh"
sed 's/o = o "\*"/o = sprintf("%s*", o)/' "$SCRIPT" > "$MUTAWK"
expect "a rewritten awk loop fails the ledger (0 where 1 is expected)" 0 "$(grep -cF 'o = o "*"' "$MUTAWK")"
for n in a ab; do
  printf '%s\n' "$n" > "$WORK/short-$n"
  "$SCRIPT" --list "$WORK/short-$n" "$WORK/sample.txt" >/dev/null 2>"$WORK/err.txt"
  expect "a length-${#n} entry refuses the run" 2 "$?"
  contains "'$n' is too short" "$(cat "$WORK/err.txt")" "and names '$n' unmasked, as before"
  expect "and stderr holds only the two-line refusal (no slice error)" 2 "$(wc -l < "$WORK/err.txt" | tr -d ' ')"
  lacks "substring" "$(cat "$WORK/err.txt")" "with no bash substring error"
done

echo "== a multibyte name: the floor counts characters and the report cuts at a character (#416) =="
# Before: `${#n}` was a byte count under C and a character count under UTF-8, so the list `日本`
# (2 characters, 6 bytes) was kept under C and refused under UTF-8, and the C redaction kept two
# BYTES, printing half a character. Now the floor counts UTF-8 lead bytes with the locale pinned
# (a 2-character CJK name stays refused everywhere, a 3-character one is kept everywhere) and every
# redaction keeps two whole characters, the awk copy of --history included.
CJK2=$'\xe6\x97\xa5\xe6\x9c\xac'; CJK3="$CJK2"$'\xe8\xaa\x9e'; CJKSTAR="$CJK2*"
printf '%s\n' "$CJK2" > "$WORK/t416-short"; printf '%s\n' "$CJK3" > "$WORK/t416-list"
printf 'see %s here\n' "$CJK3" > "$WORK/t416-s.txt"
printf 'plain\n' > "$WORK/t416-plain.txt"
# row416 <script> <locale> <list> <file> -> "rc|evidence", the evidence being what follows `private-name: `
row416() {
  local out rc
  out="$(LC_ALL=$2 "$1" --list "$3" "$4" 2>"$WORK/err.txt")"; rc=$?
  echo "$rc|$(printf '%s\n' "$out" | sed -n 's/.*private-name: //p')"
}
# hrow416 <script> <locale> [name] -> "rc|evidence|path" of a --history run over one committed line
# naming the name (default CJK3)
hrow416() {
  local nm="${3:-$CJK3}"
  mkrepo cjk416
  ( cd "$HREPO" && mkdir -p "$nm" && printf 'see %s here\n' "$nm" > "$nm/n.md" && git add . && git commit -qm cjk ) >/dev/null 2>&1
  printf '%s\n' "$nm" > "$WORK/hlist416"
  local out rc
  out="$( cd "$HREPO" && LC_ALL=$2 "$1" --list "$WORK/hlist416" --history 2>"$WORK/err.txt" )"; rc=$?
  echo "$rc|$(printf '%s\n' "$out" | sed -n 's/.*private-name: //p')|$(printf '%s\n' "$out" | sed -n 's/@.*//p')"
}
for L in $locs; do
  expect "the 2-character list name is refused under $L, as the refusal text says" "2|" "$(row416 "$SCRIPT" "$L" "$WORK/t416-short" "$WORK/t416-s.txt")"
  contains "is too short (under 3 characters)" "$(cat "$WORK/err.txt")" "and the refusal names the character floor under $L"
  expect "the 3-character list name is kept under $L, and the evidence is two whole characters then one star" "1|$CJKSTAR" "$(row416 "$SCRIPT" "$L" "$WORK/t416-list" "$WORK/t416-s.txt")"
  expect "the same list on a clean file exits 0 under $L" "0|" "$(row416 "$SCRIPT" "$L" "$WORK/t416-list" "$WORK/t416-plain.txt")"
  for short in $'a\xe6\x97\xa5' $'\xe6\x9c\xac'; do   # a 2-character name of 4 bytes, and 1 character
    printf '%s\n' "$short" > "$WORK/t416-sh"
    expect "the short name '$short' is refused under $L" "2|" "$(row416 "$SCRIPT" "$L" "$WORK/t416-sh" "$WORK/t416-s.txt")"
  done
  printf '%s\n' "${CJK3}"$'\xe6\x97\xa5' > "$WORK/t416-l4"; printf 'see %s\n' "${CJK3}"$'\xe6\x97\xa5' > "$WORK/t416-s4.txt"
  expect "a 4-character name masks characters minus two under $L" "1|${CJK2}**" "$(row416 "$SCRIPT" "$L" "$WORK/t416-l4" "$WORK/t416-s4.txt")"
  EMO=$'\xf0\x9f\x98\x80'
  printf '%s\n' "$EMO$EMO$EMO"x > "$WORK/t416-l5"; printf 'see %s\n' "$EMO$EMO${EMO}x" > "$WORK/t416-s5.txt"
  expect "a 4-byte character is never split under $L" "1|$EMO$EMO**" "$(row416 "$SCRIPT" "$L" "$WORK/t416-l5" "$WORK/t416-s5.txt")"
  expect "--history reports the name and cuts its evidence and its path at a character under $L" "1|$CJKSTAR|$CJKSTAR/n.md" "$(hrow416 "$SCRIPT" "$L")"
  # The continuation-byte range ends at 0x80 (emoji) and 0xBF (y with a diaeresis, c3 bf): a boundary
  # edit on either side of any copy of the range must change one of these rows (review r1, #416).
  YY=$'\xc3\xbf'
  printf '%s\n' "$YY$YY" > "$WORK/t416-yy2"
  expect "a 2-character name of 0xBF bytes is refused under $L" "2|" "$(row416 "$SCRIPT" "$L" "$WORK/t416-yy2" "$WORK/t416-s.txt")"
  printf '%s\n' "$YY$YY${YY}a" > "$WORK/t416-yy4"; printf 'see %s\n' "$YY$YY${YY}a" > "$WORK/t416-yys.txt"
  expect "a 4-character name of 0xBF bytes masks two under $L" "1|$YY$YY**" "$(row416 "$SCRIPT" "$L" "$WORK/t416-yy4" "$WORK/t416-yys.txt")"
  expect "--history cuts a 0xBF name at a character under $L" "1|$YY$YY**|$YY$YY**/n.md" "$(hrow416 "$SCRIPT" "$L" "$YY$YY${YY}a")"
  expect "--history cuts a 4-byte character name at a character under $L" "1|$EMO$EMO**|$EMO$EMO**/n.md" "$(hrow416 "$SCRIPT" "$L" "$EMO$EMO${EMO}x")"
done
if command -v iconv >/dev/null 2>&1; then
  for L in $locs; do
    LC_ALL=$L "$SCRIPT" --list "$WORK/t416-list" "$WORK/t416-s.txt" > "$WORK/t416-out" 2>&1
    iconv -f UTF-8 -t UTF-8 < "$WORK/t416-out" >/dev/null 2>&1
    expect "the report is valid UTF-8 under $L (no split sequence)" 0 "$?"
  done
fi
# One mutant per choice, each a sed on a scratch copy BESIDE the library (--history needs it), shown
# to differ (cmp) and to change at least one row of sig416, the signature of every row above.
# The tr pin has no row on a GNU tr, which is bytewise in every locale, so its mutant runs behind a
# stub tr that, like a multibyte-aware one, rejects the byte range unless LC_ALL=C. The redact pin
# changes no output on bash 5.2, so it is pinned as text, and the comment above redact() says so.
mkdir -p "$WORK/lone"; cp "$LIB" "$WORK/lone/"
SHIM416="$WORK/shim416"; mkdir -p "$SHIM416"
printf '%s\n' '#!/bin/sh' "case \"\$*\" in *'\\200-\\277'*) [ \"\${LC_ALL:-}\" = C ] || { echo 'tr: Illegal byte sequence' >&2; exit 1; } ;; esac" "exec $(command -v tr) \"\$@\"" > "$SHIM416/tr"
chmod +x "$SHIM416/tr"
sig416() {  # sig416 <script>: all the rows above, every locale, on one line
  local L s=""
  for L in $locs; do
    s="$s $(row416 "$1" "$L" "$WORK/t416-short" "$WORK/t416-s.txt") $(row416 "$1" "$L" "$WORK/t416-list" "$WORK/t416-s.txt") $(hrow416 "$1" "$L") $(hrow416 "$1" "$L" "$YY$YY${YY}a") $(hrow416 "$1" "$L" "$EMO$EMO${EMO}x") $(row416 "$1" "$L" "$WORK/t416-yy2" "$WORK/t416-s.txt") $(row416 "$1" "$L" "$WORK/t416-yy4" "$WORK/t416-yys.txt")"
  done
  printf '%s' "$s"
}
GOOD416="$(sig416 "$SCRIPT")"
cp "$SCRIPT" "$WORK/lone/m416-good.sh"
expect "the pinned scanner gives the same rows behind the rejecting tr (control)" "$GOOD416" "$(PATH="$SHIM416:$PATH" sig416 "$WORK/lone/m416-good.sh")"
m416() {  # m416 <name> <what it undoes> <sed script> [PATH prefix]
  local f="$WORK/lone/m416-$1.sh"
  sed "$3" "$SCRIPT" > "$f"; chmod +x "$f"
  if cmp -s "$SCRIPT" "$f"; then bad "mutant ledger (#416, $1): the edit changed nothing"; return; fi
  ok "mutant ledger (#416, $1): the scratch copy differs from the scanner"
  local sig; sig="$(PATH="${4:+$4:}$PATH" sig416 "$f")"
  case "$sig" in *" 127|"*|*" 126|"*) bad "mutant (#416, $1): the copy did not run ($sig)"; return ;; esac
  if [ "$sig" != "$GOOD416" ]; then ok "mutant (#416, $1): $2 changes a row"; else bad "mutant (#416, $1): $2 survives every row"; fi
}
m416 floor "counting bytes at the floor" 's|^  if \[ "\$CHARS" -lt "\$MIN_NAME_LEN" \]; then$|  if [ "${#n}" -lt "$MIN_NAME_LEN" ]; then|'
m416 cut "keeping two bytes in the bash redact" 's|printf .%s%s. "\${n:0:i}" "\${s:0:k}"|printf "%s%s" "${n:0:2}" "${s:0:k}"|'
if [ -n "$utf8loc" ]; then
  m416 tr-pin "an unpinned tr" 's/| LC_ALL=C tr -d/| tr -d/' "$SHIM416"
else
  ok "(skipped, no UTF-8 locale: the stub tr cannot tell a pinned tr from an unpinned one under C alone)"
fi
m416 awk-lo "an awk range starting above 0x80" 's|b >= "\\200" \&\& b <= "\\277"|b > "\\200" \&\& b <= "\\277"|'
m416 awk-hi "an awk range ending below 0xBF" 's|b >= "\\200" \&\& b <= "\\277"|b >= "\\200" \&\& b <= "\\276"|'
m416 bash-hi "a bash pattern ending below 0xBF" "s|\\[\$'\\\\200'-\$'\\\\277'\\]|[\$'\\\\200'-\$'\\\\276']|"
m416 awk-cut "dropping the awk redact's kept continuation bytes" 's|{ if (c <= 2) o = o b }|{ }|'
m416 awk-bytes "the awk redact keeping two bytes" 's|if (c <= 2) o = o b; else o = o "\*"|if (c <= 2 \&\& length(o) < 2) o = o b; else o = o "*"|'
expect "the bash redact pins the locale (ledger; no row can fail it on bash 5.2)" 1 "$(grep -cF 'local LC_ALL=C n=' "$SCRIPT")"

echo "== --history: this scanner sources the library (#206) =="
mkrepo forged
( cd "$HREPO" && printf '0000000000000000000000000000000000000000 blob 999999\nsecretproj\n' > forged.md && git add forged.md && git commit -qm forged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "the name after a forged header is reported" 1 "$rc"
contains "forged.md@$(hoid HEAD:forged.md):2:" "$OUT" "at line 2"
# The scanner ALONE (#206): --history refuses, naming the library and never the directory looked
# in, and prints no finding line, so a refusal can never read as clean.
mkdir -p "$WORK/nolib"; cp "$SCRIPT" "$WORK/nolib/"
OUT="$( cd "$HREPO" && "$WORK/nolib/check-private-leaks.sh" --list "$WORK/hlist" --history 2>"$WORK/herr.txt" )"; rc=$?; ERR="$(cat "$WORK/herr.txt")"
expect "without leak-lib.sh beside it --history is refused" 2 "$rc"
contains "leak-lib.sh" "$ERR" "naming the library"
case "$ERR" in check-private-leaks:*) ok "with this scanner's own prefix" ;; *) bad "with this scanner's own prefix (got '$ERR')" ;; esac
expect "and nothing on stdout" "" "$OUT"
( cd "$HREPO" && "$WORK/nolib/check-private-leaks.sh" --list "$WORK/hlist" --all ) >/dev/null 2>&1
expect "while the tree modes still run without it (the leak in forged.md is reported)" 1 "$?"
# Sourced for hm_kill below (#360); the private r<0 mutant it once served is the public suite's now (#206).
. "$ROOT/scripts/mutant-crash.sh"


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
# proving the edit applied, each killed: the read taken from the worktree file; the root anchor deleted (killed by G3);
# the anchor moved ahead of the option reads (killed by G4); the unborn-HEAD refusal removed; the `ls-tree` pre-check removed; the
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

echo "== the tree modes scan the whole repository from any directory (G, #401) =="
# `--all` and `--head` change to the work-tree root after the allow file and list are read, so a
# run from sub/ covers every tracked file and prints root-relative paths. G1 was the #375 row for
# `HEAD:./$f`; it now also pins the root-relative name.
mkrepo h-sub
( cd "$HREPO" && printf 'clean\n' > README.md && mkdir sub && printf 'secretproj\n' > sub/README.md \
  && git add -A && git commit -qm sub ) >/dev/null 2>&1
for m in --head --all; do
  OUT="$( cd "$HREPO/sub" && "$SCRIPT" --list "$WORK/hlist" $m 2>"$WORK/herr.txt" )"; rc=$?
  expect "G1 ($m): from sub/, a leaking sub/README.md is reported, never judged by the clean root README.md" 1 "$rc"
  contains "sub/README.md:1: private-name" "$OUT" "G1 ($m): as a root-relative private-name finding for sub/README.md"
done
mkrepo h-sub-clean
( cd "$HREPO" && printf 'clean\n' > README.md && mkdir sub && printf 'also clean\n' > sub/README.md \
  && git add -A && git commit -qm sub ) >/dev/null 2>&1
for m in --head --all; do
  OUT="$( cd "$HREPO/sub" && "$SCRIPT" --list "$WORK/hlist" $m 2>"$WORK/herr.txt" )"; rc=$?
  expect "G2 ($m): a clean tree run from sub/ exits 0" 0 "$rc"
  [ -z "$OUT" ] && ok "G2 ($m): with no output" || bad "G2 ($m): with no output (got '$OUT')"
done
mkrepo h-root
( cd "$HREPO" && printf 'secretproj\n' > leak.md && mkdir sub && printf 'clean\n' > sub/README.md \
  && git add -A && git commit -qm root ) >/dev/null 2>&1
for m in --head --all; do
  OUT="$( cd "$HREPO/sub" && "$SCRIPT" --list "$WORK/hlist" $m 2>"$WORK/herr.txt" )"; rc=$?
  expect "G3 ($m): from sub/, a committed root leak is reported" 1 "$rc"
  contains "leak.md:1: private-name" "$OUT" "G3 ($m): named root-relative as leak.md"
  lacks "sub/README.md" "$OUT" "G3 ($m): and the clean sub/README.md is not named"
done
printf 'secretproj\n' > "$HREPO/sub/hl"
OUT="$( cd "$HREPO/sub" && "$SCRIPT" --all --list ./hl 2>"$WORK/herr.txt" )"; rc=$?
expect "G4: a caller-relative --list ./hl from sub/ is read before the anchor (the root leak is found, exit 1)" 1 "$rc"

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
lone_mutant() {  # lone_mutant <name> <sed script>: as head_mutant, but in $WORK/lone beside leak-lib.sh (#206)
  # A --history mutant copied ALONE refuses for want of the library (exit 2) instead of losing or
  # keeping its finding. head_mutant stays in $WORK because the crash control below names its path.
  mkdir -p "$WORK/lone"; cp "$LIB" "$WORK/lone/"
  HMUT="$WORK/lone/mutant-head-$1.sh"; sed "$2" "$SCRIPT" > "$HMUT"; chmod +x "$HMUT"
  if cmp -s "$HMUT" "$SCRIPT"; then bad "mutant ledger ($1): the edit changed nothing"; return 1; fi
  ok "mutant ledger ($1): the scratch copy differs from the scanner"
}
if head_mutant worktree-read 's|^    head)   {.*$|    head)   scanfile="$f" ;;|'; then
  mkrepo hm-masked; hcommit leak.md 'secretproj\n'; printf 'edited out\n' > "$HREPO/leak.md"
  ( cd "$HREPO" && "$HMUT" --list "$WORK/hlist" --head ) >/dev/null 2>&1
  expect "mutant: reading the worktree file instead of HEAD misses the masked name (the masked case fails it)" 0 "$?"
fi
# The `HEAD:$f` (no `./`) mutant is retired (#401): the scan now runs from the root, where the two
# forms read the same blob, so it is equivalent. The anchor itself carries the mutants instead.
if head_mutant anchor-dropped '/^    \[ -n "\$top" \] && CDPATH= cd -- "\$top" || die/d'; then
  mkrepo hm-root
  ( cd "$HREPO" && printf 'secretproj\n' > leak.md && mkdir sub && printf 'clean\n' > sub/README.md \
    && git add -A && git commit -qm root ) >/dev/null 2>&1
  ( cd "$HREPO/sub" && "$HMUT" --list "$WORK/hlist" --all ) >/dev/null 2>&1
  expect "mutant: without the anchor a run from sub/ misses the root leak (G3 fails it)" 0 "$?"
fi
if head_mutant anchor-early 's|^ALLOW_FILE="\${ALLOW_FILE:-}"$|&; CDPATH= cd -- "$(git rev-parse --show-toplevel)"|'; then
  mkrepo hm-early
  ( cd "$HREPO" && printf 'secretproj\n' > leak.md && mkdir sub && printf 'clean\n' > sub/README.md \
    && git add -A && git commit -qm root ) >/dev/null 2>&1
  printf 'secretproj\n' > "$HREPO/sub/hl"
  ( cd "$HREPO/sub" && "$HMUT" --all --list ./hl ) >/dev/null 2>&1; rc=$?
  [ "$rc" != 1 ] && ok "mutant: an anchor ahead of the option reads resolves ./ against the root (G4 fails it, rc=$rc)" \
    || bad "mutant: an anchor ahead of the option reads resolves ./ against the root"
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

echo "== whole-word tokens: a line starting with = matches only a whole word (#222) =="
# A short username listed as a plain name is a substring of ordinary words (`ana` in `banana`), so
# it fired on whole translation files. `=ana` matches it as a word, with ASCII boundaries.
# wrow <list content> <text> [flags...]: a tree-mode scan of one file; OUT, ERR and RC set.
wrow() {
  printf '%b' "$1" > "$WORK/wlist"; printf '%s\n' "$2" > "$WORK/wsample.txt"; shift 2
  OUT="$("$SCRIPT" --list "$WORK/wlist" "$@" "$WORK/wsample.txt" 2>"$WORK/werr.txt")"; RC=$?
  ERR="$(cat "$WORK/werr.txt")"
}
wrow '=ana\n' 'see /proj/ana/notes';        expect "=ana: a whole word in a path is reported" 1 "$RC"
expect "and redacted like any other name" "$WORK/wsample.txt:1: private-name: an*" "$OUT"
wrow '=ana\n' 'banana analysis canal';      expect "=ana: inside longer words it is not reported" 0 "$RC"
expect "and nothing is printed" "" "$OUT"
wrow '=ana\n' 'quoted "ana" here';          expect "=ana: a quoted word is reported" 1 "$RC"
wrow '=ana\n' 'Ana.';                       expect "=ana: case insensitive, punctuation is a boundary" 1 "$RC"
wrow '=ana\n' 'ana-signals@1.0';            expect "=ana: - is not a word constituent, so ana-signals is reported" 1 "$RC"
wrow '=ana\n' 'ana_v2';                     expect "=ana: _ is a word constituent, so ana_v2 is not" 0 "$RC"
wrow '=ana\n' 'banana ana';                 expect "=ana: a word after a rejected occurrence on the line is still found" 1 "$RC"
wrow 'ana\n' 'banana';                      expect "a plain ana is still a substring: banana is reported" 1 "$RC"
wrow 'bramble\n' 'bramble-social';          expect "a plain bramble reports bramble-social (as before)" 1 "$RC"
wrow '=bramble\n' 'bramble-social';         expect "=bramble still reports bramble-social: = is not an exact-token rule" 1 "$RC"
wrow '=ana\n' 'ana was here';               expect "an all-= list still scans (the exit guard counts both lists)" 1 "$RC"
wrow '=ana\r\n' 'ana was here';             expect "a CRLF =ana line is trimmed like any other" 1 "$RC"
wrow '= ana\n' 'ana was here';              expect "= ana trims to the token ana" 1 "$RC"
expect "and refuses nothing" "" "$ERR"
wrow '=ana\n' 'mañana';                     expect "documented limit: an accented neighbour is a boundary, so mañana IS reported" 1 "$RC"
wrow '=ana\n' 'mañana' ; m_c="$RC"
OUT="$(LC_ALL=C.UTF-8 "$SCRIPT" --list "$WORK/wlist" "$WORK/wsample.txt" 2>/dev/null)"
expect "and the same under C.UTF-8 (the token grep is pinned to C)" "$m_c" "$?"

# Every refused shape exits 2 and names the list line; checked under C and under a UTF-8 locale,
# where a range glob would let an accented letter through on bash before 5.0.
for bad_tok in '=ab' '==ana' '=ana-' '=an a' '=' '=josé' '=aéa' '=ÉBC'; do
  for loc in C C.UTF-8; do
    printf 'keepme\n%s\n' "$bad_tok" > "$WORK/wlist"
    LC_ALL="$loc" "$SCRIPT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>"$WORK/werr.txt"; rc=$?
    expect "refused token '$bad_tok' ($loc) exits 2" 2 "$rc"
    contains "wlist:2:" "$(cat "$WORK/werr.txt")" "and names line 2 ($bad_tok, $loc)"
  done
done
printf '=josé\n' > "$WORK/wlist"
"$SCRIPT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>"$WORK/werr.txt"
lacks "josé" "$(cat "$WORK/werr.txt")" "a refused token is redacted in the message"
printf 'abcd\n' > "$WORK/wlist"; printf 'ab\n' >> "$WORK/wlist"
"$SCRIPT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>"$WORK/werr.txt"
expect "a plain two-letter name still dies as too short" 2 "$?"

echo "== whole-word tokens in every mode (#222) =="
mkrepo wmodes
( cd "$HREPO" && printf 'banana analysis canal\n' > clean.md && git add clean.md && git commit -qm c ) >/dev/null 2>&1
printf '=ana\n' > "$WORK/wl"
for mode in --all --head --staged '--range HEAD~1' --history; do
  # shellcheck disable=SC2086
  OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wl" $mode 2>/dev/null )"; rc=$?
  expect "=ana over banana analysis canal, $mode: exit 0" 0 "$rc"
done
( cd "$HREPO" && printf 'ping ana today\n' > hit.md && git add hit.md && git commit -qm h ) >/dev/null 2>&1
for mode in --all --head --staged '--range HEAD~1' --history; do
  [ "$mode" = --staged ] && printf 'ana again\n' > "$HREPO/staged.md" && ( cd "$HREPO" && git add staged.md )
  # shellcheck disable=SC2086
  OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wl" $mode 2>/dev/null )"; rc=$?
  expect "=ana over a bare ana, $mode: exit 1" 1 "$rc"
done

echo "== whole-word tokens under --history (#222) =="
printf '=ana\nbramble\n' > "$WORK/wh"
mkrepo wperm; hcommit p.md 'hobramblefoo\n'
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh" --history 2>/dev/null )"; rc=$?
expect "list =ana then bramble, line hobramblefoo: reported (the flag sorts with its name)" 1 "$rc"
expect "exactly one finding" 1 "$(printf '%s\n' "$OUT" | grep -c 'private-name')"
# The loader reads plain names before tokens, so the sort moves entries only when a token is
# longer than a plain name: =bramble with ana must keep ana a substring and bramble a word.
printf '=bramble\nana\n' > "$WORK/wp"
mkrepo wperm2; hcommit p.md 'banana\nhobramblefoo\n'
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wp" --history 2>/dev/null )"; rc=$?
expect "list =bramble and ana: banana reported, hobramblefoo not" "1 1 0" "$rc $(printf '%s\n' "$OUT" | grep -c 'p.md@[0-9a-f]*:1:') $(printf '%s\n' "$OUT" | grep -c 'p.md@[0-9a-f]*:2:')"
mkrepo wmixed; hcommit m.md 'bramble banana\n'
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh" --history --show-names 2>/dev/null )"; rc=$?
expect "bramble banana: exit 1" 1 "$rc"
expect "and exactly one finding, bramble" "1 1" "$(printf '%s\n' "$OUT" | grep -c 'private-name') $(printf '%s\n' "$OUT" | grep -c 'private-name: bramble$')"
mkrepo wboth; hcommit b.md 'bramble ana\n'
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh" --history 2>/dev/null )"; rc=$?
expect "bramble ana, a line matching both lists: exit 1" 1 "$rc"
expect "and exactly two findings, never doubled" 2 "$(printf '%s\n' "$OUT" | grep -c 'private-name')"
mkrepo wana; hcommit a.md 'Ana and banana\n'
printf '=ana\n' > "$WORK/wh1"
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh1" --history 2>/dev/null )"; rc=$?
expect "Ana and banana with =ana: exit 1" 1 "$rc"
expect "and exactly one finding on that line" 1 "$(printf '%s\n' "$OUT" | grep -c 'private-name')"
mkrepo wban; hcommit n.md 'banana\n'
( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh1" --history ) >/dev/null 2>&1
expect "history holding only banana with =ana: exit 0" 0 "$?"
mkrepo wred; hcommit r.md 'see /proj/ana/notes\n'
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh1" --history 2>/dev/null )"
contains "r.md@$(hoid HEAD:r.md):1: private-name: an*" "$OUT" "a token hit is redacted as a name hit is"
OUT="$( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh1" --history --show-names 2>/dev/null )"; rc=$?
contains "private-name: ana" "$OUT" "--show-names prints the token whole"
expect "and exits 1" 1 "$rc"
mkrepo wmanana; hcommit x.md 'mañana\n'
( cd "$HREPO" && "$SCRIPT" --list "$WORK/wh1" --history ) >/dev/null 2>&1
expect "documented limit under --history too: mañana IS reported for =ana" 1 "$?"

echo "== each list's grep runs only when that list has entries (#222) =="
# A grep shim first on PATH logs every invocation's arguments; only invocations carrying -f are
# counted, since --all also runs the `-Iq .` text probe on each file.
REALGREP="$(type -P grep)"; mkdir -p "$WORK/shim"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec %s "$@"\n' "$WORK/shim.log" "$REALGREP" > "$WORK/shim/grep"
chmod +x "$WORK/shim/grep"
mkrepo wshim; hcommit s.md 'nothing to see\n'
( cd "$HREPO" && git rm -q seed.md && git commit -qm one-file ) >/dev/null 2>&1   # one tracked file, one pattern grep
printf 'bramble\n' > "$WORK/ws"; : > "$WORK/shim.log"
( cd "$HREPO" && PATH="$WORK/shim:$PATH" "$SCRIPT" --list "$WORK/ws" --all ) >/dev/null 2>&1
flog="$(grep -e ' -f ' -e '^-f ' "$WORK/shim.log")"
expect "a substring-only list: exactly one invocation carrying -f" 1 "$(printf '%s\n' "$flog" | grep -c .)"
case "$flog" in *-noiFw*|*/words*) bad "and it is not the whole-word grep ($flog)" ;; *names*) ok "and it is the substring grep against the names file" ;; *) bad "and it is the substring grep ($flog)" ;; esac
printf '=ana\n' > "$WORK/ws"; : > "$WORK/shim.log"
( cd "$HREPO" && PATH="$WORK/shim:$PATH" "$SCRIPT" --list "$WORK/ws" --all ) >/dev/null 2>&1; rc=$?
flog="$(grep -e ' -f ' -e '^-f ' "$WORK/shim.log")"
expect "an all-= list: exactly one invocation carrying -f" 1 "$(printf '%s\n' "$flog" | grep -c .)"
case "$flog" in *-noiFw*words*) ok "and it is the whole-word grep against the words file" ;; *) bad "and it is the whole-word grep ($flog)" ;; esac
expect "and the clean tree exits 0" 0 "$rc"
: > "$WORK/shim.log"
( cd "$HREPO" && PATH="$WORK/shim:$PATH" "$SCRIPT" --list "$WORK/ws" --history ) >/dev/null 2>&1
flog="$(grep -e ' -f ' "$WORK/shim.log")"
expect "--history with an all-= list: one pre-filter carrying -f" 1 "$(printf '%s\n' "$flog" | grep -c .)"
lacks "/names" "$flog" "and the empty names file is not passed to it"

echo "== whole-word mutants (#222) =="
if lone_mutant w-perm-dropped 's/name\[j + 1\] = name\[j\]; wd\[j + 1\] = wd\[j\]; j--/name[j + 1] = name[j]; j--/; s/name\[j + 1\] = v; wd\[j + 1\] = vw/name[j + 1] = v/'; then
  mkrepo wm-perm; hcommit p.md 'banana\nhobramblefoo\n'
  OUT="$( cd "$HREPO" && "$HMUT" --list "$WORK/wp" --history 2>/dev/null )"
  expect "mutant: unpermuted flags swap the rules (ana a word, bramble a substring)" "0 1" "$(printf '%s\n' "$OUT" | grep -c 'p.md@[0-9a-f]*:1:') $(printf '%s\n' "$OUT" | grep -c 'p.md@[0-9a-f]*:2:')"
fi
if lone_mutant w-two-streams 's|^  LC_ALL=C grep -aiF "\${pf\[@\]}" "\$tagged" > "\$hits" \|\| true$|  { [ -s "$PATFILE" ] \&\& LC_ALL=C grep -aiF -f "$PATFILE" "$tagged"; [ -s "$WORDFILE" ] \&\& LC_ALL=C grep -aiF -f "$WORDFILE" "$tagged"; } > "$hits"|'; then
  mkrepo wm-two; hcommit b.md 'bramble ana\n'
  OUT="$( cd "$HREPO" && "$HMUT" --list "$WORK/wh" --history 2>/dev/null )"
  expect "mutant: two merged pre-filter streams double every finding" 4 "$(printf '%s\n' "$OUT" | grep -c 'private-name')"
fi
if head_mutant w-guard-names-only 's/^\[ \$(( \${#NAMES\[@\]} + \${#WORDS\[@\]} )) -gt 0 \] || exit 0$/[ "${#NAMES[@]}" -gt 0 ] || exit 0/'; then
  printf '=ana\n' > "$WORK/wlist"; printf 'ana was here\n' > "$WORK/wsample.txt"
  "$HMUT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>&1
  expect "mutant: an exit guard counting names only reads an all-= list as clean" 0 "$?"
fi
if lone_mutant w-boundary-dropped '/^          if (wd\[k\] && ((start > 1/,/free = 0$/d'; then
  mkrepo wm-bound; hcommit n.md 'banana\n'
  ( cd "$HREPO" && "$HMUT" --list "$WORK/wh1" --history ) >/dev/null 2>&1
  expect "mutant: without the awk boundary test banana is reported for =ana" 1 "$?"
fi
if head_mutant w-tree-no-w 's/LC_ALL=C grep -noiFw -f "\$WORDFILE"/LC_ALL=C grep -noiF -f "$WORDFILE"/'; then
  printf '=ana\n' > "$WORK/wlist"; printf 'banana\n' > "$WORK/wsample.txt"
  "$HMUT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>&1
  expect "mutant: the tree grep without -w reports banana for =ana" 1 "$?"
fi
if head_mutant w-edge-only 's/^        \*\[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_\]\*)$/        [!A-Za-z0-9_]*|*[!A-Za-z0-9_])/'; then
  printf '=an a\n' > "$WORK/wlist"
  "$HMUT" --list "$WORK/wlist" "$WORK/wsample.txt" >/dev/null 2>&1
  expect "mutant: an edge-only byte rule accepts =an a" 0 "$?"
fi
# Not run, recorded: the range glob `*[!A-Za-z0-9_]*` in place of the spelled-out set is EQUIVALENT
# on the bash 5 CI runs (globasciiranges is on there), so only bash before 5.0 would kill it.

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
contains "# =ana" "$(cat "$TEMPLATE" 2>/dev/null)" "it shows the whole-word form, commented out (#222)"
printf 'ana was here\n' > "$WORK/init-sample.txt"
"$SCRIPT" --list "$TEMPLATE" "$WORK/init-sample.txt" >/dev/null 2>&1
expect "and the fresh template holds no live entry: ana is not reported" 0 "$?"
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
