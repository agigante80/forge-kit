#!/usr/bin/env bash
# Contract test for check-live-placeholders.sh (#163).
#
# WHY THE DISTINCTION NEEDS A TEST. A placeholder in PROSE is correct: the manual-install path has
# to be documentable, and a guard that forbade the explanation would forbid the reason. A
# placeholder inside a runnable command is what pins a component to one project and forces a
# per-project copy. Those two look identical to a grep, which is why this is a script with cases
# rather than a line in CI.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/check-live-placeholders.sh"

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

echo "== prose is allowed, because the manual path must be documentable =="
mk "$T/plugins/g/agents/a.md" <<'M'
**Repository:** resolved at runtime; a manual install substitutes `{{GITHUB_REPO}}` by hand.
The placeholder {{GITHUB_REPO}} is named here in ordinary prose.
M
run
expect "a placeholder in prose passes" 0 "$rc"

echo "== inside a fenced command it is a violation =="
mk "$T/plugins/g/agents/a.md" <<'M'
Text about the gate.

```bash
gh issue view 1 --repo {{GITHUB_REPO}} --json body
```
M
run
expect "a placeholder inside a fenced block fails" 1 "$rc"
contains "a.md" "$out" "and names the file"
contains "4" "$out" "and the line"
contains "GITHUB_REPO" "$out" "and the placeholder"

echo "== the substitution command itself is the one legitimate live use =="
mk "$T/plugins/g/agents/a.md" <<'M'
Manual installs need one step:

```bash
sed -i "s|{{GITHUB_REPO}}|owner/repo|g" .claude/agents/a.md
```
M
run
expect "the sed that REPLACES the placeholder is allowed" 0 "$rc"

# ...and the exemption is narrow: any other command on the same shape still fails.
mk "$T/plugins/g/agents/a.md" <<'M'
```bash
curl https://api.github.com/repos/{{GITHUB_REPO}}/issues
```
M
run
expect "another command mentioning it still fails" 1 "$rc"

echo "== an unclosed fence must not swallow the rest of the file =="
# A file whose fence is never closed would otherwise put every following line "inside" a block,
# turning prose into violations. Reported as a malformed file rather than guessed at.
mk "$T/plugins/g/agents/a.md" <<'M'
```bash
echo hello
Some prose after a fence nobody closed, naming {{GITHUB_REPO}}.
M
run
expect "an unclosed fence refuses rather than guessing" 2 "$rc"
contains "unclosed" "$out" "and says why"

echo "== a clean tree, and things that are not components =="
mk "$T/plugins/g/agents/a.md" <<'M'
```bash
gh issue view 1 --repo "$REPO" --json body
```
M
run
expect "a component using a runtime value passes" 0 "$rc"

# references/ and scripts/ are not components; the enforced path set is one directory deep.
mk "$T/plugins/g/agents/references/note.md" <<'M'
```bash
gh issue view 1 --repo {{GITHUB_REPO}}
```
M
run
expect "a nested reference file is not a component and is not scanned" 0 "$rc"

echo "== any placeholder, not just this one =="
mk "$T/plugins/g/agents/a.md" <<'M'
```bash
deploy --to {{TARGET_ENV}}
```
M
run
expect "a different placeholder is caught too" 1 "$rc"

echo "== review round 1: the sed exemption was an unanchored substring =="
# `$0 ~ /sed/` matched "used", "based", "parsed", "closed". A comment on the same line as a
# placeholder was therefore enough to exempt the command carrying it.
mk "$T/plugins/g/agents/a.md" <<'M'
```bash
REPO={{GITHUB_REPO}}  # the value used at install time
```
M
run
expect "a line merely containing the letters s-e-d is not exempt" 1 "$rc"

mk "$T/plugins/g/agents/a.md" <<'M'
```bash
sed -i "s|{{GITHUB_REPO}}|owner/repo|g" f.md
```
M
run
expect "and the real sed command still is" 0 "$rc"

echo "== review round 1: a project-scoped component may carry one =="
# check-component-scope.sh tells a maintainer to declare scope: project as the remedy. This guard
# rejected that remedy in the same CI job, so the two contradicted each other and the scope suite
# asserted a behaviour the pipeline refused.
mk "$T/plugins/g/agents/a.md" <<'M'
---
name: a
scope: project
scope-reason: the repo placeholder is substituted at install time
---
```bash
gh issue view 1 --repo {{GITHUB_REPO}}
```
M
run
expect "a declared project scope is honoured here too" 0 "$rc"

echo "== review round 1: finding nothing must not read as success =="
mkdir -p "$T/empty/plugins"
rc=0; out=$(bash "$SCRIPT" "$T/empty/plugins" 2>&1) || rc=$?
expect "zero components refuses rather than reporting clean" 2 "$rc"
contains "no components" "$out" "and says the scan found none"

echo "== usage =="
rc=0; out=$(bash "$SCRIPT" "$T/nope" 2>&1) || rc=$?
expect "a missing root exits 2 rather than passing" 2 "$rc"

echo ""
echo "live-placeholder tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
