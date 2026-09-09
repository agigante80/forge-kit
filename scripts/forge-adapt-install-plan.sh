#!/usr/bin/env bash
# forge-adapt-install-plan.sh: decide whether a component is REGISTERED or COPIED (#166).
#
# forge-adapt runs this instead of carrying the rule as prose, for the reason #149 established: a
# rule in prose cannot be tested, and this one decides whether a copy lands in every project that
# installs the kit. It also keeps `adapt/SKILL.md` under its size ratchet, which the prose version
# measurably could not.
#
#   forge-adapt-install-plan.sh <component-file> [--group <name>] [--no-marketplace]
#
# Prints ONE line, which forge-adapt reads and acts on:
#   register<TAB><group><TAB><reason>     enable the plugin group; write no copy
#   copy<TAB><group><TAB><reason>         adapt and write into .claude/
#
# Exit 0 when it decided, 2 when it could not.
#
# THE RULE. A `scope: user` component (the default, #164) resolves what it needs at runtime, so it
# is correct in every project as shipped and is REGISTERED. A registered component owns no user
# config, so it cannot drift, duplicate or clobber, and copy-and-mutate is what CLAUDE.md blames for
# every hook bug in this repo's history.
#
# THREE THINGS STILL COPY, and each for a reason a script can check:
#   - `scope: project`, which carries a scope-reason saying what must be rewritten per project.
#   - Anything installed from a bare clone, where there is no marketplace to register with.
#   - Hooks, which reach a project through their own three shapes (see CLAUDE.md) rather than this
#     decision. They are not components in the frontmatter sense and this refuses to judge them.
set -uo pipefail

FILE=""; GROUP=""; MARKETPLACE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --group)          shift; [ $# -gt 0 ] || { echo "install-plan: --group needs a name" >&2; exit 2; }; GROUP="$1" ;;
    --no-marketplace) MARKETPLACE=0 ;;
    -*)               echo "install-plan: unknown flag: $1" >&2; exit 2 ;;
    *)                FILE="$1" ;;
  esac
  shift
done
[ -n "$FILE" ] || { echo "install-plan: give a component file" >&2; exit 2; }
[ -f "$FILE" ] || { echo "install-plan: no such file: $FILE" >&2; exit 2; }

case "$FILE" in
  */hooks/*) echo "install-plan: $FILE is a hook; hooks reach a project by their own install shapes, not by scope" >&2; exit 2 ;;
esac

# Derive the group from the path when not given, so a caller can pass just the file.
if [ -z "$GROUP" ]; then
  case "$FILE" in
    */plugins/*) GROUP="${FILE#*/plugins/}"; GROUP="${GROUP%%/*}" ;;
    *)           GROUP="" ;;
  esac
fi

# FRONTMATTER ONLY, matching check-component-scope.sh: a `scope:` in the body is an example, and
# reading it would let a component be scoped by its own documentation.
fm="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$FILE")"
scope="$(printf '%s\n' "$fm" | sed -n 's/^scope:[[:space:]]*//p' | head -1)"
reason="$(printf '%s\n' "$fm" | sed -n 's/^scope-reason:[[:space:]]*//p' | head -1)"
scope="${scope%"${scope##*[![:space:]]}"}"
reason="${reason%"${reason##*[![:space:]]}"}"
[ -n "$scope" ] || scope=user

emit() { printf '%s\t%s\t%s\n' "$1" "$GROUP" "$3"; }

case "$scope" in
  user) ;;
  project)
    [ -n "$reason" ] || { echo "install-plan: $FILE declares scope: project with no scope-reason" >&2; exit 2; }
    emit copy "$GROUP" "scope: project ($reason)"; exit 0 ;;
  *)
    echo "install-plan: $FILE declares an unrecognised scope '$scope' (want: user, project)" >&2; exit 2 ;;
esac

if [ "$MARKETPLACE" -eq 0 ]; then
  emit copy "$GROUP" "installed from a clone, so there is no marketplace to register with"
  exit 0
fi
emit register "$GROUP" "user-scoped: correct in every project as shipped, and a registered component owns no user config to drift or clobber"
exit 0
