#!/usr/bin/env bash
# Contract test for ticket-gate-reference/assets/gate-env.sh (#347): what each ticket-gate Bash call
# sources to rebuild what a fresh shell loses. Every case sources the asset in a FRESH bash with a
# throwaway D, HOME and plugin tree; forge-lib is a stub file that defines forge_repo and records
# that it was sourced. Then ticket-gate.md is read structurally: Steps 3A, 5 and 6 each open with the
# source line, and no block after Step 1 names a variable from the preamble's shell.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSET="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/gate-env.sh"
GATE_MD="$ROOT/plugins/forge-kit-governance/agents/ticket-gate.md"
[ -f "$ASSET" ] || { echo "missing asset: $ASSET"; exit 1; }

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# stub_lib <path> <tag>: a forge-lib stand-in that records which copy was sourced.
stub_lib() { mkdir -p "$(dirname "$1")"; printf '# forge-lib-version: %s\nforge_repo() { echo o/r; }\necho "%s" >> "$SOURCED"\n' "${3:-1}" "$2" > "$1"; }
# layout <dir> [with-lib]: a checker, gate-status.sh and gate-env.sh in <dir>, optionally forge-lib.
layout() { mkdir -p "$1"; : > "$1/check-ticket-mechanics.sh"; : > "$1/gate-status.sh"; cp "$ASSET" "$1/gate-env.sh"; [ "${2:-}" = with-lib ] && stub_lib "$1/forge-lib.sh" beside; return 0; }
# ge <D> [env assignments...]: source the asset as the gate does, in a fresh bash with HOME=$W/home;
# prints rc, then MECH A GS FORGE_LIB(child) forge_repo, one per line. stderr goes to $W/err.
ge() {
  local d=$1; shift
  env -i PATH="$PATH" HOME="$W/home" SOURCED="$W/sourced" "$@" bash -c '
    D='"'$d'"'; . "$(dirname "$(cat "$D/mech" 2>/dev/null)")/gate-env.sh"; rc=$?
    echo "rc=$rc"; echo "MECH=${MECH-}"; echo "A=${A-}"; echo "GS=${GS-}"
    echo "child=$(bash -c '\''echo "${FORGE_LIB-}"'\'')"; echo "repo=$(forge_repo 2>/dev/null)"' 2>"$W/err"
}
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
fresh() { rm -rf "$W/home" "$W/sourced" "$W"/case; mkdir -p "$W/home/.claude/plugins" "$W/case"; : > "$W/sourced"; }

echo "== gate-env.sh: resolution =="
fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"
o=$(ge "$D")
[ "$(field "$o" rc)" = 0 ] && [ "$(field "$o" MECH)" = "$W/case/scripts/check-ticket-mechanics.sh" ] && [ "$(field "$o" GS)" = "$W/case/scripts/gate-status.sh" ] \
  && [ "$(field "$o" repo)" = o/r ] && [ "$(field "$o" child)" = "$W/case/scripts/forge-lib.sh" ] \
  && ok "the scripts/ layout resolves MECH, A, GS and the forge-lib beside it, exported to a child" || bad "the scripts/ layout did not resolve: $o $(cat "$W/err")"
o=$(ge "$D" FORGE_LIB=); [ "$(field "$o" rc)" = 0 ] && [ "$(cat "$W/sourced" | tail -1)" = beside ] \
  && ok "an empty FORGE_LIB means unset" || bad "an empty FORGE_LIB was not treated as unset: $o"
fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"
o=$(ge "$D" FORGE_LIB=/nonexistent/forge-lib.sh)
[ "$(field "$o" rc)" = 2 ] && grep -q 'FORGE_LIB=/nonexistent/forge-lib.sh is not a file' "$W/err" && [ ! -s "$W/sourced" ] \
  && ok "a FORGE_LIB naming a missing file is refused, nothing sourced, never a fall-back" || bad "an invalid FORGE_LIB was not refused: $o $(cat "$W/err")"
