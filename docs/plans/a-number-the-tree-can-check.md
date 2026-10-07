# Plan: A number the tree can check

Phase opened 2026-09-14 for #201: `CLAUDE.md` states a count for eleven contract suites, nothing
checks it, and three were already stale when the ticket was written.

## Goal

Make the suite counts generated, the way the component index already is: one script rewrites
them from the suites' own printed totals, and `--check` fails CI when a number is stale.

## Done looks like

- `scripts/update-suite-counts.py` with `--check`, `--list`, `--doc`, `--root`; exit 2 and no
  write when a suite is missing or prints no recognisable total.
- `scripts/test-update-suite-counts.sh` covering the four GWT conditions plus the real-repo
  `--list` case, in CI beside the generator's `--check`.
- The three stale numbers corrected by running the script, not by hand; `--check` green.
- `CLAUDE.md`'s validation list names both commands, and one sentence says the counts are generated
  and that `N` is the printed assertion total.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The anchor reached past the claim** and rewrote `24 downstream tests` on line 97, so the guard
  that exists to stop numbers drifting changed a number that was never a count.
- **The Python suite read as zero** because its total is on stderr and the reader took stdout, and
  the generator "fixed" a true 12 to a false 0. An unreadable total must refuse, never write.
- **The contract test ran the generator against this repo inside itself**, so a real suite
  changing here could make the guard's own test fail for the wrong reason. `--list` exists so the
  real-repo case checks the parser and runs nothing.
- **The spelled-out counts on line 19 were "fixed" here too**, widening the ticket. They are #202.

## Expected work

#201. Nothing else.

## Out of scope

- #202 (line 19's three counts), the pre-commit fast path, #191, #196.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

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
