# working-overnight: per-task governance pipeline

Every implementation task runs through these in order. Reuse the existing
components; do not reinvent them.

1. **Best practice (research).** Web-search the current best practice for the
   specific change (framework, security, testing idioms). Note what you found.
2. **Project rules.** Apply CLAUDE.md and docs/coding-standards.md. Match the
   surrounding code.
3. **Tests first (TDD).** Derive cases from the ticket's GWT and test specs. Write
   the failing test, then the implementation (superpowers:test-driven-development).
4. **Security.** Run the security-auditor over the change. For anything touching
   auth, input handling, or data exposure, treat findings as blocking.
5. **Verify.** Drive the real behavior (superpowers:verification-before-completion),
   not just the test suite. Unattended work over-verifies.
6. **Land.** Commit on a branch in the item's worktree, open a PR whose body links
   the ticket and lists what was verified. Never merge.

To gate a ticket, run ticket-gate: a clean pass moves it to the ready queue; a
non-pass parks it with the gate's review (verdict + required changes).

For an investigation, run the relevant review: full-review in its unattended mode
(every prompt auto-resolves; ticket filing honours the manifest's investigation-depth
cap, over-cap findings listed unfiled in the report), or a security-auditor pass for
security investigations (no checkpoint machinery; its findings are filed within the same
cap). Write findings and create tickets for actionable items within the
investigation-depth cap, then let a later cycle gate and implement them.

## Repeated reviews: chain the rounds, and stop where the contract says stop

full-review's iteration contract is written for a caller who is present. Overnight there is
none, and the rules below are what honouring it unattended means. They are the caller's side of
that contract, not new review policy.

**Chain the rounds with `--since`.** Re-reviewing a target an earlier cycle already reviewed is
round N+1, not a fresh round 1: pass `--since <ref>` so the round is delta-scoped and the target
cannot grow. A loop that re-runs the whole target every cycle is the unbounded-target pathology
the contract exists to stop, and it is expensive in exactly the hours nobody is watching.

**Do not expect `.full-review/state.json` to be there.** It is gitignored and lives at the root of
the checkout that ran the review, and every implementation item gets its OWN worktree, so the
next cycle usually starts where no state exists. Read it when the review ran in this same
checkout; otherwise the ref must come from somewhere that survives, so **record the reviewed ref
on the queue item** in `.claude/overnight/queue.md` when a review completes, and read it back from
there. Without that, this rule silently never fires and every round is round 1 again, which is the
failure it was written to prevent.

If neither store has a ref, this IS round 1 and `--since` is omitted. Never invent one: a `--since`
pointing at the wrong commit reviews the wrong delta and reports clean.

**The trip wire is a defer, never a decision.** The contract says remaining findings become
tickets and continuing past the trip wire is the caller's explicit call, never a default.
Overnight has no caller, so nothing here is entitled to make that call, and "the findings look
minor" is that call being made anyway.

So on a `trip wire` stop, do both halves. File the remaining findings as tickets, within the
manifest's investigation-depth cap like any other overnight filing. Then append the item to
`.claude/overnight/decisions.md` with the loop's own stopping data (rounds run, the count of
rounds that found in-prior-fix defects, the tickets filed) and pick another item. The question
being deferred is whether to CONTINUE the loop, not what to do with the findings; those are
already handled.

A `hard stop` is not a defer. The contract ends the loop there with no decision offered, so its
remaining findings become tickets and the item is done, the same as `clean round`. A stop for
`fixes pending` is ordinary and continues. Parking a hard stop would hand the human a decision
the contract does not give them, which is its own way of not honouring it.

**The report names the trip wire first.** A trip-wire park leads the deferred-decisions section
of `.claude/overnight/report.md`, above the ordinary you-only calls: it is the one where the loop
already did the work and needs a human to say whether the work was any good.
