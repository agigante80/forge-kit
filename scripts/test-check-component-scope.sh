#!/usr/bin/env bash
# Contract test for check-component-scope.sh (#164).
#
# WHAT THE FIELD IS FOR. A component that resolves what it needs at RUNTIME is correct in every
# project and can be installed once by enabling its plugin group. One that must be rewritten for the
# project it lands in cannot. Until now that distinction lived as folklore, so forge-adapt copied
# everything into `.claude/` by default, which is the copy-and-mutate path CLAUDE.md blames for
# every hook bug in this repo's history.
#
# WHY THE DEFAULT IS `user`. A default should point at the good path. After #163 no component bakes
# a value in at install time, so `user` is not merely the common case, it is the case the tree can
# actually prove. `project` is the exception and must therefore carry its reason, the same shape
# check-restatements.sh requires of an allowlist entry: an exception without a stated reason is one
# that grows by argument.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-component-scope.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
out=""; rc=0
run() { out=$(bash "$SCRIPT" "$T/plugins" 2>&1); rc=$?; }

echo "== the default is user, and costs nobody anything =="
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
description: does a thing
---
<!-- a-version: 1 -->
Ordinary component with no scope field.
M
run
expect "a component declaring no scope inherits user" 0 "$rc"
contains "user" "$out" "and the summary says how many are user-scoped"

echo "== an explicit user scope is fine =="
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: user
---
<!-- a-version: 1 -->
body
M
run
expect "an explicit user scope passes" 0 "$rc"

echo "== project is the exception, so it carries its reason =="
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: project
---
<!-- a-version: 1 -->
body
M
run
expect "scope: project with no reason is refused" 1 "$rc"
contains "scope-reason" "$out" "and names the field it wants"

mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: project
scope-reason: rewritten for the project's test runner at install time
---
<!-- a-version: 1 -->
body
M
run
expect "scope: project WITH a reason passes" 0 "$rc"

mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: project
scope-reason:
---
<!-- a-version: 1 -->
body
M
run
expect "an empty reason is not a reason" 1 "$rc"

echo "== an unknown scope is refused rather than assumed =="
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: global
---
<!-- a-version: 1 -->
body
M
run
expect "an unrecognised scope value is refused" 1 "$rc"
contains "user" "$out" "and lists what it accepts"

echo "== the declaration is checked against the tree, not taken on trust =="
# The phase plan's premortem: "scope: user became a lie". A user-scoped component carrying an
# install-time placeholder is the one mechanical contradiction available, so it is refused.
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: user
---
<!-- a-version: 1 -->
```bash
gh issue view 1 --repo {{GITHUB_REPO}}
```
M
run
expect "a user-scoped component with a live placeholder is refused" 1 "$rc"
contains "placeholder" "$out" "and says what contradicts the claim"

# ...and NO scope makes it legitimate. Round 1 of review allowed it under scope: project; round 2
# found there is no substitution machinery behind that remedy since #163, so it would have installed
# a component with a live placeholder in it.
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: project
scope-reason: the repo placeholder is substituted at install time
---
<!-- a-version: 1 -->
```bash
gh issue view 1 --repo {{GITHUB_REPO}}
```
M
run
expect "a declared project scope does NOT license a placeholder" 1 "$rc"
contains "does NOT help" "$out" "and says why the obvious remedy is wrong"

echo "== only frontmatter counts =="
# A `scope:` written in the body is prose, not a declaration. Reading it would let a component be
# scoped by an example inside its own documentation.
# The realistic shape: a component that DOCUMENTS the field carries an example at column 0 inside a
# fenced block. Reading the whole file would take that example as this component's own declaration.
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
---
<!-- a-version: 1 -->
Declare the scope in frontmatter, for example:

```yaml
scope: global
scope-reason:
```

and an unrecognised value like that one is refused.
M
run
expect "a scope example in the BODY is not a declaration" 0 "$rc"

echo "== scope of the scan =="
mk "$T/plugins/g/agents/references/note.md" <<'M'
---
scope: nonsense
---
body
M
run
expect "a nested reference file is not a component and is not scanned" 0 "$rc"

# Review round 1: the same unanchored sed test was copied here and inherited the hole.
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: user
---
```bash
REPO={{GITHUB_REPO}}  # the value used at install time
```
M
run
expect "a line merely containing the letters s-e-d is not exempt here either" 1 "$rc"

mkdir -p "$T/empty/plugins"
rc=0; out=$(bash "$SCRIPT" "$T/empty/plugins" 2>&1) || rc=$?
expect "zero components refuses rather than reporting clean" 2 "$rc"

rc=0; out=$(bash "$SCRIPT" "$T/nope" 2>&1) || rc=$?
expect "a missing root exits 2 rather than passing" 2 "$rc"

echo ""
echo "component-scope tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
