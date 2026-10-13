#!/usr/bin/env bash
# Contract test for forge-gate-mechanics.sh (#182).
#
# WHAT THIS ENTRY POINT IS FOR. Every mechanical check forge-kit has is already plain shell with its
# own suite (check-ticket-mechanics.sh, 79 cases). What was missing was a way to RUN it without
# Claude Code, which is the whole of forge-kit's portability claim. So the cases below are mostly
# about what the entry point must NOT do: not re-judge a row, not print a verdict, not depend on the
# `claude` CLI, and not report clean when it cannot run.
#
# Driven with a STUB forge-lib.sh placed beside a copy of the script, the shape test-sync-labels.sh
# already uses, so no network and no token are involved.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
REAL="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/forge-gate-mechanics.sh"
MECH="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if grep -qF -- "$1" <<< "$2"; then bad "$3 (found '$1')"; else ok "$3"; fi; }

[ -f "$REAL" ] || { echo "missing script: $REAL"; exit 1; }
[ -f "$MECH" ] || { echo "missing script: $MECH"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
cp "$REAL" "$MECH" "$BIN/"

# The stub transport: forge_issue_view prints whatever fixture the case wrote.
cat > "$BIN/forge-lib.sh" <<'LIB'
forge_repo() { echo "fixture/repo"; }
forge_host() { echo "github"; }
forge_issue_view() { cat "$FIXTURE_ISSUE"; }
LIB

# A project tree with a template directory, since the entry point resolves one.
proj() {
  rm -rf "$T/proj"; mkdir -p "$T/proj/$1"
  cp "$ROOT/.github/ISSUE_TEMPLATE/feature.yml" "$T/proj/$1/feature.yml"
  # bug.yml too, so a type label can be seen choosing a template other than the fallback (#476).
  cp "$ROOT/.github/ISSUE_TEMPLATE/bug.yml" "$T/proj/$1/bug.yml"
}

# A body carrying every heading the real template declares, each with content, so a `fail` row can
# only mean the entry point fed the checker something wrong.
build_full_body() {
  {
    echo '<!-- template-version: 6 -->'
    grep -oP '^\s+label: \K.*' "$ROOT/.github/ISSUE_TEMPLATE/feature.yml" | while IFS= read -r l; do
      printf '### %s\n' "$l"
      # The content heuristics are check-ticket-mechanics.sh's business and it has 79 tests of its
      # own. What this fixture needs is a body that satisfies them, so that a `fail` row here can
      # only mean the ENTRY POINT fed it something wrong.
      case "$l" in
        *"Given / When / Then"*)
          printf '%s\n' '**Positive**' '- **Given**: a valid request' '- **When**: it is submitted' \
            '- **Then**: the record is stored' '' '**Negative**' '- **Given**: a malformed request' \
            '- **When**: it is submitted' '- **Then**: it is rejected with a 422' ;;
        *"Unit tests"*)   echo '- `scripts/test-forge-gate-mechanics.sh` covers the entry point' ;;
        *"E2E test"*)     echo 'N/A. No UI and no emulator suite in this fixture project.' ;;
        *"Documentation impact"*) echo 'Updates `docs/guides/ticket-standards.md` and this README.' ;;
        *) echo 'Content for this section, long enough to read as filled in rather than a placeholder.' ;;
      esac
    done
  } > "$T/full-body.md"
  FULL="$(cat "$T/full-body.md")"
}
issue() {  # issue <body-text> [labels...]
  local body="$1"; shift
  local labels="" sep=""
  for l in "$@"; do labels="$labels$sep{\"name\":\"$l\"}"; sep=","; done
  python3 - "$T/issue.json" "$body" "[$labels]" <<'PY'
import json, sys
json.dump({"number": 42, "title": "fixture", "body": sys.argv[2],
           "labels": json.loads(sys.argv[3])}, open(sys.argv[1], "w"))
PY
}
out=""; rc=0
run() { out=$(cd "$T/proj" && FIXTURE_ISSUE="$T/issue.json" bash "$BIN/forge-gate-mechanics.sh" "$@" 2>&1); rc=$?; }

FULL=""
build_full_body

