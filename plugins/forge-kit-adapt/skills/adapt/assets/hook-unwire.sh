#!/usr/bin/env bash
# hook-unwire-version: 1
# hook-unwire.sh: remove one hook's wiring from a project's .claude/settings.json (#564).
#
#   hook-unwire.sh <name> [--project <dir>]
#
# <name> is the extensionless hook name the catalogue prints (`hook: block-dashes | v5`): it must match
# ^[a-z0-9][a-z0-9-]*$, the regex forge-adapt-marker-delta.sh applies. A name with an extension, a slash,
# a leading dash or `..` exits 2 with `hook-unwire:` and the refused name on stderr, and nothing is read
# or written. --project defaults to the current directory.
#
# WHAT IT DOES. Removes every hook entry whose command line names `<name>.py` or `<name>.sh` from
# EVERY event in .claude/settings.json (PreToolUse, PostToolUse, Stop, any other), matching on a PATH
# BOUNDARY: the file name must start the command text or follow a `/` or a space, and end it or precede a
# space or quote, so `my-block-dashes.py` is never touched when `block-dashes` is unwired. A matcher
# group that still holds another hook keeps it; only a group this removal emptied is dropped. A group
# it did not touch is kept as it was, even when it was already empty.
#
# WHAT IT DOES NOT DO. It never deletes the hook file, never edits settings.local.json, and never
# touches the plugin's own hooks.json. It rewrites the file with jq (two-space indent), through a temp
# file in the same directory that replaces the original only when jq succeeded, mode kept.
#
# WHY IT EXISTS AND WHY THE ORDER MATTERS. Retiring a project-local copy of a hook the plugin now
# provides has two steps: unwire, then delete. A wired hook whose file is gone makes `python3 <missing>`
# exit 2, which Claude Code reads as a deny for a PreToolUse hook, so EVERY matching call is denied,
# including the Bash call that would run this script. Unwire first: a wired hook that still exists is
# merely a duplicate. Callers print or run `hook-unwire.sh <name>` BEFORE any `rm`.
#
# Exit 0: removed, or nothing wired (`no wiring found for <name>`: no file, no .hooks, or no match).
# Exit 1: settings.json cannot be edited safely (not valid JSON, a symlink, jq missing); left unchanged.
# Exit 2: usage or a name outside the guard.
set -uo pipefail

NAME=""; PROJECT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) shift; [ $# -gt 0 ] || { echo "hook-unwire: --project needs a value" >&2; exit 2; }; PROJECT="$1" ;;
    --*)       echo "hook-unwire: unexpected argument: $1" >&2; exit 2 ;;
    *)         [ -z "$NAME" ] || { echo "hook-unwire: one name only, got a second: $1" >&2; exit 2; }; NAME="$1" ;;
  esac
  shift
done
[ -n "$NAME" ] || { echo "hook-unwire: usage: hook-unwire.sh <name> [--project <dir>]" >&2; exit 2; }
case "$NAME" in
  *[!a-z0-9-]*|-*) echo "hook-unwire: '$NAME' is not a hook name (extensionless, lower-case letters, digits and hyphens, no leading hyphen)" >&2; exit 2 ;;
esac

S="$PROJECT/.claude/settings.json"
if [ ! -e "$S" ] && [ ! -L "$S" ]; then echo "no wiring found for $NAME"; exit 0; fi
command -v jq >/dev/null 2>&1 || { echo "hook-unwire: jq is required; settings.json left unchanged" >&2; exit 1; }
[ -L "$S" ] && { echo "hook-unwire: $S is a symlink; left unchanged" >&2; exit 1; }
[ -f "$S" ] || { echo "hook-unwire: $S is not a regular file; left unchanged" >&2; exit 1; }
jq -e . "$S" >/dev/null 2>&1 || { echo "hook-unwire: $S is not valid JSON; left unchanged" >&2; exit 1; }

DEFS='
def is_it: ((.command? // "") + " " + ((.args? // []) | map(tostring) | join(" ")))
  | test("(^|[/ ])" + $n + "\\.(py|sh)($|[ \"\\u0027])");
def groups: if type == "object" and (.hooks | type) == "object" then [.hooks[] | select(type == "array") | .[] | select(type == "object" and (.hooks | type) == "array") | .hooks[] | select(type == "object")] else [] end;
'
count=$(jq --arg n "$NAME" "$DEFS"' [groups[] | select(is_it)] | length' "$S" 2>/dev/null) || count=""
[ -n "$count" ] || { echo "hook-unwire: could not read $S; left unchanged" >&2; exit 1; }
if [ "$count" -eq 0 ]; then echo "no wiring found for $NAME"; exit 0; fi

tmp=$(mktemp "$PROJECT/.claude/.settings.XXXXXX") || { echo "hook-unwire: cannot make a temp file; left unchanged" >&2; exit 1; }
cp -p "$S" "$tmp" 2>/dev/null
if jq --arg n "$NAME" "$DEFS"'
  .hooks |= with_entries(.value |= (
    if type == "array" then
      [ .[] |
        if type == "object" and (.hooks | type) == "array" then
          (.hooks | length) as $before
          | (.hooks |= map(select((type == "object" and is_it) | not)))
          | select($before == (.hooks | length) or (.hooks | length) > 0)
        else . end ]
    else . end))' "$S" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$S" || { rm -f "$tmp"; echo "hook-unwire: could not replace $S; left unchanged" >&2; exit 1; }
  echo "hook-unwire: removed $count wiring entries for $NAME from .claude/settings.json"
else
  rm -f "$tmp"; echo "hook-unwire: jq failed; $S left unchanged" >&2; exit 1
fi
