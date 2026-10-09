#!/usr/bin/env bash
# Contract test for context-budget/assets/context-budget.sh (#297).
#
# The script reports how many characters a project's next session loads before the first prompt.
# Every case runs it as a subprocess over a throwaway tree with a fixture HOME, so the real
# auto-memory never leaks in. Fixtures carry MULTIBYTE text (an e-acute, a three-byte CJK character,
# a four-byte emoji), because a byte count passes every ASCII fixture and is wrong on the first
# multibyte CLAUDE.md: #403's class, which the leak guard fixed one site at a time four times.
# STREAMS ARE THE CONTRACT: the figures on stdout, WARN/FAIL and refusals on stderr, the exit code.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-devops/skills/context-budget/assets/context-budget.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { if grep -qF -- "$2" <<< "$3"; then ok "$1"; else bad "$1 (no '$2' in output)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$3"; then bad "$1 ('$2' present)"; else ok "$1"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(cd -P "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; unset CLAUDE_CONFIG_DIR; mkdir -p "$HOME"
# The fixtures may sit inside this repository's own tmp/; stop git from finding it.
export GIT_CEILING_DIRECTORIES="$T"

E=$(printf '\303\251')          # e-acute, two bytes
CJK=$(printf '\344\270\255')    # three bytes
EMO=$(printf '\360\237\230\200') # four bytes
# rep <char> <n>: n copies of a character, no newline.
rep() { printf '%*s' "$2" '' | sed "s/ /$1/g"; }
# file <path> <n> [char]: a file of exactly n characters, ending in a newline (counted).
file() { mkdir -p "$(dirname "$1")"; { rep "${3:-$E}" $(($2 - 1)); printf '\n'; } > "$1"; }
# slug <abs>: the ASCII fixtures' slug, every non-alphanumeric a dash.
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
memdir() { echo "$HOME/.claude/projects/$(slug "$1")/memory"; }

P=""
fresh() { P="$T/p/$1"; rm -rf "$P"; mkdir -p "$P"; }