echo "== it runs the real checks and prints their rows =="
proj .github/ISSUE_TEMPLATE; issue "$FULL" feature P2 api
run 42
contains "template-version" "$out" "a check row about the template version is present"
[ "$(printf '%s\n' "$out" | grep -cE '^[a-z0-9_]+ +(pass|fail|warn|na|referred) ')" -gt 3 ] \
  && ok "several check rows came back, not a summary alone" \
  || bad "several check rows came back (got: $(printf '%s' "$out" | head -3))"

echo "== it never prints a verdict =="
# Step 3A is the MECHANICAL half. A summary saying PASS would look like the real gate and would be
# a worse liar than today's silence, because the critic in Step 3B has not run.
lacks "PASS" "$out" "no PASS verdict"
lacks "NEEDS-WORK" "$out" "no NEEDS-WORK verdict"
lacks "BLOCKED" "$out" "no BLOCKED verdict"
contains "referred" "$out" "but the summary names the referred count, because a referral is not a pass"
# The COUNT, not just the word: folding referrals into the good news is the quiet way this stops
# being honest, and the prose line below the summary contains "referred" either way.
want_ref=$(printf '%s\n' "$out" | grep -cE '^[a-z0-9_]+ +referred ')
got_ref=$(printf '%s\n' "$out" | grep -oE '[0-9]+ REFERRED' | grep -oE '^[0-9]+')
expect "the summary's referred count matches the rows" "$want_ref" "$got_ref"

echo "== the TSV passthrough is byte-identical to the checker's own output =="
# If the entry point filtered or re-judged a row, this is where it would show. The direct run
# passes the same --labels-doc the entry point does, because since #425 an absent doc is announced
# in the labels row, so a direct run without the flag would differ by that notice alone.
cp "$T/full-body.md" "$T/body.md"
direct=$(cd "$T/proj" && bash "$BIN/check-ticket-mechanics.sh" --body "$T/body.md" \
  --template .github/ISSUE_TEMPLATE/feature.yml --tpl-version 6 --current-tpl-version 6 --labels "feature,P2,api" \
  --labels-doc docs/guides/labels.md 2>/dev/null)
[ -n "$direct" ] && ok "the checker produced rows to compare against" \
  || bad "the checker produced rows to compare against (an empty comparison passes vacuously)"
via=$(cd "$T/proj" && FIXTURE_ISSUE="$T/issue.json" bash "$BIN/forge-gate-mechanics.sh" 42 --format tsv 2>/dev/null)
[ "$direct" = "$via" ] && ok "--format tsv reproduces check-ticket-mechanics.sh exactly" \
  || bad "--format tsv reproduces the checker exactly (diff: $(diff <(printf '%s' "$direct") <(printf '%s' "$via") | head -2 | tr '\n' ' '))"

echo "== the project's own area set reaches the checker (#204) =="
# The entry point passes --labels-doc docs/guides/labels.md unconditionally, so a project whose
# table declares `protocol` and whose ticket carries only `protocol` gets `labels pass`; without
# the doc the same ticket is referred with the notice (#425), since `protocol` is in neither
# compiled-in set and only Step 3B can judge whether it is the project's area.
NOTICE="labels.md not found; using forge-kit's built-in nine areas. Run forge-adapt Templates mode, \"Labels\" step, to declare yours."
mkdir -p "$T/proj/docs/guides"
printf '### Area labels\n| Label |\n|---|\n| `protocol` |\n\n### Type labels\n' > "$T/proj/docs/guides/labels.md"
issue "$(cat "$T/full-body.md")" feature P2 protocol
out=$(cd "$T/proj" && FIXTURE_ISSUE="$T/issue.json" bash "$BIN/forge-gate-mechanics.sh" 42 --format tsv 2>/dev/null)
expect "a ticket carrying only the project's own area passes check 2 through the entry point" pass "$(printf '%s\n' "$out" | awk -F'\t' '$1=="labels"{print $2}')"
lacks "Templates mode" "$out" "a present doc gives no notice through the entry point"
rm "$T/proj/docs/guides/labels.md"
out=$(cd "$T/proj" && FIXTURE_ISSUE="$T/issue.json" bash "$BIN/forge-gate-mechanics.sh" 42 --format tsv 2>/dev/null)
expect "without the doc the same ticket is referred, never failed on the compiled-in set" referred "$(printf '%s\n' "$out" | awk -F'\t' '$1=="labels"{print $2}')"
contains "$NOTICE" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="labels"{print $3}')" "and the labels row carries the notice"

