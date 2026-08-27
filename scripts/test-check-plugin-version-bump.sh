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

# Cross-group rename: rename detection reports only the destination, which would exempt
# the SOURCE group from its bump; the guard must diff with --no-renames so both groups count.
r="$T/xrename"; mk_repo "$r"
mkdir -p "$r/plugins/g2/.claude-plugin" "$r/plugins/g2/agents"
printf '{"name":"g2","version":"0.1.0","description":"d"}\n' > "$r/plugins/g2/.claude-plugin/plugin.json"
commit "$r"
git -C "$r" branch -qf base   # both groups exist at base
git -C "$r" mv plugins/g1/agents/a.md plugins/g2/agents/a.md
printf '{"name":"g2","version":"0.2.0","description":"d"}\n' > "$r/plugins/g2/.claude-plugin/plugin.json"
commit "$r"
run "a cross-group rename still requires the SOURCE group's bump" 1 "$r"

# Semver precedence: a pre-release to its release is an INCREASE; the reverse is a decrease.
r="$T/prerel"; mk_repo "$r"
printf '{"name":"g1","version":"0.2.0-rc1","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"; git -C "$r" branch -qf base
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"0.2.0","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"
run "pre-release to release (0.2.0-rc1 to 0.2.0) passes as an increase" 0 "$r"

r="$T/torel"; mk_repo "$r"
printf '{"name":"g1","version":"0.2.0","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"; git -C "$r" branch -qf base
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"0.2.0-rc1","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"
run "release to pre-release (0.2.0 to 0.2.0-rc1) fails as a decrease" 1 "$r"

r="$T/malformed"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"undefined","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
commit "$r"
run "a malformed version string fails rather than sorting above semver" 1 "$r"

# A loose FILE directly under plugins/ is not a group; the guard must ignore it by design.
r="$T/loose"; mk_repo "$r"
printf 'note\n' > "$r/plugins/README.md"; commit "$r"
run "a loose file directly under plugins/ is ignored, not treated as a group" 0 "$r"

# --staged mode (the pre-commit hook consumes this; one implementation, both surfaces):
staged_run() {  # <desc> <expected-rc> <repo>  (changes staged, NOT committed)
  local out rc
  out=$( (cd "$3" && bash "$SCRIPT" --staged 2>&1) ); rc=$?
  if [ "$rc" -eq "$2" ]; then ok "$1"; else bad "$1 (expected exit $2, got $rc: $(printf '%s' "$out" | head -1))"; fi
}
r="$T/stg-nobump"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"; git -C "$r" add -A
staged_run "staged: a changed group without a bump fails" 1 "$r"

r="$T/stg-bump"; mk_repo "$r"
printf 'changed\n' >> "$r/plugins/g1/agents/a.md"
printf '{"name":"g1","version":"0.1.1","description":"d"}\n' > "$r/plugins/g1/.claude-plugin/plugin.json"
git -C "$r" add -A
staged_run "staged: a changed group with a bump passes" 0 "$r"

r="$T/stg-rmgroup"; mk_repo "$r"
git -C "$r" rm -qr plugins/g1
staged_run "staged: deleting a whole group passes (nothing left to bump)" 0 "$r"

r="$T/nobase"; mk_repo "$r"
out=$( (cd "$r" && bash "$SCRIPT" no-such-ref 2>&1) ); rc=$?
[ "$rc" -eq 1 ] && ok "a missing base ref fails closed" || bad "a missing base ref fails closed (got $rc)"

echo ""
echo "check-plugin-version-bump tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
