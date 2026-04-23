# Upgrading an Existing Project

claude-scaffold is a living reference. As new agents, patterns, and governance improvements
are added, you can pull them into existing projects using the `upgrade-audit` skill.

## How it works

The `upgrade-audit` skill compares the current project's `.claude/` directory and GitHub
issue templates against `~/[redacted]/claude-scaffold/` and produces a
prioritized gap report.

## Running upgrade-audit

In any Claude Code session in your project, say:

```
Run upgrade-audit
```

Or invoke the skill by name. Claude will:
1. List recent changes to claude-scaffold (via git log)
2. Compare your project's agents, commands, skills, and templates
3. Produce a report with exact copy commands for each gap

## Example report output

```
## upgrade-audit report
Reference: ~/[redacted]/claude-scaffold (commit: abc1234)
Date: 2026-04-23

### P0 - Critical governance gaps
- ticket-gate agent missing -> copy from claude-scaffold and customize {{GITHUB_REPO}}

### P1 - Missing core agents
- security-auditor: not present
  cp ~/[redacted]/claude-scaffold/.claude/agents/security-auditor.md .claude/agents/

### P2 - Outdated issue templates
- feature.yml: v3 detected, current is v4
  cp ~/[redacted]/claude-scaffold/.github/ISSUE_TEMPLATE/feature.yml .github/ISSUE_TEMPLATE/

### P3 - Optional enhancements
- tdd-orchestrator: not present
  cp ~/[redacted]/claude-scaffold/.claude/agents/tdd-orchestrator.md .claude/agents/

### Already up to date
- code-reviewer, architect-review: present
- gate-ticket command: present
```

## Applying a gap

The report includes a copy command for each gap. Apply selectively:

```bash
# Copy an agent
cp ~/[redacted]/claude-scaffold/.claude/agents/security-auditor.md .claude/agents/

# Copy a skill directory
cp -r ~/[redacted]/claude-scaffold/.claude/skills/owasp-api-security .claude/skills/

# Copy issue templates
cp ~/[redacted]/claude-scaffold/.github/ISSUE_TEMPLATE/feature.yml .github/ISSUE_TEMPLATE/
```

After copying `ticket-gate.md`, replace the placeholder with your repo:
```bash
sed -i 's/{{GITHUB_REPO}}/owner\/repo/g' .claude/agents/ticket-gate.md
```

## Keeping claude-scaffold up to date

```bash
git -C ~/[redacted]/claude-scaffold pull
```

Run upgrade-audit after pulling to see what's new.

## Issue template auto-upgrade

You don't need to manually upgrade issue templates for existing tickets. When you run
`/gate-ticket` on an old ticket (filed against template v3, current is v4), the gate's
Step 0c auto-synthesis pipeline will:
1. Detect the version mismatch
2. Synthesise the missing GWT scenarios and test specs from the existing issue body
3. Update the issue body via `gh issue edit`
4. Post a void+synthesis comment
5. Re-score all agents against the enriched body

No human intervention needed for per-ticket upgrades.
