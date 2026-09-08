#!/usr/bin/env bash
# Contract test for .githooks/pre-commit, driven against a throwaway repo with real staged content.
#
# WHY IT EXISTS. The pre-push hook has had a contract test since #98; this one never did, and the
# gap showed. The leak guard was wired in below the hook's `plugins/` pathspec early exit, so a
# commit touching only docs or memory was never scanned, and the commit that introduced the wiring
# went in unscanned itself. Prose is exactly where a pasted home path or a private folder name
# lands, so that was the guard missing its main case.
#
# THE ORDERING IS THE CONTRACT. Everything here asserts that the leak scan runs BEFORE the version
# machinery's early exits, and that "found something" and "could not run" stay distinguishable:
# both block, but a broken allow-file must not be reported as a leak, or the fix sends you the
# wrong way.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
LG=plugins/forge-kit-security/skills/leak-guard/assets

git init --quiet -b main "$REPO"
cd "$REPO"
git config user.email t@example.invalid; git config user.name test
mkdir -p scripts .githooks "$LG" plugins/g/agents plugins/g/.claude-plugin
cp "$ROOT/.githooks/pre-commit" .githooks/
cp "$ROOT/scripts/check-plugin-version-bump.sh" scripts/
cp "$ROOT/$LG/check-public-leaks.sh" "$ROOT/$LG/check-private-leaks.sh" "$LG/"
printf '{ "name": "g", "version": "1.0.0", "description": "fixture" }\n' > plugins/g/.claude-plugin/plugin.json
printf '<!-- a-version: 1 -->\noriginal body\n' > plugins/g/agents/a.md
git add -A >/dev/null; git commit --quiet -m init

run_hook() { bash .githooks/pre-commit 2>&1; }

echo "== a commit that touches nothing under plugins/ =="
# The whole finding: this used to exit 0 at the pathspec check, before the scanner ever ran.
# Composed rather than written literally, so this file needs no `skip` entry in the repo's own
# allow-file. An exemption is a hole in the guard; the fixture only needs the string to exist.
leaky() { printf 'the traceback showed %s/alice/clients/build.log\n' /home; }
leaky > NOTES.md
git add NOTES.md
out="$(run_hook)"; rc=$?
[ "$rc" -ne 0 ] && ok "a leak in a docs-only commit is blocked" \
  || bad "a leak in a docs-only commit is blocked (rc=$rc)"
printf '%s' "$out" | grep -q 'home-path' \
  && ok "and the finding is shown" || bad "and the finding is shown"
printf '%s' "$out" | grep -qi 'carries something from this machine' \
  && ok "and it is reported as a leak" || bad "and it is reported as a leak"

echo "== a clean docs-only commit still passes =="
printf 'nothing to see, install to /home/user/.claude/\n' > NOTES.md
git add NOTES.md
run_hook >/dev/null 2>&1
expect_rc=$?
[ "$expect_rc" -eq 0 ] && ok "a clean docs-only commit is not blocked" \
  || bad "a clean docs-only commit is not blocked (rc=$expect_rc)"

echo "== the scanner scans STAGED content, not the worktree =="
leaky > NOTES.md                                                # written, NOT staged
run_hook >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "an unstaged leak does not block the commit" \
  || bad "an unstaged leak does not block the commit"
git add NOTES.md
run_hook >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "and staging it does block" || bad "and staging it does block"
git checkout -- . 2>/dev/null; printf 'clean\n' > NOTES.md; git add NOTES.md

echo "== could not run is not the same as found something =="
printf 'nonsense line\n' > .leak-guard-allow
git add .leak-guard-allow
out="$(run_hook)"; rc=$?
[ "$rc" -ne 0 ] && ok "a scanner that cannot run still blocks" \
  || bad "a scanner that cannot run still blocks (rc=$rc)"
printf '%s' "$out" | grep -qi 'could not RUN' \
  && ok "and says so" || bad "and says so"
printf '%s' "$out" | grep -qi 'carries something from this machine' \
  && bad "and does NOT call a config error a leak" \
  || ok "and does NOT call a config error a leak"
git rm -q --cached .leak-guard-allow >/dev/null; rm -f .leak-guard-allow

echo "== the version machinery still works underneath it =="
printf '<!-- a-version: 1 -->\nchanged body, marker not bumped\n' > plugins/g/agents/a.md
git add plugins/g/agents/a.md
run_hook >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "a changed component with no marker bump is still blocked" \
  || bad "a changed component with no marker bump is still blocked"
printf '<!-- a-version: 2 -->\nchanged body, marker bumped\n' > plugins/g/agents/a.md
python3 - <<'PY'
import json
p='plugins/g/.claude-plugin/plugin.json'
d=json.load(open(p)); d['version']='1.0.1'; open(p,'w').write(json.dumps(d,indent=2)+"\n")
PY
git add -A
run_hook >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "and a bumped one passes" || bad "and a bumped one passes"

cd "$ROOT"
echo ""
echo "pre-commit hook tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
