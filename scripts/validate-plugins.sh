#!/usr/bin/env bash
# Structural validation for the forge-kit marketplace. Runs in CI and locally.
# Checks (current tree, no git diff needed):
#   1. each plugin.json is valid JSON with name + description + semver version + author
#   2. marketplace.json is valid JSON and every plugin source resolves to a plugin.json
#   3. every component (agent/command/skill/hook/shell asset) carries a <name>-version marker
#   4. every declared `dependencies` entry is well shaped and names a plugin this marketplace has
# Exit 1 on any violation, with every violation on stderr. This is the forge-kit analogue of
# `claude plugin validate`, and check 4 is the half that analogue does NOT cover (see below).
# Contract test: scripts/test-validate-plugins.sh.
set -uo pipefail
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

if [ "$err" -ne 0 ]; then echo ""; echo "forge-kit: plugin validation FAILED."; exit 1; fi
echo "forge-kit: plugin validation passed."
