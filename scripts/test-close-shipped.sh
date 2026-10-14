#!/usr/bin/env bash
# Contract test for release-automation/assets/close-shipped.sh (issue #496).
#
# close-shipped.sh closes the tickets a release shipped (or, with --report, lists the ones still
# open). Every case runs it as a subprocess inside a throwaway git repository, with a PATH-shim
# `gh` that serves issue JSON and comment arrays from a per-test state directory, flips an issue
# to closed on the close PATCH, appends a comment on the POST, answers 403, 404 or 500 when a
# fixture file says so, and logs every call. A write is logged as `WRITE <METHOD> <n> <body>`, so
# "no write" is a grep, and a read of an issue is visible as its path. A path with an empty
# owner/repo (`repos//`) gets the 404 GitHub really answers it with. One row uses a `curl` shim
# to prove the Forgejo 404 arm (forge_api's rc 44).
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
CS="$ROOT/plugins/forge-kit-devops/skills/release-automation/assets/close-shipped.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/      | /'; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
S="$GHSTUB"
echo "gh $*" >> "$S/log"
if [ "${1-}" = release ]; then [ "${2-}" = view ] && exit 1; exit 0; fi
shift
method=GET path=""
while [ $# -gt 0 ]; do
  case "$1" in -X) method="$2"; shift ;; --paginate) ;; --input) shift ;; *) path="$1" ;; esac
  shift
done
case "$path" in   # an empty owner/repo is what GitHub answers with a 404 (review M1)
  *repos//*) echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
case "$path" in
  */issues/*/comments) n="${path%/comments}"; n="${n##*/}"; kind=comments ;;
  */issues/*)          n="${path##*/}"; kind=issue ;;
  *) echo "gh stub: unexpected path $path" >&2; exit 3 ;;
esac
op="$method-$kind"
if [ -f "$S/fail/$op-$n" ]; then
  code="$(cat "$S/fail/$op-$n")"
  echo '{"message":"stubbed failure"}'; echo "gh: stubbed (HTTP $code)" >&2; exit 1
fi
case "$op" in
  GET-issue)
    [ -f "$S/issues/$n.json" ] || { echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    cat "$S/issues/$n.json" ;;
  GET-comments) if [ -f "$S/comments/$n.json" ]; then cat "$S/comments/$n.json"; else echo '[]'; fi ;;
  POST-comments)
    body="$(cat)"; echo "WRITE POST $n $body" >> "$S/log"
    [ -f "$S/comments/$n.json" ] || echo '[]' > "$S/comments/$n.json"
    jq -c --argjson c "$body" '. + [$c]' "$S/comments/$n.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/comments/$n.json"
    echo '{}' ;;
  PATCH-issue)
    body="$(cat)"; echo "WRITE PATCH $n $body" >> "$S/log"
    jq -c '.state = "closed"' "$S/issues/$n.json" > "$S/i.tmp" && mv "$S/i.tmp" "$S/issues/$n.json"
    echo '{}' ;;
  *) echo "gh stub: unexpected $op" >&2; exit 3 ;;
esac
STUB
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$GHSTUB/log"
printf '{"message":"not found"}\n404'
STUB
chmod +x "$BIN/gh" "$BIN/curl"

newstate() { S=$(mktemp -d "$TMP/s.XXXXXX"); mkdir -p "$S/issues" "$S/comments" "$S/fail"; : > "$S/log"; }
issue() {   # issue <n> open|closed [pr]
  if [ "${3-}" = pr ]; then
    printf '{"number":%s,"state":"%s","pull_request":{"url":"x"}}\n' "$1" "$2" > "$S/issues/$1.json"
  else
    printf '{"number":%s,"state":"%s","pull_request":null}\n' "$1" "$2" > "$S/issues/$1.json"
  fi
}
comment() { jq -nc --arg b "$2" '[{body:$b}]' > "$S/comments/$1.json"; }
failop()  { echo "$3" > "$S/fail/$1-$2"; }   # failop PATCH-issue 10 403
state()   { jq -r .state "$S/issues/$1.json"; }
writes()  { grep -c '^WRITE' "$S/log"; }
posts()   { grep -c "^WRITE POST $1 " "$S/log"; }
patched() { grep -q "^WRITE PATCH $1 " "$S/log"; }
touched() { grep -Eq "issues/$1( |/|\$)|^WRITE [A-Z]+ $1 " "$S/log"; }
calls()   { wc -l < "$S/log" | tr -d ' '; }

