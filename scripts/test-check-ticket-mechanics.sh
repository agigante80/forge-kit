#!/usr/bin/env bash
# Contract test for check-ticket-mechanics.sh, the scripted half of ticket-gate Step 3A (#149).
#
# WHY IT BUILDS FIXTURES FROM THE REAL TEMPLATES. Version 1 of this suite exercised feature.yml
# with every field filled, and that single blind spot hid the two worst defects in the script:
# the four templates that name their test sections differently (or carry none) all produced a
# blocking failure on a perfectly compliant ticket, and the four `required: false` fields that
# GitHub renders as `_No response_` did the same. A fixture that is written by hand agrees with
# whatever the author assumed; one generated from the template does not.
#
# WHY EVERY REFER PATH IS TESTED EXPLICITLY. The script's heuristics are deliberately narrower
# than the canonical rules, so where it cannot decide it must emit `referred` and let the critic
# rule. A naive implementation fails outright instead, which would reject doc-compliant tickets.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"
TPLDIR="$ROOT/.github/ISSUE_TEMPLATE"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0; failed=0
ok()  { printf '  ok: %s\n' "$1"; passed=$((passed+1)); }
bad() { printf '  FAIL: %s\n' "$1"; failed=$((failed+1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected $2, got '$3')"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

# Fixture generator: reads a real template and writes a body that satisfies it, so the suite
# cannot drift from the templates the gate actually runs against.
cat > "$WORK/gen.py" <<'PY'
import re, sys
def fields(path):
    out=[]; type_=None; label=None; req="false"; kind=None
    for line in open(path):
        m=re.match(r'\s*-\s*type:\s*(\S+)', line)
        if m:
            if label: out.append((label, req=="true", kind))
            type_=m.group(1); label=None; req="false"; kind=type_; continue
        m=re.match(r'      label: (.*)$', line)
        if m and type_!="markdown" and label is None: label=m.group(1).rstrip()
        m=re.match(r'      required: (\S+)', line)
        if m: req=m.group(1)
    if label: out.append((label, req=="true", kind))
    return out
GWT = sys.argv[3] if len(sys.argv) > 3 else """**Condition: login**

Positive
- Given: a valid user
- When: they submit
- Then: a session starts

Negative
- Given: a bad password
- When: they submit
- Then: 401 with AUTH_FAILED"""
UNIT = sys.argv[4] if len(sys.argv) > 4 else "- [ ] `tests/unit/auth.test.ts` valid input -> session"
E2E  = sys.argv[5] if len(sys.argv) > 5 else "- [ ] `tests/e2e/login.spec.ts` happy and unhappy"
DOCS = sys.argv[6] if len(sys.argv) > 6 else "Updates `docs/guides/auth.md`"
def content(label, required):
    l = label.lower()
    if re.search(r'given.*when.*then', l): return GWT
    if 'unit test' in l: return UNIT
    if re.search(r'e2e|end.to.end', l): return E2E
    if 'documentation impact' in l: return DOCS
    return "filled in" if required else "_No response_"
body = ["<!-- template-version: 6 -->", ""]
for label, req, kind in fields(sys.argv[1]):
    # GitHub renders a checkboxes group as list items, never as `_No response_`.
    c = "- [x] acknowledged" if kind == "checkboxes" else content(label, req)
    body += ["### " + label, "", c, ""]
open(sys.argv[2], "w").write("\n".join(body))
PY

# mkbody <template-name> <out> [gwt] [unit] [e2e] [docs]
mkbody() {
  local tpl="$1" out="$WORK/$2"; shift 2
  python3 "$WORK/gen.py" "$TPLDIR/$tpl.yml" "$out" "$@"
  printf '%s' "$out"
}
run() { # run <body> <template-name> [extra args...]
  local body="$1" tpl="$2"; shift 2
  bash "$SCRIPT" --body "$body" --template "$TPLDIR/$tpl.yml" \
    --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" "$@" 2>/dev/null
}
outcome() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1 == c { print $2 }'; }

echo "check-ticket-mechanics: a compliant ticket passes on EVERY template"
for tpl in feature bug security design infrastructure; do
  B="$(mkbody "$tpl" "ok-$tpl.md")"
  out="$(run "$B" "$tpl")"
  offenders="$(printf '%s\n' "$out" | awk -F'\t' '$2 == "fail" { printf "%s=%s ", $1, $2 }')"
  [ -z "$offenders" ] && ok "$tpl: no spurious FAIL on a compliant ticket" || bad "$tpl: $offenders"
done
# An unresolved role is REFERRED, never `na`: the script cannot tell "this template does not ask
# for E2E specs" from "this template names it something my regex misses", and scoring the second
# `na` would let a project with differently-named sections PASS having checked nothing.
B="$(mkbody security "sec.md")"
expect "a template with no E2E section refers, never fails" referred "$(outcome "$(run "$B" security)" e2e_tests)"
B="$(mkbody design "des.md")"
expect "a template with no unit-test section refers, never fails" referred "$(outcome "$(run "$B" design)" unit_tests)"
expect "a template with no unit or E2E section still judges GWT" pass "$(outcome "$(run "$B" design)" gwt)"
# REGRESSION for the fail-open this replaced.
cat > "$WORK/odd.yml" <<'ODD'
body:
  - type: textarea
    id: summary
    attributes:
      label: Summary
    validations:
      required: true
ODD
printf '<!-- template-version: 6 -->\n\n### Summary\n\nsomething\n' > "$WORK/odd.md"
odd="$(bash "$SCRIPT" --body "$WORK/odd.md" --template "$WORK/odd.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature)"
[ "$(printf '%s\n' "$odd" | awk -F'\t' '$2 == "na" { n++ } END { print n+0 }')" -eq 0 ] \
  && ok "REGRESSION: an unrecognised template scores no check 'na', so it cannot pass unchecked" \
  || bad "an unrecognised template still produces na rows"
# Only check 1 may ever emit `na`, and only for a project with no versioned templates.
allna="$(run "$(mkbody feature "nacheck.md")" feature | awk -F'\t' '$2 == "na" { print $1 }')"
[ -z "$allna" ] && ok "REGRESSION: a normal run emits no na row at all" || bad "unexpected na rows: $allna"
[ "$(printf '%s\n' "$odd" | awk -F'\t' '$2 == "referred" { n++ } END { print n+0 }')" -eq 4 ] \
  && ok "REGRESSION: all four role checks refer to the critic instead" \
  || bad "expected four referred rows on an unrecognised template"

echo "check-ticket-mechanics: the parser, against a hand-written oracle"
# gen.py's parser is a transliteration of the script's awk, so the two would mis-read any
# template shape identically and the suite would agree with the bug. This list is written by
# hand from feature.yml, so a shared misreading has something to disagree with.
expected_fields="Summary|yes
Priority|yes
Affected areas|yes
Files to create/modify|no
Implementation details|no
Acceptance criteria|yes
Personal data handling|yes
Security considerations|yes
Dependencies|no
Test scenarios (Given / When / Then)|yes
Unit tests|yes
Required reviews (mandatory)|yes
QA & Security testing|yes
E2E test scenarios|yes
Documentation impact|yes
Codebase Context|no"
actual_fields="$(bash "$SCRIPT" --body "$WORK/ok-feature.md" --template "$TPLDIR/feature.yml" \
  --dump-fields | tr '\t' '|')"
if [ "$expected_fields" = "$actual_fields" ]; then
  ok "the field parser matches a hand-written reading of feature.yml"
else
  bad "field parser disagrees with the hand-written oracle:"
  diff <(printf '%s\n' "$expected_fields") <(printf '%s\n' "$actual_fields") | sed 's/^/      /'
fi

echo "check-ticket-mechanics: sections and GitHub's _No response_"
B="$(mkbody feature "sec3.md")"
expect "optional fields left as _No response_ still pass" pass "$(outcome "$(run "$B" feature)" sections)"
sed '/^### Acceptance criteria$/{n;n;s/^filled in$/_No response_/}' "$B" > "$WORK/reqempty.md"
expect "a REQUIRED field left as _No response_ fails" fail "$(outcome "$(run "$WORK/reqempty.md" feature)" sections)"
grep -v '^### Acceptance criteria$' "$B" > "$WORK/nohead.md"
expect "an absent heading fails" fail "$(outcome "$(run "$WORK/nohead.md" feature)" sections)"

# A template whose test section is OPTIONAL. Check 3 was fixed to honour `required`; checks 4 to 6
# had the same bug, so an empty optional section produced `sections pass` beside `e2e_tests fail`
# on a ticket GitHub accepted.
cat > "$WORK/opt.yml" <<'OPT'
body:
  - type: textarea
    id: summary
    attributes:
      label: Summary
    validations:
      required: true
  - type: textarea
    id: e2e
    attributes:
      label: E2E test scenarios
    validations:
      required: false
OPT
printf '<!-- template-version: 6 -->\n\n### Summary\n\nsomething\n\n### E2E test scenarios\n\n_No response_\n' > "$WORK/opt.md"
optout="$(bash "$SCRIPT" --body "$WORK/opt.md" --template "$WORK/opt.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature)"
# `na` would be a fail-open of its own: the E2E and documentation sections still bind when optional, and
# nothing looks at an `na` row again.
expect "an OPTIONAL section left empty is REFERRED, neither fail nor na" referred "$(outcome "$optout" e2e_tests)"
expect "and check 3 still passes it" pass "$(outcome "$optout" sections)"

# A checkboxes group is required when any of its options is, and that `required` nests deeper than
# a field's own. Tested through behaviour, since the parser is internal.
cbout="$(run "$(mkbody feature "cb.md")" feature)"
expect "a checkboxes group renders as items, not _No response_" pass "$(outcome "$cbout" sections)"
sed '/^### Required reviews (mandatory)$/{n;n;s/^.*$/_No response_/}' "$WORK/cb.md" > "$WORK/cbempty.md"
expect "REGRESSION: an empty REQUIRED checkboxes group fails check 3" fail "$(outcome "$(run "$WORK/cbempty.md" feature)" sections)"

echo "check-ticket-mechanics: template version"
expect "current version passes" pass "$(outcome "$(run "$B" feature)" template_version)"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 4 --current-tpl-version 6 --labels "backend,feature")"
expect "an older marker fails" fail "$(outcome "$o" template_version)"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 7 --current-tpl-version 6 --labels "backend,feature")"
expect "a NEWER marker warns, or a re-run cannot converge" warn "$(outcome "$o" template_version)"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version "" --labels "backend,feature")"
expect "no versioned templates is na" na "$(outcome "$o" template_version)"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version "" --current-tpl-version 6 --labels "backend,feature")"
expect "a missing marker fails" fail "$(outcome "$o" template_version)"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version "6 7" --current-tpl-version 6 --labels "backend,feature")"
expect "REGRESSION: a non-numeric marker fails, never falls through to pass" fail "$(outcome "$o" template_version)"
# A die here would give the gate "could not run", which it turns into ALL checks referred, so one
# stray match in Step 0a's template scan would silently disable every mechanical check.
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version "6 7" --labels "backend,feature")"
rc=$?
expect "REGRESSION: a non-numeric CURRENT version is a fail row, not a die" fail "$(outcome "$o" template_version)"
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" -eq 7 ] \
  && ok "REGRESSION: and the other six checks still run" \
  || bad "a non-numeric current version suppressed the other checks"

echo "check-ticket-mechanics: labels, against docs/guides/labels.md"
lbl() { bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "$1" | awk -F'\t' '$1=="labels"{print $2}'; }
expect "area plus type passes" pass "$(lbl "backend,feature")"
expect "REGRESSION: privacy is an AREA label, so it satisfies the area requirement" warn "$(lbl "privacy")"
expect "REGRESSION: infrastructure is a TYPE label, not an area" fail "$(lbl "infrastructure")"
expect "REGRESSION: frontend is not a declared label at all" fail "$(lbl "frontend")"
expect "a missing type label only warns" warn "$(lbl "backend")"
expect "a project-specific area label can be supplied" pass \
  "$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "robotics,feature" --area-labels "robotics" | awk -F'\t' '$1=="labels"{print $2}')"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "$(printf 'backend\nfeature')")"
expect "REGRESSION: newline-separated labels do not emit a phantom row" 7 "$(printf '%s\n' "$o" | wc -l | tr -d ' ')"
# #430 item 4b: labels split on commas and newlines only, each trimmed, so a label with a space
# is ONE label. Word-splitting read `needs api review` as three, and its `api` satisfied the area rule.
expect "#430: a comma-space list still passes" pass "$(lbl "governance, enhancement")"
expect "#430: a newline list still passes" pass "$(lbl "$(printf 'governance\nenhancement')")"
expect "#430: a spaced label is one label, not three" fail "$(lbl "needs api review,enhancement")"
o="$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "needs api review,enhancement" | awk -F'\t' '$1=="labels"{print $3}')"
case "$o" in "no area label"*) ok "#430: the spaced label's evidence starts 'no area label'" ;; *) bad "#430: spaced label evidence (got '$o')" ;; esac
mkdir -p "$WORK/globdir"; : > "$WORK/globdir/api"
expect "#430: a glob character in a label stays literal (a* does not expand to the file api)" fail \
  "$(cd "$WORK/globdir" && bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "a*,enhancement" | awk -F'\t' '$1=="labels"{print $2}')"

# #472: label names match without regard to case, against KNOWN area and type names only.
expect "#472: API,bug passes under the fallback area list" pass "$(lbl "API,bug")"
expect "#472: aPi,bug (mixed case) passes" pass "$(lbl "aPi,bug")"
expect "#472: Privacy,feature passes" pass "$(lbl "Privacy,feature")"
expect "#472: an uppercase type label is a type label (Backend,Feature)" pass "$(lbl "Backend,Feature")"
expect "#472: Apiary,bug still fails (not api in any case)" fail "$(lbl "Apiary,bug")"
expect "#472: an unknown area stays unknown (Ops,bug)" fail "$(lbl "Ops,bug")"
mkdir -p "$WORK/case472"; printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `UI` | The UI |\n' > "$WORK/case472/labels.md"
expect "#472: a doc row UI accepts label ui" pass \
  "$(bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "ui,bug" --labels-doc "$WORK/case472/labels.md" 2>/dev/null | awk -F'\t' '$1=="labels"{print $2}')"
MUT="$WORK/mut472.sh"
# The fold lives in lc(), shared by every label comparison since #425 factored the split rule out.
sed '/^lc() {/s/ | tr .A-Z. .a-z.//' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#472: the case-fold mutant did not apply"; else
  m="$(bash "$MUT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "API,bug" 2>/dev/null | awk -F'\t' '$1=="labels"{print $2}')"
  m2="$(bash "$MUT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "Privacy,feature" 2>/dev/null | awk -F'\t' '$1=="labels"{print $2}')"
  [ "$m" = fail ] && [ "$m2" = fail ] && ok "#472: MUTANT: removing the case fold fails API,bug and Privacy,feature" || bad "#472: MUTANT survived: the case fold is not pinned ('$m' '$m2')"
fi

echo "check-ticket-mechanics: GWT structure"
expect "a specific negative Then passes" pass "$(outcome "$(run "$B" feature)" gwt)"
V="$(mkbody feature "vague.md" "$(printf 'Positive\n- Given: a user\n- When: they act\n- Then: it works\n\nNegative\n- Given: bad input\n- When: they act\n- Then: it should not work')")"
expect "a vague negative Then is REFERRED, not failed" referred "$(outcome "$(run "$V" feature)" gwt)"
Q="$(mkbody feature "quoted.md" "$(printf 'Positive\n- Given: a user\n- When: they act\n- Then: it works\n\nNegative\n- Given: bad input\n- When: they act\n- Then: rejected with "bad credentials"')")"
expect "a quoted message is mechanically specific" pass "$(outcome "$(run "$Q" feature)" gwt)"
L="$(mkbody feature "later.md" "$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 404 NOT_FOUND\n\nPositive\n- Given: f\n- When: g\n- Then: h\n\nNegative\n- Given: i\n- When: j\n- Then: it just breaks')")"
expect "REGRESSION: a LATER negative block's vague Then is still caught" referred "$(outcome "$(run "$L" feature)" gwt)"
T="$(mkbody feature "twowhen.md" "$(printf 'Positive\n- Given: a\n- When: b\n- When: c\n- Then: d\n\nNegative\n- Given: e\n- When: f\n- Then: 401')")"
expect "two When lines in one block fails" fail "$(outcome "$(run "$T" feature)" gwt)"
P="$(mkbody feature "posonly.md" "$(printf 'Positive\n- Given: a\n- When: b\n- Then: c')")"
expect "positive only fails" fail "$(outcome "$(run "$P" feature)" gwt)"
N="$(mkbody feature "nothen.md" "$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e')")"
expect "a negative block with no Then fails" fail "$(outcome "$(run "$N" feature)" gwt)"

echo "check-ticket-mechanics: unit and E2E specs"
expect "a named unit path passes" pass "$(outcome "$(run "$B" feature)" unit_tests)"
U="$(mkbody feature "bareunit.md" "" "add unit tests")"
expect "bare 'add unit tests' fails" fail "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "unitna.md" "" "N/A docs-only change")"
expect "a unit N/A is REFERRED, never auto-accepted" referred "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "bareNA.md" "" "N/A")"
expect "REGRESSION: a bare N/A is not read as a file path" referred "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "slash.md" "" "covers the and/or branch")"
expect "REGRESSION: prose containing a slash is not a path" fail "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "shortcircuit.md" "" "N/A docs-only change" "")"
expect "REGRESSION: a referred unit result does not hide an unusable E2E section" fail \
  "$(outcome "$(run "$U" feature)" e2e_tests)"
E="$(mkbody feature "e2ena.md" "" "" "N/A, this ticket changes no UI-visible behaviour at all")"
expect "an E2E N/A with a reason is REFERRED, since the E2E test specs section is the critic's call" referred "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2enapath.md" "" "" "N/A, covered by \`tests/unit/auth.test.ts\` instead")"
expect "REGRESSION: an N/A citing a path is still an N/A claim, not a pass" referred "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2ebare.md" "" "" "N/A")"
expect "an E2E N/A with no reason fails" fail "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2evague.md" "" "" "we will test it somehow")"
expect "an E2E section naming no path and claiming no N/A fails" fail "$(outcome "$(run "$E" feature)" e2e_tests)"

# --- #459: a slashless `na` mention is prose; the slash and phrase forms stay claims anywhere, and
# a slashless NA/na is a claim only as a line's first word (after an optional list, number,
# checkbox or bold prefix). Narrowing only the slashless form is deliberate: a missed claim becomes
# a blocking fail, while a false refer only misdirects, so the slash forms are not narrowed.
U="$(mkbody feature "na459a.md" "" 'assert the row reports `na` for an empty body')"
expect "#459: a backticked na mention in unit tests is prose, so it fails as no path (not a refer)" fail "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "na459b.md" "" 'In `scripts/test-x.sh`, assert the row reports na for an empty body')"
expect "#459: a bare na mention beside a named path passes" pass "$(outcome "$(run "$U" feature)" unit_tests)"
E="$(mkbody feature "na459c.md" "" "" 'assert the row reports `na` for an empty body')"
expect "#459: a backticked na mention in E2E tests is prose and fails" fail "$(outcome "$(run "$E" feature)" e2e_tests)"
S="$(mkbody feature "na459d.md" "$(printf -- 'The state machine reports `na` for an empty body, which the scenarios below do not cover at all.')")"
expect "#459: a backticked na mention in the scenarios section is prose, not an N/A claim" fail "$(outcome "$(run "$S" feature)" gwt)"
for form in 'NA' 'Unit tests: NA' 'E2E: na, no UI' '- Unit tests: NA, docs only' 'na: docs only' '- [ ] NA: docs only' '* NA, docs only' '1. NA, docs only' '2) na docs only' '**NA**: docs only' '- **NA** docs only' '*NA*: docs only' '_na_ docs only' '  NA'; do
  U="$(mkbody feature "na459claim.md" "" "$form")"
  expect "#459: the leading-NA claim form [$form] stays an N/A claim" referred "$(outcome "$(run "$U" feature)" unit_tests)"
done
for form in 'None needed, this is N/A for a docs-only change' 'None needed, this is n/a for a docs-only change' 'None needed, this is not applicable for a docs-only change' 'Docs only. N/A' ; do
  U="$(mkbody feature "na459mid.md" "" "$form")"
  expect "#459: the claim [$form] still refers anywhere in the line" referred "$(outcome "$(run "$U" feature)" unit_tests)"
done
U="$(mkbody feature "na459e.md" "" 'None needed, this is na for a docs-only change')"
expect "#459: a mid-sentence slashless na is not a claim (accepted: it fails as no path)" fail "$(outcome "$(run "$U" feature)" unit_tests)"
U="$(mkbody feature "na459f.md" "" 'nano editor tests')"
expect "#459: na as the start of a longer word is not a claim" fail "$(outcome "$(run "$U" feature)" unit_tests)"

echo "check-ticket-mechanics: documentation impact"
expect "naming a doc passes" pass "$(outcome "$(run "$B" feature)" docs_impact)"
D="$(mkbody feature "docsnone.md" "" "" "" "None, this changes no documented behaviour whatsoever")"
expect "a reasoned none is REFERRED, since the documentation currency section applies to every work ticket" referred "$(outcome "$(run "$D" feature)" docs_impact)"
D="$(mkbody feature "docsbare.md" "" "" "" "none")"
expect "a bare none fails" fail "$(outcome "$(run "$D" feature)" docs_impact)"
D="$(mkbody feature "docsvague.md" "" "" "" "we should think about it")"
expect "neither a doc nor a none claim fails" fail "$(outcome "$(run "$D" feature)" docs_impact)"


echo "check-ticket-mechanics: the four gaps found gating another project (#205)"
# --- gap 1: the evidence row was cut at 160 characters, so a long absent-list lost its tail. ---
# feature.yml's required-label list is 248 characters joined; bug.yml's 259. The count prefix is
# what makes any future truncation visible, and the companion below asserts the count is honest.
printf '<!-- template-version: 6 -->\n' > "$WORK/bare.md"
ev="$(run "$WORK/bare.md" feature | awk -F'\t' '$1=="sections"{print $3}')"
case "$ev" in "heading absent ("*"):"*) ok "gap 1: the absent list carries a count prefix" ;; *) bad "gap 1: no count prefix in '$ev'" ;; esac
# Re-anchored by #304: Codebase Context is gate-filled and no longer charged, so the last CHARGED
# feature.yml label is Documentation impact.
case "$ev" in *"; Documentation impact") ok "gap 1: the LAST charged feature.yml label survives (no 160-byte cut)" ;; *) bad "gap 1: the absent list is still truncated: '$ev'" ;; esac
n="$(printf '%s' "$ev" | sed -n 's/^heading absent (\([0-9]*\)):.*/\1/p')"
items="$(printf '%s' "${ev#*: }" | awk -F'; ' '{print NF}')"
expect "gap 1: the count equals the items listed (companion)" "$n" "$items"
B="$(mkbody bug "gap1-bug.md")"
sed 's/^filled in$/_No response_/; s/^- \[x\] acknowledged$/_No response_/' "$B" > "$WORK/gap1-empty.md"
ev="$(run "$WORK/gap1-empty.md" bug | awk -F'\t' '$1=="sections"{print $3}')"
case "$ev" in "required heading present but empty ("*"):"*"QA & Regression tests"*) ok "gap 1: the present-but-empty branch counts and keeps its tail too (bug.yml)" ;; *) bad "gap 1: present-but-empty branch: '$ev'" ;; esac

# --- gap 2: one marker regex for all seven sites; qualified and bold markers count, prose does not.
G2="$(mkbody feature "gap2.md" "$(printf 'Positive (happy path)\n- Given: a\n- When: b\n- Then: c\n\n**Negative** with a note\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
expect "gap 2: a parenthetical qualifier and a bold marker both count as blocks" pass "$(outcome "$(run "$G2" feature)" gwt)"
G2b="$(mkbody feature "gap2b.md" "$(printf 'Positive:\n- Given: a\n- When: b\n- Then: c\n\n**Negative:**\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
expect "gap 2: a trailing colon, bare or inside bold, counts" pass "$(outcome "$(run "$G2b" feature)" gwt)"
G2h="$(mkbody feature "gap2h.md" "$(printf '*Positive _and_ negative paths are covered.*\n\nPositive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
o="$(run "$G2h" feature)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="gwt"{print $3}')" in "1 positive and 1 negative"*) ok "gap 2: an emphasised prose line whose inner markup could pose as a closer is not a marker" ;; *) bad "gap 2: emphasised prose was counted as a block" ;; esac
G2g="$(mkbody feature "gap2g.md" "$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED\n\nPositive:\n- Given: f\n- When: g\n- Then: h\n\n**Negative (bad input)**\n- Given: i\n- When: j\n- Then: 400 BAD_INPUT')")"
o="$(run "$G2g" feature)"
expect "gap 2: a parenthetical INSIDE the bold markup is a marker (the ticket's own scenario)" pass "$(outcome "$o" gwt)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="gwt"{print $3}')" in "2 positive and 2 negative"*) ok "gap 2: and both pairs are counted" ;; *) bad "gap 2: the bold-with-parenthetical block was folded into the previous one" ;; esac
G2c="$(mkbody feature "gap2c.md" "$(printf 'Positive outcome expected here\nNegative scenarios are listed below.\n\nPositive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
o="$(run "$G2c" feature)"
expect "gap 2: a prose line starting with the bare word is NOT a block (near miss)" pass "$(outcome "$o" gwt)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="gwt"{print $3}')" in "1 positive and 1 negative"*) ok "gap 2: and the counts stay 1/1" ;; *) bad "gap 2: prose lines were counted as blocks" ;; esac
G2d="$(mkbody feature "gap2d.md" "$(printf 'Positively wrong\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
expect "gap 2: a longer word is not the marker" fail "$(outcome "$(run "$G2d" feature)" gwt)"
G2e="$(mkbody feature "gap2e.md" "$(printf 'Positive (a)\n- Given: a\n- When: b\n- When: bb\n- Then: c\n\n**Negative**\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
expect "gap 2: the When-count site recognises the qualified marker (two Whens still fail)" fail "$(outcome "$(run "$G2e" feature)" gwt)"
G2f="$(mkbody feature "gap2f.md" "$(printf 'Positive (a)\n- Given: a\n- When: b\n- Then: c\n\n**Negative** case\n- Given: d\n- When: e')")"
expect "gap 2: the missing-Then site recognises the bold marker" fail "$(outcome "$(run "$G2f" feature)" gwt)"

# --- #233: a ONE-LINE scenario is a shape this check cannot read, so it refers, never fails.
# `- Positive. Given a. When b. Then c.` carries a complete scenario that the marker regex cannot
# see (the marker must stand alone on its line), and v9 emitted `fail`, "0 positive, 0 negative":
# a heuristic miss that INVERTED the verdict, which the header forbids. The detector is separate
# from the marker regex and runs before the block count; the regexes are unchanged.
gwt_ev() { printf '%s\n' "$1" | awk -F'\t' '$1=="gwt"{print $3}'; }
# --- #359: the When-count evidence names a block by its anchored marker, not by a substring. A
# Negative block whose label CONTAINS the word Positive used to be reported as Positive.
wc_run() { run "$(mkbody feature "$1" "$2")" feature; }
wc_ev() { gwt_ev "$(wc_run "$1" "$2")"; }
P1='Positive\n- Given: a\n- When: b\n- Then: c'
N1='Negative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED'
N2='Negative\n- Given: d\n- When: e\n- When: ee\n- Then: 401 AUTH_FAILED'
o="$(wc_run wc1.md "$(printf "$P1\n\nNegative (the Positive path is blocked)\n- Given: d\n- When: e\n- When: ee\n- Then: 401 AUTH_FAILED")")"; ev="$(gwt_ev "$o")"
expect "#371: wc1's outcome is fail" fail "$(outcome "$o" gwt)"
case "$ev" in *"Positive: 2 When lines"*) bad "#371: wc1 also names a Positive block: $ev" ;; *) ok "#371: wc1 names no Positive block" ;; esac
case "$ev" in *"(Negative: 2 When lines)"*) ok "#359: a plain-parenthetical Negative label naming Positive is reported Negative" ;; *) bad "#359: labelled Negative misnamed: $ev" ;; esac
ev="$(wc_ev wc2.md "$(printf "$P1\n\n**Negative** guards the Positive path\n- Given: d\n- When: e\n- When: ee\n- Then: 401 AUTH_FAILED")")"
case "$ev" in *"(Negative: 2 When lines)"*) ok "#359: a bold Negative marker with Positive in the prose is reported Negative" ;; *) bad "#359: bold Negative misnamed: $ev" ;; esac
ev="$(wc_ev wc3.md "$(printf "Positive\n- Given: a\n- When: b\n- When: bb\n- Then: c\n\n$N1")")"
case "$ev" in *"(Positive: 2 When lines)"*) ok "#359: an unlabelled two-When Positive is still reported Positive" ;; *) bad "#359: Positive regressed: $ev" ;; esac
ev="$(wc_ev wc4.md "$(printf "Positive\n- Given: a\n- When: b\n- When: bb\n- Then: c\n\n$N2")")"
[ "$ev" = "each scenario block needs exactly one When (Positive: 2 When lines; Negative: 2 When lines)" ] && ok "#359/#365: both blocks at two Whens are named in order, joined by '; ' (whole-field equality)" || bad "#359/#365: two-block evidence wrong: $ev"
P2='Positive\n- Given: a\n- When: b\n- When: bb\n- Then: c'
ev="$(wc_ev wc8.md "$(printf "$P2\n\n$N2\n\n$P2")")"
W3="each scenario block needs exactly one When (Positive: 2 When lines; Negative: 2 When lines; Positive: 2 When lines)"
[ "$ev" = "$W3" ] && ok "#365: three offending blocks are joined by '; ' with no run-on pair (whole-field equality)" || bad "#365: three-block evidence wrong: $ev"
ev="$(wc_ev wc9.md "$(printf "$P2\n\n$N2\n\n$P2\n\n$N2")")"
[ "$ev" = "$W3" ] && ok "#365: four offending blocks name the first three only (the head -3 cap, whole-field equality)" || bad "#365: four-block evidence wrong: $ev"
o="$(wc_run wc5.md "$(printf "Positive (the Negative path is not taken)\n- Given: a\n- When: b\n- When: bb\n- Then: c\n\n$N1")")"; ev="$(gwt_ev "$o")"
expect "#371: wc5's outcome is fail" fail "$(outcome "$o" gwt)"
case "$ev" in *"Negative: "*) bad "#359: a Positive label naming Negative was misnamed: $ev" ;; *"(Positive: 2 When lines)"*) ok "#359: a Positive block whose label names Negative keeps its own name" ;; *) bad "#359: mirror case evidence wrong: $ev" ;; esac
expect "#359: the one-When mirror (Positive labelled with Negative) passes" pass "$(outcome "$(run "$(mkbody feature wc6.md "$(printf 'Positive (the Negative path is not taken)\n- Given: a\n- When: b\n- Then: c\n\n%b' "$N1")")" feature)" gwt)"
expect "#359: the one-When Negative labelled with Positive passes" pass "$(outcome "$(run "$(mkbody feature wc7.md "$(printf '%b\n\nNegative (the Positive path is blocked)\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED' "$P1")")" feature)" gwt)"
ev="$(gwt_ev "$(run "$G2e" feature)")"
case "$ev" in *"Positive: 2 When lines"*) case "$ev" in *Negative*) bad "#359: G2e evidence names Negative: $ev" ;; *) ok "#359: the G2e fixture reports Positive: 2 When lines only" ;; esac ;; *) bad "#359: G2e evidence wrong: $ev" ;; esac

O1="$(mkbody feature "one1.md" "$(printf -- '**Condition: x**\n- Positive. Given a valid token. When the endpoint is called. Then it returns 200.\n- Negative. Given a bad token. When the endpoint is called. Then 401 AUTH_FAILED.')")"
o="$(run "$O1" feature)"
expect "#233: a one-line bullet scenario (dot form) refers, never fails" referred "$(outcome "$o" gwt)"
case "$(gwt_ev "$o")" in *"one-line scenario"*"Positive. Given a valid token"*) ok "#233: and the evidence quotes the one-line bullet" ;; *) bad "#233: evidence does not quote the bullet: $(gwt_ev "$o")" ;; esac
O2="$(mkbody feature "one2.md" "$(printf -- '- Positive: Given a. When b. Then c.\n- Negative: Given d. When e. Then 401 AUTH_FAILED.')")"
expect "#233: the colon form refers too" referred "$(outcome "$(run "$O2" feature)" gwt)"
O3="$(mkbody feature "one3.md" "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\n- Negative: Given d. When e. Then 401 AUTH_FAILED.')")"
o="$(run "$O3" feature)"
expect "#233: a one-line Negative beside a block-shaped Positive refers" referred "$(outcome "$o" gwt)"
case "$(gwt_ev "$o")" in *"When lines"*) bad "#233: the mixed section emitted a When-count row" ;; *) ok "#233: and no When-count row is emitted for the mixed section" ;; esac
O4="$(mkbody feature "one4.md" "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\n- **Negative**: Given d. When e. Then 401 AUTH_FAILED.')")"
expect "#233: a bold one-liner is the same shape with different markup and refers" referred "$(outcome "$(run "$O4" feature)" gwt)"
O5="$(mkbody feature "one5.md" "$(printf -- '**Positive**: Given a. When b. Then c.\n**Negative**: Given d. When e. Then 401 AUTH_FAILED.')")"
expect "#233: a bold one-liner with no bullet (v9 failed it one site later with 0 When lines) refers" referred "$(outcome "$(run "$O5" feature)" gwt)"
O6="$(mkbody feature "one6.md" "$(printf -- '- Positive outcome expected here.\n- Negative cases are below.')")"
expect "#233: a bullet starting with the word, no punctuation and no Given/When/Then, still fails 0/0 (near miss)" fail "$(outcome "$(run "$O6" feature)" gwt)"
case "$(gwt_ev "$(run "$O6" feature)")" in *"found 0 positive, 0 negative"*) ok "#233: and the near miss keeps v9's message" ;; *) bad "#233: near-miss message changed" ;; esac

