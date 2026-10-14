#!/usr/bin/env bash
# forge-adapt-plugin-active.sh: is a plugin LIVE in this project? (#500)
#
#   forge-adapt-plugin-active.sh <name@marketplace> [--project <dir>]
#
# Prints exactly one line and exits 0 for every answer:
#   yes
#   no<TAB><reason>        a definite no
#   unknown<TAB><reason>   the answer could not be determined (the caller must treat it as no)
# Exit 2 is a usage error only (no id, an unknown option, --project without a value or a missing
# directory). Nothing is written to stderr on an answer, because forge-adapt's S2 harness merges
# 2>&1 and a stray line would corrupt the one-line contract. Read only: it writes nothing anywhere.
#
# WHY. S2 used to call the governance plugin active when its cache directory existed or
# installed_plugins.json mentioned it anywhere. The cache survives a disable and an uninstall, the
# registry lists `local` installs made for OTHER projects, and enabledPlugins was never read, so a
# project that disabled the plugin (or a dependency of it) still read `yes`, and forge-adapt then
# deleted that project's working local block-dashes copy as "superseded by the plugin".
#
# LIVE means all of:
#   1. installed for this project: an entry of <config dir>/plugins/installed_plugins.json whose
#      scope is `user`, or `local`/`project` with a projectPath equal to the project. Both paths
#      are compared by EXACT match after `cd -P && pwd -P`, never by prefix (a worktree carries its
#      own `local` entry; a symlinked project path must still match).
#   2. enabled: enabledPlugins[<id>] from .claude/settings.local.json, then .claude/settings.json,
#      then <config dir>/settings.json; the first file that HAS the key wins. Absent from all
#      three the plugin is enabled unless its own plugin.json (at the entry's installPath) sets
#      `defaultEnabled: false`.
#   3. every plugin it declares in plugin.json `dependencies` is installed and enabled by rules 1
#      and 2. A dependency is `name@marketplace` or a bare `name` (resolved against the declaring
#      plugin's marketplace); any other shape is `unknown`.
# LIMITS, stated so nobody mistakes the answer for more than it is: managed policy settings and the
# --settings flag outrank these files and are NOT read; dependencies are NOT followed recursively
# (a dependency's own dependencies are not checked); the dependency version range is not checked.
#
# The config dir is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}. Reasons name a project-relative settings
# file or `user settings`, never an absolute or home path, so the line is safe to paste into a
# public ticket. Requires jq; without it the answer is `unknown`, never a guess.
set -uo pipefail

ID=""; PROJ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || { echo "forge-adapt-plugin-active: --project needs a directory" >&2; exit 2; }
      PROJ="$2"; shift 2 ;;
    --*) echo "forge-adapt-plugin-active: unknown option '$1'" >&2; exit 2 ;;
    *)
      [ -z "$ID" ] || { echo "forge-adapt-plugin-active: one plugin id only (got a second '$1')" >&2; exit 2; }
      ID="$1"; shift ;;
  esac
done
case "$ID" in
  ?*@?*) ;;
  *) echo "forge-adapt-plugin-active: give <name@marketplace>" >&2; exit 2 ;;
esac
[ -n "$PROJ" ] || PROJ="$PWD"
PROJ=$(CDPATH= cd -P -- "$PROJ" 2>/dev/null && pwd -P) \
  || { echo "forge-adapt-plugin-active: --project is not a directory" >&2; exit 2; }

