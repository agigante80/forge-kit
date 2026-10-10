#!/usr/bin/env bash
# test-reassess-phases-version: 6
#
# Contract test for reassess-phases.sh (#249): the reshape script that answers whether the
# ROADMAP itself is still the right plan, one level above /phase review's single-phase question.
# Runs the real script as a subprocess against a stubbed forge-lib.sh, the same shape
# test-sync-phases.sh uses, extended with mutable ticket state so a merge/rename/delete's
# move-then-reread sequence is exercised for real rather than assumed.

set -uo pipefail
# #287: an inherited environment must not steer resolution. FORGE_LIB is consulted before anything
# else, and GIT_DIR/GIT_WORK_TREE (which git exports into hooks, and pre-push runs this suite) override
# the ceiling below. The set is complete for `rev-parse --show-toplevel` (git(1) and git-config(1)
# ENVIRONMENT, 2.43, #288): GIT_DISCOVERY_ACROSS_FILESYSTEM only lets a search cross a mount the
# ceiling still stops, GIT_CONFIG_COUNT and GIT_CONFIG_PARAMETERS act on a repository already found,
# which the ceiling prevents, and GIT_NAMESPACE scopes refs only. All three are ruled out, not missed.
# #306: FORGE_DRY_RUN joins the list because the stubs below now honour it as forge-lib v28 does: an
# inherited flag from a maintainer shell or the pre-push hook would steer every case. Each dry-run case
# passes it per call (`FORGE_DRY_RUN=1 run ...`).
unset FORGE_DRY_RUN FORGE_LIB GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
SRC="$ASSETS/reassess-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qiF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
absent()   { if grep -qiF -- "$1" <<< "$2"; then bad "$3"; else ok "$3"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

# #287: the script under test resolves forge-lib.sh from $FORGE_LIB, beside itself, then the git root
# of its working directory. A case that hides the stub must find NO repository there, or it loads the
# real library and writes to the live host, which once created four milestones on this repository.
# $T is made ABSOLUTE (git ignores a relative ceiling, and mktemp under a relative TMPDIR returns a
# relative path), the ceiling is its parent, and gh/curl are shims that log and fail; the last
# assertion requires their log to be empty. Two steps, not `cd "$(mktemp -d)"`: a failed mktemp would
# make that `cd ""`, a no-op, and the EXIT trap would then remove the working directory.
# #288: three statements, trap before the cd, so a cd that fails after mktemp succeeded still
# removes the directory; the absolute path goes through T_ABS since a failed `T=$(...)` empties $T.
T=$(mktemp -d) || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$T"' EXIT
T_ABS=$(cd "$T" && pwd -P) || { echo "cannot resolve the temp dir"; exit 1; }
T=$T_ABS
export GIT_CEILING_DIRECTORIES="$(dirname "$T")"
mkdir -p "$T/shim"
for c in gh curl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/shim/live.log"\nexit 1\n' "$c" "$T" > "$T/shim/$c"
  chmod +x "$T/shim/$c"
done
PATH="$T/shim:$PATH"
mkdir -p "$T/docs/plans"
cp "$SRC" "$T/reassess-phases.sh"
cp "$ASSETS/roadmap-lib.sh" "$T/roadmap-lib.sh"
cp "$ASSETS/sync-phases.sh" "$T/sync-phases.sh"
cp "$ASSETS/check-phases.sh" "$T/check-phases.sh"

cat > "$T/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 1
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
# #306: these list stubs model forge-lib v28 under FORGE_DRY_RUN=1: forge_api_paginate returns a literal
# `[]` for every method, GET included. Each call appends the value of the flag it SAW to $READLOG
# ("ms <value>" or "iss <value>", "unset" when the variable is not set), so a read that is not scoped
# is visible even when it is behaviourally dead (reassess-phases.sh's MS read is never used after
# assignment). STUB_LIST_FAIL fails a list whatever the flag is: `iss` fails only the issue list, any
# other non-empty value fails both. A stub that failed only under the flag would never fail once the
# read runs with the flag at 0.
forge_milestone_list() {
  printf 'ms %s\n' "${FORGE_DRY_RUN-unset}" >> "$READLOG"
  [ -n "${STUB_LIST_FAIL:-}" ] && [ "$STUB_LIST_FAIL" != iss ] && return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[]'; else cat "$STUB_MILESTONES"; fi
}
forge_milestone_create() {
  printf 'CREATE %s\n' "$1" >> "$REQLOG"
  local maxid
  maxid=$(jq '[.[].id] | max // 0' "$STUB_MILESTONES")
  jq --arg t "$1" --argjson id "$((maxid + 1))" '. + [{id:$id, title:$t, state:"open"}]' \
    "$STUB_MILESTONES" > "$STUB_MILESTONES.tmp" && mv "$STUB_MILESTONES.tmp" "$STUB_MILESTONES"
}
forge_milestone_close() {
  printf 'CLOSE %s\n' "$1" >> "$REQLOG"
  jq --arg t "$1" 'map(if .title == $t then .state = "closed" else . end)' \
    "$STUB_MILESTONES" > "$STUB_MILESTONES.tmp" && mv "$STUB_MILESTONES.tmp" "$STUB_MILESTONES"
}
forge_issue_milestone() {
  local n="$1" title="$2"
  if [ -n "${FAIL_MOVE:-}" ] && [ "$n" = "$FAIL_MOVE" ]; then
    echo "stub: forced failure moving #$n" >&2
    return 1
  fi
  jq --arg n "$n" --arg t "$title" \
    '(.[] | select(.number == ($n|tonumber)) | .milestone) = $t' \
    "$STUB_ISSUES" > "$STUB_ISSUES.tmp" && mv "$STUB_ISSUES.tmp" "$STUB_ISSUES"
  printf 'MOVE %s %s\n' "$n" "$title" >> "$REQLOG"
}
forge_issue_milestone_list() {
  printf 'iss %s\n' "${FORGE_DRY_RUN-unset}" >> "$READLOG"
  [ -n "${STUB_LIST_FAIL:-}" ] && return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[]'; else cat "$STUB_ISSUES"; fi
}
STUB

goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }
goodplan Zeta > "$T/docs/plans/zeta.md"
goodplan Alpha > "$T/docs/plans/alpha.md"
goodplan Gamma > "$T/docs/plans/gamma.md"

roadmap() { cat > "$T/docs/roadmap.md"; }

