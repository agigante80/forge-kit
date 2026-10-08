# Plan: Work with no decision left in it

Written 2026-10-07 by the roadmap review that closed *The leak guard, tightened*. Every open ticket
was verified against the tree that day (body, comments and the files named). Of 24, none was
already done, about half wait on a maintainer pick, and the rest have their decisions recorded and
only implementation left. This phase is that rest. The decision-blocked tickets went to the planned
phases they belong to, so this phase can run without stopping to ask.

## Goal

Land every open ticket whose decisions are already recorded, without reopening a decision and
without restarting a gate loop that already stopped.

## Done looks like

- `forge-adapt templates` installs `labels.md`, `labels.yml` and `sync-labels.sh` beside the
  ticket-standards doc, never clobbering an existing one, and `adapt` does not grow past its 7147
  ratchet (#214).
- `closing-sessions/scripts/memory.py` opens both the memory file and the index without following a
  symlink or blocking on a FIFO swapped in after the ownership check (#324).
- `roadmap-lib.sh` has zero `awk -v` values and the #405 ratchet in `test-roadmap-lib.sh` is 0
  (#412); a phase name is validated and a plan-less block no longer dies (#260); the #328 review
  Lows in `reassess-phases.sh` are fixed (#345).
- The tier-diff and guard-lib frontmatter rules agree on CRLF and on an absent key versus a literal
  `-` (#290); the forge-adapt host-probe suite extracts a bounded block and cannot re-enter itself
  (#327); the forge-host and sync-labels test-pinning Lows are pinned (#333).
- Every ticket above is closed against a named commit, and `Validate` is green on `main` after each.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **A decision leaked in after all.** One of these turned out to need a maintainer pick (#214's
  never-clobber posture against an existing `labels.md`, or #290's assumption that CRLF installs
  are supported), and it was implemented on a guess that then had to be undone.
- **The gate loop restarted.** #260, #290, #324, #327 and #345 each stopped at the trip wire with
  the replacement text named. Someone ran round 4 instead of applying that text and implementing,
  and the phase spent its time reviewing prose.
- **#214 grew `adapt`.** The install step went into SKILL.md rather than `references/`, the
  exemption ratchet failed the build, and the fix was to raise the baseline, which an agent must
  never do on its own.
- **The three roadmap-lib tickets collided.** #412, #260 and #345 all edit `roadmap-lib.sh`; their
  line references drifted, one ticket's tests pinned the other's intermediate state, or the #405
  ratchet was lowered and then raised again.
- **#324 fixed half the write path.** `O_NOFOLLOW` went onto the memory file and missed the index
  writes (`memory.py` around lines 87 and 93), the half the round-3 gate named explicitly.
- **The neighbours came along.** #351 sits beside #324 and #340 beside #260, and both need
  maintainer picks; folding either in "while we are there" is the leak the first clause names.

## Expected work

In order:

1. **#214** (P2), never gated: gate it first. It leads because it is the only P2. A downstream
   project silently gets the nine compiled-in area labels instead of its own.
2. **#324**, the closing-sessions write path: apply the round-3 text (relabel the optional GWT
   blocks, the equivalent mutant, an index-write-open test, rebase on #329), then implement with no
   round 4. It is the one security-labelled ticket, so it goes early.
3. **#412**, never gated: recount with `awkv_count` first, since its line list is from 110832a.
4. **#260**: apply the one-sentence leading `-` rationale the round-3 gate named, then implement.
5. **#345**: apply the round-3 wording to item 1, Steps note 1 and AC1, then implement.
6. **#290**: apply the round-3 fix (the no-op control runs after the `late-first-rule` mutant and
   captures `mutant()` output), then implement.
7. **#327**: settle line 32 so `extract_block()` replaces the `-n` guard and add the
   `HOST_SUITE_CHILD` re-entry guard, then implement.
8. **#333**: replace the 4b mutant with the hoisted echo, name both README generated hunks, rebase
   the version numbers (`forge-lib` is v33), then implement.

## Out of scope

- **The gate's own friction** (#263, #286, #213): *The gate's own friction*, picks recorded
  2026-10-07; #277 closed as moot.
- **The leak guard's open questions** (#416, #207, #226, #391, and #417):
  *The leak guard's open questions*.
- **The startup-context budget** (#297): *What a session loads before work begins*.
- **Tickets near this phase's files** (#351, #302, #261) and the re-scope (#272): `backlog`, picks
  recorded 2026-10-07; #351 lands after #324. #340 closed, resolved by the roadmap condensation.

## Close record

Closed 2026-10-08, outcome **done**. All eight planned tickets landed, one or two commits each, in
the planned order where it mattered (the three `roadmap-lib.sh` tickets ran strictly in sequence)
and in parallel worktrees where the files did not overlap: #412 (4aa4927), #324 (48b7a63), #260
(570d229), #214 (39475f0), #327 (48f44f3), #345 (75eb6b6, d2bcc11), #290 (03ae037, 41a2e3f) and
#333 (bc96b0e). `Validate` was green on `main` after each. Every review's Lows were filed rather
than folded in, one ticket per review: #421 to #424 and #426 to #429, all in `backlog`. #214 also
filed #425, a gap it found rather than a Low: a project with `ticket-gate` but without Templates
mode still falls back to the compiled-in nine area labels.

The premortem, clause by clause. **No decision leaked in.** #290's CRLF and `(absent)` choices were
already on the ticket; #214's round-2 gate came back NEEDS-WORK with specification gaps only, which
were applied without a third round, and the agent took the stricter reading of its input contract
(both `LABEL_AREAS` and `FORGE_HOST` required) rather than asking. **No gate loop restarted:** the
five trip-wired tickets and #333 had their named text applied and went straight to implementation;
only the two never-gated tickets were gated, #214 twice and #412 once. **`adapt` did not grow:** it
shrank from 7150 to 7147 and the baseline was lowered with it. The plan's own "7199" was wrong
from the day it was written (the real baseline was 7150), the same stale-number class #214 fixed in
passing. **The roadmap-lib tickets did not collide:** each refreshed its line references against
the previous landing, and the #405 ratchet stayed at zero throughout. **#324 fixed both halves:**
the memory file and the index are opened through one `O_NOFOLLOW | O_NONBLOCK` helper for `write`
and `remove`. **The neighbours stayed out:** #351 was not folded into #324, and #423, the #260
review's leftovers, was not folded into #345.

Two things the plan did not foresee. A gate critic ran `rm -rf tmp/*` and wiped the shared `tmp/`
while other agents were using it; every later agent got its own `tmp/<ticket>` directory, and the
incident is recorded on #419, whose daytime matcher would have caught it. And #333's first
`test-forge-lib.sh` run reported one unidentified failure that no rerun reproduced; it is not
counted as a finding because nothing named the case.

Out of the phase: #421 to #429 go to `backlog`.
