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
#   forge-adapt-agent-skills.sh --rewrite --skills-root <dir> <agent.md>
#                                                      rewrite a qualified entry to its bare name
#                                                      ONLY when <dir>/<bare>/SKILL.md exists
#
# WHY --rewrite NEEDS A ROOT (#508). A bare name resolves only to a skill installed in the project.
# When the providing plugin stays enabled and the skill is not copied (the minimum install), the
# qualified name `plugin:skill` is the only one that resolves, so stripping it unconditionally made
# `ticket-gate` stop with BLOCKED REFERENCE_MISSING and `code-reviewer` lose its companion skill
# silently. An entry is therefore made bare only when its project copy exists; every other entry is
# kept verbatim. There is no legacy default: plain --rewrite exits 2, so a caller that predates this
# fails loudly instead of silently stripping qualifiers. The root is PROJECT scope only (forge-adapt
# passes .claude/skills): a skill installed under the user's ~/.claude/skills is not looked up, so
# an entry whose only copy lives there keeps its qualifier, which still resolves through the plugin.
# --skills-root is meaningless with --names or print mode and is refused there.
#
# Exit codes: 0 success (an agent with no `skills:` field prints nothing and is NOT an error, the
# normal case for most agents); 2 the file is missing or unreadable, so a caller cannot mistake a
# vanished file for an agent that declares nothing, or a usage error (an unknown option, a
# --skills-root that is missing, has no value, is not a directory or is given without --rewrite, or
# --rewrite without it). Every stderr line starts `forge-adapt-agent-skills:`.
set -uo pipefail

mode=""; root=""; have_root=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --names|--rewrite)
      [ -z "$mode" ] || { echo "forge-adapt-agent-skills: '$1' given after '--$mode'; give one mode" >&2; exit 2; }
      mode="${1#--}"; shift ;;
    --skills-root)
      [ "$#" -ge 2 ] || { echo "forge-adapt-agent-skills: --skills-root needs a directory" >&2; exit 2; }
      root="$2"; have_root=1; shift 2 ;;
    --*) echo "forge-adapt-agent-skills: unknown option '$1'" >&2; exit 2 ;;
    *)   break ;;
  esac
done
[ -n "$mode" ] || mode=print

f="${1-}"
[ -n "$f" ] && [ -r "$f" ] || { echo "forge-adapt-agent-skills: cannot read agent file '${f:-<none>}'" >&2; exit 2; }

if [ "$have_root" -eq 1 ] && [ "$mode" != rewrite ]; then
  echo "forge-adapt-agent-skills: --skills-root only means something with --rewrite" >&2; exit 2
fi
if [ "$mode" = rewrite ]; then
  [ "$have_root" -eq 1 ] || {
    echo "forge-adapt-agent-skills: --rewrite needs --skills-root <dir> (the project's skills directory, e.g. .claude/skills)" >&2; exit 2; }
  [ -d "$root" ] || { echo "forge-adapt-agent-skills: --skills-root '$root' is not a directory" >&2; exit 2; }
