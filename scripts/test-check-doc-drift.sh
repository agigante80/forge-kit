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
# MUTANTS KILLED, the first ten run by hand on 2026-09-23 and each shown to fail this suite: the
# marker-region exclusion dropped; the line-level comparison relaxed to document level; the
# newest-in-range selection changed to oldest; the age comparison inverted; the untracked-document
# refusal turned into a skip; the absent-document refusal turned into a skip; the range validation
# dropped; the component-name resolution dropped; the posture changed back to failing a build on a
# finding; and one apostrophe put back into the awk program, which is not a contrived mutant but
# the defect this suite caught during the write: a single quote inside a single-quoted awk body
# ends it, and the script then dies with a shell syntax error on every input.
#
# #265 ADDED FOUR MORE, run by hand on 2026-10-01, each shown to fail this suite (so fourteen in
# all): the equal-anchor comparison reverted from $_rest to $_path (4 failures); the CR strip
# deleted (12); the CR strip moved AFTER the blank/comment case, which only the blank-line fixtures
# kill because a no-blank CRLF file never reaches a blank line (9, and the no-blank fixtures still
# pass); and the anchor check loosened to emptiness alone, which accepts a missing fourth field
# and is killed only by the L1 missing-anchor negative (4).
#
# #332 ADDED TEN MORE for the bare-filename resolution, run by hand on 2026-10-01, each shown to
# fail this suite: an ambiguous token resolved to its first candidate (10 failures); the bare lookup
# disabled (16); the scripts/ half dropped (10); the asset half dropped (15); the ambiguity line
# printed per mention instead of once (1); the ambiguity line made to depend on the range (8); the
# line's text corrupted (4); its path list cut to the last candidate (2); a bare-name table hit
# allowed to override a changed root-level path of the same name (1); and the report-only posture
# changed to exit 1 on a finding (16). Two candidate mutants were EQUIVALENT and the code was
# simplified instead: the `continue` after the ambiguity line (the empty path is skipped on the
# next line anyway) and a `/` test on the token (a table key never holds one). A sort of the table
# was dropped for the same reason: the catalogue's order already puts plugins/ before scripts/.
#
# #354 ADDED SEVEN MORE (so thirty-one in all), run by hand on 2026-10-01, each shown to fail this
# suite. (a) the not-found warning removed (3 failures); (b) the guard moved so it fires without the
# `-d plugins` test (2); (c) the script directory resolved after the --root cd again, a bare
# `dirname "$0"` (5); (d) the failing-catalogue warning removed so a non-zero catalogue is silent
# again (1); (e) an empty-output catalogue treated as failed, `|| [ ! -s cat.tsv ]` (1); (f) the
# CDPATH-safe `CDPATH= cd --` reverted to a bare `cd` (2); (g) the not-found warning printed before
# the documents are validated (the not-found printf moved above the validation loop and silenced in
# its old place), so a refused run still warns (1, re-measured in the #354 round-2 review). The
# first ten ran on 2026-09-23, four more under #265 and ten under #332, both on 2026-10-01.
#
# #372 ADDED SEVEN MORE (so thirty-eight in all), run by hand on 2026-10-01 in a scratch copy, each
# shown to fail this suite. (a) the ambiguity exit, `; exit 1` after the ambiguity printf (3
# failures, the three bare-dup full-path assertions), and the same exit placed after the `warned`
# block's closing brace (also 3), which are two runs of ONE mutant, so the count of seven counts
# mutants and not runs; (b) the ANCHORED regex lookup, `tok ~ ("^" k "$")` with `.` in the
# key a wildcard, which SURVIVED the pre-#372 suite (224 passed, 0 failed) because `demo-assetXsh`
# has no `demo-asset.sh` to miss, and dies after the near-miss became `demo-checkXsh` (2); (c) M3,
# the token expanded through a shell or a git pathspec: the bare lookup becomes
# `"git ls-files -- \"scripts/" tok "\"" | getline` with NO .sh suffix guard, which is the only
# shape meta-subst-unresolved kills because its token `$(touch pwned-two)` has no .sh (see the
# literal edit below; 15 failures, among them meta-subst, meta-subst-unresolved and
# meta-glob-absent); (d) the reverse regex, `k ~ tok`, killed by meta-glob-literal's column 4 (see
# the literal edit below; 7 failures); (e) the program name put back to the
# literal "check-doc-drift" in the ambiguity printf (2, the PROG scratch copy); (f) the root-level
# exception sentence reworded so it no longer says "resolves only when the range changed it" (1);
# and (g) the printed sha taken from a path other than the resolved one (5, the three live-range
# column-4 pins among them). The anchored regex run is by-hand evidence only: no committed test
# builds a mutant.
#
# #382 RECORDS THE LITERAL EDITS for (c) and (d) above, measured against the suite as it stood
# before the #382 rows (measured at 5363792), under GNU Awk 5.2.1. Each is
# applied to scripts/check-doc-drift.sh in a scratch copy.
#  (c) INSERT, immediately above the awk line `if (path == "" && tok in bn) {`, this one line:
#      if (path == "") { cmd = "git ls-files -- \"scripts/" tok "\""; if ((cmd | getline lf) > 0) path = lf; close(cmd) }
#      15 failures (17 against the suite with the #382 rows). The PLACEMENT matters: the same line
#      put directly above `if (path == "") continue`, as a fallback, gives 6 failures, because a
#      token the table already resolved never reaches it: meta-subst PASSES (it survives), and only
#      meta-subst-unresolved and meta-glob-absent fail, with the four bare-dup rows still green.
#  (d) REPLACE the two awk lines `if (path == "" && tok in bn) {` and
#      `if (bn[tok] == 1) path = bfirst[tok]` with these three:
#      lk = ""; if (path == "") for (k in bn) if (k ~ tok) lk = k
#      if (path == "" && lk != "") {
#      if (bn[lk] == 1) path = bfirst[lk]
#      7 failures: meta-subst's two rows, meta-glob-literal's column 4, meta-glob-absent's two, and
#      the live-range forge-lib.sh column-4 pins of ranges f15dd74e and 9416a77b. The last two read
#      HEAD's README, so the count can move with it. The earlier figure of 6 did not reproduce.
#
# #308 ADDED THREE (so forty-one in all), run by hand on 2026-10-01 in a scratch copy, shown to
# fail this suite: the path-split guard removed, leaving `_rest="${_rest#* }"` unguarded, so a
# document with no path field is reused as the path and refuses as "missing its anchor" (2
# failures, the bare entry's path-message and no-anchor-message pins). Two more by-hand mutants
# kill the rest of the new cases: the pre-existing empty-path die reworded to the anchor message
# (2, the trailing-space pair), and the new guard printing a line to stdout before dying (1, the
# empty-stdout pin).
#
# #382 ADDED TWO MORE (so forty-three in all: the last paragraph's total plus two), run by hand on
# 2026-10-01 in a scratch copy, each measured under GNU Awk 5.2.1 against the suite as it stood
# before the #382 rows (at 5363792) and against the suite with them. The ambiguity branch run
# even when a changed root path already won, the awk edit `if (path == "" && tok in bn) {` to
# `if (tok in bn) {` and `if (bn[tok] == 1) path = bfirst[tok]` to
# `if (bn[tok] == 1) { if (path == "") path = bfirst[tok] }`: 0 failures before, 2 after (the
# bare-root-dup one-row-summary row and its range-3 no-ambiguity row). And the `[ -n "$2" ] && `
# guard deleted from col4_is: 0 failures before, 1 after (the empty-sha control).
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

