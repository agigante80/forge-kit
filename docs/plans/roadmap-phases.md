# Plan: Roadmap phases

Phase opened 2026-09-08. Spec: `docs/superpowers/specs/2026-09-08-roadmap-phases-design.md`.
Implementation plan: `docs/superpowers/plans/2026-09-08-roadmap-phases.md`.

## Goal

Give forge-kit a unit of work larger than a ticket, as an optional plugin group, and prove it by
running it on forge-kit itself.

## Done looks like

`forge-kit-roadmap` is installable and declinable. `docs/roadmap.md` exists, every open ticket has
a phase, and `check-phases.sh` exits 0 against this repo with the host rules actually running rather
than skipped. A project that declines the group loses nothing, and a guard proves it.

## Fails if

Written as a premortem: it is the end of this phase and it failed badly. What happened?

- **The guards became something to work around.** Every one of the four is a refusal, and a refusal
  that fires on legitimate work gets bypassed and then deleted. The near-miss cases in both suites
  exist for this and are the ones to keep adding to.
- **The group turned out not to be optional.** Somebody added one convenient reference from
  `ticket-gate` or `forge-adapt`, and the methodology became mandatory in practice while remaining
  optional on paper. `check-group-isolation.sh` is the answer, and it already caught one violation
  on its first run.
- **The roadmap became a second copy of the ticket tracker.** If phase membership is ever recorded
  here as well as on the host, the two drift and the design's central claim is void.
- **Nobody ran it.** The system was built, dogfooded once, and then not used, which is how it would
  end up describing a method rather than enforcing one. The test is whether the next phase opens
  and closes through `/phase` rather than by hand.

## Expected work

Eight tasks in the implementation plan. Tasks 1 to 7 shipped (`1c762f0` through `b358dc7`), Task 8
is this bootstrap.

## Out of scope

- An **appetite** per phase, and a circuit breaker that fires on time rather than at the close
  review. Considered and deliberately deferred: it would import a time box nobody asked for. Revisit
  after one real cycle.
- Teaching `ticket-gate` about phases. Never, unless it is a separate decision with its own ticket.
- Deep-segment path detection in the leak guard (#159), which is unrelated and sits in Backlog.
