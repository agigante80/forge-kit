#!/usr/bin/env bash
# Contract test for .githooks/pre-push (issue #98 item 3), driven against a real throwaway git
# repo with a real bare remote, because the hook's whole subject is refs and ranges. Feeding it
# a hand-written stdin line in this repo would test the parser and not the behaviour.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# HOME is isolated for the whole run (#384, item 7). The private scanner's default list is
# "$HOME/.claude/forge-kit/private-names.txt" and the hook passes no --list, so without this the
# fixture's content is judged against the DEVELOPER'S REAL list on a host that has one, and the
# suite's result differs between hosts. Nothing is written under it until the isolation is asserted.
REAL_HOME="${HOME:-}"
export HOME="$TMP/fakehome"
mkdir -p "$HOME"
REPO="$TMP/repo"; BARE="$TMP/remote.git"
git init --quiet --bare "$BARE"
git init --quiet -b main "$REPO"
cd "$REPO"
git config user.email t@example.com; git config user.name test
mkdir -p scripts .githooks plugins/g/agents plugins/g/.claude-plugin
cp "$ROOT/scripts/check-version-bump.sh" "$ROOT/scripts/check-plugin-version-bump.sh" scripts/
cp "$ROOT/.githooks/pre-push" .githooks/
printf '{ "name": "g", "version": "1.0.0", "description": "fixture" }\n' > plugins/g/.claude-plugin/plugin.json
printf '<!-- a-version: 1 -->\noriginal body\n' > plugins/g/agents/a.md
git add -A >/dev/null; git commit --quiet -m init
git remote add origin "$BARE"
git push --quiet origin main 2>/dev/null
git remote set-head origin main >/dev/null 2>&1

# run_hook_stdout / run_hook_stderr: ONE stream each, because the hook's CI wording sits on stdout
# on the violation path and on stderr on the missing-base path (#311). A merged capture would pass
# wording that sits on the wrong stream.
run_hook_stdout() {
  local ref="$1" sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/$ref" "$sha" "refs/heads/$ref" \
    "0000000000000000000000000000000000000000" | bash .githooks/pre-push origin "$BARE" 2>/dev/null
}
run_hook_stderr() {
  local ref="$1" hook="${2:-.githooks/pre-push}" sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/$ref" "$sha" "refs/heads/$ref" \
    "0000000000000000000000000000000000000000" | bash "$hook" origin "$BARE" 2>&1 >/dev/null
}

# push_stdin <ref>: the four fields git feeds a pre-push hook for a new branch.
run_hook() {
  local ref="$1" hook="${2:-.githooks/pre-push}" sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/$ref" "$sha" "refs/heads/$ref" \
    "0000000000000000000000000000000000000000" \
    | bash "$hook" origin "$BARE" 2>&1
}

# --- 1. a clean branch passes ------------------------------------------------------------------
git checkout --quiet -b clean
printf 'unrelated\n' > notes.txt; git add -A >/dev/null; git commit --quiet -m docs
out=$(run_hook clean); rc=$?
[ "$rc" -eq 0 ] && ok "a branch touching no component passes" || bad "clean branch passes (rc=$rc)"

# --- 2. a component changed WITHOUT a marker bump is caught ------------------------------------
git checkout --quiet -b unbumped main
printf '<!-- a-version: 1 -->\nCHANGED body\n' > plugins/g/agents/a.md
git add -A >/dev/null; git commit --quiet -m "change without bump"
out=$(run_hook unbumped); rc=$?
[ "$rc" -ne 0 ] && ok "an unbumped component marker fails the push" \
  || bad "an unbumped component marker fails the push (rc=$rc)"
printf '%s' "$out" | grep -q 'bump the <name>-version marker' \
  && ok "the marker failure names the fix" || bad "the marker failure names the fix"

# The CI wording on the violation path is on STDOUT (#311). It must say what CI really does and
# must not promise an identical answer: a PR compares against the PR's target branch and a push
# against the branch's previous tip (scripts/resolve-range-base.sh), so the two bases differ.
so="$(run_hook_stdout unbumped)"
printf '%s' "$so" | grep -q 'range check(s) failed' \
  && ok "the violation summary is on stdout" || bad "the violation summary is on stdout"
for frag in 'pull requests' "PR's target branch" 'pushes to main and develop' 'previous tip' 'can differ' 'new ref or a force push' 'triggers no' 'though an open PR for it still triggers one'; do
  printf '%s' "$so" | grep -q "$frag" \
    && ok "stdout states the real CI behaviour: $frag" || bad "stdout states the real CI behaviour: $frag"
done
for frag in 'same answer' 'will fail there too'; do
  printf '%s' "$so" | grep -q "$frag" \
    && bad "stdout no longer promises CI agreement: $frag" || ok "stdout no longer promises CI agreement: $frag"
done
hdr="$(sed -n '1,/^set -uo/p' "$ROOT/.githooks/pre-push")"
printf '%s' "$hdr" | grep -q 'duplicates CI' \
  && bad "the header no longer says the hook duplicates CI" || ok "the header no longer says the hook duplicates CI"
printf '%s' "$hdr" | grep -q 'not a preview of CI' \
  && ok "the header says this is an early check, not a preview of CI" || bad "the header says this is an early check, not a preview of CI"
# #366: the header must not say a push to another branch gets no run WITHOUT the open-PR caveat
# (validate.yml has an unfiltered `pull_request:`, so a branch with an open PR does get a run).
printf '%s' "$hdr" | grep -q 'push-time CI run' \
  && ok "the header still speaks of the push-time CI run" || bad "the header still speaks of the push-time CI run"
printf '%s' "$hdr" | grep -q 'open PR' \
  && ok "the header says an open PR still triggers a CI run" || bad "the header says an open PR still triggers a CI run"
# Permanent mutant (scratch copy under $TMP, the tracked hook is never touched). The ledger is
# scoped to the HEADER: the caveat also exists on stdout, so a whole-file grep would pass vacuously.
mut_hdr="$TMP/mut-header.sh"
sed '/^# push-time CI run, though/s/, though an open PR for it still triggers one\././' "$ROOT/.githooks/pre-push" > "$mut_hdr"
if printf '%s' "$hdr" | grep -q 'though an open PR for it still triggers one' \
   && ! cmp -s "$mut_hdr" "$ROOT/.githooks/pre-push"; then
  mhdr="$(sed -n '1,/^set -uo/p' "$mut_hdr")"
  printf '%s' "$mhdr" | grep -q 'open PR' \
    && bad "the header open-PR check detects a header without the caveat" \
    || ok "the header open-PR check detects a header without the caveat"
else
  bad "the header open-PR check detects a header without the caveat (ledger or mutant failed)"
fi

# --- 3. bumping the marker but NOT the plugin semver is still caught ---------------------------
printf '<!-- a-version: 2 -->\nCHANGED body\n' > plugins/g/agents/a.md
git add -A >/dev/null; git commit --quiet -m "bump marker only"
out=$(run_hook unbumped); rc=$?
if command -v jq >/dev/null 2>&1; then
  [ "$rc" -ne 0 ] && ok "a group changed without a plugin.json bump fails the push" \
    || bad "a group changed without a plugin.json bump fails the push (rc=$rc)"
else
  printf '%s' "$out" | grep -q 'jq is not installed' \
    && ok "no jq: the semver check skips LOUDLY" || bad "no jq: the semver check skips loudly"
fi

# --- 4. both bumped: the push is allowed -------------------------------------------------------
printf '{ "name": "g", "version": "1.0.1", "description": "fixture" }\n' > plugins/g/.claude-plugin/plugin.json
git add -A >/dev/null; git commit --quiet -m "bump plugin semver"
out=$(run_hook unbumped); rc=$?
[ "$rc" -eq 0 ] && ok "marker + semver both bumped passes" || bad "marker + semver both bumped passes (rc=$rc)"

