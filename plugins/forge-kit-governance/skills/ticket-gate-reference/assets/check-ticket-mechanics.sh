#!/usr/bin/env bash
# check-ticket-mechanics-version: 48
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
# A SECTION IS FOUND AT EITHER HEADING LEVEL, AND ITS BOUNDARY IS A LABEL, NOT A LEVEL (#190). A
# web-form submission renders each field as `### <label>`; `gh issue create --body-file`, a
# first-class filing path, produces whatever the author wrote, usually `## <label>`; and the kit's
# own dep-auditor emits `### Priority` beside `##` sections. Keyed on `### ` alone, a `##` body read
# as five absent sections, five FAILs, where the same body at `###` got two and a referred: a
# heuristic miss that INVERTED the verdict instead of referring it. A first fix detected one level
# per body and let `###` win a mixed one, which inverted the dep-auditor shape exactly the same
# way (found by the gate reviewing the ticket). So there is no level: a label is present at `##`
# or `###`, and its section runs to the next heading at ITS OWN level or the next heading at
# either level whose text is a template label, whichever comes first. A `###` subsection inside a
# `##` section is content, because it is not a label; a `### Priority` beside it is a boundary,
# because it is. A `###` body is untouched: every boundary it had is still one. Nothing about what
# a section must CONTAIN moved.
#
# FOUR SHAPES FOUND BY RUNNING THIS ON ANOTHER PROJECT (#205). The evidence row was cut at 160
# bytes, so on a template whose joined label list is 248 bytes the absent-sections list lost its
# tail and the gate read "Required reviews" as never absent: the bound is now 1000 and the list
# carries a count prefix, so any future truncation is visible. A Positive/Negative marker with a
# qualifier (`Positive (happy path)`, `**Negative** note`, `Positive:`) read as no block: ONE marker
# regex, defined once and shared by every site, admits those and refuses a prose line that merely
# starts with the word, because admitting that would produce a block with no When and a false
# FAIL. A template that renames its E2E section (id and label both) to "Integration / subprocess
# test scenarios" got `referred` forever: roles are now found by pattern in priority order (E2E
# before integration), each tried against the field's `id:` before its label, so an E2E-named
# section outranks an integration-named one whatever the template order. And a template whose
# `value:` or `placeholder:` carries `### ...` sub-headings ended a `###`-level section at the
# first of them, so the kit's own feature.yml failed a compliant web-form body twice: a same-level
# heading now ends a section unless its text is a sub-heading the template places inside THIS
# field, scoped per field; a template label always ends it.
#
# TWO SHAPES CHECK 4 REFERS RATHER THAN FAILS (#233, #241), both found by the gate on this
# repository's own tickets in one night. A ONE-LINE scenario, `- Positive. Given a. When b. Then
# c.` in any of its markups, carries a complete scenario the marker regex cannot read, and v9
# emitted "0 positive, 0 negative": a heuristic miss that inverted the verdict. It is detected by
# a separate test run BEFORE the block count, so the marker regex and every site keyed on it are
# unchanged; widening the regex would have read the line as a block with zero When lines and
# failed it one site later. And a REASONED N/A in the scenarios section, which the canonical doc
# permits where no behaviour delta exists, failed the same way where check 5 had always referred one for
# the unit and E2E sections; it is now tested first, only where no block exists, so an N/A named
# inside a real pair is still a pair, and a bare N/A with no reason still fails.
#
# CHECK 4'S BLOCK POLARITY COMES FROM THE ANCHORED `MARK_NEG` (#359). The When-count evidence names
# a block Negative when its marker line matches `MARK_NEG`, which is `marker_re Negative`, so the
# one `marker_re` that builds `MARK_ANY` and `MARK_POS` decides polarity too. A substring test is
# deliberately not used: it named a Negative block Positive when its label held the word.
#
# TWO RULES KEEP GATE-WRITTEN TEXT OFF THE AUTHOR'S ACCOUNT (#304). A field the TEMPLATE marks
# gate-filled is never charged for an absent heading: the mark is a `description:` line carrying the
# fixed, case-sensitive substring "Auto-populated by ticket-gate", or a `# gate-owned` YAML comment
# on a line of its own at the field's key indent (four spaces, beside `id:`), after the field's
# `- type:` line. A comment above the NEXT `- type:` (two spaces) or a line inside a `value:` or
# `placeholder:` block (eight) is not the mark, since either would exempt the wrong field. It is
# read from the template only, never from body text and never from a field id, and a `required:
# true` field is never exempt, so a template that loses the mark gets the old charge, never a wider
# pass. And the lines of a body REGION of any prefix (forge-lib's grammar, `<!-- <name>:start -->`
# to `<!-- <name>:end -->`, a trailing CR or blank tolerated) are never section content: the gate
# appends its `gate-context` region at the body end, where it read as content of the author's last
# `##` section and its paths satisfied check 6. Reading resumes after the matching end marker, so
# author text below a region is still judged; an unterminated region runs to the end of the body.
# Region text is excluded as if absent, which is no more than an author could do by deleting it,
# and the critic still reads the whole body.
#
# Usage:
#   check-ticket-mechanics.sh --body FILE --template FILE \
#     --tpl-version N --current-tpl-version N --labels "a,b" \
#     [--labels-doc docs/guides/labels.md] [--area-labels "..."] [--type-labels "..."]
#     [--standards-doc docs/guides/ticket-standards.md]
#   check-ticket-mechanics.sh --roles --template FILE   (no --body; see --roles below)
#
# THE AREA SET IS THE PROJECT'S OWN, WHEN IT HAS ONE (#204). `--labels-doc` names the project's
# `docs/guides/labels.md`, and the first column of its `### Area labels` table REPLACES the
# compiled-in nine (one definition, #188: a union would keep forge-kit's areas as areas in every
# project forever). Both callers pass it. An explicit `--area-labels` still wins. A doc that is
# present with no such table refers check 2. A doc that is MISSING (#425) keeps the compiled-in
# nine and says so in the row's evidence, and a ticket label outside both compiled-in sets is
# then REFERRED rather than failed, because without the doc the checker cannot tell a project's
# own area from a priority or host label; only type labels alone, or none, still fail. So a
# missing doc loosens check 2 to a referral, never to a pass.
#
# A CITED SECTION FOLLOWS THE PROJECT'S ALIAS (#557). Four referred rows cite a section of the
# project's ticket-standards doc by its kit title. When that doc renames one and says so with a
# `<!-- citation-alias: "<Title>" = "<Heading>" -->` line, the row names the project's heading
# followed by `(the kit's "<Title>")`, so an author can find the section. `--standards-doc` names
# the doc, default docs/guides/ticket-standards.md in the working directory (the project root, as
# for --labels-doc), and an empty value turns it off. The doc is read with citation-check.sh's
# grammar and rules, which forge-kit-adapt ships and which a parity test pins: the whole line is the
# marker, a fence is a line opening with ``` or ~~~ after any indent and the same character closes
# it, a heading is `#` to `######` with a leading `N. ` and a trailing parenthetical dropped, an
# alias applies only when its target is a heading of the doc and its title is not, and the first
# alias for a title wins. Acknowledgement lines are not read. Only the FIRST citation in a row is
# rewritten, the kit's own, never a quotation in the author text after it, and it is spliced as
# literal text. A missing, unreadable or marker-free doc leaves every row byte for byte as before.
#
# Emits TSV to stdout: <check>\t<outcome>\t<evidence>, outcome in pass|fail|warn|na|referred.
# Exit 0 whenever the checks ran, so a FAIL is data, and so is a version it cannot parse. Exit
# non-zero ONLY when it cannot read the body (not needed by --roles) or the template at all: the gate turns that into
# every check referred, so anything narrower must be a row instead.
#
# --dump-fields prints the parsed <label>\t<required> table and exits, so a test can drive the
# real parser rather than a copy of it.
#
# --headings prints the body's real heading lines, fenced ones left out (#485), and exits. Needs
# --body only; refused with --roles or --dump-fields. forge-gate-mechanics.sh's template-shape test
# reads it, so that test and check 3 share one fence-aware reader instead of two copies of the awk.
#
# --skeleton prints the STATIC checklist parts of a template that a form submission would have carried
# and an API-filed body (forge_issue_create, `gh issue create --body-file`) lacks (#505): per field,
# in template order, `## <label>` and then the `- [ ]` option lines of a checkboxes field, or the
# `value: |` block of a textarea that holds a `- [ ]` line. Everything else prints nothing (inputs,
# dropdowns, a textarea with only a placeholder, bare-stub value blocks, markdown). Without --body
# it prints the template-version marker line (when the template has one) and then the sections.
# With --body F it prints F byte for byte, then ONLY the sections whose heading is missing under
# check 3's own presence rule (`## <label>` or `### <label>` as a whole line of the body_headings
# output: case-sensitive, fence-aware, so a `####` heading is absent) and never a marker, because a
# marker added to a body that has none would make Step 0a skip Step 0c. It writes nothing and adds
# no size policy: the host rejects an oversized body with its own message. Refusals (exit 2, nothing
# on stdout): no `body:` list in the template, a textarea `value:` that is not a `|` or `|-` block,
# a flag combination. Recipe for an API caller, fail-closed (a bare command substitution would
# discard the refusal and file an EMPTY issue):
#   body="$(check-ticket-mechanics.sh --skeleton --template T --body F)" || exit 1
#   forge_issue_create "$title" "$body"
# --classes prints `<class>\t<label>` per template field (#513), see the block that implements it.
#
# --tag-blocks N filters stdin to stdout and exits (#532): the text the GATE composed for a body
# section (Step 0c-iii's scenarios and docs_impact, Step 6's appended items), with EVERY block
# ending its first line `(gate-written, round N)`. A block is a maximal run of non-blank lines, a
# fence line and every line inside a fence counting as non-blank: the same cut forge-lib.sh's
# forge_body_section_append reads, which treats a block as the gate's only when its first line ENDS
# with that tag. A synthesiser writing the tag freehand got that wrong five times in one night
# (tagged only a first line or the Condition lines, left an Assumption paragraph bare, put the tag
# inside the bold markers), and each time the same run's append refused with 108. This makes the
# shape mechanical instead. A first line already ending in a tag is kept byte for byte, whatever
# its round (provenance survives a re-run, so it is idempotent). A tag followed by nothing but
# closing `*` or `_` is moved out of the emphasis to the end, with the blanks before it, so
# `**Condition: x (gate-written, round 0)**` becomes `**Condition: x** (gate-written, round 0)`.
# A tag quoted anywhere else in the line stays where it is and the block still gets its own tag
# at the end: `Assumptions (gate-written, round 0): x` gains ` (gate-written, round N)`.
# A block opening with a fence gets a line of its own holding just the tag, since a tag on a fence
# line would change the fence. A block opening with a heading or a region marker is passed through
# untouched: the append refuses those loudly (103) and tagging would corrupt them. A block that is
# exactly `_No response_` is a placeholder and also passes through. NEVER pipe AUTHOR text through
# this: tagging author text as the gate's is the one thing the write-once rule exists to stop, so
# only text the gate itself composed goes in. N is a non-negative integer; exclusive of every other
# mode, and it needs no --body or --template.
#
# --roles prints `<role>\t<label>` per resolved role and exits (#213), in the fixed order
# scenarios, unit_tests, e2e_tests, docs_impact: the ids ticket-gate's Step 0c targets and the
# synthesis table are keyed on (`scenarios` feeds check 3's row `gwt`). Same resolution as
# check 3, so the rule lives here alone. An unresolved role prints no line. A label carries no
# trailing CR because template_fields() strips it at the source (#493), so --roles prints it as
# read. Needs --template, not --body; refused with --dump-fields.
# Stdout is empty on any error, and a caller treats non-zero as a failed run, never as a
# reason to fall back to matching ids itself.
#
# A CRLF BODY READS AS ITS LF COPY (#491): every line is matched with its trailing CR stripped,
# --headings prints heading lines with no CR, and row() deletes CR from the evidence, so a body
# saved with CRLF endings gets byte-identical rows. A bare-CR body (no LF at all) is out of scope.
# A CRLF TEMPLATE READS AS ITS LF COPY TOO (#493): template_fields() strips a trailing CR from each
# label and template_subheadings() from its label and heading text, each before the blank strip,
# so a template checked out with core.autocrlf=true gives the LF rows and --dump-fields and
# --roles print no CR. Only a TRAILING CR is stripped: a CR inside a label is kept, byte for byte.
# A QUOTED TEMPLATE LABEL IS COMPARED BY ITS VALUE (#492). YAML requires quotes on a label holding
# `: `, and the parsed label used to keep them, so its section read as `heading absent` on every
# body. Both label readers now unquote through one awk function, unq() (see UNQ_AWK), and so
# --dump-fields, --roles and check 3 all see the value. Only `\"`, `\\` and `''` are decoded, a
# deliberate subset of YAML's escapes; any other escape stays verbatim, an unterminated or
# mismatched quote and a value that unquotes to empty (`""`, `''`, `" "`) are left as read, so
# each still fails closed, and only `label:` is unquoted (`id:`, `type:` and `required:` are not).