stub_lib "$W/case/mine.sh" mine; o=$(ge "$D" FORGE_LIB="$W/case/mine.sh")
[ "$(field "$o" rc)" = 0 ] && [ "$(tail -1 "$W/sourced")" = mine ] && ok "a valid FORGE_LIB wins over the copy beside the checker" || bad "a valid FORGE_LIB was not used: $o"

echo "== gate-env.sh: \$D/mech guards =="
fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"
o=$(ge "$D"); [ "$(field "$o" rc)" != 0 ] && [ ! -s "$W/sourced" ] && ok "a missing \$D/mech: rc non-zero, nothing sourced" || bad "a missing \$D/mech was not refused: $o"
: > "$D/mech"; o=$(ge "$D"); [ "$(field "$o" rc)" != 0 ] && [ ! -s "$W/sourced" ] && ok "an empty \$D/mech: rc non-zero, nothing sourced" || bad "an empty \$D/mech was not refused: $o"
echo "$W/case/nowhere/check-ticket-mechanics.sh" > "$D/mech"; o=$(ge "$D"); [ "$(field "$o" rc)" != 0 ] && [ ! -s "$W/sourced" ] && ok "a \$D/mech naming a missing checker: rc non-zero, nothing sourced" || bad "a dead \$D/mech was not refused: $o"
# Sourced directly with the asset path known but D unset, the asset's own guard names \$D/mech.
o=$(env -i PATH="$PATH" HOME="$W/home" SOURCED="$W/sourced" bash -c '. "'"$W/case/scripts/gate-env.sh"'"; echo "rc=$?"' 2>"$W/err")
[ "$(field "$o" rc)" = 2 ] && grep -q '/mech; run Step 0 first' "$W/err" && ok "sourced with D unset, the asset refuses and names \$D/mech" || bad "the D guard did not fire: $o $(cat "$W/err")"
# A checker path that exists once Step 1 ran, then was removed: the asset names the stale record.
fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"; rm "$W/case/scripts/check-ticket-mechanics.sh"
# #431 item 6: the header names Step 0, the step that writes $D/mech, not Step 1.
hdr=$(sed -n 1,12p "$ASSET")
{ grep -qF 'Step 0 sources it' <<< "$hdr" && grep -qF 'the checker Step 0 chose' <<< "$hdr" && ! grep -qE 'Step 1 (sources|chose)|Step 1 chose' <<< "$hdr"; } \
  && ok "the header names Step 0 as the writer of \$D/mech (#431)" || bad "the header still names Step 1 as the writer of \$D/mech (#431)"
o=$(ge "$D"); [ "$(field "$o" rc)" = 2 ] && grep -q 'which does not exist' "$W/err" && [ ! -s "$W/sourced" ] && ok "a checker removed after Step 1 is refused by name" || bad "a removed checker was not refused: $o $(cat "$W/err")"

