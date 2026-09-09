#!/usr/bin/env bash
# check-restatements.sh: verify ticket-standards.md's Precedence list against the gate (issue #125).
#
# THE DEFECT THIS REPLACES. The Precedence section enumerates every place `ticket-gate` restates a
# doc rule, and it used to certify itself as the complete set. That claim was false every time it
# was made: three consecutive review rounds on PR #123 each found more entries, nine and counting.
# A maintainer editing a rule consults the list, edits what it names, and ships a fork in the exact
# place the doc calls drift-free. Same class as the component inventory (#96) and the label
# taxonomy (#104), both already converted from declarative prose to a guard.
#
# HOW IT CHECKS, and why not fingerprints. The ticket proposed matching normalised phrases against
# paraphrased prose, accepting false positives. Declared ANCHORS get both directions with no fuzzy
# matching at all:
#   listed-but-absent  an item's anchor no longer appears in the gate  -> the entry is stale.
#   found-but-unlisted a `rule N` reference sits in a section that no item's anchor covers.
# The cost is that an author must name the location precisely, which is the thing they were getting
# wrong. An item with NO anchor fails too: it can never be checked, so it would rot silently.
#
# A mention that genuinely does not restate anything (a routing pointer that states no bar of its
# own) goes in the allowlist, which REQUIRES a reason, so waving one through is a visible edit.
#
# Usage: check-restatements.sh [<ticket-standards.md> <ticket-gate.md> [<extra file>...]]
# With no arguments it checks this repo, including the gate's companion reference skill, whose
# content is part of the gate for this purpose (issue #109 moved the lens briefs there).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$#" -eq 1 ]; then
  echo "check-restatements: give BOTH a doc and at least one gate file, or no arguments at all" >&2
  exit 2
elif [ "$#" -ge 2 ]; then
  DOC="$1"; shift; GATE_FILES=("$@")