# The baseline every test starts from unless it says otherwise: two open buckets, one closed
# phase with a real plan (for the "done is never rewritten" refusals), one backlog phase (for
# --to backlog's resolution).
base_roadmap() {
  roadmap <<'MD'
## Phase: Alpha
state: planned

Alpha's prose.

## Phase: Beta
state: planned

Beta's prose.

## Phase: Zeta
state: done
plan: docs/plans/zeta.md

Zeta's prose, already closed.

## Phase: Cellar
state: backlog

Backlog phase, never closes.
MD
}
base_milestones() {
  cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Beta","state":"open"},
 {"id":3,"title":"Zeta","state":"closed"},{"id":4,"title":"Cellar","state":"open"}]
JSON
}
base_issues() { printf '[]' > "$T/iss.json"; }

out=""; sout=""; serr=""; rc=0; REQLOG="$T/req.log"; READLOG="$T/read.log"
# #306: stdout and stderr are captured SEPARATELY ($sout, $serr) so a case can compare them one by
# one; $out is both joined, which is what every older assertion reads.
run() {
  : > "$REQLOG"; : > "$READLOG"
  # #328: RUN_TMPDIR, when set (even empty), becomes TMPDIR for this one invocation only. The suite's
  # own `mktemp -d` and EXIT trap above honour TMPDIR, so it is never exported at file level.
  (cd "$T" && { [ -z "${RUN_TMPDIR+x}" ] || export TMPDIR="$RUN_TMPDIR"; } && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" REQLOG="$REQLOG" READLOG="$READLOG" \
        FAIL_MOVE="${FAIL_MOVE:-}" bash ./reassess-phases.sh "$@" >"$T/run.out" 2>"$T/run.err"); rc=$?
  sout=$(cat "$T/run.out"); serr=$(cat "$T/run.err"); out="$sout
$serr"
}
# Every list call of a FLAGGED or --check run must have seen the flag at 0. Not other runs: a merge,
# rename or delete-with-tickets run with neither the flag nor --check reaches confirm_emptied's read,
# which is unscoped on purpose and logs the flag as unset.
# #336: a flagged or --check merge reaches confirm_emptied under CHECK=1, where its re-read must never
# run (the early return); this catches that read when it does. The --check merge's reads do see 0.
reads_all_zero() {
  local n bad_lines
  n=$(wc -l < "$READLOG" | tr -d ' ')
  bad_lines=$(grep -vc ' 0$' "$READLOG" || true)
  if [ "${n:-0}" -ge 2 ] && [ "$bad_lines" = 0 ]; then ok "$1: every list read ($n) saw FORGE_DRY_RUN=0"
  else bad "$1: list reads did not all see FORGE_DRY_RUN=0 ($(tr '\n' ';' < "$READLOG"))"; fi
}

# ---------------------------------------------------------------------------------------------
echo "== a rule-breaking reshape is refused whole, and nothing is written (AC2) =="
base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run reorder Ghost --end
expect "an unknown phase refuses" 5 "$rc"
contains "no phase named" "$out" "and names the problem"
expect "and the roadmap file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"
expect "and nothing was sent to the host" "" "$(cat "$REQLOG")"

echo "== reorder moves a phase (positive) =="
base_roadmap; base_milestones; base_issues
run reorder Beta --before Alpha
expect "reorder exits 0" 0 "$rc"
first="$(grep -m1 '^## Phase:' "$T/docs/roadmap.md")"
expect "Beta now comes first" "## Phase: Beta" "$first"

echo "== refocus rewrites prose (positive), never a done phase (negative, AC5-adjacent) =="
base_roadmap; base_milestones; base_issues
run refocus Alpha --prose "Alpha now covers different ground"
expect "refocus exits 0" 0 "$rc"
contains "Alpha now covers different ground" "$(cat "$T/docs/roadmap.md")" "the new prose landed"

before="$(cat "$T/docs/roadmap.md")"
run refocus Zeta --prose "trying to rewrite a closed phase"
expect "refocusing a done phase refuses" 5 "$rc"
contains "done" "$out" "and says why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== insert-and-open gate (AC7) =="
base_roadmap; base_milestones; base_issues
run insert Gamma --before Beta --state open --plan docs/plans/gamma.md --prose "New open work"
expect "insert with a real plan exits 0" 0 "$rc"
contains "## Phase: Gamma" "$(cat "$T/docs/roadmap.md")" "the phase landed"
contains "CREATE Gamma" "$(cat "$REQLOG")" "and its milestone was created"

base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run insert Gamma --end --state open --prose "no plan given"
expect "insert open with no plan refuses" 5 "$rc"
contains "rule 2" "$out" "citing the rule it would break"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

roadmap <<'MD'
## Phase: Alpha
state: open
plan: docs/plans/alpha.md

Alpha is already open.

## Phase: Beta
state: planned

Beta's prose.
MD
cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Beta","state":"open"}]
JSON
base_issues
before="$(cat "$T/docs/roadmap.md")"
run insert Gamma --end --state open --plan docs/plans/gamma.md --prose "a second open phase"
expect "inserting a second open phase refuses" 5 "$rc"
contains "already open" "$out" "citing rule 3's at-most-one-open"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== split moves named tickets into a new phase (positive), never out of done (negative) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run split Alpha --into AlphaB --move 10 --end
expect "split exits 0" 0 "$rc"
contains "## Phase: AlphaB" "$(cat "$T/docs/roadmap.md")" "the new phase landed"
contains "CREATE AlphaB" "$(cat "$REQLOG")" "its milestone was created"
contains "MOVE 10 AlphaB" "$(cat "$REQLOG")" "and the named ticket moved"
expect "the ticket now shows the new phase" "AlphaB" "$(jq -r '.[0].milestone' "$T/iss.json")"

base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Zeta"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
run split Zeta --into ZetaB --move 10 --end
expect "splitting a done phase refuses" 5 "$rc"
contains "done" "$out" "citing why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== merge composes under policy (positive), refuses on either side being done (negative, AC5) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run merge Alpha --into Beta --reason "consolidating scope"
expect "merge exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the losing phase is gone"
contains 'Merged "Alpha" in: consolidating scope' "$(cat "$T/docs/roadmap.md")" "the reason is recorded in the winner's prose"
contains "MOVE 10 Beta" "$(cat "$REQLOG")" "and its ticket moved to the winner"
contains "Alpha" "$(jq -c '.' "$T/ms.json")" "the loser's milestone is left on the host, not deleted"

base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run merge Zeta --into Beta --reason "should refuse"
expect "merging a done loser refuses" 5 "$rc"
contains "done" "$out" "citing why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

before="$(cat "$T/docs/roadmap.md")"
run merge Alpha --into Zeta --reason "should also refuse"
expect "merging into a done winner refuses" 5 "$rc"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== a partial move is reported, never swallowed, and a re-run resumes (AC and #249 scenario 6/7) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"},{"number":11,"milestone":"Alpha"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
FAIL_MOVE=11 run merge Alpha --into Beta --reason "test"
expect "the partial failure exits 4" 4 "$rc"
contains "MOVE 10 Beta" "$(cat "$REQLOG")" "the ticket that succeeded is logged"
absent "MOVE 11 Beta" "$(cat "$REQLOG")" "and the one that failed never logged as moved"
contains "moved so far: 10" "$out" "the report names what moved"
contains "still to move: 11" "$out" "and what did not"
expect "the file half was never touched" "$before" "$(cat "$T/docs/roadmap.md")"
expect "ticket 10 already shows the winner on the host" "Beta" "$(jq -r '.[] | select(.number==10) | .milestone' "$T/iss.json")"

FAIL_MOVE="" run merge Alpha --into Beta --reason "test"
expect "the re-run completes" 0 "$rc"
absent "MOVE 10 Beta" "$(cat "$REQLOG")" "and does not repeat the already-succeeded move"
contains "MOVE 11 Beta" "$(cat "$REQLOG")" "only the remaining ticket moves"
merges_recorded="$(grep -c 'Merged "Alpha" in: test' "$T/docs/roadmap.md" || true)"
expect "the merge reason appears exactly once, not duplicated by the retry" 1 "$merges_recorded"

echo "== rename leaves the old milestone emptied, never deleted (AC3/AC8-adjacent) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run rename Alpha NewAlpha
expect "rename exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the old heading is gone"
contains "## Phase: NewAlpha" "$(cat "$T/docs/roadmap.md")" "the new heading landed"
expect "the ticket followed the rename" "NewAlpha" "$(jq -r '.[0].milestone' "$T/iss.json")"
contains "emptied, not deleted" "$out" "the old milestone is reported emptied rather than removed"
contains "Alpha" "$(jq -c '.' "$T/ms.json")" "and it is still present on the host under its old title"

echo "== #446: rename over the REAL forge_issue_milestone_list on Forgejo =="
# The stub above returns flattened issues, so it never exercised the filter #446 broke. Under that bug
# the read dropped every Forgejo issue, so rename moved nothing and confirm_emptied counted zero and
# reported the old phase emptied while it still held a ticket. This wrapper sources the real library
# and stubs only the transport (Forgejo's wire shape) and the writers; NOOP446=1 makes the move a no-op.
LIB446="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh"
# The copied stub minus the three functions the real library must answer: its forge_host would say
# github, and its issue read is the flattened one.
awk '/^forge_issue_milestone_list\(\) \{/{skip=1} /^forge_(host|repo)\(\)/{next} !skip{print} skip&&/^\}/{skip=0}' "$T/forge-lib.sh" > "$T/stub446.sh"
cat > "$T/lib446.sh" <<STUB
. "$LIB446"
. "$T/stub446.sh"
export FORGE_HOST=forgejo FORGE_REPO=o/r
forge_api() { case "\$2" in *"/issues?"*page=1*) cat "\$ISS446" ;; *) printf '[]' ;; esac; }
forge_issue_milestone() {
  [ "\${NOOP446:-0}" = 1 ] && return 0
  jq --argjson n "\$1" --arg t "\$2" 'map(if .number == \$n then .milestone = {title: \$t} else . end)' \
    "\$ISS446" > "\$ISS446.tmp" && mv "\$ISS446.tmp" "\$ISS446"
}
STUB
iss446='[{"number":10,"pull_request":null,"milestone":{"title":"Alpha"}},{"number":12,"pull_request":{"merged":false},"milestone":{"title":"Alpha"}}]'
base_roadmap; base_milestones; base_issues
printf '%s' "$iss446" > "$T/iss446.json"
export FORGE_LIB="$T/lib446.sh" ISS446="$T/iss446.json"
run rename Alpha NewAlpha
expect "#446: rename on Forgejo exits 0 once the ticket really moved" 0 "$rc"
expect "#446: and issue #10 now sits in NewAlpha" "NewAlpha" "$(jq -r '.[] | select(.number==10) | .milestone.title' "$T/iss446.json")"
contains '"Alpha" is now emptied, not deleted' "$out" "#446: and the old phase is reported emptied"
base_roadmap; base_milestones; base_issues
printf '%s' "$iss446" > "$T/iss446.json"
NOOP446=1 run rename Alpha NewAlpha
expect "#446: when the move does not land, rename refuses with exit 4" 4 "$rc"
contains 'reassess-phases: "Alpha" still holds 1 open ticket(s) after moving; not proceeding.' "$out" "#446: and counts the one ISSUE left behind, never the PR"
unset FORGE_LIB ISS446

