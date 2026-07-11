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
non-pass parks it with the gate's scorecard.

For an investigation, run the relevant review (full-review or security-review),
write findings, and create tickets for actionable items within the
investigation-depth cap, then let a later cycle gate and implement them.
