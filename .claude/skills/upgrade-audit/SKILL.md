---
name: upgrade-audit
version: "2026-04-23"
description: Compare the current project's Claude Code governance against the claude-scaffold reference kit and produce a prioritized gap report. Use when you want to know what agents, commands, skills, or issue templates the current project is missing or has outdated compared to claude-scaffold.
---

# upgrade-audit

Compares the current project's Claude Code governance structure against the
`~/dev-github-personal/claude-scaffold/` reference kit and produces a prioritized gap report.

## When to Use This Skill

- "What governance pieces is this project missing?"
- "Has claude-scaffold been updated since we last synced?"
- "What should I bring in from claude-scaffold?"
- "Run an upgrade audit"
- Any time you want to improve a project's Claude Code structure

## How to Run

When this skill is invoked, follow these steps exactly:

### Step 0: Self-update check

Run this before any other step. Complete (or gracefully skip) before proceeding.

```bash
# 1. Read installed version
grep "^version:" ~/.claude/skills/upgrade-audit/SKILL.md | head -1
```

```bash
# 2. Fetch GitHub version (requires gh auth)
gh api repos/agigante80/claude-scaffold/contents/.claude/skills/upgrade-audit/SKILL.md \
  --jq '.content' | base64 -d | grep "^version:" | head -1
```

Compare the two version strings (ISO date - lexicographic comparison is correct):

- **GitHub version > installed version:** auto-update, then print:
  `upgrade-audit updated: <old> -> <new>. Continuing with new version.`
- **Equal or check fails (no gh auth, network error):** skip silently, proceed with installed version.

Auto-update command (run only when newer found):
```bash
gh api repos/agigante80/claude-scaffold/contents/.claude/skills/upgrade-audit/SKILL.md \
  --jq '.content' | base64 -d > ~/.claude/skills/upgrade-audit/SKILL.md
```

### Step 1: Verify claude-scaffold is available

```bash
ls ~/dev-github-personal/claude-scaffold/.claude/agents/ 2>/dev/null | head -5
```

If the directory does not exist, stop and print:
```
claude-scaffold not found at ~/dev-github-personal/claude-scaffold/
Clone it first: git clone https://github.com/agigante80/claude-scaffold ~/dev-github-personal/claude-scaffold
```

### Step 2: Show recent claude-scaffold changes

```bash
git -C ~/dev-github-personal/claude-scaffold log --oneline -5
```

Print the output so the user knows what version of the reference they're comparing against.

### Step 3: Inventory claude-scaffold

Collect the reference inventory:

```bash
ls ~/dev-github-personal/claude-scaffold/.claude/agents/
ls ~/dev-github-personal/claude-scaffold/.claude/commands/
ls ~/dev-github-personal/claude-scaffold/.claude/skills/
ls ~/dev-github-personal/claude-scaffold/.github/ISSUE_TEMPLATE/
```

Also read the current template version:
```bash
grep "template-version:" ~/dev-github-personal/claude-scaffold/.github/ISSUE_TEMPLATE/feature.yml | head -1
```

### Step 4: Inventory the current project

```bash
ls .claude/agents/ 2>/dev/null
ls .claude/commands/ 2>/dev/null
ls .claude/skills/ 2>/dev/null
ls .github/ISSUE_TEMPLATE/ 2>/dev/null
```

Also check template versions for each issue template file:
```bash
grep "template-version:" .github/ISSUE_TEMPLATE/*.yml 2>/dev/null
```

Check if CLAUDE.md exists and has key sections:
```bash
grep -l "Hard constraints\|File length\|Branch strategy\|Naming conventions" CLAUDE.md 2>/dev/null
```

### Step 5: Check ticket-gate quality

```bash
grep -l "0c-v\|auto-synthesis" .claude/agents/ticket-gate.md 2>/dev/null
```

If `ticket-gate.md` exists but does NOT contain `0c-v`, flag it as outdated (missing
auto-synthesis pipeline).

### Step 6: Build the gap report

Produce output in this exact format:

```
## upgrade-audit report
Reference: ~/dev-github-personal/claude-scaffold (commit: <hash>)
Date: <today>
Skill version: <installed version>

### P0 - Critical governance gaps
[List only if present. P0 = ticket-gate missing or has no auto-synthesis, issue templates have no version marker]

### P1 - Missing core agents
[Agents in claude-scaffold/.claude/agents/ that are not in current .claude/agents/]

### P2 - Outdated issue templates
[Templates where current project version < claude-scaffold version]

### P3 - Optional enhancements
[Commands and skills in claude-scaffold that are not in the current project]

### Already up to date
[Agents, commands, skills that match claude-scaffold]

---
### How to apply a gap

To copy an agent:
  cp ~/dev-github-personal/claude-scaffold/.claude/agents/<name>.md .claude/agents/<name>.md

To copy a skill directory:
  cp -r ~/dev-github-personal/claude-scaffold/.claude/skills/<name> .claude/skills/<name>

To copy a command:
  cp ~/dev-github-personal/claude-scaffold/.claude/commands/<name>.md .claude/commands/<name>.md

To copy issue templates:
  cp ~/dev-github-personal/claude-scaffold/.github/ISSUE_TEMPLATE/*.yml .github/ISSUE_TEMPLATE/

After copying ticket-gate.md, replace {{GITHUB_REPO}} with your repo (owner/name):
  sed -i 's/{{GITHUB_REPO}}/owner\/repo/g' .claude/agents/ticket-gate.md
```

## Rules

- **Report only - never auto-apply gaps.** Always list what should change, never change project files.
- **Skip upgrade-audit itself** when comparing skills (globally installed, not a project gap).
- **Ignore project-specific agents** not in claude-scaffold (safety-logic-reviewer, prisma-schema-guardian, etc.) - intentionally project-specific.
- **P0 is a hard gate.** If ticket-gate is missing or outdated, say so prominently first.
- **For each gap, provide the exact copy command** so the user can act in one step.
- **Step 0 is the only exception to "report only"** - it may overwrite `~/.claude/skills/upgrade-audit/SKILL.md`.
