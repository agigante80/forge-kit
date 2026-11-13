# Phase plans

These files are forge-kit's own working records, not user documentation. Nothing here tells you how
to install or use the kit; for that, start at the [documentation map](../README.md).

Each file is the plan for one phase of the project, written when that phase opened and never before
(rolling wave planning, as the `roadmap-phases` skill describes it). A plan states the goal, what
"done" looks like, and a **Fails if** section written as a premortem. When the phase closes, the plan
gains a `## Close record`: what landed, what the premortem caught and what moved. The file names say
what the phase was about, often by the occasion that started it rather than by a subject, so do not
expect to find a topic by its filename.

## Where to look

[`docs/roadmap.md`](../roadmap.md) is the index. It lists every phase with its title and its state
(`planned`, `open`, `done` or `backlog`), and each phase that has started has a `plan:` line naming the file here. This page does
not repeat that table on purpose: only the roadmap is guarded by `check-phases.sh`, so a second copy
of the states would go stale at the next phase transition.

To find a plan, find its phase in the roadmap and follow the `plan:` line. To find the plan for a
ticket, open the ticket: its milestone names the phase.

A `README.md` in this directory is not a phase. The roadmap guards and the `/phase` command read a
plan only by the path a roadmap entry names, never by listing the directory.
