#!/usr/bin/env bash
# Contract test for scripts/check-review-rule.sh (#495).
#
# The guard keeps the review-lows rule in one home: one rule id in the canonical skill, the same
# id in every pointer and every other carrier, the rule's anchor phrases nowhere else under
# plugins/, and the retired-rules data never retiring the current version. Each case breaks one of
# those in a fixture copied from this repository and expects exit 1 naming the file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
G="$ROOT/scripts/check-review-rule.sh"
CANON="plugins/forge-kit-review/skills/review-lows/SKILL.md"
CR="plugins/forge-kit-review/agents/code-reviewer.md"
FR="plugins/forge-kit-review/commands/full-review.md"
PL="plugins/forge-kit-governance/skills/working-overnight/references/pipeline.md"
RL="docs/guides/review-loop.md"
TSV="plugins/forge-kit-adapt/skills/adapt/assets/retired-rules.tsv"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3': $out)"; fi; }
names() { if grep -qF -- "$1" <<< "$out"; then ok "$2"; else bad "$2 (no '$1' in: $out)"; fi; }

[ -f "$G" ] || { echo "missing script: $G"; exit 1; }
# the live canonical version, so a rule bump needs no edit here; V1 is the next one up
V=$(grep -oE '<!-- rule: review-lows v[0-9]+ -->' "$ROOT/$CANON" | sed -E 's/.* v([0-9]+) -->/\1/')
case "$V" in ''|*[!0-9]*) echo "cannot read the canonical rule version from $CANON"; exit 1 ;; esac
[ "$V" -ge 2 ] || { echo "the older-version cases need a canonical version of 2 or more"; exit 1; }
V1=$((V + 1))

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd -P -- "$T" && pwd -P)

n=0
fresh() {
  n=$((n + 1)); R="$T/repo$n"
  for f in "$CANON" "$CR" "$FR" "$PL" "$RL" "$TSV"; do
    mkdir -p "$R/$(dirname "$f")"; cp "$ROOT/$f" "$R/$f"
  done
  git -C "$R" init -q
  git -C "$R" add -A
}
track() { git -C "$R" add -A; }
run() { out=$(bash "$G" --root "$R" 2>&1); rc=$?; }
# rewrite every rule id comment in FILE to version V
setv() { sed -E -i "s/<!-- rule: review-lows v[0-9]+ -->/<!-- rule: review-lows v$2 -->/" "$R/$1"; }

echo "consistent fixture"
fresh; run
expect "the real files agree" 0 "$rc"

echo "the canonical home"
fresh; printf '\n<!-- rule: review-lows v%s -->\n' "$V" >> "$R/$CANON"; run
expect "two ids in the canonical skill fail" 1 "$rc"
names "$CANON" "the canonical file is named"
fresh; setv "$CANON" "$V1"; run
expect "a canonical bump without the pointers fails" 1 "$rc"
names "$CR: rule id review-lows v$V, canonical is v$V1" "each stale pointer is named"
names "$RL: rule id review-lows v$V, canonical is v$V1" "a docs pointer is named too"

fresh; sed -i "s/roughly 15 minutes/about a quarter hour/" "$R/$CANON"; run
expect "an anchor missing from the canonical file fails" 1 "$rc"
names "$CANON: anchor 'roughly 15 minutes' is missing" "the canonical file and the anchor are named"

echo "declared pointers"
fresh; setv "$FR" 1; run
expect "a pointer at an older version fails" 1 "$rc"
names "$FR: rule id review-lows v1" "the pointer and its version are named"
fresh; sed -E -i 's/<!-- rule: review-lows v[0-9]+ -->//' "$R/$PL"; run
expect "a pointer that lost its id fails" 1 "$rc"
names "$PL: declared pointer carries no rule id" "the bare pointer is named"
fresh; git -C "$R" rm -q -f "$CR"; run
expect "a missing pointer fails" 1 "$rc"
names "$CR: declared pointer is missing" "the missing pointer is named"
fresh; printf '\nAgain <!-- rule: review-lows v1 -->\n' >> "$R/$CR"; run  # retired-rule-quote
expect "a second, older id in a pointer fails" 1 "$rc"

