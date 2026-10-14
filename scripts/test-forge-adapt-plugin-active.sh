#!/usr/bin/env bash
# Contract test for forge-adapt-plugin-active.sh (#500).
#
# THE FAILURE THIS PREVENTS. S2 called the governance plugin active when its cache directory existed
# or the registry mentioned it anywhere. A project that had disabled it, or disabled the devops
# plugin it depends on, still read `yes`, and forge-adapt then deleted that project's working local
# block-dashes copy and reported success. Every fixture below is a throwaway config dir and project.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/forge-adapt-plugin-active.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TAB=$(printf '\t')

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want '$3', got '$2')"; }

G=forge-kit-governance@forge-kit
D=forge-kit-devops@forge-kit

# fresh <name>: a clean config dir CFG and project P under $T/<name>.
fresh() {
  W="$T/$1"; CFG="$W/cfg"; P="$W/proj"
  rm -rf "$W"; mkdir -p "$CFG/plugins" "$P/.claude"
  P=$(cd -P "$P" && pwd -P)
}
# plug <name> <deps json array> [extra json members]: a plugin dir with a manifest; prints its path.
plug() {
  local d="$W/cache/$1"
  mkdir -p "$d/.claude-plugin"
  printf '{"name":"%s","dependencies":%s%s}\n' "$1" "$2" "${3:+,$3}" > "$d/.claude-plugin/plugin.json"
  printf '%s' "$d"
}
# entry <scope> <installPath> [projectPath]: one registry entry as JSON.
entry() {
  jq -nc --arg s "$1" --arg i "$2" --arg p "${3-}" \
    '{scope:$s, installPath:$i} + (if $p == "" then {} else {projectPath:$p} end)'
}
# registry <id>=<entry>[,<entry>] ...: writes installed_plugins.json (several entries per id allowed
# by passing id=entry1 id=entry2).
registry() {
  local args=() a
  for a in "$@"; do args+=("$a"); done
  printf '%s\n' "${args[@]}" | jq -Rn '
    [inputs | capture("^(?<id>[^=]+)=(?<e>.*)$") | {id, e: (.e | fromjson)}]
    | group_by(.id) | map({key: .[0].id, value: map(.e)}) | from_entries
    | {version: 2, plugins: .}' > "$CFG/plugins/installed_plugins.json"
}
settings() { printf '%s\n' "$2" > "$1"; }   # settings <file> <json>
run() {
  out=$(CLAUDE_CONFIG_DIR="$CFG" bash "$S" "$@" 2>"$W/err"); rc=$?
}
want() {   # want <label> <expected stdout>
  eq "$1" "$out" "$2"
  eq "$1: exit 0" "$rc" "0"
  eq "$1: nothing on stderr" "$(cat "$W/err")" ""
}

# The healthy baseline: governance (depends on devops) and devops, both user scope.
baseline() {
  fresh "$1"
  local gp dp
  gp=$(plug forge-kit-governance '["forge-kit-devops@forge-kit"]')
  dp=$(plug forge-kit-devops '[]')
  registry "$G=$(entry user "$gp")" "$D=$(entry user "$dp")"
  settings "$CFG/settings.json" "{\"enabledPlugins\":{\"$G\":true,\"$D\":true}}"
  GP="$gp"; DP="$dp"
}

# --- condition 1: enabled everywhere is yes; a local disable is no with its reason ---------------
baseline c1
run "$G" --project "$P"; want "enabled everywhere reads yes" "yes"
settings "$P/.claude/settings.local.json" "{\"enabledPlugins\":{\"$G\":false}}"
run "$G" --project "$P"; want "a local disable reads no with the file" "no${TAB}disabled in .claude/settings.local.json"

