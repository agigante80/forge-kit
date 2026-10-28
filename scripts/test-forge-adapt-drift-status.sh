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
# The drift table prints an unmarked component as `vnone` (v${v:-none}), so that cell is read as none.
say unversioned "the table cell vnone is read as none" --local vnone --catalogue 1
say unversioned "vnone against a v catalogue" --local vnone --catalogue v2

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

echo "== an enabled group shadows a copy that exists (#550) =="
# #550 reverses the old rule. A local copy of a component the live plugin group already provides runs
# TWICE, so it is not compared and refreshed: it is `shadowed`, or `kept` once the user said keep.
say shadowed    "a local copy under an enabled group is shadowed, not behind" --local 2 --catalogue 3 --group-enabled
say shadowed    "and an unmarked local copy is shadowed, not unversioned" --local none --catalogue 3 --group-enabled
say shadowed    "a current local copy is shadowed too" --local 3 --catalogue 3 --group-enabled
say shadowed    "a local copy ahead of the catalogue is shadowed" --local 5 --catalogue 3 --group-enabled
say shadowed    "an unmarked catalogue entry does not hide a shadow" --local 2 --catalogue none --group-enabled
say shadowed    "v-prefixed markers are shadowed as well" --local v2 --catalogue v3 --group-enabled
say shadowed    "the table cell vnone is shadowed as well" --local vnone --catalogue v3 --group-enabled
say kept        "--kept turns a shadow into kept" --local 2 --catalogue 3 --group-enabled --kept
say kept        "--kept with an unmarked local copy" --local none --catalogue 3 --group-enabled --kept
say kept        "--kept overrides an unmarked catalogue too" --local 2 --catalogue none --group-enabled --kept
say kept        "--kept before --group-enabled is the same" --local 2 --catalogue 3 --kept --group-enabled
say behind      "without --group-enabled nothing changes: behind" --local 2 --catalogue 3
say unversioned "without --group-enabled nothing changes: unversioned" --local none --catalogue 3
say current     "--kept without --group-enabled is ignored: current" --local 3 --catalogue 3 --kept
say behind      "--kept without --group-enabled is ignored: behind" --local 2 --catalogue 3 --kept
say registered  "--local absent with the group enabled stays registered" --local absent --catalogue 3 --group-enabled
say missing     "--local absent without the group stays missing" --local absent --catalogue 3

echo "== --kept needs a local copy (#550) =="
cap() { # cap <args...>: sets cout, cerr, crc from one run, so stdout and stderr stay apart
  local e; e=$(mktemp); cout=$(bash "$S" "$@" 2>"$e"); crc=$?; cerr=$(cat "$e"); rm -f "$e"
}
for extra in "" "--group-enabled"; do
  cap --local absent --catalogue 3 --kept $extra
  [ "$crc" = 2 ] && ok "--kept --local absent $extra exits 2" || bad "--kept --local absent $extra exits 2 (got $crc)"
  case "$cerr" in *"--kept needs a local copy"*) ok "and says --kept needs a local copy ($extra)" ;; *) bad "and says --kept needs a local copy ($extra): '$cerr'" ;; esac
  [ -z "$cout" ] && ok "and prints nothing on stdout ($extra)" || bad "and prints nothing on stdout ($extra): '$cout'"
done
cap --local 2 --catalogue 3 --group-enabled --kept
[ -z "$cerr" ] && ok "a valid kept run prints nothing on stderr" || bad "a valid kept run prints nothing on stderr: '$cerr'"
[ "$crc" = 0 ] && ok "and exits 0" || bad "and exits 0 (got $crc)"

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
for w in shadowed kept; do
  out=$(bash "$S" --local 2 --catalogue 3 --group-enabled $([ "$w" = kept ] && echo --kept))
  [ "$out" = "$w" ] && [ "$(printf '%s' "$out" | wc -w | tr -d ' ')" = 1 ] && ok "$w is one bare word" || bad "$w is one bare word: '$out'"
done

