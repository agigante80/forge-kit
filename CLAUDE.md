# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

**forge-kit** is an AI-assisted project governance scaffold — AI-agnostic at the governance layer (issue templates, labels, GWT scenarios), Claude Code-native at the automation layer (agents, skills, slash commands). It is a template repository, not a buildable application. Its purpose is to be bootstrapped into other projects or used as an upgrade reference via the `forge-adapt` skill. There are no build steps, package managers, or CI pipelines.

**Validation approach:** There is no local test runner. To validate a component change, install it into a test project via `forge-adapt` and exercise the workflow there.

## Architecture

The kit is organized into plugin groups under `plugins/<group>/`:

| Plugin group | Contents |
|---|---|
| `forge-kit-adapt` | forge-adapt skill (the entry point — install this first) |
| `forge-kit-governance` | ticket-gate agent, gate-ticket command |
| `forge-kit-review` | code-reviewer, architect-review, backend-architect agents; full-review, pr-enhance commands |
| `forge-kit-security` | security-auditor, backend-security-coder, api-security-tester agents; owasp-api-security skill |
| `forge-kit-testing` | tdd-orchestrator, test-automator, performance-engineer agents |
| `forge-kit-devops` | dep-auditor, health-check agents; ci-health command |
| `forge-kit-backend` | api-design-principles, architecture-patterns, microservices-patterns, cqrs-implementation, saga-orchestration skills |

Users install via the plugin marketplace (`/plugin marketplace add agigante80/forge-kit`) or by cloning the repo and running `forge-adapt` from within the target project.

## Component Types

**Agents** (`plugins/<group>/agents/*.md`) — Isolated specialist subagents that run in a separate context window, invoked via the Claude Code `Agent` tool with `subagent_type`. Required YAML frontmatter:

```yaml
---
name: <agent-name>
description: <when to invoke this agent — include trigger phrases>
model: opus          # or omit for default
tools: ["Agent", "Bash", "Read", "Grep", "Glob"]
color: red           # optional; used in Claude Code UI
---
```

Key agents:
- `ticket-gate` — Orchestrator that runs 5 core scoring agents + dynamic agents selected by issue labels, then posts a scorecard to GitHub. All agents must score 10/10 to pass.
- `full-review` — 5-phase code review orchestrator with a mid-run user checkpoint. Persists progress state to `.full-review/` in the project root; can be resumed after interruption.
- `dep-auditor` — Scans workspace packages for unused deps, unmaintained libraries, and vulnerabilities; caches results in `docs/audit/dep-audit-cache.json` (30-day window); creates GitHub tickets for every finding.
- `health-check` — Verifies the dev environment (runtime, package manager, Docker, TypeScript, env files, GitHub CLI).
- Specialist agents: `security-auditor`, `architect-review`, `backend-architect`, `code-reviewer`, `api-security-tester`, `tdd-orchestrator`, `test-automator`, `performance-engineer`, `backend-security-coder`.

**Commands** (`plugins/<group>/commands/*.md`) — Thin slash-command wrappers that delegate to agents. Frontmatter requires only `name` and `description`. Users invoke these directly:
- `/gate-ticket <N>` — Run the ticket readiness gate on GitHub issue N.
- `/full-review [path] [--security-focus] [--performance-critical] [--strict-mode] [--framework name]` — 5-phase code review.
- `/pr-enhance` — Pull request enhancement (description, scope review, checklist generation).
- `/ci-health` — Check all GitHub Actions workflows, create P0 tickets for failures, auto-fix safe failures.

Note: `dep-auditor` and `health-check` are agent types, not slash commands. Trigger them by mentioning "health check" or "audit dependencies" in conversation.

**Skills** (`plugins/<group>/skills/*/SKILL.md`) — Domain knowledge injected into the main conversation (not isolated). Frontmatter requires only `name` and `description`. Skills can have `assets/` (checklists, templates) and `references/` (supporting docs) subdirectories alongside `SKILL.md` — only `api-design-principles` in `forge-kit-backend` currently uses this pattern. Triggered automatically when relevant or by user invocation. Includes: `forge-adapt`, `api-design-principles`, `owasp-api-security`, `architecture-patterns`, `microservices-patterns`, `cqrs-implementation`, `saga-orchestration`.

