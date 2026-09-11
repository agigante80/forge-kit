#!/usr/bin/env bash
# Contract test for forge_ci_status's Forgejo path (#193), and for the one case it exists to
# disambiguate: Forgejo's combined commit status reports a CANCELLED run as `failure`, so a branch
# that merely got superseded by a second push looks broken and has no failing step to point at.
# v13 was wrong on 23 of 39 red commits in the sample the ticket measured.
#
# THE DESIGN UNDER TEST IS OPTION B. The combined status the function already holds carries a
# per-job `description` that Forgejo hard-codes ("Has been cancelled", "Failing after 12s"), so the
# verdict is one jq filter over data already fetched: red state, every red row cancelled -> cancelled;
# anything else red -> failure. An unknown string falls towards failure, so an i18n change reverts
# to v13's answer and never to a false green. The red path makes NO second request, which is what
# lets a Forgejo without /actions/tasks behave exactly as v13 there, and one case asserts it.
#
# Option A, a paginated walk of /actions/tasks, was NOT ported: the gate's critic drove it with a
# server-clamped 20-item page and a failure on page 2 and got `cancelled`, the exact direction the
# function promises never to take, and the 24 downstream tests were blind to it.
#
# The second defect: `total_count == 0` was read as `not_configured`, but a queued run has no status
# row yet, so "CI is running" read as "no CI here", the one wrong answer that tells you to stop
# looking. One page of /actions/tasks now decides: a task for the sha is `pending`, none is `none`,
# an endpoint that cannot be asked stays `not_configured`. The sha match is a PREFIX match, since
# the caller's ref falls back to its literal (possibly short) form for a sha in another repository.
#
# Hermetic: forge_api, forge_host and forge_repo are stubbed after sourcing, and every call runs
# from a directory that is not a git repository so the ref cannot resolve to a real commit.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${FORGE_LIB_UNDER_TEST:-$HERE/../plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# shellcheck disable=SC1090
. "$LIB"
forge_host() { echo forgejo; }
forge_repo() { echo owner/repo; }

# forge_api GET <path>. STATUS_JSON and TASKS_JSON are set per case and served by path; every
# request is logged so a case can assert which endpoints were (not) asked.
REQLOG="$T/req.log"
forge_api() {
  echo "$1 $2" >> "$REQLOG"
  case "$2" in
    */commits/*/status) printf '%s' "$STATUS_JSON" ;;
    */actions/tasks*)   [ "$TASKS_JSON" = "ERROR" ] && return 22; printf '%s' "$TASKS_JSON" ;;
    *) return 1 ;;
  esac
}

# run <desc> <expected> <status-json> <tasks-json> [ref]
run() {
  STATUS_JSON="$3"; TASKS_JSON="$4"; : > "$REQLOG"
  local got; got=$(cd "$T" && forge_ci_status "${5:-deadbeef}" 2>/dev/null)
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1 (expected '$2', got '$got')"; fi
}
row() { printf '{"status":"%s","description":"%s"}' "$1" "$2"; }
red() { printf '{"total_count":%s,"state":"failure","statuses":[%s]}' "$1" "$2"; }

echo "== baseline =="
run "green stays green" success '{"total_count":1,"state":"success","statuses":[]}' '{}'
run "pending stays pending" pending '{"total_count":1,"state":"pending","statuses":[]}' '{}'

echo "== (a) cancelled versus failure, read from the combined status =="
run "a CANCELLED run is reported as cancelled, not failure" cancelled \
    "$(red 1 "$(row failure 'Has been cancelled')")" '{}'
run "two cancelled jobs are still cancelled" cancelled \
    "$(red 2 "$(row failure 'Has been cancelled'),$(row failure 'Has been cancelled')")" '{}'
run "a cancellation among successes is cancelled (the 6cffcb82 shape)" cancelled \
    "$(red 3 "$(row success 'Successful in 7m35s'),$(row success 'Successful in 56s'),$(row failure 'Has been cancelled')")" '{}'
run "and the order of the rows does not matter" cancelled \
    "$(red 3 "$(row failure 'Has been cancelled'),$(row success 'Successful in 7m35s'),$(row success 'Successful in 56s')")" '{}'
run "a real failure is a failure" failure \
    "$(red 1 "$(row failure 'Failing after 12s')")" '{}'
run "an infra error is a failure" failure \
    '{"total_count":1,"state":"error","statuses":[{"status":"error","description":"Failing after 1s"}]}' '{}'
run "a failure alongside a cancelled job is a FAILURE" failure \
    "$(red 2 "$(row failure 'Has been cancelled'),$(row failure 'Failing after 3m')")" '{}'
