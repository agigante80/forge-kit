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
expect "an allowed address survives"  no  "$(trips 'author a.gigante@gmail.com' --allow-file "$WORK/allow")"
expect "allowing one root does not allow another" yes \
  "$(trips 'cloned into ~/other-thing/x' --allow-file "$WORK/allow")"

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

echo ""
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