# --- #241: a REASONED N/A in the scenarios section refers, as check 5 refers one for unit and E2E
# tests; a bare N/A with no reason fails; and an N/A mentioned inside a real block pair is a block.
N1="$(mkbody feature "na1.md" "$(printf -- 'N/A: documentation only, no behaviour delta, nothing for a scenario to review.')")"
o="$(run "$N1" feature)"
expect "#241: a reasoned N/A in the scenarios section refers" referred "$(outcome "$o" gwt)"
case "$(gwt_ev "$o")" in *"claim N/A"*'section "GWT scenarios"'*) ok "#241: and the evidence is in check 5's shape" ;; *) bad "#241: evidence shape: $(gwt_ev "$o")" ;; esac
N2="$(mkbody feature "na2.md" "$(printf -- 'N/A.')")"
expect "#241: a bare N/A with no reason fails" fail "$(outcome "$(run "$N2" feature)" gwt)"
N3="$(mkbody feature "na3.md" "$(printf -- 'Positive\n- Given: a config whose field is N/A\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
o="$(run "$N3" feature)"
expect "#241: an N/A mentioned inside a real block pair is still a block pair (near miss)" pass "$(outcome "$o" gwt)"
N4="$(mkbody feature "na4.md" "$(printf -- 'The scenarios below cover the change; nothing is n/a here.\n\nPositive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')")"
expect "#241: a prose mention of n/a above real blocks is not an N/A claim (near miss)" pass "$(outcome "$(run "$N4" feature)" gwt)"
# Two mutants survived the first draft of these cases (review round 1): the `-z "$one_line"`
# guard on the N/A branch, and ONE_LINE's Then clause. Each gets the fixture that kills it.
N5="$(mkbody feature "na5.md" "$(printf -- '- Positive: Given N/A. When b. Then c.\n- Negative: Given d. When e. Then 401 AUTH_FAILED.')")"
case "$(gwt_ev "$(run "$N5" feature)")" in "one-line scenario"*) ok "#233/#241: a one-line scenario that mentions N/A is reported as the one-line form, not as an N/A claim" ;; *) bad "#233/#241: the N/A branch took a one-line scenario: $(gwt_ev "$(run "$N5" feature)")" ;; esac
O7="$(mkbody feature "one7.md" "$(printf -- '- Positive: Given a. When b.\n- Negative: Given d. When e.')")"
expect "#233: a one-line bullet with no Then is not a scenario and still fails 0/0 (near miss)" fail "$(outcome "$(run "$O7" feature)" gwt)"

# --- #479: the one-line detector is case-insensitive, so a lowercase one-liner refers like the
# capitalised one instead of failing 0/0. The rows marked guard fail before AND after the fix:
# they prove `-i` did not widen the match past a real scenario, not that the fix works.
one479() { mkbody feature "one479-$1.md" "$2"; }
gwt479() { gwt_ev "$(run "$1" feature)"; }
L1="$(one479 lkw '- Positive. given a user, when they click save, then the file is written.')"
expect "#479: lowercase given/when/then with a capitalised marker refers" referred "$(outcome "$(run "$L1" feature)" gwt)"
case "$(gwt479 "$L1")" in "one-line scenario form"*) ok "#479: and its evidence names the one-line scenario form" ;; *) bad "#479: lowercase keyword evidence: $(gwt479 "$L1")" ;; esac
L2="$(one479 lmk '- positive: Given a user, When they click save, Then the file is written.')"
expect "#479: a lowercase marker word refers" referred "$(outcome "$(run "$L2" feature)" gwt)"
case "$(gwt479 "$L2")" in "one-line scenario form"*) ok "#479: and its evidence names the one-line scenario form" ;; *) bad "#479: lowercase marker evidence: $(gwt479 "$L2")" ;; esac
L3="$(one479 cap '- Positive. Given a user, When they click save, Then the file is written.')"
expect "#479: the capitalised one-liner still refers" referred "$(outcome "$(run "$L3" feature)" gwt)"
L4="$(one479 nothen '- Positive. given a user, when they click save.')"
case "$(outcome "$(run "$L4" feature)" gwt)|$(gwt479 "$L4")" in "fail|"*"found 0 positive, 0 negative"*) ok "#479 guard: a lowercase one-liner with no then still fails 0/0" ;; *) bad "#479 guard: no-then lowercase: $(gwt479 "$L4")" ;; esac
L5="$(one479 nogiven '- positive: a user, when they click save, then the file is written.')"
case "$(outcome "$(run "$L5" feature)" gwt)|$(gwt479 "$L5")" in "fail|"*"found 0 positive, 0 negative"*) ok "#479 guard: a lowercase one-liner with no given still fails 0/0" ;; *) bad "#479 guard: no-given lowercase: $(gwt479 "$L5")" ;; esac
case "$(gwt479 "$O7")" in *"found 0 positive, 0 negative"*) ok "#479 guard: the O7 no-Then near miss keeps the 0/0 message" ;; *) bad "#479 guard: O7 message changed: $(gwt479 "$O7")" ;; esac
L6="$(one479 caps '- POSITIVE: GIVEN a, WHEN b, THEN c.')"
case "$(outcome "$(run "$L6" feature)" gwt)|$(gwt479 "$L6")" in "referred|one-line scenario form"*) ok "#479: an all-caps one-liner refers" ;; *) bad "#479: all caps: $(gwt479 "$L6")" ;; esac
L7="$(one479 mixed '- pOsItIvE: gIvEn a, wHeN b, tHeN c.')"
case "$(outcome "$(run "$L7" feature)" gwt)|$(gwt479 "$L7")" in "referred|one-line scenario form"*) ok "#479: a mixed-case one-liner refers" ;; *) bad "#479: mixed case: $(gwt479 "$L7")" ;; esac
L8="$(one479 bold '- **negative**: Given a, When b, Then c.')"
case "$(outcome "$(run "$L8" feature)" gwt)|$(gwt479 "$L8")" in "referred|one-line scenario form"*) ok "#479: a bold lowercase marker one-liner refers" ;; *) bad "#479: bold lowercase: $(gwt479 "$L8")" ;; esac
L9="$(one479 forgiven '- Positive. forgiven a user, when they click save, then the file is written.')"
case "$(outcome "$(run "$L9" feature)" gwt)|$(gwt479 "$L9")" in "fail|"*"found 0 positive, 0 negative"*) ok "#479 guard: forgiven is not given, so the word boundary still holds under -i" ;; *) bad "#479 guard: forgiven: $(gwt479 "$L9")" ;; esac
# A valid block pair is judged by its blocks (#479 review round 1): the one-line detector is
# ignored where a Positive and a Negative block both exist, unless a block header is itself a
# one-liner owning no When line (O5's shape). This REVERSES the side effect the ticket accepted,
# so a stray one-liner inside a valid pair passes again, in either case.
L10="$(one479 stray "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\npositive: given a prose note, when read, then ignored.')")"
case "$(outcome "$(run "$L10" feature)" gwt)|$(gwt479 "$L10")" in "pass|1 positive and 1 negative blocks"*) ok "#479: stray lowercase one-liner in a valid pair passes (judged by its blocks)" ;; *) bad "#479: stray lowercase one-liner in a valid pair: $(outcome "$(run "$L10" feature)" gwt) $(gwt479 "$L10")" ;; esac
L11="$(one479 straycap "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\nPositive: Given a prose note, When read, Then ignored.')")"
expect "#479: a capitalised stray one-liner in a valid pair passes too" pass "$(outcome "$(run "$L11" feature)" gwt)"
L12="$(one479 boldhdr "$(printf -- '**Positive**: given a, when b, then c\n- Given: a\n- When: b\n- When: b2\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$L12" feature)" gwt)|$(gwt479 "$L12")" in "fail|"*"Positive: 2 When lines"*) ok "#479: a bold header that is also a lowercase one-liner keeps its block's When count fail" ;; *) bad "#479: bold one-liner header hid the When count: $(outcome "$(run "$L12" feature)" gwt) $(gwt479 "$L12")" ;; esac
L13="$(one479 mixed2 "$(printf -- '**Positive**: Given a. When b. Then c.\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID')")"
expect "#479 guard: a bold one-liner header with no When line beside a real Negative block still refers" referred "$(outcome "$(run "$L13" feature)" gwt)"
# Review round 2: a header that owns When lines is a block even when the pair is INCOMPLETE, so a
# missing polarity still fails; only a header owning no When line, or a non-header one-liner,
# keeps the one-line form there. This also flips the capitalised form, which referred since #233.
L14="$(one479 halfhdr "$(printf -- '**Positive**: given a, when b, then c\n- Given: a\n- When: b\n- When: b2\n- Then: c')")"
case "$(outcome "$(run "$L14" feature)" gwt)|$(gwt479 "$L14")" in "fail|"*"found 1 positive, 0 negative"*) ok "#479: a lowercase one-liner header owning When lines with no Negative block fails the missing polarity" ;; *) bad "#479: incomplete pair header: $(outcome "$(run "$L14" feature)" gwt) $(gwt479 "$L14")" ;; esac
L15="$(one479 halfneg "$(printf -- '**Negative**: given d, when e, then 400 INVALID\n- Given: d\n- When: e\n- When: e2\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$L15" feature)" gwt)|$(gwt479 "$L15")" in "fail|"*"found 0 positive, 1 negative"*) ok "#479: the Negative mirror with no Positive block fails too" ;; *) bad "#479: incomplete pair mirror: $(outcome "$(run "$L15" feature)" gwt) $(gwt479 "$L15")" ;; esac
L16="$(one479 halfcap "$(printf -- '**Positive**: Given a, When b, Then c\n- Given: a\n- When: b\n- Then: c')")"
case "$(outcome "$(run "$L16" feature)" gwt)|$(gwt479 "$L16")" in "fail|"*"found 1 positive, 0 negative"*) ok "#479: the capitalised header owning a When line with no Negative block fails (referred before)" ;; *) bad "#479: incomplete pair capitalised: $(outcome "$(run "$L16" feature)" gwt) $(gwt479 "$L16")" ;; esac
L17="$(one479 halfline "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\n- Negative: given d, when e, then 400 INVALID')")"
expect "#479 guard: a Positive block beside a lowercase Negative one-liner still refers" referred "$(outcome "$(run "$L17" feature)" gwt)"

# --- #487: a no-When one-line header keeps the one-line form, but no longer hides another block's
# failure. The refer branch judges the When count, then the missing Then, on the field with every
# no-When one-line header block removed, and refers only when both pass. Evidence is pinned by
# whole-field equality, as the wc_ev rows pin it. L13 above is the valid-block guard.
WC487P='each scenario block needs exactly one When (Positive: 2 When lines)'
R1="$(one479 rep "$(printf -- '**Positive**: Given a. When b. Then c.\n\nNegative\n- Given: d\n- When: e\n- When: e2\n- Then: 400 INVALID')")"
o="$(outcome "$(run "$R1" feature)" gwt)"; ev="$(gwt479 "$R1")"
expect "#487: the reproduction (no-When Positive header, Negative block with two When lines) fails" fail "$o"
[ "$ev" = 'each scenario block needs exactly one When (Negative: 2 When lines)' ] && ok "#487: and the evidence names only the Negative block (whole-field equality)" || bad "#487: reproduction evidence: $ev"
case "$ev" in *"Positive: 0 When lines"*) bad "#487: the no-When header was counted as a block: $ev" ;; *) ok "#487: the no-When header is never reported as Positive: 0 When lines" ;; esac
R2="$(one479 nothen "$(printf -- '**Positive**: Given a. When b. Then c.\n\nNegative\n- Given: d\n- When: e')")"
case "$(outcome "$(run "$R2" feature)" gwt)|$(gwt479 "$R2")" in "fail|a Negative block has no Then line") ok "#487: the reproduction with ONE When line and no Negative Then fails the missing Then" ;; *) bad "#487: missing Then: $(outcome "$(run "$R2" feature)" gwt) $(gwt479 "$R2")" ;; esac
R3="$(one479 vague "$(printf -- '**Positive**: Given a. When b. Then c.\n\nNegative\n- Given: d\n- When: e\n- Then: it fails')")"
case "$(outcome "$(run "$R3" feature)" gwt)|$(gwt479 "$R3")" in "referred|one-line scenario form"*) ok "#487: the vague-Then variant stays referred with the one-line evidence (a vague Then is never failed)" ;; *) bad "#487: vague Then: $(outcome "$(run "$R3" feature)" gwt) $(gwt479 "$R3")" ;; esac
R4="$(one479 mirror "$(printf -- '**Negative**: Given d. When e. Then 400 INVALID.\n\nPositive\n- Given: a\n- When: b\n- Then: c')")"
o="$(outcome "$(run "$R4" feature)" gwt)"; ev="$(gwt479 "$R4")"
case "$o|$ev" in *"When lines"*) bad "#487: the mirror counted the no-When Negative header: $o $ev" ;; "referred|one-line scenario form"*) ok "#487: a no-When Negative header beside a valid Positive block refers (mirror)" ;; *) bad "#487: mirror: $o $ev" ;; esac
R5="$(one479 mirror2 "$(printf -- '**Negative**: Given d. When e. Then 400 INVALID.\n\nPositive\n- Given: a\n- When: b\n- When: b2\n- Then: c')")"
case "$(outcome "$(run "$R5" feature)" gwt)|$(gwt479 "$R5")" in "fail|$WC487P") ok "#487: the mirror beside a two-When Positive block fails with exactly Positive: 2 When lines" ;; *) bad "#487: mirror two When: $(outcome "$(run "$R5" feature)" gwt) $(gwt479 "$R5")" ;; esac
R6="$(one479 bullet "$(printf -- 'Positive\n- Given: a\n- When: b\n- When: b2\n- Then: c\n\n- Negative: Given d. When e. Then 400 INVALID.')")"
case "$(outcome "$(run "$R6" feature)" gwt)|$(gwt479 "$R6")" in "fail|$WC487P") ok "#487: a bullet one-liner beside a two-When Positive block fails with exactly Positive: 2 When lines" ;; *) bad "#487: bullet sibling: $(outcome "$(run "$R6" feature)" gwt) $(gwt479 "$R6")" ;; esac
# The WHOLE header block is removed, not just its line: a `- Then:` bullet under a no-When Negative
# header must not stand in for the Then the Negative block above it lacks.
R7="$(one479 thenhdr "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n\n**Negative**: Given d. When e. Then 400 INVALID.\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$R7" feature)" gwt)|$(gwt479 "$R7")" in "fail|a Negative block has no Then line") ok "#487: a Then bullet under a removed header does not cover the Negative block above it" ;; *) bad "#487: header Then bullet: $(outcome "$(run "$R7" feature)" gwt) $(gwt479 "$R7")" ;; esac
case "$(outcome "$(run "$O5" feature)" gwt)|$(gwt479 "$O5")" in "referred|one-line scenario form"*) ok "#487 guard: O5's two bold one-line headers and no block still refer" ;; *) bad "#487 guard: O5: $(gwt479 "$O5")" ;; esac
case "$(gwt479 "$O3")" in "one-line scenario form"*) ok "#487 guard: O3 still refers with the one-line evidence" ;; *) bad "#487 guard: O3: $(gwt479 "$O3")" ;; esac
# Review round 1: the header removal is case-insensitive, as the detector is. A lowercase no-When
# header must be removed like the capitalised one.
R8="$(one479 lowhdr "$(printf -- '**Positive**: given a, when b, then c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$R8" feature)" gwt)|$(gwt479 "$R8")" in "referred|one-line scenario form"*) ok "#487: a lowercase no-When one-line header beside a valid Negative block refers" ;; *) bad "#487: lowercase header, valid block: $(outcome "$(run "$R8" feature)" gwt) $(gwt479 "$R8")" ;; esac
R9="$(one479 lowrep "$(printf -- '**Positive**: given a, when b, then c\n\nNegative\n- Given: d\n- When: e\n- When: e2\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$R9" feature)" gwt)|$(gwt479 "$R9")" in "fail|each scenario block needs exactly one When (Negative: 2 When lines)") ok "#487: the lowercase reproduction fails naming only the Negative block" ;; *) bad "#487: lowercase reproduction: $(outcome "$(run "$R9" feature)" gwt) $(gwt479 "$R9")" ;; esac
# Review round 1: a bold grouping header above bullet one-liners owns no When line and is no
# block the scans can read. With no pair it referred before #487 and must still refer.
R10="$(one479 grp1 "$(printf -- '**Positive**\n- Positive: Given a valid token. When the endpoint is called. Then 200.\n- Negative: Given a bad token. When the endpoint is called. Then 401 AUTH_FAILED.')")"
case "$(outcome "$(run "$R10" feature)" gwt)|$(gwt479 "$R10")" in "referred|one-line scenario form"*) ok "#487: a grouping header above bullet one-liners refers, never 0 When lines" ;; *) bad "#487: grouping header: $(outcome "$(run "$R10" feature)" gwt) $(gwt479 "$R10")" ;; esac
# Both grouping headers make a pair. #479 failed this with 0 When lines on both; it refers now.
R11="$(one479 grp2 "$(printf -- '**Positive**\n- Positive: Given a valid token. When the endpoint is called. Then 200.\n\n**Negative**\n- Negative: Given a bad token. When the endpoint is called. Then 401 AUTH_FAILED.')")"
case "$(outcome "$(run "$R11" feature)" gwt)|$(gwt479 "$R11")" in "referred|one-line scenario form"*) ok "#487: Positive and Negative grouping headers holding only bullet one-liners refer (reverses the #479-era fail)" ;; *) bad "#487: both grouping headers: $(outcome "$(run "$R11" feature)" gwt) $(gwt479 "$R11")" ;; esac
# And a grouping header beside a real block that fails is still no shield.
R12="$(one479 grp3 "$(printf -- '**Positive**\n- Positive: Given a. When b. Then c.\n\nNegative\n- Given: d\n- When: e\n- When: e2\n- Then: 400 INVALID')")"
case "$(outcome "$(run "$R12" feature)" gwt)|$(gwt479 "$R12")" in "fail|each scenario block needs exactly one When (Negative: 2 When lines)") ok "#487: a grouping header beside a two-When Negative block still fails on that block" ;; *) bad "#487: grouping header beside a failing block: $(outcome "$(run "$R12" feature)" gwt) $(gwt479 "$R12")" ;; esac
# Review round 2: a block written in block grammar (`- Given:`/`- Then:`) that lacks its When is a
# real block with 0 When lines, even when a one-liner sits under it; it must fail, never refer.
R13="$(one479 gtwhen "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: 200\n\nNegative\n- Given: d\n- Then: 400 INVALID\n- Negative: Given an expired token. When called. Then 401 AUTH_FAILED.')")"
case "$(outcome "$(run "$R13" feature)" gwt)|$(gwt479 "$R13")" in "fail|each scenario block needs exactly one When (Negative: 0 When lines)") ok "#487: a Given/Then Negative block missing its When fails even with a one-liner under it" ;; *) bad "#487: Given/Then block with a one-liner: $(outcome "$(run "$R13" feature)" gwt) $(gwt479 "$R13")" ;; esac
R14="$(one479 gonly "$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: 200\n\nNegative\n- Given: d\n- Negative: Given x. When y. Then 401.')")"
case "$(outcome "$(run "$R14" feature)" gwt)" in fail) ok "#487: a Negative block with a Given, no When and no Then fails even with a one-liner under it" ;; *) bad "#487: Given-only block with a one-liner: $(outcome "$(run "$R14" feature)" gwt) $(gwt479 "$R14")" ;; esac
case "$(outcome "$(run "$O7" feature)" gwt)|$(gwt479 "$O7")" in "fail|needs at least one Positive and one Negative block (found 0 positive, 0 negative)") ok "#487 guard: the O7 near miss keeps its exact 0/0 evidence" ;; *) bad "#487 guard: O7: $(gwt479 "$O7")" ;; esac

# --- #490: a line inside a fenced code block is plain text to every GWT block scan. Check 4 reads
# two copies of the field: the raw one for has_content, looks_na, long_enough and first_line, and a
# fence-free one (fence_free(), #485's grammar) for every block scan. Rows marked guard give the
# same outcome before the fix; the rest fail on the 54562d0 checker.
FB='```'
P490="$(printf -- 'Positive\n- Given: a\n- When: b\n- Then: c')"
GWT490='1 positive and 1 negative blocks, each Then specific'
g490() { printf '%s|%s' "$(outcome "$(run "$1" feature)" gwt)" "$(gwt479 "$1")"; }
# The ticket's reproduction: a fence indented 2 spaces between the Negative When and its real Then.
F490R="$(one479 f490rep "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n\n  The one-line form we accept:\n  %stext\n  **Negative**: Given d. When e. Then 400 INVALID.\n  %s\n- Then: 400 INVALID' "$P490" "$FB" "$FB")")"
expect "#490: the reproduction (fenced one-liner between a Negative When and its real Then) passes" "pass|$GWT490" "$(g490 "$F490R")"
F490W="$(one479 f490pair "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\n**Positive**: Given a. When b. Then c.\n%s' "$P490" "$FB" "$FB")")"
expect "#490: a fenced bold one-liner inside a valid pair passes, not referred (the #479 shape)" "pass|$GWT490" "$(g490 "$F490W")"
F490N="$(one479 f490noth "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n\n  %stext\n  **Negative**: Given d. When e. Then 400 INVALID.\n  %s' "$P490" "$FB" "$FB")")"
expect "#490 guard: the reproduction with its real Then removed still fails the missing Then" "fail|a Negative block has no Then line" "$(g490 "$F490N")"
F490H="$(one479 f490neg "$(printf -- '%s\n\n%s\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n%s' "$P490" "$FB" "$FB")")"
expect "#490: a Negative header that exists only inside a fence is not counted" "fail|needs at least one Positive and one Negative block (found 1 positive, 0 negative)" "$(g490 "$F490H")"
# Fence-only fields (decided in the ticket, round 2). A pair only inside a fence has no real
# blocks: accepted pass-to-fail. Keep N/A out of this fixture, since looks_na reads the raw field.
F490P="$(one479 f490fpair "$(printf -- 'The shape we expect:\n\n%s\n%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n%s' "$FB" "$P490" "$FB")")"
expect "#490: a complete pair quoted only inside a fence fails 0/0 (accepted pass-to-fail)" "fail|needs at least one Positive and one Negative block (found 0 positive, 0 negative)" "$(g490 "$F490P")"
# A fenced-only reasoned N/A stays referred: looks_na and first_line read the RAW field, so the
# evidence quotes the fence opener, the field's first non-blank line.
F490A="$(one479 f490na "$(printf -- '%s\nN/A: a docs-only change with no behaviour delta\n%s' "$FB" "$FB")")"
expect "#490 guard: a fence holding only a reasoned N/A stays referred, evidence read from the raw field" \
  "referred|scenarios claim N/A; legitimate only where section \"GWT scenarios\" finds no behaviour delta: $FB" "$(g490 "$F490A")"
# A field whose only scenario is a fenced one-liner fails 0/0 where it referred: intended.
F490O="$(one479 f490one "$(printf -- '%s\n- Positive: Given a. When b. Then c.\n- Negative: Given d. When e. Then 400 INVALID.\n%s' "$FB" "$FB")")"
expect "#490: a field whose only scenarios are fenced one-liners fails 0/0 (referred before, intended)" "fail|needs at least one Positive and one Negative block (found 0 positive, 0 negative)" "$(g490 "$F490O")"
F490T="$(one479 f490two "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\nPositive\n- Given: a\n- When: b\n- When: b2\n- Then: c\n%s' "$P490" "$FB" "$FB")")"
expect "#490: a fenced Positive example with two When lines beside a valid pair passes" "pass|$GWT490" "$(g490 "$F490T")"
F490X="$(one479 f490two2 "$(printf -- 'Positive\n- Given: a\n- When: b\n- When: b2\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\n**Positive**: Given a. When b. Then c.\n%s' "$FB" "$FB")")"
expect "#490 guard: a real second When outside the fence still fails" "fail|each scenario block needs exactly one When (Positive: 2 When lines)" "$(g490 "$F490X")"
# Unfenced behaviour is unchanged: the #487 R1 shape is the guard, and R1 to R14 above still hold.
expect "#490 guard: an unfenced no-When one-line header beside a two-When Negative block still fails" "fail|each scenario block needs exactly one When (Negative: 2 When lines)" "$(g490 "$R1")"
expect "#490 guard: unfenced Positive and Negative headers are both counted" "pass|$GWT490" "$(g490 "$(one479 f490plain "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID' "$P490")")")"
# The fence grammar is #485's: indent 0 to 3 is a fence, 4 is not. A 4-space backtick line is no
# fence under that grammar, so the bold one-liner after it stays visible and the field is decided
# as the unfenced shape is: a no-When one-line header beside a valid pair refers (L13's outcome).
F490I3="$(one479 f490ind3 "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n   %s\n**Positive**: Given a. When b. Then c.\n   %s' "$P490" "$FB" "$FB")")"
expect "#490: a fence indented 3 spaces hides its one-liner" "pass|$GWT490" "$(g490 "$F490I3")"
F490I4="$(one479 f490ind4 "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n    %s\n**Positive**: Given a. When b. Then c.\n    %s' "$P490" "$FB" "$FB")")"
case "$(g490 "$F490I4")" in "referred|one-line scenario form"*) ok "#490 guard: a backtick line indented 4 spaces is no fence, so its one-liner refers as unfenced" ;; *) bad "#490: 4-space fence: $(g490 "$F490I4")" ;; esac
F490TL="$(one479 f490tilde "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n~~~\n**Negative**: Given d. When e. Then 400 INVALID.\n~~~' "$P490")")"
expect "#490: a tilde fence quoting the one-line form passes" "pass|$GWT490" "$(g490 "$F490TL")"
# An unclosed fence runs to the end of the body, so a Negative block with no Then after it is hidden.
F490U="$(one479 f490open "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\nNegative\n- Given: x\n- When: y' "$P490" "$FB")")"
expect "#490: an unclosed fence hides every scenario line after its opener" "pass|$GWT490" "$(g490 "$F490U")"
F490S="$(one479 f490short "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n````\n%s\nNegative\n- Given: x\n- When: y\n````' "$P490" "$FB")")"
expect "#490: three backticks do not close a four-backtick fence, so what follows stays hidden" "pass|$GWT490" "$(g490 "$F490S")"
F490B="$(one479 f490bash "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\n%sbash\nNegative\n- Given: x\n- When: y\n%s' "$P490" "$FB" "$FB" "$FB")")"
expect "#490: a backtick line followed by text closes nothing, so what follows stays hidden" "pass|$GWT490" "$(g490 "$F490B")"
# The vague-Then scan reads the fence-free copy: a fenced vague Then above the real specific one
# was the block's first Then, so the field referred.
F490V="$(one479 f490vague "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n%s\n- Then: it fails\n%s\n- Then: 400 INVALID' "$P490" "$FB" "$FB")")"
expect "#490: a fenced vague Then does not stand in for the block's real specific Then" "pass|$GWT490" "$(g490 "$F490V")"
# Round 1, L1: headers outside the fences with every bullet inside them. It passed before #490 and
# now fails 0/0 When lines (an accepted change, named in the script); the evidence says why.
F490L="$(one479 f490hdr "$(printf -- '**Positive**\n%s\n- Given: a\n- When: b\n- Then: c\n%s\n\n**Negative**\n%s\n- Given: x\n- When: y\n- Then: 401 with AUTH_FAILED\n%s' "$FB" "$FB" "$FB" "$FB")")"
expect "#490: headers outside fences with their bullets inside fail 0 When lines, naming the fences (accepted pass-to-fail)" \
  "fail|each scenario block needs exactly one When (Positive: 0 When lines; Negative: 0 When lines) (lines inside a fenced code block are not read)" "$(g490 "$F490L")"
# Round 1, L2: fence_free() strips a CR and trailing blanks before it tests a fence line.
F490C="$(one479 f490crlf "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n\n  The one-line form we accept:\n  %stext\n  **Negative**: Given d. When e. Then 400 INVALID.\n  %s\n- Then: 400 INVALID' "$P490" "$FB" "$FB" | sed 's/$/\r/')")"
grep -q $'^  ```\r$' "$F490C" && ok "#490: the CRLF fixture's closing fence carries a CR (fixture sanity)" || bad "#490: the CRLF fixture has no CR on its fence"
expect "#490: a CRLF scenarios field closes its fence (the reproduction passes)" "pass|$GWT490" "$(g490 "$F490C")"
F490E="$(one479 f490trail "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n%s   \n**Negative**: Given d. When e. Then 400 INVALID.\n%s   \n- Then: 400 INVALID' "$P490" "$FB" "$FB")")"
expect "#490: a fence whose opener and closer carry trailing blanks still opens and closes" "pass|$GWT490" "$(g490 "$F490E")"
# Round 2: the note appears only where the fences can be the cause. A real second When, or a real
# missing Then, beside an unrelated fenced example gets no note; a fenced Then or When that the
# failing block needed gets it, on every call site.
OL490='**Positive**: Given a. When b. Then c.'
F490NB="$(one479 f490nb "$(printf -- 'Positive\n- Given: a\n- When: b\n- When: b2\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n\n%s\n- When: the client posts /login\n%s' "$FB" "$FB")")"
expect "#490: a real second When beside a fenced example When gets no fence note" "fail|each scenario block needs exactly one When (Positive: 2 When lines)" "$(g490 "$F490NB")"
F490NC="$(one479 f490nc "$(printf -- '%s\n%s\n- Then: 200 OK\n%s\n\nNegative\n- Given: d\n- When: e' "$P490" "$FB" "$FB")")"
expect "#490: a real missing Then beside a fenced example Then gets no fence note" "fail|a Negative block has no Then line" "$(g490 "$F490NC")"
F490NE="$(one479 f490ne "$(printf -- '%s\n\nNegative\n- Given: d\n- When: e\n%s\n- Then: 400 INVALID\n%s' "$P490" "$FB" "$FB")")"
expect "#490: a Negative block whose only Then is fenced names the fences (block branch)" "fail|a Negative block has no Then line (lines inside a fenced code block are not read)" "$(g490 "$F490NE")"
F490NF="$(one479 f490nf "$(printf -- '%s\n\nNegative\n%s\n- Given: x\n- When: y\n- Then: 401 AUTH_FAILED\n%s' "$OL490" "$FB" "$FB")")"
expect "#490: a one-liner beside a Negative block whose bullets are fenced names the fences (one-line branch, When)" "fail|each scenario block needs exactly one When (Negative: 0 When lines) (lines inside a fenced code block are not read)" "$(g490 "$F490NF")"
F490NT="$(one479 f490nt "$(printf -- '%s\n\nNegative\n- Given: x\n- When: y\n%s\n- Then: 401 AUTH_FAILED\n%s' "$OL490" "$FB" "$FB")")"
expect "#490: a one-liner beside a Negative block whose only Then is fenced names the fences (one-line branch, Then)" "fail|a Negative block has no Then line (lines inside a fenced code block are not read)" "$(g490 "$F490NT")"
F490NH="$(one479 f490nh "$(printf -- '%s\n\nNegative\n- Given: x\n- When: y\n- When: y2\n- Then: 401 AUTH_FAILED\n%s\n- Then: example\n%s' "$OL490" "$FB" "$FB")")"
expect "#490: a one-liner beside a real two-When block and a fenced Then gets no fence note" "fail|each scenario block needs exactly one When (Negative: 2 When lines)" "$(g490 "$F490NH")"
F490NG="$(one479 f490ng "$(printf -- 'Positive\n- Given: a\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 400 INVALID\n%s\n- Then: example\n%s' "$FB" "$FB")")"
expect "#490: a real 0-When block beside a fenced Then (no fenced When) gets no fence note" "fail|each scenario block needs exactly one When (Positive: 0 When lines)" "$(g490 "$F490NG")"
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$WORK/mawk490"; printf '#!/bin/sh\nexec mawk "$@"\n' > "$WORK/mawk490/awk"; chmod +x "$WORK/mawk490/awk"
  expect "#490: portability: the 2-space reproduction passes under mawk" "pass|$GWT490" "$(PATH="$WORK/mawk490:$PATH" g490 "$F490R")"
  expect "#490: portability: the 3-space fence hides its one-liner under mawk" "pass|$GWT490" "$(PATH="$WORK/mawk490:$PATH" g490 "$F490I3")"
else
  ok "#490: portability: mawk not on PATH, fence rows under mawk skipped"
fi

# --- gap 3: role detection by id then label, E2E before integration, no --e2e-label. ---
# An optional fourth field is the field's description line, and an optional fifth, `gate-owned`,
# adds that YAML comment to the field block (#304); every older call keeps its shape.
mktpl() {  # mktpl <out> <fields as "id|label|required[|description[|gate-owned]]" ...>
  local out="$1"; shift; { echo 'body:'; for f in "$@"; do IFS='|' read -r id lab req desc cmt <<EOF
$f
EOF
  printf '  - type: textarea\n    id: %s\n' "$id"
  [ "$cmt" = gate-owned ] && printf '    # gate-owned\n'
  printf '    attributes:\n      label: %s\n' "$lab"
  [ -n "$desc" ] && printf '      description: %s\n' "$desc"
  printf '    validations:\n      required: %s\n' "$req"; done; } > "$out"; }
