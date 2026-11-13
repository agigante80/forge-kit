# Design specs and implementation plans

These files are forge-kit's own working records, not user documentation. They are the paper trail
left by the superpowers brainstorming and planning flow: a **spec** is the design that was agreed
before a component was built, and a **plan** is the task-by-task implementation plan written from it.
Nothing here tells you how to use the kit; start at the [documentation map](../README.md).

Read one before redesigning the component it describes. Each is a record of a day, so its counts,
group names and file lists describe the tree as it was then; the tree and the guides are the
current truth.

The directory keeps its name because other files cite its paths.

## Status

- **shipped**: the component exists in the tree and is wired in.
- **superseded**: a later design replaced it.
- **abandoned**: it was dropped.
- **in progress**: the work it plans is still going.

Each status was checked against the commit history and the tree, not copied from the file's own
header, which was written before the work started.

## Specs

| Spec | Date | Status | What it designs |
|---|---|---|---|
| [`closing-sessions` skill](specs/2026-07-11-closing-sessions-skill-design.md) | 2026-07-11 | shipped | A skill that saves what mattered from a session to project memory and a dated handoff note before it ends. Shipped in `forge-kit-governance`. |
| [`working-overnight` bundle](specs/2026-07-11-working-overnight-design.md) | 2026-07-11 | shipped | Governed unattended work: a skill plus a Stop hook, landing as branch and pull request, never merging. Shipped in `forge-kit-governance`. |
| [`overnight-guard` hook](specs/2026-07-11-overnight-guard-design.md) | 2026-07-11 | shipped | A hook that denies destructive commands while an overnight run is armed. Shipped in `forge-kit-governance`. |
| [Ticket standard improvements](specs/2026-07-16-ticket-standard-improvements-design.md) | 2026-07-16 | shipped (part 1 only) | Part 1, the ticket standard (issue #73), shipped as template version 5. Part 2, a CI documentation-currency gate, was never approved or built; `scripts/check-doc-drift.sh` (#247) later took on the same need as an advisory report. |
| [Portability audit of the catalogue](specs/2026-08-27-portability-audit.md) | 2026-08-27 | shipped | A static audit classifying every component by what binds it to Claude Code (issue #81). It is a finished report, not a component. |
| [Roadmap phases](specs/2026-09-08-roadmap-phases-design.md) | 2026-09-08 | shipped | Rolling wave planning as a plugin group: a roadmap file owns the phases, the host owns each ticket's phase. Shipped as `forge-kit-roadmap`. |

## Implementation plans

| Plan | Date | Status | What it plans |
|---|---|---|---|
| [`closing-sessions` skill](plans/2026-07-11-closing-sessions-skill.md) | 2026-07-11 | shipped | The tasks that built the skill and its `memory.py` helper. |
| [`working-overnight` bundle](plans/2026-07-11-working-overnight.md) | 2026-07-11 | shipped | The tasks that built the skill, its references and the `overnight-continue` hook. |
| [`overnight-guard` hook](plans/2026-07-11-overnight-guard.md) | 2026-07-11 | shipped | The tasks that built the fail-closed command guard. |
| [`forge-kit-roadmap` plugin group](plans/2026-09-08-roadmap-phases.md) | 2026-09-08 | shipped | The eight tasks that built the roadmap skill, its guard and sync scripts and the `/phase` command. |
| [Documentation overhaul](plans/2026-10-30-documentation-overhaul.md) | 2026-10-30 | in progress | The work packages that turn the public documentation into a landing page, reference pages and community files (umbrella ticket #572). |
