# Getting Started

Add forge-kit governance to a new or existing project in 5 minutes.

## Prerequisites

- Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
- GitHub CLI installed (`gh`) and authenticated (`gh auth login`)
- Git repository with a GitHub remote

## Option A: Plugin marketplace (recommended for Claude Code users)

The fastest path — no cloning required.

```shell
/plugin marketplace add agigante80/forge-kit
/plugin install forge-kit-governance@forge-kit
```

Install additional groups as needed:

```shell
/plugin install forge-kit-security@forge-kit
/plugin install forge-kit-review@forge-kit
/plugin install forge-kit-testing@forge-kit
/plugin install forge-kit-devops@forge-kit
/plugin install forge-kit-backend@forge-kit
```

Run `/reload-plugins` to activate. Enable auto-update in `/plugin` → **Marketplaces** to stay current automatically.

## Option B: forge-adapt (existing project, no plugin marketplace)

Clone forge-kit once, then run `forge-adapt` from inside your target project:

```bash
git clone https://github.com/agigante80/forge-kit ~/forge-kit
```

Open Claude Code in your project and say:

```
run forge-adapt
```

forge-adapt will:
1. Analyse your codebase — stack, domain, security surface, existing governance
2. Recommend the most relevant forge-kit components with reasoning
3. Wait for your selection before writing anything
4. Write project-customised versions directly into `.claude/` — not generic copies

## After setup

### 1. Fill in CLAUDE.md

Open `CLAUDE.md` and replace all `{{TODO: ...}}` sections with your project-specific content:
- What the project does and who uses it
- Tech stack (languages, frameworks, databases)
- Setup and test commands
- Architecture notes and service boundaries
- Branch strategy

### 2. Customize ticket-gate (optional)

If your project has domain-specific agents (e.g., a schema reviewer, mobile reviewer), add them to the dynamic agent table in `.claude/agents/ticket-gate.md`. See `docs/guides/agent-selection.md` for the pattern.

### 3. File your first issue and run the gate

```bash
# File a test issue using the feature template on GitHub
# Then run the gate:
# /gate-ticket <issue-number>
```

The gate auto-synthesises missing GWT scenarios and test specs if the template version
is outdated — no manual upgrades needed.

### 4. Run forge-adapt periodically

Keep your project in sync with the forge-kit reference:

```bash
# Pull latest forge-kit
git -C ~/forge-kit pull

# Run forge-adapt in your project — it detects what has changed and offers to update
```

See `docs/guides/upgrade-existing.md` for details on the forge-adapt workflow.