mktpl "$WORK/hubbub.yml" "summary|Summary|true" "integration_tests|Integration / subprocess test scenarios|true" "docs|Documentation impact|true"
printf '<!-- template-version: 6 -->\n\n### Summary\n\nx\n\n### Integration / subprocess test scenarios\n\n- [ ] `tests/integration/spawn.test.ts` spawns the child\n\n### Documentation impact\n\nUpdates `docs/x.md`\n' > "$WORK/hubbub.md"
o="$(bash "$SCRIPT" --body "$WORK/hubbub.md" --template "$WORK/hubbub.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null)"
expect "gap 3: a section renamed to Integration in both id and label is judged, not referred" pass "$(outcome "$o" e2e_tests)"
mktpl "$WORK/tie.yml" "integration_tests|Integration tests|true" "e2e_tests|Browser flows|true"
printf '<!-- template-version: 6 -->\n\n### Integration tests\n\nprose with no path at all\n\n### Browser flows\n\n- [ ] `tests/e2e/login.spec.ts`\n' > "$WORK/tie.md"
o="$(bash "$SCRIPT" --body "$WORK/tie.md" --template "$WORK/tie.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null)"
expect "gap 3: an E2E-named id outranks an integration-named section listed before it (tie-break)" pass "$(outcome "$o" e2e_tests)"
mktpl "$WORK/idonly.yml" "e2e_tests|Browser flows|true"
printf '<!-- template-version: 6 -->\n\n### Browser flows\n\n- [ ] `tests/e2e/login.spec.ts`\n' > "$WORK/idonly.md"
o="$(bash "$SCRIPT" --body "$WORK/idonly.md" --template "$WORK/idonly.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null)"
expect "gap 3: the id decides when the label says nothing" pass "$(outcome "$o" e2e_tests)"
B="$(mkbody security "gap3-sec.md")"
expect "gap 3: a template with no E2E-shaped section at all still refers" referred "$(outcome "$(run "$B" security)" e2e_tests)"
# A non-test "Integration" section must NOT be taken for the E2E role: v6 referred this, and a
# bare `integration` pattern turned it into a FAIL for naming no path, the forbidden direction.
mktpl "$WORK/design-int.yml" "summary|Summary|true" "integration_points|Integration points|true"
printf '<!-- template-version: 6 -->\n\n### Summary\n\nx\n\n### Integration points\n\nTalks to the billing service over its queue.\n' > "$WORK/design-int.md"
o="$(bash "$SCRIPT" --body "$WORK/design-int.md" --template "$WORK/design-int.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null)"
expect "gap 3: a prose Integration section without test or scenario in its name is still referred, never failed" referred "$(outcome "$o" e2e_tests)"
bash "$SCRIPT" --body "$WORK/idonly.md" --template "$WORK/idonly.yml" --e2e-label x >/dev/null 2>&1
[ $? -ne 0 ] && ok "gap 3: there is no --e2e-label option" || bad "gap 3: --e2e-label was accepted"
dump="$(bash "$SCRIPT" --body "$WORK/idonly.md" --template "$WORK/idonly.yml" --dump-fields)"
expect "gap 3: --dump-fields keeps its two-column contract" "Browser flows	yes" "$dump"

# --- gap 4: a template's own value:/placeholder: sub-headings are content inside THEIR field. ---
# feature.yml renders E2E's placeholder as `### Happy path` / `### Unhappy path`; on a web-form
# body every label is `###` too, so those two used to END the section: E2E read as empty (one
# false fail) and e2e_tests had no content (a second). The kit's own template, failing itself.
B="$(mkbody feature "gap4.md" "$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')" '- [ ] `tests/unit/auth.test.ts` valid input' "$(printf '### Happy path\n- [ ] `tests/e2e/login.spec.ts` user sees the screen\n\n### Unhappy path\n- [ ] API returns 500 -> retry button')")"
o="$(run "$B" feature)"
expect "gap 4: E2E filled under the placeholder sub-headings is present and filled" pass "$(outcome "$o" sections)"
expect "gap 4: and its content is judged" pass "$(outcome "$o" e2e_tests)"
python3 - "$B" "$WORK/gap4-other.md" <<'PY'
import sys
s=open(sys.argv[1]).read()
before=s
s=s.replace("### Unit tests\n\n- [ ] `tests/unit/auth.test.ts` valid input\n","### Unit tests\n\n_No response_\n\n### Happy path\n- [ ] `tests/unit/auth.test.ts`\n",1)
assert s != before, "fixture anchor did not match"
open(sys.argv[2],"w").write(s)
PY
o="$(run "$WORK/gap4-other.md" feature)"
expect "gap 4: a sub-heading belonging to ANOTHER field still ends this one (scoped per field)" fail "$(outcome "$o" unit_tests)"

# --- mutants, in the shape of the suite's other companions: a scratch copy, one line altered. ---
MUT="$WORK/mut.sh"
sed 's/cut -c1-1000/cut -c1-160/' "$SCRIPT" > "$MUT"
grep -q 'cut -c1-1000' "$SCRIPT" && ok "mutant ledger: the script carries the 1000-byte bound" || bad "mutant ledger: bound line not found"
ev="$(bash "$MUT" --body "$WORK/bare.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null | awk -F'\t' '$1=="sections"{print $3}')"
n="$(printf '%s' "$ev" | sed -n 's/^heading absent (\([0-9]*\)):.*/\1/p')"; items="$(printf '%s' "${ev#*: }" | awk -F'; ' '{print NF}')"
[ "$n" != "$items" ] && ok "mutant: with the old 160-byte cut the count disagrees with the items (the companion can fail)" || bad "mutant: the companion did not notice the cut"

# #459 mutant: restore the slashless `n/?a` alternation on a copy; the na-mention rows must flip to referred.
grep -qF 'n/a([^a-z]|$)|not applicable|^[[:space:]]*' "$SCRIPT" && ok "mutant ledger: the script carries the narrowed looks_na (#459)" || bad "mutant ledger: #459 looks_na not found"
sed "s#^looks_na()   { grep -qiE '[^']*'#looks_na()   { grep -qiE '(^|[^a-z])n/?a([^a-z]|\$)|not applicable'#" "$SCRIPT" > "$MUT"
grep -qF "n/?a" "$MUT" && ok "mutant ledger: the #459 mutant carries the old n/?a" || bad "mutant ledger: #459 mutant not built"
mrun() { bash "$MUT" --body "$1" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null; }
expect "mutant: the old n/?a reads the unit mention as a claim again (the #459 unit row can fail)" referred "$(outcome "$(mrun "$WORK/na459a.md")" unit_tests)"
expect "mutant: the old n/?a refers the path-naming unit row (the #459 path row can fail)" referred "$(outcome "$(mrun "$WORK/na459b.md")" unit_tests)"
expect "mutant: the old n/?a refers the E2E mention (the #459 E2E row can fail)" referred "$(outcome "$(mrun "$WORK/na459c.md")" e2e_tests)"
expect "mutant: the old n/?a refers the scenarios mention (the #459 scenarios row can fail)" referred "$(outcome "$(mrun "$WORK/na459d.md")" gwt)"
# Opposite mutant: anchor the slash form too; the mid-sentence claim must flip to fail.
sed "s#^looks_na()   { grep -qiE '[^']*'#looks_na()   { grep -qiE '^[[:space:]]*(n/a|na)([^a-z]|\$)'#" "$SCRIPT" > "$MUT"
expect "mutant: anchoring N/A too turns a mid-sentence claim into a fail (the claim-kept row can fail)" fail "$(outcome "$(mrun "$WORK/na459mid.md")" unit_tests)"

# #359 mutant: restore the substring polarity test on a copy; the labelled-Negative fixture must flip.
grep -q 'block = (\$0 ~ neg ? "Negative" : "Positive")' "$SCRIPT" && ok "mutant ledger: the script carries the anchored polarity test (#359)" || bad "mutant ledger: #359 expression not found"
sed 's/(\$0 ~ neg ? "Negative" : "Positive")/(index($0, "Positive") ? "Positive" : "Negative")/' "$SCRIPT" > "$MUT"
ev="$(bash "$MUT" --body "$WORK/wc1.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null | awk -F'\t' '$1=="gwt"{print $3}')"
case "$ev" in *"(Positive: 2 When lines)"*) ok "mutant: the substring test names the labelled Negative Positive (the #359 companion can fail)" ;; *) bad "mutant: substring test not detected: $ev" ;; esac

# #479 mutant: drop the case-insensitivity on a copy; both lowercase one-liners must flip to fail.
grep -qF 'grep -m1 -iE "$ONE_LINE"' "$SCRIPT" && ok "mutant ledger: the script carries the case-insensitive one-line detector (#479)" || bad "mutant ledger: #479 grep -m1 -iE line not found"
sed 's/grep -m1 -iE "\$ONE_LINE"/grep -m1 -E "$ONE_LINE"/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#479: the case-sensitivity mutant did not apply"; else
  expect "mutant: a case-sensitive detector fails the lowercase keyword row (the #479 row can fail)" fail "$(outcome "$(mrun "$L1")" gwt)"
  expect "mutant: a case-sensitive detector fails the lowercase marker row (the #479 row can fail)" fail "$(outcome "$(mrun "$L2")" gwt)"
fi
# #479 review mutants: drop the block gate, narrow it back to a valid pair, drop the incomplete-pair
# pass-through, then drop the header-owns-no-When exemption.
GATE479='if { [ "$pos_count" -gt 0 ] || [ "$neg_count" -gt 0 ]; } && [ -n "$one_line" ]; then'
grep -qF "$GATE479" "$SCRIPT" && ok "mutant ledger: the script carries the block gate (#479 review)" || bad "mutant ledger: #479 block gate not found"
sed 's/^\( *\)if { \[ "\$pos_count" -gt 0 \] || \[ "\$neg_count" -gt 0 \]; } && \[ -n "\$one_line" \]; then$/\1if false; then/' "$SCRIPT" > "$MUT"
# Its L12 row was dropped by #487: the refer branch now runs the When count, so L12 fails under
# this mutant exactly as under the real script (equivalent there). L10 still kills it.
if cmp -s "$SCRIPT" "$MUT"; then bad "#479: the valid-pair gate mutant did not apply"; else
  expect "mutant: without the valid-pair gate a stray one-liner in a valid pair refers (the stray row can fail)" referred "$(outcome "$(mrun "$L10")" gwt)"
fi
sed 's/^\( *\)if { \[ "\$pos_count" -gt 0 \] || \[ "\$neg_count" -gt 0 \]; }/\1if { [ "$pos_count" -gt 0 ] \&\& [ "$neg_count" -gt 0 ]; }/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#479: the valid-pair-only mutant did not apply"; else
  # Re-aimed at the evidence by #487: the refer branch now counts L14's two When lines, so the
  # mutant fails too, but on the When count where the real script fails the missing polarity.
  ev="$(gwt_ev "$(mrun "$L14")")"
  case "$ev" in *"found 1 positive, 0 negative"*) bad "mutant: valid-pair-only survived on L14: $ev" ;; *"Positive: 2 When lines"*) ok "mutant: a gate on a valid pair only reports L14's When count instead of its missing polarity (the round 2 row can fail)" ;; *) bad "mutant: valid-pair-only L14 evidence: $ev" ;; esac
  expect "mutant: a gate on a valid pair only refers the capitalised incomplete-pair header" referred "$(outcome "$(mrun "$L16")" gwt)"
fi
sed 's/^ *!pair { print }$//' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#479: the incomplete-pair pass-through mutant did not apply"; else
  expect "mutant: without the pass-through a Negative one-liner beside a lone Positive block fails (the L17 row can fail)" fail "$(outcome "$(mrun "$L17")" gwt)"
fi
sed 's/whens == 0) print hdr/whens < 0) print hdr/g' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#479: the header exemption mutant did not apply"; else
  expect "mutant: without the header exemption O5's bold one-liners fail one site later (the O5 row can fail)" fail "$(outcome "$(mrun "$O5")" gwt)"
  expect "mutant: without the header exemption a bold one-liner beside a real block fails (the mixed row can fail)" fail "$(outcome "$(mrun "$L13")" gwt)"
fi
# #487 mutant: keep every no-When one-line header block in the refer branch's judged text; the
# reproduction then names the header as `Positive: 0 When lines` and the valid mirror fails.
X487='n_when == 0 && (tolower(head) ~ one'
grep -qF "$X487" "$SCRIPT" && ok "mutant ledger: the script carries the no-When header exclusion (#487)" || bad "mutant ledger: #487 exclusion not found"
sed 's/n_when == 0 && (tolower(head) ~ one/n_when < 0 \&\& (tolower(head) ~ one/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#487: the header exclusion mutant did not apply"; else
  ev="$(gwt_ev "$(mrun "$R1")")"
  case "$ev" in *"Positive: 0 When lines"*) ok "mutant: without the exclusion the reproduction names the header block (the #487 evidence row can fail)" ;; *) bad "mutant: #487 exclusion survived on the reproduction: $ev" ;; esac
  expect "mutant: without the exclusion the valid mirror fails on Negative: 0 When lines (the mirror row can fail)" fail "$(outcome "$(mrun "$R4")" gwt)"
fi
# #487 review round 1 mutants. Each literal below belongs to its mutant alone.
# (1) A case-sensitive removal: drop the three tolower calls of without_oneliner_headers.
XLOW='one = tolower(ENVIRON["CTM_ONE"])'
grep -qF "$XLOW" "$SCRIPT" && ok "mutant ledger: the header removal folds case (#487 round 1)" || bad "mutant ledger: #487 tolower not found"
sed -e 's/one = tolower(ENVIRON\["CTM_ONE"\])/one = ENVIRON["CTM_ONE"]/' -e 's/(tolower(head) ~ one/(head ~ one/' -e 's/inblk && tolower(\$0) ~ one/inblk \&\& $0 ~ one/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF 'tolower(head)' "$MUT"; then bad "#487: the case-sensitive removal mutant did not apply"; else
  expect "mutant: a case-sensitive removal fails the lowercase header beside a valid block (the R8 row can fail)" fail "$(outcome "$(mrun "$R8")" gwt)"
  ev="$(gwt_ev "$(mrun "$R9")")"
  case "$ev" in *"Positive: 0 When lines"*) ok "mutant: a case-sensitive removal names the lowercase header block (the R9 row can fail)" ;; *) bad "mutant: case-sensitive removal survived on R9: $ev" ;; esac
fi
# (2) Key the removal on the header alone: the grouping header row fails on 0 When lines.
XGRP='inblk && tolower($0) ~ one { one_in = 1 }'
grep -qF "$XGRP" "$SCRIPT" && ok "mutant ledger: the removal also reads the block's lines (#487 round 1)" || bad "mutant ledger: #487 one_in rule not found"
sed '/inblk && tolower(\$0) ~ one { one_in = 1 }/d' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#487: the header-only removal mutant did not apply"; else
  case "$(gwt_ev "$(mrun "$R10")")" in *"Positive: 0 When lines"*) ok "mutant: a header-only removal fails the grouping header on 0 When lines (the R10 row can fail)" ;; *) bad "mutant: header-only removal survived on R10: $(gwt_ev "$(mrun "$R10")")" ;; esac
fi
# (3) In a pair, stop reading the lines of a no-When block: both grouping headers fail again.
XPAIR='if (whens == 0) printf "%s", grp'
grep -qF "$XPAIR" "$SCRIPT" && ok "mutant ledger: the pair filter reads a no-When block's lines (#487 round 1)" || bad "mutant ledger: #487 grp print not found"
sed 's/if (whens == 0) printf "%s", grp/if (whens < 0) printf "%s", grp/g' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#487: the pair-lines mutant did not apply"; else
  case "$(outcome "$(mrun "$R11")" gwt)|$(gwt_ev "$(mrun "$R11")")" in "fail|"*"0 When lines"*) ok "mutant: without the block lines both grouping headers fail on 0 When lines (the R11 row can fail)" ;; *) bad "mutant: pair-lines mutant survived on R11: $(gwt_ev "$(mrun "$R11")")" ;; esac
fi
# (4) Drop the Given/Then guard on the line path (round 2): a block-grammar block missing its When
# refers again.
XGT='(one_in && !n_gt)'
grep -qF "$XGT" "$SCRIPT" && ok "mutant ledger: the line removal spares a block with a Given or Then bullet (#487 round 2)" || bad "mutant ledger: #487 n_gt guard not found"
sed 's/(one_in \&\& !n_gt)/one_in/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#487: the n_gt mutant did not apply"; else
  expect "mutant: without the Given/Then guard the block missing its When refers (the R13 row can fail)" referred "$(outcome "$(mrun "$R13")" gwt)"
fi

# #490 mutants. (1) No filter: the block scans read the raw field, so the reproduction fails again.
XF490='SCEN_BLOCKS="$(fence_free "$SCENARIOS")"'
grep -qF "$XF490" "$SCRIPT" && ok "mutant ledger: check 4 builds the fence-free copy (#490)" || bad "mutant ledger: #490 fence_free assignment not found"
sed 's/SCEN_BLOCKS="\$(fence_free "\$SCENARIOS")"/SCEN_BLOCKS="$SCENARIOS"/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XF490" "$MUT"; then bad "#490: the no-filter mutant did not apply"; else
  expect "mutant: without the fence filter the reproduction fails on its hidden Then (the #490 row can fail)" fail "$(outcome "$(mrun "$F490R")" gwt)"
  expect "mutant: without the fence filter a fenced-only pair passes again (the fence-only row can fail)" pass "$(outcome "$(mrun "$F490P")" gwt)"
  expect "mutant: without the fence filter a fenced vague Then refers (the vague-Then row can fail)" referred "$(outcome "$(mrun "$F490V")" gwt)"
fi
# (2) Filter in place: the raw field is gone, so looks_na and first_line read the filtered text
# and the fenced-only N/A turns from referred into a 0/0 fail.
sed 's/SCEN_BLOCKS="\$(fence_free "\$SCENARIOS")"/SCENARIOS="$(fence_free "$SCENARIOS")"; SCEN_BLOCKS="$SCENARIOS"/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XF490" "$MUT"; then bad "#490: the in-place filter mutant did not apply"; else
  expect "mutant: a filter applied in place fails the fenced-only N/A (the raw-field row can fail)" fail "$(outcome "$(mrun "$F490A")" gwt)"
  expect "mutant: ...and the reproduction still passes, so only the raw-field rows see it" pass "$(outcome "$(mrun "$F490R")" gwt)"
fi
# (3) and (4) Round 1, L2: drop one of fence_free()'s line strips. body_headings() and section_of()
# carry the same literals, so the sed and the applied-check are confined to fence_free() alone.
ff490() { sed -n '/^fence_free() {/,/^}/p' "$1"; }
for strip in 'sub(/\r$/, "", l); ' 'sub(/[ \t]+$/, "", l)'; do
  grep -qF "$strip" <<< "$(ff490 "$SCRIPT")" && ok "mutant ledger: fence_free() carries $strip (#490)" || bad "mutant ledger: fence_free() lacks $strip"
done
sed '/^fence_free() {/,/^}/ s/sub(\/\\r\$\/, "", l); //' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF 'sub(/\r$/, "", l)' <<< "$(ff490 "$MUT")"; then bad "#490: the CR-strip mutant did not apply"; else
  expect "mutant: without fence_free's CR strip the CRLF reproduction fails (the CRLF row can fail)" fail "$(outcome "$(mrun "$F490C")" gwt)"
fi
sed '/^fence_free() {/,/^}/ s/; sub(\/\[ \\t\]+\$\/, "", l)//' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF 'sub(/[ \t]+$/, "", l)' <<< "$(ff490 "$MUT")"; then bad "#490: the trailing-blank mutant did not apply"; else
  expect "mutant: without fence_free's trailing-blank strip the padded fence breaks (the trailing-blank row can fail)" fail "$(outcome "$(mrun "$F490E")" gwt)"
fi
# (5) No fence note: the L1 row's evidence loses its reason.
XN490='FENCE_NOTE=" (lines inside a fenced code block are not read)"'
grep -qF "$XN490" "$SCRIPT" && ok "mutant ledger: check 4 sets the fence note (#490)" || bad "mutant ledger: #490 fence note not found"
sed 's/FENCE_NOTE=" (lines inside a fenced code block are not read)"/FENCE_NOTE=""/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XN490" "$MUT"; then bad "#490: the fence-note mutant did not apply"; else
  expect "mutant: without the fence note the L1 evidence stops naming the fences (the L1 row can fail)" \
    "each scenario block needs exactly one When (Positive: 0 When lines; Negative: 0 When lines)" "$(mrun "$F490L" | awk -F'\t' '$1 == "gwt" { print $3 }')"
fi
# (6) to (8) Round 2: each guard that keeps the note off an unrelated fail, dropped on a copy.
ev490() { mrun "$1" | awk -F'\t' '$1 == "gwt" { print $3 }'; }
XW490='*": 0 When lines"*) [ "$fence_hid" -eq 0 ]'
grep -qF "$XW490" "$SCRIPT" && ok "mutant ledger: when_note keys on a 0 When lines block (#490)" || bad "mutant ledger: #490 when_note guard not found"
sed 's/\*": 0 When lines"\*) \[ "\$fence_hid" -eq 0 \]/*) [ "$fence_hid" -eq 0 ]/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XW490" "$MUT"; then bad "#490: the when_note guard mutant did not apply"; else
  expect "mutant: without the 0 When lines guard a real second When names the fences (the no-note When row can fail)" \
    "each scenario block needs exactly one When (Positive: 2 When lines) (lines inside a fenced code block are not read)" "$(ev490 "$F490NB")"
fi
XT490='[ "$(then_missing "$SCENARIOS")" -ge "$1" ] ||'
grep -qF "$XT490" "$SCRIPT" && ok "mutant ledger: then_note compares the raw missing-Then count (#490)" || bad "mutant ledger: #490 then_note guard not found"
sed 's/\[ "\$(then_missing "\$SCENARIOS")" -ge "\$1" \] ||/false ||/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XT490" "$MUT"; then bad "#490: the then_note guard mutant did not apply"; else
  expect "mutant: without the raw count a real missing Then names the fences (the no-note Then row can fail)" \
    "a Negative block has no Then line (lines inside a fenced code block are not read)" "$(ev490 "$F490NC")"
fi
XB490="[*]*When[*]*[[:space:]]*:'"
grep -qF "WHEN_BULLET='^[[:space:]]*[-*][[:space:]]*$XB490" "$SCRIPT" && ok "mutant ledger: the note's trigger counts When bullets only (#490)" || bad "mutant ledger: #490 WHEN_BULLET not found"
sed "s/^\(    WHEN_BULLET=.*\)\[\*\]\*When\[\*\]\*/\1[*]*(When|Then)[*]*/" "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT"; then bad "#490: the WHEN_BULLET mutant did not apply"; else
  expect "mutant: a trigger that counts Then bullets blames a fenced Then for a real 0-When block (the 0-When row can fail)" \
    "each scenario block needs exactly one When (Positive: 0 When lines) (lines inside a fenced code block are not read)" "$(ev490 "$F490NG")"
fi

# #365 mutant: restore `paste -sd'; ' -` on a copy; the three-block whole-field pin must flip.
grep -q 'NR>1{printf "; "}' "$SCRIPT" && ok "mutant ledger: the script carries the awk join (#365)" || bad "mutant ledger: #365 awk join not found"
sed "s/awk 'NR>1{printf \"; \"} {printf \"%s\", \$0} END{print \"\"}'/paste -sd'; ' -/" "$SCRIPT" > "$MUT"
ev="$(bash "$MUT" --body "$WORK/wc8.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null | awk -F'\t' '$1=="gwt"{print $3}')"
case "$ev" in *"lines;Negative: 2 When lines Positive"*) ok "mutant: paste restored, the three-block pin flips to the run-on join (the #365 companion can fail)" ;; *) bad "mutant: paste restoration not detected: $ev" ;; esac
ev="$(bash "$MUT" --body "$WORK/wc9.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null | awk -F'\t' '$1=="gwt"{print $3}')"
case "$ev" in *"lines;Negative: 2 When lines Positive"*) ok "mutant: paste restored, the four-block pin flips to the run-on join" ;; *) bad "mutant: paste restoration not detected on four blocks: $ev" ;; esac

# The fifth fix (lists via ENVIRON) is invisible to gawk, which accepts a newline in -v; only BWK
# awk refuses it, and CI has no BWK awk. Running the whole script under a second awk is still the
# only CI-visible tripwire for awk portability, so when busybox is on PATH the compliant feature
# body is checked under it too, and the skip line says when it is not. The Apple-awk run is by hand.
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$WORK/bbawk"; printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$WORK/bbawk/awk"; chmod +x "$WORK/bbawk/awk"
  o="$(PATH="$WORK/bbawk:$PATH" run "$WORK/ok-feature.md" feature)"
  # Seven rows AND no fail: a refused awk construct dies with no rows at all, and "zero fails"
  # alone was satisfied by that (found in review).
  expect "portability: the compliant feature body emits every row under busybox awk" 7 "$(printf '%s\n' "$o" | grep -c .)"
  expect "portability: and none of them fails" 0 "$(printf '%s\n' "$o" | awk -F'\t' '$2=="fail"' | wc -l | tr -d ' ')"
else
  ok "portability: busybox awk not on PATH, second-awk case skipped"
fi


echo "check-ticket-mechanics: the area set comes from the project's own labels.md (#204)"
mkdir -p "$WORK/proj/docs/guides"
cat > "$WORK/proj/docs/guides/labels.md" <<'MD'
# Labels

### Area labels (this project's)
| Label | Description |
|---|---|
| `protocol` | The wire protocol |
| `client` | The client |
not-a-row `server` |

### Type labels
| Label |
|---|
| `bug` |
MD
B="$(mkbody feature "areas.md")"
lbldoc() { bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels "$1" "${@:2}" 2>/dev/null | awk -F'\t' '$1=="labels"{print $2 "\t" $3}'; }
o="$(lbldoc "protocol,feature" --labels-doc "$WORK/proj/docs/guides/labels.md")"
expect "a ticket carrying only the project's own area passes with --labels-doc" pass "${o%%	*}"
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/labels.md")"
expect "REPLACEMENT: a compiled-in area absent from the table fails" fail "${o%%	*}"
case "${o#*	}" in *"protocol, client"*) ok "and the fail message lists the table's set, not the nine" ;; *) bad "the fail message lists the wrong set: '${o#*	}'" ;; esac
case "${o#*	}" in *server*) bad "a malformed row became an area" ;; *) ok "a row whose first column is not backticked is not an area" ;; esac
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/labels.md" --area-labels "components")"
expect "an explicit --area-labels wins over the doc" pass "${o%%	*}"
# #425: a MISSING doc keeps the compiled-in nine but says so, and a label outside both compiled-in
# sets (a candidate) is referred to Step 3B rather than failed, since the checker cannot tell a
# project's own area from any other label. Only type labels alone, or none, still fail.
NOTICE="labels.md not found; using forge-kit's built-in nine areas. Run forge-adapt Templates mode, \"Labels\" step, to declare yours."
NINE="no area label (one of: api, privacy, web, mobile, backend, database, components, tooling, governance)"
has_notice() { case "$1" in *"$NOTICE"*) return 0 ;; *) return 1 ;; esac; }
o="$(lbldoc "protocol,feature" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "a missing doc refers a project's own area (protocol) to Step 3B" referred "${o%%	*}"
if has_notice "${o#*	}"; then ok "and the referred row carries the notice"; else bad "referred row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "and the default still admits its own areas" pass "${o%%	*}"
case "${o#*	}" in "labels: components,feature"*) ok "and the pass row keeps its labels evidence" ;; *) bad "pass evidence: '${o#*	}'" ;; esac
if has_notice "${o#*	}"; then ok "and the pass row carries the notice"; else bad "pass row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "feature" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "a missing doc and only a type label still fails" fail "${o%%	*}"
case "${o#*	}" in "$NINE"*) ok "and the fail row names the nine" ;; *) bad "fail evidence: '${o#*	}'" ;; esac
if has_notice "${o#*	}"; then ok "and the fail row carries the notice"; else bad "fail row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "feature,P3" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "a missing doc refers feature,P3 (the checker has no priority set)" referred "${o%%	*}"
if has_notice "${o#*	}"; then ok "and that referred row carries the notice"; else bad "feature,P3 row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "components" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "a missing doc and an area with no type label warns" warn "${o%%	*}"
case "${o#*	}" in "no type label (one of: bug, enhancement, feature, security, infrastructure, design, documentation, testing)"*) ok "and the warn row names the type set" ;; *) bad "warn evidence: '${o#*	}'" ;; esac
if has_notice "${o#*	}"; then ok "and the warn row carries the notice"; else bad "warn row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "Feature, bug " --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "type labels in another case and with stray spaces are no candidate: still fail" fail "${o%%	*}"
case "${o#*	}" in "$NINE"*) ok "and that fail row names the nine" ;; *) bad "normalised fail evidence: '${o#*	}'" ;; esac
if has_notice "${o#*	}"; then ok "and that fail row carries the notice"; else bad "normalised fail row lacks the notice: '${o#*	}'"; fi
o="$(lbldoc "nope,feature")"
expect "no --labels-doc at all still fails an unknown area" fail "${o%%	*}"
if has_notice "${o#*	}"; then bad "no --labels-doc emitted the notice"; else ok "and carries no notice"; fi
o="$(lbldoc "protocol,feature" --labels-doc "$WORK/proj/docs/guides/nope.md" --area-labels "components")"
if has_notice "${o#*	}"; then bad "an explicit --area-labels emitted the notice"; else ok "an explicit --area-labels is the area set: no notice"; fi
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/labels.md")"
case "${o#*	}" in *"not found"*|*"Templates mode"*) bad "a present doc with a table emitted the notice: '${o#*	}'" ;; *) ok "a present doc with a table gives no notice" ;; esac
printf '# Labels\n\nno table here\n' > "$WORK/proj/docs/guides/empty.md"
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/empty.md")"
expect "a PRESENT doc with no area table is referred, never silently judged on the default" referred "${o%%	*}"
expect "and its evidence is unchanged, with no notice" "no Area labels table in $WORK/proj/docs/guides/empty.md; Step 3B rules on the area and type labels" "${o#*	}"
printf '### Area labels\n| Label |\n|---|\n' > "$WORK/proj/docs/guides/norows.md"
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/norows.md")"
expect "a table heading with no rows is referred too, never an empty set" referred "${o%%	*}"
printf '### Area labels\n| Label |\n|---|\n| `client` |\n## Priority labels\n| Label |\n|---|\n| `P0` |\n' > "$WORK/proj/docs/guides/twolevel.md"
o="$(lbldoc "P0,feature" --labels-doc "$WORK/proj/docs/guides/twolevel.md")"
expect "a ## heading after the table ends it: a priority label is not an area" fail "${o%%	*}"
printf '### Area labels\n| Label |\n|---|\n | `server` |\n|`proto`|\n| `client ` |\n' > "$WORK/proj/docs/guides/rows.md"
for l in server proto client; do
  o="$(lbldoc "$l,feature" --labels-doc "$WORK/proj/docs/guides/rows.md")"
  expect "a valid row with unusual whitespace still declares its area ($l)" pass "${o%%	*}"
done
o="$(lbldoc "nope,feature" --labels-doc "$WORK/proj/docs/guides/rows.md")"
case "${o#*	}" in *"server, proto, client)"*) ok "and the trailing space inside the backticks is stripped from the set" ;; *) bad "trailing space kept: '${o#*	}'" ;; esac
o="$(lbldoc "nope,feature" --labels-doc "$ROOT/docs/guides/labels.md")"
case "${o#*	}" in *"api, privacy, web, mobile, backend, database, components, tooling, governance"*) ok "this repository's own labels.md reads as exactly the nine, in order (parity with check-label-taxonomy.sh)" ;; *) bad "parity: read '${o#*	}'" ;; esac

echo "check-ticket-mechanics: the template's own scenarios placeholder is a format check 4 accepts (#361)"
# Step 0c-iii tells the synthesis sub-agent to copy each `label:` verbatim and follow the
# scenarios `placeholder:` of the template. That instruction is only sound if the placeholder IS a
# shape check 4 parses, so each real template is read at test time (no copy of the format here)
# and its placeholder is run through the checker under its own label.
cat > "$WORK/ph.py" <<'PY'
import re, sys
# usage: ph.py <template> <mode> ; prints "<label>\n<placeholder>" of the scenarios field
lines = open(sys.argv[1]).read().split("\n")
label = None; ph = []; infield = False; inph = False
for ln in lines:
    if re.match(r'\s*id:\s*scenarios\s*$', ln): infield = True; continue
    if infield and re.match(r'      label: ', ln): label = ln.split("label: ", 1)[1].rstrip()
    if infield and re.match(r'      placeholder: \|', ln): inph = True; continue
    if inph:
        if ln.startswith("        "): ph.append(ln[8:])
        elif ln.strip() == "": ph.append("")
        else: break
