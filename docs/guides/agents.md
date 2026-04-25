# Agents in this project

Claude Code discovers agents in this directory automatically. Each `.md` file is one agent.

## What agents are

Agents are specialist sub-processes. When Claude invokes an agent (via the Agent tool with
`subagent_type`), it runs in isolation with its own context window, tools list, and role.
Use agents for tasks that score, audit, or produce structured artifacts independently.

## Built-in subagent types

Claude Code includes built-in agent types you can invoke without adding a file here:
- `general-purpose` - multi-purpose agent with all tools
- `Explore` - fast read-only codebase explorer
- `Plan` - implementation planner

For the full list, see the Claude Code documentation.

## Agents in forge-kit

| Agent | Purpose | Invoke when |
|---|---|---|
| `ticket-gate` | Scores a GitHub issue (5 core + dynamic agents) | Before implementing any ticket |
| `code-reviewer` | Elite code review: quality, security, performance | Code review, pre-merge |
| `security-auditor` | DevSecOps, OWASP, compliance, threat modeling | Security audit, compliance review |
| `architect-review` | Clean architecture, microservices, DDD review | Architectural decisions |
| `backend-architect` | Scalable API design, service boundaries | New backend services or APIs |
| `backend-security-coder` | Secure coding: input validation, auth, API security | Security code review |
| `api-security-tester` | OWASP API tests: injection, auth bypass, IDOR | Writing security tests |
| `tdd-orchestrator` | Red-green-refactor discipline, TDD governance | TDD implementation |
| `test-automator` | Unit, integration, E2E test suite creation | Test creation during feature dev |
| `performance-engineer` | Response times, memory, query efficiency | Performance review |

## Agents vs Skills vs Commands

| Type | Location | Invoked by | Purpose |
|------|----------|------------|---------|
| **Agent** | `.claude/agents/*.md` | Claude Code Agent tool (`subagent_type`) | Long-running specialist. Has own context, model, tools. Scores, audits, produces artifacts. |
| **Skill** | `.claude/skills/*/SKILL.md` | Automatically when relevant, or skill name mentioned | Domain knowledge injected into the main conversation. No isolated context. |
| **Command** | `.claude/commands/*.md` | User types `/command-name` | User-facing slash command. Typically delegates to an agent. |

**Classification rule:** Does it score independently or need its own context window? -> Agent.
Does it add knowledge to the current conversation without isolation? -> Skill.
Does the user invoke it explicitly and it delegates to an agent? -> Command.

## Adding a project-specific agent

1. Create `.claude/agents/my-agent.md`
2. Write frontmatter:
   ```yaml
   ---
   name: my-agent
   description: One-sentence description. Use PROACTIVELY when X.
   model: opus  # or sonnet, haiku
   tools: ["Read", "Grep", "Glob", "Bash"]
   ---
   ```
3. Write the agent body: its role, what it checks, scoring criteria if applicable
4. To trigger it from ticket-gate: add a row to the dynamic agent table in ticket-gate.md

## Finding community agents

Search GitHub for agents others have published:
```
language:Markdown path:.claude/agents
```

To import an agent from another repo:
```bash
gh api repos/OWNER/REPO/contents/.claude/agents/AGENT.md \
  --jq '.content' | base64 -d > .claude/agents/AGENT.md
# Then edit: update description, remove repo-specific references
```
