# Claude Code Resources

## Official Documentation

- **Claude Code docs:** https://docs.anthropic.com/en/docs/claude-code
  - Agent frontmatter format (name, description, model, tools, color)
  - settings.json structure (permissions, hooks, allowedTools)
  - Slash commands and skills format
  - Built-in subagent_type values (general-purpose, Explore, Plan, and others)
  - Memory system and MEMORY.md format
  - Hooks: how to trigger shell commands on events (PreToolUse, PostToolUse, etc.)

- **Anthropic API docs:** https://docs.anthropic.com/en/api/getting-started

- **Claude Code GitHub:** https://github.com/anthropics/claude-code
  - Issues and discussions for bugs and feature requests
  - Changelog for new Claude Code features

## Finding Community Agents

There is no central agent marketplace yet. The best sources:

### GitHub search
```
language:Markdown path:.claude/agents
```
```
topic:claude-code
```
```
site:github.com ".claude/agents" filename:*.md
```

### Explore repos with Claude Code setups
Many open-source projects using Claude Code have `.claude/agents/` directories.
Look for projects with `CLAUDE.md` files as an indicator.

## Importing an Agent

```bash
# Preview an agent from another repo
gh api repos/OWNER/REPO/contents/.claude/agents/AGENT.md \
  --jq '.content' | base64 -d

# Import it locally
gh api repos/OWNER/REPO/contents/.claude/agents/AGENT.md \
  --jq '.content' | base64 -d > .claude/agents/AGENT.md

# Then review and edit:
# - Update description: to be project-agnostic or project-specific
# - Remove repo-specific references (paths, org names, specific stack names)
# - Adjust tools list to what the agent actually needs
# - Verify model choice (opus for complex reasoning, sonnet for general, haiku for fast)
```

## Agents vs Skills vs Commands: When to Use Each

### Agent (`.claude/agents/*.md`)
- Long-running specialist task with its own isolated context
- Has a specific role, model, and tools list
- Scores, audits, or produces structured artifacts
- Examples: ticket-gate, code-reviewer, security-auditor

### Skill (`.claude/skills/*/SKILL.md`)
- Domain knowledge injected into the main conversation
- No isolated context - adds to Claude's current session
- Used for patterns, checklists, or guidelines Claude applies inline
- Examples: owasp-api-security, api-design-principles, forge-adapt

### Command (`.claude/commands/*.md`)
- User-facing slash command the user invokes with `/command-name`
- Typically a thin wrapper that delegates to an agent
- Describes a multi-step workflow or agent invocation
- Examples: gate-ticket, full-review, pr-enhance

## Agent Model Selection

| Model | Best for | Cost |
|---|---|---|
| `opus` | Complex reasoning, multi-step scoring, security analysis | Highest |
| `sonnet` | General-purpose tasks, code review, test generation | Medium |
| `haiku` | Fast lookups, simple transforms, classification | Lowest |
| `inherit` | Uses parent conversation's model | Varies |

## Common Agent Frontmatter Fields

```yaml
---
name: my-agent
description: |
  One-sentence description used in the Agent tool's agent list.
  Use PROACTIVELY when X. Include example invocations.
model: opus          # or sonnet, haiku, inherit
color: red           # optional: accent color in Claude Code UI
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "Agent"]
---
```

Available tools: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch, Agent,
TaskCreate, TaskUpdate, AskUserQuestion, EnterPlanMode, ExitPlanMode, and others.
See Claude Code docs for the full tool list.
