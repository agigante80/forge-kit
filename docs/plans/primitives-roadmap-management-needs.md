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