echo "== delete relocates open tickets before removing the block (AC10, --to backlog resolves by state) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run delete Alpha --to backlog
expect "delete with a destination exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the phase is removed"
expect "the ticket landed in the phase whose state is backlog" "Cellar" "$(jq -r '.[0].milestone' "$T/iss.json")"

base_roadmap; base_milestones
printf '[{"number":20,"milestone":"Beta"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
run delete Beta
expect "deleting a phase with open tickets and no destination refuses" 5 "$rc"
contains "nowhere for them" "$out" "and says why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== FORGE_DRY_RUN=1 behaves as --check, and its reads see the real host (#306) =="
# Fixture: phase Alpha is open (its plan carries a Fails if section, rule 2), phase Cell is planned
# (a planned phase needs no plan) and holds open ticket #9 on the host. Both milestones exist.
dryroadmap() {
  roadmap <<'MD'
## Phase: Alpha
state: open
plan: docs/plans/alpha.md

Alpha is open.

## Phase: Cell
state: planned

Cell is planned.
MD
  cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Cell","state":"open"}]
JSON
  printf '[{"number":9,"milestone":"Cell"}]' > "$T/iss.json"
}
dryroadmap
before="$(cat "$T/docs/roadmap.md")"; ibefore="$(cat "$T/iss.json")"
run delete Cell --check
ref_sout="$sout"; ref_serr="$serr"; ref_rc="$rc"
expect "the unflagged --check refuses a delete of a phase holding open tickets" 5 "$ref_rc"
FORGE_DRY_RUN=1 run delete Cell
expect "flagged delete of a phase holding open tickets exits 5" 5 "$rc"
contains "reassess-phases: 'Cell' holds 1 open ticket(s) (9) and names nowhere for them. Pass --to <phase>|backlog" "$serr" "and prints the refusal"
expect "its stdout equals the unflagged --check run" "$ref_sout" "$sout"
expect "its stderr equals the unflagged --check run" "$ref_serr" "$serr"
expect "and the roadmap is byte-identical" "$before" "$(cat "$T/docs/roadmap.md")"
expect "and no ticket moved" "$ibefore" "$(cat "$T/iss.json")"
expect "and no write reached the host" "" "$(cat "$REQLOG")"
reads_all_zero "flagged delete refusal"