# NO `awk -v` IN THIS FILE (#259). `-v` runs a backslash-escape pass over its value and Apple's awk
# refuses one holding a newline, so every value reaches awk through ENVIRON (`CTM_*`). Classified
# per site: `want` (section_of, template_subheadings) and `l` (role_required) are field LABELS read
# from the project's own --template, caller text, and a label `Steps\tx` read as `Steps<TAB>x`, so
# its filled section was reported empty; `p` (role_label) receives only the literal role patterns,
# and `any`/`neg`/`pos` are built by marker_re from literals, both moved as hardening (not
# reproducible), which also removes the trap where a future `\.` in a regex silently became `.`.
# scripts/test-check-ticket-mechanics.sh counts zero `awk ... -v` lines (scripts/awkv-count.sh,
# continuations joined). No awk takes a file operand either (#405): a `--body 'b=x.md'` operand
# was read as an assignment, so files come in through `<`.
#
set -uo pipefail

STANDARDS_DOC="docs/guides/ticket-standards.md"; TAG_ROUND=""; BODY=""; TEMPLATE=""; TPL_VERSION=""; CURRENT_TPL_VERSION=""; LABELS=""; DUMP_FIELDS=0; ROLES=0; CLASSES=0; SKELETON=0; HEADINGS=0; LABELS_DOC=""; AREA_EXPLICIT=0
# The canonical taxonomy is docs/guides/labels.md, and scripts/check-label-taxonomy.sh fails the
# build when this default disagrees with it (#188). `infrastructure` and `design` are TYPE labels
# there, not areas, and `frontend` is not a declared label at all. The last three are for a
# governance repository, where the six product-application areas describe nothing the project
# works on. Overridable because labels.md documents adding project-specific area labels.
AREA_LABELS="api privacy web mobile backend database components tooling governance"
TYPE_LABELS="bug enhancement feature security infrastructure design documentation testing"

die() { printf 'check-ticket-mechanics: %s\n' "$1" >&2; exit 2; }
# A recognised flag as the LAST argument leaves nothing to consume: `shift 2` then fails
# silently and the loop spins forever. A hang is worse than a crash, so this refuses instead.
need_value() { [ "$1" -ge 2 ] || die "$2 needs a value"; }