echo "== gate-env.sh: the plugin cache, colon-safe =="
cache_case() {  # cache_case <dir with colon or not> <version> ...: stubs under the throwaway HOME
  fresh; layout "$W/case/gov/skills/ticket-gate-reference/assets"; D="$W/case/d"; mkdir -p "$D"
  echo "$W/case/gov/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh" > "$D/mech"
  while [ $# -gt 0 ]; do stub_lib "$W/home/.claude/plugins/$1/forge-kit-devops/skills/forge-host/assets/forge-lib.sh" "$1" "$2"; shift 2; done
}
cache_case c29 29 c30 30; o=$(ge "$D")
[ "$(field "$o" rc)" = 0 ] && [ "$(tail -1 "$W/sourced")" = c30 ] && ok "the highest cache version wins (30 over 29)" || bad "the cache search did not pick 30: $o $(cat "$W/sourced")"
cache_case c29 29 c30 30 'a:b' 31; o=$(ge "$D")
[ "$(field "$o" rc)" = 0 ] && [ "$(tail -1 "$W/sourced")" = 'a:b' ] && [ "$(field "$o" child)" = "$W/home/.claude/plugins/a:b/forge-kit-devops/skills/forge-host/assets/forge-lib.sh" ] \
  && ok "a path holding a colon keeps its version (31) and its whole path" || bad "the colon path was not chosen whole: $o $(cat "$W/sourced")"
cache_case; o=$(ge "$D")
[ "$(field "$o" rc)" = 2 ] && grep -q 'forge-lib.sh not found' "$W/err" && ok "no copy anywhere is refused by name" || bad "a missing forge-lib was not refused: $o"

echo "== mutants =="
. "$ROOT/scripts/mutant-crash.sh"
# ge_live: the build, sourced in the scripts/ layout with the forge-lib stub, still resolves (#360).
ge_live() { local o; fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"
  o=$(ge "$D"); [ "$(field "$o" rc)" = 0 ] && [ "$(field "$o" repo)" = o/r ] && [ "$(field "$o" GS)" = "$W/case/scripts/gate-status.sh" ]; }
# m_ge <name> <old> <new> <check-fn>: the check must FAIL on a copy of the asset with one edit, and
# the copy must not crash (#360): it must parse, leave no signature in the check's stderr, and pass
# ge_live.
m_ge() {
  local name=$1 old=$2 new=$3 fn=$4 real=$ASSET
  OLD="$old" NEW="$new" python3 - "$real" "$W/mut.sh" <<'PY' || { bad "mutant '$name': anchor not found once"; return; }
import os, sys
s = open(sys.argv[1]).read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(sys.argv[2], "w").write(s.replace(o, os.environ["NEW"]))
PY
  local held=0 why
  ASSET="$W/mut.sh"; "$fn" && held=1; cp "$W/err" "$W/mut-err.log" 2>/dev/null || : > "$W/mut-err.log"
  why=$(mutant_crash_reason "$W/mut.sh" "$W/mut-err.log" ge_live); ASSET=$real
  if [ -n "$why" ]; then bad "mutant '$name' crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant '$name' survived"
  else ok "mutant '$name' dies"; fi
}
chk_strict() { fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"
  o=$(ge "$D" FORGE_LIB=/nonexistent/forge-lib.sh); [ "$(field "$o" rc)" = 2 ] && [ ! -s "$W/sourced" ] && grep -q 'FORGE_LIB=/nonexistent/forge-lib.sh is not a file' "$W/err"; }
chk_export() { fresh; layout "$W/case/scripts" with-lib; D="$W/case/d"; mkdir -p "$D"; echo "$W/case/scripts/check-ticket-mechanics.sh" > "$D/mech"
  o=$(ge "$D"); [ "$(field "$o" child)" = "$W/case/scripts/forge-lib.sh" ]; }
chk_colon() { cache_case c30 30 'a:b' 31; o=$(ge "$D"); [ "$(tail -1 "$W/sourced")" = 'a:b' ]; }
chk_guard() { o=$(env -i PATH="$PATH" HOME="$W/home" SOURCED="$W/sourced" bash -c '. "'"$ASSET"'"; echo "rc=$?"' 2>"$W/err"); [ "$(field "$o" rc)" = 2 ] && grep -q '/mech; run Step 0 first' "$W/err"; }
m_ge "FORGE_LIB file test removed" '[ -f "$FORGE_LIB" ] || { echo "ticket-gate: FORGE_LIB=$FORGE_LIB is not a file; refusing to fall back" >&2; return 2; }   # gate-env: strict' ':' chk_strict
m_ge "FORGE_LIB not exported" 'export FORGE_LIB=$_ge_lib   # gate-env: export' 'FORGE_LIB=$_ge_lib' chk_export
m_ge "colon-unsafe sort restored" "| sed 's/:forge-lib-version: \\([0-9]*\\)\$/	\\1/' | sort -t'	' -k2,2n -k1,1 | tail -1 | cut -f1)" "| sort -t: -k3,3n -k1,1 | tail -1 | cut -d: -f1)" chk_colon
m_ge "\$D/mech guard removed" 'if [ -z "${D:-}" ] || [ ! -s "$D/mech" ]; then' 'if false; then' chk_guard
# Crash control (#360): a gate-env.sh that exits, then one that does not parse. m_ge has no no-op
# check, so the control compares each build with the asset itself. m_ge runs in $( ), so its rows
# stay out of the total.
crash_ok=1; crashed=0
for x in 'exit 127' 'fi fi'; do
  cap=$(m_ge crash-control '# gate-env-version: 2' "# gate-env-version: 2
$x" chk_strict)
  cmp -s "$W/mut.sh" "$ASSET" && crash_ok=0
  case "$cap" in *" dies"*|*" survived"*) crash_ok=0 ;; *"FAIL: mutant 'crash-control' crashed ("*) crashed=$((crashed + 1)) ;; esac
