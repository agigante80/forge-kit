#!/usr/bin/env bash
# Contract test for forge-adapt-drift-status.sh (#167).
#
# Five inputs, one word out, so every combination that matters gets a case. The one that motivated
# the script is `absent` with an enabled group: #166 stopped forge-adapt copying a user-scoped
# component, so a correctly installed component now has NO local copy, and reporting that as
# `missing` would invite the user to install it again by copying.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
S="$ROOT/scripts/forge-adapt-drift-status.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
say() { # say <expected> <desc> <args...>
  local want="$1" desc="$2"; shift 2
  local got; got=$(bash "$S" "$@" 2>&1)
  if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc (expected '$want', got '$got')"; fi
}
rcof() { bash "$S" "$@" >/dev/null 2>&1; echo $?; }

echo "== comparing two markers =="
say current "equal versions are current"        --local 3 --catalogue 3
say current "a local ahead of the catalogue is current, not behind" --local 4 --catalogue 3
say behind  "strictly lower is behind"          --local 2 --catalogue 3
say behind  "and version 9 vs 10 compares numerically, not as text" --local 9 --catalogue 10

echo "== absent is not the same as none =="
# The distinction the whole script exists for. `none` is a copy with no marker, which is the entire
# install base predating markers (#64); `absent` is no copy at all.
say unversioned "a present copy with no marker is unversioned, never behind" --local none --catalogue 3
say unversioned "and an unmarked CATALOGUE entry cannot be compared either" --local 2 --catalogue none
say missing     "no copy and nothing providing it is missing" --local absent --catalogue 3
say registered  "no copy but the group provides it is REGISTERED" --local absent --catalogue 3 --group-enabled

echo "== an enabled group does not rewrite a copy that exists =="
say behind      "a local copy is still compared even when the group is enabled" --local 2 --catalogue 3 --group-enabled
say unversioned "and an unmarked local copy is still unversioned" --local none --catalogue 3 --group-enabled

echo "== it refuses rather than guessing =="
[ "$(rcof --local 1)" = 2 ] && ok "a missing --catalogue refuses" || bad "a missing --catalogue refuses"
[ "$(rcof --catalogue 1)" = 2 ] && ok "a missing --local refuses" || bad "a missing --local refuses"
[ "$(rcof --local v1 --catalogue 2)" = 2 ] && ok "a non-numeric version refuses" || bad "a non-numeric version refuses"
[ "$(rcof --local 1 --catalogue absent)" = 2 ] \
  && ok "an absent CATALOGUE refuses, since that means the library is broken" \
  || bad "an absent catalogue refuses"
[ "$(rcof --local 1 --catalogue 2 --nonsense)" = 2 ] && ok "an unknown flag refuses" || bad "an unknown flag refuses"

echo "== the output is exactly one bare word a caller can print =="
out=$(bash "$S" --local absent --catalogue 3 --group-enabled)
[ "$(printf '%s' "$out" | wc -w | tr -d ' ')" = 1 ] && ok "one word, no punctuation" || bad "one word, no punctuation"

echo ""
echo "drift-status tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
