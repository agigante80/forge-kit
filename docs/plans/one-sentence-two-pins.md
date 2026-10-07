# Plan: One sentence, two pins

Phase opened 2026-09-12 for #199, the advisory both rounds of #198's gate raised: the `grep -a`
sentence #198 added to both scanner headers is pinned by no test.

## Goal

Make the leak guard's newest reach sentence as hard to lose as its older ones, so a header edit
that drops it fails a suite instead of being noticed a phase later.

## Done looks like

- `scripts/test-check-public-leaks.sh` has one new `--help` case after the `for asset` loop, and
  ends `passed: 81  failed: 0`.
- `scripts/test-check-private-leaks.sh` has its first `== --help ==` section with one case, and
  ends `passed: 41  failed: 0`.
- Deleting the sentence from a scratch copy of either scanner makes exactly that suite print exactly
  one `FAIL:` line and exit 1.
- `CLAUDE.md` L110 and L130 say 81 and 41. Nothing under `plugins/` changes.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The case was put inside the public suite's `for asset` loop**, so the count grew by two and
  pinned the private scanner from the public suite, and AC 3's 81/41 was then "corrected" to
  match the mistake rather than the mistake to match AC 3.
- **The mutation check was skipped** because the needle obviously matched. The suites' history is
  the argument: mutation twice found a case that could not fail minutes after it was written.
- **The header was edited to fit the test.** The needle is the shared core both headers already
  print on one line; if it does not match, the test is wrong, not the header. AC 2's rewrite is
  optional and not taken here.
- **The CLAUDE.md counts were left at 80 and 40**, which is the exact drift the commit "docs: the public leak suite has 80 cases, not 72" (since
  purged from history with CLAUDE.md, #232) was filed to fix, and the one blocking item the gate found on this ticket.

## Expected work

#199. On close, file the follow-up the gate named: the "never looks at history" sentence is pinned
in neither suite either, and the two wordings differ, so it needs per-asset needles.

## Out of scope

- AC 2 (rewriting the public header into the private header's form) and any marker or semver bump.
- #191, #196.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-12, outcome **done**. One ticket, two gate rounds, one follow-up (#200, the history
sentence, same shape) to `backlog`. Round 1 found the one thing the plan's fourth premortem clause
named: Documentation impact said "None" against the two `CLAUDE.md` counts, the same drift that "docs: the public leak
suite has 80 cases, not 72" fixed (a commit since purged from history, #232), again. This phase's gate runs were also the first on the installed v55 agent, and they confirmed
what three earlier phase closes could not: the round is counted from posted comments (round 2 read
as 2) and the mechanics line names its script with a `~`-relative path and its marker.

Opened 2026-09-12 for #199, the follow-up #198's close filed: the `grep -a` sentence that phase
added to both scanner headers is pinned by no test, where the public scanner's other reach
sentences are. One ticket, two suites, one line each, and the `CLAUDE.md` counts that go with them.
