#!/usr/bin/env bash
# Structural validation for the forge-kit marketplace. Runs in CI and locally.
# Checks (current tree, no git diff needed):
#   1. each plugin.json is valid JSON with name + description + semver version + author
#   2. marketplace.json is valid JSON and every plugin source resolves to a plugin.json
#   3. every component (agent/command/skill/hook/shell asset) carries a <name>-version marker
#   4. every declared `dependencies` entry is well shaped and names a plugin this marketplace has
#   5. every subagent_type dispatched by a component, and every skill or command frontmatter
#      `agent:`, names an agent that exists
#   6. no scripts/*.sh carries the marker name of a shipped shell asset (a second copy, #231)
#   7. each component's model and effort, and each dispatch's model, sit inside its role's range
#      in docs/guides/model-tiers.md (#253; its blind spots are listed at the check)
# Exit 1 on any violation, with every violation on stderr. This is the forge-kit analogue of
# `claude plugin validate`, and check 4 is the half that analogue does NOT cover (see below).
# Contract test: scripts/test-validate-plugins.sh.
set -uo pipefail
# Resolved before the cd: $0 may be relative. Sourced for component_frontmatter_field (check 5).
. "$(cd "$(dirname "$0")" && pwd)/guard-lib.sh"
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

err=0
fail() { echo "  ✗ $1" >&2; err=1; }
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+([-+].+)?$'

# 1. plugin.json
for pj in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$pj" ] || continue
  if ! jq -e . "$pj" >/dev/null 2>&1; then fail "$pj: invalid JSON"; continue; fi
  [ -n "$(jq -r '.name // empty' "$pj")" ]        || fail "$pj: missing name"
  [ -n "$(jq -r '.description // empty' "$pj")" ] || fail "$pj: missing description"
  ver=$(jq -r '.version // empty' "$pj")
  if [ -z "$ver" ]; then fail "$pj: missing version"
  elif ! echo "$ver" | grep -qE "$SEMVER"; then fail "$pj: version '$ver' is not semver"; fi

  # ATTRIBUTION IS REQUIRED HERE, not merely suggested by the advisory step (#173). Every group
  # was missing it, so `claude plugin validate` printed eight warnings on every build and nobody
  # read any of them; an advisory check that is never silent is an advisory check that is never
  # heard. The shape is the CLI's own, probed on 2.1.267: an OBJECT with a non-empty `name`, and
  # an optional `url`. A bare string fails there with `author: Invalid input`, so accepting one
  # here would make this guard laxer than the thing it stands in front of.
  atype=$(jq -r 'if has("author") then (.author | type) else "missing" end' "$pj")
  case "$atype" in
    missing) fail "$pj: missing author. Add {\"name\": \"<handle>\"} (a url is optional; an email address is not required and is not published here)" ;;
    object)
      [ -n "$(jq -r '.author.name // empty' "$pj")" ] \
        || fail "$pj: author.name is missing or empty. An empty attribution is the same as none, and the CLI rejects it too" ;;
    *) fail "$pj: author is a $atype; it must be an object with a name (the CLI rejects a bare string)" ;;
  esac
done

# 2. marketplace.json integrity
MP=.claude-plugin/marketplace.json
if jq -e . "$MP" >/dev/null 2>&1; then
  jq -e '(.plugins | type == "array") and (.plugins | length > 0)' "$MP" >/dev/null 2>&1 \
    || fail "$MP: .plugins must be a non-empty array"
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    [ -f "${src#./}/.claude-plugin/plugin.json" ] || fail "marketplace.json: source '$src' has no plugin.json"
  done < <(jq -r '.plugins[].source' "$MP")
else
  fail "$MP: invalid or missing JSON"
fi

