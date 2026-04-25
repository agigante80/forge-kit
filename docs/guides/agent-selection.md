# Agent Selection Guide

Which agents does your project need? Use this guide to decide.

## Always include (non-negotiable)

| Agent | Why |
|---|---|
| `ticket-gate` | The governance gate. Mandatory before any implementation. |
| `code-reviewer` | Code quality, security, performance - needed everywhere. |
| `security-auditor` | OWASP, auth, compliance - every project has security surface. |

## By project type

| Project type | Add these agents |
|---|---|
| REST API backend | `backend-architect`, `api-security-tester` |
| Full-stack web | `architect-review`, `performance-engineer` |
| Backend-heavy / complex | `tdd-orchestrator`, `test-automator` |
| Security-critical system | `backend-security-coder` |
| Test-driven team | `tdd-orchestrator`, `test-automator` |

## Domain-specific agents (create your own)

If your project has a specific domain that needs specialist review, create a new agent:

- **Database-heavy**: create a schema-guardian agent that checks migration safety, indexes, soft deletes
- **Mobile app**: create a mobile-reviewer that checks React Native/Flutter patterns
- **Payment processing**: create a payment-security agent that verifies PCI-DSS compliance
- **Safety-critical system**: create a safety-logic-reviewer that validates state machines and escalation

See `.claude/agents/README.md` for how to create an agent and wire it into ticket-gate.

## Adding a project-specific agent to ticket-gate

After creating the agent file, add it to the dynamic agent table in `ticket-gate.md`:

```markdown
| My Domain Agent | Label `domain-label` OR body matches `keyword` | Check labels or regex on body |
```

And add its definition in the "Dynamic Agent Definitions" section:

```markdown
#### My Domain Agent (triggered by `domain-label` label)
Use agent type: `my-agent`

Score criteria (1-10):
- [specific criteria for your domain]
```

## Taxonomy: when to make an agent vs a skill

Use an **agent** when the specialist task:
- Needs to score something (1-10)
- Produces a structured report
- Benefits from isolated context (doesn't need to know the main conversation)
- Runs for more than a few seconds

Use a **skill** when:
- You want to inject domain knowledge into Claude's current conversation
- The task is a checklist or pattern reference
- It doesn't produce an independent artifact
- Examples: forge-adapt, owasp-api-security checklist, API design principles
