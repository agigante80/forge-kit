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
| `planned` | no | open | **no** | declared and ordered, not started |
| `open` | **yes** | open | yes | in progress |
| `done` | yes | closed | yes (all closed) | finished, closed in both places |
| `backlog` | no | open | yes | the permanent holding phase; never closes |

**`planned` to `open` is the mechanical form of "the plan is written at the beginning of the
phase".** The transition is the moment a plan becomes required, so the rule is a state change a
script can refuse rather than a habit someone has to remember.

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
- **Fails if.** What would make this phase a failure rather than an unfinished success. Required,
  and checked for, because a plan that only says what finishing looks like cannot tell you to stop.
- **Expected work.** The tickets this phase anticipates needing. Not binding: the close review
  compares this against what was actually created, and the difference is the interesting part.
- **Out of scope.** With the phase each deferral goes to, or `backlog`.

## Components

Five pieces, in two plugin groups.

### `forge_milestone_*` in `forge-lib.sh` (`forge-kit-devops`)

`forge_milestone_list`, `forge_milestone_create`, `forge_milestone_update`, `forge_milestone_close`,
and `forge_issue_set_milestone`. None exist today. Host-aware like the rest of the adapter, and
paginated through `forge_api_paginate`, because the milestones endpoint is a LIST endpoint and a
plain GET silently truncates (the class #62 fixed for issues, already noted in `dep-auditor.md`).

### `check-phases.sh` (`forge-kit-governance`, shipped asset)

The guard. Exit 0 clean, 1 violation, 2 could not run, matching the leak scanners. One line per
violation naming the rule.

1. **Every open ticket has a milestone.** The rule that makes the untriaged set one query.
2. **Every `open` OR `done` phase has a plan file that exists and contains a "Fails if" section.**
   `done` is included to close a hole: a phase moved straight from `planned` to `done` would
   otherwise never have passed through the state where a plan is required.
3. **`roadmap.md` state and milestone state agree**, and **at most one phase is `open`**.
   `planned`/`open`/`backlog` map to an open milestone, `done` to a closed one.
4. **A phase marked `done` has no open tickets in its milestone.**
5. **No open tickets assigned to a `planned` phase.** The mechanical form of "tickets are not
   created for the whole roadmap at once". Precise rather than a judgment call, because `planned`
   is a declared state and not an inference.

Rule 2 is file-only. Rules 1, 3, 4 and 5 need the host. With no token available the host rules
report **SKIPPED loudly and never silently pass**, the posture `.githooks/pre-push` already takes
for a missing base ref: a check that cannot run must never report clean.

### `sync-phases.sh` (`forge-kit-governance`, shipped asset)

Makes the host's milestones match `roadmap.md`: creates what is missing, renames what changed,
closes what is `done`. `--check` reports disagreement and writes nothing.

**It never deletes.** A milestone that is not in the roadmap is reported and left alone, the same
rule and the same reason as `sync-labels.sh`: a milestone you did not declare may be holding
someone's tickets, and a sync that deletes what it does not recognise is a footgun aimed at other
people's data.

A malformed roadmap phase block **refuses the whole run** rather than skipping the entry, again
matching `sync-labels.sh`, because a silent partial sync is exactly the drift the guard exists to
end.

### `roadmap-phases` skill (`forge-kit-governance`)

The workflow: the states and what each means, the roadmap and plan templates, the close review, and
what to do when a phase needs splitting, reordering or deleting. It is the canonical statement of
every rule the guards enforce, and the guards' messages point at it.

### `/phase` command (`forge-kit-governance`)

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

forge-kit adopts it: a real `docs/roadmap.md`, real milestones, and all open tickets assigned. The
phase breakdown is proposed for the maintainer to correct, since the ordering is a judgment about
the project rather than about the design.

This is not ceremony. `block-dashes`, the size budget and the leak guard each found a real defect by
being run against this repo rather than described, and the leak guard's worst bug was found by the
hook it had just been wired into refusing its own commit.

## Consequences and costs

- Two plugin groups change, so both take a semver bump.
- Five new components plus two contract suites, taking the kit from 21 CI suites to 23.
- `forge-adapt` must install the assets and the skill together; a shipped `assets/*.sh` is already
  handled, but the guard is useless without the skill that explains its refusals.
- A downstream project with no roadmap must not be broken by this. The guard is opt-in by the
  presence of `roadmap.md`: no roadmap means nothing to check, and it exits 0 saying so.

## Open questions

None blocking. The fifth rule was proposed by the implementer and accepted by default rather than
by explicit choice; it is the one item most likely to want removing after a real cycle, and removing
it is deleting one check and its tests.
