#!/usr/bin/env bash
# citation-check-version: 5
# citation-check.sh: find the ticket-standards section titles the gate cites that the project's own
# doc does not have (#519).
#
# Since #510 the gate cites a rule of docs/guides/ticket-standards.md by TITLE, as `section "Unit
# test specs"`, because a project that adapts the doc renumbers or renames sections. A renamed
# section leaves the gate pointing at a heading that is not there, and neither the version markers
# nor stale-rules.sh can see it. This reads the citing components, collects every cited title and
# checks each against the headings of the project's doc. READ ONLY: it writes nothing anywhere.
#
# Usage: citation-check.sh [--kit <forge-kit dir>] [--project <dir>] [--doc <ticket-standards.md>]
#
#   --kit      the forge-kit checkout, the LAST resort for a citing file (forge-adapt passes
#              $FORGE_KIT_DIR), and the home of the kit's own docs/guides/ticket-standards.md,
#              read for rename candidates only. Default: the checkout this script sits in, when
#              it has a plugins/ directory; otherwise there is no kit fallback.
#   --project  the project to check. Default: the current directory.
#   --doc      the doc to read the headings and markers from. Default:
#              <project>/docs/guides/ticket-standards.md.
#
# WHICH COPY OF A CITING FILE IS READ, first that exists:
#   0. for check-ticket-mechanics only, the project's scripts/check-ticket-mechanics.sh, where the
#      installer copies it and the copy the project runs (#556); a symlink there, or a symlinked
#      scripts/ directory, is ignored;
#   1. the project's own copy under .claude/ (same path below agents/ or skills/); a symlink there is
#      ignored, the project may be untrusted;
#   2. the live plugin copy: an entry of <config dir>/plugins/installed_plugins.json for the file's
#      plugin group whose scope is `user`, or `local`/`project` with a projectPath equal to the
#      project, read at that entry's installPath (several cached versions coexist, so the registry
#      decides, never a glob of the cache). The config dir is $CLAUDE_CONFIG_DIR, default ~/.claude;
#   3. the forge-kit checkout.
# FILES SCANNED (the only components that cite a section; the list is data below, one place):
#   ticket-gate, check-ticket-mechanics (including its user-facing evidence strings, where the
#   quotes are escaped), and privacy-regime FROM THE PROJECT'S OWN COPY ONLY (step 1): it is a
#   per-project fill-in template and the gate reads no other copy, so a plugin or kit copy is never
#   a citer and its absence prints no row (#547). adapt's references/skills.md is not a citer: the
#   project never runs it as a gate.
#
# MATCHING. A citation is `section "Title"`, or `section \"Title\"` inside a shell string, and may
# wrap across lines (a leading `# ` of a wrapped comment is tolerated). A heading of the doc is
# `#`..`######`, an optional leading `N. `, the title, a trailing parenthetical dropped, so
# `### 1. GWT scenarios (Given / When / Then)` is "GWT scenarios". The match is the whole title, not
# a substring ("Unit test specs for the API layer" is not "Unit test specs"), and a heading inside
# a fenced code block does not count. These are the rules scripts/check-restatements.sh applies to
# the kit's own gate; that script is repo-only and cannot ship, so the grammar is restated here.
# If one changes, change the other (scripts/test-forge-adapt-citation-check.sh pins this copy).
#
# MARKERS (#543, #547), read from the doc, one per line, outside any fenced block, parsed as data
# and never evaluated:
#   <!-- citation-alias: "<Cited title>" = "<Heading>" -->   the project renamed that section
#   <!-- citation-acknowledged: "<Cited title>" -->           the project has no such section, on purpose
# Whitespace around the parts is tolerated; the whole line must be the marker, so text before or
# after it, two on a line, another key or a missing quote or `=` is not a marker and prints nothing.
# A line opening a marker with no `-->` on it is citation-marker-invalid. Titles and targets are
# normalised as a heading is (whitespace collapsed, leading `N. ` and trailing parenthetical
# dropped) and compared exactly, case sensitive. Rules, for one title: a real heading wins over
# both markers; an alias beats an acknowledgement; the first alias in the doc wins, and a later one
# to a different target is invalid when the first printed citation-aliased, stale otherwise (never
# promoted); an identical repeat is one row; a marker that changes no outcome (an uncited title, a
# title with a real heading, a superseded marker) is stale. The alias target check is EXISTENCE
# ONLY, by design: the target is a real heading of the doc, nothing checks it is the right section.
# A skipped doc reads no markers. Line numbers count "\n" only (CRLF and CR are read as "\n").
# A SECOND READER (#557): forge-kit-governance's check-ticket-mechanics.sh reads the alias lines
# alone, under these same rules, to name the project's heading in its evidence. Change a rule here
# and change it there; scripts/test-check-ticket-mechanics.sh runs both and fails if they disagree.
#
# OUTPUT, stdout, tab separated, in this order:
#   citation-missing         "<Title>"                 a cited title the doc has no heading, alias or acknowledgement for
#   citation-rename-candidate "<Title>" "<Heading>"  a GUESS for a missing title, in kit order (below)
#   citation-marker-invalid  "<Title>"  "<Heading>"    a cited title's alias to a missing heading, or a conflicting later alias
#   citation-marker-invalid  line <N>                  a marker with no closing --> (N: 1-based doc line)
#   citation-aliased         "<Title>"  "<Heading>"    an applied alias
#   citation-acknowledged    "<Title>"                 an applied acknowledgement
#   citation-marker-stale    "<Title>"                 a marker that changes no outcome; suppressed on any
#                                                      run that prints not-scanned (what it cites is unknown)
#   skipped                  no ticket-standards doc   the doc does not exist (one line, however many titles)
#   not-scanned              <what>  <reason>          ticket-gate/not installed, or an unreadable file or doc
#   summary                  <titles checked>  <missing>  <not-scanned>          (always last)
# Each marker group prints in marker line order. An aliased or acknowledged title counts as checked
# and not missing.
# RENAME CANDIDATES (#544), only when the kit's doc exists: order alone, never a section number.
# Anchors are the doc start and end, each kit heading whose title the project doc has, and each
# alias whose target it has; an acknowledged title leaves the kit side first. If the anchors are in
# another order in the project doc, nothing is offered. Between two anchors the unmatched kit and
# project headings of one level pair in order only when their counts are equal, and a pair is a row
# only when its kit title is cited and missing. A heading holding a double quote or a control
# character is never offered (an alias line cannot name it). The row is a guess the user confirms
# by adding a citation-alias line; it changes neither the summary nor the exit code.
# EXIT 0 nothing missing or invalid and everything scanned (a skipped doc is clean); 1 at least one
# citation-missing or citation-marker-invalid row (invalid is the second exit-1 cause, since #547);
# 3 nothing missing or invalid but something was not scanned (incomplete is never clean); 2 usage
# error, nothing on stdout. aliased, acknowledged and stale rows never change the exit code.
set -uo pipefail
export LC_ALL=C

