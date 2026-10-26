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
# #521 round 1: continuation keys under the dash belong to the step, so deleting only the run line would
# reattach them to the previous step. The next line deeper than the dash makes the row `other`.
d=$(proj cont); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n        if: github.event_name == 'push'\n"
run "$d"; expect "a step with a continuation key (if:) is other" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj contenv); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n\n        # why\n        env:\n          A: b\n"
run "$d"; expect "a blank and a comment line before the continuation key are skipped" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj nocont); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n\n  other:\n    steps:\n      - uses: y\n"
run "$d"; expect "a following dedented job does not disqualify the step" "step" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
# The sibling must sit in the same steps: block, not anywhere in the file.
d=$(proj onpush); wf "$d" a.yml "name: lock\non:\n  push:\n    branches:\n      - main\njobs:\n  lock:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "a '- main' under on.push.branches is not a sibling step" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj otherjob); wf "$d" a.yml "${HEAD}      - run: bash scripts/test-template-lockstep.sh\n  second:\n    steps:\n      - uses: y\n"
run "$d"; expect "a step in another job is not a sibling" "other" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj flush); wf "$d" a.yml "name: lock\njobs:\n  lock:\n    steps:\n    - uses: x\n    - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "steps: with items at the key's own indent still finds its sibling" "step" "$(printf '%s\n' "$out" | head -n 1 | cut -f5)"
d=$(proj twin); wf "$d" a.yml "${HEAD}      - run: bash scripts/test-template-lockstep.sh\n      - run: bash scripts/test-template-lockstep.sh\n"
run "$d"; expect "two retired steps alone in a job: the first is other (not each other's sibling)" "other" "$(printf '%s\n' "$out" | sed -n 1p | cut -f5)"
expect "and the second is other too" "other" "$(printf '%s\n' "$out" | sed -n 2p | cut -f5)"
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
# A symlinked workflow location is only worth a not-scanned row when a retired file exists to be run by it.
d="$T/slclean"; mkdir -p "$d/.github/workflows" "$d/.forgejo"; ln -s ../.github/workflows "$d/.forgejo/workflows"
run "$d"; expect "symlinked workflow dir, no retired file: clean, exit 0" "summary${TAB}0${TAB}0|0" "$out|$rc"
d=$(proj slfound); mkdir -p "$d/.forgejo"; ln -s ../.github/workflows "$d/.forgejo/workflows"
run "$d"; expect "symlinked workflow dir with a retired file present: reported" "not-scanned${TAB}.forgejo/workflows${TAB}symlink" "$(printf '%s\n' "$out" | grep '^not-scanned')"
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
# #540: the old assertion pinned the bug (a Makefile and package.json caller read as no caller at all).
run "$d"; expect "a Makefile and a package.json caller are reported as caller-unscanned rows" "retired${TAB}$P${TAB}-${TAB}-${TAB}-
caller-unscanned${TAB}$P${TAB}package.json${TAB}1
caller-unscanned${TAB}$P${TAB}Makefile${TAB}2
summary${TAB}1${TAB}0" "$out"

