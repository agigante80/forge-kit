#!/usr/bin/env bash
# Contract test for check-doc-drift.sh (#247).
#
# The check answers one mechanical question per claim: is the last commit that touched THAT LINE
# older than a commit in the range that touched the path the line names? Everything here is a
# throwaway repository whose commit dates are fixed, because "older" is the whole rule and a test
# that let git pick the timestamps would be asserting against the clock.
#
# THE POSTURE IS WHAT MOST OF THESE CASES PIN. The check reports and never fails: exit 0 whether or
# not it found anything, exit 2 only when it could not run. So every findings assertion here is on
# the ROWS on stdout and never on the exit status, which is the same for a clean run and a dirty
# one. A suite that asserted on the status would pass against a script that found nothing, ever.
#
# MUTANTS KILLED, all ten run by hand on 2026-09-23 and each shown to fail this suite: the
# marker-region exclusion dropped; the line-level comparison relaxed to document level; the
# newest-in-range selection changed to oldest; the age comparison inverted; the untracked-document
# refusal turned into a skip; the absent-document refusal turned into a skip; the range validation
# dropped; the component-name resolution dropped; the posture changed back to failing a build on a
# finding; and one apostrophe put back into the awk program, which is not a contrived mutant but
# the defect this suite caught during the write: a single quote inside a single-quoted awk body
# ends it, and the script then dies with a shell syntax error on every input.
#
# One mutant is deliberately absent. A sha-equality branch for "the same commit addressed it" was
# written, and no input could reach it: a line whose last commit IS the commit that changed the
# path carries that commit timestamp, so the age test already decides it. It was removed rather
# than covered, because unreachable code that looks like a second rule is what this tree keeps
# finding in its own reviews.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SUT="$ROOT/scripts/check-doc-drift.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks()    { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1' in output)"; else ok "$3"; fi; }