dryroadmap
STUB_LIST_FAIL=iss FORGE_DRY_RUN=1 run delete Cell
expect "a failed issue read under the flag exits 2" 2 "$rc"
contains "reassess-phases: could not list issue milestones; check the token and the forge configuration" "$serr" "and prints the read failure"
expect "and the roadmap is byte-identical" "$before" "$(cat "$T/docs/roadmap.md")"
reads_all_zero "flagged failed read"

# The positive: a reorder under the flag previews and writes nothing, exactly as --check does.
base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run reorder Beta --before Alpha --check
ref_sout="$sout"; ref_serr="$serr"; ref_rc="$rc"
expect "the unflagged --check reorder exits 0" 0 "$ref_rc"
FORGE_DRY_RUN=1 run reorder Beta --before Alpha
expect "flagged reorder exits 0" 0 "$rc"
expect "its stdout equals the unflagged --check run" "$ref_sout" "$sout"
expect "its stderr equals the unflagged --check run" "$ref_serr" "$serr"
expect "and docs/roadmap.md is byte-identical, so the flag held the file write" "$before" "$(cat "$T/docs/roadmap.md")"
expect "and no write reached the host" "" "$(cat "$REQLOG")"
reads_all_zero "flagged reorder"

# The same reorder with Beta's milestone missing, so the sync-phases.sh --check subprocess prints a
# line (`would create milestone "Beta"`) and the compared output is not an empty string on both sides.
base_roadmap; base_issues
cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":3,"title":"Zeta","state":"closed"},
 {"id":4,"title":"Cellar","state":"open"}]
JSON
before="$(cat "$T/docs/roadmap.md")"
run reorder Beta --before Alpha --check
ref_sout="$sout"; ref_serr="$serr"; ref_rc="$rc"
contains 'would create milestone "Beta"' "$ref_sout" "the unflagged --check preview names the missing milestone"
FORGE_DRY_RUN=1 run reorder Beta --before Alpha
expect "flagged reorder with a missing milestone exits as --check does" "$ref_rc" "$rc"
expect "its stdout equals the unflagged --check run" "$ref_sout" "$sout"
expect "its stderr equals the unflagged --check run" "$ref_serr" "$serr"
expect "and the roadmap is byte-identical" "$before" "$(cat "$T/docs/roadmap.md")"
reads_all_zero "flagged reorder with a missing milestone"

# The negative: without the flag, or with any value but 1, the same command writes, so the flag and
# not the operation is what holds the file.
for flagval in unset 0 true; do
  base_roadmap; base_milestones; base_issues
  if [ "$flagval" = unset ]; then run reorder Beta --before Alpha
  else FORGE_DRY_RUN="$flagval" run reorder Beta --before Alpha; fi
  expect "FORGE_DRY_RUN=$flagval: reorder exits 0" 0 "$rc"
  first="$(grep -m1 '^## Phase:' "$T/docs/roadmap.md")"
  expect "FORGE_DRY_RUN=$flagval: the roadmap was written, Beta now comes first" "## Phase: Beta" "$first"
done

# #336: a flagged MERGE reaches confirm_emptied under CHECK=1, the only FLAGGED path that does (the flagged
# delete refuses earlier, and every other merge, rename and delete case is unflagged). Open ticket #10
# in Alpha is load-bearing: with an empty issue fixture both runs print "is now emptied" and only
# reads_all_zero kills a mutant that drops confirm_emptied's early --check return. With it, that mutant
# re-reads, finds #10 still in Alpha (nothing moved), and exits 4. The --check run is asserted
# ABSOLUTELY, since comparing the flagged run to it alone passes a mutant that changes both alike.
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"; ibefore="$(cat "$T/iss.json")"
run merge Alpha --into Beta --reason "dry" --check
ref_sout="$sout"; ref_serr="$serr"; ref_rc="$rc"
expect "the unflagged --check merge exits 0" 0 "$ref_rc"
expect "and prints no stderr" "" "$ref_serr"
contains 'would confirm "Alpha" holds zero open tickets before continuing' "$ref_sout" "and says it would confirm the loser is empty"
expect "and sent nothing to the host" "" "$(cat "$REQLOG")"
reads_all_zero "unflagged --check merge"
FORGE_DRY_RUN=1 run merge Alpha --into Beta --reason "dry"
expect "flagged merge exits as --check does" "$ref_rc" "$rc"
expect "its stdout equals the unflagged --check run" "$ref_sout" "$sout"
expect "its stderr equals the unflagged --check run" "$ref_serr" "$serr"
expect "and the roadmap is byte-identical" "$before" "$(cat "$T/docs/roadmap.md")"
expect "and no ticket moved" "$ibefore" "$(cat "$T/iss.json")"
expect "and no write reached the host" "" "$(cat "$REQLOG")"
reads_all_zero "flagged merge"

echo "== structural: missing libraries, a malformed roadmap, --help, an unknown op =="
base_roadmap; base_milestones; base_issues
mv "$T/roadmap-lib.sh" "$T/roadmap-lib.hidden"
run reorder Alpha --end
expect "a missing roadmap-lib.sh refuses" 2 "$rc"
contains "roadmap-lib.sh" "$out" "and names what is missing"
mv "$T/roadmap-lib.hidden" "$T/roadmap-lib.sh"
# The second extractor: --help after an op is read in the flag loop (#447).
out=$(cd "$T" && bash ./reassess-phases.sh reorder --help 2>&1); hrc=$?
first447=$(printf '%s\n' "$out" | awk 'NF{print; exit}')
case "$first447" in "Reshapes docs/roadmap.md itself"*) ok "reorder --help opens with the purpose line (#447)" ;; *) bad "reorder --help opens with the purpose line (#447) (got '$first447')" ;; esac
expect "reorder --help exits 0 (#447)" 0 "$hrc"
grep -q 'NO .awk -v. IN THIS FILE' <<< "$out" \
  && bad "reorder --help does not print the #259 maintainer note (#447)" \
  || ok "reorder --help does not print the #259 maintainer note (#447)"

