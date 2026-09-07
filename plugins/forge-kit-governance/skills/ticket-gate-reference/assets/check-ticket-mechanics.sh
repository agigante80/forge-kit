#!/usr/bin/env bash
# check-ticket-mechanics-version: 4
#
# Step 3A's mechanical checks, as a script rather than as prose for the agent to read (#149).
#
# WHAT IT MUST NEVER DO: decide a verdict. It emits one row per check and nothing else. Every
# semantic question stays with the critic in Step 3B. Its heuristics are deliberately NARROWER
# than the canonical rules in ticket-standards.md, so where it cannot rule mechanically it emits
# `referred`. A check that failed outright on a heuristic miss would reject doc-compliant
# tickets, which is strictly worse than the prose it replaced.
#
# EVERYTHING TEMPLATE-SHAPED IS DERIVED, NEVER HARDCODED. The six work templates do not share a
# section set: `security`, `design` and `infrastructure` carry no unit-test or E2E section at
# all, and `bug` calls it "E2E tests" where `feature` says "E2E test scenarios". Hardcoding
# feature.yml's names made four templates fail on a perfectly compliant ticket.
#
# A ROLE THE TEMPLATE DOES NOT CARRY IS `referred`, NEVER `na`, and so is an OPTIONAL section
# left empty. `na` means a check did not apply and nothing looks at it again, so using it for
# either case makes a rule evaporate silently: a project template that renames its sections, or
# marks E2E optional, would otherwise score a PASS with those bars unjudged by anyone.
# Only check 1 emits `na`, for a project with no versioned templates at all.
#
# Usage:
#   check-ticket-mechanics.sh --body FILE --template FILE \
#     --tpl-version N --current-tpl-version N --labels "a,b" \
#     [--area-labels "..."] [--type-labels "..."]
#
# Emits TSV to stdout: <check>\t<outcome>\t<evidence>, outcome in pass|fail|warn|na|referred.
# Exit 0 whenever the checks ran, so a FAIL is data, and so is a version it cannot parse. Exit
# non-zero ONLY when it cannot read the body or the template at all: the gate turns that into
# every check referred, so anything narrower must be a row instead.
#
# --dump-fields prints the parsed <label>\t<required> table and exits, so a test can drive the
# real parser rather than a copy of it.

set -uo pipefail

BODY=""; TEMPLATE=""; TPL_VERSION=""; CURRENT_TPL_VERSION=""; LABELS=""; DUMP_FIELDS=0
# The canonical taxonomy is docs/guides/labels.md. `infrastructure` and `design` are TYPE
# labels there, not areas, and `frontend` is not a declared label at all. Overridable because
# labels.md documents adding project-specific area labels.
AREA_LABELS="api privacy web mobile backend database"
TYPE_LABELS="bug enhancement feature security infrastructure design documentation testing"

die() { printf 'check-ticket-mechanics: %s\n' "$1" >&2; exit 2; }
# A recognised flag as the LAST argument leaves nothing to consume: `shift 2` then fails
# silently and the loop spins forever. A hang is worse than a crash, so this refuses instead.
need_value() { [ "$1" -ge 2 ] || die "$2 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --body)                need_value $# "$1"; BODY="$2"; shift 2 ;;
    --template)            need_value $# "$1"; TEMPLATE="$2"; shift 2 ;;
    --tpl-version)         need_value $# "$1"; TPL_VERSION="$2"; shift 2 ;;
    --current-tpl-version) need_value $# "$1"; CURRENT_TPL_VERSION="$2"; shift 2 ;;
    --labels)              need_value $# "$1"; LABELS="$2"; shift 2 ;;
    --area-labels)         need_value $# "$1"; AREA_LABELS="$2"; shift 2 ;;
    --type-labels)         need_value $# "$1"; TYPE_LABELS="$2"; shift 2 ;;
    --dump-fields)         DUMP_FIELDS=1; shift ;;
    -h|--help)             sed -n '2,34p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$BODY" ]     || die "--body is required"
