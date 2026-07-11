# Design: `working-overnight` autonomous-work bundle

Date: 2026-07-11
Status: approved design, pending spec review then implementation plan

## Problem

The user leaves the AI to work unattended overnight. Today a single blocking
question halts the whole session: the agent asks something only the user can
answer, stops, and the rest of the night is wasted. The user wants unattended
runs that keep making progress on work that is safe to do, follow the project's
best practices and governance automatically, and never idle-stall on a question
that could have been deferred.

The naive framing ("a skill that makes the AI never stop asking") is incomplete.
Field reports on overnight autonomous runs show the dominant failures are not
blocking questions but context exhaustion (the session silently stalls when the
window fills, and the model cannot see it happening), instruction drift (project
rules lose force after repeated compaction), runaway loops, and confidently wrong
irreversible actions. A design that only suppresses questions would leave every
one of those unaddressed, and "never stop, always guess" would amplify the
confidently-wrong risk into a whole night of work built on a bad assumption.

## Goal

An unattended overnight run that:

- pulls work from a defined source and keeps progressing on whatever is safe,
- resolves its own questions where it can, defers genuine you-only decisions
  instead of guessing (with a narrow low-stakes exception), and switches to other
  ready work rather than idling,
- routes every piece of work through the project's existing governance (best
  practice research, project rules, security, tests, verification),
- lands implementation as branch plus PR and never merges, and
- winds down cleanly with a morning report instead of stalling.

## Non-goals

- Not a new planning, review, or gating engine. It sequences components that
  already exist; it does not duplicate them.
- Not a merge/deploy automation. It never merges to main, deploys, or touches
  production unattended.
- Not a headless/container runner. This bundle targets a long live session on the
  user's machine (the chosen substrate), armed before the user leaves.

## Resolved decisions

| Decision | Choice | Rationale |
|---|---|---|
| Substrate and loop engine | `/loop working-overnight` (self-paced) drives the loop; each cycle is a fresh re-invocation. The `overnight-continue` hook is a within-iteration idle-stop safety net, not the engine | Verified against the installed Claude Code: a Stop hook is capped at 8 consecutive blocks, so it cannot drive an all-night loop on its own. `/loop` re-invokes per cycle, which both sustains the run and resets context each cycle, fixing the single-session exhaustion risk. |
| Work source | Tiered: investigations and ticket drafting/gating (reversible artifacts), then implementation of cleanly-gated tickets | User wants both queue work and investigation-generated work. Tiering by output reversibility is what makes open-ended scope safe. |
| Action limit | Branch plus PR, never merge | User choice. Reversible via review; CI still gates; main is never touched unattended. |
| Blocked policy | Self-resolve first; genuine you-only decision -> low-stakes and reversible: assume, log, continue; else defer to a decision queue and move on | User choice (tiered). Keeps progress without building a night on a wrong guess. |
| Wind-down | Queue-empty is the goal state, with a mandatory low-context/budget backstop and an investigation-depth cap | User chose queue-empty; the backstop and cap are added because queue-empty alone can non-terminate (investigation regenerates the queue) and does not prevent the silent-stall failure. |
| Home and enforcement | A `working-overnight` skill in forge-kit-governance plus an `overnight-continue` Stop hook, driven by `/loop` | User choice. The skill holds the judgment and drives the cycle; the hook keeps a single cycle from halting on a question; `/loop` sustains the run across cycles. |
| Naming | Gerund form: `working-overnight` (skill), `overnight-continue` (hook) | House convention for skill names. |

## Architecture

This is a bundle, not a lone skill.

```
plugins/forge-kit-governance/
  skills/working-overnight/
    SKILL.md                      # pre-flight, the governed loop, wind-down
    references/
      pipeline.md                 # the per-task governance pipeline (best practice -> rules -> TDD -> security -> verify)
      safety.md                   # tier model, Tier-3 never-list, isolation rules
  hooks/
    overnight-continue.py         # sentinel-gated, fail-open Stop hook
    hooks.json                    # wires the Stop hook (plugin-registered)
```

Runtime artifacts (in the target project, gitignored):

