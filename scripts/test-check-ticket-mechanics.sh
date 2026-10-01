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
wc_ev() { gwt_ev "$(run "$(mkbody feature "$1" "$(printf '%s' "$2")")" feature)"; }
P1='Positive\n- Given: a\n- When: b\n- Then: c'
N1='Negative\n- Given: d\n- When: e\n- Then: 401 AUTH_FAILED'
N2='Negative\n- Given: d\n- When: e\n- When: ee\n- Then: 401 AUTH_FAILED'
ev="$(wc_ev wc1.md "$(printf "$P1\n\nNegative (the Positive path is blocked)\n- Given: d\n- When: e\n- When: ee\n- Then: 401 AUTH_FAILED")")"
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
ev="$(wc_ev wc5.md "$(printf "Positive (the Negative path is not taken)\n- Given: a\n- When: b\n- When: bb\n- Then: c\n\n$N1")")"
case "$ev" in *"(Positive: 2 When lines)"*"Negative: "*|*"Negative: "*) bad "#359: a Positive label naming Negative was misnamed: $ev" ;; *"(Positive: 2 When lines)"*) ok "#359: a Positive block whose label names Negative keeps its own name" ;; *) bad "#359: mirror case evidence wrong: $ev" ;; esac
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
case "$(gwt_ev "$o")" in *"claim N/A"*"rule 1"*) ok "#241: and the evidence is in check 5's shape" ;; *) bad "#241: evidence shape: $(gwt_ev "$o")" ;; esac
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

# #359 mutant: restore the substring polarity test on a copy; the labelled-Negative fixture must flip.
grep -q 'block = (\$0 ~ neg ? "Negative" : "Positive")' "$SCRIPT" && ok "mutant ledger: the script carries the anchored polarity test (#359)" || bad "mutant ledger: #359 expression not found"
sed 's/(\$0 ~ neg ? "Negative" : "Positive")/(index($0, "Positive") ? "Positive" : "Negative")/' "$SCRIPT" > "$MUT"
ev="$(bash "$MUT" --body "$WORK/wc1.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels x 2>/dev/null | awk -F'\t' '$1=="gwt"{print $3}')"
case "$ev" in *"(Positive: 2 When lines)"*) ok "mutant: the substring test names the labelled Negative Positive (the #359 companion can fail)" ;; *) bad "mutant: substring test not detected: $ev" ;; esac

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
for tpl in bug feature security infrastructure design; do
  label_ok "$tpl" "$WORK/ph-mut.py" \
    && bad "#383: $tpl: MUTANT survived: an always-Unit-tests ph.py still passes label_ok" \
    || ok "#383: $tpl: MUTANT: an always-Unit-tests ph.py fails label_ok"
done
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
doc_pin() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF "$DOC_PHRASE"; }
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
grep -qF 'The absolute path `$PWD/$TPL_DIR/<type>.yml`' "$GATE" && ok "#361: the 0c-iii dispatch names the template path" || bad "#361: the dispatch does not name the template path"
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
case "$(sec_ev "$o")" in *"; gate-filled, not charged: Codebase Context") ok "#304: and its evidence ends naming Codebase Context as gate-filled" ;; *) bad "#304: evidence does not name the gate-filled field: $(sec_ev "$o")" ;; esac
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
expect "#304: a start marker with a trailing CR still ends the section" fail "$(outcome "$(run "$WORK/g304-r2cr.md" feature)" docs_impact)"
sed 's/gate-context:/brief-decision:/' "$WORK/g304-r2.md" > "$WORK/g304-r2brief.md"
expect "#304: a region of any prefix ends the section (brief-*)" fail "$(outcome "$(run "$WORK/g304-r2brief.md" feature)" docs_impact)"
B="$(mkbody feature "g304-p.md" "" "" "" 'Updates `docs/guides/labels.md`')"
{ sed 's/^### /## /' "$B" | no_cc; printf '%s\n' "$REGION"; } > "$WORK/g304-p2.md"
expect "#304: the author's own docs line is judged and quoted, not the region's" "$(printf 'pass\tUpdates `docs/guides/labels.md`')" "$(docs_row "$(run "$WORK/g304-p2.md" feature)")"
# Mutant 1: the gate-filled clause deleted (one line altered); the positive case must flip.
CL1="'\$4 == \"yes\" && \$2 == \"no\" { print \$1 }'"
grep -qF "$CL1" "$SCRIPT" && ok "mutant ledger: the script carries the gate-filled clause (#304)" || bad "mutant ledger: #304 gate-filled clause not found"
sed "s/'\$4 == \"yes\" && \$2 == \"no\" { print \$1 }'/'0 { print \$1 }'/" "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the gate-filled mutant did not apply"
ev="$(sec_ev "$(bash "$MUT" --body "$WORK/g304-nocc.md" --template "$TPLDIR/bug.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,bug 2>/dev/null)")"
expect "mutant: with the gate-filled clause deleted, Codebase Context is charged (the #304 case can fail)" "heading absent (1): Codebase Context" "$ev"
# Mutant 2: the region-start boundary removed from section_of(); the region case must flip to pass.
CL2='inside && l ~ /^<!-- [^ \t]+:start -->$/ { inside = 0 }'
grep -qF "$CL2" "$SCRIPT" && ok "mutant ledger: section_of() carries the region boundary (#304)" || bad "mutant ledger: #304 region boundary not found"
grep -vF "$CL2" "$SCRIPT" > "$MUT"
cmp -s "$SCRIPT" "$MUT" && bad "#304: the boundary mutant did not apply"
o="$(bash "$MUT" --body "$WORK/g304-r2.md" --template "$TPLDIR/feature.yml" --tpl-version 6 --current-tpl-version 6 --labels backend,feature 2>/dev/null)"
expect "mutant: with the region boundary removed, the region's path passes docs_impact (the #304 case can fail)" pass "$(outcome "$o" docs_impact)"

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