echo "== callers outside a workflow (#540) =="
# M <file> <line>: the refusal line for one caller. The retired path is $P in every case.
M() { printf 'not removed: %s:%s names %s outside a workflow; delete it by hand, then remove %s' "$1" "$2" "$P" "$P"; }
# refused <desc> <project> <file:line>...: removal refuses with exactly those lines, exit 1, tree and script untouched.
refused() {
  local desc="$1" d="$2" exp="" a before; shift 2
  for a in "$@"; do exp="${exp:+$exp$'\n'}$(M "${a%:*}" "${a##*:}")"; done
  before=$(sum "$d"); run "$d" --remove "$P"
  expect "$desc: refusal on stderr" "$exp" "$err"
  expect "$desc: exit 1" 1 "$rc"
  [ "$before" = "$(sum "$d")" ] && ok "$desc: the tree is byte for byte unchanged" || bad "$desc: the refusal changed the tree"
  [ -f "$d/$P" ] && ok "$desc: the script is kept" || bad "$desc: the script was removed"
}
row() { printf 'caller-unscanned\t%s\t%s\t%s' "$P" "$1" "$2"; }
callers() { printf '%s\n' "$out" | grep '^caller-unscanned' | cat; }

d=$(proj npm); printf '{\n  "scripts": {\n    "guard": "bash scripts/check-template-lockstep.sh && bash scripts/test-template-lockstep.sh"\n  }\n}\n' > "$d/package.json"
before=$(sum "$d"); run "$d"
expect "package.json: scan prints the retired row, the caller row and the summary, exit 1" "retired${TAB}$P${TAB}-${TAB}-${TAB}-
$(row package.json 3)
summary${TAB}1${TAB}0|1" "$out|$rc"
[ "$before" = "$(sum "$d")" ] && ok "package.json: the scan is read only" || bad "package.json: the scan changed the tree"
refused "package.json" "$d" package.json:3

d=$(proj mkf); printf 'guard:\n\tbash scripts/test-template-lockstep.sh\n' > "$d/Makefile"
run "$d"; expect "Makefile: caller row on line 2" "$(row Makefile 2)" "$(callers)"
refused "Makefile" "$d" Makefile:2
for name in makefile GNUmakefile justfile Justfile .justfile; do
  d=$(proj "k$name"); printf 'guard:\n    bash scripts/test-template-lockstep.sh\n' > "$d/$name"
  run "$d"; expect "$name: caller row on line 2" "$(row "$name" 2)" "$(callers)"
  refused "$name" "$d" "$name:2"
done
d=$(proj gh); mkdir -p "$d/.githooks"; printf '#!/bin/sh\nbash scripts/test-template-lockstep.sh\n' > "$d/.githooks/pre-commit"
run "$d"; expect ".githooks/pre-commit: caller row on line 2" "$(row .githooks/pre-commit 2)" "$(callers)"
refused ".githooks" "$d" .githooks/pre-commit:2
d=$(proj hu); mkdir -p "$d/.husky/_"; printf '#!/usr/bin/env sh\n. "$(dirname -- "$0")/_/husky.sh"\nbash scripts/test-template-lockstep.sh\n' > "$d/.husky/pre-push"; printf 'echo scripts/test-template-lockstep.sh\n' > "$d/.husky/_/husky.sh"
run "$d"; expect ".husky: exactly one caller row, .husky/_ is not scanned" "$(row .husky/pre-push 3)" "$(callers)"
refused ".husky" "$d" .husky/pre-push:3

# #564: a hook still wired in .claude/settings.json (or settings.local.json) is a caller too, so a removal
# of its file refuses until `hook-unwire.sh` has run. The rules file lists the hook path for this case only.
HP=.claude/hooks/block-dashes.py
HRULES="$T/hrules.tsv"; printf '%s\t564\t2026-10-26\tnote\n' "$HP" > "$HRULES"
hproj() { local d="$T/$1"; mkdir -p "$d/.claude/hooks"; echo x > "$d/$HP"; echo "$d"; }
hrun() { local d="$1"; shift; out=$(bash "$SCRIPT" --project "$d" --rules "$HRULES" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
d=$(hproj hs); printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"python3","args":["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dashes.py"]}]}]}}\n' > "$d/.claude/settings.json"
hrun "$d"; expect "settings.json: a wired hook is a caller row, line 1" "caller-unscanned${TAB}$HP${TAB}.claude/settings.json${TAB}1" "$(printf '%s\n' "$out" | grep '^caller-unscanned')"
hrun "$d" --remove "$HP"; expect "settings.json: the removal refuses and names the file and line" "1|not removed: .claude/settings.json:1 names $HP outside a workflow; delete it by hand, then remove $HP" "$rc|$(printf '%s' "$err" | head -n 1)"
[ -f "$d/$HP" ] && ok "settings.json: the hook file is kept" || bad "settings.json: the hook file was removed"
d=$(hproj hl); printf '{\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "python3 .claude/hooks/block-dashes.py"}]}]}\n}\n' > "$d/.claude/settings.local.json"
hrun "$d"; expect "settings.local.json is a caller too" "caller-unscanned${TAB}$HP${TAB}.claude/settings.local.json${TAB}2" "$(printf '%s\n' "$out" | grep '^caller-unscanned')"
hrun "$d" --remove "$HP"; expect "settings.local.json: the removal refuses" 1 "$rc"
d=$(hproj hn); printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"python3 .claude/hooks/my-block-dashes.py"}]}]}}\n' > "$d/.claude/settings.json"
hrun "$d" --remove "$HP"; expect "an unwired hook (only a longer name remains) is removed" "removed $HP|0" "$out|$rc"
d=$(hproj hu); printf '{"permissions":{}}\n' > "$d/.claude/settings.json"; hrun "$d" --remove "$HP"; expect "a settings.json with no hooks does not block" "removed $HP|0" "$out|$rc"
d=$(hproj hk); mkdir -p "$T/realset"; echo '{}' > "$T/realset/s.json"; ln -s "$T/realset/s.json" "$d/.claude/settings.json"
hrun "$d" --remove "$HP"; expect "a symlinked settings.json blocks the removal as not scanned" 1 "$rc"

d=$(proj base); printf 'guard:\n\tcd scripts && ./test-template-lockstep.sh\n' > "$d/Makefile"
run "$d"; expect "a basename-only mention is a caller" "$(row Makefile 2)" "$(callers)"
refused "basename-only" "$d" Makefile:2

d=$(proj both); wf "$d" a.yml "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n"; printf '{\n  "scripts": {\n    "g": "bash scripts/test-template-lockstep.sh"\n  }\n}\n' > "$d/package.json"
run "$d"; expect "a workflow step and a package.json caller are both listed" "retired${TAB}$P${TAB}.github/workflows/a.yml${TAB}7${TAB}step
$(row package.json 3)" "$(printf '%s\n' "$out" | grep -v '^summary')"
refused "workflow step plus package.json" "$d" package.json:3
expect "the workflow step survives the refusal" "$(printf '%b' "${HEAD}      - uses: x\n      - run: bash scripts/test-template-lockstep.sh\n")" "$(cat "$d/.github/workflows/a.yml")"

