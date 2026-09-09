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
state: done
plan: docs/plans/guards-that-do-not-guard.md

Closed 2026-09-09, outcome **done**. All six tickets landed in the plan's order, nothing was moved
or abandoned, and the close review found no skipped work. Every fix was verified by mutation, and
mutation twice found a hole in a test written minutes earlier: a dropped `-H` that no case could
see, and a scoping assertion that passed even when the scope was ignored. That is the phase's own
"fails if" clause earning its place, not a coincidence.

One thing to carry forward. `check-restatements.sh` got STRICTER (an item naming several rules must
now scope each anchor), which the premortem named as the way this phase could go wrong. It was paid
immediately, by scoping three items in the real list, rather than left for the next reader to meet
as a surprise.

Every ticket in this phase shares one cause: a guard that is imprecise, or absent, or checking
something other than what it claims. #158 is the live one, and it was created BY changing the
workflow: both range guards are `pull_request`-only and this repo no longer opens pull requests, so
they now run on no path at all. The rest are the same shape found by review rather than by use.

They belong together because the fix for one is the argument for the fix for the next, and because
a guard suite whose members disagree about what they check is worse than a smaller honest one.

## Phase: The ticket-gate size decision
state: done
plan: docs/plans/ticket-gate-size.md

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

## Phase: Install scope, user level by default
state: done
plan: docs/plans/install-scope.md

Closed 2026-09-09, outcome **re-shaped**. All four tickets landed, and one acceptance criterion
of #166 did not: `drift` still reports a registered component as missing. It hit the same ratchet
that forced #166's rule into a script, so it moved to #167 rather than being squeezed in at 4am.
That is the circuit breaker working, not a shortfall.

The plan's premortem was right twice. It said the placeholder work must not become a ticket-gate
rewrite, and #163 stayed six lines while SHRINKING the gate. It said `scope: user` must not become
a lie, and a review round then found the scope guard and the placeholder guard contradicting each
other inside one CI job, which is that failure arriving by a route the plan did not name.

## Phase: Known gaps in shipped assets
state: done
plan: docs/plans/known-gaps.md

Closed 2026-09-09, outcome **done**. All six closed: #161, #167, #131, #134, #159 and #168, the
last of which did not exist when the phase opened. It was found by ARMING the overnight run against
this repo's own workflow, which the guard then made impossible; the phase's own subject is a shipped
asset whose behaviour is broader than it claims, and that is a textbook instance found by use rather
than by review.

#159 closed as working-as-intended by maintainer decision, with the limit documented beside the
reach statement it qualifies. The plan's premortem warned against closing a gap by narrowing the
claim quietly; this one is narrowed loudly.

Tickets filed at a review trip wire against components that already shipped. Each was reported as
LOW or latent, fixed nowhere, and recorded so the next reader would not rediscover it. They belong
together because they share a cause: a shipped asset whose stated behaviour is broader than what it
actually does.

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

## Phase: What the loop hands back to the human
state: done
plan: docs/plans/handing-back-to-the-human.md

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

## Phase: Backlog
state: backlog

Tickets whose home is not yet known. A decision to decide later, and visible as such.
