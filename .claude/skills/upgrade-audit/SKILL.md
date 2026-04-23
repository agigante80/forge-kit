---
name: upgrade-audit
version: "2026-04-24"
description: Compare the current project's Claude Code governance against the ai-projectforge reference kit and produce a prioritized gap report. Optionally focus on a specific area (agents, commands, skills, templates). Detects project items that could be contributed back to ai-projectforge. Use when you want to know what agents, commands, skills, or issue templates the current project is missing or has outdated compared to ai-projectforge.
---

# upgrade-audit

Compares the current project's Claude Code governance structure against the
`~/dev-github-personal/ai-projectforge/` reference kit and produces a prioritized gap report.
Optionally run on a specific area only, and detect project items worth contributing back.

## When to Use This Skill

- "What governance pieces is this project missing?"
- "Has ai-projectforge been updated since we last synced?"
- "What should I bring in from ai-projectforge?"
- "Run an upgrade audit"
- "upgrade-audit agents" / "upgrade-audit templates" (focus on one area)
- Any time you want to improve a project's Claude Code structure

## How to Run

When this skill is invoked, follow these steps exactly:

### Focus detection (runs before everything else)

Read the invocation text for a focus keyword:

- `agents` or `agent` -> focus = **agents**
- `commands` or `command` -> focus = **commands**
- `skills` or `skill` -> focus = **skills**
- `templates`, `template`, or `issue templates` -> focus = **templates**
- no keyword -> focus = **all** (default)

If a focus is detected, print at the top of the report:
```
Focus: <area> only
```

Apply this focus in Steps 3, 4, and 6: only collect and report on the selected area.
The P0 ticket-gate quality check (Step 5) always runs regardless of focus.

---

### Step 0: Self-update check

Run this before any other step. Complete (or gracefully skip) before proceeding.

```bash
# 1. Read installed version
grep "^version:" ~/.claude/skills/upgrade-audit/SKILL.md | head -1
```

```bash
# 2. Fetch GitHub version (requires gh auth)
gh api repos/agigante80/ai-projectforge/contents/.claude/skills/upgrade-audit/SKILL.md \
  --jq '.content' | base64 -d | grep "^version:" | head -1
```

Compare the two version strings (ISO date - lexicographic comparison is correct):

- **GitHub version > installed version:** auto-update, then print:
  `upgrade-audit updated: <old> -> <new>. Continuing with new version.`
- **Equal or check fails (no gh auth, network error):** skip silently, proceed with installed version.

Auto-update command (run only when newer found):
```bash
gh api repos/agigante80/ai-projectforge/contents/.claude/skills/upgrade-audit/SKILL.md \
  --jq '.content' | base64 -d > ~/.claude/skills/upgrade-audit/SKILL.md
```

### Step 1: Verify ai-projectforge is available

```bash
ls ~/dev-github-personal/ai-projectforge/.claude/agents/ 2>/dev/null | head -5
```

If the directory does not exist, stop and print:
```
ai-projectforge not found at ~/dev-github-personal/ai-projectforge/
Clone it first: git clone https://github.com/agigante80/ai-projectforge ~/dev-github-personal/ai-projectforge
```

### Step 2: Show recent ai-projectforge changes

```bash
git -C ~/dev-github-personal/ai-projectforge log --oneline -5
```

Print the output so the user knows what version of the reference they're comparing against.

### Step 3: Inventory ai-projectforge

Collect only what the current focus requires:

```bash
# Always collect (for ticket-gate check):
ls ~/dev-github-personal/ai-projectforge/.claude/agents/

# Collect if focus = all or agents:
ls ~/dev-github-personal/ai-projectforge/.claude/agents/

# Collect if focus = all or commands:
ls ~/dev-github-personal/ai-projectforge/.claude/commands/

# Collect if focus = all or skills:
ls ~/dev-github-personal/ai-projectforge/.claude/skills/

# Collect if focus = all or templates:
ls ~/dev-github-personal/ai-projectforge/.github/ISSUE_TEMPLATE/
grep "template-version:" ~/dev-github-personal/ai-projectforge/.github/ISSUE_TEMPLATE/feature.yml | head -1
```