print(label); print("\n".join(ph).rstrip())
PY
# ph_gwt <template-name> <variant> [placeholder-source.yml] -> the gwt row's outcome and evidence
# ("outcome<TAB>evidence"). The body is generated from the real template, with its scenarios
# content replaced by the placeholder read from the template (or from a mutated copy of it).
ph_gwt() {
  local tag="$1" variant="$2" tf="${3:-$TPLDIR/$1.yml}"
  python3 "$WORK/ph.py" "$tf" > "$WORK/ph-$tag.txt"
  local ph; ph="$(tail -n +2 "$WORK/ph-$tag.txt")"
  case "$variant" in
    quoted) ph="$(printf '%s' "$ph" | sed 's/\[expected error \/ rejection message\]/rejected with "INVALID_EMAIL"/')" ;;
    verbatim) : ;;
    twowhen) ph="$(printf '%s' "$ph" | sed '0,/^- When: \[action is performed\]$/s//&\n- When: [a second action]/' | sed 's/\[expected error \/ rejection message\]/rejected with "INVALID_EMAIL"/')" ;;
  esac
  local b; b="$(mkbody "$tag" "ph-$tag-$variant.md" "$ph")"
  run "$b" "$tag" | awk -F'\t' '$1 == "gwt" { print $2 "\t" $3 }'
}
# label_ok <template-name> <ph-script>: the first non-blank line under "### <label>" in the body
# ph_gwt generated (<label> as <ph-script> reports it) is the first line of the placeholder
# <ph-script> reports. Needs ph_gwt to have run for the template; label_ok re-runs
# <ph-script> itself and reads only the generated .md body.
label_ok() {
  local tpl="$1" script="$2" lbl first got
  lbl="$(python3 "$script" "$TPLDIR/$tpl.yml" | sed -n 1p)"
  first="$(python3 "$script" "$TPLDIR/$tpl.yml" | sed -n 2p)"
  got="$(awk -v h="### $lbl" '$0 == h { f = 1; next } f && NF { print; exit }' "$WORK/ph-$tpl-quoted.md")"
  [ -n "$got" ] && [ "$got" = "$first" ]
}
for tpl in bug feature security infrastructure design; do
  r="$(ph_gwt "$tpl" quoted)"
  expect "#361: $tpl: the placeholder with a quoted negative message passes" pass "${r%%$'\t'*}"
  case "$r" in *"1 positive and 1 negative blocks"*) ok "#361: $tpl: and it counts 1 positive and 1 negative" ;; *) bad "#361: $tpl: evidence: $r" ;; esac
  r="$(ph_gwt "$tpl" verbatim)"
  expect "#361: $tpl: the placeholder left verbatim is referred" referred "${r%%$'\t'*}"
  case "$r" in *"not mechanically specific:"*"[expected error / rejection message]"*) ok "#361: $tpl: and says the negative Then is not specific, quoting the bracketed placeholder" ;; *) bad "#361: $tpl: evidence: $r" ;; esac
  r="$(ph_gwt "$tpl" twowhen)"
  expect "#361: $tpl: a second When in the Positive block fails" fail "${r%%$'\t'*}"
  case "$r" in *"each scenario block needs exactly one When (Positive: 2 When lines)"*) ok "#361: $tpl: and says the Positive block has 2 When lines" ;; *) bad "#361: $tpl: evidence: $r" ;; esac
  # The label ph.py read from the template is the heading gen.py wrote, so the two cannot diverge.
  label_ok "$tpl" "$WORK/ph.py" \
    && ok "#361: $tpl: the template's scenarios label heads the placeholder's own first line in the body" \
    || bad "#361: $tpl: label '$(head -n 1 "$WORK/ph-$tpl.txt")' does not head the placeholder in the generated body"
done
# MUTANT (#383): a ph.py that always reports the label "Unit tests". The old `grep -qxF "### <label>"`
# passed it for bug, feature and security, because those three templates really do carry a
# `### Unit tests` heading. label_ok compares the first line under the heading with the
# placeholder's first line, which only the real scenarios heading carries. This runs through the
# function, never through bad(), so a surviving mutant is the failure and a killed one is an ok.
sed 's/label = ln.split("label: ", 1)\[1\].rstrip()/label = "Unit tests"/' "$WORK/ph.py" > "$WORK/ph-mut.py"
cmp -s "$WORK/ph.py" "$WORK/ph-mut.py" && bad "#383: the ph.py mutant did not apply (sed matched nothing)"
# #414: a ph.py that exits fails label_ok too, so ph_kill classifies the build with
# scripts/mutant-crash.sh (Python compile() as the parse check) against ph_live and prints
# `mutant <name> crashed (<reason>)` instead of the kill when a reason fires (#330).
. "$ROOT/scripts/mutant-crash.sh"
# ph_live <build>: on bug.yml the build exits 0 and prints at least 2 lines.
ph_live() { local o; o="$(python3 "$1" "$TPLDIR/bug.yml")" || return 1; [ "$(grep -c '' <<< "$o")" -ge 2 ]; }
ph_kill() {  # ph_kill <tpl> <build>: the label_ok case on <build>, classified, then its kill
  local held=0 why
  label_ok "$1" "$2" && held=1
  why=$(mutant_crash_reason "$2" /dev/null ph_live "$2")
  if [ -n "$why" ]; then bad "mutant #383 $1 crashed ($why)"; return; fi
  [ "$held" = 1 ] && bad "#383: $1: MUTANT survived: an always-Unit-tests ph.py still passes label_ok" \
    || ok "#383: $1: MUTANT: an always-Unit-tests ph.py fails label_ok"
}
for tpl in bug feature security infrastructure design; do
  ph_kill "$tpl" "$WORK/ph-mut.py"
done
# Crash control (#414): its own copy, so ph-mut.py is never overwritten. ph_kill runs in $( ), so
# its row stays out of the total, and the capture is not echoed.
sed '1a\
raise SystemExit(2)' "$WORK/ph-mut.py" > "$WORK/ph-crash.py"
crash_ok=1
cmp -s "$WORK/ph-crash.py" "$WORK/ph-mut.py" && crash_ok=0
cap=$(ph_kill bug "$WORK/ph-crash.py")
case "$cap" in *"fails label_ok"*) crash_ok=0 ;; *"FAIL: mutant #383 bug crashed (the liveness run failed)"*) ;; *) crash_ok=0 ;; esac
[ "$crash_ok" = 1 ] && ok "crash control: ph_kill reports a crashing ph.py as crashed, never as a kill" \
  || bad "crash control: ph_kill credited or missed a crashing ph.py"
# MUTANT: a copy of bug.yml whose placeholder lost its Negative marker line must NOT pass, which
# shows the loop above can fail (a mutation of the input, since the script is not under test here).
sed '0,/^        Negative$/{/^        Negative$/d}' "$TPLDIR/bug.yml" > "$WORK/mut-bug.yml"
r="$(ph_gwt bug quoted "$WORK/mut-bug.yml")"
[ "${r%%$'\t'*}" = fail ] && ok "#361: MUTANT: a placeholder with no Negative marker no longer passes" \
  || bad "#361: MUTANT survived: a placeholder with no Negative marker still passes ($r)"
# The heading absent (what a synthesis never told the label produces).
python3 - "$(mkbody bug nohead.md)" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'### Test scenarios \(Given / When / Then\)\n\n.*?(?=### )', '', s, count=1, flags=re.S)
open(p, "w").write(s)
PY
o="$(run "$WORK/nohead.md" bug)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="sections"{print $3}')" in *"heading absent"*"Test scenarios (Given / When / Then)"*) ok "#361: a body without the scenarios heading names it as absent" ;; *) bad "#361: heading-absent evidence: $(printf '%s\n' "$o" | awk -F'\t' '$1=="sections"{print $3}')" ;; esac
case "$(gwt_ev "$o")" in *"no content in Test scenarios (Given / When / Then)"*) ok "#361: and the gwt row says there is no content under it" ;; *) bad "#361: gwt evidence: $(gwt_ev "$o")" ;; esac

echo "check-ticket-mechanics: Step 0c's variant-heading rule is scoped to non-target sections (#361)"
# Why this matters: checks 4 to 7 read only the text under the template-label heading, so a
# one-line pointer under `## Unit tests` fails unit_tests (the failure the scoped rule prevents),
# while real content under that label passes.
B1="$(mkbody bug cond4-pointer.md "" 'See "Tests" below.')"
printf '\n### Tests\n\n- `scripts/test-foo.sh` with input x expects error E\n' >> "$B1"
o="$(run "$B1" bug)"
expect "#361: a pointer line under the Unit tests label fails unit_tests" fail "$(outcome "$o" unit_tests)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="unit_tests"{print $3}')" in *'unit tests name no file path: See "Tests" below.'*) ok "#361: and the evidence is the checker's own, quoting the pointer" ;; *) bad "#361: unit_tests evidence: $(printf '%s\n' "$o" | awk -F'\t' '$1=="unit_tests"{print $3}')" ;; esac
B2="$(mkbody bug cond4-synth.md "" '- [ ] `scripts/test-foo.sh` input x expects error E')"
printf '\n### Tests\n\n- `scripts/test-foo.sh` with input x expects error E\n' >> "$B2"
o="$(run "$B2" bug)"
expect "#361: the synthesised section under the label passes with the author's Tests section left in place" pass "$(outcome "$o" unit_tests)"
case "$(printf '%s\n' "$o" | awk -F'\t' '$1=="unit_tests"{print $3}')" in *"name no file path"*) bad "#361: a pass row still carries the failure evidence" ;; *) ok "#361: and the pass row carries no failure evidence" ;; esac
# #383: a GDPR-headed personal_data. Step 0c-iv now writes `## Personal data handling` plus a
# pointer above the author's GDPR section, because check 3 reads the template heading and the
# label alone is absent otherwise. The agent's behaviour is prose; these two cases pin the body
# SHAPE the checker accepts and rejects, and the live /gate-ticket check covers the behaviour.
BG="$(mkbody bug gdpr-base.md)"
sed 's/^### Personal data handling$/### GDPR considerations/' "$BG" > "$WORK/gdpr-renamed.md"
cmp -s "$BG" "$WORK/gdpr-renamed.md" && bad "#383: the GDPR rename did not apply"
o="$(run "$WORK/gdpr-renamed.md" bug)"
sec_ev() { printf '%s\n' "$1" | awk -F'\t' '$1=="sections"{print $2 "\t" $3}'; }
r="$(sec_ev "$o")"
expect "#383: a GDPR-headed personal data section with no pointer fails the sections check" fail "${r%%$'\t'*}"
case "$r" in *"heading absent (1): Personal data handling"*) ok "#383: and it names Personal data handling as the absent heading" ;; *) bad "#383: sections evidence: $r" ;; esac
awk '/^### GDPR considerations$/ { print "## Personal data handling\n\nSee \"GDPR considerations\" below.\n" } { print }' "$WORK/gdpr-renamed.md" > "$WORK/gdpr-pointer.md"
o="$(run "$WORK/gdpr-pointer.md" bug)"
r="$(sec_ev "$o")"
expect "#383: the pointer above the GDPR-headed section makes the sections check pass" pass "${r%%$'\t'*}"
offenders="$(printf '%s\n' "$o" | awk -F'\t' '$2 == "fail" { printf "%s ", $1 }')"
[ -z "$offenders" ] && ok "#383: and no other check fails on the pointered body" || bad "#383: pointered body fails: $offenders"
# MUTANT: removing the inserted `## Personal data handling` heading (the pointer text left in
# place) must flip pass to fail, so the positive above is carried by the heading the pointer sits
# under and not by anything else in the body.
grep -v '^## Personal data handling$' "$WORK/gdpr-pointer.md" > "$WORK/gdpr-nohead.md"
cmp -s "$WORK/gdpr-pointer.md" "$WORK/gdpr-nohead.md" && bad "#383: the heading-strip mutant did not apply"
r="$(sec_ev "$(run "$WORK/gdpr-nohead.md" bug)")"
[ "${r%%$'\t'*}" = fail ] && ok "#383: MUTANT: a pointer line with no template heading fails again" || bad "#383: MUTANT survived: no template heading still passes ($r)"
# The doc twin (docs/guides/template-versioning.md) restates the rule. The phrase is searched in
# the whole file with newlines joined to spaces, so a re-wrap of the paragraph cannot hide it.
DOC="$ROOT/docs/guides/template-versioning.md"
DOC_PHRASE='The one exception is the four target sections `scenarios`, `unit_tests`, `e2e_tests` and `docs_impact`'
doc_pin() { grep -qF "$DOC_PHRASE" <<< "$(tr '\n' ' ' < "$1" | tr -s ' ')"; }
doc_pin "$DOC" && ok "#383: template-versioning.md names the four no-pointer sections" || bad "#383: template-versioning.md lost the four-section exception"
sed 's/The one exception is the four target sections/The exception is every target section/' "$DOC" > "$WORK/doc-mut.md"
cmp -s "$DOC" "$WORK/doc-mut.md" && bad "#383: the doc mutant did not apply"
doc_pin "$WORK/doc-mut.md" && bad "#383: MUTANT survived: the doc pin passes with the exception reworded" || ok "#383: MUTANT: rewording the doc exception fails the pin"
# Re-wrapping must not matter: the same words split over two lines still pass.
sed 's/four target sections `scenarios`,/four target sections\n`scenarios`,/' "$DOC" > "$WORK/doc-wrap.md"
cmp -s "$DOC" "$WORK/doc-wrap.md" && bad "#383: the wrap mutant did not apply"
doc_pin "$WORK/doc-wrap.md" && ok "#383: the doc pin survives a re-wrap of the phrase" || bad "#383: the doc pin is wrap-sensitive"
# The prose pins. The scope sentence must survive a rewrite, and the dispatch must stay a pointer
# to the template: a literal copy of the format would be a second source (Condition 2).
GATE="$ROOT/plugins/forge-kit-governance/agents/ticket-gate.md"
# #383: the scope is now spelled as the four no-pointer sections, NOT "outside Step 0c's target set",
# because that phrase put `personal_data` (whose GDPR-headed section needs the pointer for check 3)
# in the no-pointer set. The pin moved with the wording; the absence pin keeps the old one out.
SCOPE_PHRASE='Except for `scenarios`, `unit_tests`, `e2e_tests`, `docs_impact`'
scope_pin() { grep -qF "$SCOPE_PHRASE" "$1"; }
old_scope_pin() { grep -qF "outside Step 0c's target set" "$1"; }
scope_pin "$GATE" && ok "#361: ticket-gate.md names the four no-pointer sections on one line" || bad "#361: ticket-gate.md lost the scope sentence"
sed "s/Except for \`scenarios\`, \`unit_tests\`, \`e2e_tests\`, \`docs_impact\`/everywhere/" "$GATE" > "$WORK/gate-mut.md"
cmp -s "$GATE" "$WORK/gate-mut.md" && bad "#383: the scope mutant did not apply"
scope_pin "$WORK/gate-mut.md" && bad "#361: MUTANT survived: the scope pin passes with the phrase removed" || ok "#361: MUTANT: removing the scope phrase fails the pin"
old_scope_pin "$GATE" && bad "#383: ticket-gate.md still says the rule is outside Step 0c's target set (it puts personal_data in the no-pointer set)" || ok "#383: ticket-gate.md no longer says outside Step 0c's target set"
sed "s/Except for \`scenarios\`, \`unit_tests\`, \`e2e_tests\`, \`docs_impact\`/Only outside Step 0c's target set/" "$GATE" > "$WORK/gate-mut-old.md"
cmp -s "$GATE" "$WORK/gate-mut-old.md" && bad "#383: the restoring mutant did not apply"
old_scope_pin "$WORK/gate-mut-old.md" && ok "#383: MUTANT: restoring the old wording trips the absence pin" || bad "#383: MUTANT survived: the absence pin passes with the old wording restored"
scope_pin "$WORK/gate-mut-old.md" && bad "#383: MUTANT survived: the moved scope pin passes with the old wording restored" || ok "#383: MUTANT: restoring the old wording also fails the moved scope pin"
# #392: the doc's thin-section sentence is a READING of the agent's Thin row, and the agent is
# deliberately not edited: ticket-gate.md plus its preloaded skill sit at the 5754-word ratchet with
# zero headroom, so the doc declares itself a reading and both sides are pinned. A pin on the doc
# alone would never fail when the agent's Thin row changed, which is the drift this guards.
doc_has() { grep -qF -- "$2" <<< "$(tr '\n' ' ' < "$1" | tr -s ' ')"; }
P392_READ='a reading of the Thin row'
P392_NA='unless it states N/A with a reason'
P392_PLACE="appended after the author's text, inside the author's section"
doc_has "$DOC" "$P392_READ" && ok "#392: template-versioning.md marks the thin rule as a reading of the Thin row" || bad "#392: template-versioning.md lost the reading marker"
doc_has "$DOC" "$P392_NA" && ok "#392: template-versioning.md exempts an N/A with a reason from thin" || bad "#392: template-versioning.md lost the N/A carve-out"
doc_has "$DOC" "$P392_PLACE" && ok "#392: template-versioning.md places the append inside the author's section" || bad "#392: template-versioning.md lost the placement"
mut392() {  # mut392 <name> <file> <sed-expr> <pin-fn> <pin-arg> <ok-text>
  local out="$WORK/m392-$1"
  sed "$3" "$2" > "$out"
  if cmp -s "$2" "$out"; then bad "#392: the $1 mutant did not apply"; return; fi
  if "$4" "$out" "$5"; then bad "#392: MUTANT survived: $6"; else ok "#392: MUTANT: $6"; fi
}
mut392 reading "$DOC" 's/a reading of the Thin row/a summary of the Thin row/' doc_has "$P392_READ" "rewording the reading marker fails the pin"
mut392 carve-out "$DOC" 's/unless it states N\/A with a reason, //' doc_has "$P392_NA" "removing the N/A carve-out fails the pin"
mut392 placement "$DOC" "s/inside the author's section/above the author's section/" doc_has "$P392_PLACE" "moving the append above the author's section fails the pin"
sed 's/a reading of the Thin/a reading of the\nThin/' "$DOC" > "$WORK/doc392-wrap.md"
cmp -s "$DOC" "$WORK/doc392-wrap.md" && bad "#392: the re-wrap mutant did not apply"
doc_has "$WORK/doc392-wrap.md" "$P392_READ" && ok "#392: the reading pin survives a re-wrap" || bad "#392: the reading pin is wrap-sensitive"
# The agent's own wording the doc reads from, one line each.
line_has() { grep -qF -- "$2" "$1"; }
A392_THIN='Keep existing text verbatim, append what the current template requires'
A392_SEVEN='`personal_data` is the seven facts'
A392_VAGUE='content vague or placeholder-only'
line_has "$GATE" "$A392_THIN" && ok "#392: ticket-gate.md's Thin row is unchanged" || bad "#392: ticket-gate.md's Thin row moved; re-read template-versioning.md against it"
line_has "$GATE" "$A392_SEVEN" && ok "#392: ticket-gate.md's seven-facts line is unchanged" || bad "#392: ticket-gate.md's seven-facts line moved"
line_has "$GATE" "$A392_VAGUE" && ok "#392: ticket-gate.md's thin definition is unchanged" || bad "#392: ticket-gate.md's thin definition moved"
mut392 thin-row "$GATE" 's/append what the current template requires/replace what the current template requires/' line_has "$A392_THIN" "editing the Thin row fails the anchor pin"
mut392 seven-facts "$GATE" 's/`personal_data` is the seven facts/`personal_data` is the six facts/' line_has "$A392_SEVEN" "editing the seven-facts line fails the anchor pin"
mut392 thin-definition "$GATE" 's/content vague or placeholder-only/content vague or empty/' line_has "$A392_VAGUE" "editing the thin definition fails the anchor pin"
# Fails loudly (prints MISSING, never a count) when a path or glob does not exist, so a moved
# reference cannot make the "no copies" assertion pass vacuously.
gwt_copies() {
  local f n=0 c
  for f in "$@"; do
    [ -f "$f" ] || { echo MISSING; return; }
    c="$(grep -c 'Given / When / Then' "$f")"; n=$((n + c))
  done
  echo "$n"
}
GREF="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference"
expect "#361: no prose copy of the scenarios label in the gate or its reference (derived, never copied)" 0 "$(gwt_copies "$GATE" "$GREF/SKILL.md" "$GREF"/references/*.md)"
printf 'Test scenarios (Given / When / Then)\n' >> "$WORK/gate-mut.md"
[ "$(gwt_copies "$WORK/gate-mut.md")" -ge 1 ] && ok "#361: MUTANT: a pasted label is countable by gwt_copies" || bad "#361: gwt_copies cannot see a pasted label"
[ "$(gwt_copies "$GATE" "$GREF/references/no-such-file.md")" = MISSING ] && ok "#361: MUTANT: a nonexistent path makes gwt_copies fail rather than count 0" || bad "#361: gwt_copies passes vacuously on a missing path"
grep -qF 'The absolute path `$PWD/<0a'"'"'s TPL_DIR>/<type>.yml`' "$GATE" && ok "#361: the 0c-iii dispatch names the template path" || bad "#361: the dispatch does not name the template path"
# #431 item 1: $TPL_DIR is empty in a fresh shell, so the path names 0a's value; the $PWD/ keeps "absolute" true.
# mut431 <name> <file> <from> <to> <pin phrase>: the pin must pass on the file and die on the one-line edit.
mut431() { local m="$WORK/m431.txt"; sed "s|$3|$4|" "$2" > "$m"; cmp -s "$2" "$m" && { bad "#431: mutant '$1' did not apply"; return; }
  grep -qF -- "$5" "$m" && bad "#431: mutant '$1' survived" || ok "#431: mutant '$1' dies"; }
mut431 "restore \$TPL_DIR in the dispatch" "$GATE" '<0a.s TPL_DIR>/<type>.yml`' '$TPL_DIR/<type>.yml`' 'The absolute path `$PWD/<0a'"'"'s TPL_DIR>/<type>.yml`'
mut431 'drop $PWD/ in the dispatch' "$GATE" 'The absolute path `$PWD/<0a' 'The absolute path `<0a' 'The absolute path `$PWD/<0a'"'"'s TPL_DIR>/<type>.yml`'
grep -qF '$PWD/<0a'"'"'s TPL_DIR>/<type>.yml' "$DOC" && ok "#431: template-versioning.md names the resolvable template path" || bad "#431: template-versioning.md names an unresolvable template path"
mut431 'restore $TPL_DIR in the doc' "$DOC" '<0a.s TPL_DIR>/<type>.yml' '$TPL_DIR/<type>.yml' '$PWD/<0a'"'"'s TPL_DIR>/<type>.yml'
mut431 'drop $PWD/ in the doc' "$DOC" '\$PWD/<0a' '<0a' '$PWD/<0a'"'"'s TPL_DIR>/<type>.yml'
grep -qxF 'Use 0a'"'"'s values below.' "$GATE" && ok "#431: Step 0a hands over 0a's values, not an unset variable" || bad "#431: Step 0a still says Use \$CURRENT_TPL_VER everywhere below"
mut431 'restore the unset-variable sentence' "$GATE" "^Use 0a.s values below\\.\$" 'Use `$CURRENT_TPL_VER` everywhere below.' 'Use 0a'"'"'s values below.'
# #430 item 1: 0a keeps the first marker only. #431 item 3: 0a ends by echoing the two values later steps reuse.
grep -qF "| grep -oPm1 'template-version: \\K\\d+'" "$GATE" && ok "#430: Step 0a's extraction keeps the first marker only (-m1)" || bad "#430: Step 0a's extraction can print several markers"
mut431 'Step 0a extraction without -m1' "$GATE" 'grep -oPm1 ' 'grep -oP ' "| grep -oPm1 'template-version: \\K\\d+'"
grep -qxF 'echo "TPL_DIR=$TPL_DIR CURRENT_TPL_VER=$CURRENT_TPL_VER"' "$GATE" && ok "#431: Step 0a echoes TPL_DIR and CURRENT_TPL_VER" || bad "#431: Step 0a echoes neither value"
mut431 'Step 0a echo deleted' "$GATE" '^echo "TPL_DIR=.*$' '' 'echo "TPL_DIR=$TPL_DIR CURRENT_TPL_VER=$CURRENT_TPL_VER"'
grep -qF 'never placeholder text' "$GATE" && ok "#361: the never-placeholder-text instruction is kept" || bad "#361: never placeholder text was dropped"

echo "check-ticket-mechanics: a gate-filled heading is never charged, and gate regions are not author text (#304)"
sec_ev() { printf '%s\n' "$1" | awk -F'\t' '$1=="sections"{print $3}'; }
docs_row() { printf '%s\n' "$1" | awk -F'\t' '$1=="docs_impact"{print $2 "\t" $3}'; }
B="$(mkbody bug "g304.md")"
python3 - "$B" "$WORK/g304-nocc.md" "$WORK/g304-nodeps.md" "$WORK/g304-bodytext.md" <<'PY'
import sys
s=open(sys.argv[1]).read()
cc="### Codebase Context\n\n_No response_\n"
dep="### Dependencies\n\n_No response_\n"
bd="### Bug description\n\nfilled in\n"
assert cc in s and dep in s and bd in s, "fixture anchors did not match"
nocc=s.replace(cc,"",1); open(sys.argv[2],"w").write(nocc)
open(sys.argv[3],"w").write(nocc.replace(dep,"",1))
open(sys.argv[4],"w").write(s.replace(dep,"",1).replace(bd,bd+"Auto-populated by ticket-gate. Do not edit manually.\n",1))
PY
o="$(run "$WORK/g304-nocc.md" bug)"
expect "#304: a bug body lacking only Codebase Context passes sections" pass "$(outcome "$o" sections)"
expect "#304, #320: its evidence names the exempt field with a count and claims no more than the charged sections" "every charged section present, every required one filled (headings at ###); gate-filled, absent and not charged (1): Codebase Context" "$(sec_ev "$o")"
expect "#320: with nothing exempt the evidence is unchanged" "every template section present, every required one filled (headings at ###)" "$(sec_ev "$(run "$B" bug)")"
sed 's/^### /## /' "$WORK/g304-nocc.md" > "$WORK/g304-nocc2.md"
expect "#304: the same body at ## headings passes too" pass "$(outcome "$(run "$WORK/g304-nocc2.md" bug)" sections)"
expect "#304: an author-owned optional heading is still charged, by name and alone" "heading absent (1): Dependencies" "$(sec_ev "$(run "$WORK/g304-nodeps.md" bug)")"
expect "#304: body text saying Auto-populated by ticket-gate exempts nothing" "heading absent (1): Dependencies" "$(sec_ev "$(run "$WORK/g304-bodytext.md" bug)")"
# The stronger form (gate round 2): the template copy carries no mark, and the body carries the words.
sed '/Auto-populated by ticket-gate/d' "$TPLDIR/bug.yml" > "$WORK/bug-nomark.yml"
grep -q 'Auto-populated by ticket-gate' "$TPLDIR/bug.yml" && ! grep -q 'Auto-populated by ticket-gate' "$WORK/bug-nomark.yml" \
  && ok "#304: the unmarked template copy lost its mark (fixture sanity)" || bad "#304: the unmarked template copy is not unmarked"
python3 - "$WORK/g304-nocc.md" "$WORK/g304-nocc-words.md" <<'PY'
import sys
s=open(sys.argv[1]).read(); bd="### Bug description\n\nfilled in\n"
assert bd in s, "bug description anchor did not match"
open(sys.argv[2],"w").write(s.replace(bd,bd+"Auto-populated by ticket-gate. Do not edit manually.\n",1))
PY
o="$(bash "$SCRIPT" --body "$WORK/g304-nocc-words.md" --template "$WORK/bug-nomark.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: a template that does not mark the field charges it, whatever the body says" "heading absent (1): Codebase Context" "$(sec_ev "$o")"
mktpl "$WORK/g304-cmt.yml" "summary|Summary|true" "notes|Gate notes|false||gate-owned"
printf '<!-- template-version: 6 -->\n\n### Summary\n\nx\n' > "$WORK/g304-cmt.md"
o="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-cmt.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: a # gate-owned YAML comment is the second marking route" pass "$(outcome "$o" sections)"
mktpl "$WORK/g304-plain.yml" "summary|Summary|true" "notes|Gate notes|false|Anything else."
o="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-plain.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: an unmarked optional field is still charged (the exemption does not generalise)" "heading absent (1): Gate notes" "$(sec_ev "$o")"
mktpl "$WORK/g304-req.yml" "summary|Summary|true" "notes|Gate notes|true|Auto-populated by ticket-gate. Do not edit manually."
o="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-req.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: a REQUIRED field is never exempt, whatever its description says" "heading absent (1): Gate notes" "$(sec_ev "$o")"
mktpl "$WORK/g304-case.yml" "summary|Summary|true" "notes|Gate notes|false|auto-populated by Ticket-Gate."
o="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-case.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: the description match is case-sensitive, so a near miss is charged" "heading absent (1): Gate notes" "$(sec_ev "$o")"
dump="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-cmt.yml" --dump-fields)"
expect "#304: --dump-fields keeps its two columns beside the new gate column" "$(printf 'Summary\tyes\nGate notes\tno')" "$dump"
# Region boundary: the #299 shape, a ## body with no Codebase Context heading (so nothing but the
# region can end the last section), a vague Documentation impact, and the gate's appended region.
no_cc() { awk '$0 == "## Codebase Context" { skip = 3 } skip > 0 { skip--; next } { print }'; }
REGION="$(printf '\n<!-- gate-context:start -->\n### Codebase context (gate, 2026-10-01)\n- `plugins/x/y.sh`: a path\n<!-- gate-context:end -->')"
B="$(mkbody feature "g304-r.md" "" "" "" "we should think about it")"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n' "$REGION"; } > "$WORK/g304-r2.md"
grep -qx '## Codebase Context' "$WORK/g304-r2.md" && bad "#304: the region fixture still carries a Codebase Context heading" || ok "#304: the region fixture has no Codebase Context heading (fixture sanity)"
expect "#304: a gate-context region's paths cannot satisfy docs_impact" "$(printf 'fail\tnames no docs and makes no explicit none claim: we should think about it')" "$(docs_row "$(run "$WORK/g304-r2.md" feature)")"
sed 's/^<!-- gate-context:start -->$/&\r/' "$WORK/g304-r2.md" > "$WORK/g304-r2cr.md"
grep -q $'start -->\r$' "$WORK/g304-r2cr.md" && ok "#304: the CR fixture carries a CR (fixture sanity)" || bad "#304: the CR fixture has no CR"
expect "#304: a start marker with a trailing CR still opens a region, so its path is not author text" fail "$(outcome "$(run "$WORK/g304-r2cr.md" feature)" docs_impact)"
sed 's/gate-context:/brief-decision:/' "$WORK/g304-r2.md" > "$WORK/g304-r2brief.md"
expect "#304: a region of any prefix (brief-*) is skipped, not read as author text" fail "$(outcome "$(run "$WORK/g304-r2brief.md" feature)" docs_impact)"
B="$(mkbody feature "g304-p.md" "" "" "" 'Updates `docs/guides/labels.md`')"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n' "$REGION"; } > "$WORK/g304-p2.md"
expect "#304: the author's own docs line is judged and quoted, not the region's" "$(printf 'pass\tUpdates `docs/guides/labels.md`')" "$(docs_row "$(run "$WORK/g304-p2.md" feature)")"
# #335: a region ends only at the end marker of its OWN name (landed in fd05cba), so a nested region
# of another name neither ends the outer skip early nor leaks its paths, and a mismatched end marker
# does not close a region it does not name. Built the way the region fixtures above are.
NEST="$(printf '\n<!-- gate-context:start -->\n<!-- gate-verdict:start -->\n- `plugins/x/y.sh`: a path\n<!-- gate-verdict:end -->\n- `docs/guides/labels.md`\n<!-- gate-context:end -->')"
MISM="$(printf '\n<!-- gate-context:start -->\n- `plugins/x/y.sh`: a path\n<!-- gate-verdict:end -->\n- `docs/guides/labels.md`')"
B="$(mkbody feature "g335.md" "" "" "" "we should think about it")"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n' "$NEST"; } > "$WORK/g335-nest.md"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n' "$MISM"; } > "$WORK/g335-mism.md"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n\n%s\n' "$NEST" 'Updates `docs/guides/labels.md`'; } > "$WORK/g335-after.md"
expect "#335: a nested region of another name leaks no path" "$(printf 'fail\tnames no docs and makes no explicit none claim: we should think about it')" "$(docs_row "$(run "$WORK/g335-nest.md" feature)")"
expect "#335: an end marker of another name does not close the region" "$(printf 'fail\tnames no docs and makes no explicit none claim: we should think about it')" "$(docs_row "$(run "$WORK/g335-mism.md" feature)")"
expect "#335: author text after the nested region closes is read" pass "$(outcome "$(run "$WORK/g335-after.md" feature)" docs_impact)"
CL3='rgn != "" { if (l == "<!-- " rgn ":end -->") rgn = ""; next }'
grep -qF "$CL3" "$SCRIPT" && ok "mutant ledger: section_of() ends a region at its own end marker (#335)" || bad "mutant ledger: #335 end rule not found"
sed 's|if (l == "<!-- " rgn ":end -->") rgn = ""|if (l ~ /:end -->$/) rgn = ""|' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#335: the name-blind mutant did not apply"
o="$(bash "$MUT" --body "$WORK/g335-nest.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature 2>/dev/null)"
expect "mutant: a name-blind end rule lets the nested region's path pass docs_impact (#335 can fail)" pass "$(outcome "$o" docs_impact)"
o="$(bash "$MUT" --body "$WORK/g335-mism.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature 2>/dev/null)"
expect "mutant: a name-blind end rule closes a region at another name's end marker (#335 can fail)" pass "$(outcome "$o" docs_impact)"
# Mutant 1: the gate-filled clause deleted (one line altered); the positive case must flip. Since
# #320 the clause is the per-row test in check 3's loop.
CL1='if [ "$gate" = yes ] && [ "$required" = no ]; then   # check 3: per-row gate flag'
grep -qF "$CL1" "$SCRIPT" && ok "mutant ledger: the script carries the gate-filled clause (#304)" || bad "mutant ledger: #304 gate-filled clause not found"
sed 's/if \[ "\$gate" = yes \] && \[ "\$required" = no \]; then   # check 3/if false; then   # check 3/' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the gate-filled mutant did not apply"
ev="$(sec_ev "$(bash "$MUT" --body "$WORK/g304-nocc.md" --template "$TPLDIR/bug.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)")"
expect "mutant: with the gate-filled clause deleted, Codebase Context is charged (the #304 case can fail)" "heading absent (1): Codebase Context" "$ev"
# #320 finding 1: a required field and a gate-filled optional field may share a label (GitHub forms
# allow it when one has an id); the required one is charged. And a gate-filled field with no `id:`
# keeps its exemption: a TAB-IFS read would collapse the empty id column and shift the flag.
mktpl "$WORK/g320-dup.yml" "summary|Summary|true" "notes_author|Notes|true" "notes_gate|Notes|false|Auto-populated by ticket-gate. Do not edit manually."
printf '<!-- template-version: 6 -->\n\n### Summary\n\nx\n' > "$WORK/g320-dup.md"
o="$(bash "$SCRIPT" --body "$WORK/g320-dup.md" --template "$WORK/g320-dup.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#320: a required field sharing its label with a gate-filled one is charged" "heading absent (1): Notes" "$(sec_ev "$o")"
printf 'body:\n  - type: textarea\n    id: summary\n    attributes:\n      label: Summary\n    validations:\n      required: true\n  - type: textarea\n    attributes:\n      label: Gate notes\n      description: Auto-populated by ticket-gate. Do not edit manually.\n    validations:\n      required: false\n' > "$WORK/g320-noid.yml"
o="$(bash "$SCRIPT" --body "$WORK/g320-dup.md" --template "$WORK/g320-noid.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#320: a gate-filled field with no id keeps its exemption" "every charged section present, every required one filled (headings at ###); gate-filled, absent and not charged (1): Gate notes" "$(sec_ev "$o")"
sed 's/if \[ "\$gate" = yes \] && \[ "\$required" = no \]; then   # check 3/if grep -qxF -- "$label" <<< "$(printf "%s\\n" "$TEMPLATE_FIELDS" | awk -F"\\t" '"'"'$4 == "yes" \&\& $2 == "no" { print $1 }'"'"')"; then   # check 3/' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#320: the label-lookup mutant did not apply"
o="$(bash "$MUT" --body "$WORK/g320-dup.md" --template "$WORK/g320-dup.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "mutant: the exemption looked up by label passes the shared-label template (#320 can fail)" pass "$(outcome "$o" sections)"
# #320 finding 2: only a WHOLE-LINE start marker opens a region; text after it on the line is author text.
B="$(mkbody feature "g320-r.md" "" "" "" '<!-- gate-context:start --> is the marker the gate writes')"
{ sed 's/^### /## /' "$B" | no_cc; } > "$WORK/g320-same.md"
printf 'Updates `docs/guides/labels.md`\n' >> "$WORK/g320-same.md"
expect "#320: text after a start marker on its line is author content" pass "$(outcome "$(run "$WORK/g320-same.md" feature)" docs_impact)"
B="$(mkbody feature "g320-w.md" "" "" "" 'x')"
{ sed 's/^### /## /' "$B" | no_cc | sed '/^## Documentation impact$/,$d'; printf '## Documentation impact\n\n<!-- gate-context:start -->\nUpdates `docs/guides/labels.md`\n<!-- gate-context:end -->\n'; } > "$WORK/g320-whole.md"
expect "#320: a whole-line start marker still hides its region" "$(printf 'fail\tno content in Documentation impact')" "$(docs_row "$(run "$WORK/g320-whole.md" feature)")"
sed 's|l ~ /^<!-- \[^ \\t\]+:start -->\$/|l ~ /^<!-- [^ \\t]+:start -->/|' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#320: the anchor mutant did not apply"
o="$(bash "$MUT" --body "$WORK/g320-same.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature 2>/dev/null)"
expect "mutant: the start marker's end anchor dropped hides same-line author text (#320 can fail)" fail "$(outcome "$o" docs_impact)"
# Mutant 2: the region-start rule removed from section_of(); the region case must flip to pass.
CL2='l ~ /^<!-- [^ \t]+:start -->$/ { rgn = substr(l, 6, length(l) - 15); next }'
grep -qF "$CL2" "$SCRIPT" && ok "mutant ledger: section_of() carries the region boundary (#304)" || bad "mutant ledger: #304 region boundary not found"
grep -vF "$CL2" "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the boundary mutant did not apply"
o="$(bash "$MUT" --body "$WORK/g304-r2.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature 2>/dev/null)"
expect "mutant: with the region boundary removed, the region's path passes docs_impact (the #304 case can fail)" pass "$(outcome "$o" docs_impact)"
# Review round 1 of #304: the mark is anchored to the template's own structure, and a region is
# skipped to its end marker rather than ending the section, so author text below it is still read.
cat > "$WORK/g304-blk.yml" <<'YML'
body:
  - type: textarea
    id: summary
    attributes:
      label: Summary
    validations:
      required: true
  - type: textarea
    id: notes
    attributes:
      label: Notes
      placeholder: |
        Auto-populated by ticket-gate is a phrase an author may quote here.
        # gate-owned
    validations:
      required: false
  # gate-owned
  - type: textarea
    id: deps
    attributes:
      label: Deps
    validations:
      required: false