mv "$T/forge-lib.sh" "$T/forge-lib.hidden"
mkdir -p "$T/nohome"
out=$(cd "$T" && HOME="$T/nohome" STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
      REQLOG="$REQLOG" bash ./reassess-phases.sh reorder Alpha --end 2>&1); rc=$?
expect "a missing forge-lib.sh refuses" 2 "$rc"
contains "forge-kit-devops" "$out" "and names the plugin group that provides it"
mv "$T/forge-lib.hidden" "$T/forge-lib.sh"

roadmap <<'MD'
## Phase: A
state: nonsense
MD
run reorder A --end
expect "a malformed roadmap exits 3" 3 "$rc"
expect "and nothing is sent to the host" "" "$(cat "$REQLOG")"

out=$(cd "$T" && bash ./reassess-phases.sh --help 2>&1)
hrc=$?
# #447: the #259 maintainer note sits below the header, so --help opens with what the script does.
first447=$(printf '%s\n' "$out" | awk 'NF{print; exit}')
case "$first447" in "Reshapes docs/roadmap.md itself"*) ok "--help opens with the purpose line (#447)" ;; *) bad "--help opens with the purpose line (#447) (got '$first447')" ;; esac
expect "--help exits 0 (#447)" 0 "$hrc"
grep -q 'NO .awk -v. IN THIS FILE' <<< "$out" \
  && bad "--help does not print the #259 maintainer note (#447)" \
  || ok "--help does not print the #259 maintainer note (#447)"
hb447=$(awk 'NR>1 && /^$/{print NR; exit}' "$T/reassess-phases.sh"); nl447=$(grep -n -m1 'NO .awk -v. IN THIS FILE' "$T/reassess-phases.sh" | cut -d: -f1)
expect "the #259 note stays in the source once, below the header (#447)" "1 below" \
  "$(grep -c 'NO .awk -v. IN THIS FILE' "$T/reassess-phases.sh") $([ "${nl447:-0}" -gt "${hb447:-0}" ] && echo below || echo above)"
contains "reassess-phases.sh" "$out" "--help prints the synopsis"

# #328: a refused refocus --plan writes nothing. The prose write used to land before the plan write
# could refuse, and --check (whose act never calls a writer) exited 0 where the real run refuses.
# Fixtures are one-off roadmaps in the base_roadmap shape: Dup has two column-0 plan lines, Solo has
# exactly one. $T/rm.before is a saved copy so "byte-identical" is a real cmp, not a $(cat) compare.
dup_roadmap() {
  roadmap <<'MD'
## Phase: Dup
state: planned
plan: docs/plans/a.md
plan: docs/plans/b.md

Dup's prose.

## Phase: Solo
state: planned
plan: docs/plans/a.md

Solo's prose.

## Phase: Zeta
state: done
plan: docs/plans/zeta.md

Zeta's prose, already closed.

## Phase: Beta
state: planned

Beta's prose.
MD
}
unchanged() {  # unchanged <label>: the roadmap is byte-identical to $T/rm.before
  if cmp -s "$T/rm.before" "$T/docs/roadmap.md"; then ok "$1: roadmap byte-identical"
  else bad "$1: roadmap changed ($(diff "$T/rm.before" "$T/docs/roadmap.md" | head -4 | tr '\n' ';'))"; fi
}
snap() { cp "$T/docs/roadmap.md" "$T/rm.before"; }
# Lines that differ between the saved copy and the roadmap, as "<>" lines only.
difflines() { diff "$T/rm.before" "$T/docs/roadmap.md" | grep '^[<>]' || true; }
empty_dir() {  # empty_dir <label> <dir>: no entries at all, dotfiles included
  if [ -z "$(find "$2" -mindepth 1 2>/dev/null)" ]; then ok "$1: TMPDIR left empty"
  else bad "$1: TMPDIR holds $(find "$2" -mindepth 1 | tr '\n' ' ')"; fi
}

echo "== #328 a refused refocus --plan writes nothing =="
dup_roadmap; base_milestones; base_issues; snap
run refocus Dup --prose "New prose" --plan docs/plans/x.md
expect "duplicate plan lines refuse" 5 "$rc"
contains "single column-0 plan line" "$serr" "and stderr names the cause"
unchanged "duplicate plan lines, live"

dup_roadmap; snap
run refocus Dup --prose "New prose" --plan docs/plans/x.md --check
expect "--check refuses duplicate plan lines" 5 "$rc"
contains "single column-0 plan line" "$serr" "and stderr names the same cause"
unchanged "duplicate plan lines, --check"

dup_roadmap; snap
run refocus Solo --prose "New prose" --plan docs/plans/x.md
expect "a single plan line succeeds" 0 "$rc"
contains "New prose" "$(cat "$T/docs/roadmap.md")" "Solo's prose landed"
contains "plan: docs/plans/x.md" "$(cat "$T/docs/roadmap.md")" "and its plan line"
expect "exactly Solo's prose and plan lines differ" 4 "$(difflines | wc -l | tr -d ' ')"
absent "Dup's prose" "$(difflines)" "and no other phase's lines differ"

# #328 pinned here that the plan dry run runs on the copy the PROSE dry run already modified, using a
# prose that is itself a column-0 plan line. #345 made roadmap-lib's _rm_prose_ok refuse that prose
# first (rc 5, "carries a column-0 'plan:' line"), so the prose-modified-copy ordering is no longer
# observable through this input and the two assertions below expect the new message. That is a
# decision, not drift: do not restore `single column-0 plan line` here. The ordering itself is still
# guarded by the Dup case above, where the plan write alone refuses.
dup_roadmap; snap
run refocus Solo --prose "plan: docs/plans/a.md" --plan docs/plans/x.md
expect "prose that adds a plan line refuses live" 5 "$rc"
contains "carries a column-0 'plan:' line" "$serr" "and stderr names the library's cause"
unchanged "prose-added plan line, live"

dup_roadmap; snap
run refocus Solo --prose "plan: docs/plans/a.md" --plan docs/plans/x.md --check
expect "--check refuses prose that adds a plan line" 5 "$rc"
contains "carries a column-0 'plan:' line" "$serr" "and stderr names the same cause"
unchanged "prose-added plan line, --check"

