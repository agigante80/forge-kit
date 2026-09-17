# Plan: A guard that can fire

Phase opened 2026-09-17 for #218, which follows `a44d7e3` (the assistant files stopped being
published) and `a5bd55c` (three guards made to skip an absent doc rather than fail the build).

## Goal

No CI step exists whose only possible assertion is over a file no checkout carries, and the twelve
suite-count claims are checked where the doc actually lives, at push time, for the suites the push
touched.

## Done looks like

- The `Suite counts in CLAUDE.md match what the suites print` step is gone from `validate.yml`, and
  the three steps that legitimately skip each print their own named skip line.
- `update-suite-counts.py --changed <paths>` narrows `--check` to the claims whose suite is in the
  list, and says so when none is.
- `.githooks/pre-push` runs that rule and `update-component-index.py --check` above the base-ref
  exit, taking its range from the hook's own stdin, with its own counter and message: exit 1 blocks
  as a stale claim, exit 2 blocks in could-not-run wording, a missing `python3` skips loudly.
- `scripts/test-pre-push-hook.sh` and `scripts/test-update-suite-counts.sh` pin every one of those
  behaviours, including the one that matters most: a checkout with no `CLAUDE.md` is not blocked.
- `test-update-suite-counts.sh` reports the same total with and without the doc present.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The rule went in below the base-ref exit** and is silently skipped on any clone that has not
  fetched, which is the defect this hook's own header records at lines 49-52 for the leak guard and
  the one gate round 2 caught in the first fix. The range comes from stdin for exactly this reason.
- **The hook got slow and started being bypassed.** The full battery is 93 s; `--changed` is what
  keeps a push that touches no suite at 0.31 s. If a common push ends up running the leak suite
  every time, the rule has recreated the problem it was written to avoid.
- **A test asserted wall time** and flaked on a loaded machine, which is #219's failure mode
  arriving in a second place. Sentinel files, never seconds.
- **The blocked push was wrong**: #219's flake makes a counted suite report a different total, the
  rule calls the claim stale, and the maintainer learns to pass `--no-verify` by reflex.
- **The deletion took the real check with it**: `Component index freshness` also names CLAUDE.md,
  and removing the wrong step would drop the enforcement of two tracked regions.

## Expected work

#218 alone. Two tickets are adjacent and deliberately out: #219 (the flake) and the
`ticket-standards.md` rule 8 example error the gate found, which is filed separately on close.

## Out of scope

- Moving the twelve claims into a tracked doc. Weighed in the ticket and rejected on audience; if
  the counts ever acquire a public reader, that option subsumes this one.
- Anything about `a44d7e3` itself. The files were restored by hand; the local store is not this
  phase's subject.
