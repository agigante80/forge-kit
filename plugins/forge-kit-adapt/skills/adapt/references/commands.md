# forge-kit commands: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/commands/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why". Commands are thin
entry points that delegate to agents, so recommend the command alongside the agent it drives.

| Signal in the project | Command | Group | Canonical "why" (≤60) | Pairs with |
|---|---|---|---|---|
| Uses GitHub issues for work intake | `/gate-ticket` | governance | run the readiness gate on an issue | `ticket-gate` |
| Pre-merge / large change reviews | `/full-review` | review | multi-dimensional code review pass | review agents |
| Pull-request workflow | `/pr-enhance` | review | generate PR description + checklist | (none) |
| `.github/workflows/` present | `/ci-health` | devops | scan CI, ticket failures, auto-fix safe | `ticket-gate` |

Recommend `/gate-ticket` whenever `ticket-gate` is recommended: they are a pair. `/ci-health`
only when GitHub Actions workflows actually exist.