# --- 5. a branch DELETION is not audited -------------------------------------------------------
out=$(printf 'refs/heads/x 0000000000000000000000000000000000000000 refs/heads/x %s\n' \
        "$(git rev-parse HEAD)" | bash .githooks/pre-push origin "$BARE" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a branch deletion is not audited" || bad "a branch deletion is not audited (rc=$rc)"

# --- 6. pushing a ref that is not the checked-out HEAD is skipped, loudly ----------------------
out=$(printf 'refs/heads/other %s refs/heads/other 0000000000000000000000000000000000000000\n' \
        "$(git rev-parse main)" | bash .githooks/pre-push origin "$BARE" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a non-HEAD ref does not fail the push" || bad "a non-HEAD ref does not fail the push"
printf '%s' "$out" | grep -q 'not the checked-out HEAD' \
  && ok "a non-HEAD ref is skipped LOUDLY" || bad "a non-HEAD ref is skipped loudly"

# --- 7. a missing base ref skips loudly rather than blocking the push --------------------------
# Recreate the violation, then remove the remote-tracking ref the guards compare against.
git checkout --quiet unbumped
printf '<!-- a-version: 2 -->\nCHANGED AGAIN\n' > plugins/g/agents/a.md
git add -A >/dev/null; git commit --quiet -m "another change, no bump"
git update-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
git update-ref -d refs/remotes/origin/main 2>/dev/null || true
out=$(run_hook unbumped); rc=$?
[ "$rc" -eq 0 ] && ok "a missing base ref does not block the push" \
  || bad "a missing base ref does not block the push (rc=$rc)"
printf '%s' "$out" | grep -q 'range checks SKIPPED' \
  && ok "a missing base ref says so LOUDLY" || bad "a missing base ref says so loudly"
printf '%s' "$out" | grep -q 'git fetch origin' \
  && ok "the skip message says how to fix it" || bad "the skip message says how to fix it"
# The CI claim on this path is on STDERR (#311): stderr alone, and no promise that CI checks it.
se="$(run_hook_stderr unbumped)"
printf '%s' "$se" | grep -q 'is still checked there' \
  && bad "the skip message no longer promises the push is still checked" || ok "the skip message no longer promises the push is still checked"
for frag in "target branch" 'previous tip' 'can differ' 'no push-time CI run' 'pull requests' 'pushes to main and develop' 'open PR'; do
  printf '%s' "$se" | grep -q "$frag" \
    && ok "the skip message states the real CI behaviour: $frag" || bad "the skip message states the real CI behaviour: $frag"
done
# Permanent mutant (#366): the stderr caveat removed, on a scratch copy run from this fixture.
# Only `>&2` lines are touched, so the stdout and header copies of the caveat stay intact.
mut_se="$TMP/mut-stderr.sh"
sed '/>&2$/s/, though an open PR for it still triggers one\././' "$ROOT/.githooks/pre-push" > "$mut_se"
if grep -q 'no push-time CI run, though an open PR for it still triggers one' "$ROOT/.githooks/pre-push" \
   && ! cmp -s "$mut_se" "$ROOT/.githooks/pre-push"; then
  mse="$(run_hook_stderr unbumped "$mut_se")"
  printf '%s' "$mse" | grep -q 'open PR' \
    && bad "the stderr open-PR check detects a hook without the caveat" \
    || ok "the stderr open-PR check detects a hook without the caveat"
else
  bad "the stderr open-PR check detects a hook without the caveat (ledger or mutant failed)"
fi

# --- the leak guard runs even when the range guards cannot -----------------------------------
# It used to sit BELOW the missing-base-ref exit, so a clone that had not fetched origin/main
# skipped both scanners silently, and the private half runs nowhere else at all.
echo "== leak guard placement =="
LG=plugins/forge-kit-security/skills/leak-guard/assets
mkdir -p "$LG"
cp "$ROOT/$LG/check-public-leaks.sh" "$ROOT/$LG/check-private-leaks.sh" "$LG/"
# Composed rather than written literally, so this file needs no `skip` entry in the repo's own
# allow-file. An exemption is a hole in the guard; the fixture only needs the string to exist.
printf 'the log said %s/alice/secret/build.log\n' /home > docs-leak.md
git add -A >/dev/null; git commit --quiet -m "a leak, no marker bump needed"
# Base ref still deleted from the case above, so the range guards cannot run at all.
out=$(run_hook leakcheck); rc=$?
# Exactly 1: a crash or exit 2 must not pass as a block;
# which branch fired is pinned by the wording below.
[ "$rc" -eq 1 ] && ok "a leak blocks the push even with no base ref" \
  || bad "a leak blocks the push even with no base ref (rc=$rc)"
printf '%s' "$out" | grep -q 'home-path' \
  && ok "and the finding itself is shown" || bad "and the finding itself is shown"
# Wording assertions use STDOUT only (the leak block echoes there). The old phrases survive only
# as absence patterns (#313).
so="$(run_hook_stdout leakcheck)"
printf '%s' "$so" | grep -qi 'NOT one of the CI checks' \
  && bad "the message no longer says the leak guard is not a CI check" \
  || ok "the message no longer says the leak guard is not a CI check"
printf '%s' "$so" | grep -q 'nothing server-side will catch it for you' \
  && bad "the message no longer says nothing server-side catches it" \
  || ok "the message no longer says nothing server-side catches it"
printf '%s' "$so" | grep -q 'this push has published it' \
  && bad "the message no longer says this push has published it" \
  || ok "the message no longer says this push has published it"
for frag in 'CI also runs' 'pushes to main and develop' 'triggers no CI scan' 'runs only on this machine' '--no-verify can publish it' 'once it is published' 'with no pull request triggers no CI scan'; do
  printf '%s' "$so" | grep -q -e "$frag" \
    && ok "leak message states: $frag" || bad "leak message states: $frag"
done
printf '%s' "$so" | grep 'private-name' | grep -q 'runs only on this machine' \
  && ok "the private-name line says it runs only on this machine" \
  || bad "the private-name line says it runs only on this machine"
printf '%s' "$so" | grep 'private-name' | grep -q 'CI also runs' \
  && bad "the private-name line does not claim CI runs it" \
  || ok "the private-name line does not claim CI runs it"
printf '%s' "$out" | grep -q 'range check(s) failed' \
  && bad "a leak is not reported as a range-check failure" \
  || ok "a leak is not reported as a range-check failure"

# Exit 2 (could not run) must not be reported as a finding.
printf 'nonsense line\n' > .leak-guard-allow
git add -A >/dev/null; git commit --quiet -m "broken allow-file"
out=$(run_hook leakcheck); rc=$?
[ "$rc" -ne 0 ] && ok "a scanner that cannot run still blocks" || bad "a scanner that cannot run still blocks"
printf '%s' "$out" | grep -qi 'could not RUN' \
  && ok "and says it could not run, not that it found something" \
  || bad "and says it could not run, not that it found something"
# Structural regression guard (the leak_errors exit comes first), not coverage of the new wording.
printf '%s' "$out" | grep -q -e 'CI also runs' -e 'runs only on this machine' \
  && bad "a could-not-run result carries none of the finding wording" \
  || ok "a could-not-run result carries none of the finding wording"
rm -f .leak-guard-allow docs-leak.md; git add -A >/dev/null; git commit --quiet -m cleanup

# --- the scan reads HEAD, not the working tree (#375) ----------------------------------------------
# Every case that dirties the tree restores it, because later sections run `git add -A` and commit.
LEAKLINE="$(printf 'the log said %s/alice/work/build.log' /home)"
hook_commit() { git add -A >/dev/null; git commit --quiet --allow-empty -m "$1"; }
# A: a leak committed at HEAD and removed only in an uncommitted edit still blocks.
printf '%s\n' "$LEAKLINE" > docs-leak.md; hook_commit "a committed leak"
printf 'edited out, not committed\n' > docs-leak.md
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "a committed leak masked by an uncommitted fix still blocks (rc exactly 1)" \
  || bad "a committed leak masked by an uncommitted fix still blocks (rc=$rc)"
printf '%s' "$out" | grep -q 'home-path' && ok "and the finding is shown" || bad "and the finding is shown"
# B: a clean HEAD with an uncommitted-only leak passes: nothing leaky is published.
printf 'clean\n' > docs-leak.md; hook_commit "fix the leak"
printf '%s\n' "$LEAKLINE" > docs-leak.md
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 0 ] && ok "an uncommitted-only leak over a clean HEAD passes (never published)" \
  || bad "an uncommitted-only leak over a clean HEAD passes (rc=$rc)"
printf 'clean\n' > docs-leak.md
printf '%s' "$out" | grep -q 'NOT BEING CHECKED' \
  && ok "an isolated HOME with no list: the private scan says its names are not being checked" \
  || bad "an isolated HOME with no list: the private scan says its names are not being checked"
# #384 item 7: the default list is the fixture's, never the developer's. The isolation is asserted
# BEFORE anything is written under $HOME, so a missed isolation cannot touch a real list.
if [ "$HOME" = "$TMP/fakehome" ] && [ "$HOME" != "$REAL_HOME" ]; then
  ok "HOME is isolated to the fixture directory"
  mkdir -p "$HOME/.claude/forge-kit"
  printf 'zq384token\n' > "$HOME/.claude/forge-kit/private-names.txt"
  printf 'notes mentioning zq384token here\n' > names-leak.md; hook_commit "a private name at HEAD"
  out=$(run_hook leakcheck); rc=$?
  [ "$rc" -eq 1 ] && ok "the fixture list is the one consulted: a private name at HEAD blocks (rc exactly 1)" \
    || bad "the fixture list is the one consulted: a private name at HEAD blocks (rc=$rc)"
  printf '%s' "$out" | grep -q 'names-leak.md:1: private-name:' \
    && ok "and the private-name finding is shown" || bad "and the private-name finding is shown"
  # Mutant home-not-isolated: a different, empty HOME stands for the export removed. The fixture
  # list is no longer consulted, so the finding disappears and the case above fails it.
  mkdir -p "$TMP/otherhome"
  out=$(HOME="$TMP/otherhome" run_hook leakcheck)
  printf '%s' "$out" | grep -q 'names-leak.md:1: private-name:' \
    && bad "mutant home-not-isolated: the fixture list is still consulted" \
    || ok "mutant home-not-isolated: without the fixture HOME the finding vanishes (the private-name case fails it)"
  rm -f names-leak.md "$HOME/.claude/forge-kit/private-names.txt"; hook_commit "drop the private name"
else
  bad "HOME is isolated to the fixture directory (HOME=$HOME)"
fi
# F1: an allow-file entry that exists only in the working tree must not suppress a committed leak.
printf '%s\n' "$LEAKLINE" > docs-leak.md; hook_commit "a committed leak again"
printf 'skip docs-leak.md\n' > .leak-guard-allow
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "F1: an uncommitted skip entry does not mask a committed leak (no allow-file at HEAD)" \
  || bad "F1: an uncommitted skip entry does not mask a committed leak (no allow-file at HEAD) (rc=$rc)"
# #384 item 2, positive: ABSENT at HEAD is not a read failure. rc is exactly 1 on the finding, and
# neither the read-failure line nor a mode refusal is printed.
printf '%s' "$out" | grep -q 'docs-leak.md:1: home-path:' \
  && ok "probe: with no allow-file at HEAD the finding is reported" || bad "probe: with no allow-file at HEAD the finding is reported"
printf '%s' "$out" | grep -q 'could not read .leak-guard-allow at HEAD' \
  && bad "probe: an allow-file absent at HEAD is not reported as unreadable" \
  || ok "probe: an allow-file absent at HEAD is not reported as unreadable"
printf 'root nowhere\n' > .leak-guard-allow; hook_commit "an allow-file without the entry"
printf 'root nowhere\nskip docs-leak.md\n' > .leak-guard-allow
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "F1: an uncommitted skip entry does not mask it over a committed allow-file lacking the entry" \
  || bad "F1: an uncommitted skip entry does not mask it over a committed allow-file lacking the entry (rc=$rc)"
printf '%s' "$out" | grep -q 'home-path' \
  && ok "F1: and it blocks on the finding, not on a malformed allow-file" || bad "F1: and it blocks on the finding, not on a malformed allow-file"
# F2: a committed entry covers the finding; emptying it in the working tree does not un-cover it.
printf 'skip docs-leak.md\n' > .leak-guard-allow; hook_commit "a committed skip"
: > .leak-guard-allow
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 0 ] && ok "F2: a committed skip entry still applies when emptied in the working tree only" \
  || bad "F2: a committed skip entry still applies when emptied in the working tree only (rc=$rc)"
