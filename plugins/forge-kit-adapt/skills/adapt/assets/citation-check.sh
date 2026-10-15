#!/usr/bin/env bash
# citation-check-version: 1
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
#              $FORGE_KIT_DIR). Default: the checkout this script sits in, when it has a plugins/
#              directory; otherwise there is no kit fallback.
#   --project  the project to check. Default: the current directory.
#   --doc      the doc to read the headings from. Default: <project>/docs/guides/ticket-standards.md.
#
# WHICH COPY OF A CITING FILE IS READ, first that exists:
#   1. the project's own copy under .claude/ (same path below agents/ or skills/); a symlink there is
#      ignored, the project may be untrusted;
#   2. the live plugin copy: an entry of <config dir>/plugins/installed_plugins.json for the file's
#      plugin group whose scope is `user`, or `local`/`project` with a projectPath equal to the
#      project, read at that entry's installPath (several cached versions coexist, so the registry
#      decides, never a glob of the cache). The config dir is $CLAUDE_CONFIG_DIR, default ~/.claude;
#   3. the forge-kit checkout.
# FILES SCANNED (the only components that cite a section; the list is data below, one place):
#   ticket-gate, check-ticket-mechanics (including its user-facing evidence strings, where the
#   quotes are escaped), privacy-regime, and adapt's references/skills.md.
#
# MATCHING. A citation is `section "Title"`, or `section \"Title\"` inside a shell string, and may
# wrap across lines (a leading `# ` of a wrapped comment is tolerated). A heading of the doc is
# `#`..`######`, an optional leading `N. `, the title, a trailing parenthetical dropped, so
# `### 1. GWT scenarios (Given / When / Then)` is "GWT scenarios". The match is the whole title, not
# a substring ("Unit test specs for the API layer" is not "Unit test specs"), and a heading inside
# a fenced code block does not count. These are the rules scripts/check-restatements.sh applies to
# the kit's own gate; that script is repo-only and cannot ship, so the grammar is restated here.
# If one changes, change the other (scripts/test-check-citations.sh pins this copy).
#
# OUTPUT, stdout, tab separated:
#   citation-missing  "<Title>"                      a cited title the doc has no heading for
#   skipped           no ticket-standards doc        the doc does not exist (one line, however many titles)
#   not-scanned       <what>  <reason>               ticket-gate/not installed, or an unreadable file or doc
#   summary           <titles checked>  <missing>  <not-scanned>          (always last)
# EXIT 0 nothing missing and everything scanned (a skipped doc is clean); 1 at least one
# citation-missing row; 3 nothing missing but something was not scanned (incomplete is never
# clean); 2 usage error, nothing on stdout.
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
CITING = [
    ("ticket-gate", "forge-kit-governance", "agents/ticket-gate.md"),
    ("check-ticket-mechanics", "forge-kit-governance", "skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"),
    ("privacy-regime", "forge-kit-security", "skills/privacy-regime/SKILL.md"),
    ("adapt-skills", "forge-kit-adapt", "skills/adapt/references/skills.md"),
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

def candidates(group, rel):
    if rel.startswith(("agents/", "skills/")):
        p = os.path.join(project, ".claude", rel)
        if not os.path.islink(p):
            yield p
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
titles = []
for label, group, rel in CITING:
    found = next((p for p in candidates(group, rel) if os.path.isfile(p)), None)
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
headings, skipped = None, False
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
        for line in doc.splitlines():
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
    except OSError:
        not_scanned("docs/guides/ticket-standards.md" if not doc_arg else doc_arg, "unreadable")

checked = missing = 0
if skipped:
    rows.append("skipped\tno ticket-standards doc")
elif headings is not None:
    for t in titles:
        checked += 1
        if t not in headings:
            missing += 1
            rows.append(f'citation-missing\t"{t}"')

# citation-missing rows first, then the rest, summary last.
rows.sort(key=lambda r: 0 if r.startswith("citation-missing") else 1)
for r in rows:
    print(r)
print(f"summary\t{checked}\t{missing}\t{unscanned}")
sys.exit(1 if missing else 3 if unscanned else 0)
PY
