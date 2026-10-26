#!/usr/bin/env bash
# forge-adapt-marker-delta.sh: the upstream delta between an installed marker and the library's HEAD (#529).
#
# Usage: forge-adapt-marker-delta.sh <library dir> <component path in library> <name> <installed version>
#
# `refresh <name>` wants what changed upstream between the version the project installed and the one
# the library now carries. The library is a depth-1 marketplace checkout, so that history is usually
# not there. This finds the commit that set `<name>-version: <N>` in the component file and prints
# `git diff <that commit> HEAD -- <path>`. The diff is DISPLAY ONLY: it is never a merge base, and the
# two-way classification in `refresh <name>` is unchanged. The commit id in the first line is also a
# baseline pointer (#550): forge-adapt reads the installed copy's files at that commit to tell an
# untouched copy from an edited one before it offers to retire a copy the plugin now provides.
#
# stdout (always one of):
#   marker-delta: <name> v<N> set in <sha>; delta v<N> to HEAD follows     then the diff     exit 0
#   marker-delta: <name> v<N> is current                                                      exit 0
#   marker-delta: unavailable (<reason>); fall back to a full content diff against the
#     catalogue copy                                                                          exit 1
# Exit 1 is informational: the caller shows the line and carries on with the content diff. It never
# fails a refresh. Exit 2 is a usage error (message on stderr, `forge-adapt-marker-delta:` prefix).
#
# Deepening the library (the decisions of #529, 2026-10-15):
#   - Only when the commit is NOT in the history already, and only when the library is shallow. A full
#     clone, or a shallow one that already holds the commit, makes no network call.
#   - Once: `git fetch --unshallow origin`. If git refuses that, one plain `git fetch --deepen=N` as
#     the fallback. No retry loop, no poll (the repo's no-poll-loops rule). Both fail -> unavailable.
#   - Never while .git/shallow.lock exists: another forge-adapt run is writing the shared library, and
#     contending for it is what scripts/forge-adapt-refresh.sh already survives. Skip, say so, fall
#     back. S2 (forge-adapt-refresh.sh) later resets the library to depth 1 (fetch --depth 1), which is
#     accepted: the next refresh <name> deepens again.
#   - A commit found only because it is the shallow BOUNDARY is not trusted: a boundary commit looks
#     as if it introduced the whole file, so the delta from it would be truncated. Unavailable.
# Only .git state changes; the working tree is never touched. Output is a diff of one tracked public
# file and the short commit id.
set -uo pipefail

bad() { echo "forge-adapt-marker-delta: $1" >&2; exit 2; }
if [ "$#" -ne 4 ]; then
  echo "forge-adapt-marker-delta: usage: forge-adapt-marker-delta.sh <library dir> <component path> <name> <installed version>" >&2
  exit 2
fi
LIB="$1"; REL="$2"; NAME="$3"; VER="$4"

grep -qE '^[a-z0-9][a-z0-9-]*$' <<<"$NAME" || bad "invalid component name '$NAME'"
grep -qE '^[0-9]{1,9}$' <<<"$VER" || bad "invalid version '$VER'"
case "$REL" in
  ''|/*|..|../*|*/..|*/../*) bad "invalid component path '$REL'" ;;
esac
[ -d "$LIB" ] || bad "not a git repository: $LIB"
GD="$(git -C "$LIB" rev-parse --absolute-git-dir 2>/dev/null)" || bad "not a git repository: $LIB"
export GIT_TERMINAL_PROMPT=0

unavailable() {
  echo "marker-delta: unavailable ($1); fall back to a full content diff against the catalogue copy"
  exit 1
}

# The marker at HEAD, from the first marker-shaped token in the file.
head_marker="$(git -C "$LIB" show "HEAD:$REL" 2>/dev/null | grep -oE -m1 -- "${NAME}-version: [0-9]+" | grep -oE '[0-9]+$')"
[ -n "$head_marker" ] || unavailable "no $NAME-version marker in $REL at HEAD"
if [ "$head_marker" = "$VER" ]; then
  echo "marker-delta: $NAME v$VER is current"
  exit 0
fi

# The oldest commit whose diff touches the marker line. The class after N stops at a non-digit, so
# 8 never matches 81.
find_commit() {
  git -C "$LIB" log --format=%H -G "${NAME}-version: ${VER}([^0-9]|\$)" -- "$REL" 2>/dev/null | tail -n 1
}
is_shallow() { [ "$(git -C "$LIB" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; }
# A commit listed in .git/shallow is a boundary: its parents are not here.
is_boundary() { [ -f "$GD/shallow" ] && grep -qx -- "$1" "$GD/shallow"; }

sha="$(find_commit)"
if { [ -z "$sha" ] || is_boundary "$sha"; } && is_shallow; then
  if [ -e "$GD/shallow.lock" ]; then
    unavailable "cannot deepen the library: another forge-adapt run holds shallow.lock"
  fi
  # macOS has no timeout(1): a stalled transfer is bounded by git itself (under 1000 B/s for 30 s aborts).
  T=()
  command -v timeout >/dev/null 2>&1 && T=(timeout 120)
  if ! ${T[@]+"${T[@]}"} git -C "$LIB" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 fetch --quiet --unshallow origin >/dev/null 2>&1; then
    ${T[@]+"${T[@]}"} git -C "$LIB" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 fetch --quiet --deepen=1000 origin >/dev/null 2>&1 \
      || unavailable "cannot deepen the library: origin unreachable"
  fi
  sha="$(find_commit)"
fi
if [ -z "$sha" ] && is_shallow; then
  unavailable "cannot deepen the library: history stops before the commit that set $NAME-version: $VER"
fi
[ -n "$sha" ] || unavailable "no commit sets $NAME-version: $VER in $REL"
if is_shallow && is_boundary "$sha"; then
  unavailable "cannot deepen the library: history stops before the commit that set $NAME-version: $VER"
fi

echo "marker-delta: $NAME v$VER set in $(git -C "$LIB" rev-parse --short "$sha"); delta v$VER to HEAD follows"
git -C "$LIB" --no-pager diff --no-color --no-ext-diff "$sha" HEAD -- "$REL"
exit 0