**Issue Templates** (`.github/ISSUE_TEMPLATE/*.yml`) — Six templates: `feature.yml`, `bug.yml`, `security.yml`, `infrastructure.yml`, `design.yml`, `contribution.yml`. All carry `<!-- template-version: 4 -->` and include mandatory sections: GWT scenarios, unit test specs, E2E test specs, GDPR considerations, security checklist, and required reviews checkbox. The `ticket-gate` agent auto-synthesizes missing v4 sections from earlier-version tickets. See `docs/guides/template-versioning.md` for the versioning scheme and auto-synthesis logic.

## Plugin Structure

Each plugin group has a `.claude-plugin/plugin.json` with just `name` and `description` (no version field):

```json
{ "name": "forge-kit-<group>", "description": "..." }
```

The root `.claude-plugin/marketplace.json` lists all plugins with their local `source` paths. This is the file the plugin marketplace reads to discover installable plugins.

## Key Conventions

**Agents vs. Skills vs. Commands:**
- Agents → isolated context, structured output, scoring, auditing
- Skills → injected knowledge, patterns, checklists; no isolation
- Commands → user-facing entry points; delegate to agents

**`{{GITHUB_REPO}}` placeholder:** Appears in agents that call the GitHub API (e.g., `ticket-gate`). Must be replaced with `owner/repo` at install time. `forge-adapt` handles this automatically; manual installs need `sed -i 's/{{GITHUB_REPO}}/owner\/repo/g'`.

**Installation paths:**
- Plugin marketplace: `/plugin marketplace add agigante80/forge-kit` then `/plugin install forge-kit-adapt@forge-kit` — forge-adapt installs everything else
- Manual: clone `~/forge-kit`, then run `forge-adapt` from the target project — it reads the codebase, recommends components, and writes adapted versions into `.claude/`
- `.claude/` in a project repo = project-scoped; `~/.claude/` = global across all projects

**forge-adapt phases:** Phase 0 checks if `SKILL.md` SHA differs from GitHub remote (self-update); Phase 1 auto-clones `~/forge-kit` if missing; Phase 2 analyses the target project (stack, domain, existing agents); Phase 3 recommends components with reasoning and waits for approval; Phase 4 writes project-customised versions and surfaces contribution candidates. Also responds to "upgrade-audit" for backward compatibility.

**Label → agent routing:** `docs/guides/labels.md` documents the label taxonomy. Labels drive dynamic agent selection inside `ticket-gate`: the `security` label and `critical` label trigger ALL agents. The `api` area label triggers the API Design agent. To add routing for a new label, add a row to the dynamic agent table in `ticket-gate.md` and a corresponding agent definition section.

**Extending ticket-gate's dynamic routing:** The dynamic agent table inside `ticket-gate.md` maps issue labels and body keywords to specialist agents. To add a new project-specific agent to the gate, add a row to that table and a corresponding "Dynamic Agent Definitions" section.

**ci-health command** (`/ci-health`) discovers all `.github/workflows/*.yml` files, checks the latest run for each, creates P0 tickets for failures, gates each ticket, and auto-implements safe fixes (lint, type, unit, build failures). It does NOT auto-fix E2E or security scan failures.

**Template versioning:** The `template-version: N` HTML comment in issue templates enables the `ticket-gate` agent to detect outdated templates and auto-synthesize missing sections without requiring manual upgrades.

**`.full-review/` directory** is a runtime artifact created by `/full-review`. It persists state across interruptions so a review can be resumed. It is not part of the scaffold — add it to `.gitignore` in projects that run `/full-review`.

## Workflow

After every set of file changes, always commit and push to GitHub:

```bash
git add <changed files>
git commit -m "<concise message>"
git push
```

Do this at the end of every task without waiting to be asked.