YML
o="$(bash "$SCRIPT" --body "$WORK/g304-cmt.md" --template "$WORK/g304-blk.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#304: block-scalar text and a comment above the next field mark nothing, so both are charged" "heading absent (2): Notes; Deps" "$(sec_ev "$o")"
UNITREG="$(printf -- '- [ ] `tests/unit/foo.test.ts` covers it\n\n<!-- brief-notes:start -->\nregion text\n<!-- brief-notes:end -->\n\nN/A: a pure refactor with no behaviour change')"
B="$(mkbody feature "g304-u.md" "" "$UNITREG")"
expect "#304: author text below a region's end marker is still judged (an N/A there refers)" referred "$(outcome "$(run "$B" feature)" unit_tests)"
GWTREG="$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED\n\n<!-- brief-extra:start -->\nx\n<!-- brief-extra:end -->\n\nNegative\n- Given: f\n- When: g\n- When: h\n- Then: 400 BAD')"
B="$(mkbody feature "g304-g.md" "$GWTREG")"
expect "#304: a malformed block below a region still fails check 4" "$(printf 'fail\teach scenario block needs exactly one When (Negative: 2 When lines)')" "$(printf '%s\n' "$(run "$B" feature)" | awk -F'\t' '$1=="gwt"{print $2 "\t" $3}')"
# #414: a script that exits changes the evidence too, so m304_kill classifies the build with
# mutant_crash_reason "<build>" /dev/null tm_live "<build>" before it credits the kill (#330).
# tm_live <build>: on the bare body and the feature template the build prints one sections row.
tm_live() {
  local o; o="$(bash "$1" --body "$WORK/bare.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null)"
  [ "$(grep -c "^sections$(printf '\t')" <<< "$o")" = 1 ]
}
m304_kill() {  # m304_kill <name> <build> <ok text>: the g304-cmt case on <build>, classified, then its kill
  local ev why
  ev="$(sec_ev "$(bash "$2" --body "$WORK/g304-cmt.md" --template "$WORK/g304-blk.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)")"
  why=$(mutant_crash_reason "$2" /dev/null tm_live "$2")
  if [ -n "$why" ]; then bad "mutant $1 crashed ($why)"; return; fi
  [ "$ev" != "heading absent (2): Notes; Deps" ] && ok "$3" || bad "mutant: the $1 mutant survived"
}
# Mutant 3: the description anchor dropped (the phrase matched on any template line).
CL3='/^      description: / && index($0, "Auto-populated by ticket-gate") { gate = 1 }'
grep -qF "$CL3" "$SCRIPT" && ok "mutant ledger: the description match is anchored to the field's description line (#304)" || bad "mutant ledger: #304 description anchor not found"
awk -v c="$CL3" 'index($0, c) { sub(/\/\^      description: \/ && /, "") } { print }' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the description-anchor mutant did not apply"
M304_OK3="mutant: with the description anchor dropped, placeholder text exempts Notes (the #304 case can fail)"
m304_kill description-anchor "$MUT" "$M304_OK3"
# Mutant 4: the gate-owned comment matched at any indent.
CL4='/^    # gate-owned[[:space:]]*$/ { gate = 1 }'
grep -qF "$CL4" "$SCRIPT" && ok "mutant ledger: the gate-owned comment is anchored to the key indent (#304)" || bad "mutant ledger: #304 comment anchor not found"
awk -v c="$CL4" 'index($0, c) { sub(/\/\^    # gate-owned/, "/^[[:space:]]*# gate-owned") } { print }' "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the comment-anchor mutant did not apply"
m304_kill comment-anchor "$MUT" "mutant: with the comment matched at any indent, the wrong fields are exempt (the #304 case can fail)"
# Crash control (#414): its own copy, so $MUT is never overwritten. Its empty evidence differs from
# the expected text, which the kill alone would credit. m304_kill runs in $( ), so its row stays out
# of the total, and the capture is not echoed.
sed '1a\
exit 127' "$MUT" > "$WORK/m304-crash.sh"
crash_ok=1
cmp -s "$WORK/m304-crash.sh" "$MUT" && crash_ok=0
cap=$(m304_kill crash-control "$WORK/m304-crash.sh" "$M304_OK3")
case "$cap" in *"the #304 case can fail"*) crash_ok=0 ;; *"FAIL: mutant crash-control crashed (the liveness run failed)"*) ;; *) crash_ok=0 ;; esac
[ "$crash_ok" = 1 ] && ok "crash control: m304_kill reports a crashing script as crashed, never as a kill" \
  || bad "crash control: m304_kill credited or missed a crashing script"

echo "check-ticket-mechanics: the runner itself"
out="$(run "$B" feature)"
expect "emits exactly one row per check" 7 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
printf '%s\n' "$out" | awk -F'\t' 'NF != 3 { bad = 1 } END { exit bad + 0 }' \
  && ok "every row is three tab-separated fields" || bad "a row is not three fields"
echo "check-ticket-mechanics: a ## body is judged on its content, not reported as five missing sections (#190)"
# `gh issue create --body-file` is a first-class filing path here and it produces `##` headings.
# The matcher keyed on `### ` alone, so every section read as absent and a doc-compliant ticket
# got five FAILs where a `###` copy of the same body got two and a referred. The script's own rule
# is that a heuristic miss refers rather than fails; a heading-level miss is exactly that. There
# is no per-body level: a label is present at either level, and its section runs to the next
# heading at its OWN level or the next heading that is a template label, whichever first, so a
# ### body is untouched and a ## section keeps its non-label ### subsections as content.
B="$(mkbody feature "hh-ok.md")"; sed 's/^### /## /' "$B" > "$WORK/hh2.md"
out="$(run "$WORK/hh2.md" feature)"
offenders="$(printf '%s\n' "$out" | awk -F'\t' '$2 == "fail" { printf "%s=%s ", $1, $2 }')"
[ -z "$offenders" ] && ok "a compliant ticket at ## headings has no spurious FAIL" || bad "## body: $offenders"
expect "and its sections row passes" pass "$(outcome "$out" sections)"
grep -q '##' <<< "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "sections"')" \
  && ok "and the sections evidence names the heading level it keyed on" || bad "sections evidence does not name the ## level"
expect "and GWT is judged on its content, not referred for a missing section" pass "$(outcome "$out" gwt)"
# Not loosened: a section that IS absent at ## still fails, by name.
grep -v '^## Documentation impact' "$WORK/hh2.md" > "$WORK/hh2-missing.md"
out="$(run "$WORK/hh2-missing.md" feature)"
expect "a genuinely absent section at ## still FAILS" fail "$(outcome "$out" sections)"
grep -q 'Documentation impact' <<< "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "sections"')" \
  && ok "and names the absent section" || bad "the absent section is not named"
# A ## section runs to the next ## heading, so ### subsections inside it are CONTENT.
python3 - "$WORK/hh2.md" "$WORK/hh2-sub.md" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
s=s.replace("## Test scenarios (Given / When / Then)\n\n", "## Test scenarios (Given / When / Then)\n\n### The only condition\n\n",1)
open(sys.argv[2],"w").write(s)
PY
expect "a ### subsection inside a ## section is content, not a section boundary" pass "$(outcome "$(run "$WORK/hh2-sub.md" feature)" gwt)"
# A ### body is untouched by the detection: a stray ## prose heading does not flip the level.
{ cat "$B"; printf '\n## A closing remark\n\nprose\n'; } > "$WORK/hh3-stray.md"
expect "a ### body with a stray ## prose heading keeps the ### contract" pass "$(outcome "$(run "$WORK/hh3-stray.md" feature)" sections)"
# Mixed levels across TEMPLATE labels are READ, not adjudicated: dep-auditor emits `### Priority`
# beside `##` sections (found by the gate reviewing this ticket), and a "### wins" rule inverted
# that body exactly as v5 did. A label is present at either level, and its section runs to the
# next heading at its own level or the next heading that IS a template label, whichever first.
{ cat "$B"; printf '\n## Unit tests\n\nN/A\n'; } > "$WORK/hh3-mixed.md"
expect "a ### body that also carries a template label at ## still passes sections" pass "$(outcome "$(run "$WORK/hh3-mixed.md" feature)" sections)"
sed 's/^## Priority$/### Priority/' "$WORK/hh2.md" > "$WORK/hh2-depaud.md"
out="$(run "$WORK/hh2-depaud.md" feature)"
offenders="$(printf '%s\n' "$out" | awk -F'\t' '$2 == "fail" { printf "%s=%s ", $1, $2 }')"
[ -z "$offenders" ] && ok "the dep-auditor shape (### Priority beside ## sections) has no spurious FAIL" || bad "dep-auditor shape: $offenders"
# A ### label heading ENDS the ## section before it, so Priority's content is not read as Summary's.
python3 - "$WORK/hh2.md" "$WORK/hh2-bleed.md" <<'PY'
import sys
s=open(sys.argv[1]).read()
s=s.replace("## Documentation impact\n\nUpdates `docs/guides/auth.md`\n", "## Documentation impact\n\n_No response_\n\n### Codebase Context\n\nUpdates `docs/guides/auth.md`\n",1)
open(sys.argv[2],"w").write(s)
PY
out="$(run "$WORK/hh2-bleed.md" feature)"
[ "$(outcome "$out" docs_impact)" != pass ] && ok "a ### label heading ends the ## section before it (no content bleeds across)" || bad "content bled from the next labelled section into docs_impact"
# The OWN-LEVEL boundary: a same-level heading that is NOT a template label (the author's own
# `## Design notes`) still ends the section, or an empty Unit tests section would read the notes
# that follow it as its content and pass. Found by gate round 2: dropping this clause survived
# every case above.
python3 - "$WORK/hh2.md" "$WORK/hh2-own.md" <<'PY'
import sys
s=open(sys.argv[1]).read()
s=s.replace("## Unit tests\n\n- [ ] `tests/unit/auth.test.ts` valid input -> session\n", "## Unit tests\n\n_No response_\n\n## Design notes\n\n- [ ] `tests/unit/auth.test.ts` valid input -> session\n",1)
open(sys.argv[2],"w").write(s)
PY
[ "$(outcome "$(run "$WORK/hh2-own.md" feature)" unit_tests)" != pass ] \
  && ok "a same-level heading that is not a label still ends the section (own-level boundary)" \
  || bad "an empty Unit tests section read the author's next ## section as its content"

bash "$SCRIPT" --body "$WORK/nope.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x >"$WORK/o" 2>/dev/null
[ $? -ne 0 ] && ok "a missing body exits non-zero" || bad "a missing body exited 0"
[ ! -s "$WORK/o" ] && ok "a missing body emits NO rows, so it cannot read as all-pass" || bad "a missing body emitted rows"
bash "$SCRIPT" --body "$B" --template "$WORK/nope.yml" --tpl-version 6 --current-tpl-version 6 --labels x >/dev/null 2>&1
[ $? -ne 0 ] && ok "a missing template exits non-zero" || bad "a missing template exited 0"
: > "$WORK/empty.yml"
bash "$SCRIPT" --body "$B" --template "$WORK/empty.yml" --tpl-version 6 --current-tpl-version 6 --labels x >"$WORK/o2" 2>/dev/null
rc=$?
[ $rc -ne 0 ] && ok "REGRESSION: a template parsing to no fields exits non-zero" || bad "an empty template exited 0"
[ ! -s "$WORK/o2" ] && ok "REGRESSION: an empty template reports no 'sections pass'" || bad "an empty template emitted rows"
bash "$SCRIPT" --body "$B" --template "$TPLDIR/feature.yml" --bogus 1 >/dev/null 2>&1
[ $? -ne 0 ] && ok "an unknown argument exits non-zero" || bad "an unknown argument was ignored"
# A recognised flag with no value used to make `shift 2` a no-op and spin forever.
timeout 10 bash "$SCRIPT" --body >/dev/null 2>&1
rc=$?
[ $rc -ne 0 ] && [ $rc -ne 124 ] && ok "REGRESSION: a trailing valueless flag refuses instead of hanging" \
  || bad "a trailing valueless flag hung or succeeded (rc=$rc)"
run "$B" feature >/dev/null 2>&1
[ $? -eq 0 ] && ok "a run with FAIL rows still exits 0, so a fail is data" || bad "a normal run exited non-zero"
grep -q '# check-ticket-mechanics-version: [0-9]' "$SCRIPT" && ok "carries a version marker" || bad "no version marker"
# --help prints the header verbatim, so a stale header is a lie told to the caller.
helptext="$(bash "$SCRIPT" --help)"
grep -q 'referred' <<< "$helptext" \
  && ok "--help describes the current referred-not-na rule" || bad "--help header is stale"
grep -q -- '--dump-fields' <<< "$helptext" \
  && ok "--help documents every flag it accepts" || bad "--help omits a flag"
# #455: the #259 maintainer note sits below the header, so --help opens with what the script does.
first455=$(awk '{t=$0; sub(/^# ?/,"",t)} t!="" && t !~ /-version: /{print t; exit}' <<< "$helptext")
case "$first455" in "Step 3A's mechanical checks"*) ok "--help opens with the purpose line (#455)" ;; *) bad "--help opens with the purpose line (#455) (got '$first455')" ;; esac
grep -q 'NO .awk -v. IN THIS FILE' <<< "$helptext" \
  && bad "--help does not print the #259 maintainer note (#455)" \
  || ok "--help does not print the #259 maintainer note (#455)"
hb455=$(awk 'NR>1 && /^$/{print NR; exit}' "$SCRIPT"); nl455=$(grep -n -m1 'NO .awk -v. IN THIS FILE' "$SCRIPT" | cut -d: -f1)
expect "the #259 note stays in the source once, below the header (#455)" "1 below" \
  "$(grep -c 'NO .awk -v. IN THIS FILE' "$SCRIPT") $([ "${nl455:-0}" -gt "${hb455:-0}" ] && echo below || echo above)"

echo "check-ticket-mechanics: the label shape the gate writes is one check 4 reads (#273)"
# The gate is constrained (ticket-gate.md Step 6 item 2 and the Step 0c-iii scenarios row);
# marker_re is NOT widened, so the #267 shapes stay pinned to the narrow outcomes below.
gwt_row() { printf '%s\n' "$1" | awk -F'\t' '$1=="gwt"{print $2 "\t" $3}'; }
blk() { printf '%s\n- Given: g\n- When: w\n- Then: 401 AUTH_FAILED\n\n' "$@"; }
B="$(mkbody feature "g273-a.md" "$(blk '**Positive:** first' '**Negative:** bad input (gate-written, round 1)' '**Positive:** changed body (gate-written, round 1)')")"
expect "#273: bold-colon labels with trailing provenance are markers" "$(printf 'pass\t2 positive and 1 negative blocks, each Then specific')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g273-b.md" "$(blk '**Positive:** first' 'Negative (gate-written, round 1 critic)' 'Positive (changed body, gate-written, round 1 critic)')")"
expect "#273: a bare marker with one comma-bearing parenthetical is a marker" "$(printf 'pass\t2 positive and 1 negative blocks, each Then specific')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g273-c.md" "$(blk '**Positive:** first' 'Negative *(gate-written, round 1 critic)*')")"
expect "#273: the #267 Negative label is not a marker (literal string 1)" "$(printf 'fail\tneeds at least one Positive and one Negative block (found 1 positive, 0 negative)')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g273-d.md" "$(blk '**Positive:** first' 'Negative *(gate-written, round 1 critic)*' 'Positive, changed body *(gate-written, round 1 critic)*' '**Negative:** later')")"
expect "#273: the #267 pair before a real Negative folds into the author Positive (literal strings 1 and 2)" "$(printf 'fail\teach scenario block needs exactly one When (Positive: 3 When lines)')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g273-e.md" "$(blk '**Positive:** first' '**Negative** *(gate-written, round 1 critic)*' '**Positive, changed body** *(gate-written, round 1 critic)*')")"
expect "#273: a comma inside the bold is not a marker" "$(printf 'fail\teach scenario block needs exactly one When (Negative: 2 When lines)')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g273-f.md" "$(blk '**Positive:** x' '**Negative: bad input (gate-written, round 1)**')")"
expect "#273: a colon inside the bold followed by text is not a marker" "$(printf 'fail\tneeds at least one Positive and one Negative block (found 1 positive, 0 negative)')" "$(gwt_row "$(run "$B" feature)")"
# Drift: the example ticket-gate.md documents is the one the checker is run on. The example is
# the first backticked span containing `gate-written` in Step 6 item 2.
GATE_MD="$ROOT/plugins/forge-kit-governance/agents/ticket-gate.md"
gw_example() {
  local ex
  ex="$(awk '/^2\. Where the critic WROTE/ { on = 1 } on && /^3\. / { exit } on { printf "%s ", $0 }' "$1" \
    | grep -o '`[^`]*gate-written[^`]*`' | head -1 | tr -d '`')"
  [ -n "$ex" ] || { echo "documented gate-written scenario example not found" >&2; return 1; }
  printf '%s\n' "$ex"
}
ex="$(gw_example "$GATE_MD")"
case "$ex" in "**Negative:** <title> (gate-written, round N)") ok "#273: the Step 6 item 2 example is extracted whole" ;; *) bad "#273: unexpected Step 6 item 2 example: '$ex'" ;; esac
ex="$(printf '%s' "$ex" | sed 's/<title>/bad input/; s/round N/round 1/')"
B="$(mkbody feature "g273-g.md" "$(blk '**Positive:** first' '**Negative:** author case' "$ex")")"
case "$(gwt_row "$(run "$B" feature)")" in pass*) ok "#273: the documented example beside an author pair passes check 4" ;; *) bad "#273: the documented example fails check 4: $(gwt_row "$(run "$B" feature)")" ;; esac
sed 's/`\*\*Negative:\*\* <title> (gate-written, round N)`/a gate-written label/' "$GATE_MD" > "$WORK/gate-noex.md"
cmp -s "$GATE_MD" "$WORK/gate-noex.md" && bad "#273: the no-example copy did not apply"
msg="$(gw_example "$WORK/gate-noex.md" 2>&1 >/dev/null)"; rc=$?
expect "#273: a missing example fails loudly" "documented gate-written scenario example not found" "$msg"
[ "$rc" -ne 0 ] && ok "#273: and returns non-zero" || bad "#273: a missing example returned 0"
grep -q 'Apply the section "GWT scenarios" quality bar.*`\*\*Positive:\*\* <title>`' "$GATE_MD" \
  && ok "#273: the Step 0c-iii scenarios row states the label form beside its section anchor" || bad "#273: the scenarios row lacks the label form"
# #349: the critic's own advice names a label check 4 reads. Step 3B element 3 gives the shape the
# critic writes; #341's critic invented `Control (...)`, which check 4 does not read, and #292's
# writer used `_(...)_`. The checker is unchanged: the guidance moved to it.
B="$(mkbody feature "g349-a.md" "$(blk '**Positive:** valid user' '**Negative:** bad password')")"
expect "#349: the label shape Step 3B names passes check 4" "$(printf 'pass\t1 positive and 1 negative blocks, each Then specific')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g349-b.md" "$(blk 'Control (valid user)' '**Negative:** bad password')")"
expect "#349: Control is not a label (the #341 advice)" "$(printf 'fail\tneeds at least one Positive and one Negative block (found 0 positive, 1 negative)')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g349-c.md" "$(blk 'Positive' 'Negative _(gate-written, round 1: bad password)_')")"
expect "#349: the #292 underscore-italic annotation is not a marker" "$(printf 'fail\tneeds at least one Positive and one Negative block (found 1 positive, 0 negative)')" "$(gwt_row "$(run "$B" feature)")"
B="$(mkbody feature "g349-d.md" "$(blk '**Positive:** valid user (gate-written, round 1)' '**Negative:** bad password (gate-written, round 1)')")"
expect "#349: the Step 6 item 2 gate-written shape passes" pass "$(outcome "$(run "$B" feature)" gwt)"
# Extract and run: the first backticked span holding **Positive:** in Step 3B element 3.
cr_example() {
  local ex n
  ex="$(awk '/^3\. \*\*GWT review or additions\*\*/ { on = 1 } on && /^4\. / { exit } on { printf "%s ", $0 }' "$1" \
    | grep -o '`[^`]*\*\*Positive:\*\*[^`]*`')"
  n="$(printf '%s' "$ex" | grep -c .)"
  [ "$n" = 1 ] || { echo "documented critic scenario label not found exactly once (found $n)" >&2; return 1; }
  printf '%s\n' "$ex" | tr -d '`'
}
ex="$(cr_example "$GATE_MD")"
case "$ex" in "**Positive:** <title>") ok "#349: the Step 3B element 3 example is extracted whole" ;; *) bad "#349: unexpected Step 3B example: '$ex'" ;; esac
B="$(mkbody feature "g349-e.md" "$(blk "$(printf '%s' "$ex" | sed 's/<title>/valid user/')" '**Negative:** bad password')")"
case "$(gwt_row "$(run "$B" feature)")" in pass*) ok "#349: the documented critic label passes check 4" ;; *) bad "#349: the documented critic label fails check 4: $(gwt_row "$(run "$B" feature)")" ;; esac
sed 's/`\*\*Positive:\*\* <title>` or `\*\*Negative:\*\* <title>`\./`Control (valid user)`./' "$GATE_MD" > "$WORK/gate-cr-control.md"
cmp -s "$GATE_MD" "$WORK/gate-cr-control.md" && bad "#349: the Control copy did not apply"
msg="$(cr_example "$WORK/gate-cr-control.md" 2>&1 >/dev/null)"; rc=$?
expect "#349: a Step 3B example swapped to Control is not found, loudly" "documented critic scenario label not found exactly once (found 0)" "$msg"
[ "$rc" -ne 0 ] && ok "#349: and returns non-zero" || bad "#349: a Control example returned 0"

echo "== no awk -v in the shipped asset, and a backslash label resolves (#259) =="
# #405: the zero-`awk -v` rule and the no-operand rule, one definition in scripts/awkv-count.sh.
. "$ROOT/scripts/awkv-count.sh"; awkv_checks check-ticket-mechanics.sh "$SCRIPT" "$WORK"
# A template LABEL carrying backslash-t: under -v, section_of() looked for `Steps<TAB>x` and the
# filled section read as empty.
printf 'body:\n  - type: textarea\n    id: steps\n    attributes:\n      label: Steps\\tx\n    validations:\n      required: true\n' > "$WORK/bs.yml"
printf '<!-- template-version: 6 -->\n\n## Steps\\tx\n\nreal content\n' > "$WORK/bs-full.md"
printf '<!-- template-version: 6 -->\n\n## Steps\\tx\n\n' > "$WORK/bs-empty.md"
grep -qF 'Steps\tx' "$WORK/bs.yml" && ok "#259: the fixture label carries a literal backslash-t (fixture sanity)" || bad "#259: the fixture label has no backslash-t"
o="$(bash "$SCRIPT" --body "$WORK/bs-full.md" --template "$WORK/bs.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#259: a backslash-t label resolves to its filled section" pass "$(outcome "$o" sections)"
o="$(bash "$SCRIPT" --body "$WORK/bs-empty.md" --template "$WORK/bs.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)"
expect "#259: and an empty one still fails, by its label as typed" 'required heading present but empty (1): Steps\tx' "$(sec_ev "$o")"

# #405: a file named name=value is read as a file. Before, awk took `b=x.md` for an assignment and
# read stdin, so a filled section was reported empty; `tp=x.yml` parsed no fields at all.
cp "$WORK/bs-full.md" "$WORK/b=x.md"; cp "$WORK/bs.yml" "$WORK/tp=x.yml"; cp "$WORK/proj/docs/guides/labels.md" "$WORK/l=x.md"
ctm() { (cd "$WORK" && bash "$SCRIPT" --tpl-version 6 --current-tpl-version 6 "$@" 2>&1 </dev/null); }
o="$(ctm --body 'b=x.md' --template bs.yml --labels backend,bug)"
expect "#405: --body 'b=x.md' reads the body: its filled section passes" pass "$(outcome "$o" sections)"
expect "#405: --template 'tp=x.yml' gives the same rows as bs.yml" "$(ctm --body bs-full.md --template bs.yml --labels backend,bug)" \
  "$(ctm --body bs-full.md --template 'tp=x.yml' --labels backend,bug | sed 's/tp=x\.yml/bs.yml/g')"
o="$(ctm --body bs-full.md --template bs.yml --labels protocol,feature --labels-doc 'l=x.md' | awk -F'\t' '$1=="labels"{print $2}')"
expect "#405: --labels-doc 'l=x.md' reads the project's areas (protocol passes)" pass "$o"

echo "check-ticket-mechanics: a heading inside a fenced code block is never a heading (#485)"
# A ticket that quotes a template heading inside a code block had the quote read as the real
# section, by section_of() AND by check 3's presence scan. Every body below is the generated bug
# body with text inserted into Steps to reproduce (and, where named, the real scenarios section
# removed), so one inserted fence is the only difference from a passing body. Fence grammar is
# CommonMark 0.31.2 section 4.5.
cat > "$WORK/f485.py" <<'PY'
import sys
src, out, ins, drop = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "drop"
s = open(src).read()
anchor = "### Steps to reproduce\n\nfilled in\n"
assert anchor in s, "steps anchor did not match"
s = s.replace(anchor, anchor + "\n" + ins + "\n", 1)
if drop:
    h = "### Test scenarios (Given / When / Then)\n"
    i = s.rindex(h); j = s.index("\n### ", i + len(h))
    s = s[:i] + s[j + 1:]
open(out, "w").write(s)
PY
B485="$(mkbody bug "f485-base.md")"
f485() {  # f485 <name> <inserted text> [drop]; prints the body path
  python3 "$WORK/f485.py" "$B485" "$WORK/$1.md" "$2" "${3:-keep}"; printf '%s' "$WORK/$1.md"; }
gwt_ev() { printf '%s\n' "$1" | awk -F'\t' '$1=="gwt"{print $2 "\t" $3}'; }
Q='### Test scenarios (Given / When / Then)'
BT='```'
GWT_OK="$(printf 'pass\t1 positive and 1 negative blocks, each Then specific')"
expect "#485: the unchanged base body passes gwt (fixture sanity)" "$GWT_OK" "$(gwt_ev "$(run "$B485" bug)")"
F1="$(f485 f1 "$(printf '%s\n%s\n\n- quoted example\n%s' "$BT" "$Q" "$BT")")"
F2="$(f485 f2 "$(printf '~~~\n%s\n\n- quoted example\n~~~' "$Q")")"
F3="$(f485 f3 "$(printf '````\n%s\n%s\n````' "$BT" "$Q")")"
F4="$(f485 f4 "$(printf '%s\n~~~\n%s\n%s' "$BT" "$Q" "$BT")")"
F5="$(f485 f5 "$(printf '   %s\n%s\n   %s' "$BT" "$Q" "$BT")")"
F7="$(f485 f7 "$(printf '%s\n%s\n\n- quoted example\n%s' "$BT" "$Q" "$BT")" drop)"
F8="$(f485 f8 "$(printf '%s\nan unclosed fence' "$BT")")"
F9="$(f485 f9 "$(printf '%s\n%sbash\n%s\n%s' "$BT" "$BT" "$Q" "$BT")")"
F10="$(f485 f10 "$(printf '%s\n<!-- gate-context:start -->\n%s\n%s' "$BT" "$Q" "$BT")")"
G1="$(f485 g1 "$(printf '%sx%s inline code, not a fence' "$BT" "$BT")")"
G2="$(f485 g2 "$(printf '<!-- gate-context:start -->\n%s\n<!-- gate-context:end -->' "$BT")")"
G3="$(f485 g3 "$(printf '    %s' "$BT")")"
grep -qxF "$Q" "$F7" && [ "$(grep -c "^$BT\$" "$F7")" = 2 ] && [ "$(grep -cxF "$Q" "$F7")" = 1 ] \
  && ok "#485: the fence-only body quotes the heading once and has no real one (fixture sanity)" || bad "#485: the fence-only fixture is malformed"
expect "#485: a backtick fence quoting the scenarios heading does not hide the real section" "$GWT_OK" "$(gwt_ev "$(run "$F1" bug)")"
expect "#485: a tilde fence quoting the scenarios heading does not hide the real section" "$GWT_OK" "$(gwt_ev "$(run "$F2" bug)")"
expect "#485: three backticks inside a four-backtick fence do not close it" "$GWT_OK" "$(gwt_ev "$(run "$F3" bug)")"
expect "#485: a tilde line does not close a backtick fence" "$GWT_OK" "$(gwt_ev "$(run "$F4" bug)")"
expect "#485: a fence indented three spaces is a fence" "$GWT_OK" "$(gwt_ev "$(run "$F5" bug)")"
o="$(run "$F7" bug)"
expect "#485: a scenarios heading that exists only inside a fence fails sections" fail "$(outcome "$o" sections)"
case "$(sec_ev "$o")" in "heading absent ("*"Test scenarios (Given / When / Then)"*) ok "#485: ...as heading absent, naming the scenarios label" ;;
  *) bad "#485: the fence-only heading was counted present: $(sec_ev "$o")" ;; esac