# 3. component version markers (ignores body template-version references)
#
# THE ENFORCED PATH SET. Exactly ONE directory level deep: `plugins/<group>/agents/x.md` is a
# component, `plugins/<group>/agents/references/x.md` is not. This string is byte-identical to the
# pattern in scripts/check-version-bump.sh and .githooks/pre-commit, and scripts/test-component-paths.sh
# fails if the three drift apart or if the catalogue's glob stops agreeing with them.
#
# It used to be a set of `find -path '*/agents/*.md'` globs (issue #112). In `find -path`, unlike a
# shell glob, `*` CROSSES `/`, so those matched at any depth: a nested reference file would have been
# required to carry a version marker that the catalogue could never see and nothing would ever
# compare. Using the same ERE the other two guards use removes the dialect difference entirely.
COMPONENT_RE='^plugins/[^/]+/(agents|commands)/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$|^plugins/[^/]+/hooks/[^/]+\.(py|sh)$|^plugins/[^/]+/skills/[^/]+/assets/[^/]+\.sh$'
ver_of() { grep -oP '[a-z0-9-]+-version: \d+' | grep -v '^template-version' | head -1; }
while IFS= read -r f; do
  [ -f "$f" ] || continue
  [ -n "$(ver_of < "$f")" ] || fail "$f: missing <name>-version marker"
done < <(find plugins -type f -regextype posix-extended -regex "$COMPONENT_RE")

# 4. declared cross-group dependencies (#169)
#
# WHAT THE CLI DOES, PROBED AGAINST 2.1.267 RATHER THAN READ. `plugin.json` accepts `dependencies`
# as an ARRAY of `plugin@marketplace` identifiers; the installer resolves them and says so
# (`+ 1 dependency: plug-b`); an OBJECT of version ranges is rejected as `dependencies: Invalid
# input`. But an UNRESOLVABLE identifier passes `claude plugin validate` with no error and then
# INSTALLS SILENTLY, with no dependency line, leaving a user whose dependency never arrived and
# nothing anywhere saying so.
#
# So the CLI checks the SHAPE and never the TARGET. The target is the half a local script can see,
# which is why this check is here rather than left to the advisory step.
#
# THE LIMIT, STATED. A dependency on a FOREIGN marketplace cannot be resolved from this tree, so it
# is reported and not failed. Failing it would invent a violation out of a legitimate declaration,
# which is the mistake the leak guard's near-miss cases exist to prevent.
mkt_name=$(jq -r '.name // empty' "$MP" 2>/dev/null)
mkt_plugins=$(jq -r '.plugins[].name // empty' "$MP" 2>/dev/null)
for pj in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$pj" ] || continue
  jq -e . "$pj" >/dev/null 2>&1 || continue          # check 1 already failed this one
  jq -e 'has("dependencies")' "$pj" >/dev/null 2>&1 || continue
  group=$(jq -r '.name // "?"' "$pj")
  dtype=$(jq -r '.dependencies | type' "$pj")
  if [ "$dtype" != "array" ]; then
    fail "$pj: dependencies is a $dtype; it must be an array of \"plugin@marketplace\" strings (the CLI rejects anything else outright)"
    continue
  fi
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    case "$dep" in
      *@*@*|@*|*@) fail "$group declares dependency '$dep', which is not of the form plugin@marketplace" ; continue ;;
      *@*) : ;;
      *)   fail "$group declares dependency '$dep', which is not of the form plugin@marketplace" ; continue ;;
    esac
    dep_plugin="${dep%@*}"
    dep_mkt="${dep##*@}"
    if [ "$dep_mkt" != "$mkt_name" ]; then
      echo "  note: $group depends on '$dep', in another marketplace; this tree cannot verify it." >&2
      continue
    fi
    printf '%s\n' "$mkt_plugins" | grep -qxF "$dep_plugin" \
      || fail "$group declares dependency '$dep', but marketplace.json lists no plugin named '$dep_plugin'"
  done < <(jq -r '.dependencies[] | select(type == "string")' "$pj")
  # A non-string entry inside the array is caught here rather than ignored.
  bad_entries=$(jq -r '[.dependencies[] | select(type != "string")] | length' "$pj")
  [ "$bad_entries" = "0" ] || fail "$pj: dependencies contains $bad_entries non-string entr(y|ies); each must be a \"plugin@marketplace\" string"
