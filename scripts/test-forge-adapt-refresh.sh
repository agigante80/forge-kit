#!/usr/bin/env bash
# Contract test for forge-adapt-refresh.sh (#501, building on #502).
#
# THE FAILURES THIS PREVENTS. (1) Two forge-adapt runs in two projects refresh the ONE shared library
# at once; git serialises them through .git/shallow.lock and .git/index.lock, the loser failed, and
# S2 printed "could not refresh ... it may be behind" although the winner had just made HEAD current.
# (2) The #502 refresh (no `reset --hard`, which overnight-guard denies) must keep working on a
# depth-1 clone from a detached HEAD and on a non-main default branch.
# Every fixture is a throwaway upstream plus a depth-1 `file://` clone (a plain path clones in full
# and is not shallow). The wait between the two attempts is injected, so no test sleeps.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/forge-adapt-refresh.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want '$3', got '$2')"; }

gx() { GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"; }
# mk <branch>: sets UP (upstream) and LB (its depth-1 library clone), HEAD one commit behind nothing.
mk() {
  W=$(mktemp -d "$T/f.XXXXXX"); UP="$W/up"; LB="$W/lib"
  gx init -q -b "$1" "$UP"; echo 1 > "$UP/f.txt"; echo a > "$UP/g.txt"
  gx -C "$UP" add .; gx -C "$UP" commit -qm c1; echo 2 > "$UP/f.txt"; gx -C "$UP" commit -qam c2
  gx clone -q --depth 1 "file://$UP" "$LB"
}
up() { printf '%s\n' "$2" > "$UP/$1"; gx -C "$UP" add -A; gx -C "$UP" commit -qm "more $1"; }
head_of() { git -C "$1" rev-parse HEAD; }
# run [VAR=value ...]: the helper on $LB with the wait injected as `true`; sets out, rc.
run() { out=$(env FORGE_ADAPT_REFRESH_WAIT="${WAITCMD:-true}" "$@" bash "$S" "$LB" 2>&1); rc=$?; }
WAITCMD=true

echo "== a plain refresh =="
mk main; eq "the fixture library is shallow" "$(git -C "$LB" rev-parse --is-shallow-repository)" true
up f.txt 3; run
eq "shallow refresh exits 0" "$rc" 0; eq "shallow refresh prints nothing" "$out" ""
eq "shallow HEAD equals the upstream" "$(head_of "$LB")" "$(head_of "$UP")"
mk trunk; git -C "$LB" checkout -q --detach HEAD; up f.txt 3; run
eq "detached HEAD on a non-main default branch: exit 0" "$rc" 0
eq "detached non-main HEAD equals the upstream" "$(head_of "$LB")" "$(head_of "$UP")"
eq "the library is left on the default branch" "$(git -C "$LB" symbolic-ref --short HEAD)" trunk

echo "== local changes in the library =="
mk main; echo local > "$LB/f.txt"; old=$(head_of "$LB"); up f.txt 3; run
eq "a conflicting edit: exit 1" "$rc" 1; eq "a conflicting edit survives" "$(cat "$LB/f.txt")" local
eq "a conflicting edit leaves HEAD unchanged" "$(head_of "$LB")" "$old"
mk main; echo mine >> "$LB/g.txt"; up f.txt 3; run
eq "a non-conflicting edit: exit 0" "$rc" 0; eq "a non-conflicting edit is carried" "$(tail -1 "$LB/g.txt")" mine
eq "a non-conflicting edit still moves HEAD" "$(head_of "$LB")" "$(head_of "$UP")"
mk main; echo mine > "$LB/added.txt"; old=$(head_of "$LB"); up added.txt theirs; run
eq "an untracked file the commit adds: exit 1" "$rc" 1; eq "the colliding file survives" "$(cat "$LB/added.txt")" mine
eq "the colliding file leaves HEAD unchanged" "$(head_of "$LB")" "$old"

echo "== a lost race =="
# The library is already current, and a lock makes every attempt fail: the comparison with the
# remote decides, and says current.
mk main; up f.txt 3; run; : > "$LB/.git/shallow.lock"; run
eq "shallow.lock held, HEAD current: exit 0" "$rc" 0; eq "shallow.lock held, HEAD current: silent" "$out" ""
rm -f "$LB/.git/shallow.lock"
mk main; up f.txt 3; run; : > "$LB/.git/index.lock"; run
eq "index.lock held, HEAD current: exit 0" "$rc" 0; eq "index.lock held, HEAD current: silent" "$out" ""
eq "index.lock held, HEAD current: HEAD equals ls-remote" "$(head_of "$LB")" "$(git -C "$LB" ls-remote origin HEAD | cut -f1)"
rm -f "$LB/.git/index.lock"
# Behind with a lock held: it fails, HEAD unchanged.
mk main; : > "$LB/.git/shallow.lock"; old=$(head_of "$LB"); up f.txt 3; run
eq "shallow.lock held, HEAD behind: exit 1" "$rc" 1; eq "shallow.lock held, HEAD behind: HEAD unchanged" "$(head_of "$LB")" "$old"
rm -f "$LB/.git/shallow.lock"

echo "== the retry =="
# The wait removes the lock, standing in for the winner finishing between the two attempts.
mk main; : > "$LB/.git/shallow.lock"; up f.txt 3; WAITCMD="rm -f '$LB/.git/shallow.lock'"; run; WAITCMD=true
eq "a lock released during the wait: exit 0" "$rc" 0
eq "a lock released during the wait: HEAD equals the upstream" "$(head_of "$LB")" "$(head_of "$UP")"
eq "a lock released during the wait: silent" "$out" ""
# A held lock the wait leaves alone proves the wait command really runs: it leaves a witness file.
mk main; up f.txt 3; WAITCMD="echo waited > '$W/witness'"; run; WAITCMD=true
eq "the wait runs only after a failed first attempt (success never waits)" "$([ -e "$W/witness" ] && echo ran || echo skipped)" skipped
mk main; : > "$LB/.git/shallow.lock"; up f.txt 3; WAITCMD="echo waited > '$W/witness'"; run; WAITCMD=true
eq "the wait runs once between two failed attempts" "$(cat "$W/witness" 2>/dev/null)" waited

echo "== the remote cannot be read =="
mk main; gx -C "$LB" remote set-url origin "$T/does-not-exist"; old=$(head_of "$LB"); run
eq "an unreachable remote: exit 1" "$rc" 1; eq "an unreachable remote leaves HEAD unchanged" "$(head_of "$LB")" "$old"
# A remote that answers ls-remote with nothing must not count as "equal to an empty HEAD".
mk main; old=$(head_of "$LB")
STUB="$W/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\ncase "$*" in *ls-remote*) exit 0 ;; *rev-parse*) echo; exit 0 ;; *) exit 1 ;; esac\n' > "$STUB/git"; chmod +x "$STUB/git"
out=$(PATH="$STUB:$PATH" FORGE_ADAPT_REFRESH_WAIT=true bash "$S" "$LB" 2>&1); rc=$?
eq "an empty ls-remote and an empty HEAD are not equal: exit 1" "$rc" 1

echo "== usage and the pin =="
out=$(bash "$S" 2>&1); eq "no argument: exit 2" "$?" 2
case "$out" in *"usage: forge-adapt-refresh.sh <library dir>"*) ok "no argument: the usage line" ;; *) bad "no argument: '$out'" ;; esac
out=$(bash "$S" "" 2>&1); eq "an empty argument: exit 2" "$?" 2
# The #502 fix must not be undone inside the helper, where overnight-guard cannot see it.
code=$(grep -v '^[[:space:]]*#' "$S")
case "$code" in *"reset --hard"*) bad "the helper runs reset --hard" ;; *) ok "the helper has no reset --hard" ;; esac
case "$code" in *"merge --ff-only"*) bad "the helper runs merge --ff-only" ;; *) ok "the helper has no merge --ff-only" ;; esac
[ -x "$S" ] && ok "the helper is executable" || bad "the helper is not executable"

echo ""
echo "forge-adapt-refresh tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