d=$(proj nomatch); printf '# bash scripts/test-template-lockstep.sh\n\t# scripts/test-template-lockstep.sh\nall:\n\ttrue\n' > "$d/Makefile"
printf '{\n  "a": "scripts/test-template-lockstep.sh.bak",\n  "b": "scripts/my-test-template-lockstep.sh"\n}\n' > "$d/package.json"
run "$d" --remove "$P"; expect "comments (tab-led included) and longer names are no caller: removed" "removed $P|0" "$out|$rc"
d=$(proj nearreal); printf 'scripts/test-template-lockstep.sh.bak\nbash scripts/test-template-lockstep.sh\n' > "$d/Makefile"
refused "a real caller beside a false match" "$d" Makefile:2

d=$(proj two2); mkdir -p "$d/.husky"; printf 'x:\n\tbash scripts/test-template-lockstep.sh\n' > "$d/Makefile"; printf '#!/bin/sh\n\nbash scripts/test-template-lockstep.sh\n' > "$d/.husky/pre-push"
refused "two blockers are both listed, fixed names first" "$d" Makefile:2 .husky/pre-push:3

d=$(proj slnpm); echo '{}' > "$T/realpkg"; ln -s "$T/realpkg" "$d/package.json"
run "$d"; expect "a symlinked package.json is not-scanned, never followed, no caller row, exit 1" "not-scanned${TAB}package.json${TAB}symlink|0|1" "$(printf '%s\n' "$out" | grep '^not-scanned')|$(callers | grep -c .)|$rc"
run "$d" --remove "$P"
expect "and it blocks the removal" "not removed: package.json was not scanned (symlink); check it for a step that runs $P, then remove it by hand|1" "$err|$rc"
d=$(proj slhooks); mkdir -p "$T/elsehooks"; printf 'bash scripts/test-template-lockstep.sh\n' > "$T/elsehooks/pre-commit"; ln -s "$T/elsehooks" "$d/.githooks"
run "$d"; expect "a symlinked .githooks directory is not-scanned, once" "not-scanned${TAB}.githooks${TAB}symlink" "$(printf '%s\n' "$out" | grep '^not-scanned')"
run "$d" --remove "$P"; expect "and it blocks the removal" 1 "$rc"
d=$(proj slhook); mkdir -p "$d/.githooks"; ln -s "$T/elsehooks/pre-commit" "$d/.githooks/pre-commit"
run "$d"; expect "a symlinked hook file is not-scanned" "not-scanned${TAB}.githooks/pre-commit${TAB}symlink" "$(printf '%s\n' "$out" | grep '^not-scanned')"
d=$(proj nonce); mkdir -p "$d/.githooks"; printf 'x:\n\tbash scripts/test-template-lockstep.sh\n' > "$d/Makefile"; ln -s "$T/realpkg" "$d/package.json"
run "$d"; expect "one not-scanned row per blocked candidate, not per listed path" "summary${TAB}1${TAB}1" "$(printf '%s\n' "$out" | tail -n 1)"
if [ "$(id -u)" -ne 0 ]; then
  d=$(proj unr); printf 'bash scripts/test-template-lockstep.sh\n' > "$d/Makefile"; chmod 000 "$d/Makefile"
  run "$d"; expect "an unreadable Makefile is not-scanned (unreadable)" "not-scanned${TAB}Makefile${TAB}unreadable" "$(printf '%s\n' "$out" | grep '^not-scanned')"
  run "$d" --remove "$P"; expect "and it blocks the removal" "not removed: Makefile was not scanned (unreadable); check it for a step that runs $P, then remove it by hand|1" "$err|$rc"
  chmod 644 "$d/Makefile"
else
  ok "unreadable candidate: skipped as root"; ok "unreadable candidate refusal: skipped as root"
fi
d=$(proj crlf); printf '{\r\n  "g": "bash scripts/test-template-lockstep.sh"\r\n}\r\n' > "$d/package.json"
run "$d"; expect "CRLF line endings still match" "$(row package.json 2)" "$(callers)"
d=$(proj nonl); mkdir -p "$d/.githooks"; printf '#!/bin/sh\nbash scripts/test-template-lockstep.sh' > "$d/.githooks/pre-commit"
run "$d"; expect "a hook with no trailing newline is still scanned" "$(row .githooks/pre-commit 2)" "$(callers)"
d=$(proj dirpkg); mkdir -p "$d/package.json"; printf 'bash scripts/test-template-lockstep.sh\n' > "$d/package.json/scripts"
run "$d"; expect "a directory named package.json is not read: no row" "summary${TAB}1${TAB}0|1" "$(printf '%s\n' "$out" | tail -n 1)|$rc"
d=$(proj clean2); printf 'all:\n\ttrue\n' > "$d/Makefile"; echo '{}' > "$d/package.json"
run "$d" --remove "$P"; expect "a project whose build files name other scripts removes as before" "removed $P|0" "$out|$rc"
d=$(proj nocand); run "$d" --remove "$P"; expect "no candidate file at all: the unchanged message" "removed $P|0" "$out|$rc"

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