usage() {
  echo "citation-check: $1" >&2
  echo "usage: citation-check.sh [--kit <dir>] [--project <dir>] [--doc <file>]" >&2
  exit 2
}

HERE=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd -P) || usage "cannot locate the script directory"
KIT=""; PROJECT=""; DOC=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --kit)     [ "$#" -ge 2 ] || usage "--kit needs a value";     KIT="$2"; shift 2 ;;
    --project) [ "$#" -ge 2 ] || usage "--project needs a value"; PROJECT="$2"; shift 2 ;;
    --doc)     [ "$#" -ge 2 ] || usage "--doc needs a value";     DOC="$2"; shift 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
[ -n "$PROJECT" ] || PROJECT=.
[ -d "$PROJECT" ] || usage "no such project directory '$PROJECT'"
if [ -z "$KIT" ] && [ -d "$HERE/../../../../../plugins" ]; then KIT="$HERE/../../../../.."; fi
if [ -n "$KIT" ] && [ ! -d "$KIT/plugins" ]; then usage "'$KIT' is not a forge-kit checkout (no plugins/)"; fi
command -v python3 >/dev/null 2>&1 || usage "python3 is required"
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"

python3 -I - "$PROJECT" "$KIT" "$DOC" "${CFG%/}" <<'PY'
import json, os, re, sys

