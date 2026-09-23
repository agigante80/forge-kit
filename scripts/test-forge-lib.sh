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
#   - #78: the config memo actually SAVES work (measured with a counting git on PATH), the
#     forgejo arm of forge_api behaviourally (200/404/401/500/transport/empty/multiline via a
#     stubbed curl), and the temp dir (created once, trapped when the caller has no trap,
#     removed on the normal path)
# The github branches shell out to `gh` and are unchanged by #62/#63; they are exercised by
# real use, not stubbed here.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${FORGE_LIB_UNDER_TEST:-$HERE/../plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

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
  forge_api() {   # ids derive from the page, or the #228 identical-page stop would end this at page 2
    case "$2" in
      *"/issues?"*page=1*|*"/issues?"*page=2*|*"/issues?"*page=3*) printf '%s' "$BIGPAGE" | jq -c --argjson pg "${2##*page=}" 'map(.number += 50*($pg-1))' ;;
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
      "GET /orgs/"*"/labels?"*page=1*)  printf '[{"name":"org-wide","id":42}]' ;;
      "GET "*"/labels?"*)               printf '[]' ;;
      "POST "*)                         printf '{}' ;;
    esac
  }
  forge_issue_label 7 org-wide || exit 1
  grep -q '^POST /repos/o/r/issues/7/labels {"labels":\[42\]}' "$REQLOG" || exit 2
)
case $? in
  0) ok "issue_label resolves an org-level label and POSTs its id (id distinct from the issue number)";;
  1) bad "issue_label refused a valid org-level label (repo list treated as the whole universe)";;
  2) bad "issue_label did not POST the org label id";;
  *) bad "issue_label org-label case errored";;
esac

# --- forge_issue_label: an EMPTY-STRING name must be refused, not slip past the gate ---
# join(" ") of [""] is "", so a string-emptiness gate reads an empty name as "nothing missing"
# and would POST [null, ...]: the silent-partial class again, reached by an argv quoting slip.
(
  . "$LIB"
  REQLOG="$T/h.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$1 $2" in
      "GET "*"/labels?"*page=1*) printf '[{"name":"bug","id":1}]' ;;
      "GET "*"/labels?"*)        printf '[]' ;;
      "POST "*)                  printf '{}' ;;
    esac
  }
  err=$(forge_issue_label 7 "" bug 2>&1 >/dev/null); rc=$?
  [ "$rc" -ne 0 ]             || exit 1
  ! grep -q '^POST' "$REQLOG" || exit 2
)
case $? in
  0) ok "issue_label refuses an empty-string name (no null id ever POSTed)";;
  1) bad "issue_label accepted an empty-string name (refusal gate bypass, POSTs null ids)";;
  2) bad "issue_label POSTed despite an empty-string name";;
  *) bad "issue_label empty-name case errored";;
esac

# --- forge_issue_comments (#192): ALL pages, in order, so a round count cannot stop at page 1 ---
# 31 comments across a 30-item page and a 1-item page. The count-gate-rounds helper counts these,
# and a count that stopped at the first page would read round 31 as round 30 for ever after.
(
  . "$LIB"
  REQLOG="$T/c.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$2" in
      */issues/42/comments?*page=1*) jq -nc '[range(1;31) | {id: ., body: ("c" + tostring)}]' ;;
      */issues/42/comments?*page=2*) printf '[{"id":31,"body":"c31"}]' ;;
      */issues/42/comments?*)        printf '[]' ;;
      *) printf '[]' ;;
    esac
  }
  out=$(forge_issue_comments 42) || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 31 ] || exit 1
  [ "$(printf '%s' "$out" | jq -r '.[30].body')" = c31 ] || exit 2
  grep -q '/issues/42/comments' "$REQLOG" || exit 3
  exit 0
)
case $? in
  0) ok "issue_comments returns all 31 comments across two pages, in order (#192)";;
  1) bad "issue_comments did not return all 31 comments (stopped at a page boundary)";;
  2) bad "issue_comments returned the comments out of order";;
  3) bad "issue_comments did not request the issue's comments path";;
  *) bad "issue_comments errored (function missing?)";;
esac

# --- pagination: an EMPTY 200 body mid-run is an ERROR, not a silent end-of-list ---
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { case "$2" in *page=1*) printf '[{"number":1}]';; *) printf '';; esac; }
  out=$(forge_issue_list 2>/dev/null); rc=$?
  [ "$rc" -ne 0 ]
)
[ $? -eq 0 ] && ok "paginate treats an empty response body as an error, not completion"              || bad "paginate silently truncated on an empty 200 body (rc 0, partial list)"

# --- pagination: a NON-ARRAY 200 body (error object) is an ERROR, not counted by key ---
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { printf '{"message":"temporarily unavailable"}'; }
  out=$(forge_issue_list 2>/dev/null); rc=$?
  [ "$rc" -ne 0 ]
)
[ $? -eq 0 ] && ok "paginate treats a non-array body as an error (jq length on an object counts keys)"              || bad "paginate accepted a non-array body (object keys counted as items)"

# --- pagination cap survives a NON-NUMERIC override (a junk cap must not mean no cap) ---
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=junk
  # non-empty forever, with a DISTINCT id per page so the #228 identical-page stop cannot end it:
  # only the cap can stop this
  out=$(timeout 30 bash -c '
    . "'"$LIB"'"
    export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=junk
    forge_api() { printf "[{\"number\":%s}]" "${2##*page=}"; }
    forge_issue_list 2>/dev/null
  '); rc=$?
  [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]
)
[ $? -eq 0 ] && ok "a non-numeric FORGE_PAGINATE_MAX_PAGES falls back to the default cap (errors, no spin)"              || bad "a non-numeric page cap disabled the spin guard (timed out or exited 0)"

# --- #228: a host that IGNORES page returns the same page for ever; stop on the same KEYS -------
# Forgejo's per-issue comments endpoint returns the whole list whatever page= says (go-gitea
# #6132), so no page is ever empty and v16 spun to the cap: 500 requests, seventeen minutes,
# then rc 2 and count-gate-rounds read `unknown`. The stop compares stable keys, not bytes.
(
  . "$LIB"
  REQLOG="$T/ign.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=3   # red takes seconds, not minutes
  forge_api() { echo "$1 $2" >> "$REQLOG"; printf '[{"id":13725,"body":"a"},{"id":13734,"body":"b"}]'; }
  out=$(forge_issue_comments 104 2>"$T/ign.err") || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 2 ] || exit 1
  [ "$(grep -c comments "$REQLOG")" = 2 ] || exit 2
  grep -q 'identical page: server ignores page' "$T/ign.err" || exit 3
  exit 0
)
case $? in
  0) ok "paginate stops after one identical page on a host that ignores page= (#228)";;
  1) bad "paginate returned the identical page more than once (accumulated before comparing)";;
  2) bad "paginate made more than two requests on an identical page (did not stop)";;
  3) bad "paginate did not say on stderr that the identical-page stop fired";;
  *) bad "paginate ran to the cap on an identical page (#228 spin)";;
esac

# --- #228: same keys, different bytes: a volatile field must not defeat the stop ----------------
(
  . "$LIB"
  REQLOG="$T/vol.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=3
  forge_api() { echo "$1 $2" >> "$REQLOG"; local c; c=$(wc -l < "$REQLOG" | tr -d " "); printf '[{"id":1,"updated_at":"t%s"},{"id":2,"updated_at":"t%s"}]' "$c" "$c"; }
  out=$(forge_api_paginate /repos/o/r/issues/1/comments 2>"$T/vol.err") || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 2 ] || exit 1
  [ "$(wc -l < "$REQLOG" | tr -d " ")" = 2 ] || exit 2
  grep -q 'identical page: server ignores page' "$T/vol.err" || exit 3
  exit 0
)
case $? in
  0) ok "paginate's identical-page stop compares keys, so a volatile updated_at does not defeat it";;
  1) bad "paginate returned duplicated rows when only a volatile field differed";;
  2) bad "paginate kept requesting when only a volatile field differed (byte comparison)";;
  3) bad "the volatile-field stop did not name itself on stderr";;
  *) bad "paginate ran to the cap when only a volatile field differed";;
