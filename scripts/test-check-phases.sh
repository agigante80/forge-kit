#!/usr/bin/env bash
# Contract test for check-phases.sh, the roadmap-phases guards (forge-kit-roadmap).
#
# Rules 1, 3 and 4 need the host, so they run against a STUBBED forge-lib.sh placed beside a copy of
# the script, the same seam test-sync-labels.sh uses. Rule 2 is file-only and needs no stub.
#
# EVERY RULE GETS A NEAR-MISS. These are refusal rules, and a refusal rule fails by being too eager:
# one that rejects a legitimate roadmap gets deleted rather than fixed. The near-misses here are the
# states that must NOT require a plan (planned, backlog) and the roadmap that does not exist at all.
set -uo pipefail
# #287: an inherited environment must not steer resolution. FORGE_LIB is consulted before anything
# else, and GIT_DIR/GIT_WORK_TREE (which git exports into hooks, and pre-push runs this suite) override
# the ceiling below. The set is complete for `rev-parse --show-toplevel` (git(1) and git-config(1)
# ENVIRONMENT, 2.43, #288): GIT_DISCOVERY_ACROSS_FILESYSTEM only lets a search cross a mount the
# ceiling still stops, GIT_CONFIG_COUNT and GIT_CONFIG_PARAMETERS act on a repository already found,
# which the ceiling prevents, and GIT_NAMESPACE scopes refs only. All three are ruled out, not missed.
# #306: FORGE_DRY_RUN joins the list because the host stub below now honours it as forge-lib v28 does:
# an inherited flag from a maintainer shell or the pre-push hook would steer every case. Each dry-run
# case passes it per call (`FORGE_DRY_RUN=1 hostrun ...`).
unset FORGE_DRY_RUN FORGE_LIB GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qiF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
# #336: literal, case-sensitive absence (no -i, unlike contains, since rule lines are lower case on
# purpose). -F is load-bearing: without it a pattern's dot matches any character.
# Both properties are pinned in the "== absent_line self-test (#336) ==" section below.
absent_line() { if grep -qF -- "$1" <<< "$2"; then bad "$3"; else ok "$3"; fi; }

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
cp "$SRC" "$T/check-phases.sh"
cp "$(dirname "$SRC")/roadmap-lib.sh" "$T/roadmap-lib.sh" 2>/dev/null || true

goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }
out=""; rc=0
run() { out=$(cd "$T" && bash ./check-phases.sh "$@" 2>&1); rc=$?; }

echo "== absent_line self-test (#336) =="
# #336: absent_line matches LITERALLY and case-sensitively (the comment above its definition, pinned here).
# The probes run in subshells so a deliberate failure never touches this suite's counters; `bad` prints
# with a two-space prefix, so the output is checked with contains rather than equality. "a.b" must not
# match "axb" (a regex dot would), and must match "a.b". "rule 3" must not match "Rule 3: x" (a -i would).
probe_pass="$( absent_line "a.b" "axb" "probe" )"
contains "ok: probe" "$probe_pass" "absent_line treats a dot literally: 'a.b' is absent from 'axb'"
probe_fail="$( absent_line "a.b" "a.b" "probe" )"
contains "FAIL: probe" "$probe_fail" "and fails when the literal text is present"
probe_case="$( absent_line "rule 3" "Rule 3: x" "probe" )"
contains "ok: probe" "$probe_case" "absent_line is case-sensitive: 'rule 3' is absent from 'Rule 3: x'"

echo "== rule 2: an open phase needs a plan carrying a Fails if section =="
goodplan A > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

why A exists
MD
run --offline
expect "an open phase with a complete plan passes" 0 "$rc"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/missing.md
MD
run --offline
expect "an open phase whose plan file is absent fails" 1 "$rc"
contains "rule 2" "$out" "and names the rule"

printf '# A\n\n## Goal\nx\n\n## Done looks like\nx\n' > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
run --offline
expect "a plan with no Fails if section fails" 1 "$rc"
contains "Fails if" "$out" "and says which section is missing"
contains "premortem" "$out" "and gives the prompt for writing it"

