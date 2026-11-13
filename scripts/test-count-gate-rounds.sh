#!/usr/bin/env bash
# Contract test for count-gate-rounds.sh (#192, #581).
#
# WHAT THE HELPER IS FOR. The gate's round number decides whether the delta rows of its round table
# engage and whether a caller's trip wire, which counts rounds, can fire. #192 moved the count out
# of the body into posted review comments, because a body edit erased the `gate-verdict` region.
# #581 (the maintainer: the gate posts NO comment) moved it back: the round is the heading of the
# gate-verdict / gate-review regions, and the legacy review comments of tickets gated before that
# change are a second source. Rounds run = the MAX of the two, so a migrated ticket needs no
# conversion. These cases pin what counts as a round (a marker inside a gate region; a comment whose
# FIRST line is the review heading for THIS issue), what does not (a synthesis-void or clarification
# comment, a heading quoted on a later line or in author text, a sibling ticket's review), the
# honest residual (regions deleted, no legacy comment: round 1 PLUS a stderr warning) and the two
# refusals: a listing that cannot run must never print `1`.
#
# v2 (#196) added `--memory`, which restores the prior blocking items. v4 (#581) reads them from the
# body's gate-required-changes region first, a PASS verdict second, and only then the legacy
# `gate-items` pair of the latest review comment. These cases pin the exit rows and the argument-order
# refusal: the issue number must come first, so a stale caller reaching a stale v1 copy always
# fails the same way regardless of which script it actually hits.
#
# Driven with a STUB forge-lib.sh placed beside a copy of the script, the shape
# test-forge-gate-mechanics.sh uses, so no network and no token are involved.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
REAL="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/count-gate-rounds.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if grep -qF -- "$1" <<< "$2"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