[ -f "$BODY" ]     || die "body file not found: $BODY"
[ -n "$TEMPLATE" ] || die "--template is required"
[ -f "$TEMPLATE" ] || die "template file not found: $TEMPLATE"

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Evidence is untrusted body text. A newline in it would emit a phantom row and a tab would
# shift a field, so the row separator is stripped from the payload rather than trusted.
row() {
  local ev
  ev="$(printf '%s' "$3" | tr '\n\t' '  ' | cut -c1-160)"
  printf '%s\t%s\t%s\n' "$1" "$2" "$ev"
}

# Everything under a `### <label>` heading, up to the next heading. Compared literally, never
# as a regex, because labels carry `/`, `&` and parentheses.
section_of() {
  awk -v want="$1" '
    /^### / { cur = substr($0, 5); sub(/[ \t]+$/, "", cur); inside = (cur == want); next }
    inside { print }
  ' "$BODY"
}

# GitHub renders an unfilled OPTIONAL textarea as `_No response_`. That is presence without
# content, and it is legitimate on a field the template marks `required: false`.
has_content() {
  local squashed
  squashed="$(printf '%s' "$1" | tr -d '[:space:]')"
  [ -n "$squashed" ] && [ "$squashed" != "_Noresponse_" ]
}

first_line() { printf '%s' "$1" | grep -m1 -v '^[[:space:]]*$' | cut -c1-120; }

# Emits `<label>\t<required>` per rendered field. Field labels sit at exactly six spaces and
# field-level `required` at six; a checkboxes OPTION nests deeper and carries a leading dash,
# which is what keeps option text out of the section list.
template_fields() {
  awk '
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ {
      if (label != "") { print label "\t" (req == "true" ? "yes" : "no") }
      t = $0; sub(/^.*type:[[:space:]]*/, "", t); gsub(/[[:space:]]/, "", t)
      type = t; label = ""; req = "false"; next
    }
    /^      label: / { if (type != "markdown" && label == "") { l = substr($0, 14); sub(/[ \t]+$/, "", l); label = l } }
    /^      required: / { r = $0; sub(/^.*required:[[:space:]]*/, "", r); gsub(/[[:space:]]/, "", r); req = r }
    /^          required: true/ { req = "true" }   # a checkboxes group with a required option
    END { if (label != "") { print label "\t" (req == "true" ? "yes" : "no") } }
  ' "$TEMPLATE"
}

TEMPLATE_FIELDS="$(template_fields)"
# A template that parses to nothing is unusable input, not a body that passes every check. The
# first version reported `sections pass` here, a fail-open on the one check that reads it.
[ -n "$TEMPLATE_FIELDS" ] || die "no fields parsed from template: $TEMPLATE"
[ "$DUMP_FIELDS" -eq 0 ] || { printf '%s\n' "$TEMPLATE_FIELDS"; exit 0; }

# Which rendered section plays each role, by label shape rather than by a fixed name.
#
# AN UNRESOLVED ROLE IS `referred`, NEVER `na`. The script cannot tell "this template does not
# ask for E2E specs" from "this template calls it something my regex misses", and treating the
# second as `na` is a fail-open: a project template naming its sections differently would score
# every check `na` and the gate would PASS having checked nothing. `referred` costs a little
# noise on the three templates that genuinely carry no test sections, and `referred` never
# blocks, so the trade is one the critic can absorb and a silent pass is not.
role_label() {
  printf '%s\n' "$TEMPLATE_FIELDS" | cut -f1 | grep -m1 -iE "$1" || true
}
role_required() {
  [ -n "$1" ] || return 1
  printf '%s\n' "$TEMPLATE_FIELDS" | awk -F'\t' -v l="$1" '$1 == l { print $2; exit }' | grep -q yes
}
# An OPTIONAL section left empty is what GitHub renders for a field the template did not demand,
# so it is not a FAILURE. It is not `na` either: the rule still binds and only the critic can say
# whether it is met, so an unfilled optional section is REFERRED.
empty_outcome() { if role_required "$1"; then echo fail; else echo referred; fi; }
SCENARIOS_LABEL="$(role_label 'given.*when.*then')"
UNIT_LABEL="$(role_label 'unit test')"
E2E_LABEL="$(role_label 'e2e|end.to.end')"
DOCS_LABEL="$(role_label 'documentation impact')"