done
[ "$crash_ok" = 1 ] && [ "$crashed" = 2 ] && ok "crash control (#360): m_ge reports a crashing gate-env.sh as crashed, never as dies" \
  || bad "crash control (#360): m_ge credited or missed a crashing gate-env.sh ($crashed of 2 crashed)"

echo "== ticket-gate.md: every later step sources it =="
# first_block <step heading prefix>: the first fenced bash block after that heading.
first_block() { awk -v h="$1" 'index($0, h) == 1 { on = 1; next } on && /^### Step/ { exit } on && /^```bash$/ { inb = 1; next } inb && /^```$/ { exit } inb { print }' "$2"; }
SRC='D=<scratchpad>/gate-<NUMBER>; . "$(dirname "$(cat "$D/mech")")/gate-env.sh" || exit 2'
for st in "### Step 1:" "### Step 3A" "### Step 5" "### Step 6"; do
  [ "$(first_block "$st" "$GATE_MD" | head -1)" = "$SRC" ] && ok "${st#\#\#\# } opens with the gate-env.sh source line" || bad "${st#\#\#\# } does not open with the source line"
done
grep -q '\. "$(dirname "$MECH")/gate-env.sh" || exit 2' <<< "$(first_block "### Step 0:" "$GATE_MD")" && ok "Step 0's preamble sources gate-env.sh after writing \$D/mech" || bad "Step 0's preamble does not source gate-env.sh"
# 0a and 0b make a forge call in a fresh shell, so each fetch is preceded by the source line (#286).
[ "$(grep -B1 -F 'I=$(forge_issue_view' "$GATE_MD" | grep -cxF "$SRC")" = 2 ] && ok "0a and 0b open their fetch with the gate-env.sh source line" || bad "0a or 0b fetches without the gate-env.sh source line"
grep -q '"\$REPO"' <<< "$(awk '/^### Step 1:/ { on = 1 } on' "$GATE_MD")" && bad "a block after Step 1 names \$REPO from the preamble's shell" || ok "no block after Step 1 names \$REPO from the preamble's shell"
sed "s|^$(printf '%s' "$SRC" | sed 's/[][\.*^$|]/\\&/g')\$||" "$GATE_MD" > "$W/gate-nosrc.md"
cmp -s "$GATE_MD" "$W/gate-nosrc.md" && bad "the no-source copy did not apply"
[ "$(first_block "### Step 6" "$W/gate-nosrc.md" | head -1)" = "$SRC" ] && bad "mutant 'Step 6 source line deleted' survived" || ok "mutant 'Step 6 source line deleted' dies"
grep -q 'gate-env-version: [0-9]' "$ASSET" && ok "the asset carries its version marker" || bad "the asset has no version marker"

echo ""
echo "gate-env tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