done

# 5. every dispatched agent exists (#180)
#
# WHY THIS IS HERE AND NOT IN A RENAME. #180 asked whether our agent names should carry a plugin
# prefix the way every neighbouring plugin's do. The answer was no: Claude Code namespaces subagent
# types by plugin already, so nothing collides, and renaming every agent would touch every marker
# and every semver to buy readability in a listing most users never see.
#
# But the FAILURE that ticket identified is real and became live the day #178 deleted six agents: a
# component that dispatches `subagent_type: "x"` where no agent x exists fails at RUNTIME, silently,
# the same class as #124's undeclared companion skill. So the check ships without the rename.
#
# `general-purpose` is Claude Code's own built-in and is not ours to provide.
agents=$(find plugins -type f -regextype posix-extended -regex '^plugins/[^/]+/agents/[^/]+\.md$' \
           -exec basename {} .md \; 2>/dev/null | sort -u)
while IFS= read -r target; do
  [ -n "$target" ] || continue
  [ "$target" = general-purpose ] && continue
  printf '%s\n' "$agents" | grep -qxF "$target" || {
    where=$(grep -rlP "subagent_type[\":[:space:]=]+$target\\b" plugins/ 2>/dev/null | head -1)
    fail "${where:-plugins/} dispatches subagent_type '$target', which no agent in this tree provides (it would fail silently at runtime)"
  }
done < <(grep -rhoP 'subagent_type[\":[:space:]=]+\K[a-z][a-z0-9-]*' plugins/ 2>/dev/null | sort -u)

