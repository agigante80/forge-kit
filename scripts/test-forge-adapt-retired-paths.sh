#!/usr/bin/env bash
# Contract test for plugins/forge-kit-adapt/skills/adapt/assets/retired-paths.sh (#521): the scan for
# a file the kit retired, and the one-path removal with its workflow step.
#
# Every fixture is a throwaway directory and a throwaway --rules file, so no case depends on what the
# shipped data file lists; ONE case reads the shipped retired-paths.tsv. RETIRED_PATHS overrides the
# script under test, so a mutant can run on a cp copy.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ASSET="$ROOT/plugins/forge-kit-adapt/skills/adapt/assets"
SCRIPT="${RETIRED_PATHS:-$ASSET/retired-paths.sh}"
[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=scripts/test-template-lockstep.sh
TAB=$'\t'
RULES="$T/rules.tsv"
printf '# header\n%s\t506\t2026-10-14\tnote\n' "$P" > "$RULES"

# proj <name>: a fresh project directory holding the retired file; echoes its path.
proj() { local d="$T/$1"; mkdir -p "$d/scripts" "$d/.github/workflows"; echo '#!/bin/sh' > "$d/$P"; echo "$d"; }
# wf <project> <file> <content, printf %b>
wf() { printf '%b' "$3" > "$1/.github/workflows/$2"; }
out=""; err=""; rc=""
run() { local d="$1"; shift; out=$(bash "$SCRIPT" --project "$d" --rules "$RULES" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
sum() { (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | xargs -r cksum | cksum) 2>/dev/null; }

HEAD='name: lock\njobs:\n  lock:\n    runs-on: ubuntu-latest\n    steps:\n'
LIVE='      - run: bash scripts/check-template-lockstep.sh\n'

echo "== the real pre-#506 shape: two steps, one live, one retired =="
d=$(proj real); wf "$d" template-lockstep.yml "${HEAD}      - uses: actions/checkout@v4\n${LIVE}      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"
expect "scan: one row, the step on line 8" "retired${TAB}$P${TAB}.github/workflows/template-lockstep.yml${TAB}8${TAB}step
summary${TAB}1${TAB}0" "$out"
expect "scan: exit 1" 1 "$rc"
before=$(sum "$d"); run "$d"; [ "$before" = "$(sum "$d")" ] && ok "scan is read only (checksum of the tree unchanged)" || bad "scan changed the tree"
run "$d" --remove "$P"
expect "remove: message" "removed $P and its step in .github/workflows/template-lockstep.yml" "$out"
expect "remove: exit 0" 0 "$rc"
expect "remove: the workflow keeps every other line, the live step included" "$(printf '%b' "${HEAD}      - uses: actions/checkout@v4\n${LIVE}")" "$(cat "$d/.github/workflows/template-lockstep.yml")"
[ ! -e "$d/$P" ] && ok "remove: the script is gone" || bad "remove: the script is still there"
run "$d"; expect "after removal: nothing found, exit 0" "summary${TAB}0${TAB}0|0" "$out|$rc"

echo "== the live guard is never matched =="
d=$(proj live); echo '#!/bin/sh' > "$d/scripts/check-template-lockstep.sh"; wf "$d" a.yml "${HEAD}${LIVE}"
run "$d"; expect "check-template-lockstep.sh is not the retired path" "summary${TAB}1${TAB}0" "$(printf '%s\n' "$out" | tail -n 1)"
expect "no caller row names the live guard" "retired${TAB}$P${TAB}-${TAB}-${TAB}-" "$(printf '%s\n' "$out" | head -n 1)"

echo "== forms =="
d=$(proj rel); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash ./scripts/test-template-lockstep.sh\n"
run "$d"; expect "bash ./scripts/... is a step" "step" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj sh); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: sh scripts/test-template-lockstep.sh\n"
run "$d"; expect "sh scripts/... is a step" "step" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj direct); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: ./scripts/test-template-lockstep.sh\n"
run "$d"; expect "running it directly is other" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj blk); wf "$d" a.yml "${HEAD}      - name: t\n        run: |\n          bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "a run: | block line is other" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj chain); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh && echo done\n"
run "$d"; expect "a chained command is other" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj quoted); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: 'bash scripts/test-template-lockstep.sh'\n"
run "$d"; expect "a quoted command is other" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj only); wf "$d" a.yml "${HEAD}      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "the only step of a job is other (deleting it would empty the job)" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj cmt); wf "$d" a.yml "${HEAD}      # - run: bash scripts/test-template-lockstep.sh\n      - uses: x\n"
run "$d"; expect "a commented line is not a caller" "retired${TAB}$P${TAB}-${TAB}-${TAB}-" "$(printf '%s\n' "$out" | head -n 1)"
d=$(proj two); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n"; wf "$d" b.yaml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "one row per (path, caller): two files, two rows plus summary" 3 "$(printf '%s\n' "$out" | grep -c .)"