goodplan A > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
MD
run --offline
expect "an open phase declaring no plan at all fails" 1 "$rc"

echo "== the near-misses: states that must NOT require a plan =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: planned

not started, so no plan needed yet
MD
run --offline
expect "a planned phase needs no plan" 0 "$rc"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: Backlog
state: backlog
MD
run --offline
expect "backlog needs no plan" 0 "$rc"

# The hole the spec's self-review found: planned straight to done would otherwise never pass
# through the state where a plan is required.
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/never-written.md
MD
run --offline
expect "a done phase with no plan file fails too" 1 "$rc"

echo "== the parser refuses a malformed roadmap rather than skipping the block =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A

no state line at all
MD
run --offline
expect "a phase block with no state refuses the run" 3 "$rc"
contains "no state" "$out" "and says what is wrong"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: nonsense
MD
run --offline
expect "an unknown state value refuses the run" 3 "$rc"
contains "planned" "$out" "and lists the states it accepts"

# A refusal must be total. A roadmap with one bad block and one good one checks NOTHING.
goodplan A > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: typo
MD
run --offline
expect "one malformed block refuses the whole file" 3 "$rc"

echo "== ordinary prose in the roadmap is not a phase =="
cat > "$T/docs/roadmap.md" <<'MD'
# forge-kit roadmap

Some introduction, with a ## Heading that is not a phase.

## How to read this

Prose.

## Phase: A
state: open
plan: docs/plans/a.md
MD
run --offline
expect "only '## Phase:' headings are parsed as phases" 0 "$rc"

echo "== no roadmap at all is not an error =="
rm -f "$T/docs/roadmap.md"
run --offline
expect "a project with no roadmap exits 0" 0 "$rc"
contains "no roadmap" "$out" "and says so rather than passing silently"

echo "== --offline says what it did not check =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
run --offline
contains "were NOT checked" "$out" "--offline states that the host rules did not run"

echo "== the host rules, against a stubbed transport =="
# The stub sits beside the copied script, so the script sources it instead of the real forge-lib.
# Nothing here touches a network or a real forge.
cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
# #306: these list stubs model forge-lib v28 under FORGE_DRY_RUN=1: forge_api_paginate returns a
# literal `[]` for every method, GET included. Each call appends the value of the flag it SAW to
# $READLOG ("ms <value>" or "iss <value>", "unset" when the variable is not set), so a read that is
# not scoped is visible. STUB_LIST_FAIL fails a list whatever the flag is: `iss` only the issue list,
# any other non-empty value both. A stub that failed only under the flag would never fail once the
# read runs with the flag at 0.
forge_milestone_list() {
  printf 'ms %s\n' "${FORGE_DRY_RUN-unset}" >> "$READLOG"
  [ -n "${STUB_LIST_FAIL:-}" ] && [ "$STUB_LIST_FAIL" != iss ] && return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[]'; else cat "$STUB_MILESTONES"; fi
}
forge_issue_milestone_list() {
  printf 'iss %s\n' "${FORGE_DRY_RUN-unset}" >> "$READLOG"
  [ -n "${STUB_LIST_FAIL:-}" ] && return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[]'; else cat "$STUB_ISSUES"; fi
}
STUB
READLOG="$T/read.log"
# #306: stdout and stderr are captured SEPARATELY ($sout, $serr) so a case can compare them one by
# one; $out is both joined, which is what every older assertion reads.
sout=""; serr=""
hostrun() {
  : > "$READLOG"
  (cd "$T" && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" READLOG="$READLOG" \
        bash ./check-phases.sh "$@" >"$T/run.out" 2>"$T/run.err"); rc=$?
  sout=$(cat "$T/run.out"); serr=$(cat "$T/run.err"); out="$sout
$serr"
}
# Both list reads of a FLAGGED run must have seen the flag at 0. Only a flagged case that really runs
# a read's code path can fail for an unscoped read; a read added later on a path no flagged case
# reaches is not covered by this.
reads_all_zero() {
  local n bad_lines
  n=$(wc -l < "$READLOG" | tr -d ' ')
  bad_lines=$(grep -vc ' 0$' "$READLOG" || true)
  if [ "${n:-0}" -ge 2 ] && [ "$bad_lines" = 0 ]; then ok "$1: both list reads ($n) saw FORGE_DRY_RUN=0"
  else bad "$1: list reads did not all see FORGE_DRY_RUN=0 ($(tr '\n' ';' < "$READLOG"))"; fi
}

goodplan A > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
hostrun
expect "a consistent roadmap and host pass" 0 "$rc"

echo "-- rule 1: every open ticket has a phase --"
printf '[{"number":7,"milestone":"A"},{"number":9,"milestone":null}]' > "$T/iss.json"
hostrun
expect "a ticket with no phase fails" 1 "$rc"
contains "rule 1" "$out" "and names the rule"
contains "#9" "$out" "and names the ticket"
contains "backlog" "$out" "and points at backlog as the decision to decide later"

echo "-- rule 3: states agree, and one phase is open --"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
hostrun
expect "an open phase whose milestone is closed fails" 1 "$rc"
contains "rule 3" "$out" "and names the rule"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[]' > "$T/iss.json"
hostrun
expect "a done phase whose milestone is open fails" 1 "$rc"

goodplan B > "$T/docs/plans/b.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: open
plan: docs/plans/b.md
MD
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"B","state":"open"}]' > "$T/ms.json"
hostrun
expect "two open phases fail" 1 "$rc"
contains "at most one" "$out" "and says why"