echo "other carriers"
fresh; mkdir -p "$R/docs/x"; printf 'See <!-- rule: review-lows v1 -->\n' > "$R/docs/x/old.md"; track; run  # retired-rule-quote
expect "another docs carrier at an older version fails" 1 "$rc"
names "docs/x/old.md" "the carrier is named"
fresh; mkdir -p "$R/docs/x"; printf 'See <!-- rule: review-lows v%s -->\n' "$V" > "$R/docs/x/ok.md"; track; run
expect "another carrier at the canonical version passes" 0 "$rc"
fresh; mkdir -p "$R/other"; printf 'See <!-- rule: review-lows v1 -->\n' > "$R/other/old.md"; track; run  # retired-rule-quote
expect "a file outside plugins/ and docs/ is not a carrier" 0 "$rc"

echo "anchor phrases"
fresh; mkdir -p "$R/plugins/g/agents"; printf 'Fix it when it takes ROUGHLY 15\n   minutes.\n' > "$R/plugins/g/agents/a.md"; track; run
expect "a wrapped, recased anchor under plugins/ fails" 1 "$rc"
names "plugins/g/agents/a.md: restates 'roughly 15 minutes'" "the restating file and anchor are named"
fresh; printf '\nTicket it when a user could really hit it.\n' >> "$R/$FR"; run
expect "an anchor in a pointer fails" 1 "$rc"
fresh; mkdir -p "$R/docs/x"; printf 'Fix it in roughly 15 minutes.\n' > "$R/docs/x/guide.md"; track; run
expect "an anchor in docs/ is explanation, not a restated component" 0 "$rc"
fresh; mkdir -p "$R/plugins/g"; printf 'Fix it in roughly 15 minutes.\n' > "$R/plugins/g/untracked.md"; run
expect "an untracked file is not checked" 0 "$rc"

echo "the retired-rules data"
fresh; printf 'review-lows\t%s\t2026-10-14\tsome phrase\treplacement\n' "$V" >> "$R/$TSV"; run
expect "a row retiring the current version fails" 1 "$rc"
names "$TSV: retires review-lows v$V" "the data file is named"
fresh; printf 'review-lows\tx\t2026-10-14\tsome phrase\treplacement\n' >> "$R/$TSV"; run
expect "a non-numeric version fails" 1 "$rc"
fresh; printf 'other-rule\t9\t2026-10-14\tsome phrase\treplacement\n' >> "$R/$TSV"; run
expect "another rule's rows are not compared" 0 "$rc"

echo "errors"
fresh; rm "$R/$CANON"; run
expect "a missing canonical skill exits 2" 2 "$rc"
fresh; rm "$R/$TSV"; run
expect "a missing data file exits 2" 2 "$rc"
out=$(bash "$G" --bogus 2>&1); rc=$?
expect "an unknown argument exits 2" 2 "$rc"
out=$(bash "$G" --root "$T/nowhere" 2>&1); rc=$?
expect "a missing root exits 2" 2 "$rc"

echo "this repository"
out=$(bash "$G" 2>&1); rc=$?
expect "forge-kit's review-lows rule has one home" 0 "$rc"
# The loop's stop reasons are defined, not just listed: a downstream round 1 whose only fixes were
# Mediums ended as `clean round` and its fixes were never reviewed.
grep -qF 'applied no fix, so the next delta is empty' "$ROOT/$FR" \
  && ok "full-review defines clean round as a round that applied no fix" \
  || bad "full-review defines clean round as a round that applied no fix"
grep -qF '`round-gate not met` (round 2 or 3 applied a' "$ROOT/$FR" \
  && ok "full-review defines round-gate not met" || bad "full-review defines round-gate not met"
# An overnight investigation never tickets a Medium: it is one "Noticed, not filed" line.
grep -qF 'each Medium is one line under "Noticed, not filed"' "$ROOT/$PL" \
  && ok "an overnight investigation notes its Mediums instead of ticketing them" \
  || bad "an overnight investigation notes its Mediums instead of ticketing them"

echo
echo "check-review-rule: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