# FENCED CODE BLOCKS (#485). A ticket that quotes a template heading inside a code block, to show
# a reproduction input, had the quote read as the real section by section_of() and by check 3's
# presence scan, so a valid scenarios section after it read as 0 positive, 0 negative. Every reader
# of the body's headings now shares this fence state, and so does every GWT block scan of check 4,
# through fence_free() (#490), CommonMark 0.31.2 section 4.5, on a line
# already stripped of its CR and trailing blanks: an opener is at most 3 spaces of indent, then 3
# or more backticks or 3 or more tildes; a backtick opener whose info string holds a backtick is
# inline code, not a fence; a closer is at most 3 spaces of indent, the opener's character, at
# least as long, and nothing after it; an unclosed fence runs to the end of the body, as the forge
# renders it. Indented code blocks, and fences inside list items or block quotes, are not modelled.
# REGIONS AND FENCES: fence state is evaluated first, so a region marker inside an open fence is
# literal text and opens no region; inside a gate region fence state is frozen, so a stray fence
# line there never leaks an open fence into the author text after the region. Functions only:
# each reader applies them in that order itself. Portable to Apple awk (no intervals, no gawk).
# INDENT is measured with match() and RLENGTH, never with `sub(/^ ? ? ?/, ...)`: mawk 1.3.4 reads
# that regex as stripping ONE space, so a fence indented 2 or 3 spaces was no fence there (#485
# round 1). The match form was checked on gawk, mawk, busybox and Apple awk.
FENCE_AWK='
function fence_open(s,   o, n, info) {
  match(s, /^ */); if (RLENGTH > 3) return 0; o = substr(s, RLENGTH + 1)
  if (substr(o, 1, 3) == "```") match(o, /^`+/)
  else if (substr(o, 1, 3) == "~~~") match(o, /^~+/)
  else return 0
  n = RLENGTH; info = substr(o, n + 1)
  if (substr(o, 1, 1) == "`" && index(info, "`")) return 0   # backtick info string holds no backtick
  fch = substr(o, 1, 1); flen = n; return 1
}
function fence_close(s,   c, pat) {
  match(s, /^ */); if (RLENGTH > 3) return 0; c = substr(s, RLENGTH + 1)
  if (fch == "`") pat = "^`+$"; else pat = "^~+$"
  return c ~ pat && length(c) >= flen
}'
# The body's real heading lines (`^##+ `), once each in body order: check 3's presence scan
# and --headings read this, so presence and content cannot disagree about a fenced line again.
# Unlike section_of() it still READS a gate region's headings, as the raw grep it replaced did;
# a region only freezes fence state here. A line is printed with its trailing CR stripped and
# nothing else (#491): `h`, not the fully cleaned `l`, so an LF heading with trailing blanks is
# still `heading absent` exactly as before, and LF --headings output is unchanged.
body_headings() {
  awk "$FENCE_AWK"'
    { l = $0; sub(/\r$/, "", l); h = l; sub(/[ \t]+$/, "", l) }
    fopen { if (fence_close(l)) fopen = 0; next }
    rgn != "" { if (l == "<!-- " rgn ":end -->") rgn = ""; else if (/^##+ /) print h; next }
    fence_open(l) { fopen = 1; next }
    l ~ /^<!-- [^ \t]+:start -->$/ { rgn = substr(l, 6, length(l) - 15); next }
    /^##+ / { print h }
  ' < "$BODY"
}
# A field's text minus every fence line and every line inside a fence, other lines printed as
# they came (#490). Check 4's block scans read this, so a scenario header, When or Then quoted in
# a code block is plain text to them. No region rule: section_of() has already dropped regions.
fence_free() {
  printf '%s\n' "$1" | awk "$FENCE_AWK"'
    { l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l) }
    fopen { if (fence_close(l)) fopen = 0; next }
    fence_open(l) { fopen = 1; next }
    { print }
  '
}

while [ $# -gt 0 ]; do
  case "$1" in
    --body)                need_value $# "$1"; BODY="$2"; shift 2 ;;
    --template)            need_value $# "$1"; TEMPLATE="$2"; shift 2 ;;
    --tpl-version)         need_value $# "$1"; TPL_VERSION="$2"; shift 2 ;;
    --current-tpl-version) need_value $# "$1"; CURRENT_TPL_VERSION="$2"; shift 2 ;;
    --labels)              need_value $# "$1"; LABELS="$2"; shift 2 ;;
    --area-labels)         need_value $# "$1"; AREA_LABELS="$2"; AREA_EXPLICIT=1; shift 2 ;;
    --labels-doc)          need_value $# "$1"; LABELS_DOC="$2"; shift 2 ;;
    --type-labels)         need_value $# "$1"; TYPE_LABELS="$2"; shift 2 ;;
    --standards-doc)       need_value $# "$1"; STANDARDS_DOC="$2"; shift 2 ;;
    --dump-fields)         DUMP_FIELDS=1; shift ;;
    --roles)               ROLES=1; shift ;;
    --tag-blocks)          need_value $# "$1"; TAG_ROUND="$2"; shift 2 ;;
    --headings)            HEADINGS=1; shift ;;
    --classes)             CLASSES=1; shift ;;
    --skeleton)            SKELETON=1; shift ;;
    -h|--help)             awk 'NR==1{next} /^#/{print; next} {exit}' < "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [ -n "$TAG_ROUND" ]; then   # #532: a stdin filter, before any mode or file checks
  case "$TAG_ROUND" in ''|*[!0-9]*) die "--tag-blocks takes a round number (digits only), got '$TAG_ROUND'" ;; esac
  [ -z "$BODY$TEMPLATE" ] && [ "$ROLES$DUMP_FIELDS$HEADINGS$CLASSES$SKELETON" = 00000 ] \
    || die "--tag-blocks is exclusive of every other mode and takes no --body or --template"
  GATE_ROUND="$TAG_ROUND" awk "$FENCE_AWK"'
    function tagged(s) { return s ~ /\(gate-written, round [0-9]+\)$/ }
    BEGIN { first = 1; tag = "(gate-written, round " ENVIRON["GATE_ROUND"] ")" }
    { l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l) }
    fopen { if (fence_close(l)) fopen = 0; print; next }
    l == "" { first = 1; print; next }
    {
      isf = fence_open(l); if (isf) fopen = 1   # the fence state the lines after it are read in
      if (!first) { print; next }
      first = 0
      match(l, /^ */); t = substr(l, RLENGTH + 1)
      if (RLENGTH <= 3 && (t ~ /^#+ / || t ~ /^<!-- [^ \t]+:(start|end) -->$/ || l == "_No response_")) { print; next }
      if (tagged(l)) { print; next }
      if (isf) { print tag; print l; next }
      # a tag quoted mid-line stays; only one followed by nothing but closing * or _ (in bold) goes
      if (match(l, /[ \t]*\(gate-written, round [0-9]+\)[*_ \t]*$/)) { c = substr(l, RSTART); sub(/^[ \t]*\(gate-written, round [0-9]+\)/, "", c); sub(/[ \t]+$/, "", c); l = substr(l, 1, RSTART - 1) c }
      print l " " tag
    }'
  exit 0
fi
[ "$ROLES" -eq 0 ] || [ "$DUMP_FIELDS" -eq 0 ] || die "--roles and --dump-fields are mutually exclusive"
[ "$HEADINGS" -eq 0 ] || { [ "$ROLES" -eq 0 ] && [ "$DUMP_FIELDS" -eq 0 ]; } || die "--headings is exclusive of --roles and --dump-fields"
[ "$CLASSES" -eq 0 ] || { [ "$ROLES" -eq 0 ] && [ "$DUMP_FIELDS" -eq 0 ] && [ "$HEADINGS" -eq 0 ]; } || die "--classes is exclusive of --roles, --dump-fields and --headings"
[ "$SKELETON" -eq 0 ] || { [ "$ROLES" -eq 0 ] && [ "$DUMP_FIELDS" -eq 0 ] && [ "$HEADINGS" -eq 0 ] && [ "$CLASSES" -eq 0 ]; } || die "--skeleton is exclusive of --roles, --dump-fields, --headings and --classes"
# --classes (#513) and --skeleton (#505) need no body, exactly like --roles, so they take the same
# no-body path below. --skeleton's optional --body is checked in its own block.
{ [ "$CLASSES" -eq 0 ] && [ "$SKELETON" -eq 0 ]; } || ROLES=1
if [ "$ROLES" -eq 0 ]; then
  [ -n "$BODY" ]   || die "--body is required"
  [ -f "$BODY" ]   || die "body file not found: $BODY"
fi
[ "$HEADINGS" -eq 0 ] || { body_headings; exit 0; }
[ -n "$TEMPLATE" ] || die "--template is required"
[ -f "$TEMPLATE" ] || die "template file not found: $TEMPLATE"
[ "$SKELETON" -eq 0 ] || grep -q '^body:' "$TEMPLATE" || die "$TEMPLATE has no body: list"
[ "$SKELETON" -eq 0 ] || [ -z "$BODY" ] || [ -f "$BODY" ] || die "body file not found: $BODY"

# The project's area table, read the way scripts/check-label-taxonomy.sh reads the canonical one
# (the two awk bodies are byte-identical, and its suite asserts that): rows of the `### Area
# labels` table whose first column is a backticked name, with any leading whitespace or a compact
# `|\`x\`|` allowed (review: a valid row silently dropped is a wrong set with nothing reporting it).
# The section ends at the next heading of one to three hashes, since a `## Priority labels` after
# the table used to be swallowed into the area set (review); a `####` inside it is read through as
# Markdown nesting. Explicit --area-labels wins. A doc that is
# ABSENT keeps the default, sets DOC_ABSENT and is announced in check 2's evidence (#425), where
# a label outside both compiled-in sets is referred. A doc that is present but carries no such table is REFERRED at check 2
# rather than silently judged on the default, because forge-gate-mechanics.sh passes this flag
# unconditionally and a project whose table differs in heading level or case would otherwise be
# widened back to the nine with nothing saying so. TYPE_LABELS stays compiled-in: a project's own
# type only draws a warn row here, never a fail.
DOC_NO_TABLE=0; DOC_ABSENT=0
if [ "$AREA_EXPLICIT" -eq 0 ] && [ -n "$LABELS_DOC" ] && [ ! -f "$LABELS_DOC" ]; then DOC_ABSENT=1; fi
if [ "$AREA_EXPLICIT" -eq 0 ] && [ -n "$LABELS_DOC" ] && [ -f "$LABELS_DOC" ]; then
  doc_areas="$(awk '
    /^### Area labels/ { inside = 1; next }
    inside && /^##?#? / { exit }
    inside && /^[ \t]*\|[ \t]*`/ { sub(/^[ \t]*\|[ \t]*`/, ""); sub(/[ \t]*`.*/, ""); print }
  ' < "$LABELS_DOC" | tr '\n' ' ')"
  doc_areas="${doc_areas% }"
  if [ -n "$doc_areas" ]; then AREA_LABELS="$doc_areas"; else DOC_NO_TABLE=1; fi
fi

# The project's applied aliases, one `<title>\t<heading>` line each (#557, see the header). The doc
# comes in on stdin, never as an operand or through -v; a failed read leaves the list empty.
STD_AWK='
function sp(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
function ttl(s) { sub(/[ \t]*\([^)]*\)[ \t]*$/, "", s); return sp(s) }
function mk(s) { s = ttl(sp(s)); sub(/^[0-9]+\.[ \t]+/, "", s); return sp(s) }
  { l = $0; sub(/\r$/, "", l) }
  match(l, /^[ \t]*(```|~~~)/) { c = substr(l, RSTART + RLENGTH - 1, 1); fc = (fc == "") ? c : (fc == c ? "" : fc); next }
  fc != "" { next }
  match(l, /^#+[ \t]/) && RLENGTH <= 7 {
    t = substr(l, RLENGTH + 1); sub(/^[ \t]+/, "", t); sub(/^[0-9]+\.[ \t]+/, "", t)
    sub(/[ \t]*#*[ \t]*$/, "", t); t = ttl(t); if (t != "") H[t] = 1; next
  }
  l ~ /^[ \t]*<!--[ \t]*citation-alias:[ \t]*"[^"]+"[ \t]*=[ \t]*"[^"]+"[ \t]*-->[ \t]*$/ {
    split(l, q, "\""); t = mk(q[2]); g = mk(q[4])
    if (t != "" && g != "" && !(t in first)) { first[t] = g; order[++n] = t }
  }
  END {
    for (i = 1; i <= n; i++) { t = order[i]
      if (!(t in H) && (first[t] in H)) print t "\t" first[t]
    }
  }'
ALIASES=""
if [ -n "$STANDARDS_DOC" ] && [ -f "$STANDARDS_DOC" ]; then
  ALIASES="$( { awk "$STD_AWK" < "$STANDARDS_DOC"; } 2>/dev/null)"
fi
# The row's first citation, renamed when its title has an applied alias. Plain concatenation, never
# a ${//} substitution, whose replacement treats & and a backslash as syntax in bash 5.2.
alias_ev() {
  local ev="$1" sw=section op pre rest title t g
  op="$sw \""
  case "$ev" in *"$op"*) ;; *) printf '%s' "$ev"; return ;; esac
  pre=${ev%%"$op"*}; rest=${ev#*"$op"}
  title=${rest%%\"*}
  while IFS="$(printf '\t')" read -r t g; do
    if [ "$t" = "$title" ]; then
      ev="$pre$op$g\" (the kit's \"$title\")${rest#*\"}"; break
    fi
  done <<EOF
$ALIASES
EOF
  printf '%s' "$ev"
}

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Evidence is untrusted body text. A newline in it would emit a phantom row and a tab would
# shift a field, so the row separator is stripped from the payload rather than trusted.
# The bound is 1000, not 160: the joined required-label list of a shipped template is 248 bytes
# (feature.yml) and 259 (bug.yml), and the old cut hid the tail of the absent list (#205). Any row
# that lists items carries a count prefix so a cut can never again pass as a complete list.
row() {
  local ev
  ev="$(printf '%s' "$3" | tr -d '\r' | tr '\n\t' '  ' | cut -c1-1000)"
  [ -z "$ALIASES" ] || ev="$(alias_ev "$ev" | cut -c1-1000)"   # the bound holds after a rename too
  printf '%s\t%s\t%s\n' "$1" "$2" "$ev"
}

# Everything under a `## <label>` or `### <label>` heading, up to the next heading at the same
# level or the next heading that is itself a template label (see the header). Compared
# literally, never as a regex, because labels carry `/`, `&` and parentheses. TEMPLATE_LABELS is
# set once the template is parsed, below.
# A same-level heading ends the section UNLESS its text is a sub-heading the template itself
# places inside this field (its `value:` or `placeholder:` block), scoped per field (#205):
# feature.yml's E2E placeholder carries `### Happy path`, and a web-form body renders the label at
# `###` too, so without this the kit's own template ended its E2E section at its own first line.
# A template label always ends it, whatever field it belongs to.
# The two newline-joined lists travel through the ENVIRONMENT, never `-v`: Apple's awk (the one
# macOS ships) refuses a -v value containing a newline ("newline in string"), so on a Mac every
# section read as empty and every check failed. Found by running the suite with that awk (#205).
# A heading-shaped line inside a fenced code block is never a heading (#485): it neither opens nor
# ends a section, though inside a real section it is still that section's content. See FENCE_AWK.
TEMPLATE_LABELS=""
section_of() {
  CTM_LABELS="$TEMPLATE_LABELS" CTM_SUBS="$(template_subheadings "$1")" CTM_WANT="$1" awk "$FENCE_AWK"'
    BEGIN { want = ENVIRON["CTM_WANT"]
            n = split(ENVIRON["CTM_LABELS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") islabel[a[i]] = 1
            n = split(ENVIRON["CTM_SUBS"], b, "\n");   for (i = 1; i <= n; i++) if (b[i] != "") issub[b[i]] = 1 }
    { l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l) }
    fopen { if (fence_close(l)) fopen = 0; if (inside) print; next }
    rgn != "" { if (l == "<!-- " rgn ":end -->") rgn = ""; next }
    fence_open(l) { fopen = 1; if (inside) print; next }   # section_of: a fence opens
    l ~ /^<!-- [^ \t]+:start -->$/ { rgn = substr(l, 6, length(l) - 15); next }
    /^##+ / {
      lvl = index($0, " ") - 1; cur = substr(l, lvl + 2); sub(/[ \t]+$/, "", cur)   # text from l (no CR, #491); the level from $0, so a bare `### ` heading still ends a section
      if (inside && ((lvl == want_lvl && !(cur in issub)) || (cur in islabel))) inside = 0
      if (!inside && !found && cur == want) { inside = 1; found = 1; want_lvl = lvl; next }
    }
    inside { print }
  ' < "$BODY"
}
# A QUOTED LABEL IS ITS YAML VALUE (#492). unq() is the one rule both label readers apply, after
# the CR and blank strips: strip only when the value opens with a double or single quote AND the
# matching closing quote is found by scanning, with nothing after it but an optional ` # comment`.
# Inside double quotes `\"` and `\\` decode in one left-to-right pass, so in `"C:\\"` the escaped
# backslash cannot escape the closing quote, and every other escape stays verbatim. Inside single
# quotes `''` decodes to one quote. An unterminated or mismatched value comes back untouched, so
# its section still fails closed, and so does a value that unquotes to nothing (`""`, `''`,
# `" "`): template_fields() skips an empty label, so its required section was never checked.
# Trailing blanks inside the quotes are trimmed after unquoting, on the unquoted value only, so an
# unquoted label goes through exactly the strips it had before. That trim sits INSIDE unq(), not
# after it as #492's step list says, on purpose: a trim after unq() would re-trim the blanks a
# #493 blank-then-CR order mutant leaves behind, and that mutant would survive.
# The single quote is written \047 because this program sits inside a single-quoted shell string.
UNQ_AWK='
function unq(s,   q, n, i, c, d, out) {
  q = substr(s, 1, 1); if (q != "\"" && q != "\047") return s   # opens with a quote
  n = length(s); out = ""
  for (i = 2; i <= n; i++) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1)
    if (q == "\"" && c == "\\" && (d == "\"" || d == "\\")) { out = out d; i++; continue }   # one decode pass
    if (q == "\047" && c == "\047" && d == "\047") { out = out c; i++; continue }   # a doubled single quote
    if (c == q) { if (substr(s, i + 1) !~ /^([ \t]+#.*)?$/) return s; sub(/[ \t]+$/, "", out); if (out == "") return s; return out }   # the closing quote
    out = out c
  }
  return s
}'
# The `#`-headed lines inside ONE field's `value:` or `placeholder:` block, heading marks stripped.
template_subheadings() {
  CTM_WANT="$1" awk "$UNQ_AWK"'
    BEGIN { want = ENVIRON["CTM_WANT"] }
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ { label = ""; inblk = 0; next }
    /^      label: / { if (label == "") { l = substr($0, 14); sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); label = unq(l) } }   # trailing CR first (#493), then unq (#492)
    /^      (value|placeholder): \|/ { inblk = 1; next }
    /^      [a-z]/ { inblk = 0 }
    inblk && label == want && /^        #+ / { h = $0; sub(/^[[:space:]]*#+[[:space:]]*/, "", h); sub(/\r$/, "", h); sub(/[ \t]+$/, "", h); print h }
  ' < "$TEMPLATE"
}