mkrepo() {
  local r; r=$(mktemp -d "$TMP/repo.XXXXXX")
  git init --quiet -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name test
  git -C "$r" commit --quiet --allow-empty -m "initial"
  R="$r"
}
c()  { if [ $# -gt 1 ]; then git -C "$R" commit --quiet --allow-empty -m "$1" -m "$2"
       else git -C "$R" commit --quiet --allow-empty -m "$1"; fi; }
tg() { git -C "$R" tag "$1"; }

# run_cs [VAR=value ...] <args...>: output in $out, status in $rc
run_cs() {
  local envs=()
  while [ $# -gt 0 ] && [[ "$1" == [A-Z_]*=* ]]; do envs+=("$1"); shift; done
  out=$(CDPATH= cd -- "$R" && env -u DRY_RUN -u FORGE_DRY_RUN -u FORGE_LIB -u FORGEJO_TOKEN \
        PATH="$BIN:$PATH" GHSTUB="$S" FORGE_HOST=github FORGE_REPO=o/r ${envs[@]+"${envs[@]}"} \
        bash "${CS_UNDER_TEST:-$CS}" "$@" 2>&1)
  rc=$?
}

# A standard release: v1.1.0, then two ticket subjects, then v1.2.0. #9 sits BEFORE v1.1.0.
std() {
  mkrepo; c "fix(z): old (#9)"; tg v1.1.0
  c "fix(a): x (#10)"; c "feat(b): y (#11)"; tg v1.2.0
  newstate; issue 9 open; issue 10 open; issue 11 open
}

echo "close mode"
std; run_cs v1.2.0
check "shipped issues are closed (rc 0)" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && [ "$(state 11)" = closed ]'
check "the closes are reported" 'grep -q "^closed #10$" <<< "$out" && grep -q "^closed #11$" <<< "$out"'
check "each gets exactly one Released comment" '[ "$(posts 10)" = 1 ] && [ "$(posts 11)" = 1 ] && grep -q "^WRITE POST 10 {\"body\":\"Released in v1.2.0\"}$" "$S/log"'
check "the manifest line names the range" 'grep -q "^manifest: 2 tickets (v1.1.0..v1.2.0)$" <<< "$out"'
check "a ticket before the previous tag is never touched" '! touched 9 && [ "$(state 9)" = open ]'
check "the summary line" 'grep -q "^close-shipped: v1.2.0: closed 2, already closed 0, kept open 0, skipped 0, failed 0$" <<< "$out"'
w0=$(writes); run_cs v1.2.0
check "a rerun of the same tag writes nothing (idempotent)" '[ $rc -eq 0 ] && [ "$w0" = 4 ] && [ "$(writes)" = 4 ]'
check "a rerun counts both as already closed" 'grep -q "closed 0, already closed 2" <<< "$out"'

mkrepo; tg v1.1.0; c "fix(a): x (#12) (#13)"; tg v1.2.0
newstate; issue 12 open; issue 13 open pr; run_cs v1.2.0
check "a pull request number is skipped and never written to" '[ $rc -eq 0 ] && grep -q "^skip #13: pull request$" <<< "$out" && ! grep -q "^WRITE [A-Z]* 13 " "$S/log"'
check "the issue beside it on the same subject is closed" '[ "$(state 12)" = closed ]'

std; issue 10 closed; issue 11 open; comment 11 "Released in v1.2.0"; run_cs v1.2.0
check "a present comment is not reposted; the open issue is closed" '[ $rc -eq 0 ] && [ "$(posts 11)" = 0 ] && patched 11 && [ "$(state 11)" = closed ]'
check "an already closed issue receives no write" '! grep -q "^WRITE [A-Z]* 10 " "$S/log"'

std; failop PATCH-issue 10 403; run_cs v1.2.0
check "a failed close warns, the loop goes on, the run exits 1" '[ $rc -eq 1 ] && grep -q "^::warning::close #10 failed (rc=1)$" <<< "$out" && [ "$(state 11)" = closed ]'
check "the failure is counted in the summary" 'grep -q "failed 1$" <<< "$out"'
rm -f "$S/fail/PATCH-issue-10"; run_cs v1.2.0
check "the rerun after a failed close converges with no second comment" '[ $rc -eq 0 ] && [ "$(posts 10)" = 1 ] && [ "$(state 10)" = closed ]'

std; failop POST-comments 10 403; run_cs v1.2.0
check "a failed comment means no close" '[ $rc -eq 1 ] && ! patched 10 && [ "$(state 10)" = open ] && grep -q "^::warning::comment #10 failed" <<< "$out"'
check "the other ticket is still closed" '[ "$(state 11)" = closed ]'

std; failop GET-comments 10 500; run_cs v1.2.0
check "a failed comment read writes nothing to that ticket and fails the run" '[ $rc -eq 1 ] && ! grep -q "^WRITE [A-Z]* 10 " "$S/log" && grep -q "^::warning::comments #10 failed" <<< "$out"'

std; rm "$S/issues/10.json"; run_cs v1.2.0
check "a 404 is a skip, not a failure" '[ $rc -eq 0 ] && grep -q "^skip #10: not found$" <<< "$out" && [ "$(state 11)" = closed ]'

std; failop GET-issue 10 500; run_cs v1.2.0
check "a failed issue read is a failure, not a skip" '[ $rc -eq 1 ] && grep -q "^::warning::view #10 failed (rc=1)$" <<< "$out" && ! grep -q "^WRITE [A-Z]* 10 " "$S/log"'

std; failop GET-issue 10 403; run_cs v1.2.0
check "a 403 on the issue read is a failure, never a not-found skip" '[ $rc -eq 1 ] && grep -q "^::warning::view #10 failed (rc=1)$" <<< "$out" && ! grep -q "^skip #10" <<< "$out" && ! grep -q "^WRITE [A-Z]* 10 " "$S/log"'

# Review M1: no origin and no FORGE_REPO used to build repos//issues/N, read the 404 as not found
# and exit 0 having closed nothing.
std; run_cs FORGE_REPO= v1.2.0
check "an unresolvable owner/repo exits 2 with forge-lib's error and makes no host call" '[ $rc -eq 2 ] && grep -q "forge-lib: " <<< "$out" && grep -q "cannot resolve owner/repo" <<< "$out" && ! grep -q "^skip #" <<< "$out" && [ "$(calls)" = 0 ]'
run_cs FORGE_REPO= --report v1.2.0
check "report mode refuses the same way (exit 2, no zero-open summary)" '[ $rc -eq 2 ] && ! grep -q "^close-shipped report:" <<< "$out" && [ "$(calls)" = 0 ]'

echo "the manifest"
mkrepo; tg v1.1.0; c "feat(c): part one (refs #14)"; tg v1.2.0
newstate; issue 14 open; run_cs v1.2.0
check "(refs #N) keeps a ticket open with no read and no write" '[ $rc -eq 0 ] && grep -q "^kept open #14 (refs)$" <<< "$out" && ! touched 14 && [ "$(calls)" = 0 ]'

mkrepo; tg v1.1.0; c "feat(c): part one (refs #15)"; c "feat(c): part two (#15)"; tg v1.2.0
newstate; issue 15 open; run_cs v1.2.0
check "(#N) wins over (refs #N) for the same number" '[ "$(state 15)" = closed ] && ! grep -q "kept open #15" <<< "$out"'

mkrepo; tg v1.1.0; c "chore: thing" "this body cites #15 and (#15)"; tg v1.2.0
newstate; issue 15 open; run_cs v1.2.0
check "bodies are never scanned" '[ $rc -eq 0 ] && grep -q "^manifest: 0 tickets" <<< "$out" && [ "$(calls)" = 0 ]'

mkrepo; tg v1.1.0; c "fix: handle (#5) edge case"; tg v1.2.0
newstate; issue 5 open; run_cs v1.2.0
check "a mid-subject (#N) is not a match" '[ $rc -eq 0 ] && grep -q "^manifest: 0 tickets" <<< "$out" && [ "$(calls)" = 0 ]'

mkrepo; tg v1.1.0; c "fix(a): x (#10)"; c "fix(a): again (#10)"; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "a number cited twice is closed once with one comment" '[ "$(posts 10)" = 1 ] && grep -q "^manifest: 1 tickets" <<< "$out"'

mkrepo; tg v1.1.0; c "fix: x (#10)"; c 'Revert "fix: x (#10)" (#25)'; c "feat: y (#11)"; tg v1.2.0
newstate; issue 10 open; issue 11 open; issue 25 open pr; run_cs v1.2.0
check "a commit reverted in the same range ships nothing" '[ $rc -eq 0 ] && ! touched 10 && [ "$(state 10)" = open ] && [ "$(state 11)" = closed ]'

mkrepo; tg v1.1.0; c "fix: x (#10)"; c 'Revert "fix: x (#10)"'; c "fix: x again (#10)"; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "a ticket cited again after the revert is still closed" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ]'

mkrepo; tg v1.1.0; c "fix: x (#10)"; c "fix: x (#10)"; c 'Revert "fix: x (#10)"'; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "one revert cancels one copy of a subject, not every copy (a cherry-pick survives)" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ]'

