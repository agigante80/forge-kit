# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

**ai-projectforge** is an AI-assisted project governance scaffold — AI-agnostic at the governance layer (issue templates, labels, GWT scenarios), Claude Code-native at the automation layer (agents, skills, slash commands). It is a template repository, not a buildable application. Its purpose is to be bootstrapped into other projects or used as an upgrade reference via the `upgrade-audit` skill. There are no build steps, package managers, or CI pipelines.

## Scripts

- `bootstrap.sh` — Interactive one-time setup for a new project. Copies `.claude/`, `.github/ISSUE_TEMPLATE/`, and `CLAUDE.md.template` into a target repo, replaces placeholders (`{{GITHUB_REPO}}`, `{{PROJECT_NAME}}`), and creates GitHub labels via `gh`.
- `install-global.sh` — Interactive installer that copies agents/skills into `~/.claude/` for global use across all projects.

Both scripts are self-contained and require `gh` and `git` to be installed.

## Architecture

The kit is organized into four layers:

**Agents** (`.claude/agents/*.md`) — Isolated specialist subagents, each with YAML frontmatter (`model`, `tools`, `description`). They run in a separate context window and are invoked via the Claude Code `Agent` tool with `subagent_type`. Each scores independently (1–10). Key agents:
- `ticket-gate` — Orchestrator that runs 5 core scoring agents + dynamic agents selected by issue labels, then posts a scorecard to GitHub.
- `full-review` — 5-phase code review orchestrator with a mid-run user checkpoint. Writes progress state to `.full-review/` in the project root.
- `dep-auditor` — Scans workspace packages for unused deps, unmaintained libraries, and vulnerabilities; caches results in `docs/audit/dep-audit-cache.json` (30-day window); creates GitHub tickets for every finding.
- `health-check` — Verifies the dev environment (runtime, package manager, Docker, TypeScript, env files, GitHub CLI).
- Specialist agents: `security-auditor`, `architect-review`, `backend-architect`, `code-reviewer`, `api-security-tester`, `tdd-orchestrator`, `test-automator`, `performance-engineer`, `backend-security-coder`.

**Commands** (`.claude/commands/*.md`) — Thin slash-command wrappers that delegate to agents. Users invoke these directly (e.g., `/gate-ticket 44`, `/full-review`, `/pr-enhance`, `/ci-health`).

**Skills** (`.claude/skills/*/SKILL.md`) — Domain knowledge injected into the main conversation (not isolated). Triggered automatically when relevant or by user invocation. Includes: `upgrade-audit`, `api-design-principles`, `owasp-api-security`, `architecture-patterns`, `microservices-patterns`, `cqrs-implementation`, `saga-orchestration`.

**Issue Templates** (`.github/ISSUE_TEMPLATE/*.yml`) — All templates carry `<!-- template-version: 4 -->` and include mandatory sections: GWT scenarios, unit test specs, E2E test specs, GDPR considerations, security checklist, and required reviews checkbox. The `ticket-gate` agent auto-synthesizes missing v4 sections from earlier-version tickets.

## Key Conventions

**Agents vs. Skills vs. Commands:**
- Agents → isolated context, structured output, scoring, auditing
- Skills → injected knowledge, patterns, checklists; no isolation
- Commands → user-facing entry points; delegate to agents

**Global vs. per-project installation:**
- `.claude/` in a project repo = project-scoped
- `~/.claude/` = global across all projects
- `bootstrap.sh` handles project-scoped; `install-global.sh` handles global
- `{{GITHUB_REPO}}` placeholder in agents must be replaced at install time — it is not a runtime variable

**upgrade-audit skill** (`v2026-04-24`) checks the current project against this scaffold's reference files, produces a prioritized gap report with exact `cp` commands to close gaps, and detects local improvements worth contributing back upstream. Step 0 of the skill auto-updates itself from GitHub before running.

**ci-health command** (`/ci-health`) discovers all `.github/workflows/*.yml` files, checks the latest run for each, creates P0 tickets for failures, gates each ticket, and auto-implements safe fixes (lint, type, unit, build failures). It does NOT auto-fix E2E or security scan failures.

**Template versioning:** The `template-version: N` HTML comment in issue templates enables the `ticket-gate` agent to detect outdated templates and auto-synthesize missing sections without requiring manual upgrades.

## CLAUDE.md.template

`CLAUDE.md.template` is the deliverable for bootstrapped projects — it contains `{{TODO}}` placeholders that the project team fills in. When editing this file, preserve the placeholder format so `bootstrap.sh` can replace the repo-level ones and leave the project-specific ones for humans.