[ -f "$SUT" ] || { echo "missing script: $SUT"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mkrepo() {  # mkrepo <name>: an empty repo with a fixed identity
  R="$T/$1"; rm -rf "$R"; mkdir -p "$R/scripts"
  git -C "$R" init -q
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name tester
  git -C "$R" config commit.gpgsign false
}
snap() {  # snap <date> <message>: commit everything at a fixed date
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$R" commit -q -m "$2"
}
sha() { git -C "$R" rev-parse "$1"; }
run() {  # run <args...>: capture rows, stderr and rc
  OUT="$(cd "$R" && bash "$SUT" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
}

# Two dates, far enough apart that no timezone reading of them can reorder the pair.
T1="2026-01-05T10:00:00+00:00"
T2="2026-06-05T10:00:00+00:00"

echo "== a document claim that lags the change it describes =="
mkrepo drift
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nThe guard is `scripts/guard.sh` and it does things.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "change the guard"; HEADSHA=$(sha HEAD)
run --range "$BASE..$HEADSHA" --docs README.md
expect "a stale claim exits 0, because this check reports and never fails" 0 "$RC"
expect "and prints exactly one row" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "README.md" "$OUT" "naming the document"
contains "scripts/guard.sh" "$OUT" "naming the path"
contains "$HEADSHA" "$OUT" "naming the sha of the commit that changed the path"
contains "	3	" "$OUT" "and the line number the claim sits on"

echo "== a claim updated in the same commit is not stale =="
mkrepo same
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nThe guard is `scripts/guard.sh` and it does things.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nThe guard is `scripts/guard.sh` and it now does other things.\n' > "$R/README.md"
snap "$T2" "change the guard and the line that describes it"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "the same-commit case exits 0" 0 "$RC"
expect "and prints nothing at all" "" "$OUT"

echo "== an unrelated edit to the document does not silence the claim =="
mkrepo unrelated
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nSome unrelated line.\n\nThe guard is `scripts/guard.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "commit A: change the guard only"; A=$(sha HEAD)
printf '# Doc\n\nSome unrelated line.  \n\nThe guard is `scripts/guard.sh`.\n' > "$R/README.md"
snap "$T2" "commit B: whitespace on an unrelated line"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "the row survives a later edit elsewhere in the document" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "$A" "$OUT" "and still names commit A, the one that changed the path"
expect "exit 0 either way" 0 "$RC"

echo "== an edit to the claiming line itself does silence it =="
mkrepo addressed
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nSome unrelated line.\n\nThe guard is `scripts/guard.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "commit A: change the guard only"
printf '# Doc\n\nSome unrelated line.\n\nThe guard is `scripts/guard.sh`, rewritten for the change.\n' > "$R/README.md"
snap "$T2" "commit B: address the claim on its own line"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an edit to the claiming line clears it" "" "$OUT"
expect "and exits 0" 0 "$RC"

echo "== a generated region is excluded by marker, and only inside it =="
mkrepo region
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\n<!-- component-index:start -->\n| `scripts/guard.sh` | a row nobody writes by hand |\n<!-- component-index:end -->\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "change the guard"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a claim inside a generated region is not reported" "" "$OUT"
expect "and that is not an error" 0 "$RC"
mkrepo region-and-prose
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nIn prose, the guard is `scripts/guard.sh`.\n\n<!-- component-index:start -->\n| `scripts/guard.sh` | a row nobody writes by hand |\n<!-- component-index:end -->\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "change the guard"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "the same path in prose outside the region IS reported, exactly once" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "	3	" "$OUT" "and the row is the prose line, not the region line"

echo "== the three region names this repository actually uses =="
for marker in plugin-catalogue component-index plugin-groups; do
  mkrepo "region-$marker"
  printf 'guard\n' > "$R/scripts/guard.sh"
  printf '# Doc\n\n<!-- %s:start -->\n`scripts/guard.sh`\n<!-- %s:end -->\n' "$marker" "$marker" > "$R/README.md"
  snap "$T1" "base"; BASE=$(sha HEAD)
  printf 'guard, changed\n' > "$R/scripts/guard.sh"
  snap "$T2" "change the guard"
  run --range "$BASE..$(sha HEAD)" --docs README.md
  expect "the $marker region is excluded" "" "$OUT"
done

echo "== a component NAME resolves through the catalogue, not a second path parser =="
mkrepo component
mkdir -p "$R/plugins/demo-group/skills/demo-skill" "$R/plugins/demo-group/.claude-plugin"
printf '<!-- demo-skill-version: 1 -->\nbody\n' > "$R/plugins/demo-group/skills/demo-skill/SKILL.md"
printf '{"name":"demo-group","version":"0.1.0","description":"d","author":{"name":"a"}}\n' > "$R/plugins/demo-group/.claude-plugin/plugin.json"
printf '# Doc\n\nThe `demo-skill` skill does the thing.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf '<!-- demo-skill-version: 2 -->\nbody, changed\n' > "$R/plugins/demo-group/skills/demo-skill/SKILL.md"
snap "$T2" "change the skill"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a claim naming a component rather than a path is reported" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "demo-skill" "$OUT" "and the row names it"
expect "exit 0" 0 "$RC"

echo "== unresolvable input REFUSES rather than reporting clean =="
mkrepo refuse
printf 'guard\n' > "$R/scripts/guard.sh"; printf '# Doc\n\n`scripts/guard.sh`\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
run --range "${BASE}..0000000000000000000000000000000000000000" --docs README.md
expect "a range naming an absent sha exits 2" 2 "$RC"
expect "with nothing on stdout" "" "$OUT"
contains "cannot resolve the range" "$ERR" "and says that is what went wrong, not something downstream of it"
run --range "$BASE..HEAD" --docs no-such-file.md
expect "a document absent at HEAD exits 2" 2 "$RC"
expect "with nothing on stdout either" "" "$OUT"
contains "no-such-file.md" "$ERR" "and names the document it could not find"
printf 'untracked\n`scripts/guard.sh`\n' > "$R/NOTES.md"
run --range "$BASE..HEAD" --docs NOTES.md
expect "an untracked document exits 2 rather than reporting it clean" 2 "$RC"
contains "NOTES.md" "$ERR" "and names it, loudly, because staleness has no meaning without history"
run --docs README.md
expect "a missing --range is a usage error, exit 2" 2 "$RC"
run --range "$BASE..HEAD"
expect "a missing --docs is a usage error, exit 2" 2 "$RC"

echo "== the sha reported is the NEWEST in-range commit touching the path =="
# A path changed twice in one range has two candidate shas, and the row must name the later one:
# the earlier one was already superseded inside the very range being reported on.
mkrepo newest
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# Doc\n\nThe guard is `scripts/guard.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed once\n' > "$R/scripts/guard.sh"
snap "2026-03-05T10:00:00+00:00" "first change"; FIRST=$(sha HEAD)
printf 'guard, changed twice\n' > "$R/scripts/guard.sh"
snap "$T2" "second change"; SECOND=$(sha HEAD)
run --range "$BASE..$SECOND" --docs README.md
expect "exactly one row, not one per commit" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "$SECOND" "$OUT" "naming the newest commit that touched the path"
lacks "$FIRST" "$OUT" "and not the one it superseded inside the same range"

echo "== several documents in one run =="
mkrepo many
printf 'guard\n' > "$R/scripts/guard.sh"
printf '# A\n\n`scripts/guard.sh`\n' > "$R/README.md"
printf '# B\n\n`scripts/guard.sh`\n' > "$R/GUIDE.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"
snap "$T2" "change the guard"
run --range "$BASE..$(sha HEAD)" --docs README.md,GUIDE.md
expect "both documents are read in one run" 2 "$(printf '%s' "$OUT" | grep -c .)"
contains "README.md" "$OUT" "the first is reported"
contains "GUIDE.md" "$OUT" "and so is the second"

echo "== a clean range says nothing and still exits 0 =="
mkrepo clean
printf 'guard\n' > "$R/scripts/guard.sh"; printf '# Doc\n\n`scripts/guard.sh`\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'unrelated\n' > "$R/scripts/other.sh"
snap "$T2" "touch a path no document claims"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "nothing on stdout" "" "$OUT"
expect "and exit 0, which is the same code a finding produces" 0 "$RC"

# --- #258: the allow-file, keyed on the TEXT of a claim rather than its line number -------------
#
# The noise is a per-LINE property. A path filter is per-PATH and provably cannot express the
# answer here: both noisy paths carry mentions AND claims. An in-document marker was chosen in
# round 1 and rejected in round 2 as UNPLACEABLE, because the marker must sit on its own line (an
# end-of-line one changes the claim line's content and blame then re-dates it, suppressing the row
# for the wrong reason) and every suppression site in this repository's README is a mid-sentence
# continuation line, where an HTML comment interrupts the paragraph under CommonMark.
#
# So the exemption lives in a file and is keyed on an ANCHOR, a substring of the claiming line.
# That is the house shape, it touches no document, and it is immune to the line moving, which is
# what broke round 1's acceptance criteria: they named line numbers, and the check blames HEAD, so
# inserting any line moved every row and a no-op satisfied them.

row_text() {  # the text of the lines $OUT names, and EMPTY when it names none.
  # `sed -n "p"` with no address prints the WHOLE file, so building this inline made every needle
  # match whenever $OUT was empty. The guard is the point, not the convenience.
  local ln acc=""
  for ln in $(printf '%s' "$OUT" | cut -f2); do
    case "$ln" in ''|*[!0-9]*) continue ;; esac
    acc="$acc$(git -C "$R" show HEAD:README.md | sed -n "${ln}p")"
  done
  printf '%s' "$acc"
}

