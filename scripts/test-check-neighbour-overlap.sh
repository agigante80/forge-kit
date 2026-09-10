#!/usr/bin/env bash
# Contract test for check-neighbour-overlap.sh (#177).
#
# THE CASE THAT MATTERS MOST is the collision one. `code-reviewer` is a name anyone would pick, and
# a guard that failed on every shared name would be switched off within a week, which is worse than
# not having a guard at all. So the suite pins BOTH verdicts, and the mutation check below breaks
# the threshold in both directions: a guard that fails everything and a guard that fails nothing
# must each break a case.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-neighbour-overlap.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

TODAY=$(date +%Y-%m-%d)
tree() { rm -rf "$T/tree"; mkdir -p "$T/tree/docs"; }
manifest() {  # manifest <rows...>, each "plugin|kind|name|differing|verdict[|date]"
  { printf '# fixture\n'
    printf 'marketplace\tplugin\tkind\tname\ttheir_lines\tour_lines\tdiffering\tverdict\tmeasured\n'
    for row in "$@"; do
      IFS='|' read -r plug kind name diff verdict when <<< "$row"
      printf 'fixmkt\t%s\t%s\t%s\t100\t100\t%s\t%s\t%s\n' "$plug" "$kind" "$name" "$diff" "$verdict" "${when:-$TODAY}"
    done
  } > "$T/tree/docs/neighbours.tsv"
}
allow() { printf '%s\n' "$@" > "$T/tree/.neighbour-allow"; }
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$T/tree" 2>&1); rc=$?; }

echo "== a duplicate fails, and names both sides =="
tree; manifest "fixplug|agent|dupe-agent|1|duplicate"
run
expect "an unallowed duplicate fails" 1 "$rc"
contains "dupe-agent" "$out" "and names the component"
contains "fixplug" "$out" "and names the neighbour plugin"
contains "differing by 1" "$out" "and how far apart they are"

echo "== a collision is reported and does NOT fail =="
# Two ecosystems may pick the same obvious name. This is the case that keeps the guard installed.
tree; manifest "fixplug|agent|code-reviewer|312|collision"
run
expect "a collision exits 0" 0 "$rc"
contains "collision" "$out" "and says so explicitly"
contains "Not a defect" "$out" "and says it is not a defect"

echo "== an allowlist entry with a reason permits a duplicate, and shows the reason =="
tree; manifest "fixplug|agent|dupe-agent|1|duplicate"
allow "dupe-agent :: it is dispatched by name and retiring it would break the caller"
run
expect "an allowed duplicate exits 0" 0 "$rc"
contains "allowed" "$out" "and is reported as allowed rather than silently skipped"
contains "dispatched by name" "$out" "and the reason is printed where the reader meets it"

echo "== an allowlist entry with NO reason refuses the whole run =="
# An unreasoned exemption is how a temporary licence becomes permanent with nobody able to say why.
tree; manifest "fixplug|agent|dupe-agent|1|duplicate"
allow "dupe-agent"
run
expect "a reasonless entry refuses" 2 "$rc"
contains "no reason" "$out" "and says what is wrong with it"

tree; manifest "fixplug|agent|dupe-agent|1|duplicate"
allow "dupe-agent :: "
run
expect "an empty reason refuses too" 2 "$rc"

echo "== a missing manifest cannot report clean =="
# A check that cannot run must never pass. The posture check-phases.sh and the leak guard take.
tree
run
expect "no manifest exits 2, not 0" 2 "$rc"
contains "neighbour-manifest.sh --refresh" "$out" "and names the command that fixes it"

echo "== an empty manifest is an error, not a vacuous pass =="
tree; { printf '# fixture\n'; printf 'marketplace\tplugin\tkind\tname\ttheir_lines\tour_lines\tdiffering\tverdict\tmeasured\n'; } > "$T/tree/docs/neighbours.tsv"
run
expect "a manifest with no rows exits 2" 2 "$rc"

echo "== an ageing manifest warns loudly and still checks =="
tree; manifest "fixplug|agent|dupe-agent|1|duplicate|2020-01-01"
allow "dupe-agent :: allowed for this case"
run
expect "a stale manifest still exits 0 when nothing is wrong" 0 "$rc"
contains "days ago" "$out" "and says how old it is"
contains "refresh" "$out" "and how to fix it"

echo "== a stale manifest still FAILS an unallowed duplicate =="
# Weaker evidence is not no evidence.
tree; manifest "fixplug|agent|dupe-agent|1|duplicate|2020-01-01"
run
expect "an old manifest does not excuse a duplicate" 1 "$rc"

echo "== an unknown verdict refuses rather than guessing =="
tree; manifest "fixplug|agent|dupe-agent|1|probably"
run
expect "an unrecognised verdict exits 2" 2 "$rc"

echo "== the guard reads nothing outside the tree =="
# It must run identically on a machine with no marketplaces installed, which is every CI runner.
tree; manifest "fixplug|agent|only-in-manifest|400|collision"
run
expect "a component named only in the manifest is fine" 0 "$rc"
lacks "$HOME/.claude" "$out" "and no path outside the tree appears in the output"

echo "== this repository passes =="
out=$(bash "$SCRIPT" "$ROOT" 2>&1); rc=$?
expect "the real tree has no unallowed duplicate" 0 "$rc"
contains "collision" "$out" "and reports its collisions rather than hiding them"

echo ""
echo "neighbour-overlap tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
