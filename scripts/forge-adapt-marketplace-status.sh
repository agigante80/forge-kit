#!/usr/bin/env bash
# forge-adapt-marketplace-status.sh: is the marketplace checkout behind its remote? (#172)
#
#   forge-adapt-marketplace-status.sh <marketplace-name> [--dir <marketplaces-root>]
#
# Prints ONE tab-separated line and ALWAYS exits 0 when it could look:
#   current<TAB><detail>         local HEAD matches the remote's default branch
#   stale<TAB><detail>           they differ; run the update command named in the detail
#   unknown<TAB><detail>         not a checkout, no remote, or the remote could not be reached
#   not-applicable<TAB><detail>  no such marketplace: the bare-clone install path
#
# THE DEFECT. #166 stopped forge-adapt copying user-scoped components, so the modern install is
# REGISTRATION, and #167 taught `drift` to call a registered component `registered` rather than
# missing. Neither says anything about the marketplace CHECKOUT behind that registration, so a
# registered component can be arbitrarily stale and every tool in this repo calls it healthy. Found
# by probe: the maintainer's own forge-kit-governance read 0.7.11 against a tree at 0.11.1, with the
# checkout 84 commits behind.
#
# `stale`, NOT `behind`. Probed: the checkout is a real clone with an origin remote, and the
# comparison that writes nothing is `git ls-remote` against local HEAD. That establishes the two
# DIFFER. It cannot establish direction, because behind-versus-diverged needs the remote objects,
# which needs a fetch, which is a WRITE into a directory another tool owns. The word says what was
# measured rather than what was hoped.
#
# IT NEVER WRITES. No fetch, no config, no refs. The checkout belongs to Claude Code.
#
# UNREACHABLE IS `unknown`, NEVER `current`. An absent answer reading as agreement is the shape that
# hid every pre-marker install in #64, and a network hiccup must not certify a stale kit.
set -uo pipefail

NAME=""; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) shift; [ $# -gt 0 ] || { echo "marketplace-status: --dir needs a path" >&2; exit 2; }; DIR="$1" ;;
    -*)    echo "marketplace-status: unknown flag: $1" >&2; exit 2 ;;
    *)     NAME="$1" ;;
  esac
  shift
done
[ -n "$NAME" ] || { echo "marketplace-status: give a marketplace name" >&2; exit 2; }
[ -n "$DIR" ]  || DIR="${HOME:-}/.claude/plugins/marketplaces"

emit() { printf '%s\t%s\n' "$1" "$2"; exit 0; }

CO="$DIR/$NAME"
# Deliberately BEFORE the git checks: a missing directory is the bare-clone install shape, which has
# no marketplace to be behind. Reporting it as stale would invite an update of something absent.
[ -d "$CO" ] || emit not-applicable "no marketplace checkout for '$NAME'; nothing to compare (this is the bare-clone install path)"

git -C "$CO" rev-parse --git-dir >/dev/null 2>&1 \
  || emit unknown "'$NAME' is not a git checkout, so it cannot be compared with a remote"

local_head="$(git -C "$CO" rev-parse HEAD 2>/dev/null)" \
  || emit unknown "'$NAME' has no resolvable HEAD"

branch="$(git -C "$CO" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$branch" ] && [ "$branch" != HEAD ] || branch=HEAD

# ls-remote READS the remote and writes nothing locally, which is the whole reason it is used here
# rather than fetch. A failure is a network or auth problem, and both are `unknown`.
if [ "$branch" = HEAD ]; then
  remote_line="$(git -C "$CO" ls-remote origin HEAD 2>/dev/null | head -1)"
else
  remote_line="$(git -C "$CO" ls-remote origin "refs/heads/$branch" 2>/dev/null | head -1)"
fi
remote_head="${remote_line%%[[:space:]]*}"

[ -n "$remote_head" ] \
  || emit unknown "could not reach the remote for '$NAME', so its freshness is unknown rather than current"

if [ "$local_head" = "$remote_head" ]; then
  emit current "'$NAME' matches its remote"
fi

# The detail is printed to a human and may be pasted, so it names the MARKETPLACE and never the
# absolute path: a home path in a pasted message is exactly what check-public-leaks.sh exists to
# catch, and this kit ships that scanner.
emit stale "'$NAME' differs from its remote; run: claude plugin marketplace update $NAME (then claude plugin update <plugin>)"
