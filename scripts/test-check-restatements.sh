#!/usr/bin/env bash
# Contract test for check-restatements.sh (issue #125).
#
# WHY THIS GUARD EXISTS. ticket-standards.md's Precedence section enumerates every place
# ticket-gate is allowed to restate a doc rule, and it used to certify itself complete. That claim
# was false every time it was made: three consecutive review rounds on PR #123 each found more
# entries, nine and counting. A maintainer who trusts a list like that edits one rule and ships a
# fork in the exact place the doc calls drift-free. This is the same defect class the repo already
# converted to guards twice (#96 the component inventory, #104 the label taxonomy).
#
# WHY DECLARED ANCHORS RATHER THAN FINGERPRINTS. The ticket proposed matching normalised phrases
# against paraphrased prose and accepted false positives. Declared anchors get both directions with
# NO fuzzy matching: a stale entry is an anchor that no longer resolves, and an unlisted restatement
# is a rule reference in a section no anchor covers. The cost is that an author must name the
# location, which is the thing they were getting wrong anyway.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-restatements.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# A fixture pair: a doc with a Precedence list, and a gate that restates rules.
mkfix() {                     # mkfix <dir> <precedence-items-file> <gate-file>
  mkdir -p "$1/docs/guides" "$1/gate"
  { echo "# Ticket standards"; echo
    # The guard reads the DEFINED rule numbers from these headings, so a fixture needs them or
    # nothing is a valid rule. This is also what stops "rules 400 lines below" parsing as rule 400.
    n=0; for t in "GWT scenarios (Given / When / Then)" "Unit test specs" "E2E test specs" "Personal data handling" "Security checklist" "Required reviews" "Documentation currency" "Implementation concreteness"; do n=$((n + 1)); echo "### $n. $t"; echo; done
    echo "## Precedence"; echo
    cat "$2"; echo; echo "## The N/A rule (load-bearing)"; echo "text"; } > "$1/docs/guides/ticket-standards.md"
  cp "$3" "$1/gate/ticket-gate.md"
}

cat > "$T/gate-ok.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
G
cat > "$T/items-ok.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
2. section "E2E test specs"'s UI E2E hard-fail bar in the critic's brief. <!-- anchor: "**UI E2E (section "E2E test specs"):**" -->
I

# --- matching: both directions clean ------------------------------------------------------------
mkfix "$T/a" "$T/items-ok.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/a/docs/guides/ticket-standards.md" "$T/a/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a complete, accurate list passes" || bad "complete list passes (rc=$rc: $out)"

# --- found-but-unlisted: the gate cites a rule in a section no anchor covers ---------------------
cat > "$T/items-missing.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
I
mkfix "$T/b" "$T/items-missing.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/b/docs/guides/ticket-standards.md" "$T/b/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an unlisted restatement fails the build" || bad "unlisted restatement fails"
case "$out" in *'UNLISTED restatement: section "E2E test specs" is cited in'*) ok "and it names the section that is unlisted" ;;
               *) bad "names the unlisted section (got: $out)" ;; esac
case "$out" in *"Step 3B"*) ok "and the section it was found in" ;;
               *) bad "names the section (got: $out)" ;; esac

# --- listed-but-absent: an anchor that no longer resolves ----------------------------------------
cat > "$T/items-stale.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
2. section "E2E test specs"'s UI E2E hard-fail bar in the critic's brief. <!-- anchor: "**UI E2E (section "E2E test specs"):**" -->
3. section "Threat model"'s retired bar. <!-- anchor: "this text was deleted from the gate" -->
I
mkfix "$T/c" "$T/items-stale.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/c/docs/guides/ticket-standards.md" "$T/c/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a stale list entry fails the build (the other direction)" || bad "stale entry fails"
case "$out" in *"this text was deleted"*) ok "and it quotes the anchor that no longer resolves" ;;
               *) bad "quotes the dead anchor (got: $out)" ;; esac

# --- an item with NO anchor is itself a failure, or the list rots silently -----------------------
cat > "$T/items-noanchor.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
2. section "E2E test specs"'s UI E2E bar, described but never anchored.
I
mkfix "$T/d" "$T/items-noanchor.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/d/docs/guides/ticket-standards.md" "$T/d/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an item with no anchor fails (it can never be checked)" || bad "unanchored item fails"

