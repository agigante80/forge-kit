# When to run what

Hand-written on purpose: this is sequencing guidance, not inventory.

| When | Run | Why |
|---|---|---|
| Before writing code for a ticket | `/gate-ticket <N>` | A ticket that fails the gate costs a rewrite; one that passes carries its own GWT scenarios and test specs. |
| While implementing | `code-reviewer` | The per-task reviewer, under the bounded iteration contract. Not `/full-review`. |
| Before merging, or periodically | `/full-review` | Multi-lens audit. Findings are fixed in-loop, ticketed or dropped. |
| When CI is red | `/ci-health` | Files P0 tickets for failures (GitHub or Forgejo) and auto-fixes the safe classes on GitHub. |
| Periodically | "audit dependencies", "health check" | `dep-auditor` and `health-check` are agents, not slash commands: mention them in conversation. |
| Before a session ends | `closing-sessions` | Persists durable facts and resume state; without it the next session starts cold. |
| When a ticket is stalled on a decision | `decision-brief` | Re-gates it, costs the options, and rewrites the body so the decision can be made from it. |
| When you ask for an opinion or pros and cons in conversation | `weighing-options` | One answer shape with dated sources and a recommendation; an accepted decision is recorded as a coding rule or an accepted ADR. |
| Opening, reviewing or closing a phase | `/phase` | Only with `forge-kit-roadmap` installed. Inert in a project with no roadmap. `/phase review` is the mid-flight alignment check; `/phase reassess` reassesses the whole roadmap. |
| Every few months | `forge-adapt drift` | Reports what lags forge-kit and whether the marketplace copy itself is stale. Writes nothing. |

Overnight work is its own mode: `working-overnight` runs governed unattended cycles that ship
branch-plus-PR and never merge, deferring decisions that are yours rather than guessing.