else
  ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-restatements: not a git checkout and no explicit paths given" >&2; exit 2; }
  DOC="$ROOT/docs/guides/ticket-standards.md"
  GATE_FILES=("$ROOT/plugins/forge-kit-governance/agents/ticket-gate.md"
              "$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/SKILL.md"
              "$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"
              # references/ too (#150). #150 moved the lens briefs and the templates one hop out of
              # SKILL.md so they stop being preloaded, and that immediately orphaned a Precedence
              # anchor. Without this line, moving prose into references/ would be a way to launder a
              # rule out of this guard's sight, which is the same hazard CLAUDE.md already records
              # for prose moved into a script.
              "$ROOT"/plugins/forge-kit-governance/skills/ticket-gate-reference/references/*.md
              # decision-brief (#129) runs the gate rather than citing it, and carries no copy of
              # its bars. That is a promise, and this is what keeps it one: a `rule N` reference
              # appearing here is an unlisted restatement and fails, the same as one in the gate.
              "$ROOT/plugins/forge-kit-governance/skills/decision-brief/SKILL.md")
fi

[ -r "$DOC" ] || { echo "check-restatements: cannot read '$DOC'" >&2; exit 2; }
for f in "${GATE_FILES[@]}"; do
  [ -r "$f" ] || { echo "check-restatements: cannot read '$f'" >&2; exit 2; }
done

python3 - "$DOC" "${GATE_FILES[@]}" <<'PY'
import re, sys

doc_path, gate_paths = sys.argv[1], sys.argv[2:]
doc = open(doc_path, encoding="utf-8").read()

m = re.search(r'^## Precedence\s*$(.*?)^## ', doc, re.M | re.S)
if not m:
    print("check-restatements: no '## Precedence' section in the doc", file=sys.stderr)
    sys.exit(2)
block = m.group(1)

# Numbered items. An item runs to the next "N. " at the start of a line, or the end of the block.
# An item runs from its "N. " line through its INDENTED continuations and blank lines, and stops
# at the first unindented line that is not another item. Bounding the last one at end-of-block
# swallowed the allowlist comment and the closing prose, whose rule mentions then joined that
# item's rule set: its single anchor went on to whitelist that section for rules 4 and 5.
items, cur = [], None
for line in block.split('\n'):
    if re.match(r'^\d+\. ', line):
        if cur is not None: items.append('\n'.join(cur))
        cur = [line]; continue
    if cur is None: continue
    if line.strip() == '' or line.startswith((' ', '\t')):
        cur.append(line); continue
    items.append('\n'.join(cur)); cur = None
if cur is not None: items.append('\n'.join(cur))
if not items:
    print("check-restatements: the Precedence section lists no numbered items", file=sys.stderr)
    sys.exit(2)

# An anchor may scope itself: `<!-- anchor: "..." :: rules 3 -->`. Without a scope it covers every
# rule its item names, which is the historical behaviour and is right for a single-rule item.
#
# WHY THE SCOPE EXISTS (#138.1). Coverage became per LOCATION in round 2 of PR #137, closing the
# per-section hole. It did not close the per-item one: every anchor of an item granted coverage for
# every rule that item's prose mentioned, so a brand-new bar for another of those rules, one line
# after the anchor, inherited the licence. The same class as the round-2 finding at five-line scale.
ANCHOR = re.compile(r'<!--\s*anchor:\s*"(.*?)"\s*(?:::\s*rules?\s*([\d,\s and]*?)\s*)?-->', re.S)
# The rule numbers this doc DEFINES, read from its own "### N. Title" headings, so the guard can
# never be argued into tracking a number that is not a rule.
VALID_RULES = set(re.findall(r'^### (\d+)\. ', doc, re.M))
if not VALID_RULES:
    print("check-restatements: the doc defines no numbered rules ('### N. Title')", file=sys.stderr)
    sys.exit(2)

RULEREF = re.compile(r'\brule[-\s](\d+)', re.I)
# "rules 2, 3, 4 and 7" is one mention of four rules; matching only the first granted rule 1 alone.
RULES_PLURAL = re.compile(r'\brules\s+((?:\d+(?:\s*(?:,|and)\s*)?)+)', re.I)

# A plural reference wrapped across a line break (#138.2). Direction 2 evaluates per LINE while
# direction 1 evaluates per item, so "restating rules" ending one line and "5 and 6" starting the
# next matched neither pattern. Both gate files wrap at about 95 columns, so ordinary editing
# reaches it. Only a line whose TAIL is an unfinished plural is joined with its successor, which
# keeps the join narrow: an ordinary line followed by one that happens to start with a digit is
# untouched.
TRAILING_PLURAL = re.compile(r'\brules\b[\d,\s]*(?:\band\b)?\s*$', re.I)

def undefined_rules_in(text):
    """Singular `rule N` citations naming a rule the doc does not define.

    Dropping these silently conflated "not a rule reference" with "a reference to a rule that no
    longer exists": a new (rule 9) bar passed, and renumbering a rule would have made every stale
    gate citation invisible while the guard reported the list complete."""
    return {r for r in RULEREF.findall(text) if r not in VALID_RULES}

def rules_in(text):
    found = set(RULEREF.findall(text))
    for mm in RULES_PLURAL.finditer(text):
        found.update(re.findall(r'\d+', mm.group(1)))
    # Only numbers the doc actually defines as rules. Without this the plural pattern read
    # "the re-run rules 400 lines from the steps they govern" as a reference to rule 400.
    return {r for r in found if r in VALID_RULES}

# Allowlist: "<section> :: rule <N> :: <reason>". The reason is mandatory.
allow, allow_bad = set(), []
for a in re.finditer(r'<!--\s*restatement-allow:\s*(.*?)\s*-->', doc, re.S):
    parts = [p.strip() for p in a.group(1).split('::')]
    if len(parts) < 3 or not parts[2]:
        allow_bad.append(a.group(1).strip()); continue
    rn = re.search(r'(\d+)', parts[1])
    if not rn:
        allow_bad.append(a.group(1).strip()); continue
    allow.add((parts[0], rn.group(1)))

# Gate text, attributed to its nearest preceding heading.
sections = []
for path in gate_paths:
    name = path.split('/')[-1]
    sec, fenced = f"{name} (top)", False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith('```'):
            fenced = not fenced
        elif not fenced:
            h = re.match(r'^#{2,4} (.+)', line)
            # Keyed by FILE too: ticket-gate.md and its companion skill share heading names, and
            # without this an anchor in one silently granted coverage in the other.
            if h: sec = f"{name} :: {h.group(1).strip()}"
        sections.append((sec, line))

def anchor_sites(needle):
    """Every (file, line index) where this literal anchor appears.

    Line-level rather than section-level: an anchor names one bar, and coverage has to be that
    precise or a bar added later in the same section inherits the anchor's licence."""
    hits = []
    for i, (sec, line) in enumerate(sections):
        if needle and needle in line:
            hits.append((sec.split(' :: ')[0], i))
    return hits

# How near a rule reference must be to an anchor that covers it. Anchors sit on or beside the bar
# they name, so this is deliberately tight: a bar invented later, elsewhere in an already-anchored
# section, is exactly what per-section coverage used to hide.
WINDOW = 2

# An allowlist entry must name ONE section. A bare prefix like "Step" matched every Step heading
# and silenced a rule across all of them, while the comment beside it claimed that was impossible.
all_sections = {sec for sec, _ in sections}
allow_broad = []
for ss, rr in sorted(allow):
    hits = {q for q in all_sections
            if q.startswith(ss) or (' :: ' in q and q.split(' :: ', 1)[1].startswith(ss))}
    if len(hits) > 1:
        allow_broad.append((ss, rr, sorted(hits)))

errors = []
for idx, (sec, line) in enumerate(sections):
    for r in sorted(undefined_rules_in(line)):
        errors.append(f"[{sec}] cites rule {r}, which this doc does not define "
                      f"(defined: {', '.join(sorted(VALID_RULES, key=int))})")
for ss, rr, hits in allow_broad:
    errors.append(f"allowlist entry '{ss} :: rule {rr}' is too broad: it matches "
                  f"{len(hits)} sections ({', '.join(hits[:3])}...). Name one.")
for bad in allow_bad:
    errors.append(f"allowlist entry has no reason (needs '<section> :: rule N :: <why>'): {bad}")

# Direction 1, listed-but-absent: every item needs an anchor, and every anchor must resolve.
covered = {}                     # rule -> list of (file, line) an item anchors it at
for n, item in enumerate(items, 1):
    anchors = ANCHOR.findall(item)
    rules = rules_in(item)
    if not anchors:
        errors.append(f"Precedence item {n} declares no anchor, so nothing can verify it")
        continue
    # An item that names no rule number covers nothing, and was accepted anyway (#138.4). The
    # "a restatement must cite its rule number" discipline was enforced on the GATE side only, so
    # the two sides disagreed about a rule the doc itself states.
    #
    # Keyed on naming NO number at all, not on naming no VALID one: an item citing a retired rule
    # is a different fault, and it must still reach the staleness check below rather than being
    # replaced by this message. For the same reason this does not `continue`.
    if not re.search(r'\brules?[-\s]\d+', item, re.I):
        errors.append(f"Precedence item {n} names no rule number, so it covers nothing. "
                      f"Cite the rule it restates, or scope its anchors with ':: rules N'.")

    # AN ITEM NAMING MORE THAN ONE RULE MUST SCOPE ITS ANCHORS (#138.1). Making the scope merely
    # AVAILABLE would not close the hole the ticket describes, because the items that leak are
    # exactly the ones nobody would bother to scope. Requiring it where ambiguity is possible
    # closes it by construction, and a single-rule item stays as simple as it was.
    if len(rules) > 1 and any(not sc for _, sc in anchors):
        errors.append(f"Precedence item {n} names rules {', '.join(sorted(rules, key=int))} but has "
                      f"an unscoped anchor. With more than one rule an anchor must say which it "
                      f"covers (':: rules N'), or a new bar for ANY of them inherits its licence.")
        # NOT `continue`, so the anchors below are still checked for STALENESS, which is the cascade
        # the sibling check above documents avoiding. But they grant NOTHING: letting them through
        # restored the #138.1 blanket licence, one cascade traded for another (review round 2).
        grant = False
    else:
        grant = True

    for a, scope in anchors:
        # A multi-line anchor used to be truncated to its first line, which silently turned an
        # exact match into a PREFIX match that could resolve somewhere unintended (#138.3). The
        # header promises no fuzzy matching at all, so this refuses rather than quietly narrowing.
        if '\n' in a:
            errors.append(f"Precedence item {n} has a multi-line anchor; an anchor must be on one "
                          f"line, because matching only its first line is a prefix match: \"{a[:60]}...\"")
            continue
        nums = re.findall(r'\d+', scope or '')
        scoped = {r for r in nums if r in VALID_RULES}
        # ANY undefined number refuses. Firing only when EVERY one was undefined let
        # ':: rules 3 and 44' silently drop 44, narrowing the scope without saying so.
        undef = [r for r in nums if r not in VALID_RULES]
        if undef:
            errors.append(f"Precedence item {n} scopes an anchor to rule(s) the doc does not "
                          f"define: {', '.join(undef)} (in '{scope}')")
            continue
        sites = anchor_sites(a)
        if not sites:
            errors.append(f"Precedence item {n} is STALE: anchor no longer appears in the gate: \"{a}\"")
        elif grant or scoped:
            # A SCOPED anchor is unambiguous and still grants, even in an item whose other anchors
            # are unscoped: the error above is about the unscoped ones.
            for r in (scoped or rules):
                covered.setdefault(r, []).extend(sites)

# Direction 2, found-but-unlisted: every rule reference must sit in a covered section.
seen = set()
tail_rules = {}          # line index -> rules whose text wrapped onto it from the line above
for idx, (sec, line) in enumerate(sections):
    fname = sec.split(' :: ')[0]
    # A wrapped plural: the rules found only in the JOINED text belong to the NEXT line, which is
    # where they are written. Attributing them here measured the coverage window from the wrong
    # line, so a reference whose anchor sat two lines below it read as unlisted (review round 1).
    #
    # And an ordered-list item is not a continuation. "...lists the rules" followed by "3. A list
    # item" joined into a phantom `rules 3`, which would fail a build over prose.
    here = rules_in(line)
    if TRAILING_PLURAL.search(line.rstrip('\n')) and idx + 1 < len(sections) \
       and sections[idx + 1][0] == sec \
       and not re.match(r'^\s*\d+\.\s', sections[idx + 1][1]):
        joined = rules_in(line.rstrip('\n') + ' ' + sections[idx + 1][1])
        for r in joined - here:
            tail_rules.setdefault(idx + 1, set()).add(r)
    for r in here | tail_rules.get(idx, set()):
        if (idx, r) in seen: continue
        seen.add((idx, r))
        head = sec.split(' :: ', 1)[1] if ' :: ' in sec else sec
        # An entry may name the heading ("Step 2.5") or the file-qualified form
        # ("ticket-gate.md :: Step 2.5"). Either way the too-broad check above counts how many
        # SECTIONS it reaches, so a shared heading or a bare file name is refused rather than
        # silencing everything it touches.
        if any(rr == r and (head.startswith(ss) or sec.startswith(ss))
               and not any(b[0] == ss and b[1] == rr for b in allow_broad) for ss, rr in allow):
            continue
        # A wrapped reference is written across TWO lines, so an anchor near either satisfies it.
        # Measuring only from the tail was the mirror of the bug it fixed: an anchor above the head
        # line, previously covered, started failing (review round 2).
        anchor_lines = [idx]
        if r in tail_rules.get(idx, set()):
            anchor_lines.append(idx - 1)
        near = [1 for f, li in covered.get(r, [])
                if f == fname and any(abs(li - a) <= WINDOW for a in anchor_lines)]
        if not near:
            errors.append(f"UNLISTED restatement: rule {r} is referenced in [{sec}] "
                          f"but no Precedence item anchors rule {r} within {WINDOW} lines of it")

if errors:
    print("check-restatements: the Precedence list does not match the gate.\n", file=sys.stderr)
    for e in errors: print(f"  x {e}", file=sys.stderr)
    print(f"\n{len(errors)} problem(s). Fix the list, or add an allowlist entry with a reason.",
          file=sys.stderr)
    sys.exit(1)

print(f"check-restatements: {len(items)} Precedence items, all anchored and current.")
PY