rm -f .leak-guard-allow
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 0 ] && ok "F2: nor when deleted in the working tree" || bad "F2: nor when deleted in the working tree (rc=$rc)"
# F3: an unreadable HEAD allow-file is a could-not-run, never a silent drop of the allow-file.
GSHIM="$TMP/gshim"; mkdir -p "$GSHIM"
REALGIT="$(command -v git)"
# The read is `git cat-file blob <oid>` (#384), so that is the call the shim fails. The scanners
# stream blobs with `cat-file --batch`, which this does not match.
printf '#!/bin/sh\n[ "$1" = cat-file ] && [ "$2" = blob ] && exit 1\nexec "%s" "$@"\n' "$REALGIT" > "$GSHIM/git"
chmod +x "$GSHIM/git"
# A second shim for the PROBE: `ls-tree` naming the allow-file exits 128. The scanners' own ls-tree
# calls carry no such path, so they are untouched and the scan still runs.
PSHIM="$TMP/pshim"; mkdir -p "$PSHIM"
printf '#!/bin/sh\n[ "$1" = ls-tree ] && case "$*" in *.leak-guard-allow*) exit 128;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$PSHIM/git"
chmod +x "$PSHIM/git"
out=$(PATH="$GSHIM:$PATH" run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "F3: a failing read of .leak-guard-allow at HEAD blocks (rc exactly 1)" \
  || bad "F3: a failing read of .leak-guard-allow at HEAD blocks (rc=$rc)"
printf '%s' "$out" | grep -q 'forge-kit: could not read .leak-guard-allow at HEAD' \
  && ok "F3: and names the unreadable allow-file" || bad "F3: and names the unreadable allow-file"
printf '%s' "$out" | grep -q 'could not RUN' \
  && ok "F3: and reports could not RUN, not a finding" || bad "F3: and reports could not RUN, not a finding"
# The hook's own comment no longer describes the working tree as what is scanned.
grep -q 'reads the checked-out worktree' .githooks/pre-push \
  && bad "the hook comment no longer says it reads the checked-out worktree" \
  || ok "the hook comment no longer says it reads the checked-out worktree"
grep -q 'scans the WORKING TREE' .githooks/pre-push \
  && bad "the hook comment no longer says it scans the WORKING TREE" \
  || ok "the hook comment no longer says it scans the WORKING TREE"
# Hook-level mutants, each applied (cmp -s) and each killed. Scratch copies of the hook.
hook_mutant() {  # hook_mutant <name> <sed>: writes .githooks/pre-push.mut-<name>; fails if unchanged
  HM=".githooks/pre-push.mut-$1"; sed "$2" .githooks/pre-push > "$HM"
  if cmp -s "$HM" .githooks/pre-push; then bad "hook mutant ledger ($1): the edit changed nothing"; return 1; fi
  ok "hook mutant ledger ($1): the scratch copy differs from the hook"
}
if hook_mutant swallow-read-error '/could not read .leak-guard-allow at HEAD/{n;s/leak_errors=\$((leak_errors + 1))/:/}'; then
  out=$(PATH="$GSHIM:$PATH" run_hook leakcheck .githooks/pre-push.mut-swallow-read-error)
  printf '%s' "$out" | grep -q 'could not RUN' \
    && bad "mutant: swallowing the read failure still reports could not RUN" \
    || ok "mutant: swallowing the read failure drops could not RUN (the F3 case fails it)"
fi
# #384: the allow-file probe is a MODE check on `git ls-tree --full-tree HEAD -- .leak-guard-allow`.
# State here: HEAD carries a regular skip entry over a committed leak in docs-leak.md.
# 100755 is read like 100644 (100644 is F2 above).
printf 'skip docs-leak.md\n' > .leak-guard-allow; chmod +x .leak-guard-allow; hook_commit "an executable allow-file"
git ls-tree HEAD -- .leak-guard-allow | grep -q '^100755 ' \
  && ok "probe ledger: the committed allow-file is mode 100755" || bad "probe ledger: the committed allow-file is mode 100755"
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 0 ] && ok "probe: a 100755 allow-file at HEAD is read and its skip applies (rc 0)" \
  || bad "probe: a 100755 allow-file at HEAD is read and its skip applies (rc=$rc)"
