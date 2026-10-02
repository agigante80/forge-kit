#!/usr/bin/env bash
# Contract test for /phase review's second-run proof (#394): the step 1, step 4 and step 7 snippets
# of plugins/forge-kit-roadmap/commands/phase.md, EXTRACTED from the command at run time and run in
# throwaway git repositories, so the prose and the test cannot drift apart.
#
# WHY IT EXISTS. The snapshot was one fixed file per repository, so an overlapping run's step 1
# overwrote an earlier run's baseline and the earlier run's step 7 printed `held` over a path that
# changed during it, and a finishing run deleted the other run's file. Each run now owns
# `phase-review.<id>`, the id printed by step 1 and carried into steps 4 and 7 as a literal.
#
# EXTRACTION FAILS LOUDLY. Each snippet is the one fenced bash block carrying its marker: `XXXXXX`
# (step 1), `no docs beyond the roadmap and plan` (step 4), `second-run proof` (step 7). Zero or
# two matches, or a placeholder substitution that changes nothing, aborts the suite with a named
# message and exit 1, never a skip.
#
# MUTANTS (run below on a copy of phase.md, each must fail its named case): the shared fixed name
# restored in step 1 (markers kept, so extraction still works) fails the overlap negative by
# printing `held`; step 7's rm widened to a phase-review.* glob fails the finished-run positive;
# `-mtime +1` dropped from step 1's find fails the live-run negative; step 4 pinned to another name
# fails the step 4 positive.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
DOC="$ROOT/plugins/forge-kit-roadmap/commands/phase.md"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
die() { echo "test-phase-review-snapshot: $1" >&2; exit 1; }

[ -f "$DOC" ] || die "missing command: $DOC"
T="$(mktemp -d)" || die "cannot make a temp dir"
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# extract <doc> <outdir>: writes step1.sh, step4.sh and step7.sh, or dies naming what is wrong.
extract() {
  local doc="$1" out="$2" name marker n
  mkdir -p "$out"
  for name in step1:XXXXXX "step4:no docs beyond the roadmap and plan" "step7:second-run proof"; do
    marker="${name#*:}"; name="${name%%:*}"
    n="$(M="$marker" awk '
      /^```bash$/ { inb = 1; buf = ""; next }
      inb && /^```$/ { inb = 0; if (index(buf, ENVIRON["M"])) { k++; keep = buf } next }
      inb { buf = buf $0 "\n" }
      END { printf "%s", keep > "/dev/stderr"; print k + 0 }' "$doc" 2>"$out/$name.sh")"
    [ "$n" = 1 ] || die "$name: expected exactly one bash block carrying '$marker' in $(basename "$doc"), found $n"
  done
}
# fill <file> <from> <to>: a literal, whole-file substitution (so <from> may span lines) that must
# find <from>. The quoted pattern makes bash match it literally.
fill() {
  local c; c="$(cat "$1"; printf x)"; c="${c%x}"
  case "$c" in *"$2"*) ;; *) die "placeholder '$2' not found in $(basename "$1")" ;; esac
  printf '%s' "${c//"$2"/"$3"}" > "$1"
}

newrepo() {  # newrepo: a throwaway repo with the three covered paths; sets R
  R="$(mktemp -d "$T/repo.XXXXXX")"
  ( cd "$R" && git init -q . && git config user.email t@t.invalid && git config user.name t \
    && mkdir -p docs/plans && printf 'r\n' > docs/roadmap.md && printf 'p\n' > docs/plans/p1.md \
    && printf 'x\n' > README.md && printf 'c\n' > CHANGELOG.md && git add -A && git commit -qm init ) >/dev/null 2>&1
}
SRC=""   # the extracted snippets in use (the real command, or a mutant's)
step1() {  # step1 <doc>: run step 1 in $R listing that document; prints the run id
  cp "$SRC/step1.sh" "$T/s1.sh"; fill "$T/s1.sh" '"<plan>" "<doc>"...' "\"docs/plans/p1.md\" \"$1\""
  ( cd "$R" && bash "$T/s1.sh" ) | sed -n 's/^run id: //p'
}
step4() {  # step4 <id>: run step 4's read-back in $R
  cp "$SRC/step4.sh" "$T/s4.sh"; [ "$1" = ID ] || fill "$T/s4.sh" 'RUN=ID' "RUN=$1"; fill "$T/s4.sh" '"<plan>"' '"docs/plans/p1.md"'
  ( cd "$R" && bash "$T/s4.sh" )
}
step7() {  # step7 <id>: run step 7 in $R with ACTS=0
  cp "$SRC/step7.sh" "$T/s7.sh"; [ "$1" = ID ] || fill "$T/s7.sh" 'RUN=ID' "RUN=$1"; fill "$T/s7.sh" 'ACTS=N' 'ACTS=0'
  ( cd "$R" && bash "$T/s7.sh" )
}
snapfile() { printf '%s/.git/phase-review.%s' "$R" "$1"; }
HELD='second-run proof: held (3 paths unchanged, 0 acts)'
NOTHELD='second-run proof: not held, changed during the run: docs/roadmap.md'
UNPROVEN='second-run proof: unproven, no snapshot from step 1'