allowrepo() {  # a repo whose README names the guard twice, once to be suppressed
  mkrepo "$1"
  printf 'guard\n' > "$R/scripts/guard.sh"
  printf '# Doc\n\nIn passing, `scripts/guard.sh` is mentioned here.\n\nThe guard `scripts/guard.sh` does exactly three things.\n' > "$R/README.md"
  snap "$T1" "base"; BASE=$(sha HEAD)
  printf 'guard, changed\n' > "$R/scripts/guard.sh"
  snap "$T2" "change the guard"
}
allow() { printf '%s\n' "$@" > "$R/.doc-drift-allow"; }

echo "== #258: an anchored mention is suppressed and an unanchored claim is not =="
allowrepo allow1
allow '# names the path in passing and claims nothing about it' 'mention README.md scripts/guard.sh In passing,'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an anchored line is suppressed" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "does exactly three things" "$(row_text)" "and the surviving row is the CLAIM, not the mention"
expect "and it exits 0" 0 "$RC"
rm -f "$R/.doc-drift-allow"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "removing the allow-file brings the row back, so the entry was the reason" 2 "$(printf '%s' "$OUT" | grep -c .)"

echo "== #258: the exemption survives the line moving, which a line number could not =="
allowrepo allow2
allow '# incidental' 'mention README.md scripts/guard.sh In passing,'
printf '%s\n' "prepended one" "prepended two" "prepended three" > "$R/pre.txt"
{ cat "$R/pre.txt"; git -C "$R" show HEAD:README.md; } > "$R/README.md"
snap "$T2" "prepend three lines, moving every line below"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "the anchored line is still suppressed after three lines were inserted above it" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "does exactly three things" "$(row_text)" "and the row that survives is still the claim"