mkrepo; tg v1.1.0; c 'fix: handle "foo" input (#10)'; c 'Revert "fix: handle "foo" input (#10)" (#25)'; tg v1.2.0
newstate; issue 10 open; issue 25 open pr; run_cs v1.2.0
check "a reverted subject with its own double quotes, behind a squash suffix, ships nothing" '[ $rc -eq 0 ] && ! touched 10 && [ "$(state 10)" = open ]'

# #498: a whole merged PR reverted inside the range (`git revert -m 1`, the host's Revert button on
# a --no-ff merge). The revert quotes the MERGE subject, which the --no-merges manifest never lists.
fc() {     # fc <subject>: a commit that changes a file, so a revert of it has something to undo
  echo "$1" >> "$R/f.$(git -C "$R" rev-parse --abbrev-ref HEAD)"
  git -C "$R" add -A && git -C "$R" commit --quiet -m "$1"
}
br() {     # br <branch> <subject>...: a branch off main carrying one file-changing commit per subject
  local b="$1" s; shift
  git -C "$R" checkout --quiet -b "$b" main
  for s in "$@"; do fc "$s"; done
  git -C "$R" checkout --quiet main
}
mkpr() {   # mkpr <branch> <subject>...: that branch merged --no-ff as "Merge pull request #24 from o/<branch>"
  br "$@"
  git -C "$R" merge --quiet --no-ff -m "Merge pull request #24 from o/$1" "$1"
}
revm() {   # revm [<merge>]: revert a merge (default HEAD) as the host's Revert button does; a fixture failure is loud
  git -C "$R" revert --no-edit -m 1 "${1:-HEAD}" >/dev/null 2>&1 || bad "fixture: git revert -m 1 failed"
}
revm_nobody() {   # revm_nobody: the same revert with its message rewritten to the subject alone (no sha line)
  local s; s="Revert \"$(git -C "$R" log -1 --pretty=%s HEAD)\""
  git -C "$R" revert --no-commit -m 1 HEAD >/dev/null 2>&1 && git -C "$R" commit --quiet -m "$s" \
    || bad "fixture: subject-only revert failed"
}
mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)" "feat: b (#12)"; revm; tg v1.2.0
newstate; issue 10 open; issue 12 open; issue 24 open pr; run_cs v1.2.0
check "a merge reverted in the same range ships none of the PR's tickets" '[ $rc -eq 0 ] && ! touched 10 && ! touched 12 && [ "$(state 10)" = open ] && [ "$(state 12)" = open ] && grep -q "^manifest: 0 tickets" <<< "$out" && [ "$(writes)" = 0 ]'
check "the reverted merge is reported" 'grep -q "^reverted in range: merge [0-9a-f]\{7\} Merge pull request #24 from o/feat$" <<< "$out"'

mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)" "feat: b (#12)"; revm; fc "fix: redo (#10)"; tg v1.2.0
newstate; issue 10 open; issue 12 open; run_cs v1.2.0
check "after a reverted merge, a commit citing the ticket again still closes it" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && [ "$(posts 10)" = 1 ] && [ "$(state 12)" = open ] && ! touched 12'

mkrepo; tg v1.1.0; br a "feat: a (#10)"; br b "feat: b (#12)"; br d "feat: d (#13)"
git -C "$R" merge --quiet --no-ff -m "Merge octopus" a b d >/dev/null 2>&1; revm; tg v1.2.0
newstate; issue 10 open; issue 12 open; issue 13 open; run_cs v1.2.0
check "a reverted octopus merge ships the tickets of none of its parents" '[ $rc -eq 0 ] && [ "$(git -C "$R" rev-list --parents -n 1 HEAD~1 | wc -w)" = 5 ] && ! touched 10 && ! touched 12 && ! touched 13'

# The merge lies BEFORE the previous tag, so it is not this release's to undo; the same subject
# landing again inside the range ships. An unrelated merge in range makes the lookup actually run.
mkrepo; mkpr feat "feat: a (#10)"; tg v1.1.0; revm; fc "feat: a (#10)"; mkpr other "feat: c (#14)"; tg v1.2.0
newstate; issue 10 open; issue 14 open; run_cs v1.2.0
check "a revert of a merge outside the range drops nothing" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && [ "$(state 14)" = closed ] && ! grep -q "^reverted in range:" <<< "$out"'

# Merge subjects repeat on a two-branch model. The revert body's sha, not the subject, picks the
# merge: reverting the second drops #12 only, reverting the first drops #10 only.
dup() {
  mkrepo; tg v1.1.0; br a "feat: a (#10)"; git -C "$R" merge --quiet --no-ff -m "Merge branch dev" a
  M1=$(git -C "$R" rev-parse HEAD)
  br b "feat: b (#12)"; git -C "$R" merge --quiet --no-ff -m "Merge branch dev" b
}
dup; revm; tg v1.2.0; newstate; issue 10 open; issue 12 open; run_cs v1.2.0
check "two merges share a subject: the revert of the second drops only the second" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && [ "$(state 12)" = open ] && ! touched 12'
dup; revm "$M1"; tg v1.2.0; newstate; issue 10 open; issue 12 open; run_cs v1.2.0
check "two merges share a subject: the revert of the first drops only the first" '[ $rc -eq 0 ] && [ "$(state 10)" = open ] && ! touched 10 && [ "$(state 12)" = closed ]'

# A revert whose message lost the sha line (edited, or squash-merged with a rewritten message)
# falls back to its quoted subject, and only an unambiguous one drops anything.
mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)"; revm_nobody; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "no sha line: a quoted subject matching exactly one merge drops it" '[ $rc -eq 0 ] && ! touched 10 && grep -q "^reverted in range: merge " <<< "$out"'
dup; revm_nobody; tg v1.2.0; newstate; issue 10 open; issue 12 open; run_cs v1.2.0
check "no sha line: a quoted subject matching two merges drops nothing and says so" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && [ "$(state 12)" = closed ] && grep -q "^reverted merge not identified: 2 merges match \"Merge branch dev\"; nothing dropped$" <<< "$out"'