echo "== #354: a missing or failing catalogue is said so, never silently skipped =="
# run() always executes the absolute $SUT, so these build their own copy directory OUTSIDE the
# fixture repo and capture OUT, ERR and RC the way run() does. cdoc <dir> <args...> runs from <dir>.
NF_MSG="check-doc-drift: forge-adapt-catalogue.sh not found beside the script; component-name claims were not checked"
FL_MSG="check-doc-drift: forge-adapt-catalogue.sh failed; component-name claims were not checked"
cdoc() {
  _d="$1"; shift
  OUT="$(cd "$_d" && bash "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
}
nlines() { printf '%s\n' "$2" | grep -cF -- "$1"; }
cpdir() {  # cpdir <name> <with-catalogue 0|1|stub>: D/scripts holding the script copy
  D="$T/$1"; rm -rf "$D"; mkdir -p "$D/scripts"
  cp "$SUT" "$D/scripts/check-doc-drift.sh"
  case "$2" in
    1) cp "$ROOT/scripts/forge-adapt-catalogue.sh" "$D/scripts/" ;;
    stub) printf '#!/usr/bin/env bash\nexit 3\n' > "$D/scripts/forge-adapt-catalogue.sh" ;;
  esac
}
mkrepo cat354
mkdir -p "$R/plugins/demo-group/skills/demo-skill" "$R/plugins/demo-group/.claude-plugin"
printf '<!-- demo-skill-version: 1 -->\nbody\n' > "$R/plugins/demo-group/skills/demo-skill/SKILL.md"
printf '{"name":"demo-group","version":"0.1.0","description":"d","author":{"name":"a"}}\n' > "$R/plugins/demo-group/.claude-plugin/plugin.json"
printf '# Doc\n\nThe `demo-skill` skill does the thing.\n\nThe tool is `scripts/tool.sh` here.\n' > "$R/README.md"
printf '#!/usr/bin/env bash\n' > "$R/scripts/tool.sh"
snap "$T1" "base"; B354=$(sha HEAD)
printf 'body, changed\n' >> "$R/plugins/demo-group/skills/demo-skill/SKILL.md"
printf '# changed\n' >> "$R/scripts/tool.sh"
snap "$T2" "change both"
RG="$B354..$(sha HEAD)"
SUMLINE="check-doc-drift: 1 suspected stale claim(s) across the documents given."