out=""; err=""; rc=0
run() { out=$(LC_ALL=${RUN_LC:-C} bash "$SRC" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
total() { sed -n 's/^total: //p' <<< "$out"; }
level() { sed -n 's/^level: //p' <<< "$out"; }

echo "== R1 counts characters over the always-loaded set =="
fresh warn; { rep "$E" 29980; printf '\n@a.md\n'; rep "$E" 12; printf '\n'; } > "$P/CLAUDE.md"; file "$P/a.md" 15000
run "$P"
expect "30,000 + 15,000 e-acute characters total 45000" 45000 "$(total)"
expect "45000 exits 0" 0 "$rc"
has "45000 warns on stderr" "WARN" "$err"
expect "45000 is warn" warn "$(level)"
fresh small; { rep a 9990; printf '\n@a.md\n'; rep a 2; printf '\n'; } > "$P/CLAUDE.md"; file "$P/a.md" 5000
run "$P"
expect "10,000 + 5,000 characters total 15000" 15000 "$(total)"
expect "15000 exits 0" 0 "$rc"
hasnt "15000 prints no WARN" "WARN" "$err"; hasnt "15000 prints no FAIL" "FAIL" "$out$err"
fresh over; { printf '@a.md\n'; rep "$CJK" 49993; printf '\n'; } > "$P/CLAUDE.md"; file "$P/a.md" 35000 "$EMO"
run "$P"
expect "50,000 + 35,000 multibyte characters total 85000" 85000 "$(total)"
expect "85000 exits 1" 1 "$rc"
expect "85000 is FAIL" FAIL "$(level)"
has "FAIL is reported on stderr" "FAIL" "$err"

echo "== levels are at-or-over =="
for pair in 39999:ok:0 40000:warn:0 79999:warn:0 80000:FAIL:1; do
  n=${pair%%:*}; rest=${pair#*:}; l=${rest%%:*}; c=${rest#*:}
  fresh "b$n"; file "$P/CLAUDE.md" "$n"
  run "$P"
  expect "$n characters is $l" "$l" "$(level)"; expect "$n characters exits $c" "$c" "$rc"
done

echo "== the count is the same in every locale, malformed bytes included =="
fresh mixed; { rep "$E" 10; rep "$CJK" 10; rep "$EMO" 10; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; expect "multibyte under C" 31 "$(total)"
UTF=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.utf-?8$' | head -1)
if [ -n "$UTF" ]; then RUN_LC=$UTF run "$P"; RUN_LC=""; expect "multibyte under $UTF" 31 "$(total)"
else ok "(skipped, no UTF-8 locale) multibyte under a UTF-8 locale"; fi
mal() {  # mal <label> <printf-bytes> <expected>
  fresh mal; printf "$2" > "$P/CLAUDE.md"
  run "$P"; expect "$1 under C" "$3" "$(total)"; expect "$1 exits 0" 0 "$rc"
  if [ -n "$UTF" ]; then RUN_LC=$UTF run "$P"; RUN_LC=""; expect "$1 under UTF-8" "$3" "$(total)"; fi
}
A100=$(rep a 100)
mal "stray continuation bytes count 0" "${A100}\200\200\303" 101
mal "a lone pair of continuation bytes" "a\200\200" 1
mal "a lone lead byte at end of file counts 1" "${A100}\303" 101
mal "a truncated three-byte sequence counts its lead" "\342\202" 1
mal "invalid lead bytes count 1 each" "\300\301\365\377" 4

echo "== only existing files outside code spans, fences and comments are imports =="
fresh imp; { printf '@docs/conventions.md here\n'; rep a 19973; printf '\n'; } > "$P/CLAUDE.md"; file "$P/docs/conventions.md" 10000
run "$P"
expect "a prose import is counted" 30000 "$(total)"
has "the import is listed at hop 1" "docs/conventions.md (hop 1)" "$out"
expect "the import count is 1" "imports: 1" "$(grep '^imports:' <<< "$out")"
fresh notimp
{ printf '@actual-app/api\n```\n@docs/x.md\n```\nsee `@docs/x.md` and <!-- @docs/x.md -->\n<!--\n@docs/x.md\n-->\n'; } > "$P/CLAUDE.md"
file "$P/docs/x.md" 500
base=$(LC_ALL=C tr -d '\200-\277' < "$P/CLAUDE.md" | wc -c | tr -d ' ')
run "$P"
expect "a missing target, a fence, a span and comments import nothing" "$base" "$(total)"
expect "the import count is 0" "imports: 0" "$(grep '^imports:' <<< "$out")"
fresh pos; printf 'name@p2.md -@p3.md\n@p1.md\ntext @p4.md\n' > "$P/CLAUDE.md"
for f in p1 p2 p3 p4; do file "$P/$f.md" 100; done
run "$P"
has "an @ at a line start imports" "p1.md (hop 1)" "$out"; has "an @ after a space imports" "p4.md (hop 1)" "$out"
hasnt "name@p2.md does not import" "p2.md" "$out"; hasnt "-@p3.md does not import" "p3.md" "$out"
fresh comment; { printf '<!--\n'; rep x 5990; printf '\n@c.md\n-->\n'; } > "$P/CLAUDE.md"; file "$P/c.md" 100
run "$P"
expect "a block comment is counted raw and its @ is not an import" 6006 "$(total)"
fresh quote; printf '@"q.md" @my\\ file.md\n' > "$P/CLAUDE.md"; file "$P/q.md" 100; file "$P/my file.md" 50
run "$P"
hasnt "a quoted path does not import" "q.md" "$out"; has "an escaped-space path imports" "my file.md (hop 1)" "$out"

echo "== the fixture tree gives the exact set of counted files and hops =="
fresh tree
printf '@a.md\n`@span.md`\n```\n@fence.md\n```\n@"quoted.md"\n@sp\\ ace.md\n@sub/rel.md\n@data.json\n@trail.md.\n' > "$P/CLAUDE.md"
for f in a span fence quoted "sp ace" trail; do file "$P/$f.md" 10; done
file "$P/data.json" 10; mkdir -p "$P/sub"; printf '@near.md\n' > "$P/sub/rel.md"; file "$P/sub/near.md" 10
run "$P"
got=$(grep ' (hop ' <<< "$out" | sed 's/^ *[0-9]*\t//' | sort)
want=$(printf '%s\n' "a.md (hop 1)" "data.json (hop 1)" "sp ace.md (hop 1)" "sub/near.md (hop 2)" "sub/rel.md (hop 1)" | sort)
expect "exactly these files at these hops" "$want" "$got"

echo "== transitive imports: four hops, each file once =="
fresh chain; printf '@a.md\n' > "$P/CLAUDE.md"; printf '@b.md\n' > "$P/a.md"; file "$P/b.md" 20000
run "$P"; has "b.md is counted at hop 2" "b.md (hop 2)" "$out"
fresh five; printf '@h1.md\n' > "$P/CLAUDE.md"
for i in 1 2 3 4; do printf '@h%d.md\n' $((i + 1)) > "$P/h$i.md"; done; file "$P/h5.md" 3000
run "$P"
has "the fourth hop is counted" "h4.md (hop 4)" "$out"; hasnt "the fifth hop is not" "h5.md" "$out"
expect "five hops total 4 chain files" 35 "$(total)"
fresh cycle; printf '@a.md\n' > "$P/CLAUDE.md"; printf '@CLAUDE.md @b.md\n' > "$P/a.md"; printf '@a.md\n' > "$P/b.md"
run "$P"
expect "a cycle terminates and counts each file once" 29 "$(total)"; expect "two imports" "imports: 2" "$(grep '^imports:' <<< "$out")"

echo "== out-of-tree and broken targets end cleanly =="
fresh escape; mkdir -p "$T/outside"; file "$T/outside/o.md" 777
ln -s "$P/nowhere.md" "$P/dangling.md"; ln -s "$P/loop1.md" "$P/loop2.md"; ln -s "$P/loop2.md" "$P/loop1.md"
printf 'SENTINEL_TOKEN\n@missing.md @dangling.md @loop1.md @../../outside/o.md @%s @~/x.md\n' "$T/outside/o.md" > "$P/CLAUDE.md"
run "$P"
expect "nothing outside the tree or broken is counted" "imports: 0" "$(grep '^imports:' <<< "$out")"
expect "and the run exits 0" 0 "$rc"
hasnt "no file text in the output" "SENTINEL_TOKEN" "$out$err"
fresh linkin; file "$P/real.md" 40; ln -s "$P/real.md" "$P/alias.md"; printf '@alias.md @real.md\n' > "$P/CLAUDE.md"
run "$P"; expect "a symlink inside the tree counts its target once" "imports: 1" "$(grep '^imports:' <<< "$out")"

echo "== the auto-memory MEMORY.md counts its loaded portion =="
fresh mem; file "$P/CLAUDE.md" 10000; M=$(memdir "$P"); mkdir -p "$M"
for i in $(seq 1 300); do rep b 39; printf '\n'; done > "$M/MEMORY.md"
run "$P"
expect "the first 200 lines are counted" 18000 "$(total)"
has "the loaded portion is its own line item" "8000	MEMORY.md, loaded portion" "$out"
has "the whole file is a separate non-counted line" "MEMORY.md whole file: 12000 (not counted)" "$out"
{ rep "$E" 12999; printf '\n'; rep "$E" 100; printf '\n'; } > "$M/MEMORY.md"
run "$P"
expect "over 25,000 bytes in two lines is cut at a character boundary" 22500 "$(total)"
printf 'a' > "$M/MEMORY.md"; rep "$E" 13000 >> "$M/MEMORY.md"
run "$P"
expect "a cut inside a character drops that character" 22500 "$(total)"
rm -rf "$HOME/.claude"
run "$P"
expect "no auto-memory directory leaves the total unchanged" 10000 "$(total)"
expect "and exits 0" 0 "$rc"; expect "with an empty stderr" "" "$err"
fresh cfg; file "$P/CLAUDE.md" 100; C="$T/cfg"; mkdir -p "$C/projects/$(slug "$P")/memory"; file "$C/projects/$(slug "$P")/memory/MEMORY.md" 50
out=$(CLAUDE_CONFIG_DIR="$C" bash "$SRC" "$P" 2>/dev/null)
expect "CLAUDE_CONFIG_DIR is read when set" 150 "$(total)"
run "$P"; expect "and HOME/.claude when unset" 100 "$(total)"

echo "== one input decides the auto-memory directory in both modes =="
fresh gitrepo; git init --quiet "$P"; mkdir -p "$P/pkg"; file "$P/pkg/CLAUDE.md" 100
M=$(memdir "$P"); mkdir -p "$M"; file "$M/MEMORY.md" 70
run "$P/pkg"; expect "a subdirectory of a git repo reads the git root's MEMORY.md" 170 "$(total)"
run --sweep "$P"; has "and so does its sweep row" "170	ok	$P/pkg" "$out"
fresh nogit; mkdir -p "$P/pkg"; file "$P/pkg/CLAUDE.md" 100; M=$(memdir "$P/pkg"); mkdir -p "$M"; file "$M/MEMORY.md" 30
run "$P/pkg"; expect "outside a git work tree, the directory's own slug" 130 "$(total)"
run --sweep "$P"; has "in both modes" "130	ok	$P/pkg" "$out"
fresh slug1; d="$P/sp ace${E}.x"; mkdir -p "$d"; file "$d/CLAUDE.md" 10
s="$(slug "$P")-sp-ace--x"; mkdir -p "$HOME/.claude/projects/$s/memory"; file "$HOME/.claude/projects/$s/memory/MEMORY.md" 5
run "$d"; expect "a space and the dot are one dash each, the e-acute one dash (observed on 2.1.295)" 15 "$(total)"
run --sweep "$P"; has "and a sweep derives the same literal slug" "15	ok	$d" "$out"
fresh slug2; d="$P/a${EMO}b"; mkdir -p "$d"; file "$d/CLAUDE.md" 10
s="$(slug "$P")-a--b"; mkdir -p "$HOME/.claude/projects/$s/memory"; file "$HOME/.claude/projects/$s/memory/MEMORY.md" 5
run "$d"; expect "a four-byte character is two dashes, as UTF-16 counts it" 15 "$(total)"
fresh long; d="$P/$(rep d 200)"; mkdir -p "$d"; file "$d/CLAUDE.md" 10
run "$d"; has "a slug over 200 characters is reported, not guessed" "MEMORY.md not read" "$out"

echo "== the marker raises the fail level =="
fresh mark; { printf '<!-- context-budget: 90000 reason: SENTINEL_REASON -->\n'; rep "$E" 84950; printf '\n'; } > "$P/CLAUDE.md"
run "$P"
expect "a valid marker passes an 85,000 project" 0 "$rc"
has "the raised level is printed" "fail level: 90000 (fail level raised by a context-budget marker)" "$out"
hasnt "the reason is never printed" "SENTINEL_REASON" "$out$err"
run --sweep "$T/p/mark"
has "a sweep row shows the raised level" "fail level raised to 90000" "$out"
hasnt "nor in a sweep" "SENTINEL_REASON" "$out$err"; expect "the sweep exits 0" 0 "$rc"
refuse() {  # refuse <label> <marker text> <rule fragment>
  fresh refuse; { printf '%s\n' "$2"; rep a 85000; printf '\n'; } > "$P/CLAUDE.md"
  run "$P"
  expect "$1 is refused with exit 2" 2 "$rc"; has "$1 names the rule" "$3" "$err"
  expect "$1 leaves the default level" "fail level: 80000" "$(grep '^fail level' <<< "$out")"
}
refuse "no number" '<!-- context-budget: reason: x -->' "missing or not a whole number"
refuse "a non-numeric N" '<!-- context-budget: lots reason: x -->' "missing or not a whole number"
refuse "N of 80000" '<!-- context-budget: 80000 reason: x -->' "above 80000"
refuse "N of 0" '<!-- context-budget: 0 reason: x -->' "above 80000"
refuse "no reason" '<!-- context-budget: 90000 -->' "reason is missing"
refuse "an empty reason" '<!-- context-budget: 90000 reason:   -->' "reason is empty"
refuse "two markers" "$(printf '<!-- context-budget: 90000 reason: x -->\n<!-- context-budget: 95000 reason: y -->')" "more than one"
fresh multi; { printf '<!--\ncontext-budget: 90000 reason: SENTINEL_ML\n-->\n'; rep a 85000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; expect "a marker on its own lines inside a block comment is read" 0 "$rc"
hasnt "and its reason is not printed" "SENTINEL_ML" "$out$err"
fresh multi2; { printf '<!-- context-budget: 90000\nreason: split\n-->\n'; rep a 85000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; expect "a marker whose reason is on the next line is read" 0 "$rc"
fresh fenced; { printf '```\n<!-- context-budget: 90000 reason: x -->\n```\n'; rep a 85000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; expect "a marker inside a fence is ignored, so the default level fails" 1 "$rc"
fresh sweepbad; { printf '<!-- context-budget: 9 reason: x -->\n'; rep a 100; printf '\n'; } > "$P/CLAUDE.md"
run --sweep "$P"; has "a sweep shows a refused marker" "marker refused" "$out"; expect "and still exits 0" 0 "$rc"

echo "== the sweep reports and never reads out =="
R="$T/root"; rm -rf "$R"; mkdir -p "$R/big" "$R/mid" "$R/small" "$R/none" "$R/nested/sub" "$R/x/node_modules/y" "$R/x/.git/z"
for spec in big:90000 mid:45000 small:10000; do
  d=${spec%%:*}; n=${spec#*:}; { printf 'SENTINEL_BODY\n'; rep "$E" $((n - 15)); printf '\n'; } > "$R/$d/CLAUDE.md"
done
file "$R/none/README.md" 10; file "$R/nested/CLAUDE.md" 5; file "$R/nested/sub/CLAUDE.md" 5
file "$R/x/node_modules/y/CLAUDE.md" 5; file "$R/x/.git/z/CLAUDE.md" 5
before=$(cd "$R" && find . -exec ls -ld --time-style=+%s {} + 2>/dev/null | md5sum)
run --sweep "$R"
expect "rows in descending total" "$(printf '%s\n' 90000 45000 10000 5)" "$(grep -E '^[0-9]' <<< "$out" | cut -f1)"
has "levels per row" "90000	FAIL	$R/big" "$out"
hasnt "a directory with no CLAUDE.md has no row" "$R/none" "$out"
expect "a CLAUDE.md directory's subtree is not searched" 1 "$(grep -c "$R/nested" <<< "$out")"
hasnt "node_modules is skipped" "node_modules" "$out"; hasnt ".git is skipped" "/.git" "$out"
expect "the sweep exits 0 with a FAIL row" 0 "$rc"
hasnt "no file text in a sweep" "SENTINEL_BODY" "$out$err"
after=$(cd "$R" && find . -exec ls -ld --time-style=+%s {} + 2>/dev/null | md5sum)
expect "nothing under the root is modified" "$before" "$after"
expect "no stray file appears" "" "$(find "$R" -newer "$T/err" -type f 2>/dev/null)"
ln -s "$R" "$T/rootlink"; run --sweep "$T/rootlink"
expect "a symlinked root is swept like the real one" 4 "$(grep -cE '^[0-9]' <<< "$out")"
mkdir -p "$T/cdp/root"; (cd "$T" && CDPATH="$T/cdp" run --sweep root; [ "$(grep -cE "^[0-9]" <<< "$out")" = 4 ] && echo yes > "$T/cdpok"); [ -f "$T/cdpok" ] && ok "an exported CDPATH does not redirect a relative root" || bad "an exported CDPATH does not redirect a relative root"
R2="$T/tie"; mkdir -p "$R2/b" "$R2/a"; file "$R2/b/CLAUDE.md" 10; file "$R2/a/CLAUDE.md" 10
run --sweep "$R2"; expect "equal totals run in path order" "$(printf '%s\n' "$R2/a" "$R2/b")" "$(cut -f3 <<< "$out")"

echo "== sections are report-only move candidates =="
fresh sec; { printf '# T\n## SENTINEL_HEAD big\n'; rep "$E" 8999; printf '\n'; printf '## small\n'; rep a 91; printf '\n'; } > "$P/CLAUDE.md"
run "$P"
expect "exactly one move candidate" 1 "$(grep -c '^move candidate' <<< "$out")"
has "with its line, size and heading" "move candidate: line 2, 9021 chars, SENTINEL_HEAD big" "$out"
expect "the exit code is unchanged" 0 "$rc"
run --sweep "$T/p/sec"
has "a sweep prints line and size" "move candidate: line 2, 9021 chars" "$out"
hasnt "but never the heading" "SENTINEL_HEAD" "$out$err"
sec_of() {  # sec_of <total chars of the section, heading line included>
  fresh secb; { printf '## h\n'; rep a $(($1 - 6)); printf '\n'; } > "$P/CLAUDE.md"; run "$P"
}
sec_of 8000; expect "exactly 8,000 is not flagged" 0 "$(grep -c '^move candidate' <<< "$out")"
sec_of 8001; expect "8,001 is flagged" 1 "$(grep -c '^move candidate' <<< "$out")"
sec_of 7999; expect "7,999 is not flagged" 0 "$(grep -c '^move candidate' <<< "$out")"
fresh secfence; { printf '## s\n```\n# x\n## y\n```\n'; rep a 9000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; has "headings inside a fence end nothing" "move candidate: line 1, 9023 chars, s" "$out"
fresh sechash; { printf '## s\n### deeper\n'; rep a 9000; printf '\n# top\n'; rep a 9000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; has "a ### heading does not end a section" "line 1, 9017 chars" "$out"
expect "a # heading ends it and starts none" 1 "$(grep -c '^move candidate' <<< "$out")"
fresh secfail; { printf '## big\n'; rep a 85000; printf '\n'; } > "$P/CLAUDE.md"
run "$P"; expect "a flag never changes a FAIL exit" 1 "$rc"; has "and is still printed" "move candidate" "$out"

echo "== no file text in either mode, but a single-repository heading =="
fresh sent; M=$(memdir "$P"); mkdir -p "$M"; printf 'SENTINEL_MEM\n' > "$M/MEMORY.md"
{ printf 'SENTINEL_MAIN\n@i.md\n## SENTINEL_HEADING\n'; rep a 8100; printf ' SENTINEL_SECTION\n'; } > "$P/CLAUDE.md"
printf 'SENTINEL_IMPORT\n' > "$P/i.md"
run "$P"; both="$out$err"
for s in SENTINEL_MAIN SENTINEL_IMPORT SENTINEL_MEM SENTINEL_SECTION; do hasnt "$s is in neither stream of a single run" "$s" "$both"; done
has "the heading is printed on a single run" "SENTINEL_HEADING" "$out"
run --sweep "$T/p/sent"; both="$out$err"
for s in SENTINEL_MAIN SENTINEL_IMPORT SENTINEL_MEM SENTINEL_SECTION SENTINEL_HEADING; do hasnt "$s is in neither stream of a sweep" "$s" "$both"; done
has "the sweep still counts all three" "$((14 + 6 + 20 + 8118 + 16 + 13))	ok" "$out"

echo "== malformed tokens and files end cleanly =="
fresh malformed; mkdir -p "$P/adir"; file "$P/unread.md" 10; chmod 000 "$P/unread.md"
printf '@\n@ x\ntrailing @\n@adir\n@unread.md\n@bin.dat\n' > "$P/CLAUDE.md"; head -c 300 /dev/urandom > "$P/bin.dat" 2>/dev/null
run "$P"
case "$rc" in 0|1) ok "malformed tokens, a directory, an unreadable and a binary file exit cleanly" ;; *) bad "malformed tokens exit cleanly (rc $rc)" ;; esac
has "a binary import is still counted as a file" "bin.dat (hop 1)" "$out"
hasnt "a directory is not an import" "adir" "$out"
chmod 644 "$P/unread.md"

echo "== names and tokens never reach a shell =="
fresh inj; cd "$T"; printf '@$(touch\\ PWNED).md @x;touch\\ PWNED2.md\n' > "$P/CLAUDE.md"
file "$P/\$(touch PWNED).md" 10
run "$P"; cd "$ROOT"
expect "a \$( ) token is only a file name" 0 "$rc"
[ ! -e "$T/PWNED" ] && [ ! -e "$P/PWNED" ] && [ ! -e "$T/PWNED2.md" ] && ok "no command ran" || bad "no command ran"
has "the oddly named file is counted as a file" "touch PWNED).md (hop 1)" "$out"

echo "== usage =="
fresh empty; run "$P"; expect "a <repo-dir> without CLAUDE.md exits 2" 2 "$rc"; has "naming the problem" "no CLAUDE.md" "$err"
expect "with nothing on stdout" "" "$out"
run --sweep; expect "--sweep without a root exits 2" 2 "$rc"
run --sweep "$T/nope"; expect "a missing root exits 2" 2 "$rc"
run a b; expect "two repo dirs exit 2" 2 "$rc"
run --bogus; expect "an unknown option exits 2" 2 "$rc"
fresh emptyfile; : > "$P/CLAUDE.md"; run "$P"; expect "an empty CLAUDE.md is 0 and ok" "0 ok" "$(total) $(level)"

echo "== this repository's own CLAUDE.md, state-independent =="
# Skipped where the file is absent, which is every CI checkout: CLAUDE.md is local working state.
# It asserts nothing about the file's state (that moves whenever the owner prunes it), only that
# the run is a measurement: exit 0 or 1, and a total at least the file's own character count.
if [ ! -f "$ROOT/CLAUDE.md" ]; then
  ok "(skipped, CLAUDE.md is not in this checkout) the dogfood run"
else
  run "$ROOT"
  case "$rc" in 0|1) ok "the dogfood run exits 0 or 1" ;; *) bad "the dogfood run exits 0 or 1 (got $rc)" ;; esac
  floor=$(LC_ALL=C tr -d '\200-\277' < "$ROOT/CLAUDE.md" | wc -c | tr -d ' ')
  [ "$(total)" -ge "$floor" ] 2>/dev/null && ok "the total is at least CLAUDE.md's own count" || bad "the total is at least CLAUDE.md's own count ($(total) < $floor)"
fi

echo
echo "context-budget: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
