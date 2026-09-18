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
lacks()    { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1')"; else ok "$3"; fi; }
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
# /home/.. is the relative-path idiom, not a username: the segment strips to nothing, and before
# this fix nothing in the allow-file could suppress it either (fleet hit: actual-mcp-server's
# budget_loader_postcondition.test.js).
expect "the /home/.. relative-path idiom survives" no  "$(trips 'require(from + "/home/../fixtures")')"
expect "/home/alice/ still trips (no regression from the /home/.. fix)" yes \
  "$(trips '/home/alice/notes.txt')"

# #230: /home/ INSIDE a relative path is a directory called home, not a home directory. Rule A is
# anchored the way rule C is (#211): the byte before /home/ or /Users/ must not be a word byte or a
# dot. A real path always starts at a boundary (a quote, =, (, a space, start of line).
echo "== rule A: a /home/ preceded by a word byte or a dot is not a home directory (#230) =="
expect "./home/Foo.vue (a relative import) does not trip"  no  "$(trips "import Foo from './home/Foo.vue'")"
expect "src/home/index.ts does not trip"                    no  "$(trips 'export * from "src/home/index.ts"')"
expect "./Users/bob/x does not trip (symmetry)"             no  "$(trips 'see ./Users/bob/x')"
expect "a URL path https://example.com/home/alice does not trip" no "$(trips 'https://example.com/home/alice')"
expect "/home/alice/x at the start of the line still trips" yes "$(trips '/home/alice/x')"
expect '"/home/alice" after a quote still trips'             yes "$(trips 'p = "/home/alice"')"
expect "path=/home/alice after = still trips"                yes "$(trips 'path=/home/alice')"
expect "(/home/alice) after ( still trips"                   yes "$(trips 'see (/home/alice)')"
expect "a space then /home/alice/x still trips"              yes "$(trips 'https://example.com/ /home/alice/x')"
expect "//home/alice (a doubled slash) still trips"          yes "$(trips 'x //home/alice/y')"
expect "see /Users/bob/Desktop/x still trips"                yes "$(trips 'see /Users/bob/Desktop/x')"
expect "the evidence is the path without its boundary byte" yes "$(scan_line 'path=/home/alice/x' >/dev/null; printf '%s' "$OUT" | grep -q 'home-path: /home/alice/' && echo yes || echo no)"
expect "~/home/x still lands on rule B, not rule A"          yes "$(scan_line 'see ~/home/x' >/dev/null; printf '%s' "$OUT" | grep -q 'home-root: ~/home/' && echo yes || echo no)"
# The header names the shape it gives up, the way it names rule C's two.
expect "the header's shape list names the word-byte boundary" 1 "$(grep -c 'preceded by a word byte or a dot' "$SCRIPT")"
# The mutant: the anchor removed must report the relative import again, or the cases above prove nothing.
MUT230="$WORK/mutant-230.sh"; sed "s#^RE_HOME='(^|\[^A-Za-z0-9_.\])(/home#RE_HOME='(/home#" "$SCRIPT" > "$MUT230"; chmod +x "$MUT230"
expect "mutant ledger (#230): the anchored RE_HOME line exists" 1 "$(grep -c "^RE_HOME='(^|\[^A-Za-z0-9_.\])(/home" "$SCRIPT")"
expect "mutant ledger (#230): the anchor is gone from the mutant" 0 "$(grep -c "^RE_HOME='(^|" "$MUT230")"
printf '%s\n' "import Foo from './home/Foo.vue'" > "$WORK/m230.txt"
"$MUT230" "$WORK/m230.txt" >/dev/null 2>&1; expect "mutant (#230): without the anchor the relative import is reported again" 1 "$?"

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
# ~/} and ~/... are shell/shape fragments (a "$HOME/..."-style line, a bare ellipsis), not a
# person's home: the root strips to nothing. Fleet hit: this scanner's own source, and a home-path
# style doc example.
expect "~/} survives (a shell-fragment root, not a person)" no "$(trips 'like \"\$HOME/...\": echo ~/}')"
expect "~/... survives (an ellipsis root, not a person)"    no "$(trips 'root at ~/... something')"

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

# A prefix segment that strips to nothing ("..") is never a username, so judge() would return
# before ALLOW_PREFIXES is ever consulted: such an entry can never match anything. Refused at
# parse time rather than accepted as a silent no-op.
printf 'prefix /home/..\n' > "$WORK/punct-allow"
"$SCRIPT" --allow-file "$WORK/punct-allow" "$WORK/sample.txt" >/dev/null 2>"$WORK/err.txt"
expect "a punctuation-only prefix segment refuses the run" 2 "$?"
contains "cannot be a username" "$(cat "$WORK/err.txt")" "and explains why"

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
# the --orphans content test applied to every object; the reader stage's status
# unchecked; the merge group's first stage failing. Re-run 2026-09-16 (#210): the enumeration and
# the path map each reverted to --branches --tags --remotes (both run below, each losing a finding);
# --exclude placed after --all (the stash case fails); --all replaced by HEAD --branches
# (refs/original lost). The former "--remotes dropped" mutant no longer exists, since --remotes is
# no longer named. Equivalent (no observable difference, kept for
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

mkrepo relimport
hcommit screen.vue "import A from './home/A.vue'\n"
hrun --history; rc=$RC; expect "--history: a relative ./home/ import is not a home path (#230)" 0 "$rc"
hcommit note.md 'const p = "/home/alice/notes"\n'
hrun --history; rc=$RC; expect "--history: a quoted /home/alice/ still is" 1 "$rc"
contains "home-path: /home/al***/" "$OUT" "--history: the evidence is the path, redacted"

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

echo "== --history: every ref a mirror push sends (#210) =="
# The first cut enumerated --branches --tags --remotes, so a scrubbed history whose filter-branch
# backup under refs/original still held the leak scanned clean, as did refs/notes, a detached HEAD
# and any custom namespace. The set is now --exclude=refs/stash --all. The mutants below revert
# the enumeration and the path map separately, and each must LOSE THE FINDING against a fixture
# that passes only because of the widened set; a fixture that also passes against the mutant is
# testing nothing (three such fixtures were caught by the gate on the ticket's first draft).
mkrepo original
hcommit leak.md '/home/alice/x\n'
L="$(hoid HEAD)"
# reset --hard, not checkout --orphan: the orphan keeps the index, so the "clean" tip held the leak.
( cd "$HREPO" && git update-ref refs/original/refs/heads/scrubbed "$L" && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
hrun --history; expect "a leak reachable only from refs/original (a filter-branch backup) is reported" 1 "$RC"
contains "leak.md@$(hoid "$L:leak.md"):1: home-path:" "$OUT" "at its path"
( cd "$HREPO" && git update-ref -d refs/original/refs/heads/scrubbed ) >/dev/null 2>&1
hrun --history; expect "with the backup ref deleted the blob is unreachable and not reported" 0 "$RC"
hrun --history --orphans; expect "and --orphans still reaches it in the store" 1 "$RC"

mkrepo notes
hcommit clean.md 'ok\n'
( cd "$HREPO" && git notes add -m '/home/alice/x' HEAD ) >/dev/null 2>&1
hrun --history; expect "a leak only in refs/notes/commits is reported" 1 "$RC"
contains "home-path:" "$OUT" "as a home path"
contains "$(hoid HEAD)@" "$OUT" "labelled by the annotated commit's oid, which is the blob's name in the notes tree"
# `git notes remove` commits a new notes tree whose PARENT still holds the blob, so the ref must
# go, not the note: found on the first run, where the gate's remove-and-gc draft still reported.
# No gc here: the blob stays in the store, so this passes only for a scanner reading reachability.
( cd "$HREPO" && git update-ref -d refs/notes/commits ) >/dev/null 2>&1
hrun --history; expect "with the notes ref deleted nothing is reported (reachability, not presence)" 0 "$RC"
hrun --history --orphans; expect "and --orphans still finds the blob in the store" 1 "$RC"

mkrepo detached
hcommit leak.md '/home/alice/x\n'
# symbolic-ref, never a hardcoded refs/heads/master: the default branch name is user config.
( cd "$HREPO" && B="$(git symbolic-ref HEAD)" && git checkout -q --detach && git update-ref -d "$B" ) >/dev/null 2>&1
hrun --history; expect "a leak reachable only from a detached HEAD is reported (over-reporting, the safe side)" 1 "$RC"

mkrepo blobref
( cd "$HREPO" && o="$(printf '/home/alice/x\n' | git hash-object -w --stdin)" && git update-ref refs/misc/raw "$o" ) >/dev/null 2>&1
hrun --history; expect "a ref pointing straight at a blob is reported" 1 "$RC"
contains "blob@" "$OUT" "labelled blob@<oid>, since no commit ever carried it"

mkrepo stash
hcommit clean.md 'ok\n'
( cd "$HREPO" && printf '/home/alice/x\n' > leak.md && git add leak.md && git stash push -q ) >/dev/null 2>&1
( cd "$HREPO" && git rev-parse -q --verify refs/stash >/dev/null ) && ok "the fixture holds a stash entry" || bad "the fixture holds a stash entry"
hrun --history; expect "a leak only in refs/stash is not reported: no push sends it" 0 "$RC"
hrun --history --orphans; expect "--orphans reaches the stash" 1 "$RC"

# The path map must walk the same set: this blob's CURRENT name is skipped (.png) and only the
# refs/original walk knows it was once leak.md. Only the map rescues it.
mkrepo pathmap
hcommit leak.md '/home/alice/x\n'
( cd "$HREPO" && git mv leak.md leak.png && git commit -qm png && git update-ref refs/original/refs/heads/scrubbed HEAD && git reset -q --hard HEAD~2 ) >/dev/null 2>&1
hrun --history; expect "a blob skipped by its current name is read for its historical one, through refs/original" 1 "$RC"
contains "leak.md@" "$OUT" "at the historical path"

MUT="$WORK/mutant-enum.sh"
sed 's/rev-list --objects --exclude=refs\/stash --all/rev-list --objects --branches --tags --remotes/' "$SCRIPT" > "$MUT"; chmod +x "$MUT"
expect "mutant ledger: the scanner enumerates with --exclude=refs/stash --all" 1 "$(grep -c -- 'rev-list --objects --exclude=refs/stash --all' "$SCRIPT")"
expect "the enumeration mutant reads branches, tags and remotes only" 1 "$(grep -c -- 'rev-list --objects --branches --tags --remotes' "$MUT")"
mkrepo original2
hcommit leak.md '/home/alice/x\n'
( cd "$HREPO" && git update-ref refs/original/refs/heads/scrubbed HEAD && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
( cd "$HREPO" && "$MUT" --history ) >/dev/null 2>&1; expect "the enumeration mutant loses the refs/original finding" 0 "$?"
hrun --history; expect "the scanner finds it" 1 "$RC"
MUT2="$WORK/mutant-pathmap.sh"
sed 's/log -m --exclude=refs\/stash --all --raw/log -m --branches --tags --remotes --raw/' "$SCRIPT" > "$MUT2"; chmod +x "$MUT2"
expect "mutant ledger: the path map walks --exclude=refs/stash --all" 1 "$(grep -c -- 'log -m --exclude=refs/stash --all --raw' "$SCRIPT")"
expect "the path-map mutant walks branches, tags and remotes only" 1 "$(grep -c -- 'log -m --branches --tags --remotes --raw' "$MUT2")"
mkrepo pathmap2
hcommit leak.md '/home/alice/x\n'
( cd "$HREPO" && git mv leak.md leak.png && git commit -qm png && git update-ref refs/original/refs/heads/scrubbed HEAD && git reset -q --hard HEAD~2 ) >/dev/null 2>&1
( cd "$HREPO" && "$MUT2" --history ) >/dev/null 2>&1; expect "the path-map mutant loses the finding (its only mapped name is the skipped leak.png)" 0 "$?"
hrun --history; expect "the scanner finds it" 1 "$RC"
h="$("$SCRIPT" --help 2>&1)"
contains "filter-branch" "$h" "--help names filter-branch's refs/original"
contains "mirror" "$h" "and the mirror push"

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


echo "== the tree modes fail closed, the way --history does (#208) =="
# Each of these was a silent exit 0 on a real leak at 89e774f, found by the overnight audit.
mkrepo rename
( cd "$HREPO" && for i in $(seq 1 20); do echo "line $i"; done > a.md && git add a.md && git commit -qm twenty \
  && git mv a.md b.md && printf '/home/alice/x\n' >> b.md && git add b.md ) >/dev/null 2>&1
st="$( cd "$HREPO" && git diff --cached --name-status | cut -c1 )"; expect "fixture: git sees a rename" R "$st"
hrun --staged; rc=$RC; expect "a renamed-and-edited file is reported by --staged" 1 "$rc"
contains "b.md:21: home-path: /home/alice/" "$OUT" "at its new name and line"
( cd "$HREPO" && git commit -qm renamed ) >/dev/null 2>&1
hrun --range HEAD~1; rc=$RC; expect "and by --range" 1 "$rc"
contains "b.md:21:" "$OUT" "at the new name"
mkrepo purerename
( cd "$HREPO" && for i in $(seq 1 20); do echo "line $i"; done > a.md && git add a.md && git commit -qm twenty && git mv a.md c.md ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a pure rename adds no content and is clean" 0 "$rc"
mkrepo typechange
( cd "$HREPO" && ln -s seed.md link.md && git add link.md && git commit -qm link && rm link.md && printf '/home/alice/x\n' > link.md && git add link.md ) >/dev/null 2>&1
st="$( cd "$HREPO" && git diff --cached --name-status | cut -c1 )"; expect "fixture: git sees a typechange" T "$st"
hrun --staged; rc=$RC; expect "a symlink replaced by a leaking file is reported" 1 "$rc"
contains "link.md:1:" "$OUT" "at its path"
mkrepo stagesyntax
( cd "$HREPO" && printf '/home/alice/x\n' > '0:x' && git add -- '0:x' ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a staged path shaped like a stage spec (0:x) is reported" 1 "$rc"
contains "0:x:1:" "$OUT" "at its path"
mkrepo gitlink
( cd "$HREPO" && printf '/home/alice/x\n' > leak.md && git add leak.md \
  && git update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,sub ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "a staged gitlink beside a staged leak: reported, never a refusal" 1 "$rc"
# A gitlink whose commit IS in the store: git show would print the commit, and its message was
# scanned as the file (review). Only a blob is read.
( cd "$HREPO" && c="$(git commit-tree -m '/home/carol/z in a message' "$(git write-tree)")" \
  && git update-index --add --cacheinfo 160000,"$c",present ) >/dev/null 2>&1
hrun --staged; rc=$RC
lacks "present:" "$OUT" "a gitlink whose commit is present is not scanned as a file"
mkrepo symlink
( cd "$HREPO" && ln -s /home/alice/secret dangling && git add dangling && git commit -qm link ) >/dev/null 2>&1
hrun --all; rc=$RC; expect "a tracked symlink is scanned as its link TEXT under --all (it used to be followed and skipped)" 1 "$rc"
contains "dangling:1: home-path: /home/alice/" "$OUT" "at the link's path"
( cd "$HREPO" && git rm -q dangling && ln -s /home/alice/secret staged-link && git add staged-link ) >/dev/null 2>&1
hrun --staged; rc=$RC; expect "and a staged symlink is reported the same way" 1 "$rc"
mkrepo optnames
( cd "$HREPO" && printf '/home/alice/x\n' > ./-v && printf '/home/bob/y\n' > ./- && git add -- -v - && git commit -qm dashes ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && "$SCRIPT" --all </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "files named -v and - are scanned, not read as options or stdin" 1 "$rc"
contains "-v:1:" "$OUT" "the -v file"
contains "-:1:" "$OUT" "and the - file, with stdin from /dev/null"
mkrepo notmp
( cd "$HREPO" && printf '/home/alice/x\n' > leak.md && git add leak.md ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && TMPDIR="$WORK/does-not-exist" "$SCRIPT" --staged </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "mktemp failure refuses --staged" 2 "$rc"
contains "cannot create a temp directory" "$(cat "$WORK/herr.txt")" "and says so"
[ -z "$OUT" ] && ok "with nothing on stdout" || bad "with nothing on stdout (got '$OUT')"
OUT="$( cd "$HREPO" && TMPDIR="$WORK/does-not-exist" "$SCRIPT" --all </dev/null 2>"$WORK/herr.txt" )"; rc=$?
expect "and --all under the same TMPDIR refuses the same way" 2 "$rc"
mkrepo nowrite
( cd "$HREPO" && head -c 3000 /dev/zero | tr '\0' a > big.md && printf '\n/home/alice/x\n' >> big.md && git add big.md ) >/dev/null 2>&1
# No trap in the harness: the kernel KILLS git show under RLIMIT_FSIZE, and it is the scanner's
# job to keep the shell's own notice for a signalled child (which carries the script's path) off
# its stderr (review of #208).
( cd "$HREPO" && ulimit -f 1 && "$SCRIPT" --staged </dev/null >"$WORK/wout.txt" 2>"$WORK/werr.txt"; echo $? > "$WORK/wrc.txt" ) 2>/dev/null
expect "a blob the scanner cannot write refuses --staged" 2 "$(cat "$WORK/wrc.txt")"
contains "could not read big.md" "$(cat "$WORK/werr.txt")" "naming the file"
lacks "$WORK" "$(cat "$WORK/werr.txt")" "and never the temp path"
lacks "$ROOT" "$(cat "$WORK/werr.txt")" "nor the script's path, even for a child killed by a signal"
if [ "$(id -u)" -ne 0 ]; then
  mkrepo unreadable
  ( cd "$HREPO" && printf '/home/alice/x\n' > leak.md && git add leak.md && git commit -qm leak && chmod 000 leak.md ) >/dev/null 2>&1
  hrun --all; rc=$RC; expect "a tracked file the scanner cannot open refuses --all" 2 "$rc"
  contains "could not read leak.md" "$ERR" "naming the file"
  lacks "$ROOT" "$ERR" "and never the script's own path"
  [ -z "$OUT" ] && ok "with nothing on stdout" || bad "with nothing on stdout"
  ( cd "$HREPO" && chmod 644 leak.md ) >/dev/null 2>&1
  hrun --all; rc=$RC; expect "readable again, it is reported" 1 "$rc"
else
  ok "unreadable-file case skipped: running as root"
fi
MUT="$WORK/mutant-renames.sh"; sed 's/ --no-renames / /' "$SCRIPT" > "$MUT"; chmod +x "$MUT"
grep -q -- '--no-renames' "$SCRIPT" && ok "mutant ledger: the scanner passes --no-renames" || bad "mutant ledger: --no-renames not found"
mkrepo rename2
( cd "$HREPO" && for i in $(seq 1 20); do echo "line $i"; done > a.md && git add a.md && git commit -qm twenty && git mv a.md b.md && printf '/home/alice/x\n' >> b.md && git add b.md ) >/dev/null 2>&1
( cd "$HREPO" && "$MUT" --staged ) >/dev/null 2>&1; expect "mutant (a): without --no-renames the rename is missed" 0 "$?"
MUT2="$WORK/mutant-filter.sh"; sed 's/--diff-filter=ACMT/--diff-filter=ACM/' "$SCRIPT" > "$MUT2"; chmod +x "$MUT2"
mkrepo typechange2
( cd "$HREPO" && ln -s seed.md link.md && git add link.md && git commit -qm link && rm link.md && printf '/home/alice/x\n' > link.md && git add link.md ) >/dev/null 2>&1
( cd "$HREPO" && "$MUT2" --staged ) >/dev/null 2>&1; expect "mutant (b): without T in the filter the typechange is missed" 0 "$?"

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


echo "== rule C is linear in the line length, in both modes and both locales (#211) =="
# The defect: unanchored, rule C's local part can start at every position of a long word-class run
# and grep leaves its DFA to retry each one (64 KB then one address: 105 s). Two halves fix it, the
# anchor and LC_ALL=C on the tree grep, and judge()'s split is a third quadratic in bash. Each half
# has a mutant here that must be KILLED at the bound, which is what proves the half load-bearing.
# MUTANTS (2026-09-16, #211): the anchor removed from RE_MAIL; LC_ALL=C removed from the tree grep
# (observable under ANY UTF-8 locale, C.utf8 included, and skipped only where none exists); the
# IFS=@ read split
# replaced by ${addr#*@}. All three killed. The bound is this suite's own helper, never GNU
# `timeout`, which stock macOS does not ship.
bounded() {  # bounded <secs> <cmd...>: cmd in its own process group; 124 if the bound kills it
  local secs="$1"; shift
  ( set -m
    "$@" & pid=$!
    ( sleep "$secs"; kill -- -"$pid" 2>/dev/null ) >/dev/null 2>&1 & w=$!
    set +m
    wait "$pid" 2>/dev/null; rc=$?
    kill -- -"$w" 2>/dev/null
    [ "$rc" -ge 128 ] && rc=124; exit "$rc" )
}
# The watcher is spawned while set -m is still on, so it is its own group and the kill reaches its
# sleep, and its stdio is detached so that sleep cannot hold a capture pipe open: written the naive
# way, OUT="$(bounded 10 ...)" blocks for the whole bound even when the command returns at once.
# On bash 3.2 a killed mutant's WALL time overshoots the bound (a fatal signal waits for the
# expansion it is inside to finish); the exit code is still 124. The three mutants cost about 40 s.
LONG="$WORK/long-spaced.md"; { head -c 1048576 /dev/zero | tr '\0' a; printf ' alice@corp.io\n'; } > "$LONG"
GLUED="$WORK/long-glued.md"; { head -c 262144 /dev/zero | tr '\0' a; printf '@corp.io\n'; } > "$GLUED"
# 1 MB spaced, 256 KB glued: the glued shape is the one that reaches bash, and at 1 MB the FIXED
# scanner needs 5.1 s of a 10 s bound on bash 3.2.57, which is a flake waiting to happen; at
# 256 KB it is 1.3 s and the unfixed split still needs 48 s.
OUT="$(bounded 10 "$SCRIPT" --all "$LONG" 2>/dev/null)"; rc=$?
expect "a 1 MB token followed by an address is reported within the bound (--all)" 1 "$rc"
contains "email: alice@corp.io" "$OUT" "and the address is the evidence"
OUT="$(bounded 10 "$SCRIPT" --all "$GLUED" 2>/dev/null)"; rc=$?
expect "a 256 KB match is split within the bound (--all)" 1 "$rc"
contains "email: a" "$OUT" "and reported"

mkrepo longtoken
cp "$LONG" "$HREPO/long.md"; cp "$GLUED" "$HREPO/glued.md"
( cd "$HREPO" && git add long.md glued.md && git commit -qm long ) >/dev/null 2>&1
OUT="$( cd "$HREPO" && bounded 10 "$SCRIPT" --history --show-evidence 2>/dev/null )"; rc=$?
expect "both shapes are reported within the bound (--history)" 1 "$rc"
contains "long.md@" "$OUT" "the spaced one at its path"
contains ":1: email: alice@corp.io" "$OUT" "on line 1"
contains "glued.md@" "$OUT" "the glued one too"

MUTA="$WORK/mutant-unanchored.sh"
sed "s/^RE_MAIL='(^|\[^A-Za-z0-9._%+-\])/RE_MAIL='/" "$SCRIPT" > "$MUTA"; chmod +x "$MUTA"
# -F, not a BRE: ugrep reads the pattern as an ERE and would report the anchor absent from the
# file that carries it, passing a mutant identical to the scanner.
grep -qF "RE_MAIL='(^|" "$SCRIPT" && ok "the scanner carries the anchor the mutant removes" || bad "the scanner carries the anchor the mutant removes"
grep -qF "RE_MAIL='(^|" "$MUTA" && bad "the mutant no longer carries it" || ok "the mutant no longer carries it"
bounded 10 "$MUTA" --all "$LONG" >/dev/null 2>&1
expect "the unanchored mutant is killed at the bound (exit 124)" 124 "$?"

MUTS="$WORK/mutant-split.sh"
sed 's/IFS=@ read -r local_part domain <<< "$addr"/local_part="${addr%%@*}"; domain="${addr#*@}"/' "$SCRIPT" > "$MUTS"; chmod +x "$MUTS"
expect "the scanner splits the address with IFS=@ read" 1 "$(grep -c 'IFS=@ read -r local_part domain' "$SCRIPT")"
expect "the split mutant uses the quadratic expansion instead" 0 "$(grep -c 'IFS=@ read -r local_part domain' "$MUTS")"
bounded 10 "$MUTS" --all "$GLUED" >/dev/null 2>&1
expect "the quadratic-split mutant is killed at the bound (exit 124)" 124 "$?"

# Two different locales are needed, and conflating them skipped half of this for no reason (review
# round 1). The TIMING mutant dies under ANY UTF-8 locale, C.utf8 included (25 s there against
# 0.098 s pinned), so a slim container still runs it. The accented-class case needs a TERRITORY
# locale, because C.utf8 does not admit the accented classes either and so cannot tell the pin
# from its absence.
ANYUTF8="$(locale -a 2>/dev/null | grep -i 'utf' | head -1)"
UTF8="$(locale -a 2>/dev/null | grep -i '^[a-z][a-z]_.*utf' | head -1)"
if [ -n "$ANYUTF8" ]; then
  MUTL="$WORK/mutant-locale.sh"
  sed 's/done < <(LC_ALL=C grep -onE/done < <(grep -onE/' "$SCRIPT" > "$MUTL"; chmod +x "$MUTL"
  expect "the scanner pins the tree-mode grep to the C locale" 1 "$(grep -c 'LC_ALL=C grep -onE' "$SCRIPT")"
  expect "the locale mutant drops the pin" 0 "$(grep -c 'LC_ALL=C grep -onE' "$MUTL")"
  LC_ALL="$ANYUTF8" bounded 10 "$MUTL" --all "$LONG" >/dev/null 2>&1
  expect "without the pin the anchored regex is still quadratic under a UTF-8 locale (124)" 124 "$?"
  OUT="$(LC_ALL="$ANYUTF8" bounded 10 "$SCRIPT" --all "$LONG" 2>/dev/null)"; rc=$?
  expect "with the pin the same run is reported within the bound" 1 "$rc"
else
  ok "(skipped, no UTF-8 locale on this machine) the locale mutant"
fi

echo "== the two shapes rule C deliberately misses, pinned so they are not rediscovered as bugs =="
# Both are stated in the scanner's header. A limit with no case is a limit nobody knows about.
printf 'see /home/alice/alice@corp.io here\n' > "$WORK/glue-path.txt"
OUT="$("$SCRIPT" "$WORK/glue-path.txt" 2>/dev/null)"; rc=$?
expect "an address glued to a home path still trips" 1 "$rc"
contains "home-path: /home/alice/" "$OUT" "as the path row"
lacks "email:" "$OUT" "and NOT as an email: rule A's /? consumes the anchor byte (documented limit)"
printf 'see ~/secret/alice@corp.io here\n' > "$WORK/glue-root.txt"
OUT="$("$SCRIPT" "$WORK/glue-root.txt" 2>/dev/null)"; rc=$?
expect "an address glued to a home root still trips" 1 "$rc"
lacks "email:" "$OUT" "and not as an email either, the same limit in rule B"
printf 'x /home/alice/notes alice@corp.io\n' > "$WORK/glue-sep.txt"
OUT="$("$SCRIPT" "$WORK/glue-sep.txt" 2>/dev/null)"; rc=$?
expect "a separator between the path and the address restores both rows" 1 "$rc"
contains "home-path:" "$OUT" "the path"
contains "email: alice@corp.io" "$OUT" "and the address"
if [ -n "$UTF8" ]; then
  printf 'mail jos\xc3\xa9@corp.io today\n' > "$WORK/accent.txt"
  OUT="$(LC_ALL="$UTF8" "$SCRIPT" "$WORK/accent.txt" 2>/dev/null)"; rc=$?
  expect "an accented local part is SILENT under the C pin (documented limit)" 0 "$rc"
  OUT="$(LC_ALL="$UTF8" "$WORK/mutant-locale.sh" "$WORK/accent.txt" 2>/dev/null)"; rc=$?
  expect "and the pin, not the anchor, is what narrows it (the unpinned copy reports it)" 1 "$rc"
else
  ok "(skipped, no territory UTF-8 locale) the accented-address limit"
fi

echo "== no address shape is lost by the anchor =="
expect "an address at line start trips" yes "$(trips 'alice@corp.io wrote this')"
expect "an address after a space trips" yes "$(trips 'mail alice@corp.io for help')"
expect "an address in brackets trips" yes "$(trips 'contact (alice@corp.io) first')"
expect "an address after a quote trips" yes "$(trips 'author "alice@corp.io"')"
expect "an address after a tab trips" yes "$(trips "$(printf 'owner\talice@corp.io')")"
expect "an address after an equals sign trips" yes "$(trips 'MAIL=alice@corp.io')"
expect "an address after a slash trips" yes "$(trips 'see docs/alice@corp.io')"
expect "an address after a tilde trips" yes "$(trips 'see ~alice@corp.io')"
expect "an address after a multibyte character trips" yes "$(trips "$(printf 'caf\xc3\xa9alice@corp.io')")"
printf 'a@corp.io,b@corp.io\n' > "$WORK/two.txt"
OUT="$("$SCRIPT" "$WORK/two.txt" 2>/dev/null)"
expect "two adjacent addresses are both reported" 2 "$(printf '%s\n' "$OUT" | grep -c 'email:')"
# The ROW, not the exit code: the strip mutant reports `home-path: /alice@corp.io` here and still
# trips, so an exit-code assertion would pass on the mutant it is named for (review round 1).
printf 'see docs/alice@corp.io\n' > "$WORK/slashmail.txt"
OUT="$("$SCRIPT" "$WORK/slashmail.txt" 2>/dev/null)"
contains "email: alice@corp.io" "$OUT" "a slash-preceded address is judged as email, not as a path"
lacks "home-path:" "$OUT" "and no path row is invented from the stripped byte"
OUT="$("$SCRIPT" "$WORK/two.txt" 2>/dev/null)"
contains "email: a@corp.io" "$OUT" "the first whole"
contains "email: b@corp.io" "$OUT" "the second whole"
expect "noreply@ survives" no "$(trips 'from noreply@github.com')"
expect "the git@ SSH clone user survives" no "$(trips 'clone git@github.com:owner/repo.git')"
expect "example.com survives" no "$(trips 'try someone@example.com')"
expect "the .invalid TLD survives" no "$(trips 'try someone@mail.invalid')"
expect "a bare mention survives" no "$(trips 'thanks @agigante80 for the fix')"

echo "== the stripped byte does not bypass redaction =="
mkrepo slashmail
hcommit notes.md 'see docs/alice@corp.io\n'
hrun --history; expect "a slash-preceded address in history is reported" 1 "$RC"
contains "email: al***********" "$OUT" "redacted by default"
lacks "alice@corp.io" "$OUT" "with the whole address absent from the report"
hrun --history --show-evidence; expect "--show-evidence still shows it" 1 "$RC"
contains "email: alice@corp.io" "$OUT" "whole"

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
