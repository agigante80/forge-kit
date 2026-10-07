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

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-09, outcome **done**. Both tickets landed in the plan's order, #88 then #129, and
nothing was moved or abandoned.

The premortem's sharpest clause fired, on the ticket it was written about. It said #88's whole
subject is what a loop does with no human present, so prose "reads as covered while being
unexecutable" there more easily than anywhere else. The review round then found exactly that: the
draft read the reviewed ref from `.full-review/state.json`, which is gitignored and per-worktree, so
the rule would have silently never fired and every round would have been round 1 again. That is the
failure it was written to prevent, found by asking where the file actually lives rather than by
reading the sentence again.

One thing the plan did not anticipate. #129 needed a new host primitive, `forge_issue_edit`, because
`forge-lib.sh` had no body-write at all and the ticket requires a rewrite rather than a comment. The
plan's Expected work listed only the skill. It was a small addition with its own tests, so it was
built rather than deferred, but the estimate was wrong in the ordinary way: the receiver existed and
the channel did not.

Carry forward: `check-restatements.sh` now scans `decision-brief/SKILL.md`. The skill promises to
run the gate rather than copy its bars, and that promise is now a build failure rather than a
sentence, which is the pattern this repo keeps converging on.

The kit runs work unattended and stops on rules of its own. Two moments in that are still
hand-waved: WHEN the loop stops without a human to ask, and WHAT it hands over when it does.

#88 is the first. The iteration contract says continuing past the trip wire is the caller's explicit
call and never a default, and an overnight loop has no caller present, so the only honest reading is
that it defers. #129 is the second: four tickets in one session each ended as a hand-written
decision brief, which is the artifact a deferral should produce.

They belong together because they are two halves of one handover, and either alone leaves it
half-built.
