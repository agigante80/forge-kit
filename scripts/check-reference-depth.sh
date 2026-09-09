#!/usr/bin/env bash
# Reference depth guard (#175): every file under a skill's references/ must be named by that
# skill's own SKILL.md.
#
#   check-reference-depth.sh [ROOT]      default: the git top level, else .
#   exit 0  every reference is reachable from its SKILL.md
#   exit 1  at least one is not, and every one of them is listed
#   exit 2  the guard could not run
#
# THE RULE IS ANTHROPIC'S AND ITS REASON IS MECHANICAL. "Keep references one level deep from
# SKILL.md. All reference files should link directly from SKILL.md to ensure agents read complete
# files when needed." The failure it names is not untidiness: an agent meeting a reference INSIDE
# another reference may preview it with something like `head -100` rather than reading it whole,
# so it acts on half a file and nothing anywhere reports that it did. A partially read reference
# is worse than an absent one.
#
# IT MATCHES THE FILENAME, NOT A LINK SYNTAX. This kit names references in prose backticks
# (`references/x.md`), not as markdown links. A guard that required link syntax would report every
# reference in the tree as an orphan on its first run and be deleted by whoever ran it.
#
# WHAT IS OUT OF SCOPE, AND WHY EACH IS. `agents/` has no `references/` and never will: the loader
# claims every `.md` beneath `agents/` at any depth (#124), so a violation reported there would
# send the fixer at a constraint they cannot satisfy. `assets/` and `scripts/` are executed or
# copied rather than read into context, so the rule does not apply to them.
#
# WHAT IT DOES NOT SEE. Reachability only. It cannot tell a live pointer from a stale one, and a
# SKILL.md naming a reference it no longer uses satisfies it. That is the honest limit of one grep
# per file, and the alternative (parsing prose for intent) is a guard nobody could trust either.
#
# THE ticket-gate SHAPE IS NOT A VIOLATION. An agent cannot have references/ (#124), so ticket-gate
# reaches its material through a companion SKILL that has its own references/. That looks like two
# hops and is not: the companion's full body is PRELOADED into the agent at spawn (verified in
# #150), so from the agent's position those files are one hop from content it already holds. The
# guard walks skills, so it judges the companion on its own terms, which is the correct question.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
[ -d "$ROOT" ] || { echo "check-reference-depth: no such directory: $ROOT" >&2; exit 2; }
cd "$ROOT" || exit 2
[ -d plugins ] || { echo "check-reference-depth: no plugins/ under $ROOT, nothing to check." ; exit 0; }

orphans=0
checked=0

# Shell globs, not `find -path`: in find, `*` crosses `/`, which is the dialect trap #112 was
# about. One directory level, exactly the shape the enforced path set uses.
shopt -s nullglob
for ref in plugins/*/skills/*/references/*.md; do
  checked=$((checked + 1))
  skill="$(dirname "$(dirname "$ref")")/SKILL.md"
  base="$(basename "$ref")"
  if [ ! -f "$skill" ]; then
    echo "  ✗ $ref: there is no $skill beside it, so nothing can reach it." >&2
    orphans=$((orphans + 1))
    continue
  fi
  grep -qF -- "$base" "$skill" || {
    echo "  ✗ $ref: $(basename "$(dirname "$skill")")/SKILL.md never names it." >&2
    orphans=$((orphans + 1))
  }
done

if [ "$orphans" -ne 0 ]; then
  {
    echo ""
    echo "check-reference-depth: $orphans of $checked reference file(s) are unreachable from their SKILL.md."
    echo "  Name each one from its SKILL.md (backticks are enough), merge it into another reference"
    echo "  that IS named, or delete it. A reference reached only from another reference may be read"
    echo "  in part rather than whole, and nothing reports that it was."
  } >&2
  exit 1
fi

echo "check-reference-depth: $checked reference file(s), all reachable from their SKILL.md."
