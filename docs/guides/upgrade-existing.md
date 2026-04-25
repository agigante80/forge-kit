# Keeping Your Project in Sync with forge-kit

forge-kit is a living reference. As new agents, patterns, and governance improvements
are added, `forge-adapt` pulls them into your project — selecting only what's relevant
and rewriting each component to fit your specific stack and domain.

## How forge-adapt works

When you run `forge-adapt`, it runs eight phases:

| Phase | What happens |
|---|---|
| 0 | Self-update check — compares local vs remote blob SHA, auto-updates if different |
| 1 | Verify forge-kit is available at `~/forge-kit/` |
| 2 | Analyse your project — stack, domain, security surface, existing governance |
| 3 | Catalogue forge-kit — reads all available agents, commands, and skills |
| 4 | Produce a ranked recommendation table — waits for your selection |
| 5 | Adapt and install approved items — Claude rewrites each template for your project |
| 6 | Scan for contribution candidates — project-only components worth sharing back |
| 7 | Create GitHub issues on forge-kit for accepted contribution candidates |

Phases 0–4 are read-only. No files are written until you approve selections in Phase 4.

## Running forge-adapt

First, make sure forge-kit is cloned locally:

```bash
git clone https://github.com/agigante80/forge-kit ~/forge-kit
```

Then open Claude Code in your project and say:

```
run forge-adapt
```

### Example Phase 4 output

```
## forge-adapt — my-saas-app

Skill: forge-adapt @ a3f7c12
forge-kit: 0b9d948 (2026-04-23)

Project: TypeScript/Next.js SaaS with PostgreSQL and JWT auth.
         REST API, 3 external integrations, GDPR-relevant user data.

### Recommended to install and adapt
| # | Component | Type | Why this project needs it | Priority |
|---|-----------|------|--------------------------|----------|
| 1 | ticket-gate | agent | Quality gate — universal need | P0 |
| 2 | security-auditor | agent | JWT + PostgreSQL surface has OWASP exposure | P0 |
| 3 | api-security-tester | agent | Public REST API with auth endpoints | P0 |
| 4 | dep-auditor | agent | npm ecosystem with transitive deps | P1 |
| 5 | forge-adapt | skill | Keeps governance in sync over time | P1 |

### Already installed — version check
| # | Component | Status |
|---|-----------|--------|
| 6 | code-reviewer | ⚠ Differs from forge-kit reference — consider updating |

Which would you like to import and adapt?
Reply with numbers (e.g. "1 3 5"), "all", or "none".
```

### What "adapt" means

When you select a component, forge-adapt does not copy the generic template.
It reads both the template and your project profile, then generates a version
specific to your project. For example:

- Generic: "check for SQL injection in database queries"
- Adapted: "check for Prisma `$queryRaw` / `$executeRaw` injection; verify parameterized queries are used in all raw SQL calls"

Every customisation is traceable to a specific characteristic of your project.

## Keeping forge-kit up to date

```bash
git -C ~/forge-kit pull
```

Then run `forge-adapt` in your project — it will detect what has changed (via blob SHA comparison) and offer to update your installed components.

## "Am I up to date?"

The Phase 4 "Already installed — version check" table shows every component whose
content differs from the current forge-kit reference. Run `forge-adapt`, skip
Phase 4 new installs (reply "none"), and update only the outdated items.

## Backward compatibility

`forge-adapt` also responds to "run upgrade-audit" for projects that used the old skill name.
