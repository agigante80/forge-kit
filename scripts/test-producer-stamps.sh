#!/usr/bin/env bash
# Contract test for check-producer-stamps.sh (issue #84).
#
# THE DEFECT IT GUARDS. A component that EMITS ticket bodies used to hardcode the template-version
# it stamped. `dep-auditor` and `/ci-health` both did, still writing v4 after the v5 bump, and
# check-template-lockstep.sh could not see it because its scope is the template dir plus the
# canonical doc. Every machine-filed ticket was then born stale and triggered a synthesis
# round-trip against a ticket the kit itself had just created. PR #83 fixed the two instances by
# making both producers read the current version; nothing mechanical stopped the next one.
#
# WHY ITS OWN SCRIPT. The ticket suggested extending the lockstep guard or validate-plugins.sh.
# validate-plugins.sh has no contract test to extend, and this repo's record is that an untested
# guard is the defect. Widening lockstep breaks its hermetic argument contract, since the tests
# pass it fixture paths precisely so it never reads the real repo. One guard, one concern, one test.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-producer-stamps.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# --- the legitimate forms must all pass ---------------------------------------------------------
mk "$T/clean/g/agents/a.md" <<'M'
Emit the CURRENT `<!-- template-version: N -->` marker, never a hardcoded number.
Replace `template-version: N` with `template-version: $CURRENT_TPL_VER` (read at runtime).
A generic placeholder like `<!-- template-version: <current> -->` is fine too.
M
bash "$SCRIPT" "$T/clean" >/dev/null 2>&1
[ $? -eq 0 ] && ok "the N form, a shell variable and a placeholder all pass" \
  || bad "legitimate forms pass"

# --- a hardcoded digit stamp must fail, and name the file ---------------------------------------
mk "$T/dirty/g/agents/dep-auditor.md" <<'M'
Create the issue with this body:
<!-- template-version: 4 -->
## Problem
M
out=$(bash "$SCRIPT" "$T/dirty" 2>&1); rc=$?
# EXACTLY 1. The guard documents 0 clean / 1 violation / 2 could-not-scan, and this suite is the
# only thing certifying that contract, so "non-zero" would let a violation report as a scan error.
[ "$rc" -eq 1 ] && ok "a hardcoded digit stamp exits 1, the violation status" \
  || bad "digit stamp exits 1 (got $rc)"
case "$out" in *dep-auditor.md*) ok "and it names the offending file" ;;
               *) bad "names the file (got: $out)" ;; esac
case "$out" in *"template-version: 4"*) ok "and quotes the stamp it found" ;;
               *) bad "quotes the stamp (got: $out)" ;; esac

# --- the bare (non-comment) form is the same defect ----------------------------------------------
mk "$T/bare/g/commands/c.md" <<'M'
body: |
  template-version: 6
M
bash "$SCRIPT" "$T/bare" >/dev/null 2>&1
[ $? -eq 1 ] && ok "the bare form without an HTML comment is caught too" || bad "bare form caught"

# --- the contract is "anywhere under the tree", not "in markdown" -------------------------------
# Producers are not all prose: hooks are .py, shell assets are .sh, and the release lanes are .yml.
# With only .md fixtures, restricting the guard to markdown left the suite green.
for ext in py sh yml; do
  mk "$T/ext-$ext/g/hooks/producer.$ext" <<M
# emits a ticket body
# <!-- template-version: 4 -->
M
  bash "$SCRIPT" "$T/ext-$ext" >/dev/null 2>&1
  [ $? -eq 1 ] && ok "a hardcoded stamp in a .$ext file is caught too" \
    || bad "non-markdown producers are scanned (.$ext)"
done