echo "== #258: an anchor matching nothing is STALE, and does not block =="
allowrepo allow3
allow '# a reason' 'mention README.md scripts/guard.sh this text is nowhere in the document'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a stale entry exits 0" 0 "$RC"
expect "and suppresses nothing" 2 "$(printf '%s' "$OUT" | grep -c .)"
contains ".doc-drift-allow line 2: stale" "$ERR" "and says so on stderr, naming the entry"
# Range-independence is the whole point: round 1's rule was 'matches no ROW', which reported a live
# entry as stale on any range where its path happened not to change. So an entry whose anchor DOES
# match a line must never be called stale, even on an empty range that produces no rows at all.
allow '# a reason' 'mention README.md scripts/guard.sh In passing,'
run --range "$BASE..$BASE" --docs README.md
lacks ".doc-drift-allow line" "$ERR" "and a matching entry is never called stale, even on a range with no rows"

echo "== #258: an ambiguous anchor refuses rather than guessing which line was meant =="
allowrepo allow4
allow '# a reason' 'mention README.md scripts/guard.sh guard'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an anchor matching two lines exits 2" 2 "$RC"
expect "with nothing on stdout" "" "$OUT"
contains "more than one line" "$ERR" "and says what is ambiguous"
allow '# a reason' 'mention README.md scripts/guard.sh The guard `scripts/guard.sh` does'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "lengthening the anchor to match one line resolves it" 0 "$RC"

echo "== #258: a malformed entry refuses the whole run =="
allowrepo allow5
allow '# a reason' 'suppress README.md scripts/guard.sh In passing,'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an unknown key exits 2" 2 "$RC"
contains "unknown key" "$ERR" "naming the key"
allow 'mention README.md scripts/guard.sh In passing,'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an entry with no reason above it exits 2" 2 "$RC"
contains "reason" "$ERR" "and says a reason is required"
allow '# a reason' 'mention README.md'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an entry missing its anchor exits 2" 2 "$RC"

echo "== #258: the anchor is LITERAL text, not a pattern =="
(
  # `.` is a regex metacharacter. An anchor of `guard.sh` read as a pattern also matches `guardXsh`,
  # which makes it ambiguous and refuses a run that should have worked.
  mkrepo literal
  printf 'guard\n' > "$R/scripts/guard.sh"
  printf '# Doc\n\nThe file `scripts/guard.sh` does things.\n\nUnrelated prose mentioning guardXsh here.\n' > "$R/README.md"
  snap "$T1" "base"; BASE=$(sha HEAD)
  printf 'guard, changed\n' > "$R/scripts/guard.sh"
  snap "$T2" "change it"
  # Anchor `guard.sh`. Literally it matches line 3 alone. As a PATTERN the `.` matches any
  # character, so it also matches `guardXsh` on line 5, which makes it ambiguous and refuses.
  printf '%s\n' '# a reason' 'mention README.md scripts/guard.sh guard.sh' > "$R/.doc-drift-allow"
  out="$(cd "$R" && bash "$SUT" --range "$BASE..$(sha HEAD)" --docs README.md 2>"$T/lit.err")"; rc=$?
  [ "$rc" = 0 ] || exit 1
  [ -z "$out" ] || exit 2
  exit 0
)
case $? in
  0) ok "an anchor containing a regex metacharacter is matched literally and suppresses its row";;
  1) bad "the literal anchor was read as a pattern and the run refused";;
  2) bad "the literal anchor did not suppress its row";;
  *) bad "the literal-anchor case errored";;
esac

