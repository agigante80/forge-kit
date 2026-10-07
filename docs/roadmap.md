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

A `done` phase keeps a one-paragraph summary here. Its full close record (what landed, what the premortem caught, what moved) is in its plan file, under **Close record**.

## Phase: Roadmap phases
state: done
plan: docs/plans/roadmap-phases.md

Closed 2026-09-08, **done** (#160). Added the phase as a shape larger than a ticket, as an optional plugin group. Lesson: three defects were found by running the guards rather than reading them.

## Phase: Guards that do not guard
state: done
plan: docs/plans/guards-that-do-not-guard.md

Closed 2026-09-09, **done** (#127, #138, #140, #142, #143, #158). Guards made to check what they claim, each fix verified by mutation; mutation twice caught a hole in a test written minutes earlier.

## Phase: The ticket-gate size decision
state: done
plan: docs/plans/ticket-gate-size.md

Closed 2026-09-09, **done** (#150, #103). A phase blocked on a maintainer decision, not on work: the tickets waited in the bucket and the plan was written from the decision.

## Phase: Install scope, user level by default
state: done
plan: docs/plans/install-scope.md

Closed 2026-09-09, **re-shaped** (#163 to #166). One acceptance criterion of #166 (`drift` on registered components) moved to #167 rather than being squeezed past the size ratchet.

## Phase: Known gaps in shipped assets
state: done
plan: docs/plans/known-gaps.md

Closed 2026-09-09, **done** (#131, #134, #159, #161, #167, #168). #168 was found by arming the overnight run against this repo, a shipped asset broader than it claimed, found by use.

## Phase: What the loop hands back to the human
state: done
plan: docs/plans/handing-back-to-the-human.md

Closed 2026-09-09, **done** (#88, #129). The two halves of one handover: the decision brief and what the loop returns.

## Phase: What Claude Code now ships itself
state: done
plan: docs/plans/what-claude-code-ships.md

Closed 2026-09-10, **done** (#169 to #175). Each hand-rolled piece was asked whether it still earns its place next to what Claude Code now ships.

## Phase: Standing next to the neighbours
state: done
plan: docs/plans/standing-next-to-the-neighbours.md

Closed 2026-09-10, **done** (#177 to #181). Five near-duplicates of wshobson/agents retired, 5,507 lines deleted, and the overlap guard added so it cannot recur.

## Phase: The unit the budget defends
state: done
plan: docs/plans/the-unit-the-budget-defends.md

Closed 2026-09-10, **done** (#176). Closed as a documented decision plus a reporting change, not as a move.

## Phase: The half that needs no Claude Code
state: done
plan: docs/plans/the-half-that-needs-no-claude-code.md

Closed 2026-09-10, **done** (#182, #183). The claim was narrowed until true: the rules and mechanical checks are portable, the judgement is not.

## Phase: The gate has never run here
state: done
plan: docs/plans/the-gate-has-never-run-here.md

Closed 2026-09-10, **done** (#184). Found that the repository shipping a ticket gate had never gated a ticket; gating every new ticket became the rule.

## Phase: Borrowing back from the on-ramp
state: done
plan: docs/plans/borrowing-back-from-the-on-ramp.md

Closed 2026-09-10, **re-shaped** (#185 to #188). #185 shipped outcome B and moved outcome A to #191, because two of A's constraints contradicted each other.

## Phase: The gate's own debt, and one contribution
state: done
plan: docs/plans/the-gates-own-debt.md

Closed 2026-09-11, **done** (#189, #192, #193). Each gated for exactly two rounds; three P3 follow-ups (#194 to #196) went to the backlog.

## Phase: Four small debts from the gate runs
state: done
plan: docs/plans/four-small-debts.md

Closed 2026-09-11, **done** (#197, #190, #194, #195). The first phase whose gate runs filed no follow-up ticket.

## Phase: What a push does not send
state: done
plan: docs/plans/what-a-push-does-not-send.md

Closed 2026-09-12, **done** (#198). Both gate rounds corrected a fact as first written; follow-up #199 to the backlog.

## Phase: One sentence, two pins
state: done
plan: docs/plans/one-sentence-two-pins.md

Closed 2026-09-12, **done** (#199). Round 1 caught Documentation impact saying None against two stale CLAUDE.md counts; follow-up #200.

## Phase: The sentence that matters more
state: done
plan: docs/plans/the-sentence-that-matters-more.md

Closed 2026-09-13, **done** (#200). The first hand-filed ticket to PASS the gate at round 1.

## Phase: A number the tree can check
state: done
plan: docs/plans/a-number-the-tree-can-check.md

Closed 2026-09-14, **done** (#201). The suite counts in CLAUDE.md became generated and checked; round 1's five blocking items each became a test case.

## Phase: A count claims completeness
state: done
plan: docs/plans/a-count-claims-completeness.md

Closed 2026-09-14, **done** (#202). A stale list is stale by omission, which is invisible, so every list now says "among them"; follow-up #203.

## Phase: The sweep the gate finished
state: done
plan: docs/plans/the-sweep-the-gate-finished.md

Closed 2026-09-14, **done** (#203). The gate found two live claims the sweep's grep could not see.

## Phase: The history the guard never read
state: done
plan: docs/plans/the-history-the-guard-never-read.md

Closed 2026-09-14, **done** (#191). The leak guard's `--history` mode; follow-ups #206 and #207 to the backlog.

## Phase: Four gaps found downstream
state: done
plan: docs/plans/four-gaps-found-downstream.md

Closed 2026-09-16, **done** (#205). The first ticket the fold-and-regate rule took to a PASS overnight; follow-up #213.

## Phase: What the tree modes could not read
state: done
plan: docs/plans/what-the-tree-modes-could-not-read.md

Closed 2026-09-16, **done** (#208, #209). Review found a tracked symlink followed under `--all`, fixed inside the phase.

## Phase: One definition that travels
state: done
plan: docs/plans/one-definition-that-travels.md

Closed 2026-09-16, **done** (#204). ticket-gate hands the project's own area-label set to the mechanics check; the gate itself filed #214 (nothing installs the doc).

## Phase: The host slot
state: done
plan: docs/plans/the-host-slot.md

Closed 2026-09-16, **done** (#212). `forge_host` stopped classifying any URL containing `@github.com/` as GitHub, with the #209 authority cut shipped alongside so the two parsers agree; follow-ups #215 and #216.

## Phase: What a mirror push sends
state: done
plan: docs/plans/what-a-mirror-push-sends.md

Closed 2026-09-17, **done** (#210, #211). `--history` reads every ref a mirror push sends, and rule C is linear; four tickets came out of the review loops, none dropped.

## Phase: A guard that can fire
state: done
plan: docs/plans/a-guard-that-can-fire.md

Closed 2026-09-17, **done** (#218). A CI step that could not fail for any input was deleted and its question moved to the push hook.

## Phase: What a downstream Forgejo found
state: done
plan: docs/plans/what-a-downstream-forgejo-found.md

Closed 2026-09-18, **done** (#216, #228, #229). Both round 2s that ran found defects in round 1's folded text.

## Phase: What seventeen repositories found
state: done
plan: docs/plans/what-seventeen-repositories-found.md

Closed 2026-09-18, unattended, **re-shaped** (#223 to #231, #233, #241). The leak guard's first rollout crop; #222 and #226 parked as decisions an unattended run does not make.

## Phase: The reviews' own crop
state: done
plan: docs/plans/the-reviews-own-crop.md

Closed 2026-09-23, unattended, **done** (#234, #235, #237, #239, #240). Survived a five-day rate-limit interruption mid-gate because every finished unit had already landed.

## Phase: The primitives roadmap management needs
state: done
plan: docs/plans/primitives-roadmap-management-needs.md

Closed 2026-09-23, **done** (#236, #245 to #247). The write halves (`forge_issue_milestone`, roadmap-lib's writer) and the doc-drift check the two workflows needed.

## Phase: Reviewing a phase, reassessing the roadmap
state: done
plan: docs/plans/reviewing-a-phase-reassessing-the-roadmap.md

Closed 2026-09-24, **done** (#196, #244, #248, #249, #258, #262, #266 to #268). `/phase review` and `/phase reassess`, which ran on this repository and fixed their own defects.

## Phase: Choosing a model and an effort on purpose
state: done
plan: docs/plans/choosing-a-model-and-an-effort.md

Closed 2026-09-24, **done** (#250 to #253, #278 to #281, #288, #289). Model tier and effort chosen per role and enforced; `/full-review` sizes its pipeline to the diff.

## Phase: What contributor-docs still cannot see
state: done
plan: docs/plans/what-contributor-docs-cannot-see.md

Closed 2026-10-01, **re-shaped** (#300, #301, #309, #398, #406, #408). #297 moved to its own planned phase and #302 to the backlog, both waiting on the maintainer.

## Phase: The gate's own correctness
state: done
plan: docs/plans/the-gates-own-correctness.md

Closed 2026-10-01, **done** (#320, #335, #347, #349, #409). The ticket-gate ratchet was lowered (5754 to 5742), not raised.

## Phase: Portable shell, everywhere
state: done
plan: docs/plans/portable-shell-everywhere.md

Closed 2026-10-01, **done** (#377, #379, #405, #407, #410). Each sweep closed its class with a guard, not a list; #412 to the backlog.

## Phase: Tests that can be believed
state: done
plan: docs/plans/tests-that-can-be-believed.md

Closed 2026-10-02, **re-shaped** (#219, #331, #360, #378, #404, #411, #413 to #415). The flakes' real cause was `printf | grep -q` under pipefail, now a guarded class; crashing mutants report as crashed.

## Phase: The leak guard, tightened
state: done
plan: docs/plans/the-leak-guard-tightened.md

Closed 2026-10-07, **done** (#403, #401, #222, #217, #206). Both scanners agree in any locale and from any directory, and share one history reader; #416 and #417 came out of it.

## Phase: Work with no decision left in it
state: open
plan: docs/plans/work-with-no-decision-left.md

Opened 2026-10-07 by the roadmap review that closed *The leak guard, tightened*. Every open ticket was checked against the tree that day: none was already done, about half wait on a maintainer pick, and the rest have their decisions recorded and only implementation left. This phase is that rest. Five of its tickets (#260, #290, #324, #327, #345) stopped at the gate's trip wire with the replacement text already named, and nobody applied it; #333 stopped at round 2 the same way; #214 and #412 were never gated. #214 leads because it is the only P2: a downstream project silently gets the nine compiled-in area labels instead of its own.

## Phase: The gate's own friction
state: planned
plan: 

A bucket, filed 2026-10-07 by the roadmap review. The ticket gate's two P2s and their neighbour, every pick recorded on the tickets on 2026-10-07. #263: every gate run leaks background poll loops, one held a verdict five days; a sentinel-gated Bash PreToolUse hook denies them (verified that day to fire on a subagent's own Bash calls), with no prose added to the gate. #286: Step 2.9's codebase-context cache is deleted, so every round re-explores, and items 2, 4 and 6 are mechanical; item 5 was dropped. #213: Step 0c reads a new `check-ticket-mechanics.sh --roles` dump for its synthesis targets. #277 closed as moot once the cache went. `ticket-gate.md` may not grow past its 5754 ratchet, so the plan says where each fix's words come from; the cache deletion pays for most of it.

## Phase: The leak guard's open questions
state: planned
plan: 

A bucket, filed 2026-10-07 from what *The leak guard, tightened* left, every pick recorded on the tickets on 2026-10-07. #417 leads: drop each timing row a structural row already kills, calibrate the rest per run. #416: the private name floor counts characters in every locale, and redaction keeps two whole characters. #207: the 38 historical `--history` findings, all verified placeholders, are allowlisted. #226: `skip` means literal-or-suffix in both halves and both parsers refuse `*` and `?` (never `[`), gated on the maintainer's audit of the downstream allow-files. #391: a new `marker [name]` allow-file entry kind.

## Phase: What a session loads before work begins
state: planned
plan: 

A bucket, split out 2026-10-01 when *What contributor-docs still cannot see* closed. #297 asks forge-kit to treat startup context (a project's CLAUDE.md, its transitive @-imports and the auto-memory MEMORY.md) as a budget, the way `check-component-size.sh` budgets component bodies. Its picks were recorded on 2026-10-07: a contract-tested shell asset plus a thin skill, called by `health-check` and `forge-adapt`; characters, warn at 40,000 and fail at 80,000, exit 1 over the fail level but wired into nothing by default; a `context-budget` marker in CLAUDE.md as the escape hatch; a shipped `--sweep <root>...` mode; R1 enforced and R2 to R10 in a `docs/guides` page; a report-only flag on any `##` section over 8,000 characters. R5, the edits to the components that write memory, is #418.

## Phase: Backlog
state: backlog

Tickets whose home is not yet known. A decision to decide later, and visible as such.
