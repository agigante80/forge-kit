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

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-09, outcome **done**. Both tickets landed, #150 then #103, in the plan's order and
for the plan's reason: #103 is pure addition and doing it first is how the phase would have ended
with a bigger problem than it began.

The phase found that the question was wrong before it found an answer. The metric measured one file
while an agent PRELOADS every skill it declares, so the true figure was 6355 and every option in
#150 had been costed against a false number. The baseline was RE-DERIVED to 6355, which is not a
raise, and then genuinely reduced to 5778: the companion's read-once artifacts moved into
`references/`, which are not preloaded, and the round table paid for itself out of a duplicate
pointer. No capability was dropped to reach it.

The premortem was right about the shape of the danger and wrong about where it would come from. It
warned against raising the ceiling quietly; the ceiling was raised LOUDLY, as a stated orchestrator
number with its reason in CLAUDE.md, which is the thing the premortem asked for. What it did not
foresee is that the number being enforced was false, so the phase's first act had to be fixing the
measure rather than arguing about the target.

Two things to carry forward. The orchestrator row is MECHANICAL (an agent whose `tools:` declares
`Agent`), so it cannot rot into a list, and today it selects `ticket-gate` alone. And the ratchet
outlived the ceiling: at 5778 against a 6000 ceiling the file finally has headroom, and the ratchet
is now the only thing holding it, which is exactly the arrangement the policy intends.

`ticket-gate.md` was 5265 words against a 3000 ceiling and the compression lever was exhausted. This
phase was blocked on a maintainer decision rather than on implementation, which is exactly what a
planned phase is for: the tickets sat in the bucket until the decision was made, and the plan was
written from the decision.