dup_roadmap; snap
run refocus Solo --prose "New prose" --plan "docs/plans/a.md " --check
expect "--check refuses the trailing-space plan path" 5 "$rc"
contains "reads the result differently" "$serr" "and stderr names the parse-back"
unchanged "trailing-space plan path, --check"

dup_roadmap; snap
run refocus Solo --prose "New prose" --plan docs/plans/x.md --check
expect "--check on a valid input exits 0" 0 "$rc"
contains "would refocus 'Solo'" "$sout" "and says what it would do"
unchanged "valid input, --check"

dup_roadmap; snap
run refocus Solo --prose "New prose" --plan "docs/plans/a.md "
expect "a trailing-space plan path refuses whole" 5 "$rc"
contains "reads the result differently" "$serr" "and stderr names the parse-back"
unchanged "trailing-space plan path, live (prose included)"

dup_roadmap; snap
run refocus Solo --prose "New prose" --plan docs/plans/b.md
expect "a clean plan path succeeds" 0 "$rc"
expect "exactly Solo's prose and plan lines differ" 4 "$(difflines | wc -l | tr -d ' ')"

base_roadmap; snap
run refocus Beta --prose "New prose"
expect "refocus without --plan still succeeds" 0 "$rc"
expect "and exactly Beta's prose lines differ" "< Beta's prose.
> New prose" "$(difflines)"

dup_roadmap; snap
run refocus Zeta --prose "New prose" --plan docs/plans/z.md
expect "a done phase is still refused" 5 "$rc"
contains "is done" "$serr" "and says why"
unchanged "done phase"

echo "== #328 prose the library refuses is caught live and under --check =="
dup_roadmap; snap
run refocus Solo --prose "## Bad"
expect "'## ' prose refuses live (regression guard)" 5 "$rc"
contains "opens a '## ' section" "$serr" "and says why"
unchanged "'## ' prose, live"

dup_roadmap; snap
run refocus Solo --prose "## Bad" --check
expect "'## ' prose refuses under --check" 5 "$rc"
contains "opens a '## ' section" "$serr" "and says why"
unchanged "'## ' prose, --check"

# #345 item 6: a keyed line in the prose is the library's refusal, reached through the script.
dup_roadmap; snap
run refocus Solo --prose $'Para.\nstate: planned'
expect "prose carrying a state line refuses live" 5 "$rc"
contains "carries a column-0 'state:' line" "$serr" "and stderr names the key"
contains "nothing written" "$serr" "and says nothing was written"
unchanged "state-line prose, live"

dup_roadmap; snap
run refocus Solo --prose $'Para.\nstate: planned' --check
expect "prose carrying a state line refuses under --check" 5 "$rc"
unchanged "state-line prose, --check"

dup_roadmap; snap
run refocus Solo --prose "Plain prose"
expect "ordinary prose succeeds" 0 "$rc"
expect "and exactly Solo's prose lines differ" "< Solo's prose.
> Plain prose" "$(difflines)"

echo "== #328 no temp file is left behind, and an unusable TMPDIR is refused =="
# #345: each case gets its OWN directory, made with mkdir -p before the run. Two cases sharing one
# directory turned both red when only one leaked, and a directory that does not exist would make the
# TMPDIR refusal and empty_dir pass vacuously.
mkdir -p "$T/tmp345-refused" "$T/tmp345-ok"
dup_roadmap; snap
RUN_TMPDIR="$T/tmp345-refused" run refocus Dup --prose "New prose" --plan docs/plans/x.md
expect "a refused run exits 5" 5 "$rc"
contains "single column-0 plan line" "$serr" "and stderr names the plan cause, not the TMPDIR refusal"
empty_dir "refused run" "$T/tmp345-refused"

dup_roadmap; snap
RUN_TMPDIR="$T/tmp345-ok" run refocus Solo --prose "New prose" --plan docs/plans/x.md
expect "a successful run exits 0" 0 "$rc"
empty_dir "successful run" "$T/tmp345-ok"

dup_roadmap; snap
RUN_TMPDIR="$T/no-such-dir" run refocus Solo --prose "New prose" --plan docs/plans/x.md
expect "a missing TMPDIR is refused" 5 "$rc"
contains "cannot make a scratch copy" "$serr" "and says the scratch copy could not be made"
contains "nothing written" "$serr" "and says nothing was written"
unchanged "missing TMPDIR"

# #345 fixtures. "Twin" holds two `## Phase: Dup` blocks, then Lose and Win; "plain" is the same with
# one Dup. The milestones list Dup, Lose and Win. A ticket sits where each case says.
twin_roadmap() {
  roadmap <<'MD'
## Phase: Dup
state: planned

Dup one.

## Phase: Dup
state: planned

Dup two.

## Phase: Lose
state: planned

Lose prose.

## Phase: Win
state: planned

Win prose.
MD
}
plain_roadmap() {
  roadmap <<'MD'
## Phase: Dup
state: planned

Dup prose.

## Phase: Lose
state: planned

Lose prose.

## Phase: Win
state: planned

Win prose.
MD
}
ms345() { printf '[{"id":1,"title":"Dup","state":"open"},{"id":2,"title":"Lose","state":"open"},{"id":3,"title":"Win","state":"open"}]' > "$T/ms.json"; }
no_move() { absent "MOVE" "$(cat "$REQLOG")" "$1: no MOVE reached the host"; }
no_request() { expect "$1: the host received no request" "" "$(cat "$REQLOG")"; }

echo "== #345 an unwritable TMPDIR refuses refocus, delete and merge whole =="
if [ "$(id -u)" = 0 ]; then
  echo "  skip: running as root, a mode 555 directory is still writable"
else
  mkdir -p "$T/tmp345-ro"; chmod 555 "$T/tmp345-ro"
  if [ -w "$T/tmp345-ro" ]; then bad "the read-only TMPDIR fixture is still writable"; else ok "the read-only TMPDIR fixture is unwritable"; fi
  dup_roadmap; base_milestones; base_issues; snap
  RUN_TMPDIR="$T/tmp345-ro" run refocus Solo --prose "New prose"
  expect "refocus: an unwritable TMPDIR exits 5" 5 "$rc"
  contains "cannot make a scratch copy" "$serr" "refocus: and says so"
  unchanged "refocus, unwritable TMPDIR"
  plain_roadmap; ms345; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"; snap
  RUN_TMPDIR="$T/tmp345-ro" run delete Lose --to Win
  expect "delete: an unwritable TMPDIR exits 5" 5 "$rc"
  contains "cannot make a scratch copy" "$serr" "delete: and says so"
  no_move "delete, unwritable TMPDIR"
  unchanged "delete, unwritable TMPDIR"
  RUN_TMPDIR="$T/tmp345-ro" run merge Lose --into Win --reason r
  expect "merge: an unwritable TMPDIR exits 5" 5 "$rc"
  contains "cannot make a scratch copy" "$serr" "merge: and says so"
  no_move "merge, unwritable TMPDIR"
  unchanged "merge, unwritable TMPDIR"
  chmod 755 "$T/tmp345-ro"
