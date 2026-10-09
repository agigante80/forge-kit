# Plan: What a session loads before work begins

Written 2026-10-09, when *The leak guard's open questions* closed. The bucket was split out
2026-10-01 when *What contributor-docs still cannot see* closed, and holds two tickets: #297 (P2,
the measurement) and #418 (P3, its rule R5). Both were read with all their comments and checked
against the tree on 2026-10-09 at a24b76a. #297 has ten comments, the last of them the maintainer's
seven picks of 2026-10-07; #418 has none. Neither is done and neither is superseded. **Neither is
gated at a PASS**: #297 holds a clarification-needed gate comment from before the picks and its
body has not been rewritten to them, and #418 was never gated and its acceptance criteria read "to
be written when the phase opens". Nothing in the bucket is waiting on a decision, so despite the
size of #297 this phase is two tickets and one new component.


**Status at opening (2026-10-09, overnight run).** #297's body was rewritten to the picks that
night (previous body preserved on the ticket) and gated three times, all NEEDS-WORK; rounds 2 and 3
each found a defect in the previous round's fix, so the run stopped on the trip wire rather than
forcing a fourth. Round 3's three one-clause changes are listed on the ticket and in the run's
decisions file. The phase therefore opens with nothing ready to implement: #297 waits for the
maintainer to accept the folded-in fixes and re-gate, and #418 waits for #297.

## Goal

A project can see, from one command, how many characters its next session loads before the first
prompt, and the two components that write into that startup context cannot grow it unseen.

## Done looks like