# --- condition 2: precedence ----------------------------------------------------------------------
baseline c2
settings "$CFG/settings.json" "{\"enabledPlugins\":{\"$G\":false,\"$D\":true}}"
settings "$P/.claude/settings.local.json" "{\"enabledPlugins\":{\"$G\":true}}"
run "$G" --project "$P"; want "a local true beats a user false" "yes"
baseline c2b
settings "$P/.claude/settings.json" "{\"enabledPlugins\":{\"$G\":false}}"
run "$G" --project "$P"; want "a project false beats a user true" "no${TAB}disabled in .claude/settings.json"
baseline c2c
settings "$CFG/settings.json" "{\"enabledPlugins\":{\"$G\":false,\"$D\":true}}"
run "$G" --project "$P"; want "a user false names 'user settings', never a path" "no${TAB}disabled in user settings"
baseline c2d
settings "$P/.claude/settings.json" "{\"enabledPlugins\":{\"$G\":true}}"
settings "$P/.claude/settings.local.json" "{\"enabledPlugins\":{\"$G\":false}}"
run "$G" --project "$P"; want "local settings outrank project settings" "no${TAB}disabled in .claude/settings.local.json"

# --- condition 3: no entry anywhere --------------------------------------------------------------
baseline c3
rm -f "$CFG/settings.json"
run "$G" --project "$P"; want "an installed plugin with no entry anywhere is enabled" "yes"
gp=$(plug forge-kit-governance '["forge-kit-devops@forge-kit"]' '"defaultEnabled":false')
registry "$G=$(entry user "$gp")" "$D=$(entry user "$DP")"
run "$G" --project "$P"; want "the plugin's own defaultEnabled false is honoured" "no${TAB}disabled by the plugin default"
settings "$P/.claude/settings.local.json" "{\"enabledPlugins\":{\"$G\":true}}"
run "$G" --project "$P"; want "an explicit true beats the plugin default" "yes"

# --- condition 4: dependencies -------------------------------------------------------------------
baseline c4
gp=$(plug forge-kit-governance '["forge-kit-devops"]')
registry "$G=$(entry user "$gp")" "$D=$(entry user "$DP")"
run "$G" --project "$P"; want "a bare dependency resolves against the declaring marketplace" "yes"
settings "$P/.claude/settings.local.json" "{\"enabledPlugins\":{\"$D\":false}}"
run "$G" --project "$P"; want "a disabled dependency reads no" "no${TAB}dependency forge-kit-devops disabled"
baseline c4b
registry "$G=$(entry user "$GP")"
run "$G" --project "$P"; want "a dependency with no registry entry reads no" "no${TAB}dependency forge-kit-devops not installed"
baseline c4c
dp2=$(plug forge-kit-devops '[]' '"defaultEnabled":false')
registry "$G=$(entry user "$GP")" "$D=$(entry user "$dp2")"
settings "$CFG/settings.json" "{\"enabledPlugins\":{\"$G\":true}}"
run "$G" --project "$P"; want "a dependency's own default-off reads no" "no${TAB}dependency forge-kit-devops disabled"
baseline c4d
gp=$(plug forge-kit-governance '[{"name":"x"}]')
registry "$G=$(entry user "$gp")" "$D=$(entry user "$DP")"
run "$G" --project "$P"; want "an object dependency is an unsupported shape" "unknown${TAB}unsupported dependency shape"
gp=$(plug forge-kit-governance '["a@b@c"]')
registry "$G=$(entry user "$gp")" "$D=$(entry user "$DP")"
run "$G" --project "$P"; want "a dependency with two @ is an unsupported shape" "unknown${TAB}unsupported dependency shape"
baseline c4e
rm -f "$GP/.claude-plugin/plugin.json"
run "$G" --project "$P"; want "a missing manifest reads no" "no${TAB}plugin manifest missing"
baseline c4f
printf '{ nope' > "$GP/.claude-plugin/plugin.json"
run "$G" --project "$P"; want "an unparseable manifest reads unknown" "unknown${TAB}cannot parse plugin manifest"