# Condition A: the catalogue absent beside a copy, tree has plugins/.
cpdir a354 0
cdoc "$R" "$D/scripts/check-doc-drift.sh" --range "$RG" --docs README.md
expect "catalogue missing warns exactly once" 1 "$(nlines "$NF_MSG" "$ERR")"
expect "and exit stays 0" 0 "$RC"
lacks "demo-skill" "$OUT" "and the component row is absent"
expect "while the path row still prints" 1 "$(printf '%s' "$OUT" | grep -c .)"
contains "scripts/tool.sh" "$OUT" "and it names the path"
expect "and the summary is still the last stderr line" "$SUMLINE" "$(printf '%s\n' "$ERR" | tail -n 1)"
lacks "failed" "$ERR" "and the failed message does not appear"
# Positive control: the real catalogue beside the copy.
cpdir a354p 1
cdoc "$R" "$D/scripts/check-doc-drift.sh" --range "$RG" --docs README.md
expect "catalogue present: component and path rows" 2 "$(printf '%s' "$OUT" | grep -c .)"
contains "demo-skill" "$OUT" "the component row names demo-skill"
lacks "not found beside the script" "$ERR" "no not-found warning"
lacks "failed" "$ERR" "no failed warning"
expect "exit 0" 0 "$RC"
# Several documents still warn once.
printf '# Two\n\nSee `scripts/tool.sh` too.\n' > "$R/OTHER.md"; snap "$T1" "other"
RG2="$B354..$(sha HEAD)"
cdoc "$R" "$T/a354/scripts/check-doc-drift.sh" --range "$RG2" --docs README.md,OTHER.md
expect "two documents still warn exactly once" 1 "$(nlines "$NF_MSG" "$ERR")"

# Condition B: no plugins/ directory stays silent.
mkrepo np354
printf '# Doc\n\nThe tool is `scripts/tool.sh` here.\n' > "$R/README.md"
printf '#!/usr/bin/env bash\n' > "$R/scripts/tool.sh"
snap "$T1" "base"; NB=$(sha HEAD)
printf '# changed\n' >> "$R/scripts/tool.sh"; snap "$T2" "change tool"
cpdir b354 0
cdoc "$R" "$D/scripts/check-doc-drift.sh" --range "$NB..$(sha HEAD)" --docs README.md
expect "no plugins/ dir: not-found warning absent" 0 "$(nlines "not found beside the script" "$ERR")"
expect "one path row for scripts/tool.sh" 1 "$(printf '%s' "$OUT" | grep -c 'scripts/tool.sh')"
expect "stderr is exactly the summary line" "$SUMLINE" "$ERR"
expect "exit 0" 0 "$RC"

# Condition C: a RELATIVE script path plus --root, run from outside the fixture repo.
cpdir c354 1
R354="$T/cat354"
cdoc "$D" scripts/check-doc-drift.sh --root "$R354" --range "$RG" --docs README.md
expect "relative path + --root, catalogue beside: component row found" 2 "$(printf '%s' "$OUT" | grep -c .)"
contains "demo-skill" "$OUT" "the row names demo-skill"
lacks "not found beside the script" "$ERR" "and no false not-found warning"
expect "exit 0" 0 "$RC"
cpdir c354n 0
cdoc "$D" scripts/check-doc-drift.sh --root "$R354" --range "$RG" --docs README.md
expect "relative path + --root, catalogue absent: warns exactly once" 1 "$(nlines "$NF_MSG" "$ERR")"
lacks "demo-skill" "$OUT" "and no component row"
expect "exit 0" 0 "$RC"

# Condition D: a catalogue that exists but exits non-zero.
cpdir d354 stub
cdoc "$R354" "$D/scripts/check-doc-drift.sh" --range "$RG" --docs README.md
expect "failing catalogue warns exactly once" 1 "$(nlines "$FL_MSG" "$ERR")"
lacks "not found beside the script" "$ERR" "and the not-found message does not appear"
lacks "demo-skill" "$OUT" "and no component row"
expect "exit 0" 0 "$RC"
expect "summary still last" "$SUMLINE" "$(printf '%s\n' "$ERR" | tail -n 1)"
cpdir d354np stub
cdoc "$T/np354" "$D/scripts/check-doc-drift.sh" --range "$NB..$(cd "$T/np354" && git rev-parse HEAD)" --docs README.md
lacks "failed" "$ERR" "a failing catalogue with no plugins/ dir stays silent"
expect "and that run exits 0" 0 "$RC"
expect "and stderr is exactly the summary line" "$SUMLINE" "$ERR"

# Condition E: a catalogue that exists, exits 0 and prints nothing (empty plugins/) is neither
# missing nor failed: no warning of either kind, rc 0, stderr exactly the summary line.
mkrepo em354
mkdir -p "$R/plugins/empty"
printf '# Doc\n\nThe tool is `scripts/tool.sh` here.\n' > "$R/README.md"
printf '#!/usr/bin/env bash\n' > "$R/scripts/tool.sh"
snap "$T1" "base"; EB=$(sha HEAD)
printf '# changed\n' >> "$R/scripts/tool.sh"; snap "$T2" "change tool"
cpdir e354 1
cdoc "$R" "$D/scripts/check-doc-drift.sh" --range "$EB..$(sha HEAD)" --docs README.md
expect "an empty-output catalogue exits 0" 0 "$RC"
expect "and stderr is exactly the summary line" "$SUMLINE" "$ERR"
expect "and the path row still prints" 1 "$(printf '%s' "$OUT" | grep -c 'scripts/tool.sh')"

# Condition F: a refused run (exit 2) prints no catalogue warning and never runs the catalogue.
cpdir f354 0
printf '# Untracked\n' > "$R354/UNTRACKED.md"
cdoc "$R354" "$D/scripts/check-doc-drift.sh" --range "$RG" --docs README.md,UNTRACKED.md
expect "an untracked doc is refused with rc 2" 2 "$RC"
lacks "component-name claims were not checked" "$ERR" "and no catalogue warning is printed on a refused run"
cpdir f354s stub
cdoc "$R354" "$D/scripts/check-doc-drift.sh" --range "$RG" --docs README.md,UNTRACKED.md
expect "a refused run with a failing catalogue is rc 2" 2 "$RC"
lacks "component-name claims were not checked" "$ERR" "and prints no failed warning either"
rm -f "$R354/UNTRACKED.md"