o="$(run "$F8" bug)"
expect "#485: an unclosed fence hides every heading after it (sections fail)" fail "$(outcome "$o" sections)"
case "$(sec_ev "$o")" in "heading absent ("*"Test scenarios (Given / When / Then)"*) ok "#485: ...and names the scenarios label as absent" ;;
  *) bad "#485: an unclosed fence left the scenarios heading present: $(sec_ev "$o")" ;; esac
expect "#485: a backtick line followed by text does not close the fence" "$GWT_OK" "$(gwt_ev "$(run "$F9" bug)")"
expect "#485: ...and every later heading stays present (sections)" pass "$(outcome "$(run "$F9" bug)" sections)"
o="$(run "$F10" bug)"
expect "#485: a region start marker inside a fence is literal (gwt)" "$GWT_OK" "$(gwt_ev "$o")"
expect "#485: ...and opens no region that swallows later sections" pass "$(outcome "$o" sections)"
expect "#485: Guard: a line starting with inline triple-backtick code opens no fence" "$GWT_OK" "$(gwt_ev "$(run "$G1" bug)")"
expect "#485: Guard: a fence line inside a gate region opens no fence" "$GWT_OK" "$(gwt_ev "$(run "$G2" bug)")"
# The same freeze in body_headings(): a fence opened there would hide every later heading from
# the presence scan, which gwt never reads, so only the sections row can see it (round 1, M1).
expect "#485: Guard: ...and the presence scan still sees every later heading (sections)" pass "$(outcome "$(run "$G2" bug)" sections)"
expect "#485: Guard: a backtick line indented four spaces opens no fence" "$GWT_OK" "$(gwt_ev "$(run "$G3" bug)")"
# Round 1: a closer's indent is measured on its own, so a closer indented 2 spaces closes a fence
# opened at 0, and a line indented 4 spaces closes nothing, so the quoted heading after it stays
# inside the fence and the true closer below it ends the fence.
F11="$(f485 f11 "$(printf '%s\n%s\n  %s' "$BT" "$Q" "$BT")")"
F12="$(f485 f12 "$(printf '%s\n    %s\n%s\n%s' "$BT" "$BT" "$Q" "$BT")")"
expect "#485: a closer indented 2 spaces closes a fence opened at 0" "$GWT_OK" "$(gwt_ev "$(run "$F11" bug)")"
expect "#485: a line indented 4 spaces closes no fence (sections)" pass "$(outcome "$(run "$F12" bug)" sections)"
expect "#485: ...and the quoted heading after it is no section (gwt)" "$GWT_OK" "$(gwt_ev "$(run "$F12" bug)")"
# mawk 1.3.4 reads `sub(/^ ? ? ?/, ...)` as stripping one space, so the indent is measured with
# match() instead (round 1, H1). Running the indent rows under mawk is the CI-visible tripwire for
# that, as busybox is above for the rest; the skip line says when mawk is absent.
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$WORK/mawk"; printf '#!/bin/sh\nexec mawk "$@"\n' > "$WORK/mawk/awk"; chmod +x "$WORK/mawk/awk"
  expect "#485: portability: a fence indented three spaces is a fence under mawk" "$GWT_OK" "$(gwt_ev "$(PATH="$WORK/mawk:$PATH" run "$F5" bug)")"
  expect "#485: portability: a closer indented 2 spaces closes the fence under mawk" "$GWT_OK" "$(gwt_ev "$(PATH="$WORK/mawk:$PATH" run "$F11" bug)")"
  expect "#485: portability: ...and every section stays present under mawk" pass "$(outcome "$(PATH="$WORK/mawk:$PATH" run "$F11" bug)" sections)"
else
  ok "#485: portability: mawk not on PATH, fence-indent case skipped"
fi
# A code block inside a real section stays that section's content, and its heading-shaped lines
# end nothing: the Unit tests row comes AFTER the fenced Documentation impact line, and the docs
# row quotes the real Documentation impact section rather than the fence.
U6="$(mkbody bug "f485-u6.md" "" "$(printf '~~~\n## Documentation impact\n~~~\n- [ ] `tests/unit/auth.test.ts` valid input -> session')")"
o="$(run "$U6" bug)"
expect "#485: a fenced template-label heading does not cut the Unit tests section" "$(printf 'pass\t~~~')" "$(printf '%s\n' "$o" | awk -F'\t' '$1=="unit_tests"{print $2 "\t" $3}')"
expect "#485: ...and the docs row reads the real Documentation impact section" "$(printf 'pass\tUpdates `docs/guides/auth.md`')" "$(docs_row "$o")"
# A fence's content inside a section is still that section's content (round 1, L1).
U7="$(mkbody bug "f485-u7.md" "" "$(printf '~~~\n- [ ] `tests/unit/auth.test.ts` valid input -> session\n~~~')")"
expect "#485: a Unit tests row that sits only inside a fence still counts" pass "$(outcome "$(run "$U7" bug)" unit_tests)"
# The heading-level evidence counts real headings only: a ## body quoting a ### label in a fence.
sed 's/^### /## /' "$B485" > "$WORK/f485-l2base.md"
python3 - "$WORK/f485-l2base.md" "$WORK/f485-l2.md" <<'PY'
import sys
s = open(sys.argv[1]).read(); a = "## Steps to reproduce\n\nfilled in\n"
assert a in s, "level-2 steps anchor did not match"
open(sys.argv[2], "w").write(s.replace(a, a + "\n```\n### Documentation impact\n```\n", 1))
PY
expect "#485: a fenced ### label on a ## body reports headings at ## only" \
  "every template section present, every required one filled (headings at ##)" "$(sec_ev "$(run "$WORK/f485-l2.md" bug)")"
# --headings: the one fence-aware heading reader, exposed for forge-gate-mechanics.sh's SHAPED test.
o="$(bash "$SCRIPT" --headings --body "$F7" 2>/dev/null)"; rc=$?
expect "#485: --headings needs no --template and exits 0" 0 "$rc"
grep -qxF "### Steps to reproduce" <<< "$o" && ok "#485: --headings prints a real heading" || bad "#485: --headings lost a real heading: $o"
grep -qxF "$Q" <<< "$o" && bad "#485: --headings printed a fenced heading" || ok "#485: --headings omits a fenced heading"
grep -qv '^##' <<< "$o" && bad "#485: --headings printed a non-heading line" || ok "#485: --headings prints heading lines only"
o="$(bash "$SCRIPT" --headings --roles --body "$F7" --template "$TPLDIR/bug.yml" 2>"$WORK/err")"; rc=$?
expect "#485: --headings with --roles exits 2" 2 "$rc"
expect "#485: ...with empty stdout" "" "$o"
o="$(bash "$SCRIPT" --headings --dump-fields --body "$F7" --template "$TPLDIR/bug.yml" 2>/dev/null)"; rc=$?
expect "#485: --headings with --dump-fields exits 2" 2 "$rc"
expect "#485: ...with empty stdout (dump-fields)" "" "$o"
o="$(bash "$SCRIPT" --headings 2>/dev/null)"; rc=$?
expect "#485: --headings without --body exits 2" 2 "$rc"
# Mutants: each guard the fix adds, applied to a scratch copy; each must flip a row above.
fmut() {  # fmut <name> <sed expr>: leaves the mutant at $MUT, or reports that it did not apply
  sed "$2" "$SCRIPT" > "$MUT"; if cmp -s "$SCRIPT" "$MUT"; then bad "#485: mutant $1 did not apply"; return 1; fi; return 0; }
frun() { bash "$MUT" --body "$1" --template "$TPLDIR/bug.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null; }
grep -qF '# section_of: a fence opens' "$SCRIPT" && ok "mutant ledger: section_of() opens fences (#485)" || bad "mutant ledger: #485 section_of fence rule not found"
if fmut M1 '/# section_of: a fence opens/d'; then
  expect "mutant M1: without fence tracking in section_of the backtick row fails gwt" fail "$(outcome "$(frun "$F1")" gwt)"
  expect "mutant M1: ...and the tilde row" fail "$(outcome "$(frun "$F2")" gwt)"
  expect "mutant M1: ...and the fenced-label Unit tests row" fail "$(outcome "$(frun "$U6")" unit_tests)"
fi
grep -qF '<<< "$BODY_HEADINGS"' "$SCRIPT" && ok "mutant ledger: check 3 reads the fence-aware heading list (#485)" || bad "mutant ledger: #485 presence scan not found"
if fmut M2 's/<<< "\$BODY_HEADINGS"/"$BODY"/'; then
  case "$(sec_ev "$(frun "$F7")")" in "heading absent"*) bad "mutant M2 survived: a raw presence scan still reports the fenced heading absent" ;;
    *) ok "mutant M2: a raw presence scan counts the fenced heading present" ;; esac
  expect "mutant M2: ...and the heading-level evidence counts the fenced ###" \
    "every template section present, every required one filled (headings at ## and ###)" "$(sec_ev "$(frun "$WORK/f485-l2.md")")"
fi
if fmut M3 's/^    fopen { if (fence_close(l)) fopen = 0; if (inside) print; next }/    fopen \&\& l !~ \/:start -->$\/ { if (fence_close(l)) fopen = 0; if (inside) print; next }/'; then
  expect "mutant M3: a region marker read inside a fence fails the fenced-marker row" fail "$(outcome "$(frun "$F10")" gwt)"
fi
if fmut M4 's/pat = "^`+\$"/pat = "^`+"/'; then
  # gwt cannot see M4: the true closer then REOPENS an unclosed fence, which swallows the real
  # section into the quote's content. The sections row sees every later heading hidden.
  expect "mutant M4: a closer that accepts trailing text fails the closer-with-bash row (sections)" fail "$(outcome "$(frun "$F9")" sections)"
fi
if fmut M5 '/backtick info string holds no backtick/d'; then
  expect "mutant M5: without the info-string rule the inline triple-backtick Guard fails" fail "$(outcome "$(frun "$G1")" gwt)"
fi
if fmut M6 's/rgn != "" { if (l == "<!-- " rgn ":end -->") rgn = ""; next }/rgn != "" { if (l == "<!-- " rgn ":end -->") rgn = ""; else if (fence_open(l)) fopen = 1; next }/'; then
  expect "mutant M6: fence state moved inside a region fails the region Guard" fail "$(outcome "$(frun "$G2")" gwt)"
fi
if fmut M7 's/match(s, \/^ \*\/); if (RLENGTH > 3) return 0; o = /match(s, \/^ *\/); o = /'; then
  expect "mutant M7: without the opener's indent limit the four-space Guard fails" fail "$(outcome "$(frun "$G3")" gwt)"
fi
# Round 1 of #485: four more guards, each with the row that kills it.
grep -qF 'else if (/^##+ /) print h; next }' "$SCRIPT" && ok "mutant ledger: body_headings() freezes fence state inside a region (#485)" || bad "mutant ledger: #485 body_headings region rule not found"
if fmut M9 's/else if (\/^##+ \/) print h; next }/else { if (\/^##+ \/) print h; if (fence_open(l)) fopen = 1 }; next }/'; then
  expect "mutant M9: a fence opened inside a region in body_headings fails the region Guard (sections)" fail "$(outcome "$(frun "$G2")" sections)"
fi
if fmut M10 's/match(s, \/^ \*\/); if (RLENGTH > 3) return 0; c = /match(s, \/^ *\/); c = /'; then
  expect "mutant M10: without the closer's indent limit the four-space closer row fails (sections)" fail "$(outcome "$(frun "$F12")" sections)"
fi
if fmut M11 's/^    fopen { if (fence_close(l)) fopen = 0; if (inside) print; next }/    fopen { if (fence_close(l)) fopen = 0; next }/'; then
  expect "mutant M11: a fence's content dropped from its section fails the fenced Unit tests row" fail "$(outcome "$(frun "$U7")" unit_tests)"
fi
if fmut M12 's/ \&\& \[ "\$DUMP_FIELDS" -eq 0 \]//'; then
  bash "$MUT" --headings --dump-fields --body "$F7" --template "$TPLDIR/bug.yml" >/dev/null 2>&1; rc=$?
  expect "mutant M12: without the --dump-fields exclusion --headings with --dump-fields exits 0" 0 "$rc"
fi

echo "check-ticket-mechanics: a CRLF body reads as its LF copy (#491)"
# Three sites carried the CR: section_of() built `cur` from the raw line, body_headings() printed
# it, and row() kept it in the evidence. Every row below compares a CRLF body with its LF copy run
# through the same script, so a difference anywhere in the seven rows is caught, evidence included.
r491() { bash "$1" --body "$2" --template "$TPLDIR/bug.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null; }
crlf491() { sed 's/$/\r/' "$1" > "$2"; printf '%s' "$2"; }
ev491() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1 == c { print $2 "|" $3 }'; }
L491="$(mkbody bug "i491-lf.md")"; C491="$(crlf491 "$L491" "$WORK/i491-crlf.md")"
[ "$(grep -c $'\r$' "$C491")" = "$(wc -l < "$C491" | tr -d ' ')" ] && [ "$(wc -l < "$C491" | tr -d ' ')" -gt 0 ] \
  && ok "#491: the CRLF fixture carries a CR on every line (fixture sanity)" || bad "#491: the CRLF fixture is not CRLF throughout"
LO491="$(r491 "$SCRIPT" "$L491")"; CO491="$(r491 "$SCRIPT" "$C491")"
for c in gwt unit_tests e2e_tests docs_impact; do
  expect "#491: site 1: $c passes on the CRLF body" pass "$(outcome "$CO491" "$c")"
done
SEC491='every template section present, every required one filled (headings at ###)'
expect "#491: site 2: sections passes on the CRLF body" "pass|$SEC491" "$(ev491 "$CO491" sections)"
expect "#491: parity: the CRLF body's seven rows equal its LF copy's, evidence included" "$LO491" "$CO491"
expect "#491: parity: ...and there are seven of them" 7 "$(printf '%s\n' "$CO491" | grep -c .)"
grep -q $'\r' <<< "$CO491" && bad "#491: site 3: a CR byte reached the rows" || ok "#491: site 3: no CR byte in any output row"
for c in unit_tests e2e_tests docs_impact; do
  expect "#491: site 3: $c evidence equals the LF run's" "$(ev491 "$LO491" "$c")" "$(ev491 "$CO491" "$c")"
done
H491="$(bash "$SCRIPT" --headings --body "$C491" 2>/dev/null)"
expect "#491: --headings on the CRLF body equals the LF body's" "$(bash "$SCRIPT" --headings --body "$L491" 2>/dev/null)" "$H491"
grep -q $'\r' <<< "$H491" && bad "#491: CR leaked into --headings output" || ok "#491: no CR byte in --headings output"
# Portability: the same parity under mawk and busybox awk, each through a PATH shim.
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$WORK/mawk491"; printf '#!/bin/sh\nexec mawk "$@"\n' > "$WORK/mawk491/awk"; chmod +x "$WORK/mawk491/awk"
  expect "#491: portability: the CRLF body's rows equal the LF rows under mawk" "$LO491" "$(PATH="$WORK/mawk491:$PATH" r491 "$SCRIPT" "$C491")"
else
  ok "#491: portability: mawk not on PATH, CRLF parity under mawk skipped"
fi
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$WORK/bb491"; printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$WORK/bb491/awk"; chmod +x "$WORK/bb491/awk"
  expect "#491: portability: the CRLF body's rows equal the LF rows under busybox awk" "$LO491" "$(PATH="$WORK/bb491:$PATH" r491 "$SCRIPT" "$C491")"
else
  ok "#491: portability: busybox awk not on PATH, CRLF parity under busybox awk skipped"
fi
# A CR inside a fenced block: the closer still closes, and a quoted label stays a quote.
FG491="$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\n```\n### Unit tests\n- Then: example\n```\n\nNegative\n- Given: d\n- When: e\n- Then: 401 with AUTH_FAILED')"
CF491="$(crlf491 "$(mkbody bug "i491-fence-lf.md" "$FG491")" "$WORK/i491-fence.md")"
grep -q $'^```\r$' "$CF491" && ok "#491: the fenced CRLF fixture's fence carries a CR (fixture sanity)" || bad "#491: the fenced CRLF fixture has no CR on its fence"
o="$(r491 "$SCRIPT" "$CF491")"
expect "#491: a CRLF fenced block in the scenarios field leaves gwt passing" pass "$(outcome "$o" gwt)"
expect "#491: ...and sections passing" "pass|$SEC491" "$(ev491 "$o" sections)"
# Mixed endings: only the Unit tests heading and its content line carry a CR.
sed -e '/^### Unit tests$/ s/$/\r/' -e '/tests\/unit\/auth\.test\.ts/ s/$/\r/' "$L491" > "$WORK/i491-mixed.md"
expect "#491: the mixed fixture carries exactly two CR lines (fixture sanity)" 2 "$(grep -c $'\r$' "$WORK/i491-mixed.md")"
expect "#491: a mixed LF and CRLF body gives the LF rows" "$LO491" "$(r491 "$SCRIPT" "$WORK/i491-mixed.md")"
# No final newline: the body ends in `Updates ...\r` (the gate-owned Codebase Context dropped).
sed -n '1,/^Updates /p' "$L491" > "$WORK/i491-nonl-lf.md"
printf '%s' "$(sed 's/$/\r/' "$WORK/i491-nonl-lf.md")" > "$WORK/i491-nonl.md"
[ "$(tail -c 2 "$WORK/i491-nonl.md" | od -An -c | tr -d ' ')" = '`\r' ] && ok "#491: the no-final-newline fixture ends in a CR with no LF (fixture sanity)" || bad "#491: the no-final-newline fixture ends otherwise"
o="$(r491 "$SCRIPT" "$WORK/i491-nonl.md")"
expect "#491: a CRLF body with no final newline passes docs_impact" pass "$(outcome "$o" docs_impact)"
expect "#491: ...and gives the rows of its LF copy" "$(r491 "$SCRIPT" "$WORK/i491-nonl-lf.md")" "$o"
# Negatives: the strip must not turn an absent heading or an empty section into a pass.
awk '/^### Security impact$/ { skip = 1; next } skip && /^### / { skip = 0 } !skip' "$L491" > "$WORK/i491-nosec-lf.md"
grep -q '^### Security impact' "$WORK/i491-nosec-lf.md" && bad "#491: the Security impact deletion did not apply" || ok "#491: the Security impact deletion applied (fixture sanity)"
o="$(r491 "$SCRIPT" "$(crlf491 "$WORK/i491-nosec-lf.md" "$WORK/i491-nosec.md")")"
expect "#491: a CRLF body without Security impact still fails sections, naming it" "fail|heading absent (1): Security impact" "$(ev491 "$o" sections)"
grep -v 'tests/unit/auth\.test\.ts' "$L491" > "$WORK/i491-nounit-lf.md"
o="$(r491 "$SCRIPT" "$(crlf491 "$WORK/i491-nounit-lf.md" "$WORK/i491-nounit.md")")"
expect "#491: a CRLF Unit tests section of bare CR lines still fails unit_tests" "fail|no content in Unit tests" "$(ev491 "$o" unit_tests)"
expect "#491: ...and sections names it empty" "fail|required heading present but empty (1): Unit tests" "$(ev491 "$o" sections)"
# Round 1: a bare `### ` heading line still ends the section above it. With the level read from the
# blank-stripped line it had no space, so the empty heading and the text under it became Unit tests
# content and the emptied required section passed `sections` (LF and CRLF alike).
awk '{ print } /^### Unit tests$/ { print "### "; print "stray text" }' "$WORK/i491-nounit-lf.md" > "$WORK/i491-bare-lf.md"
grep -qx '### ' "$WORK/i491-bare-lf.md" && ok "#491: the bare-heading fixture carries a '### ' line (fixture sanity)" || bad "#491: the bare-heading fixture lacks its '### ' line"
o="$(r491 "$SCRIPT" "$WORK/i491-bare-lf.md")"
expect "#491: an LF bare '### ' heading after an emptied Unit tests leaves it empty" "fail|required heading present but empty (1): Unit tests" "$(ev491 "$o" sections)"
expect "#491: ...and its CRLF copy gives the same rows" "$o" "$(r491 "$SCRIPT" "$(crlf491 "$WORK/i491-bare-lf.md" "$WORK/i491-bare.md")")"
awk '/^### Test scenarios / { skip = 1; next } skip && /^### / { skip = 0 } !skip' "$L491" > "$WORK/i491-noscen-lf.md"
o="$(r491 "$SCRIPT" "$(crlf491 "$WORK/i491-noscen-lf.md" "$WORK/i491-noscen.md")")"
expect "#491: a CRLF body without Test scenarios fails gwt, naming the label" "fail|no content in Test scenarios (Given / When / Then)" "$(ev491 "$o" gwt)"
expect "#491: ...and every row equals the LF run of the same body" "$(r491 "$SCRIPT" "$WORK/i491-noscen-lf.md")" "$o"
# LF unchanged: site 2 strips only the CR, so a heading with trailing blanks is still absent.
sed 's/^### Unit tests$/### Unit tests  /' "$L491" > "$WORK/i491-blank.md"
grep -qx '### Unit tests  ' "$WORK/i491-blank.md" && ok "#491: the trailing-blank fixture applied (fixture sanity)" || bad "#491: the trailing-blank fixture did not apply"
expect "#491: an LF heading with trailing blanks still fails sections as before" "fail|heading absent (1): Unit tests" "$(ev491 "$(r491 "$SCRIPT" "$WORK/i491-blank.md")" sections)"
grep -qxF '### Unit tests  ' <<< "$(bash "$SCRIPT" --headings --body "$WORK/i491-blank.md" 2>/dev/null)" \
  && ok "#491: LF --headings keeps a heading's trailing blanks byte for byte" || bad "#491: LF --headings lost a heading's trailing blanks"
# Mutants, one per site, each with its ledger row and an applied-check (cmp -s plus grep -qF).
X1_491='cur = substr(l, lvl + 2)'
grep -qF "$X1_491" "$SCRIPT" && ok "mutant ledger: section_of() takes cur from the CR-free line (#491)" || bad "mutant ledger: #491 section_of cur not found"
sed 's/cur = substr(l, lvl + 2)/cur = substr($0, lvl + 2)/' "$SCRIPT" > "$MUT"   # site 1: cur alone reverted
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$X1_491" "$MUT"; then bad "#491: the site 1 mutant did not apply"; else
  o="$(r491 "$MUT" "$C491")"
  case "$(ev491 "$o" sections)" in "fail|required heading present but empty (13): "*) ok "mutant site 1: sections fails required heading present but empty (13)" ;;
    *) bad "mutant site 1: sections gave '$(ev491 "$o" sections)'" ;; esac
  expect "mutant site 1: gwt fails no content" "fail|no content in Test scenarios (Given / When / Then)" "$(ev491 "$o" gwt)"
  expect "mutant site 1: unit_tests fails no content" "fail|no content in Unit tests" "$(ev491 "$o" unit_tests)"
  expect "mutant site 1: e2e_tests fails no content" "fail|no content in E2E tests" "$(ev491 "$o" e2e_tests)"
  expect "mutant site 1: docs_impact fails no content" "fail|no content in Documentation impact" "$(ev491 "$o" docs_impact)"
fi
# Round 1: the level read from the blank-stripped line loses a bare `### ` heading (the bare-heading row can fail).
XL491='lvl = index($0, " ") - 1; cur = substr(l, lvl + 2)'
grep -qF "$XL491" "$SCRIPT" && ok "mutant ledger: section_of() reads the heading level from \$0 (#491)" || bad "mutant ledger: #491 section_of level from \$0 not found"
sed 's/lvl = index(\$0, " ") - 1; cur = substr(l, lvl + 2)/lvl = index(l, " ") - 1; cur = substr(l, lvl + 2)/' "$SCRIPT" > "$MUT"
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$XL491" "$MUT"; then bad "#491: the level mutant did not apply"; else
  expect "mutant: a level read from the cleaned line passes the emptied Unit tests under a bare heading" pass "$(outcome "$(r491 "$MUT" "$WORK/i491-bare-lf.md")" sections)"
fi
bh491() { sed -n '/^body_headings() {/,/^}/p' "$1"; }
[ "$(grep -cF 'print h' <<< "$(bh491 "$SCRIPT")")" = 2 ] && ok "mutant ledger: body_headings() prints the CR-free line on both paths (#491)" || bad "mutant ledger: #491 body_headings print h not found twice"
sed '/^body_headings() {/,/^}/ s/print h/print/g' "$SCRIPT" > "$MUT"   # site 2: both prints raw again
if cmp -s "$SCRIPT" "$MUT" || grep -qF 'print h' <<< "$(bh491 "$MUT")"; then bad "#491: the site 2 mutant did not apply"; else
  o="$(r491 "$MUT" "$C491")"
  case "$(ev491 "$o" sections)" in "fail|heading absent (15): "*) ok "mutant site 2: sections fails heading absent (15)" ;;
    *) bad "mutant site 2: sections gave '$(ev491 "$o" sections)'" ;; esac
  for c in gwt unit_tests e2e_tests docs_impact; do
    expect "mutant site 2: $c stays pass" pass "$(outcome "$o" "$c")"
  done
  grep -q $'\r' <<< "$(bash "$MUT" --headings --body "$C491" 2>/dev/null)" && ok "mutant site 2: --headings on the CRLF body carries a CR" || bad "mutant site 2: --headings carries no CR"
fi
X3_491="tr -d '\\r' | tr '\\n\\t' '  '"
grep -qF "$X3_491" "$SCRIPT" && ok "mutant ledger: row() deletes CR from the evidence (#491)" || bad "mutant ledger: #491 row() CR strip not found"
sed "s/ | tr -d '\\\\r' | tr '\\\\n\\\\t' '  '/ | tr '\\\\n\\\\t' '  '/" "$SCRIPT" > "$MUT"   # site 3
if cmp -s "$SCRIPT" "$MUT" || grep -qF "$X3_491" "$MUT"; then bad "#491: the site 3 mutant did not apply"; else
  o="$(r491 "$MUT" "$C491")"
  expect "mutant site 3: all seven outcomes equal the LF run" "$(printf '%s\n' "$LO491" | cut -f1,2)" "$(printf '%s\n' "$o" | cut -f1,2)"
  for c in unit_tests e2e_tests docs_impact; do
    grep -q $'\r$' <<< "$(printf '%s\n' "$o" | awk -F'\t' -v c="$c" '$1 == c')" && ok "mutant site 3: $c evidence ends in a CR" || bad "mutant site 3: $c evidence has no CR"
  done
  expect "mutant site 3: the site 2 row still passes" "pass|$SEC491" "$(ev491 "$o" sections)"
  for c in gwt unit_tests e2e_tests docs_impact; do
    expect "mutant site 3: the site 1 row for $c still passes" pass "$(outcome "$o" "$c")"
  done
fi

echo "check-ticket-mechanics: a CRLF template reads as its LF copy (#493)"
# A template checked out with core.autocrlf=true has a CR on every line. template_fields() kept it on
# each label and template_subheadings() on its label and heading text, so every section read as
# absent. Every row below compares the CRLF template copy with the LF template on the same body.
r493() { bash "$1" --body "$2" --template "$3" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null; }
crlft493() { sed 's/$/\r/' "$TPLDIR/$1.yml" > "$WORK/crlf493-$1.yml"; printf '%s' "$WORK/crlf493-$1.yml"; }
ev493() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1 == c { print $2 "|" $3 }'; }
for tpl in feature bug security infrastructure design; do
  CT493="$(crlft493 "$tpl")"
  [ "$(grep -c $'\r$' "$CT493")" = "$(wc -l < "$CT493" | tr -d ' ')" ] \
    && ok "#493: $tpl: the CRLF template copy carries a CR on every line (fixture sanity)" || bad "#493: $tpl: the CRLF template copy is not CRLF throughout"
  B493="$(mkbody "$tpl" "i493-$tpl.md")"
  LO="$(r493 "$SCRIPT" "$B493" "$TPLDIR/$tpl.yml")"; CO="$(r493 "$SCRIPT" "$B493" "$CT493")"
  [ -n "$LO" ] && ok "#493: $tpl: the LF run produced rows (an empty comparison passes vacuously)" || bad "#493: $tpl: the LF run produced no rows"
  expect "#493: $tpl: the CRLF template's rows equal the LF template's, evidence included" "$LO" "$CO"
  expect "#493: $tpl: sections passes against the CRLF template" pass "$(outcome "$CO" sections)"
  DL="$(bash "$SCRIPT" --dump-fields --body "$B493" --template "$TPLDIR/$tpl.yml" 2>/dev/null)"
  DC="$(bash "$SCRIPT" --dump-fields --body "$B493" --template "$CT493" 2>/dev/null)"
  [ -n "$DL" ] && expect "#493: $tpl: --dump-fields on the CRLF template equals the LF output" "$DL" "$DC" || bad "#493: $tpl: --dump-fields printed nothing"
  grep -q $'\r' <<< "$DC" && bad "#493: $tpl: a CR byte reached --dump-fields" || ok "#493: $tpl: no CR byte in --dump-fields output"
done
# LF unchanged: the compliant bug body against the LF template is seven passes, as before the fix.
B493="$(mkbody bug "i493-bug.md")"; LB493="$(r493 "$SCRIPT" "$B493" "$TPLDIR/bug.yml")"
expect "#493: the LF bug template still gives seven rows" 7 "$(printf '%s\n' "$LB493" | grep -c .)"
expect "#493: ...and every one passes" 7 "$(printf '%s\n' "$LB493" | awk -F'\t' '$2 == "pass" { n++ } END { print n+0 }')"
# Negative: a heading genuinely missing from the body is still absent, and is the only one named.
grep -vx '### Unit tests' "$B493" > "$WORK/i493-nounit.md"
grep -qx '### Unit tests' "$WORK/i493-nounit.md" && bad "#493: the Unit tests heading deletion did not apply" || ok "#493: the Unit tests heading deletion applied (fixture sanity)"
o="$(r493 "$SCRIPT" "$WORK/i493-nounit.md" "$WORK/crlf493-bug.yml")"
expect "#493: a CRLF bug template with ### Unit tests missing fails sections, naming it alone" "fail|heading absent (1): Unit tests" "$(ev493 "$o" sections)"
expect "#493: ...and every row equals the LF template run" "$(r493 "$SCRIPT" "$WORK/i493-nounit.md" "$TPLDIR/bug.yml")" "$o"
# template_subheadings(): feature.yml's E2E placeholder lists `### Happy path` and `### Unhappy path`,
# which a ###-rendered body puts at the section's own level, so they must stay inside it.
GWT493="$(printf 'Positive\n- Given: a\n- When: b\n- Then: c\n\nNegative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED')"
UNIT493='- [ ] `tests/unit/auth.test.ts` valid input'
S493="$(mkbody feature "i493-sub.md" "$GWT493" "$UNIT493" "$(printf '### Happy path\n- [ ] `tests/e2e/login.spec.ts` user sees the screen\n\n### Unhappy path\n- [ ] API returns 500 -> retry button')")"
grep -qx '### Happy path' "$S493" && ok "#493: the sub-heading fixture carries ### Happy path (fixture sanity)" || bad "#493: the sub-heading fixture lacks ### Happy path"
CF493="$(crlft493 feature)"
SL493="$(r493 "$SCRIPT" "$S493" "$TPLDIR/feature.yml")"; SC493="$(r493 "$SCRIPT" "$S493" "$CF493")"
expect "#493: a CRLF feature template keeps its listed sub-headings inside E2E: sections passes" pass "$(outcome "$SC493" sections)"
expect "#493: ...and e2e_tests passes on the Happy path content" "pass|### Happy path" "$(ev493 "$SC493" e2e_tests)"
expect "#493: ...and every row equals the LF template run" "$SL493" "$SC493"
# Negative: a sub-heading the template does not list still ends the section.
U493="$(mkbody feature "i493-unl.md" "$GWT493" "$UNIT493" "$(printf '### Unlisted heading\n- [ ] `tests/e2e/login.spec.ts` user sees the screen')")"
grep -qx '### Unlisted heading' "$U493" && ok "#493: the unlisted-heading fixture applied (fixture sanity)" || bad "#493: the unlisted-heading fixture did not apply"
o="$(r493 "$SCRIPT" "$U493" "$CF493")"
expect "#493: an unlisted sub-heading still empties E2E against the CRLF template" "fail|required heading present but empty (1): E2E test scenarios" "$(ev493 "$o" sections)"
expect "#493: ...and e2e_tests fails no content" "fail|no content in E2E test scenarios" "$(ev493 "$o" e2e_tests)"
expect "#493: ...and every row equals the LF template run" "$(r493 "$SCRIPT" "$U493" "$TPLDIR/feature.yml")" "$o"
# Only a TRAILING CR is stripped: a CR inside a label or a template sub-heading is kept, so a
# strip-every-CR rewrite (gsub) at any of the three sites changes a row below.
printf 'body:\n  - type: textarea\n    id: mid\n    attributes:\n      label: Mid\rCR label\n      placeholder: |\n        ### Happy\rpath\n    validations:\n      required: true\n' > "$WORK/mid493.yml"
sed 's/$/\r/' "$WORK/mid493.yml" > "$WORK/mid493-crlf.yml"
printf '<!-- template-version: 6 -->\n\n### Mid\rCR label\n\n### Happy\rpath\n\n- filled under the sub-heading\n' > "$WORK/mid493.md"
MO493="$(r493 "$SCRIPT" "$WORK/mid493.md" "$WORK/mid493.yml")"
expect "#493: a label with an interior CR is printed with it by --dump-fields" "$(printf 'Mid\rCR label\tyes')" "$(bash "$SCRIPT" --dump-fields --body "$WORK/mid493.md" --template "$WORK/mid493.yml" 2>/dev/null)"
expect "#493: ...and by --dump-fields on its CRLF copy" "$(printf 'Mid\rCR label\tyes')" "$(bash "$SCRIPT" --dump-fields --body "$WORK/mid493.md" --template "$WORK/mid493-crlf.yml" 2>/dev/null)"
expect "#493: an interior-CR label and sub-heading keep the section filled: sections passes" pass "$(outcome "$MO493" sections)"
expect "#493: ...and the CRLF copy gives the same rows" "$MO493" "$(r493 "$SCRIPT" "$WORK/mid493.md" "$WORK/mid493-crlf.yml")"
# Portability: the CRLF template parity under mawk and busybox awk, each through a PATH shim.
port493() {  # port493 <shim dir> <awk name>
  local tpl
  for tpl in feature bug security infrastructure design; do
    expect "#493: portability: $tpl: the CRLF template's rows equal the LF rows under $2" \
      "$(r493 "$SCRIPT" "$WORK/i493-$tpl.md" "$TPLDIR/$tpl.yml")" "$(PATH="$1:$PATH" r493 "$SCRIPT" "$WORK/i493-$tpl.md" "$WORK/crlf493-$tpl.yml")"
  done
  expect "#493: portability: the CRLF sub-heading case equals the LF rows under $2" "$SL493" "$(PATH="$1:$PATH" r493 "$SCRIPT" "$S493" "$CF493")"
  expect "#493: portability: the CRLF unlisted-heading case equals the LF rows under $2" "$(r493 "$SCRIPT" "$U493" "$TPLDIR/feature.yml")" "$(PATH="$1:$PATH" r493 "$SCRIPT" "$U493" "$CF493")"
  expect "#493: portability: the interior-CR case equals the default awk's rows under $2" "$MO493" "$(PATH="$1:$PATH" r493 "$SCRIPT" "$WORK/mid493.md" "$WORK/mid493-crlf.yml")"
}
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$WORK/mawk493"; printf '#!/bin/sh\nexec mawk "$@"\n' > "$WORK/mawk493/awk"; chmod +x "$WORK/mawk493/awk"
  port493 "$WORK/mawk493" mawk
