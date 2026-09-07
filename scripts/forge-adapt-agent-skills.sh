#!/usr/bin/env bash
# forge-adapt-agent-skills.sh: read the `skills:` frontmatter field of an agent (issue #124).
#
# WHY THIS EXISTS. Claude Code's `agents/` directory is a FLAT namespace owned by the loader, which
# claims every .md under it at any depth, so an agent can never carry a `references/` directory the
# way a skill can (probed against `claude plugin validate`: a nested AGENT.md is silently skipped
# and the reference file is reported as the agent instead). The supported way to give an agent
# reference material is a COMPANION SKILL named in its `skills:` frontmatter, whose content Claude
# Code injects into the subagent at startup.
#
# forge-adapt therefore has a dependency edge to follow at install time: an agent that declares
# `skills:` needs those skills installed too, and the plugin-scoped `plugin-name:skill-name` form
# has to become the bare name a project skill answers to. Both steps are mechanical and fiddly, and
# this repo already knows what happens when a mechanical step stays prose: the S3 catalogue became
# a script because an LLM executor kept reintroducing fixed bugs. So forge-adapt runs this verbatim.
#
# THE FAILURE IT PREVENTS is silent. A declared skill that is missing is "skipped with a warning to
# the debug log", so an agent installed without its companion skill runs with its lens material
# gone and nothing in the project shows a problem.
#
# Usage:
#   forge-adapt-agent-skills.sh <agent.md>             print declared skills verbatim, one per line
#   forge-adapt-agent-skills.sh --names <agent.md>     print the bare skill names (project scope)
#   forge-adapt-agent-skills.sh --rewrite <agent.md>   rewrite the file's list to bare names
#
# Exit codes: 0 success (an agent with no `skills:` field prints nothing and is NOT an error, the
# normal case for most agents); 2 the file is missing or unreadable, so a caller cannot mistake a
# vanished file for an agent that declares nothing.
set -uo pipefail

mode=print
case "${1-}" in
  --names)   mode=names;   shift ;;
  --rewrite) mode=rewrite; shift ;;
  --*) echo "forge-adapt-agent-skills: unknown option '$1'" >&2; exit 2 ;;
esac

f="${1-}"
[ -n "$f" ] && [ -r "$f" ] || { echo "forge-adapt-agent-skills: cannot read agent file '${f:-<none>}'" >&2; exit 2; }

# ONE normalisation, shared by every reader and by the rewriter. Three rounds of review found the
# same defect three ways because `parse` and the rewrite branch each normalised an item their own
# way and drifted: rewrite did not unquote at all, then it unquoted BEFORE trimming so a trailing
# space left a stray quote, then a trailing comment leaked through the reader. Order matters, and
# it is fixed here once: drop a trailing comment, trim, unquote, trim again (a quote can hide a
# space). \047 is the single quote, written as an octal escape so this survives shell quoting.
NORM='
function norm(s) {
  sub(/[[:space:]]+#.*$/, "", s)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  gsub(/^["\047]|["\047]$/, "", s)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  return s
}
'

# Frontmatter is the block between the FIRST '---' on line 1 and the next '---'. A later '---' in
# the body cannot reopen it, and a `skills:` line in the body is prose, not a declaration. CR is
# stripped first: forge-lib.sh tolerates CRLF for the same reason, and without it `---\r` fails the
# line-1 test and every mode goes silently empty, which is the outcome this script exists to remove.
extract() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && /^---[[:space:]]*$/ { exit }
    infm { print }
  ' "$1"
}

