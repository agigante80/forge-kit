#!/usr/bin/env bash
# forge-adapt S3 catalogue: print every forge-kit component's type, name, and <name>-version marker.
#
# Shipped as a real script so the forge-adapt skill RUNS it verbatim instead of an LLM executor
# paraphrasing an inline block and reintroducing fixed bugs (printing "SKILL.md" instead of the
# skill's directory name, dropping `shopt -s nullglob` and exiting 1, etc.). Read-only; always
# exits 0 so a component group with no hooks/agents never reads as "Failed to run".
#
# Usage: forge-adapt-catalogue.sh <FORGE_KIT_DIR>
#   Prints "=== <group> ===" headers and "<type>: <name> | v<N>" rows.
#   The NAME is the component name (agent/command/hook basename, skill DIRECTORY name), never the
#   filename - every skill file is SKILL.md, so echoing the filename would collapse them all.
set -uo pipefail

FORGE_KIT_DIR="${1:-}"
if [ -z "$FORGE_KIT_DIR" ] || [ ! -d "$FORGE_KIT_DIR/plugins" ]; then
  echo "forge-adapt-catalogue: no plugins/ tree under '${FORGE_KIT_DIR:-<unset>}'" >&2
  exit 0
fi

# Version resolution runs in two stages, because a component's marker name is not guaranteed to
# equal the name this catalogue prints for it.
#
# Stage 1, by name: the marker must be a lowercase-kebab name followed by digits, anchored to its
# comment lead-in so a match-name that is a suffix of a longer marker (e.g. "adapt" inside
# "forge-adapt-version") cannot match by substring; \K then captures only the digits.
#
# Stage 2, the fallback (issue #95): take the file's FIRST marker whatever its name, which is the
# same positional "first <name>-version wins" rule the three enforcement points use (see ver_of in
# scripts/validate-plugins.sh, scripts/check-version-bump.sh, .githooks/pre-commit), so the
# catalogue and the guards agree on which marker is a file's version. It has no match-name to
# substring-collide with, so it drops the lead-in anchor and stays no stricter than those guards;
# template-version is skipped there for the same reason it is here.
#
# Without stage 2, skills/adapt/SKILL.md printed "vnone": the row NAME is the directory ("adapt")
# but the marker reads "forge-adapt-version". That silently hid forge-adapt itself from its own
# drift/refresh comparison, i.e. the one component whose job is detecting drift.
#
# Rejected alternative: rename skills/adapt/ to skills/forge-adapt/ so name and marker agree. It is
# conceptually cleaner but changes the published slash-command form users type
# (/forge-kit-adapt:adapt) and every documented install path, to fix one row. The fallback is the
# cheaper fix and it also covers any FUTURE name/marker divergence rather than this one instance.
#
# Every path shape walked below is one that validate-plugins.sh requires a marker on, so a "vnone"
# row means a marker that is provably present could not be read, never a genuinely unversioned
# component. test-forge-adapt-catalogue.sh asserts no row prints it.
cat_row() {  # $1 = type label, $2 = file, $3 = NAME (never basename "$2")
  local v
  v=$(grep -oP -- "(?:<!--\s*|#\s*)${3}-version:\s*\K\d+" "$2" | head -1)
  [ -n "$v" ] || v=$(grep -oP -- '[a-z0-9-]+-version:\s*\d+' "$2" \
                       | grep -v '^template-version' | head -1 | grep -oP '\d+$')
  echo "$1: $3 | v${v:-none}"
}

shopt -s nullglob   # empty globs must not iterate a literal path and leave a non-zero exit
for dir in "$FORGE_KIT_DIR"/plugins/*/; do
  echo "=== $(basename "$dir") ==="
  for f in "$dir"agents/*.md;       do cat_row subagent "$f" "$(basename "$f" .md)"; done
  for f in "$dir"commands/*.md;     do cat_row command  "$f" "$(basename "$f" .md)"; done
  for f in "$dir"skills/*/SKILL.md; do cat_row skill    "$f" "$(basename "$(dirname "$f")")"; done
  for f in "$dir"hooks/*.py "$dir"hooks/*.sh; do n=$(basename "$f"); cat_row hook "$f" "${n%.*}"; done
  # Versioned shell assets (issue #64): copied verbatim into projects (e.g. scripts/forge-lib.sh),
  # so drift/refresh needs their forge-kit-side version here like any other component's.
  for f in "$dir"skills/*/assets/*.sh; do n=$(basename "$f"); cat_row asset "$f" "${n%.*}"; done
done
exit 0
