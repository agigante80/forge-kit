# Plan: Tests that can be believed

Written 2026-10-01 from the roadmap prose and the six tickets in the bucket (#411 landed before it
opened), opened when *Portable shell, everywhere* closed. The roadmap asked that the plan say what each flake's root cause is
rather than raise a timeout; where a cause is not yet known, the plan says how it will be found.

## Goal

A green run means what it says: a suite that passes alone also passes beside other copies of
itself and under load, and a mutant harness credits a kill only when the mutant ran and was caught.

## Done looks like

- Every suite row that is red under load is either fixed at a named cause or shown not to
  reproduce under one written load recipe, with the runs recorded on its ticket. No timeout is raised
  to make a row pass.
- The #402 watcher rows no longer see other copies' watchers (#411).
- `test-forge-lib.sh`'s compose rows (`crlf`, own-region), its large-page count and its row
  recorder each have a stated cause or a recorded non-reproduction (#404, #378, #331 item 1).
- No script asks `grep -q` a question through a pipe under pipefail, and a CI guard keeps it so
  (#413, with #378 for `test-forge-lib.sh`). That is the named cause of the `glued` row (#219, closed
  into #413), the compose rows (#378) and #331 item 1, and it can skip a shipped refusal.
- A mutant harness outside `test-forge-lib.sh` reports a crashed mutant as crashed, never as
  killed (#360).
- `test-forge-lib.sh` unsets every `FORGE_*` variable that can change a case, and sync-labels'
  host dispatch refuses an unknown host by name (#331 items 2 and 3).

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The flakes were "fixed" by waiting longer.** A bound went from 30 to 60, the row went green,
  and the cause is still there for the next machine that is slower again.
- **Nothing reproduced, so nothing was learned.** The runs were 12 idle copies; the flake needs
  sustained load, and the phase closed with "could not reproduce" on every ticket.
- **The load recipe became its own flake.** A soak that saturates the box fails rows that are fine,
  and the tickets chase the recipe instead of the suite.
- **#360 credited crashes differently in each harness.** Five copies of a crash classifier drifted
  apart, which is the shape #405 just removed for the `awk -v` count.

## Expected work

In order:

1. **#411**, DONE before the phase opened (ce5b192): per-run watcher durations in both #402 blocks.
   It removed the one flake reproduced on demand (8 of 12 runs under 4 parallel copies; 0 of 24
   after), so the later soaks are not polluted by it.
2. **One load recipe**, written into #404 before any of its rows are judged: N parallel copies held
   for the whole soak, with the measured load average recorded, and the control run named. #378 and
   #331 item 1 are judged against the same recipe; if they are #404's rows, they close into it.
3. **#378 then #413**, the SIGPIPE class: `printf | grep -q` under pipefail returns 141 on a match
   when grep exits first (49 of 400 loaded runs; the here-string form 0 of 400). Re-diagnosed by
   #219's round-4 gate, which closed #219 into #413: the cause is a pipe, not a bound, so no bound
   moves. #378 converts `test-forge-lib.sh`; #413 converts the other 282 lines its guard's rule
   counted at 7f8e87c (shipped assets included) and adds the guard, `check-pipe-grep-q.sh`, which
   starts green only after #378.
4. **#360**, one crash classification for the harnesses outside `test-forge-lib.sh`.
5. **#331 items 2 and 3**, the env reset and the host dispatch (item 1 moved to #378).

Evidence already in hand (2026-10-01, this phase's opening): under 4 parallel copies for 3 rounds,
only the #402 rows failed in `test-forge-lib.sh` (8 of 12 runs); the compose and `crlf` rows did not
fail. #411's acceptance run (4 parallel copies x 3 rounds, after its fix) then saw `compose dropped
the caller's own region` in 1 of 12 forge-lib copies (#331 item 1, #404) and `the glued one too` in
3 of 12 public-leaks copies (#219; 4 of 12 during #411's gate). One `test-reassess-phases.sh` run
failed a row beside a running leak suite (not reproduced in 3 idle runs; the row was not captured).

## Out of scope

- **The startup-context budget** (#297): *What a session loads before work begins*.
- **roadmap-lib's remaining `awk -v` values** (#412): backlog, a portability ratchet, not a flake.