# Only a commit whose subject is `Revert "..."` counts: a plain commit that quotes the sha line in
# its body (a partial undo, a cherry-pick note) drops nothing.
mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)"; M=$(git -C "$R" rev-parse HEAD)
echo z >> "$R/z"; git -C "$R" add -A; git -C "$R" commit --quiet -m "fix: partial undo" -m "This reverts commit $M, in part."
tg v1.2.0; newstate; issue 10 open; run_cs v1.2.0
check "a non-revert commit naming a merge sha in its body drops nothing" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && ! grep -q "^reverted in range:" <<< "$out"'

# `git revert -m 2` writes the same subject and sha line but undoes the MAINLINE side and keeps the
# feature: its `changes made to` sha is M^2, not M^1, so it drops nothing and says so.
mkrepo; tg v1.1.0; br feat "feat: a (#10)"; fc "chore: main work"
git -C "$R" merge --quiet --no-ff -m "Merge pull request #24 from o/feat" feat
git -C "$R" revert --no-edit -m 2 HEAD >/dev/null 2>&1 || bad "fixture: git revert -m 2 failed"
tg v1.2.0; newstate; issue 10 open; run_cs v1.2.0
check "a -m 2 revert of a merge drops nothing and says so" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ] && grep -q "^reverted merge [0-9a-f]\{7\} not on mainline 1; nothing dropped$" <<< "$out" && ! grep -q "^reverted in range:" <<< "$out"'