# Condition G: an exported CDPATH must not corrupt the script directory (cd would echo it).
cpdir g354 1
OUT="$(cd "$D" && CDPATH="$T:$D:." bash scripts/check-doc-drift.sh --root "$R354" --range "$RG" --docs README.md 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"
expect "CDPATH exported: exit 0" 0 "$RC"
lacks "not found beside the script" "$ERR" "and no false not-found warning"
contains "demo-skill" "$OUT" "and the component row is found"

echo "== #332: a bare <name>.sh resolves to a shipped asset or a tracked scripts/ file, and refuses to guess on a collision =="
# Fixture builders. A group needs its plugin.json and one skill for the catalogue to list its asset.
bare_group() {  # bare_group <group> <asset-basename>: a group with one skill carrying that asset
  mkdir -p "$R/plugins/$1/skills/$1-skill/assets" "$R/plugins/$1/.claude-plugin"
  printf '<!-- %s-skill-version: 1 -->\nbody\n' "$1" > "$R/plugins/$1/skills/$1-skill/SKILL.md"
  printf '{"name":"%s","version":"0.1.0","description":"d","author":{"name":"a"}}\n' "$1" > "$R/plugins/$1/.claude-plugin/plugin.json"
  printf '#!/usr/bin/env bash\n# %s-version: 1\n' "${2%.sh}" > "$R/plugins/$1/skills/$1-skill/assets/$2"
}
bare_touch() { printf '# changed\n' >> "$1"; }
rows() { printf '%s' "$OUT" | grep -c .; }
ZERO="check-doc-drift: 0 suspected stale claim(s) across the documents given."

# Condition A: a shipped asset's bare filename.
mkrepo bare-asset
bare_group demo-group demo-asset.sh
printf '# Doc\n\nThe asset is `demo-asset.sh` here.\n\nThe same by catalogue name: `demo-asset`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/plugins/demo-group/skills/demo-group-skill/assets/demo-asset.sh"
snap "$T2" "change the asset"; HEADSHA=$(sha HEAD)
run --range "$BASE..$HEADSHA" --docs README.md
expect "a bare asset filename and the same asset by catalogue name yield one row each" 2 "$(rows)"
contains "	3	demo-asset.sh	" "$OUT" "the bare token's row names it and its line"
contains "	5	demo-asset	" "$OUT" "and the catalogue-name row is unchanged beside it"
contains "$HEADSHA" "$OUT" "and the commit that changed the asset"
expect "exit 0" 0 "$RC"
mkrepo bare-asset-neg
bare_group demo-group demo-asset.sh
printf '# Doc\n\nThe asset is `demo-asset.sh` here.\n' > "$R/README.md"; printf 'x\n' > "$R/other.txt"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'y\n' > "$R/other.txt"; snap "$T2" "touch only a file the README does not cite"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a commit that touches only an uncited file reports nothing" "" "$OUT"
expect "with exactly the zero-claims summary on stderr" "$ZERO" "$ERR"
expect "and exit 0" 0 "$RC"

# Condition B: a repo-only scripts/ file's bare filename.
mkrepo bare-script
printf 'x\n' > "$R/scripts/demo-check.sh"
printf '# Doc\n\nRun `demo-check.sh` first, and `demo-missing.sh` never.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/demo-check.sh"; snap "$T2" "change the script"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a bare repo-only script filename yields exactly one row" 1 "$(rows)"
contains "demo-check.sh" "$OUT" "naming it"
lacks "demo-missing.sh" "$OUT" "and a bare name matching nothing yields no row"
lacks "ambiguous" "$ERR" "nor an ambiguity line"
expect "exit 0" 0 "$RC"
mkrepo bare-none
printf 'x\n' > "$R/scripts/demo-check.sh"
printf '# Doc\n\nRun `demo-missing.sh`, `demo-checkXsh` and `demo-check.shx`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/demo-check.sh"; snap "$T2" "change the script"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a missing name and two near-miss spellings yield no row" "" "$OUT"
expect "stderr is exactly the zero-claims summary, with no ambiguity line" "$ZERO" "$ERR"
expect "exit 0" 0 "$RC"