echo "== token boundary =="
d=$(proj sub); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh.bak\n      - run: bash scripts/test-template-lockstep.sh-old\n      - run: bash scripts/my-test-template-lockstep.sh\n"
run "$d"; expect "longer file names are not the path" "retired${TAB}$P${TAB}-${TAB}-${TAB}-" "$(printf '%s\n' "$out" | head -n 1)"

echo "== refusals write nothing =="
d=$(proj multi); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n      - name: t\n        run: |\n          ./scripts/test-template-lockstep.sh\n"
before=$(sum "$d"); run "$d" --remove "$P"
expect "an other row refuses with exit 1" 1 "$rc"
expect "the refusal message is exact" "not removed: .github/workflows/a.yml:10 is not a one-line run step; delete it by hand, then remove $P" "$err"
[ "$before" = "$(sum "$d")" ] && ok "refusal: the tree is byte for byte unchanged (the step stays too)" || bad "refusal changed the tree"
[ -f "$d/$P" ] && ok "refusal: the script is kept" || bad "refusal removed the script"
d=$(proj slwf); mkdir -p "$T/elsewhere"; rm -rf "$d/.github/workflows"; ln -s "$T/elsewhere" "$d/.github/workflows"
run "$d"; expect "a symlinked workflow directory is reported not-scanned" "not-scanned${TAB}.github/workflows${TAB}symlink" "$(printf '%s\n' "$out" | grep '^not-scanned')"
run "$d" --remove "$P"; expect "and it blocks a removal" 1 "$rc"; [ -f "$d/$P" ] && ok "blocked removal keeps the script" || bad "removed despite a symlinked workflow dir"
d=$(proj slpath); rm "$d/$P"; echo real > "$T/realfile"; ln -s "$T/realfile" "$d/$P"
run "$d"; expect "a symlinked retired path is not-scanned, never followed" "not-scanned${TAB}$P${TAB}symlink" "$(printf '%s\n' "$out" | grep '^not-scanned')"
expect "and counts as incomplete: exit 3" 3 "$rc"
run "$d" --remove "$P"; expect "removing a symlink is refused" 1 "$rc"; [ -L "$d/$P" ] && ok "the symlink is untouched" || bad "the symlink was removed"

echo "== no caller =="
d=$(proj nocall); wf "$d" a.yml "${HEAD}      - uses: x\n"
run "$d"; expect "no workflow names it: caller - (not proof nothing runs it)" "retired${TAB}$P${TAB}-${TAB}-${TAB}-
summary${TAB}1${TAB}0" "$out"
run "$d" --remove "$P"; expect "caller -: the script alone goes" "removed $P" "$out"
d=$(proj mk); printf 'test:\n\tbash scripts/test-template-lockstep.sh\n' > "$d/Makefile"; printf '{"scripts":{"t":"bash scripts/test-template-lockstep.sh"}}\n' > "$d/package.json"
run "$d"; expect "a Makefile and package.json caller are not scanned" "retired${TAB}$P${TAB}-${TAB}-${TAB}-" "$(printf '%s\n' "$out" | head -n 1)"