echo "== #258: an exemption is per PATH, not per line =="
(
  # One line can claim things about two paths. Exempting one must not silence the other.
  mkrepo perpath
  printf 'a\n' > "$R/scripts/guard.sh"; printf 'b\n' > "$R/scripts/other.sh"
  printf '# Doc\n\nBoth `scripts/guard.sh` and `scripts/other.sh` are described on this one line.\n' > "$R/README.md"
  snap "$T1" "base"; BASE=$(sha HEAD)
  printf 'a2\n' > "$R/scripts/guard.sh"; printf 'b2\n' > "$R/scripts/other.sh"
  snap "$T2" "change both"
  printf '%s\n' '# a reason' 'mention README.md scripts/guard.sh described on this one line' > "$R/.doc-drift-allow"
  out="$(cd "$R" && bash "$SUT" --range "$BASE..$(sha HEAD)" --docs README.md 2>/dev/null)"
  [ "$(printf '%s' "$out" | grep -c .)" = 1 ] || exit 1
  printf '%s' "$out" | grep -q 'scripts/other.sh' || exit 2
  printf '%s' "$out" | grep -q 'scripts/guard.sh' && exit 3
  exit 0
)
case $? in
  0) ok "exempting one path on a shared line leaves the other path's row standing";;
  1) bad "the wrong number of rows survived a shared line";;
  2) bad "the unexempted path lost its row";;
  3) bad "the exempted path kept its row";;
  *) bad "the per-path case errored";;
esac

echo "== #258: no allow-file, and an empty one, change nothing =="
allowrepo allow6
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "with no allow-file both rows are printed" 2 "$(printf '%s' "$OUT" | grep -c .)"
expect "and it exits 0" 0 "$RC"
allow '# only a comment, no entries'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an allow-file of comments alone suppresses nothing" 2 "$(printf '%s' "$OUT" | grep -c .)"
expect "and is not read as suppress-everything" 0 "$RC"

echo "== #258: this repository's own three ranges, asserted on TEXT and never on a line number =="
# Round 1's criteria named line numbers. check-doc-drift blames HEAD, so inserting any line moves
# every row below it, and a no-op satisfied them.
#
# EVERY RANGE CARRIES A POSITIVE CONTROL, which the first version of this block did not. It checked
# only that certain texts were ABSENT, discarded the exit status and stderr, and looked at nothing
# else, so a script that printed nothing at all scored ok on every assertion. A review mutant that
# broke the script outright kept six of nine green. An absence assertion with no matching presence
# assertion beside it is not a test.
ranges_expect() {  # ranges_expect <range> <expected-row-count> <claim-anchor-that-must-survive>
  local r="$1" n="$2" keep="$3" out rc txt ln
  out="$(cd "$ROOT" && bash "$SUT" --range "$r" --docs README.md 2>/dev/null)"; rc=$?
  expect "range ${r%%..*} exits 0" 0 "$rc"
  expect "range ${r%%..*} reports exactly $n row(s)" "$n" "$(printf '%s' "$out" | grep -c .)"
  txt=""
  for ln in $(printf '%s' "$out" | cut -f2); do
    txt="$txt$(git -C "$ROOT" show HEAD:README.md | sed -n "${ln}p")"
  done
  case "$txt" in *"$keep"*) ok "range ${r%%..*} still reports the claim '$keep'" ;;
                 *) bad "range ${r%%..*} lost the claim '$keep'" ;; esac
  RANGE_TXT="$txt"
}
ranges_expect f15dd74e..106a4531 3 'The canonical rules'
for a in 'canonical ready-ticket rules' 'what is being worked on now'; do
  case "$RANGE_TXT" in *"$a"*) ok "range 1 still reports the claim '$a'" ;; *) bad "range 1 lost the claim '$a'" ;; esac
done
for a in 'block-dashes` hook stays dormant' 'the group stays inert' 'you copy the issue templates'; do
  case "$RANGE_TXT" in *"$a"*) bad "range 1 still reports the mention anchored by '$a'" ;; *) ok "range 1 no longer reports '$a'" ;; esac
done
for r in 106a4531..9416a77b 9416a77b..c15150c4; do
  ranges_expect "$r" 1 'what is being worked on now'
  # Only the two roadmap mentions exist in these ranges; the ticket-standards one does not, so
  # asserting its absence here would pass whatever the code did.
  for a in 'block-dashes` hook stays dormant' 'the group stays inert'; do
    case "$RANGE_TXT" in *"$a"*) bad "range ${r%%..*} still reports the mention anchored by '$a'" ;;
                         *) ok "range ${r%%..*} no longer reports '$a'" ;; esac
  done
done

echo "== #258: the reason is required PER ENTRY, not once per block =="
allowrepo reason2
allow '# one reason' 'mention README.md scripts/guard.sh In passing,' 'mention README.md scripts/guard.sh does exactly three things'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a second entry cannot inherit the first entry's reason" 2 "$RC"
contains "needs a reason" "$ERR" "and says a reason is needed"
allow '# one reason' 'mention README.md scripts/guard.sh In passing,' '' '# another reason' 'mention README.md scripts/guard.sh does exactly three things'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "two entries each with their own reason are both accepted" 0 "$RC"
expect "and both rows are suppressed" "" "$OUT"

