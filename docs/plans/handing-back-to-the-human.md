# Plan: What the loop hands back to the human

Phase opened 2026-09-09, written from the roadmap prose plus the two tickets that had accumulated
in the Backlog bucket, #88 and #129.

## Goal

Make the two moments an autonomous loop must stop at mechanical: when to stop, and what to hand over
when it does.

## Done looks like

`working-overnight` names delta chaining and defer-on-trip-wire in its pipeline, so an unattended
review loop cannot continue past the trip wire on its own; and a `decision-brief` skill exists that
re-gates a stalled ticket, costs its options, and produces the artifact a deferral hands over.

## Why these two are one phase

They are the two halves of the same handover. #88 decides WHEN the loop stops and refuses to decide
for the human. #129 is WHAT it hands over when it does. Shipping either alone leaves the handover
half-built: a loop that defers correctly into an unreadable ticket, or a brief nobody reaches
because the loop never stops.

The evidence is this repo's own record. The trip wire has fired five times, and the four tickets
that motivated #129 (#94, #102, #103, #120) each ended as a hand-written version of that artifact.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **`decision-brief` became a second ticket-gate.** The ticket already names this and reverses two of
  its own design points to avoid it: the brief RE-GATES rather than citing a stored verdict, because
  a verdict written before the standard moved describes a standard that no longer exists. If the
  brief ends up carrying a COPY of the gate's bars in its prose, this phase produced the exact
  restatement drift #125 exists to catch.
- **The skill grew a judgment it is not entitled to.** It costs options; it does not choose. A brief
  that arrives with the decision already made is worse than no brief, because it is read as analysis.
- **#88 was written as prose nobody can check.** Its whole subject is what an unattended loop does
  without a human, so "the pipeline says to defer" is exactly the kind of claim that reads as covered
  while being unexecutable. If it cannot be tested, it must at least be stated where the loop reads
  it every cycle, not in a reference the cycle never opens.
- **The trip wire got a bypass.** The contract says continuing past it is the caller's explicit call
  and never a default. An overnight loop has no caller present. Any wording that lets the loop decide
  it is fine to continue defeats the ticket.
- **The phase was opened to have an open phase.** Both tickets are P2 design work that sat in Backlog
  on purpose. If the work turns out to want a maintainer decision first, the honest move is to say so
  and re-shape, not to implement something to close a milestone.

## Expected work

- #88: `working-overnight` passes `--since` when re-reviewing a target from an earlier cycle, and
  parks a trip-wire stop in `decisions.md` with the loop's stopping data rather than continuing.
- #129: the `decision-brief` skill in `forge-kit-governance`.

Order: #88 first. It is smaller, it is the one currently running unattended in this repo, and #129's
output is what #88's defer path hands over, so building the receiver before the sender would be
guessing at the shape.

## Out of scope

- Changing the iteration contract itself (#66). This phase makes an unattended caller honour it.
- Any new review lane. The trip wire's rules are the ones already written.