# Condition C: a collision, asset against scripts/ file, and then two assets in two groups.
mkrepo bare-dup
bare_group demo-group demo-dup.sh
printf 'x\n' > "$R/scripts/demo-dup.sh"
printf '# Doc\n\nBare: `demo-dup.sh`.\n\nFull: `scripts/demo-dup.sh`.\n\nBare again: `demo-dup.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/plugins/demo-group/skills/demo-group-skill/assets/demo-dup.sh"
snap "$T2" "change the asset"; DUP_ASSET=$(sha HEAD)
run --range "$BASE..$DUP_ASSET" --docs README.md
expect "a bare name matching an asset and a scripts/ file yields no row" "" "$OUT"
contains "ambiguous bare name 'demo-dup.sh'" "$ERR" "and stderr names the token"
contains "plugins/demo-group/skills/demo-group-skill/assets/demo-dup.sh" "$ERR" "and the asset path"
contains "scripts/demo-dup.sh" "$ERR" "and the scripts/ path"
contains "cite the full path" "$ERR" "and says what to do"
expect "exit 0, ambiguity never fails" 0 "$RC"
bare_touch "$R/scripts/demo-dup.sh"; snap "$T2" "change the scripts/ file"; DUP_SCRIPT=$(sha HEAD)
run --range "$DUP_ASSET..$DUP_SCRIPT" --docs README.md
expect "the full path in the same document still yields exactly one row" 1 "$(rows)"
contains "scripts/demo-dup.sh" "$OUT" "naming the full path"
contains "$DUP_SCRIPT" "$OUT" "and the commit that changed it"
contains "ambiguous bare name 'demo-dup.sh'" "$ERR" "while the bare token is still refused beside it"
printf 'z\n' > "$R/other.txt"; snap "$T2" "change neither candidate"
run --range "$DUP_SCRIPT..$(sha HEAD)" --docs README.md
expect "ambiguity does not depend on the range: a range changing neither candidate yields no row" "" "$OUT"
contains "ambiguous bare name 'demo-dup.sh'" "$ERR" "and still prints the ambiguity line"
expect "once, not once per mention" 1 "$(printf '%s\n' "$ERR" | grep -c 'ambiguous bare name')"
# #372: the program name in the ambiguity line comes from $PROG. A scratch copy with PROG edited is
# the only way to see it; the edit fails loudly when its anchor matches nothing.
cpdir prog372 1
sed 's/^PROG="check-doc-drift"$/PROG="renamed-drift"/' "$D/scripts/check-doc-drift.sh" > "$D/scripts/renamed.tmp"
if cmp -s "$D/scripts/renamed.tmp" "$D/scripts/check-doc-drift.sh"; then
  bad "the PROG= edit changed nothing: its anchor no longer matches, so the two checks below are not run"
else
  mv "$D/scripts/renamed.tmp" "$D/scripts/check-doc-drift.sh"
  cdoc "$R" "$D/scripts/check-doc-drift.sh" --range "$DUP_SCRIPT..$(sha HEAD)" --docs README.md
  contains "renamed-drift: ambiguous bare name 'demo-dup.sh'" "$ERR" "the ambiguity line carries the program name from PROG"
  lacks "check-doc-drift: ambiguous" "$ERR" "and no line still carries the literal name"
fi
mkrepo bare-dup-assets
bare_group group-one demo-twin.sh; bare_group group-two demo-twin.sh
printf '# Doc\n\nTwice shipped: `demo-twin.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/plugins/group-one/skills/group-one-skill/assets/demo-twin.sh"; snap "$T2" "change one"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "two assets in different groups sharing a basename yield no row" "" "$OUT"
contains "plugins/group-one/skills/group-one-skill/assets/demo-twin.sh, plugins/group-two/skills/group-two-skill/assets/demo-twin.sh" "$ERR" "and stderr names both paths, in catalogue order"
expect "exit 0" 0 "$RC"

# A token carrying a path separator takes the existing full-path route and is never checked for ambiguity.
mkrepo bare-sep
printf 'x\n' > "$R/scripts/demo-check.sh"
printf '# Doc\n\nFull: `scripts/demo-check.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/demo-check.sh"; snap "$T2" "change the script"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a path-separator token yields one row by the full-path route" 1 "$(rows)"
lacks "ambiguous" "$ERR" "with no ambiguity line"

# A changed file at the repository root that is itself named by the bare token wins over the table.
mkrepo bare-root
printf 'x\n' > "$R/demo-root.sh"; printf 'x\n' > "$R/scripts/demo-root.sh"
printf '# Doc\n\nRoot script: `demo-root.sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/demo-root.sh"; snap "$T2" "change the root file"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a token that is itself a changed path keeps resolving to it, ahead of the bare-name table" 1 "$(rows)"
# #372, Option A: the root-level exception is range dependent by design and the header says so.
if grep -qF -- 'resolves only when the range changed it' "$SUT"; then ok "the script header states the root-level, range-dependent exception"; else bad "the script header lacks the root-level exception sentence"; fi
ROOT_HEAD=$(sha HEAD)
printf 'z\n' > "$R/other.txt"; snap "$T2" "change neither root candidate"
run --range "$ROOT_HEAD..$(sha HEAD)" --docs README.md
expect "a later range that did not change the root file yields no row" "" "$OUT"
expect "with exactly the zero-claims summary and no ambiguity line" "$ZERO" "$ERR"

