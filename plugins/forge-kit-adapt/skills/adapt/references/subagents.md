# forge-kit subagents — signal → component → why

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
| Backend handles untrusted input | `backend-security-coder` | security | secure-coding pass for backend handlers | P1 |
| Architecture decisions / large diffs | `architect-review` | review | architectural integrity + boundaries | P1 |
| Backend service / API design work | `backend-architect` | review | backend + API design review | P1 |
| General code quality | `code-reviewer` | review | code quality + correctness review | P1 |
| Frequent edits, churn | `code-simplifier` | review | simplify recently changed code | P2 |
| Deep / many dependencies | `dep-auditor` | devops | unused, unmaintained, vulnerable deps | P1 |
| New / unfamiliar dev environment | `health-check` | devops | verify runtime, package mgr, env files | P2 |
| Test-first culture / TDD | `tdd-orchestrator` | testing | orchestrate red-green-refactor flow | P2 |
| Tests sparse or missing | `test-automator` | testing | generate + maintain test coverage | P1 |
| Performance-critical paths | `performance-engineer` | testing | find + fix performance bottlenecks | P2 |

Ordering rule: `ticket-gate` first when missing, then any P0, then P1, then P2. Lead the
Subagents block with at most the top 1-2 unless the user asks for "more subagents".