fi

echo "== #345 a refused delete writes nothing and contacts no host =="
base_roadmap; base_milestones; base_issues
run delete Alpha --reason "dropped"
expect "delete of an unopened phase exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the block is gone"
contains 'Deleted phase "Alpha": dropped' "$(cat "$T/docs/roadmap.md")" "and Notes holds the line"
snap
run delete Alpha --reason "dropped"
expect "the identical delete re-run exits 0" 0 "$rc"
contains "already removed from the roadmap" "$out" "and says it skipped"
unchanged "delete re-run"
no_request "delete re-run"

twin_roadmap; ms345; base_issues; snap
run delete Dup
expect "a duplicate heading refuses" 5 "$rc"
contains "two phases are named 'Dup'" "$serr" "and names the cause"
unchanged "delete of a duplicate heading"
no_request "delete of a duplicate heading"
run delete Dup --check
expect "--check agrees on the duplicate heading" 5 "$rc"
FORGE_DRY_RUN=1 run delete Dup
expect "FORGE_DRY_RUN=1 agrees on the duplicate heading" 5 "$rc"
unchanged "delete of a duplicate heading, --check and the flag"

twin_roadmap; printf '[{"number":10,"milestone":"Dup"}]' > "$T/iss.json"; snap
run delete Dup --to Win
expect "a duplicate heading with a ticket to relocate refuses" 5 "$rc"
no_move "delete of a duplicate heading with a ticket"
unchanged "delete of a duplicate heading with a ticket"

plain_roadmap; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"; snap
run delete Lose --to Win --reason $'x\n## Phase: Evil'
expect "a reason that would malform the notes exits 2" 2 "$rc"
contains "that note would leave the roadmap malformed" "$serr" "and names the cause"
no_move "delete with a malforming reason"
unchanged "delete with a malforming reason"
run delete Lose --to Win --reason $'x\n## Phase: Evil' --check
expect "--check agrees on the malforming reason" 2 "$rc"
unchanged "delete with a malforming reason, --check"

echo "== #345 a refused merge writes nothing and contacts no host =="
twin_roadmap; ms345; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"
run merge Lose --into Win --reason "consolidating scope"
expect "a legitimate merge beside a twin heading exits 0" 0 "$rc"
contains "MOVE 11 Win" "$(cat "$REQLOG")" "and its ticket moved"
absent "## Phase: Lose" "$(cat "$T/docs/roadmap.md")" "and Lose is gone"
contains 'Merged "Lose" in: consolidating scope' "$(cat "$T/docs/roadmap.md")" "and Win carries the reason"
snap
run merge Lose --into Win --reason "consolidating scope"
expect "the identical merge re-run exits 0" 0 "$rc"
contains "already merged away" "$out" "and says it skipped"
no_request "merge re-run"
unchanged "merge re-run"

plain_roadmap; ms345; printf '[{"number":11,"milestone":"Lose"},{"number":12,"milestone":"Lose"}]' > "$T/iss.json"; snap
run merge Lose --into Win --reason $'why\n## oops'
expect "a reason that opens a section refuses" 5 "$rc"
contains "opens a '## ' section" "$serr" "and names the cause"
no_move "merge with a section-opening reason"
unchanged "merge with a section-opening reason"
run merge Lose --into Win --reason $'why\n## oops' --check
expect "--check agrees on the section-opening reason" 5 "$rc"
unchanged "merge with a section-opening reason, --check"

plain_roadmap; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"; snap
# Deliberately no library message in this Then: item 6 owns the keyed-line wording.
run merge Lose --into Win --reason $'x\nstate: done'
expect "a reason carrying a keyed line refuses" 5 "$rc"
no_move "merge with a keyed-line reason"
unchanged "merge with a keyed-line reason"

twin_roadmap; printf '[]' > "$T/iss.json"; snap
run merge Dup --into Win --reason r
expect "a duplicate loser refuses" 5 "$rc"
contains "two phases are named 'Dup'" "$serr" "and names the cause"
no_request "merge of a duplicate loser"
unchanged "merge of a duplicate loser"

twin_roadmap; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"; snap
run merge Lose --into Dup --reason r
expect "a duplicate winner refuses" 5 "$rc"
no_move "merge into a duplicate winner"
unchanged "merge into a duplicate winner"

# Mutants: with the dry run turned into a no-op, the refusal cases above must fail again because the
# ticket moves first. The sed replaces the CALL only and leaves the definition alone.
cp "$T/reassess-phases.sh" "$T/rp-keep.sh"
sed 's/dry_run delete delete_file_half/: delete delete_file_half/' "$T/rp-keep.sh" > "$T/reassess-phases.sh"
if cmp -s "$T/rp-keep.sh" "$T/reassess-phases.sh"; then bad "#345: mutant: the delete dry run was not removed"
else
  twin_roadmap; ms345; printf '[{"number":10,"milestone":"Dup"}]' > "$T/iss.json"; run delete Dup --to Win
  if grep -q "MOVE" "$REQLOG"; then ok "#345: mutant: without the delete dry run the ticket moves before the refusal"
  else bad "#345: mutant: without the delete dry run no MOVE was sent"; fi
fi
sed 's/dry_run merge merge_file_half/: merge merge_file_half/' "$T/rp-keep.sh" > "$T/reassess-phases.sh"
if cmp -s "$T/rp-keep.sh" "$T/reassess-phases.sh"; then bad "#345: mutant: the merge dry run was not removed"
else
  plain_roadmap; ms345; printf '[{"number":11,"milestone":"Lose"}]' > "$T/iss.json"; run merge Lose --into Win --reason $'why\n## oops'
  if grep -q "MOVE" "$REQLOG"; then ok "#345: mutant: without the merge dry run the ticket moves before the refusal"
  else bad "#345: mutant: without the merge dry run no MOVE was sent"; fi