# A failing PROBE is could-not-RUN, never an absent allow-file; the scan itself still runs.
out=$(PATH="$PSHIM:$PATH" run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "probe: a failing ls-tree probe blocks (rc exactly 1)" \
  || bad "probe: a failing ls-tree probe blocks (rc=$rc)"
printf '%s' "$out" | grep -q 'forge-kit: could not read .leak-guard-allow at HEAD' \
  && ok "probe: and names the unreadable allow-file" || bad "probe: and names the unreadable allow-file"
printf '%s' "$out" | grep -q 'could not RUN' \
  && ok "probe: and reports could not RUN" || bad "probe: and reports could not RUN"
printf '%s' "$out" | grep -q 'docs-leak.md:1: home-path:' \
  && ok "probe: and the scan still ran over the committed leak" || bad "probe: and the scan still ran over the committed leak"
# A symlink at HEAD, entry-shaped link text: the case that failed OPEN (exit 0 over a leak).
rm -f .leak-guard-allow; ln -s 'skip docs-leak.md' .leak-guard-allow; hook_commit "a symlinked allow-file, entry-shaped text"
git ls-tree HEAD -- .leak-guard-allow | grep -q '^120000 ' \
  && ok "probe ledger: the committed allow-file is mode 120000" || bad "probe ledger: the committed allow-file is mode 120000"
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "symlink: a 120000 allow-file whose text is a valid entry blocks (rc exactly 1, never 0)" \
  || bad "symlink: a 120000 allow-file whose text is a valid entry blocks (rc=$rc)"
printf '%s' "$out" | grep -q 'could not RUN' \
  && ok "symlink: and reports could not RUN" || bad "symlink: and reports could not RUN"
printf '%s' "$out" | grep -q 'forge-kit: .leak-guard-allow at HEAD is mode 120000, not a regular file' \
  && ok "symlink: and prints the hook's own refusal naming the mode" || bad "symlink: and prints the hook's own refusal naming the mode"
if hook_mutant symlink-mode-unchecked 's/100644|100755)/100644|100755|120000)/'; then
  out=$(run_hook leakcheck .githooks/pre-push.mut-symlink-mode-unchecked); rc=$?
  [ "$rc" -eq 0 ] && ok "mutant symlink-mode-unchecked: reading a 120000 link applies its text and passes the leak (the entry-shaped case fails it)" \
    || bad "mutant symlink-mode-unchecked: reading a 120000 link applies its text and passes the leak (rc=$rc)"
fi
# A symlink whose text is NOT an entry: refused by the same mode check, with no scanner parse error.
rm -f .githooks/pre-push.mut-* .leak-guard-allow; ln -s real-allow.txt .leak-guard-allow; hook_commit "a symlinked allow-file, plain text"
out=$(run_hook leakcheck); rc=$?
[ "$rc" -eq 1 ] && ok "symlink: a 120000 allow-file to real-allow.txt blocks (rc exactly 1)" \
  || bad "symlink: a 120000 allow-file to real-allow.txt blocks (rc=$rc)"
printf '%s' "$out" | grep -q 'could not RUN' && ok "symlink: and reports could not RUN" || bad "symlink: and reports could not RUN"
printf '%s' "$out" | grep -q 'is mode 120000, not a regular file' \
  && ok "symlink: the refusal line names mode 120000" || bad "symlink: the refusal line names mode 120000"
printf '%s' "$out" | grep -q 'entry has no value' \
  && bad "symlink: no scanner parse error for a non-entry link" || ok "symlink: no scanner parse error for a non-entry link"
if hook_mutant symlink-mode-unchecked-b 's/100644|100755)/100644|100755|120000)/'; then
  out=$(run_hook leakcheck .githooks/pre-push.mut-symlink-mode-unchecked-b)
  printf '%s' "$out" | grep -q 'entry has no value' \
    && ok "mutant symlink-mode-unchecked: a non-entry link reaches the scanner's parse error (the no-parse-error assertion fails it)" \
    || bad "mutant symlink-mode-unchecked: a non-entry link reaches the scanner's parse error"
fi
# probe-error-as-absent: a failing probe falls through to "no allow-file". Needs HEAD to carry a
# regular allow-file so the shimmed probe has something to lose.
rm -f .githooks/pre-push.mut-* .leak-guard-allow; printf 'skip docs-leak.md\n' > .leak-guard-allow; hook_commit "a regular skip allow-file again"
if hook_mutant probe-error-as-absent 's/^if ! al_line=\(.*\); then$/if ! al_line=\1 \&\& false; then/'; then
  out=$(PATH="$PSHIM:$PATH" run_hook leakcheck .githooks/pre-push.mut-probe-error-as-absent)
  printf '%s' "$out" | grep -q 'could not read .leak-guard-allow at HEAD' \
    && bad "mutant probe-error-as-absent: a failing probe is treated as absent and the report is lost" \
    || ok "mutant probe-error-as-absent: a failing probe is treated as absent (the probe-failure case fails it)"
fi
rm -f .githooks/pre-push.mut-*
# #396: the hook changes to the work-tree root before every directory-relative step, so a hand run
# from a SUBDIRECTORY scans the whole of HEAD, exactly as a run from the root does. Git itself runs
# a pre-push hook from the root, so a real push never needed this; it is the hand run that failed
# open. The case plants a leak OUTSIDE sub/ in root-leak.md (not docs-leak.md, which the root
# allow-file's `skip docs-leak.md` covers at this point) and expects it reported from sub/. The
# `--full-tree` flag on the probe is now defence in depth with no test of its own: the `cd` makes
# the probe root-relative already (#388 pinned the flag; its mutant became equivalent here). Both
# hooks are called by absolute path because `run_hook`'s default is relative to the root. The
# fixture and the mutant copies are removed afterwards: `hook_commit` runs `git add -A`.
HOOKABS="$REPO/.githooks/pre-push"
run_hook_in() {  # run_hook_in <dir> <hook>: the hook run with <dir> as its working directory
  local sha; sha=$(git rev-parse HEAD)
  ( CDPATH= cd -- "$1" && printf '%s %s %s %s\n' "refs/heads/leakcheck" "$sha" "refs/heads/leakcheck" \
      "0000000000000000000000000000000000000000" | bash "$2" origin "$BARE" 2>&1 )
}
run_hook_sub() { run_hook_in "$REPO/sub" "$1"; }  # run_hook_sub <hook>: sub/ as the working directory
mkdir -p sub; printf 'clean\n' > sub/notes.md; hook_commit "a clean tracked file under sub/"
out=$(run_hook_sub "$HOOKABS"); rc=$?
[ "$rc" -eq 0 ] && ok "subdirectory: with no unskipped leak anywhere, the hook run from sub/ exits 0" \
  || bad "subdirectory: with no unskipped leak anywhere, the hook run from sub/ exits 0 (rc=$rc)"
printf '%s' "$out" | grep -q 'could not RUN' \
  && bad "subdirectory: and nothing reports could not RUN" || ok "subdirectory: and nothing reports could not RUN"
printf '%s' "$out" | grep -q 'home-path:' \
  && bad "subdirectory: and no finding line is printed" || ok "subdirectory: and no finding line is printed"
printf '%s\n' "$LEAKLINE" > root-leak.md; hook_commit "a leak at the root, outside sub/"
out=$(run_hook_sub "$HOOKABS"); rc=$?
[ "$rc" -eq 1 ] && ok "subdirectory: run from sub/, a committed leak at the root is reported (rc 1)" \
  || bad "subdirectory: run from sub/, a committed leak at the root is reported (rc=$rc)"
printf '%s' "$out" | grep -q 'root-leak.md:1: home-path:' \
  && ok "subdirectory: and the finding line names root-leak.md" || bad "subdirectory: and the finding line names root-leak.md"
printf '%s' "$out" | grep -q 'forge-kit: the tree carries something from this machine' \
  && ok "subdirectory: and the hook says the tree carries something from this machine" \
  || bad "subdirectory: and the hook says the tree carries something from this machine"
if hook_mutant cd-dropped '/^\[ -n "\$ROOT" \] && CDPATH= cd -- "\$ROOT" /d'; then
  out=$(run_hook_sub "$HOOKABS.mut-cd-dropped"); rc=$?
  [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'root-leak.md:1:' \
    && ok "mutant cd-dropped: from sub/ the root leak is invisible (rc 0, no finding line)" \
    || bad "mutant cd-dropped: from sub/ the root leak is invisible (rc=$rc)"
fi
# Fail closed: from .git, `rev-parse --show-toplevel` fails and ROOT is empty, where a bare
# `cd "$ROOT"` returns 0 without moving. The hook must exit 1, not 0, over the committed leak.
out=$(run_hook_in "$REPO/.git" "$HOOKABS"); rc=$?
[ "$rc" -eq 1 ] && ok "fail closed: run from .git over a committed root leak the hook exits 1" \
  || bad "fail closed: run from .git over a committed root leak the hook exits 1 (rc=$rc)"
printf '%s' "$out" | grep -q 'could not change to the work-tree root' \
  && printf '%s' "$out" | grep -q 'could not RUN' \
  && ok "fail closed: and the output says it could not change to the work-tree root and could not RUN" \
  || bad "fail closed: and the output says it could not change to the work-tree root and could not RUN"
if hook_mutant cd-unguarded 's|^\[ -n "\$ROOT" \] && CDPATH= cd -- "\$ROOT" .*$|cd "$ROOT"|'; then
  out=$(run_hook_in "$REPO/.git" "$HOOKABS.mut-cd-unguarded"); rc=$?
  [ "$rc" -eq 0 ] && ok "mutant cd-unguarded: a bare cd of an empty ROOT fails open from .git (rc 0)" \
    || bad "mutant cd-unguarded: a bare cd of an empty ROOT fails open from .git (rc=$rc)"
fi
rm -f .githooks/pre-push.mut-*; rm -f root-leak.md sub/notes.md; rmdir sub
# Both remaining mutants need HEAD to carry an allow-file WITHOUT the skip entry, plus the committed leak.
printf 'root nowhere\n' > .leak-guard-allow; hook_commit "an allow-file without the entry, for the mutants"
if hook_mutant worktree-allow 's|git cat-file blob "$al_oid"|cat .leak-guard-allow|; s|git ls-tree --full-tree HEAD -- .leak-guard-allow|echo 100644 blob x|'; then
  printf 'root nowhere\nskip docs-leak.md\n' > .leak-guard-allow
  out=$(run_hook leakcheck .githooks/pre-push.mut-worktree-allow); rc=$?
  [ "$rc" -eq 0 ] && ok "mutant: reading the allow-file from the worktree lets an uncommitted skip mask the leak (F1 fails it)" \
    || bad "mutant: reading the allow-file from the worktree lets an uncommitted skip mask the leak (rc=$rc)"
  printf 'root nowhere\n' > .leak-guard-allow
fi
if hook_mutant worktree-scan 's/ --head//'; then
  printf 'edited out, not committed\n' > docs-leak.md
  out=$(run_hook leakcheck .githooks/pre-push.mut-worktree-scan); rc=$?
  [ "$rc" -eq 0 ] && ok "mutant: dropping --head reads the worktree and passes the masked leak (the masked case fails it)" \
    || bad "mutant: dropping --head reads the worktree and passes the masked leak (rc=$rc)"
fi
rm -f .githooks/pre-push.mut-* .leak-guard-allow docs-leak.md
git add -A >/dev/null; git commit --quiet --allow-empty -m "restore a clean tree"

# --- the roadmap guard's OFFLINE half ----------------------------------------------------------
# --offline on purpose: a push must never depend on the host being reachable, and rule 2 (an open
# phase has a plan carrying a Fails if section) needs only the files.
echo "== roadmap phase guard =="
RG=plugins/forge-kit-roadmap/skills/roadmap-phases/assets
mkdir -p "$RG" docs/plans
# Both assets: the format lives in roadmap-lib.sh (#162), so installing the guard alone is a
# refusal rather than a degraded run. That refusal is itself covered in test-check-phases.sh.
cp "$ROOT/$RG/check-phases.sh" "$ROOT/$RG/roadmap-lib.sh" "$RG/"
cat > docs/roadmap.md <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '# A\n\n## Goal\nx\n\n## Fails if\nx\n' > docs/plans/a.md
git add -A >/dev/null; git commit --quiet -m "a roadmap with a complete plan"
out=$(run_hook roadmapok); rc=$?
[ "$rc" -eq 0 ] && ok "a phase with a complete plan does not block the push" \
  || bad "a phase with a complete plan does not block the push (rc=$rc)"

printf '# A\n\n## Goal\nx\n' > docs/plans/a.md
git add -A >/dev/null; git commit --quiet -m "plan loses its premortem"
out=$(run_hook roadmapbad); rc=$?
[ "$rc" -ne 0 ] && ok "a plan with no Fails if section blocks the push" \
  || bad "a plan with no Fails if section blocks the push (rc=$rc)"
printf '%s' "$out" | grep -q 'rule 2' \
  && ok "and the rule is named" || bad "and the rule is named"
# Round 2 of the leak guard's review found exactly this class: a check sharing another check's
# counter reports its finding in the other's words, and the words say what to do about it.
printf '%s' "$out" | grep -qi 'from this machine' \
  && bad "a roadmap failure is not reported as a leak" \
  || ok "a roadmap failure is not reported as a leak"
printf '%s' "$out" | grep -qi 'roadmap' \
  && ok "and is reported in its own words" || bad "and is reported in its own words"
# #311: the host rules run from /phase, not in CI (CI runs only the guard's contract tests).
printf '%s' "$out" | grep -q 'host rules run in CI' \
  && bad "a roadmap failure does not claim the host rules run in CI" \
  || ok "a roadmap failure does not claim the host rules run in CI"
# Permanent mutant (#366): the restored claim, on a scratch copy outside the fixture's tree, so
# it can never be committed by the `git add -A` below.
mut_rm="$TMP/mut-roadmap.sh"
sed "/host rules run from \\/phase;/s/the host rules run from \/phase; CI runs only the guard's contract tests\./the host rules run in CI and from \/phase./" \
  "$ROOT/.githooks/pre-push" > "$mut_rm"
if grep -q "the host rules run from /phase; CI runs only the guard's contract tests" "$ROOT/.githooks/pre-push" \
   && ! cmp -s "$mut_rm" "$ROOT/.githooks/pre-push"; then
  # Captured, not piped: under pipefail a `grep -q` that exits early SIGPIPEs the hook and the
  # pipeline then reports failure although the pattern matched.
  mout="$(run_hook roadmapbad "$mut_rm")"
  printf '%s' "$mout" | grep -q 'host rules run in CI' \
    && ok "the roadmap check detects the restored claim" \
    || bad "the roadmap check detects the restored claim"
else
  bad "the roadmap check detects the restored claim (ledger or mutant failed)"
fi
# #396: the roadmap guard reads docs/roadmap.md relative to the working directory, so from sub/ it
# used to print "nothing to check" and exit 0 over a plan lacking Fails if. Distinct variable names
# (rs_out, rs_rc): the assertions above read $out from the roadmapbad run, and the bad plan must
# stay committed for the mutant below.
mkdir -p sub; printf 'clean\n' > sub/notes.md; hook_commit "a tracked file under sub/, plan still lacks Fails if"
rs_out=$(run_hook_sub "$HOOKABS"); rs_rc=$?
[ "$rs_rc" -eq 1 ] && ok "roadmap from sub/: a plan with no Fails if section blocks the push (rc 1)" \
  || bad "roadmap from sub/: a plan with no Fails if section blocks the push (rc=$rs_rc)"
printf '%s' "$rs_out" | grep -q 'rule 2:' \
  && printf '%s' "$rs_out" | grep -q 'the roadmap does not satisfy check-phases.sh' \
  && ok "roadmap from sub/: and rule 2 and the roadmap message are printed" \
  || bad "roadmap from sub/: and rule 2 and the roadmap message are printed"
if hook_mutant cd-undone-before-roadmap '/^phase_problems=0$/i cd -- "$OLDPWD"'; then
  rs_out=$(run_hook_sub "$HOOKABS.mut-cd-undone-before-roadmap"); rs_rc=$?
  [ "$rs_rc" -eq 0 ] && printf '%s' "$rs_out" | grep -q 'nothing to check' \
    && ok "mutant cd-undone-before-roadmap: from sub/ the roadmap guard is skipped as nothing to check (rc 0)" \
    || bad "mutant cd-undone-before-roadmap: from sub/ the roadmap guard is skipped as nothing to check (rc=$rs_rc)"
fi
rm -f .githooks/pre-push.mut-*
printf '# A\n\n## Goal\nx\n\n## Fails if\nx\n' > docs/plans/a.md
hook_commit "plan regains its premortem, for the sub/ positive case"
rs_out=$(run_hook_sub "$HOOKABS"); rs_rc=$?
[ "$rs_rc" -eq 0 ] && ok "roadmap from sub/: a complete plan exits 0" \
  || bad "roadmap from sub/: a complete plan exits 0 (rc=$rs_rc)"
printf '%s' "$rs_out" | grep -q 'nothing to check' \
  && bad "roadmap from sub/: and the guard did not skip as nothing to check" \
  || ok "roadmap from sub/: and the guard did not skip as nothing to check"
rm -f sub/notes.md; rmdir sub
rm -rf docs plugins/forge-kit-roadmap; git add -A >/dev/null; git commit --quiet -m cleanup

cd "$ROOT"

echo "== the local-doc claims are checked here, because nowhere else can (#218) =="
# CLAUDE.md stopped being published on 2026-09-16, so its suite-count claims and its
# generated plugin-groups region are in no CI checkout. The step that checked the counts was
# deleted rather than disabled, and this rule is where the question is asked instead. The cases
# that matter most are the negative ones: a checkout WITHOUT the doc must not be blocked, and a
# suite that could not run must not be reported as a stale claim.
cd "$REPO"
git checkout --quiet main
mkdir -p scripts
cp "$ROOT/scripts/update-suite-counts.py" "$ROOT/scripts/update-component-index.py" \
   "$ROOT/scripts/forge-adapt-catalogue.sh" scripts/
# A fixture suite that prints a known total AND records that it ran, so "which suites ran" is
# asserted by sentinels rather than by wall time, which a loaded machine makes unreliable.
cat > scripts/test-fixture-one.sh <<'F1'
#!/usr/bin/env bash
: > "${SENTINEL_DIR:-$(dirname "$0")}/one.ran"
echo "fixture one: 7 passed, 0 failed"
F1
cat > scripts/test-fixture-two.sh <<'F2'
#!/usr/bin/env bash
: > "${SENTINEL_DIR:-$(dirname "$0")}/two.ran"
echo "fixture two: 3 passed, 0 failed"
F2
chmod +x scripts/test-fixture-one.sh scripts/test-fixture-two.sh
# The index generator rewrites three regions across two files, so the fixture carries both.
printf '# Fixture\n\n<!-- plugin-catalogue:start -->\n<!-- plugin-catalogue:end -->\n\n<!-- component-index:start -->\n<!-- component-index:end -->\n' > README.md
printf '# Fixture rules\n\n- `scripts/test-fixture-one.sh`, 7 tests, in CI.\n- `scripts/test-fixture-two.sh`, 3 tests, in CI.\n\n<!-- plugin-groups:start -->\n<!-- plugin-groups:end -->\n' > CLAUDE.md
git add -A >/dev/null; git commit --quiet -m "fixture: the local doc and its claims"
python3 scripts/update-component-index.py >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "fixture: generated regions current" 2>/dev/null
git push --quiet origin main 2>/dev/null

SENT="$TMP/sent"; mkdir -p "$SENT"
# push_range <base-sha>: the stdin a real push sends when the remote already has the branch.
push_range() {
  local sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/main" "$sha" "refs/heads/main" "$1" \
    | SENTINEL_DIR="$SENT" bash .githooks/pre-push origin "$BARE" 2>&1
}

# A push that touches no counted suite must run none of them.
rm -f "$SENT"/*.ran
base=$(git rev-parse HEAD)
printf 'prose\n' > notes.md; git add -A >/dev/null; git commit --quiet -m prose
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "a push touching no counted suite passes" || bad "a push touching no counted suite passes (rc $rc, $out)"
printf '%s' "$out" | grep -q 'no counted suite changed' && ok "and says no counted suite changed" || bad "and says no counted suite changed"
ls "$SENT"/*.ran >/dev/null 2>&1 && bad "and invoked no suite" || ok "and invoked no suite"

# A push that changes one counted suite runs THAT suite and no other.
rm -f "$SENT"/*.ran
base=$(git rev-parse HEAD)
printf '#!/usr/bin/env bash\n: > "${SENTINEL_DIR:-$(dirname "$0")}/one.ran"\necho "fixture one: 8 passed, 0 failed"\n' > scripts/test-fixture-one.sh
git add -A >/dev/null; git commit --quiet -m "one more case in fixture one"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a suite that grew without its claim being regenerated blocks the push" || bad "a suite that grew without its claim being regenerated blocks the push (rc $rc)"
printf '%s' "$out" | grep -q 'test-fixture-one.sh' && ok "naming the claim" || bad "naming the claim"
printf '%s' "$out" | grep -q 'update-suite-counts.py' && ok "and the script that fixes it" || bad "and the script that fixes it"
[ -f "$SENT/one.ran" ] && ok "the changed suite was invoked" || bad "the changed suite was invoked"
[ -f "$SENT/two.ran" ] && bad "and the unchanged one was not" || ok "and the unchanged one was not"

# #396: the same stale-count path from a SUBDIRECTORY. The suite-count pathspec
# `-- 'scripts/test-*'` is directory-relative, so without the hook's `cd` to the root a run from
# sub/ would list no changed suite and say nothing counted changed. The mutant undoes the cd just
# before the doc rule runs, which is the only step this case isolates.
rm -f "$SENT"/*.ran
mkdir -p sub
sub_push() {  # sub_push <hook> <base-sha>: the hook run from sub/ over the main push
  local sha; sha=$(git rev-parse HEAD)
  ( CDPATH= cd -- "$REPO/sub" && printf '%s %s %s %s\n' "refs/heads/main" "$sha" "refs/heads/main" "$2" \
      | SENTINEL_DIR="$SENT" bash "$1" origin "$BARE" 2>&1 )
}
out="$(sub_push "$REPO/.githooks/pre-push" "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "suite counts from sub/: a stale claim still blocks the push (rc 1)" || bad "suite counts from sub/: a stale claim still blocks the push (rc $rc, $out)"
printf '%s' "$out" | grep -q 'test-fixture-one.sh' && ok "suite counts from sub/: and the claim is named" || bad "suite counts from sub/: and the claim is named"
[ -f "$SENT/one.ran" ] && ok "suite counts from sub/: and the changed suite was invoked" || bad "suite counts from sub/: and the changed suite was invoked"
if hook_mutant cd-undone-before-counts 's|^doc_problems=0$|cd -- "$OLDPWD"\ndoc_problems=0|'; then
  rm -f "$SENT"/*.ran
  out="$(sub_push "$REPO/.githooks/pre-push.mut-cd-undone-before-counts" "$base")"; rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no counted suite changed' \
    && ok "mutant cd-undone-before-counts: from sub/ the changed suite is invisible (rc 0, no counted suite changed)" \
    || bad "mutant cd-undone-before-counts: from sub/ the changed suite is invisible (rc $rc)"
fi
rm -f .githooks/pre-push.mut-*; rmdir sub

# Regenerating the claim clears it.
python3 scripts/update-suite-counts.py --doc CLAUDE.md --root . >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate the claim"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "regenerating the claim clears the block" || bad "regenerating the claim clears the block (rc $rc, $out)"

# THE CASE THAT MATTERS MOST: no doc, no block, and nothing said about counts.
base=$(git rev-parse HEAD)
git rm -q CLAUDE.md; git commit --quiet -m "the doc is local now"
printf '#!/usr/bin/env bash\n: > "${SENTINEL_DIR:-$(dirname "$0")}/one.ran"\necho "fixture one: 9 passed, 0 failed"\n' > scripts/test-fixture-one.sh
git add -A >/dev/null; git commit --quiet -m "a change a contributor without the doc makes"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "a checkout without the doc is not blocked" || bad "a checkout without the doc is not blocked (rc $rc, $out)"
printf '%s' "$out" | grep -qi 'stale:' && bad "and nothing is said about stale claims" || ok "and nothing is said about stale claims"
git checkout --quiet HEAD~2 -- CLAUDE.md 2>/dev/null; git add -A >/dev/null; git commit --quiet -m "restore the fixture doc"
python3 scripts/update-suite-counts.py --doc CLAUDE.md --root . >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate" 2>/dev/null

# A suite that cannot report a total is could-not-run, not a stale claim.
base=$(git rev-parse HEAD)
printf '#!/usr/bin/env bash\necho "this suite prints no recognisable total"\n' > scripts/test-fixture-two.sh
git add -A >/dev/null; git commit --quiet -m "fixture two stops reporting"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a suite that cannot report a total blocks the push" || bad "a suite that cannot report a total blocks the push (rc $rc)"
printf '%s' "$out" | grep -q 'could not RUN' && ok "in could-not-run wording, not stale-claim wording" || bad "in could-not-run wording, not stale-claim wording"
git checkout --quiet HEAD~1 -- scripts/test-fixture-two.sh; git add -A >/dev/null; git commit --quiet -m "restore fixture two"

# A stale GENERATED region blocks too, so the index half is exercised and not merely invoked.
base=$(git rev-parse HEAD)
sed -i 's/plugin-catalogue:start -->/plugin-catalogue:start -->\nhand-edited/' README.md
git add -A >/dev/null; git commit --quiet -m "hand-edit a generated region"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a hand-edited generated region blocks the push" || bad "a hand-edited generated region blocks the push (rc $rc)"
python3 scripts/update-component-index.py >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate the region"

# No python3: a loud skip, never a block. PATH is emptied of it for one run only.
base=$(git rev-parse HEAD)
mkdir -p "$TMP/nopy"
for c in git bash sed grep awk cat cut sort uniq head tail diff mktemp rm mkdir printf ls env dirname basename readlink wc tr find chmod cp date; do
  p_="$(command -v "$c" 2>/dev/null)"; [ -n "$p_" ] && ln -sf "$p_" "$TMP/nopy/$c"
done
sha=$(git rev-parse HEAD)
out="$(printf '%s %s %s %s\n' "refs/heads/main" "$sha" "refs/heads/main" "$base" | PATH="$TMP/nopy" bash .githooks/pre-push origin "$BARE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "no python3 does not block the push" || bad "no python3 does not block the push (rc $rc, $out)"
printf '%s' "$out" | grep -q 'python3 not found' && ok "and says so loudly" || bad "and says so loudly"

# A MISSING GENERATOR IS A LOUD SKIP (#221), one condition per generator. Both are repo-owned
# scripts, not opt-in guards, so an absent one means a checkout that is missing part of the kit,
# and the claims it owns go unchecked. Each case captures STDERR ALONE (stdout discarded), because
# the contract is that the notice is on stderr: a merged stream would pass a notice sent to stdout.
push_range_err() {  # push_range_err <base-sha>: the hook's stderr only
  local sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/main" "$sha" "refs/heads/main" "$1" \
    | SENTINEL_DIR="$SENT" bash .githooks/pre-push origin "$BARE" 2>&1 >/dev/null
}
# The exit code is read with `rc=$?` IMMEDIATELY after `err="$(push_range_err ...)"`. Under
# pipefail the status of that assignment is the pipeline's, and the hook is the pipeline's last
# stage, so it IS the hook's status: no second run is needed (#311 corrected an earlier comment
# that said otherwise). `local err=...` would break this, since `local` returns its own status,
# which is why these are plain assignments. The "exits through the index check" case below proves
# the status is the hook's and not a constant, since all the others assert 0.
base=$(git rev-parse HEAD)
printf 'prose two\n' > notes.md; git add -A >/dev/null; git commit --quiet -m "prose for the generator cases"
cp scripts/update-suite-counts.py "$TMP/cnt.bak"
cp scripts/update-component-index.py "$TMP/idx.bak"

rm scripts/update-suite-counts.py
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "a missing update-suite-counts.py does not block the push" || bad "a missing update-suite-counts.py does not block the push (rc $rc)"
printf '%s' "$err" | grep -q '^  ! pre-push: .*update-suite-counts.py' && ok "and stderr carries a named skip line" || bad "and stderr carries a named skip line ($err)"
printf '%s' "$err" | grep 'update-suite-counts.py' | grep -q 'NOT checked' && ok "that says the suite-count claims were NOT checked" || bad "that says the suite-count claims were NOT checked"
printf '%s' "$err" | grep -q 'update-component-index.py' && bad "and does not name the other generator" || ok "and does not name the other generator"
cp "$TMP/cnt.bak" scripts/update-suite-counts.py

rm scripts/update-component-index.py
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "a missing update-component-index.py does not block the push" || bad "a missing update-component-index.py does not block the push (rc $rc)"
printf '%s' "$err" | grep -q '^  ! pre-push: .*update-component-index.py' && ok "and stderr carries a named skip line" || bad "and stderr carries a named skip line ($err)"
printf '%s' "$err" | grep 'update-component-index.py' | grep -q 'NOT checked' && ok "that says the generated regions were NOT checked" || bad "that says the generated regions were NOT checked"
printf '%s' "$err" | grep -q 'update-suite-counts.py' && bad "and does not name the other generator" || ok "and does not name the other generator"
cp "$TMP/idx.bak" scripts/update-component-index.py

rm scripts/update-suite-counts.py scripts/update-component-index.py
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "both generators missing does not block the push" || bad "both generators missing does not block the push (rc $rc)"
if printf '%s' "$err" | grep -q '^  ! pre-push: .*update-suite-counts.py' && printf '%s' "$err" | grep -q '^  ! pre-push: .*update-component-index.py'; then
  ok "and two skips are named, one per generator"; else bad "and two skips are named, one per generator ($err)"; fi
cp "$TMP/cnt.bak" scripts/update-suite-counts.py
cp "$TMP/idx.bak" scripts/update-component-index.py

err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 0 ] && ok "with both generators present the push passes" || bad "with both generators present the push passes (rc $rc)"
if printf '%s' "$err" | grep -q 'update-suite-counts.py\|update-component-index.py'; then
  bad "and stderr carries no generator skip line ($err)"; else ok "and stderr carries no generator skip line"; fi
# Current regions: no stale notice at all, and never a region name (#311, L5).
if printf '%s' "$err" | grep -q 'plugin-catalogue\|component-index\|STALE'; then
  bad "and a current index names no region and no STALE ($err)"; else ok "and a current index names no region and no STALE"; fi

# The skip covers only an ABSENT script; it never replaces the real check.
sed -i 's/plugin-catalogue:start -->/plugin-catalogue:start -->\nhand-edited/' README.md
git add -A >/dev/null; git commit --quiet -m "hand-edit a generated region again"
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a present index generator still blocks a hand-edited region" || bad "a present index generator still blocks a hand-edited region (rc $rc)"
printf '%s' "$out" | grep -q 'a generated claim in a LOCAL doc is stale or could not be checked' && ok "with the stale-claim message" || bad "with the stale-claim message"
python3 scripts/update-component-index.py >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate the region again"

# A STALE REGION IS NAMED ON STDERR, and the exit status is the hook's (#311, L5 and L3). One hand
# edit, committed, captured through push_range_err: stderr alone, rc taken at once. rc is 1 here and
# 0 everywhere above, so a hardcoded `rc=0` or a capture that dropped the status fails this case.
sed -i 's/plugin-catalogue:start -->/plugin-catalogue:start -->\nhand-edited/' README.md
git add -A >/dev/null; git commit --quiet -m "hand-edit the plugin-catalogue region"
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a stale generated region exits 1 through the stderr-only capture" || bad "a stale generated region exits 1 through the stderr-only capture (rc $rc)"
printf '%s' "$err" | grep -q 'update-component-index.py' && ok "stderr names the generator that reported it" || bad "stderr names the generator that reported it ($err)"
printf '%s' "$err" | grep -q 'README.md (plugin-catalogue)' && ok "and the stale region, as file and id" || bad "and the stale region, as file and id ($err)"
printf '%s' "$err" | grep -q 'component-index)' && bad "and does not name a region that is current" || ok "and does not name a region that is current"
python3 scripts/update-component-index.py >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate the plugin-catalogue region"

# BOTH README regions stale: both are named, each once, as two distinct entries. Before #311 the
# list carried the bare file name, which would have printed README.md twice with nothing to tell
# the two apart.
sed -i 's/plugin-catalogue:start -->/plugin-catalogue:start -->\nhand-edited/; s/component-index:start -->/component-index:start -->\nhand-edited/' README.md
git add -A >/dev/null; git commit --quiet -m "hand-edit both README regions"
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "two stale regions exit 1" || bad "two stale regions exit 1 (rc $rc)"
printf '%s' "$err" | grep -q 'README.md (plugin-catalogue)' && ok "the first stale region is named" || bad "the first stale region is named ($err)"
printf '%s' "$err" | grep -q 'README.md (component-index)' && ok "the second stale region is named" || bad "the second stale region is named ($err)"
[ "$(printf '%s' "$err" | grep -o 'README.md (' | wc -l)" -eq 2 ] && ok "each exactly once" || bad "each exactly once ($err)"
python3 scripts/update-component-index.py >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate both README regions"

# A region whose marker pair is gone is a generator SystemExit on stderr. It is not swallowed by
# the capture, so the reason (which file, which marker) stays visible next to the hook's own line.
cp README.md "$TMP/readme.bak"
sed -i '/plugin-catalogue:end -->/d' README.md
git add -A >/dev/null; git commit --quiet -m "remove a region marker"
err="$(push_range_err "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "a missing region marker exits 1" || bad "a missing region marker exits 1 (rc $rc)"
printf '%s' "$err" | grep -q "has no 'plugin-catalogue' region" && ok "and the generator's own reason stays visible on stderr" || bad "and the generator's own reason stays visible on stderr ($err)"
cp "$TMP/readme.bak" README.md
git add -A >/dev/null; git commit --quiet -m "restore the region marker"

# THE PLACEMENT ITSELF (review round 1 on #218). Every case above runs with origin/main intact, so
# moving the whole block below the base-ref exit at the end of this hook left the suite green. The
# defect that mutation reintroduces is the one gate round 2 blocked this ticket on: with no
# remote-tracking ref, a rule placed down there is skipped by a bare `exit 0` and says nothing.
# Here the remote tip comes from the hook's own stdin, which is why the rule can still run.
base=$(git rev-parse HEAD)
printf '#!/usr/bin/env bash\n: > "${SENTINEL_DIR:-$(dirname "$0")}/one.ran"\necho "fixture one: 11 passed, 0 failed"\n' > scripts/test-fixture-one.sh
git add -A >/dev/null; git commit --quiet -m "a claim goes stale"
git update-ref -d refs/remotes/origin/HEAD 2>/dev/null
git update-ref -d refs/remotes/origin/main 2>/dev/null
out="$(push_range "$base")"; rc=$?
[ "$rc" -eq 1 ] && ok "with no remote-tracking ref at all, a stale claim still blocks: the rule sits above the base-ref exit" \
  || bad "with no remote-tracking ref at all, a stale claim still blocks (rc $rc, $out)"
printf '%s' "$out" | grep -q 'test-fixture-one.sh' && ok "and still names the claim" || bad "and still names the claim"

# ITS OWN SKIP LINE. No remote-tracking ref AND a branch the remote does not have: there is no
# range to compute, so the rule must say so in its own words rather than leave the impression it
# checked. Distinct from the range guards' 'range checks SKIPPED', which is a different rule.
sha=$(git rev-parse HEAD)
out="$(printf '%s %s %s %s\n' "refs/heads/main" "$sha" "refs/heads/main" \
  "0000000000000000000000000000000000000000" \
  | SENTINEL_DIR="$SENT" bash .githooks/pre-push origin "$BARE" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "with no range at all the push is not blocked" || bad "with no range at all the push is not blocked (rc $rc)"
printf '%s' "$out" | grep -q 'suite-count claims were NOT checked' \
  && ok "and the rule says so in its own words" || bad "and the rule says so in its own words"
git fetch -q origin main 2>/dev/null
git remote set-head origin main >/dev/null 2>&1   # after the fetch: before it, there is no ref to point at
python3 scripts/update-suite-counts.py --doc CLAUDE.md --root . >/dev/null 2>&1
git add -A >/dev/null; git commit --quiet -m "regenerate after the placement cases" 2>/dev/null

cd "$ROOT"

echo "== the history mode never reaches the hook =="
# --history (#191) is a pre-publish step run by hand: it reads the whole reachable store and its
# evidence is a report, not a commit gate. A hook that ran it would make every commit or push wait
# on the history and print redacted findings nobody asked for.
grep -q -- '--history' "$ROOT/.githooks/pre-push" \
  && bad "the pre-push hook does not invoke --history" || ok "the pre-push hook does not invoke --history"

echo ""
echo "pre-push hook tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
