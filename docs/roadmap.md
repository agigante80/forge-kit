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

## Phase: What Claude Code now ships itself
state: done
plan: docs/plans/what-claude-code-ships.md

Closed 2026-09-10, outcome **done**. All seven tickets landed, in the plan's order for the five it
was written for and then #174 and #175, which arrived after it was written. Nothing was moved or
abandoned.

The phase's premise was that our hand-rolled machinery might now be duplication with a guard on
top. The probes said otherwise three times, and each time the SHAPE of the answer was the same:
the first-party thing checks less than its help text suggests. `plugin validate` accepts an
unresolvable dependency and the installer then adds it silently. `plugin details` does not charge
an agent for what it preloads, which is the quantity #150 spent a phase establishing. `plugin tag`
validates an agreement that cannot fail here, because it fires only on a marketplace entry version
this repo deliberately does not keep. So nothing was replaced, three of ours were kept with the
reason written where the next reader meets it, and two of the seven turned into real work.

The premortem's first clause is the one that fired, and it fired in reverse. It warned against
adopting a finding because it exists rather than because it is better; what actually happened is
that every comparison came back in our favour, which is the same trap seen from the other side. The
guard against it was the same either way: run the probe, record its output, and let the answer be
whatever it is. #171 is the clearest case, since its own opening sentence turned out to be wrong.

Two things to carry forward. `scripts/test-validate-plugins.sh` now exists, so the kit's oldest
structural guard can grow rules that something proves fire. And the size budget finally measures
BOTH costs: the always-on half was invisible for the budget's whole life, and paying it down took
no compression at all, only deleting description sentences that each component's body already
carried.

A bucket, opened 2026-09-09 after probing the installed CLI (2.1.265) rather than reading its docs.
Several things this kit built by hand now exist first-party: a `dependencies` array in
`plugin.json` with a `prune` collector, `claude plugin tag` validating that a plugin's version and
its marketplace entry agree, and `claude plugin details` reporting a projected TOKEN cost per
component.

The question each ticket here answers is the same one: is our hand-rolled version still earning its
place, or is it now duplication with a guard on top? Neither answer is assumed. Some of ours is
stricter (a build failure, not a tag-time check) and some of it is simply older.

## Phase: Standing next to the neighbours
state: done
plan: docs/plans/standing-next-to-the-neighbours.md

Closed 2026-09-10, outcome **done**. All five tickets landed in the plan's order, guard first, and
5,507 lines were deleted.

**The premortem's fifth clause fired, on the ticket it was written about.** It warned against taking
the comparison as an instruction rather than as evidence, and `architect-review` is exactly that
case: the table said retire, and `/full-review` dispatches it by name, so retiring it would have
broken the one component the phase existed to protect. It stayed, allowlisted, with the reason in
the file. The sixth clause fired too, on the README: the first draft claimed 22 guards and 34 test
suites and was wrong on both, which is why criterion 8 asked for every number to be checked against
the tree.

**One thing went wrong that no clause named.** The overlap was measured before its SOURCE was
checked, so the first hour of this phase credited five near-duplicates to Anthropic when they are
wshobson/agents, the upstream forge-kit's specialist agents were forked from. It reached a public
README and two ticket bodies before `known_marketplaces.json` was read. The measurement was right
and the attribution was not, which is a distinct failure from the ones the premortem imagined.

Two to carry forward. `adapt` went 7314 to 7300 to 7209 in one day, every step through the #149
lever, which is now the fourth time converting prose to a tested script on that one file has been
the only way to add a rule to it. And the boundary is now checked in both directions: at build time
by `check-neighbour-overlap.sh`, and at install time by `forge-adapt-neighbour-disposition.sh`.

Opened 2026-09-10 after measuring this tree against the two installed official marketplaces and
superpowers. The kit's stated reason for existing is to complement them, and decision #69 draws the
line: superpowers owns the inner loop, forge-kit the outer.

