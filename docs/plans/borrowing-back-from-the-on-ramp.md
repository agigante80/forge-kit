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

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-10, outcome **re-shaped**. All four tickets closed, one of them by splitting: #185
shipped its outcome B and moved outcome A to #191, because the gate found that two of A's own
constraints contradict each other.

**The phase was overwhelmingly about the gate rather than about the borrowings.** Its three tickets
took six gate runs between them, and produced five defects that were in none of them: #188 the label
taxonomy, which blocked every ticket in this repository and shipped inside the phase; #189 the stale
plugin-cache resolution, confirmed by three separate runs; #190 the checker failing five times on a
`##` body where its own rule says refer once; #192 the gate's verdict region being erasable by an
ordinary body edit, which silently prevents the trip wire from ever firing; and a stale test count in
CLAUDE.md.

**Two of the three borrowings would have shipped wrong.** #186's premise check, written as shell
greps, would have been DENIED by this kit's own overnight guard whenever a ticket quoted a
destructive command, recording a destructive-command deferral that never happened. #187's boundary
had two independent holes, and the second needed no strained reading: the prohibition it leaned on
lives inside one review dimension and does not govern a general rule placed elsewhere.

The premortem's first clause held: fourteen prompts were compared and eleven refused as subjects the
neighbours own.

**The stopping decision is the thing to carry forward.** Gating stopped at two rounds per ticket
under the bounded iteration contract, with everything unfixed becoming a ticket. Both round 2s found
defects in the round-1 fix, which is one round of fix-induced findings and one short of the trip
wire. Continuing would have been the move the rule exists to refuse.

Opened 2026-09-10 after a content comparison against `agigante80/vibe-coding-prompts`, the sister
project and the on-ramp: prose prompts pasted into any assistant, where this kit installs components
and fails builds. The two have traded mechanisms before, the generated index and the version-bump
gate both came from there, and this is the third trip.

Three rules that collection states and this one does not. One of them, the leak guard's blindness to
history, is a defect in a shipped security component rather than a missing feature: `--all` means
`git ls-files`, so a home path committed and later deleted is invisible to the guard written for the
moment a repository goes public.

The discipline here is in what was refused. Fourteen prompts were compared and eleven are subjects
the neighbours own, one day after #178 retired eleven components for being exactly that.