### Step 4: Inventory the current project

Collect only what the current focus requires:

```bash
# Collect if focus = all or agents:
ls .claude/agents/ 2>/dev/null

# Collect if focus = all or commands:
ls .claude/commands/ 2>/dev/null

# Collect if focus = all or skills:
ls .claude/skills/ 2>/dev/null

# Collect if focus = all or templates:
ls .github/ISSUE_TEMPLATE/ 2>/dev/null
grep "template-version:" .github/ISSUE_TEMPLATE/*.yml 2>/dev/null
```

Check if CLAUDE.md exists and has key sections (focus = all only):
```bash
grep -l "Hard constraints\|File length\|Branch strategy\|Naming conventions" CLAUDE.md 2>/dev/null
```

### Step 5: Check ticket-gate quality (always runs)

```bash
grep -l "0c-v\|auto-synthesis" .claude/agents/ticket-gate.md 2>/dev/null
```

If `ticket-gate.md` exists but does NOT contain `0c-v`, flag it as outdated (missing
auto-synthesis pipeline).

### Step 6: Build the gap report

Produce only the sections relevant to the current focus. Number every gap item
sequentially across all priorities — this numbering is used in Step 6.5 for selection.

```
## upgrade-audit report
Reference: ~/dev-github-personal/ai-projectforge (commit: <hash>)
Date: <today>
Skill version: <installed version>
[Focus: <area> only  <- include this line only when a focus keyword was detected]

### P0 - Critical governance gaps
[Always included. P0 = ticket-gate missing or has no auto-synthesis, issue templates have no version marker]
1. [P0] <description>
   cp ~/dev-github-personal/ai-projectforge/.claude/agents/ticket-gate.md .claude/agents/ticket-gate.md

### P1 - Missing core agents
[Include when focus = all or agents]
2. [P1] <agent-name> missing
   cp ~/dev-github-personal/ai-projectforge/.claude/agents/<name>.md .claude/agents/<name>.md

### P2 - Outdated issue templates
[Include when focus = all or templates]
3. [P2] <template-name> is version vN (current: vM)
   cp ~/dev-github-personal/ai-projectforge/.github/ISSUE_TEMPLATE/<name>.yml .github/ISSUE_TEMPLATE/<name>.yml

### P3 - Optional enhancements
[Include when focus = all or commands or skills]
4. [P3] <command-or-skill-name> not present
   cp ~/dev-github-personal/ai-projectforge/.claude/commands/<name>.md .claude/commands/<name>.md
   (or: cp -r ~/dev-github-personal/ai-projectforge/.claude/skills/<name> .claude/skills/<name>)

### Already up to date
[Items in the focused area that match ai-projectforge — no number, no action needed]
```

After printing the report, end with:

```
Which gaps would you like to apply?
Reply with numbers (e.g. "1 3 5"), "all", or "none" to skip.
```

Then wait for the user's reply before continuing.

---

### Step 6.5: Apply selected gaps

Parse the user's reply and apply only the selected items.

**If the reply is "none", "0", or empty:** print `Skipping gap application.` and proceed to Step 7.

**Otherwise:**

**6.5a. Detect the current repo** (used for placeholder adaptation):

```bash
git remote get-url origin 2>/dev/null \
  | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|'
```

Store the result (e.g. `myorg/my-project`) as `CURRENT_REPO`.

**6.5b. For each selected gap number**, run its `cp` command exactly as printed in the report.

**6.5c. Adapt copied files** — after copying, check for `{{GITHUB_REPO}}` in the file:

```bash
grep -l '{{GITHUB_REPO}}' <destination-path> 2>/dev/null
```

If found, replace the placeholder with the detected repo:

```bash
sed -i 's|{{GITHUB_REPO}}|'"$CURRENT_REPO"'|g' <destination-path>
```

This applies primarily to agent files (`ticket-gate.md`, `dep-auditor.md`, `health-check.md`).
Skills, commands, and issue templates do not use this placeholder — skip adaptation for them.

**6.5d. Confirm what was done:**

```
Applied gaps: <list of numbers and names>
Adapted placeholders in: <list of files where {{GITHUB_REPO}} was replaced, or "none">
```

