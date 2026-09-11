# Plan: The gate's own debt, and one contribution

Phase opened 2026-09-11, written from the three tickets already in the bucket. Two of them
(#189, #192) were found BY the gate while it reviewed the last phase's tickets, which is the first
time this repository has run it on itself. The third (#193) arrived from a downstream Forgejo
project with its fix attached.

## Goal

Make three signals tell the truth: the checker Step 3A runs, the verdict the gate leaves behind,
and the CI status `forge-lib.sh` reports on Forgejo.

## Done looks like

- Step 3A resolves `check-ticket-mechanics.sh` in a stated order (a project's own forge-adapt
  install, then the repository's tree when the gate runs inside a forge-kit checkout, then the
  highest `check-ticket-mechanics-version` across installed copies), never `head -1`, and PRINTS the
  path it chose. Verified by a live gate run on one of this phase's own tickets, with the printed
  path being the v5 tree copy.
- The gate's durable output survives an ordinary body edit, or lives somewhere an edit does not
  reach, and the trip wire can be shown to fire on a fixture that previously silenced it.
- On Forgejo, `forge_ci_status` returns `cancelled` for a superseded run, `pending` for a sha with a
  task and no status row, `none` for a sha with neither, and `not_configured` only when the API
  could not be asked. Its contract tests run in CI beside `test-forge-lib.sh`. Every reader of
  `not_configured` in the tree has been read and handles `none`.
- All three tickets were gated before implementation, per the 2026-09-10 decision, and the stopping
  rule was applied to the gating rounds as it was last phase.

## Order, and why

#189 first. It is the P1, it is the cheapest, and it is the tool that gates the other two: gating
#192 and #193 through a stale checker would repeat the corruption the ticket describes. Its own gate
run is the one exception, and Step 3A is run from the tree by hand for it, with the path recorded in
the review comment.

#192 second, because it is the second gate defect and the phase's premise is that the gate's own
debt gets paid before the gate is trusted with more work.

#193 last, not because it is least important but because it carries two maintainer decisions
(Option A or B, and what `none` means to `release`), and those are best made with the gate's
critic having read the ticket rather than before.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The Option A walk was ported whole.** The library gained a paginated task walk with a page
  budget and three documented escapes, all of them pagination or matching defects, into a file that
  had none. The ticket's own author measured the sample sha falling OUTSIDE the default budget on
  the day of filing. Option B is one jq filter over data the function already holds, and its failure
  mode is today's behaviour.
- **`none` inherited `not_configured`'s meaning, or the reverse.** `release` reads `not_configured`
  as "fall back to a local test gate". If `none` is left to mean the same thing, a repo whose CI
  simply has not started yet is told to skip CI. If `none` is NOT handled at all, a repo with no
  runner waits forever where it used to fall back. The vocabulary change is the risky half of #193
  and the grep of every reader is the whole of the work, not a footnote.
- **#189 was fixed for the case that bit.** Preferring the repository's own tree inside a forge-kit
  checkout is the branch that corrupted three runs here, so it is the one that got implemented, and
  the general case (highest marker across installed copies) was left as `head -1` because nobody
  here can reproduce it. The next user with two cached plugin versions gets the stale one, which is
  the original bug with a narrower witness.
- **#192 was fixed by convention.** The verdict region got a comment saying "do not edit this", or
  the fix depends on the maintainer remembering which region is the gate's. That is prose
  persuasion, which this kit exists to replace with mechanism, and it fails the first time a body is
  rewritten by Step 0c or by `decision-brief`, both of which edit bodies by design.
- **Gating produced a third crop.** Last phase, three tickets took six gate runs and produced five
  gate defects that were in none of them. If this phase's three runs do the same, the phase ends
  with more gate tickets open than it closed, and the honest question becomes whether "gate every
  new ticket" is the right rule rather than whether the gate has bugs. The bounded loop's stopping
  rule governs the gating rounds too: two rounds, and everything unfixed becomes a ticket.
- **The ported tests came with their blindness.** The downstream suite was green through all three
  escapes because every fixture was a short page holding one job for one full-length sha, a shape
  the real endpoint never returns. Porting the fixtures ports the blindness. Every ported test gets
  mutated before it is trusted, and the fall-back direction (an unknown description, an unreachable
  endpoint, an exhausted budget) must be a mutant that dies, not a comment that says so.

## Expected work

#189, #192, #193. #193 may split if the maintainer chooses Option B and wants the `total_count == 0`
half (`forge_ci_no_status_kind`, which still needs one `/actions/tasks` call) shipped separately
from the `cancelled` half.

## Out of scope

- #190, the checker failing five times on a `##` body. Same script as #189, but a different rule;
  it joins this phase only if #189's change reaches the heading check, and otherwise stays in
  `backlog`.
- #191, the leak guard's history mode. Blocked on the bash 3.2 rule and stays in `backlog`.
- Any change to the trip wire's policy. #192 is about the trip wire being ABLE to fire, not about
  when it should.
- Retro-gating closed tickets. Still refused, for the reason recorded on 2026-09-10.