# #382: the root file beside an AMBIGUOUS table. bare-root has one table candidate, so a table lookup
# would resolve it without any ambiguity and could not tell the two orders apart; this fixture has two.
mkrepo bare-root-dup
bare_group demo-group demo-rootdup.sh
printf 'x\n' > "$R/scripts/demo-rootdup.sh"; printf 'x\n' > "$R/demo-rootdup.sh"
printf '# Doc\n\nThe demo is `demo-rootdup.sh` here.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/demo-rootdup.sh"; snap "$T2" "change the root file"; RD_ROOT=$(sha HEAD)
run --range "$BASE..$RD_ROOT" --docs README.md
expect "a changed root file beside two table candidates yields exactly its row" "README.md	3	demo-rootdup.sh	$RD_ROOT" "$OUT"
expect "with only the one-row summary, so the root path won ahead of the ambiguity branch" "check-doc-drift: 1 suspected stale claim(s) across the documents given." "$ERR"
bare_touch "$R/scripts/demo-rootdup.sh"; snap "$T2" "change the scripts/ file"; RD_SCRIPT=$(sha HEAD)
run --range "$RD_ROOT..$RD_SCRIPT" --docs README.md
expect "a range changing only a candidate yields no row" "" "$OUT"
contains "ambiguous bare name 'demo-rootdup.sh' (matches plugins/demo-group/skills/demo-group-skill/assets/demo-rootdup.sh, scripts/demo-rootdup.sh); cite the full path" "$ERR" "and the ambiguity line lists exactly the asset and the scripts/ file, never the root file"
run --range "$BASE..$RD_SCRIPT" --docs README.md
expect "a range changing both resolves to the root file, pinned to its commit" "README.md	3	demo-rootdup.sh	$RD_ROOT" "$OUT"
lacks "ambiguous" "$ERR" "with no ambiguity line in that range"
if grep -qF -- 'a root file is never listed as a candidate' "$SUT"; then ok "the script header states that a root file is never listed as a candidate"; else bad "the script header lacks the never-listed-as-a-candidate sentence"; fi

# #372: a token is only ever an awk array key. M3 is the mutant that expands it through a shell or a
# git pathspec (the bare lookup becoming "git ls-files -- \"scripts/" tok "\"" | getline, with no
# .sh suffix guard); meta-subst, meta-subst-unresolved and meta-glob-absent kill it.
mkrepo meta-subst
printf 'x\n' > "$R/scripts/\$(touch pwned).sh"
printf '# Doc\n\nRun `$(touch pwned).sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/\$(touch pwned).sh"; snap "$T2" "change the metacharacter-named script"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a command-substitution filename resolves to exactly one row" 1 "$(rows)"
contains '	$(touch pwned).sh	' "$OUT" "whose token column is the literal text"
lacks "ambiguous" "$ERR" "with no ambiguity line"
if [ ! -e "$R/pwned" ]; then ok "and no pwned file was created, so nothing was executed"; else bad "a pwned file exists: the token was executed"; fi
mkrepo meta-subst-unresolved
printf 'x\n' > "$R/scripts/demo-check.sh"
printf '# Doc\n\nRun `$(touch pwned-two)`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/demo-check.sh"; snap "$T2" "change the script"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an unresolved command-substitution span yields no row" "" "$OUT"
expect "with exactly the zero-claims summary" "$ZERO" "$ERR"
if [ ! -e "$R/pwned-two" ]; then ok "and no pwned-two file was created"; else bad "a pwned-two file exists: the token was executed"; fi
mkrepo meta-glob-literal
printf 'a\n' > "$R/scripts/a.sh"; printf 'ab\n' > "$R/scripts/[ab].sh"
printf '# Doc\n\nRun `[ab].sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/a.sh"; snap "$T2" "change a.sh"; GLOB_A=$(sha HEAD)
bare_touch "$R/scripts/[ab].sh"; snap "$T2" "change [ab].sh"; GLOB_AB=$(sha HEAD)
run --range "$BASE..$GLOB_AB" --docs README.md
expect "a literal [ab].sh file yields exactly one row" 1 "$(rows)"
expect "whose commit is the [ab].sh commit, not the a.sh commit (kills the reverse-regex mutant)" "$GLOB_AB" "$(printf '%s' "$OUT" | cut -f4)"
if [ "$GLOB_A" != "$GLOB_AB" ]; then ok "the two commits differ, so the check above can tell them apart"; else bad "the a.sh and [ab].sh commits are the same"; fi
lacks "ambiguous" "$ERR" "with no ambiguity line"
mkrepo meta-glob-absent
printf 'a\n' > "$R/scripts/a.sh"
printf '# Doc\n\nRun `[ab].sh`.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/scripts/a.sh"; snap "$T2" "change a.sh"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a glob citation with no literal file yields no row, so [ab].sh did not match a.sh" "" "$OUT"
expect "with exactly the zero-claims summary" "$ZERO" "$ERR"

# Condition D: an allow-file mention suppresses a bare-name line, keyed on the RESOLVED path.
mkrepo bare-allow
bare_group demo-group demo-asset.sh
printf '# Doc\n\nIn passing, `demo-asset.sh` is only named here.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
bare_touch "$R/plugins/demo-group/skills/demo-group-skill/assets/demo-asset.sh"; snap "$T2" "change the asset"
ASSETPATH=plugins/demo-group/skills/demo-group-skill/assets/demo-asset.sh
printf '# only a mention\nmention README.md %s is only named here\n' "$ASSETPATH" > "$R/.doc-drift-allow"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an entry for the resolved asset path suppresses the bare-name row" "" "$OUT"
expect "with exactly the zero-claims summary on stderr, no stale line" "$ZERO" "$ERR"
printf '# wrong path\nmention README.md plugins/demo-group/skills/demo-group-skill/SKILL.md is only named here\n' > "$R/.doc-drift-allow"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an entry naming a different path does not suppress" 1 "$(rows)"
lacks "ambiguous" "$ERR" "and prints no ambiguity line"

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