run "in either order" failure \
    "$(red 2 "$(row failure 'Failing after 3m'),$(row failure 'Has been cancelled')")" '{}'
run "a failure among successes and cancellations still wins" failure \
    "$(red 3 "$(row success 'Successful in 1s'),$(row failure 'Has been cancelled'),$(row failure 'Failing after 2s')")" '{}'

echo "== (f) the Option B negatives, each naming the mutant it kills =="
run "a red row with an unknown description is a failure (kills relaxing == to a looser match)" failure \
    "$(red 1 "$(row failure 'Something this rule does not know')")" '{}'
run "a red row saying 'Has been skipped', Forgejo's own string, is a failure (kills a prefix match)" failure \
    "$(red 1 "$(row failure 'Has been skipped')")" '{}'
run "a red row saying 'Has been cancelled by admin' is a failure (kills == relaxed to contains)" failure \
    "$(red 1 "$(row failure 'Has been cancelled by admin')")" '{}'
run "a red row with an EMPTY description is a failure (kills treating missing as cancelled)" failure \
    "$(red 1 '{"status":"failure"}')" '{}'
run "state failure with no rows at all is a failure (kills dropping the length guard)" failure \
    "$(red 1 '')" '{}'
run "a cancelled description on a GREEN row is not red: the other red row decides" failure \
    "$(red 2 "$(row success 'Has been cancelled'),$(row failure 'Failing after 9s')")" '{}'
# A success state is never inspected for descriptions: shadow the classifier to fail loudly.
( _forge_ci_failure_kind_from_status() { echo INSPECTED; }
  STATUS_JSON='{"total_count":1,"state":"success","statuses":[{"status":"success","description":"Has been cancelled"}]}'
  TASKS_JSON='{}'
  got=$(cd "$T" && forge_ci_status deadbeef 2>/dev/null)
  [ "$got" = success ] )
[ $? -eq 0 ] && ok "a success state is never inspected for descriptions (kills inspecting green)" \
              || bad "a success state was inspected for descriptions, or did not return success"

got=$(_forge_ci_failure_kind_from_status 'not json at all' 2>/dev/null)
[ "$got" = failure ] && ok "the classifier falls to failure on input jq cannot parse (kills a cancelled fallback)" \
                      || bad "the classifier returned '$got' on unparseable input"

echo "== (c) the red path never asks a second endpoint =="
STATUS_JSON="$(red 1 "$(row failure 'Has been cancelled')")"; TASKS_JSON='ERROR'; : > "$REQLOG"
got=$(cd "$T" && forge_ci_status deadbeef 2>/dev/null)
[ "$got" = cancelled ] && ok "a Forgejo whose /actions/tasks errors still answers cancelled on the red path" \
                        || bad "the red path depended on /actions/tasks (got '$got')"
grep -q '/actions/tasks' "$REQLOG" && bad "the red path requested /actions/tasks" \
                                     || ok "and /actions/tasks was never requested there (v13's request set, exactly)"

echo "== (b) total_count == 0: a missing status row is not a missing CI =="
NOSTAT='{"total_count":0,"state":"pending","statuses":[]}'
run "no status and no task means none, not not_configured" none "$NOSTAT" '{"workflow_runs":[]}'
run "no status but a task for this sha is PENDING, not not_configured" pending "$NOSTAT" \
    '{"workflow_runs":[{"head_sha":"deadbeef","status":"running"}]}'
run "no status and a task for ANOTHER sha is still none" none "$NOSTAT" \
    '{"workflow_runs":[{"head_sha":"other","status":"running"}]}'
run "an unreachable tasks endpoint with no status stays not_configured" not_configured "$NOSTAT" 'ERROR'
run "an empty tasks body with no status stays not_configured" not_configured "$NOSTAT" ''
run "a bare task array (older Forgejo envelope) is handled too" pending "$NOSTAT" \
    '[{"head_sha":"deadbeef","status":"running"}]'

echo "== (d) the sha match is a prefix match, in the no-status half =="
run "a SHORT sha still matches a full head_sha (kills startswith to ==)" pending "$NOSTAT" \
    '{"workflow_runs":[{"head_sha":"deadbeefcafebabe0123456789abcdef01234567","status":"running"}]}'
run "a short sha does not match an unrelated head_sha" none "$NOSTAT" \
    '{"workflow_runs":[{"head_sha":"0000beefcafebabe0123456789abcdef01234567","status":"running"}]}'

echo "== the run itself =="
grep -q 'limit=' "$REQLOG" && ok "the tasks request bounds its page (one page, never a walk)" \
                            || bad "the tasks request set no page limit"

echo
echo "forge-ci-status tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