That line is prose in a skill. Meanwhile `check-group-isolation.sh` fails the build if anything
outside the roadmap group so much as names it, to keep one optional group optional. The claim that
defines the project is the least enforced thing in the repository, and five components have already
crossed it: `tdd-orchestrator` (4 lines differ from the official file, of 185),
`backend-security-coder` (4 of 155), `pr-enhance` (6 lines of about 2,000 words),
`architect-review` (12 of 172) and `backend-architect` (13 of 320).

The counter-example is the one to protect. `full-review` shares an ancestor with wshobson's
`comprehensive-review` and diverged by 174 lines, and what diverged is the ITERATION CONTRACT: round
accounting, the trip wire, bad-fix injection, none of which the original has. That is outer-loop
discipline added to an inner-loop tool, and it is what this kit should be doing wherever it touches
a neighbour.

The attribution matters and was wrong for the first hour of this phase. `claude-code-workflows` is
`wshobson/agents`, a community collection and the upstream these agents were forked from;
`claude-plugins-official` is Anthropic's, and superpowers is distributed through it from
`obra/superpowers`. All five near-duplicates are wshobson's, not Anthropic's. The phase closes with
a README that says so, which is #181.

## Phase: The unit the budget defends
state: done
plan: docs/plans/the-unit-the-budget-defends.md

Closed 2026-09-10, outcome **done**. One ticket, and it closed the way the plan said it might: as a
documented decision plus a reporting change rather than as a move.

The classification is the whole result. Sixteen of `adapt`'s twenty fenced blocks are commands the
skill runs and four are templates it emits; none is reference material, so the splitting convention
forbids moving any of them and the file is the size the work is. The premortem's first clause was
the live risk throughout, and it did not fire because the classification came first, which is the
only reason it did not.

The phase also answers a question that had been open since #97 without being asked: the budget
counts words because the alternative units measure something this repo cannot act on. Lines are now
REPORTED beside them, marked against Anthropic's 500-line tip, and gate nothing.

Opened 2026-09-10 to work #176, which came out of the #172 ratchet raise: the thing `adapt`'s
ratchet defends is a WORD count, a unit nobody outside this repository uses, while the file is 820
lines against the only externally stated number, Anthropic's 500-line tip for a skill body.

The phase exists because the question is answerable and has never been asked properly. 277 of those
lines are fenced blocks, and whether any of them can move is a classification problem, not a
compression problem: the splitting convention forbids relocating a step the skill executes, and this
file is mostly steps.

## Phase: The half that needs no Claude Code
state: done
plan: docs/plans/the-half-that-needs-no-claude-code.md

Closed 2026-09-10, outcome **done**. Both tickets landed in the plan's order, gate then document,
and the claim is now narrower and true: the rules are portable and the mechanical checks are
portable, and the judgement is not.

**The phase paid for itself the moment the entry point could be pointed at a real ticket.** Running
it against this repository's own issues found that EVERY one of them fails or refers every
mechanical check, because no body carries the `template-version` marker and none uses the `###`
headings the checker matches. That is #184, filed to the backlog rather than absorbed here: it is a
defect in how the gate and the tree fit together, not in making the portable half usable, and
extending a phase to swallow a new finding is the thing this method exists to refuse.

The premortem's first two clauses were the live risks and neither fired. Nothing new was written
that `check-ticket-mechanics.sh` already does, and the entry point prints no verdict, with tests
that fail if either ever changes. Two guards fired instead, both correctly: the group-isolation
guard on a comment naming the optional roadmap group, and the template-dir-order guard on the
seventh copy of the resolution order, which is the documented cost of resolving a template
directory outside the agent.

Opened 2026-09-10. The kit calls itself AI-agnostic at the governance layer, and #181 had to write
down what that actually means today: the templates, `labels.yml`, `docs/guides/ticket-standards.md`
and ten shell assets are portable, and **nothing enforces any of them** for a team not using Claude
Code. The gate, the hooks, the size budget and drift detection are all components.

The gap is narrower than it looks, which is why this is a phase rather than an ambition.
`check-ticket-mechanics.sh` is plain shell with 41 contract tests and already does Step 3A;
`forge-lib.sh` already fetches an issue on either host without `gh` being assumed. What is missing
is a door between them, and one document to point another agent at. AGENTS.md exists but tells an
agent how to CONTRIBUTE to forge-kit, which is the opposite of the question.