# Each case returns 0 when the command behaves as #394 requires; the real command must pass all,
# and each mutant must fail its named one.
c_single_held() { newrepo; local a; a="$(step1 README.md)"; [ -n "$a" ] || return 1
  [ "$(step7 "$a")" = "$HELD" ] && [ ! -e "$(snapfile "$a")" ] && [ ! -e "$(snapfile "$a").after" ]; }
c_single_notheld() { newrepo; local a; a="$(step1 README.md)"; printf 'x\n' >> "$R/docs/roadmap.md"
  [ "$(step7 "$a")" = "$NOTHELD" ]; }
c_overlap_held() { newrepo; local a b; a="$(step1 README.md)"; b="$(step1 README.md)"; [ "$a" != "$b" ] || return 1
  [ "$(step7 "$a")" = "$HELD" ]; }
c_overlap_notheld() { newrepo; local a b o; a="$(step1 README.md)"; printf 'x\n' >> "$R/docs/roadmap.md"; b="$(step1 README.md)"
  o="$(step7 "$a")"; [ "$o" = "$NOTHELD" ] && ! grep -q '^second-run proof: held' <<< "$o"; }
c_finished_other_held() { newrepo; local a b; a="$(step1 README.md)"; b="$(step1 README.md)"
  [ "$(step7 "$b")" = "$HELD" ] && [ "$(step7 "$a")" = "$HELD" ]; }
c_finished_other_notheld() { newrepo; local a b o; a="$(step1 README.md)"; b="$(step1 README.md)"; step7 "$b" >/dev/null
  printf 'x\n' >> "$R/docs/roadmap.md"; o="$(step7 "$a")"
  [ "$o" = "$NOTHELD" ] && ! grep -q '^second-run proof: held' <<< "$o"; }
c_wrong_id() { newrepo; local a id o; a="$(step1 README.md)"
  for id in '' ID zzzzzz ../x; do
    o="$(step7 "$id")"; [ "$o" = "$UNPROVEN" ] || { echo "    id '$id': $o"; return 1; }
    [ -e "$(snapfile "$a")" ] || { echo "    id '$id' removed the run's file"; return 1; }
  done; [ "$(step7 "$a")" = "$HELD" ]; }
c_orphan_cleaned() { newrepo; printf 'old\n' > "$R/.git/phase-review.OLD123"; touch -t 200001010000 "$R/.git/phase-review.OLD123"
  local a; a="$(step1 README.md)"; [ ! -e "$R/.git/phase-review.OLD123" ] && [ -e "$(snapfile "$a")" ]; }
c_live_kept() { newrepo; local a b; a="$(step1 README.md)"; b="$(step1 README.md)"
  [ -e "$(snapfile "$a")" ] && [ "$(step7 "$a")" = "$HELD" ]; }
c_step4_own() { newrepo; local a b; a="$(step1 README.md)"; b="$(step1 CHANGELOG.md)"
  [ "$(step4 "$a")" = README.md ] && [ "$(step4 "$b")" = CHANGELOG.md ]; }
c_step4_none() { newrepo; [ "$(step4 zzzzzz)" = "no snapshot from step 1" ]; }

run_cases() {  # run_cases <srcdir>: every case against those snippets, as ok/bad rows
  SRC="$1"
  c_single_held && ok "a single run with nothing changed prints held and removes its own files" || bad "single run: not held, or its files remain"
  c_single_notheld && ok "a single run whose roadmap changed prints not held" || bad "single run: a change was not reported"
  c_overlap_held && ok "two overlapping runs get distinct ids and the earlier still prints held" || bad "overlap: the earlier run lost held"
  c_overlap_notheld && ok "an edit before an overlapping run's step 1 is still not held for the earlier run (the reported defect)" || bad "overlap: the earlier run printed held over a changed path"
  c_finished_other_held && ok "a run that finishes first leaves the other run's file, which still proves held" || bad "finished run: the other run's evidence was removed"
  c_finished_other_notheld && ok "after the other run finishes, an edit is still not held for the earlier run" || bad "finished run: the earlier run printed held over a changed path"
  c_wrong_id && ok "a missing, placeholder, mistyped or path-shaped id is unproven and deletes nothing" || bad "a wrong id was not unproven, or deleted the run's file"
  c_orphan_cleaned && ok "step 1 deletes an orphan snapshot two or more days old" || bad "an orphan snapshot survived step 1"
  c_live_kept && ok "step 1 never deletes a live run's snapshot" || bad "a live run's snapshot was deleted by another step 1"
  c_step4_own && ok "step 4 reads its own run's document list" || bad "step 4 read another run's document list"
  c_step4_none && ok "step 4 with an id no step 1 printed reports no snapshot" || bad "step 4 with an unknown id did not report no snapshot"
}

