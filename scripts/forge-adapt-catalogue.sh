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

# ver_of: the marker must be a lowercase-kebab name followed by digits, anchored to its comment
# lead-in so a match-name that is a suffix of a longer marker (e.g. "adapt" inside
# "forge-adapt-version") cannot match by substring; \K then captures only the digits.
cat_row() {  # $1 = type label, $2 = file, $3 = NAME (never basename "$2")
  local v
  v=$(grep -oP -- "(?:<!--\s*|#\s*)${3}-version:\s*\K\d+" "$2" | head -1)
  echo "$1: $3 | v${v:-none}"
}

shopt -s nullglob   # empty globs must not iterate a literal path and leave a non-zero exit
for dir in "$FORGE_KIT_DIR"/plugins/*/; do
  echo "=== $(basename "$dir") ==="
  for f in "$dir"agents/*.md;       do cat_row subagent "$f" "$(basename "$f" .md)"; done
  for f in "$dir"commands/*.md;     do cat_row command  "$f" "$(basename "$f" .md)"; done
  for f in "$dir"skills/*/SKILL.md; do cat_row skill    "$f" "$(basename "$(dirname "$f")")"; done
  for f in "$dir"hooks/*.py "$dir"hooks/*.sh; do n=$(basename "$f"); cat_row hook "$f" "${n%.*}"; done
done
exit 0
