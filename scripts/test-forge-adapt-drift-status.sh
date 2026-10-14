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

echo "== the v<N> form the catalogue and the drift table print (#504) =="
say behind      "v1 against v2 compares as numbers" --local v1 --catalogue v2
say current     "v3 against v3 is current" --local v3 --catalogue v3
say current     "a bare local against a v catalogue" --local 4 --catalogue v3
say behind      "v9 against v10 is numeric, not text" --local v9 --catalogue v10
say unversioned "v1 against none is unversioned" --local v1 --catalogue none
say registered  "absent with the group enabled against v3" --local absent --catalogue v3 --group-enabled

echo "== edge markers (#504) =="
say current "zero against zero is current" --local 0 --catalogue 0
say behind  "zero against one is behind" --local 0 --catalogue 1
say behind  "a leading zero is decimal, not octal" --local 08 --catalogue 9
say behind  "the longest accepted marker, nine digits" --local 1 --catalogue 999999999
# A marker over nine digits is a typo, and the numeric comparison overflows on it and falls through to
# `current` with exit 0: a wrong word with a success exit. It is refused, naming the original token.
say "drift-status: '99999999999999999999' is too large to compare" "an oversized catalogue is refused, not called current" \
  --local 3 --catalogue 99999999999999999999
say "drift-status: 'v99999999999999999999' is too large to compare" "an oversized local is refused naming the original token" \
  --local v99999999999999999999 --catalogue 3
[ "$(rcof --local 3 --catalogue 99999999999999999999)" = 2 ] && ok "an oversized marker exits 2" || bad "an oversized marker exits 2"
[ -z "$(bash "$S" --local 3 --catalogue 99999999999999999999 2>/dev/null)" ] && ok "and prints nothing on stdout" || bad "and prints nothing on stdout"

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
[ "$(rcof --local x1 --catalogue 2)" = 2 ] && ok "a non-numeric version refuses" || bad "a non-numeric version refuses"
# #504: the catalogue prints `v<N>`, so one leading v is read as the number. Nothing looser is.
for tok in v vv1 V1 1v v-1 v1.5 .claude/agents/x.md ""; do
  [ "$(rcof --local "$tok" --catalogue 2)" = 2 ] && ok "refuses --local '$tok'" || bad "refuses --local '$tok'"
  [ "$(rcof --local 1 --catalogue "$tok")" = 2 ] && ok "refuses --catalogue '$tok'" || bad "refuses --catalogue '$tok'"
done
say "drift-status: '.claude/agents/x.md' is not a version, 'none' or 'absent'" "a path is refused naming the token" \
  --local .claude/agents/x.md --catalogue 2
say "drift-status: 'vv1' is not a version, 'none' or 'absent'" "a doubled v is refused naming the ORIGINAL token" --local vv1 --catalogue 2
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
