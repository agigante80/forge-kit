#!/usr/bin/env bash
# forge-gate-mechanics-version: 3
#
# Run forge-kit's mechanical ticket checks against a live issue, with no agent harness (#182).
#
#   forge-gate-mechanics.sh <issue-number> [--repo OWNER/NAME] [--format tsv|human]
#                           [--template FILE] [--type NAME]
#
#   exit 0  the checks ran and none of them failed
#   exit 1  at least one check FAILED
#   exit 2  the checks could not run
#
# WHY THIS EXISTS. Every mechanical check this kit has is already plain shell with its own contract
# suite, and `forge-lib.sh` already fetches an issue from GitHub or Forgejo. What was missing was the
# glue between them. This is that glue and nothing else: it fetches, resolves a template, and hands both to check-ticket-mechanics.sh.
#
# IT DOES NOT DECIDE A VERDICT, and that is the most important line in this file. Step 3A is the
# MECHANICAL half of the ticket gate. The critic in Step 3B is a judgement no shell script makes,
# and every `referred` row exists because a heuristic here is deliberately NARROWER than the rule in
# docs/guides/ticket-standards.md. A summary that said PASS would look like the real gate while
# having skipped the half that reads the ticket, which is worse than not offering this at all. So
# the summary counts outcomes and stops, and `referred` is reported as its own number rather than
# folded into the good news.
#
# WHAT IT NEEDS BESIDE IT. `forge-lib.sh` and `check-ticket-mechanics.sh`. In a forge-adapt install
# both land in the project's `scripts/`, so adjacency holds; from a source checkout they sit in two
# different plugin groups, so the fallbacks below reach across. Absent either one, this REFUSES:
# a check that cannot run must never report clean, which is the posture every guard here takes.
#
# NO DEPENDENCY ON THE HARNESS CLI ANYWHERE IN THIS PATH. That is the entire point of the script,
# and its contract test asserts it by scanning this file as well as by running it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Beside this script first, which is the shape a forge-adapt install produces (every asset lands in
# the project's scripts/). The fallback reaches across plugin groups, which is the shape of a source
# checkout, where forge-lib.sh lives in forge-kit-devops and this does not.
find_beside() {  # find_beside <filename> <source-tree-relative-fallback>
  if [ -f "$HERE/$1" ]; then printf '%s\n' "$HERE/$1"; return 0; fi
  if [ -f "$HERE/../../../../$2" ]; then
    printf '%s/%s\n' "$(cd "$HERE/../../../../$(dirname "$2")" && pwd)" "$(basename "$2")"
    return 0
  fi
  return 1
}

LIB="${FORGE_LIB:-}"
[ -n "$LIB" ] || LIB=$(find_beside forge-lib.sh forge-kit-devops/skills/forge-host/assets/forge-lib.sh) || {
  echo "forge-gate-mechanics: forge-lib.sh not found beside this script." >&2
  echo "  It is the forge transport, so nothing can be fetched without it. Copy it alongside," >&2
  echo "  or point FORGE_LIB at it. Refusing rather than reporting clean." >&2
  exit 2
}
MECH=$(find_beside check-ticket-mechanics.sh forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh) || {
  echo "forge-gate-mechanics: check-ticket-mechanics.sh not found beside this script." >&2
  echo "  It owns every check; this script only feeds it. Refusing." >&2
  exit 2
}
# shellcheck source=/dev/null
. "$LIB"

NUM=""; REPO_OVERRIDE=""; FORMAT=human; TEMPLATE=""; TYPE=""
die() { printf 'forge-gate-mechanics: %s\n' "$1" >&2; exit 2; }
need() { [ "$1" -ge 2 ] || die "$2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     need $# "$1"; REPO_OVERRIDE="$2"; shift 2 ;;
    --format)   need $# "$1"; FORMAT="$2"; shift 2 ;;
    --template) need $# "$1"; TEMPLATE="$2"; shift 2 ;;
    --type)     need $# "$1"; TYPE="$2"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    -*)         die "unknown argument: $1" ;;
    *)          NUM="$1"; shift ;;
  esac
done
[ -n "$NUM" ] || die "an issue number is required"
case "$FORMAT" in tsv|human) : ;; *) die "--format takes tsv or human" ;; esac
[ -n "$REPO_OVERRIDE" ] && FORGE_REPO="$REPO_OVERRIDE" && export FORGE_REPO

command -v jq >/dev/null 2>&1 || die "jq is required (forge-lib.sh parses the forge's JSON with it)"

# THE TEMPLATE DIRECTORY ORDER IS SHARED, NOT INVENTED HERE. Host-grouped, lowercase variants are
# forge-adapt v34-and-earlier installs (#61). scripts/check-template-dir-order.sh fails the build if
# this copy disagrees with the others, which is why it is written as one run of five.
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .forgejo/issue_template \
                   .gitea/ISSUE_TEMPLATE .gitea/issue_template .github/ISSUE_TEMPLATE; do
  [ -d "$d" ] && { echo "$d"; break; }; done)
[ -n "$TPL_DIR" ] || die "no issue-template directory here. Looked for the five host-grouped names; run this from the project root."

