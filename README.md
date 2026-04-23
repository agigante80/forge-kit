# claude-scaffold

Claude Code governance kit for any software project.

Provides the structural support that keeps a Claude Code project disciplined over time:
versioned issue templates, a ticket readiness gate with auto-synthesis, specialist agents,
and an upgrade-audit skill that tells you exactly what your project is missing.

## What's included

| Component | What it does |
|---|---|
| `ticket-gate` agent | Scores every GitHub issue before implementation (5 core agents + dynamic routing). Auto-synthesises missing GWT scenarios and test specs from old issues - no manual upgrades. |
| 9 specialist agents | code-reviewer, security-auditor, architect-review, backend-architect, backend-security-coder, api-security-tester, tdd-orchestrator, test-automator, performance-engineer |
| `upgrade-audit` skill | Compares your project against this reference and produces a prioritized gap report with exact copy commands |
| 5 issue templates | feature, bug, security, infrastructure, design - all v4 with GWT scenarios, unit test specs, and E2E test specs |
| GitHub labels | Standard label set for issue routing and agent triggering |
| `gate-ticket` command | `/gate-ticket <N>` slash command |
| `full-review` command | Multi-phase code review orchestrator |
| 5 skills | api-design-principles, owasp-api-security, architecture-patterns, microservices-patterns, cqrs-implementation |
| `CLAUDE.md.template` | Fill-in project instructions template |
| `bootstrap.sh` | Interactive setup: copies files, fills placeholders, creates GitHub labels |

## Two use cases

### 1. Bootstrap a new project

```bash
git clone https://github.com/agigante80/claude-scaffold ~/[redacted]/claude-scaffold
cd your-new-project
~/[redacted]/claude-scaffold/bootstrap.sh
```

Or use GitHub's "Use this template" button on this repo.

### 2. Upgrade an existing project (primary use case)

Run the `upgrade-audit` skill in any Claude Code session:

```
Run upgrade-audit
```

You'll get a prioritized report like:

```
## upgrade-audit report
Reference: claude-scaffold (commit: abc1234)

### P0 - Critical governance gaps
- ticket-gate agent missing -> copy from claude-scaffold and customize

### P1 - Missing core agents
- security-auditor: not present
  cp ~/[redacted]/claude-scaffold/.claude/agents/security-auditor.md .claude/agents/

### P2 - Outdated issue templates
- feature.yml: v3 detected, current is v4
  cp ~/[redacted]/claude-scaffold/.github/ISSUE_TEMPLATE/feature.yml .github/ISSUE_TEMPLATE/
```

Apply selectively. The report includes a one-line command for each gap.

Keep claude-scaffold updated to get new agents and improvements:
```bash
git -C ~/[redacted]/claude-scaffold pull
```

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