# This parses two YAML SHAPES, not YAML. Anything else has to fail closed: a half-understood
# rewrite leaves frontmatter that no longer parses, and the agent then stops loading entirely,
# which is a worse outcome than the silent missing skill this script exists to prevent.
#   supported: `skills:` followed by `  - name` lines, or `skills: [a, b]` closed on the SAME line.
#   refused:   a multi-line flow list, a plain scalar, a block scalar, anything else.
# A BARE `skills:` with no items is YAML null and is deliberately NOT refused: null and absent both
# mean "no companion skills", so there is no ambiguity to report.
classify() {
  extract "$1" | awk '
    /^skills:[[:space:]]*(#.*)?$/      { print "block"; seen = 1; exit }
    /^skills:[[:space:]]*\[.*\]/       { print "flow";  seen = 1; exit }
    /^skills:/                         { print "bad";   seen = 1; exit }
    END { if (!seen) print "none" }
  '
}

parse() {
  awk "$NORM"'
    /^skills:[[:space:]]*\[/ {                       # inline: skills: [a, plugin:b]
      line = $0
      sub(/^skills:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, parts, ",")
      for (i = 1; i <= n; i++) { item = norm(parts[i]); if (item != "") print item }
      next
    }
    /^skills:[[:space:]]*(#.*)?$/ { inlist = 1; next }   # block: skills: then "  - name" lines
    inlist && /^[[:space:]]*-[[:space:]]*/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      item = norm(item)
      if (item != "") print item
      next
    }
    inlist && /^[^[:space:]]/ { inlist = 0 }         # a new top-level key ends the list
  '
}

# A project skill at .claude/skills/<name>/SKILL.md answers to its BARE name. The docs give the
# plugin form as plugin-name:skill-name, or plugin-name:folder:skill-name when a plugin groups its
# skills, and in both the SKILL name is the last segment.
bare() { sed 's/.*://'; }

shape="$(classify "$f")"
if [ "$shape" = bad ]; then
  echo "forge-adapt-agent-skills: unsupported 'skills:' shape in '$f'." >&2
  echo "  Supported: a block list, or an inline flow list closed on the same line." >&2
  exit 2
fi

case "$mode" in
  print) extract "$f" | parse ;;
  names) extract "$f" | parse | bare ;;
  rewrite)
    # BESIDE the target, deliberately not in TMPDIR: `mv` is only atomic within one filesystem, and
    # on the usual tmpfs-plus-disk layout a /tmp temp file degrades the rename into a
    # copy-then-unlink, which is the half-written-on-interrupt case this is here to prevent.
    dir="$(dirname "$f")"
    tmp="$(mktemp "$dir/.forge-adapt-skills.XXXXXX")" || {
      echo "forge-adapt-agent-skills: cannot create a temp file in '$dir'" >&2; exit 2; }
    trap 'rm -f "$tmp"' EXIT
    # `cp -p` FIRST so the temp file carries the agent's own mode, then overwrite its contents and
    # `mv` it into place. mv alone would install mktemp's 0600, which no git diff would show; a
    # plain `cat >` over the original would keep the mode but lose atomicity. This keeps both. One
    # declared exception to leaving the file otherwise untouched: awk terminates every line, so a
    # file with no trailing newline gains one.
    cp -p "$f" "$tmp" || exit 2
    # A READ-ONLY agent (mode 444) is legitimate, and cp -p stamps that mode onto the temp file
    # before the shell opens it, so the write would die with a raw shell error instead of one of
    # this script's own messages. Add the write bit only when the original lacked it, and take it
    # back before the rename, so the mode still round-trips exactly.
    ro=0; [ -w "$f" ] || { ro=1; chmod u+w "$tmp" || exit 2; }
    awk "$NORM"'
      { cr = sub(/\r$/, "") ? "\r" : "" }
      NR == 1 && $0 == "---" { infm = 1; print $0 cr; next }
      infm && /^---[[:space:]]*$/ { infm = 0; print $0 cr; next }
      infm && /^skills:[[:space:]]*\[/ {
        idx = index($0, "["); head = substr($0, 1, idx); rest = substr($0, idx + 1)
        cidx = index(rest, "]")
        body = substr(rest, 1, cidx - 1); tail = substr(rest, cidx)   # tail keeps ] and any comment
        n = split(body, parts, ","); out = ""
        for (i = 1; i <= n; i++) {
          item = norm(parts[i]); sub(/.*:/, "", item)
          if (item != "") out = out (out == "" ? "" : ", ") item
        }
        print head out tail cr; next
      }
      infm && /^skills:[[:space:]]*(#.*)?$/ { inlist = 1; print $0 cr; next }
      infm && inlist && /^[[:space:]]*-[[:space:]]*/ {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        prefix = substr($0, 1, length($0) - length(item))   # preserve the exact indentation
        item = norm(item); sub(/.*:/, "", item)
        print prefix item cr; next
      }
      infm && inlist && /^[^[:space:]]/ { inlist = 0 }
      { print $0 cr }
    ' "$f" > "$tmp" || exit 2
    [ "$ro" = 1 ] && { chmod u-w "$tmp" || exit 2; }
    mv "$tmp" "$f" || exit 2
    trap - EXIT
    ;;
esac