# --- a component version marker is NOT a template stamp -----------------------------------------
# Every component carries `<!-- <name>-version: N -->` with a real digit. Matching those would make
# the guard fire on every file in the tree, so it must anchor on the word template-version.
mk "$T/markers/g/agents/a.md" <<'M'
<!-- ticket-gate-version: 33 -->
<!-- forge-adapt-version: 56 -->
<!-- doc-rules-version: 12 -->
M
bash "$SCRIPT" "$T/markers" >/dev/null 2>&1
[ $? -eq 0 ] && ok "component version markers are not mistaken for template stamps" \
  || bad "component markers pass"

# --- multiple offenders are all reported, not just the first ------------------------------------
mk "$T/many/g/agents/a.md" <<'M'
<!-- template-version: 4 -->
M
mk "$T/many/g/commands/b.md" <<'M'
<!-- template-version: 5 -->
M
out=$(bash "$SCRIPT" "$T/many" 2>&1)
# Count the HIT lines only. Counting every "template-version:" in the output made this vacuous:
# the guard's own advice trailer names the marker, so one offender already satisfied -ge 2.
n=$(printf '%s\n' "$out" | grep -c '^  x ')
[ "$n" -eq 2 ] && ok "every offender is reported, not only the first" || bad "reports all offenders (got $n)"

# --- fail closed on a missing root, never pass vacuously ----------------------------------------
bash "$SCRIPT" "$T/does-not-exist" >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing root fails closed with exit 2" || bad "missing root fails closed"

# --- an EMPTY tree is a pass, not a failure: a project may ship no producers --------------------
mkdir -p "$T/empty"
bash "$SCRIPT" "$T/empty" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a tree with no files passes rather than reading as broken" || bad "empty tree passes"

# --- an UNREADABLE subtree must fail closed, not read as "no matches" ---------------------------
# grep exits 2 on a read error, and swallowing that made an unreadable tree containing an
# offending producer go green: the same vacuous pass the missing-root case exists to prevent.
if [ "$(id -u)" -eq 0 ]; then
  echo "  skip: unreadable-subtree case (running as root, which can read anything)"
else
  mk "$T/unreadable/g/agents/a.md" <<'M'
clean file
M
  mkdir -p "$T/unreadable/g/secret"; printf '<!-- template-version: 4 -->\n' > "$T/unreadable/g/secret/x.md"
  chmod 000 "$T/unreadable/g/secret"
  bash "$SCRIPT" "$T/unreadable" >/dev/null 2>&1; rc=$?
  chmod 755 "$T/unreadable/g/secret"
  [ "$rc" -eq 2 ] && ok "an unreadable subtree fails closed rather than passing clean" \
    || bad "unreadable subtree fails closed (rc=$rc)"
fi

# --- round 2: a hostile TMPDIR must not turn a violation into a clean pass ----------------------
# The first version wrote grep's stderr to a mktemp file. With TMPDIR unusable, mktemp failed, the
# redirect failed, grep never ran, and its status was read as "clean tree": the guard printed
# success with a violation sitting in the tree. There is no temp file any more, and this pins it.
out=$(TMPDIR=/nonexistent-on-purpose bash "$SCRIPT" "$T/dirty" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a violation is still caught when TMPDIR is unusable" \
  || bad "hostile TMPDIR does not mask a violation (rc=$rc)"

# --- round 2: a scan error must not HIDE a violation already found ------------------------------
# grep exits 2 on a read error even when it matched elsewhere, and discarding the hits meant an
# unreadable subtree reported "could not scan" while saying nothing about the stamp it had found.
if [ "$(id -u)" -eq 0 ]; then
  echo "  skip: partial-scan case (running as root, which can read anything)"
else
  mk "$T/partial/g/agents/a.md" <<'M'
<!-- template-version: 7 -->
M
  mkdir -p "$T/partial/g/locked"; printf 'x\n' > "$T/partial/g/locked/y.md"
  chmod 000 "$T/partial/g/locked"
  out=$(bash "$SCRIPT" "$T/partial" 2>&1); rc=$?
  chmod 755 "$T/partial/g/locked"
  [ "$rc" -ne 0 ] && ok "a partial scan still fails" || bad "partial scan fails (rc=$rc)"
  case "$out" in *"template-version: 7"*) ok "and it still reports the violation it did find" ;;
                 *) bad "a scan error must not hide a found violation (got: $out)" ;; esac
  # The NOTE is the only signal that the hit list may be incomplete, so it needs its own assertion
  # or deleting it would leave the suite green.
  case "$out" in *"there may be more"*) ok "and warns that the hit list may be incomplete" ;;
                 *) bad "partial scan warns the list may be incomplete (got: $out)" ;; esac
