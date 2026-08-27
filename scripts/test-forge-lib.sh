#!/usr/bin/env bash
# Contract test for forge-host's forge-lib.sh (issues #62, #63). The library is driven with a
# stubbed forge_api standing in for the network layer (defined AFTER sourcing, so the real one
# is shadowed), a request log, and canned Forgejo responses. Covers:
#   - forge_issue_list (forgejo): concatenates ALL pages; a page SHORTER than the requested
#     limit but non-empty must NOT terminate the loop (server-side limit clamping, #62)
#   - forge_issue_list (forgejo): requests type=issues (PR exclusion is server-side)
#   - forge_issue_label (forgejo): resolves names across pages (#63 follow-up to the old
#     single-page ?limit=100 lookup), refuses the WHOLE call on any unresolvable name
#     (atomic, non-zero exit, stderr names the labels), zero-label repos get a distinct
#     message, and nothing is POSTed on refusal
#   - FORGE_DRY_RUN=1 sends nothing on either function
# The github branches shell out to `gh` and are unchanged by #62/#63; they are exercised by
# real use, not stubbed here.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${FORGE_LIB_UNDER_TEST:-$HERE/../plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

# Each case runs in a subshell: source the lib, shadow forge_api with the stub, act, assert.
# The stub logs every request to REQLOG and serves canned pages keyed on the query string.

# --- forge_issue_list pagination (#62) ---
(
  . "$LIB"
  REQLOG="$T/a.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$2" in
      *"/issues?"*page=1*) printf '[{"number":1},{"number":2}]' ;;   # short page (2 < limit): clamp shape
      *"/issues?"*page=2*) printf '[{"number":3}]' ;;
      *"/issues?"*page=3*) printf '[]' ;;
      *) printf '[]' ;;
    esac
  }
  out=$(forge_issue_list) || exit 9
  len=$(printf '%s' "$out" | jq 'length')
  [ "$len" = 3 ] || exit 1
  grep -q 'type=issues' "$REQLOG" || exit 2
  exit 0
)
case $? in
  0) ok "issue_list concatenates all pages; short-but-nonempty page does not terminate (clamp-safe)";;
  1) bad "issue_list did not return all 3 issues across pages (#62 truncation)";;
  2) bad "issue_list dropped the type=issues PR exclusion";;
  *) bad "issue_list errored";;
esac

# --- forge_issue_list small repo: terminates (no infinite loop) and returns the page ---
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { case "$2" in *page=1*) printf '[{"number":1}]';; *) printf '[]';; esac; }
  out=$(forge_issue_list) || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 1 ]
)
[ $? -eq 0 ] && ok "issue_list on a sub-page repo returns the single page and terminates" \
             || bad "issue_list on a sub-page repo"

# --- forge_issue_label: resolves across pages, POSTs resolved ids (#63 AC6) ---
(
  . "$LIB"
  REQLOG="$T/c.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2 ${3-}" >> "$REQLOG"
    case "$1 $2" in
      "GET "*"/labels?"*page=1*) seq 1 50 | jq -sc 'map({name:("l"+tostring),id:.})' ;;
      "GET "*"/labels?"*page=2*) printf '[{"name":"bug","id":99}]' ;;
      "GET "*"/labels?"*)        printf '[]' ;;
      "POST "*)                  printf '{}' ;;
    esac
  }
  forge_issue_label 7 bug || exit 1
  grep -q '^POST /repos/o/r/issues/7/labels {"labels":\[99\]}' "$REQLOG" || exit 2
)
case $? in
  0) ok "issue_label resolves a name on label page 2 and POSTs its id";;
  1) bad "issue_label failed on a resolvable name found beyond page 1 (#63 AC6)";;
  2) bad "issue_label did not POST the resolved id";;
  *) bad "issue_label multi-page case errored";;
esac

# --- forge_issue_label: unresolvable name refuses the WHOLE call, names it, POSTs nothing ---
(
  . "$LIB"
  REQLOG="$T/d.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$1 $2" in
      "GET "*"/labels?"*page=1*) printf '[{"name":"bug","id":1}]' ;;
      "GET "*"/labels?"*)        printf '[]' ;;
      "POST "*)                  printf '{}' ;;
    esac
  }
  err=$(forge_issue_label 7 bug nosuchlabel 2>&1 >/dev/null); rc=$?
  [ "$rc" -ne 0 ]                          || exit 1
  printf '%s' "$err" | grep -q 'nosuchlabel' || exit 2
  ! grep -q '^POST' "$REQLOG"              || exit 3
)
case $? in
  0) ok "issue_label refuses atomically on an unresolvable name, names it, sends no POST";;
  1) bad "issue_label exited 0 despite an unresolvable name (#63: the silent-drop bug)";;
  2) bad "issue_label error does not name the failing label";;
  3) bad "issue_label POSTed despite refusing (not atomic)";;
  *) bad "issue_label unresolvable case errored";;