echo "== #258: an EMPTY field refuses, and an empty anchor never suppresses everything =="
allowrepo empties
allow '# r' 'mention README.md scripts/guard.sh '
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a trailing space leaves an empty anchor, which refuses" 2 "$RC"
contains "missing its anchor" "$ERR" "naming what is missing"
allow '# r' 'mention  README.md scripts/guard.sh In passing,'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an empty document field refuses" 2 "$RC"
allow '# r' 'mention README.md  scripts/guard.sh In passing,'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an empty path field refuses" 2 "$RC"
(
  # The dangerous shape: an empty anchor matches EVERY line under grep -F, so on a one-line
  # document it silently suppressed the row instead of refusing.
  mkrepo oneline
  printf 'guard\n' > "$R/scripts/guard.sh"
  printf 'Only this one line names `scripts/guard.sh` here.\n' > "$R/README.md"
  snap "$T1" "base"; BASE=$(sha HEAD)
  printf 'guard2\n' > "$R/scripts/guard.sh"; snap "$T2" "change"
  printf '%s\n' '# r' 'mention README.md scripts/guard.sh ' > "$R/.doc-drift-allow"
  out="$(cd "$R" && bash "$SUT" --range "$BASE..$(sha HEAD)" --docs README.md 2>/dev/null)"; rc=$?
  [ "$rc" = 2 ] || exit 1
  [ -z "$out" ] || exit 2
  exit 0
)
case $? in
  0) ok "an empty anchor refuses on a ONE-LINE document too, where it used to suppress silently";;
  1) bad "the one-line document did not refuse";;
  2) bad "the one-line document printed rows";;
  *) bad "the one-line case errored";;
esac

echo "== #258: an explicitly named allow-file that cannot be read REFUSES =="
allowrepo explicit
run --range "$BASE..$(sha HEAD)" --docs README.md --allow-file no/such/file
expect "a missing explicit allow-file exits 2" 2 "$RC"
expect "with nothing on stdout" "" "$OUT"
contains "no such allow-file" "$ERR" "naming the path it could not read"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "while an ABSENT default is still skipped in silence" 0 "$RC"
expect "and reports every row" 2 "$(printf '%s' "$OUT" | grep -c .)"

echo "== #258: --help reaches the usage line =="
helpout="$(cd "$ROOT" && bash "$SUT" --help 2>&1)"
contains "Usage: check-doc-drift.sh" "$helpout" "--help prints the usage line the header grew past"
contains "--allow-file" "$helpout" "and documents the flag this ticket added"

echo "== portability: this runs on a bash 3.2 laptop with BSD tools =="
# CODE lines only. The header names every banned tool on purpose, to say it is not used, and a flat
# grep would fail the script for documenting its own portability floor.
CODE="$(grep -v '^[[:space:]]*#' "$SUT")"
expect "no bash-4 case expansion" 0 "$(printf '%s\n' "$CODE" | grep -cE '\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}')"
expect "no associative arrays" 0 "$(printf '%s\n' "$CODE" | grep -c 'declare -A')"
expect "no GNU readlink -f" 0 "$(printf '%s\n' "$CODE" | grep -c 'readlink -f')"
expect "no GNU timeout" 0 "$(printf '%s\n' "$CODE" | grep -cE '(^|[^-[:alnum:]])timeout ')"
expect "no grep -P" 0 "$(printf '%s\n' "$CODE" | grep -cE 'grep [^|]*-[A-Za-z]*P')"
lacks "date -d" "$CODE" "no GNU date -d, which BSD date spells differently"
expect "the header states the residual limit of the line-level rule" 0 "$(grep -qi 'reflow' "$SUT"; echo $?)"
expect "and the residual limit of the exemptions beside it" 0 "$(grep -qi 'THE EXEMPTIONS HAVE THEIR OWN LIMITS' "$SUT"; echo $?)"
expect "and names the three marker regions somebody else owns" 3 "$(grep -o 'plugin-catalogue\|component-index\|plugin-groups' "$SUT" | sort -u | grep -c .)"

echo "check-doc-drift tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
