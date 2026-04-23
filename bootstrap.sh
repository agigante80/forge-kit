#!/usr/bin/env bash
set -euo pipefail

SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "claude-scaffold bootstrap"
echo "========================="
echo ""

# Check prerequisites
if ! command -v gh &>/dev/null; then
  echo "Error: GitHub CLI (gh) is required. Install from https://cli.github.com/"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Error: Not authenticated with GitHub CLI. Run: gh auth login"
  exit 1
fi

# Collect project info
read -rp "GitHub owner/repo (e.g. myorg/my-project): " GITHUB_REPO
if [[ -z "$GITHUB_REPO" || "$GITHUB_REPO" != *"/"* ]]; then
  echo "Error: Must be in owner/repo format"
  exit 1
fi

PROJECT_NAME=$(echo "$GITHUB_REPO" | cut -d'/' -f2)

read -rp "Target directory (default: current directory .): " TARGET_DIR
TARGET_DIR="${TARGET_DIR:-.}"
TARGET_DIR=$(realpath "$TARGET_DIR")

echo ""
echo "Settings:"
echo "  GitHub repo:  $GITHUB_REPO"
echo "  Project name: $PROJECT_NAME"
echo "  Target dir:   $TARGET_DIR"
echo ""
read -rp "Continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Copying files..."

# Copy .claude/ directory
mkdir -p "$TARGET_DIR/.claude"
cp -r "$SCAFFOLD_DIR/.claude/agents" "$TARGET_DIR/.claude/"
cp -r "$SCAFFOLD_DIR/.claude/commands" "$TARGET_DIR/.claude/"
cp -r "$SCAFFOLD_DIR/.claude/skills" "$TARGET_DIR/.claude/"
if [[ ! -f "$TARGET_DIR/.claude/memory/MEMORY.md" ]]; then
  mkdir -p "$TARGET_DIR/.claude/memory"
  cp "$SCAFFOLD_DIR/.claude/memory/MEMORY.md" "$TARGET_DIR/.claude/memory/MEMORY.md"
fi

# Copy issue templates
mkdir -p "$TARGET_DIR/.github/ISSUE_TEMPLATE"
cp "$SCAFFOLD_DIR/.github/ISSUE_TEMPLATE/"*.yml "$TARGET_DIR/.github/ISSUE_TEMPLATE/"

# Copy labels.yml
cp "$SCAFFOLD_DIR/.github/labels.yml" "$TARGET_DIR/.github/labels.yml"

# Copy CLAUDE.md template (only if CLAUDE.md doesn't already exist)
if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  echo "  CLAUDE.md already exists - skipping (check CLAUDE.md.template for new sections)"
  cp "$SCAFFOLD_DIR/CLAUDE.md.template" "$TARGET_DIR/CLAUDE.md.template"
else
  cp "$SCAFFOLD_DIR/CLAUDE.md.template" "$TARGET_DIR/CLAUDE.md"
fi

echo "Replacing placeholders..."

# Replace {{GITHUB_REPO}} and {{PROJECT_NAME}} in all copied .md files
find "$TARGET_DIR/.claude" -name "*.md" -type f | while read -r file; do
  sed -i "s|{{GITHUB_REPO}}|$GITHUB_REPO|g" "$file"
  sed -i "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" "$file"
done

if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  sed -i "s|{{GITHUB_REPO}}|$GITHUB_REPO|g" "$TARGET_DIR/CLAUDE.md"
  sed -i "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" "$TARGET_DIR/CLAUDE.md"
fi

echo "Creating GitHub labels..."
if gh api "repos/$GITHUB_REPO" &>/dev/null; then
  # Parse labels.yml and create each label
  python3 - <<PYEOF
import subprocess, re, sys

with open("$TARGET_DIR/.github/labels.yml") as f:
    content = f.read()

blocks = re.split(r'\n- name:', '\n' + content)
for block in blocks:
    if not block.strip():
        continue
    name_m = re.search(r'^([^\n]+)', block.strip())
    color_m = re.search(r'color:\s*"([^"]+)"', block)
    desc_m = re.search(r'description:\s*(.+)', block)
    if not (name_m and color_m):
        continue
    name = name_m.group(1).strip().strip('"')
    color = color_m.group(1)
    desc = desc_m.group(1).strip() if desc_m else ""
    result = subprocess.run(
        ["gh", "label", "create", name, "--color", color, "--description", desc,
         "--repo", "$GITHUB_REPO", "--force"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"  Created label: {name}")
    else:
        print(f"  Skipped label: {name} ({result.stderr.strip()})")
PYEOF
else
  echo "  Skipping labels - repo $GITHUB_REPO not found on GitHub (run gh repo create first)"
fi

echo ""
echo "Global install (optional)"
echo "-------------------------"
echo "Skills and agents installed in ~/.claude/ are available in ALL projects without"
echo "per-project copying. The upgrade-audit skill is the most useful one to install globally."
echo ""
read -rp "Install upgrade-audit skill globally in ~/.claude/skills/? (Y/n): " GLOBAL_SKILL
if [[ "$GLOBAL_SKILL" != "n" && "$GLOBAL_SKILL" != "N" ]]; then
  mkdir -p "$HOME/.claude/skills"
  cp -r "$SCAFFOLD_DIR/.claude/skills/upgrade-audit" "$HOME/.claude/skills/"
  echo "  Installed: upgrade-audit -> ~/.claude/skills/upgrade-audit/"
  echo "  It is now available in every Claude Code project."
fi

echo ""
read -rp "Install gate-ticket command globally in ~/.claude/commands/? (y/N): " GLOBAL_CMD
if [[ "$GLOBAL_CMD" == "y" || "$GLOBAL_CMD" == "Y" ]]; then
  mkdir -p "$HOME/.claude/commands"
  cp "$SCAFFOLD_DIR/.claude/commands/gate-ticket.md" "$HOME/.claude/commands/gate-ticket.md"
  echo "  Installed: /gate-ticket -> ~/.claude/commands/gate-ticket.md"
fi

echo ""
echo "For a full interactive global install (all agents + commands), run:"
echo "  $SCAFFOLD_DIR/install-global.sh"

echo ""
echo "Done!"
echo ""
echo "Next steps:"
echo "  1. Fill in CLAUDE.md - replace all {{TODO: ...}} sections"
echo "  2. Commit: git add .claude/ .github/ CLAUDE.md && git commit -m 'chore: add claude-scaffold governance'"
echo "  3. File a test issue using the feature template on GitHub"
echo "  4. Run /gate-ticket <issue-number> in Claude Code to verify the gate works"
echo "  5. Keep claude-scaffold updated: git -C $SCAFFOLD_DIR pull"
echo ""
echo "Run /upgrade-audit at any time to see what's new in claude-scaffold."