# A skill or command can dispatch too: `context: fork` runs it as the agent its `agent:` key names,
# and a missing one fails silently the same way (#279). Read from FRONTMATTER only, through the
# helper check-component-scope.sh already uses (line 1 exactly `---`, closed by a later `---`), so
# an `agent:` in a body example is not a dispatch and ci-health.md's body `---` rule is never
# mistaken for frontmatter. The value may carry quotes and a `<plugin>:` prefix; both are stripped.
while IFS= read -r f; do
  a=$(component_frontmatter_field "$f" agent)
  a=${a#\"}; a=${a%\"}; a=${a#\'}; a=${a%\'}; a=${a##*:}
  [ -n "$a" ] && [ "$a" != general-purpose ] || continue
  printf '%s\n' "$agents" | grep -qxF "$a" ||
    fail "$f declares agent: '$a', which no agent in this tree provides (it would fail silently at runtime)"
done < <(find plugins -type f -regextype posix-extended \
           -regex '^plugins/[^/]+/commands/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$' 2>/dev/null | sort)

# 6. no scripts/ copy of a shipped shell asset (#231)
#
# The leak guard was installed into this repository the way it is installed into any other: as a
# scripts/ copy, in the one tree that ships the same file as an asset. The hooks ran the asset and a
# second workflow ran the copy, and the first bump to the asset left CI running a stale scanner that
# reported the new asset's own doc examples. Keyed on the MARKER NAME, never on content: a copy that
# still matches byte for byte is the one that is about to drift. scripts/test-*.sh is excluded,
# because four suites carry marker lines as heredoc fixtures, and that exclusion is pinned by a
# near-miss case rather than left to memory.
assets=$(find plugins -type f -regextype posix-extended -regex '^plugins/[^/]+/skills/[^/]+/assets/[^/]+\.sh$' 2>/dev/null)
for sc in scripts/*.sh; do
  [ -f "$sc" ] || continue
  case "$sc" in scripts/test-*) continue ;; esac
  m=$(ver_of < "$sc") || true
  [ -n "$m" ] || continue
  mname="${m%%-version:*}"
  while IFS= read -r asset; do
    [ -n "$asset" ] || continue
    [ "$(ver_of < "$asset" | sed 's/-version:.*//')" = "$mname" ] || continue
    fail "$sc carries the marker '$mname-version', which the shipped asset $asset also carries: a second copy of a shipped asset drifts the moment the asset is bumped; run the asset instead"
  done <<< "$assets"
done

# 7. every component's model and effort sit inside its role's range (#253)
#
# ONE DEFINITION. docs/guides/model-tiers.md holds a Roles table (the allowed Models and Effort per
# role) and a Components table (each component's role). No component file declares its role: a
# `role:` key would have touched all 28 files and relied on the CLI tolerating an unknown key on
# skills and commands. The values themselves stay in each component's frontmatter, so the table
# states RANGES and cannot drift from a value it never copied. Read by the same heading-anchored,
# first-table-after-the-heading shape check-label-taxonomy.sh uses on labels.md.
#
# DISPATCHES FOLLOW THE AGENT TOOL'S PRECEDENCE (probed on 2.1.281, model-tiers.md Q5): a model
# named at the dispatch site wins over the agent's frontmatter, and with none the frontmatter
# governs. So a NAMED-agent dispatch may name nothing, and one that does must stay inside that
# agent's range. `general-purpose` and `Explore` have no frontmatter in this tree, so a dispatch of
# either that names no model runs on whatever session called it, and it fails.
#
# WHAT A DISPATCH IS, in two shapes. A YAML block: inside a fence, a `Task:` line and an indented
# `subagent_type:` key; its model is a `model:` key at the SAME indentation, so a `model:` inside
# the `prompt: |` text is prompt content and is never read. A prose dispatch: a paragraph outside a
# fence (a table row is its own unit, so one model cannot cover a whole table) naming a backticked
# `general-purpose`, a bare `Explore agent` or a backticked `subagent_type: <name>`, AND carrying
# `subagent`, `sub-agent` or their plurals as a WHOLE word, `Agent tool`, `launch` or `spawn`.
# Whole word is what keeps full-review.md's "All `subagent_type` references use ... `general-purpose`"
# out: it is a policy sentence, and `subagent_type` is not the word `subagent`.
#
# BLIND SPOTS, stated. A dispatch whose agent type is named only in an earlier paragraph; a verb
# outside the list above (ci-health.md's "Run the ticket-gate agent", ticket-gate.md's security
# lens dispatch, decision-brief's "run the gate"); a named agent dispatched in prose without the
# `subagent_type:` form; anything under a skill's references/, which is not scanned; and delegation
# naming no agent type at all, which is guidance rather than a dispatch. It also cannot say whether
# a tier was RIGHT for a run: that is #250's measurement, the line #174 drew for the always-on cost.
TIERS=docs/guides/model-tiers.md
tier_table() {  # tier_table <heading>: the rows of the first table after it, cells trimmed, TSV
  awk -v h="$1" '
    $0 == h { inside = 1; next }
    inside && /^#/ { exit }
    inside && /^[ \t]*\|/ {
      if ($0 ~ /^[ \t]*\|[- \t|:]*$/) { seen = 1; next }   # the separator row
      if (!seen) next                                     # the header row
      n = split($0, c, "|"); out = ""
      for (i = 2; i < n; i++) { v = c[i]; gsub(/`/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
        out = out (i > 2 ? "\t" : "") v }
      print out; rows = 1
    }
    inside && rows && !/^[ \t]*\|/ && NF { exit }
  ' "$TIERS"
}
effort_rank() { case "$1" in low) echo 1;; medium) echo 2;; high) echo 3;; xhigh) echo 4;; max) echo 5;; *) echo 0;; esac; }
in_models() {  # in_models <value> <models-cell>
  printf '%s\n' "$2" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qxF "$1"
}
in_effort() {  # in_effort <value> <effort-cell>, the cell already validated
  local v lo hi
  v=$(effort_rank "$1"); [ "$v" -gt 0 ] || return 1
  lo=$(effort_rank "${2%%..*}"); hi=$(effort_rank "${2##*..}")
  [ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ]
}
fm_key() {  # fm_key <file> <key>: the value in the leading frontmatter only, unquoted
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2)
      sub(/[ \t]+#.*/, "", v); gsub(/^[ \t"'"'"']+|[ \t"'"'"']+$/, "", v); print v; exit }
  ' "$1"
}

if [ ! -f "$TIERS" ]; then
  fail "$TIERS not found: it is the one definition of each component's allowed model and effort"
else
  roles=$(tier_table '### Roles'); comps=$(tier_table '### Components')
  [ -n "$roles" ] || fail "$TIERS: no parseable Roles table under '### Roles'"
  # An EMPTY Components table is a tree with no components, not a parse failure; a missing one is.
  awk '$0 == "### Components" { h = 1; next } h && /^#/ { exit } h && /^[ \t]*\|/ { f = 1; exit } END { exit !f }' "$TIERS" \
    || fail "$TIERS: no parseable Components table under '### Components'"
  while IFS=$'\t' read -r r m e _; do
    [ -n "$r" ] || continue
    if [ "$m" != none ]; then
      for t in $(printf '%s' "$m" | tr ',' ' '); do
        case "$t" in inherit|haiku|sonnet|opus|fable) ;; *) fail "$TIERS: role '$r' has unparseable Models '$m' (each of inherit, haiku, sonnet, opus, fable, or none alone)" ;; esac
      done
    fi
    if [ "$e" != none ]; then
      lo="${e%%..*}"; hi="${e##*..}"
      if [ "$(effort_rank "$lo")" -eq 0 ] || [ "$(effort_rank "$hi")" -eq 0 ] \
         || [ "$(effort_rank "$lo")" -gt "$(effort_rank "$hi")" ]; then
        fail "$TIERS: role '$r' has unparseable Effort '$e' (none, one level, or lo..hi over low < medium < high < xhigh < max)"
      fi
    fi
  done <<< "$roles"
  role_of()   { printf '%s\n' "$comps" | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'; }
  role_cell() { printf '%s\n' "$roles" | awk -F'\t' -v r="$1" -v c="$2" '$1 == r { print $c; exit }'; }

  names=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in */SKILL.md) n=$(basename "$(dirname "$f")") ;; *) n=$(basename "$f" .md) ;; esac
    names="$names$n"$'\n'
    r=$(role_of "$n")
    if [ -z "$r" ]; then fail "$n: no row in $TIERS"; continue; fi
    rm_=$(role_cell "$r" 2); re_=$(role_cell "$r" 3)
    if [ -z "$rm_" ]; then fail "$n: role '$r' is not defined in the Roles table of $TIERS"; continue; fi
    fmm=$(fm_key "$f" model); fme=$(fm_key "$f" effort)
    case "$f" in */agents/*) [ -n "$fmm" ] || fail "$n: agents must declare model (an omitted one silently becomes the session's)" ;; esac
    if [ -n "$fmm" ] && { [ "$rm_" = none ] || ! in_models "$fmm" "$rm_"; }; then
      fail "$n: model '$fmm' outside role '$r' (allowed: $rm_)"
    fi
    if [ -n "$fme" ] && { [ "$re_" = none ] || ! in_effort "$fme" "$re_"; }; then
      fail "$n: effort '$fme' outside role '$r' (allowed: $re_)"
    fi
  done < <(find plugins -type f -regextype posix-extended -regex '^plugins/[^/]+/(agents|commands)/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$' | sort)
  while IFS=$'\t' read -r n _; do
    [ -n "$n" ] || continue
    printf '%s' "$names" | grep -qxF "$n" || fail "$TIERS: Components row '$n' names no component in this tree"
  done <<< "$comps"

  # The dispatch scanner: one TSV row per dispatch, <file> <line> <type> <model-or-empty>.
  while IFS=$'\t' read -r file line type model; do
    [ -n "$type" ] || continue
    case "$type" in
      general-purpose|Explore)
        [ -n "$model" ] || fail "$file:$line: $type dispatch names no model" ;;
      *)
        [ -n "$model" ] || continue
        a="${type##*:}"; r=$(role_of "$a"); [ -n "$r" ] || continue   # the row check above reports it
        rm_=$(role_cell "$r" 2)
        { [ "$rm_" != none ] && in_models "$model" "$rm_"; } \
          || fail "$file:$line: dispatch of '$a' names model '$model' outside role '$r' (allowed: $rm_)" ;;
    esac
  done < <(find plugins -type f -regextype posix-extended -regex '^plugins/[^/]+/(agents|commands)/[^/]+\.md$|^plugins/[^/]+/skills/[^/]+/SKILL\.md$' | sort \
    | xargs -r awk '
      function modelin(t,   s) {
        if (match(t, /model:[ \t]*"?[A-Za-z0-9._-]+/)) { s = substr(t, RSTART + 6, RLENGTH - 6); gsub(/[ \t"]/, "", s); return s }
        if (match(t, /`(haiku|sonnet|opus|fable|inherit)`/)) return substr(t, RSTART + 1, RLENGTH - 2)
        return ""
      }
      function judge(t, ln,   low, ty, s) {
        low = tolower(t)
        if (!(low ~ /(^|[^a-z0-9_-])sub-?agents?([^a-z0-9_-]|$)/ || low ~ /agent tool/ \
              || low ~ /(^|[^a-z])(launch|spawn)([^a-z]|$)/)) return
        ty = ""
        if (t ~ /`general-purpose`/) ty = "general-purpose"
        else if (t ~ /(^|[^A-Za-z])Explore agent/) ty = "Explore"
        else if (match(t, /`subagent_type:[ \t]*"?[a-z][a-z0-9:-]*/)) {
          s = substr(t, RSTART, RLENGTH); sub(/^`subagent_type:[ \t]*"?/, "", s); ty = s }
        if (ty != "") print FILENAME "\t" ln "\t" ty "\t" modelin(t)
      }
      function flush() { if (buf != "") judge(buf, start); buf = "" }
      function task_end() { if (intask && ttype != "") print FILENAME "\t" tline "\t" ttype "\t" tmodel; intask = 0 }
      function yval(l) { sub(/^[ \t]*[a-z_]+:[ \t]*/, "", l); sub(/[ \t]+#.*/, "", l); gsub(/["'"'"' \t]/, "", l); return l }
      FNR == 1 { flush(); task_end(); fence = 0; front = ($0 == "---"); if (front) next }
      front { if ($0 == "---") front = 0; next }
      /^[ \t]*```/ { flush(); if (fence) task_end(); fence = !fence; next }
      fence {
        if ($0 ~ /^[ \t]*Task:[ \t]*$/) { task_end(); intask = 1; ttype = ""; tmodel = ""; tline = FNR; kind = -1; next }
        if (intask && $0 ~ /[^ \t]/) {
          match($0, /^[ \t]*/); ind = RLENGTH
          if (kind < 0) kind = ind
          if (ind == kind && ind > 0) {
            if ($0 ~ /^[ \t]*subagent_type:/) ttype = yval($0)
            else if ($0 ~ /^[ \t]*model:/) tmodel = yval($0)
          }
        }
        next
      }
      /^[ \t]*$/ || /^#/ { flush(); next }
      /^[ \t]*\|/ { flush(); judge($0, FNR); next }
      { if (buf == "") start = FNR; buf = buf " " $0 }
      END { flush(); task_end() }
    ')
fi

if [ "$err" -ne 0 ]; then echo ""; echo "forge-kit: plugin validation FAILED."; exit 1; fi
echo "forge-kit: plugin validation passed."
