# ai-projectforge

AI-assisted project governance scaffold — AI-agnostic patterns, Claude Code automation.

The **governance layer** (issue templates, GWT scenarios, OWASP checklists, labels) works for any team regardless of which AI tool they use. The **automation layer** (agents, skills, slash commands) is Claude Code-native and optional.

The primary tool is the **`upgrade-audit` skill** — run it in any existing project to get a prioritized gap report with exact copy commands for everything your project is missing.

## What's included

### Governance layer — works without Claude Code

| Component | What it does |
|---|---|
| 6 issue templates | feature, bug, security, infrastructure, design, contribution — v4 with GWT scenarios, unit test specs, E2E test specs, GDPR and security checklists |
| GitHub labels | Standard label taxonomy for issue routing and prioritization |
| `CLAUDE.md.template` | Fill-in project instructions template (Claude Code-specific, but the conventions inside are universal) |
| `bootstrap.sh` | Copies templates, fills placeholders, creates GitHub labels — also installs the Claude automation layer if you want it |

### Automation layer — Claude Code-native

| Component | What it does |
|---|---|
| `upgrade-audit` skill | **Start here.** Compares your project against this reference and produces a prioritized gap report with exact copy commands |
| `ticket-gate` agent | Scores every GitHub issue before implementation (5 core agents + dynamic routing). Auto-synthesises missing GWT scenarios and test specs from old issues |
| 9 specialist agents | code-reviewer, security-auditor, architect-review, backend-architect, backend-security-coder, api-security-tester, tdd-orchestrator, test-automator, performance-engineer |
| `gate-ticket` command | `/gate-ticket <N>` slash command |
| `full-review` command | Multi-phase code review orchestrator |
| 7 skills | upgrade-audit, api-design-principles, owasp-api-security, architecture-patterns, microservices-patterns, cqrs-implementation, saga-orchestration |

## Install and run upgrade-audit

### Step 1 — clone this repo

```bash
git clone https://github.com/agigante80/ai-projectforge ~/ai-projectforge
```

### Step 2 — install the skill globally

```bash
~/ai-projectforge/install-global.sh
```

When prompted, say **y** to `upgrade-audit`. Skip the agents and commands for now — you can install them selectively later.

This copies `.claude/skills/upgrade-audit/` into `~/.claude/skills/` so the skill is available in every project without any per-project setup.

### Step 3 — run it in your project

Open Claude Code in your project and say:

```
Run upgrade-audit
```

You'll get a prioritized report like:

```
## upgrade-audit report
Reference: ai-projectforge (commit: abc1234)

### P0 - Critical governance gaps
- ticket-gate agent missing -> copy from ai-projectforge and customize

### P1 - Missing core agents
- security-auditor: not present
  cp ~/ai-projectforge/.claude/agents/security-auditor.md .claude/agents/

### P2 - Outdated issue templates
- feature.yml: v3 detected, current is v4
  cp ~/ai-projectforge/.github/ISSUE_TEMPLATE/feature.yml .github/ISSUE_TEMPLATE/
```

Apply selectively. The report includes a one-line command for each gap.

### Keeping it up to date

```bash
git -C ~/ai-projectforge pull
~/ai-projectforge/install-global.sh  # re-run to update the skill
```

## Bootstrap a new project from scratch

If you're starting a new project rather than upgrading an existing one:

```bash
git clone https://github.com/agigante80/ai-projectforge ~/ai-projectforge
cd your-new-project
~/ai-projectforge/bootstrap.sh
```

Or use GitHub's "Use this template" button on this repo.

## Using without Claude Code

If your team uses Cursor, GitHub Copilot, or no AI CLI at all, you can still adopt the governance layer directly:

```bash
git clone https://github.com/agigante80/ai-projectforge ~/ai-projectforge
cd your-project
~/ai-projectforge/bootstrap.sh
```

When the installer asks about agents and skills, skip them. What you get:

- **Issue templates** in `.github/ISSUE_TEMPLATE/` — structured tickets with GWT scenarios, test specs, GDPR and security checklists
- **GitHub labels** — standard taxonomy for routing and prioritization
- **`CLAUDE.md.template`** — rename to `AI.md` or `AGENTS.md` and fill in your project's conventions for whichever AI tool your team uses

The automation layer (agents, skills, `/gate-ticket`) requires Claude Code and can be added later.

## The ticket-gate (how it works)

`/gate-ticket <N>` runs 5 mandatory specialist agents on a GitHub issue + dynamic agents
by label. All must score 10/10.

**Auto-synthesis:** If an issue was filed on an older template version, the gate
automatically synthesises the missing content (GWT scenarios, unit test specs, E2E test specs)
from the existing issue body - no human intervention. It updates the issue, posts a comment,
and re-scores.

```
/gate-ticket 42

Running ticket readiness gate on #42...

Template auto-upgraded to v4 - content synthesised
- Test scenarios (GWT): 3 conditions, 6 scenarios
- Unit tests: 4 specific cases
- E2E tests: 2 specific cases

Security:  10/10 PASS
Architect: 10/10 PASS
Developer: 10/10 PASS
QA:         10/10 PASS
GDPR:      10/10 PASS

PASS - Ticket #42 is ready for implementation
```

## Docs

- `docs/guides/getting-started.md` - 5-minute setup
- `docs/guides/upgrade-existing.md` - using upgrade-audit
- `docs/guides/agent-selection.md` - which agents does your project need?
- `docs/guides/template-versioning.md` - how v4 GWT versioning + auto-synthesis works
- `docs/guides/labels.md` - label taxonomy and agent routing rules
- `docs/references/claude-code-resources.md` - official docs, community, finding more agents
- `.claude/agents/README.md` - taxonomy (agents vs skills vs commands), adding new agents

## After bootstrapping

1. Fill in `CLAUDE.md` - replace `{{TODO: ...}}` sections with your project details
2. File a test issue using the feature template
3. Run `/gate-ticket <N>` to verify the gate works
4. Consider adding project-specific agents (see `docs/guides/agent-selection.md`)
