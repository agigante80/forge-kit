# forge-kit commands: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/commands/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why". Commands are thin
entry points that delegate to agents, so recommend the command alongside the agent it drives.

| Signal in the project | Command | Group | Canonical "why" (≤60) | Pairs with |
|---|---|---|---|---|
| Uses GitHub issues for work intake | `/gate-ticket` | governance | run the readiness gate on an issue | `ticket-gate` |
| Pre-merge / release / periodic audits | `/full-review` | review | multi-lens audit; per-task uses code-reviewer | review agents, `review-lows` skill |
| `.forgejo/workflows/`, `.gitea/workflows/` or `.github/workflows/` | `/ci-health` | devops | scan CI, ticket failures, auto-fix safe | `ticket-gate`, `forge-lib.sh` off GitHub |

Recommend `/gate-ticket` with `ticket-gate`: they are a pair. `/ci-health`
only when workflows exist.

**Sensitive-path offer (#448).** Whenever `/full-review` is recommended or already installed
(a plugin-registered one counts) and `.full-review-sensitive` is absent at the project root, add
one section under the tables showing the candidate list built by the "Generating the file" section
of `$FORGE_KIT_DIR/plugins/forge-kit-review/skills/review-sizing/SKILL.md`. Until that file
exists, `size-review.sh` sizes every round `full`. The user approves by replying `sensitive`
(alone or beside component names), with any edits to the list; that reply goes to Step 3, which
writes the approved list even when no component is picked. `none`, or a reply without `sensitive`,
declines: nothing is written and the next run offers again. Never offer over an existing file,
even an empty one. `refresh`/`drift` and `refresh <name>` never offer or write it.

**Retired in #178**: `/pr-enhance`. The original is `comprehensive-review@claude-code-workflows`.
