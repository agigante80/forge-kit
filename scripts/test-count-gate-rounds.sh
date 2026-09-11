#!/usr/bin/env bash
# Contract test for count-gate-rounds.sh (#192).
#
# WHAT THE HELPER IS FOR. The gate's round number used to be read from a `gate-verdict` region in
# the issue body, and an ordinary body edit erases that region. The gate then believed every round
# was round 1: delta scope never engaged, and a caller's trip wire, which counts rounds, could never
# fire. A posted review comment is not erased by a body edit, so the count now comes from the
# comments and the body block is only a projection of it. These cases pin down what counts as a
# round (a comment whose FIRST line is the review heading for THIS issue), what does not (a
# synthesis-void comment, a heading quoted on a later line, a sibling ticket's review), and the two
# refusals: a listing that cannot run must never print `1`.
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
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

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
LIB

# comments <body>...  writes a fixture of one comment per argument, each authored by a sentinel
# login that must never reach stderr.
comments() {
  FIXTURE_COMMENTS="$T/comments.json"
  jq -nc --args '[$ARGS.positional[] | {user: {login: "sentinel-author"}, body: .}]' "$@" > "$FIXTURE_COMMENTS"
  export FIXTURE_COMMENTS
}
review() { printf '## Ticket Readiness Review - #%s\n\n**Verdict: NEEDS-WORK**' "$1"; }

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

echo "== the body block is a projection of the count, never its source =="
comments "$(review 42)" "$(review 42)"
printf '<!-- gate-verdict:start -->\n### Gate verdict (round 2)\n<!-- gate-verdict:end -->\n' > "$T/body-agree.md"
run 42 --body "$T/body-agree.md"
expect "block and comments agree: prints 3" 3 "$out"
expect "and stderr is empty" "" "$err"

printf '### Gate verdict (round 7)\n' > "$T/body-stale.md"
run 42 --body "$T/body-stale.md"
expect "a stale block does not change the answer" 3 "$out"
expect "and the run still exits 0" 0 "$rc"
contains "body block says round 7, comments say 2" "$err" "and the disagreement is one visible stderr line"
lacks "sentinel-author" "$err" "which names no comment author"

printf '### Gate verdict (round two)\n' > "$T/body-junk.md"
run 42 --body "$T/body-junk.md"
expect "a non-integer round in the block is ignored, not parsed as 0" 3 "$out"
lacks "body block says" "$err" "and raises no disagreement"

printf '### Gate verdict (round 1)\n' > "$T/body-edited.md"
run 42 --body "$T/body-edited.md"
expect "a body rewritten between rounds reads round 3, never round 1" 3 "$out"
contains "body block says round 1, comments say 2" "$err" "and says the block is behind"

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

echo "== portability =="
code() { grep -v '^[[:space:]]*#' "$1"; }
code "$REAL" | grep -q ',,}' && bad "uses the bash-4 lowercase expansion" || ok "no bash-4 lowercase expansion"
code "$REAL" | grep -q 'readlink -f' && bad "uses GNU readlink -f" || ok "no GNU readlink -f"
code "$REAL" | grep -qE '(^|[^a-z-])(claude|gh) ' && bad "shells out to the harness CLI or gh directly" || ok "no dependency on the harness CLI or on gh: the transport is forge-lib's"

echo
echo "count-gate-rounds tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
