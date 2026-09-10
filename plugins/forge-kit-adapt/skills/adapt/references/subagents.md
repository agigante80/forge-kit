# forge-kit subagents: signal, component, why

Reference for Step 2 of forge-adapt. The live `ls` of `$FORGE_KIT_DIR/plugins/*/agents/` is the
source of truth for what EXISTS; this file is the source of truth for the canonical ≤60-char
"why" and the priority. Keep reasons consistent with the phrasing here. If a row's component is
not in the live catalogue, skip it.

| Signal in the project | Subagent | Group | Canonical "why" (≤60) | Priority |
|---|---|---|---|---|
| Any project (universal gate) | `ticket-gate` | governance | quality gate before implementation | P0 |
| Coding standards not `proper` (inline/scattered/missing) | `coding-standards-auditor` | review | consolidate standards to docs/coding-standards.md | P0 |
| Auth / payments / PII in code | `security-auditor` | security | OWASP + auth + secrets exposure | P0 |
| Public/REST API surface | `api-security-tester` | security | tests endpoints vs OWASP API Top 10 | P0 |
| Architecture decisions / large diffs | `architect-review` | review | architectural integrity + boundaries | P1 |
| General code quality | `code-reviewer` | review | THE per-task reviewer, rounds bounded | P1 |
| Frequent edits, churn | `code-simplifier` | review | simplify changed code; request-only w/ superpowers | P2 |
| Deep / many dependencies | `dep-auditor` | devops | unused, unmaintained, vulnerable deps | P1 |
| New / unfamiliar dev environment | `health-check` | devops | verify runtime, package mgr, env files | P2 |

Ordering rule: `ticket-gate` first when missing, then any P0, then P1, then P2. Lead the
Subagents block with at most the top 1-2 unless the user asks for "more subagents".

Coexistence: the two rows above defer to the superpowers plugin where present; the
disposition table in SKILL.md Step 2 is the single decision point.

**Retired in #178** and not to be recommended: `backend-security-coder`, `backend-architect`,
`tdd-orchestrator`, `test-automator`, `performance-engineer`. The originals are maintained
upstream in wshobson/agents (`claude-code-workflows`). Point the user there rather than at a
forge-kit component that no longer exists.