# --- check 1: template version currency -------------------------------------------------
# Two shapes are deliberately NOT failures, or a re-run could never converge: a marker NEWER
# than the project's templates (a fork ahead of us) warns, and no versioned templates at all
# is N/A. Only missing-or-older fails, and 0c auto-synthesis is its repair path.
if [ -z "$CURRENT_TPL_VERSION" ]; then
  row template_version na "no versioned templates in this project"
elif ! is_num "$CURRENT_TPL_VERSION"; then
  # A fail ROW, not a die: exiting here would give the gate "could not run", which it turns into
  # all six checks referred, so one stray match in 0a's template scan would silently disable
  # every mechanical check. The sibling --tpl-version case is a row for the same reason.
  row template_version fail "current template version is not a number: $CURRENT_TPL_VERSION"
elif [ -z "$TPL_VERSION" ]; then
  row template_version fail "no template-version marker in body (current: v$CURRENT_TPL_VERSION)"
elif ! is_num "$TPL_VERSION"; then
  # Never fall through to pass: a body whose marker cannot be read is exactly the stale body
  # 0c exists to repair, and a numeric comparison on a non-number silently skips both arms.
  row template_version fail "template-version marker is not a number: $TPL_VERSION"
elif [ "$TPL_VERSION" -gt "$CURRENT_TPL_VERSION" ]; then
  row template_version warn "body v$TPL_VERSION is NEWER than templates v$CURRENT_TPL_VERSION; update the templates"
elif [ "$TPL_VERSION" -lt "$CURRENT_TPL_VERSION" ]; then
  row template_version fail "body v$TPL_VERSION is older than templates v$CURRENT_TPL_VERSION"
else
  row template_version pass "template-version: $TPL_VERSION"
fi

# --- check 2: labels --------------------------------------------------------------------
# Records Step 0b's rule exactly: an area label is required, a type label warns only. This
# check never demands a label no step requires.
has_label_from() {
  local w l
  for w in $1; do
    for l in $(printf '%s' "$LABELS" | tr ',\n' '  '); do
      [ "$l" = "$w" ] && return 0
    done
  done
  return 1
}
if ! has_label_from "$AREA_LABELS"; then
  row labels fail "no area label (one of: ${AREA_LABELS// /, })"
elif ! has_label_from "$TYPE_LABELS"; then
  row labels warn "no type label (one of: ${TYPE_LABELS// /, })"
else
  row labels pass "labels: $LABELS"
fi

# --- check 3: required sections present -------------------------------------------------
# Every section the template carries needs a heading. Only a field the template marks
# `required: true` needs CONTENT: GitHub renders an unfilled optional field as `_No response_`,
# and faulting that failed a template-perfect ticket in the first version.
missing=""; empty=""
while IFS="$(printf '\t')" read -r label required; do
  [ -n "$label" ] || continue
  if ! grep -qxF "### $label" "$BODY"; then
    missing="$missing${missing:+; }$label"
  elif [ "$required" = "yes" ] && ! has_content "$(section_of "$label")"; then
    empty="$empty${empty:+; }$label"
  fi
done <<EOF
$TEMPLATE_FIELDS
EOF
if [ -n "$missing" ]; then
  row sections fail "heading absent: $missing"
elif [ -n "$empty" ]; then
  row sections fail "required heading present but empty: $empty"
else
  row sections pass "every template section present, every required one filled"
fi

