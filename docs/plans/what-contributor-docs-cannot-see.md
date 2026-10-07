# Plan: What contributor-docs still cannot see

Written 2026-10-01 from the roadmap prose and the seven tickets filed against `contributor-docs`
since the last phase closed, none of which had a phase. The batches that ran between the phases
(#385, #386, #387, #390, #395) fixed how the check reads a line. What is left is what it reads:
files it follows out of the repository, files it never follows, and files it never counts.

## Goal

`check-contributor-docs.sh` judges every instruction file a clone actually loads, never one it
does not, and it says what that file costs.

## Done looks like

- A tracked symlink chain cannot lead `required` out of the repository or print outside content
  (#309).
- A tracked `CLAUDE.md`'s `@`-imports are followed, and an import whose target a clone does not have
  fails (#301).
- A per-harness copy that neither links nor imports `AGENTS.md` is reported as `referred`, and
  `SKILL.md` says how to keep the copies one source (#300).
- The size of what a session loads at start (a `CLAUDE.md` plus its `@`-imports) is measured and
  budgeted, the way `check-component-size.sh` budgets component bodies, or the ticket records why
  that is the wrong place to measure it (#297).
- The `max-lines` question has a maintainer decision written into the ticket and the skill (#302).
- The byte-order-mark strips work under Apple's awk in a UTF-8 locale (#406), and #381's review
  Lows are closed (#398).
- `scripts/test-check-contributor-docs.sh` stays green under gawk and mawk in CI, and the README
  and CHANGELOG describe the new behaviour.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The security fix shipped last.** #309 sat behind the feature tickets because its gate verdict
  was stale. A check that prints outside content was in the field for the whole phase.
- **Following `@`-imports re-opened #309 by another road.** #301 resolved an import target through
  a symlink or a `..` path and read outside the repository, because it did not reuse #309's
  containment.
- **#297 became a rewrite of other projects' `CLAUDE.md` files.** The ticket's own field notes say
  a cross-project tool may measure and report, and only each project's session may change the file.
  A budget that edits or nags is one nobody keeps installed.
- **The import parser was a `^@` grep.** It counted `@actual-app/api` in a diagram as an import, or
  followed imports inside code spans, and the measured number was wrong.
- **#302 was implemented without a decision.** The ticket says not to. The phase closed with a
  default flipped by whoever got there first.
- **Gate rounds ate the phase.** #300 and #309 have each had three rounds, and the trip wire on
  #300 says to stop after a one-line fix. Re-gating went past that instead of going to the
  maintainer.

## Expected work

In order:

1. **#309**, the containment fix. Re-gate first: the round-3 verdict is stale.
2. **#406**, the BOM strips under BWK awk. Small, and the test harness for it already exists.
3. **#398**, #381's review Lows, after the one mechanical gate fix it is waiting on.
4. **#301**, `@`-import following (gate PASS), reusing #309's containment.
5. **#300**, per-harness copies, after its one-line gate fix. Re-gating goes to the maintainer.
6. **#297**, the startup-context budget, built on #301's import resolution. Expect it to need a
   scoping pass and possibly a split before it gates.
7. **#302**, a maintainer decision, then a small change or none.

## Out of scope

- **The rest of the unphased set**, triaged on the same day: test-harness flakes and mutant
  counting go to *Tests that can be believed*, ticket-gate correctness to *The gate's own
  correctness*, CDPATH and awk portability to *Portable shell, everywhere*, and the leak-guard,
  forge-host, reassess and closing-sessions Lows to `backlog`.
- **Editing any downstream project's `CLAUDE.md`.** #297 measures and reports only.
- **Plugin always-on cost** (#170, #174, both closed). This phase measures the project's own files.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-10-01, outcome **re-shaped**. Five of the seven planned tickets landed in the planned order, #309, #406, #398, #301 and #300, and one appeared: #408, found by #297's research, which showed Claude Code strips block HTML comments before it reads imports. The two that did not land each wait on the maintainer, not on work: #297 (startup context as a budget) moved to its own planned phase, *What a session loads before work begins*, with its prior-art research done and recorded on the ticket, and #302 (the line budget) moved to `backlog` until a choice among its three options is recorded. None of the premortem's clauses fired: the security fix shipped first, #301 resolved its symlink imports through #309's `safe_resolve` rather than a second definition, #297 measured and edited nothing, #302 was not implemented, and #300's trip wire held at one more round. What the phase learned is that the installed CLI is the only source to believe: probing Claude Code 2.1.287 reversed two of #301's rules (trailing punctuation is part of an import path, and an import inside a symlinked file resolves from the target's directory), and the free `/context` call turned out to report what #297 wanted to measure. The suite went from 607 to 805 cases, and CI now also runs it under BWK awk in a UTF-8 locale.

Opened 2026-10-01, when no phase was open and 28 open tickets had none. Seven of them are about one check, `check-contributor-docs.sh`, and they share a cause: the check reads a line well now (#385 to #395 saw to that), but it follows a tracked symlink out of the repository (#309), never follows a `CLAUDE.md`'s `@`-imports (#301), never looks at per-harness copies of `AGENTS.md` (#300), and never counts what a session loads before any work begins (#297), which one downstream repository measured at 258 KB. #302's line budget waits on a maintainer decision, and #398 and #406 are the Lows and the Apple-awk gap the last batches left.