# The near-miss: backlog is open forever and must not count toward the one-open-phase rule.
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: Backlog
state: backlog
MD
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"Backlog","state":"open"}]' > "$T/ms.json"
hostrun
expect "backlog alongside one open phase is fine" 0 "$rc"

echo "-- rule 4: a done phase holds no open tickets --"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
hostrun
expect "a done phase holding an open ticket fails" 1 "$rc"
contains "rule 4" "$out" "and names the rule"
contains "re-shape, never extend" "$out" "and says to move the ticket rather than extend the phase"

printf '[]' > "$T/iss.json"
hostrun
expect "a done phase with nothing open passes" 0 "$rc"

echo "-- a phase with no milestone yet --"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[]' > "$T/ms.json"
printf '[]' > "$T/iss.json"
hostrun
expect "a phase with no milestone fails" 1 "$rc"
contains "sync-phases" "$out" "and points at the script that fixes it"

echo "-- FORGE_DRY_RUN=1 changes nothing: the reads see the real host (#306) --"
# check-phases.sh has no write path, so a flagged run must print exactly what an unflagged one does.
# Fixture: phase A is open (its plan carries a Fails if section, rule 2), phase B is done (plan too).
goodplan A > "$T/docs/plans/a.md"; goodplan B > "$T/docs/plans/b.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: done
plan: docs/plans/b.md
MD
# Positive, the clean verdict: milestone A open, B closed, every open ticket in a phase.
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"B","state":"closed"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
hostrun
expect "unflagged: the consistent host is clean" 0 "$rc"
FORGE_DRY_RUN=1 hostrun
expect "flagged: a clean verdict exits 0" 0 "$rc"
expect "flagged: with no stdout" "" "$sout"
expect "flagged: and no stderr" "" "$serr"
reads_all_zero "flagged clean run"