- A contract-tested shell asset in `forge-kit-devops` reports, for one repository, the characters
  in `CLAUDE.md` plus its transitive `@`-imports (resolving files only, none inside a code span or
  block, four hops, each file once) plus the auto-memory `MEMORY.md`, each as its own line item.
  It exits 0 under 80,000, exits 1 at or over it, warns on stderr from 40,000, and is wired into no
  hook, workflow or pre-push by default (#297).
- A `<!-- context-budget: <N> reason: <text> -->` marker in `CLAUDE.md` raises that project's fail
  level to N; a marker with no number, a non-numeric one or no reason is refused (#297).
- `--sweep <root>...` walks the named roots for repositories with a `CLAUDE.md`, derives each
  one's auto-memory directory forward from the repository path (never by reversing the lossy
  slug), prints paths, sizes and levels only, and a sentinel string planted in every fixture file
  never reaches stdout or stderr (#297).
- A `##` section over 8,000 characters is reported as a move candidate and never fails the run
  (#297).
- `docs/guides/startup-context.md` states R2 to R10 and the prune recipe, including the
  line-multiset proof, the generator-owned-anchor check and keeping a moved block's visibility
  tier (#297).
- `health-check` reports the figure as one advisory row and forge-adapt reports it without gaining
  a word of `SKILL.md` (#297).
- `coding-standards-auditor` and `closing-sessions` are each recorded against R1 and R2 with the
  result of reading them: a change where one can add to the always-loaded set, a pinned
  no-change verdict where it cannot (#418).
- Each ticket is closed against a named commit, `Validate` is green on `main` after each, no
  component baseline is raised, and the new skill ends under its 2500-word budget.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The unit drifted back to bytes.** The ticket body, written before the picks, still says byte
  sizes and `FAIL at 85,000 B` throughout its 19 unit cases. The pick is characters, what Claude
  Code counts. A fixture built with `head -c` and an ASCII payload cannot tell the two apart, so
  the suite passed while the tool was wrong on the first multibyte `CLAUDE.md`. This is #403's
  class, which the leak guard fixed one site at a time four times. The fixtures must carry
  multibyte text, and a mutant that counts bytes must die (see the `mask-in-bytes` mutant in the
  leak-guard suites for the shape).
- **The loaded portion was not the measured portion.** The gate's third question noted that only
  the first 200 lines or 25 KB of `MEMORY.md` load at session start. A tool that charges the
  whole file reports a number no session ever loads, and a project is told to prune text that
  costs nothing. Maintainer question 1 settles it before the body is rewritten.
- **The import walk was written a second time and disagrees with the first.**
  `check-contributor-docs.sh` already implements the grammar (code spans and fences skipped, a
  breadth-first walk, `MAX_IMPORT_HOPS=4`, around line 957 of `check-contributor-docs.sh`). A
  second parser in another group drifts on the first edge case the CLI changes (a quoted path, an
  escaped space, an external import needing approval). Whatever the choice, the two must be pinned
  against the same fixtures, or one must call the other.
- **The tool read what it must not print.** The sweep reads other projects' untracked `CLAUDE.md`
  and auto-memory. A debug line, a section heading in the move-candidate report or an error that
  quotes a malformed import echoes file text. The pick is paths, sizes and levels only; a heading
  is file content, so the section flag prints the line number and size, not the heading, unless
  maintainer question 2 says otherwise.
- **A hook sneaked in.** Wired into `SessionStart` or `pre-push` "for convenience", the tool adds
  its own output to every session, which is the cost being cut, and fails a push in a repository
  whose `CLAUDE.md` is legitimately large. The pick is wired nowhere by default; the guide shows a
  project how to wire it, and no `hooks.json` row appears in the diff.
- **R5 was implemented against a premise the tree no longer has.** #418 says #298 touches the same
  skill and the two must be ordered. #298 closed 2026-10-01 (eab0f27), and `closing-sessions`
  version 7 already dedups against the topic files its index points at. The downstream failure the
  ticket describes (an auditor that "re-imported the topic files it had just moved out") was a
  locally adapted copy; #297's own comment of 2026-10-01 records that the template's Phase 4a only
  extracts inline standards and adds a plain `Coding standards:` reference line, and that was
  re-checked: the template contains no `@`. An edit made to satisfy the ticket's wording, rather
  than a gap found in the tree, adds words and a version bump for nothing.
- **The generator-owned anchors broke.** The new suite adds a line to CLAUDE.md's
  `scripts/test-X`, N tests list and a row to the component index. The count line is the shape
  `update-suite-counts.py` reads and `pre-push` checks, and the suite must be a `validate.yml` step
  or `check-test-suites-wired.sh` fails. Run both generators and keep their output.
- **Words.** The new skill is thin by pick, but `health-check` (1037 words), `closing-sessions`
  (1123) and `coding-standards-auditor` (1310) all have room, while `adapt` is at its 7144 ratchet
  with zero headroom. A forge-adapt pointer written into `SKILL.md` grew it and someone raised the
  baseline. An agent never raises a baseline; the wiring goes in `references/skills.md`, which is
  not budgeted, and any `SKILL.md` line pays for itself in the same commit.
- **Collisions.** #297 adds a group to `forge-kit-devops` (0.20.9) and bumps `health-check` (marker
  6); #418 may bump `coding-standards-auditor` (4) and `closing-sessions` (7), in `forge-kit-review`
  (0.7.0) and `forge-kit-governance` (0.34.1). Two ran in parallel and the second took the same
  semver.

## Expected work

In order, one at a time. The two share no component, but #418's rule cites #297's guide and
budget, so #418 cannot be judged until #297 exists.

1. **#297** (P2, round-0 clarification comment, body not rewritten to the picks): first, because
   #418's acceptance criteria cite R1 and R2 in a guide that does not exist, and a rule about
   respecting a budget has nothing to be checked against until the budget is defined. First
   step: rewrite the body to the seven picks of 2026-10-07 (characters not bytes, 40,000 and 80,000,
   the marker form, `--sweep`, R1 only, the 8,000-character section flag, the home in
   `forge-kit-devops`; also answer the gate's four questions in the body, three of which the picks
   already do), resolve maintainer question 1, then re-run the gate. Then: `skills/context-budget/`
   in `forge-kit-devops` with `assets/context-budget.sh` (marker `context-budget-version: 1`) and
   `scripts/test-context-budget.sh` (a `validate.yml` step, a count line in CLAUDE.md, and the
   component index regenerated); `docs/guides/startup-context.md`; a `health-check` step 11 that
   runs the asset when it is present and reports one row; a forge-adapt row in
   `references/skills.md`. The cross-reference to `claude -p --output-format json "/context"` is
   optional per the 2026-10-01 comment (free, no model call, but human-oriented markdown with
   rounded counts): the tool walks the load set itself, and this phase does not depend on the CLI
   being present. **Words:** new skill under 2500 (thin by design); `health-check` +60 words at
   most of 2000 budget; `adapt` +0, any `SKILL.md` pointer paid for by cutting the same count.
   **Baselines at risk:** `adapt` (7144) only.
2. **#418** (P3, never gated, acceptance "to be written when the phase opens"): second, for the
   reason above. Write the acceptance criteria now, from the tree: (a) read `coding-standards-auditor`
   Phase 4a, which edits `CLAUDE.md` only to delete inline standards and add one reference line, and
   `closing-sessions`, which writes `.claude/memory/` files and the `MEMORY.md` index and reads
   `CLAUDE.md` only to dedup; (b) for each, state whether it can add to the always-loaded set
   (a `CLAUDE.md` section, an `@`-import, an index line) and what R1 and R2 require of it; (c) change
   a component only where that reading finds a path to growth, otherwise pin the verdict with a
   `scripts/test-*` row where a test exists to host it. Note that `memory.py` targets the project's
   `.claude/memory/`, while the budget counts the auto-memory `MEMORY.md` under
   `~/.claude/projects/<slug>/memory/`; whether `closing-sessions` ever writes the second is the
   first fact to establish. Gate, then implement. **Words:** auditor 1310 of 2000, closing-sessions
   1123 of 2500, so any pointer is affordable; neither is an exempt component. **Baselines at risk:**
   none.

## Maintainer questions

Each was answered overnight on 2026-10-09 by the recommended option, recorded on #297 as
"(assumed 2026-10-09 overnight, pending maintainer)"; a different answer reopens the ticket text,
not shipped code, because nothing has been implemented.

Only decisions not already recorded on a ticket.

1. **Does the auto-memory `MEMORY.md` count whole, or only the portion that loads?** Pick 3 says
   "plus the auto-memory `MEMORY.md`"; the gate's third question and the 2026-10-01 comment record
   that only the first 200 lines or 25 KB load at session start. **Recommended:** count the loaded
   portion (first 200 lines or 25 KB, whichever is less), and print the whole-file size as a
   separate non-counted line, so a bloated index is visible but not charged for text no session
   reads.
2. **May the section flag name the heading?** The pick is a report-only flag on any `##` over 8,000
   characters, and the sweep prints "paths, sizes and levels only, never file contents". A heading
   is content. **Recommended:** a single-repository run prints the heading (the reader owns the
   file), and `--sweep` prints the line number and size only.
3. **Does the import walk reuse `check-contributor-docs.sh`'s, or carry its own?** The shell asset
   lives in `forge-kit-governance`, the new one in `forge-kit-devops`, and a cross-group source
   needs a dependency declared in both places. **Recommended:** carry a small own walk and pin both
   walks against one shared fixture set in the new suite, rather than add a cross-group dependency
   for one function.
4. **If reading shows neither #418 component can grow the startup set, may #418 close with a pinned
   verdict and no component edit?** **Recommended:** yes; a recorded no-change finding is a
   finished outcome, and an edit made to match the ticket's wording is the premortem's sixth
   clause.

## Out of scope

- **A `SessionStart` hook or any default wiring into CI or pre-push:** rejected on #297 (pick 3),
  not deferred.
- **Pruning the downstream repositories**: each project's
  own session applies it, because a sweep reports and never edits; not forge-kit's work, no ticket.
- **Taking token counts from `claude -p "/context"`:** `backlog`, a new ticket if a measurement of
  tokens rather than characters is ever wanted; the picks fix the unit at characters.
- **Mandating a name for moved topic files** (`.claude/memory/topic-*.md` is only suggested): the
  guide says so, no component enforces it.
- **Raising any component baseline or budget:** an agent never does; a shortfall is a maintainer
  question.