# --- the allowlist lets a genuine non-restatement mention through, with a reason -----------------
cat > "$T/gate-pointer.md" <<'G'
### Step 2.5: Select the review set
| Privacy regime | label `privacy` | appends section "Personal data handling" obligations, no restatement |
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
G
cat > "$T/items-allow.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Step 2.5 :: rule 4 :: routing pointer, states no bar of its own -->
I
mkfix "$T/e" "$T/items-allow.md" "$T/gate-pointer.md"
out=$(bash "$SCRIPT" "$T/e/docs/guides/ticket-standards.md" "$T/e/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "an allowlisted pointer passes" || bad "allowlisted pointer passes (rc=$rc: $out)"

cat > "$T/items-allow-noreason.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Step 2.5 :: rule 4 -->
I
mkfix "$T/f" "$T/items-allow-noreason.md" "$T/gate-pointer.md"
bash "$SCRIPT" "$T/f/docs/guides/ticket-standards.md" "$T/f/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "an allowlist entry with no reason is refused" || bad "allowlist demands a reason"

# A prefix match must still name a REAL section, or the allowlist becomes a mute button.
cat > "$T/items-allow-wrong.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Step 9.9 :: rule 4 :: names a section that does not exist -->
I
mkfix "$T/g" "$T/items-allow-wrong.md" "$T/gate-pointer.md"
bash "$SCRIPT" "$T/g/docs/guides/ticket-standards.md" "$T/g/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "an allowlist entry for the wrong section does not silence the real one" \
  || bad "allowlist prefix must still match a real section"

# --- round 1: the LAST item must not swallow the prose after it ---------------------------------
# The final item was bounded at end-of-block, so it absorbed the allowlist comment and the closing
# paragraphs. Its rule set grew to whatever those mentioned, and its anchor then whitelisted that
# section for rules it never covered: a brand-new rule-5 bar in Step 3A passed with exit 0.
cat > "$T/gate-tail.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
5. **Security bar** restating section "Security checklist" point for point, newly added and unlisted
G
cat > "$T/items-tail.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

Closing prose that mentions section "Security checklist" and section "Personal data handling" while explaining precedence.
I
mkfix "$T/h" "$T/items-tail.md" "$T/gate-tail.md"
out=$(bash "$SCRIPT" "$T/h/docs/guides/ticket-standards.md" "$T/h/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "trailing prose does not extend the last item's rule set" \
  || bad "trailing prose leaks into the last item (a new rule 5 bar passed)"

# --- round 1: a heading must be scoped to its FILE ----------------------------------------------
# Sections were keyed by heading text alone, and the agent and its companion skill both have a
# "Lens definitions" heading, so an anchor in one silently covered the other.
cat > "$T/gate-dup.md" <<'G'
### Lens definitions
The agent restates section "Security checklist" here, and nothing lists it.
G
cat > "$T/skill-dup.md" <<'G'
## Lens definitions
- OWASP Top 10: injection, XSS, CSRF
G
cat > "$T/items-dup.md" <<'I'
1. The security lens checklist restates section "Security checklist". <!-- anchor: "OWASP Top 10: injection, XSS, CSRF" -->
I
mkfix "$T/i" "$T/items-dup.md" "$T/gate-dup.md"
cp "$T/skill-dup.md" "$T/i/gate/SKILL.md"
out=$(bash "$SCRIPT" "$T/i/docs/guides/ticket-standards.md" "$T/i/gate/ticket-gate.md" "$T/i/gate/SKILL.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a same-named heading in another file does not grant coverage" \
  || bad "identical headings in two files collapse into one section"

# --- round 1: plural rule lists must parse ------------------------------------------------------
cat > "$T/gate-plural.md" <<'G'
### Step 0c
| Section | Derived from | restating section "Unit test specs" and section "Documentation currency" shape
G
cat > "$T/items-plural.md" <<'I'
1. The synthesis table restates the shape required by section "Unit test specs" and section "Documentation currency". <!-- anchor: "| Section | Derived from |" :: rules 2 and 7 -->
I
mkfix "$T/j" "$T/items-plural.md" "$T/gate-plural.md"
bash "$SCRIPT" "$T/j/docs/guides/ticket-standards.md" "$T/j/gate/ticket-gate.md" >/dev/null 2>&1
# The anchor is SCOPED because the item names two rules (#138.1). That also exercises the scope
# parser's own plural handling, which has to read "rules 2 and 7" the same way the prose does.
[ $? -eq 0 ] && ok "a scope 'rules 2 and 7' grants coverage for both" || bad "plural rule lists parse"

# --- round 1: a lone path argument must not silently check the repo instead ----------------------
bash "$SCRIPT" "$T/a/docs/guides/ticket-standards.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "one path argument is refused rather than silently ignored" \
  || bad "a single path argument is refused"

# --- round 1: headings inside fenced blocks are payload, not sections ----------------------------
# A heading inside a fenced block is template PAYLOAD. If it were treated as a section, an
# unlisted restatement would be reported against a heredoc body instead of the step that owns it.
cat > "$T/gate-fence.md" <<'G'
### Step 5: Post to the forge
```markdown
## ticket-gate: remediation guide
```
a bar restating section "Required reviews" that nothing lists
G
cat > "$T/items-fence.md" <<'I'
1. section "GWT scenarios"'s quality bar. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
I
cat > "$T/gate-fence2.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
G
mkfix "$T/k" "$T/items-fence.md" "$T/gate-fence2.md"
cp "$T/gate-fence.md" "$T/k/gate/extra.md"
out=$(bash "$SCRIPT" "$T/k/docs/guides/ticket-standards.md" "$T/k/gate/ticket-gate.md" "$T/k/gate/extra.md" 2>&1)
case "$out" in
  *"Step 5: Post to the forge"*) ok "an unlisted item is reported against the real heading" ;;
  *"remediation guide"*) bad "a fenced heading was treated as the section" ;;
  *) bad "fenced-heading case did not report as expected (got: $out)" ;;
esac