## Phase: The gate has never run here
state: done
plan: docs/plans/the-gate-has-never-run-here.md

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

## Phase: Borrowing back from the on-ramp
state: done
plan: docs/plans/borrowing-back-from-the-on-ramp.md

Closed 2026-09-10, outcome **re-shaped**. All four tickets closed, one of them by splitting: #185
shipped its outcome B and moved outcome A to #191, because the gate found that two of A's own
constraints contradict each other.

**The phase was overwhelmingly about the gate rather than about the borrowings.** Its three tickets
took six gate runs between them, and produced five defects that were in none of them: #188 the label
taxonomy, which blocked every ticket in this repository and shipped inside the phase; #189 the stale
plugin-cache resolution, confirmed by three separate runs; #190 the checker failing five times on a
`##` body where its own rule says refer once; #192 the gate's verdict region being erasable by an
ordinary body edit, which silently prevents the trip wire from ever firing; and a stale test count in
CLAUDE.md.

**Two of the three borrowings would have shipped wrong.** #186's premise check, written as shell
greps, would have been DENIED by this kit's own overnight guard whenever a ticket quoted a
destructive command, recording a destructive-command deferral that never happened. #187's boundary
had two independent holes, and the second needed no strained reading: the prohibition it leaned on
lives inside one review dimension and does not govern a general rule placed elsewhere.

The premortem's first clause held: fourteen prompts were compared and eleven refused as subjects the
neighbours own.

**The stopping decision is the thing to carry forward.** Gating stopped at two rounds per ticket
under the bounded iteration contract, with everything unfixed becoming a ticket. Both round 2s found
defects in the round-1 fix, which is one round of fix-induced findings and one short of the trip
wire. Continuing would have been the move the rule exists to refuse.

Opened 2026-09-10 after a content comparison against `agigante80/vibe-coding-prompts`, the sister
project and the on-ramp: prose prompts pasted into any assistant, where this kit installs components
and fails builds. The two have traded mechanisms before, the generated index and the version-bump
gate both came from there, and this is the third trip.

Three rules that collection states and this one does not. One of them, the leak guard's blindness to
history, is a defect in a shipped security component rather than a missing feature: `--all` means
`git ls-files`, so a home path committed and later deleted is invisible to the guard written for the
moment a repository goes public.

The discipline here is in what was refused. Fourteen prompts were compared and eleven are subjects
the neighbours own, one day after #178 retired eleven components for being exactly that.

## Phase: The gate's own debt, and one contribution
state: done
plan: docs/plans/the-gates-own-debt.md

