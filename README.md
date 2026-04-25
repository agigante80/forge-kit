# forge-kit

forge-adapt reads your codebase and installs the governance tools that fit — rewritten for your stack, not copy-pasted.

forge-kit is a library of project governance components: ticket gates, code reviewers, security auditors, dependency auditors, and more. `forge-adapt` is the skill that bridges forge-kit and your project — it reads your codebase, recommends what's relevant, and writes project-specific versions into `.claude/`. Nothing generic. Every component knows your stack.

## How it works

```
1. Install forge-kit          /plugin marketplace add https://github.com/agigante80/forge-kit
                              /plugin install forge-kit-governance@forge-kit

2. Open your project          cd my-project
   and run forge-adapt        (say "run forge-adapt" to Claude Code)
```

forge-adapt takes it from there.

## What forge-adapt does

When you say "run forge-adapt", it:

1. **Analyses your project** — reads your stack files, CLAUDE.md, source structure, and existing `.claude/` contents to build a project profile
2. **Recommends components** — cross-references your profile against the forge-kit library, ranks by relevance and priority, shows you why each component fits your project specifically
3. **Waits for your approval** — nothing is written until you select what to install
4. **Writes adapted versions** — Claude rewrites each component using your project profile. "Check for SQL injection" becomes "check for Prisma `$queryRaw` / `$executeRaw` injection in `src/db/`"

## Example

```
Project profile:
  Language/framework: TypeScript / Next.js 14
  Domain: SaaS — multi-tenant project management with billing
  Security surface: JWT auth, Stripe webhooks, PostgreSQL via Prisma
  Governance already installed: none

### Recommended to install and adapt
| # | Component          | Type    | Why this project needs it                        | Priority |
|---|--------------------|---------|--------------------------------------------------|----------|
| 1 | ticket-gate        | agent   | Quality gate — universal need                    | P0       |
| 2 | security-auditor   | agent   | JWT + Stripe webhook surface has OWASP exposure  | P0       |
| 3 | api-security-tester| agent   | Public REST API with auth and payment endpoints  | P0       |
| 4 | dep-auditor        | agent   | npm ecosystem with deep transitive deps          | P1       |
| 5 | code-reviewer      | agent   | TypeScript/Next.js patterns and type safety      | P1       |
| 6 | forge-adapt        | skill   | Keeps governance in sync with forge-kit          | P1       |

Which would you like to import and adapt?
Reply with numbers (e.g. "1 3 5"), "all", or "none".

> all

✓ ticket-gate (agent) — adapted for agigante80/my-saas; Prisma + Stripe checks added
✓ security-auditor (agent) — JWT algorithm and webhook signature checks injected
✓ api-security-tester (agent) — Stripe webhook endpoint added to test surface
✓ dep-auditor (agent) — npm audit + license checks for payment libraries
✓ code-reviewer (agent) — Next.js App Router patterns and Prisma query safety
✓ forge-adapt (skill) — installed and self-updating
```

## The library

forge-kit ships two layers.

### Governance layer — works without Claude Code

| Component | What it does |
|---|---|
| 6 issue templates | feature, bug, security, infrastructure, design, contribution — v4 with GWT scenarios, unit test specs, E2E test specs, GDPR and security checklists |
| GitHub labels | Standard label taxonomy for issue routing and prioritisation |

### Automation layer — Claude Code-native

| Component | What it does |
|---|---|
| `forge-adapt` skill | Analyses the target project, recommends relevant components, writes project-customised versions, and surfaces contribution candidates back to forge-kit |
| `ticket-gate` agent | Scores every GitHub issue before implementation (5 core agents + dynamic routing by label). ALL must score 10/10 to pass |
| 11 specialist agents | code-reviewer, security-auditor, architect-review, backend-architect, backend-security-coder, api-security-tester, tdd-orchestrator, test-automator, performance-engineer, dep-auditor, health-check |
| `/full-review` | Multi-phase code review orchestrator with a mid-run checkpoint |
| `/pr-enhance` | Pull request description and checklist generation |
| `/ci-health` | Check all GitHub Actions workflows, create P0 tickets for failures, auto-fix safe failures |
| 7 skills | forge-adapt, api-design-principles, owasp-api-security, architecture-patterns, microservices-patterns, cqrs-implementation, saga-orchestration |

## After setup

Once forge-adapt has installed your components, the governance workflow looks like this:

```
file ticket → gate it (10/10 from all specialists) → implement → review
```

`/gate-ticket <N>` runs on every GitHub issue before a line of code is written. If the issue was filed against an older template, the gate auto-synthesises missing GWT scenarios and test specs — no manual rework needed.

```
/gate-ticket 42

Running ticket readiness gate on #42...

Template auto-upgraded to v4 - content synthesised
- GWT scenarios: 3 conditions, 6 scenarios
- Unit tests: 4 specific cases
- E2E tests: 2 specific cases

Security:  10/10 PASS
Architect: 10/10 PASS
Developer: 10/10 PASS
QA:        10/10 PASS
GDPR:      10/10 PASS

PASS - Ticket #42 is ready for implementation
```

## Manual install (without plugin marketplace)

```bash
git clone https://github.com/agigante80/forge-kit ~/forge-kit
```

Then open Claude Code in your project and say "run forge-adapt". It will find forge-kit at `~/forge-kit/` and run all phases from there.

## Using without Claude Code

If your team uses Cursor, GitHub Copilot, or no AI CLI, you can still adopt the governance layer. Copy `.github/ISSUE_TEMPLATE/` and `.github/labels.yml` into your project. The automation layer — forge-adapt, agents, slash commands — requires Claude Code and can be added later.

## Keeping up to date

forge-adapt auto-updates itself on every run via a blob SHA check against the GitHub remote — no manual steps needed.

To pull new or updated library components:

```bash
# Plugin marketplace
/reload-plugins   # after enabling auto-update in /plugin → Marketplaces

# Manual install
git -C ~/forge-kit pull
```

Then run forge-adapt again in your project. Phase 4 shows which of your installed components have drifted from the forge-kit reference and offers to refresh them.

## Docs

- `docs/guides/template-versioning.md` — v4 GWT versioning and auto-synthesis
- `docs/guides/labels.md` — label taxonomy and agent routing rules