# --- round 2: a NEW restatement inside an already-anchored section must still be caught ---------
# Coverage used to be per whole section, so once Step 3B was anchored for rule 4 anywhere, a
# brand-new "(rule 4)" bar anywhere else in Step 3B passed. Coverage is now proximity-based.
cat > "$T/gate-near.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
- a long stretch of unrelated brief text
- another line of unrelated brief text
- yet another line of unrelated brief text
- and one more line of unrelated brief text
- and still more unrelated brief text
- and further unrelated brief text here
- **Newly added bar (section "E2E test specs"):** invented later, anchored by nobody
G
cat > "$T/items-near.md" <<'I'
1. section "E2E test specs"'s UI E2E bar in the critic's brief. <!-- anchor: "**UI E2E (section "E2E test specs"):**" -->
I
mkfix "$T/l" "$T/items-near.md" "$T/gate-near.md"
out=$(bash "$SCRIPT" "$T/l/docs/guides/ticket-standards.md" "$T/l/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a new restatement far from any anchor is caught inside a covered section" \
  || bad "per-section coverage hides a new bar in an anchored section"

# and the legitimate case: a rule reference ON or beside its anchor still passes
cat > "$T/gate-adj.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs,
  a call Step 3A confirms for section "E2E test specs" as well
G
mkfix "$T/m" "$T/items-near.md" "$T/gate-adj.md"
bash "$SCRIPT" "$T/m/docs/guides/ticket-standards.md" "$T/m/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a rule reference adjacent to its anchor still passes" || bad "adjacent reference passes"

# --- round 2: direction 2 must read the PLURAL form in the gate, not only in the doc -------------
cat > "$T/gate-plural2.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
5. a bar restating section "Security checklist" and section "Required reviews" that nothing lists
G
cat > "$T/items-plural2.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
I
mkfix "$T/n" "$T/items-plural2.md" "$T/gate-plural2.md"
out=$(bash "$SCRIPT" "$T/n/docs/guides/ticket-standards.md" "$T/n/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "two section citations on one gate line are both detected" \
  || bad "direction 2 reads the plural form"

# --- round 2: an allowlist entry must not be able to silence broadly ----------------------------
cat > "$T/items-broad.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Step :: rule 4 :: far too broad, matches every Step section -->
I
cat > "$T/gate-broad.md" <<'G'
### Step 2.5: Select the review set
a routing row mentioning section "Personal data handling"
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
### Step 3B: The critic
a second place mentioning section "Personal data handling"
G
mkfix "$T/o" "$T/items-broad.md" "$T/gate-broad.md"
out=$(bash "$SCRIPT" "$T/o/docs/guides/ticket-standards.md" "$T/o/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an allowlist prefix matching several sections is refused as too broad" \
  || bad "a broad allowlist prefix is refused"
case "$out" in *"too broad"*) ok "and it says the entry is too broad" ;;
               *) bad "names the breadth problem (got: $out)" ;; esac

# --- round 2: an allowlist rule field with no digits must fail, not be dropped -------------------
cat > "$T/items-nodigit.md" <<'I'
1. section "GWT scenarios"'s quality bar as a mechanical check. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Step 2.5 :: the privacy rule :: no rule number given -->
I
mkfix "$T/p" "$T/items-nodigit.md" "$T/gate-pointer.md"
bash "$SCRIPT" "$T/p/docs/guides/ticket-standards.md" "$T/p/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "an allowlist entry naming no rule number is refused" || bad "allowlist needs a rule number"

# --- round 3: a gate reference to a rule the doc does not define must be an ERROR --------------
# rules_in() silently dropped any number outside the doc's own rule set, which conflates "not a
# rule reference" with "a reference to a rule that no longer exists". A new (rule 9) bar passed,
# and renumbering a rule would make every stale gate reference invisible at once.
cat > "$T/gate-undef.md" <<'G'
### Step 3B: The critic
- **Threat-model bar (section "Threat model"):** invented, and section "Threat model" does not exist in the doc
G
cat > "$T/items-undef.md" <<'I'
1. section "GWT scenarios"'s quality bar. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->
I
mkfix "$T/q" "$T/items-undef.md" "$T/gate-undef.md"
out=$(bash "$SCRIPT" "$T/q/docs/guides/ticket-standards.md" "$T/q/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "the gate citing an undefined rule fails" || bad "undefined rule citation fails"
case "$out" in *"does not define"*) ok "and it says the doc does not define that rule" ;;
               *) bad "names the undefined rule (got: $out)" ;; esac