### Step 7: Potential contributions to ai-projectforge

Run this step after Step 6.5 (gap application). Skip if focus is set (only run in full-audit mode).

**7a. Collect project-only items**

Compare project `.claude/` contents against the scaffold inventory from Step 3:

```bash
# Agents in project but not in scaffold:
comm -23 <(ls .claude/agents/ 2>/dev/null | sort) \
         <(ls ~/dev-github-personal/ai-projectforge/.claude/agents/ | sort)

# Commands in project but not in scaffold:
comm -23 <(ls .claude/commands/ 2>/dev/null | sort) \
         <(ls ~/dev-github-personal/ai-projectforge/.claude/commands/ | sort)

# Skills in project but not in scaffold (upgrade-audit excluded - it's global):
comm -23 <(ls .claude/skills/ 2>/dev/null | grep -v "^upgrade-audit$" | sort) \
         <(ls ~/dev-github-personal/ai-projectforge/.claude/skills/ | grep -v "^upgrade-audit$" | sort)
```

**7b. Apply generalisability filter**

Exclude items that are obviously project-specific. Read the top of each candidate file
and skip if it:
- Has a filename containing a product/brand name found in CLAUDE.md (check "What this is" section)
- Has a filename containing `prisma-schema-guardian`, `safety-logic-reviewer`,
  `mobile-a11y-reviewer`, `mobile-security-reviewer`, `mobile-performance-reviewer`,
  `mobile-build-engineer`, `mobile-developer`, `e2e-test-engineer`, `help-center-reviewer`,
  `seo-reviewer`, `wireframe-gate`, `roadmap-gate`, `terminology-checker`, or
  `github-project-manager` (domain-specific patterns)
- Contains hardcoded repo names, internal endpoints, or product-specific terminology
  in the first 20 lines

**7c. Present candidates to user**

For each remaining candidate, read its description line and write:

```
### Potential contributions to ai-projectforge

The following items in this project are not in ai-projectforge and may be generalisable:

  1. <name> (<type: agent/command/skill>) - <one-sentence description from file>
  2. ...

Reply with numbers to open contribution issues (e.g. "1, 2"), or "none" to skip.
```

If no candidates remain after filtering, print:
```
### Potential contributions to ai-projectforge
No generalisable candidates found (all project-only items appear domain-specific).
```
and stop.

**7d. Wait for user response**

If the user replies "none", "0", or empty: print `Skipping contributions.` and stop.

**7e. Create GitHub issues for accepted items**

For each accepted number, read the full file content and run:

```bash
gh issue create \
  --repo agigante80/ai-projectforge \
  --title "Contribution: <name> (<type>)" \
  --label "contribution" \
  --body "$(cat <<'EOF'
### Category
<type: agent / command / skill / issue template>

### What it does
<description extracted from the file's description/purpose section>

### Why it would be useful across projects
<brief rationale - infer from the file content>

### Source project
<current repo from git remote, or "private">

### Content or link
<full file content, wrapped in a markdown code block>

### Checklist
- [ ] Generalise any hardcoded project references
- [ ] Add to ai-projectforge README table
- [ ] Write or update docs/guides/ if needed
- [ ] Verify no sensitive data in content
EOF
)"
```

Print the issue URL after each creation.

---

## Rules

- **Present gaps as a numbered list and wait for user selection** before applying anything.
- **After copying any agent file, run `{{GITHUB_REPO}}` adaptation** using the detected git remote. Skills, commands, and templates do not need this.
- **Step 7 (contributions) runs after Step 6.5 (gap application) is complete**, not before.
- **Skip upgrade-audit itself** when comparing skills (globally installed, not a project gap).
- **Ignore project-specific agents** not in ai-projectforge (safety-logic-reviewer, prisma-schema-guardian, etc.) - intentionally project-specific.
- **P0 is a hard gate.** If ticket-gate is missing or outdated, say so prominently first.
- **Step 0 is the only exception** — it may overwrite `~/.claude/skills/upgrade-audit/SKILL.md` without user selection.
- **Step 7 only runs in full-audit mode** (no focus keyword). Skip it when focus is set.
- **Never auto-create contribution issues.** Always wait for explicit user confirmation.