# GitHub renders an unfilled OPTIONAL textarea as `_No response_`. That is presence without
# content, and it is legitimate on a field the template marks `required: false`.
has_content() {
  local squashed
  squashed="$(printf '%s' "$1" | tr -d '[:space:]')"
  [ -n "$squashed" ] && [ "$squashed" != "_Noresponse_" ]
}

first_line() { printf '%s' "$1" | grep -m1 -v '^[[:space:]]*$' | cut -c1-120; }

# Emits `<label>\t<required>\t<id>\t<gate>` per rendered field. Field labels sit at exactly six
# spaces and field-level `required` at six; a checkboxes OPTION nests deeper and carries a leading
# dash, which is what keeps option text out of the section list. The id is the third column and
# every reader below takes it explicitly (`read -r label required _`): a two-field read would take
# the id as the required flag and check 3 would fail open. The fourth column is `yes` for a field
# the template marks gate-filled (see the header, #304), and is read with awk -F'\t' only, never
# bash `read`: tab is IFS whitespace, so an empty id would collapse two tabs and shift it.
# --dump-fields keeps its two-column contract.
template_fields() {
  awk "$UNQ_AWK"'
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ {
      if (label != "") { print label "\t" (req == "true" ? "yes" : "no") "\t" id "\t" (gate ? "yes" : "no") }
      t = $0; sub(/^.*type:[[:space:]]*/, "", t); gsub(/[[:space:]]/, "", t)
      type = t; label = ""; req = "false"; id = ""; gate = 0; next
    }
    /^      description: / && index($0, "Auto-populated by ticket-gate") { gate = 1 }
    /^    # gate-owned[[:space:]]*$/ { gate = 1 }
    /^    id: / { i = substr($0, 9); gsub(/[[:space:]]/, "", i); id = i }
    /^      label: / { if (type != "markdown" && label == "") { l = substr($0, 14); sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); label = unq(l) } }   # trailing CR only (#493), then unq (#492)
    /^      required: / { r = $0; sub(/^.*required:[[:space:]]*/, "", r); gsub(/[[:space:]]/, "", r); req = r }
    /^          required: true/ { req = "true" }   # a checkboxes group with a required option
    END { if (label != "") { print label "\t" (req == "true" ? "yes" : "no") "\t" id "\t" (gate ? "yes" : "no") } }
  ' < "$TEMPLATE"
}

