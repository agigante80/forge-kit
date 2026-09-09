# Plan: The ticket-gate size decision

Phase opened 2026-09-09, written from the roadmap prose plus what the metric fix (#150's first half)
now makes measurable.

## Goal

Decide what `ticket-gate` should cost, against a number that is true, and act on the decision.

## Done looks like

#150 closed with a decision recorded in CLAUDE.md rather than as an exemption, and #103 unblocked
and either implemented or explicitly re-scoped.

## What changed before this phase opened

The metric was measuring one file. Verified against the installed Claude Code, an agent PRELOADS
every skill it declares, so `ticket-gate` has been loading 6355 words all along, not 5259, and
#109's split reduced nothing real. **Every option in #150 was previously being costed against a
false number.** That is why this phase opens now and could not have opened before.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The decision was to raise the ceiling, quietly.** A stated higher number with a stated reason is
  defensible; an exemption that grows is what a ratchet becomes when nobody wants to say the number
  out loud. If the answer is "orchestrators may cost more", CLAUDE.md has to say the number and why.
- **Auto-synthesis was dropped to hit a target.** It is roughly 560 words and it is why pre-v6
  tickets stay reviewable without manual upgrades. Trading it for a number is a real capability loss
  and must be argued as one, not slipped in as tidying.
- **Scripting was used a fifth time on something that is not mechanical.** The lever worked four
  times this week because each rule was deterministic. Applying it to the critic's brief or to a
  judgment rule would move prose into a file that cannot test it, which is worse than leaving it.
- **#103 got implemented against the old shape.** It is pure addition to a component whose size
  question is unresolved; doing it first is how the phase ends with a bigger problem than it began.

## Expected work

The decision is the work. Implementation follows from it, and #103 follows from that.

## Out of scope

- Re-opening #159, decided this phase.
- The two Backlog design tickets, #129 and #88.
