#!/usr/bin/env bash
# Contract test for forge-adapt-marketplace-status.sh (#172).
#
# THE DEFECT IT GUARDS. #166 stopped forge-adapt copying user-scoped components, so the modern
# install is REGISTRATION through the marketplace, and #167 taught `drift` to report a registered
# component as `registered` rather than missing. Neither says anything about whether the marketplace
# CHECKOUT behind that registration is current. Found the hard way: the maintainer's own
# forge-kit-governance was 0.7.11 against a tree at 0.11.1, the checkout 84 commits behind, and
# every tool in this repo reported it healthy.
#
# WHY `stale` AND NOT `behind`. Probed: the checkout is a real clone with an origin remote, and the
# comparison that costs nothing and writes nothing is `git ls-remote` against local HEAD. That says
# the two DIFFER; it cannot say in which direction, because deciding behind-versus-diverged needs
# the remote objects, which needs a fetch, which is a WRITE into a directory another tool owns. The
# word is therefore honest about what was measured. The ticket's own GWT said "behind"; the probe
# said that word could not be earned.
#
# ALWAYS EXIT 0. This is a report, and `drift` writes nothing and must not fail a user's session
# over an unreachable network or a directory that was never there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/forge-adapt-marketplace-status.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; }
word() { printf '%s' "$out" | cut -f1; }

# A bare repo standing in for the remote, and a clone standing in for the marketplace checkout.
REMOTE="$T/remote.git"
git init -q --bare "$REMOTE"
SEED="$T/seed"
git init -q "$SEED"
( cd "$SEED" && git config user.email t@t && git config user.name t \
  && echo one > f && git add f && git commit -q -m one \
  && git branch -M main && git remote add origin "$REMOTE" && git push -q origin main ) >/dev/null 2>&1
# `git init --bare` points HEAD at the init default (often master), so a clone of a repo that only
# has `main` checks out nothing, and every later assertion then measures a broken fixture rather
# than the script. Point it at what was actually pushed, and fail loudly if the clone is empty.
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
CO="$T/marketplaces/forge-kit"
mkdir -p "$T/marketplaces"
git clone -q "$REMOTE" "$CO" >/dev/null 2>&1
git -C "$CO" rev-parse HEAD >/dev/null 2>&1 || { echo "fixture is broken: the clone has no HEAD"; exit 1; }

echo "== a checkout matching its remote is current =="
run forge-kit --dir "$T/marketplaces"
expect "it exits 0" 0 "$rc"
expect "and reports current" "current" "$(word)"

echo "== a checkout the remote has moved past is stale, not current =="
( cd "$SEED" && echo two > f && git commit -q -am two && git push -q origin main ) >/dev/null 2>&1
run forge-kit --dir "$T/marketplaces"
expect "it still exits 0, because a report never fails a session" 0 "$rc"
expect "and reports stale" "stale" "$(word)"
contains "marketplace update" "$out" "and names the command that fixes it"
contains "forge-kit" "$out" "and names the marketplace, not an absolute path"
# The message is printed to a human and may be pasted. A home path in it is the shape
# check-public-leaks.sh exists to catch, so the detail must not carry one.
if printf '%s' "$out" | grep -q "$HOME"; then bad "the message leaks a home path"; else ok "and no home path appears in the message"; fi

echo "== the shapes that are not a failure =="
run forge-kit --dir "$T/nowhere"
expect "an absent marketplace dir exits 0" 0 "$rc"
expect "and is not-applicable, never stale" "not-applicable" "$(word)"
contains "no marketplace" "$out" "and says why (this is the bare-clone install path)"

mkdir -p "$T/marketplaces/plainfile"
run plainfile --dir "$T/marketplaces"
expect "a directory that is not a git checkout exits 0" 0 "$rc"
expect "and is unknown, never current" "unknown" "$(word)"

echo "== an unreachable remote is unknown, never current =="
# The failure that matters: a network hiccup must not read as agreement. Same shape as #64.
git -C "$CO" remote set-url origin "$T/does-not-exist.git"
run forge-kit --dir "$T/marketplaces"
expect "it exits 0" 0 "$rc"
expect "and reports unknown" "unknown" "$(word)"

echo "== it never writes into a directory it does not own =="
git -C "$CO" remote set-url origin "$REMOTE"
head_before=$(git -C "$CO" rev-parse HEAD)
refs_before=$(git -C "$CO" for-each-ref --format='%(refname) %(objectname)' | sort)
run forge-kit --dir "$T/marketplaces"
expect "the run reaches the remote, so the no-write claim is about a real run" "stale" "$(word)"
expect "HEAD is unchanged after a run" "$head_before" "$(git -C "$CO" rev-parse HEAD)"
expect "and every ref is byte-identical, so nothing was fetched" \
  "$refs_before" "$(git -C "$CO" for-each-ref --format='%(refname) %(objectname)' | sort)"
if [ -e "$CO/.git/FETCH_HEAD" ]; then
  bad "the script fetched into a checkout it does not own"
else
  ok "and no FETCH_HEAD was written"
fi

echo "== the output is one tab-separated line a caller can act on =="
expect "exactly one line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect "two tab-separated fields" 2 "$(printf '%s' "$out" | awk -F'\t' '{print NF}')"

echo "== it refuses rather than guessing =="
run
expect "no marketplace name refuses" 2 "$rc"

echo ""
echo "marketplace-status tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
