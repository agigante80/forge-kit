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
# `na` would be a fail-open of its own: rules 3 and 7 still bind on an optional section, and
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
expect "an E2E N/A with a reason is REFERRED, since rule 3 is the critic's call" referred "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2enapath.md" "" "" "N/A, covered by \`tests/unit/auth.test.ts\` instead")"
expect "REGRESSION: an N/A citing a path is still an N/A claim, not a pass" referred "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2ebare.md" "" "" "N/A")"
expect "an E2E N/A with no reason fails" fail "$(outcome "$(run "$E" feature)" e2e_tests)"
E="$(mkbody feature "e2evague.md" "" "" "we will test it somehow")"
expect "an E2E section naming no path and claiming no N/A fails" fail "$(outcome "$(run "$E" feature)" e2e_tests)"

echo "check-ticket-mechanics: documentation impact"
expect "naming a doc passes" pass "$(outcome "$(run "$B" feature)" docs_impact)"
D="$(mkbody feature "docsnone.md" "" "" "" "None, this changes no documented behaviour whatsoever")"
expect "a reasoned none is REFERRED, since rule 7 applies to every work ticket" referred "$(outcome "$(run "$D" feature)" docs_impact)"
D="$(mkbody feature "docsbare.md" "" "" "" "none")"
expect "a bare none fails" fail "$(outcome "$(run "$D" feature)" docs_impact)"
D="$(mkbody feature "docsvague.md" "" "" "" "we should think about it")"
expect "neither a doc nor a none claim fails" fail "$(outcome "$(run "$D" feature)" docs_impact)"

echo "check-ticket-mechanics: the runner itself"
out="$(run "$B" feature)"
expect "emits exactly one row per check" 7 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
printf '%s\n' "$out" | awk -F'\t' 'NF != 3 { bad = 1 } END { exit bad + 0 }' \
  && ok "every row is three tab-separated fields" || bad "a row is not three fields"
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
printf '%s' "$helptext" | grep -q 'referred' \
  && ok "--help describes the current referred-not-na rule" || bad "--help header is stale"
printf '%s' "$helptext" | grep -q -- '--dump-fields' \
  && ok "--help documents every flag it accepts" || bad "--help omits a flag"

echo
echo "check-ticket-mechanics tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
