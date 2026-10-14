#!/usr/bin/env bash
# forge-adapt-refresh.sh: bring the shared component library checkout up to its remote head (#501).
#
# Usage: forge-adapt-refresh.sh <library dir>
#   Exit 0: the library is current (silently). Exit 1: it may be behind (prints nothing; S2 owns the
#   one warning line and its fix hint). Exit 2: usage error.
#
# Why this is a script and not inline SKILL.md text: adapt/SKILL.md is on a word ratchet, and the
# retry and comparison below do not fit it.
#
# The library is ONE checkout per machine, so two forge-adapt runs in two projects can refresh it at
# once. Git serialises that through .git/shallow.lock (fetch) and .git/index.lock (checkout); the
# loser fails although the winner has just made HEAD current. So: try, wait once, try again, and if
# that fails too, ask the remote (git ls-remote) whether local HEAD IS the remote head. Only a
# library that is still behind, or a remote that cannot be read, is reported as a failure. One
# retry, then the comparison: no loop, no poll (the repo's no-poll-loops rule). A stale lock left by
# a crashed fetch is never removed; the comparison decides. flock was rejected: absent on stock macOS.
#
# The refresh is `checkout -B <default branch> origin/HEAD`, never `reset --hard` (overnight-guard
# denies it in a .claude/no-destructive project, #502) and never `merge --ff-only` (a depth-1 fetch
# makes that fail with "unrelated histories"). The branch name comes from refs/remotes/origin/HEAD,
# not from the current branch, so a detached HEAD and a non-main default branch both refresh. git
# carries a non-conflicting local edit and refuses a conflicting one (exit 1, HEAD unchanged).
#
# Environment: FORGE_ADAPT_REFRESH_WAIT, the command run between the two attempts (default
# `sleep 2`); tests inject `true` or a command that releases a lock.
set -uo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "forge-adapt-refresh: usage: forge-adapt-refresh.sh <library dir>" >&2
  exit 2
fi
D="$1"
WAIT="${FORGE_ADAPT_REFRESH_WAIT:-sleep 2}"

refresh_once() {
  local ref
  git -C "$D" fetch --depth 1 origin --quiet 2>/dev/null || return 1
  ref=$(git -C "$D" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || return 1
  [ -n "$ref" ] || return 1
  git -C "$D" checkout -q -B "${ref#origin/}" origin/HEAD 2>/dev/null
}

refresh_once && exit 0
bash -c "$WAIT" >/dev/null 2>&1
refresh_once && exit 0

remote=$(GIT_TERMINAL_PROMPT=0 git -C "$D" ls-remote origin HEAD 2>/dev/null | cut -f1)
local_head=$(git -C "$D" rev-parse HEAD 2>/dev/null)
if [ -n "$remote" ] && [ "$remote" = "$local_head" ]; then
  exit 0
fi
exit 1