echo "== other workflow directories =="
d=$(proj fj); mkdir -p "$d/.forgejo/workflows" "$d/.gitea/workflows"
printf '%b' "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n" > "$d/.forgejo/workflows/f.yml"
printf '%b' "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n" > "$d/.gitea/workflows/g.yml"
run "$d"; expect "forgejo and gitea workflow files are scanned" ".forgejo/workflows/f.yml .gitea/workflows/g.yml" "$(printf '%s\n' "$out" | grep '^retired' | cut -f3 | paste -sd' ')"
run "$d" --remove "$P"; expect "a removal edits every step file" "removed $P and its step in .forgejo/workflows/f.yml, .gitea/workflows/g.yml" "$out"

echo "== the kit checkout is exempt =="
d=$(proj kit); mkdir -p "$d/plugins/forge-kit-adapt/.claude-plugin"; echo '{}' > "$d/plugins/forge-kit-adapt/.claude-plugin/plugin.json"; wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "scan: exempt, exit 0" "exempt${TAB}kit checkout
summary${TAB}0${TAB}0|0" "$out|$rc"
before=$(sum "$d"); run "$d" --remove "$P"; expect "remove: refused" 1 "$rc"
[ "$before" = "$(sum "$d")" ] && ok "kit checkout untouched by --remove" || bad "kit checkout changed"

echo "== nothing found =="
d="$T/empty"; mkdir -p "$d"; run "$d"; expect "no listed path: summary only, exit 0" "summary${TAB}0${TAB}0|0" "$out|$rc"

echo "== usage and the data file =="
run "$T/nope"; expect "--project not a directory: exit 2" 2 "$rc"; expect "nothing on stdout" "" "$out"
out=$(bash "$SCRIPT" --project "$T/empty" --rules "$T/missing.tsv" 2>&1); expect "--rules unreadable: exit 2" 2 "$?"
out=$(bash "$SCRIPT" --bogus 2>&1); expect "unknown flag: exit 2" 2 "$?"
out=$(bash "$SCRIPT" --project 2>&1); expect "flag without a value: exit 2" 2 "$?"
for bad_path in '/etc/passwd' '../x' 'a/../b' '-rf' 'a b' 'a//b'; do
  printf '%s\t1\t2026-01-01\tn\n' "$bad_path" > "$T/badrules.tsv"
  out=$(bash "$SCRIPT" --project "$T/empty" --rules "$T/badrules.tsv" 2>&1); expect "an unsafe rules path '$bad_path' is refused: exit 2" 2 "$?"
done
printf 'no-tab-here\n' > "$T/badrules.tsv"; out=$(bash "$SCRIPT" --project "$T/empty" --rules "$T/badrules.tsv" 2>&1); expect "a rules row without a tab: exit 2" 2 "$?"
d=$(proj unlisted); echo x > "$d/scripts/other.sh"; run "$d" --remove scripts/other.sh; expect "--remove of an unlisted path: exit 2" 2 "$rc"
[ -f "$d/scripts/other.sh" ] && ok "and the file is kept" || bad "an unlisted file was removed"
d="$T/absent"; mkdir -p "$d"; run "$d" --remove "$P"; expect "--remove of a listed path that is absent: exit 2" 2 "$rc"

echo "== the shipped data file =="
tsv="$ASSET/retired-paths.tsv"
[ -f "$tsv" ] && ok "retired-paths.tsv ships beside the script" || bad "retired-paths.tsv is missing"
d=$(proj shipped); wf "$d" template-lockstep.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n"
out=$(bash "$SCRIPT" --project "$d" --rules "$tsv" 2>&1); rc=$?
expect "the shipped list names scripts/test-template-lockstep.sh" "retired${TAB}$P${TAB}.github/workflows/template-lockstep.yml${TAB}7${TAB}step
summary${TAB}1${TAB}0|1" "$out|$rc"
if [ -z "${RETIRED_PATHS:-}" ]; then
  out=$(bash "$SCRIPT" --project "$d" 2>&1); expect "the default rules file is the one beside the script" "retired" "$(printf '%s\n' "$out" | head -n 1 | cut -f1)"
fi
grep -q '^# retired-paths-version: [0-9][0-9]*$' "$SCRIPT" && ok "carries its version marker" || bad "no retired-paths-version marker"

echo ""
echo "forge-adapt retired-paths tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