fi

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
  # ONE verdict, decided in END. An earlier version printed from each branch and relied on `exit`,
  # but awk runs END after `exit`, so a refusal printed "bad" and then "block" as well.
  extract "$1" | awk "$NORM"'
    verdict == "" && /^skills:[[:space:]]*\[.*\]/  { verdict = "flow"; exit }
    verdict == "" && /^skills:[[:space:]]*(#.*)?$/ { verdict = "block"; inlist = 1; next }
    verdict == "" && /^skills:/                    { verdict = "bad"; exit }
    # A MAPPING item is refused rather than rewritten (#134.3). `- name: x` was classified block and
    # became `-  x`, turning a mapping into a scalar. The input is already invalid, and this script
    # advertises refusing anything outside the two supported shapes; corrupting invalid input is
    # still corrupting.
    #
    # Told apart by the SPACE after the colon, which is what YAML requires of a mapping. A
    # plugin-scoped name is `plugin:skill` with no space, so it is unaffected. The comment is
    # stripped first, or a "#: " inside one would read as a mapping.
    inlist && /^[[:space:]]*-[[:space:]]*/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      item = norm(item)
      if (item ~ /^[^:]+:[[:space:]]/) { verdict = "bad"; exit }
      next
    }
    inlist && /^[^[:space:]]/ { inlist = 0 }
    END { print (verdict == "" ? "none" : verdict) }
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
    # RESOLVE A SYMLINK FIRST (#134.1). The atomic write-beside-and-mv is what makes this
    # mode-preserving and interrupt-safe, and on a symlink it replaces the LINK with a regular file,
    # leaving the real file still carrying its plugin-scoped names. The companion skill then fails
    # SILENTLY, which is the exact outcome this script exists to prevent.
    #
    # `readlink` without -f, resolved by hand: -f is GNU, and this runs on whatever the user has.
    # The hop limit turns a symlink cycle into an error instead of a hang.
    hops=0
    while [ -L "$f" ]; do
      hops=$((hops + 1))
      [ "$hops" -le 10 ] || { echo "forge-adapt-agent-skills: symlink loop at '$f'" >&2; exit 2; }
      target="$(readlink "$f")" || { echo "forge-adapt-agent-skills: cannot read link '$f'" >&2; exit 2; }
      case "$target" in
        /*) f="$target" ;;
        *)  f="$(CDPATH= cd -- "$(dirname "$f")" 2>/dev/null && pwd -P)/$target" ;;
      esac
    done
    [ -f "$f" ] || { echo "forge-adapt-agent-skills: '$f' is not a regular file" >&2; exit 2; }

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
    # The names this project has: a directory under the root holding a SKILL.md. A directory
    # without one, and a plain file, do not count. Handed to awk through the environment, so no
    # path or name passes through shell quoting into awk source.
    have=""
    for d in "$root"/*/; do
      [ -f "${d}SKILL.md" ] || continue
      d="${d%/}"; have="$have${d##*/}"$'\n'
    done
    export FORGE_ADAPT_HAVE="$have"
    mark="$tmp.changed"
    trap 'rm -f "$tmp" "$mark"' EXIT
    cp -p "$f" "$tmp" || exit 2
    # A READ-ONLY agent (mode 444) is legitimate, and cp -p stamps that mode onto the temp file
    # before the shell opens it, so the write would die with a raw shell error instead of one of
    # this script's own messages. Add the write bit only when the original lacked it, and take it
    # back before the rename, so the mode still round-trips exactly.
    ro=0; [ -w "$f" ] || { ro=1; chmod u+w "$tmp" || exit 2; }
    awk -v MARK="$mark" "$NORM"'
      BEGIN {
        n = split(ENVIRON["FORGE_ADAPT_HAVE"], names, "\n")
        for (i = 1; i <= n; i++) if (names[i] != "") have[names[i]] = 1
      }
      # The name an entry should carry: bare when its project copy exists, else unchanged.
      function pick(item,   b) { b = item; sub(/.*:/, "", b); return (b in have) ? b : item }
      { cr = sub(/\r$/, "") ? "\r" : "" }
      NR == 1 && $0 == "---" { infm = 1; print $0 cr; next }
      infm && /^---[[:space:]]*$/ { infm = 0; print $0 cr; next }
      infm && /^skills:[[:space:]]*\[/ {
        idx = index($0, "["); head = substr($0, 1, idx); rest = substr($0, idx + 1)
        cidx = index(rest, "]")
        body = substr(rest, 1, cidx - 1); tail = substr(rest, cidx)   # tail keeps ] and any comment
        n = split(body, parts, ","); out = ""; changed = 0
        for (i = 1; i <= n; i++) {
          item = norm(parts[i]); new = pick(item)
          if (item != "" && new != item) {
            # Keep the part'"'"'s own spacing around the new name; every other part stays verbatim.
            match(parts[i], /^[[:space:]]*/); lead = substr(parts[i], 1, RLENGTH)
            match(parts[i], /[[:space:]]*$/); trail = substr(parts[i], RSTART)
            parts[i] = lead new trail; changed = 1
          }
          out = out (i > 1 ? "," : "") parts[i]
        }
        if (changed) { print "1" > MARK; print head out tail cr } else print $0 cr
        next
      }
      infm && /^skills:[[:space:]]*(#.*)?$/ { inlist = 1; print $0 cr; next }
      infm && inlist && /^[[:space:]]*-[[:space:]]*/ {
        item = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", item)
        prefix = substr($0, 1, length($0) - length(item))   # preserve the exact indentation
        # Capture the trailing comment BEFORE norm() strips it (#134.2). Sharing norm() between the
        # reader and the rewriter is what ended three rounds of drift, and it made the rewriter
        # inherit comment-stripping; the flow branch kept its comment only because it preserves
        # everything after the closing bracket. Preserved in both now.
        comment = ""
        if (match(item, /[[:space:]]+#.*$/)) comment = substr(item, RSTART, RLENGTH)
        item = norm(item); new = pick(item)
        if (item != "" && new != item) { print "1" > MARK; print prefix new comment cr } else print $0 cr
        next
      }
      infm && inlist && /^[^[:space:]]/ { inlist = 0 }
      { print $0 cr }
    ' "$f" > "$tmp" || exit 2
    # Nothing to rewrite: leave the file untouched, mtime and a missing final newline included.
    [ -s "$mark" ] || { rm -f "$tmp" "$mark"; trap - EXIT; exit 0; }
    [ "$ro" = 1 ] && { chmod u-w "$tmp" || exit 2; }
    mv "$tmp" "$f" || exit 2
    rm -f "$mark"
    trap - EXIT
    ;;
esac