# A reapply restores nothing: as for a reverted commit, the ticket needs its own trailing (#N).
mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)"; revm; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "a reapplied merge revert keeps the ticket open (the documented own (#N) rule)" '[ $rc -eq 0 ] && ! touched 10 && [ "$(state 10)" = open ]'

# The previous tag sits on the merged branch itself, so the merge's second parent reaches back past
# it. Exclusion is by sha, so main's in-range cherry-pick with the same subject still ships.
mkrepo; br feat "feat: a (#10)"; git -C "$R" tag v1.1.0 feat; fc "feat: a (#10)"
git -C "$R" merge --quiet --no-ff -m "Merge pull request #24 from o/feat" feat; revm; tg v1.2.0
newstate; issue 10 open; run_cs v1.2.0
check "a reverted merge never drops a same-subject commit it did not bring in" '[ $rc -eq 0 ] && [ "$(state 10)" = closed ]'

# Report mode shares the matcher: the reverted PR's tickets are not released-but-open.
mkrepo; tg v1.1.0; mkpr feat "feat: a (#10)"; revm; fc "fix: z (#13)"; tg v1.2.0
newstate; issue 10 open; issue 13 open; run_cs --report v1.2.0
check "report mode does not list a reverted merge's ticket" '[ $rc -eq 1 ] && grep -q "^released but open: #13$" <<< "$out" && ! grep -q "#10" <<< "$out" && [ "$(writes)" = 0 ]'

mkrepo; c "feat: start (#1)"; tg v1.0.0
newstate; issue 1 open; run_cs v1.0.0
check "a first release closes nothing and makes no call" '[ $rc -eq 0 ] && grep -q "no previous tag; nothing closed" <<< "$out" && [ "$(calls)" = 0 ]'

mkrepo; tg v1.1.0; git -C "$R" checkout --quiet -b side; c "side work (#99)"; tg v9.0.0
git -C "$R" checkout --quiet main; c "fix: real (#20)"; tg v1.2.0
newstate; issue 20 open; issue 99 open; run_cs v1.2.0
check "the previous tag is found by reachability, never repo-wide" 'grep -q "^manifest: 1 tickets (v1.1.0..v1.2.0)$" <<< "$out" && [ "$(state 20)" = closed ] && ! touched 99'

mkrepo; tg v1.1.0; c "a (#21)"; tg v1.2.0-rc1; c "b (#22)"; tg v1.2.0
newstate; issue 21 open; issue 22 open; run_cs v1.2.0
check "a prerelease tag is not a previous release" 'grep -q "^manifest: 2 tickets (v1.1.0..v1.2.0)$" <<< "$out"'

mkrepo; tg v1.1.0; c "chore(release): v1.2.0 (#40)"; tg v1.2.0
newstate; issue 40 open pr; run_cs v1.2.0
check "a squash range carrying only a PR number closes nothing" '[ $rc -eq 0 ] && grep -q "^skip #40: pull request$" <<< "$out" && [ "$(writes)" = 0 ]'

mkrepo; tg v1.1.0; git -C "$R" checkout --quiet -b dev; c "fix: feature (#30)"
git -C "$R" checkout --quiet main; git -C "$R" merge --quiet --no-ff -m "Merge pull request (#31)" dev; tg v1.2.0
newstate; issue 30 open; issue 31 open; run_cs v1.2.0
check "a commit under a merge's second parent is included" '[ "$(state 30)" = closed ]'
check "a merge commit subject is ignored" '! touched 31'

# The downstream regression: 12 ticket subjects promoted through a merge commit, none closed.
mkrepo; tg v1.1.0; git -C "$R" checkout --quiet -b develop
for n in 101 102 103 104 105 106 107 108 109 110 111 112; do c "fix(x): item $n (#$n)"; done
git -C "$R" checkout --quiet main; git -C "$R" merge --quiet --no-ff -m "Release v1.2.0 (#120)" develop; tg v1.2.0
newstate; for n in 101 102 103 104 105 106 107 108 109 110 111 112; do issue "$n" open; done; issue 120 open pr
run_cs v1.2.0
check "regression: all 12 promoted tickets are closed in one run" '[ $rc -eq 0 ] && [ "$(grep -c "^closed #" <<< "$out")" = 12 ]'
w1=$(writes); run_cs v1.2.0
check "regression: a rerun posts nothing" '[ $rc -eq 0 ] && [ "$(writes)" = "$w1" ]'

echo "dry run and --to"
std; run_cs DRY_RUN=1 v1.2.0
check "DRY_RUN prints and writes nothing" '[ $rc -eq 0 ] && grep -q "^\[dry-run\] would comment and close #10 for v1.2.0$" <<< "$out" && [ "$(writes)" = 0 ] && [ "$(state 10)" = open ]'
check "DRY_RUN still reads the host" 'grep -q "issues/10" "$S/log"'

std; run_cs FORGE_DRY_RUN=1 v1.2.0
check "an inherited FORGE_DRY_RUN=1 writes nothing and still reads" '[ $rc -eq 0 ] && grep -q "would comment and close #11" <<< "$out" && [ "$(writes)" = 0 ] && grep -q "issues/11" "$S/log"'

std; c "fix: next (#50)"; issue 50 open; run_cs v1.3.0 --to HEAD
check "--to names the range end when the tag does not exist yet" '[ $rc -eq 0 ] && grep -q "^manifest: 1 tickets (v1.2.0..HEAD)$" <<< "$out" && grep -q "^WRITE POST 50 {\"body\":\"Released in v1.3.0\"}$" "$S/log"'

std; run_cs v1.3.0
check "a missing tag without --to is a usage error" '[ $rc -eq 2 ] && [ "$(calls)" = 0 ]'

echo "report mode"
mkrepo; tg v1.1.0; c "a (#16)"; c "b (refs #17)"; c "c (#18)"; tg v1.2.0
newstate; issue 16 open; issue 17 open; issue 18 closed; run_cs --report v1.2.0
check "report lists a released but open issue and exits 1" '[ $rc -eq 1 ] && grep -q "^released but open: #16$" <<< "$out"'
check "report shows refs as kept open, not as released but open" 'grep -q "^kept open #17 (refs)$" <<< "$out" && ! grep -q "released but open: #17" <<< "$out" && ! grep -q "released but open: #18" <<< "$out"'
check "report never writes" '[ "$(writes)" = 0 ]'

issue 16 closed; run_cs --report v1.2.0
check "report exits 0 when everything is closed" '[ $rc -eq 0 ] && ! grep -q "released but open: #" <<< "$out"'

failop GET-issue 16 500; run_cs --report v1.2.0
check "report exits 2 when a read failed and nothing was found open" '[ $rc -eq 2 ]'

mkrepo; tg v1.1.0; c "a (#60)"; tg v1.2.0; c "b (#61)"; tg v1.3.0
newstate; issue 60 open; issue 61 open; run_cs --report --last 2
check "--last 2 reports the two highest tags, each against its own previous" '[ $rc -eq 1 ] && grep -q "^== v1.3.0$" <<< "$out" && grep -q "^== v1.2.0$" <<< "$out" && grep -q "^released but open: #60$" <<< "$out" && grep -q "^released but open: #61$" <<< "$out" && grep -q "(v1.2.0..v1.3.0)" <<< "$out" && [ "$(writes)" = 0 ]'
run_cs --report --last 1
check "--last 1 reports only the newest tag" 'grep -q "#61" <<< "$out" && ! grep -q "#60" <<< "$out"'

mkrepo; tg v1.1.0; c "a (#62)"; c "b (#63)"; tg v1.2.0
newstate; issue 62 open; issue 63 open; failop GET-issue 63 500; run_cs --report v1.2.0
check "report: one open ticket and one failed read exits 1, open outranking the failure" '[ $rc -eq 1 ] && grep -q "^released but open: #62$" <<< "$out" && grep -q "^::warning::view #63 failed" <<< "$out"'

# Review M2: the tag lives on main behind a --no-ff merge, and the report runs from a branch cut
# from develop, which does not contain that merge.
mkrepo; tg v1.1.0; git -C "$R" checkout --quiet -b develop; c "fix: shipped (#70)"
git -C "$R" checkout --quiet main; git -C "$R" merge --quiet --no-ff -m "Release v1.2.0" develop; tg v1.2.0
git -C "$R" checkout --quiet develop; git -C "$R" checkout --quiet -b feature; c "wip"
newstate; issue 70 open; run_cs --report --last 1
check "--last finds tags not merged into HEAD (run from a development branch)" '[ $rc -eq 1 ] && grep -q "^== v1.2.0$" <<< "$out" && grep -q "^released but open: #70$" <<< "$out"'

echo "interface and environment"
std; run_cs
check "no arguments is exit 2" '[ $rc -eq 2 ]'
run_cs --help
check "--help exits 0 with usage" '[ $rc -eq 0 ] && grep -q "^usage: close-shipped.sh" <<< "$out"'
run_cs --last 2
check "--last outside report mode is exit 2" '[ $rc -eq 2 ]'
run_cs --report v1.2.0 --to HEAD
check "--to in report mode is exit 2" '[ $rc -eq 2 ] && [ "$(calls)" = 0 ]'

LONE="$TMP/lone"; mkdir -p "$LONE"; cp "$CS" "$LONE/close-shipped.sh"
CS_UNDER_TEST="$LONE/close-shipped.sh" run_cs v1.2.0
check "forge-lib absent: refuses with exit 2" '[ $rc -eq 2 ] && grep -q "forge-lib.sh not found" <<< "$out" && [ "$(calls)" = 0 ]'

mkrepo; tg v1.1.0; c "fix: x (#10)"; tg v1.2.0; newstate
run_cs FORGE_HOST=forgejo FORGE_API_URL=https://forge.example FORGEJO_TOKEN=t FORGE_NO_GIT_CREDENTIALS=1 v1.2.0
check "Forgejo: a 404 (forge_api rc 44) is a skip" '[ $rc -eq 0 ] && grep -q "^skip #10: not found$" <<< "$out" && grep -q "^curl " "$S/log"'

echo ""
echo "close-shipped tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
