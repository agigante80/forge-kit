# Plan: The primitives roadmap management needs

Phase opened 2026-09-23. The maintainer asked for roadmap and phase management to be the highest
priority, in its own phases, and for the tickets to be organised so the work can start at once. He
was not present when this plan was written, so the premortem below is mine and is recorded as an
assumption for him to correct.

## Goal

The three things a roadmap or phase review must DO, and the one thing it must not be noisy about,
exist as tested primitives before either review is written.

## Done looks like

- `forge_issue_milestone <issue> <title|"">` sets and clears a ticket's phase on both hosts,
  resolving the title the way labels are resolved, refusing an unresolvable one rather than
  clearing the field, and speaking on a 404 (#245). The kit can move a ticket between phases on
  Forgejo, which it never could.
- `roadmap-lib.sh` can WRITE the roadmap as well as read it: set a phase's state, insert, rename,
  reorder, remove, each preserving every byte of prose it did not mean to change, each refusing a
  malformed file whole, and none of them able to produce a file `parse_roadmap` rejects (#246).
- `check-doc-drift.sh` answers "which tracked documents did this range of commits make stale" as a
  check with a contract test, excluding the generated regions whose own `--check` owns them, and
  reporting rather than failing a build (#247).
- The paginator's end-of-list line is settled one way or the other (#236), because a review that
  reads every ticket's comments turns one line per call into one line per ticket.
- Every one of them is gated before implementation, reviewed under the bounded loop, and merged to
  `main` on its own commit, so an interruption costs at most one ticket.

## Fails if

Premortem, mine rather than the maintainer's: it is the end of this phase and it failed badly.

- **The milestone writer was written against GitHub and stubbed for Forgejo.** The two hosts address
  a milestone by different fields, which `forge-lib.sh` line 642 already records and `sync-labels.sh`
  learned the hard way. If the Forgejo path is only ever exercised by a stub, the first real use is
  the test, and the downstream session is the one who finds out.
- **The roadmap writer reflowed the prose.** A phase block's prose is the record of why the phase
  exists and, once closed, the close review. A writer that normalises whitespace or reorders keys
  would pass every parse-back test and quietly destroy the thing the file is for. The `cmp`-based
  cases are not ceremony; they are the point.
- **The writer produced a file its own parser accepts and a human cannot read**, which is the same
  failure wearing a passing test.
- **The doc-drift check became a build gate** and was argued with, then switched off. This
  repository has made that mistake's inverse decision twice already (#174, #176): report the
  number, do not budget it.
- **The phase shipped primitives nobody could use**, because the two reviews turned out to need a
  different shape. The mitigation is that #244 and #249 are already written down in detail, and
  each primitive's acceptance criteria quote the step of the workflow that needs it.
- **It grew.** The temptation is to write the review while the primitive is fresh. The review is
  the next phase, and this one is done when four tickets are closed.

## Expected work

#245, #246, #247, #236, in that order: the two writers first because everything is blocked on them,
the check third, the noise decision last because it is the smallest and its answer may change once
a review exists to be noisy.

## Out of scope

- #244, #248, #249 and #196: the next phase, `planned` and named.
- #220 (the bash 3.2 and Apple awk harness): this phase ships three new shell assets and the
  portability claim applies to each, but the harness is a project-wide gap and pulling it in here
  would make this phase about something else. Every new asset avoids bash-4 idioms and says so.
- #219 (the timing flake) and everything else in `backlog`.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Opened 2026-09-23 at the maintainer's request, who asked for roadmap and phase management to be the
highest priority and to have its own phases. Two workflows he runs by hand, often, have no component
in this kit: a mid-phase alignment review (#244) and a whole-roadmap reassessment (#249). Writing
either first would have produced a component that cannot act, because two write halves are missing
and the third piece is a check nobody has written: nothing in the kit can SET a ticket's milestone,
so every phase move this repository has ever made went through `gh issue edit` and is GitHub-only
(#245); `roadmap-lib.sh` is a parser with no writer, so reshaping the roadmap is a hand edit and a
second component would be the format's second definition (#246); and the README question the
maintainer keeps having to ask by hand is a comparison of two path sets and two timestamps, which is
a check rather than a reading (#247). #236 joins them because the reviews amplify it: a review reads
every ticket's comments, so a per-call stderr line becomes a per-ticket one.

This phase ships no user-facing workflow. That is deliberate: the two workflows are the next phase,
and they are written against primitives that already exist rather than invented alongside them.

**Closed 2026-09-23. Outcome: done.** All four tickets landed in the planned order, each gated,
each reviewed under the bounded loop, each merged to `main` on its own commit. `forge-lib.sh` v23
(`forge_issue_milestone`, and `FORGE_DEBUG` for the paginator), `roadmap-lib.sh` v4 (seven write
primitives, not the five the plan named: `/phase review` needs to rewrite a phase's PROSE when
scope changes, and a reassessment needs to write the reason for a refocus, so `set_plan` and
`set_prose` were added), and `scripts/check-doc-drift.sh`.

**Two of the premortem's five failures were live and were caught by review rather than by design.**
"The roadmap writer reflowed the prose" nearly happened: round 2 found that `reorder` was not
byte-reversible on a roadmap whose last phase runs to EOF, because a blank line between phases
belongs to the POSITION and not to the block, and blank lines are not a parsed field, so the
writer's own parse-back check could not see it. "The milestone writer was written against GitHub and
stubbed for Forgejo" is half true and is the phase's one open debt: the Forgejo path is exercised
only by a stub here, its review found two Mediums in exactly that area, and the live run is still
owed by the session that holds a real Forgejo. #254 and #256 came out of the same ground.

**What the plan did not expect is the eight tickets the work produced**, which is the close review's
real content. Seven went to `backlog` (#254, #255, #256, #257, #259, #260, #261) and one to the next
phase (#258), because it decides whether the check this phase shipped is usable by the reviews that
consume it: a dry run over three ranges of this repository reported 3, 6 and 3 rows, and every row
was a line that merely NAMES a churning path rather than claiming anything about it.

**The discipline the plan asked for held.** "It grew" was the last premortem item, and the phase
closed on exactly the four tickets it opened with; everything else was filed rather than absorbed.
