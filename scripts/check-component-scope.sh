#!/usr/bin/env bash
# check-component-scope.sh: every component says where it belongs, and the tree must agree (#164).
#
#   scope: user      installed once by enabling the plugin group; correct in every project
#   scope: project   must be rewritten for the project it lands in; forge-adapt copies and adapts
#
# ABSENT MEANS `user`, and that is a deliberate default rather than a convenience. A default should
# point at the good path, and after #163 no component bakes a value in at install time, so `user`
# is not merely the common case: it is the case the tree can prove. Declaring it on all thirty-eight
# components would be noise that says nothing.
#
# `project` IS THE EXCEPTION AND CARRIES ITS REASON, in a `scope-reason:` field. Same shape
# check-restatements.sh requires of an allowlist entry, for the same reason: an exception without a
# stated reason is one that grows by argument, and this one decides whether a component gets copied
# into every project that installs it.
#
# THE CLAIM IS CHECKED, NOT TRUSTED. The phase plan's premortem named "scope: user became a lie" as
# the way this goes wrong, because a component declared user-scope that quietly needs a project fact
# is worse than one honestly copied: nothing tells the user why it misbehaves. The one mechanical
# contradiction available is an install-time placeholder inside a command, so a user-scoped
# component carrying one is refused. That is a narrow check and it is stated narrowly; the rest of
# the claim rests on the reason a maintainer wrote.
#
# Exit 0 clean, 1 a declaration is wrong or contradicted, 2 could not run.
set -uo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  TOP="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-component-scope: not a git checkout and no root given" >&2; exit 2; }
  ROOT="$TOP/plugins"
fi
[ -d "$ROOT" ] || { echo "check-component-scope: '$ROOT' is not a directory" >&2; exit 2; }

COMPONENT_RE='.*/plugins/[^/]+/(agents|commands)/[^/]+\.md|.*/plugins/[^/]+/skills/[^/]+/SKILL\.md'

errors=0
n_user=0
n_project=0

while IFS= read -r f; do
  rel="${f#"$ROOT"/}"

  # FRONTMATTER ONLY. A `scope:` written in the body is prose, and reading it would let a component
  # be scoped by an example inside its own documentation.
  fm="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$f")"
  scope="$(printf '%s\n' "$fm" | sed -n 's/^scope:[[:space:]]*//p' | head -1)"
  reason="$(printf '%s\n' "$fm" | sed -n 's/^scope-reason:[[:space:]]*//p' | head -1)"
  scope="${scope%"${scope##*[![:space:]]}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"
  [ -n "$scope" ] || scope=user

  case "$scope" in
    user)    n_user=$((n_user + 1)) ;;
    project) n_project=$((n_project + 1)) ;;
    *)
      echo "$rel: unrecognised scope '$scope' (want: user, project)" >&2
      errors=$((errors + 1)); continue ;;
  esac

  if [ "$scope" = project ] && [ -z "$reason" ]; then
    echo "$rel: scope: project needs a 'scope-reason:' saying what must be rewritten per project." >&2
    echo "    Copying a component into every project is the cost this field exists to justify." >&2
    errors=$((errors + 1)); continue
  fi

  if [ "$scope" = user ]; then
    # The one contradiction a script can see: a value baked in at install time cannot be correct in
    # every project. Positional, like check-live-placeholders.sh: a fenced line is a command.
    hit="$(awk '
      /^[[:space:]]*```/ { fenced = !fenced; next }
      fenced && /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/ && $0 !~ /sed/ {
        match($0, /\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/)
        printf("%d: %s", NR, substr($0, RSTART, RLENGTH)); exit }' "$f")"
    if [ -n "$hit" ]; then
      echo "$rel:$hit: a user-scoped component carries an install-time placeholder, so it cannot be" >&2
      echo "    correct in every project. Resolve it at runtime, or declare scope: project with a reason." >&2
      errors=$((errors + 1))
    fi
  fi
done < <(find "$ROOT" -regextype posix-extended -regex "$COMPONENT_RE" -type f 2>/dev/null | sort)

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "check-component-scope: $errors component(s) with a scope problem."
  exit 1
fi
echo "check-component-scope: $n_user user-scoped, $n_project project-scoped, all consistent with the tree."
exit 0