echo "== a failing check exits non-zero, a referred one does not =="
# Template-shaped on purpose: since #184 a body that was never template-shaped exits 0 with an
# explanation instead, so a hand-written fixture here would test the wrong branch.
proj .github/ISSUE_TEMPLATE
issue '<!-- template-version: 6 -->
### Summary
Shaped like a form submission, and missing everything else.' feature P2 api
run 42
[ "$rc" -ne 0 ] && ok "a template-shaped body missing its required sections exits non-zero" \
  || bad "a template-shaped body missing its required sections exits non-zero (rc=$rc)"

proj .github/ISSUE_TEMPLATE; issue "$FULL" feature P2 api
run 42
expect "a clean body exits 0" 0 "$rc"

echo "== a body lacking only the gate-filled Codebase Context heading is not charged (#304) =="
# The #299/#300 shape: a hand-filed body with every heading but Codebase Context. This path never
# writes the body, so only the checker's template-keyed exemption can keep it from failing.
grep -qx '### Codebase Context' "$T/full-body.md" && ok "the full fixture carries the heading to remove (fixture sanity)" \
  || bad "the full fixture carries no Codebase Context heading to remove"
proj .github/ISSUE_TEMPLATE
issue "$(awk '$0 == "### Codebase Context" { skip = 2 } skip > 0 { skip--; next } { print }' "$T/full-body.md")" feature P2 api
run 42 --format tsv
expect "it exits 0" 0 "$rc"
expect "and carries no sections FAIL row" pass "$(printf '%s\n' "$out" | awk -F'\t' '$1=="sections"{print $2}')"

echo "== the Forgejo template directories are resolved too =="
proj .forgejo/ISSUE_TEMPLATE; issue "$FULL" feature P2 api
run 42
expect "a .forgejo template dir is found" 0 "$rc"
contains "referred" "$out" "and the run produced real rows"

echo "== the type label picks the template without regard to case (#476) =="
# Since #472 the labels check folds case, so a `Bug` ticket passes it; the template choice must
# agree, or that ticket is judged against feature.yml, the fallback.
proj .github/ISSUE_TEMPLATE
for lab in bug Bug BUG; do
  issue "$FULL" "$lab" P2 api
  run 42
  contains "against .github/ISSUE_TEMPLATE/bug.yml" "$out" "a ticket labelled $lab is checked against bug.yml"
done
# Only whole label names fold, exactly as `Apiary` is not `api` in the labels check.
issue "$FULL" Bugfix P2 api
run 42
contains "against .github/ISSUE_TEMPLATE/feature.yml" "$out" "a ticket labelled Bugfix falls back to feature.yml"
lacks "bug.yml" "$out" "and is not checked against bug.yml"
# The fold is a copy for the type loop only: the checker still gets the labels as written.
issue "$FULL" Bug P2 api
direct=$(cd "$T/proj" && bash "$BIN/check-ticket-mechanics.sh" --body "$T/full-body.md" \
  --template .github/ISSUE_TEMPLATE/bug.yml --tpl-version 6 --current-tpl-version 6 --labels "Bug,P2,api" \
  --labels-doc docs/guides/labels.md 2>/dev/null)
via=$(cd "$T/proj" && FIXTURE_ISSUE="$T/issue.json" bash "$BIN/forge-gate-mechanics.sh" 42 --format tsv 2>/dev/null)
[ -n "$direct" ] && [ "$direct" = "$via" ] && ok "the checker receives the original-case labels" \
  || bad "the checker receives the original-case labels (diff: $(diff <(printf '%s' "$direct") <(printf '%s' "$via") | head -2 | tr '\n' ' '))"

echo "== no template directory at all is reported, not guessed =="
rm -rf "$T/proj"; mkdir -p "$T/proj"; issue "$FULL" feature P2 api
run 42
[ "$rc" -ne 0 ] && ok "a project with no template directory exits non-zero" \
  || bad "a project with no template directory exits non-zero (rc=$rc)"
contains "template" "$out" "and says what is missing"