# Positive, rules 1 and 4: issue #7 in no phase, issue #8 open in the done phase B.
printf '[{"number":7,"milestone":null},{"number":8,"milestone":"B"}]' > "$T/iss.json"
hostrun
ref_sout="$sout"; ref_serr="$serr"; ref_rc="$rc"
expect "unflagged: rules 1 and 4 fail" 1 "$ref_rc"
FORGE_DRY_RUN=1 hostrun
expect "flagged: rules 1 and 4 still exit 1" 1 "$rc"
contains "rule 1: issue #7 has no phase." "$sout" "flagged: names the ticket with no phase"
contains 'rule 4: phase "B" is done but holds 1 open ticket(s).' "$sout" "flagged: names the done phase holding a ticket"
absent_line "rule 3" "$sout" "flagged: and prints no rule 3 line"
expect "flagged: stdout equals the unflagged run" "$ref_sout" "$sout"
expect "flagged: stderr equals the unflagged run" "$ref_serr" "$serr"
reads_all_zero "flagged rules 1 and 4 run"

# Negative, rule 3: B is PLANNED here (a planned phase needs no plan and cannot trip the at-most-one
# open rule), and only milestone A exists. Exactly one rule 3 line, for B, none for A.
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: planned
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
FORGE_DRY_RUN=1 hostrun
expect "flagged: a missing milestone exits 1" 1 "$rc"
expect "flagged: with exactly the one rule 3 line, for B" 'rule 3: phase "B" has no milestone on the host. Run sync-phases.sh.' "$sout"
expect "flagged: and no stderr" "" "$serr"
reads_all_zero "flagged missing-milestone run"

# Negative: a failed issue read is still a read failure, whatever the flag. (The ms.json rewrite below
# is dead setup: the read fails before any rule runs. The roadmap is the rule-3 case's above
# (B planned), and an open milestone is the consistent state for a planned phase; do not "fix" it
# to closed, that would be a real rule 3 inconsistency, #336.)
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"B","state":"open"}]' > "$T/ms.json"
STUB_LIST_FAIL=iss FORGE_DRY_RUN=1 hostrun
expect "flagged: a failed issue read exits 2" 2 "$rc"
contains "check-phases: the host could not be reached, so rules 1, 3 and 4 were SKIPPED." "$serr" "flagged: and says the host rules were skipped"
reads_all_zero "flagged failed read"

echo "-- a check that cannot run must never report clean --"
cp "$T/forge-lib.sh" "$T/forge-lib.good.sh"
cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { return 2; }
forge_host() { printf 'github'; }
forge_milestone_list()       { return 2; }
forge_issue_milestone_list() { return 2; }
STUB
hostrun
expect "an unreachable host exits 2, not 0" 2 "$rc"
contains "SKIPPED" "$out" "and says the host rules were skipped"
contains "NOT passed" "$out" "and says they were not passed"
cp "$T/forge-lib.good.sh" "$T/forge-lib.sh"

rm -f "$T/forge-lib.sh" "$T/forge-lib.good.sh"
# HOME is redirected so the resolver's last resort, ~/.claude/plugins, finds nothing either. Without
# this the fixture picked up the REAL forge-lib from the plugin cache and took a different error
# path, so the assertions below passed against the wrong message.
mkdir -p "$T/nohome"
out=$(cd "$T" && HOME="$T/nohome" STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
      bash ./check-phases.sh 2>&1); rc=$?
expect "a missing forge-lib.sh exits 2 rather than reporting clean" 2 "$rc"
# #161: a clean install of this group ALONE has no forge-lib anywhere, and three of the four rules
# then cannot run. The failure is loud, which is right, but it must name exactly what else to
# install rather than describing it.
contains "forge-kit-devops" "$out" "and names the plugin group that provides it"
contains "/plugin install" "$out" "as a command that can be run"
cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list()       { cat "$STUB_MILESTONES"; }
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB

