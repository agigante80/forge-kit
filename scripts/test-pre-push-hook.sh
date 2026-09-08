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

# push_stdin <ref>: the four fields git feeds a pre-push hook for a new branch.
run_hook() {
  local ref="$1" sha; sha=$(git rev-parse HEAD)
  printf '%s %s %s %s\n' "refs/heads/$ref" "$sha" "refs/heads/$ref" \
    "0000000000000000000000000000000000000000" \
    | bash .githooks/pre-push origin "$BARE" 2>&1
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
[ "$rc" -ne 0 ] && ok "a leak blocks the push even with no base ref" \
  || bad "a leak blocks the push even with no base ref (rc=$rc)"
printf '%s' "$out" | grep -q 'home-path' \
  && ok "and the finding itself is shown" || bad "and the finding itself is shown"
printf '%s' "$out" | grep -qi 'NOT one of the CI checks' \
  && ok "the message does not claim CI will catch it" \
  || bad "the message does not claim CI will catch it"
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
rm -f .leak-guard-allow docs-leak.md; git add -A >/dev/null; git commit --quiet -m cleanup

cd "$ROOT"

echo ""
echo "pre-push hook tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
