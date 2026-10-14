#!/usr/bin/env bash
# Contract test for forge-adapt's adapt/assets/stale-rules.sh (#495).
#
# The scanner finds a RETIRED rule where earlier installs and sessions left it: adapted components,
# config-dir copies, instruction prose and memory. Its worst failure is a false clean, so the cases
# pin every way it could report nothing while it did not look (a symlink, an underivable auto
# memory dir) as well as every way it finds a hit (a listed phrasing, a wrapped one, an older rule
# id). STREAMS ARE THE CONTRACT: tab-separated rows and a summary row on stdout, exit 0 clean,
# 1 hits, 3 incomplete, 2 usage error with nothing on stdout. Fixture text quotes retired phrasings
# on purpose, which is why scripts/check-retired-rules.sh exempts this file by path.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
S="$ROOT/plugins/forge-kit-adapt/skills/adapt/assets/stale-rules.sh"
RULES="$ROOT/plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { if grep -qxF -- "$1" <<< "$out"; then ok "$2"; else bad "$2 (no row '$1' in: $out)"; fi; }
hasnt() { if grep -qF -- "$1" <<< "$out"; then bad "$2 (found '$1' in: $out)"; else ok "$2"; fi; }
nrows() { printf '%s\n' "$out" | grep -c "^$1	" | tr -d ' '; }

[ -f "$S" ] || { echo "missing script: $S"; exit 1; }
[ -f "$RULES" ] || { echo "missing data file: $RULES"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd -P -- "$T" && pwd -P)
TAB=$(printf '\t')
TL="~"   # a tilde built apart from its path, so the public-leak guard reads no home root here

# The fixture kit: the one place the current rule id comes from.
KIT="$T/kit"
mkdir -p "$KIT/plugins/forge-kit-review/skills/review-lows"
printf -- '---\nname: review-lows\n---\n\n<!-- rule: review-lows v2 -->\n\nFix, ticket or drop.\n' \
  > "$KIT/plugins/forge-kit-review/skills/review-lows/SKILL.md"

P=""
# fresh: an empty git project (its own toplevel, so the slug is the fixture's, never an enclosing
# checkout's) and an empty HOME with no CLAUDE_CONFIG_DIR.
fresh() {
  rm -rf "$T/p" "$T/home" "$T/cfg" "$T/outside"
  P="$T/p"; mkdir -p "$P" "$T/home"
  git init --quiet "$P" >/dev/null 2>&1
}
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }
put() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
sum() { cksum < "$1"; }

