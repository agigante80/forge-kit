#!/usr/bin/env bash
# Contract test for check-lens-contract.sh (#103 part 1).
#
# THE DEFECT. ticket-gate dispatches the security lens with a result contract in its prompt, which
# fixes what the auditor is ASKED for and not whether the installed auditor understands the ask.
# The two live in different plugin GROUPS, so a user can hold governance at one version and security
# at another, and nothing says so. The failure is silent: the lens returns something the gate cannot
# merge, or merges it wrongly.
#
# WHY A LOCKSTEP GUARD RATHER THAN ONLY RUNTIME PROSE. The ticket prices both. This moves the
# SHIPPED pair's failure from runtime to CI, which is the same trade check-template-lockstep.sh
# already makes for the templates and the canonical doc: a version that cannot drift needs no
# runtime check. It does not cover a user's INSTALLED pair, and says so rather than implying it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-lens-contract.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
DEF="$T/plugins/forge-kit-governance/skills/ticket-gate-reference/references/lens-definitions.md"
AUD="$T/plugins/forge-kit-security/agents/security-auditor.md"
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?; }

echo "== the pair agrees =="
mk "$DEF" <<'M'
<!-- lens-contract-version: 3 -->
The security lens returns JSON with verdict, blocking[] and class.
M
mk "$AUD" <<'M'
<!-- security-auditor-version: 4 -->
<!-- lens-contract-version: 3 -->
body
M
run
expect "a matching pair passes" 0 "$rc"
contains "3" "$out" "and reports the contract version they share"

echo "== skew is caught, and both sides are named =="
mk "$AUD" <<'M'
<!-- security-auditor-version: 4 -->
<!-- lens-contract-version: 2 -->
body
M
run
expect "a skewed pair fails" 1 "$rc"
contains "lens-definitions.md" "$out" "and names the definition side"
contains "security-auditor.md" "$out" "and names the agent side"
contains "3" "$out" "and both versions, not just that they differ"
contains "2" "$out" "and both versions, not just that they differ (second)"

echo "== a missing marker is a skew, not a pass =="
# The failure mode that matters: an unmarked file compared against a marked one used to be the
# shape that read as agreement, which is how every install predating a marker went unnoticed (#64).
mk "$AUD" <<'M'
<!-- security-auditor-version: 4 -->
body with no contract marker
M
run
expect "a missing marker on the agent fails" 1 "$rc"
contains "no lens-contract-version" "$out" "and says which file lacks it"

mk "$AUD" <<'M'
<!-- security-auditor-version: 4 -->
<!-- lens-contract-version: 3 -->
body
M
mk "$DEF" <<'M'
no marker here either
M
run
expect "a missing marker on the definitions fails too" 1 "$rc"

echo "== it refuses rather than passing when it cannot look =="
rm -f "$AUD"
run
expect "an absent file refuses" 2 "$rc"
contains "cannot read" "$out" "and says so"

echo ""
echo "lens-contract tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
