---
name: roadmap-phases
description: Rolling wave planning made mechanical. docs/roadmap.md owns which phases exist and their state; the host owns which phase each ticket is in, as the milestone. A phase is planned when it starts, not before, and every ticket belongs to exactly one phase. Use when opening, closing, splitting or reordering a phase, when a ticket has no phase, when asked whether the current phase is done, or when check-phases.sh refuses something.
---

<!-- roadmap-phases-version: 1 -->

# Roadmap phases

## What this is, and what it is not

**Rolling wave planning.** Detailed planning is limited to the work about to begin; later work is
elaborated as uncertainty falls. The method exists because plans drift: writing every phase's plan
up front produces plans that are wrong by the time they are read, and filing every ticket up front
produces tickets for work the project has since decided against.

It is **not project management**. No dates, no estimates, no burndown, no reporting. It answers four
questions and refuses four mistakes, and a fifth of either is how it becomes something nobody runs.

## Source of truth

`docs/roadmap.md` owns **which phases exist and what state each is in**. The host owns **which phase
each ticket is in**, as the milestone field.

These are different facts, so neither store duplicates the other and there is nothing to drift.
Never record a ticket's phase in the roadmap, and never record a phase's existence only on the host.

## The four states

| state | plan required | milestone | tickets may be assigned | meaning |
|---|---|---|---|---|
| `planned` | no | open | **yes** | declared and ordered, not started: a bucket |
| `open` | **yes** | open | yes | in progress |
| `done` | yes | closed | yes (all closed) | finished, closed in both places |
| `backlog` | no | open | yes | the permanent holding phase; never closes |

**`planned` to `open` is what makes "the plan is written at the start" mechanical.** The transition
is the moment a plan becomes required, so the rule is a state change a script refuses rather than a
habit someone has to remember.

**A `planned` phase is a BUCKET, and that is its main job.** Small things you know you will want but
do not want to think about now get filed against it as they occur to you. Filing a thought you have
already had is not the same as enumerating work nobody has thought about yet, which is the thing to
avoid. When the phase opens, its plan is written from the roadmap prose AND whatever accumulated in
the bucket. The bucket is the evidence the plan is written from.

**`backlog` is an ordinary phase, not the absence of one.** That is what makes "every ticket has a
phase" true without forcing a premature decision. A ticket whose home is unknown goes to backlog,
which is a decision to decide later and is visible as such.

**At most one phase is `open`**, backlog excepted. "The current phase" has to name exactly one thing,
and two phases in progress is the state this method exists to prevent.

**Only the open phase carries commitment.** A `planned` phase's prose is a reason, never a promise.

## The roadmap format

```markdown
## Phase: Host awareness
state: open
plan: docs/plans/host-awareness.md

Why this phase exists, what it unlocks, why it sits here in the order.
```

Phases appear in roadmap order. **The plan path is declared, never derived from a number or a slug**,
because phases get split, reordered, renamed and deleted, and any convention encoding position in a
filename breaks on the first reorder by silently pointing at the wrong plan.

## The plan format

- **Goal.** One sentence.
- **Done looks like.** The observable state that ends the phase.
- **Fails if.** Required, and checked for.
- **Expected work.** The tickets this phase anticipates needing. Not binding.
- **Out of scope.** With the phase each deferral goes to, or `backlog`.

**Write "Fails if" as a premortem, not a risk list.** The prompt is: *it is the end of this phase and
it failed badly; what happened?* Imagining a failure that has already happened, rather than one that
might, surfaces roughly 30 percent more causes, because it licenses doubts people will not otherwise
raise while planning. A plan that only says what finishing looks like cannot tell you to stop.

## Opening a phase

Read **both** inputs: the roadmap prose saying why the phase exists, and the tickets already sitting
in its milestone. Write the plan from them, then move the phase to `open`.

Never open a second phase while one is open. Finish or re-shape the first.

## Closing a phase

1. Compare the plan against the tickets **actually created**, not the ones it expected. The
   difference is the interesting part.
2. **File tickets for skipped or missing work, and prioritise them.** Work that was silently
   dropped is the thing this review exists to catch.
3. Close the milestone **and** set the roadmap entry to `done`. Both, or the phase is not closed.
4. Record which of the three outcomes it was.

## When a phase does not finish: re-shape, never extend

The common case in a drifting project is not a phase that completes but one that stalls. The default
is to re-shape it, never to give it more time, so the project cannot spend multiples of the original
intent on something that needed rethinking first.

Rule 4 enforces this: a phase cannot be marked `done` while it holds open tickets, so closing one
forces every unfinished item somewhere explicit.

Three closing outcomes, and the roadmap records which:

- **done**, the work landed.
- **re-shaped**, some landed and the rest moved, with the phase closed anyway and the remainder
  named.
- **abandoned**, the phase was a wrong turn, its tickets closed or moved, and the roadmap says why.

**Abandoned is the one people skip, and the one worth writing down.** A phase deleted without a
record looks, six months later, like a phase nobody considered.

## Splitting, reordering and deleting

All three are ordinary edits to `roadmap.md`, then `sync-phases.sh`. Splitting a phase means adding
a phase and moving tickets between milestones. Reordering means moving the `##` blocks. Deleting
means removing the block and moving its tickets; the milestone is left on the host, because nothing
here ever deletes one.

## The four rules `check-phases.sh` enforces

1. **Every open ticket has a phase.** This is the rule that makes the untriaged set a single query
   instead of a full rescan, and it is what the whole method pays for by deferring plans.
2. **Every `open` or `done` phase has a plan file that exists and carries a "Fails if" section.**
   `done` is included so a phase moved straight from `planned` to `done` cannot skip the state where
   a plan is required.
3. **Roadmap state and milestone state agree, and at most one phase is `open`.**
4. **A phase marked `done` holds no open tickets.**

Rule 2 needs only the files. Rules 1, 3 and 4 need the host, and when it cannot be reached they are
reported as SKIPPED and the run exits non-zero: **a check that cannot run must never report clean.**

## Applying the roadmap to the host

`sync-phases.sh` creates missing milestones, closes the ones whose phase is `done`, and reports what
it would do under `--check`.

**It never deletes.** A milestone not in the roadmap is reported and left alone: it may be holding
someone's tickets, and a sync that deletes what it does not recognise is a footgun aimed at other
people's data. It also **refuses a malformed roadmap outright rather than skipping the block**,
because a silent partial sync is the drift the whole design exists to end.