# The CURRENT standard is the highest marker across ALL work templates, never feature.yml alone:
# the six templates do not share a section set and reading one mis-fires for every other type.
CURRENT_TPL_VER=$(grep -ho 'template-version: [0-9]*' "$TPL_DIR"/*.yml 2>/dev/null \
                    | grep -o '[0-9]*' | sort -un | tail -1)
[ -n "$CURRENT_TPL_VER" ] || die "no template-version marker in $TPL_DIR, so there is no standard to check against"

issue_json=$(forge_issue_view "$NUM") || die "could not fetch issue #$NUM"
body=$(printf '%s' "$issue_json" | jq -r '.body // ""')
labels=$(printf '%s' "$issue_json" | jq -r '[.labels[]?.name] | join(",")')
[ -n "$body" ] || die "issue #$NUM has an empty body"

BODY_FILE="$(mktemp)"; trap 'rm -f "$BODY_FILE"' EXIT
printf '%s' "$body" > "$BODY_FILE"

# The ticket's OWN version, from the marker the template plants in the body. Absent is not an error:
# check 1 exists to rule on exactly that, and guessing here would take the decision away from it.
TPL_VER=$(grep -o 'template-version: [0-9]*' "$BODY_FILE" | grep -o '[0-9]*' | head -1)

if [ -z "$TEMPLATE" ]; then
  [ -n "$TYPE" ] || for t in bug security infrastructure design feature; do
    case ",$labels," in *",$t,"*) TYPE="$t"; break ;; esac
  done
  [ -n "$TYPE" ] || TYPE=feature
  TEMPLATE="$TPL_DIR/$TYPE.yml"
  [ -f "$TEMPLATE" ] || die "no template for type '$TYPE' at $TEMPLATE (pass --template to choose one)"
fi

# WAS THIS BODY EVER TEMPLATE-SHAPED? (#184) Two signals, and the message claims exactly what they
# support and no more: no `template-version` marker, and no TEMPLATE LABEL as a heading at either
# level (the checker reads a section at `##` or `###` since #190, so a `##` body carrying the
# template's labels is JUDGED, not excused; a body whose `##` headings are the author's own words
# is not recognised and gets this notice, as before). A body with neither signal was written by
# hand rather than submitted through the form, so EVERY section check will fail for one reason,
# and saying it seven times buries the one fact worth knowing.
#
# It is not a defect in the ticket and not a defect in the checks. The gate's own Step 0c
# SYNTHESISES the missing sections and writes the enriched body back to the forge BEFORE Step 3A
# runs, so inside a gate run the checks always see template-shaped input. This script does not
# synthesise, deliberately: that step generates prose and needs a model.
SHAPED=1
if [ -z "$TPL_VER" ]; then
  SHAPED=0
  while IFS="$(printf '\t')" read -r label _; do
    [ -n "$label" ] && grep -qxF -e "## $label" -e "### $label" "$BODY_FILE" && { SHAPED=1; break; }
  done <<FIELDS
$("$MECH" --body "$BODY_FILE" --template "$TEMPLATE" --dump-fields 2>/dev/null)
FIELDS
fi

rows=$("$MECH" --body "$BODY_FILE" --template "$TEMPLATE" \
        ${TPL_VER:+--tpl-version "$TPL_VER"} --current-tpl-version "$CURRENT_TPL_VER" \
        --labels "$labels") || die "the checker could not read the body or the template"

if [ "$FORMAT" = tsv ]; then
  printf '%s\n' "$rows"
  exit 0
fi

if [ "$SHAPED" -eq 0 ]; then
  echo "never template-shaped: issue #$NUM has no template-version marker and none of the template's headings,"
  echo "  so it was never submitted through the issue form. Every section check below fails for"
  echo "  that ONE reason, which is not a defect in the ticket and not a defect in the checks."
  echo "  The full gate handles this at Step 0c: it synthesises the missing sections and writes"
  echo "  the enriched body back before the mechanics run. This script does not synthesise,"
  echo "  because that step generates prose and needs a model."
  echo ""
fi

printf '%s\n' "$rows" | awk -F'\t' '{ printf "%-26s %-9s %s\n", $1, $2, $3 }'

count() { printf '%s\n' "$rows" | awk -F'\t' -v w="$1" '$2 == w { n++ } END { print n + 0 }'; }
p=$(count pass); f=$(count fail); w=$(count warn); n=$(count na); r=$(count referred)
echo ""
echo "forge-gate-mechanics: issue #$NUM against $TEMPLATE (ticket v${TPL_VER:-none}, current v$CURRENT_TPL_VER)"
echo "  $p pass, $f fail, $w warn, $n n/a, $r REFERRED"
echo ""
if [ "$SHAPED" -eq 0 ]; then
  echo ""
  echo "  Exit 0 despite the failures: see the note above. Re-run after the gate has synthesised"
  echo "  this ticket, or on a ticket filed through the form, to get a meaningful result."
fi
echo ""
echo "  This is Step 3A, the mechanical half, and it is not a verdict. The $r referred check(s)"
echo "  need a human or an agent, and the whole critical review (Step 3B) has not run at all."
echo "  The rules those checks come from are docs/guides/ticket-standards.md."
[ "$SHAPED" -eq 0 ] || [ "$f" -eq 0 ]