echo "== every --docs entry is validated before any row is printed (#267 F2) =="
# README.md carries a stale claim on its own (as pinned by the drift case above), and would print a
# row for it if this document alone were asked about. Pairing it with the untracked NOTES.md must
# still exit 2 with NOTHING on stdout: validating inside the emit loop would let README.md's row out
# before NOTES.md was reached, which is the exact partial-output defect this case pins.
printf 'guard, changed\n' > "$R/scripts/guard.sh"
# Committed by path, not via snap's `add -A`: NOTES.md must stay untracked for this case.
git -C "$R" add scripts/guard.sh
GIT_AUTHOR_DATE="$T2" GIT_COMMITTER_DATE="$T2" git -C "$R" commit -q -m "change the guard, so README.md now carries a stale claim"
run --range "$BASE..$(sha HEAD)" --docs README.md,NOTES.md
expect "the run exits 2" 2 "$RC"
expect "and stdout is empty, not README.md's row followed by the refusal" "" "$OUT"
contains "NOTES.md" "$ERR" "and stderr names the untracked document that made it refuse"

echo "== --docs takes a comma-separated list, not a space-separated one (#267 F3) =="
run --range "$BASE..HEAD" --docs "README.md NOTES.md"
expect "a space-separated list exits 2" 2 "$RC"
expect "with nothing on stdout" "" "$OUT"
contains "README.md NOTES.md" "$ERR" "and the whole space-joined string is reported as one absent document"

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
expect "an entry with a document and no path exits 2" 2 "$RC"
contains "line 2: entry is missing its path" "$ERR" "and says the PATH is missing (#308)"
lacks "missing its anchor" "$ERR" "and does not call it a missing anchor"
expect "with nothing on stdout" "" "$OUT"

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
  RANGE_TXT="$txt"; RANGE_OUT="$out"
}
# #372: column 3 is the token as cited, so a wrong-file resolution still prints it. Column 4 is the
# newest in-range commit that changed the RESOLVED path, which is what pins the file. The helper
# RETURNS non-zero on a mismatch and never calls bad(), so a control can assert the status.
FL=plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh
col4_is() {  # col4_is <rows> <expected-sha>: 0 only when the forge-lib.sh row's column 4 equals it
  [ -n "$2" ] && [ "$(printf '%s\n' "$1" | awk -F'\t' '$3 == "forge-lib.sh" { print $4 }')" = "$2" ]
}
pin_forge_lib() {  # pin_forge_lib <range>: the row from the last ranges_expect names the right commit
  local want; want="$(git -C "$ROOT" log -1 --format=%H "$1" -- "$FL")"
  if col4_is "$RANGE_OUT" "$want"; then ok "range ${1%%..*} pins the forge-lib.sh row to the commit that changed the asset"
  else bad "range ${1%%..*} forge-lib.sh row column 4 is not $want"; fi
}
ranges_expect f15dd74e..106a4531 4 'The canonical rules'
pin_forge_lib f15dd74e..106a4531
for a in 'canonical ready-ticket rules' 'what is being worked on now'; do
  case "$RANGE_TXT" in *"$a"*) ok "range 1 still reports the claim '$a'" ;; *) bad "range 1 lost the claim '$a'" ;; esac
done
for a in 'block-dashes` hook stays dormant' 'the group stays inert' 'you copy the issue templates'; do
  case "$RANGE_TXT" in *"$a"*) bad "range 1 still reports the mention anchored by '$a'" ;; *) ok "range 1 no longer reports '$a'" ;; esac
done
for r in 106a4531..9416a77b 9416a77b..c15150c4; do
  ranges_expect "$r" 2 'what is being worked on now'
  pin_forge_lib "$r"
  # Only the two roadmap mentions exist in these ranges; the ticket-standards one does not, so
  # asserting its absence here would pass whatever the code did.
  for a in 'block-dashes` hook stays dormant' 'the group stays inert'; do
    case "$RANGE_TXT" in *"$a"*) bad "range ${r%%..*} still reports the mention anchored by '$a'" ;;
                         *) ok "range ${r%%..*} no longer reports '$a'" ;; esac
  done
done

# Negative control for the helper: right token, wrong sha, must be refused with a non-zero status.
WANT_CTL="$(git -C "$ROOT" log -1 --format=%H 106a4531..9416a77b -- "$FL")"
if col4_is "$(printf 'README.md\t77\tforge-lib.sh\t%040d\n' 0)" "$WANT_CTL"; then bad "the column-4 helper accepted a doctored row"; else ok "the column-4 helper rejects a doctored row (right token, wrong sha)"; fi
if col4_is "$(printf 'README.md\t77\tforge-lib.sh\t%s\n' "$WANT_CTL")" "$WANT_CTL"; then ok "and accepts the same row with the right sha"; else bad "the helper rejected a correct row"; fi
if col4_is "$(printf 'README.md\t77\tforge-lib.sh\t\n')" ""; then bad "the column-4 helper accepted an empty expected sha against an empty column 4"; else ok "the column-4 helper rejects an empty expected sha, even against an empty column 4"; fi

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
allow '# r' 'mention README.md '
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "a document with a trailing space and no path refuses" 2 "$RC"
contains "line 2: entry is missing its path" "$ERR" "with the same path message as the bare form (#308)"
lacks "missing its anchor" "$ERR" "and not the anchor message"
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