fi
cp "$T/rp-keep.sh" "$T/reassess-phases.sh"; rm -f "$T/rp-keep.sh"

base_roadmap; base_milestones; base_issues
run bogus-op Alpha
expect "an unknown op is a usage error" 2 "$rc"

echo "== portability =="
code() { grep -v '^[[:space:]]*#' "$1"; }
# #345: ONE global scratch path and ONE trap that reads it (a `local` read by an EXIT trap is unbound
# once the function returns, and a per-op trap replaces the one before it).
expect "#345: exactly one EXIT trap in the shipped asset" 1 "$(code "$SRC" | grep -c "trap '")"
expect "#345: and it reads the global scratch path" 1 "$(code "$SRC" | grep -c 'trap .rm -f "${_SCRATCH-}". EXIT')"
expect "#345: and no local scratch remains" 0 "$(code "$SRC" | grep -c 'local scratch')"
grep -q 'readlink -f' <<< "$(code "$SRC")" \
  && bad "avoids GNU-only readlink -f" || ok "avoids GNU-only readlink -f"
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SRC" \
  && ok "carries a version marker" || bad "carries a version marker"

if [ -s "$T/shim/live.log" ]; then
  bad "a suite case reached a live forge: $(head -3 "$T/shim/live.log" | tr '\n' ';')"
else
  ok "no live forge call (the gh/curl shim log is empty)"
fi

echo "== no awk -v in the shipped asset, and a backslash path is printed as typed (#259) =="
# #405: the zero-`awk -v` rule and the no-operand rule, one definition in scripts/awkv-count.sh.
. "$ROOT/scripts/awkv-count.sh"; awkv_checks reassess-phases.sh "$SRC" "$T"
# #413: a MALFORMED phase FIRST, then 2000 well-formed ones, so parse_roadmap prints over 64 KiB.
# `printf | grep -q '^MALFORMED'` under pipefail lost that first-row match in 186 to 198 runs of 200
# unloaded (grep exits at the match, printf takes SIGPIPE, the pipeline reads 141, the refusal is
# skipped). Three calls must each refuse; a scratch copy with the pipe form restored must not.
awk 'BEGIN { printf "## Phase: Bad one\nstate: bogus\n\nWhy.\n\n"; for (i = 0; i < 2000; i++) printf "## Phase: P%d\nstate: planned\nplan: docs/plans/a-long-plan-name-that-grows-the-parse-output-past-64k.md\n\nWhy %d.\n\n", i, i }' > "$T/big.md"
n3=0; for i in 1 2 3; do run reorder P1 --before P0 --check --roadmap big.md </dev/null; [ "$rc" = 3 ] && n3=$((n3 + 1)); done
expect "#413: a large roadmap with its MALFORMED phase first exits 3 on each of three runs" 3 "$n3"
P='|'; cp "$T/reassess-phases.sh" "$T/rp-keep.sh"; sed "s/if grep -q '^MALFORMED' <<< \"\$PHASES\"; then/if printf '%s\\\\n' \"\$PHASES\" $P grep -q '^MALFORMED'; then/" "$T/rp-keep.sh" > "$T/reassess-phases.sh"
n3=0; for i in 1 2 3; do run reorder P1 --before P0 --check --roadmap big.md </dev/null; [ "$rc" = 3 ] && n3=$((n3 + 1)); done
if cmp -s "$T/rp-keep.sh" "$T/reassess-phases.sh"; then bad "#413: mutant: the pipe form was not restored"
elif [ "$n3" -lt 3 ]; then ok "#413: mutant: the pipe form lets the malformed roadmap through ($((3 - n3)) of 3 runs)"
else bad "#413: mutant: the pipe form still refused all three runs"; fi
cp "$T/rp-keep.sh" "$T/reassess-phases.sh"; rm -f "$T/rp-keep.sh" "$T/big.md"
# #405: a roadmap named name=value reads the same as the plain name (the path text aside).
printf '## Phase: A\nstate: open\nplan: docs/plans/a.md\n\nWhy A.\n\n## Phase: B\nstate: planned\nplan:\n\nWhy B.\n' > "$T/x.md"
cp "$T/x.md" "$T/r=x.md"; [ -f "$T/ms.json" ] || printf '[]' > "$T/ms.json"
run reorder B --before A --check --roadmap x.md </dev/null; plain_rc=$rc; plain_out=$(printf '%s' "$out" | sed 's/x\.md/ROADMAP/g')
run reorder B --before A --check --roadmap 'r=x.md' </dev/null
expect "#405: --roadmap 'r=x.md' exits as x.md does ($plain_rc)" "$plain_rc" "$rc"
expect "#405: and prints the same output" "$plain_out" "$(printf '%s' "$out" | sed 's/r=x\.md/ROADMAP/g')"
[ -n "$plain_out" ] && ok "#405: the control printed something to compare" || bad "#405: the control printed nothing"
rm -f "$T/x.md" "$T/r=x.md"
printf '## Phase: A\nstate: bogus\n\nx\n' > "$T/r\\tmap.md"
run reorder A --end --check --roadmap 'r\tmap.md'
expect "a malformed roadmap at a backslash path still exits 3" 3 "$rc"
contains 'r\tmap.md' "$serr" "and the diagnostic names r\\tmap.md with its backslash"
case "$serr" in *"$(printf '\t')"*) bad "and the diagnostic carries no TAB byte (the -v escape pass)" ;; *) ok "and the diagnostic carries no TAB byte (the -v escape pass)" ;; esac
rm -f "$T/r\\tmap.md"
# A phase NAME carrying backslash-t: under -v the lookup compared against a TAB and refused it.
base_roadmap; base_issues
printf '\n## Phase: a\\tb\nstate: planned\n\nA backslash phase.\n' >> "$T/docs/roadmap.md"
cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Beta","state":"open"},
 {"id":3,"title":"Zeta","state":"closed"},{"id":4,"title":"Cellar","state":"open"},
 {"id":5,"title":"a\\tb","state":"open"}]
JSON
run reorder 'a\tb' --end --check
expect "a phase named a\\tb is found by reorder --check" 0 "$rc"
expect "and the preview names it as typed" "would reorder 'a\\tb' to the end" "$(printf '%s\n' "$sout" | head -1)"
run reorder zzz --end --check
expect "an unknown phase still refuses with 5" 5 "$rc"
expect "and says so" "reassess-phases: no phase named 'zzz'" "$serr"

echo ""
echo "reassess-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