```
.claude/overnight/active.md       # run manifest + sentinel: armed while present, removed at wind-down
.claude/overnight/queue.md        # work-queue state, checkpointed after every item
.claude/overnight/decisions.md    # deferred you-only decisions, with options, for the morning
.claude/overnight/report.md       # the morning report written at wind-down
```

The run manifest doubles as the hook's arming sentinel: its presence means a run
is active; its removal at wind-down disarms the hook.

## Reuses (no duplication)

- superpowers: brainstorming is already done; the loop uses writing-plans,
  test-driven-development, executing-plans / subagent-driven-development, and
  verification-before-completion for each implementation task.
- forge-kit governance: `ticket-gate` (gate a ticket), `security-auditor`,
  `code-reviewer`, `coding-standards-auditor` / `docs/coding-standards.md`.
- `closing-sessions`: the morning report reuses its handoff format and, where
  durable facts emerge overnight, its `memory.py` helper.
- Web search: for the best-practice research step of the pipeline.

## The loop

`/loop working-overnight` is the engine: it re-invokes the skill each cycle, self
paced. A cycle does one unit of work (see below) and returns; the next cycle
starts with fresh context, which is the primary defense against context
exhaustion. The `overnight-continue` hook only prevents a single cycle from
halting early on a question. Wind-down stops the loop (via `ScheduleWakeup`
`stop: true`) and disarms the hook.

### Pre-flight (interactive, before the user leaves)

The skill confirms and records, into `.claude/overnight/active.md`:

- scope and work source (which tickets, which investigations, any no-go areas),
- the budget (token/cost ceiling) and any investigation-depth cap,
- the safety config (allowed tools, the Tier-3 never-list),
- isolation setup (a worktree per task).

It writes the manifest, seeds `queue.md`, and arms the hook. Nothing autonomous
starts until the user confirms the manifest.

### Each iteration

1. Re-read the manifest and the project rules (CLAUDE.md, coding-standards). This
   is the antidote to instruction-drift: the rules are refreshed every loop rather
   than trusted to survive compaction.
2. Pull the next work item by priority: cleanly-gated ready tickets, then gating
   ungated tickets, then investigations (bounded by the depth cap).
3. Classify the item by tier. A Tier-3 action is never performed; it is parked.
4. Resolve questions: try web, code, and project rules first. A genuine you-only
   decision that is low-stakes and reversible gets a logged assumption and
   continues; otherwise it is written to `decisions.md` with the options seen and
   the item is skipped.
5. Execute through the governance pipeline (see references/pipeline.md): best
   practice research, project rules, TDD from the ticket's test specs, security
   review, verification before completion.
6. Land the result as a branch plus a PR, in the item's own worktree. Never merge.
7. Checkpoint `queue.md`.
8. Backstop check: if context or budget is near its limit, finish the current
   step, write the report, disarm, and stop.

Context survival is layered: the primary defense is that `/loop` starts each cycle
with fresh context, so a cycle only needs to hold one unit of work. Within a
cycle, real work is still delegated to subagents so their tool output consumes
their context, not the cycle's. State lives in the on-disk artifacts
(`queue.md`, `decisions.md`, the manifest), never only in conversation memory, so
a fresh cycle resumes exactly where the last one left off.

### Wind-down

Triggered by queue-empty (the goal) or the backstop. The skill writes
`report.md` (shipped PRs, deferred decisions with options, investigations done,
assumptions to verify, suggested next), removes the sentinel to disarm the hook,
and stops the loop with `ScheduleWakeup` `stop: true` so no further cycle fires.

## The `overnight-continue` hook

A `Stop` hook that fires when the agent finishes a turn. Its job is narrow: keep a
single overnight cycle from idling to a stop on a question. It is a safety net,
not the loop engine (`/loop` is the engine).

Verified `Stop`-hook contract (checked against the installed Claude Code, CLI
2.1.207, not from memory):

- To continue: exit 0 and print `{"decision": "block", "reason": "<why>"}` on
  stdout. `reason` is required and is shown to the model.