TAB=$(printf '\t')
US=$(printf '\037')   # field separator for registry rows: a tab is IFS whitespace and would collapse an empty projectPath
no()      { printf 'no%s%s\n' "$TAB" "$1"; exit 0; }
unknown() { printf 'unknown%s%s\n' "$TAB" "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || unknown "jq is not installed"

CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
REG="$CFG/plugins/installed_plugins.json"

# Settings files in precedence order, with the name a reason may print for each.
SETTINGS_PATHS=("$PROJ/.claude/settings.local.json" "$PROJ/.claude/settings.json" "$CFG/settings.json")
SETTINGS_NAMES=(".claude/settings.local.json" ".claude/settings.json" "user settings")

# A file that exists must parse, whether or not it has our key: a half-written settings file is
# exactly when a guess would be wrong.
i=0
for f in "${SETTINGS_PATHS[@]}"; do
  if [ -e "$f" ]; then
    jq -e 'type == "object"' "$f" >/dev/null 2>&1 || unknown "cannot parse ${SETTINGS_NAMES[$i]}"
  fi
  i=$((i + 1))
done
if [ -e "$REG" ]; then
  jq -e '.plugins | type == "object"' "$REG" >/dev/null 2>&1 || unknown "cannot parse installed_plugins.json"
fi

canon() { local d; d=$(CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P) && printf '%s\n' "$d" || printf '%s\n' "$1"; }

# entries_for <id>: one `P:<installPath>` line for every registry entry that counts for this
# project (the prefix keeps an entry with no installPath from vanishing as an empty line).
entries_for() {
  local id="$1" scope pp ip
  [ -e "$REG" ] || return 0
  while IFS="$US" read -r scope pp ip; do
    case "$scope" in
      user) printf 'P:%s\n' "$ip" ;;
      local|project)
        if [ -n "$pp" ] && [ "$(canon "$pp")" = "$PROJ" ]; then printf 'P:%s\n' "$ip"; fi ;;
    esac
  done < <(jq -r --arg id "$id" \
    '(.plugins[$id] // []) | if type == "array" then .[] else empty end
     | [(.scope // ""), (.projectPath // ""), (.installPath // "")] | join("\u001f")' "$REG" 2>/dev/null)
}

# decide <id> <installPaths>: sets DECISION to `true`, `false` or `` (no settings file has the key)
# and WHERE to the name of the file that decided. Plain globals, not a $(...) result, so WHERE
# survives. The loop reads the first file that HAS the key, in precedence order.
DECISION=""; WHERE=""
decide() {
  local id="$1" i=0 f v
  DECISION=""; WHERE=""
  for f in "${SETTINGS_PATHS[@]}"; do
    if [ -e "$f" ]; then
      v=$(jq -r --arg id "$id" \
        '.enabledPlugins | if type == "object" and has($id) and (.[$id] | type == "boolean") then .[$id] | tostring else "" end' \
        "$f" 2>/dev/null)
      if [ "$v" = true ] || [ "$v" = false ]; then DECISION="$v"; WHERE="${SETTINGS_NAMES[$i]}"; return 0; fi
    fi
    i=$((i + 1))
  done
}

# default_off <installPath>: succeeds when that plugin.json sets defaultEnabled to false.
default_off() {
  local m="$1/.claude-plugin/plugin.json"
  [ -n "$1" ] && [ -f "$m" ] && [ "$(jq -r '.defaultEnabled == false' "$m" 2>/dev/null)" = true ]
}

MARKET="${ID#*@}"

# 1. installed for this project
ENTRIES=$(entries_for "$ID")
[ -n "$ENTRIES" ] || no "not installed for this project"

# 2. enabled (an explicit setting always wins over the plugin's own default)
decide "$ID"
if [ "$DECISION" = false ]; then
  no "disabled in $WHERE"
elif [ -z "$DECISION" ]; then
  while IFS= read -r line; do
    default_off "${line#P:}" && no "disabled by the plugin default"
  done <<EOF2
$ENTRIES
EOF2
fi

# 3. dependencies, from every matching entry's own manifest (never a glob of the cache, which holds
# one directory per installed version)
while IFS= read -r line; do
  ip="${line#P:}"; m="$ip/.claude-plugin/plugin.json"
  [ -n "$ip" ] && [ -f "$m" ] || no "plugin manifest missing"
  jq -e 'type == "object"' "$m" >/dev/null 2>&1 || unknown "cannot parse plugin manifest"
  DEPS=$(jq -r '(.dependencies // []) | if type == "array" then .[] | if type == "string" then . else "\u0001" end else "\u0001" end' "$m" 2>/dev/null)
  [ -n "$DEPS" ] || continue
  while IFS= read -r dep; do
    case "$dep" in
      ""|*[!A-Za-z0-9._@-]*|@*|*@|*@*@*) unknown "unsupported dependency shape" ;;
    esac
    case "$dep" in *@*) did="$dep" ;; *) did="$dep@$MARKET" ;; esac
    dname="${did%@*}"
    DENT=$(entries_for "$did")
    [ -n "$DENT" ] || no "dependency $dname not installed"
    decide "$did"
    if [ "$DECISION" = false ]; then
      no "dependency $dname disabled"
    elif [ -z "$DECISION" ]; then
      while IFS= read -r dl; do
        default_off "${dl#P:}" && no "dependency $dname disabled"
      done <<EOF3
$DENT
EOF3
    fi
  done <<EOF4
$DEPS
EOF4
done <<EOF5
$ENTRIES
EOF5

echo yes
