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
- **The CLAUDE.md counts were left at 80 and 40**, which is the exact drift `965d7e0` was filed to
  fix, and the one blocking item the gate found on this ticket.

## Expected work

#199. On close, file the follow-up the gate named: the "never looks at history" sentence is pinned
in neither suite either, and the two wordings differ, so it needs per-asset needles.

## Out of scope

- AC 2 (rewriting the public header into the private header's form) and any marker or semver bump.
- #191, #196.
