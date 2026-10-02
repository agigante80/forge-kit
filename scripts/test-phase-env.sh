#!/usr/bin/env bash
# Contract test for #407: /phase's values reach every later Bash call, each a fresh shell.
#
# HOW. The resolve block, the rule's source line and every read are EXTRACTED from the shipped
# phase.md, so this cannot drift from the text users install. A fixture repository holds stub
# assets in scripts/ (the first place the search looks) that print their own names, plus the real
# forge-lib.sh, roadmap-lib.sh and phase-env.sh. The resolve block runs once; every read then runs
# under `env -i` as the rule writes it: the source line, then the read. Assets are removed to show
# that a missing one stops only what reads it, and phase-env.sh is mutated to show each guard holds.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
DOC="${PHASE_DOC:-$ROOT/plugins/forge-kit-roadmap/commands/phase.md}"
ASSETS="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
LIB="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
EH="$T/home"; mkdir -p "$EH"

# fence <pattern>: the one fenced bash block of phase.md holding <pattern>.
fence() { P="$1" awk '/^```bash$/ { inb = 1; buf = ""; next }
  inb && /^```$/ { inb = 0; if (index(buf, ENVIRON["P"])) { k++; keep = buf } next }
  inb { buf = buf $0 "\n" } END { printf "%s", keep; exit (k == 1 ? 0 : 1) }' "$DOC"; }
# span <literal>: the one inline code span of phase.md that starts with <literal>.
span() { grep -o -- '`[^`]*`' "$DOC" | tr -d '`' | grep -F -x -- "$1" | head -1; }

RB=$(fence 'resolve phase-env.sh') || { echo "no single resolve block in $DOC"; exit 1; }
SRC='. "$(git rev-parse --git-path forge-kit-phase-env)" || exit 2'
grep -qF -- "\`$SRC\`" "$DOC" && ok "phase.md states the rule's source line verbatim" || bad "phase.md does not state the source line"
VB=$(fence "forge-lib-version: [0-9]*") || { echo "no single version-check block in $DOC"; exit 1; }
STATUS1=$(span 'bash "${CP:?}"'); CLOSE4=$(span 'bash "${SP:?}"'); RP1=$(span 'bash "${RP:?}" --help')
[ -n "$STATUS1" ] && [ -n "$CLOSE4" ] && [ -n "$RP1" ] && ok "the guarded CP, SP and RP reads are in phase.md" || bad "a guarded read is missing from phase.md"

# fixture [asset...]: a repo whose scripts/ holds the stubs and libraries named (default: all).
fixture() {
  R="$T/r.$RANDOM$RANDOM"; mkdir -p "$R/scripts"; git -C "$R" init -q
  local a; for a in ${@:-check-phases.sh sync-phases.sh reassess-phases.sh check-doc-drift.sh forge-lib.sh roadmap-lib.sh}; do
    case "$a" in
      forge-lib.sh)   cp "$LIB" "$R/scripts/" ;;
      roadmap-lib.sh) cp "$ASSETS/roadmap-lib.sh" "$R/scripts/" ;;
      *) printf '#!/bin/sh\necho "%s $*"\n' "${a%.sh}" > "$R/scripts/$a" ;;
    esac
  done
  cp "${PHASE_ENV:-$ASSETS/phase-env.sh}" "$R/scripts/phase-env.sh"
  resolve_out=$(cd "$R" && env -i PATH="$PATH" HOME="$EH" bash -c "$RB" 2>&1); resolve_rc=$?
}
# fresh <command>: the command in a fresh shell from the fixture, as the rule writes it.
fresh() { out=$(cd "$R" && env -i PATH="$PATH" HOME="$EH" bash -c "$SRC
$1" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

echo "== every asset present =="
fixture
[ "$resolve_rc" = 0 ] && printf '%s' "$resolve_out" | grep -q '^using CP=' && ok "the resolve block writes the env file and prints its picks" \
  || bad "the resolve block: rc $resolve_rc, '$resolve_out'"
fresh "$STATUS1"; [ "$rc" = 0 ] && [ "$out" = "check-phases " ] && [ -z "$err" ] && ok "/phase status step 1 runs check-phases.sh in a fresh shell" || bad "/phase status step 1: rc $rc out '$out' err '$err'"
fresh "$CLOSE4"; [ "$rc" = 0 ] && [ "$out" = "sync-phases " ] && ok "/phase close step 4 runs sync-phases.sh in a fresh shell" || bad "/phase close step 4: rc $rc out '$out' err '$err'"
fresh "$VB"; [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^forge-lib-version: [0-9]' && ok "/phase review's version check reads FL in a fresh shell" || bad "/phase review's version check: rc $rc out '$out' err '$err'"
fresh 'type forge_issue_comments roadmap_set_prose >/dev/null && echo both'
[ "$out" = both ] && ok "/phase review steps 2 and 6 see forge_issue_comments and roadmap_set_prose" || bad "the sourced functions are missing: '$err'"
fresh "$RP1"; [ "$rc" = 0 ] && [ "$out" = "reassess-phases --help" ] && ok "/phase reassess runs reassess-phases.sh in a fresh shell" || bad "/phase reassess: rc $rc out '$out'"
fresh '[ -n "$DD" ] && bash "$DD" --range a..b'; [ "$out" = "check-doc-drift --range a..b" ] && ok "/phase review step 4 runs check-doc-drift.sh when DD is set" || bad "step 4 with DD: '$out'"
( cd "$R" && mkdir -p sub && cd sub && env -i PATH="$PATH" HOME="$EH" bash -c "$SRC
$STATUS1" ) >"$T/o" 2>&1; [ "$(cat "$T/o")" = "check-phases " ] && ok "the source line works from a subdirectory" || bad "from a subdirectory: '$(cat "$T/o")'"

echo "== a missing asset stops only what reads it =="
fixture check-phases.sh sync-phases.sh forge-lib.sh roadmap-lib.sh
fresh "$STATUS1"; [ "$rc" = 0 ] && [ "$out" = "check-phases " ] && [ -z "$err" ] && ok "with check-doc-drift.sh and reassess-phases.sh unresolvable, /phase status step 1 still runs" || bad "status with optional assets missing: rc $rc out '$out' err '$err'"
fresh "$CLOSE4"; [ "$rc" = 0 ] && [ "$out" = "sync-phases " ] && ok "and /phase close step 4 still runs" || bad "close with optional assets missing: rc $rc err '$err'"
fresh '[ -n "$DD" ] && bash "$DD" --range a..b; echo done'; [ "$out" = done ] && ok "an empty DD skips the drift check (the skill asks the question by hand)" || bad "empty DD: '$out' '$err'"
fresh "$RP1 --check"; [ "$rc" != 0 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'RP: parameter null or not set' \
  && ! printf '%s' "$err" | grep -q 'No such file or directory\|command not found' \
  && ok "/phase reassess with reassess-phases.sh unresolvable stops: 'RP: parameter null or not set'" || bad "reassess with RP missing: rc $rc out '$out' err '$err'"
fixture check-phases.sh sync-phases.sh forge-lib.sh
fresh "$STATUS1"; [ "$rc" = 0 ] && [ "$out" = "check-phases " ] && [ -z "$err" ] && ok "with roadmap-lib.sh unresolvable, /phase status step 1 still runs (rc 0, empty stderr)" || bad "status with RL empty: rc $rc out '$out' err '$err'"
fresh "$VB"; [ "$rc" != 0 ] && printf '%s' "$err" | grep -q 'RL: parameter null or not set' && ok "and /phase review's version check stops naming RL" || bad "review with RL empty: rc $rc err '$err'"
rm -f "$(cd "$R" && git rev-parse --absolute-git-dir)/forge-kit-phase-env"
fresh "$STATUS1"; [ "$rc" = 2 ] && [ -z "$out" ] && ok "with the env file absent the source line exits 2" || bad "env file absent: rc $rc out '$out'"

echo "== the search is colon-safe =="
CH="$T/chome"; mkdir -p "$CH/.claude/plugins/a:b" "$CH/.claude/plugins/plain"
printf '#!/bin/sh\n# check-phases-version: 9\necho high\n' > "$CH/.claude/plugins/a:b/check-phases.sh"
printf '#!/bin/sh\n# check-phases-version: 3\necho low\n' > "$CH/.claude/plugins/plain/check-phases.sh"
cp "$ASSETS/phase-env.sh" "$CH/.claude/plugins/a:b/phase-env.sh"
R="$T/colon"; mkdir -p "$R"; git -C "$R" init -q
( cd "$R" && env -i PATH="$PATH" HOME="$CH" bash -c "$RB" ) >/dev/null 2>&1
out=$(cd "$R" && env -i PATH="$PATH" HOME="$CH" bash -c "$SRC
$STATUS1" 2>&1)
[ "$out" = high ] && ok "the highest marker wins although its path holds a colon (phase.md's resolve and phase-env.sh)" || bad "colon path: '$out'"

echo "== no read of a resolved value is left unguarded in phase.md =="
lint() { grep -nE '"\$(CP|SP|RP|FL|RL)"' "$1"; }
[ -z "$(lint "$DOC")" ] && ok "every CP, SP, RP, FL and RL read is \${X:?}" || bad "unguarded reads: $(lint "$DOC")"
sed 's/bash "${RP:?}" --help/bash "$RP" --help/' "$DOC" > "$T/phase-mut.md"
[ -n "$(lint "$T/phase-mut.md")" ] && ok "mutant: a read restored to bare \"\$RP\" fails the lint" || bad "mutant: the lint missed a bare \"\$RP\""
out=$(cd "$T/colon" && env -i PATH="$PATH" HOME="$EH" bash -c 'RP=; bash "$RP" --help' 2>&1)
case "$out" in *"No such file or directory"*) ok "and that bare read is the 'bash \"\"' failure #407 removes" ;; *) bad "bare RP read: '$out'" ;; esac

echo "== mutants of phase-env.sh =="
. "$ROOT/scripts/mutant-crash.sh"
# pe_live: the build, with all six assets present, still resolves and runs /phase status step 1
# (#360). It never reads the case's stderr, because two genuine kills ARE bash diagnostics; it
# writes the resolve output and its own fresh shell's stderr to stderr, the log
# mutant_crash_reason_live reads.
pe_live() {
  PHASE_ENV="$T/pe-mut.sh" fixture; printf '%s\n' "$resolve_out" >&2
  [ "$resolve_rc" = 0 ] || return 1
  fresh "$STATUS1"; printf '%s\n' "$err" >&2
  [ "$rc" = 0 ] && [ "$out" = "check-phases " ]
}
mutant() {  # mutant <name> <awk program> <assets...> -- <command> <expect>: the case must fail
  local name="$1" prog="$2" held=0 got why; shift 2; local assets=(); while [ "$1" != -- ]; do assets+=("$1"); shift; done; shift
  awk "$prog" "$ASSETS/phase-env.sh" > "$T/pe-mut.sh"
  cmp -s "$ASSETS/phase-env.sh" "$T/pe-mut.sh" && { bad "mutant $name: nothing to change"; return; }
  PHASE_ENV="$T/pe-mut.sh" fixture "${assets[@]}"; fresh "$1"
  [ "$rc" = 0 ] && [ "$out" = "$2" ] && [ -z "$err" ] && held=1
  got="rc $rc${err:+, $(printf '%s' "$err" | head -1)}"
  why=$(mutant_crash_reason_live "$T/pe-mut.sh" pe_live)
  if [ -n "$why" ]; then bad "mutant $name crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant $name survived"
  else ok "mutant $name dies ($got)"; fi
}
# The awk programs replace phase-env.sh's last printf line (the libraries and the final `:`).
LAST='/^printf .%s\\n. .if/'
P_NOFL=$LAST' { print "printf '"'"'%s\\n'"'"' '"'"'if [ -n \"$RL\" ]; then . \"$RL\"; fi'"'"' '"'"':'"'"'"; next } 1'
P_AND=$LAST' { print "printf '"'"'%s\\n'"'"' '"'"'if [ -n \"$FL\" ]; then . \"$FL\"; fi'"'"' '"'"'[ -n \"$RL\" ] && . \"$RL\"'"'"'"; next } 1'
P_DD=$LAST' { print "echo '"'"': \"${DD:?}\"'"'"'" } 1'
mutant "no FL source" "$P_NOFL" check-phases.sh forge-lib.sh roadmap-lib.sh -- 'type forge_issue_comments >/dev/null && echo yes' yes
mutant "bare && last line" "$P_AND" check-phases.sh forge-lib.sh -- "$STATUS1" "check-phases "
mutant "a missing DD fails the file" "$P_DD" check-phases.sh forge-lib.sh roadmap-lib.sh -- "$STATUS1" "check-phases "
# pe_search_live: the colon-search build, run in an empty repository under the empty HOME, still
# prints its six assignments and exits 0 (#360).
pe_search_live() {
  local o; o=$(CDPATH= cd -- "$T/colon2" && env -i PATH="$PATH" HOME="$EH" bash "$T/pe-sort.sh") || return 1
  [ "$(printf '%s\n' "$o" | grep -c '^[A-Z][A-Z]=')" = 6 ]
}
pe_search_mutant() {  # pe_search_mutant <name> <awk program>: the colon-path pick must be lost
  local name="$1" why
  awk "$2" "$ASSETS/phase-env.sh" > "$T/pe-sort.sh"
  if cmp -s "$ASSETS/phase-env.sh" "$T/pe-sort.sh"; then bad "mutant $name: nothing to change"; return; fi
  R="$T/colon2"; mkdir -p "$R"; git -C "$R" init -q
  out=$(CDPATH= cd -- "$R" && env -i PATH="$PATH" HOME="$CH" bash "$T/pe-sort.sh" | sed -n 's/^CP=//p')
  why=$(mutant_crash_reason_live "$T/pe-sort.sh" pe_search_live)
  if [ -n "$why" ]; then bad "mutant $name crashed ($why)"; return; fi
  case "$out" in *a:b*) bad "mutant $name survived" ;; *) ok "mutant $name dies (picked '$out')" ;; esac
}
pe_search_mutant "old sort -t: search" '/^[[:space:]]*\| sed .*sort -t/ { print "    | sort -t: -k3,3n -k1,1 | tail -1 | cut -d: -f1"; next } 1'
# Crash control (#360): a phase-env.sh that exits, through both harnesses, judged in one row. They
# run in $( ), so their rows stay out of the total.
P_CRASH='NR==1 { print; print "exit 127"; next } 1'
awk "$P_CRASH" "$ASSETS/phase-env.sh" > "$T/pe-crash.sh"
crash_ok=1
cmp -s "$T/pe-crash.sh" "$ASSETS/phase-env.sh" && crash_ok=0
cap=$(mutant crash-control "$P_CRASH" check-phases.sh forge-lib.sh roadmap-lib.sh -- "$STATUS1" "check-phases "
      pe_search_mutant crash-control "$P_CRASH")
case "$cap" in *" dies"*|*" survived"*) crash_ok=0 ;; esac
[ "$(printf '%s\n' "$cap" | grep -c '^  FAIL: mutant crash-control crashed (')" = 2 ] || crash_ok=0
[ "$crash_ok" = 1 ] && ok "crash control (#360): phase-env reports a crashing phase-env.sh as crashed, never as dies" \
  || bad "crash control (#360): phase-env credited or missed a crashing phase-env.sh"

echo ""
echo "phase-env tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