# --- check 4: GWT structure (rule 1, the checkable half) --------------------------------
# WHICH conditions are independent is the critic's judgment, never this check's.
if [ -z "$SCENARIOS_LABEL" ]; then
  row gwt referred "no section matched Given/When/Then; the critic must judge rule 1 unaided"
else
  SCENARIOS="$(section_of "$SCENARIOS_LABEL")"
  if ! has_content "$SCENARIOS"; then
    row gwt "$(empty_outcome "$SCENARIOS_LABEL")" "no content in $SCENARIOS_LABEL"
  else
    pos_count=$(printf '%s\n' "$SCENARIOS" | grep -cE '^[[:space:]]*\**Positive\**[[:space:]]*$')
    neg_count=$(printf '%s\n' "$SCENARIOS" | grep -cE '^[[:space:]]*\**Negative\**[[:space:]]*$')
    if [ "$pos_count" -eq 0 ] || [ "$neg_count" -eq 0 ]; then
      row gwt fail "needs at least one Positive and one Negative block (found $pos_count positive, $neg_count negative)"
    else
      multi_when="$(printf '%s\n' "$SCENARIOS" | awk '
        /^[[:space:]]*\**(Positive|Negative)\**[[:space:]]*$/ {
          if (block != "" && whens != 1) { print block ": " whens " When lines" }
          block = $0; gsub(/[^A-Za-z]/, "", block); whens = 0; next
        }
        block != "" && /^[[:space:]]*[-*][[:space:]]*\**When\**[[:space:]]*:/ { whens++ }
        END { if (block != "" && whens != 1) { print block ": " whens " When lines" } }
      ' | head -3 | paste -sd'; ' -)"
      if [ -n "$multi_when" ]; then
        row gwt fail "each scenario block needs exactly one When ($multi_when)"
      else
        # EVERY negative block is judged, not just the first: a ticket with three conditions
        # would otherwise have two of its negatives unchecked. A digit-bearing status, a
        # quoted message, or an UPPER_SNAKE identifier is specific enough; anything else is
        # REFERRED, never failed, because this heuristic is narrower than rule 1's quality
        # bar on purpose and must not reject a message the canonical doc allows.
        vague="$(printf '%s\n' "$SCENARIOS" | awk '
          /^[[:space:]]*\**Negative\**[[:space:]]*$/ { inneg = 1; seen = 0; next }
          /^[[:space:]]*\**Positive\**[[:space:]]*$/ { inneg = 0; next }
          inneg && !seen && /^[[:space:]]*[-*][[:space:]]*\**Then\**[[:space:]]*:/ { seen = 1; print }
        ' | grep -vE '[0-9]|"[^"]+"|'"'"'[^'"'"']+'"'"'|[A-Z][A-Z0-9_]{2,}' | head -1)"
        missing_then=$(printf '%s\n' "$SCENARIOS" | awk '
          /^[[:space:]]*\**Negative\**[[:space:]]*$/ { if (inneg && !seen) n++; inneg = 1; seen = 0; next }
          /^[[:space:]]*\**Positive\**[[:space:]]*$/ { if (inneg && !seen) n++; inneg = 0; next }
          inneg && /^[[:space:]]*[-*][[:space:]]*\**Then\**[[:space:]]*:/ { seen = 1 }
          END { if (inneg && !seen) n++; print n+0 }
        ')
        if [ "$missing_then" -gt 0 ]; then
          row gwt fail "a Negative block has no Then line"
        elif [ -n "$vague" ]; then
          row gwt referred "a negative Then is not mechanically specific: $(first_line "$vague")"
        else
          row gwt pass "$pos_count positive and $neg_count negative blocks, each Then specific"
        fi
      fi
    fi
  fi
fi

# --- check 5: test specs concrete -------------------------------------------------------
# Unit and E2E get their own rows. Sharing one row let a `referred` unit result short-circuit
# the chain, so an unusable E2E section went unreported entirely.
#
# A path is a backticked token containing a slash, or a bare filename with a known extension.
# Deliberately NOT "anything containing a slash": the literal `N/A` matches that, so an N/A
# claim read as a named path and PASSED a check that must refer it. So did prose like "and/or".
looks_na()   { printf '%s' "$1" | grep -qiE '(^|[^a-z])n/?a([^a-z]|$)|not applicable'; }
names_path() { printf '%s' "$1" | grep -qE '`[^`]*/[^`]*`|[A-Za-z0-9_-]+\.(ts|tsx|js|jsx|mjs|cjs|py|go|rb|rs|java|kt|php|cs|sh|sql|md|yml|yaml)([^A-Za-z0-9]|$)'; }
long_enough() { [ "$(printf '%s' "$1" | tr -d '[:space:]' | wc -c)" -gt 12 ]; }

if [ -z "$UNIT_LABEL" ]; then
  row unit_tests referred "no section matched unit tests; the critic must judge rule 2 unaided"
else
  UNIT="$(section_of "$UNIT_LABEL")"
  # N/A is tested BEFORE a path, here and in the E2E branch below, so the two cannot disagree:
  # an N/A that happens to cite a path is still an N/A claim for the critic to rule on.
  if ! has_content "$UNIT"; then
    row unit_tests "$(empty_outcome "$UNIT_LABEL")" "no content in $UNIT_LABEL"
  elif looks_na "$UNIT"; then
    row unit_tests referred "unit tests claim N/A; legitimate only where rule 2 is out of scope: $(first_line "$UNIT")"
  elif names_path "$UNIT"; then
    row unit_tests pass "$(first_line "$UNIT")"
  else
    row unit_tests fail "unit tests name no file path: $(first_line "$UNIT")"
  fi
fi

if [ -z "$E2E_LABEL" ]; then
  row e2e_tests referred "no section matched E2E; the critic must judge rule 3 unaided"
else
  E2E="$(section_of "$E2E_LABEL")"
  if ! has_content "$E2E"; then
    row e2e_tests "$(empty_outcome "$E2E_LABEL")" "no content in $E2E_LABEL"
  elif looks_na "$E2E"; then
    # Whether the ticket touches UI at all (rule 3), is Step 3B's call, so a reasoned N/A is
    # referred rather than passed, and an unreasoned one fails.
    if long_enough "$E2E"; then
      row e2e_tests referred "E2E N/A with a reason; rule 3 says a UI-touching ticket cannot claim it: $(first_line "$E2E")"
    else
      row e2e_tests fail "E2E N/A with no reason given"
    fi
  elif names_path "$E2E"; then
    row e2e_tests pass "$(first_line "$E2E")"
  else
    row e2e_tests fail "E2E names no file path and makes no N/A claim: $(first_line "$E2E")"
  fi
fi

# --- check 6: documentation impact present ----------------------------------------------
# Presence only. Whether a "none" reason HOLDS is rule 7, judged by the critic.
if [ -z "$DOCS_LABEL" ]; then
  row docs_impact referred "no section matched documentation impact; rule 7 is the critic's"
else
  DOCS="$(section_of "$DOCS_LABEL")"
  if ! has_content "$DOCS"; then
    row docs_impact "$(empty_outcome "$DOCS_LABEL")" "no content in $DOCS_LABEL"
  elif names_path "$DOCS"; then
    row docs_impact pass "$(first_line "$DOCS")"
  elif printf '%s' "$DOCS" | grep -qiE 'none|no doc'; then
    if long_enough "$DOCS"; then
      row docs_impact referred "claims no docs needed; rule 7 applies to every work ticket: $(first_line "$DOCS")"
    else
      row docs_impact fail "claims no docs needed with no reason given"
    fi
  else
    row docs_impact fail "names no docs and makes no explicit none claim: $(first_line "$DOCS")"
  fi
fi

exit 0