else
  ok "#493: portability: mawk not on PATH, CRLF template parity under mawk skipped"
fi
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$WORK/bb493"; printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$WORK/bb493/awk"; chmod +x "$WORK/bb493/awk"
  port493 "$WORK/bb493" "busybox awk"
else
  ok "#493: portability: busybox awk not on PATH, CRLF template parity under busybox awk skipped"
fi
# Mutants, one per strip, each with its ledger row and an applied-check (cmp -s plus grep -qF on the
# function's own lines), and one strip-every-CR mutant per site for the interior-CR rows.
M493="$WORK/mut493.sh"
fn493() { sed -n "/^$1() {/,/^}/p" "$2"; }
X493='sub(/\r$/, "", l); '
XH493='sub(/\r$/, "", h); '
grep -qF "$X493" <<< "$(fn493 template_fields "$SCRIPT")" && ok "mutant ledger: template_fields() strips a label's trailing CR (#493)" || bad "mutant ledger: #493 template_fields label strip not found"
grep -qF "$X493" <<< "$(fn493 template_subheadings "$SCRIPT")" && ok "mutant ledger: template_subheadings() strips its label's trailing CR (#493)" || bad "mutant ledger: #493 template_subheadings label strip not found"
grep -qF "$XH493" <<< "$(fn493 template_subheadings "$SCRIPT")" && ok "mutant ledger: template_subheadings() strips its heading text's trailing CR (#493)" || bad "mutant ledger: #493 template_subheadings heading strip not found"
mut493() {  # mut493 <function> <sed substitution> <the string the mutant must remove>
  sed "/^$1() {/,/^}/ $2" "$SCRIPT" > "$M493"
  if cmp -s "$SCRIPT" "$M493" || grep -qF "$3" <<< "$(fn493 "$1" "$M493")"; then bad "#493: the mutant '$1 $2' did not apply"; return 1; fi; return 0; }
if mut493 template_fields 's/sub(\/\\r\$\/, "", l); //' "$X493"; then
  case "$(ev493 "$(r493 "$M493" "$B493" "$WORK/crlf493-bug.yml")" sections)" in "fail|heading absent (15): "*) ok "mutant: the template_fields label strip removed fails the CRLF bug sections row heading absent (15)" ;;
    *) bad "mutant: the template_fields label strip removed gave sections '$(ev493 "$(r493 "$M493" "$B493" "$WORK/crlf493-bug.yml")" sections)'" ;; esac
  grep -q $'\r' <<< "$(bash "$M493" --dump-fields --body "$B493" --template "$WORK/crlf493-bug.yml" 2>/dev/null)" && ok "mutant: ...and --dump-fields carries a CR again" || bad "mutant: ...--dump-fields carries no CR"
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", l); //' "$X493"; then
  o="$(r493 "$M493" "$S493" "$CF493")"
  expect "mutant: the template_subheadings label strip removed empties E2E on the CRLF sub-heading case" "fail|required heading present but empty (1): E2E test scenarios" "$(ev493 "$o" sections)"
  expect "mutant: ...and e2e_tests fails no content" "fail|no content in E2E test scenarios" "$(ev493 "$o" e2e_tests)"
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", h); //' "$XH493"; then
  o="$(r493 "$M493" "$S493" "$CF493")"
  expect "mutant: the template_subheadings heading strip removed empties E2E on the CRLF sub-heading case" "fail|required heading present but empty (1): E2E test scenarios" "$(ev493 "$o" sections)"
  expect "mutant: ...and e2e_tests fails no content" "fail|no content in E2E test scenarios" "$(ev493 "$o" e2e_tests)"
fi
if mut493 template_fields 's/sub(\/\\r\$\/, "", l); /gsub(\/\\r\/, "", l); /' "$X493"; then
  expect "mutant: a strip-every-CR template_fields loses the interior CR from --dump-fields" "$(printf 'MidCR label\tyes')" "$(bash "$M493" --dump-fields --body "$WORK/mid493.md" --template "$WORK/mid493.yml" 2>/dev/null)"
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", l); /gsub(\/\\r\/, "", l); /' "$X493"; then
  expect "mutant: a strip-every-CR subheadings label empties the interior-CR section" fail "$(outcome "$(r493 "$M493" "$WORK/mid493.md" "$WORK/mid493.yml")" sections)"
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", h); /gsub(\/\\r\/, "", h); /' "$XH493"; then
  expect "mutant: a strip-every-CR subheadings heading empties the interior-CR section" fail "$(outcome "$(r493 "$M493" "$WORK/mid493.md" "$WORK/mid493.yml")" sections)"
fi
# Order: each site strips the CR BEFORE the blanks. A line `      label: Unit tests  \r` stripped the
# other way round keeps `Unit tests  `, because the blank strip sees the CR at the end and does
# nothing. This copy puts two blanks before the CR on every label line and every placeholder
# heading line, so each order swap below changes a row.
sed -E 's/^(      label: .*|        #+ .*)$/\1  /; s/$/\r/' "$TPLDIR/feature.yml" > "$WORK/blank493-feature.yml"
expect "#493: the blank-then-CR copy carries two blanks before the CR on every label and heading line (fixture sanity)" \
  "$(grep -cE '^      label: |^        #+ ' "$TPLDIR/feature.yml")" "$(grep -cE '^(      label: |        #+ ).*[^ ]  '$'\r''$' "$WORK/blank493-feature.yml")"
BF493="$(mkbody feature "i493-blank.md")"
expect "#493: a blank-then-CR template gives the LF template's rows on the compliant feature body" \
  "$(r493 "$SCRIPT" "$BF493" "$TPLDIR/feature.yml")" "$(r493 "$SCRIPT" "$BF493" "$WORK/blank493-feature.yml")"
expect "#493: ...and the LF rows on the sub-heading case" "$SL493" "$(r493 "$SCRIPT" "$S493" "$WORK/blank493-feature.yml")"
expect "#493: ...and the LF --dump-fields output" "$(bash "$SCRIPT" --dump-fields --body "$BF493" --template "$TPLDIR/feature.yml" 2>/dev/null)" \
  "$(bash "$SCRIPT" --dump-fields --body "$BF493" --template "$WORK/blank493-feature.yml" 2>/dev/null)"
XO493='sub(/[ \t]+$/, "", l); '
XOH493='sub(/[ \t]+$/, "", h); '
grep -qF "$X493$XO493" <<< "$(fn493 template_fields "$SCRIPT")" && ok "mutant ledger: template_fields() strips the label's CR before its blanks (#493)" || bad "mutant ledger: #493 template_fields CR-then-blank order not found"
grep -qF "$X493$XO493" <<< "$(fn493 template_subheadings "$SCRIPT")" && ok "mutant ledger: template_subheadings() strips its label's CR before its blanks (#493)" || bad "mutant ledger: #493 template_subheadings label CR-then-blank order not found"
grep -qF "$XH493$XOH493" <<< "$(fn493 template_subheadings "$SCRIPT")" && ok "mutant ledger: template_subheadings() strips its heading text's CR before its blanks (#493)" || bad "mutant ledger: #493 template_subheadings heading CR-then-blank order not found"
if mut493 template_fields 's/sub(\/\\r\$\/, "", l); sub(\/\[ \\t\]+\$\/, "", l); /sub(\/[ \\t]+$\/, "", l); sub(\/\\r$\/, "", l); /' "$X493$XO493"; then
  case "$(ev493 "$(r493 "$M493" "$BF493" "$WORK/blank493-feature.yml")" sections)" in "fail|heading absent ("*) ok "mutant: template_fields stripping blanks before the CR fails the blank-then-CR feature sections row heading absent" ;;
    *) bad "mutant: template_fields stripping blanks before the CR gave sections '$(ev493 "$(r493 "$M493" "$BF493" "$WORK/blank493-feature.yml")" sections)'" ;; esac
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", l); sub(\/\[ \\t\]+\$\/, "", l); /sub(\/[ \\t]+$\/, "", l); sub(\/\\r$\/, "", l); /' "$X493$XO493"; then
  o="$(r493 "$M493" "$S493" "$WORK/blank493-feature.yml")"
  expect "mutant: subheadings stripping its label's blanks before the CR empties E2E on the blank-then-CR template" "fail|required heading present but empty (1): E2E test scenarios" "$(ev493 "$o" sections)"
fi
if mut493 template_subheadings 's/sub(\/\\r\$\/, "", h); sub(\/\[ \\t\]+\$\/, "", h); /sub(\/[ \\t]+$\/, "", h); sub(\/\\r$\/, "", h); /' "$XH493$XOH493"; then
  o="$(r493 "$M493" "$S493" "$WORK/blank493-feature.yml")"
  expect "mutant: subheadings stripping its heading's blanks before the CR empties E2E on the blank-then-CR template" "fail|required heading present but empty (1): E2E test scenarios" "$(ev493 "$o" sections)"
fi

echo "check-ticket-mechanics: a quoted template label is compared by its YAML value (#492)"
# YAML requires quotes on a label holding `: `, and the parser kept them, so the section read as
# `heading absent` on every body. Every template and every expected label below is written by
# hand: gen.py and ph.py keep the quotes, so as oracles they would agree with the bug.
r492() { bash "$1" --body "$2" --template "$3" --tpl-version 9 --current-tpl-version 9 --labels bug 2>/dev/null; }
d492() { bash "$1" --dump-fields --body "$2" --template "$3" 2>/dev/null; }
sec492() { printf '%s\n' "$1" | awk -F'\t' '$1 == "sections" { print $2 "|" $3 }'; }
cat > "$WORK/dq492.yml" <<'YML'
body:
  - type: textarea
    id: summary
    attributes:
      label: Summary
    validations:
      required: true
  - type: textarea
    id: dod
    attributes:
      label: "Definition of Done: MANDATORY (dod-version 9)"
    validations:
      required: true
YML
printf '<!-- template-version: 9 -->\n\n## Summary\n\nsomething\n\n## Definition of Done: MANDATORY (dod-version 9)\n\n- [ ] the change is reviewed\n' > "$WORK/dq492-ok.md"
printf '<!-- template-version: 9 -->\n\n## Summary\n\nsomething\n' > "$WORK/dq492-absent.md"
printf '<!-- template-version: 9 -->\n\n## Summary\n\nsomething\n\n## "Definition of Done: MANDATORY (dod-version 9)"\n\n- [ ] the change is reviewed\n' > "$WORK/dq492-lit.md"
cat > "$WORK/sq492.yml" <<'YML'
body:
  - type: textarea
    id: news
    attributes:
      label: 'What''s new'
YML
printf "<!-- template-version: 9 -->\n\n## What's new\n\nthe release notes\n" > "$WORK/sq492.md"
cat > "$WORK/esc492.yml" <<'YML'
body:
  - type: textarea
    id: greet
    attributes:
      label: "Say \"hi\" to C:\\dir"
    validations:
      required: true
YML
printf '<!-- template-version: 9 -->\n\n## Say "hi" to C:\\dir\n\nthe greeting\n' > "$WORK/esc492.md"
cat > "$WORK/cm492.yml" <<'YML'
body:
  - type: textarea
    id: steps
    attributes:
      label: "Steps to reproduce" # keep
    validations:
      required: true
YML
printf '<!-- template-version: 9 -->\n\n## Steps to reproduce\n\n1. run it\n' > "$WORK/cm492.md"
cat > "$WORK/sub492.yml" <<'YML'
body:
  - type: textarea
    id: rollout
    attributes:
      label: "Rollout: plan"
      value: |
        ### Sub
        - [ ] fill me
    validations:
      required: true
YML
printf '<!-- template-version: 9 -->\n\n### Rollout: plan\n\n### Sub\n\n- filled under the sub-heading\n' > "$WORK/sub492.md"
cat > "$WORK/br492.yml" <<'YML'
body:
  - type: textarea
    id: broken
    attributes:
      label: "Broken
YML
printf '<!-- template-version: 9 -->\n\n## Broken\n\nsomething\n' > "$WORK/br492.md"
cat > "$WORK/pc492.yml" <<'YML'
body:
  - type: textarea
    id: path
    attributes:
      label: "Path C:\\"
YML
printf '<!-- template-version: 9 -->\n\n## Path C:\\\n\nthe path\n' > "$WORK/pc492.md"
cat > "$WORK/rl492.yml" <<'YML'
body:
  - type: textarea
    id: unit_tests
    attributes:
      label: "Unit tests: per module"
    validations:
      required: true
YML
# Blanks inside the quotes: the dump is exactly `Foo`, so a `## Foo` body finds its section.
cat > "$WORK/tb492.yml" <<'YML'
body:
  - type: textarea
    id: foo
    attributes:
      label: "Foo  "
    validations:
      required: true
YML
printf '<!-- template-version: 9 -->\n\n## Foo\n\nthe foo text\n' > "$WORK/tb492.md"
# A required field whose quoted label is empty. Unquoted to nothing, template_fields() would skip
# the field and its section would never be checked, so the value is kept as read and fails closed.
cat > "$WORK/em492.yml" <<'YML'
body:
  - type: textarea
    id: summary
    attributes:
      label: Summary
    validations:
      required: true
  - type: textarea
    id: empty
    attributes:
      label: ""
    validations:
      required: true
YML
sed "s/label: \"\"/label: ''/" "$WORK/em492.yml" > "$WORK/em492-sq.yml"
sed 's/label: ""/label: " "/' "$WORK/em492.yml" > "$WORK/em492-sp.yml"
printf '<!-- template-version: 9 -->\n\n## Summary\n\nsomething\n' > "$WORK/em492.md"
sed 's/$/\r/' "$WORK/dq492.yml" > "$WORK/dq492-crlf.yml"
# Fixture sanity: each template carries its quotes as written, so no row below passes vacuously.
grep -qxF '      label: "Definition of Done: MANDATORY (dod-version 9)"' "$WORK/dq492.yml" && grep -qxF "      label: 'What''s new'" "$WORK/sq492.yml" \
  && grep -qxF '      label: "Say \"hi\" to C:\\dir"' "$WORK/esc492.yml" && grep -qxF '      label: "Path C:\\"' "$WORK/pc492.yml" \
  && grep -qxF '## Path C:\' "$WORK/pc492.md" && grep -qxF '## Say "hi" to C:\dir' "$WORK/esc492.md" \
  && grep -qxF '      label: "Foo  "' "$WORK/tb492.yml" && grep -qxF '      label: ""' "$WORK/em492.yml" \
  && grep -qxF "      label: ''" "$WORK/em492-sq.yml" && grep -qxF '      label: " "' "$WORK/em492-sp.yml" \
  && ok "#492: the hand-written templates and bodies carry their quotes and backslashes as written (fixture sanity)" || bad "#492: a hand-written fixture is not what it claims"
# The quoted cases, run once under the default awk and again through each portability shim.
cases492() {  # cases492 <awk name>
  local o
  o="$(r492 "$SCRIPT" "$WORK/dq492-ok.md" "$WORK/dq492.yml")"
  expect "#492 ($1): a double-quoted label compares by value: sections passes" pass "$(outcome "$o" sections)"
  case "$(sec492 "$o")" in *"heading absent"*) bad "#492 ($1): ...the evidence still names an absent heading" ;; *) ok "#492 ($1): ...and its evidence names no absent heading" ;; esac
  expect "#492 ($1): a single-quoted label decodes its doubled quote in --dump-fields" "$(printf "What's new\tno")" "$(d492 "$SCRIPT" "$WORK/sq492.md" "$WORK/sq492.yml")"
  expect "#492 ($1): an escaped quote and an escaped backslash decode in one pass" 'Say "hi" to C:\dir' "$(d492 "$SCRIPT" "$WORK/esc492.md" "$WORK/esc492.yml" | cut -f1)"
  expect "#492 ($1): ...and that body passes sections" pass "$(outcome "$(r492 "$SCRIPT" "$WORK/esc492.md" "$WORK/esc492.yml")" sections)"
  expect "#492 ($1): a trailing comment after the closing quote is ignored: sections passes" pass "$(outcome "$(r492 "$SCRIPT" "$WORK/cm492.md" "$WORK/cm492.yml")" sections)"
  expect "#492 ($1): a quoted field's sub-heading still sits inside its section: sections passes" pass "$(outcome "$(r492 "$SCRIPT" "$WORK/sub492.md" "$WORK/sub492.yml")" sections)"
  expect "#492 ($1): the section absent fails, naming the label without quotes" "fail|heading absent (1): Definition of Done: MANDATORY (dod-version 9)" "$(sec492 "$(r492 "$SCRIPT" "$WORK/dq492-absent.md" "$WORK/dq492.yml")")"
  expect "#492 ($1): a literal-quoted heading is not the label" "fail|heading absent (1): Definition of Done: MANDATORY (dod-version 9)" "$(sec492 "$(r492 "$SCRIPT" "$WORK/dq492-lit.md" "$WORK/dq492.yml")")"
  expect "#492 ($1): an unterminated quote is dumped as read, quote kept" "$(printf '"Broken\tno')" "$(d492 "$SCRIPT" "$WORK/br492.md" "$WORK/br492.yml")"
  expect "#492 ($1): ...and a full run fails it, quote kept" 'fail|heading absent (1): "Broken' "$(sec492 "$(r492 "$SCRIPT" "$WORK/br492.md" "$WORK/br492.yml")")"
  expect "#492 ($1): an escaped backslash does not escape the closing quote" 'Path C:\' "$(d492 "$SCRIPT" "$WORK/pc492.md" "$WORK/pc492.yml" | cut -f1)"
  expect "#492 ($1): the CRLF copy of the double-quoted template gives the LF rows (passing body)" "$o" "$(r492 "$SCRIPT" "$WORK/dq492-ok.md" "$WORK/dq492-crlf.yml")"
  expect "#492 ($1): ...and the LF rows on the absent body" "$(r492 "$SCRIPT" "$WORK/dq492-absent.md" "$WORK/dq492.yml")" "$(r492 "$SCRIPT" "$WORK/dq492-absent.md" "$WORK/dq492-crlf.yml")"
  expect "#492 ($1): ...and the LF --dump-fields output" "$(printf 'Summary\tyes\nDefinition of Done: MANDATORY (dod-version 9)\tyes')" "$(d492 "$SCRIPT" "$WORK/dq492-ok.md" "$WORK/dq492-crlf.yml")"
  expect "#492 ($1): --roles prints a quoted unit-test label unquoted" "$(printf 'unit_tests\tUnit tests: per module')" "$(bash "$SCRIPT" --roles --template "$WORK/rl492.yml" 2>/dev/null)"
  expect "#492 ($1): blanks inside the quotes are trimmed: --dump-fields prints exactly Foo" "$(printf 'Foo\tyes')" "$(d492 "$SCRIPT" "$WORK/tb492.md" "$WORK/tb492.yml")"
  expect "#492 ($1): ...and a ## Foo body passes sections" pass "$(outcome "$(r492 "$SCRIPT" "$WORK/tb492.md" "$WORK/tb492.yml")" sections)"
  expect "#492 ($1): an empty quoted required label fails closed, the heading absent" 'fail|heading absent (1): ""' "$(sec492 "$(r492 "$SCRIPT" "$WORK/em492.md" "$WORK/em492.yml")")"
  expect "#492 ($1): ...and --dump-fields prints it as read" "$(printf 'Summary\tyes\n""\tyes')" "$(d492 "$SCRIPT" "$WORK/em492.md" "$WORK/em492.yml")"
  expect "#492 ($1): an empty single-quoted label is kept as read" "$(printf "Summary\tyes\n''\tyes")" "$(d492 "$SCRIPT" "$WORK/em492.md" "$WORK/em492-sq.yml")"
  expect "#492 ($1): a blank-only quoted label is kept as read" "$(printf 'Summary\tyes\n" "\tyes')" "$(d492 "$SCRIPT" "$WORK/em492.md" "$WORK/em492-sp.yml")"
}
cases492 "default awk"
if command -v mawk >/dev/null 2>&1; then
  mkdir -p "$WORK/mawk492"; printf '#!/bin/sh\nexec mawk "$@"\n' > "$WORK/mawk492/awk"; chmod +x "$WORK/mawk492/awk"
  PATH="$WORK/mawk492:$PATH" cases492 mawk
else
  ok "#492: portability: mawk not on PATH, quoted-label rows under mawk skipped"
fi
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN{}' 2>/dev/null; then
  mkdir -p "$WORK/bb492"; printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$WORK/bb492/awk"; chmod +x "$WORK/bb492/awk"
  PATH="$WORK/bb492:$PATH" cases492 "busybox awk"
else
  ok "#492: portability: busybox awk not on PATH, quoted-label rows under busybox awk skipped"
fi
# Mutants: a ledger row says the code is there, an applied-check says the mutant changed it, and the
# row it names must fail on the mutant.
M492="$WORK/mut492.sh"
XU492='label = unq(l)'
XP492='awk "$UNQ_AWK"'
for f492 in template_fields template_subheadings; do
  grep -qF "$XU492" <<< "$(fn493 "$f492" "$SCRIPT")" && ok "mutant ledger: $f492() unquotes its label (#492)" || bad "mutant ledger: $f492() lacks $XU492"
  grep -qF "$XP492" <<< "$(fn493 "$f492" "$SCRIPT")" && ok "mutant ledger: $f492() prepends UNQ_AWK (#492)" || bad "mutant ledger: $f492() does not prepend UNQ_AWK"
done
XS492='return s   # opens with a quote'
XD492='{ out = out d; i++; continue }   # one decode pass'
grep -qF "$XS492" "$SCRIPT" && ok "mutant ledger: unq() opens with the quote test and scans for the close (#492)" || bad "mutant ledger: #492 opening line not found"
grep -qF "$XD492" "$SCRIPT" && ok "mutant ledger: unq() decodes both escapes in one pass (#492)" || bad "mutant ledger: #492 decode line not found"
XT492='sub(/[ \t]+$/, "", out); '
XE492='if (out == "") return s; '
grep -qF "$XT492" "$SCRIPT" && ok "mutant ledger: unq() trims the blanks inside the quotes (#492)" || bad "mutant ledger: #492 inner trim not found"
grep -qF "$XE492" "$SCRIPT" && ok "mutant ledger: unq() keeps a value that unquotes to empty as read (#492)" || bad "mutant ledger: #492 empty-value guard not found"
mut492() {  # mut492 <sed range or empty> <sed expr> <string the mutant must remove>
  if [ -n "$1" ]; then sed "/^$1() {/,/^}/ $2" "$SCRIPT" > "$M492"; else sed "$2" "$SCRIPT" > "$M492"; fi
  if cmp -s "$SCRIPT" "$M492"; then bad "#492: the mutant '$2' did not apply"; return 1; fi
  if [ -n "$1" ] && grep -qF "$3" <<< "$(fn493 "$1" "$M492")"; then bad "#492: the mutant '$2' left '$3' in $1()"; return 1; fi
  if [ -z "$1" ] && grep -qF "$3" "$M492"; then bad "#492: the mutant '$2' left '$3'"; return 1; fi
  return 0; }
if mut492 template_fields 's/label = unq(l)/label = l/' "$XU492"; then
  expect "mutant: template_fields() without unq() fails the double-quoted positive (the dq row can fail)" \
    'fail|heading absent (1): "Definition of Done: MANDATORY (dod-version 9)"' "$(sec492 "$(r492 "$M492" "$WORK/dq492-ok.md" "$WORK/dq492.yml")")"
fi
if mut492 template_subheadings 's/label = unq(l)/label = l/' "$XU492"; then
  expect "mutant: template_subheadings() without unq() ends the quoted field at its own ### Sub (the sub-heading row can fail)" \
    "fail|required heading present but empty (1): Rollout: plan" "$(sec492 "$(r492 "$M492" "$WORK/sub492.md" "$WORK/sub492.yml")")"
fi
if mut492 "" 's/return s   # opens with a quote$/return s; if (substr(s, n = length(s), 1) == q) return substr(s, 2, n - 2); return s   # last character/' "$XS492"; then
  expect "mutant: testing the last character instead of scanning fails the trailing-comment positive (the comment row can fail)" \
    fail "$(outcome "$(r492 "$M492" "$WORK/cm492.md" "$WORK/cm492.yml")" sections)"
fi
if mut492 "" '/# one decode pass$/d' "$XD492"; then
  expect "mutant: dropping the escape decode fails the one-pass positive (the escape row can fail)" \
    '"Say \"hi\" to C:\\dir"' "$(d492 "$M492" "$WORK/esc492.md" "$WORK/esc492.yml" | cut -f1)"
fi
if mut492 "" 's/{ out = out d; i++; continue }   # one decode pass$/{ out = out d; if (d == "\\"") i++; continue }   # misread pairs/' "$XD492"; then
  expect "mutant: a scan that lets an escaped backslash escape the closing quote keeps the Path label quoted (the Path row can fail)" \
    '"Path C:\\"' "$(d492 "$M492" "$WORK/pc492.md" "$WORK/pc492.yml" | cut -f1)"
fi
if mut492 "" 's/sub(\/\[ \\t\]+\$\/, "", out); //' "$XT492"; then
  expect "mutant: dropping the inner trim dumps the blanks (the Foo row can fail)" "$(printf 'Foo  \tyes')" "$(d492 "$M492" "$WORK/tb492.md" "$WORK/tb492.yml")"
  expect "mutant: ...and the ## Foo body reads heading absent" 'fail|heading absent (1): Foo  ' "$(sec492 "$(r492 "$M492" "$WORK/tb492.md" "$WORK/tb492.yml")")"
fi
if mut492 "" 's/if (out == "") return s; //' "$XE492"; then
  expect "mutant: dropping the empty-value guard skips the field and passes sections (the empty row can fail)" \
    pass "$(outcome "$(r492 "$M492" "$WORK/em492.md" "$WORK/em492.yml")" sections)"
fi

echo "check-ticket-mechanics: --roles prints the label each role resolves to (#213)"
# Step 0c reads this instead of matching field ids itself, so the resolution rule lives here alone.
roles() { bash "$SCRIPT" --roles --template "$1" 2>/dev/null; }
role_line() { printf '%s\n' "$1" | awk -F'\t' -v r="$2" '$1==r{print $2}'; }
FEAT="$TPLDIR/feature.yml"
o="$(roles "$FEAT")"
expect "#213: feature.yml lists the four roles in the fixed order, tab-separated" \
  "$(printf 'scenarios\tTest scenarios (Given / When / Then)\nunit_tests\tUnit tests\ne2e_tests\tE2E test scenarios\ndocs_impact\tDocumentation impact')" "$o"
expect "#213: role scenarios resolves" "Test scenarios (Given / When / Then)" "$(role_line "$o" scenarios)"
expect "#213: role unit_tests resolves" "Unit tests" "$(role_line "$o" unit_tests)"
expect "#213: role e2e_tests resolves" "E2E test scenarios" "$(role_line "$o" e2e_tests)"
expect "#213: role docs_impact resolves" "Documentation impact" "$(role_line "$o" docs_impact)"
expect "#213: bug.yml prints its own E2E label" "E2E tests" "$(role_line "$(roles "$TPLDIR/bug.yml")" e2e_tests)"
o="$(roles "$WORK/hubbub.yml")"
expect "#213: a renamed E2E section (id and label) resolves under e2e_tests" "Integration / subprocess test scenarios" "$(role_line "$o" e2e_tests)"
expect "#213: the hubbub template prints exactly its two roles" "$(printf 'e2e_tests\tIntegration / subprocess test scenarios\ndocs_impact\tDocumentation impact')" "$o"
o="$(roles "$TPLDIR/security.yml")"
expect "#213: a template with no E2E field prints no e2e_tests line" "" "$(role_line "$o" e2e_tests)"
expect "#213: ...and still prints scenarios" "Test scenarios (Given / When / Then)" "$(role_line "$o" scenarios)"
expect "#213: ...and docs_impact" "Documentation impact" "$(role_line "$o" docs_impact)"
# The label --roles prints is the heading check 3 judges: the hubbub body, headed by it, is a pass.
rl="$(role_line "$(roles "$WORK/hubbub.yml")" e2e_tests)"
printf '<!-- template-version: 6 -->\n\n### Summary\n\nx\n\n### %s\n\n- [ ] `tests/integration/spawn.test.ts` spawns the child\n\n### Documentation impact\n\nUpdates `docs/x.md`\n' "$rl" > "$WORK/rt.md"
o="$(bash "$SCRIPT" --body "$WORK/rt.md" --template "$WORK/hubbub.yml" --tpl-version 6 --current-tpl-version 6 --labels "backend,feature" 2>/dev/null)"
expect "#213: the printed E2E label is the heading check 3 judges (pass)" pass "$(outcome "$o" e2e_tests)"
# A metacharacter label is printed verbatim.
mktpl "$WORK/meta2.yml" 'unit_tests|Unit tests & (a/b) $HOME `x` \d|true'
o="$(bash "$SCRIPT" --roles --template "$WORK/meta2.yml" 2>/dev/null)"
expect "#213: a label of shell and regex metacharacters prints verbatim" "$(printf 'unit_tests\tUnit tests & (a/b) $HOME `x` \\d')" "$o"
# Two E2E-shaped fields: the first one wins, as check 3 reads it.
mktpl "$WORK/dup.yml" "e2e_tests|First E2E|true" "more_e2e|Second E2E|true"
expect "#213: a duplicate E2E field resolves to the first" "First E2E" "$(role_line "$(roles "$WORK/dup.yml")" e2e_tests)"
# A CRLF template: template_fields() strips each label's trailing CR at the source (#493), so
# --roles prints the label as read, with no print-time strip of its own.
sed 's/$/\r/' "$FEAT" > "$WORK/crlf.yml"
o="$(roles "$WORK/crlf.yml")"
expect "#213: a CRLF template prints labels without a trailing CR" "$(roles "$FEAT")" "$o"
grep -q $'\r' <<< "$o" && bad "#213: CR leaked into --roles output" || ok "#213: no CR byte in --roles output"
# Argument and error contract: stdout is empty on every refusal.
o="$(bash "$SCRIPT" --roles 2>"$WORK/err")"; rc=$?
expect "#213: --roles without --template exits 2" 2 "$rc"
expect "#213: ...with empty stdout" "" "$o"
grep -q -- '--template is required' "$WORK/err" && ok "#213: ...and says --template is required" || bad "#213: wrong message: $(cat "$WORK/err")"
o="$(bash "$SCRIPT" --roles --template "$WORK/nowhere.yml" 2>/dev/null)"; rc=$?
expect "#213: an unreadable template exits 2" 2 "$rc"
expect "#213: ...with empty stdout" "" "$o"
: > "$WORK/empty.yml"
o="$(bash "$SCRIPT" --roles --template "$WORK/empty.yml" 2>/dev/null)"; rc=$?
expect "#213: a template that parses to nothing exits 2" 2 "$rc"
expect "#213: ...with empty stdout" "" "$o"
o="$(bash "$SCRIPT" --roles --dump-fields --template "$FEAT" 2>"$WORK/err")"; rc=$?
expect "#213: --roles with --dump-fields exits 2" 2 "$rc"
expect "#213: ...with empty stdout" "" "$o"
grep -q 'mutually exclusive' "$WORK/err" && ok "#213: ...and says they are mutually exclusive" || bad "#213: wrong message: $(cat "$WORK/err")"
o="$(bash "$SCRIPT" --dump-fields --template "$FEAT" 2>"$WORK/err")"; rc=$?
expect "#213: --dump-fields still requires --body" 2 "$rc"
o="$(bash "$SCRIPT" --roles --body "$WORK/nowhere.md" --template "$FEAT" 2>/dev/null)"
expect "#213: --roles ignores a --body it is given" "$(roles "$FEAT")" "$o"
grep -q -- '--roles' <<< "$helptext" && ok "#213: --help documents --roles" || bad "#213: --help omits --roles"

