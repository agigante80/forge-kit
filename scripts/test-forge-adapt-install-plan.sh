#!/usr/bin/env bash
# Contract test for forge-adapt-install-plan.sh (#166).
#
# WHY THIS IS A SCRIPT AND NOT PROSE IN adapt/SKILL.md. Two reasons, and the second is the one that
# forced it. A rule in prose cannot be tested, and this one decides whether a copy lands in every
# project that installs the kit. And `adapt/SKILL.md` sits exactly on its size ratchet: the prose
# version measured +118 words, tightened to roughly +40, with no duplication left to pay with. Code
# is not word-counted, so this is the #149 lever rather than a baseline raise nobody authorised.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/forge-adapt-install-plan.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
D="$T/plugins/forge-kit-governance/agents"

out=""; rc=0
run() { out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; }
verdict() { printf '%s' "$out" | cut -f1; }
group()   { printf '%s' "$out" | cut -f2; }

echo "== the default is register =="
mk "$D/a.md" <<'M'
---
name: a
---
body
M
run "$D/a.md"
expect "a component with no scope exits 0" 0 "$rc"
expect "and is REGISTERED" "register" "$(verdict)"
expect "and the group comes from the path" "forge-kit-governance" "$(group)"
contains "owns no user config" "$out" "and the reason is stated for the user"

run "$D/a.md" --group other-group
expect "an explicit --group wins over the path" "other-group" "$(group)"

echo "== the three things that still copy =="
mk "$D/b.md" <<'M'
---
name: b
scope: project
scope-reason: rewritten for the project's test runner
---
body
M
run "$D/b.md"
expect "scope: project copies" "copy" "$(verdict)"
contains "test runner" "$out" "and carries the declared reason, not a generic one"

run "$D/a.md" --no-marketplace
expect "a bare clone copies even a user-scoped component" "copy" "$(verdict)"
contains "no marketplace" "$out" "and says why"

mk "$T/plugins/forge-kit-governance/hooks/h.py" <<'M'
# a hook
M
run "$T/plugins/forge-kit-governance/hooks/h.py"
expect "a hook refuses rather than guessing" 2 "$rc"
contains "install shapes" "$out" "and says hooks have their own"

echo "== it refuses rather than assuming =="
mk "$D/c.md" <<'M'
---
name: c
scope: project
---
body
M
run "$D/c.md"
expect "scope: project with no reason refuses" 2 "$rc"

mk "$D/d.md" <<'M'
---
name: d
scope: global
---
body
M
run "$D/d.md"
expect "an unrecognised scope refuses" 2 "$rc"

run "$T/nope.md"
expect "a missing file refuses" 2 "$rc"
run
expect "no argument refuses" 2 "$rc"

echo "== frontmatter only, like check-component-scope.sh =="
# A component DOCUMENTING the field carries an example at column 0 inside a fence. Reading the whole
# file would take that example as this component's own declaration and copy it into every project.
mk "$D/e.md" <<'M'
---
name: e
---
Declare it in frontmatter, for example:

```yaml
scope: project
scope-reason: an example, not this component's own declaration
```
M
run "$D/e.md"
expect "a scope example in the body is not a declaration" "register" "$(verdict)"

echo "== the output is one tab-separated line a caller can act on =="
run "$D/a.md"
expect "exactly one line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect "three tab-separated fields" 3 "$(printf '%s' "$out" | awk -F'\t' '{print NF}')"

echo ""
echo "install-plan tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
