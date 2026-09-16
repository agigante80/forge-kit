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


echo "check-ticket-mechanics: the four gaps found gating another project (#205)"
# --- gap 1: the evidence row was cut at 160 characters, so a long absent-list lost its tail. ---
# feature.yml's required-label list is 248 characters joined; bug.yml's 259. The count prefix is
# what makes any future truncation visible, and the companion below asserts the count is honest.
printf '<!-- template-version: 6 -->\n' > "$WORK/bare.md"
ev="$(run "$WORK/bare.md" feature | awk -F'\t' '$1=="sections"{print $3}')"
case "$ev" in "heading absent ("*"):"*) ok "gap 1: the absent list carries a count prefix" ;; *) bad "gap 1: no count prefix in '$ev'" ;; esac
case "$ev" in *"Codebase Context"*) ok "gap 1: the LAST feature.yml label survives (no 160-byte cut)" ;; *) bad "gap 1: the absent list is still truncated: '$ev'" ;; esac
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

# --- gap 3: role detection by id then label, E2E before integration, no --e2e-label. ---
mktpl() {  # mktpl <out> <fields as "id|label|required" ...>
  local out="$1"; shift; { echo 'body:'; for f in "$@"; do IFS='|' read -r id lab req <<EOF
$f
EOF
  printf '  - type: textarea\n    id: %s\n    attributes:\n      label: %s\n    validations:\n      required: %s\n' "$id" "$lab" "$req"; done; } > "$out"; }
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
o="$(lbldoc "protocol,feature" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "a missing doc keeps the compiled-in default (protocol is not in it)" fail "${o%%	*}"
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/nope.md")"
expect "and the default still admits its own areas" pass "${o%%	*}"
printf '# Labels\n\nno table here\n' > "$WORK/proj/docs/guides/empty.md"
o="$(lbldoc "components,feature" --labels-doc "$WORK/proj/docs/guides/empty.md")"
expect "a PRESENT doc with no area table is referred, never silently judged on the default" referred "${o%%	*}"
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
printf '%s\n' "$out" | awk -F'\t' '$1 == "sections"' | grep -q '##' \
  && ok "and the sections evidence names the heading level it keyed on" || bad "sections evidence does not name the ## level"
expect "and GWT is judged on its content, not referred for a missing section" pass "$(outcome "$out" gwt)"
# Not loosened: a section that IS absent at ## still fails, by name.
grep -v '^## Documentation impact' "$WORK/hh2.md" > "$WORK/hh2-missing.md"
out="$(run "$WORK/hh2-missing.md" feature)"
expect "a genuinely absent section at ## still FAILS" fail "$(outcome "$out" sections)"
printf '%s\n' "$out" | awk -F'\t' '$1 == "sections"' | grep -q 'Documentation impact' \
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
printf '%s' "$helptext" | grep -q 'referred' \
  && ok "--help describes the current referred-not-na rule" || bad "--help header is stale"
printf '%s' "$helptext" | grep -q -- '--dump-fields' \
  && ok "--help documents every flag it accepts" || bad "--help omits a flag"

echo
echo "check-ticket-mechanics tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
