#!/usr/bin/env bash
# hook-unwire-version: 4
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
# EVERY event in .claude/settings.json (PreToolUse, PostToolUse, Stop, any other), matching on a WORD
# BOUNDARY: the character before `<name>.py` and the one after it must each be absent or outside
# [A-Za-z0-9_.-] (the same class retired-paths.sh uses), so a quote, `;`, `&&`, `|`, `)`, a tab or a
# newline all end a match, while `my-block-dashes.py` and `block-dashes.pyu` are never touched. (jq's
# regex does not read `\u0027` inside a class as a quote, which is why the boundary is a complement.) A matcher
# group that still holds another hook keeps it; only a group this removal emptied is dropped. A group
# it did not touch is kept as it was, even when it was already empty.
#
# WHAT IT DOES NOT DO. It never deletes the hook file, never edits settings.local.json, and never
# touches the plugin's own hooks.json. A hook still wired in settings.local.json is REFUSED (exit 1,
# naming the file), as is a settings.local.json it cannot read safely, so the delete that follows an
# exit-0 unwire can never leave a wired hook without its file. Callers chain: `hook-unwire.sh <n> && rm`. It rewrites the file with jq (two-space indent), through a temp
# file in the same directory that replaces the original only when jq succeeded, mode kept.
#
# WHY IT EXISTS AND WHY THE ORDER MATTERS. Retiring a project-local copy of a hook the plugin now
# provides has two steps: unwire, then delete. A wired hook whose file is gone makes `python3 <missing>`
# exit 2, which Claude Code reads as a deny for a PreToolUse hook, so EVERY matching call is denied,
# including the Bash call that would run this script. Unwire first: a wired hook that still exists is
# merely a duplicate. Callers print or run `hook-unwire.sh <name>` BEFORE any `rm`.
#
# Exit 0: removed, or nothing wired (`no wiring found for <name>`: no file, no .hooks, or no match).
# Exit 1: nothing may be deleted after this: settings.json cannot be edited safely (not one valid JSON object, a
# symlink or a symlinked .claude, jq missing), or settings.local.json still wires the hook; left unchanged.
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

# A symlinked .claude directory would send the temp file and the replace outside the project (the project
# may be untrusted), so it is refused before anything is read or written, the same as a symlinked file.
if [ -L "$PROJECT/.claude" ]; then echo "hook-unwire: $PROJECT/.claude is a symlink; left unchanged" >&2; exit 1; fi
S="$PROJECT/.claude/settings.json"; L="$PROJECT/.claude/settings.local.json"
have_s=1; if [ ! -e "$S" ] && [ ! -L "$S" ]; then have_s=0; fi
have_l=1; if [ ! -e "$L" ] && [ ! -L "$L" ]; then have_l=0; fi
if [ "$have_s" -eq 0 ] && [ "$have_l" -eq 0 ]; then echo "no wiring found for $NAME"; exit 0; fi
command -v jq >/dev/null 2>&1 || { echo "hook-unwire: jq is required; settings left unchanged" >&2; exit 1; }
# one_object <file>: a regular, non-symlink file holding exactly one JSON object (a concatenation is not one)
one_object() { [ ! -L "$1" ] && [ -f "$1" ] && [ "$(jq -s 'length' "$1" 2>/dev/null)" = 1 ] && jq -e 'type == "object"' "$1" >/dev/null 2>&1; }

DEFS='
def is_it: ((if (.command? | type) == "string" then .command else "" end) + " "
    + (if (.args? | type) == "array" then (.args | map(tostring) | join(" ")) else "" end))
  | test("(^|[^A-Za-z0-9_.-])" + $n + "\\.(py|sh)($|[^A-Za-z0-9_.-])");
def groups: if type == "object" and (.hooks | type) == "object" then [.hooks[] | select(type == "array") | .[] | select(type == "object" and (.hooks | type) == "array") | .hooks[] | select(type == "object")] else [] end;
'
COUNT_JQ="$DEFS"' [groups[] | select(is_it)] | length'
# settings.local.json is never edited, so a hook wired there blocks the delete: refuse, naming the file.
if [ "$have_l" -eq 1 ]; then
  one_object "$L" || { echo "hook-unwire: $L is a symlink or not one valid JSON object; cannot tell whether it wires $NAME; left unchanged" >&2; exit 1; }
  lc=$(jq --arg n "$NAME" "$COUNT_JQ" "$L" 2>/dev/null) || lc=""
  [ -n "$lc" ] || { echo "hook-unwire: could not read $L; left unchanged" >&2; exit 1; }
  [ "$lc" -eq 0 ] || { echo "hook-unwire: $NAME is wired in .claude/settings.local.json, which this script never edits; unwire it there by hand, then re-run hook-unwire.sh (it also checks settings.json) before deleting the file" >&2; exit 1; }
fi
if [ "$have_s" -eq 0 ]; then echo "no wiring found for $NAME"; exit 0; fi
one_object "$S" || { echo "hook-unwire: $S is a symlink, not a regular file, or not one valid JSON object; left unchanged" >&2; exit 1; }
count=$(jq --arg n "$NAME" "$COUNT_JQ" "$S" 2>/dev/null) || count=""
[ -n "$count" ] || { echo "hook-unwire: could not read $S; left unchanged" >&2; exit 1; }
if [ "$count" -eq 0 ]; then echo "no wiring found for $NAME"; exit 0; fi
mode=$(stat -c %a "$S" 2>/dev/null || stat -f %Lp "$S" 2>/dev/null)

tmp=$(mktemp "$PROJECT/.claude/.settings.XXXXXX") || { echo "hook-unwire: cannot make a temp file; left unchanged" >&2; exit 1; }
if jq --arg n "$NAME" "$DEFS"'
  .hooks |= with_entries(.value |= (
    if type == "array" then
      [ .[] |
        if type == "object" and (.hooks | type) == "array" then
          (.hooks | length) as $before
          | (.hooks |= map(select((type == "object" and is_it) | not)))
          | select($before == (.hooks | length) or (.hooks | length) > 0)
        else . end ]
    else . end))' "$S" > "$tmp" 2>/dev/null && { [ -z "$mode" ] || chmod "$mode" "$tmp"; }; then
  mv "$tmp" "$S" || { rm -f "$tmp"; echo "hook-unwire: could not replace $S; left unchanged" >&2; exit 1; }
  echo "hook-unwire: removed $count wiring entries for $NAME from .claude/settings.json"
else
  rm -f "$tmp"; echo "hook-unwire: jq failed; $S left unchanged" >&2; exit 1
fi