echo "== the real command =="
extract "$DOC" "$T/real"
grep -q 'phase-review.snapshot' "$T/real/step1.sh" "$T/real/step4.sh" "$T/real/step7.sh" \
  && bad "no snippet names the shared phase-review.snapshot file" || ok "no snippet names the shared phase-review.snapshot file"
run_cases "$T/real"

echo "== mutants, each must fail its named case =="
. "$ROOT/scripts/mutant-crash.sh"
# ps_live: the snippets in $SRC still work on a new repository (#360): step 1 prints a run id, step
# 4 prints exactly one line for it, and step 7 prints held.
ps_live() { newrepo; local a o; a="$(step1 README.md)"; [ -n "$a" ] || return 1
  o="$(step4 "$a")"; [ -n "$o" ] && [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] || return 1
  [ "$(step7 "$a")" = "$HELD" ]; }
# mutate <name> <from> <to> <case>: a copy of phase.md with one literal change; the case must fail,
# and the snippets must not crash (#360): each must parse, and step 7, the one ps_live can tell
# apart, must leave no signature in the case's stderr and pass ps_live.
mutate() {
  local name="$1" d="$T/mut-$1" held=0 why s
  mkdir -p "$d"; cp "$DOC" "$d/phase.md"; fill "$d/phase.md" "$2" "$3"
  extract "$d/phase.md" "$d"; SRC="$d"
  "$4" >/dev/null 2>"$d/case-err.log" && held=1
  for s in step1 step4; do why=$(mutant_crash_reason "$d/$s.sh" /dev/null); [ -z "$why" ] || break; done
  [ -n "$why" ] || why=$(mutant_crash_reason "$d/step7.sh" "$d/case-err.log" ps_live)
  if [ -n "$why" ]; then bad "mutant '$name' crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant '$name' survived $4"
  else ok "mutant '$name' dies on $4"; fi
}
mutate shared-name 'SNAP="$(mktemp "$G.XXXXXX")"' 'SNAP="$G.snapshot" && : XXXXXX' c_overlap_notheld
mutate rm-glob 'rm -f "$SNAP" "$SNAP.after"' 'rm -f "$(dirname "$SNAP")"/phase-review.*' c_finished_other_held
mutate no-mtime " -mtime +1 -delete" " -delete" c_live_kept
mutate step4-other-name 'SNAP="$(git rev-parse --git-path "phase-review.$RUN")"
if [ ! -f "$SNAP" ]; then echo "no snapshot from step 1"' 'SNAP="$(git rev-parse --git-path "phase-review.zzzzzz")"
if [ ! -f "$SNAP" ]; then echo "no snapshot from step 1"' c_step4_own
# Crash control (#360): a step 7 that exits before it runs, on a case that credited it and on one
# that read it as a survivor. mutate runs in $( ), so its rows stay out of the total.
OPEN7='( cd "$(git rev-parse --show-toplevel)" &&
  RUN=ID'
mkdir -p "$T/crash"; cp "$DOC" "$T/crash/phase.md"; fill "$T/crash/phase.md" "$OPEN7" "exit 127
$OPEN7"
crash_ok=1; crashed=0
cmp -s "$T/crash/phase.md" "$DOC" && crash_ok=0
for c in c_overlap_notheld c_step4_own; do
  cap=$(mutate crash-control "$OPEN7" "exit 127
$OPEN7" "$c")
  case "$cap" in *"dies on"*|*survived*) crash_ok=0 ;; *"FAIL: mutant 'crash-control' crashed ("*) crashed=$((crashed + 1)) ;; esac
done
[ "$crash_ok" = 1 ] && [ "$crashed" = 2 ] && ok "crash control (#360): mutate() reports a crashing snippet as crashed, never as dies" \
  || bad "crash control (#360): mutate() credited or missed a crashing snippet ($crashed of 2 crashed)"

echo ""
echo "phase-review-snapshot tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