- To allow a normal stop: exit 0 with no stdout (or `{}`).
- Do not use exit 2 for continuation: for `Stop`, exit 2 blocks but its stderr is
  not surfaced to the model as instruction, and exit codes and JSON are mutually
  exclusive.
- Claude Code ends the turn after 8 consecutive `Stop`-hook blocks, and
  `stop_hook_active` is true once it is already continuing from a block. This cap
  is why the hook cannot be the loop engine.

Behavior:

- Sentinel-gated: it emits a continue decision only when `.claude/overnight/active.md`
  exists. With no manifest it exits 0 silently, so normal daytime sessions are
  never affected. This mirrors how `block-dashes` stays dormant without
  `.claude/no-dashes`.
- Fails OPEN as allow-stop. This is the inverse of a guard hook. For an
  auto-continue hook the dangerous direction is continuing, so any error,
  unparseable payload, or missing manifest exits 0 with no output and lets the
  session stop. A broken hook must never be able to hold a session open.
- Honors `stop_hook_active`: if it is already true, the hook allows the stop
  rather than pushing toward the 8-block cap, leaving sustained progress to
  `/loop`.
- Respects wind-down: once the skill removes the sentinel, the next `Stop` is
  allowed.

## Safety rails

- Tier model by output reversibility. Tier 1 (investigations, reviews, research,
  drafting and gating tickets) is free to run; it produces reviewable artifacts and
  changes no code. Tier 2 (implementing gated tickets, opening PRs) runs but is
  parked for review, never merged. Tier 3 (merge to main, force-push, delete,
  deploy, secrets, prod) is never done unattended.
- Gating filters, never self-approves. A ticket the same run authored is
  implemented only if it cleanly passes the gate; anything short is parked.
- Permission allowlist with no destructive tools; a worktree per task so parallel
  work cannot collide and main stays clean.
- Everything logged: every assumption and every deferral is written down and shows
  up in the morning report.
- Over-verify. Unattended work gets more verification than a supervised task, not
  less: drive the real flow, not just tests.

## Honest limits

- forge-kit cannot unit-test a skill. Behavioral validation is a real overnight
  dry-run in a throwaway project. Only the hook has a mechanical contract test.
- Context exhaustion is mitigated primarily by fresh context per `/loop` cycle,
  plus subagent delegation and the low-context backstop within a cycle. The
  backstop is mandatory, not optional.
- The end-to-end loop behavior (that `/loop` plus the hook sustains many cycles
  and winds down cleanly) can only be confirmed by the behavioral dry-run, not by
  a unit test.
- This is larger than a single component; the plan will be several tasks (hook and
  its tests, skill and its references, arming/artifacts, wiring and gates).

## Testing and acceptance

- The `overnight-continue` hook gets contract tests in `scripts/test-hooks.py`:
  armed manifest present and `stop_hook_active` false -> emits
  `decision: block` on stdout, exit 0; no manifest -> no stdout, exit 0 (allow
  stop); malformed payload -> no stdout, exit 0 (fail-open); `stop_hook_active`
  true -> allow stop (do not push the 8-block cap); sentinel removed mid-run ->
  allow stop.
- Skill acceptance is behavioral: arm a run in a throwaway project seeded with a
  couple of gated tickets and one investigation, let it loop, and confirm it opens
  PRs (never merges), defers a planted you-only decision to `decisions.md`,
  continues to the next item rather than stalling, and writes a coherent
  `report.md` at queue-empty.

## Shipping and CI

- Bump `forge-kit-governance` plugin.json version (new skill and new hook).
- Version markers: `<!-- working-overnight-version: 1 -->` in SKILL.md and
  `# overnight-continue-version: 1` in the hook.
- Add `.claude/overnight/` to the project's gitignore (runtime artifacts).
- Gates: `validate-plugins.sh`, `test-hooks.py`, `check-version-bump.sh` against
  origin/main; all files free of em and en dashes.

## Follow-ups (out of scope)

- A forge-adapt recommender row so the bundle surfaces during install.
- A headless/phased substrate variant (fresh `claude -p` per phase) for users who
  want container isolation instead of a live session.
- Optional integration with the `minion` (Pi) as the executor.
