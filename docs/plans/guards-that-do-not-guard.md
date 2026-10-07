# Plan: Guards that do not guard

Phase opened 2026-09-08, written from the roadmap prose plus the six tickets already in the bucket.

## Goal

Make every guard in this repository check what it claims to check, and run where it claims to run.

## Done looks like

`#158` closed: both range guards run server-side on the path work actually takes. `#140` and `#142`
closed together: no guard decides anything from the worktree when it means the tracked set. `#143`,
`#138` and `#127` closed: the remaining guards report accurately and their suites cover the paths
that were found by review rather than by use.

And the standing claim in `CLAUDE.md` about what CI enforces is true when read literally.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A guard was made stricter and got bypassed.** Every ticket here tightens something. Tightening
  is how a guard acquires false positives, and a guard that fires on legitimate work is one people
  learn to pass with `--no-verify`. Each fix needs a near-miss case, not only a firing one.
- **#158 was fixed with a branch name instead of a base-ref decision.** Adding `push` to a trigger
  is one line and looks like the fix. It is not: `github.event.before` is wrong after a force push
  and all-zeroes on a first push, and the guards must keep failing closed rather than passing
  vacuously. A vacuous pass would leave the claim true on paper and false in fact, which is worse
  than the current honest gap.
- **#140 and #142 were fixed separately.** They are the same defect in two guards, and #142 says so.
  Fixing one leaves the other as evidence that the class was not understood.
- **The phase grew.** Six tickets share a cause; a seventh that merely sounds similar would dilute
  the review that closes this. New guard work goes to a new phase or backlog.
- **Nothing was verified by mutation.** Every fix here is to a checker, and a checker's test passes
  just as readily when the check has been deleted. A fix without a mutant is a fix without evidence.

## Expected work

`#158` (P1) first, since it is the live gap and the others are latent. Then `#140` with `#142` as
one change. Then `#143`, `#138`, `#127`.

## Out of scope

- `#159` (the leak guard's first-segment limit) stays in Backlog: it is a coverage decision, not a
  guard that is lying about itself.
- The `ticket-gate` size decision (`#150`, `#103`) is its own phase and is blocked on the
  maintainer, not on this work.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

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
