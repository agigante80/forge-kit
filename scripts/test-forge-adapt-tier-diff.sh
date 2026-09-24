#!/usr/bin/env bash
# Contract test for forge-adapt-tier-diff.sh (#281).
#
# `refresh <name>` copies this script's stdout into its report verbatim, so the contract is the
# exact line shape, the fixed key order, silence on equal keys, and an EMPTY stdout whenever it
# cannot answer. The three mutants at the end are the wrong ways to read a tier: the whole file
# rather than the frontmatter, a first `---` accepted below line 1, and the order dropped.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/forge-adapt-tier-diff.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { cat > "$T/$1"; }
out=""; err=""; rc=0
run() { out=$(bash "${S:-$SCRIPT}" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

mk base.md <<'M'
---
name: demo
model: opus
effort: high
---
body
M
mk same.md <<'M'
---
name: demo-adapted
model: opus
effort: high
---
a different body, adapted for the project
M
mk effort-low.md <<'M'
---
name: demo
effort: low
---
body
M
mk no-effort.md <<'M'
---
name: demo
---
body
M
mk all-a.md <<'M'
---
name: demo
model: sonnet
effort: low
context: fork
agent: reviewer
background: true
---
M
mk all-b.md <<'M'
---
name: demo
model: opus
effort: high
context: inherit
agent: other
background: false
---
M
mk body-key.md <<'M'
---
name: demo
model: opus
effort: high
---
An example in the body is not this file's tier:

model: haiku
effort: low
M
mk no-fm.md <<'M'
# A title, not frontmatter
M
mk late-rule.md <<'M'
# No frontmatter on line 1

---
model: opus
---
M
mk unclosed.md <<'M'
---
model: opus
M

echo "== equal keys print nothing =="
run "$T/same.md" "$T/base.md"
expect "identical tier keys exit 0" 0 "$rc"
expect "and print nothing, whatever the bodies" "" "$out"

echo "== one fixed line per differing key =="
run "$T/effort-low.md" "$T/no-effort.md"
expect "a differing key exits 0" 0 "$rc"
expect "an absent catalogue key reads -" "tier: effort local=low forge-kit=- (kept)" "$out"
run "$T/no-effort.md" "$T/base.md"
expect "absent locally reads - on the local side, in key order" \
  "tier: model local=- forge-kit=opus (kept)
tier: effort local=- forge-kit=high (kept)" "$out"
run "$T/all-a.md" "$T/all-b.md"
expect "all five differing print five lines in the fixed order" \
  "tier: model local=sonnet forge-kit=opus (kept)
tier: effort local=low forge-kit=high (kept)
tier: context local=fork forge-kit=inherit (kept)
tier: agent local=reviewer forge-kit=other (kept)
tier: background local=true forge-kit=false (kept)" "$out"

echo "== frontmatter only =="
run "$T/body-key.md" "$T/base.md"
expect "a tier key in the body is ignored" "" "$out"
expect "and that exits 0" 0 "$rc"

echo "== refusals: exit 2, empty stdout, the file named =="
run "$T/no-fm.md" "$T/base.md"
expect "an installed file with no frontmatter exits 2" 2 "$rc"
expect "with nothing on stdout" "" "$out"
case "$err" in *no-fm.md*) ok "and stderr names the file" ;; *) bad "stderr does not name the file: $err" ;; esac
run "$T/base.md" "$T/no-fm.md"
expect "a catalogue file with no frontmatter exits 2 too" 2 "$rc"
run "$T/late-rule.md" "$T/base.md"
expect "a body --- rule below line 1 is not frontmatter" 2 "$rc"
expect "and prints nothing" "" "$out"
run "$T/unclosed.md" "$T/base.md"
expect "an unclosed frontmatter is no frontmatter" 2 "$rc"
run "$T/missing.md" "$T/base.md"
expect "an unreadable file exits 2" 2 "$rc"
expect "with nothing on stdout" "" "$out"
case "$err" in *missing.md*) ok "and stderr names it" ;; *) bad "stderr does not name it: $err" ;; esac
run "$T/base.md"
expect "one argument is a usage error" 2 "$rc"

echo "== the key set is the one array =="
expect "TIER_KEYS holds #253's five keys in order" \
  "TIER_KEYS=(model effort context agent background)" "$(grep -m1 '^TIER_KEYS=' "$SCRIPT")"

echo "== mutants die =="
M="$T/mut"; mkdir -p "$M"; cp "$ROOT/scripts/guard-lib.sh" "$M/"
mutant() {  # mutant <name> <python replace: old> <new> <check-fn>
  python3 - "$SCRIPT" "$M/forge-adapt-tier-diff.sh" "$2" "$3" <<'P' || { bad "mutant $1 did not apply"; return; }
import sys
src = open(sys.argv[1]).read()
if sys.argv[3] not in src: sys.exit(1)
open(sys.argv[2], "w").write(src.replace(sys.argv[3], sys.argv[4]))
P
  if S="$M/forge-adapt-tier-diff.sh" "$4"; then bad "mutant $1 survived"; else ok "mutant $1 dies"; fi
}
body_is_ignored() { run "$T/body-key.md" "$T/base.md"; [ "$rc" = 0 ] && [ -z "$out" ]; }
late_rule_refused() { run "$T/late-rule.md" "$T/base.md"; [ "$rc" = 2 ] && [ -z "$out" ]; }
order_kept() { run "$T/all-a.md" "$T/all-b.md"; [ "$(printf '%s\n' "$out" | head -1)" = "tier: model local=sonnet forge-kit=opus (kept)" ]; }
mutant whole-file 'a=$(component_frontmatter_field "$1" "$k"); b=$(component_frontmatter_field "$2" "$k")' \
  'a=$(sed -n "s/^$k:[[:space:]]*//p" "$1" | tail -1); b=$(sed -n "s/^$k:[[:space:]]*//p" "$2" | tail -1)' body_is_ignored
mutant late-first-rule "awk 'NR==1 && \$0 != \"---\" { exit 1 } NR>1" "awk 'NR>=1" late_rule_refused
mutant order-dropped 'for k in "${TIER_KEYS[@]}"; do' 'for k in $(printf "%s\n" "${TIER_KEYS[@]}" | sort); do' order_kept

echo ""
echo "tier-diff tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