[ -f "$REAL" ] || { echo "missing script: $REAL"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$REAL" "$BIN/"

# The stub transport: forge_issue_comments prints the fixture the case wrote, or fails when told to.
# Every comment carries a user.login so the "stderr never prints an author" cases have something
# to catch.
cat > "$BIN/forge-lib.sh" <<'LIB'
forge_repo() { echo "fixture/repo"; }
forge_host() { echo "github"; }
forge_issue_comments() {
  [ "${FIXTURE_FAIL:-0}" = 1 ] && { echo "forge_api: transport failure" >&2; return 22; }
  cat "$FIXTURE_COMMENTS"
}
forge_issue_view() {
  [ "${FIXTURE_VIEW_FAIL:-0}" = 1 ] && { echo "forge_api: transport failure" >&2; return 22; }
  if [ -n "${FIXTURE_BODY_FILE:-}" ] && [ -f "$FIXTURE_BODY_FILE" ]; then jq -Rs '{body:.}' < "$FIXTURE_BODY_FILE"; else echo '{"body":""}'; fi
}
LIB

# comments <body>...  writes a fixture of one comment per argument, each authored by a sentinel
# login that must never reach stderr.
comments() {
  FIXTURE_COMMENTS="$T/comments.json"
  jq -nc --args '[$ARGS.positional[] | {user: {login: "sentinel-author"}, body: .}]' "$@" > "$FIXTURE_COMMENTS"
  export FIXTURE_COMMENTS
}
review() { printf '## Ticket Readiness Review - #%s\n\n**Verdict: NEEDS-WORK**' "$1"; }

# reviewItems <issue> <item>...  a review comment wrapping a non-empty gate-items pair.
reviewItems() {
  issue="$1"; shift
  printf '## Ticket Readiness Review - #%s\n\n**Verdict: NEEDS-WORK**\n\n<!-- gate-items:start -->\n' "$issue"
  for i in "$@"; do printf -- '- [ ] %s\n' "$i"; done
  printf '<!-- gate-items:end -->\n'
}
# reviewPass <issue>  a review comment wrapping an empty gate-items pair.
reviewPass() { printf '## Ticket Readiness Review - #%s\n\n**Verdict: PASS**\n\n<!-- gate-items:start -->\n<!-- gate-items:end -->\n' "$1"; }

# run <args...>: out on stdout, err on stderr, rc.
run() { out=$(cd "$BIN" && bash ./count-gate-rounds.sh "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

echo "== the count comes from posted review comments =="
comments
run 42
expect "no comments: this run is round 1" 1 "$out"
expect "and exits 0" 0 "$rc"

comments "$(review 42)" "$(review 42)"
run 42
expect "two review comments: this run is round 3 (the erased-region case)" 3 "$out"

echo "== what does NOT count =="
comments "$(review 42)" "$(review 42)" \
  "$(printf '## Synthesis void - #42\n\nThe body was synthesised.')" \
  "$(printf 'A remediation note quoting the heading:\n## Ticket Readiness Review - #42\non a later line.')"
run 42
expect "a void comment and a quoted heading are not rounds: only a FIRST-line heading counts" 3 "$out"

comments "$(review 41)"
run 42
expect "a review pasted from a sibling ticket (#41) is not a round of #42" 1 "$out"

comments "$(review 42)" "$(review 420)"
run 42
expect "the issue number must match exactly: #420 is not #42" 2 "$out"

# verdictbody <round> [extra]: a body whose gate-verdict region heading carries <round>.
verdictbody() {
  printf '## Summary\n\nThe thing.\n\n<!-- gate-verdict:start -->\n### Gate verdict (round %s)\n**Verdict:** NEEDS-WORK\n- significant: fix it\n<!-- gate-verdict:end -->\n%s\n' "$1" "${2-}"
}

echo "== the round comes from the body's gate regions (#581) =="
comments
verdictbody 2 > "$T/b.md"
run 42 --body "$T/b.md"
expect "a gate-verdict heading says round 2, no comments: this run is round 3" 3 "$out"
expect "and stderr is empty" "" "$err"

printf '## Summary\n\n<!-- gate-review:start -->\n### Gate review (round 4)\nthe review\n<!-- gate-review:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a gate-review heading alone says round 4: this run is round 5" 5 "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 3): STALE\n<!-- gate-verdict:end -->\n<!-- gate-review:start -->\n### Gate review (round 3)\n<!-- gate-review:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a STALE verdict heading still carries its round; both regions agree" 4 "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 2)\n<!-- gate-verdict:end -->\n<!-- gate-review:start -->\n### Gate review (round 5)\n<!-- gate-review:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "the regions disagree (a crash between the two writes): the highest wins" 6 "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 10)\n<!-- gate-verdict:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "round 10 compares as a number, not as text" 11 "$out"

printf '## Summary\n\nAuthor rewrote every section, gate regions untouched.\n\n## Acceptance\n\n1. new text\n<!-- gate-verdict:start -->\n### Gate verdict (round 2)\n<!-- gate-verdict:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a second round after the author rewrote every section reports round 3, not 1" 3 "$out"

printf '## Notes\n\n### Gate verdict (round 9)\n\nan author quoting a heading outside any region\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a round heading outside the gate regions is author text and does not count" 1 "$out"
expect "and a body with no gate trace warns nothing" "" "$err"

printf '<!-- gate-context:start -->\n### Gate verdict (round 9)\n<!-- gate-context:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a round heading inside another gate region (gate-context) does not count" 1 "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round two)\n<!-- gate-verdict:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a non-integer round in the heading is ignored, not parsed as 0 or 2" 1 "$out"

echo "== legacy review comments are the second source: the MAX of both =="
verdictbody 2 > "$T/b.md"
comments "$(review 42)" "$(review 42)" "$(review 42)"
run 42 --body "$T/b.md"
expect "marker 2, three legacy comments: 3 rounds run, this is round 4 (max, not sum)" 4 "$out"
expect "and stderr is empty" "" "$err"

verdictbody 5 > "$T/b.md"
comments "$(review 42)"
run 42 --body "$T/b.md"
expect "marker 5, one legacy comment: this is round 6" 6 "$out"

comments "$(review 42)" "$(review 42)"
printf '## Summary\n\nno gate regions at all\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "legacy comments alone (a ticket gated before #581): round 3, as before" 3 "$out"
expect "and no reset warning, the comments back the count" "" "$err"

verdictbody 1 > "$T/b.md"
comments "$(review 42)" "$(review 42)" "$(review 42)" "$(review 41)" "$(printf '## Synthesis void - #42\n\nx')"
run 42 --body "$T/b.md"
expect "a body block behind the comments never lowers the count and raises no disagreement line" 4 "$out"
expect "  stderr stays empty" "" "$err"

echo "== the residual case: regions deleted, no legacy comment (#581) =="
comments
printf '## Summary\n\n<!-- gate-verdict:start -->\n### Gate verdict\n**Verdict:** NEEDS-WORK\nJudged body: sha256:0123456789abcdef (fp11).\n<!-- gate-verdict:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a verdict region whose heading lost its round, no comments: round 1" 1 "$out"
expect "and the exit is still 0" 0 "$rc"
contains "the count may have been reset" "$err" "and one stderr line says the count may have been reset"
lacks "sentinel-author" "$err" "which names no comment author"

printf '## Summary\n\nJudged body: sha256:0123456789abcdef (fp11).\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a Judged stamp left in author text with no region: round 1" 1 "$out"
contains "the count may have been reset" "$err" "  and it warns"

printf '## Summary\n\n<!-- gate-required-changes:start -->\n### Required changes\n- [ ] x\n<!-- gate-required-changes:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
contains "the count may have been reset" "$err" "a surviving required-changes region with no round heading also warns"

printf '## Summary\n\n<!-- gate-review:start -->\n### Gate clarification needed\n1. question?\n<!-- gate-review:end -->\n<!-- gate-context:start -->\nctx\n<!-- gate-context:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a clarification stop and a context region are not a round" 1 "$out"
contains "the count may have been reset" "$err" "and a gate-review region with no round heading is a trace: the advisory warning fires (round 2 review)"

echo "== 0c then 1.5 in one run keeps the count (round 2 review) =="
# First run on a hand-filed ticket: 0c-v writes the void note under a round 0 heading. Round 1, no warning.
printf '## Summary\n\n<!-- gate-review:start -->\n### Gate review (round 0)\n#### Template auto-upgraded to v6\nnote\n<!-- gate-review:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "a round 0 void heading reports round 1" 1 "$out"
expect "  and it does not warn of a reset" "" "$err"

# Round 2 ticket: 0c clears gate-verdict, 0c-v writes the round-2 heading with the void note, 1.5 APPENDS the clarification.
printf '## Summary\n\n<!-- gate-review:start -->\n### Gate review (round 2)\n#### Template auto-upgraded to v6\nnote\n\n### Gate clarification (needed before review)\n1. q?\n<!-- gate-review:end -->\n' > "$T/b.md"
comments
run 42 --body "$T/b.md"
expect "after 0c-v and 1.5 appended: round 3, not 1" 3 "$out"
expect "  and no warning" "" "$err"
# The broken sequence (1.5 overwrote the heading) can only reset, and now says so.
printf '## Summary\n\n<!-- gate-review:start -->\n### Gate clarification (needed before review)\n1. q?\n<!-- gate-review:end -->\n' > "$T/b.md"
run 42 --body "$T/b.md"
expect "1.5 overwriting the heading resets to round 1" 1 "$out"
contains "the count may have been reset" "$err" "  but the reset is no longer silent"

printf '## Summary\n\nJudged body: sha256:0123456789abcdef (fp11).\n' > "$T/b.md"
comments "$(review 42)"
run 42 --body "$T/b.md"
expect "the same trace with a legacy comment behind it: round 2" 2 "$out"
expect "  and no warning" "" "$err"

echo "== without --body the body is read from the forge =="
comments
verdictbody 3 > "$T/b.md"; export FIXTURE_BODY_FILE="$T/b.md"
run 42
expect "forge_issue_view supplies the body: round 4" 4 "$out"
FIXTURE_VIEW_FAIL=1 run 42
expect "an unreadable issue exits 2" 2 "$rc"
expect "and prints nothing" "" "$out"
contains "forge_issue_view" "$err" "and names the call"
unset FIXTURE_VIEW_FAIL FIXTURE_BODY_FILE

echo "== the boundary =="
set --; i=0; while [ $i -lt 51 ]; do set -- "$@" "$(review 42)"; i=$((i + 1)); done
comments "$@"
run 42
expect "51 review comments in one listing: prints 52 (the off-by-one at the boundary)" 52 "$out"

echo "== a count that cannot run never reports 1 =="
comments "$(review 42)"
FIXTURE_FAIL=1 run 42
expect "a transport failure exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "forge_issue_comments" "$err" "and stderr names the call that failed"
lacks "sentinel-author" "$err" "and names no comment author"
unset FIXTURE_FAIL

mv "$BIN/forge-lib.sh" "$BIN/forge-lib.hidden"
run 42
expect "no forge-lib.sh beside the script and no FORGE_LIB: exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "forge-lib.sh" "$err" "and stderr names the missing file"
mv "$BIN/forge-lib.hidden" "$BIN/forge-lib.sh"

run
expect "no issue number: exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"

echo "== --memory restores prior blocking items =="
comments "$(review 42)" "$(reviewItems 42 "fix A" "fix B")"
run 42 --memory
expect "two items restored, one per line" 0 "$rc"
expect "and the answer is the checklist text" "fix A
fix B" "$out"

comments "$(review 42)" "$(reviewPass 42)"
run 42 --memory
expect "an empty gate-items pair (PASS) exits 0" 0 "$rc"
expect "and prints nothing" "" "$out"
contains "latest review was a PASS" "$err" "and stderr says so"

comments "$(reviewItems 42 'a backtick item using `code`' 'an issue reference to #248')"
run 42 --memory
expect "item order preserved, a backtick and an issue reference pass through unchanged" 0 "$rc"
expect "and both lines are printed verbatim" 'a backtick item using `code`
an issue reference to #248' "$out"

comments "$(reviewItems 42 "an earlier item")" "$(review 42)"
run 42 --memory
expect "a gate-items pair in an EARLIER comment but not the latest: only the latest is read" 3 "$rc"
expect "and prints nothing" "" "$out"

comments "$(printf '## Ticket Readiness Review - #42\n\nQuoted for reference:\n```\n- [ ] not a real item\n- [ ] another quoted line\n```\n\n<!-- gate-items:start -->\n- [ ] the real item\n<!-- gate-items:end -->')"
run 42 --memory
expect "a fenced checklist outside the marker pair is not read as memory" 0 "$rc"
expect "only the item inside the pair is printed" "the real item" "$out"

echo "== --memory refuses what it cannot read as a list =="
comments "$(review 42)"
run 42 --memory
expect "no gate-items marker at all: refuses" 3 "$rc"
expect "and prints nothing" "" "$out"
contains "no gate-items marker" "$err" "and stderr says so, naming the raw line count"

comments "$(review 41)"
run 42 --memory
expect "no review comment for THIS issue at all: refuses" 3 "$rc"
expect "and prints nothing" "" "$out"
contains "no '## Ticket Readiness Review - #42' comment" "$err" "and stderr names the issue"

comments "$(printf '## Ticket Readiness Review - #42\n\n<!-- gate-items:start -->\n- [ ] a\n<!-- gate-items:start -->\n- [ ] b\n<!-- gate-items:end -->')"
run 42 --memory
expect "two start markers is malformed: refuses" 3 "$rc"
expect "and prints nothing" "" "$out"
contains "2 gate-items start markers" "$err" "and stderr names the count"
lacks "sentinel-author" "$err" "and names no comment author"

comments "$(printf '## Ticket Readiness Review - #42\n\n<!-- gate-items:start -->\n- [ ] a')"
run 42 --memory
expect "an unterminated pair is malformed: refuses" 3 "$rc"
contains "unterminated" "$err" "and stderr says so"

comments "$(printf '## Ticket Readiness Review - #42\n\n<!-- gate-items:end -->\n- [ ] a\n<!-- gate-items:start -->')"
run 42 --memory
expect "an end marker before its start is malformed: refuses" 3 "$rc"
contains "reversed order" "$err" "and stderr says so"

comments "$(printf '## Ticket Readiness Review - #42\n\n<!-- gate-items:start -->\n- [ ] real item\n<!-- gate-items:end -->\n\nExample of the marker syntax:\n\n```\n<!-- gate-items:start -->\n```')"
run 42 --memory
expect "a fenced quote of the marker is read as a second start (not fence-aware): refuses" 3 "$rc"
contains "2 gate-items start markers" "$err" "and the quoted line counts exactly like a real one"

echo "== --memory reads the body's regions first (#581) =="
printf '## Summary\n\n<!-- gate-required-changes:start -->\n### Required changes (round 2)\n- [ ] fix A\n- [x] done B\n- [ ] fix `C` for #248\n<!-- gate-required-changes:end -->\n' > "$T/b.md"
comments
run 42 --memory --body "$T/b.md"
expect "unchecked items of the body region are restored, no comment needed" 0 "$rc"
expect "  ticked items are not, order and punctuation are kept" 'fix A
fix `C` for #248' "$out"

comments "$(reviewItems 42 "a stale legacy item")"
run 42 --memory --body "$T/b.md"
expect "the body wins over a legacy comment" 'fix A
fix `C` for #248' "$out"

printf '## Summary\n\n<!-- gate-required-changes:start -->\n### Required changes (round 2)\n- [x] all done\n<!-- gate-required-changes:end -->\n' > "$T/b.md"
comments "$(reviewItems 42 "a stale legacy item")"
run 42 --memory --body "$T/b.md"
expect "a region with every item ticked restores nothing, exit 0 (not the legacy item)" 0 "$rc"
expect "  and prints nothing" "" "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 3)\n**Verdict:** PASS\n<!-- gate-verdict:end -->\n' > "$T/b.md"
comments "$(reviewItems 42 "a stale legacy item")"
run 42 --memory --body "$T/b.md"
expect "a PASS verdict in the body with no required-changes region: exit 0" 0 "$rc"
expect "  nothing to carry, the older legacy comment is not consulted" "" "$out"
contains "PASS" "$err" "  and stderr says so"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 1)\n**Verdict:** NEEDS-WORK\n<!-- gate-verdict:end -->\n' > "$T/b.md"
comments "$(reviewItems 42 "legacy item")"
run 42 --memory --body "$T/b.md"
expect "a body round NOT newer than the legacy count, no required-changes region: the legacy comment" "legacy item" "$out"

printf '<!-- gate-verdict:start -->\n### Gate verdict (round 3)\n**Verdict:** NEEDS-WORK\n<!-- gate-verdict:end -->\n' > "$T/b.md"
comments "$(reviewItems 42 "an older round's item")"
run 42 --memory --body "$T/b.md"
expect "round 5 review: a body round (3) newer than the legacy count (1) must not return an older comment's items: exit 3" 3 "$rc"
expect "  nothing on stdout" "" "$out"
contains "newer than the legacy comments" "$err" "  and stderr says why"

echo "== regions quoted in a fenced block are text (round 1 review) =="
FENCED='An example of the block the gate writes:

```
<!-- gate-verdict:start -->
### Gate verdict (round 7)
**Verdict:** PASS
<!-- gate-verdict:end -->
```
'
{ printf '%s\n' "$FENCED"; verdictbody 1; } > "$T/b.md"
comments
run 42 --body "$T/b.md"
expect "a fenced example region (round 7) above the real round 1 region: the count is 2, not 8" 2 "$out"
printf '%s\n<!-- gate-required-changes:start -->\n- [ ] real item\n<!-- gate-required-changes:end -->\n' "$(cat "$T/b.md")" > "$T/b2.md"
run 42 --memory --body "$T/b2.md"
expect "--memory: the fenced PASS does not hide the real required-changes region" "real item" "$out"
{ printf '%s\n' "$FENCED"; printf '<!-- gate-verdict:start -->\n### Gate verdict (round 1)\n**Verdict:** NEEDS-WORK\n<!-- gate-verdict:end -->\n'; } > "$T/b3.md"
comments
run 42 --memory --body "$T/b3.md"
expect "--memory: a fenced PASS example with a real NEEDS-WORK verdict and nothing else: exit 3, not 0" 3 "$rc"
printf '~~~\n<!-- gate-verdict:start -->\n### Gate verdict (round 9)\n<!-- gate-verdict:end -->\n~~~\n' > "$T/b4.md"
run 42 --body "$T/b4.md"
expect "a ~~~ fence is a fence too: nothing counted, round 1" 1 "$out"

printf '## Summary\n\nnothing of the gate\n' > "$T/b.md"
comments
run 42 --memory --body "$T/b.md"
expect "no body region and no legacy comment: exit 3" 3 "$rc"
expect "  nothing on stdout" "" "$out"

verdictbody 1 > "$T/b.md"
printf '<!-- gate-required-changes:start -->\n- [ ] kept\n<!-- gate-required-changes:end -->\n' >> "$T/b.md"
comments
export FIXTURE_BODY_FILE="$T/b.md"; run 42 --memory
expect "without --body the body is read from the forge for memory too" "kept" "$out"
unset FIXTURE_BODY_FILE

echo "== --memory and the plain count share the same transport failure =="
comments "$(review 42)" "$(reviewItems 42 "fix A")"
FIXTURE_FAIL=1 run 42 --memory
expect "a transport failure exits 2" 2 "$rc"
expect "and prints nothing" "" "$out"
contains "forge_issue_comments" "$err" "and stderr names the call that failed"
unset FIXTURE_FAIL

echo "== the issue number must come first =="
comments "$(review 42)" "$(reviewItems 42 "fix A")"
run 42 --memory
expect "issue first: succeeds" 0 "$rc"
expect "and restores the item" "fix A" "$out"

run --memory 42
expect "flag first is a usage error, not read as the issue number" 2 "$rc"
expect "and prints nothing" "" "$out"
contains "usage" "$err" "and stderr carries the usage line"

run 42 --bogus
expect "an unrecognised option is a usage error" 2 "$rc"
expect "and prints nothing" "" "$out"
contains "unrecognised option" "$err" "and stderr names the option"

run 42 43
expect "a second positional argument is a usage error" 2 "$rc"
contains "unexpected argument" "$err" "and stderr names it"

echo "== portability =="
code() { grep -v '^[[:space:]]*#' "$1"; }
grep -qF '\|' <<< "$(code "$REAL")" && bad "uses a GNU-only \\| alternation (BSD sed matches it literally)" || ok "no GNU-only \\| alternation in sed or grep"
grep -q ',,}' <<< "$(code "$REAL")" && bad "uses the bash-4 lowercase expansion" || ok "no bash-4 lowercase expansion"
grep -q 'readlink -f' <<< "$(code "$REAL")" && bad "uses GNU readlink -f" || ok "no GNU readlink -f"
grep -qE '(^|[^a-z-])(claude|gh) ' <<< "$(code "$REAL")" && bad "shells out to the harness CLI or gh directly" || ok "no dependency on the harness CLI or on gh: the transport is forge-lib's"

echo
echo "count-gate-rounds tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
