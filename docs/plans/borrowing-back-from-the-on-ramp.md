# Plan: Borrowing back from the on-ramp

Phase opened 2026-09-10, written from a content comparison against the sister project
`agigante80/vibe-coding-prompts` rather than from a wish list. Every item below is a rule that
collection states and this one does not.

## Goal

Take the three things the prompt library knows that forge-kit forgot, and refuse the rest.

## Done looks like

The leak guard either reaches history or says in its own header that it does not. The unattended
overnight loop asks whether a ticket is still worth doing before doing it. The reviewer sweeps for
the family of a finding rather than fixing the instance.

## Order, and why

**The leak guard first**, because it is the only one of the three that is a defect in something
already shipped rather than an absent capability, and because it is a security component whose
stated reach is wrong by omission. Then the overnight premise check, which is the largest behaviour
change. Then the sweep rule, which is prose in one agent.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **forge-kit grew three subjects the neighbours already own.** The comparison surfaced fourteen
  prompts and the discipline was in refusing eleven of them. If this phase adds a logging component,
  a documentation-standardisation component or a test generator, it has undone the argument #178
  made one day earlier, when eleven components were retired for exactly that.
- **The leak guard's history mode became a secrets scanner.** `gitleaks` exists, is better at it,
  and is what the sister prompt actually recommends. This kit's guard is about the developer's
  identity leaking, not credentials. Widening the subject is how a narrow honest guard becomes a
  broad unreliable one.
- **A history scan made the guard unusable.** Scanning every blob in a long history is slow, and a
  pre-commit hook that takes thirty seconds gets bypassed with `--no-verify` permanently. Whatever
  ships must stay off the per-commit path.
- **The overnight premise check became a second gate.** `ticket-gate` decides readiness and
  `decision-brief` re-validates a stalled ticket. The overnight loop needs a cheap "is this still
  true" pass, not a third component that re-litigates either.
- **The sweep rule turned into scope creep licence.** "Fix the family" and "stay on the ticket's
  scope" pull against each other, and the sister prompt states both in the same breath for that
  reason. A rule that licenses touching anything, reported as a sweep, is worse than no rule.

## Expected work

Three tickets. The first may end as a documented limit rather than a history mode, and that is a
finished outcome.

## Out of scope

- Any new component. All three are changes to things that exist.
- Secrets scanning. Name `gitleaks` and stop.
- Anything from the other eleven prompts.
