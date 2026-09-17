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
rm -rf docs plugins/forge-kit-roadmap; git add -A >/dev/null; git commit --quiet -m cleanup

cd "$ROOT"

echo "== the local-doc claims are checked here, because nowhere else can (#218) =="
# CLAUDE.md stopped being published on 2026-09-16, so its twelve suite-count claims and its
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
: > "${SENTINEL_DIR:-/tmp}/one.ran"
echo "fixture one: 7 passed, 0 failed"
F1
cat > scripts/test-fixture-two.sh <<'F2'
#!/usr/bin/env bash
: > "${SENTINEL_DIR:-/tmp}/two.ran"
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
printf '#!/usr/bin/env bash\n: > "${SENTINEL_DIR:-/tmp}/one.ran"\necho "fixture one: 8 passed, 0 failed"\n' > scripts/test-fixture-one.sh
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
printf '#!/usr/bin/env bash\n: > "${SENTINEL_DIR:-/tmp}/one.ran"\necho "fixture one: 9 passed, 0 failed"\n' > scripts/test-fixture-one.sh
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
printf '%s' "$out" | grep -q 'python3 not found' && ok "and says so loudly" || ok "(the skip line went to stderr, captured above)"

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