# --- condition 5: which registry entries count ---------------------------------------------------
baseline c5
mkdir -p "$W/real" "$W/other"
RP=$(CDPATH= cd -P "$W/real" && pwd -P); ln -s "$RP" "$W/link"
registry "$G=$(entry local "$GP" "$RP")" "$D=$(entry user "$DP")"
settings "$CFG/settings.json" "{}"
run "$G" --project "$W/link"; want "a local install for this project reads yes, through a symlinked --project" "yes"
registry "$G=$(entry local "$GP" "$W/other")" "$D=$(entry user "$DP")"
run "$G" --project "$RP"; want "a local install for another project reads no" "no${TAB}not installed for this project"
mkdir -p "$CFG/plugins/cache/forge-kit/forge-kit-governance"
run "$G" --project "$RP"; want "and a leftover cache dir changes nothing" "no${TAB}not installed for this project"
mkdir -p "$W/real/sub"
registry "$G=$(entry local "$GP" "$RP")" "$D=$(entry user "$DP")"
run "$G" --project "$RP/sub"; want "a project below the entry's path is not a match (exact, not prefix)" "no${TAB}not installed for this project"
registry "$G=$(entry project "$GP" "$RP")" "$D=$(entry user "$DP")"
run "$G" --project "$RP"; want "a project-scope entry for this project reads yes" "yes"
registry "$G=$(entry local "$GP" "$W/other")" "$G=$(entry user "$GP")" "$D=$(entry user "$DP")"
run "$G" --project "$RP"; want "several entries: the user one counts, the other project's does not" "yes"
rm -f "$CFG/plugins/installed_plugins.json"
run "$G" --project "$RP"; want "no registry file at all reads no" "no${TAB}not installed for this project"
registry "$D=$(entry user "$DP")"
run "$G" --project "$RP"; want "a registry without the plugin reads no" "no${TAB}not installed for this project"

# --- condition 6: cannot be determined -----------------------------------------------------------
baseline c6
printf '{ not json' > "$P/.claude/settings.local.json"
run "$G" --project "$P"; want "a malformed local settings file reads unknown" "unknown${TAB}cannot parse .claude/settings.local.json"
rm -f "$P/.claude/settings.local.json"
printf '{ not json' > "$CFG/settings.json"
run "$G" --project "$P"; want "a malformed user settings file reads unknown, without its path" "unknown${TAB}cannot parse user settings"
baseline c6b
printf 'nope' > "$CFG/plugins/installed_plugins.json"
run "$G" --project "$P"; want "an unparseable registry reads unknown" "unknown${TAB}cannot parse installed_plugins.json"
baseline c6c
out=$(PATH=/nonexistent CLAUDE_CONFIG_DIR="$CFG" "$BASH" "$S" "$G" --project "$P" 2>"$W/err"); rc=$?
want "a PATH without jq reads unknown" "unknown${TAB}jq is not installed"

# --- default project is $PWD, config dir falls back to HOME/.claude -------------------------------
baseline c7
out=$(cd "$P" && CLAUDE_CONFIG_DIR="$CFG" bash "$S" "$G" 2>"$W/err"); rc=$?
want "the default project is the current directory" "yes"
mkdir -p "$W/h/.claude/plugins"; cp "$CFG/plugins/installed_plugins.json" "$W/h/.claude/plugins/"
out=$(cd "$P" && env -u CLAUDE_CONFIG_DIR HOME="$W/h" bash "$S" "$G" 2>"$W/err"); rc=$?
want "without CLAUDE_CONFIG_DIR the config dir is HOME/.claude" "yes"

# --- the script writes nothing -------------------------------------------------------------------
baseline c8
find "$W" -type f -exec cksum {} + | sort > "$W/before"
run "$G" --project "$P"
find "$W" -type f -not -name err -not -name before -not -name after -exec cksum {} + | sort > "$W/after"
grep -v ' '"$W"'/err$' "$W/before" | grep -v '/before$' > "$W/before2"
eq "no fixture file changes" "$(diff "$W/before2" "$W/after")" ""

# --- usage errors --------------------------------------------------------------------------------
baseline c9
for args in "" "noat" "$G --bogus" "$G --project" "$G $D" "$G --project $W/missing-dir"; do
  # shellcheck disable=SC2086
  err=$(CLAUDE_CONFIG_DIR="$CFG" bash "$S" $args 2>&1 >/dev/null); rc=$?
  eq "usage error exits 2: '$args'" "$rc" "2"
  case "$err" in "forge-adapt-plugin-active:"*) ok "and says so on stderr: '$args'" ;; *) bad "stderr was '$err' for '$args'" ;; esac
done

echo ""
echo "forge-adapt-plugin-active tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
