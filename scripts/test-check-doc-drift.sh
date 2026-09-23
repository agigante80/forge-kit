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
expect "and names the three marker regions somebody else owns" 3 "$(grep -o 'plugin-catalogue\|component-index\|plugin-groups' "$SUT" | sort -u | grep -c .)"

echo "check-doc-drift tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