echo "== #446: rules 1 and 4 over the REAL forge_issue_milestone_list on Forgejo =="
# The stub above returns already-flattened issues, so it can never see the filter #446 broke: the
# real function dropped EVERY Forgejo issue (each carries "pull_request": null), and rules 1 and 4
# then passed over an empty list. This wrapper sources the real library and stubs only forge_api,
# with Forgejo's wire shape; the milestone list keeps the stub, since #446 is about the issue read.
LIB446="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh"
cat > "$T/lib446.sh" <<STUB
. "$LIB446"
export FORGE_HOST=forgejo FORGE_REPO=o/r
forge_api() { case "\$2" in *"/issues?"*page=1*) cat "\$ISS446" ;; *) printf '[]' ;; esac; }
forge_milestone_list() { cat "\$STUB_MILESTONES"; }
STUB
run446() {
  out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" ISS446="$T/iss446.json" \
        FORGE_LIB="$T/lib446.sh" bash ./check-phases.sh 2>&1); rc=$?
}
goodplan A > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[{"number":21,"pull_request":null,"milestone":{"title":"A"}},{"number":22,"pull_request":null,"milestone":null}]' > "$T/iss446.json"
run446
expect "#446: a Forgejo issue (pull_request null) with no phase fails rule 1" 1 "$rc"
contains "rule 1: issue #22 has no phase." "$out" "#446: and names issue #22"
printf '[{"number":21,"pull_request":null,"milestone":{"title":"A"}},{"number":23,"pull_request":{"merged":false},"milestone":null}]' > "$T/iss446.json"
run446
expect "#446: a Forgejo PR with no phase is not a ticket, so rule 1 passes" 0 "$rc"
absent_line "#23" "$out" "#446: and the PR number is never reported"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
printf '[{"number":22,"pull_request":null,"milestone":{"title":"A"}}]' > "$T/iss446.json"
run446
expect "#446: a done phase holding a Forgejo issue fails rule 4" 1 "$rc"
contains 'rule 4: phase "A" is done but holds 1 open ticket(s).' "$out" "#446: and names phase A and the count"
printf '[{"number":23,"pull_request":{"merged":false},"milestone":{"title":"A"}}]' > "$T/iss446.json"
run446
expect "#446: a Forgejo PR in a done phase's milestone is not a ticket, so rule 4 passes" 0 "$rc"
absent_line "rule 4" "$out" "#446: and no rule 4 line is printed for it"

echo "== forge-lib.sh resolves by SEARCH, not only by adjacency =="
# The two assets belong to DIFFERENT skills, so in the source tree they can never sit beside each
# other, and in a forge-adapt install they both land in scripts/ and can. Resolving only by
# adjacency works in one shape and silently degrades in the other, which is the failure
# .claude/memory/shipped-asset-path-resolution.md exists to warn about.
mkdir -p "$T/elsewhere"
mv "$T/forge-lib.sh" "$T/elsewhere/forge-lib.sh"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
      FORGE_LIB="$T/elsewhere/forge-lib.sh" bash ./check-phases.sh 2>&1); rc=$?
expect "FORGE_LIB points it at a library that is not adjacent" 0 "$rc"
mv "$T/elsewhere/forge-lib.sh" "$T/forge-lib.sh"

echo "== the last-resort search picks the HIGHEST marker, never the first hit (#189) =="
# ~/.claude/plugins holds plugin versions SIDE BY SIDE (the cache keeps every installed semver and
# the marketplace checkout is a fifth copy), and `find` returns them in directory order. The old
# `find ... | head -1` therefore selected an arbitrary copy, and on the machine that filed #189 it
# selected a stale one in three gate runs out of four. The rule now: highest `forge-lib-version`
# marker wins, lexical path breaks a tie (an equal marker implies an equal committed body, which
# check-version-bump.sh enforces), and the choice is PRINTED so a stale pick is visible in the run.
# Two copies at v1 and one at v9, so a first-hit pick is wrong two times in three even before the
# provenance line is checked; the provenance assertion is the deterministic half.
mv "$T/forge-lib.sh" "$T/forge-lib.hidden"
H="$T/home189"; rm -rf "$H"; mkdir -p "$H/.claude/plugins/cache/g/0.1.0" "$H/.claude/plugins/cache/g/0.2.0" "$H/.claude/plugins/marketplaces/m"
for d in cache/g/0.1.0 cache/g/0.2.0; do
  cat > "$H/.claude/plugins/$d/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 1
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list()       { echo 'STALE COPY' >&2; return 2; }
forge_issue_milestone_list() { return 2; }
STUB
done
cat > "$H/.claude/plugins/marketplaces/m/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 9
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list()       { cat "$STUB_MILESTONES"; }
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB
out=$(cd "$T" && HOME="$H" STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
      bash ./check-phases.sh 2>&1); rc=$?
