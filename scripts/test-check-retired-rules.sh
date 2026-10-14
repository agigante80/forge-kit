#!/usr/bin/env bash
# Contract test for scripts/check-retired-rules.sh (#495).
#
# The guard fails forge-kit's own build when a tracked file still states a retired rule. Its worst
# failure is a false clean, so the cases pin a retired phrasing put back into a real component (the
# regression #495 exists for), an older rule id, and that the exemptions stay whole files: a file
# that merely shares an exempt basename, or anything under plugins/, is still scanned. Fixture text
# quotes retired phrasings on purpose, which is why the guard exempts this file by path.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
G="$ROOT/scripts/check-retired-rules.sh"
A="plugins/forge-kit-adapt/skills/adapt/assets"
FR="plugins/forge-kit-review/commands/full-review.md"
SK="plugins/forge-kit-review/skills/review-lows/SKILL.md"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { if grep -qxF -- "$1" <<< "$out"; then ok "$2"; else bad "$2 (no line '$1' in: $out)"; fi; }

[ -f "$G" ] || { echo "missing script: $G"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
T=$(CDPATH= cd -P -- "$T" && pwd -P)

# fresh: a fixture checkout holding the real scanner, data file, canonical skill and full-review,
# all tracked (the index is enough: the guard lists tracked files, so nothing needs committing).
fresh() {
  R="$T/repo$1"
  mkdir -p "$R/$A" "$R/$(dirname "$FR")" "$R/$(dirname "$SK")" "$R/docs"
  cp "$ROOT/$A/stale-rules.sh" "$ROOT/$A/retired-rules.tsv" "$R/$A/"
  cp "$ROOT/$FR" "$R/$FR"
  cp "$ROOT/$SK" "$R/$SK"
  printf '# Notes\n\nNothing retired here.\n' > "$R/docs/notes.md"
  git -C "$R" init -q
  git -C "$R" add -A
}
run() { out=$(bash "$G" --root "$R" 2>&1); rc=$?; }
# put LINE in at line N of FILE (relative to the fixture), then track it
inject() { awk -v n="$2" -v l="$3" 'NR == n { print l } { print }' "$R/$1" > "$R/$1.new" \
  && mv "$R/$1.new" "$R/$1" && git -C "$R" add -A; }

echo "clean fixture"
fresh 1; run
expect "a clean tree exits 0" 0 "$rc"
if grep -q "no retired rule" <<< "$out"; then ok "a clean tree says so"; else bad "no clean message: $out"; fi

echo "a retired phrasing put back into full-review"
fresh 2; inject "$FR" 20 "Each Low becomes a ticket immediately."; run
expect "the regression exits 1" 1 "$rc"
has "$FR:20: retired rule review-lows" "the hit names the component, its line and the rule id"

echo "a deliberate quote"
fresh 3; inject "$FR" 20 "The old text said a Low becomes a ticket immediately. retired-rule-quote"; run
expect "a line marked retired-rule-quote passes" 0 "$rc"

echo "an older rule id"
fresh 4; printf '# Old\n\n<!-- rule: review-lows v1 -->\n' > "$R/docs/old.md"; git -C "$R" add -A; run
expect "an older rule id exits 1" 1 "$rc"
has "docs/old.md:3: retired rule review-lows" "the old id is located"

echo "exemptions are whole files"
fresh 5; printf 'Retired: Lows were ticketed immediately.\n' > "$R/CHANGELOG.md"; git -C "$R" add -A; run
expect "the root CHANGELOG is exempt" 0 "$rc"
fresh 6; printf 'Lows were ticketed immediately.\n' > "$R/docs/CHANGELOG.md"; git -C "$R" add -A; run
expect "a CHANGELOG elsewhere is scanned" 1 "$rc"
has "docs/CHANGELOG.md:1: retired rule review-lows" "the basename alone earns nothing"
fresh 7; printf 'Lows were ticketed immediately.\n' > "$R/$A/notes.md"; git -C "$R" add -A; run
expect "a file beside the exempt data file is scanned" 1 "$rc"

echo "only tracked files"
fresh 8; printf 'Lows were ticketed immediately.\n' > "$R/docs/untracked.md"; run
expect "an untracked file is not this guard's business" 0 "$rc"

echo "a tracked symlink"
fresh 9; ln -s notes.md "$R/docs/link.md"; git -C "$R" add -A; run
expect "a tracked symlink is skipped, not an incomplete scan" 0 "$rc"

echo "files the scanner cannot or need not read"
fresh 11; printf 'x\0Lows were ticketed immediately.\n' > "$R/docs/blob.bin"; git -C "$R" add -A; run
expect "a tracked binary is not scanned" 0 "$rc"
if [ "$(id -u)" -ne 0 ]; then
  fresh 12; chmod 000 "$R/docs/notes.md"; run; chmod 644 "$R/docs/notes.md"
  expect "an unreadable tracked file fails as an incomplete scan, never clean" 2 "$rc"
  if grep -q "docs/notes.md" <<< "$out"; then ok "the incomplete scan names the file"; else bad "unnamed: $out"; fi
else
  ok "skipped as root: an unreadable file"; ok "skipped as root: the file is named"
fi

echo "errors"
out=$(bash "$G" --root "$T/nowhere" 2>&1); rc=$?
expect "a missing root exits 2" 2 "$rc"
out=$(bash "$G" --bogus 2>&1); rc=$?
expect "an unknown argument exits 2" 2 "$rc"
out=$(bash "$G" --root 2>&1); rc=$?
expect "--root without a value exits 2" 2 "$rc"
fresh 10; rm "$R/$A/stale-rules.sh"; run
expect "a missing scanner exits 2, never clean" 2 "$rc"
mkdir -p "$T/plain/$A"; cp "$ROOT/$A/stale-rules.sh" "$ROOT/$A/retired-rules.tsv" "$T/plain/$A/"
R="$T/plain"; run
expect "a directory that is not a checkout exits 2" 2 "$rc"

echo "this repository"
out=$(bash "$G" 2>&1); rc=$?
expect "forge-kit itself states no retired rule" 0 "$rc"

echo
echo "check-retired-rules: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
