#!/usr/bin/env bash
# Contract test for forge-adapt-neighbour-disposition.sh (#179).
#
# THE CASE THAT MATTERS MOST is the one where a neighbour ships the same NAME and forge-adapt keeps
# recommending ours anyway. #177 already refused to treat a name match as a defect; this refuses to
# treat it as a suppression. Handing the user less than they had, because a string matched, is the
# failure this suite exists to prevent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/forge-adapt-neighbour-disposition.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

installed() {  # installed <plugin@marketplace>...
  { printf '{ "plugins": {'
    sep=""
    for p in "$@"; do printf '%s "%s": [{"scope":"user"}]' "$sep" "$p"; sep=","; done
    printf ' } }\n'; } > "$T/installed.json"
}
none() { printf '{ "plugins": {} }\n' > "$T/installed.json"; }

verdict() { bash "$SCRIPT" "$1" --installed "$T/installed.json" | cut -f1; }
reason()  { bash "$SCRIPT" "$1" --installed "$T/installed.json" | cut -f2; }

echo "== with no neighbours, everything is recommended =="
none
for c in code-simplifier code-reviewer full-review closing-sessions security-auditor; do
  expect "$c is recommended when nothing else is installed" recommend "$(verdict "$c")"
done

echo "== superpowers owns the inner loop =="
installed "superpowers@claude-plugins-official"
expect "code-simplifier is suppressed" suppress "$(verdict code-simplifier)"
contains "#69" "$(reason code-simplifier)" "and the reason cites the boundary decision"
contains "bad-fix accounting" "$(reason code-simplifier)" "and says what the actual conflict is"
expect "closing-sessions is a caveat, not a suppression" caveat "$(verdict closing-sessions)"
contains "canon" "$(reason closing-sessions)" "and states the memory split"
expect "code-reviewer is a caveat under superpowers" caveat "$(verdict code-reviewer)"
contains "fresh subagent" "$(reason code-reviewer)" "and names the preferred dispatch shape"
expect "an outer-loop component is untouched by superpowers" recommend "$(verdict ticket-gate)"
expect "so is the roadmap command" recommend "$(verdict phase)"

echo "== a neighbour that ships the same NAME is a caveat, never a suppression =="
# The whole point. Suppressing ours because a name matched would hand the user less than they had.
installed "pr-review-toolkit@claude-plugins-official"
expect "code-reviewer survives a same-named neighbour" caveat "$(verdict code-reviewer)"
contains "iteration contract" "$(reason code-reviewer)" "and says what distinguishes ours"

installed "comprehensive-review@claude-code-workflows"
expect "full-review survives its own ancestor" caveat "$(verdict full-review)"
contains "ITERATION CONTRACT" "$(reason full-review)" "and names what ours added"

installed "code-simplifier@claude-plugins-official"
expect "code-simplifier is a caveat when only the neighbour is present" caveat "$(verdict code-simplifier)"

echo "== superpowers wins over a neighbour on the same component =="
# Both installed: the inner-loop boundary is the stronger claim and must not be silently overridden.
installed "superpowers@claude-plugins-official" "code-simplifier@claude-plugins-official"
expect "superpowers still suppresses code-simplifier" suppress "$(verdict code-simplifier)"

echo "== a missing record is an absent neighbour, not an error =="
rm -f "$T/installed.json"
rc=0; out=$(bash "$SCRIPT" code-simplifier --installed "$T/installed.json" 2>&1) || rc=$?
expect "a missing install record still exits 0" 0 "$rc"
expect "and recommends" recommend "$(printf '%s' "$out" | cut -f1)"

echo "== a malformed record does not take forge-adapt down =="
# That file is written by another tool and this kit does not own its schema.
printf 'this is not json at all {{{\n' > "$T/installed.json"
rc=0; out=$(bash "$SCRIPT" code-reviewer --installed "$T/installed.json" 2>&1) || rc=$?
expect "malformed JSON exits 0" 0 "$rc"
expect "and falls back to recommend" recommend "$(printf '%s' "$out" | cut -f1)"

echo "== the contract shape holds =="
none
line=$(bash "$SCRIPT" ticket-gate --installed "$T/installed.json")
[ "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" = "2" ] \
  && ok "output is exactly two tab-separated fields" || bad "output is two fields (got '$line')"
[ "$(bash "$SCRIPT" anything-at-all --installed "$T/installed.json" | cut -f1)" = "recommend" ] \
  && ok "an unknown component defaults to recommend" || bad "an unknown component defaults to recommend"
rc=0; bash "$SCRIPT" --installed "$T/installed.json" >/dev/null 2>&1 || rc=$?
expect "no component name refuses" 2 "$rc"

echo ""
echo "neighbour-disposition tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