project, kit, doc_arg, cfg = sys.argv[1:5]
project = os.path.realpath(project)
doc_path = doc_arg or os.path.join(project, "docs", "guides", "ticket-standards.md")

# The citing components: (label, plugin group, path below the group). The first one is the gate
# itself; when it does not resolve, nothing the project runs can be checked.
# The last field says whether the plugin registry and the kit may supply the file: privacy-regime is a
# per-project fill-in template the gate reads only from the project's own copy (#547).
CITING = [
    ("ticket-gate", "forge-kit-governance", "agents/ticket-gate.md", True),
    ("check-ticket-mechanics", "forge-kit-governance", "skills/ticket-gate-reference/assets/check-ticket-mechanics.sh", True),
    ("privacy-regime", "forge-kit-security", "skills/privacy-regime/SKILL.md", False),
]

def registry_roots(group):
    """installPath of every registry entry for this group that counts for this project."""
    try:
        with open(os.path.join(cfg, "plugins", "installed_plugins.json"), encoding="utf-8") as f:
            plugins = json.load(f).get("plugins", {})
    except (OSError, ValueError, AttributeError):
        return []
    out = []
    for pid, entries in plugins.items():
        if pid.split("@")[0] != group or not isinstance(entries, list):
            continue
        for e in entries:
            if not isinstance(e, dict) or not e.get("installPath"):
                continue
            scope, pp = e.get("scope") or "", e.get("projectPath") or ""
            if scope == "user" or (scope in ("local", "project") and pp and os.path.realpath(pp) == project):
                out.append(e["installPath"])
    return out

# The citers a project runs from its own scripts/ directory: the installer copies
# check-ticket-mechanics.sh verbatim to scripts/check-ticket-mechanics.sh (#556).
PROJECT_SCRIPT = {"check-ticket-mechanics"}

def candidates(label, group, rel, shared):
    if label in PROJECT_SCRIPT:
        sp = os.path.join(project, "scripts", os.path.basename(rel))
        # A symlinked copy, or one below a symlinked scripts/ directory, is skipped although the
        # gate's own `[ -f ]` test would follow the link and run it: the project tree is untrusted
        # and a link may point outside it, so the next candidate is read instead.
        if not os.path.islink(sp) and not os.path.islink(os.path.dirname(sp)):
            yield sp
    if rel.startswith(("agents/", "skills/")):
        p = os.path.join(project, ".claude", rel)
        if not os.path.islink(p):
            yield p
    if not shared:
        return
    for root in registry_roots(group):
        yield os.path.join(root, rel)
    if kit:
        yield os.path.join(kit, "plugins", group, rel)

rows, unscanned = [], 0
def not_scanned(what, why):
    global unscanned
    rows.append(f"not-scanned\t{what}\t{why}")
    unscanned += 1

# Citations, in order of first appearance, each title once.
SECTIONREF = re.compile(r'\b[Ss]ection\s+\\?"([^"\\]+?)\\?"')
PAREN = re.compile(r'\s*\([^)]*\)\s*$')                 # a heading's trailing parenthetical
HEADING = re.compile(r'^#{1,6}\s+(?:\d+\.\s+)?(.+?)\s*#*\s*$')  # an optional leading "N. " is not part of the title
def norm_title(t):
    return re.sub(r'\s+', ' ', re.sub(r'\s*\n\s*(?:#\s*)?', ' ', t)).strip()
def norm_marker(t):
    """A marker title or alias target, normalised as a heading is (shared marker rules)."""
    t = PAREN.sub('', norm_title(t))
    return re.sub(r'\s+', ' ', re.sub(r'^\d+\.\s+', '', t)).strip()
