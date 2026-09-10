#!/usr/bin/env bash
# Contract test for check-label-taxonomy.sh (#188).
#
# THE FAILURE IT EXISTS FOR. The area label set was stated in four places, three disagreed, and the
# disagreement was found by the ticket gate blocking on the first ticket it was ever pointed at in
# this repository. Step 0b named `frontend`, which has never been a declared label, and
# `infrastructure`, which is declared a TYPE, while omitting `privacy` and `database`.
#
# THE CASE THAT MATTERS MOST is the last one: ticket-gate.md must NOT carry a copy at all. The fix
# for that file was deletion rather than synchronisation, and a guard that only compared copies
# would be satisfied by the copy coming back in agreement, which is how it drifted the first time.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-label-taxonomy.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

MECHDIR=plugins/forge-kit-governance/skills/ticket-gate-reference/assets
GATEDIR=plugins/forge-kit-governance/agents

tree() {  # tree <canonical areas> <yml areas> <AREA_LABELS> [gate-line]
  rm -rf "$T/tree"
  mkdir -p "$T/tree/docs/guides" "$T/tree/.github" "$T/tree/$MECHDIR" "$T/tree/$GATEDIR"
  { echo "### Type labels"
    echo "| Label | Description |"
    echo "|---|---|"
    echo '| `bug` | Something is not working |'
    echo ""
    echo "### Area labels (modulate the gate's review set)"
    echo "| Label | Description | Triggers |"
    echo "|---|---|---|"
    for l in $1; do printf '| `%s` | fixture | - |\n' "$l"; done
    echo ""
    echo "### Priority labels"
  } > "$T/tree/docs/guides/labels.md"
  { for l in $2; do printf -- '- name: %s\n  color: "ffffff"\n  description: fixture\n\n' "$l"; done
  } > "$T/tree/.github/labels.yml"
  printf 'AREA_LABELS="%s"\n' "$3" > "$T/tree/$MECHDIR/check-ticket-mechanics.sh"
  printf '%s\n' "${4:-Check for an area label, as defined in docs/guides/labels.md.}" \
    > "$T/tree/$GATEDIR/ticket-gate.md"
}
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$T/tree" 2>&1); rc=$?; }

SIX="api privacy web mobile backend database"

echo "== every copy agreeing passes =="
tree "$SIX" "$SIX" "$SIX"
run
expect "an agreeing tree exits 0" 0 "$rc"
contains "6 area labels" "$out" "and reports how many it compared"

echo "== an area missing from labels.yml fails, because the host never gets it =="
# This is #104's failure: a taxonomy declared in prose and applied by nothing.
tree "$SIX" "api privacy web mobile backend" "$SIX"
run
expect "an area absent from labels.yml fails" 1 "$rc"
contains "database" "$out" "and names the missing label"
contains "never reaches the host" "$out" "and says why it matters"

echo "== AREA_LABELS disagreeing fails, and both sides are named =="
tree "$SIX" "$SIX" "api privacy web mobile backend frontend"
run
expect "a divergent AREA_LABELS default fails" 1 "$rc"
contains "only in labels.md: database" "$out" "and names what the canon has"
contains "only here: frontend" "$out" "and names what the copy invented"

echo "== ticket-gate.md restating the set fails, even when the copy AGREES =="
# The whole point. Synchronising the copy is not the fix; not having one is.
tree "$SIX" "$SIX" "$SIX" 'Check for one of `api`, `privacy`, `web`, `mobile`, `backend`, `database`.'
run
expect "a restated set in the gate fails" 1 "$rc"
contains "restate" "$out" "and says so"
contains "cannot drift" "$out" "and gives the reason"

echo "== a missing canonical table is an error, not agreement =="
# Deleting the definition must never read as every copy agreeing with nothing.
tree "" "$SIX" "$SIX"
run
expect "an empty Area labels table exits 2" 2 "$rc"
contains "definition" "$out" "and says the doc is the definition"

echo "== a missing file cannot report clean =="
tree "$SIX" "$SIX" "$SIX"
rm -f "$T/tree/.github/labels.yml"
run
expect "a missing labels.yml exits 2" 2 "$rc"

echo "== labels.yml may carry MORE than the areas =="
# It holds types and priorities too, so the check is containment, not equality.
tree "$SIX" "$SIX bug enhancement P0 P1" "$SIX"
run
expect "extra non-area entries in labels.yml are fine" 0 "$rc"

echo "== this repository passes =="
out=$(bash "$SCRIPT" "$ROOT" 2>&1); rc=$?
expect "the real tree agrees with itself" 0 "$rc"
contains "9 area labels" "$out" "and carries the three governance areas added by #188"

echo ""
echo "label-taxonomy tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