echo "== a body that was never template-shaped is reported ONCE, not as seven failures (#184) =="
# The finding behind this: the gate's Step 0c SYNTHESISES a body and writes it back to the forge
# before Step 3A ever sees it, so inside a gate run the checks get template-shaped input. Run
# against a raw hand-filed ticket they all fail, and all of those failures are one fact. Saying it
# seven times buries it.
proj .github/ISSUE_TEMPLATE
issue 'Summary: written by hand with gh issue create, so no marker and no headings at all.
# A top-level title is not a section heading either
Acceptance criteria: it works' feature P2 api
run 42
contains "never template-shaped" "$out" "the report names the one fact"
contains "0c" "$out" "and points at the step that would have fixed it"
notice_line=$(printf '%s\n' "$out" | grep -n "never template-shaped" | head -1 | cut -d: -f1)
first_row=$(printf '%s\n' "$out" | grep -nE '^[a-z0-9_]+ +(pass|fail|warn|na|referred) ' | head -1 | cut -d: -f1)
[ -n "$notice_line" ] && [ -n "$first_row" ] && [ "$notice_line" -lt "$first_row" ] \
  && ok "and the reader meets the explanation BEFORE the rows it explains" \
  || bad "and the reader meets the explanation before the rows (notice at ${notice_line:-none}, first row at ${first_row:-none})"
expect "and it exits 0, because the shape is not a ticket defect" 0 "$rc"

echo "== the shape test needs BOTH signals, because either alone is a different situation =="
# The plan's premortem named this: "a body could carry the headings and no marker, or the reverse.
# If the message states more certainty than those two signals support, it will be wrong in public."
# A mutant swapping && for || survived until these two cases existed.
proj .github/ISSUE_TEMPLATE
issue '### Summary
Form headings, but the marker was stripped or the template predates markers.
### Acceptance criteria
- it works' feature P2 api
run 42
lacks "never template-shaped" "$out" "form headings with no marker is NOT called never-template-shaped"

issue '<!-- template-version: 6 -->
Summary: a marker, but no headings at all afterwards.' feature P2 api
run 42
lacks "never template-shaped" "$out" "a marker with no form headings is NOT called never-template-shaped either"

# #190: a ## body carrying the template's labels is recognised by the checker and JUDGED on its
# content, so the notice must not excuse it; its sections row decides.
issue '## Summary
Written by hand with gh issue create at two-hash headings.
## Acceptance criteria
- it works' feature P2 api
run 42
lacks "never template-shaped" "$out" "a ## body with template labels is judged, not called never-template-shaped (#190)"

# ...but a ## body whose headings are the AUTHOR'S words, not template labels, is still
# unrecognised, and the notice must still fire: this is #184's case, and #190 must not regress it.
issue '## What happened
Written by hand with two-hash headings of my own.
## What I expected
- it works' feature P2 api
run 42
contains "never template-shaped" "$out" "a ## body with no template label is still never-template-shaped (#184 kept under #190)"

# #485: template headings QUOTED inside a fenced code block are not headings, so a hand-written body
# whose only template labels sit in a fence is still never template-shaped. The detector reads the
# checker's fence-aware --headings, never a raw grep of the body.
FENCED485='Written by hand. The form looks like this:
```
### Summary
### Acceptance criteria
```
and nothing else.'
issue "$FENCED485" feature P2 api
run 42
contains "never template-shaped" "$out" "a body whose template headings are only inside a fence is never template-shaped (#485)"
issue "$(printf '%s\n### Summary\nreal heading after the fence' "$FENCED485")" feature P2 api
run 42
lacks "never template-shaped" "$out" "a real template heading after the fence is still template-shaped (#485)"
# M8: the detector reverted to a raw grep of the body must lose the notice on the fenced body.
grep -qF '<<< "$HEADS"' "$REAL" && ok "mutant ledger: SHAPED reads the fence-aware heading list (#485)" || bad "mutant ledger: #485 SHAPED line not found"
cp "$BIN/forge-gate-mechanics.sh" "$T/fgm.bak"
sed 's/<<< "\$HEADS"/"$BODY_FILE"/' "$T/fgm.bak" > "$BIN/forge-gate-mechanics.sh"
if cmp -s "$T/fgm.bak" "$BIN/forge-gate-mechanics.sh"; then bad "#485: mutant M8 did not apply"; else
  issue "$FENCED485" feature P2 api
  run 42
  lacks "never template-shaped" "$out" "mutant M8: a raw-grep detector loses the notice on the fenced body (the #485 row can fail)"
