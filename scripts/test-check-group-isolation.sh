#!/usr/bin/env bash
# Contract test for check-group-isolation.sh, which keeps forge-kit-roadmap optional.
#
# Built against a THROWAWAY plugins/ tree, not this repo, so the cases can assert a violation
# without putting one in the real tree. The guard takes a root as its first argument for exactly
# this reason.
#
# The near-misses are the point. A guard that fired on the English word "roadmap" would flag half
# the kit's prose and be deleted within a day, and one that flagged the roadmap group's own
# dependency on forge-lib.sh would forbid the thing the design requires.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/scripts/check-group-isolation.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/assets" \
         "$T/plugins/forge-kit-governance/agents" \
         "$T/plugins/forge-kit-adapt/skills/adapt"

out=""; rc=0
run() { out=$(bash "$SRC" "$T" 2>&1); rc=$?; }

# The group's own files, which must never be flagged.
printf 'sources forge-lib.sh from forge-kit-devops\n' \
  > "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"
printf 'the roadmap-phases skill\n' \
  > "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/SKILL.md"

echo "== a clean tree =="
printf 'the ticket gate reviews a ticket\n' > "$T/plugins/forge-kit-governance/agents/ticket-gate.md"
run
expect "a tree with no cross-reference passes" 0 "$rc"

echo "== a reference from another group is a violation =="
printf 'see check-phases.sh for the rules\n' > "$T/plugins/forge-kit-governance/agents/ticket-gate.md"
run
expect "a reference from another group fails" 1 "$rc"
contains "check-phases.sh" "$out" "and names the identifier"
contains "ticket-gate.md" "$out" "and names the file"
contains "optional" "$out" "and says why it matters"

for id in forge-kit-roadmap roadmap-phases sync-phases.sh; do
  printf 'mentions %s here\n' "$id" > "$T/plugins/forge-kit-governance/agents/ticket-gate.md"
  run
  expect "the identifier $id is caught too" 1 "$rc"
done

echo "== the near-misses =="
# The word in prose is not an identifier. This is the case that decides whether the guard survives.
printf 'our roadmap for next year is long, and the road map is longer\n' \
  > "$T/plugins/forge-kit-governance/agents/ticket-gate.md"
run
expect "the English word roadmap in prose is not a violation" 0 "$rc"

# The declared dependency runs the other way and must not be flagged.
printf 'sources forge-lib.sh, and names check-phases.sh, its own sibling\n' \
  > "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh"
run
expect "the group may name its own components" 0 "$rc"

# The installer knows every component exists.
printf 'install check-phases.sh alongside the roadmap-phases skill\n' \
  > "$T/plugins/forge-kit-adapt/skills/adapt/SKILL.md"
run
expect "forge-kit-adapt is exempt" 0 "$rc"

echo "== the exemption states its reason =="
printf 'see sync-phases.sh\n' > "$T/plugins/forge-kit-governance/agents/ticket-gate.md"
run
contains "installer" "$out" "the exemption's reason is printed with the failure"
grep -q 'EXEMPT_REASON=' "$SRC" \
  && ok "and the reason is a required field in the script" \
  || bad "and the reason is a required field in the script"

echo "== usage =="
rc=0; out=$(bash "$SRC" "$T/nope" 2>&1) || rc=$?
expect "a root with no plugins/ dir exits 2 rather than passing" 2 "$rc"

echo ""
echo "group-isolation tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
