# forge-adapt recommendation (captured 2026-11-13)

Real output of the `forge-kit-adapt:adapt` skill in recommend-only mode. The project was a throwaway
Node.js and Express orders API (JWT login, a Stripe webhook, Postgres) with no governance installed.
Nothing was written to it. The text below is the skill's reply, unedited.

```text
## forge-adapt - orders-api (Node.js / Express)

Profile
  Stack: Node.js, Express 4, jsonwebtoken, pg (Postgres), Stripe SDK, Jest
  Domain: REST API for customer orders with JWT login and Stripe payments
  Security surface: JWT signed with no expiry on `/login`; Stripe webhook with no signature check; `GET /orders/:id` with no auth check; Postgres customer data
  Superpowers: present
  Coexistence: suppressed: code-simplifier (superpowers owns the inner loop, and its proactive post-change edits sit outside the review loop's bad-fix accounting)
  Installed: none in `.claude/` (the governance, review, security and devops plugins are enabled, so picks from those groups register rather than copy)

### Recommended (top picks for this project)
| Component | Type | Why this project needs it | Priority |
|---|---|---|---|
| ticket-gate | 🤖 subagent | quality gate before implementation | P0 |
| coding-standards-auditor | 🤖 subagent | no standards doc; no CLAUDE.md or CONTRIBUTING | P0 |
| security-auditor | 🤖 subagent | JWT signed with no expiry; Stripe webhook unverified | P0 |
| api-security-tester | 🤖 subagent | GET /orders/:id has no auth check (IDOR) | P0 |
| owasp-api-security | 🎯 skill | public REST API with auth + payments | P1 |
| privacy-regime | 🎯 skill | orders + logins are personal data; needs YOUR regime | P1 |
| /gate-ticket | 🧩 command | run the readiness gate on an issue | P1 |
| /full-review | 🧩 command | multi-lens audit; per-task uses code-reviewer | P1 |
| forge-write-consent | ⚡ hook | no comment or new ticket unless the user grants it | P1 |
| masked-exit-advisory | ⚡ hook | flag a jest run whose exit code a pipe masks | P2 |

`privacy-regime` is offered, never auto-installed: it ships blank and needs your jurisdiction filled in.

### Issue templates
Issue templates: none; reply "templates" to install the v6 set inline.

### Sensitive paths for /full-review
`.full-review-sensitive` is absent, so every review round is sized `full`. Candidate list: empty, because no tracked path matched the default patterns (the repo tracks only `README.md`, `package.json` and `src/server.js`) and there is no CODEOWNERS file. Reply "sensitive" with the lines you want (for example `src/server.js`, which holds the auth and webhook code) to write the file.

Reply:
- names to install (I adapt each to your stack), "all", or "none"
- "templates" - install/upgrade the issue-template set inline (adapted to your packages) plus the optional lockstep guard + ticket-standards doc. No separate command needed.
- "sensitive" - write `.full-review-sensitive` with the list you approve
- "refresh <name>" - deep-compare one installed component and merge genuine improvements
- "refresh" - full drift report (writes nothing)
- "more subagents" / "more skills" / "more commands" / "more hooks" - full catalogue for a category, as a table
```

The skill then waits for you to name what to install, adapted to your stack. See
[Getting started](../getting-started.md).