fi

# --- the real repo must pass, or the guard is not actually adopted -------------------------------
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 0 ] && ok "this repo's own plugins/ tree is free of hardcoded stamps" \
  || bad "repo plugins/ tree is clean"

# --- inside a git checkout, only TRACKED files are in scope (#140) ------------------------------
# The failure that bites is local: a merge leftover like dep-auditor.md.orig, still carrying a
# pre-#83 stamp, hard-fails on a developer's machine over a file CI will never see and git will
# never carry. The message names a real path, so there is no signal that it is irrelevant.
#
# The sibling range guards already read committed state (`git show`) precisely so the local answer
# matches CI's. This brings the scan into line with them.
R="$T/repo"
mkdir -p "$R/plugins/g/agents"
( cd "$R" && git init -q . && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1
mk "$R/plugins/g/agents/ok.md" <<'M'
Resolve the version at runtime; never write `template-version: N` as a literal.
M
( cd "$R" && git add -A && git commit -q -m base ) >/dev/null 2>&1

# The untracked leftover.
mk "$R/plugins/g/agents/a.md.orig" <<'M'
<!-- template-version: 4 -->
M
bash "$SCRIPT" "$R/plugins" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "an UNTRACKED file carrying a stamp does not fail the guard" \
                || bad "an untracked file carrying a stamp still fails the guard"

# The same content, tracked, must still fail: this is about WHICH files are in scope, not about
# excusing any of them. The no-allowlist rule is untouched.
( cd "$R" && git add -f plugins/g/agents/a.md.orig && git commit -q -m tracked ) >/dev/null 2>&1
out=$(bash "$SCRIPT" "$R/plugins" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "and the identical content TRACKED still fails" \
                || bad "a tracked stamp stopped failing (rc=$rc)"
printf '%s' "$out" | grep -q 'a.md.orig' \
  && ok "and the report still names the file" || bad "and the report still names the file"

# EXACTLY ONE tracked file. grep omits the filename prefix when handed a single file operand, so
# without -H the report names a line number and no path. Every other case here has several files
# and grep adds the prefix anyway, which is why dropping -H survived mutation until this case.
S="$T/single"
mkdir -p "$S/plugins/g/agents"
( cd "$S" && git init -q . && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1
mk "$S/plugins/g/agents/only.md" <<'M'
<!-- template-version: 4 -->
M
( cd "$S" && git add -A && git commit -q -m one ) >/dev/null 2>&1
out=$(bash "$SCRIPT" "$S/plugins" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a lone tracked file carrying a stamp fails" || bad "a lone tracked file fails (rc=$rc)"
printf '%s' "$out" | grep -q 'only\.md' \
  && ok "and the report names it even though grep had one file" \
  || bad "the report lost the filename with a single file operand"

# A tracked file deleted from the worktree is still listed by git ls-files; grepping it would be a
# read error reported as a scan failure.
( cd "$R" && rm plugins/g/agents/a.md.orig ) >/dev/null 2>&1
bash "$SCRIPT" "$R/plugins" >/dev/null 2>&1
[ "$?" -ne 2 ] && ok "a tracked file missing from the worktree is not a scan error" \
               || bad "a tracked file missing from the worktree reported a scan error"
( cd "$R" && git checkout -- . ) >/dev/null 2>&1

echo ""
echo "producer-stamp tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
