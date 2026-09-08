# forge-kit roadmap

Rolling wave planning. This file owns **which phases exist and what state each is in**; the host
owns **which phase each ticket is in**, as the milestone. Different facts, so neither duplicates the
other. `plugins/forge-kit-roadmap/skills/roadmap-phases/SKILL.md` is canonical for the rules, and
`check-phases.sh` enforces four of them.

**Tickets closed before this file existed (everything up to #157) carry no phase, by decision on
2026-09-08.** Backfilling them would invent a plan that was never made. Rule 1 governs open tickets,
so the guard is right to ignore them, and reopening one would correctly require a phase.

Only the `open` phase carries commitment. A `planned` phase's prose below is a reason, never a
promise, and it is a bucket: file tickets against it as they occur to you, and its plan gets written
from the roadmap prose plus whatever has accumulated by the time it opens.

## Phase: Roadmap phases
state: done
plan: docs/plans/roadmap-phases.md

Closed 2026-09-08, outcome **done**. Nothing moved or abandoned. The close review found one piece
of skipped work (#161, the group's undeclared dependency on `forge-lib.sh`) and one thing worth
recording: three defects were found by running the guards rather than reading them, including the
isolation guard failing on its own first run against this tree.

The kit governs tickets, releases and hosts, and has no shape larger than a ticket. This phase adds
one, as an optional plugin group so that a project using any other method loses nothing.

## Phase: Guards that do not guard
state: open
plan: docs/plans/guards-that-do-not-guard.md

Every ticket in this phase shares one cause: a guard that is imprecise, or absent, or checking
something other than what it claims. #158 is the live one, and it was created BY changing the
workflow: both range guards are `pull_request`-only and this repo no longer opens pull requests, so
they now run on no path at all. The rest are the same shape found by review rather than by use.

They belong together because the fix for one is the argument for the fix for the next, and because
a guard suite whose members disagree about what they check is worse than a smaller honest one.

## Phase: The ticket-gate size decision
state: planned

`ticket-gate.md` is 5265 words against a 3000 ceiling and the compression lever is exhausted. This
phase is blocked on a maintainer decision rather than on implementation, which is exactly what a
planned phase is for: the tickets sit in the bucket until the decision is made, and the plan is
written from the decision.

Research done for #150 found that the companion-skill split never reduced what the agent actually
reads, so the metric may be measuring the wrong quantity. That is an input to the decision, not a
substitute for it.

## Phase: Install scope, user level by default
state: planned

The kit installs into a project by copying, and CLAUDE.md already says the opposite is better:
plugin registration "owns no user config and so has no wiring to drift, duplicate, or clobber, and
that copy-and-mutate path was the origin of every hook bug in this repo's history." The preference
is stated and not followed, because nothing makes it followable.

The blocker turns out to be small. A component pinned to one project is one with a value baked in at
INSTALL time; one that resolves at RUNTIME is already correct everywhere. The kit has exactly one
install-time placeholder, `{{GITHUB_REPO}}`, with six live uses across two files, and `forge_repo`
already replaces it at runtime elsewhere in those same files.

This phase is a bucket while the current one runs. Its plan gets written from this prose plus
whatever has accumulated by the time it opens, and the honest question it will have to answer is
whether forge-adapt's adaptation is doing as much work as its description claims.

## Phase: Backlog
state: backlog

Tickets whose home is not yet known. A decision to decide later, and visible as such.