esac

# --- forge_issue_label: zero-label repo gets a distinct error, no POST ---
(
  . "$LIB"
  REQLOG="$T/e.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$1 $2" in "GET "*"/labels?"*) printf '[]' ;; "POST "*) printf '{}' ;; esac
  }
  err=$(forge_issue_label 7 bug 2>&1 >/dev/null); rc=$?
  [ "$rc" -ne 0 ]                            || exit 1
  printf '%s' "$err" | grep -qi 'no labels'  || exit 2
  ! grep -q '^POST' "$REQLOG"                || exit 3
)
case $? in
  0) ok "issue_label on a zero-label repo errors with the distinct no-labels message";;
  1) bad "issue_label exited 0 on a zero-label repo (#63: fresh-repo silent no-op)";;
  2) bad "issue_label zero-label error is not distinct (should say the repo has no labels)";;
  3) bad "issue_label POSTed on a zero-label repo";;
  *) bad "issue_label zero-label case errored";;
esac

# --- forge_issue_list at scale: pages totalling well past the ~128KiB argv limit (F1) ---
# Accumulating pages via a jq --argjson argument dies at Linux MAX_ARG_STRLEN; one real page of
# template-v4-sized issues already sits near the ceiling, so pagination must not build argv.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  PAD="$(head -c 1300 /dev/zero | tr '\0' x)"
  BIGPAGE="$(jq -nc --arg pad "$PAD" '[range(50)] | map({number:., body:$pad})')"
  forge_api() {
    case "$2" in
      *"/issues?"*page=1*|*"/issues?"*page=2*|*"/issues?"*page=3*) printf '%s' "$BIGPAGE" ;;
      *) printf '[]' ;;
    esac
  }
  out=$(forge_issue_list) || exit 1
  [ "$(printf '%s' "$out" | jq 'length')" = 150 ] || exit 2
)
case $? in
  0) ok "issue_list survives pages totalling ~200KB (no argv-limit accumulation)";;
  1) bad "issue_list hard-failed on large pages (argv MAX_ARG_STRLEN, the E2BIG regression)";;
  2) bad "issue_list returned the wrong count on large pages";;
  *) bad "issue_list large-page case errored";;
esac

# --- forge_issue_label: org-level labels resolve (repo list alone is not the label universe) ---
(
  . "$LIB"
  REQLOG="$T/g.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2 ${3-}" >> "$REQLOG"
    case "$1 $2" in
      "GET /repos/"*"/labels?"*page=1*) printf '[{"name":"bug","id":1}]' ;;
      "GET /orgs/"*"/labels?"*page=1*)  printf '[{"name":"org-wide","id":7}]' ;;
      "GET "*"/labels?"*)               printf '[]' ;;
      "POST "*)                         printf '{}' ;;
    esac
  }
  forge_issue_label 7 org-wide || exit 1
  grep -q '^POST /repos/o/r/issues/7/labels {"labels":\[7\]}' "$REQLOG" || exit 2
)
case $? in
  0) ok "issue_label resolves an org-level label and POSTs its id";;
  1) bad "issue_label refused a valid org-level label (repo list treated as the whole universe)";;
  2) bad "issue_label did not POST the org label id";;
  *) bad "issue_label org-label case errored";;
esac

# --- forge_api_paginate directly under dry-run: prints [] and sends nothing real ---
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_API_URL=https://forge.example FORGE_DRY_RUN=1
  forge_api() { printf '[{"number":1}]'; }
  out=$(forge_api_paginate "/repos/o/r/milestones" 2>/dev/null) || exit 1
  [ "$out" = "[]" ] || exit 2
)
case $? in
  0) ok "paginate under dry-run prints [] (direct callers like dep-auditor stay side-effect free)";;
  *) bad "paginate dry-run case (rc=$?)";;
esac

# --- FORGE_DRY_RUN: nothing is sent by either function ---
(
  . "$LIB"
  REQLOG="$T/f.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_API_URL=https://forge.example FORGE_DRY_RUN=1
  forge_api() { echo "$1 $2" >> "$REQLOG"; printf '[]'; }   # must never be reached for writes
  forge_issue_list  >/dev/null 2>&1 || exit 1
  forge_issue_label 7 bug 2>/dev/null || exit 2
  ! grep -q '^POST' "$REQLOG" || exit 3
)
case $? in
  0) ok "dry-run sends no writes from issue_list or issue_label";;
  *) bad "dry-run case (rc=$?)";;
esac

echo ""
echo "forge-lib tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