expect "the highest-marker copy is the one sourced" 0 "$rc"
[ "${out#*STALE COPY}" = "$out" ] && ok "and no stale copy ran" || bad "a stale copy ran: $out"
contains "marketplaces/m/forge-lib.sh" "$out" "and the run prints the path it chose"
contains "forge-lib-version: 9" "$out" "with its marker"
mv "$T/forge-lib.hidden" "$T/forge-lib.sh"

echo "== the shared parser library =="
# parse_roadmap is ONE definition of a file format with two consumers, not two similar behaviours.
# If the two ever parsed differently the guard would pass a file the sync then mis-applies, so
# divergence is a defect by definition rather than a possibility. That is what separates this from
# the wrong-abstraction risk the Rule of Three warns about (#162).
mv "$T/roadmap-lib.sh" "$T/roadmap-lib.hidden"
run --offline
expect "a missing roadmap-lib.sh refuses the run rather than degrading" 2 "$rc"
contains "roadmap-lib.sh" "$out" "and names what is missing"
mv "$T/roadmap-lib.hidden" "$T/roadmap-lib.sh"

echo "== usage =="
run --nonsense
expect "an unknown flag refuses the run" 2 "$rc"
out=$(cd "$T" && bash ./check-phases.sh --help 2>&1)
hrc=$?
# #447: the #259 maintainer note sits below the header, so --help opens with what the script does.
first447=$(printf '%s\n' "$out" | awk 'NF{print; exit}')
case "$first447" in "The roadmap-phases guard: four rules"*) ok "--help opens with the purpose line (#447)" ;; *) bad "--help opens with the purpose line (#447) (got '$first447')" ;; esac
expect "--help exits 0 (#447)" 0 "$hrc"
grep -q 'NO .awk -v. IN THIS FILE' <<< "$out" \
  && bad "--help does not print the #259 maintainer note (#447)" \
  || ok "--help does not print the #259 maintainer note (#447)"
hb447=$(awk 'NR>1 && /^$/{print NR; exit}' "$T/check-phases.sh"); nl447=$(grep -n -m1 'NO .awk -v. IN THIS FILE' "$T/check-phases.sh" | cut -d: -f1)
expect "the #259 note stays in the source once, below the header (#447)" "1 below" \
  "$(grep -c 'NO .awk -v. IN THIS FILE' "$T/check-phases.sh") $([ "${nl447:-0}" -gt "${hb447:-0}" ] && echo below || echo above)"
contains "check-phases.sh" "$out" "--help prints the synopsis"
grep -q "sed -n '[0-9]*,[0-9]*p'" "$T/check-phases.sh" \
  && bad "--help does not print a hardcoded line range" \
  || ok "--help does not print a hardcoded line range"

echo "== portability, because this ships into other people's repositories =="
code() { grep -v '^[[:space:]]*#' "$1"; }
n="$(code "$SRC" | grep -c ',,}')"
[ "${n:-0}" -le 1 ] && ok "the bash-4 lowercase expansion appears at most once" \
                    || bad "the bash-4 lowercase expansion appears $n times"
grep -q 'readlink -f' <<< "$(code "$SRC")" \
  && bad "avoids GNU-only readlink -f" || ok "avoids GNU-only readlink -f"

echo "== the shipped asset is a component =="
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SRC" \
  && ok "carries a version marker" || bad "carries a version marker"

if [ -s "$T/shim/live.log" ]; then
  bad "a suite case reached a live forge: $(head -3 "$T/shim/live.log" | tr '\n' ';')"
else
  ok "no live forge call (the gh/curl shim log is empty)"
fi

