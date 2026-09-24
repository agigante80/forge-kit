#!/usr/bin/env bash
# Contract test for gate-status.sh (#284).
#
# Driven through the REAL forge-lib.sh with only its transport replaced: FORGE_LIB points at a
# wrapper that sources the real library and then redefines forge_api over a file-backed issue, so
# the region primitives the script writes through (#248's disjointness and re-read checks, v27's
# `top`) are the shipped ones and not a stub's idea of them. No network and no token.
#
# STUB_RACE_AT lists the GET numbers (1-based, per run) on which the stored body changes BEFORE it
# is served, which is how a concurrent edit reaches the re-read and returns 102. STUB_RACE_KIND
# says whose edit it is: `author` (the default) adds a line outside every region, `region` edits
# the text inside `gate-context`, which is another writer's and changes no author section.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
REAL="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/gate-status.sh"
FLIB="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1')"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

[ -f "$REAL" ] || { echo "missing script: $REAL"; exit 1; }
[ -f "$FLIB" ] || { echo "missing library: $FLIB"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S="$T/store"; mkdir -p "$S"
cp "$REAL" "$T/gate-status.sh"

cat > "$T/wrap.sh" <<LIB
. "$FLIB"
LIB
cat >> "$T/wrap.sh" <<'LIB'
export FORGE_HOST=forgejo FORGE_REPO=o/r
forge_api() {
  local n
  case "$1" in
    GET)
      [ -f "$S/fail-get" ] && return 7
      n=$(( $(cat "$S/gets" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/gets"
      for r in ${STUB_RACE_AT:-}; do
        [ "$r" = "$n" ] || continue
        if [ "${STUB_RACE_KIND:-author}" = region ]; then sed -i "s/^context v.*/& r$n/" "$S/body"
        else printf '\nracing edit %s\n' "$n" >> "$S/body"; fi
      done
      jq -Rs '{body:.}' < "$S/body" ;;
    PATCH)
      echo x >> "$S/patches"
      printf '%s' "$3" | jq -j '.body' > "$S/body"; echo '{}' ;;
  esac
}
forge_issue_comments() { cat "$S/comments.json"; }
LIB
export S FORGE_LIB="$T/wrap.sh"

GS() { rm -f "$S/gets"; bash "$T/gate-status.sh" "$@"; }
setbody() { printf '%s' "$1" > "$S/body"; rm -f "$S/patches" "$S/fail-get"; }
patches() { if [ -f "$S/patches" ]; then wc -l < "$S/patches" | tr -d ' '; else echo 0; fi; }

printf '%s' '[{"body":"## Ticket Readiness Review - #7\nold","html_url":"https://x/c/1"},
{"body":"> ## Ticket Readiness Review - #7\nquoted","html_url":"https://x/c/2"},
{"body":"## Ticket Readiness Review - #7\r\nnew","html_url":"https://x/c/3"},
{"body":"## Ticket Readiness Review - #8\nsibling","html_url":"https://x/c/4"}]' > "$S/comments.json"

AUTHOR='<!-- template-version: 6 -->

## Summary

The thing.

## Acceptance criteria

1. It works.
'
VERDICT='<!-- gate-verdict:start -->
### Gate verdict (round 2)
**Verdict:** NEEDS-WORK
- significant: fix the scenarios
<!-- gate-verdict:end -->'
REQ='<!-- gate-required-changes:start -->
### Required changes (round 2)
- [ ] fix the scenarios
<!-- gate-required-changes:end -->'
CTX='<!-- gate-context:start -->
context v1
<!-- gate-context:end -->'
BASE="$AUTHOR
$CTX

$REQ

$VERDICT
"

echo "== argument handling =="
setbody "$BASE"
out=$(GS 2>/dev/null); expect "no issue number exits 2" 2 "$?"; expect "  and prints nothing" "" "$out"
out=$(GS 7 --bogus 2>/dev/null); expect "an unknown option exits 2" 2 "$?"
out=$(GS 7 --stamp extra 2>/dev/null); expect "a third argument exits 2" 2 "$?"
out=$(FORGE_LIB="$T/none.sh" bash "$T/gate-status.sh" 7 2>/dev/null); expect "an unresolvable forge-lib exits 2" 2 "$?"

echo "== the fingerprint ignores every region and blank-line noise =="
setbody "$BASE"; f0=$(GS 7 --fingerprint)
case "$f0" in sha256:[0-9a-f]*) [ ${#f0} = 23 ] && ok "prints sha256:<16 hex>" || bad "wrong length: $f0" ;; *) bad "not a fingerprint: $f0" ;; esac
setbody "${BASE/context v1/context v2 changed}"
expect "an edit inside gate-context leaves it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "$BASE
<!-- brief-summary:start -->
a decision brief
<!-- brief-summary:end -->"
expect "a new brief-* region leaves it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "$(printf '%s' "$BASE" | sed 's/$/\r/')"
expect "CRLF line endings leave it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "${BASE/The thing./The thing.   }"
expect "trailing blanks leave it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "${BASE/## Summary/## Summary

}"
expect "an extra blank line leaves it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "$VERDICT

$AUTHOR
$REQ
$CTX"
expect "moving the regions to the top leaves it unchanged" "$f0" "$(GS 7 --fingerprint)"
setbody "${BASE/The thing./The other thing.}"
f1=$(GS 7 --fingerprint); [ "$f1" != "$f0" ] && ok "one word outside a region changes it" || bad "author edit did not change it"
touch "$S/fail-get"; out=$(GS 7 --fingerprint 2>/dev/null); expect "an unreadable body exits 2" 2 "$?"; expect "  with empty stdout" "" "$out"

setbody "$AUTHOR
<!-- gate-context:start -->
never closed"; out=$(GS 7 --fingerprint 2>/dev/null); expect "an unpaired start marker exits 2" 2 "$?"; expect "  with empty stdout" "" "$out"
setbody "$AUTHOR
<!-- gate-context:end -->"; out=$(GS 7 2>/dev/null); expect "an end with no start: the state exits 2" 2 "$?"

echo "== states =="
setbody "$AUTHOR"; expect "no verdict reads ungated" "ungated" "$(GS 7)"
setbody "$BASE"; expect "a verdict with no Judged line reads unrecorded" "unrecorded round 2" "$(GS 7)"
touch "$S/fail-get"; out=$(GS 7 2>/dev/null); expect "an unreadable body exits 2" 2 "$?"; expect "  with empty stdout" "" "$out"

echo "== --stamp moves the blocks to the top and records the fingerprint =="
setbody "$BASE"; GS 7 --stamp; expect "stamp exits 0" 0 "$?"
body=$(cat "$S/body")
expect "the template marker stays first" '<!-- template-version: 6 -->' "$(printf '%s\n' "$body" | sed -n 1p)"
expect "the verdict region is the first region" '<!-- gate-verdict:start -->' "$(printf '%s\n' "$body" | sed -n 3p)"
first_req=$(printf '%s\n' "$body" | grep -n 'gate-required-changes:start' | cut -d: -f1)
first_sum=$(printf '%s\n' "$body" | grep -n '^## Summary' | cut -d: -f1)
[ "$first_req" -lt "$first_sum" ] && ok "required changes sit above the author sections" || bad "required changes not moved"
expect "each region appears once" 1 "$(printf '%s\n' "$body" | grep -c 'gate-verdict:start')"
fp=$(GS 7 --fingerprint)
contains "Judged body: $fp. Full review: https://x/c/3." "$body" "the Judged line carries the fingerprint and the LATEST review's url"
lacks "https://x/c/4" "$body" "a sibling ticket's review is never the pointer"
expect "the stamped ticket reads current" "current round 2 NEEDS-WORK" "$(GS 7)"
expect "the author sections are byte-identical after the moves" "$f0" "$fp"
before=$(cat "$S/body"); GS 7 --stamp
expect "re-stamping keeps a single Judged line" 1 "$(grep -c '^Judged body:' "$S/body")"
expect "re-stamping an unchanged ticket is a fixed point" "$before" "$(cat "$S/body")"

echo "== --stamp drops a pre-v60 bare pointer line (#285) =="
OLDV="${VERDICT/- significant: fix the scenarios/- significant: fix the scenarios
- advisory: see the Full review: section
Full review: the latest `## Ticket Readiness Review` comment on this issue.}"
setbody "$AUTHOR
$CTX

$REQ

$OLDV
"; GS 7 --stamp; expect "stamping an inherited pointer exits 0" 0 "$?"
expect "one line starts with Full review: none, the bare pointer is gone" 0 "$(grep -c '^Full review:' "$S/body")"
expect "two mentions left: the Judged line and the mid-line item" 2 "$(grep -c 'Full review:' "$S/body")"
contains "- advisory: see the Full review: section" "$(cat "$S/body")" "an item mentioning Full review: mid-line is kept"
GS 7 --stamp
expect "a double stamp still leaves one Judged line" 1 "$(grep -c '^Judged body:' "$S/body")"
expect "  and no bare pointer" 0 "$(grep -c '^Full review:' "$S/body")"

ALT='<!-- gate-alternatives:start -->
### Architecture alternatives
1. another way
<!-- gate-alternatives:end -->'
setbody "$BASE
$ALT
"; GS 7 --stamp
order=$(grep -o 'gate-[a-z-]*:start' "$S/body" | tr '\n' ' ')
expect "all three move up, verdict first" "gate-verdict:start gate-required-changes:start gate-alternatives:start gate-context:start " "$order"
[ "$(grep -n 'gate-alternatives:start' "$S/body" | cut -d: -f1)" -lt "$(grep -n '^## Summary' "$S/body" | cut -d: -f1)" ] \
  && ok "  and the alternatives sit above the author sections" || bad "alternatives left below"

echo "== --stamp retries only a race that left the author sections alone =="
# GETs in a stamp: 1 body, 2 verdict, 3 alternatives, 4 required, then each write reads twice
# (5-6 is the first); a retry first re-reads to hash (7), then writes again (8-9).
setbody "$BASE"; STUB_RACE_KIND=region STUB_RACE_AT=6 GS 7 --stamp 2>/dev/null
expect "a region-only race is retried and succeeds" 0 "$?"
expect "  and the result reads current" "current round 2 NEEDS-WORK" "$(GS 7)"
setbody "$BASE"; err=$(STUB_RACE_AT=6 GS 7 --stamp 2>&1 >/dev/null); expect "an author edit during the stamp exits 1" 1 "$?"
contains "an author section changed during the stamp" "$err" "  and says why"
expect "  and sends nothing after the race" 0 "$(patches)"
expect "  and the verdict stays unrecorded, never current" "unrecorded round 2" "$(GS 7)"
setbody "$BASE"; STUB_RACE_KIND=region STUB_RACE_AT="6 9" GS 7 --stamp 2>/dev/null; expect "a second race exits 1" 1 "$?"
expect "  and the verdict stays unrecorded" "unrecorded round 2" "$(GS 7)"
setbody "$AUTHOR"; GS 7 --stamp 2>/dev/null; expect "no verdict to stamp exits 1" 1 "$?"

echo "== --unstamp =="
setbody "$BASE"; GS 7 --stamp; GS 7 --unstamp; expect "unstamp exits 0" 0 "$?"
expect "an unstamped verdict reads unrecorded" "unrecorded round 2" "$(GS 7)"
rm -f "$S/patches"; GS 7 --unstamp; expect "unstamping twice writes nothing" 0 "$(patches)"

echo "== --mark-stale =="
setbody "$BASE"; GS 7 --stamp
cur=$(cat "$S/body"); printf '%s' "${cur/context v1/context v9}" > "$S/body"; rm -f "$S/patches"
GS 7 --mark-stale; expect "a region-only edit: mark-stale exits 0" 0 "$?"
expect "  and writes nothing" 0 "$(patches)"
expect "  and the verdict is still current" "current round 2 NEEDS-WORK" "$(GS 7)"
cur=$(cat "$S/body"); printf '%s' "${cur/1. It works./1. It works, now with a fix.}" > "$S/body"
expect "an author edit reads stale" "stale round 2 NEEDS-WORK" "$(GS 7)"
GS 7 --mark-stale; expect "mark-stale exits 0" 0 "$?"
body=$(cat "$S/body")
contains '### Gate verdict (round 2): STALE' "$body" "the verdict heading is marked"
contains '**Stale:** the sections outside this block changed after this verdict; re-run /gate-ticket 7 before acting on it.' "$body" "the verdict carries the Stale line"
contains '### Required changes (round 2): STALE' "$body" "the required-changes heading is marked"
contains '1. It works, now with a fix.' "$body" "the author edit is untouched"
rm -f "$S/patches"; GS 7 --mark-stale; expect "a second mark-stale writes nothing" 0 "$(patches)"
setbody "$BASE"; GS 7 --stamp; GS 7 --unstamp
cur=$(cat "$S/body"); printf '%s' "${cur/The thing./Changed.}" > "$S/body"; before=$(cat "$S/body"); rm -f "$S/patches"
GS 7 --mark-stale; expect "an unrecorded verdict is never marked" "$before" "$(cat "$S/body")"
setbody "$AUTHOR"; GS 7 --mark-stale; expect "an ungated ticket: exit 0" 0 "$?"; expect "  and nothing written" 0 "$(patches)"
# A race on mark-stale's write (GETs: 1 body, 2 verdict, 3-4 the write) is a notice, never a retry.
setbody "$BASE"; GS 7 --stamp; cur=$(cat "$S/body"); printf '%s' "${cur/The thing./Changed.}" > "$S/body"; rm -f "$S/patches"
err=$(STUB_RACE_AT=4 GS 7 --mark-stale 2>&1 >/dev/null); expect "a race on mark-stale exits 0" 0 "$?"
contains "not marked (rc 102)" "$err" "  and says so on stderr"
lacks "STALE" "$(sed -n '/gate-verdict:start/,/gate-verdict:end/p' "$S/body")" "  and the verdict is not marked"

echo "== mutants =="
m() {  # m <label> <sed expr>: a mutant of the script must fail the named probe
  sed "$2" "$REAL" > "$T/gate-status.sh"
  "$3" && bad "mutant survived: $1" || ok "mutant dies: $1"
  cp "$REAL" "$T/gate-status.sh"
}
probe_regions() { setbody "$BASE"; a=$(GS 7 --fingerprint); setbody "${BASE/context v1/context v2}"; [ "$a" = "$(GS 7 --fingerprint)" ]; }
probe_unrecorded() { setbody "$BASE"; GS 7 --mark-stale >/dev/null 2>&1; [ "$(patches)" = 0 ]; }
probe_top() { setbody "$BASE"; GS 7 --stamp >/dev/null 2>&1; [ "$(sed -n 3p "$S/body")" = '<!-- gate-verdict:start -->' ]; }
probe_retry() { setbody "$BASE"; STUB_RACE_KIND=region STUB_RACE_AT=6 GS 7 --stamp >/dev/null 2>&1; }
# The final re-read would also catch this edit; the retry-time check is what stops the stamp from
# writing ANYTHING more once an author edit is seen, so the probe counts PATCHes.
probe_judged() { setbody "$BASE"; STUB_RACE_AT=6 GS 7 --stamp >/dev/null 2>&1; [ "$(patches)" = 0 ]; }
probe_final() { setbody "$BASE"; STUB_RACE_AT=10 GS 7 --stamp >/dev/null 2>&1; [ "$(GS 7)" = "unrecorded round 2" ]; }
m "hashing the whole body, regions included" '/inside { next }/d' probe_regions
m "marking an unrecorded verdict" 's/case "$st" in stale\*) ;; \*) exit 0 ;; esac/:/' probe_unrecorded
m "stamping without top" 's/write_retry gate-verdict "$clean" top/write_retry gate-verdict "$clean"/' probe_top
m "no retry on 102" 's/if \[ "$rc" = 102 \]/if false/' probe_retry
m "retrying past an author edit" 's/\[ "$now" = "$FP0" \] ||/true ||/' probe_judged
m "stamping the re-read body's own fingerprint" 's/\[ "$fp" = "$FP0" \] ||/true ||/' probe_final

echo
echo "gate-status: $pass passed, $fail failed"
[ "$fail" = 0 ]
