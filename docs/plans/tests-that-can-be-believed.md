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

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-10-02, outcome **re-shaped**: the six planned tickets and three that appeared all closed, but around a different cause than the plan named. #411 (each run's own watcher duration) landed before it opened. #219's round-4 gate then re-diagnosed the bucket: `printf | grep -q` under pipefail returns 141 on a match when grep exits first (49 of 400 loaded runs; the here-string 0 of 400), the cause of the glued row and of #378's compose rows. That became a class: #219 closed into #413, which converted every such line outside `test-forge-lib.sh` (the 22 in shipped assets first, because a MALFORMED-first roadmap over 64 KiB was synced to the host 10 runs of 10) and added the `check-pipe-grep-q.sh` guard; #378 converted `test-forge-lib.sh`'s 29 (soak 20 of 20 under the shared recipe). #331 fixed sync-labels' unknown-host fallthrough and the suite's env reset. #360 and #414 made every mutant harness report a crash as crashed through one `scripts/mutant-crash.sh` (the scope grew from 5 harnesses to 23 across rounds, then split). #404 shipped the fail-fast TMPDIR guard (it had scattered scratch under `/` as root) and closed as not reproduced at 1.6 to 2.3 x nproc on a host with no sync client, so the synced-folder hypothesis stays open for the maintainer's machine. #415, found by #413's load run, accepts the bound's escalated 137 only when the wall time shows the bound fired. Premortem: no bound was raised to make a row pass (#415 added a lower bound, not a longer one); the flakes were reproduced on demand before they were fixed; the load recipe needed one revision (2 x nproc, since N generators never reached N); and the crash classifier is one helper, not five copies. Out of the phase: #412 (roadmap-lib's 11 `awk -v`) stays in backlog.

Opened 2026-10-01, when *Portable shell, everywhere* closed; plan: `docs/plans/tests-that-can-be-believed.md`. #411, filed while gathering this phase's load evidence, landed the day before it opened, and its acceptance run reproduced two of this bucket's flakes on demand (the compose own-region row, the glued case).

A bucket, filed 2026-10-01. Suites that pass alone and fail under load (#404, #378, #331, #219), and mutant harnesses outside test-forge-lib.sh that count a crashing mutant as killed (#360). A suite that flakes teaches people to re-run it, and a mutant that crashes proves nothing; both make a green run mean less than it says. The plan, when it opens, has to say what a flake's root cause is in each case rather than raise a timeout.