# Mutants of the script: each must change a case above, or the case is decoration.
mutroles() {  # mutroles <name> <sed expr>; leaves the mutant at $WORK/mut-roles.sh
  sed "$2" "$SCRIPT" > "$WORK/mut-roles.sh"
  cmp -s "$SCRIPT" "$WORK/mut-roles.sh" && { bad "#213: mutant '$1' did not apply"; return 1; }; return 0; }
mrun() { bash "$WORK/mut-roles.sh" --roles --template "$1" 2>/dev/null; }
want_feat="$(roles "$FEAT")"
if mutroles "order" 's/for r in "scenarios:$SCENARIOS_LABEL" "unit_tests:$UNIT_LABEL" "e2e_tests:$E2E_LABEL" "docs_impact:$DOCS_LABEL"/for r in "docs_impact:$DOCS_LABEL" "e2e_tests:$E2E_LABEL" "unit_tests:$UNIT_LABEL" "scenarios:$SCENARIOS_LABEL"/'; then
  [ "$(mrun "$FEAT")" = "$want_feat" ] && bad "#213: MUTANT survived: reversed role order" || ok "#213: MUTANT: reversed role order fails the order case"; fi
# Re-aimed by #493: the print-time `tr` is retired, so the mutant removes the source strip instead.
if mutroles "cr" '/^template_fields() {/,/^}/ s/sub(\/\\r\$\/, "", l); //'; then
  if grep -qF 'sub(/\r$/, "", l); ' <<< "$(sed -n '/^template_fields() {/,/^}/p' "$WORK/mut-roles.sh")"; then bad "#213: mutant 'cr' left the label strip in place"
  else [ "$(mrun "$WORK/crlf.yml")" = "$want_feat" ] && bad "#213: MUTANT survived: CR not stripped" || ok "#213: MUTANT: CR not stripped fails the CRLF case"; fi; fi
if mutroles "skip" 's/\[ -n "${r#\*:}" \] && printf/printf/'; then
  [ "$(mrun "$TPLDIR/security.yml")" = "$(roles "$TPLDIR/security.yml")" ] && bad "#213: MUTANT survived: unresolved role printed" || ok "#213: MUTANT: an unresolved role is printed as an empty label"; fi
if mutroles "body" 's/^if \[ "$ROLES" -eq 0 \]; then$/if true; then/'; then
  bash "$WORK/mut-roles.sh" --roles --template "$FEAT" >/dev/null 2>&1 && bad "#213: MUTANT survived: --roles demands --body" || ok "#213: MUTANT: --roles demanding --body fails the no-body case"; fi
if mutroles "exclusive" 's/^\[ "$ROLES" -eq 0 \] || \[ "$DUMP_FIELDS" -eq 0 \] || die.*$/:/'; then
  bash "$WORK/mut-roles.sh" --roles --dump-fields --template "$FEAT" >/dev/null 2>&1 && ok "#213: MUTANT: dropping the exclusion lets --roles through (rc 0, not 2)" || bad "#213: MUTANT survived: --roles with --dump-fields still refused"; fi

# The agent half cannot run here, so its two sentences are pinned and mutated.
ROLES_PHRASE='"$MECH" --roles --template <0a'"'"'s TPL_DIR>/<type>.yml'
STOP_PHRASE='A non-zero `--roles` exit is `BLOCKED - RUN_FAILED` before any write'
gate_pin() { grep -qF "$1" <<< "$(tr '\n' ' ' < "$2" | tr -s ' ')"; }
gate_pin "$ROLES_PHRASE" "$GATE" && ok "#213: ticket-gate.md's Step 0c calls --roles" || bad "#213: ticket-gate.md lost the --roles call"
gate_pin "$STOP_PHRASE" "$GATE" && ok "#213: ticket-gate.md stops on a failed --roles" || bad "#213: ticket-gate.md lost the --roles stop clause"
sed 's/"\$MECH" --roles --template/"$MECH" --dump-fields --template/' "$GATE" > "$WORK/gate-roles-mut.md"
cmp -s "$GATE" "$WORK/gate-roles-mut.md" && bad "#213: the call mutant did not apply"
gate_pin "$ROLES_PHRASE" "$WORK/gate-roles-mut.md" && bad "#213: MUTANT survived: the call pin passes without --roles" || ok "#213: MUTANT: replacing the --roles call fails the pin"
sed 's/is `BLOCKED - RUN_FAILED` before any write/is ignored/' "$GATE" > "$WORK/gate-stop-mut.md"
cmp -s "$GATE" "$WORK/gate-stop-mut.md" && bad "#213: the stop mutant did not apply"
gate_pin "$STOP_PHRASE" "$WORK/gate-stop-mut.md" && bad "#213: MUTANT survived: the stop pin passes with the clause gone" || ok "#213: MUTANT: dropping the stop clause fails the pin"
# The mechanics are resolved before 0c runs: the preamble sits in Step 0, ahead of Step 0c.
pre="$(grep -nF '> "$D/mech"' "$GATE" | head -1 | cut -d: -f1)"; zc="$(grep -n '^#### 0c\.' "$GATE" | head -1 | cut -d: -f1)"
[ -n "$pre" ] && [ -n "$zc" ] && [ "$pre" -lt "$zc" ] && ok "#213: \$MECH is resolved before Step 0c" || bad "#213: Step 0c comes before the \$MECH preamble ($pre, $zc)"
DOC_ROLES='check-ticket-mechanics.sh --roles'
grep -qF -- "$DOC_ROLES" "$DOC" && ok "#213: template-versioning.md names where Step 0c gets the role labels" || bad "#213: template-versioning.md does not name --roles"

# #472: the gate's lens routing is prose a model reads, so a grep contract pins that Step 2.5 states
# the case rule ONCE and that the two label-keyed rows it governs still key on the lowercase names.
CASE_PHRASE='Label names match without regard to case'
n472="$(grep -cF "$CASE_PHRASE" "$GATE")"
[ "$n472" = 1 ] && ok "#472: ticket-gate.md states the case rule exactly once" || bad "#472: the case rule appears $n472 times in ticket-gate.md"
gate_pin '| API-design brief | label `api` OR body matches' "$GATE" && gate_pin '| Privacy regime | label `privacy` |' "$GATE" \
  && ok "#472: the API-design and Privacy rows still key on the lowercase names the rule folds" || bad "#472: a routing row no longer keys on label api or privacy"
sed "s/$CASE_PHRASE/Label names match exactly/" "$GATE" > "$WORK/gate-case-mut.md"
cmp -s "$GATE" "$WORK/gate-case-mut.md" && bad "#472: the case-rule mutant did not apply"
[ "$(grep -cF "$CASE_PHRASE" "$WORK/gate-case-mut.md")" = 1 ] && bad "#472: MUTANT survived: the case-rule contract passes with the sentence gone" || ok "#472: MUTANT: deleting the case-rule sentence fails the contract"
sed 's/| API-design brief | label `api` OR/| API-design brief | label `API` OR/' "$GATE" > "$WORK/gate-row-mut.md"
cmp -s "$GATE" "$WORK/gate-row-mut.md" && bad "#472: the row mutant did not apply"
gate_pin '| API-design brief | label `api` OR body matches' "$WORK/gate-row-mut.md" && bad "#472: MUTANT survived: the row pin passes with the row reworded" || ok "#472: MUTANT: rewording the API row fails the pin"

# #513: --classes partitions a template's labels into what the gate owns, what Step 0c writes and what
# only the author supplies, so check 3's absent set on a post-0c body is a computed fact, not a claim.
echo "check-ticket-mechanics: --classes partitions the template labels (#513)"
classes() { bash "$SCRIPT" --classes --template "$1" 2>/dev/null; }
class_labels() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1==c{print $2}'; }
# partition_guard <body> <template>: runs check 3 and fails if it reports a SYNTHESISED label absent.
# A test helper, not a shipped mode: the rule is "Step 0c writes it, so check 3 must never miss it".
partition_guard() {
  local ev absent lab
  ev="$(bash "$SCRIPT" --body "$1" --template "$2" --tpl-version 6 --current-tpl-version 6 --labels "bug,api" 2>/dev/null | awk -F'\t' '$1=="sections"{print $3}')"
  case "$ev" in "heading absent"*) absent="${ev#*): }" ;; *) return 0 ;; esac
  while IFS= read -r lab; do
    [ -n "$lab" ] || continue
    synth="$(class_labels "$(classes "$2")" synthesised)"
    if grep -qxF -- "$lab" <<< "$synth"; then
      echo "synthesised heading reported absent: $lab"; return 1
    fi
  done <<< "$(printf '%s\n' "$absent" | sed 's/; /\n/g')"
  return 0
}
absent_of() {
  bash "$SCRIPT" --body "$1" --template "$2" --tpl-version 6 --current-tpl-version 6 --labels "bug,api" 2>/dev/null \
    | awk -F'\t' '$1=="sections"{print $3}' | sed -n 's/^heading absent ([0-9]*): //p' | sed 's/; /\n/g'
}
# A pointer-free post-0c body: only the synthesised headings, filled, plus the author's Problem.
post0c_body() {
  { printf '## Problem\nsomething\n\n'
    class_labels "$(classes "$1")" synthesised | while IFS= read -r l; do printf '## %s\ncontent\n\n' "$l"; done
  } > "$2"
}
BUG10="$(printf 'Bug description\nSteps to reproduce\nExpected vs actual behavior\nAffected areas\nSeverity\nSecurity impact\nAcceptance criteria\nDependencies\nRequired reviews (mandatory)\nQA & Regression tests')"
expect "#513: bug.yml author-supplied is the ten-label literal" "$BUG10" "$(class_labels "$(classes "$TPLDIR/bug.yml")" author-supplied)"
expect "#513: bug.yml gate-owned is Codebase Context" "Codebase Context" "$(class_labels "$(classes "$TPLDIR/bug.yml")" gate-owned)"
for t in bug feature security infrastructure design; do
  T="$TPLDIR/$t.yml"; c="$(classes "$T")"
  all="$(bash "$SCRIPT" --dump-fields --body "$T" --template "$T" 2>/dev/null | cut -f1)"
  expect "#513 ($t): every template label has exactly one class row" "$all" "$(printf '%s\n' "$c" | cut -f2)"
  expect "#513 ($t): no label has two classes" "" "$(printf '%s\n' "$c" | cut -f2 | sort | uniq -d)"
  # Independent oracle: --roles output plus the personal-data field, never --classes itself.
  want="$(bash "$SCRIPT" --roles --template "$T" | cut -f2)"
  grep -q 'id: personal_data' "$T" && want="$(printf '%s\nPersonal data handling' "$want")"
  expect "#513 ($t): synthesised is the --roles labels plus personal data where the template has it" \
    "$(printf '%s\n' "$want" | sort)" "$(class_labels "$c" synthesised | sort)"
  b="$WORK/p0c-$t.md"; post0c_body "$T" "$b"
  expect "#513 ($t): pointer-free post-0c body is absent exactly the author-supplied class" \
    "$(class_labels "$c" author-supplied | sort)" "$(absent_of "$b" "$T" | sort)"
  partition_guard "$b" "$T" >/dev/null && ok "#513 ($t): the partition guard accepts it" || bad "#513 ($t): the partition guard rejected a post-0c body"
done
# Pointer-aware: Step 0c-iv places a pointer under Bug description and Affected areas, leaving eight.
b="$WORK/p0c-bug-ptr.md"; post0c_body "$TPLDIR/bug.yml" "$b"
printf '## Bug description\nSee "Problem" below.\n\n## Affected areas\nSee "Scope" below.\n' >> "$b"
expect "#513: pointer-aware bug.yml fixture is absent eight labels" "8" "$(absent_of "$b" "$TPLDIR/bug.yml" | wc -l | tr -d ' ')"
expect "#513: pointer-aware absent set is the ten minus the two pointer-placed" \
  "$(printf '%s\n' "$BUG10" | grep -vxF -e 'Bug description' -e 'Affected areas' | sort)" "$(absent_of "$b" "$TPLDIR/bug.yml" | sort)"
# Negative: a synthesised heading missing from the body is named by the guard.
b="$WORK/p0c-bug-neg.md"; post0c_body "$TPLDIR/bug.yml" "$b"
grep -v '^## Documentation impact$' "$b" > "$b.x"; mv "$b.x" "$b"
o="$(partition_guard "$b" "$TPLDIR/bug.yml")"; rc=$?
expect "#513: guard exits 1 when a synthesised heading is absent" 1 "$rc"
expect "#513: guard message names the heading" "synthesised heading reported absent: Documentation impact" "$o"
# CLI contract.
o="$(bash "$SCRIPT" --classes --template "$TPLDIR/nope.yml" 2>&1)"; rc=$?
expect "#513: --classes on a missing template exits 2" 2 "$rc"
expect "#513: the missing-template message names the path" "check-ticket-mechanics: template file not found: $TPLDIR/nope.yml" "$o"
o="$(bash "$SCRIPT" --classes 2>&1)"; rc=$?
expect "#513: --classes without --template exits 2" 2 "$rc"
for x in --roles --dump-fields --headings; do
  o="$(bash "$SCRIPT" --classes $x --body "$TPLDIR/bug.yml" --template "$TPLDIR/bug.yml" 2>&1)"; rc=$?
  expect "#513: --classes with $x exits 2" 2 "$rc"
done
expect "#513: --classes ignores a --body it is given" "$(classes "$TPLDIR/bug.yml")" "$(bash "$SCRIPT" --classes --body "$WORK/nowhere.md" --template "$TPLDIR/bug.yml" 2>/dev/null)"
HELP="$(bash "$SCRIPT" --help)"
grep -q -- '--classes' <<< "$HELP" && ok "#513: --help documents --classes" || bad "#513: --help omits --classes"
# Mutants, on a cp copy: dropping the personal-data rule must break the bug.yml oracle.
cp "$SCRIPT" "$WORK/mut-cls.sh"
sed 's/tolower(\$3) == "personal_data"/tolower($3) == "zzz"/' "$SCRIPT" > "$WORK/mut-cls.sh"
cmp -s "$SCRIPT" "$WORK/mut-cls.sh" && bad "#513: the personal-data mutant did not apply"
[ "$(bash "$WORK/mut-cls.sh" --classes --template "$TPLDIR/bug.yml" | awk -F'\t' '$1=="author-supplied"{print $2}')" = "$BUG10" ] \
  && bad "#513: MUTANT survived: dropping personal_data from synthesised keeps the oracle" || ok "#513: MUTANT: dropping personal_data fails the bug.yml oracle"
sed 's/(\$4 == "yes") ? "gate-owned"/($4 == "zzz") ? "gate-owned"/' "$SCRIPT" > "$WORK/mut-cls2.sh"
cmp -s "$SCRIPT" "$WORK/mut-cls2.sh" && bad "#513: the gate-owned mutant did not apply"
[ -z "$(bash "$WORK/mut-cls2.sh" --classes --template "$TPLDIR/bug.yml" | awk -F'\t' '$1=="gate-owned"')" ] \
  && ok "#513: MUTANT: ignoring the gate flag empties gate-owned (the bug.yml row above fails)" || bad "#513: MUTANT survived: gate-owned still printed"
# Step 0c's target list (ticket-gate.md 0c-ii) is prose; pin it so it cannot drift from the synthesised class.
T0C='the roles `--roles` printed, and `personal_data`'
gate_pin "$T0C" "$GATE" && ok "#513: Step 0c-ii targets are the --roles labels plus personal_data, as --classes' synthesised class" || bad "#513: Step 0c-ii target wording changed; --classes' synthesised class no longer matches"
sed 's/the roles `--roles` printed, and `personal_data`/the roles printed/' "$GATE" > "$WORK/gate-0cii-mut.md"
cmp -s "$GATE" "$WORK/gate-0cii-mut.md" && bad "#513: the 0c-ii mutant did not apply"
gate_pin "$T0C" "$WORK/gate-0cii-mut.md" && bad "#513: MUTANT survived: the 0c-ii pin passes with the wording changed" || ok "#513: MUTANT: rewording the 0c-ii targets fails the pin"

# #505: --skeleton restores a template's static checklist sections on an API-filed body.
echo "check-ticket-mechanics: --skeleton prints and appends the template checklist sections (#505)"
sk() { bash "$SCRIPT" --skeleton --template "$@"; }
sk_heads() { grep '^## ' ; }
want_heads() { # <template> <literal headings, one per line>
  local o; o="$(sk "$TPLDIR/$1.yml" 2>/dev/null | sk_heads)"
  expect "#505 ($1): print mode lists exactly the checklist sections, in template order" "$2" "$o"
  expect "#505 ($1): print mode leads with the template-version marker" "<!-- template-version: 6 -->" "$(sk "$TPLDIR/$1.yml" 2>/dev/null | head -1)"
}
want_heads feature "$(printf '## Required reviews (mandatory)\n## QA & Security testing')"
want_heads bug "$(printf '## Required reviews (mandatory)\n## QA & Regression tests')"
want_heads design "$(printf '## Accessibility requirements\n## Brand consistency\n## Required reviews (mandatory)')"
want_heads security "## Required reviews (mandatory)"
want_heads infrastructure "## Required reviews (mandatory)"
o="$(sk "$TPLDIR/feature.yml" 2>/dev/null)"
grep -qxF '### Security tests' <<< "$o" && grep -qxF '### QA tests' <<< "$o" && ok "#505: the qa_security field is one section holding both embedded sub-headings" || bad "#505: the embedded sub-headings of qa_security are missing"
grep -q 'Personal data handling\|Security considerations' <<< "$o" && bad "#505: a bare-stub value block was printed" || ok "#505: bare-stub value blocks (personal data, security) are not printed"
grep -qxF -- '- [ ] **ticket-gate** - mandatory before implementation. Mechanical checks + one critic (plus the security lens by label). Must return PASS.' <<< "$o" \
  && ok "#505: a checkbox option prints as an unchecked item" || bad "#505: the Required reviews option did not print"
# A project-added checkbox section is printed; a quoted label and option print unquoted; a CRLF copy prints no CR.
cat > "$WORK/sk-proj.yml" <<'YML'
name: Proj
body:
  - type: markdown
    attributes:
      value: |
        <!-- template-version: 3 -->
  - type: input
    id: who
    attributes:
      label: Who
  - type: checkboxes
    id: dod
    attributes:
      label: "Definition of done: all"
      options:
        - label: "Docs updated"
        - label: 'It''s released'
          required: true
  - type: textarea
    id: notes
    attributes:
      label: Notes
      placeholder: |
        - [ ] a placeholder checklist is not static content
YML
o="$(sk "$WORK/sk-proj.yml")"; rc=$?
expect "#505: a project-added checkbox section prints, a placeholder checklist does not" "$(printf '<!-- template-version: 3 -->\n\n## Definition of done: all\n- [ ] Docs updated\n- [ ] It'"'"'s released')" "$o"
expect "#505: the project template exits 0" 0 "$rc"
sed 's/$/\r/' "$WORK/sk-proj.yml" > "$WORK/sk-proj-crlf.yml"
expect "#505: a CRLF template prints the LF output" "$o" "$(sk "$WORK/sk-proj-crlf.yml")"
grep -q $'\r' <<< "$(sk "$TPLDIR/feature.yml")" && bad "#505: CR leaked into skeleton output" || ok "#505: no CR in skeleton output"
# A template with no marker prints the sections and no marker line.
grep -v 'template-version' "$WORK/sk-proj.yml" > "$WORK/sk-nomark.yml"
o="$(sk "$WORK/sk-nomark.yml")"; rc=$?
expect "#505: a template with no marker prints no marker line" "$(printf '\n## Definition of done: all\n- [ ] Docs updated\n- [ ] It'"'"'s released')" "$o"
expect "#505: a template with no marker exits 0" 0 "$rc"
# Refusals: exit 2, message, nothing on stdout.
refuse() { # <label> <expected stderr substring> <args...>
  local lab="$1" sub="$2"; shift 2
  o="$(bash "$SCRIPT" "$@" 2>"$WORK/err")"; rc=$?
  expect "#505: $lab exits 2" 2 "$rc"; expect "#505: $lab prints nothing on stdout" "" "$o"
  grep -qF -- "$sub" "$WORK/err" && ok "#505: $lab names its cause" || bad "#505: $lab stderr lacks '$sub': $(cat "$WORK/err")"
}
printf 'name: x\n' > "$WORK/sk-nobody.yml"
refuse "a template with no body: list" "$WORK/sk-nobody.yml has no body: list" --skeleton --template "$WORK/sk-nobody.yml"
sed 's/^      label: Notes$/      label: Notes\n      value: "x"/' "$WORK/sk-proj.yml" > "$WORK/sk-style.yml"
refuse "an inline value: style" "has an unsupported value: style" --skeleton --template "$WORK/sk-style.yml"
refuse "a missing template" "template file not found" --skeleton --template "$WORK/nope.yml"
refuse "--skeleton without --template" "--template is required" --skeleton
refuse "a missing --body file" "body file not found" --skeleton --template "$FEAT" --body "$WORK/nope.md"
for x in --roles --dump-fields --headings --classes; do
  refuse "--skeleton with $x" "--skeleton is exclusive" --skeleton $x --template "$FEAT" --body "$FEAT"
done
HELP="$(bash "$SCRIPT" --help)"
grep -q -- '--skeleton' <<< "$HELP" && ok "#505: --help documents --skeleton" || bad "#505: --help omits --skeleton"
# Append mode.
SKB="$WORK/sk-body.md"
printf '# Title\n\n## QA & Security testing\ncustom text\n' > "$SKB"
o="$(sk "$FEAT" --body "$SKB")"
expect "#505: append keeps the custom section and adds only Required reviews, once, with no marker" \
  "$(printf '# Title\n\n## QA & Security testing\ncustom text\n\n## Required reviews (mandatory)\n- [ ] **ticket-gate** - mandatory before implementation. Mechanical checks + one critic (plus the security lens by label). Must return PASS.')" "$o"
# A complete body is returned byte for byte: LF, CRLF and no trailing newline.
{ sk "$FEAT" | tail -n +2; } > "$WORK/sk-full.md"
cmp -s "$WORK/sk-full.md" <(sk "$FEAT" --body "$WORK/sk-full.md") && ok "#505: a complete LF body is untouched (cmp)" || bad "#505: a complete LF body changed"
sed 's/$/\r/' "$WORK/sk-full.md" > "$WORK/sk-full-crlf.md"
cmp -s "$WORK/sk-full-crlf.md" <(sk "$FEAT" --body "$WORK/sk-full-crlf.md") && ok "#505: a complete CRLF body is untouched (cmp)" || bad "#505: a complete CRLF body changed"
printf '%s' "$(cat "$WORK/sk-full.md")" > "$WORK/sk-full-nonl.md"
cmp -s "$WORK/sk-full-nonl.md" <(sk "$FEAT" --body "$WORK/sk-full-nonl.md") && ok "#505: a complete body with no trailing newline is untouched (cmp)" || bad "#505: the no-newline body changed"
# A body with no trailing newline gets exactly one newline before the blank line.
printf '## QA & Security testing\ncustom' > "$WORK/sk-nonl.md"
expect "#505: a body with no trailing newline is joined with one newline and a blank line" \
  "$(printf '## QA & Security testing\ncustom\n\n## Required reviews (mandatory)')" "$(sk "$FEAT" --body "$WORK/sk-nonl.md" | head -4)"
# The marker is never added or changed.
printf '<!-- template-version: 5 -->\n# T\n' > "$WORK/sk-old.md"
o="$(sk "$FEAT" --body "$WORK/sk-old.md")"
expect "#505: an older marker never gains a second one" "1" "$(grep -c 'template-version' <<< "$o")"
grep -qxF '<!-- template-version: 5 -->' <<< "$o" && ok "#505: the older marker is still 5" || bad "#505: the older marker changed"
printf '# T\n' > "$WORK/sk-nomarker.md"
grep -q 'template-version' <<< "$(sk "$FEAT" --body "$WORK/sk-nomarker.md")" && bad "#505: a marker was added to a body that had none" || ok "#505: a body with no marker gains none"
# Presence is check 3's rule.
for pair in '#### Required reviews (mandatory)|absent|a #### heading' '### Required reviews (mandatory)|present|a ### heading' '## required reviews (mandatory)|absent|a heading differing only in case'; do
  h="${pair%%|*}"; rest="${pair#*|}"; want="${rest%%|*}"; lab="${rest#*|}"
  printf '%s\nx\n\n## QA & Security testing\ny\n' "$h" > "$WORK/sk-p.md"
  n="$(sk "$FEAT" --body "$WORK/sk-p.md" | grep -cxF '## Required reviews (mandatory)')"
  if [ "$want" = present ]; then expect "#505: $lab counts as present (nothing appended)" 0 "$n"; else expect "#505: $lab counts as absent (appended)" 1 "$n"; fi
done
printf '```\n## Required reviews (mandatory)\n```\n\n## QA & Security testing\ny\n' > "$WORK/sk-fence.md"
expect "#505: a fenced heading is not counted present" 2 "$(sk "$FEAT" --body "$WORK/sk-fence.md" | grep -cxF '## Required reviews (mandatory)')"
printf '## Required reviews (mandatory)\nx\n\n### Security tests\nsee\n' > "$WORK/sk-sub.md"
o="$(sk "$FEAT" --body "$WORK/sk-sub.md")"
expect "#505: an embedded sub-heading elsewhere does not stand in for the missing section" 1 "$(grep -cxF '## QA & Security testing' <<< "$o")"
# check 3 agrees with append mode on the result.
printf '#### Required reviews (mandatory)\nx\n' > "$WORK/sk-agree.md"
sk "$FEAT" --body "$WORK/sk-agree.md" > "$WORK/sk-agree-out.md"
n="$(bash "$SCRIPT" --body "$WORK/sk-agree-out.md" --template "$FEAT" --tpl-version 6 --current-tpl-version 6 --labels "enhancement,api" | awk -F'\t' '$1=="sections"{print $3}' | grep -c 'Required reviews')"
expect "#505: check 3 on the appended result no longer reports Required reviews absent" 0 "$n"
# Fail-closed recipe: a refusal inside the command substitution must stop the caller.
fc="$(body="$(bash "$SCRIPT" --skeleton --template "$WORK/nope.yml" 2>/dev/null)" || echo stopped; echo "[$body]")"
expect "#505: the documented '|| exit 1' form stops on a refusal with an empty body" "$(printf 'stopped\n[]')" "$fc"
SK_RECIPE='body="$(check-ticket-mechanics.sh --skeleton --template T --body F)" || exit 1'
grep -qF -- "$SK_RECIPE" "$SCRIPT" && ok "#505: the script header carries the fail-closed recipe" || bad "#505: the script header lost the fail-closed recipe"
grep -qF -- "$SK_RECIPE" "$ROOT/docs/guides/template-versioning.md" && ok "#505: template-versioning.md carries the fail-closed recipe" || bad "#505: template-versioning.md lacks the fail-closed recipe"
# Mutants, each on a cp copy of the script.
skmut() { # <name> <sed expr> <probe command producing a value> <value the real script gives>
  sed "$2" "$SCRIPT" > "$WORK/mut-sk-$1.sh"
  cmp -s "$SCRIPT" "$WORK/mut-sk-$1.sh" && { bad "#505: the $1 mutant did not apply"; return; }
}
skmut vhas 's/inval == 1 \&\& vhas/inval == 1/'
MSK="$(bash "$WORK/mut-sk-vhas.sh" --skeleton --template "$FEAT")"
grep -q 'Personal data handling' <<< "$MSK" && ok "#505: MUTANT: printing bare-stub value blocks adds Personal data handling (the stub row above fails)" || bad "#505: MUTANT survived: bare stubs not printed without the checklist test"
skmut opts 's/i <= nopt; i++) out = out "- \[ \] "/i <= 0; i++) out = out "- [ ] "/'
MSK="$(bash "$WORK/mut-sk-opts.sh" --skeleton --template "$FEAT")"
grep -qF -- '- [ ] **ticket-gate**' <<< "$MSK" && bad "#505: MUTANT survived: checkbox options dropped but still printed" || ok "#505: MUTANT: dropping the checkbox options fails the option row"
skmut miss 's/miss = !(("## " label) in have) \&\& !(("### " label) in have)/miss = 1/'
n="$(bash "$WORK/mut-sk-miss.sh" --skeleton --template "$FEAT" --body "$WORK/sk-full.md" | grep -cxF '## Required reviews (mandatory)')"
[ "$n" = 2 ] && ok "#505: MUTANT: appending without the presence check duplicates a heading (the cmp row fails)" || bad "#505: MUTANT survived: no presence check but no duplicate ($n)"
skmut hash 's/!(("### " label) in have)/1/'
printf '### Required reviews (mandatory)\nx\n' > "$WORK/sk-h3.md"
n="$(bash "$WORK/mut-sk-hash.sh" --skeleton --template "$FEAT" --body "$WORK/sk-h3.md" | grep -cxF '## Required reviews (mandatory)')"
[ "$n" = 1 ] && ok "#505: MUTANT: ignoring the ### level appends a duplicate (the ### row fails)" || bad "#505: MUTANT survived: ### level ignored without effect ($n)"

# #512: the WRITE ONCE paragraph names ownership by tag, not by "this run's 0c" (a later round cannot
# know which run synthesised a block). Step 0c-iii documents the tag; scripts/test-forge-lib.sh drives it.
OLD512="synthesised by THIS run's 0c"
grep -qF -- "gate-tagged section, never author text" "$GATE" && ok "#512: the WRITE ONCE paragraph says gate-tagged" || bad "#512: the WRITE ONCE paragraph lost 'gate-tagged'"
grep -qF -- "$OLD512" "$GATE" && bad "#512: the WRITE ONCE paragraph is back to 'synthesised by THIS run's 0c'" || ok "#512: the WRITE ONCE paragraph no longer says 'synthesised by THIS run's 0c'"
sed 's/gate-tagged section, never author text/section synthesised by THIS run'"'"'s 0c, never author text/' "$GATE" > "$WORK/gate-wo-mut.md"
cmp -s "$GATE" "$WORK/gate-wo-mut.md" && bad "#512: the WRITE ONCE mutant did not apply"
grep -qF -- "gate-tagged section, never author text" "$WORK/gate-wo-mut.md" && bad "#512: MUTANT survived: the gate-tagged pin passes on a reverted paragraph" || ok "#512: MUTANT: reverting the paragraph fails the gate-tagged pin"

# #510: the script's evidence cites a ticket-standards section by TITLE, never by number, because an
# adapted doc renumbers its sections and "rule 3" then pointed at the wrong one. Evidence is column 3.
evid() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1 == c { print $3 }'; }
E510="$(mkbody feature "e510e2e.md" "" "" "N/A, this ticket changes no UI-visible behaviour at all")"
R510="$(run "$E510" feature)"
case "$(evid "$R510" e2e_tests)" in *'section "E2E test specs"'*) ok "#510: the E2E N/A evidence names section \"E2E test specs\"" ;; *) bad "#510: E2E evidence lost the section title ($(evid "$R510" e2e_tests))" ;; esac
U510="$(mkbody feature "e510un.md" "" "N/A, a docs-only change with no code")"
R510="$(run "$U510" feature)"
case "$(evid "$R510" unit_tests)" in *'section "Unit test specs"'*) ok "#510: the unit N/A evidence names section \"Unit test specs\"" ;; *) bad "#510: unit evidence lost the section title ($(evid "$R510" unit_tests))" ;; esac
G510="$(mkbody feature "e510gw.md" "N/A, a docs-only change with no behaviour delta")"
R510="$(run "$G510" feature)"
case "$(evid "$R510" gwt)" in *'section "GWT scenarios"'*) ok "#510: the GWT N/A evidence names section \"GWT scenarios\"" ;; *) bad "#510: GWT evidence lost the section title ($(evid "$R510" gwt))" ;; esac
D510="$(mkbody feature "e510dc.md" "" "" "" "None, nothing user-visible changes")"
R510="$(run "$D510" feature)"
case "$(evid "$R510" docs_impact)" in *'section "Documentation currency"'*) ok "#510: the docs none-claim evidence names section \"Documentation currency\"" ;; *) bad "#510: docs evidence lost the section title ($(evid "$R510" docs_impact))" ;; esac
n510="$(printf '%s\n%s\n%s\n%s\n' "$(run "$E510" feature)" "$(run "$U510" feature)" "$(run "$G510" feature)" "$(run "$D510" feature)" | grep -ciE 'rules? ?-?[0-9]')"
[ "$n510" = 0 ] && ok "#510: no evidence line cites a numbered rule" || bad "#510: $n510 evidence lines still cite a numbered rule"
n510="$(grep -ciE 'rules? ?-?[0-9]' "$SCRIPT")"
[ "$n510" = 0 ] && ok "#510: the script source cites no numbered rule" || bad "#510: the script source has $n510 numbered rule citations"
sed 's/section \\"E2E test specs\\" says a UI-touching/rule 3 says a UI-touching/' "$SCRIPT" > "$WORK/mut-510.sh"
cmp -s "$SCRIPT" "$WORK/mut-510.sh" && bad "#510: the numbered-citation mutant did not apply"
n510="$(grep -ciE 'rules? ?-?[0-9]' "$WORK/mut-510.sh")"
[ "$n510" != 0 ] && ok "#510: MUTANT: a reverted citation is caught by the no-numbered-rule row" || bad "#510: MUTANT survived: the no-numbered-rule row passes a reverted citation"

echo
echo "check-ticket-mechanics tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