TEMPLATE_FIELDS="$(template_fields)"
# A template that parses to nothing is unusable input, not a body that passes every check. The
# first version reported `sections pass` here, a fail-open on the one check that reads it.
[ -n "$TEMPLATE_FIELDS" ] || die "no fields parsed from template: $TEMPLATE"
[ "$DUMP_FIELDS" -eq 0 ] || { printf '%s\n' "$TEMPLATE_FIELDS" | cut -f1,2; exit 0; }
TEMPLATE_LABELS="$(printf '%s\n' "$TEMPLATE_FIELDS" | cut -f1)"

# Which rendered section plays each role, by label shape rather than by a fixed name.
#
# AN UNRESOLVED ROLE IS `referred`, NEVER `na`. The script cannot tell "this template does not
# ask for E2E specs" from "this template calls it something my regex misses", and treating the
# second as `na` is a fail-open: a project template naming its sections differently would score
# every check `na` and the gate would PASS having checked nothing. `referred` costs a little
# noise on the three templates that genuinely carry no test sections, and `referred` never
# blocks, so the trade is one the critic can absorb and a silent pass is not.
# Patterns in PRIORITY order, each tried against the field id first and then the label, so an
# E2E-named section outranks an integration-named one whatever order the template lists them,
# and a template that renames both id and label still resolves (#205).
role_label() {
  local pat hit
  for pat in "$@"; do
    hit="$(printf '%s\n' "$TEMPLATE_FIELDS" | CTM_P="$pat" awk -F'\t' 'tolower($3) ~ ENVIRON["CTM_P"] { print $1; exit }')"
    [ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
    hit="$(printf '%s\n' "$TEMPLATE_FIELDS" | CTM_P="$pat" awk -F'\t' 'tolower($1) ~ ENVIRON["CTM_P"] { print $1; exit }')"
    [ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
  done
  return 0
}
role_required() {
  [ -n "$1" ] || return 1
  grep -q yes <<< "$(printf '%s\n' "$TEMPLATE_FIELDS" | CTM_L="$1" awk -F'\t' '$1 == ENVIRON["CTM_L"] { print $2; exit }')"
}
# An OPTIONAL section left empty is what GitHub renders for a field the template did not demand,
# so it is not a FAILURE. It is not `na` either: the rule still binds and only the critic can say
# whether it is met, so an unfilled optional section is REFERRED.
empty_outcome() { if role_required "$1"; then echo fail; else echo referred; fi; }
SCENARIOS_LABEL="$(role_label 'given.*when.*then')"
UNIT_LABEL="$(role_label 'unit test')"
# The second pattern needs "test" or "scenario" beside "integration": a design template's
# "Integration points" section (prose, no E2E field) would otherwise be read as the E2E section
# and FAIL for naming no path, where v6 referred it. Wider than before, into FAIL, is the one
# direction this script forbids (found in review).
E2E_LABEL="$(role_label 'e2e|end.to.end' 'integration.*(test|scenario)')"
DOCS_LABEL="$(role_label 'documentation impact')"
# --classes (#513) prints `<class>\t<label>` per template field, one row per label, in template
# order, class in gate-owned | synthesised | author-supplied, resolved in that precedence:
#   gate-owned      the template marks the field gate-filled (#304), check 3 never charges it;
#   synthesised     Step 0c writes it: a role label --roles prints, or the `personal_data` field;
#   author-supplied everything else, which Step 0c never writes, so it is the set check 3 reports
#                   absent on a post-0c body (less the labels Step 0c-iv pointer-places).
# It reads the same TEMPLATE_FIELDS and role resolution as check 3, so the partition has no second
# copy. Needs --template, not --body (a --body is ignored). Check 3's evidence is unchanged.
if [ "$SKELETON" -eq 1 ]; then
  heads=""
  [ -z "$BODY" ] || heads="$(body_headings)"
  skel="$(CTM_HEADS="$heads" CTM_APPEND="$([ -n "$BODY" ] && echo 1 || echo 0)" awk "$UNQ_AWK"'
    BEGIN { n = split(ENVIRON["CTM_HEADS"], a, "\n"); for (i = 1; i <= n; i++) have[a[i]] = 1
            append = ENVIRON["CTM_APPEND"]; marker = ""; out = "" }
    { sub(/\r$/, "") }
    function flush(   i, v, last, miss) {
      if (label == "") return
      miss = !(("## " label) in have) && !(("### " label) in have)
      if (type == "checkboxes" && nopt > 0) {
        if (miss) { out = out "\n## " label "\n"; for (i = 1; i <= nopt; i++) out = out "- [ ] " opt[i] "\n" }
      } else if (type == "textarea" && inval == 1 && vhas) {
        if (miss) { last = nv; while (last > 0 && vl[last] ~ /^[ \t]*$/) last--
                    out = out "\n## " label "\n"; for (i = 1; i <= last; i++) out = out vl[i] "\n" }
      }
    }
    /^[[:space:]]*-[[:space:]]*type:[[:space:]]*/ {
      flush(); t = $0; sub(/^.*type:[[:space:]]*/, "", t); gsub(/[[:space:]]/, "", t)
      type = t; label = ""; nopt = 0; nv = 0; vhas = 0; inval = 0; inblk = 0; inopt = 0; next
    }
    /^      label: / { if (type != "markdown" && label == "") { l = substr($0, 14); sub(/[ \t]+$/, "", l); label = unq(l) } }
    /^      options:/ { inopt = 1; inblk = 0; next }
    /^      value:/ {
      inopt = 0; inblk = 0; r = substr($0, 13); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r)
      if (type == "textarea") {
        if (r == "|" || r == "|-") { inval = 1; inblk = 1 }
        else { printf "ERR\tfield \047%s\047 has an unsupported value: style (use a | or |- block)\n", label; err = 1; exit 3 }
      } else if (type == "markdown") { inblk = 1; inval = 0 }
      next
    }
    /^      [a-z]/ { inopt = 0; inblk = 0 }
    inopt && /^        - label: / { nopt++; o = substr($0, 18); sub(/[ \t]+$/, "", o); opt[nopt] = unq(o); next }
    inblk && type == "markdown" && marker == "" && match($0, /<!-- template-version: [0-9]+ -->/) { marker = substr($0, RSTART, RLENGTH) }
    inblk && type == "textarea" && (/^        / || /^[ \t]*$/) {
      line = $0; sub(/^        /, "", line); nv++; vl[nv] = line; if (line ~ /^- \[ \]/) vhas = 1
    }
    END { if (err) exit 3; flush(); if (append != "1" && marker != "") print marker; printf "%s", out }
  ' < "$TEMPLATE")"; skrc=$?
  [ "$skrc" -eq 0 ] || die "$(printf '%s' "$skel" | sed -n 's/^ERR[[:space:]]//p' | head -1)"
  if [ -n "$BODY" ]; then
    cat "$BODY"
    [ -z "$skel" ] || { [ -z "$(tail -c1 "$BODY")" ] || printf '\n'; printf '%s\n' "$skel"; }
  else
    [ -z "$skel" ] || printf '%s\n' "$skel"
  fi
  exit 0
fi
if [ "$CLASSES" -eq 1 ]; then
  synth="$(printf '%s\n%s\n%s\n%s\n' "$SCENARIOS_LABEL" "$UNIT_LABEL" "$E2E_LABEL" "$DOCS_LABEL"; printf '%s\n' "$TEMPLATE_FIELDS" | awk -F'\t' 'tolower($3) == "personal_data" { print $1 }')"
  printf '%s\n' "$TEMPLATE_FIELDS" | CTM_SYNTH="$synth" awk -F'\t' '
    BEGIN { n = split(ENVIRON["CTM_SYNTH"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") syn[a[i]] = 1 }
    $1 == "" || ($1 in seen) { next }
    { seen[$1] = 1; c = ($4 == "yes") ? "gate-owned" : (($1 in syn) ? "synthesised" : "author-supplied"); print c "\t" $1 }'
  exit 0
fi
if [ "$ROLES" -eq 1 ]; then
  for r in "scenarios:$SCENARIOS_LABEL" "unit_tests:$UNIT_LABEL" "e2e_tests:$E2E_LABEL" "docs_impact:$DOCS_LABEL"; do
    [ -n "${r#*:}" ] && printf '%s\t%s\n' "${r%%:*}" "${r#*:}"
  done
  exit 0
fi

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
# Step 0b's rule: an area label is required, a type label warns only. This check never demands a
# label no step requires. With the doc absent, Step 0b runs this check itself and blocks on its
# `fail` row (#425), so that row and Step 0b's block are one rule.
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# The ONE split rule, shared by has_label_from and has_candidate: labels split on commas and
# newlines ONLY, each trimmed (#430), since a label may hold a space and word-splitting read
# `needs api review` as three labels whose `api` met the area rule; and each case folded (#472),
# since GitHub holds one spelling per name, so `API` is the area `api`, never a new one.
ticket_labels() {
  local l
  while IFS= read -r l; do
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    printf '%s\n' "$(lc "$l")"
  done <<< "$(printf '%s' "$LABELS" | tr ',' '\n')"
}
in_set() { local w; for w in $2; do [ "$1" = "$(lc "$w")" ] && return 0; done; return 1; }
has_label_from() {
  local l
  while IFS= read -r l; do in_set "$l" "$1" && return 0; done <<< "$(ticket_labels)"
  return 1
}
# A candidate (#425) is one ticket label in neither compiled-in set. It is a per-label test, not
# has_label_from: "any label matches" cannot say whether one label is outside both sets. There is
# no priority set, so `P3` is a candidate too, and Step 3B judges it.
has_candidate() {
  local l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    in_set "$l" "$AREA_LABELS" || in_set "$l" "$TYPE_LABELS" || return 0
  done <<< "$(ticket_labels)"
  return 1
}
note=""
[ "$DOC_ABSENT" -eq 0 ] || note="; labels.md not found; using forge-kit's built-in nine areas. Run forge-adapt Templates mode, \"Labels\" step, to declare yours."
if [ "$DOC_NO_TABLE" -eq 1 ]; then
  row labels referred "no Area labels table in $LABELS_DOC; Step 3B rules on the area and type labels"
elif ! has_label_from "$AREA_LABELS"; then
  if [ "$DOC_ABSENT" -eq 1 ] && has_candidate; then
    row labels referred "no built-in area label; Step 3B rules on whether a project label is the area$note"
  else
    row labels fail "no area label (one of: ${AREA_LABELS// /, })$note"
  fi
elif ! has_label_from "$TYPE_LABELS"; then
  row labels warn "no type label (one of: ${TYPE_LABELS// /, })$note"
else
  row labels pass "labels: $LABELS$note"
fi

# --- check 3: required sections present -------------------------------------------------
# Every section the template carries needs a heading. Only a field the template marks
# `required: true` needs CONTENT: GitHub renders an unfilled optional field as `_No response_`,
# and faulting that failed a template-perfect ticket in the first version. An OPTIONAL field the
# template marks gate-filled is not charged when its heading is absent (#304, see the header).
# The flag is read PER ROW (#320): a lookup by label exempted a required field that shared its label
# with a gate-filled optional one, which GitHub forms allow when one of them has an id. Each row is
# split by position, never by `read` with a TAB IFS, which collapses the empty id column of a field
# with no `id:` and shifts the flag. role_required() and section_of() still look fields up by
# label (out of scope; two same-label sections are one heading to a reader anyway).
# Presence, and the at2/at3 level evidence, read body_headings(), never the raw body (#485): a
# heading-shaped line inside a fenced code block is a quote, not a heading, so a label present only
# inside a fence is ABSENT here, exactly as section_of() cannot find it. A raw grep counted the quote.
TAB="$(printf '\t')"
BODY_HEADINGS="$(body_headings)"
missing=""; empty=""; skipped=""; at2=""; at3=""
while IFS= read -r frow; do
  label=${frow%%"$TAB"*}; frest=${frow#*"$TAB"}; required=${frest%%"$TAB"*}; gate=${frow##*"$TAB"}
  grep -qxF "## $label" <<< "$BODY_HEADINGS" && at2="##"
  grep -qxF "### $label" <<< "$BODY_HEADINGS" && at3="###"
  [ -n "$label" ] || continue
  if ! grep -qxF -e "## $label" -e "### $label" <<< "$BODY_HEADINGS"; then
    if [ "$gate" = yes ] && [ "$required" = no ]; then   # check 3: per-row gate flag
      skipped="$skipped${skipped:+; }$label"
    else
      missing="$missing${missing:+; }$label"
    fi
  elif [ "$required" = "yes" ] && ! has_content "$(section_of "$label")"; then
    empty="$empty${empty:+; }$label"
  fi
done <<EOF
$TEMPLATE_FIELDS
EOF
count_items() { printf '%s' "$1" | awk -F'; ' '{ print NF }'; }
if [ -n "$missing" ]; then
  row sections fail "heading absent ($(count_items "$missing")): $missing"
elif [ -n "$empty" ]; then
  row sections fail "required heading present but empty ($(count_items "$empty")): $empty"
else
  # With a field exempt the evidence must not claim every section is present (#320).
  if [ -n "$skipped" ]; then
    row sections pass "every charged section present, every required one filled (headings at ${at2}${at2:+${at3:+ and }}${at3}); gate-filled, absent and not charged ($(count_items "$skipped")): $skipped"
  else
    row sections pass "every template section present, every required one filled (headings at ${at2}${at2:+${at3:+ and }}${at3})"
  fi
fi

# --- check 4: GWT structure (section "GWT scenarios", the checkable half) --------------------------------
# WHICH conditions are independent is the critic's judgment, never this check's.
#
# ONE marker regex for every site (#205): the bare word with an optional parenthetical and/or
# trailing colon and nothing else, OR the word wrapped in bold or italic followed by anything.
# `Positive (happy path)`, `**Negative** note` and `Positive:` are markers; `Positive outcome
# expected here` is prose, and admitting it would make a block with no When and a false FAIL.
# Bracket expressions rather than backslashes: the string reaches awk through ENVIRON since #259,
# which keeps a backslash, but a bracket expression reads the same however it travels. bash 3.2 has no function returning a string, so a variable per word.
# The bold branch allows a parenthetical INSIDE the markup too (`**Negative (bad input)**`), the
# shape the ticket's own scenario used; without it the block's lines fell into the previous block
# and the author was told THAT block had two Whens (found in review).
marker_re() { printf '^[[:space:]]*(%s)[[:space:]]*([(][^)]*[)])?[[:space:]]*:?[[:space:]]*$|^[[:space:]]*([*][*]|__|[*]|_)(%s)([[:space:]]*[(][^)]*[)])?:?([*][*]|__|[*]|_)' "$1" "$1"; }
MARK_ANY="$(marker_re 'Positive|Negative')"; MARK_POS="$(marker_re Positive)"; MARK_NEG="$(marker_re Negative)"
# Defined here, above their first use: check 4 reads them since #241, and bash resolves a
# function at call time.
# An N/A claim (#459). The slash forms `N/A` and `n/a` and the phrase `not applicable` count
# ANYWHERE in a line, as they always did: a missed claim becomes a blocking fail while a false
# refer only misdirects, so they are not narrowed. The slashless `NA`/`na` is prose in
# "the row reports `na`", so it counts only as a line's first word, after an optional list marker
# (`-`, `*`, `1.`, `1)`), checkbox, a short `Label:` (`Unit tests: NA`) and bold or italic
# wrapper. grep runs per line, so `^` is a line start.
looks_na()   { grep -qiE '(^|[^a-z])n/a([^a-z]|$)|not applicable|^[[:space:]]*([-*][[:space:]]+|[0-9]+[.)][[:space:]]+)?(\[[ xX]\][[:space:]]+)?([A-Za-z][A-Za-z0-9 /-]{0,40}:[[:space:]]*)?([*][*]|__|[*]|_)?na([^a-z]|$)' <<< "$1"; }
# The gate-written tag (`(gate-written, round N)`) is not a reason (#535). `--tag-blocks` ends the
# first line of EVERY blank-separated block with it, so a synthesised bare `N/A` carries 21 tag
# characters and used to clear the 12-character bar as "referred". The strip is PER LINE, because
# the argument is a whole section and the tag ends a line mid-section; END-ANCHORED, so a tag with
# text after it on its line (hand-written prose quoting the tag) is left alone; and its trailing
# `[[:space:]]*` absorbs blanks and the CR a CRLF body leaves on the line (section_of() prints the
# raw line), plus the `*` or `_` that closes bold or italic markup around the line, the same
# trailing set `--tag-blocks` accepts. A tag on a line of its own strips to an empty line. The measure stays the whole
# section: a bare N/A beside any other block of more than 12 characters is still referred, as
# before. looks_na reads the raw text; only the length test sees the strip. Written as a POSIX BRE
# with `[0-9][0-9]*` (no `sed -E`, no `+`) for Apple sed. Each part is pinned by a mutant.
long_enough() { [ "$(printf '%s\n' "$1" | sed 's/[[:space:]]*(gate-written, round [0-9][0-9]*)[*_[:space:]]*$//' | tr -d '[:space:]' | wc -c)" -gt 12 ]; }
names_path() { grep -qE '`[^`]*/[^`]*`|[A-Za-z0-9_-]+\.(ts|tsx|js|jsx|mjs|cjs|py|go|rb|rs|java|kt|php|cs|sh|sql|md|yml|yaml)([^A-Za-z0-9]|$)' <<< "$1"; }
# A ONE-LINE scenario (#233): after an optional list marker, optional bold or italic markup and
# whitespace, the marker word followed by `.` or `:`, with Given, When and Then inline. It is a
# complete scenario this check cannot read (the marker must stand alone on its line), so it is
# REFERRED, never failed: v9 emitted "0 positive, 0 negative" on it, a heuristic miss that
# inverted the verdict. A separate detector, run BEFORE the block count and the When/Then scans;
# widening the marker regex instead would read the line as a block with zero When lines and fail
# it one site later, which is what `**Positive**: Given ...` did on v9.
# Its consumer runs it CASE-INSENSITIVELY (`grep -iE`, #479): `positive: given a, when b, then c.`
# is the same scenario in lower case, and a case-sensitive detector failed it 0/0. It errs wide for
# the `looks_na` reason: a miss becomes a blocking fail, a false refer only sends the line to the
# critic. The `(^|[^A-Za-z])` boundaries still hold under -i, so `forgiven` is not `given`.
# The ticket first accepted a side effect: a stray prose one-liner inside a valid block pair
# referred instead of passing. Review round 1 REVERSED that (do not restore it): `-i` also made a
# bold lowercase block header such as `**Positive**: given a, when b, then c` a one-liner, and the
# refer hid its block's real failure (2 When lines). So a valid pair is judged by its blocks, and
# only a header owning no When line keeps the one-line form; see the gate below. The block `marker_re`
# stays case-sensitive; a lowercase BLOCK marker is a separate question (#479 out of scope).
# Where the one-line form IS kept, the refer no longer hides the other blocks (#487, do not
# restore the bare refer): a no-When one-line header beside a Negative block with two When lines
# referred, so a mechanical fail the checker already knew became a judgement call. The refer
# branch now runs the When count and the missing-Then scan first, on the field with every no-When
# one-line header block removed, and refers only when both pass; see `without_oneliner_headers`.
# A line inside a fenced code block is never a header, a one-liner, a When or a Then to any of
# these scans (#490): they all read the fence_free() copy of the field, never the raw one.
#
# The two block scans are functions so the block branch and the refer branch run the same text.
# `when_counts` prints the offending blocks joined by '; ' (empty when every block has one When);
# `then_missing` prints how many Negative blocks have no Then line.
# Polarity comes from the anchored MARK_NEG, the same regex the counts and sibling awks use
# (#359). A substring test named a Negative block Positive when its label held the word. The
# else branch is safe: every line reaching it already matched MARK_ANY, so it is Positive.
# The join is awk, not `paste -sd'; '`: paste cycles its delimiter LIST per character, so a
# two-character separator yields `a;b c` from three items (#365). Do not simplify it back.
when_counts() {
  printf '%s\n' "$1" | CTM_ANY="$MARK_ANY" CTM_NEG="$MARK_NEG" awk '
    BEGIN { any = ENVIRON["CTM_ANY"]; neg = ENVIRON["CTM_NEG"] }
    $0 ~ any {
      if (block != "" && whens != 1) { print block ": " whens " When lines" }
      block = ($0 ~ neg ? "Negative" : "Positive"); whens = 0; next
    }
    block != "" && /^[[:space:]]*[-*][[:space:]]*\**When\**[[:space:]]*:/ { whens++ }
    END { if (block != "" && whens != 1) { print block ": " whens " When lines" } }
  ' | head -3 | awk 'NR>1{printf "; "} {printf "%s", $0} END{print ""}'
}
then_missing() {
  printf '%s\n' "$1" | CTM_NEG="$MARK_NEG" CTM_POS="$MARK_POS" awk '
    BEGIN { neg = ENVIRON["CTM_NEG"]; pos = ENVIRON["CTM_POS"] }
    $0 ~ neg { if (inneg && !seen) n++; inneg = 1; seen = 0; next }
    $0 ~ pos { if (inneg && !seen) n++; inneg = 0; next }
    inneg && /^[[:space:]]*[-*][[:space:]]*\**Then\**[[:space:]]*:/ { seen = 1 }
    END { if (inneg && !seen) n++; print n+0 }
  '
}
# The field minus every block that owns no When line and whose HEADER or any line under it is a
# one-liner (matched case-insensitively, as the `grep -iE` detector matches it), of either
# polarity (#487). Such a block is one-line scenarios the block scans cannot read, so it must never
# be reported as `Positive: 0 When lines`. That covers a bold grouping header such as `**Positive**`
# above bullet one-liners (review round 1): keyed on the header alone, it failed with 0 When lines
# where it had referred. The WHOLE block goes, not just the header line: a `- Then:` bullet under a
# dropped Negative header would otherwise count as the Then of the Negative block above it and hide
# its missing Then. The LINE path removes a block only when it also holds no `- Given:` or `- Then:`
# bullet (round 2): a block written in block grammar that lacks its When is a real block with
# 0 When lines and must fail, even with a one-liner under it. The HEADER path stays unconditional
# (narrowing it too broke R7). A block that owns a When line is kept whatever one-liner it holds, so the
# bullet sibling (`- Negative: Given ...` inside a two-When Positive block) is still judged. Lines
# before the first header pass through. `tolower` on both sides rather than IGNORECASE, which only
# gawk has; ONE_LINE holds no escape `tolower` could change.
# It reads the fence-free copy, so a fenced line is never a header here (#490).
without_oneliner_headers() {
  printf '%s\n' "$1" | CTM_ANY="$MARK_ANY" CTM_ONE="$ONE_LINE" awk '
    BEGIN { any = ENVIRON["CTM_ANY"]; one = tolower(ENVIRON["CTM_ONE"]) }
    function flush() {
      if (!(inblk && n_when == 0 && (tolower(head) ~ one || (one_in && !n_gt)))) printf "%s", buf
      buf = ""
    }
    $0 ~ any { flush(); inblk = 1; head = $0; n_when = 0; one_in = 0; n_gt = 0; buf = $0 "\n"; next }
    inblk && /^[[:space:]]*[-*][[:space:]]*\**When\**[[:space:]]*:/ { n_when++ }
    inblk && /^[[:space:]]*[-*][[:space:]]*\**(Given|Then)\**[[:space:]]*:/ { n_gt++ }
    inblk && tolower($0) ~ one { one_in = 1 }
    { buf = buf $0 "\n" }
    END { flush() }
  '
}
ONE_LINE='^[[:space:]]*([-*][[:space:]]+)?([*][*]|__|[*]|_)?(Positive|Negative)([*][*]|__|[*]|_)?[.:].*(^|[^A-Za-z])Given([^A-Za-z]|$).*(^|[^A-Za-z])When([^A-Za-z]|$).*(^|[^A-Za-z])Then([^A-Za-z]|$)'
if [ -z "$SCENARIOS_LABEL" ]; then
  row gwt referred "no section matched Given/When/Then; the critic must judge section \"GWT scenarios\" unaided"
else
  SCENARIOS="$(section_of "$SCENARIOS_LABEL")"
  if ! has_content "$SCENARIOS"; then
    row gwt "$(empty_outcome "$SCENARIOS_LABEL")" "no content in $SCENARIOS_LABEL"
  else
    # TWO COPIES OF THE FIELD (#490). SCENARIOS stays raw: has_content above, and looks_na,
    # long_enough and first_line on the N/A branch, read it, so a fence holding only a reasoned N/A
    # stays `referred` and fence stripping never turns a refer into a fail. SCEN_BLOCKS is the field
    # with every fence line and fenced line removed, and EVERY block scan below reads it (the counts,
    # the one-line selector and its pair awk, without_oneliner_headers, when_counts, then_missing and
    # the vague-Then awk). Do not filter SCENARIOS in place. Accepted changes: a pair, or a one-liner,
    # that sits only inside a fence fails 0/0 where it passed or referred, a fenced-only pair whose
    # quote mentions N/A is `referred` by the raw looks_na, by design, and headers written outside
    # the fences with their Given/When/Then bullets inside them fail `Positive: 0 When lines;
    # Negative: 0 When lines` where they passed (round 1). The fence note names the fences on a
    # When-count or missing-Then fail only when the fences can be its cause (round 2): a When fail
    # needs a block reported at 0 When lines while the fences hide a When bullet (a fence
    # only removes lines, so it can lower a count, never raise it), and a missing-Then fail needs
    # the raw field to miss FEWER Thens than the fence-free one. A real second When or a real
    # missing Then beside an unrelated fenced example gets no note. The verdict stays fail.
    SCEN_BLOCKS="$(fence_free "$SCENARIOS")"
    WHEN_BULLET='^[[:space:]]*[-*][[:space:]]*[*]*When[*]*[[:space:]]*:'
    FENCE_NOTE=" (lines inside a fenced code block are not read)"
    fence_hid=0
    [ "$(printf '%s\n' "$SCENARIOS" | grep -cE "$WHEN_BULLET")" -eq "$(printf '%s\n' "$SCEN_BLOCKS" | grep -cE "$WHEN_BULLET")" ] ||
      fence_hid=1
    when_note() { case "$1" in *": 0 When lines"*) [ "$fence_hid" -eq 0 ] || printf '%s' "$FENCE_NOTE" ;; esac; }
    then_note() { [ "$(then_missing "$SCENARIOS")" -ge "$1" ] || printf '%s' "$FENCE_NOTE"; }
    pos_count=$(printf '%s\n' "$SCEN_BLOCKS" | grep -cE "$MARK_POS")
    neg_count=$(printf '%s\n' "$SCEN_BLOCKS" | grep -cE "$MARK_NEG")
    one_line="$(printf '%s\n' "$SCEN_BLOCKS" | grep -m1 -iE "$ONE_LINE")"
    # Blocks are judged by their blocks (#479 review rounds 1 and 2): where any block exists, a
    # block HEADER that is a one-liner keeps the one-line form only while it owns no When line
    # (O5's `**Positive**: Given a. When b. Then c.`, which v9 failed with 0 When lines); a header
    # that owns When lines is a block, so a missing polarity or a When count still fails. Any other
    # one-liner keeps the form only while the pair is incomplete; inside a valid pair a stray prose
    # line is left to the block checks. Keeping the form no longer hides the other blocks (#487):
    # the refer branch below judges them first, with the no-When header blocks removed.
    # Inside a pair, the LINES of a block owning no When line keep the form too (#487 review
    # round 1): `**Positive**` and `**Negative**` grouping headers each holding only bullet
    # one-liners are scenarios the block scans cannot read. Since #479 that shape failed with
    # `Positive: 0 When lines; Negative: 0 When lines`; it refers again, as it did under #233.
    # Do not restore the fail. A block that owns a When line still contributes nothing here.
    if { [ "$pos_count" -gt 0 ] || [ "$neg_count" -gt 0 ]; } && [ -n "$one_line" ]; then
      pair=0; [ "$pos_count" -gt 0 ] && [ "$neg_count" -gt 0 ] && pair=1
      one_line="$(printf '%s\n' "$SCEN_BLOCKS" | CTM_ANY="$MARK_ANY" CTM_PAIR="$pair" awk '
        BEGIN { any = ENVIRON["CTM_ANY"]; pair = ENVIRON["CTM_PAIR"] + 0 }
        $0 ~ any { if (hdr != "" && whens == 0) print hdr; if (whens == 0) printf "%s", grp; hdr = $0; whens = 0; grp = ""; next }
        !pair { print }
        hdr != "" && /^[[:space:]]*[-*][[:space:]]*\**When\**[[:space:]]*:/ { whens++ }
        pair && hdr != "" { grp = grp $0 "\n" }
        END { if (hdr != "" && whens == 0) print hdr; if (whens == 0) printf "%s", grp }
      ' | grep -m1 -iE "$ONE_LINE")"
    fi
    # Order: a reasoned N/A (#241) is tested first, as check 5 tests it before a path, and only
    # where NO block exists, so an N/A mentioned inside a real pair is still a pair; then the
    # one-line form (#233), which first runs the When count and then the missing-Then scan on the
    # other blocks (#487) and refers only when both pass; then the block count. A bare N/A with no
    # reason is still a fail. Where a one-line form is present the polarity fail below never fires:
    # a one-liner is a scenario of its polarity the count cannot see (O3, L17). Where none is
    # present the polarity fail runs before the When count (L14). The vague-Then heuristic stays
    # behind the refer, since both outcomes are `referred`.
    if [ "$pos_count" -eq 0 ] && [ "$neg_count" -eq 0 ] && [ -z "$one_line" ] && looks_na "$SCENARIOS"; then
      if long_enough "$SCENARIOS"; then
        row gwt referred "scenarios claim N/A; legitimate only where section \"GWT scenarios\" finds no behaviour delta: $(first_line "$SCENARIOS")"
      else
        row gwt fail "scenarios claim a bare N/A with no reason: $(first_line "$SCENARIOS")"
      fi
    elif [ -n "$one_line" ]; then
      judged="$(without_oneliner_headers "$SCEN_BLOCKS")"
      multi_when="$(when_counts "$judged")"
      if [ -n "$multi_when" ]; then
        row gwt fail "each scenario block needs exactly one When ($multi_when)$(when_note "$multi_when")"
      elif missing_then="$(then_missing "$judged")"; [ "$missing_then" -gt 0 ]; then
        row gwt fail "a Negative block has no Then line$(then_note "$missing_then")"
      else
        row gwt referred "one-line scenario form; the critic must judge section \"GWT scenarios\" unaided: $(first_line "$one_line")"
      fi
    elif [ "$pos_count" -eq 0 ] || [ "$neg_count" -eq 0 ]; then
      row gwt fail "needs at least one Positive and one Negative block (found $pos_count positive, $neg_count negative)"
    else
      multi_when="$(when_counts "$SCEN_BLOCKS")"
      if [ -n "$multi_when" ]; then
        row gwt fail "each scenario block needs exactly one When ($multi_when)$(when_note "$multi_when")"
      else
        # EVERY negative block is judged, not just the first: a ticket with three conditions
        # would otherwise have two of its negatives unchecked. A digit-bearing status, a
        # quoted message, or an UPPER_SNAKE identifier is specific enough; anything else is
        # REFERRED, never failed, because this heuristic is narrower than the section "GWT scenarios"
        # quality bar on purpose and must not reject a message the canonical doc allows.
        vague="$(printf '%s\n' "$SCEN_BLOCKS" | CTM_NEG="$MARK_NEG" CTM_POS="$MARK_POS" awk '
          BEGIN { neg = ENVIRON["CTM_NEG"]; pos = ENVIRON["CTM_POS"] }
          $0 ~ neg { inneg = 1; seen = 0; next }
          $0 ~ pos { inneg = 0; next }
          inneg && !seen && /^[[:space:]]*[-*][[:space:]]*\**Then\**[[:space:]]*:/ { seen = 1; print }
        ' | grep -vE '[0-9]|"[^"]+"|'"'"'[^'"'"']+'"'"'|[A-Z][A-Z0-9_]{2,}' | head -1)"
        missing_then="$(then_missing "$SCEN_BLOCKS")"
        if [ "$missing_then" -gt 0 ]; then
          row gwt fail "a Negative block has no Then line$(then_note "$missing_then")"
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

if [ -z "$UNIT_LABEL" ]; then
  row unit_tests referred "no section matched unit tests; the critic must judge section \"Unit test specs\" unaided"
else
  UNIT="$(section_of "$UNIT_LABEL")"
  # N/A is tested BEFORE a path, here and in the E2E branch below, so the two cannot disagree:
  # an N/A that happens to cite a path is still an N/A claim for the critic to rule on.
  if ! has_content "$UNIT"; then
    row unit_tests "$(empty_outcome "$UNIT_LABEL")" "no content in $UNIT_LABEL"
  elif looks_na "$UNIT"; then
    row unit_tests referred "unit tests claim N/A; legitimate only where section \"Unit test specs\" is out of scope: $(first_line "$UNIT")"
  elif names_path "$UNIT"; then
    row unit_tests pass "$(first_line "$UNIT")"
  else
    row unit_tests fail "unit tests name no file path: $(first_line "$UNIT")"
  fi
fi

if [ -z "$E2E_LABEL" ]; then
  row e2e_tests referred "no section matched E2E; the critic must judge section \"E2E test specs\" unaided"
else
  E2E="$(section_of "$E2E_LABEL")"
  if ! has_content "$E2E"; then
    row e2e_tests "$(empty_outcome "$E2E_LABEL")" "no content in $E2E_LABEL"
  elif looks_na "$E2E"; then
    # Whether the ticket touches UI at all (section "E2E test specs"), is Step 3B's call, so a reasoned N/A is
    # referred rather than passed, and an unreasoned one fails.
    if long_enough "$E2E"; then
      row e2e_tests referred "E2E N/A with a reason; section \"E2E test specs\" says a UI-touching ticket cannot claim it: $(first_line "$E2E")"
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
# Presence only. Whether a "none" reason HOLDS is section "Documentation currency", judged by the critic.
if [ -z "$DOCS_LABEL" ]; then
  row docs_impact referred "no section matched documentation impact; section \"Documentation currency\" is the critic's"
else
  DOCS="$(section_of "$DOCS_LABEL")"
  if ! has_content "$DOCS"; then
    row docs_impact "$(empty_outcome "$DOCS_LABEL")" "no content in $DOCS_LABEL"
  elif names_path "$DOCS"; then
    row docs_impact pass "$(first_line "$DOCS")"
  elif grep -qiE 'none|no doc' <<< "$DOCS"; then
    if long_enough "$DOCS"; then
      row docs_impact referred "claims no docs needed; section \"Documentation currency\" applies to every work ticket: $(first_line "$DOCS")"
    else
      row docs_impact fail "claims no docs needed with no reason given"
    fi
  else
    row docs_impact fail "names no docs and makes no explicit none claim: $(first_line "$DOCS")"
  fi
fi

exit 0
