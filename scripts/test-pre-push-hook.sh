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
for frag in 'pull requests' "PR's target branch" 'pushes to main and develop' 'previous tip' 'can differ' 'new ref or a force push' 'triggers no'; do
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
# Exactly 1: the leak block exits 1, and so does the leak_errors branch, so -ne 0 proved little.
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
for frag in 'CI also runs' 'pushes to main and develop' 'triggers no CI scan' 'runs only on this machine' '--no-verify publishes it'; do
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