esac

# --- #228 keeps #62: a short non-empty page is a FULL page on a clamped host, never a stop ------
(
  . "$LIB"
  REQLOG="$T/clamp.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { echo "$1 $2" >> "$REQLOG"; case "$2" in *page=1*) printf '[{"id":1},{"id":2}]';; *page=2*) printf '[{"id":3}]';; *) printf '[]';; esac; }
  out=$(forge_api_paginate /repos/o/r/x 2>"$T/clamp.err") || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 3 ] || exit 1
  [ "$(wc -l < "$REQLOG" | tr -d " ")" = 3 ] || exit 2
  grep -q 'empty page' "$T/clamp.err" || exit 3
  grep -q 'identical page' "$T/clamp.err" && exit 4
  exit 0
)
case $? in
  0) ok "a short non-empty page still does not terminate beside the identical-page stop (#62 holds), and stderr says empty page";;
  1) bad "paginate truncated after a short page (the length < limit rule crept back in)";;
  2) bad "paginate made the wrong number of requests on a 2-1-0 sequence";;
  3) bad "the ordinary empty-page end did not say so on stderr";;
  4) bad "an ordinary end was reported as an identical-page stop";;
  *) bad "clamp case errored";;
esac

# --- #228: rows without a stable key fall back to bytes rather than stopping on nothing ----------
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=3
  forge_api() { case "$2" in *page=1*) printf '[{"x":"a"}]';; *page=2*) printf '[{"x":"b"}]';; *) printf '[]';; esac; }
  out=$(forge_api_paginate /y 2>/dev/null) || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 2 ]
)
[ $? -eq 0 ] && ok "keyless rows that differ are not read as identical (null keys are not equal keys)" \
  || bad "keyless rows stopped the paginator early (null == null read as identical)"

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

# --- #78.1: the config is resolved ONCE per process, not once per call -------------------------
# Every page used to re-run _forge_load_conf about four times (forge_host, forge_api_base,
# _forge_token), each a `git rev-parse` plus a fork per config line.
# The OBSERVABLE consequence of memoizing is that a mid-process change to the file is not picked
# up for the same root. Asserting that is the only way to distinguish a memo from no memo; an
# earlier version of this test checked that the guard variable was merely SET, which is true
# whether or not the memo is honoured, and a mutant deleting the guard survived it.
(
  . "$LIB"
  mkdir -p "$T/memo"
  _forge_root() { printf '%s' "$T/memo"; }
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=a/one\n' > "$T/memo/.forge.conf"
  unset FORGE_REPO FORGE_HOST _FORGE_CONF_PWD
  _forge_load_conf; first="${FORGE_REPO:-}"
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=b/two\n' > "$T/memo/.forge.conf"
  unset FORGE_REPO
  _forge_load_conf; second="${FORGE_REPO:-}"
  [ "$first" = a/one ] && [ -z "$second" ]
)
[ $? -eq 0 ] && ok "the config file is parsed ONCE per root, so a mid-process edit is not re-read (#78.1)" \
  || bad "config load is memoized (#78.1)"

# The memo must actually SAVE work, not merely be present. This measures it the way the round-1
# review did, with a counting `git` on PATH: an earlier version guarded on the resolved root, which
# runs `git rev-parse` BEFORE the guard, so it cost the same 25 calls it was meant to remove.
(
  M="$T/measure"; mkdir -p "$M/bin"; ( cd "$M" && git init -q . )
  printf 'FORGE_HOST=forgejo\nFORGE_API_URL=https://x/api/v1\nFORGE_REPO=o/r\nFORGE_TOKEN_ENV=TK\n' > "$M/.forge.conf"
  printf '#!/bin/sh\necho x >> "$GITLOG"\nexec %s "$@"\n' "$(command -v git)" > "$M/bin/git"; chmod +x "$M/bin/git"
  printf '#!/bin/sh\nn=$(cat "$PAGEC" 2>/dev/null||echo 0);n=$((n+1));echo $n>"$PAGEC"\nif [ $n -le 5 ]; then printf "[{\\"id\\":1}]\\n200"; else printf "[]\\n200"; fi\n' > "$M/bin/curl"
  chmod +x "$M/bin/curl"; : > "$M/gitlog"; : > "$M/pagec"
  ( export PATH="$M/bin:$PATH" GITLOG="$M/gitlog" PAGEC="$M/pagec" TK=tok
    cd "$M" && . "$LIB" && forge_api_paginate "/repos/o/r/labels" >/dev/null 2>&1 )
  n=$(wc -l < "$M/gitlog" | tr -d ' ')
  [ "$n" -le 3 ]
)
[ $? -eq 0 ] && ok "the memo actually saves work: a 6-page paginate makes <=3 git calls (#78.1)" \
  || bad "the memo saves work (a 6-page paginate should make <=3 git calls)"

# --- #78.2: the HTTP status is surfaced, not flattened into exit 22 ----------------------------
# `curl -f` collapsed every >=400 into exit 22 with no body and no status, so a caller could not
# tell 404 (an org with no labels: fine) from 401 or 500 (a real failure).
grep -qE '^[^#]*curl -f' "$LIB" && bad "no curl -f INVOCATION remains (it flattens the status)" \
  || ok "no curl -f invocation remains (it flattens the status)"
grep -q 'return 44' "$LIB" && ok "forge_api reports 404 as exit 44, a channel that survives \$( ) (#78.2)" \
  || bad "forge_api reports the status as an exit code"
