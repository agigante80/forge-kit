#!/usr/bin/env bash
# Installs ai-projectforge skills and agents into ~/.claude/ so they are
# available in EVERY project without per-project copying.
#
# Safe to re-run - existing files are only overwritten if you confirm.
set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_DIR="$HOME/.claude"

echo ""
echo "ai-projectforge global install"
echo "=============================="
echo "Installs to: $GLOBAL_DIR"
echo ""

install_item() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ -e "$dest" ]]; then
    read -rp "  $label already exists - overwrite? (y/N): " OVERWRITE
    if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
      echo "  Skipped: $label"
      return
    fi
  fi

  if [[ -d "$src" ]]; then
    cp -r "$src" "$(dirname "$dest")/"
  else
    cp "$src" "$dest"
  fi
  echo "  Installed: $label"
}

# Skills
echo "Skills (available in all projects):"
mkdir -p "$GLOBAL_DIR/skills"
install_item \
  "$SCAFFOLD_DIR/.claude/skills/upgrade-audit" \
  "$GLOBAL_DIR/skills/upgrade-audit" \
  "upgrade-audit (gap report vs ai-projectforge)"

echo ""
echo "Agents (optional - available in all projects):"
mkdir -p "$GLOBAL_DIR/agents"

for agent in ticket-gate code-reviewer security-auditor architect-review \
             backend-architect backend-security-coder api-security-tester \
             tdd-orchestrator test-automator performance-engineer; do
  src="$SCAFFOLD_DIR/.claude/agents/${agent}.md"
  dest="$GLOBAL_DIR/agents/${agent}.md"
  read -rp "  Install $agent globally? (y/N): " INSTALL_AGENT
  if [[ "$INSTALL_AGENT" == "y" || "$INSTALL_AGENT" == "Y" ]]; then
    install_item "$src" "$dest" "$agent"
  fi
done

echo ""
echo "Commands (optional - slash commands in all projects):"
mkdir -p "$GLOBAL_DIR/commands"

for cmd in gate-ticket full-review pr-enhance; do
  src="$SCAFFOLD_DIR/.claude/commands/${cmd}.md"
  dest="$GLOBAL_DIR/commands/${cmd}.md"
  read -rp "  Install /$cmd globally? (y/N): " INSTALL_CMD
  if [[ "$INSTALL_CMD" == "y" || "$INSTALL_CMD" == "Y" ]]; then
    install_item "$src" "$dest" "/$cmd command"
  fi
done

echo ""
echo "Done. Globally installed items are active in all projects immediately."
echo ""
echo "Note: ticket-gate.md installed globally still needs {{GITHUB_REPO}} replaced"
echo "per-project. Either keep it in .claude/agents/ per project, or set it to a"
echo "default repo in the global copy."
echo ""
echo "To update global installs after pulling ai-projectforge:"
echo "  $SCAFFOLD_DIR/install-global.sh"
