# Plan: The gate has never run here

Phase opened 2026-09-10, written from #184 plus the evidence gathered before the plan, because the
ticket's central question had two possible answers and only one of them describes work.

## The answer, established first

**The gate is sound. It has simply never been run on this repository's tickets.**

- Step 0c auto-synthesis triggers on exactly the condition every ticket here meets (no
  `template-version` marker), merges the missing sections, **writes the enriched body back to the
  forge with `gh issue edit`**, and only then proceeds to 0b and Step 3A. So when the gate runs, the
  mechanics are fed a template-shaped body, and the "every FAIL is a blocking item" rule holds.
- The gate has never run here. Scanning the last 30 issues, **not one carries a gate review
  comment**, and the only two bodies containing the string `template-version` contain it in prose.

So `forge-gate-mechanics.sh` reporting all fails against a raw hand-filed body is CORRECT, and it
does not contradict the blocking rule: that rule only ever applies inside a gate run.

## Goal

Record that answer where the next reader meets it, stop the entry point reporting one fact as seven
failures, and decide what to do about the finding underneath it: the repository that ships a ticket
gate has never gated a ticket.

## Done looks like

`forge-gate-mechanics.sh` says "this body was never template-shaped" once, rather than failing every
section check. The answer is written into the script and the guide rather than living in a closed
ticket. The dogfooding gap is a ticket of its own, or a recorded decision not to close it.

## Order, and why

The evidence came first and is above. Then the entry point's reporting, because that is the only
code change. Then the documentation, because it describes what the code now does. The dogfooding
question is last and separate: it is a decision for the maintainer, not a fix.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The checker was loosened.** The temptation is to make the section checks tolerant of `##`
  headings or of a missing marker. That would defeat them for tickets that ARE gated, which is the
  only case they were written for, and #149's whole argument is that a check which guessed rejects
  compliant tickets. The fix belongs in the ENTRY POINT's reporting, not in the checks.
- **The new report claims more than it knows.** "Never template-shaped" is an inference from two
  signals (no marker, no `### ` headings). A body could carry the headings and no marker, or the
  reverse. If the message states more certainty than those two signals support, it will be wrong in
  public on someone else's repository.
- **The dogfooding finding got fixed quietly by gating a few tickets.** Running the gate on this
  repo's backlog would rewrite issue bodies through `gh issue edit`, on tickets that are already
  closed and already implemented. That is a destructive act dressed as tidying, and it is not what
  this phase is for.
- **The answer was recorded only in the ticket.** #170, #176 and #180 all went out of their way to
  put a decision where the next reader meets it. A finding this counter-intuitive, that the tool
  disagreeing with the gate is the tool being right, will be re-derived within a month if it lives
  in a closed issue alone.

## Expected work

#184, plus one new ticket for the dogfooding gap if the maintainer wants it closed rather than
recorded. The second may be a decision.

## Out of scope

- Gating this repository's existing tickets. See the premortem.
- Any change to `check-ticket-mechanics.sh`'s checks.
- Making the gate itself synthesise differently.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-10, outcome **done**. One ticket, plus the decision the finding forced.

The answer was the reassuring branch: Step 0c synthesises a body and writes it back to the forge
before Step 3A sees it, so the blocking rule holds inside a gate run and #184 was a reporting
problem rather than a defect. The premortem's second clause then fired on the fix: a mutant swapping
`&&` for `||` in the shape test survived until cases existed for a body with headings and no marker,
and a marker with no headings. Claiming more than two signals support is exactly what that clause
warned about.

**The finding underneath became a workflow decision.** This repository ships a ticket gate and had
never gated a ticket. From 2026-09-10 every NEW ticket is gated before implementation; the closed
backlog is not retro-gated, because Step 0c would rewrite the bodies of work already shipped. That
makes the gate's auto-upgrade path something this repo will actually exercise rather than only
document, which is the same correction #104 made for the label taxonomy.

Opened 2026-09-10 to work #184, whose central question was answered before the plan was written
because only one of its two answers described work.

The gate is sound: Step 0c synthesises a body and writes it back to the forge before Step 3A sees
it, so inside a gate run the mechanics get template-shaped input and the blocking rule holds. What
the evidence shows instead is that **the gate has never run on this repository's tickets**: not one
of the last thirty issues carries a gate review comment, and the only bodies containing
`template-version` contain it in prose.

That makes #184 a reporting problem rather than a defect, and leaves a separate finding underneath
it: the repository that ships a ticket gate has never gated a ticket.
