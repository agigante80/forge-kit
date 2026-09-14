#!/usr/bin/env bash
# Contract test for check-public-leaks.sh, the public half of the leak guard (#155, split from #99).
#
# WHY EVERY RULE GETS A NEAR-MISS CASE. All three rules are shape rules with an escape hatch, and a
# shape rule fails by being too eager, not by being too quiet. `/home/user/` has to survive, because
# a document explaining where a file lives has to say so; `~/projects` has to survive, because it is
# the canonical example root; `noreply@` has to survive, because it cannot reach a mailbox. A suite
# that only proved the patterns fire would ship a guard nobody can write documentation under, and
# the first response to that is to delete the guard.
#
# WHY THIS FILE IS IN forge-kit's OWN ALLOW-FILE. It is the one place a real-shaped home path and a
# real-shaped address must appear as literals. The samples are what prove the patterns can fire, and
# a guard that cannot fire reports a safety it is not providing. The scanner skips ITSELF without
# being asked (its own source carries the patterns); it skips this file only because forge-kit's
# allow-file says so, which is the general mechanism proving itself rather than a second exemption.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/check-public-leaks.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0; failed=0
ok()  { printf '  ok: %s\n' "$1"; passed=$((passed+1)); }
bad() { printf '  FAIL: %s\n' "$1"; failed=$((failed+1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in '$2')"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

# --- helpers ---------------------------------------------------------------
# Run the scanner over one file whose single line is $1. Echoes the exit code; output in $OUT.
OUT=""
scan_line() {
  local content="$1"; shift
  printf '%s\n' "$content" > "$WORK/sample.txt"
  OUT="$("$SCRIPT" "$@" "$WORK/sample.txt" 2>"$WORK/err.txt")"
  echo $?
}
# "does this line trip any rule?" as yes/no, which is what a near-miss case actually asserts.
trips() { local rc; rc="$(scan_line "$@")"; [ "$rc" = "1" ] && echo yes || echo no; }

echo "== rule A: absolute home paths, by shape =="
expect "a real /home/<name>/ path trips"        yes "$(trips '/home/alice/notes.txt')"
expect "a real /Users/<name>/ path trips"       yes "$(trips 'see /Users/bob/Desktop/x')"
expect "the /home/user/ placeholder survives"   no  "$(trips 'install to /home/user/.claude/')"
expect "the /home/<user>/ placeholder survives" no  "$(trips 'install to /home/<user>/.claude/')"
expect "the /home/.../ placeholder survives"    no  "$(trips 'install to /home/.../.claude/')"
expect "the /home/\$USER/ form survives"         no  "$(trips 'install to /home/$USER/.claude/')"
expect "/Users/username/ survives"              no  "$(trips 'install to /Users/username/x')"
expect "/home/ with no segment does not trip"   no  "$(trips 'the /home/ directory')"

echo "== rule B: ~/ roots, by allowlist =="
expect "an unlisted ~/ root trips"              yes "$(trips 'cloned into ~/secret-clients/thing')"
expect "~/projects survives"                    no  "$(trips 'cloned into ~/projects/thing')"
expect "~/.claude survives"                     no  "$(trips 'edit ~/.claude/settings.json')"
expect "~/.config survives"                     no  "$(trips 'edit ~/.config/app.toml')"
expect "~/dev survives"                         no  "$(trips 'cloned into ~/dev/thing')"
expect "~/code survives"                        no  "$(trips 'cloned into ~/code/thing')"
expect "~/src survives"                         no  "$(trips 'cloned into ~/src/thing')"
expect "~/work survives"                        no  "$(trips 'cloned into ~/work/thing')"
expect "the ~/<root> placeholder survives"      no  "$(trips 'cloned into ~/<root>/thing')"
expect "bare ~/ survives"                       no  "$(trips 'relative to ~/ itself')"
expect "a trailing period does not hide a root" yes "$(trips 'it lives in ~/acme-client.')"
expect "trailing punctuation is not part of the root" no "$(trips 'it lives in ~/projects.')"

echo "== rule C: email addresses =="
expect "a real address trips"                   yes "$(trips 'mail alice@realdomain.com for help')"
expect "noreply@ survives"                      no  "$(trips 'from noreply@github.com')"
expect "no-reply@ survives"                     no  "$(trips 'from no-reply@github.com')"
expect "example.com survives"                   no  "$(trips 'try someone@example.com')"
expect "the .invalid TLD survives"              no  "$(trips 'try someone@mail.invalid')"
expect "the .example TLD survives"              no  "$(trips 'try someone@mail.example')"
expect "a bare @mention does not trip"          no  "$(trips 'thanks @agigante80 for the fix')"
expect "the git@ SSH clone user survives"       no  "$(trips 'clone git@github.com:owner/repo.git')"

echo "== shapes the tree actually contains =="
# Every one of these was found by running the scanner over forge-kit's own tree. A rule that only
# meets its author's fixtures is a rule that has not met prose yet.
expect "a code-span root is read without its backtick" yes \
  "$(trips 'clone it into `~/acme-client`, then run')"
expect "and an allowed root in a code span still survives" no \
  "$(trips 'clone it into `~/projects`, then run')"
expect "~/.ssh survives"                        no  "$(trips 'add the key to ~/.ssh/config')"
expect "~/.bashrc survives"                     no  "$(trips 'export it from ~/.bashrc, then reload')"

echo "== the allow-file =="
cat > "$WORK/allow" <<'ALLOW'
# comment lines and blank lines are ignored

root ~/forge-kit
prefix /home/runner/
email a.gigante@gmail.com
skip docs/leaky.md
ALLOW
expect "an allowed root survives"     no  "$(trips 'cloned into ~/forge-kit/scripts' --allow-file "$WORK/allow")"
expect "an allowed prefix survives"   no  "$(trips 'runs under /home/runner/work/x' --allow-file "$WORK/allow")"
# The placeholder check strips trailing punctuation and the prefix check did not, so an allowed
# prefix at the end of a sentence, or inside brackets, reported a leak anyway.
expect "an allowed prefix survives a trailing period" no \
  "$(trips 'it lands in /home/runner.' --allow-file "$WORK/allow")"
expect "an allowed prefix survives being bracketed"   no \
  "$(trips 'it lands in (/home/runner), then builds' --allow-file "$WORK/allow")"
expect "an allowed address survives"  no  "$(trips 'author a.gigante@gmail.com' --allow-file "$WORK/allow")"
expect "allowing one root does not allow another" yes \
  "$(trips 'cloned into ~/other-thing/x' --allow-file "$WORK/allow")"

# Rule A's match is exactly one segment, so a prefix deeper than that can never equal it. Left
# unchecked, `prefix /home/runner/work/myrepo` parses cleanly and silently does nothing, which is
# the shape of config bug this component refuses rather than absorbs everywhere else.
printf 'prefix /home/runner/work/myrepo\n' > "$WORK/deep-allow"
"$SCRIPT" --allow-file "$WORK/deep-allow" "$WORK/sample.txt" >/dev/null 2>"$WORK/err.txt"
expect "a prefix deeper than one segment refuses the run" 2 "$?"
contains "one segment" "$(cat "$WORK/err.txt")" "and explains that rule A judges one segment"

printf 'x\n' > "$WORK/sample.txt"
"$SCRIPT" --allow-file "$WORK/nope" "$WORK/sample.txt" >/dev/null 2>&1
expect "a missing allow-file refuses the run" 2 "$?"

printf 'nonsense line\n' > "$WORK/bad-allow"
"$SCRIPT" --allow-file "$WORK/bad-allow" "$WORK/sample.txt" >/dev/null 2>&1
expect "an unparseable allow-file line refuses the whole run" 2 "$?"

echo "== output shape and exit codes =="
printf 'clean line\n' > "$WORK/sample.txt"
"$SCRIPT" "$WORK/sample.txt" >/dev/null 2>&1
expect "a clean file exits 0" 0 "$?"

printf 'one\n/home/alice/x\nthree\n' > "$WORK/shape.txt"
OUT="$("$SCRIPT" "$WORK/shape.txt" 2>/dev/null)"
expect "violations exit 1" 1 "$?"
expect "the report names file, line, rule and evidence" \
  "$WORK/shape.txt:2: home-path: /home/alice/" "$OUT"

printf '/home/alice/x\n~/acme/y\n' > "$WORK/two.txt"
OUT="$("$SCRIPT" "$WORK/two.txt" 2>/dev/null)"
expect "two violations report as two lines" 2 "$(printf '%s\n' "$OUT" | grep -c ':')"

"$SCRIPT" --nonsense "$WORK/sample.txt" >/dev/null 2>&1
expect "an unknown flag refuses the run" 2 "$?"

echo "== what is not scanned =="
printf '/home/alice/x\n' > "$WORK/skipme.png"
"$SCRIPT" "$WORK/skipme.png" >/dev/null 2>&1
expect "a binary suffix is skipped" 0 "$?"

printf '/home/alice/x\n' > "$WORK/package-lock.json"
"$SCRIPT" "$WORK/package-lock.json" >/dev/null 2>&1
expect "a lockfile is skipped" 0 "$?"

printf '/home/alice/x\n\000\000binary\n' > "$WORK/blob.dat"
OUT="$("$SCRIPT" "$WORK/blob.dat" 2>"$WORK/err.txt")"
rc=$?
expect "a null-byte file is treated as binary and skipped" 0 "$rc"
expect "and it produces no stderr warnings" "" "$(cat "$WORK/err.txt")"

"$SCRIPT" "$SCRIPT" >/dev/null 2>&1
expect "the scanner never reports itself" 0 "$?"

mkdir -p "$WORK/docs"
printf '/home/alice/x\n' > "$WORK/docs/leaky.md"
( cd "$WORK" && "$SCRIPT" --allow-file "$WORK/allow" docs/leaky.md ) >/dev/null 2>&1
expect "a skip entry excludes that path" 0 "$?"

echo "== git modes =="
REPO="$WORK/repo"
mkdir -p "$REPO" && ( cd "$REPO"
  git init -q . && git config user.email t@t.invalid && git config user.name t
  printf 'clean\n' > tracked.md
  git add tracked.md && git commit -qm base
) >/dev/null 2>&1
BASE="$(cd "$REPO" && git rev-parse HEAD)"

printf '/home/alice/x\n' > "$REPO/untracked.md"
( cd "$REPO" && "$SCRIPT" --all ) >/dev/null 2>&1
expect "--all ignores an untracked file" 0 "$?"

( cd "$REPO" && git add untracked.md )
( cd "$REPO" && "$SCRIPT" --all ) >/dev/null 2>&1
expect "--all reports a tracked file once it is added" 1 "$?"

( cd "$REPO" && git commit -qm add >/dev/null )
printf '/home/bob/y\n' > "$REPO/worktree-only.md"
( cd "$REPO" && "$SCRIPT" --staged ) >/dev/null 2>&1
expect "--staged ignores an unstaged worktree change" 0 "$?"

( cd "$REPO" && git add worktree-only.md && "$SCRIPT" --staged ) >/dev/null 2>&1
expect "--staged reports staged content" 1 "$?"

( cd "$REPO" && git commit -qm second >/dev/null )
( cd "$REPO" && "$SCRIPT" --range "$BASE" ) >/dev/null 2>&1
expect "--range reports a file changed since the base" 1 "$?"

( cd "$REPO" && "$SCRIPT" --range HEAD ) >/dev/null 2>&1
expect "--range over an empty range is clean" 0 "$?"

( cd "$REPO" && "$SCRIPT" --range deadbeefdeadbeefdeadbeefdeadbeefdeadbeef ) >/dev/null 2>&1
expect "--range refuses a base ref that does not exist" 2 "$?"

echo "== the shipped asset is a component =="
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SCRIPT" \
  && ok "carries a version marker" || bad "carries a version marker"
grep -qi 'would not have caught' "$SCRIPT" \
  && ok "states its own limit of reach in the source" \
  || bad "states its own limit of reach in the source"
# The reach statement was incomplete, and a review found the gap: both rules judge the FIRST path
# segment only, so a private directory NAME below an allowed root is invisible to the public half.
grep -qi 'first segment' "$SCRIPT" \
  && ok "and discloses that only the first path segment is judged" \
  || bad "and discloses that only the first path segment is judged"


echo "== the scanner skips itself in EVERY mode, not just when read from disk =="
# Found by the pre-commit hook, on this component's own commit. In --staged and --range the file
# being read is a temp blob, so comparing the SCANNED path to the script's own path never matches
# and the guard reports its own source as a leak. Every project that vendors the asset into its
# tree and wires the commit hook hits this on the commit that installs it.
SELFREPO="$WORK/selfrepo"; mkdir -p "$SELFREPO/scripts"
( cd "$SELFREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t
  printf 'x\n' > seed.md && git add seed.md && git commit -qm seed ) >/dev/null 2>&1
cp "$SCRIPT" "$SELFREPO/scripts/check-public-leaks.sh"
cp "$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh" \
   "$SELFREPO/scripts/check-private-leaks.sh"
( cd "$SELFREPO" && git add scripts && ./scripts/check-public-leaks.sh --staged ) >/dev/null 2>&1
expect "--staged does not report the public scanner's own source" 0 "$?"
( cd "$SELFREPO" && git commit -qm add >/dev/null 2>&1
  ./scripts/check-public-leaks.sh --range HEAD~1 ) >/dev/null 2>&1
expect "--range does not report it either" 0 "$?"
( cd "$SELFREPO" && ./scripts/check-public-leaks.sh --all ) >/dev/null 2>&1
expect "--all does not report it either" 0 "$?"


echo "== --history: the publishable history, read by declared byte length =="
# MUTANTS RUN AGAINST THESE SECTIONS (2026-09-14), each by editing a scratch copy of the scanner and
# confirming the edit applied; recorded here so the claim can be re-run rather than trusted. Killed:
# the r<0 gate replaced by a shape test (the case below runs it); NUL objects not dropped; -m dropped
# from the path map; GIT_OBJECT_DIRECTORY, alternates, unreadable-object and grafts refusals removed;
# redaction disabled; commit headers scanned as body; self-skip by content alone; self basename not
# recognised; refs/replace honoured; every -c override dropped; the map shape check weakened;
# --remotes dropped; the --orphans content test applied to every object; the reader stage's status
# unchecked; the merge group's first stage failing. Equivalent (no observable difference, kept for
# hygiene): the terminator record emitted (an empty line matches nothing), the buffer cleared on drop
# (memory only). Not killable in CI: a regex over the path line (aborts only under Apple's awk).
# Every case runs against a throwaway repository built here, never against this one. A helper
# makes a fresh repo per scenario so no case can lean on another's objects.
HREPO=""
mkrepo() {  # mkrepo <name>: a fresh repository, cwd-independent; sets HREPO
  HREPO="$WORK/hist-$1"; rm -rf "$HREPO"; mkdir -p "$HREPO"
  ( cd "$HREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t \
    && printf 'seed\n' > seed.md && git add seed.md && git commit -qm seed ) >/dev/null 2>&1
}
hcommit() {  # hcommit <file> <content-printf-format> [msg]: write, add, commit in HREPO
  ( cd "$HREPO" && printf "$2" > "$1" && git add -- "$1" && git commit -qm "${3:-add $1}" ) >/dev/null 2>&1
}
hrun() {  # hrun [flags]: run the scanner in HREPO; output in OUT, stderr in ERR, exit code in RC.
  # Sets variables rather than echoing the code: a caller's $(...) would run this in a subshell
  # and lose OUT, which is exactly what happened on the first run of this section.
  OUT="$( cd "$HREPO" && "$SCRIPT" "$@" 2>"$WORK/herr.txt" )"; RC=$?; ERR="$(cat "$WORK/herr.txt")"
}
hoid() { ( cd "$HREPO" && git rev-parse "$1" ); }

mkrepo deleted
hcommit leak.md 'see /home/alice/proj/x\n'
( cd "$HREPO" && git rm -q leak.md && git commit -qm remove ) >/dev/null 2>&1
hrun --all; rc=$RC; expect "a leak committed then deleted is invisible to --all" 0 "$rc"
hrun --history; rc=$RC; expect "and --history finds it" 1 "$rc"
contains "leak.md@$(hoid HEAD~1:leak.md):1: home-path: /home/al***/" "$OUT" "at <path>@<oid>:<line>, evidence redacted"
n="$(printf '%s\n' "$OUT" | grep -c .)"; expect "exactly one line" 1 "$n"

echo "== --history: orphans are opt-in, and the help text says what carries them =="
mkrepo orphan
hcommit oops.md 'oops /home/grace/\n' oops
( cd "$HREPO" && git rm -q oops.md && git commit -q --amend --allow-empty -m fixed ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "an amended-away leak is not in the publishable set" 0 "$rc"
hrun --history --orphans; rc=$RC; expect "--orphans reaches it" 1 "$rc"
contains "blob@" "$OUT" "labelled blob@<oid> since no path is known"
contains "home-path: /home/gr***/" "$OUT" "and redacted"
( cd "$HREPO" && git reflog expire --expire=now --all && git gc -q --prune=now ) >/dev/null 2>&1
hrun --history --orphans; rc=$RC; expect "after the prune step nothing is left to find" 0 "$rc"
h="$("$SCRIPT" --help 2>&1)"
contains "clone over a URL never" "$h" "--help says a push, a bundle and a URL clone never send orphans"
contains "local PATH" "$h" "and that a local-path clone does"
contains "weaker content test" "$h" "and that the self-skip under --orphans is the weaker content test"

echo "== --history: a forged batch header hides nothing, and the mutant proves the counting is load-bearing =="
# Line 1 is shaped exactly like a cat-file header declaring a huge size; a reader that trusted it
# would wait for 999999 bytes and never emit the line after it. The reader counts the real
# object's bytes and reaches line 2.
mkrepo forged
hcommit forged.md '0000000000000000000000000000000000000000 blob 999999\n/home/alice/x\n'
hrun --history; rc=$RC; expect "the leak after a forged header is reported" 1 "$rc"
contains "forged.md@$(hoid HEAD:forged.md):2: home-path: /home/al***/" "$OUT" "at line 2"
# The mutant: the same scanner with the reader's r<0 gate replaced by a shape test, so any line
# that LOOKS like a header is taken as one. It must exit 0 here, or the gate was never doing work.
MUT="$WORK/mutant-public.sh"
sed 's/^r < 0 {$/NF == 3 \&\& length($1) == 40 \&\& $3 ~ \/^[0-9]+$\/ {/' "$SCRIPT" > "$MUT"; chmod +x "$MUT"
grep -q '^r < 0 {$' "$SCRIPT" && ok "the scanner carries the r<0 gate the mutant removes" || bad "the scanner carries the r<0 gate the mutant removes"
grep -q '^r < 0 {$' "$MUT" && bad "the mutant no longer carries it" || ok "the mutant no longer carries it"
( cd "$HREPO" && "$MUT" --history ) >/dev/null 2>&1
expect "the mutant misses the leak (exit 0)" 0 "$?"

echo "== --history: an object is scanned unless EVERY path it ever had is skipped =="
mkrepo twins
( cd "$HREPO" && printf 'same /home/alice/x\n' > zzz.md && cp zzz.md aaa.lock && git add zzz.md aaa.lock && git commit -qm twins ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "identical content at zzz.md and aaa.lock is reported" 1 "$rc"
n="$(printf '%s\n' "$OUT" | grep -cF "@$(hoid HEAD:zzz.md):1: home-path: /home/al***/")"; expect "exactly once" 1 "$n"
contains "zzz.md@" "$OUT" "at the path that is not skipped"
printf 'skip zzz.md\n' > "$WORK/hallow"
hrun --history --allow-file "$WORK/hallow"; rc=$RC; expect "with zzz.md skipped by the allow-file, every path is skipped and it is not reported" 0 "$rc"
( cd "$HREPO" && cp zzz.md keep.md && git add keep.md && git commit -qm keep ) >/dev/null 2>&1
hrun --history --allow-file "$WORK/hallow"; rc=$RC; expect "a third, unskipped path brings it back" 1 "$rc"
contains "keep.md@" "$OUT" "reported at that path"
mkrepo locks
( cd "$HREPO" && printf 'same /home/alice/x\n' > aaa.lock && cp aaa.lock bbb.lock && git add aaa.lock bbb.lock && git commit -qm locks ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "content that only ever lived in lockfiles is not reported" 0 "$rc"
# A merge commit resolved to content in neither parent, and a file that exists only in the merge:
# without -m on the path map, neither has an entry and the every-path rule would skip them vacuously.
mkrepo merge
hcommit f.txt 'base\n'
( cd "$HREPO" && git checkout -q -b side && printf 'side\n' > f.txt && git commit -qam side \
  && git checkout -q master 2>/dev/null || git checkout -q main; printf 'main\n' > f.txt && git commit -qam main
  git merge -q --no-commit side >/dev/null 2>&1; printf 'evil /home/alice/x\n' > f.txt; printf 'only /home/bob/y\n' > only-in-merge.txt
  git add f.txt only-in-merge.txt && git commit -qm merged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "an evil merge is reported" 1 "$rc"
contains "f.txt@" "$OUT" "the resolved file"
contains "only-in-merge.txt@" "$OUT" "and the merge-only file"
# The case -m actually decides: rev-list gives every reachable blob ONE path, so the map only
# matters when that path is skipped and the other exists only in the merge. Here the same content
# lands at x.lock (rev-list's pick, sorted first, a lockfile) and x.md in the merge commit alone.
mkrepo mergelock
hcommit f.txt 'base\n'
( cd "$HREPO" && git checkout -q -b side2 && printf 'side\n' > f.txt && git commit -qam side \
  && { git checkout -q master 2>/dev/null || git checkout -q main; }; printf 'main\n' > f.txt && git commit -qam main
  git merge -q --no-commit side2 >/dev/null 2>&1; printf 'twin /home/alice/x\n' > x.lock; cp x.lock x.md
  git add f.txt x.lock x.md && git commit -qm merged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "content at a lockfile AND a merge-only path is reported" 1 "$rc"
contains "x.md@" "$OUT" "at the path the map (with -m) supplies"

echo "== --history: foreign stores are refused =="
mkrepo origin
hcommit notes.md '/home/alice/x\n'
hrun --history; rc=$RC; expect "an ordinary repository with one leaking blob reports it" 1 "$rc"
contains "notes.md@$(hoid HEAD:notes.md):1: home-path: /home/al***/" "$OUT" "at its path"
ORIG="$HREPO"
git clone -q --shared "$ORIG" "$WORK/hist-shared" >/dev/null 2>&1
HREPO="$WORK/hist-shared"
hrun --history; rc=$RC; expect "a --shared clone is refused" 2 "$rc"
contains "refusing --history: objects/info/alternates points outside this repository" "$ERR" "and says why"
( cd "$WORK/hist-shared" && git worktree add -q "$WORK/hist-linked" -b linked ) >/dev/null 2>&1
HREPO="$WORK/hist-linked"
hrun --history; rc=$RC; expect "a linked worktree inside it (.git is a file) is refused too" 2 "$rc"
contains "alternates" "$ERR" "through git rev-parse --git-path, not a literal path"
HREPO="$ORIG"
OUT="$( cd "$HREPO" && GIT_ALTERNATE_OBJECT_DIRECTORIES=/nonexistent "$SCRIPT" --history 2>"$WORK/herr.txt" )"; rc=$?
expect "GIT_ALTERNATE_OBJECT_DIRECTORIES set is refused" 2 "$rc"
contains "refusing --history: GIT_ALTERNATE_OBJECT_DIRECTORIES is set" "$(cat "$WORK/herr.txt")" "by name"
OUT="$( cd "$HREPO" && GIT_OBJECT_DIRECTORY="$WORK/hist-shared/.git/objects" "$SCRIPT" --history 2>"$WORK/herr.txt" )"; rc=$?
expect "GIT_OBJECT_DIRECTORY set is refused" 2 "$rc"
contains "refusing --history: GIT_OBJECT_DIRECTORY is set" "$(cat "$WORK/herr.txt")" "by name"
( cd "$ORIG" && git config uploadpack.allowFilter true )
git clone -q --filter=blob:none "file://$ORIG" "$WORK/hist-partial" >/dev/null 2>&1
HREPO="$WORK/hist-partial"
hrun --history; rc=$RC; expect "a partial clone is refused" 2 "$rc"
contains "this is a partial clone; --history would fetch every missing object from origin" "$ERR" "naming the remote"

echo "== --history: commit and tag messages are in scope, identity lines are not =="
mkrepo messages
( cd "$HREPO" && git commit -q --allow-empty -m 'fix /home/alice/x' ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a leak in a commit SUBJECT is reported" 1 "$rc"
c="$(hoid HEAD)"; ln="$( cd "$HREPO" && git cat-file -p "$c" | grep -n '/home/alice' | cut -d: -f1 )"
contains "commit@$c:$ln: home-path: /home/al***/" "$OUT" "as commit@<oid>:<line of git cat-file -p>"
( cd "$HREPO" && git tag -a v1 -m 'release' -m 'thanks, see /home/alice/x' ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a leak in an annotated tag message is reported" 1 "$rc"
t="$(hoid v1)"; ln="$( cd "$HREPO" && git cat-file -p "$t" | grep -n '/home/alice' | cut -d: -f1 )"
contains "tag@$t:$ln: home-path: /home/al***/" "$OUT" "as tag@<oid>:<line>"
mkrepo identity
( cd "$HREPO" && git commit -q --allow-empty --author='Alice <alice@corp.io>' -m 'clean subject' -m 'clean body' ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "an address on the author line is not reported" 0 "$rc"

echo "== --history: evidence is redacted by default, shown on request =="
mkrepo redact
hcommit three.md '/home/alice/x\n~/secret-clients/y\nalice@corp.io\n'
hrun --history; rc=$RC; expect "three leaks reported" 1 "$rc"
contains ":1: home-path: /home/al***/" "$OUT" "the username segment is redacted"
contains ':2: home-root: ~/se************/' "$OUT" "the ~/ root is redacted"
contains ':3: email: al***********' "$OUT" "the whole address is redacted (corp.example would be exempt as an RFC 2606 TLD)"
hrun --history --show-evidence; rc=$RC; expect "--show-evidence still reports" 1 "$rc"
contains ':1: home-path: /home/alice/' "$OUT" "the path whole"
contains ':2: home-root: ~/secret-clients/' "$OUT" "the root whole"
contains ':3: email: alice@corp.io' "$OUT" "the address whole"
hrun --all --show-evidence; rc=$RC; expect "--show-evidence without --history is refused" 2 "$rc"
contains "--show-evidence is only valid with --history" "$ERR" "and says so"

echo "== --history: a mode, not a flag =="
hrun --history three.md; rc=$RC; expect "--history with a path is refused" 2 "$rc"
contains "--history takes no paths" "$ERR" "and says so"
hrun --orphans; rc=$RC; expect "--orphans without --history is refused" 2 "$rc"
contains "--orphans is only valid with --history" "$ERR" "and says so"

echo "== --history: a binary object blinds nothing after it =="
mkrepo binary
( cd "$HREPO" && printf 'bin\0ary /home/bob/y\n' > bin.dat && git add bin.dat && git commit -qm bin ) >/dev/null 2>&1
hcommit text.md '/home/alice/x\n'
hrun --history; rc=$RC; expect "the text blob after a NUL blob is reported" 1 "$rc"
n="$(printf '%s\n' "$OUT" | grep -c .)"; expect "and only it" 1 "$n"
contains "text.md@" "$OUT" "at its path"
mkrepo binonly
( cd "$HREPO" && printf 'bin\0ary /home/bob/y\n' > bin.dat && git add bin.dat && git commit -qm bin ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a leak only inside a NUL blob is not reported, as in the tree modes" 0 "$rc"

echo "== --history: the platform claims live here, not in the header =="
mkrepo bytes
hcommit utf8.md 'prose with an em dash \342\200\224 and caf\303\251 before it\n/home/alice/x\n'
( cd "$HREPO" && { head -c 9000 /dev/zero | tr '\0' a; printf '\n/home/alice/x\n'; } > long.md && git add long.md && git commit -qm long ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "leaks after a multibyte line and after a 9000-byte line are reported" 1 "$rc"
contains "utf8.md@$(hoid HEAD:utf8.md):2:" "$OUT" "the one after the UTF-8 line, at line 2"
contains "long.md@$(hoid HEAD:long.md):2:" "$OUT" "the one after the long line, at line 2"
( cd "$HREPO" && printf 'caf\351 latin-1 then /home/alice/x\n' > latin.md && git add latin.md && git commit -qm latin ) >/dev/null 2>&1
# Pins the behaviour, not the flag: under LC_ALL=C GNU grep calls nothing here binary (no NUL
# survives tr), so -a is defence in depth for other greps and this case cannot tell them apart.
hrun --history; rc=$RC; expect "a leak on a line with an invalid UTF-8 byte is reported" 1 "$rc"
contains "latin.md@" "$OUT" "at its path"

echo "== --history: the self-skip is an identity test, not a content test =="
mkrepo self
( cd "$HREPO" && mkdir -p old && cp "$SCRIPT" old/check-public-leaks.sh && git add old && git commit -qm old ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a past copy of the scanner at another path is not reported" 0 "$rc"
( cd "$HREPO" && printf '#!/usr/bin/env bash\n# check-public-leaks-version: 3\n#\n# a document QUOTING the marker\n#\n/home/alice/x\n' > docs-notes.md && git add docs-notes.md && git commit -qm quote ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a document quoting the marker line is not self" 1 "$rc"
contains "docs-notes.md@$(hoid HEAD:docs-notes.md):6: home-path: /home/al***/" "$OUT" "and its leak is reported at line 6"
mkrepo selforphan
( cd "$HREPO" && cp "$SCRIPT" check-public-leaks.sh && git add check-public-leaks.sh && git commit -qm copy \
  && git rm -q check-public-leaks.sh && git commit -q --amend --allow-empty -m gone ) >/dev/null 2>&1
hrun --history --orphans; rc=$RC; expect "a nameless past copy under --orphans is skipped by the content test" 0 "$rc"


echo "== --history: the path map survives user git config, and refuses what it cannot parse =="
# Each of these was reproduced hiding a reachable leak in review: the map desynchronised or lost
# entries, and the every-path rule then suppressed a blob whose rev-list path was a lockfile.
# The shape that log.diffMerges decides: content at a lockfile in an ordinary commit, and at a
# real name ONLY through a merge resolution. With log.diffMerges=off the merge's diff is omitted
# from --raw, the map has no zzz.md entry, and rev-list's aaa.lock is the only path: suppressed.
# (log.diffMerges=combined is refused by the shape check instead; log.showSignature needs a signed
# commit, and a signing key is not something this suite can assume: the -c override stands
# unexercised for it, and the shape check would refuse the injected lines anyway.)
mkrepo cfg
hcommit f.txt 'base\n'
( cd "$HREPO" && printf 'twin /home/alice/x\n' > aaa.lock && git add aaa.lock && git commit -qm lock \
  && git checkout -q -b side3 && printf 'side\n' > f.txt && git commit -qam side \
  && { git checkout -q master 2>/dev/null || git checkout -q main; }; printf 'main\n' > f.txt && git commit -qam main
  git merge -q --no-commit side3 >/dev/null 2>&1; cp aaa.lock zzz.md; git add f.txt zzz.md && git commit -qm merged ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "the merge-only twin is reported with default config" 1 "$rc"
for cfg in log.diffMerges=off log.diffMerges=combined; do
  ( cd "$HREPO" && git config "${cfg%%=*}" "${cfg#*=}" )
  hrun --history; rc=$RC; expect "with $cfg set it is still reported" 1 "$rc"
  ( cd "$HREPO" && git config --unset "${cfg%%=*}" )
done
mkrepo rootonly
( cd "$HREPO" && git checkout -q --orphan fresh && git rm -qrf . && printf 'twin /home/alice/x\n' > aaa.lock && cp aaa.lock zzz.md \
  && git add aaa.lock zzz.md && git commit -qm root && { git branch -q -D master 2>/dev/null || git branch -q -D main 2>/dev/null; }; git config log.showRoot false ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "twins in a ROOT commit with log.showRoot=false are still reported" 1 "$rc"
mkrepo subdir
( cd "$HREPO" && mkdir sub && printf 'twin /home/alice/x\n' > aaa.lock && cp aaa.lock zzz.md && git add aaa.lock zzz.md && git commit -qm twins && git config diff.relative true ) >/dev/null 2>&1
OUT="$( cd "$HREPO/sub" && "$SCRIPT" --history 2>/dev/null )"; rc=$?
expect "run from a subdirectory with diff.relative=true, the twins are still reported" 1 "$rc"
mkrepo newline
( cd "$HREPO" && printf 'twin /home/alice/x\n' > aaa.lock && cp aaa.lock zzz.md && git add aaa.lock zzz.md && git commit -qm twins \
  && printf 'x\n' > "$(printf 'weird\nname.txt')" && git add . && git commit -qm weird ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a path containing a newline makes the map unparseable, and the scan refuses" 2 "$rc"
contains "path map desynchronised" "$ERR" "saying so"

echo "== --history: a store git cannot read in full is refused, never scanned partially =="
mkrepo corrupt
hcommit leak.md '/home/alice/x\n'
# Loose objects are written read-only, so the file is removed and rewritten, not overwritten.
( cd "$HREPO" && o="$(git rev-parse HEAD:leak.md)" && f=".git/objects/${o:0:2}/${o:2}" && rm -f "$f" && printf 'garbage' > "$f" ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a corrupt loose object refuses the scan" 2 "$rc"
contains "cannot read every object" "$ERR" "and says which"
# A corrupt PACK is different: --batch-check still lists the object, and git cat-file --batch dies
# mid-stream. The reader pipeline's status check is what refuses it.
mkrepo corruptpack
hcommit leak.md '/home/alice/x\n'
( cd "$HREPO" && git gc -q && pack="$(ls .git/objects/pack/*.pack | head -1)" && chmod u+w "$pack" \
  && sz="$(wc -c < "$pack")" && printf 'XXXXXXXX' | dd of="$pack" bs=1 seek=$((sz / 2)) conv=notrunc ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a corrupt pack refuses the scan rather than reporting what was read" 2 "$rc"

echo "== --history: what git shows is not always what a push sends =="
mkrepo replace
hcommit leak.md '/home/alice/x\n'
( cd "$HREPO" && leaky="$(git rev-parse HEAD)" && git rm -q leak.md && git commit -qm clean && git replace "$leaky" HEAD ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a commit hidden by git replace is still scanned (a push sends it)" 1 "$rc"
contains "leak.md@" "$OUT" "at its path"
( cd "$HREPO" && git replace -d "$(git replace -l)" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > .git/info/grafts ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a grafts file is refused, since it cannot be switched off" 2 "$rc"
contains "grafts" "$ERR" "and named"

echo "== --history: a branch that exists only on the remote is publishable =="
mkrepo remoteonly
( cd "$HREPO" && git init -q --bare "$WORK/hist-bare" && git remote add origin "$WORK/hist-bare" \
  && git checkout -q -b wip && printf '/home/alice/x\n' > wip.md && git add wip.md && git commit -qm wip \
  && git push -q origin wip && { git checkout -q master 2>/dev/null || git checkout -q main; } && git branch -q -D wip ) >/dev/null 2>&1
hrun --history; rc=$RC; expect "a leak on a branch deleted locally but pushed is reported" 1 "$rc"
contains "wip.md@" "$OUT" "at its path, not as an orphan"

echo "== --history: --orphans never narrows what --history reports =="
mkrepo widen
( cd "$HREPO" && printf '#!/usr/bin/env bash\n# check-public-leaks-version: 3\n#\n/home/alice/x\n' > quoting.md && git add quoting.md && git commit -qm q ) >/dev/null 2>&1
hrun --history; rc=$RC;           expect "a reachable document quoting the marker is reported by --history" 1 "$rc"
hrun --history --orphans; rc=$RC; expect "and still by --history --orphans (the content test is for pathless objects only)" 1 "$rc"

echo "== --history: shapes the store can take =="
mkrepo cjk
( cd "$HREPO" && printf '/home/alice/x\n' > "$(printf '\303\251tude.md')" && git add . && git commit -qm accent ) >/dev/null 2>&1
# Can only fail under Apple's awk (a regex over that path line aborts it); under gawk or mawk it
# passes whatever the code does, so it is a floor case, not a CI case.
hrun --history; rc=$RC; expect "a path whose first byte is over 0x7F is scanned (no regex over a path line)" 1 "$rc"
mkrepo bareclone
hcommit leak.md '/home/alice/x\n'
git clone -q --bare "$HREPO" "$WORK/hist-bare2" >/dev/null 2>&1
HREPO="$WORK/hist-bare2"
hrun --history; rc=$RC; expect "a bare repository is scanned (no work tree needed)" 1 "$rc"
if git init -q --object-format=sha256 "$WORK/hist-sha256" >/dev/null 2>&1; then
  HREPO="$WORK/hist-sha256"
  ( cd "$HREPO" && git config user.email t@t.invalid && git config user.name t && printf '/home/alice/x\n' > leak.md && git add leak.md && git commit -qm leak ) >/dev/null 2>&1
  hrun --history; rc=$RC; expect "a SHA-256 repository is scanned (64-hex headers)" 1 "$rc"
  contains "leak.md@" "$OUT" "at its path"
else
  ok "SHA-256 repositories: this git cannot create one, case skipped"
fi

echo "== --help does not go stale when the header is edited =="
# It printed a hardcoded line range, so growing the header by seven lines truncated the output
# mid-sentence and dropped the usage synopsis entirely. A help text that silently rots is worse
# than none, because it reads as current.
for asset in "$SCRIPT" "$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh"; do
  a="$(basename "$asset")"
  h="$("$asset" --help 2>&1)"
  contains "$a [--staged" "$h" "$a --help shows its usage synopsis"
  contains "Exit 0 clean" "$h" "$a --help shows its exit-code contract"
  grep -q "sed -n '[0-9]*,[0-9]*p'" "$asset" \
    && bad "$a --help does not print a hardcoded line range" \
    || ok "$a --help does not print a hardcoded line range"
done
# The reach sentence #198 added is each scanner's own statement about itself, so it is pinned by
# that scanner's suite rather than by the generic loop above (#199). The needle is the shared core
# both headers print on one --help line; the reason after it is prose and may be reworded.
contains 'pass `grep -a` over a `git cat-file --batch` stream' "$("$SCRIPT" --help 2>&1)" \
  "check-public-leaks.sh --help states the grep -a rule for scanning the store by hand"
# The history limit is the one most likely to matter (#185) and was pinned nowhere until #200. Two
# needles, each occurring exactly once in this scanner's --help: the limit and the pointer past it.
# `gitleaks` itself is named twice there, so it is not the needle.
h="$("$SCRIPT" --help 2>&1)"
# #191 replaced the "never looks at history" limit with the opt-in mode; these pin what the header
# now claims: the tree modes still never look, --history reads the publishable history, and it is
# never a hook.
contains 'tree modes never look at history' "$h" "check-public-leaks.sh --help states that the tree modes never look at history"
contains 'reads the publishable history' "$h" "check-public-leaks.sh --help states what --history reads"
contains 'never wired into a hook' "$h" "check-public-leaks.sh --help states that --history is never a hook"

echo "== portability, because this ships into other people's repositories =="
# Both leak scanners were the first files in this tree to reach for bash-4-only expansions and GNU
# readlink. macOS still ships bash 3.2 and BSD readlink, which has no -f, and a shipped component
# that dies on a contributor's laptop gets removed rather than reported. Enforced mechanically
# because the failure is invisible on the machine that wrote it.
# Comments are stripped first, so the constructs may still be NAMED in the prose that explains why
# they are avoided. The bash-4 expansion is allowed exactly once, inside the version-gated helper:
# banning it outright would force the slow path onto every platform, and allowing it freely is the
# bug. One occurrence plus a BASH_VERSINFO gate is the shape that means "fast path, guarded".
code() { grep -v '^[[:space:]]*#' "$1"; }
for asset in "$SCRIPT" "$ROOT/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh"; do
  a="$(basename "$asset")"
  n="$(code "$asset" | grep -c ',,}')"
  expect "$a uses the bash-4 lowercase expansion exactly once" 1 "$n"
  grep -q 'BASH_VERSINFO' "$asset" \
    && ok "$a gates it on the bash version" || bad "$a gates it on the bash version"
  code "$asset" | grep -q 'readlink -f' \
    && bad "$a avoids GNU-only readlink -f" || ok "$a avoids GNU-only readlink -f"
  grep -q 'pwd -P' "$asset" \
    && ok "$a canonicalises with a POSIX fallback" || bad "$a canonicalises with a POSIX fallback"
done

echo ""
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
