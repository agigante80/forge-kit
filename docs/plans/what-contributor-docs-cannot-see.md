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