echo "== no awk -v in the shipped asset, and a backslash path is printed as typed (#259) =="
# #405: the zero-`awk -v` rule and the no-operand rule, one definition in scripts/awkv-count.sh.
. "$ROOT/scripts/awkv-count.sh"; awkv_checks check-phases.sh "$SRC" "$T"
# #413: a MALFORMED phase FIRST, then 2000 well-formed ones, so parse_roadmap prints over 64 KiB.
# `printf | grep -q '^MALFORMED'` under pipefail lost that first-row match in 186 to 198 runs of 200
# unloaded (grep exits at the match, printf takes SIGPIPE, the pipeline reads 141, the refusal is
# skipped). Three calls must each refuse; a scratch copy with the pipe form restored must not.
awk 'BEGIN { printf "## Phase: Bad one\nstate: bogus\n\nWhy.\n\n"; for (i = 0; i < 2000; i++) printf "## Phase: P%d\nstate: planned\nplan: docs/plans/a-long-plan-name-that-grows-the-parse-output-past-64k.md\n\nWhy %d.\n\n", i, i }' > "$T/big.md"
n3=0; for i in 1 2 3; do run --offline --roadmap big.md </dev/null; [ "$rc" = 3 ] && n3=$((n3 + 1)); done
expect "#413: a large roadmap with its MALFORMED phase first exits 3 on each of three runs" 3 "$n3"
P='|'; cp "$T/check-phases.sh" "$T/cp-keep.sh"; sed "s/if grep -q '^MALFORMED' <<< \"\$PHASES\"; then/if printf '%s\\\\n' \"\$PHASES\" $P grep -q '^MALFORMED'; then/" "$T/cp-keep.sh" > "$T/check-phases.sh"
n3=0; for i in 1 2 3; do run --offline --roadmap big.md </dev/null; [ "$rc" = 3 ] && n3=$((n3 + 1)); done
if cmp -s "$T/cp-keep.sh" "$T/check-phases.sh"; then bad "#413: mutant: the pipe form was not restored"
elif [ "$n3" -lt 3 ]; then ok "#413: mutant: the pipe form lets the malformed roadmap through ($((3 - n3)) of 3 runs)"
else bad "#413: mutant: the pipe form still refused all three runs"; fi
cp "$T/cp-keep.sh" "$T/check-phases.sh"; rm -f "$T/cp-keep.sh" "$T/big.md"
# #405: a roadmap whose name is shaped name=value is still read as a file. Before, awk took
# `r=bad.md` for an assignment, read stdin instead, and a malformed roadmap passed with rc 0.
printf '## Phase: A\n\nx\n' > "$T/r=bad.md"; cp "$T/r=bad.md" "$T/rbad.md"
run --offline --roadmap 'r=bad.md' </dev/null
expect "#405: a malformed roadmap named r=bad.md exits 3, never a silent 0" 3 "$rc"
contains 'no state line' "$out" "#405: and it names the missing state line"
run --offline --roadmap rbad.md </dev/null
expect "#405: the plain-named control exits 3 too" 3 "$rc"
printf '## Phase: A\nstate: bogus\n\nx\n' > "$T/r\\tmap.md"
run --offline --roadmap 'r\tmap.md'
expect "a malformed roadmap at a backslash path still exits 3" 3 "$rc"
contains 'r\tmap.md' "$out" "and the diagnostic names r\\tmap.md with its backslash"
case "$out" in *"$(printf '\t')"*) bad "and the diagnostic carries no TAB byte (the -v escape pass)" ;; *) ok "and the diagnostic carries no TAB byte (the -v escape pass)" ;; esac
cp "$T/r\\tmap.md" "$T/rtmap.md"
run --offline --roadmap rtmap.md
expect "the backslash-free control exits 3" 3 "$rc"
expect "and its first line is unchanged" 'check-phases: rtmap.md: phase "A": unknown state "bogus"' "$(printf '%s\n' "$out" | head -1)"
rm -f "$T/r\\tmap.md" "$T/rtmap.md"

echo ""
echo "check-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