# --- round 3: an allowlist entry must be scoped to ONE section in ONE file ----------------------
cat > "$T/gate-share.md" <<'G'
### Lens definitions
a bar restating section "Security checklist" in the agent
G
cat > "$T/skill-share.md" <<'G'
## Lens definitions
a bar restating section "Security checklist" in the skill
G
cat > "$T/items-share.md" <<'I'
1. section "GWT scenarios"'s quality bar. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: Lens definitions :: rule 5 :: shared heading, silences two files -->
I
mkfix "$T/r" "$T/items-share.md" "$T/gate-share.md"
cp "$T/skill-share.md" "$T/r/gate/SKILL.md"
out=$(bash "$SCRIPT" "$T/r/docs/guides/ticket-standards.md" "$T/r/gate/ticket-gate.md" "$T/r/gate/SKILL.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an allowlist heading shared by two files is refused as too broad" \
  || bad "a shared heading silences both files"

# and a file-name entry must not silence a whole file's pre-heading region
cat > "$T/gate-top.md" <<'G'
a bar restating section "Security checklist" before any heading at all
### Step 3A: Mechanical checks
4. **GWT structure** (section "GWT scenarios" quality bar, the checkable half)
G
cat > "$T/items-top.md" <<'I'
1. section "GWT scenarios"'s quality bar. <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" -->

<!-- restatement-allow: ticket-gate.md :: rule 5 :: names a whole file -->
I
mkfix "$T/s" "$T/items-top.md" "$T/gate-top.md"
out=$(bash "$SCRIPT" "$T/s/docs/guides/ticket-standards.md" "$T/s/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an allowlist entry naming a whole file does not silence its top region" \
  || bad "a file-name allowlist entry silences the top region"

# --- fail closed on a missing input, never pass vacuously ----------------------------------------
bash "$SCRIPT" "$T/nope.md" "$T/gate-ok.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "a missing doc fails closed" || bad "missing doc fails closed"
bash "$SCRIPT" "$T/a/docs/guides/ticket-standards.md" "$T/nope.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "a missing gate fails closed" || bad "missing gate fails closed"

# --- the real repo must pass, or this guard is not actually adopted ------------------------------
out=$(bash "$SCRIPT" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "the repo's own Precedence list is complete and current" \
  || bad "repo Precedence list (rc=$rc): $out"

# --- #138.1: an anchor covers only the rules IT names, not every rule its item names ------------
# Coverage became per LOCATION in round 2, closing the per-section hole but not the per-item one:
# every anchor of an item granted coverage for every rule the item's prose mentioned. Item 1 names
# rules 3 AND 4, so a brand-new rule-4 bar one line after the rule-3 anchor inherits the licence.
cat > "$T/gate-scoped.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
- **Brand new consent bar (section "Personal data handling"):** invented after the anchor was written
G
cat > "$T/items-scoped.md" <<'I'
1. section "E2E test specs"'s UI E2E bar, and section "Personal data handling"'s personal-data judgment. <!-- anchor: "**UI E2E (section "E2E test specs"):**" -->
I
mkfix "$T/s1" "$T/items-scoped.md" "$T/gate-scoped.md"
out=$(bash "$SCRIPT" "$T/s1/docs/guides/ticket-standards.md" "$T/s1/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a new bar for another rule the item names is NOT covered by that item's anchor" \
                || bad "an anchor still grants coverage for every rule its item names"

# ...and an anchor may scope itself, so a legitimate multi-rule item still passes.
cat > "$T/items-scoped-ok.md" <<'I'
1. section "E2E test specs"'s UI E2E bar, and section "Personal data handling"'s personal-data judgment. <!-- anchor: "**UI E2E (section "E2E test specs"):**" :: rules 3 --> <!-- anchor: "**Brand new consent bar (section "Personal data handling"):**" :: rules 4 -->
I
mkfix "$T/s2" "$T/items-scoped-ok.md" "$T/gate-scoped.md"
out=$(bash "$SCRIPT" "$T/s2/docs/guides/ticket-standards.md" "$T/s2/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "per-anchor rule scoping lets a legitimate multi-rule item pass" \
                || bad "per-anchor scoping rejects a legitimate item (rc=$rc: $out)"

# ...and the scope must actually be OBEYED, not merely parsed. The case above passes even when the
# scope is ignored, because both anchors sit near both bars; this one does not. A sneaky rule-4 bar
# sits beside the rule-3 anchor, while the real rule-4 anchor is in another section, so ignoring the
# scope grants the sneaky bar coverage it has not got. Found by mutation, not by review.
cat > "$T/gate-obeyed.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
- **Sneaky new consent bar (section "Personal data handling"):** invented beside the section "E2E test specs" anchor

filler so the two sections are further apart than the coverage window

### Step 9: Elsewhere entirely
- **Personal-data judgment (section "Personal data handling"):** the real one
G
cat > "$T/items-obeyed.md" <<'I'
1. section "E2E test specs"'s UI E2E bar, and section "Personal data handling"'s personal-data judgment. <!-- anchor: "**UI E2E (section "E2E test specs"):**" :: rules 3 --> <!-- anchor: "**Personal-data judgment (section "Personal data handling"):**" :: rules 4 -->
I
mkfix "$T/s3" "$T/items-obeyed.md" "$T/gate-obeyed.md"
out=$(bash "$SCRIPT" "$T/s3/docs/guides/ticket-standards.md" "$T/s3/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a scope is obeyed: a bar beside another rule's anchor is not covered" \
                || bad "the scope is parsed but ignored; the sneaky bar inherited coverage"

# --- #138.2: a plural reference wrapped across a line break -------------------------------------
# Direction 2 evaluates per LINE while direction 1 evaluates per item, so "restating rules" ending
# one line and "5 and 6" starting the next matched neither pattern. Both gate files wrap at about
# 95 columns, so ordinary editing reaches this.
cat > "$T/gate-wrapped.md" <<'G'
### Step 9: Something new
This section is restating section "Security
checklist" and section "Required reviews", which no anchor covers.
G
cat > "$T/items-wrapped.md" <<'I'
1. section "GWT scenarios"'s quality bar. <!-- anchor: "This section is restating" -->
I
mkfix "$T/w" "$T/items-wrapped.md" "$T/gate-wrapped.md"
out=$(bash "$SCRIPT" "$T/w/docs/guides/ticket-standards.md" "$T/w/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a plural rule reference wrapped across a line break is still seen" \
                || bad "a wrapped plural reference is invisible to direction 2"

# --- #138.3: a multi-line anchor degrades to a prefix match -------------------------------------
# anchor_sites took needle.split('\n')[0], so a wrapped anchor silently became a PREFIX match and
# could resolve somewhere unintended. That contradicts the header's "no fuzzy matching at all", so
# it is refused rather than quietly narrowed.
cat > "$T/gate-one.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
G
{ printf '1. section "E2E test specs" bar. <!-- anchor: "**UI E2E (section "E2E test specs"):** a ticket\n'
  printf '   touching any UI needs" -->\n'; } > "$T/items-ml.md"
mkfix "$T/m" "$T/items-ml.md" "$T/gate-one.md"
out=$(bash "$SCRIPT" "$T/m/docs/guides/ticket-standards.md" "$T/m/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a multi-line anchor is refused rather than prefix-matched" \
                || bad "a multi-line anchor still degrades to a prefix match"
grep -qi 'one line' <<< "$out" \
  && ok "and says why" || bad "and says why (got: $out)"

# --- #138.4: an item naming no rule number covers nothing and passed ----------------------------
# An unanchored item is an error; an item whose prose names no rule was accepted while covering
# nothing. The "must name its rule" discipline was enforced on the gate side only.
cat > "$T/gate-norule.md" <<'G'
### Step 3B: The critic
- **Consent bar:** something with no rule citation at all
G
cat > "$T/items-norule.md" <<'I'
1. Something about the gate, with no number. <!-- anchor: "**Consent bar:**" -->
I
mkfix "$T/n" "$T/items-norule.md" "$T/gate-norule.md"
out=$(bash "$SCRIPT" "$T/n/docs/guides/ticket-standards.md" "$T/n/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an item that names no rule number is refused" \
                || bad "an item naming no rule still passes while covering nothing"
grep -qi 'names no section title' <<< "$out" \
  && ok "and says what is wrong" || bad "and says what is wrong (got: $out)"

# --- review round 1 on #138's own fixes ---------------------------------------------------------
# F3: the joined tail's rules were attributed to the FIRST line, so the coverage window was measured
# from the wrong place and a reference whose anchor sits two lines below it read as unlisted.
cat > "$T/gate-wrapline.md" <<'G'
### Step 9: Something
This section is restating section "Security
checklist" and section "Required reviews", covered just below.
- **the section "Security checklist" bar** anchored here
- **the section "Required reviews" bar** anchored here
G
cat > "$T/items-wrapline.md" <<'I'
1. section "Security checklist"'s bar. <!-- anchor: "**the section "Security checklist" bar**" :: rules 5 -->
2. section "Required reviews"'s bar. <!-- anchor: "**the section "Required reviews" bar**" :: rules 6 -->
I
mkfix "$T/r1" "$T/items-wrapline.md" "$T/gate-wrapline.md"
out=$(bash "$SCRIPT" "$T/r1/docs/guides/ticket-standards.md" "$T/r1/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a wrapped reference is measured from the line it is ON" \
                || bad "the joined tail is still attributed to the first line ($out)"

# F5: TRAILING_PLURAL fired on any line ending with the bare word "rules", so prose followed by a
# markdown ordered list joined into a phantom reference.
cat > "$T/gate-list.md" <<'G'
### Step 9: Something
The section below lists the rules
3. A markdown list item, not a rule reference
G
cat > "$T/items-list.md" <<'I'
1. section "GWT scenarios"'s bar. <!-- anchor: "The section below lists" :: rules 1 -->
I
mkfix "$T/r2" "$T/items-list.md" "$T/gate-list.md"
out=$(bash "$SCRIPT" "$T/r2/docs/guides/ticket-standards.md" "$T/r2/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "an ordered-list item is not joined into a phantom rule reference" \
                || bad "prose followed by a numbered list still reads as a rule reference ($out)"

# F6: the multi-rule scoping error skipped the staleness check for that item, the exact cascade the
# sibling check documents avoiding.
cat > "$T/items-both.md" <<'I'
1. section "E2E test specs"'s bar and section "Personal data handling"'s judgment. <!-- anchor: "this text is not in the gate" -->
I
mkfix "$T/r3" "$T/items-both.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/r3/docs/guides/ticket-standards.md" "$T/r3/gate/ticket-gate.md" 2>&1); rc=$?
case "$out" in *"this text is not in the gate"*) ok "an unscoped multi-rule item STILL reports its stale anchor" ;;
               *) bad "the scoping error suppressed the staleness check ($out)" ;; esac

# F7: `:: rules 3 and 44` dropped 44 silently, because the check only fired when EVERY number was
# undefined.
cat > "$T/items-partial.md" <<'I'
1. section "E2E test specs"'s bar and section "GWT scenarios"'s bar. <!-- anchor: "**UI E2E (section "E2E test specs"):**" :: rules 3 and 44 --> <!-- anchor: "(section "GWT scenarios" quality bar, the checkable half)" :: rules 1 -->
I
mkfix "$T/r4" "$T/items-partial.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/r4/docs/guides/ticket-standards.md" "$T/r4/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a scope naming one undefined rule is refused, not silently narrowed" \
                || bad "an undefined rule in a scope is dropped silently"

# --- review round 2: two regressions in round 1's own fixes ------------------------------------
# R6: dropping `continue` let the unscoped anchor grant coverage for EVERY rule the item names,
# which is the #138.1 blanket licence coming back. The item must still be reported STALE where its
# anchor is dead, and grant NOTHING.
cat > "$T/gate-blanket.md" <<'G'
### Step 3B: The critic
- **UI E2E (section "E2E test specs"):** a ticket touching any UI needs E2E specs
- **Brand new consent bar (section "Personal data handling"):** invented after the anchor was written
G
cat > "$T/items-blanket.md" <<'I'
1. section "E2E test specs"'s UI E2E bar, and section "Personal data handling"'s personal-data judgment. <!-- anchor: "**UI E2E (section "E2E test specs"):**" -->
I
mkfix "$T/x1" "$T/items-blanket.md" "$T/gate-blanket.md"
out=$(bash "$SCRIPT" "$T/x1/docs/guides/ticket-standards.md" "$T/x1/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an unscoped multi-rule item still fails" || bad "an unscoped multi-rule item still fails"
grep -q 'unscoped anchor' <<< "$out" \
  && ok "and says the anchor is unscoped" || bad "and says the anchor is unscoped"
grep -q 'UNLISTED restatement: section "Personal data handling"' <<< "$out" \
  && ok "and its anchor grants NOTHING, so the personal-data bar is still unlisted" \
  || bad "the unscoped anchor granted coverage anyway (the #138.1 blanket licence is back)"

# R1: the wrapped-plural fix measured coverage only from the TAIL line, so an anchor above the HEAD
# line, previously covered, started failing. Either line must satisfy the window.
cat > "$T/gate-above.md" <<'G'
### Step 9: Something
- **the section "Security checklist" bar** anchored above
and here we are restating section "Security
checklist" in wrapped form, and section "Required reviews".
- **the section "Required reviews" bar** anchored below
G
cat > "$T/items-above.md" <<'I'
1. section "Security checklist"'s bar. <!-- anchor: "**the section "Security checklist" bar**" :: rules 5 -->
2. section "Required reviews"'s bar. <!-- anchor: "**the section "Required reviews" bar**" :: rules 6 -->
I
mkfix "$T/x2" "$T/items-above.md" "$T/gate-above.md"
out=$(bash "$SCRIPT" "$T/x2/docs/guides/ticket-standards.md" "$T/x2/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "an anchor above the HEAD line still covers a wrapped reference" \
                || bad "the wrapped fix broke coverage from above ($out)"

# =====================================================================================================
# #510: a standards section is cited by its TITLE, never by its number.
# A project that adapts ticket-standards.md renumbers or inserts sections, so a gate review that said
# "rule 3" pointed at the wrong section there. The guard keys on the fixed introducer `section "Title"`,
# resolved to the doc's own number through a title map, and treats a bare numbered citation in any
# scanned file as a hard error. Anchor scopes (`:: rules N`) stay numeric: they live only in the doc.
# =====================================================================================================
echo "== #510: citations by title =="

# --- the title form is recognised, wherever the gate wraps or escapes it --------------------------
cat > "$T/gate-esc.md" <<'G'
### Step 3A: Mechanical checks
row e2e referred "E2E N/A with a reason; section \"E2E test specs\" says a UI-touching ticket cannot claim it"
G
cat > "$T/items-e2e.md" <<'I'
1. The E2E check restates section "E2E test specs". <!-- anchor: "E2E N/A with a reason" -->
I
cat > "$T/gate-esc-undef.md" <<'G'
### Step 3A: Mechanical checks
row e2e referred "E2E N/A with a reason; section \"Nonexistent section\" says so"
G
cat > "$T/gate-esc-unlisted.md" <<'G'
### Step 3A: Mechanical checks
row e2e referred "E2E N/A with a reason; section \"E2E test specs\" says a UI-touching ticket cannot claim it"
a long stretch of unrelated text
another long stretch of unrelated text
and one more stretch of unrelated text
row docs referred "claims no docs needed; section \"Documentation currency\" applies to every work ticket"
G
cat > "$T/gate-noint.md" <<'G'
### Step 3A: Mechanical checks
the counts are "none", "class" and "E2E test specs" and "Nonexistent section", quoted but never cited
G
cat > "$T/gate-wraptitle.sh" <<'G'
#!/usr/bin/env bash
# E2E rows: see section "E2E
# test specs" for the bar
G
cat > "$T/items-wraptitle.md" <<'I'
1. The E2E rows restate section "E2E test specs". <!-- anchor: "# E2E rows: see section" -->
I
r510_esc()     { mkfix "$T/n510e" "$T/items-e2e.md" "$T/gate-esc.md"; run510 "$T/n510e"; }
r510_pass()    { mkfix "$T/n510p" "$T/items-ok.md" "$T/gate-ok.md"; run510 "$T/n510p"; }
# run510 <fixture dir> [gate file name]: run the guard (G overrides the script) on a fixture made by mkfix
run510() { local g="${2:-ticket-gate.md}"; [ -e "$1/gate/$g" ] || cp "$T/$g" "$1/gate/$g"
  bash "${G510:-$SCRIPT}" "$1/docs/guides/ticket-standards.md" "$1/gate/$g" 2>&1; }

out=$(r510_pass); rc=$?
[ "$rc" -eq 0 ] && ok "#510: a doc and gate that cite sections by title pass" || bad "#510: a title-citing fixture failed ($out)"

out=$(r510_esc); rc=$?
[ "$rc" -eq 0 ] && ok "#510: the shell-escaped form section \\\"Title\\\" is recognised and covered by its anchor" \
                || bad "#510: an escaped title citation was not recognised ($out)"
out=$(mkfix "$T/n510e2" "$T/items-e2e.md" "$T/gate-esc-undef.md"; bash "$SCRIPT" "$T/n510e2/docs/guides/ticket-standards.md" "$T/n510e2/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "#510: an escaped citation of an undefined title fails with exit 1" || bad "#510: escaped undefined title rc=$rc ($out)"
case "$out" in *'cites section "Nonexistent section", which this doc does not define'*) ok "#510: and the FAIL text names the title the doc does not define" ;;
               *) bad "#510: undefined-title text (got: $out)" ;; esac

mkfix "$T/n510n" "$T/items-ok.md" "$T/gate-noint.md"
out=$(bash "$SCRIPT" "$T/n510n/docs/guides/ticket-standards.md" "$T/n510n/gate/ticket-gate.md" 2>&1); rc=$?
case "$out" in *"does not define"*|*"numbered citation"*) bad "#510: a quoted string without the introducer was examined ($out)" ;;
               *) ok "#510: quoted words without the introducer (\"none\", \"class\", a bare \"Nonexistent section\") are never examined" ;; esac

mkfix "$T/n510wr" "$T/items-wraptitle.md" "$T/gate-wraptitle.sh"
cp "$T/gate-wraptitle.sh" "$T/n510wr/gate/ticket-gate.md"
out=$(bash "$SCRIPT" "$T/n510wr/docs/guides/ticket-standards.md" "$T/n510wr/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "#510: a title wrapped across two comment lines resolves to its section" \
                || bad "#510: a wrapped title was not resolved ($out)"

# --- a bare numbered citation is a HARD error naming file, line and match ----------------------------
bare510() {   # bare510 <dir> <line text> <expect-match>: a gate with the text on line 2 must fail naming both
  printf '### Step 3A: Mechanical checks\n%s\n' "$2" > "$1.md"
  mkfix "$1" "$T/items-ok.md" "$1.md"
  local o r; o=$(bash "${G510:-$SCRIPT}" "$1/docs/guides/ticket-standards.md" "$1/gate/ticket-gate.md" 2>&1); r=$?
  [ "$r" -eq 1 ] && grep -qF "ticket-gate.md:2 numbered citation '$3'" <<< "$o"; }
bare510 "$T/n510b1" 'the bar is rule 3 here' 'rule 3' && ok "#510: 'rule 3' fails, naming the file, the line and the match" || bad "#510: 'rule 3' was not a hard error"
bare510 "$T/n510b2" 'the rule-1 quality bar' 'rule-1' && ok "#510: the hyphenated 'rule-1' fails" || bad "#510: 'rule-1' was not a hard error"
bare510 "$T/n510b3" 'Rule 2 says so' 'Rule 2' && ok "#510: a capitalised 'Rule 2' fails" || bad "#510: 'Rule 2' was not a hard error"
bare510 "$T/n510b4" 'see rules 2, 3, 4 and 7 for it' 'rules 2, 3, 4 and 7' && ok "#510: a plural 'rules 2, 3, 4 and 7' fails" || bad "#510: a plural was not a hard error"
printf '### Step 3A: Mechanical checks\nthis restates rules\n3 and 4 across a wrap\n' > "$T/n510b5.md"
mkfix "$T/n510b5" "$T/items-ok.md" "$T/n510b5.md"
out=$(bash "$SCRIPT" "$T/n510b5/docs/guides/ticket-standards.md" "$T/n510b5/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -qF "ticket-gate.md:2 numbered citation 'rules 3 and 4'" <<< "$out" \
  && ok "#510: a plural wrapped across a line fails, naming the line it starts on" || bad "#510: a wrapped plural was not a hard error ($out)"
printf '### Step 3A: Mechanical checks\nthe re-run rules 400 lines below, and rules 4000 of them\n' > "$T/n510b6.md"
mkfix "$T/n510b6" "$T/items-ok.md" "$T/n510b6.md"
out=$(bash "$SCRIPT" "$T/n510b6/docs/guides/ticket-standards.md" "$T/n510b6/gate/ticket-gate.md" 2>&1)
case "$out" in *"numbered citation"*) false ;; *) true ;; esac && ok "#510: 'rules 400 lines' is prose, not a citation" || bad "#510: 'rules 400' was read as a citation"

# --- each of the five default targets is scanned: a numbered citation in any of them fails ----------
# The default file list is built from the guard's own location, so each tree is a throwaway `git init`
# tree holding a copy of the guard (the guard resolves its root through git).
mk510tree() {   # mk510tree <dir>: a clean tree with every default target present
  local d="$1" g="plugins/forge-kit-governance" f
  mkdir -p "$d/scripts" "$d/docs/guides" "$d/$g/agents" "$d/$g/skills/ticket-gate-reference/assets" \
           "$d/$g/skills/ticket-gate-reference/references" "$d/$g/skills/decision-brief"
  cp "$SCRIPT" "$d/scripts/check-restatements.sh"
  git init -q "$d" 2>/dev/null
  cp "$T/a/docs/guides/ticket-standards.md" "$d/docs/guides/ticket-standards.md"
  cp "$T/gate-ok.md" "$d/$g/agents/ticket-gate.md"
  for f in skills/ticket-gate-reference/SKILL.md skills/ticket-gate-reference/assets/check-ticket-mechanics.sh \
           skills/ticket-gate-reference/references/lens.md skills/decision-brief/SKILL.md; do
    printf '# nothing here\n' > "$d/$g/$f"
  done
}
TARGETS510="agents/ticket-gate.md skills/ticket-gate-reference/SKILL.md skills/ticket-gate-reference/assets/check-ticket-mechanics.sh skills/ticket-gate-reference/references/lens.md skills/decision-brief/SKILL.md"
mk510tree "$T/n510t"
out=$(cd "$T/n510t" && bash scripts/check-restatements.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "#510: the clean default-target tree passes" || bad "#510: the clean default-target tree failed ($out)"
target510() {   # target510 <dir> <relpath>: 0 when a 'rule 3' appended to that file fails the guard naming it
  local d="$1" f="plugins/forge-kit-governance/$2" o r
  mk510tree "$d"; printf 'a stray rule 3 citation\n' >> "$d/$f"
  o=$(cd "$d" && bash scripts/check-restatements.sh 2>&1); r=$?
  local n; n=$(wc -l < "$d/$f")
  [ "$r" -eq 1 ] && grep -qF "$f:$n numbered citation 'rule 3'" <<< "$o"; }
i510=0
for tg in $TARGETS510; do
  i510=$((i510 + 1))
  target510 "$T/n510t$i510" "$tg" && ok "#510: a 'rule 3' in $tg fails, naming file and line" \
                                   || bad "#510: a 'rule 3' in $tg did not fail the guard"
done

# --- the doc may renumber: detection keys on titles ----------------------------------------------
mkfix "$T/n510r" "$T/items-ok.md" "$T/gate-ok.md"
sed -i 's/^### 3\. E2E test specs/### 5. E2E test specs/; s/^### 5\. Security checklist/### 3. Security checklist/' "$T/n510r/docs/guides/ticket-standards.md"
out=$(bash "$SCRIPT" "$T/n510r/docs/guides/ticket-standards.md" "$T/n510r/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "#510: renumbering the doc's sections does not break detection (titles are the key)" \
                || bad "#510: a renumbered doc failed ($out)"
sed -i 's/^### 5\. E2E test specs/### 5. Renamed section/' "$T/n510r/docs/guides/ticket-standards.md"
out=$(bash "$SCRIPT" "$T/n510r/docs/guides/ticket-standards.md" "$T/n510r/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "#510: renaming a section turns the gate's old title into an undefined citation" \
                || bad "#510: a renamed section was not noticed (rc=$rc)"

# --- mutants: each row above must be able to fail ---------------------------------------------------
# A mutant is a cp copy of the guard with one behaviour removed. Each must make its named row fail.
mut510() {   # mut510 <name> <sed expr> <row function that must now fail>
  mkdir -p "$T/mut"; sed "$2" "$SCRIPT" > "$T/mut/$1.sh"
  if cmp -s "$SCRIPT" "$T/mut/$1.sh"; then bad "#510: mutant $1 did not apply"; return; fi
  if G510="$T/mut/$1.sh" "$3" >/dev/null 2>&1; then bad "#510: MUTANT $1 SURVIVED ($3 still passed)"
  else ok "#510: MUTANT $1: the row fails with the behaviour removed"; fi
}
row_bare() { bare510 "$T/n510m1" 'the bar is rule 3 here' 'rule 3'; }
mut510 no-bare-detection 's/^    """(offset, matched text).*$/&\n    return []/' row_bare
row_pass() { out=$(r510_pass); [ $? -eq 0 ]; }
mut510 no-title-map 's/TITLES\.get(t)/None/' row_pass
row_esc() { local o; o=$(r510_esc) || return 1
  mkfix "$T/n510eu" "$T/items-e2e.md" "$T/gate-esc-unlisted.md"
  o=$(bash "${G510:-$SCRIPT}" "$T/n510eu/docs/guides/ticket-standards.md" "$T/n510eu/gate/ticket-gate.md" 2>&1)
  grep -qF 'UNLISTED restatement: section "Documentation currency"' <<< "$o"; }
mut510 no-escaped-form '/^SECTIONREF = /s/\\\\?"/"/g' row_esc
row_noint() { mkfix "$T/n510mi" "$T/items-ok.md" "$T/gate-noint.md"
  local o; o=$(bash "${G510:-$SCRIPT}" "$T/n510mi/docs/guides/ticket-standards.md" "$T/n510mi/gate/ticket-gate.md" 2>&1)
  ! grep -q 'does not define' <<< "$o"; }
mut510 no-introducer 's/\\b\[Ss\]ection\\s+//' row_noint
row_wrap() { mkfix "$T/n510mw" "$T/items-wraptitle.md" "$T/gate-wraptitle.sh"; cp "$T/gate-wraptitle.sh" "$T/n510mw/gate/ticket-gate.md"
  bash "${G510:-$SCRIPT}" "$T/n510mw/docs/guides/ticket-standards.md" "$T/n510mw/gate/ticket-gate.md" >/dev/null 2>&1; }
mut510 no-wrap-normalise 's/^    return re.sub(r.\\s+., . ., re.sub(.*/    return re.sub(r"\\s+", " ", t).strip()/' row_wrap
# a mutant that stops scanning the last default target must fail that target's row
sed 's#decision-brief/SKILL.md#decision-brief/NOPE.md#' "$SCRIPT" > "$T/mut/skip-target.sh"
if cmp -s "$SCRIPT" "$T/mut/skip-target.sh"; then bad "#510: mutant skip-target did not apply"
else
  mk510tree "$T/n510ms"; cp "$T/mut/skip-target.sh" "$T/n510ms/scripts/check-restatements.sh"
  printf 'a stray rule 3 citation\n' >> "$T/n510ms/plugins/forge-kit-governance/skills/decision-brief/SKILL.md"
  o=$(cd "$T/n510ms" && bash scripts/check-restatements.sh 2>&1); r=$?
  [ "$r" -eq 1 ] && grep -qF "decision-brief/SKILL.md:" <<< "$o" \
    && bad "#510: MUTANT skip-target SURVIVED (the decision-brief row still passes)" \
    || ok "#510: MUTANT skip-target: dropping a default target fails that target's row"
fi

echo ""
echo "check-restatements tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