# forge_issue_label must treat an org 404 as ordinary and anything else as flagged.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { case "$2" in *"/repos/"*) printf '[{"id":1,"name":"bug"}]' ;; *) return 1 ;; esac; }
  forge_api_paginate() {
    case "$1" in
      /orgs/*) return 44 ;;
      *) printf '[{"id":1,"name":"bug"}]' ;;
    esac
  }
  err=$(forge_issue_label 7 nope 2>&1 >/dev/null)
  printf '%s' "$err" | grep -q 'org-level labels could not be listed' && exit 1 || exit 0
)
[ $? -eq 0 ] && ok "an org 404 is not reported as an org-access failure (#78.2)" \
  || bad "org 404 is treated as ordinary"
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api_paginate() {
    case "$1" in
      /orgs/*) return 22 ;;
      *) printf '[{"id":1,"name":"bug"}]' ;;
    esac
  }
  err=$(forge_issue_label 7 nope 2>&1 >/dev/null)
  printf '%s' "$err" | grep -q 'org-level labels could not be listed'
)
[ $? -eq 0 ] && ok "an org 401 IS reported as an org-access failure (#78.2)" \
  || bad "org 401 is flagged"

# --- #78.3: one temp dir per process, and no leak on a signal ----------------------------------
grep -q 'mktemp)' "$LIB" && bad "no bare per-call mktemp files remain (#78.3)" \
  || ok "no bare per-call mktemp files remain (#78.3)"
# The helper must SET a variable, never print a path: a caller reading it with $( ) would run it
# in a subshell, discarding both the assignment and the trap, so every call would leak a dir.
# (The grep that used to sit here searched for the name of a function the library defines, so it
# could only fail once ten other tests already had. The behavioural cases below replace it.)
# And it must not clobber a caller's existing EXIT trap.
(
  . "$LIB"
  trap 'printf CALLER' EXIT
  _forge_tmp_init
  t=$(trap -p EXIT)
  rm -rf "${_FORGE_TMPDIR-}"          # this case makes a dir and no file, so clean it here
  case "$t" in *CALLER*) exit 0 ;; *) exit 1 ;; esac
)
[ $? -eq 0 ] && ok "a caller's existing EXIT trap is not overwritten (#78.3)" \
  || bad "caller EXIT trap preserved"

# --- #78.2 BEHAVIOURAL: drive forge_api's forgejo arm with a stubbed curl on PATH ---------------
# Round 1 of this change had only source greps here, two of which could not fail (one grepped for
# the name of a function the library defines; one was satisfied by a comment). Nine of twelve
# mutations survived. These drive the real code path.
api_case() {  # api_case <desc> <curl-output> <expected-rc> <expected-stdout>
  local d="$1" out="$2" want_rc="$3" want_body="$4" A; A="$T/api"; rm -rf "$A"; mkdir -p "$A/bin"
  printf '#!/bin/sh\nprintf %s "$CURLOUT"\n' "'%s'" > "$A/bin/curl"; chmod +x "$A/bin/curl"
  got=$( export PATH="$A/bin:$PATH" CURLOUT="$out" FORGE_HOST=forgejo FORGE_REPO=o/r \
                FORGE_API_URL=https://x/api/v1 FORGE_TOKEN_ENV=TK TK=tok
         . "$LIB" 2>/dev/null; forge_api GET /repos/o/r/x 2>/dev/null ); rc=$?
  if [ "$rc" = "$want_rc" ] && [ "$got" = "$want_body" ]; then ok "$d"
  else bad "$d (rc=$rc want $want_rc; body=[$got] want [$want_body])"; fi
}
api_case "a 200 returns the body and exit 0"            '{"a":1}
200' 0 '{"a":1}'
api_case "a 404 returns 44, the ordinary not-found code" '{"message":"Not Found"}
404' 44 '{"message":"Not Found"}'
api_case "a 401 returns 22, distinct from 404"           '{"message":"Bad credentials"}
401' 22 '{"message":"Bad credentials"}'
api_case "a 500 returns 22"                              'boom
500' 22 'boom'
api_case "an empty 200 body is returned as empty"        '
200' 0 ''
api_case "a body containing newlines survives the split" 'line1
line2
200' 0 'line1
line2'

# A TRANSPORT failure must surface curl's own exit code, not be flattened into 22. Flattening is
# precisely what `curl -f` did and what #78.2 exists to stop.
(
  A="$T/api2"; rm -rf "$A"; mkdir -p "$A/bin"
  printf '#!/bin/sh\nexit 7\n' > "$A/bin/curl"; chmod +x "$A/bin/curl"
  export PATH="$A/bin:$PATH" FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_API_URL=https://x/api/v1 \
         FORGE_TOKEN_ENV=TK TK=tok
  . "$LIB" 2>/dev/null; forge_api GET /repos/o/r/x >/dev/null 2>&1; [ $? -eq 7 ]
)
[ $? -eq 0 ] && ok "a transport failure keeps curl's own exit code, not 22 (#78.2)" \
  || bad "transport failure keeps curl's exit code"

# The EXIT trap must actually be installed when the caller has none, or #78.3's signal half does
# nothing.
# `trap - EXIT` first: a ( ) subshell REPORTS the parent script's EXIT trap, so without clearing
# it this case cannot express "the caller has none". That inheritance is also why re-installing
# a caller's trap was catastrophic: it then fires at SUBSHELL exit.
( trap - EXIT; . "$LIB"; _forge_tmp_init; t=$(trap -p EXIT); rm -rf "${_FORGE_TMPDIR-}"
  case "$t" in *_FORGE_TMPDIR*) exit 0 ;; *) exit 1 ;; esac )
[ $? -eq 0 ] && ok "an EXIT trap IS installed when the caller has none (#78.3)" \
  || bad "EXIT trap is installed when the caller has none"

# The directory is created ONCE per process, not per call.
( . "$LIB"; _forge_tmp_init; a="$_FORGE_TMPDIR"; _forge_tmp_init; b="$_FORGE_TMPDIR"
  rm -rf "$a" "$b"; [ "$a" = "$b" ] )
[ $? -eq 0 ] && ok "the temp dir is created once per process (#78.3)" || bad "temp dir created once"

# And it is removed on the NORMAL path once the last file goes, which is what stops the leak when
# the caller has its own EXIT trap and ours was therefore not installed.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { case "$2" in *page=1*) printf '[{"id":1}]';; *) printf '[]';; esac; }
  forge_api_paginate "/repos/o/r/labels" >/dev/null 2>&1
  [ -z "${_FORGE_TMPDIR-}" ] || [ ! -d "$_FORGE_TMPDIR" ]
)
[ $? -eq 0 ] && ok "the temp dir is gone after a completed paginate (#78.3 leak fix)" \
  || bad "temp dir removed after paginate"

# --- round-2 M4: the H1 fix (unique temp files) had NO behavioural coverage ---------------------
# Reverting mktemp to "paginate.$$" passed all 32 tests. $$ is the PARENT pid in every subshell, so
# two concurrent paginations shared one path and each returned the union of both streams.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  _forge_tmp_init
  forge_api() { case "$2" in *page=1*) printf '[{"n":"%s"}]' "$STREAM";; *) printf '[]';; esac; }
  ( STREAM=A; forge_api_paginate /x > "$T/outA" 2>/dev/null ) &
  ( STREAM=B; forge_api_paginate /x > "$T/outB" 2>/dev/null ) &
  wait
  a=$(jq -r '.[0].n' < "$T/outA" 2>/dev/null); b=$(jq -r '.[0].n' < "$T/outB" 2>/dev/null)
  la=$(jq 'length' < "$T/outA" 2>/dev/null); lb=$(jq 'length' < "$T/outB" 2>/dev/null)
  rm -rf "${_FORGE_TMPDIR-}"
  [ "$la" = 1 ] && [ "$lb" = 1 ] && [ "$a" != "$b" ]
)
[ $? -eq 0 ] && ok "concurrent paginations do not share a temp file (round-2 H1)" \
  || bad "concurrent paginations get their own streams"

# --- round-2 HIGH 1: a finished subshell paginate must not wedge the parent --------------------
# _forge_tmp_done rmdir's the shared dir and its `unset` cannot escape a subshell, so the parent
# could be left holding a path that no longer exists and every later call died rc=2.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_PAGINATE_MAX_PAGES=2
  forge_api() { printf '[{"id":%s}]' "${2##*page=}"; }   # distinct per page, so the CAP trips, not the #228 stop
  forge_api_paginate /x >/dev/null 2>&1          # trips the cap, leaving the dir behind
  forge_api() { printf '[]'; }
  out=$(forge_api_paginate /x 2>/dev/null)        # a SUBSHELL that finishes and cleans up
  forge_api_paginate /x >/dev/null 2>&1           # must still work in the parent
  rc=$?; rm -rf "${_FORGE_TMPDIR-}"; [ "$rc" -eq 0 ]
)
[ $? -eq 0 ] && ok "a subshell paginate does not leave the parent holding a stale temp dir" \
  || bad "parent survives a subshell paginate (round-2 HIGH)"

# --- round-2 M2: loading the config in the caller's shell must not break multi-repo -------------
(
  . "$LIB"
  mkdir -p "$T/rA" "$T/rB"; ( cd "$T/rA" && git init -q . ); ( cd "$T/rB" && git init -q . )
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/AAA\n' > "$T/rA/.forge.conf"
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/BBB\n' > "$T/rB/.forge.conf"
  forge_api() { printf '[]'; }
  cd "$T/rA"; forge_api_paginate /x >/dev/null 2>&1; a=$(forge_repo)
  cd "$T/rB"; b=$(forge_repo)
  rm -rf "${_FORGE_TMPDIR-}"
  [ "$a" = owner/AAA ] && [ "$b" = owner/BBB ]
)
[ $? -eq 0 ] && ok "a process that moves between repos re-reads the second repo's config" \
  || bad "multi-repo config re-read (round-2 M2)"

# An ENV-provided value must still win over both files, and must never be cleared by the re-read.
# It MUST cross a directory change: without one the memo returns early, the clear loop never runs,
# and the test cannot fail (round 3 found exactly that, and a mutant clearing all six keys on every
# chdir left the suite green).
(
  . "$LIB"
  mkdir -p "$T/rC" "$T/rD"; ( cd "$T/rC" && git init -q . ); ( cd "$T/rD" && git init -q . )
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/FILE\n' > "$T/rC/.forge.conf"
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/OTHER\n' > "$T/rD/.forge.conf"
  export FORGE_REPO=owner/ENV FORGE_HOST=forgejo
  cd "$T/rC"; forge_api() { printf '[]'; }; forge_api_paginate /x >/dev/null 2>&1
  cd "$T/rD"; after=$(forge_repo)                 # the chdir is what forces the re-read
  rm -rf "${_FORGE_TMPDIR-}"
  [ "$after" = owner/ENV ]
)
[ $? -eq 0 ] && ok "an environment value still wins over the file, and survives a re-read" \
  || bad "env-wins survives the multi-repo re-read"

# --- round-3: an empty repo root must not be treated as a valid root ---------------------------
# In a DELETED working directory both `git rev-parse` and the `pwd` fallback fail and root is empty,
# so "$root/.forge.conf" collapses to /.forge.conf. The guard was removed once as "dead"; it is not.
# The real trigger needs a file at the filesystem root, which a test cannot create, so this drives
# the same branch through _forge_root and asserts the consequence that IS reachable: with an empty
# root the function must return before the clear loop wipes the caller's already-loaded config.
(
  . "$LIB"
  _forge_root() { printf ''; }
  FORGE_REPO=owner/KEEP; _FORGE_FROM_FILE="FORGE_REPO"; _FORGE_CONF_PWD="/nowhere"
  _forge_load_conf
  [ "${FORGE_REPO-}" = owner/KEEP ]
)
[ $? -eq 0 ] && ok "an empty repo root returns early instead of reading /.forge.conf (round-3)" \
  || bad "empty-root guard (round-3)"

# --- round-3 HIGH: file-derived values must not reach a CHILD process --------------------------
# They were exported, so a child running in a different repo inherited the first repo's identity
# and a write from that child targeted the wrong repo on the wrong host. Pre-existing rather than
# introduced here (the pre-#78 baseline leaks identically on a direct call), but #78.1 moved the
# common paginated path onto exactly that shape. The child must read its OWN .forge.conf.
(
  . "$LIB"
  mkdir -p "$T/rE" "$T/rF"; ( cd "$T/rE" && git init -q . ); ( cd "$T/rF" && git init -q . )
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/EEE\n' > "$T/rE/.forge.conf"
  printf 'FORGE_HOST=forgejo\nFORGE_REPO=owner/FFF\n' > "$T/rF/.forge.conf"
  printf '. "%s"\nforge_repo\n' "$LIB" > "$T/child.sh"
  forge_api() { printf '[]'; }
  cd "$T/rE"; forge_api_paginate /x >/dev/null 2>&1   # the direct-call shape that used to leak
  rm -rf "${_FORGE_TMPDIR-}"
  cd "$T/rF"; [ "$(bash "$T/child.sh")" = owner/FFF ]
)
[ $? -eq 0 ] && ok "a child process in another repo reads its own config, not the parent's (round-3 H1)" \
  || bad "file-derived config leaks into a child process (round-3 H1)"

# --- milestones: a HOST capability, used by the optional forge-kit-roadmap group -------------
# Paginated, because /milestones is a LIST endpoint: a plain GET returns one server page and
# silently truncates, the class #62 fixed for issues. Terminating on an EMPTY page and not on a
# short one matters here for the same reason: the server clamps `limit`.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    case "$2" in
      *"/milestones?"*page=1*) printf '[{"id":1,"title":"Phase A","state":"open","extra":"x"},{"id":2,"title":"Phase B","state":"closed"}]' ;;
      *"/milestones?"*page=2*) printf '[{"id":3,"title":"Phase C","state":"open"}]' ;;
      *) printf '[]' ;;
    esac
  }
  out=$(forge_milestone_list) || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 3 ] || exit 1
  [ "$(printf '%s' "$out" | jq -r '.[0].title')" = "Phase A" ] || exit 2
  [ "$(printf '%s' "$out" | jq -r '.[0] | has("extra")')" = false ] || exit 3
)
case $? in
  0) ok "milestone_list pages, and narrows to id/title/state";;
  1) bad "milestone_list truncated instead of paginating";;
  2) bad "milestone_list did not return titles";;
  3) bad "milestone_list leaked fields beyond id/title/state";;
  *) bad "milestone_list errored";;
esac

# GitHub's milestone endpoints take the per-repo NUMBER; `.id` is a global id and 404s on PATCH.
# Forgejo's take `.id`. That difference is exactly what this adapter exists to hide, and it was
# found by a live close failing with 404 rather than by review.
(
  . "$LIB"
  export FORGE_HOST=github FORGE_REPO=o/r
  forge_api() {
    case "$2" in *"/milestones?"*page=1*) printf '[{"id":123456,"number":4,"title":"P","state":"open"}]' ;;
                 *) printf '[]' ;; esac
  }
  forge_api_paginate() { forge_api GET "/milestones?page=1"; }
  out=$(forge_milestone_list) || exit 9
  [ "$(printf '%s' "$out" | jq -r '.[0].id')" = 4 ]
)
[ $? -eq 0 ] && ok "milestone_list uses GitHub's per-repo number as the id" \
             || bad "milestone_list used GitHub's global id, which 404s on PATCH"

(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    case "$2" in *"/milestones?"*page=1*) printf '[{"id":9,"title":"P","state":"open"}]' ;;
                 *) printf '[]' ;; esac
  }
  out=$(forge_milestone_list) || exit 9
  [ "$(printf '%s' "$out" | jq -r '.[0].id')" = 9 ]
)
[ $? -eq 0 ] && ok "and Forgejo's own id, which has no number field" \
             || bad "milestone_list broke Forgejo's id"

# Closing by TITLE, because the roadmap names phases and only the host knows ids.
(
  . "$LIB"
  REQLOG="$T/ms.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    echo "$1 $2" >> "$REQLOG"
    case "$2" in *"/milestones?"*page=1*) printf '[{"id":7,"title":"Phase A","state":"open"}]' ;;
                 *) printf '[]' ;; esac
  }
  forge_milestone_close "Phase A" || exit 1
  grep -q 'PATCH /repos/o/r/milestones/7' "$REQLOG" || exit 2
)
case $? in
  0) ok "milestone_close resolves the title to an id and PATCHes it";;
  1) bad "milestone_close failed on a title that exists";;
  *) bad "milestone_close did not PATCH the resolved id";;
esac

# A close that quietly did nothing would let a roadmap say `done` while the milestone stayed open,
# which is exactly the drift the roadmap group's rule 3 exists to catch.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { printf '[]'; }
  forge_milestone_close "No Such Phase" 2>/dev/null
  [ "$?" -eq 2 ]
)
[ $? -eq 0 ] && ok "closing an unknown title FAILS rather than silently doing nothing" \
             || bad "closing an unknown title silently succeeded"

# Issues carry the milestone TITLE, and pull requests must not appear: the roadmap rule is about
# tickets. Forgejo's issues endpoint returns PRs too, which is why forge_issue_list filters them.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() {
    case "$2" in
      *"/issues?"*page=1*) printf '[{"number":7,"milestone":{"title":"Phase A"}},{"number":8,"milestone":null},{"number":9,"pull_request":{},"milestone":null}]' ;;
      *) printf '[]' ;;
    esac
  }
  out=$(forge_issue_milestone_list) || exit 9
  [ "$(printf '%s' "$out" | jq 'length')" = 2 ] || exit 1
  [ "$(printf '%s' "$out" | jq -r '.[0].milestone')" = "Phase A" ] || exit 2
  [ "$(printf '%s' "$out" | jq -r '.[1].milestone')" = "null" ] || exit 3
)
case $? in
  0) ok "issue_milestone_list flattens the title, keeps null, and excludes PRs";;
  1) bad "issue_milestone_list included a pull request";;
  2) bad "issue_milestone_list did not flatten milestone.title";;
  3) bad "issue_milestone_list did not report an unassigned issue as null";;
  *) bad "issue_milestone_list errored";;
esac

# --- #131.1: env-wins must survive a chdir -----------------------------------------------------
# The tracking recorded the KEY alone, so a value the CALLER exported after a load that had set the
# same key from a file was cleared on the next chdir. That contradicts the env-wins contract stated
# in the header and in references/local-auth.md, and it fails loudly: forge_repo then cannot parse
# owner/repo from an empty remote.
(
  . "$LIB"
  mkdir -p "$T/c1" "$T/c2"
  ( cd "$T/c1" && git init -q . && printf 'FORGE_REPO=from/file\n' > .forge.conf ) >/dev/null 2>&1
  ( cd "$T/c2" && git init -q . ) >/dev/null 2>&1
  cd "$T/c1"; forge_repo >/dev/null 2>&1          # the file sets FORGE_REPO; the key is tracked
  export FORGE_REPO=owner/explicit                # the caller's own choice, AFTER that load
  cd "$T/c2"
  [ "$(forge_repo 2>/dev/null)" = owner/explicit ]
)
[ $? -eq 0 ] && ok "an export made after a file load survives a chdir (env wins)" \
             || bad "the caller's own export was cleared on chdir (#131.1)"

# ...and the file's own value is still cleared, or a process moving between repos keeps the first
# repo's identity, which is what the tracking exists to prevent.
(
  . "$LIB"
  mkdir -p "$T/d1" "$T/d2"
  ( cd "$T/d1" && git init -q . && printf 'FORGE_REPO=first/repo\n' > .forge.conf ) >/dev/null 2>&1
  ( cd "$T/d2" && git init -q . && printf 'FORGE_REPO=second/repo\n' > .forge.conf ) >/dev/null 2>&1
  cd "$T/d1"; [ "$(forge_repo)" = first/repo ] || exit 1
  cd "$T/d2"; [ "$(forge_repo)" = second/repo ]
)
[ $? -eq 0 ] && ok "and a file-set value is still replaced by the next repo's file" \
             || bad "a file-set value leaked across a chdir"

# --- #131.2: the stale-tmpdir check is load-bearing on its own ---------------------------------
# The existing case only reverted to green when BOTH halves of the fix were reverted together, so
# neither half had its own mutant. This reaches the wedge WITHOUT going through the page cap.
(
  . "$LIB"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { printf '[]'; }
  _forge_tmp_init || exit 9
  rm -rf "$_FORGE_TMPDIR"                          # a finished subshell removed the shared dir
  _forge_tmp_init || exit 1                        # must notice and make a new one
  [ -d "$_FORGE_TMPDIR" ]
)
[ $? -eq 0 ] && ok "a stale _FORGE_TMPDIR is re-created without going through the page cap" \
             || bad "the -d check is not independently exercised (#131.2)"

# --- #129: forge_issue_edit replaces an issue BODY on either host ------------------------------
# The decision-brief skill rewrites the body rather than commenting, because a reader triaging a
# batch of tickets reads bodies and not comments. Both hosts PATCH the issue, so there is no host
# branch to get wrong; what there IS to get wrong is sending the body as anything but a JSON
# string, which is why the assertion reads the payload back through jq rather than grepping it.
(
  . "$LIB"
  REQLOG="$T/edit.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$REQLOG"; printf '{}'; }
  body='line one
line "two" with $quotes and a `backtick`'
  forge_issue_edit 44 "$body" || exit 9
  read -r m path <<< "$(cut -f1,2 "$REQLOG")"
  [ "$m" = PATCH ] || exit 1
  [ "$path" = /repos/o/r/issues/44 ] || exit 2
  sent=$(cut -f3 "$REQLOG" | jq -r .body)
  [ "$sent" = "$body" ] || exit 3
)
case $? in
  0) ok "issue_edit PATCHes the issue and sends the body as a JSON string, newlines and quotes intact";;
  1) bad "issue_edit did not use PATCH";;
  2) bad "issue_edit addressed the wrong path";;
  3) bad "issue_edit mangled the body (multiline or quoting lost)";;
  *) bad "issue_edit errored or does not exist";;
esac

# A rewrite is destructive: the old body is gone. Dry run must send nothing at all.
(
  . "$LIB"
  REQLOG="$T/edit2.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_DRY_RUN=1
  forge_api() { echo "$1 $2" >> "$REQLOG"; printf '{}'; }
  forge_issue_edit 44 "new body" 2>/dev/null || exit 1
  [ ! -s "$REQLOG" ]
)
[ $? -eq 0 ] && ok "and FORGE_DRY_RUN sends nothing, because a body rewrite cannot be undone" \
             || bad "issue_edit sent a request under FORGE_DRY_RUN"

# Refusing an empty body is the difference between a bug and an erased ticket.
(
  . "$LIB"
  REQLOG="$T/edit3.log"; : > "$REQLOG"
  export FORGE_HOST=forgejo FORGE_REPO=o/r
  forge_api() { echo "$1 $2" >> "$REQLOG"; printf '{}'; }
  forge_issue_edit 44 "" 2>/dev/null && exit 1
  [ ! -s "$REQLOG" ]
)
[ $? -eq 0 ] && ok "an empty body is refused and nothing is sent (a rewrite would erase the ticket)" \
             || bad "issue_edit accepted an empty body"


# --- #229: the three silenced writers SPEAK on a 404, and only on a 404 ---------------------------
# forge_api's 404 arm is quiet on purpose (an org with no labels is an ordinary 404 for a READ),
# and the three writers redirect the body to /dev/null, so under v16 a comment to a mistyped
# issue number produced nothing on either stream and rc 44. A caller reading silence as success
# could not tell a landed write from a miss. Every other non-zero code already prints a line
# (forge_api on rc 22, curl on transport, gh on GitHub), so those get NO second line.
w229() {  # w229 <label> <rc-from-stub> <expect-rc> <fn> <args...>
  local label="$1" stubrc="$2" wantrc="$3" fn="$4"; shift 4
  (
    . "$LIB"
    export FORGE_HOST=forgejo FORGE_REPO=o/r
    STUBRC="$stubrc"
    forge_api() { [ "$STUBRC" = 22 ] && echo "forge-lib: HTTP 500 from $1 $2" >&2; return "$STUBRC"; }
    out=$("$fn" "$@" 2>"$T/w.err"); rc=$?
    [ "$rc" = "$wantrc" ] || exit 1
    [ -z "$out" ] || exit 2
    case "$STUBRC" in
      0)  [ ! -s "$T/w.err" ] || exit 3 ;;
      44) [ "$(wc -l < "$T/w.err" | tr -d " ")" = 1 ] || exit 4
          grep -q "$fn" "$T/w.err" || exit 5
          grep -q 'HTTP 404' "$T/w.err" || exit 5
          grep -q "#${1}" "$T/w.err" || exit 6 ;;
      22) [ "$(wc -l < "$T/w.err" | tr -d " ")" = 1 ] || exit 7
          grep -q "$fn" "$T/w.err" && exit 7 ;;
    esac
    exit 0
  )
  case $? in
    0) ok "$label";;
    1) bad "$label (exit code not propagated unchanged)";;
    2) bad "$label (stdout was not empty)";;
    3) bad "$label (success printed something on stderr)";;
    4) bad "$label (404 did not print exactly one stderr line)";;
    5) bad "$label (the 404 line does not name the function and HTTP 404)";;
    6) bad "$label (the 404 line does not name the issue number)";;
    7) bad "$label (a failure that already spoke got a second line)";;
    *) bad "$label (errored)";;
  esac
}
w229 "forge_issue_comment stays silent on success (#229)"           0  0  forge_issue_comment 999 body
w229 "forge_issue_comment names a 404 on stderr, rc 44 (#229)"       44 44 forge_issue_comment 999 body
w229 "forge_issue_comment adds no second line on rc 22 (#229)"       22 22 forge_issue_comment 999 body
w229 "forge_issue_close stays silent on success (#229)"             0  0  forge_issue_close 999
w229 "forge_issue_close names a 404 on stderr, rc 44 (#229)"         44 44 forge_issue_close 999
w229 "forge_issue_close adds no second line on rc 22 (#229)"         22 22 forge_issue_close 999
w229 "forge_issue_edit stays silent on success (#229)"              0  0  forge_issue_edit 999 new
w229 "forge_issue_edit names a 404 on stderr, rc 44 (#229)"          44 44 forge_issue_edit 999 new
w229 "forge_issue_edit adds no second line on rc 22 (#229)"          22 22 forge_issue_edit 999 new

# --- #245: forge_issue_milestone, the missing WRITE half of the milestone primitives -----------
# The kit could list, create and close a milestone and list a milestone's issues, and could not put
# a ticket in one, so every phase move went through `gh issue edit --milestone` and was GitHub-only.
# Two host differences, both proved at source by the gate: the id to send is the per-repo NUMBER on
# GitHub and the `id` on Forgejo (forge_milestone_list already normalises them), and the CLEAR form
# is `null` on GitHub but the literal `0` on Forgejo, whose handler skips a nil field and returns
# SUCCESS having changed nothing, which is the #229 class of silence.
ms_stub() {  # ms_stub <host>: a forge_api that answers the milestone list and logs every request
  cat <<STUB
    forge_api() {
      echo "\$1 \$2 \${3-}" >> "$T/ms.log"
      case "\$1 \$2" in
        "GET /repos/o/r/milestones"*) printf '[{"id":7,"title":"Phase A"},{"id":9,"title":"Phase B"}]' ;;
        *) : ;;
      esac
    }
STUB
}
ms_run() {  # ms_run <host> <args...>: run forge_issue_milestone with the stub; sets RC and MSLOG
  : > "$T/ms.log"
  RC=$( ( . "$LIB"; export FORGE_HOST="$1" FORGE_REPO=o/r; shift
          eval "$(ms_stub)"
          forge_issue_milestone "$@" >/dev/null 2>"$T/ms.err"; echo $? ) )
  MSLOG="$(cat "$T/ms.log")"; MSERR="$(cat "$T/ms.err")"
}
ms_run forgejo 12 "Phase A"
expect "forgejo: setting a phase PATCHes the issue with the milestone id" 0 "$RC"
case "$MSLOG" in *'"milestone":7'*) ok "and the payload carries the id 7, as a number" ;; *) bad "payload: $MSLOG" ;; esac
# The SET payload carries whatever _forge_milestone_id returned, and nothing else: WHICH id that
# is per host is forge_milestone_list's contract (it normalises GitHub's per-repo number and
# Forgejo's id into one field, and its own comment records the live 404 that taught it). This
# function must not re-derive it, so the case stubs the resolver and asserts the passthrough. The
# github LIST path cannot be driven from here at all: forge_api_paginate shells out to `gh` there
# rather than through forge_api, which is why the suite has always said the github branches are
# exercised by real use.
RC=$( ( . "$LIB"; export FORGE_HOST=forgejo FORGE_REPO=o/r
        : > "$T/ms3.log"
        forge_api() { echo "$1 $2 ${3-}" >> "$T/ms3.log"; }
        _forge_milestone_id() { printf '%s' 4242; }
        forge_issue_milestone 12 "Phase A" >/dev/null 2>&1; echo $? ) )
expect "the SET payload carries exactly what the resolver returned" 0 "$RC"
case "$(cat "$T/ms3.log")" in *'"milestone":4242'*) ok "and never re-derives the id itself" ;; *) bad "passthrough payload: $(cat "$T/ms3.log")" ;; esac
ms_run forgejo 12 ""
expect "forgejo: clearing a phase succeeds" 0 "$RC"
case "$MSLOG" in *'"milestone":0'*) ok "and sends the literal 0, which is the only form Forgejo acts on" ;; *) bad "forgejo clear payload: $MSLOG" ;; esac
ms_run github 12 ""
expect "github: clearing a phase succeeds" 0 "$RC"
case "$MSLOG" in *'"milestone":null'*) ok "and sends null, the only form GitHub resolves" ;; *) bad "github clear payload: $MSLOG" ;; esac
ms_run forgejo 12 "Phase Z"
expect "an unresolvable title refuses with rc 2" 2 "$RC"
case "$MSERR" in *"Phase Z"*) ok "and names the title" ;; *) bad "refusal message: $MSERR" ;; esac
case "$MSLOG" in *PATCH*) bad "a PATCH was sent despite the refusal" ;; *) ok "and sends no PATCH" ;; esac
# The dry-run guard runs BEFORE the resolution, or every title is unresolvable under it: paginate
# returns a literal [] in dry-run, so a real title would take the refusal path (gate round 1).
RC=$( ( . "$LIB"; export FORGE_HOST=forgejo FORGE_REPO=o/r FORGE_DRY_RUN=1
        forge_api() { echo "REQUEST" >> "$T/ms2.log"; }
        : > "$T/ms2.log"
        forge_issue_milestone 12 "Phase A" >/dev/null 2>"$T/ms2.err"; echo $? ) )
expect "a dry-run SET prints the intended change instead of refusing a real title" 0 "$RC"
[ -s "$T/ms2.log" ] && bad "dry-run sent a request" || ok "and sends nothing at all"
grep -q 'Phase A' "$T/ms2.err" && ok "and names the phase it would set" || bad "dry-run said nothing useful"
# The 404 and rc 22 rows run on the CLEAR path, which resolves nothing, because w229's stub answers
# every call with one rc and a resolving writer would consume it on the GET (gate round 1, AC 5).
w229 "forge_issue_milestone names a 404 on stderr, rc 44 (#245)"     44 44 forge_issue_milestone 999 ""
w229 "forge_issue_milestone stays silent on success (#245)"           0  0 forge_issue_milestone 999 ""
w229 "forge_issue_milestone adds no second line on rc 22 (#245)"     22 22 forge_issue_milestone 999 ""
# Review round 1: two shapes where the writer acted on an answer it should have refused.
# An invalid FORGE_HOST makes forge_host REFUSE and print nothing, so a catch-all arm reads the
# refusal as "not forgejo" and sends GitHub's wire form; and a resolver that yields a JSON null or
# a non-numeric token turned a SET into a CLEAR, or sent an empty body, instead of refusing.
RC=$( ( . "$LIB"; export FORGE_HOST=gitea FORGE_REPO=o/r
        : > "$T/ms4.log"; forge_api() { echo "SENT $3" >> "$T/ms4.log"; }
        forge_issue_milestone 12 "" >/dev/null 2>&1; echo $? ) )
expect "an invalid FORGE_HOST refuses rather than guessing a wire form" 2 "$RC"
[ -s "$T/ms4.log" ] && bad "it sent a payload for an unknown host" || ok "and sends nothing"
RC=$( ( . "$LIB"; export FORGE_HOST=forgejo FORGE_REPO=o/r
        : > "$T/ms5.log"; forge_api() { echo "SENT ${3-}" >> "$T/ms5.log"; }
        _forge_milestone_id() { printf '%s' null; }
        forge_issue_milestone 12 "Phase A" >/dev/null 2>&1; echo $? ) )
expect "a resolver yielding a JSON null refuses instead of CLEARING the field" 2 "$RC"
case "$(cat "$T/ms5.log")" in *milestone*) bad "a null id reached the payload: $(cat "$T/ms5.log")" ;; *) ok "and sends no payload" ;; esac
RC=$( ( . "$LIB"; export FORGE_HOST=forgejo FORGE_REPO=o/r
        : > "$T/ms6.log"; forge_api() { echo "SENT ${3-}" >> "$T/ms6.log"; }
        _forge_milestone_id() { printf '%s' 'abc'; }
        forge_issue_milestone 12 "Phase A" >/dev/null 2>&1; echo $? ) )
expect "a non-numeric id refuses instead of sending an empty body" 2 "$RC"
[ -s "$T/ms6.log" ] && bad "it sent something for a non-numeric id" || ok "and sends nothing"

# --- #237: the 404 line survives a `set -e` caller. `forge_api ... >/dev/null; rc=$?` let errexit
# fire on the forge_api line before rc=$? ran, so the one shell mode forge_api's own comment
# designs for got the pre-#229 silence back. The capture is now `rc=0; ... || rc=$?`.
e237() {  # e237 <label> <stub-rc> <fn> <args...>: run the writer under `bash -c 'set -e; ...'`
  local label="$1" stubrc="$2" fn="$3"; shift 3
  local out; out="$(FORGE_HOST=forgejo FORGE_REPO=o/r STUBRC="$stubrc" bash -c '
    set -e; . "'"$LIB"'"; forge_api() { return "$STUBRC"; }; '"$fn"' "$@"; echo "rc=$?"' _ "$@" 2>"$T/e.err")"; local rc=$?
  case "$stubrc" in
    0)  [ "$out" = "rc=0" ] && [ ! -s "$T/e.err" ] && ok "$label" || bad "$label (out='$out' err='$(cat "$T/e.err")')" ;;
    44) [ "$rc" = 44 ] && grep -q "$fn" "$T/e.err" && grep -q 'HTTP 404' "$T/e.err" && ok "$label" || bad "$label (rc=$rc err='$(cat "$T/e.err")')" ;;
    *)  bad "$label (unhandled stub rc $stubrc: a case that asserts nothing counts nothing)" ;;
  esac
}
e237 "forge_issue_comment under set -e: silent success, rc 0 (#237)"    0  forge_issue_comment 7 b
e237 "forge_issue_comment under set -e: the 404 line and rc 44 (#237)"  44 forge_issue_comment 7 b
e237 "forge_issue_close under set -e: silent success (#237)"             0  forge_issue_close 7
e237 "forge_issue_close under set -e: the 404 line and rc 44 (#237)"    44 forge_issue_close 7
e237 "forge_issue_edit under set -e: silent success (#237)"              0  forge_issue_edit 7 new
e237 "forge_issue_edit under set -e: the 404 line and rc 44 (#237)"     44 forge_issue_edit 7 new

# --- forge_host decides by the URL's authority, never by a glob (#212) ---
echo "== forge_host: the host slot only =="
hostof() {  # hostof <origin-url> [FORGE_API_URL]: forge_host in a fresh repo with that origin
  local d; d="$(mktemp -d "$T/fh.XXXXXX")"
  ( cd "$d" && git init -q . && git remote add origin "$1" && . "$LIB" && FORGE_API_URL="${2:-}" forge_host 2>/dev/null; echo "rc=$?" )
}
for u in 'https://git:git@github.com/o/r' 'ssh://git@github.com:22/o/r' 'git@github.com:o/r' 'github.com:o/r' 'https://github.com/o/r' 'https://GitHub.com/o/r' 'noreply@github.com:o/r'; do
  r="$(hostof "$u" https://forge.example)"
  [ "$r" = "$(printf 'github\nrc=0')" ] && ok "github.com in the host slot is github: $u" || bad "not github: $u -> $r"
done
for u in 'https://evil.internal/x/y?z=@github.com/' 'https://evil.internal?@github.com/o/r' 'https://evil.internal#@github.com/o/r' 'https://github.com.evil.internal/o/r' 'ssh://[::1]/o/r' 'https://forgejo.example:3000/o/r'; do
  r="$(hostof "$u" https://forge.example)"
  [ "$r" = "$(printf 'forgejo\nrc=0')" ] && ok "github.com outside the host slot is not github: $u" || bad "misclassified: $u -> $r"
done
r="$(hostof 'https://evil.internal/x/y?z=@github.com/')"
[ "$r" = "$(printf 'github\nrc=0')" ] && ok "with no FORGE_API_URL the non-github default is still github (unchanged)" || bad "default changed: $r"
# The mutant: the v15 glob back in place must fail the crafted URL.
MUT="$T/forge-lib-mut.sh"; sed 's|^    github.com.ssh.github.com) echo github ;;.*$|    *) case "$url" in *://github.com/*\|*://*@github.com/*\|git@github.com:*) echo github; return 0;; esac; if [ -n "${FORGE_API_URL:-}" ]; then echo forgejo; else echo github; fi; return 0 ;;|' "$LIB" > "$MUT"
grep -q '^    github.com|ssh.github.com) echo github ;;' "$LIB" && ok "mutant ledger: the host compare is exact" || bad "mutant ledger: compare line not found"
cmp -s "$LIB" "$MUT" && bad "mutant ledger: the sed did not apply" || ok "mutant ledger: the mutant differs from the lib"
d="$(mktemp -d "$T/fh.XXXXXX")"; r="$( cd "$d" && git init -q . && git remote add origin 'https://evil.internal/x/y?z=@github.com/' && . "$MUT" && FORGE_API_URL=https://forge.example forge_host 2>/dev/null )"
[ "$r" = github ] && ok "mutant: the v15 glob classifies the crafted URL as github (the case can fail)" || bad "mutant did not misclassify (got '$r')"

echo "== _forge_token: the credential host is the authority, port kept =="
tokhost() {  # tokhost <FORGE_API_URL>: the host= line _forge_token hands to git credential fill
  rm -f "$T/credhost.txt"   # a stale capture must never satisfy the next case (review)
  ( . "$LIB"; export FORGE_API_URL="$1" FORGE_TOKEN_ENV=NOPE_UNSET FORGE_NO_GIT_CREDENTIALS=0
    git() { if [ "$1" = credential ]; then sed -n 's/^host=//p' > "$T/credhost.txt"; printf 'password=x\n'; else command git "$@"; fi; }
    _forge_token >/dev/null 2>&1; cat "$T/credhost.txt" )
}
expect "a plain instance URL asks for its host" forgejo.example "$(tokhost https://forgejo.example/api/v1)"
expect "a port is kept in the credential request" forgejo.example:3000 "$(tokhost https://forgejo.example:3000/)"
expect "a fragment cannot smuggle github.com into the request" evil.internal "$(tokhost 'https://evil.internal#@github.com')"
expect "nor a query" evil.internal "$(tokhost 'https://evil.internal?@github.com')"
expect "userinfo is stripped from the request" forgejo.example "$(tokhost 'https://git:git@forgejo.example/')"
expect "the host's case is preserved: git's credential store keys on the spelling as given" Forgejo.Example:3000 "$(tokhost https://Forgejo.Example:3000/)"
expect "a scheme-less FORGE_API_URL still yields its host with the port" forgejo.example:3000 "$(tokhost forgejo.example:3000/api/v1)"

echo "== _forge_url_host: the fixture table =="
uh() { ( . "$LIB"; _forge_url_host "$@" ); }
expect "bracketed IPv6 with a port, host only" '[::1]' "$(uh 'https://[::1]:8080/o/r')"
expect "bracketed IPv6 with a port, kept" '[::1]:8080' "$(uh 'https://[::1]:8080/o/r' keep-port)"
expect "scp form with a bracketed host" '[::1]' "$(uh 'git@[::1]:o/r')"
expect "two @ before the brackets: the last one ends the user" '[::1]' "$(uh 'a@b@[::1]:o/r')"
expect "brackets in the PATH of a plain scp URL do not move the host" 'github.com' "$(uh 'git@github.com:o/r@[x]:y')"
expect "a slash before the first colon is a local path, brackets or not" '' "$(uh 'a/b@[::1]:o/r')"
expect "file:// has an empty authority" '' "$(uh 'file:///x')"
expect "an absolute path with a colon is not scp form" '' "$(uh '/tmp/a:b/o/r')"
expect "a relative path is not scp form" '' "$(uh './host:o/r')"
expect "a scheme URL with no path" 'host' "$(uh 'ssh://host:2222')"
expect "a password containing @ : the last @ ends the userinfo" 'host' "$(uh 'ssh://user:p@ss@host/o/r')"
expect "ssh.github.com is GitHub" github "$(hostof 'ssh://git@ssh.github.com:443/o/r' https://forge.example | head -1)"

# --- #216: forge_repo cuts the slug after the SAME authority _forge_url_host isolates ---------
# v16 kept a second parser (`*://*/*` and `*:*/*` globs) that disagreed with the host helper on
# the shapes #212 was written for: `git@[::1]:o/r` printed `:1]:o/r`. Now one authority
# isolation serves both. A refusal names the URL with scheme-form userinfo redacted, because a
# remote can carry `user:token@` and the message lands in a hook's output (#229 review).
echo "== forge_repo: one authority isolation (#216) =="
repoof() {  # repoof <origin-url>: forge_repo in a fresh repo with that origin; stdout then rc
  local d; d="$(mktemp -d "$T/fr.XXXXXX")"
  ( cd "$d" && git init -q . && git remote add origin "$1" && . "$LIB" && forge_repo 2>"$d/err"; echo "rc=$?"; cat "$d/err" )
}
for u in 'ssh://git@github.com:22/o/r' 'https://github.com/o/r.git' 'git@github.com:o/r.git' 'ssh://git@[::1]:22/o/r' 'https://user:pa:ss@h/o/r' 'ssh://host:2222/o/r'; do
  expect "baseline slug unchanged: $u" "$(printf 'o/r\nrc=0')" "$(repoof "$u")"
done
expect "scp form with a bracketed IPv6 host cuts after ]: (was :1]:o/r)" "$(printf 'o/r\nrc=0')" "$(repoof 'git@[::1]:o/r')"
expect "a query is stripped from a scheme-form slug (new on v17)" "$(printf 'o/r\nrc=0')" "$(repoof 'https://h/o/r?x=1')"
expect "a fragment is stripped from a scheme-form slug (new on v17)" "$(printf 'o/r\nrc=0')" "$(repoof 'https://h/o/r#frag')"
expect "query and fragment together" "$(printf 'o/r\nrc=0')" "$(repoof 'https://h/o/r?x=1#f')"
expect "the scp form has no query syntax: bytes are kept" "$(printf 'o/r?legacy\nrc=0')" "$(repoof 'git@host:o/r?legacy')"
expect "a trailing slash and .git are both stripped, in that order" "$(printf 'o/r\nrc=0')" "$(repoof 'git@host:o/r.git/')"
r="$(repoof '/path/with:colon/o/r')"
case "$r" in "rc=2"*"cannot parse owner/repo from remote '/path/with:colon/o/r'"*"a local path has no host"*) ok "a local path with a colon is refused, naming the real path (git-clone(1): a slash before the first colon is never scp form)";; *) bad "colon path: $r";; esac
case "$r" in *"remote 'colon/o/r'"*) bad "the refusal named a fabricated sub-path";; *) ok "the refusal does not name a fabricated sub-path";; esac
r="$(repoof './o/r')"
case "$r" in "rc=2"*"cannot parse owner/repo from remote './o/r'"*) ok "a relative path is refused as before";; *) bad "relative path: $r";; esac
r="$(repoof 'file:///srv/git/o/r')"
case "$r" in "rc=2"*"file:///srv/git/o/r"*) ok "file:// has an empty authority and is refused naming the URL";; *) bad "file://: $r";; esac
r="$(repoof 'git@host:/o/r')"
case "$r" in "rc=2"*) ok "git@host:/o/r stays refused on v17 (scoped out of #216)";; *) bad "git@host:/o/r: $r";; esac
r="$(repoof 'https://user:s3cret@h/x')"
case "$r" in *s3cret*) bad "a refusal printed the credential from the remote URL";; "rc=2"*) ok "a refusal redacts scheme-form userinfo (a remote can carry user:token@)";; *) bad "single-segment refusal: $r";; esac
r="$(repoof 'https://user:p@ss@h/x')"
case "$r" in *"remote 'https://***@h/x'"*) ok "the redaction cuts at the LAST @ of the authority, so a password containing @ leaves no tail (review round 1)";; *) bad "password with @: $r";; esac
r="$(repoof 'https://h/x@y')"
case "$r" in *"remote 'https://h/x@y'"*) ok "an @ in the path is not userinfo and is not redacted";; *) bad "@ in path: $r";; esac
r="$(repoof 'https://h/a/b/c')"
case "$r" in "rc=2"*"not a plain owner/repo"*) ok "three segments are still refused as not a plain owner/repo";; *) bad "three segments: $r";; esac
# The mutant: the bracket-aware scp cut replaced by a first-colon cut must print :1]:o/r.
MUT216="$T/forge-lib-mut216.sh"; sed 's|^\( *\)\\\[\*\\\]\*) path="${url#\*\\\]:}" ;; *# bracket-aware cut.*$|\1\\[*\\]*) path="${url#*:}" ;;|' "$LIB" > "$MUT216"
grep -q '# bracket-aware cut: the #216 mutant replaces this line$' "$LIB" && ok "mutant ledger (#216): the bracket-aware cut line exists" || bad "mutant ledger (#216): cut line not found"
cmp -s "$LIB" "$MUT216" && bad "mutant ledger (#216): the sed did not apply" || ok "mutant ledger (#216): the mutant differs from the lib"
d="$(mktemp -d "$T/fr.XXXXXX")"; r="$( cd "$d" && git init -q . && git remote add origin 'git@[::1]:o/r' && . "$MUT216" && forge_repo 2>/dev/null )"
[ "$r" = ':1]:o/r' ] && ok "mutant (#216): a first-colon cut prints :1]:o/r, so the bracket case can fail" || bad "mutant (#216) did not misbehave (got '$r')"

# --- #235: an scp remote whose PATH carries an @ is refused, never printed as a slug ----------
# git reads `x-access-token:TOKEN@host:o/r` as host x-access-token and path TOKEN@host:o/r, so no
# slug forge-lib could print names a clonable repository, and the string a user pasted as a token
# would otherwise be interpolated into every API request path this library builds. Refused, with
# the remote redacted at its last @; _forge_url_host is unchanged (it already returns git's read).
echo "== forge_repo: an @ in the scp path is refused (#235) =="
r="$(repoof 'x-access-token:TOKEN@host:o/r')"
case "$r" in "rc=2"*"remote '***@host:o/r'"*) ok "a userinfo-shaped scp remote is refused, redacted at the last @ (#235)";; *) bad "userinfo-shaped scp remote: $r";; esac
case "$r" in *TOKEN*) bad "the token reached a stream";; *) ok "and the token appears on neither stream";; esac
r="$(repoof 'user:p@ss@host:o/r')"
case "$r" in "rc=2"*"remote '***@host:o/r'"*) ok "a password containing @ is redacted whole";; *) bad "password with @: $r";; esac
case "$r" in *p@ss*) bad "the password reached a stream";; *) ok "and the password appears on neither stream";; esac
r="$(repoof 'user@host:o/r@x')"
case "$r" in "rc=2"*"remote '***@x'"*) ok "an @ in the scp path alone is refused, redacted at the last @";; *) bad "@ in scp path: $r";; esac
expect "git@host:o/r is unchanged" "$(printf 'o/r\nrc=0')" "$(repoof 'git@host:o/r')"
expect "a@b@host:o/r (the last @ ends the user, as ssh reads it) is unchanged" "$(printf 'o/r\nrc=0')" "$(repoof 'a@b@host:o/r')"
expect "_forge_url_host reads the repro as git does: host x-access-token" 'x-access-token' "$(uh 'x-access-token:TOKEN@host:o/r')"
MUT235="$T/forge-lib-mut235.sh"; sed '/# an @ in the scp path is a credential shape, refuse (#235)$/d' "$LIB" > "$MUT235"
grep -q '# an @ in the scp path is a credential shape, refuse (#235)$' "$LIB" && ok "mutant ledger (#235): the refusal line exists" || bad "mutant ledger (#235): refusal line not found"
cmp -s "$LIB" "$MUT235" && bad "mutant ledger (#235): the sed did not apply" || ok "mutant ledger (#235): the mutant differs from the lib"
d="$(mktemp -d "$T/fr.XXXXXX")"; r="$( cd "$d" && git init -q . && git remote add origin 'x-access-token:TOKEN@host:o/r' && . "$MUT235" && forge_repo 2>/dev/null )"
[ "$r" = 'TOKEN@host:o/r' ] && ok "mutant (#235): without the refusal the token is printed as a slug again" || bad "mutant (#235) did not misbehave (got '$r')"

echo ""
echo "forge-lib tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
