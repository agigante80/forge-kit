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
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/docs/plans"
cp "$SRC" "$T/check-phases.sh"

goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }
out=""; rc=0
run() { out=$(cd "$T" && bash ./check-phases.sh "$@" 2>&1); rc=$?; }

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
forge_milestone_list()       { cat "$STUB_MILESTONES"; }
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB
hostrun() {
  out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
        bash ./check-phases.sh "$@" 2>&1); rc=$?
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
hostrun
expect "a missing forge-lib.sh exits 2 rather than reporting clean" 2 "$rc"
cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list()       { cat "$STUB_MILESTONES"; }
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB

echo "== usage =="
run --nonsense
expect "an unknown flag refuses the run" 2 "$rc"
out=$(cd "$T" && bash ./check-phases.sh --help 2>&1)
contains "check-phases.sh" "$out" "--help prints the synopsis"
grep -q "sed -n '[0-9]*,[0-9]*p'" "$T/check-phases.sh" \
  && bad "--help does not print a hardcoded line range" \
  || ok "--help does not print a hardcoded line range"

echo "== portability, because this ships into other people's repositories =="
code() { grep -v '^[[:space:]]*#' "$1"; }
n="$(code "$SRC" | grep -c ',,}')"
[ "${n:-0}" -le 1 ] && ok "the bash-4 lowercase expansion appears at most once" \
                    || bad "the bash-4 lowercase expansion appears $n times"
code "$SRC" | grep -q 'readlink -f' \
  && bad "avoids GNU-only readlink -f" || ok "avoids GNU-only readlink -f"

echo "== the shipped asset is a component =="
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SRC" \
  && ok "carries a version marker" || bad "carries a version marker"

echo ""
echo "check-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