out=""; err=""; rc=0
run() {
  out=$(cd "$P" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" bash "$S" --kit "$KIT" "$@" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
}
runcfg() {
  out=$(cd "$P" && HOME="$T/home" CLAUDE_CONFIG_DIR="$1" bash "$S" --kit "$KIT" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
}

echo "== the data file carries the first retired rule =="
expect "review-lows v1 has rows" yes "$(awk -F'\t' '$1=="review-lows" && $2=="1" {f=1} END {print f ? "yes" : "no"}' "$RULES")"
expect "every data row has five tab-separated columns" 0 "$(grep -v '^#' "$RULES" | grep -v '^$' | awk -F'\t' 'NF != 5' | wc -l | tr -d ' ')"

echo "== a listed phrasing in an adapted component whose marker is current =="
fresh
put "$P/.claude/agents/code-reviewer.md" '---\nname: code-reviewer\n---\n<!-- code-reviewer-version: 14 -->\n\nRules:\nA finding below High becomes a ticket immediately, not a negotiation.\n'
run
has "stale-rule${TAB}component${TAB}.claude/agents/code-reviewer.md${TAB}7${TAB}review-lows" "a downstream project's wording is found at its line"
expect "hits exit 1" 1 "$rc"
has "summary${TAB}1${TAB}1${TAB}0" "the summary counts one file, one stale row, nothing unscanned"
fresh
put "$P/.claude/agents/code-reviewer.md" '<!-- rule: review-lows v2 -->\nEach Low gets one outcome: fix, ticket or drop.\n'
run
expect "the v2 wording is clean" 0 "$(nrows stale-rule)"
expect "clean exits 0" 0 "$rc"
has "summary${TAB}1${TAB}0${TAB}0" "and the summary says so"

echo "== an older rule id, whatever the wording =="
fresh
put "$P/.claude/commands/full-review.md" 'intro\n\n<!-- rule: review-lows v1 -->\nLows go through our own process.\n'
run
has "stale-rule${TAB}component${TAB}.claude/commands/full-review.md${TAB}3${TAB}review-lows" "an older id is reported at the comment line"
expect "and exits 1" 1 "$rc"
fresh
put "$P/.claude/commands/full-review.md" 'intro\n\n<!-- rule: review-lows v2 -->\nLows go through our own process.\n'
run
expect "the current id is not reported" 0 "$(nrows stale-rule)"
fresh
put "$P/.claude/commands/full-review.md" '<!-- rule: review-lows v3 -->\n'
run
expect "a newer id than the kit's is not stale" 0 "$(nrows stale-rule)"
fresh
put "$P/.claude/commands/x.md" '<!-- rule: some-other-rule v1 -->\n'
run
expect "an id the kit does not carry is ignored" 0 "$(nrows stale-rule)"

echo "== project prose =="
fresh
put "$P/CONTRIBUTING.md" '# Contributing\n\nReview findings: anything below becomes a ticket.\n'
before=$(sum "$P/CONTRIBUTING.md")
run
has "stale-rule${TAB}prose${TAB}CONTRIBUTING.md${TAB}3${TAB}review-lows" "CONTRIBUTING wording is a prose row"
expect "and the file is unchanged" "$before" "$(sum "$P/CONTRIBUTING.md")"
for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md docs/a/b.md; do
  fresh; put "$P/$f" 'x\nLow findings are ticketed immediately.\n'; run
  has "stale-rule${TAB}prose${TAB}$f${TAB}2${TAB}review-lows" "$f is scanned as prose"
done
fresh; put "$P/docs/notes.txt" 'Low findings are ticketed immediately.\n'; run
expect "a non-markdown file under docs/ is not scanned" 0 "$(nrows stale-rule)"
fresh; put "$P/README.md" 'Low findings are ticketed immediately.\n'; run
expect "a file outside the listed places is not scanned" 0 "$(nrows stale-rule)"
fresh; run
expect "an empty project reports no rows" 0 "$(nrows stale-rule)"
expect "and no unscanned place" 0 "$(nrows not-scanned)"
expect "and exits 0" 0 "$rc"
has "summary${TAB}0${TAB}0${TAB}0" "with a zero summary"

echo "== matching is per paragraph, across wraps =="
fresh
put "$P/AGENTS.md" '# Review\n\n- Round 1: High and Medium are fixed, and all Low findings are\n  ticketed immediately by the reviewer.\n- Round 2: delta only.\n'
run
has "stale-rule${TAB}prose${TAB}AGENTS.md${TAB}3${TAB}review-lows" "a phrase wrapped under a list continuation indent is found at its start line"
expect "exactly once" 1 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'every Low finding is ticketed immediately\n'
run
expect "two regexes on one line merge into one row" 1 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'Low findings are\nticketed immediately.\n'
run
has "stale-rule${TAB}prose${TAB}AGENTS.md${TAB}1${TAB}review-lows" "matches starting on two lines of one paragraph merge at the earliest"
expect "into one row" 1 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'Lows are ticketed immediately.\n\nLows are ticketed immediately.\n'
run
expect "the same phrase in two paragraphs is two rows" 2 "$(nrows stale-rule)"
fresh
printf '# two ids\nid-a\t1\t2026-10-10\tticketed immediately\tx\nid-b\t1\t2026-10-10\tticketed immediately\ty\n' > "$T/two.tsv"
put "$P/AGENTS.md" 'Lows are ticketed immediately.\n'
run --rules "$T/two.tsv"
expect "two rule ids on one text never merge" 2 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" '> Low findings are\n> ticketed IMMEDIATELY.\n'
run
has "stale-rule${TAB}prose${TAB}AGENTS.md${TAB}1${TAB}review-lows" "a wrapped blockquote matches, case folded"
fresh
put "$P/AGENTS.md" 'Every Low finding is\n\nticketed immediately? No.\n'
run
has "stale-rule${TAB}prose${TAB}AGENTS.md${TAB}3${TAB}review-lows" "the second paragraph alone still matches its own phrase"
fresh
put "$P/AGENTS.md" 'the work is ticketed\n\nimmediately after review\n'
run
expect "halves in different paragraphs do not join" 0 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" '- item one ends ticketed\n- immediately the next item\n'
run
expect "a new list item starts a new paragraph" 0 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" '## Lows are ticketed\nimmediately below a heading\n'
run
expect "a heading is its own paragraph" 0 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'ticketed   \t  immediately\n'
run
expect "a run of spaces and tabs collapses" 1 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'ticketed immediately. Also ticketed immediately.\n\nLow findings are filed as tickets.\n'
run
expect "two hits on one line are one row; a second paragraph's hit is another" 2 "$(nrows stale-rule)"

echo "== every listed phrasing of review-lows v1 =="
for phrase in 'ticketed immediately' 'becomes a ticket immediately' 'become a ticket immediately' \
  'Ticketed at Completion' 'a Low twin is ticketed like any other Low' 'ticket-fodder by default' \
  'anything below becomes a ticket' 'anything below High becomes a ticket' 'the user wants every Low ticketed' \
  'every Low finding is ticketed' 'Low findings are filed as tickets' 'no finding is ever left with neither' \
  'no finding is left with neither'; do
  fresh; put "$P/CLAUDE.md" "$phrase\n"; run
  expect "listed: $phrase" 1 "$(nrows stale-rule)"
done
for phrase in 'Each Low gets exactly one outcome: fix, ticket or drop.' 'ticket it only when a user could hit it' \
  'An out-of-target observation is dropped with one line unless a user could hit it.' 'the ticket was filed immediately'; do
  fresh; put "$P/CLAUDE.md" "$phrase\n"; run
  expect "not listed: $phrase" 0 "$(nrows stale-rule)"
done

echo "== the opt-out marker =="
fresh
put "$P/.claude/memory/feedback.md" 'Retired: every Low finding is ticketed immediately. <!-- retired-rule-quote -->\n\nnote\n\nevery Low finding is ticketed immediately\n'
run
expect "the marked line is skipped, the unmarked one two lines below is reported" 1 "$(nrows stale-rule)"
has "stale-rule${TAB}memory${TAB}.claude/memory/feedback.md${TAB}5${TAB}review-lows" "and the reported one is the unmarked line"
fresh
put "$P/.claude/agents/code-reviewer.md" 'Low findings are\nticketed immediately (retired-rule-quote)\n'
run
expect "a marker on any line the match spans suppresses it" 0 "$(nrows stale-rule)"
fresh
put "$P/.claude/agents/code-reviewer.md" '<!-- rule: review-lows v1 --> retired-rule-quote\n'
run
expect "the marker also suppresses an id row" 0 "$(nrows stale-rule)"

echo "== memory: project stores and auto memory =="
fresh
put "$P/.claude/handoffs/2026-10-01.md" 'resume: Low findings are ticketed immediately\n'
run
has "stale-rule${TAB}memory${TAB}.claude/handoffs/2026-10-01.md${TAB}1${TAB}review-lows" "handoffs are memory"
fresh
s=$(slug "$P")
put "$T/home/.claude/projects/$s/memory/feedback.md" '---\nname: x\n---\nthe user wants every Low finding ticketed immediately\n'
before=$(sum "$T/home/.claude/projects/$s/memory/feedback.md")
run
has "stale-rule${TAB}memory${TAB}~/.claude/projects/$s/memory/feedback.md${TAB}4${TAB}review-lows" "auto memory is found by the project slug and printed with ~"
expect "and the note is unchanged" "$before" "$(sum "$T/home/.claude/projects/$s/memory/feedback.md")"
mkdir -p "$P/sub"
out=$(cd "$P/sub" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" bash "$S" --kit "$KIT" --project "$P" 2>/dev/null)
expect "--project names the project from elsewhere" 1 "$(nrows stale-rule)"
put "$T/home/.claude/projects/other/memory/x.md" 'Low findings are ticketed immediately\n'
run
expect "another project's memory is not read" 1 "$(nrows stale-rule)"

echo "== the config dir =="
fresh
put "$T/home/.claude/agents/code-reviewer.md" 'Low findings are ticketed immediately\n'
put "$T/home/.claude/commands/full-review.md" '### Low Priority (P3 -- Ticketed at Completion)\n'
put "$T/home/.claude/skills/x/references/y.md" 'ticket-fodder by default\n'
put "$T/home/.claude/CLAUDE.md" 'anything below becomes a ticket\n'
run
has "stale-rule${TAB}component${TAB}~/.claude/agents/code-reviewer.md${TAB}1${TAB}review-lows" "config agents are components"
has "stale-rule${TAB}component${TAB}~/.claude/commands/full-review.md${TAB}1${TAB}review-lows" "config commands are components"
has "stale-rule${TAB}component${TAB}~/.claude/skills/x/references/y.md${TAB}1${TAB}review-lows" "config skills are components, at any depth"
has "stale-rule${TAB}prose${TAB}~/.claude/CLAUDE.md${TAB}1${TAB}review-lows" "the global CLAUDE.md is prose"
fresh
mkdir -p "$T/cfg/agents"
put "$T/home/.claude/agents/a.md" 'Low findings are ticketed immediately\n'
put "$T/home/cfg/agents/code-reviewer.md" 'Low findings are ticketed immediately\n'
runcfg "$T/home/cfg"
has "stale-rule${TAB}component${TAB}${TL}/cfg/agents/code-reviewer.md${TAB}1${TAB}review-lows" "CLAUDE_CONFIG_DIR is honoured and printed with ~"
expect "and HOME/.claude is not read when it is set" 1 "$(nrows stale-rule)"
fresh
put "$T/cfg/agents/a.md" 'Low findings are ticketed immediately\n'
runcfg "$T/cfg"
has "stale-rule${TAB}component${TAB}$T/cfg/agents/a.md${TAB}1${TAB}review-lows" "a config dir outside HOME prints its absolute path"
fresh
mkdir -p "$T/home/.claude"
run
expect "a config dir with no agents, commands or skills reports nothing" 0 "$(nrows stale-rule)"
expect "and exits 0" 0 "$rc"

echo "== places the scan cannot look into are reported, never skipped silently =="
fresh
mkdir -p "$T/outside/shared" "$T/home/.claude/skills"
put "$T/outside/shared/SKILL.md" 'Low findings are ticketed immediately\n'
ln -s "$T/outside/shared" "$T/home/.claude/skills/shared"
run
expect "the symlink target is not read" 0 "$(nrows stale-rule)"
has "not-scanned${TAB}~/.claude/skills/shared${TAB}symlink" "the symlink is reported as not scanned"
expect "an incomplete clean scan exits 3, never 0" 3 "$rc"
has "summary${TAB}0${TAB}0${TAB}1" "and the summary counts it"
fresh
mkdir -p "$T/outside"; put "$T/outside/agents/a.md" 'Low findings are ticketed immediately\n'
mkdir -p "$T/home/.claude"; ln -s "$T/outside/agents" "$T/home/.claude/agents"
run
has "not-scanned${TAB}~/.claude/agents${TAB}symlink" "a symlinked named directory is reported, not followed"
expect "and nothing behind it is read" 0 "$(nrows stale-rule)"
fresh
put "$P/AGENTS.md" 'Low findings are ticketed immediately\n'
ln -s AGENTS.md "$P/CLAUDE.md"
run
has "not-scanned${TAB}CLAUDE.md${TAB}symlink" "a symlinked prose file is reported"
expect "a hit plus an unscanned place exits 1" 1 "$rc"
fresh
LONG="$P"
for i in 1 2 3 4 5; do LONG="$LONG/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$i"; done
mkdir -p "$LONG"; git init --quiet "$LONG" >/dev/null 2>&1
out=$(cd "$LONG" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" bash "$S" --kit "$KIT" 2>/dev/null); rc=$?
expect "an over-length slug is one not-scanned row" 1 "$(nrows not-scanned)"
if grep -q "project slug over 200 characters" <<< "$out"; then ok "with the reason named"; else bad "with the reason named ($out)"; fi
expect "and exits 3, not 0" 3 "$rc"
fresh
put "$P/.claude/memory/x.md" 'Low findings are ticketed immediately\n'
chmod 000 "$P/.claude/memory/x.md"
if [ ! -r "$P/.claude/memory/x.md" ]; then
  run
  has "not-scanned${TAB}.claude/memory/x.md${TAB}unreadable" "an unreadable file is reported"
  expect "and exits 3" 3 "$rc"
else
  ok "unreadable case skipped: running as a user who can read mode 000"
fi
chmod 644 "$P/.claude/memory/x.md"

echo "== --files-from scans a given list as prose =="
fresh
put "$P/a.md" 'Low findings are ticketed immediately\n'
put "$P/b.md" 'clean\n'
printf 'a.md\nb.md\n' > "$T/list"
out=$(cd "$P" && bash "$S" --kit "$KIT" --files-from "$T/list" 2>/dev/null); rc=$?
has "stale-rule${TAB}prose${TAB}a.md${TAB}1${TAB}review-lows" "a listed file is scanned with its path as given"
has "summary${TAB}2${TAB}1${TAB}0" "only the listed files are counted"
expect "and it exits 1" 1 "$rc"
out=$(cd "$P" && printf 'b.md\n' | bash "$S" --kit "$KIT" --files-from - 2>/dev/null); rc=$?
expect "stdin works, and a clean list exits 0" 0 "$rc"

ln -s a.md "$P/c.md"
out=$(cd "$P" && printf 'c.md\n' | bash "$S" --kit "$KIT" --files-from - 2>/dev/null); rc=$?
has "not-scanned${TAB}c.md${TAB}symlink" "a listed symlink is reported, not followed"
expect "and exits 3" 3 "$rc"

echo "== usage errors exit 2 with nothing on stdout =="
fresh
run --bogus
expect "an unknown flag exits 2" 2 "$rc"; expect "with empty stdout" "" "$out"
run --rules "$T/no-such.tsv"
expect "a missing data file exits 2" 2 "$rc"; expect "with empty stdout" "" "$out"
out=$(cd "$P" && HOME="$T/home" bash "$S" --kit "$T/home" 2>/dev/null); rc=$?
expect "a kit with no plugins/ exits 2" 2 "$rc"; expect "with empty stdout" "" "$out"
run --project "$T/no-such-dir"
expect "a missing project exits 2" 2 "$rc"
run --files-from "$T/no-such-list"
expect "a missing list exits 2" 2 "$rc"
run --kit
expect "a flag with no value exits 2" 2 "$rc"

echo "== read only =="
fresh
put "$P/CONTRIBUTING.md" 'anything below becomes a ticket\n'
put "$P/.claude/agents/a.md" 'Low findings are ticketed immediately\n'
find "$P" "$T/home" -type f -exec cksum {} + | sort > "$T/before"
run
find "$P" "$T/home" -type f -exec cksum {} + | sort > "$T/after"
expect "no file under the project or HOME changes" "" "$(diff "$T/before" "$T/after")"

echo ""
echo "stale-rules tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
