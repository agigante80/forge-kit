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
    for n in 1 2 3 4 5 6 7 8; do echo "### $n. Rule $n"; echo; done
    echo "## Precedence"; echo
    cat "$2"; echo; echo "## The N/A rule (load-bearing)"; echo "text"; } > "$1/docs/guides/ticket-standards.md"
  cp "$3" "$1/gate/ticket-gate.md"
}

cat > "$T/gate-ok.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
### Step 3B: The critic
- **UI E2E (rule 3):** a ticket touching any UI needs E2E specs
G
cat > "$T/items-ok.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
2. Rule 3's UI E2E hard-fail bar in the critic's brief. <!-- anchor: "**UI E2E (rule 3):**" -->
I

# --- matching: both directions clean ------------------------------------------------------------
mkfix "$T/a" "$T/items-ok.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/a/docs/guides/ticket-standards.md" "$T/a/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "a complete, accurate list passes" || bad "complete list passes (rc=$rc: $out)"

# --- found-but-unlisted: the gate cites a rule in a section no anchor covers ---------------------
cat > "$T/items-missing.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
I
mkfix "$T/b" "$T/items-missing.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/b/docs/guides/ticket-standards.md" "$T/b/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an unlisted restatement fails the build" || bad "unlisted restatement fails"
case "$out" in *"rule 3"*) ok "and it names the rule that is unlisted" ;;
               *) bad "names the unlisted rule (got: $out)" ;; esac
case "$out" in *"Step 3B"*) ok "and the section it was found in" ;;
               *) bad "names the section (got: $out)" ;; esac

# --- listed-but-absent: an anchor that no longer resolves ----------------------------------------
cat > "$T/items-stale.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
2. Rule 3's UI E2E hard-fail bar in the critic's brief. <!-- anchor: "**UI E2E (rule 3):**" -->
3. Rule 9's retired bar. <!-- anchor: "this text was deleted from the gate" -->
I
mkfix "$T/c" "$T/items-stale.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/c/docs/guides/ticket-standards.md" "$T/c/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a stale list entry fails the build (the other direction)" || bad "stale entry fails"
case "$out" in *"this text was deleted"*) ok "and it quotes the anchor that no longer resolves" ;;
               *) bad "quotes the dead anchor (got: $out)" ;; esac