# The markers (#543, #547): the whole line must be the marker, outside a fence; anything else is not one.
ALIAS = re.compile(r'^\s*<!--\s*citation-alias:\s*"([^"]+)"\s*=\s*"([^"]+)"\s*-->\s*$')
ACKNOWLEDGED = re.compile(r'^\s*<!--\s*citation-acknowledged:\s*"([^"]+)"\s*-->\s*$')
UNTERMINATED = re.compile(r'^\s*<!--\s*citation-(?:alias|acknowledged):(?!.*-->)')
titles = []
for label, group, rel, shared in CITING:
    found = next((p for p in candidates(label, group, rel, shared) if os.path.isfile(p)), None)
    if found is None:
        if label == "ticket-gate":
            not_scanned("ticket-gate", "not installed")
        continue
    try:
        with open(found, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        not_scanned(label, "unreadable")
        continue
    for m in SECTIONREF.finditer(text):
        t = norm_title(m.group(1))
        if t and t not in titles:
            titles.append(t)

# The doc.
headings, skipped, markers, hlist = None, False, [], []
if os.path.islink(doc_path) and not os.path.exists(doc_path):
    not_scanned("docs/guides/ticket-standards.md" if not doc_arg else doc_arg, "dangling symlink")
elif not os.path.exists(doc_path):
    skipped = True
elif not os.path.isfile(doc_path):
    not_scanned("docs/guides/ticket-standards.md" if not doc_arg else doc_arg, "not a file")
else:
    try:
        with open(doc_path, encoding="utf-8", errors="replace") as f:
            doc = f.read()
        headings, fenced = set(), None
        # Split on "\n" only: the read already turned CRLF and CR into "\n", and a form feed or a
        # U+2028 inside a line must not move the line number a citation-marker-invalid row reports.
        for n, line in enumerate(doc.split("\n"), 1):
            fm = re.match(r'^\s*(```+|~~~+)', line)
            if fm:
                fence = fm.group(1)[0]
                fenced = None if fenced == fence else (fenced or fence)
                continue
            if fenced:
                continue
            h = HEADING.match(line)
            if h:
                headings.add(re.sub(r'\s+', ' ', PAREN.sub('', h.group(1))).strip())
                hlist.append((len(line) - len(line.lstrip("#")), re.sub(r'\s+', ' ', PAREN.sub('', h.group(1))).strip()))
                continue
            a, k = ALIAS.match(line), ACKNOWLEDGED.match(line)
            if a and norm_marker(a.group(1)) and norm_marker(a.group(2)):
                markers.append(("alias", norm_marker(a.group(1)), norm_marker(a.group(2)), n))
            elif k and norm_marker(k.group(1)):
                markers.append(("ack", norm_marker(k.group(1)), None, n))
            elif UNTERMINATED.match(line):
                markers.append(("unterminated", None, None, n))
    except OSError:
        not_scanned("docs/guides/ticket-standards.md" if not doc_arg else doc_arg, "unreadable")

# Resolve the markers (the shared marker rules of #543 and #547). Each marker gets one outcome, kept
# with its line so every group prints in marker line order. An alias is "applied" when it printed
# citation-aliased; a marker that changes no outcome is stale.
cited = set(titles)
first_alias = {}                      # title -> the target of its first alias in the doc
for kind, t, target, n in markers:
    if kind == "alias":
        first_alias.setdefault(t, target)
outcome, covered, seen = [], set(), set()
for kind, t, target, n in markers:
    if kind == "unterminated":        # no title on it can be trusted, so it is reported by line
        outcome.append(("invalid", n, f"line {n}"))
        continue
    if (kind, t, target) in seen:     # a repeat of an identical marker is not a conflict: one row
        continue
    seen.add((kind, t, target))
    if t not in cited or t in headings:
        outcome.append(("stale", n, f'"{t}"'))                  # nothing cites it, or a heading wins
    elif kind == "alias" and target != first_alias[t]:
        if first_alias[t] in headings:                          # conflicts with an applied first alias
            outcome.append(("invalid", n, f'"{t}"\t"{target}"'))
        else:                                                   # the first was not applied: never promoted
            outcome.append(("stale", n, f'"{t}"'))
    elif kind == "alias" and target in headings:
        covered.add(t)
        outcome.append(("aliased", n, f'"{t}"\t"{target}"'))
    elif kind == "alias":                                       # existence only, by design
        outcome.append(("invalid", n, f'"{t}"\t"{target}"'))
    elif t in first_alias:                                      # an alias beats an acknowledgement
        outcome.append(("stale", n, f'"{t}"'))
    else:
        covered.add(t)
        outcome.append(("acknowledged", n, f'"{t}"'))

checked = missing = 0
if skipped:
    rows.append("skipped\tno ticket-standards doc")
elif headings is not None:
    for t in titles:
        checked += 1
        if t not in headings and t not in covered:
            missing += 1
            rows.append(f'citation-missing\t"{t}"')
invalid = sum(1 for o in outcome if o[0] == "invalid")

# Rename candidates (#544): a cited, missing title the kit's own doc places in the same stretch as an
# unmatched project heading. Order only, never a section number. Anchors are the doc start and end,
# every kit heading whose title the project doc has, and every alias whose target it has; an
# acknowledged title leaves the kit side first. Anchors out of order in the project doc: no candidate
# anywhere. Between two anchors, the unmatched kit and project headings of one level pair in order
# only when their counts are equal. A heading holding a double quote or a control character is never
# offered: the alias line cannot name it. A guess the user confirms; it changes no count or exit code.
def kit_heading_list(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return []
    out, fenced = [], None
    for line in text.split("\n"):
        fm = re.match(r'^\s*(```+|~~~+)', line)
        if fm:
            fence = fm.group(1)[0]
            fenced = None if fenced == fence else (fenced or fence)
            continue
        h = None if fenced else HEADING.match(line)
        if h:
            out.append((len(line) - len(line.lstrip("#")), re.sub(r'\s+', ' ', PAREN.sub('', h.group(1))).strip()))
    return out
candidate_rows = []
missing_titles = {r.split("\t", 1)[1][1:-1] for r in rows if r.startswith("citation-missing\t")}
if missing_titles and kit and os.path.isfile(os.path.join(kit, "docs", "guides", "ticket-standards.md")):
    proj = hlist
    pos = {}
    for j, (lv, t) in enumerate(proj):
        pos.setdefault(t, j)
    alias_to = {t: g for t, g in first_alias.items() if g in pos}
    acked = {t for kind, t, target, n in markers if kind == "ack"}
    kitl = [(lv, t) for lv, t in kit_heading_list(os.path.join(kit, "docs", "guides", "ticket-standards.md"))
            if not (t in acked and t not in pos and t not in alias_to)]
    anchors, used = [], set()
    for i, (lv, t) in enumerate(kitl):
        j = pos.get(t, pos.get(alias_to.get(t)))
        if j is not None and j not in used:
            anchors.append((i, j))
            used.add(j)
    if [j for i, j in anchors] == sorted(j for i, j in anchors):
        bounds = [(-1, -1)] + anchors + [(len(kitl), len(proj))]
        for (i0, j0), (i1, j1) in zip(bounds, bounds[1:]):
            ku = [(i, lv, t) for i, (lv, t) in enumerate(kitl[i0 + 1:i1], i0 + 1)]
            pu = [(lv, t) for j, (lv, t) in enumerate(proj[j0 + 1:j1], j0 + 1) if j not in used]
            for level in sorted({lv for i, lv, t in ku}):
                K = [(i, t) for i, lv, t in ku if lv == level]
                Pl = [t for lv, t in pu if lv == level]
                if len(K) != len(Pl):
                    continue
                for (i, k), h in zip(K, Pl):
                    if k in missing_titles and k != h and '"' not in h and not re.search(r'[\x00-\x1f\x7f]', h):
                        candidate_rows.append((i, f'citation-rename-candidate\t"{k}"\t"{h}"'))
candidate_rows = [r for i, r in sorted(candidate_rows)]
if unscanned:                         # the titles an unscanned file cites are unknown: never call a marker stale
    outcome = [o for o in outcome if o[0] != "stale"]
ORDER = ("invalid", "aliased", "acknowledged", "stale")
outcome.sort(key=lambda o: (ORDER.index(o[0]), o[1]))
marker_rows = [f"citation-marker-{o[0]}\t{o[2]}" if o[0] in ("invalid", "stale") else f"citation-{o[0]}\t{o[2]}" for o in outcome]

# citation-missing rows first, then the rename candidates, the marker rows, the rest, summary last.
rows.sort(key=lambda r: 0 if r.startswith("citation-missing") else 1)
nmiss = sum(1 for r in rows if r.startswith("citation-missing"))
rows[nmiss:nmiss] = candidate_rows + marker_rows
for r in rows:
    print(r)
print(f"summary\t{checked}\t{missing}\t{unscanned}")
sys.exit(1 if missing or invalid else 3 if unscanned else 0)
PY