fi
cp "$T/fgm.bak" "$BIN/forge-gate-mechanics.sh"
# #491: a markerless body with CRLF endings carries form headings, so it is template-shaped. SHAPED
# compares --headings with grep -qxF, so it depends on the checker printing headings without a CR.
CRLF491="$(printf '### Summary\r\nForm headings with CRLF endings and no marker.\r\n### Acceptance criteria\r\n- it works\r\n')"
grep -q $'^### Summary\r$' <<< "$CRLF491" && ok "#491: the markerless CRLF fixture carries a CR on its headings (fixture sanity)" || bad "#491: the markerless CRLF fixture has no CR"
issue "$CRLF491" feature P2 api
run 42
lacks "never template-shaped" "$out" "a markerless CRLF body with form headings is NOT called never-template-shaped (#491)"
# The checker's --headings mutated to print the raw line again must bring the notice back.
cp "$BIN/check-ticket-mechanics.sh" "$T/ctm.bak"
sed '/^body_headings() {/,/^}/ s/print h/print/g' "$T/ctm.bak" > "$BIN/check-ticket-mechanics.sh"
if cmp -s "$T/ctm.bak" "$BIN/check-ticket-mechanics.sh" || grep -qF 'print h' <<< "$(sed -n '/^body_headings() {/,/^}/p' "$BIN/check-ticket-mechanics.sh")"; then
  bad "#491: the --headings CR mutant did not apply"
else
  run 42
  contains "never template-shaped" "$out" "mutant: --headings printing the CR calls the CRLF body never-template-shaped (the #491 row can fail)"
fi
cp "$T/ctm.bak" "$BIN/check-ticket-mechanics.sh"

echo "== a template-shaped body missing ONE section still fails that section =="
# The near-miss that keeps the notice honest: it must key on the SHAPE, not on any failure count,
# or a gated ticket with a genuine gap would be excused by the same message.
build_full_body
python3 - "$T/full-body.md" <<'PY2'
import sys, re
lines = open(sys.argv[1]).read().split("\n")
out, drop = [], False
for l in lines:
    if l.startswith("### "): drop = l.startswith("### Documentation impact")
    if not drop: out.append(l)
open(sys.argv[1], "w").write("\n".join(out))
PY2
issue "$(cat "$T/full-body.md")" feature P2 api
run 42
[ "$rc" -ne 0 ] && ok "a template-shaped body with a missing section still fails" \
  || bad "a template-shaped body with a missing section still fails (rc=$rc)"
lacks "never template-shaped" "$out" "and is NOT excused by the not-template-shaped notice"
build_full_body

echo "== a missing forge-lib.sh refuses rather than reporting clean =="
proj .github/ISSUE_TEMPLATE; issue "$FULL" feature P2 api
mv "$BIN/forge-lib.sh" "$BIN/forge-lib.hidden"
run 42
expect "a missing library exits 2" 2 "$rc"
contains "forge-lib.sh" "$out" "and names the file it needs"
contains "Refusing rather than reporting clean" "$out" "and says why it refuses rather than continuing"
mv "$BIN/forge-lib.hidden" "$BIN/forge-lib.sh"

echo "== a missing checker refuses too =="
mv "$BIN/check-ticket-mechanics.sh" "$BIN/check.hidden"
run 42
expect "a missing checker exits 2" 2 "$rc"
mv "$BIN/check.hidden" "$BIN/check-ticket-mechanics.sh"

echo "== nothing in this path touches the claude CLI =="
# The entire point of the ticket: a governance path with no dependency on the harness.
grep -q "claude" "$REAL" && bad "the script mentions the claude CLI" || ok "the script never invokes claude"
PATH=/usr/bin:/bin run 42
expect "it runs with a minimal PATH and no plugins installed" 0 "$rc"

echo "== an issue number is required =="
proj .github/ISSUE_TEMPLATE; issue "$FULL" feature P2 api
run
[ "$rc" -eq 2 ] && ok "no issue number refuses" || bad "no issue number refuses (rc=$rc)"

echo ""
echo "forge-gate-mechanics tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
