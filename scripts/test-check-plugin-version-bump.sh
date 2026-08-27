#!/usr/bin/env bash
# Contract test for check-plugin-version-bump.sh (issue #79). Fixture git repos, exit-code
# assertions, modeled on test-template-lockstep.sh. Every case observed red before the guard
# existed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-plugin-version-bump.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# mk_repo <dir>: a repo with one plugin group g1 at 0.1.0 plus a component, committed as base.
mk_repo() {
  local r="$1"
  mkdir -p "$r/plugins/g1/.claude-plugin" "$r/plugins/g1/agents" "$r/docs"
  git -C "$r" init -q
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null || true
  printf '{"name":"g1","version":"0.1.0","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
  printf 'agent body\n' > "$r/plugins/g1/agents/a.md"
  printf 'readme\n' > "$r/docs/x.md"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$r" branch -q base
}
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm change; }
run() {  # <desc> <expected-rc> <repo>
  local out rc
  out=$( (cd "$3" && bash "$SCRIPT" base 2>&1) ); rc=$?
  if [ "$rc" -eq "$2" ]; then ok "$1"; else bad "$1 (expected exit $2, got $rc: $(printf '%s' "$out" | head -1))"; fi
}

r="$T/nobump"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"; commit "$r"
run "a changed group without a plugin.json bump fails" 1 "$r"

r="$T/bump"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"0.2.0","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"
run "a changed group with a strictly increased semver passes" 0 "$r"

r="$T/backward"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"0.0.9","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"
run "a DECREASED semver fails (strictly-increased is the contract)" 1 "$r"

r="$T/outside"; mk_repo "$r"
printf 'changed\n' >> "$r/docs/x.md"; commit "$r"
run "changes only outside plugins/ pass with no group named" 0 "$r"

r="$T/newgroup"; mk_repo "$r"
mkdir -p "$r/plugins/g2/.claude-plugin"
printf '{"name":"g2","version":"0.1.0","description":"d"}\n' > "$r/plugins/g2/.claude-plugin/plugin.json"
commit "$r"
run "a NEW group with a valid plugin.json passes" 0 "$r"

r="$T/deleted"; mk_repo "$r"
git -C "$r" rm -q plugins/g1/agents/a.md; commit "$r"
run "a deleted component file requires a bump too" 1 "$r"

r="$T/nobase"; mk_repo "$r"
out=$( (cd "$r" && bash "$SCRIPT" no-such-ref 2>&1) ); rc=$?
[ "$rc" -eq 1 ] && ok "a missing base ref fails closed" || bad "a missing base ref fails closed (got $rc)"

echo ""
echo "check-plugin-version-bump tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