echo "== #265: an anchor EQUAL to its path is accepted, a missing anchor still refuses =="
# The equal-anchor entry and the missing-anchor entry look alike to ${_rest#* }: with no fourth
# field nothing was consumed, so the expansion returns $_rest itself. The check therefore compares
# the anchor with $_rest and not with $_path, which is also what the anchor IS when it equals the
# path. This fixture names each path on exactly ONE README line, so the ambiguity refusal is not
# what decides it; the suite's shared allowrepo README names scripts/guard.sh twice.
mkrepo eqanchor
printf 'guard\n' > "$R/scripts/guard.sh"; printf 'other\n' > "$R/scripts/other.sh"
printf '# Doc\n\nOnly `scripts/guard.sh` is named here.\n\nAnd `scripts/other.sh` here.\n' > "$R/README.md"
snap "$T1" "base"; BASE=$(sha HEAD)
printf 'guard, changed\n' > "$R/scripts/guard.sh"; printf 'other, changed\n' > "$R/scripts/other.sh"
snap "$T2" "change both"
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "control: with no allow-file both rows are reported" 2 "$(printf '%s' "$OUT" | grep -c .)"
allow '# the anchor is the path itself' 'mention README.md scripts/guard.sh scripts/guard.sh'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an anchor equal to its path exits 0" 0 "$RC"
expect "and suppresses exactly that row, leaving the other" 1 "$(printf '%s' "$OUT" | grep -c .)"
lacks "scripts/guard.sh" "$(printf '%s' "$OUT" | cut -f3)" "and the surviving row is not the suppressed path"
lacks "missing its anchor" "$ERR" "and stderr does not call it a missing anchor"
allow '# no fourth field at all' 'mention README.md scripts/guard.sh'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "no fourth field still exits 2" 2 "$RC"
expect "with nothing on stdout" "" "$OUT"
contains "line 2: entry is missing its anchor" "$ERR" "and names the line and the missing anchor"
allowrepo eqambig
allow '# equal anchor, but the path is named on two lines' 'mention README.md scripts/guard.sh scripts/guard.sh'
run --range "$BASE..$(sha HEAD)" --docs README.md
expect "an accepted equal anchor still goes through matching, so two lines refuse" 2 "$RC"
contains "the anchor matches more than one line of README.md" "$ERR" "with the ambiguity message"

echo "== #265: a CRLF allow-file behaves exactly like its LF twin =="
# The BLANK-LINE shape is the required fixture: a blank CRLF line is a lone CR, which matches
# neither '' nor '#'*, so a strip placed after that case still refuses the documented format.
# Every negative is built from the blank-line fixture for the same reason.
crlf_twin() {  # crlf_twin: run LF, then the same file with CRLF endings; set LFOUT LFERR LFRC
  run --range "$BASE..$(sha HEAD)" --docs README.md
  LFOUT="$OUT"; LFERR="$ERR"; LFRC=$RC
  sed 's/$/\r/' "$R/.doc-drift-allow" > "$R/.crlf" && mv "$R/.crlf" "$R/.doc-drift-allow"
  run --range "$BASE..$(sha HEAD)" --docs README.md
}
allowrepo crlf1
allow '# r1' 'mention README.md scripts/guard.sh In passing,' '' '# r2' 'mention README.md scripts/guard.sh does exactly three things'
crlf_twin
expect "CRLF with blank separator lines exits 0" 0 "$RC"
expect "control: the LF twin suppressed both rows" "" "$LFOUT"
expect "CRLF stdout is byte-identical to the LF twin" "$LFOUT" "$OUT"
expect "CRLF stderr is byte-identical to the LF twin" "$LFERR" "$ERR"
lacks "unknown key" "$ERR" "and is not refused at the blank line"
lacks ": stale, " "$ERR" "and no entry degrades to stale"
allowrepo crlf2
allow '# r1' 'mention README.md scripts/guard.sh In passing,' '# r2' 'mention README.md scripts/guard.sh does exactly three things'
crlf_twin
expect "CRLF with no blank lines exits 0" 0 "$RC"
expect "and is byte-identical to its LF twin on stdout" "$LFOUT" "$OUT"
expect "and on stderr" "$LFERR" "$ERR"
expect "and both rows were suppressed, not merely unchanged" "" "$OUT"
allowrepo crlf3
allow '# r1' 'mention README.md scripts/guard.sh In passing,' '' '# r2' 'suppress README.md scripts/guard.sh does exactly three things'
crlf_twin
expect "a CRLF entry with an unknown key still exits 2" 2 "$RC"
contains "unknown key 'suppress' (only 'mention' is defined)" "$ERR" "with the exact message, the strip does not turn malformed input into acceptance"
expect "and the LF twin said the same" "$LFERR" "$ERR"
allowrepo crlf4
allow '# r1' 'mention README.md scripts/guard.sh In passing,' '' '# r2' 'mention README.md scripts/guard.sh no line says this'
crlf_twin
expect "a CRLF entry that is really stale exits 0" 0 "$RC"
contains "stale, no line of README.md contains that anchor" "$ERR" "and says stale"
expect "with the unmatched entry's row still printed" 1 "$(printf '%s' "$OUT" | grep -c .)"
expect "and byte-identical to its LF twin on stdout" "$LFOUT" "$OUT"
expect "and on stderr" "$LFERR" "$ERR"

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
