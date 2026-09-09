#!/usr/bin/env bash
# guard-lib.sh: what a repo guard should scan. Sourced, never executed (#140, #142).
#
# THE RULE, IN ONE PLACE. A guard that walks the WORKTREE gives a local verdict CI cannot reproduce:
# untracked and gitignored files are in scope with nothing to excuse them. A merge leftover such as
# `dep-auditor.md.orig`, still carrying a pre-#83 stamp, hard-fails on a developer's machine over a
# file CI will never see and git will never carry, and the message names a real path, so there is no
# signal that it is irrelevant.
#
# The range guards already read committed state through `git show`, precisely so the local answer
# matches the one CI computes. This brings the scanning guards into line with them.
#
# WHY THIS IS A LIBRARY AND NOT TWO COPIES. #142 asked for #140 to be fixed with it rather than
# after it, so the fallback would not become a third copy of a rule two guards share, in a repo that
# had just spent two PRs (#77, #125) on exactly that problem. The test is the same one used for
# roadmap-lib.sh: could the two consumers ever LEGITIMATELY differ? They could not. If one guard's
# local verdict matched CI and the other's did not, that is a defect by definition, which is what
# separates a shared specification from incidental similarity.
#
# THE FALLBACKS ARE NOT SHARED, AND CANNOT BE. One guard falls back to `grep -r`, the other to a
# Python os.walk. They are different mechanisms expressing the same intent, the same shape as the
# component path set (#112) where a glob cannot be a regex. What IS shared, and what would
# otherwise have become a third copy, is the DECISION: am I inside a checkout, and if so which
# files are tracked.
#
# Keeping each fallback where it was also keeps its tested behaviour intact. `grep -r` fails closed
# on an unreadable subtree; `find -print0` silently skips it, which would have reopened the vacuous
# pass check-producer-stamps.sh's header warns about at length.

# guard_in_checkout <root> -> 0 if <root> is inside a git work tree
guard_in_checkout() {
  git -C "$1" rev-parse --show-toplevel >/dev/null 2>&1
}

# guard_tracked_files <root>
#   Emits NUL-separated ABSOLUTE paths of the TRACKED files under <root>, which is what CI will see.
#   Caller must have established the checkout with guard_in_checkout first.
guard_tracked_files() {
  local root="$1" abs top rel
  abs="$(cd "$root" 2>/dev/null && pwd -P)" || return 2
  top="$(git -C "$abs" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)"
  # Listed from the repo root and filtered to the requested subtree rather than passing a pathspec,
  # so <root> may be the repo root or any directory inside it through one code path.
  while IFS= read -r -d '' rel; do
    case "$top/$rel" in
      "$abs"|"$abs"/*) ;;
      *) continue ;;
    esac
    # `git ls-files` lists a tracked file that has been DELETED from the worktree. Handing that path
    # to a reader is an error the caller would report as a scan failure: a guard claiming it could
    # not run when in fact there was nothing to read.
    [ -f "$top/$rel" ] || continue
    printf '%s\0' "$top/$rel"
  done < <(cd "$top" && git ls-files -z)
}

# component_scope <file> -> prints `user` or `project`, or the raw value if it is neither.
#
# FRONTMATTER ONLY. A `scope:` in the body is an example, and reading it would let a component be
# scoped by its own documentation. Shared because three guards now ask the same question, and a
# third copy of one rule is what #162 was about.
component_scope() {
  local fm scope
  fm="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$1")"
  scope="$(printf '%s\n' "$fm" | sed -n 's/^scope:[[:space:]]*//p' | head -1)"
  scope="${scope%"${scope##*[![:space:]]}"}"
  printf '%s' "${scope:-user}"
}

# guard_is_substitution <line> -> 0 when the line is the sed that REPLACES a placeholder.
#
# Word-anchored. An unanchored `/sed/` matched "used", "based", "parsed" and "closed", so a comment
# on the same line as a placeholder exempted the command carrying it. Found by review, round 1.
guard_is_substitution() {
  case "$1" in
    sed\ *|*[!A-Za-z0-9_]sed\ *) return 0 ;;
  esac
  return 1
}