echo "== --hook-live: a hook copy under a hook the live plugin runs (#564) =="
[ "$(bash "$S" --local 2 --catalogue 3 --hook-live)" = shadowed ] && ok "--hook-live with a numbered copy reads shadowed" || bad "--hook-live with a numbered copy reads shadowed"
[ "$(bash "$S" --local 2 --catalogue 3)" = behind ] && ok "the same copy reads behind without the flag" || bad "the same copy reads behind without the flag"
[ "$(bash "$S" --local none --catalogue 3 --hook-live)" = shadowed ] && ok "--hook-live with an unmarked copy reads shadowed" || bad "--hook-live with an unmarked copy reads shadowed"
[ "$(bash "$S" --local 5 --catalogue 3 --hook-live)" = shadowed ] && ok "--hook-live with a copy ahead of the catalogue reads shadowed" || bad "--hook-live ahead reads shadowed"
[ "$(bash "$S" --local 2 --catalogue none --hook-live)" = shadowed ] && ok "--hook-live with --catalogue none reads shadowed" || bad "--hook-live with --catalogue none reads shadowed"
[ "$(bash "$S" --local 2 --catalogue 3 --hook-live --kept)" = kept ] && ok "--hook-live --kept reads kept" || bad "--hook-live --kept reads kept"
[ "$(bash "$S" --local v2 --catalogue v3 --hook-live)" = shadowed ] && ok "--hook-live accepts the v form" || bad "--hook-live accepts the v form"
cap --local absent --catalogue 3 --hook-live
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--hook-live --local absent exits 2 with nothing on stdout" || bad "--hook-live --local absent exits 2 (got $crc, '$cout')"
case "$cerr" in *"--hook-live needs a local copy"*) ok "and says --hook-live needs a local copy" ;; *) bad "and says --hook-live needs a local copy: '$cerr'" ;; esac
cap --local 2 --catalogue 3 --hook-live --group-enabled
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--hook-live with --group-enabled exits 2 with nothing on stdout" || bad "--hook-live with --group-enabled exits 2 (got $crc, '$cout')"
case "$cerr" in *"--hook-live and --group-enabled"*) ok "and names the two flags" ;; *) bad "and names the two flags: '$cerr'" ;; esac
cap --local absent --catalogue 3 --hook-live --kept
[ "$crc" = 2 ] && ok "--hook-live --kept --local absent exits 2" || bad "--hook-live --kept --local absent exits 2 (got $crc)"

echo "== --registrable: a copy the planner would register, group not enabled =="
say registrable "a numbered copy reads registrable, not behind" --local 2 --catalogue 3 --registrable
say registrable "a current copy reads registrable" --local 3 --catalogue 3 --registrable
say registrable "a copy ahead of the catalogue reads registrable" --local 5 --catalogue 3 --registrable
say registrable "an unmarked copy reads registrable, not unversioned" --local none --catalogue 3 --registrable
say registrable "the table cell vnone reads registrable" --local vnone --catalogue v3 --registrable
say registrable "an unmarked catalogue does not hide it" --local 2 --catalogue none --registrable
say registrable "the v form is accepted" --local v2 --catalogue v3 --registrable
say kept        "--kept turns it into kept" --local 2 --catalogue 3 --registrable --kept
say kept        "--kept before --registrable is the same" --local none --catalogue 3 --kept --registrable
say behind      "without the flag a copy still reads behind" --local 2 --catalogue 3
say unversioned "without the flag an unmarked copy still reads unversioned" --local none --catalogue 3
cap --local absent --catalogue 3 --registrable
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--registrable --local absent exits 2 with nothing on stdout" || bad "--registrable --local absent exits 2 (got $crc, '$cout')"
case "$cerr" in *"--registrable needs a local copy"*) ok "and says --registrable needs a local copy" ;; *) bad "and says --registrable needs a local copy: '$cerr'" ;; esac
cap --local absent --catalogue 3 --registrable --kept
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--registrable --kept --local absent exits 2" || bad "--registrable --kept --local absent exits 2 (got $crc, '$cout')"
cap --local 2 --catalogue 3 --registrable --group-enabled
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--registrable with --group-enabled exits 2 with nothing on stdout" || bad "--registrable with --group-enabled exits 2 (got $crc, '$cout')"
case "$cerr" in *"--registrable and --group-enabled"*) ok "and names the two flags" ;; *) bad "and names the two flags: '$cerr'" ;; esac
cap --local 2 --catalogue 3 --registrable --hook-live
[ "$crc" = 2 ] && [ -z "$cout" ] && ok "--registrable with --hook-live exits 2 with nothing on stdout" || bad "--registrable with --hook-live exits 2 (got $crc, '$cout')"
case "$cerr" in *"--registrable and --hook-live"*) ok "and names the two flags" ;; *) bad "and names the two flags: '$cerr'" ;; esac
cap --local absent --catalogue 3 --registrable --group-enabled
[ "$crc" = 2 ] && ok "all-conflict with absent still exits 2" || bad "absent + both flags exits 2 (got $crc)"
out=$(bash "$S" --local 2 --catalogue 3 --registrable)
[ "$(printf '%s' "$out" | wc -w | tr -d ' ')" = 1 ] && ok "registrable is one bare word" || bad "registrable is one bare word: '$out'"

echo ""
echo "drift-status tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
