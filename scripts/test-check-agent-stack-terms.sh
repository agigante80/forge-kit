#!/usr/bin/env bash
# Contract test for scripts/check-agent-stack-terms.sh (#549, #559).
#
# The guard fails the build when a shipped agent names one project's stack. Its worst failure is a
# false clean, so every term in its list is exercised alone, the line number it reports is checked,
# a SKILL that carries the same terms must stay clean (skills may hold translated examples), and the
# real tree must pass. Each mutant edits a copy of the guard and must fail at least one case.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
G="$ROOT/scripts/check-agent-stack-terms.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has() { if grep -qxF -- "$1" <<< "$out"; then ok "$2"; else bad "$2 (no line '$1' in: $out)"; fi; }

[ -f "$G" ] || { echo "missing script: $G"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd -P -- "$T" && pwd -P)

# fresh: an empty checkout with one clean agent.
fresh() {
  rm -rf "$T/r"; mkdir -p "$T/r/plugins/g/agents" "$T/r/plugins/g/skills/s"
  printf '%s\n' '---' 'name: a' '---' 'A stack-neutral agent.' > "$T/r/plugins/g/agents/a.md"
}
# run <guard> [root]: sets out and rc.
run() { out=$(bash "$1" --root "${2:-$T/r}" 2>&1); rc=$?; }

TERMS="Fastify Prisma Zod Vitest fastify.inject app.inject Firebase Twilio SendGrid Stripe .test.ts subscriptionTier SUBSCRIPTION_REQUIRED helpers/seed"

echo "== a clean tree passes =="
fresh; run "$G"
expect "a stack-neutral agent exits 0" 0 "$rc"
expect "and prints nothing" "" "$out"

echo "== every term is caught alone, with its file and line =="
for t in $TERMS; do
  fresh; printf 'line two\nuses %s here\n' "$t" >> "$T/r/plugins/g/agents/a.md"
  run "$G"
  expect "'$t' in an agent fails" 1 "$rc"
  has "plugins/g/agents/a.md:6: $t" "'$t' is reported as <file>:<line>: <term>"
done

echo "== the scope is agents only =="
fresh; printf 'Fastify and Prisma examples, translate them.\n' > "$T/r/plugins/g/skills/s/SKILL.md"
run "$G"
expect "a SKILL with stack examples stays clean" 0 "$rc"

echo "== a missing root or no agents is an error, never a clean pass =="
run "$G" "$T/nope"
expect "a missing root exits 2" 2 "$rc"
fresh; rm "$T/r/plugins/g/agents/a.md"; run "$G"
expect "zero agents exits 2" 2 "$rc"

echo "== the real tree passes =="
run "$G" "$ROOT"
expect "no shipped agent names a stack" 0 "$rc"

echo "== mutants =="
mut() {  # mut <name> <python replace-from> <replace-to>
  cp "$G" "$T/mut.sh"
  python3 - "$T/mut.sh" "$2" "$3" <<'PY' || { bad "mutant '$1' did not apply"; return; }
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
assert s.count(a) >= 1, a
open(p, 'w').write(s.replace(a, b, 1))
PY
  local killed=0 t
  for t in $TERMS; do
    fresh; printf 'line two\nuses %s here\n' "$t" >> "$T/r/plugins/g/agents/a.md"
    run "$T/mut.sh"
    if [ "$rc" != 1 ] || ! grep -qxF -- "plugins/g/agents/a.md:6: $t" <<< "$out"; then killed=1; fi
  done
  fresh; printf 'Fastify\n' > "$T/r/plugins/g/skills/s/SKILL.md"; run "$T/mut.sh"
  [ "$rc" = 0 ] || killed=1
  fresh; rm "$T/r/plugins/g/agents/a.md"; run "$T/mut.sh"
  [ "$rc" = 2 ] || killed=1
  if [ "$killed" = 1 ]; then ok "MUTANT: $1 is caught"; else bad "MUTANT survived: $1"; fi
}
mut "glob widened to skills" '"$ROOT"/plugins/*/agents/*.md' '"$ROOT"/plugins/*/*/*.md "$ROOT"/plugins/*/skills/*/*.md'
mut "line number dropped" 'echo "$rel:$n: $term"' 'echo "$rel: $term"'
mut "exit 0 on a hit" '      rc=1' '      rc=0'
mut "no-agents guard dropped" '[ "${#agents[@]}" -gt 0 ] || die' ': die'
mut "term 'Fastify' dropped from the list" "TERMS='Fastify
" "TERMS='"
for t in $TERMS; do
  [ "$t" = Fastify ] && continue
  mut "term '$t' dropped from the list" "
$t" ""
done

echo
echo "check-agent-stack-terms tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