Closed 2026-09-11, outcome **done**. All three tickets landed in the plan's order, #189 then #192
then #193, each gated for exactly two rounds under the bounded contract, and nothing was moved or
abandoned. Three P3 follow-ups went to `backlog` (#194, #195, #196), which is the "third crop" the
premortem named, at a size that does not change the verdict on gating.

**Three premortem clauses fired, and two of them fired in the gate rather than in the code.** The
tests-with-their-blindness clause was exact: #193's round 2 showed that the fixture the ticket
named for its contains-match mutant (`"build failed"`) does not kill it, and only Forgejo's own
`"Has been cancelled by admin"` does; the shipped suite carries that string because the gate
asked. The Option A clause held because the critic REPRODUCED the walk's false green under a
server-clamped page before anyone had to argue about it. The `none` clause held by writing both
`release` branches out in full, which is the only form that could be checked.

**One raise, one refusal.** `ticket-gate` grew past its ratchet for #189 and the baseline was
raised 5709 to 5773 by maintainer decision, the #147 shape; #192 then added more and was paid for
entirely by cuts, six restated sentences in the file, so the second ask was never made.

**The finding underneath is about running gates in parallel.** Three gate runs in one session
shared a scratchpad, and two of them read a body file the third had overwritten; both caught it
from the evidence column and re-fetched, but the collision is a gate-process defect the phase
did not own. Recorded here rather than fixed, and worth a ticket if it recurs.

**Verified live, with one honest gap.** `count-gate-rounds.sh` read round 3 on all three gated
issues and round 1 on a never-gated one, against the real forge. The new Step 1 resolver was
dry-run three times against this machine's five copies and chose the same v5 copy each time, and
the gate's own runs saw the old `head -1` return a stale v4 copy again. What has NOT happened is a
gate run driven by the NEW agent prose: the installed plugin is the old version until the
marketplace updates, so every run this phase used a per-run override instead. The first unforced
run is the remaining evidence.

Opened 2026-09-11 to pay for what the first live gate runs left behind, plus one fix that arrived
from downstream. Three signals are reading wrong, each in the direction that stops you looking:
Step 3A resolves its checker with `head -1` and picked a stale plugin-cache copy in three of four
runs (#189); the gate's only durable output can be erased by an ordinary body edit, so the trip wire
can never fire (#192); and on Forgejo `forge_ci_status` calls a superseded run a failure and a
not-yet-started one `not_configured` (#193), wrong on 23 of 39 red commits in the sample the ticket
measured. #193 is a contribution: the fix and its 24 tests have run downstream since 2026-08-28, and
what forge-kit has to decide is which of the two designs to port and what the vocabulary change does
to `release`.

The last phase closed with more gate tickets than it opened with. This one is where they get paid,
and the premortem says what happens if gating them produces a third crop.

## Phase: Four small debts from the gate runs
state: done
plan: docs/plans/four-small-debts.md

Closed 2026-09-11, outcome **done**. All four landed in the plan's order, #197, #190, #194, #195;
nothing moved or abandoned, and for the first time a phase's gate runs filed no follow-up ticket.
Seven runs: two PASS at round 1 (#197, #195), two NEEDS-WORK twice (#190, #194) and stopped
there, with the remainder folded in as ticket text rather than a round 3.

**The gate changed the design of the largest ticket, and it was right.** #190 was implemented as
"detect one heading level per body, `###` wins a mixed one"; round 1 found that `dep-auditor`
emits `### Priority` beside `##` sections, so that rule inverted the kit's own producer exactly as
v5 had. The label-bounded rule replaced it (a section runs to the next heading at its own level
or the next heading that is a template label), and round 2 found the own-level clause had no case
that killed its removal. Both rounds paid for themselves. #194's round 1 found the ticket's own
proposed fix printed `mechanics: none ()` rather than `mechanics: none`.

**The second premortem clause fired, as written.** The plugin cache was updated to 0.16.2 before
the phase opened, and every gate run still reported executing `ticket-gate` v51: the CLI's
"restart to apply" is literal, and this session never restarted. So every `**Round:**` and
`mechanics:` line in this phase's reviews was still produced under a per-run instruction, and the
new Step 1 prose remains unexercised by any real run. That is now two phases carrying the same
gap, and the first action of the next session is to run one gate with a bare number.

**The ratchet moved in the direction the rule wants.** #197 and #194 were paid from restated
sentences and the baseline was LOWERED 5773 to 5767 to lock in what was left, the first lowering
since the third raise the same morning.

Opened 2026-09-11 for what the twelve gate runs of the last two phases left on the board, none of
it large and all of it in the gate's own machinery: the checker failing five times on a `##` body
where its own rule says refer once (#190, found by the gate reviewing #186); the provenance line
printing `mechanics:  ()` on the empty path and a home path in every review (#194, from #189's
round 2); a stale `<sha>` in `adapt`'s description of the cache leaf (#195, the same round); and
three concurrent gate runs sharing one body file by name (#197, which bit twice in the last phase
and was caught both times by luck). This phase is also the first one whose tickets are gated by
the NEW agent prose without a per-run override, which is the evidence the last close said was
still owed.

## Phase: What a push does not send
state: done
plan: docs/plans/what-a-push-does-not-send.md

Closed 2026-09-12, outcome **done**. One ticket, two gate rounds, one follow-up (#199, pin the new
header sentence) to `backlog`. Both rounds caught something in the facts as first written: round 1
that "GNU grep prints nothing" was an artefact of a `-I` wrapper in the session that observed it,
and round 2 that the prune step deletes the stash stack six lines after the prose said stashes are
kept. The second is the premortem's "written as a ritual" clause, fired by the gate rather than by
a reader, which is the order this repository wants.

Opened 2026-09-12 for one prose ticket, #198, the half of #191 that needs no stream reader. The
decision brief on #191 found three facts worth stating whatever happens to the history mode: a
push never sends orphaned objects (tested on a throwaway repository), the pre-publish prune step
that deletes them is standard, and `grep` over a `cat-file --batch` stream prints nothing rather
than zero without `-a`. #191 itself stays in `backlog` waiting on a probe of BWK awk on a real Mac,
which is written into its body.

## Phase: One sentence, two pins
state: done
plan: docs/plans/one-sentence-two-pins.md

Closed 2026-09-12, outcome **done**. One ticket, two gate rounds, one follow-up (#200, the history
sentence, same shape) to `backlog`. Round 1 found the one thing the plan's fourth premortem clause
named: Documentation impact said "None" against the two `CLAUDE.md` counts, the same drift that "docs: the public leak
suite has 80 cases, not 72" fixed (a commit since purged from history, #232), again. This phase's gate runs were also the first on the installed v55 agent, and they confirmed
what three earlier phase closes could not: the round is counted from posted comments (round 2 read
as 2) and the mechanics line names its script with a `~`-relative path and its marker.

Opened 2026-09-12 for #199, the follow-up #198's close filed: the `grep -a` sentence that phase
added to both scanner headers is pinned by no test, where the public scanner's other reach
sentences are. One ticket, two suites, one line each, and the `CLAUDE.md` counts that go with them.

## Phase: The sentence that matters more
state: done
plan: docs/plans/the-sentence-that-matters-more.md

Closed 2026-09-13, outcome **done**. One ticket, one gate round (PASS first time, the first hand-filed
ticket here to do so), no follow-up filed. Two of the gate's advisories were taken: two needles per
suite rather than one, since `gitleaks` is named twice in the public help and would have broken the
exactly-once mutation property, and the private suite's comment that #199 wrote the day before,
which said "only" and would have been false by the afternoon. One mutation run survived on the
first pass, and it was the mutation that was wrong, not the test: the private header spells its
pointer in lowercase and the mutant was case-sensitive. The gate's third advisory, a mechanical
check on `CLAUDE.md`'s hand-maintained suite counts after two round-1 findings on them, is left as
a question for the maintainer rather than a ticket.

Opened 2026-09-13 for #200, the follow-up #199's close filed. Same shape as the last phase, for
the sentence the leak guard's whole limit rests on (#185).

## Phase: A number the tree can check
state: done
plan: docs/plans/a-number-the-tree-can-check.md

Closed 2026-09-14, outcome **done**. One ticket, two gate rounds. Round 1 raised five blocking
items and all five were right: the Python suite reports on stderr and would have read as zero, the
anchor as first written would have rewritten `24 downstream tests` on line 97, and the contract
test's real-repo case would have run the generator inside its own test. Each became a premortem
clause and then a test case. The gate filed #202 itself (line 19's spelled-out counts), which is
the one ticket that appeared. Mutation found three gaps in the first draft of the suite: the
last-line rule was untested because the noise line matched no shape, `testers` was not a near
miss of `tests`, and the `scripts/` confinement was reachable only by symlink. The generator was
not changed for any of them; the test was.

Opened 2026-09-14 for #201, filed from #200's gate advisory after two round-1 findings on the same
hand-maintained numbers, and after running the suites found three more stale. The component index
shape (#96), applied to a number inside prose.

## Phase: A count claims completeness
state: done
plan: docs/plans/a-count-claims-completeness.md

Closed 2026-09-14, outcome **done**. One ticket, two gate rounds, one follow-up (#203, the single
phrase the promised sweep found) to `backlog`. Round 1 corrected the ticket's own reasoning: I had
written that a stale name list is visible where a stale count is not, and the gate showed the
list on line 19 was stale by OMISSION (18 of 40 named), which is invisible, so every list now
carries "among them". Round 1 also widened the scope to lines 90 and 145 and README line 8, the
same defect in the same files. Round 2's one item was in round 1's fix (the ticket's own QA and
docs-impact fields had not followed the widened scope); it was folded into the body and no third
round was run, per the two-round stop. Defect-in-prior-fix count for the phase: one.

Opened 2026-09-14 for #202, the gate's own follow-up from #201: the counts the generator cannot
anchor, spelled out or split by a rule nothing defines, come out of the prose rather than getting
a second generator.

## Phase: The sweep the gate finished
state: done
plan: docs/plans/the-sweep-the-gate-finished.md

Closed 2026-09-14, outcome **done**. One ticket, two gate rounds, no follow-up. Round 1's one
blocking item was the ticket's premise: it said the sweep had found "exactly one live claim
left", and the gate found two more in the same file ("six copies", "six sites", against a guard
printing 7), because the sweep's grep had looked for a number before a component noun and
`copies` and `sites` are neither. Round 2 PASS. The lesson is the same as #202's, one level up: a
sweep that reports completeness is itself a count claiming completeness. The next sweep starts
from the two accurate-today README phrases the plan names, not from zero.

Opened 2026-09-14 for #203. The sweep #202 promised, with the two phrases the gate found that my
grep had not.

## Phase: The history the guard never read
state: done
plan: docs/plans/the-history-the-guard-never-read.md

Closed 2026-09-14, outcome **done**. One ticket, one gate round on the rewritten body (fifteen
items, folded, no third gate run), then a review loop: two reviewers in round 1, one in round 2 on
the fix commit alone, stopped there. Two follow-ups to `backlog` (#206, one copy of the reader;
#207, what this repository says about its own history). The premortem's "a foreign store was read
as this one" clause fired, and it was drawn too narrowly: the reviews found five inputs the tool
does not control (a corrupt object, user git config, a newline in a filename, refs/replace, an
interrupted pipeline) each turning a reachable leak into a silent exit 0, where the plan had named
only alternates and the two environment variables. The lesson for the next scanner premortem is to
enumerate every input the tool does not control, not the obvious ones. What the substitute for a
Mac found that no document would have: Apple's awk aborts the moment a regex meets a byte over
0x7F under glibc's C locale, which became the design rule that no content or path byte goes
through a regex. Two tickets from elsewhere (#204, #205) arrived without a milestone during this
phase and were put in `backlog` so rule 1 would pass; where they belong is a maintainer decision.

Opened 2026-09-14 for #191, outcome A of #185, after the maintainer chose to ship without a Mac:
the probe was run against Apple's own awk source built on Linux, the suites under bash 3.2.57
built the same way, and the README states what that does and does not prove.

## Phase: Four gaps found downstream
state: done
plan: docs/plans/four-gaps-found-downstream.md

Closed 2026-09-16, outcome **done**. One ticket, two gate rounds (overnight, the first ticket the
fold-and-regate rule took to a PASS), two review rounds, one follow-up (#213, the 0c synthesis
target keyed on a field id) to `backlog`. The premortem's first clause fired in review: the marker
regex admitted a shape it should not have, twice, and both were caught before shipping. What the
plan did not name: running the suite with Apple's awk found a fifth defect older than the four,
BWK awk refusing a newline in a `-v` value, so on a Mac every section of every ticket had read as
empty. The substitute verification from #191 is now a habit for shipped shell, and it earned its
keep on the second use.

Opened 2026-09-16 for #205, the first ticket the overnight run took through fold-and-regate to a
PASS. Four heuristic misses in the mechanics script, found by running it on another project.

## Phase: What the tree modes could not read
state: done
plan: docs/plans/what-the-tree-modes-could-not-read.md

Closed 2026-09-16, outcome **done**. Two tickets, both gated to PASS (one with its last item
folded at the two-round stop), one implementation commit and two review rounds, no follow-up.
Work that appeared: round 1 found a pre-existing false negative the plan had not named, a tracked
symlink followed rather than read as its text under `--all`, and it shipped inside the phase since
the new `-r` test had turned it into a refusal. The premortem's third clause fired in review: a
signal-killed child made the shell print the script's path, and the test had hidden it with its
own trap; and its first clause almost fired, a gitlink whose commit is present being scanned as
text. Round 2's finding was the shape #191's substitute verification keeps producing: a fix that
worked on one bash and not the other, with no test on the platform CI runs.

Opened 2026-09-16 for #208 and #209: the audit's finding that the older tree modes, the ones the
hooks run, had fail-open paths the new history mode did not.

## Phase: One definition that travels
state: done
plan: docs/plans/one-definition-that-travels.md

Closed 2026-09-16, outcome **done**. One ticket, two gate rounds (the second overnight, the
maintainer's fold-and-regate rule), two review rounds, no new follow-up: #214 (nothing installs
the doc) was filed by the gate itself during round 2. The premortem's first clause fired in
review: the table read ended only at `###`, so a `##` section after it widened the set, and a
present doc with no table fell back to the nine where the folded spec said refer. Round 2 then
found two defects in the parity rule added to fix that. The pattern across the last three phases
is steady: round 1 finds the change's holes, round 2 finds the fix's, and the two-round stop with
tickets for the rest is holding.

Opened 2026-09-16 for #204: the area set is one definition here (#188) and none where the gate
is installed, because nothing hands it to the mechanics script.

## Phase: The host slot
state: done
plan: docs/plans/the-host-slot.md

Closed 2026-09-16, outcome **done**. One ticket, two gate rounds, two review rounds, two
follow-ups to `backlog`: #215 (adapt's copy of the globs, a ratcheted file) and #216 (`forge_repo`
keeps its own parser). Work that appeared and shipped inside: the authority cut in the #209 parser
(`/` alone, where a query before the first slash moved the host), because the two parsers must not
disagree on what an authority is. The premortem's third clause fired, in the review rather than
the tests: the credential fix would have been undone by lowercasing, since git's store keys on the
spelling as given; the helper now preserves case and only the compare lowercases.

Opened 2026-09-16 for #212: the adapter every forge-touching component trusts decided the host
with a glob that reads `github.com` anywhere after an `@`.

## Phase: What a mirror push sends
state: done
plan: docs/plans/what-a-mirror-push-sends.md

Opened 2026-09-16 for #210 and #211, the last two tickets from the #191 security audit, and
**done** on 2026-09-17 with both shipped. #210 widened `--history` to every ref a mirror push
sends; #211 made rule C linear, which took three changes rather than the one it opened with.

The close review's interesting part is what the phase produced that it did not expect. Both
premortem clauses fired and were caught by the process rather than by luck: the gate found three
fixtures in #210's first draft that passed against the unfixed scanner, and review round 1 found
the same shape in #211's private half, where the path-map line could be reverted with the suite
still green. Four tickets came out of the two review loops rather than out of the plan: #217
(`redact` is quadratic on the default `--history` path), #219 (a timing case that flaked once in
nine runs), #218 (three guards enforce nothing in CI since the assistant files stopped being
published), and the cosmetic evidence-picker item the #210 gate named, which was folded into #218's
neighbourhood rather than filed on its own. All four are in Backlog with a phase, none dropped
silently, which is what rule 4 exists to check.

One thing the plan did not foresee at all: another session untracked `CLAUDE.md`, `AGENTS.md` and
`.claude/` mid-phase and left the build red, so repairing three guards and restoring the local
memory store happened inside this phase without being part of it.

## Phase: A guard that can fire
state: done
plan: docs/plans/a-guard-that-can-fire.md

Opened and **done** 2026-09-17 for #218. After the assistant files stopped being published, one CI
step could no longer fail for any input; the phase deleted it and moved the question to the push
hook, where the doc actually lives.

The close review's finding is that the premortem named the right failure and the first fix walked
into it anyway. **Fails if** clause one was "the rule went in below the base-ref exit and is
silently skipped"; gate round 2 caught exactly that in the ticket, and review round 1 then found
that the suites could not tell the difference, since every case ran with `origin/main` intact. Two
rounds of two different mechanisms were needed to close one hole, which is the argument for running
both. Clause three, "a test asserted wall time and flaked", was avoided by sentinel files, and the
cost clause drove the whole shape: 93 s for the battery against 0.035 s for the hook is why
`--changed` exists.

Three tickets came out of the two loops (#219, #220, #221) and one more was filed from the gate's
advisory about `ticket-standards.md` rule 8. All are in Backlog with a phase, none dropped.

## Phase: What a downstream Forgejo found
state: done
plan: docs/plans/what-a-downstream-forgejo-found.md

Closed 2026-09-18, outcome **done**. All three tickets landed, in the order #216, #228, #229
rather than the plan's #228 first, because #228's second gate round was still running when #216
passed and the loop had nothing else gated. Two of the three took the full two gate rounds and
both round 2s found defects in round 1's folded text; #216's round 2 passed. Each implementation
had a review round 1, and only #216 needed a round 2 (one Medium, fixed, then clean). Five
follow-ups went to `backlog` from the gates and reviews: #233 (the mechanics script FAILS rather
than refers on a one-line GWT bullet), #234 (three prose drifts, among them
`forge-call-mapping.md` still mapping a body edit to a raw PATCH), #235 (an scp-form
`user:token@` prefix reaches stdout as a slug), #236 (the paginator's end-of-list line, and GNU
`timeout` in the suite). This was an unattended run: the maintainer was asleep from the plan's
confirmation to the close, with merge-to-main authorised in advance.

**The premortem's first clause fired in the gate, exactly as written.** #228's AC2 asked for the
short-page stop that `forge-lib.sh` line 298 rejects, the gate struck it in round 1, and round 2
then found what no reading had: three existing cap fixtures repeat a byte-identical page to drive
the cap, so the stop turned them red. The gate prototyped the change and ran the suite (84 of 86)
before saying so, which is the kind of evidence this repository wants a round to carry. The
second clause, "identical was byte-identical", fired in the same round and became the
volatile-field case. The fifth clause is the one that stands unresolved: the reproduction host is
a private Forgejo this checkout may not touch, so the live check is still owed by the session
that found the bug, and the close records that rather than assuming it.

**What the run learned about running the gate in parallel.** Three gates and a review ran at
once without the body-file collision #197 fixed, and one gate disclosed its own fault: it called
`forge_issue_edit 228 --body-file <path>` where the function takes the body as `$2`, so the
issue body was the literal string `--body-file` for under a minute before the gate restored it
from its prepared file. `forge-call-mapping.md` does not list that function's signature, which
is how the wrong shape got through; it is in #234.

Opened 2026-09-18 for #228 and #229, the two defects a forge-adapt refresh on a private downstream
repo (Forgejo 11.0.16) found in `forge-lib.sh` v16, plus #216, the parser follow-up #212 left in
the same file. Both bugs fail in the direction that stops you looking: the comments paginator
spins to its 500-page cap on a host that ignores `page`, so `count-gate-rounds.sh` waits seventeen
minutes and then reports `unknown` on every Forgejo gate run, and the three silenced writers say
nothing at all on a 404, so a comment to a wrong issue number looks like success. Neither has a
workaround, and the first breaks the round count #192 made durable.

## Phase: What seventeen repositories found
state: open
plan: docs/plans/what-seventeen-repositories-found.md

Opened 2026-09-18, unattended, for the crop of the leak guard's first rollout: on 2026-09-17 the
two scanners were installed in seventeen public repositories and run in every mode, and the
findings were filed as #222 to #227 and #230, with #231 and #233 from reviewing that work. Every
one is a place where the scanner's behaviour is narrower, broader or louder than its own
documentation says: a short identity token that matches inside ordinary words (#222, the one P2,
and the one with a workaround that is the guard being switched off), a redaction marker read as a
home root after the very rewrite that removed the leak (#227), `/home/` inside a relative import
(#230), the scanner's own doc comments tripping a host project's guard (#223), a `root` key that
accepts a dead entry (#224), `skip` globs whose `*` crosses `/` (#226), two facts about the private
half's `skip` missing from SKILL.md (#225), and this repository carrying the scanner twice (#231).
They belong together because each was found by USE rather than by review, in the shape the
component was named for, and because a guard that cannot be silenced precisely is a guard that
gets removed.

## Phase: Backlog
state: backlog

Tickets whose home is not yet known. A decision to decide later, and visible as such.
