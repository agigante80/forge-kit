# Roadmap phases: design

Date: 2026-09-08
Status: design agreed, spec for review

## The problem

A project needs a shape larger than a ticket and smaller than a wish. The maintainer's working
method is a roadmap of phases, where each phase gets a plan written **at the moment it starts**,
and every ticket belongs to exactly one phase. Nothing in forge-kit supports this today: the kit
governs individual tickets (`ticket-gate`), unattended work (`working-overnight`) and releases, and
has no concept of what a ticket is *for* beyond its labels.

The method exists because plans drift. Writing every phase's plan up front produces plans that are
wrong by the time they are read, and filing every ticket up front produces tickets for work the
project has since decided against. So the method deliberately defers both, and pays for that
deferral with a rule: **every ticket carries a phase, so the untriaged set is one query rather than
a full rescan.**

## What this is not

It is not project management. There are no dates, no burndown, no estimates, and no reporting. The
system exists to answer four questions and refuse four mistakes, and adding a fifth of either is
how it becomes something nobody runs.

## Source of truth

`roadmap.md` owns **which phases exist and what state each is in**. The host owns **which phase each
ticket is in**, as the milestone field. These are different facts, so neither store duplicates the
other and there is nothing to drift.

This was the load-bearing decision. Two hand-maintained copies of one fact is the defect class this
repo has been burned by twice (the component inventory, #96; the doc-versus-gate restatement, #125),
and the answer both times was one source plus a mechanical check. Milestones were chosen over labels
because a milestone already has the open/closed state a phase needs, holds at most one value per
issue by construction, and is the same primitive on GitHub and Forgejo.

`docs/roadmap.md` is the path. The guard also accepts a root `roadmap.md` for projects that put it
there, checking `docs/` first.

## The roadmap format

One `##` heading per phase, in roadmap order, each with two machine-readable fields and free prose.

```markdown
## Phase: Host awareness
state: open
plan: docs/plans/host-awareness.md

Why this phase exists, what it unlocks, why it sits here in the order. Prose, for humans.
```

`state` is one of four values, and the states do real work rather than describing it:

| state | plan required | milestone | tickets may be assigned | meaning |
|---|---|---|---|---|
| `planned` | no | open | **yes** | declared and ordered, not started: a bucket |
| `open` | **yes** | open | yes | in progress |
| `done` | yes | closed | yes (all closed) | finished, closed in both places |
| `backlog` | no | open | yes | the permanent holding phase; never closes |

**`planned` to `open` is the mechanical form of "the plan is written at the beginning of the
phase".** The transition is the moment a plan becomes required, so the rule is a state change a
script can refuse rather than a habit someone has to remember.

**A `planned` phase is a BUCKET, and that is its main job.** Small things you know you will want
but do not want to think about now get filed against it as they occur to you. When the phase opens,
its plan is written from two inputs: the roadmap prose saying why the phase exists, and whatever has
accumulated in the bucket since. The bucket is not a side effect of deferring the plan; it is the
evidence the plan is written from.

This is the one place the first draft of this design was wrong. It proposed refusing tickets on a
`planned` phase, reasoning from "do not create tickets for the whole roadmap at once". That rule is
about not enumerating work you have not thought about yet, not about refusing a thought you have
already had.

**`backlog` is an ordinary phase, not the absence of one.** That is what makes "every ticket has a
phase" true without forcing a premature decision: a ticket whose home is not yet known goes to
backlog, which is a decision to decide later, and is visible as such.

**At most one phase is `open` at a time**, `backlog` excepted. "The current phase" has to name
exactly one thing for `/phase status` to mean anything, and two phases in progress is the state the
method exists to prevent. Checked as part of rule 3.

**The plan path is declared, never derived.** No numbering, no slug convention. Phases get split,
reordered, renamed and deleted, and any convention that encodes position in a filename breaks on
the first reorder, silently, by pointing at the wrong plan.

## The plan format

Written when a phase moves to `open`, reviewed while it is open. Required sections:

- **Goal.** One sentence. What this phase is for.
- **Done looks like.** The observable state that ends the phase.
- **Fails if.** Required, and checked for, because a plan that only says what finishing looks like
  cannot tell you to stop. Written as a PREMORTEM rather than a risk list: "it is the end of this
  phase and it failed badly; what happened?" Klein's result is that imagining an event has already
  happened, rather than that it might, raises the number of correctly identified causes by about
  30 percent, and the mechanism is that it licenses people to voice doubts they are otherwise
  reluctant to raise during planning. The skill states the prompt in that form.
- **Expected work.** The tickets this phase anticipates needing. Not binding: the close review
  compares this against what was actually created, and the difference is the interesting part.
- **Out of scope.** With the phase each deferral goes to, or `backlog`.

## Prior art

This method is not new, and naming what it already is makes the design arguable rather than
personal. Three established practices line up almost exactly, and one supplied a correction.

- **Rolling wave planning** (PMI's term for the operating model, progressive elaboration being the
  underlying principle) is precisely the method: detailed planning is limited to the work about to
  begin, and later work is planned progressively as uncertainty falls. The usual shape is detailed
  tasks for the near window, milestone-level planning beyond it, and phase-level goals for the
  rest. That is what the `open` / `planned` / `backlog` split encodes.
- **Now / Next / Later** (Janna Bastow, ProdPad) is the same idea as a roadmap format, and supplies
  the rule this design most needed to state out loud: **only "Now" carries commitment. "Next" and
  "Later" are direction and priority, not a promise.** So a `planned` phase's prose is a reason,
  never a contract, and dropping dates from everything outside the current phase is the point
  rather than an omission.
- **The premortem** (Gary Klein, HBR 2007) is what the "Fails if" section should be, and gives it a
  better prompt than the one first drafted. See the plan format above.
- **The permanent backlog milestone as a triage inbox** is an existing GitHub practice, not an
  invention here: a `Backlog` milestone kept open forever so that every new issue lands somewhere
  and its state is explicit rather than absent.

**Where this differs from all of them:** each of the above is a practice that asks people to
remember it. This design's contribution is that four of its rules are refusals a script performs,
which is forge-kit's whole premise. The existing GitHub Actions in this space
(`triage-action` and friends) enforce labels or auto-assign milestones; none of them check a
roadmap document against the host, because none of them assume one exists.

## A separate plugin group, so it can be declined

**Rolling wave planning is one opinionated method. The rest of forge-kit is methodology-agnostic**:
`ticket-gate` governs a ticket, `release-automation` governs a version, `forge-host` governs a
host, and none of them care how work is grouped. Shipping phases inside `forge-kit-governance`
would force a project-management methodology on everyone who wanted a ticket gate.

So this is its own group, **`forge-kit-roadmap`**, installed or declined on its own:

```
/plugin install forge-kit-roadmap@forge-kit
```

**The dependency runs one way only.** The group needs `forge-lib.sh` from `forge-kit-devops` to
talk to milestones, which is the same shape `ticket-gate` already has and which `forge-adapt`
already installs as a declared dependency. Nothing in `devops`, `governance`, `review`, `security`,
`testing` or `backend` learns what a phase is.

**In particular, `ticket-gate` never learns about phases.** "Has a phase assigned" looks like a
ticket-readiness property and must not become one, because that single line would couple the gate
to this methodology and make the group non-optional in practice while remaining optional on paper.
If that ever looks worth doing, it is a separate decision with its own ticket.

The milestone primitives are the one thing that does NOT go in this group. Milestones are a host
capability, not a planning concept; `dep-auditor` already reads them, and a project using some
other method still wants them. They belong in the host adapter.

## Isolation is enforced, not asserted

A boundary that is only stated survives until the first convenient reference. `scripts/check-group-isolation.sh`
fails the build if any component outside `plugins/forge-kit-roadmap/` mentions this group's
identifiers: `forge-kit-roadmap`, `roadmap-phases`, `check-phases.sh`, `sync-phases.sh`.

It keys on those identifiers rather than on the English word "roadmap", which appears innocently in
prose all over the kit. The reverse direction is allowed and expected: the roadmap group referring
to `forge-lib.sh` is the declared dependency, not a violation.

**One exemption, and it requires a reason**, the shape `check-restatements.sh` already uses.
`forge-kit-adapt` is the installer and by definition knows every component exists, so its dependency
list names these like any other. That is a catalogue entry, not a dependency, and the guard says so
in the entry rather than leaving a silent hole.

## Components

Five components across two plugin groups, plus one repo guard.

### `forge_milestone_*` in `forge-lib.sh` (`forge-kit-devops`)

`forge_milestone_list`, `forge_milestone_create`, `forge_milestone_update`, `forge_milestone_close`,
and `forge_issue_set_milestone`. None exist today. Host-aware like the rest of the adapter, and
paginated through `forge_api_paginate`, because the milestones endpoint is a LIST endpoint and a
plain GET silently truncates (the class #62 fixed for issues, already noted in `dep-auditor.md`).

### `check-phases.sh` (`forge-kit-roadmap`, shipped asset)

The guard, four rules. Exit 0 clean, 1 violation, 2 could not run, matching the leak scanners.
One line per violation naming the rule.

1. **Every open ticket has a milestone.** The rule that makes the untriaged set one query.
2. **Every `open` OR `done` phase has a plan file that exists and contains a "Fails if" section.**
   `done` is included to close a hole: a phase moved straight from `planned` to `done` would
   otherwise never have passed through the state where a plan is required.
3. **`roadmap.md` state and milestone state agree**, and **at most one phase is `open`**.
   `planned`/`open`/`backlog` map to an open milestone, `done` to a closed one.
4. **A phase marked `done` has no open tickets in its milestone.** This is also the circuit
   breaker, below: closing a phase forces every unfinished ticket to be moved somewhere explicit.

Rule 2 is file-only. Rules 1, 3 and 4 need the host. With no token available the host rules
report **SKIPPED loudly and never silently pass**, the posture `.githooks/pre-push` already takes
for a missing base ref: a check that cannot run must never report clean.

### `sync-phases.sh` (`forge-kit-roadmap`, shipped asset)

Makes the host's milestones match `roadmap.md`: creates what is missing, renames what changed,
closes what is `done`. `--check` reports disagreement and writes nothing.

**It never deletes.** A milestone that is not in the roadmap is reported and left alone, the same
rule and the same reason as `sync-labels.sh`: a milestone you did not declare may be holding
someone's tickets, and a sync that deletes what it does not recognise is a footgun aimed at other
people's data.

A malformed roadmap phase block **refuses the whole run** rather than skipping the entry, again
matching `sync-labels.sh`, because a silent partial sync is exactly the drift the guard exists to
end.

### `roadmap-phases` skill (`forge-kit-roadmap`)

The workflow: the states and what each means, the roadmap and plan templates, the close review, and
what to do when a phase needs splitting, reordering or deleting. It is the canonical statement of
every rule the guards enforce, and the guards' messages point at it.

### `/phase` command (`forge-kit-roadmap`)

One command with verbs, not four commands, to keep the marker, budget and index cost down.

- `/phase status` answers "is the current phase complete, and is it marked done in both places?"
- `/phase plan <name>` writes or reviews a phase's plan before it opens, and during.
- `/phase close <name>` is the close review: compare the plan against the tickets actually created,
  **file tickets for skipped or missing work and prioritise them**, then close the milestone AND
  update `roadmap.md`. Both, or the phase is not closed.
- `/phase triage` lists tickets with no phase, and backlog tickets worth promoting.

## No new agent

Deliberate. The judgment work here (reassess, split, reorder, decide what a gap means) is a
conversation with the maintainer, not an isolated verdict, so it belongs in the main session with
the skill injected. A second orchestrator agent would also be a second component of `ticket-gate`'s
size, and #150 records that the kit cannot currently afford the first one.

## What happens when a phase does not finish

The first draft had no answer, which is a real hole: the common case in a drifting project is not a
phase that completes but a phase that stalls.

**The default is to re-shape, never to extend.** Shape Up calls this the circuit breaker: a project
that does not ship in its cycle is cancelled by default rather than given more time, so the team
cannot spend multiples of the original appetite on something that needed rethinking first. The
reasoning transfers exactly, and the mechanism is already in rule 4: a phase cannot be marked `done`
while it holds open tickets, so closing one forces every unfinished item to be moved somewhere
explicit, which is either the next phase, a new phase, or `backlog`.

So a phase has three closing outcomes, and `roadmap.md` records which:

- **done**, the work landed;
- **re-shaped**, some landed and the rest moved, with the phase closed anyway and the remainder
  named;
- **abandoned**, the phase was a wrong turn, its tickets closed or moved, and the roadmap says why.

The third is the one people skip, and it is the one worth writing down: a phase deleted without a
record looks, six months later, like a phase that was never considered.

**Deliberately NOT adopted: an appetite.** Shape Up bounds a cycle by the time you are willing to
spend, which is what makes its circuit breaker fire on a schedule. This design has no dates by
choice, so the breaker fires on judgment at the close review instead. Adding an appetite later is
a small change; adding it now would import a time box nobody asked for.

## Bootstrap

The guard cannot pass before a roadmap exists, and this work itself needs a phase. So the order is:
write `docs/roadmap.md` and its phases, sync the milestones, assign the existing tickets, and only
then wire the guard into CI. The bootstrap is one-time and is called out because a guard wired
before its data exists fails every build and gets removed.

## Testing

Contract tests, in CI, matching how every other shipped executable here is tested.

- **`check-phases.sh`**: a stubbed `forge-lib.sh` beside a copy of the script (the `sync-labels.sh`
  pattern) plus throwaway directories for the file rules. Every rule gets a firing case AND a
  near-miss that must not fire, because these are refusal rules and a refusal rule fails by being
  too eager. The SKIPPED-without-a-token path gets its own case, since a check that silently passes
  is the failure mode that matters.
- **`sync-phases.sh`**: driven with a stub transport and a dry-run mode, touching no host. Covers
  create, rename, close, the never-delete rule, and the malformed-block refusal.
- **`forge-lib.sh` milestone primitives**: added to `scripts/test-forge-lib.sh`, including
  pagination termination on an empty page.

## Dogfooding

forge-kit adopts it, which also means forge-kit is the first project to install the new group: a
real `docs/roadmap.md`, real milestones, and all open tickets assigned. The
phase breakdown is proposed for the maintainer to correct, since the ordering is a judgment about
the project rather than about the design.

This is not ceremony. `block-dashes`, the size budget and the leak guard each found a real defect by
being run against this repo rather than described, and the leak guard's worst bug was found by the
hook it had just been wired into refusing its own commit.

## Consequences and costs

- **A new plugin group**, the kit's eighth, with its own `plugin.json` and a `marketplace.json`
  entry. `forge-kit-devops` also changes (the milestone primitives) and takes a semver bump.
- Five new components plus three contract suites (`check-phases`, `sync-phases`, group isolation),
  taking the kit from 21 CI suites to 24.
- `forge-adapt` must install the assets and the skill together; a shipped `assets/*.sh` is already
  handled, but the guard is useless without the skill that explains its refusals.
- **A project that declines the group loses nothing.** No other component references it, and the
  isolation guard is what keeps that true.
- A project that installs it but has no roadmap yet must not be broken either. `check-phases.sh` is
  opt-in by the presence of `roadmap.md`: no roadmap means nothing to check, and it exits 0 saying
  so, the same posture `check-private-leaks.sh` takes for a missing name list.

## Open questions

None blocking. The one item most likely to want revisiting after a real cycle is whether a phase
should carry an appetite, which would turn the circuit breaker from a judgment at the close review
into something that fires on its own.