# --- an item with NO anchor is itself a failure, or the list rots silently -----------------------
cat > "$T/items-noanchor.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
2. Rule 3's UI E2E bar, described but never anchored.
I
mkfix "$T/d" "$T/items-noanchor.md" "$T/gate-ok.md"
out=$(bash "$SCRIPT" "$T/d/docs/guides/ticket-standards.md" "$T/d/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an item with no anchor fails (it can never be checked)" || bad "unanchored item fails"

# --- the allowlist lets a genuine non-restatement mention through, with a reason -----------------
cat > "$T/gate-pointer.md" <<'G'
### Step 2.5: Select the review set
| Privacy regime | label `privacy` | appends rule 4 obligations, no restatement |
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
G
cat > "$T/items-allow.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

<!-- restatement-allow: Step 2.5 :: rule 4 :: routing pointer, states no bar of its own -->
I
mkfix "$T/e" "$T/items-allow.md" "$T/gate-pointer.md"
out=$(bash "$SCRIPT" "$T/e/docs/guides/ticket-standards.md" "$T/e/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "an allowlisted pointer passes" || bad "allowlisted pointer passes (rc=$rc: $out)"

cat > "$T/items-allow-noreason.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

<!-- restatement-allow: Step 2.5 :: rule 4 -->
I
mkfix "$T/f" "$T/items-allow-noreason.md" "$T/gate-pointer.md"
bash "$SCRIPT" "$T/f/docs/guides/ticket-standards.md" "$T/f/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -ne 0 ] && ok "an allowlist entry with no reason is refused" || bad "allowlist demands a reason"

# A prefix match must still name a REAL section, or the allowlist becomes a mute button.
cat > "$T/items-allow-wrong.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

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
4. **GWT structure** (rule 1 quality bar, the checkable half)
5. **Security bar** restating rule 5 point for point, newly added and unlisted
G
cat > "$T/items-tail.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

Closing prose that mentions rule 5 and rule 4 while explaining precedence.
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
The agent restates rule 5 here, and nothing lists it.
G
cat > "$T/skill-dup.md" <<'G'
## Lens definitions
- OWASP Top 10: injection, XSS, CSRF
G
cat > "$T/items-dup.md" <<'I'
1. The security lens checklist restates rule 5. <!-- anchor: "OWASP Top 10: injection, XSS, CSRF" -->
I
mkfix "$T/i" "$T/items-dup.md" "$T/gate-dup.md"
cp "$T/skill-dup.md" "$T/i/gate/SKILL.md"
out=$(bash "$SCRIPT" "$T/i/docs/guides/ticket-standards.md" "$T/i/gate/ticket-gate.md" "$T/i/gate/SKILL.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a same-named heading in another file does not grant coverage" \
  || bad "identical headings in two files collapse into one section"

# --- round 1: plural rule lists must parse ------------------------------------------------------
cat > "$T/gate-plural.md" <<'G'
### Step 0c
| Section | Derived from | restating rule 2 and rule 7 shape
G
cat > "$T/items-plural.md" <<'I'
1. The synthesis table restates the shape required by rules 2 and 7. <!-- anchor: "| Section | Derived from |" -->
I
mkfix "$T/j" "$T/items-plural.md" "$T/gate-plural.md"
bash "$SCRIPT" "$T/j/docs/guides/ticket-standards.md" "$T/j/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a plural 'rules 2 and 7' grants coverage for both" || bad "plural rule lists parse"

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
a bar restating rule 6 that nothing lists
G
cat > "$T/items-fence.md" <<'I'
1. Rule 1's quality bar. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
I
cat > "$T/gate-fence2.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
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
- **UI E2E (rule 3):** a ticket touching any UI needs E2E specs
- a long stretch of unrelated brief text
- another line of unrelated brief text
- yet another line of unrelated brief text
- and one more line of unrelated brief text
- and still more unrelated brief text
- and further unrelated brief text here
- **Newly added bar (rule 3):** invented later, anchored by nobody
G
cat > "$T/items-near.md" <<'I'
1. Rule 3's UI E2E bar in the critic's brief. <!-- anchor: "**UI E2E (rule 3):**" -->
I
mkfix "$T/l" "$T/items-near.md" "$T/gate-near.md"
out=$(bash "$SCRIPT" "$T/l/docs/guides/ticket-standards.md" "$T/l/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a new restatement far from any anchor is caught inside a covered section" \
  || bad "per-section coverage hides a new bar in an anchored section"

# and the legitimate case: a rule reference ON or beside its anchor still passes
cat > "$T/gate-adj.md" <<'G'
### Step 3B: The critic
- **UI E2E (rule 3):** a ticket touching any UI needs E2E specs,
  a call Step 3A confirms for rule 3 as well
G
mkfix "$T/m" "$T/items-near.md" "$T/gate-adj.md"
bash "$SCRIPT" "$T/m/docs/guides/ticket-standards.md" "$T/m/gate/ticket-gate.md" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a rule reference adjacent to its anchor still passes" || bad "adjacent reference passes"

# --- round 2: direction 2 must read the PLURAL form in the gate, not only in the doc -------------
cat > "$T/gate-plural2.md" <<'G'
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
5. a bar restating rules 5 and 6 that nothing lists
G
cat > "$T/items-plural2.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
I
mkfix "$T/n" "$T/items-plural2.md" "$T/gate-plural2.md"
out=$(bash "$SCRIPT" "$T/n/docs/guides/ticket-standards.md" "$T/n/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a plural 'rules 5 and 6' in the GATE is detected too" \
  || bad "direction 2 reads the plural form"

# --- round 2: an allowlist entry must not be able to silence broadly ----------------------------
cat > "$T/items-broad.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

<!-- restatement-allow: Step :: rule 4 :: far too broad, matches every Step section -->
I
cat > "$T/gate-broad.md" <<'G'
### Step 2.5: Select the review set
a routing row mentioning rule 4
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
### Step 3B: The critic
a second place mentioning rule 4
G
mkfix "$T/o" "$T/items-broad.md" "$T/gate-broad.md"
out=$(bash "$SCRIPT" "$T/o/docs/guides/ticket-standards.md" "$T/o/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an allowlist prefix matching several sections is refused as too broad" \
  || bad "a broad allowlist prefix is refused"
case "$out" in *"too broad"*) ok "and it says the entry is too broad" ;;
               *) bad "names the breadth problem (got: $out)" ;; esac

# --- round 2: an allowlist rule field with no digits must fail, not be dropped -------------------
cat > "$T/items-nodigit.md" <<'I'
1. Rule 1's quality bar as a mechanical check. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

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
- **Threat-model bar (rule 9):** invented, and rule 9 does not exist in the doc
G
cat > "$T/items-undef.md" <<'I'
1. Rule 1's quality bar. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->
I
mkfix "$T/q" "$T/items-undef.md" "$T/gate-undef.md"
out=$(bash "$SCRIPT" "$T/q/docs/guides/ticket-standards.md" "$T/q/gate/ticket-gate.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "the gate citing an undefined rule fails" || bad "undefined rule citation fails"
case "$out" in *"does not define"*) ok "and it says the doc does not define that rule" ;;
               *) bad "names the undefined rule (got: $out)" ;; esac

# --- round 3: an allowlist entry must be scoped to ONE section in ONE file ----------------------
cat > "$T/gate-share.md" <<'G'
### Lens definitions
a bar restating rule 5 in the agent
G
cat > "$T/skill-share.md" <<'G'
## Lens definitions
a bar restating rule 5 in the skill
G
cat > "$T/items-share.md" <<'I'
1. Rule 1's quality bar. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

<!-- restatement-allow: Lens definitions :: rule 5 :: shared heading, silences two files -->
I
mkfix "$T/r" "$T/items-share.md" "$T/gate-share.md"
cp "$T/skill-share.md" "$T/r/gate/SKILL.md"
out=$(bash "$SCRIPT" "$T/r/docs/guides/ticket-standards.md" "$T/r/gate/ticket-gate.md" "$T/r/gate/SKILL.md" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an allowlist heading shared by two files is refused as too broad" \
  || bad "a shared heading silences both files"

# and a file-name entry must not silence a whole file's pre-heading region
cat > "$T/gate-top.md" <<'G'
a bar restating rule 5 before any heading at all
### Step 3A: Mechanical checks
4. **GWT structure** (rule 1 quality bar, the checkable half)
G
cat > "$T/items-top.md" <<'I'
1. Rule 1's quality bar. <!-- anchor: "(rule 1 quality bar, the checkable half)" -->

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

echo ""
echo "check-restatements tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
