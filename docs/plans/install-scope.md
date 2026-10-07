# Plan: Install scope, user level by default

Phase opened 2026-09-09, written from the roadmap prose plus the four tickets that accumulated in
its bucket while the previous phase ran.

## Goal

Make forge-kit installable once, at user level, for everything that does not genuinely need a
per-project copy, so the preference CLAUDE.md already states can actually be followed.

## Done looks like

A component that resolves what it needs at runtime is installed by enabling its plugin group, not
by copying it into `.claude/`. Every component says which of the two it is, and a guard refuses a
claim the tree contradicts. Nothing carries a live install-time placeholder. A project that wants
an opinionated component off can turn it off without uninstalling anything.

Concretely: #163, #164, #165 and #166 closed, and `forge-adapt` no longer copies a `scope: user`
component by default.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **forge-adapt got worse at the thing it is good at.** Its value is the RECOMMENDER: reading a
  project and saying which components fit. If shrinking the copy-and-mutate surface also blunts
  that, the phase traded the good part for the tidy part. The test is whether a first-time install
  still ends with the user knowing what to enable and why.
- **`scope: user` became a lie.** A component declared user-scope that quietly needs a project fact
  is worse than one honestly copied, because nothing will tell the user why it misbehaves. #164's
  guard is the answer, and it has to key on something real rather than on the declaration alone.
- **The placeholder work turned into a ticket-gate edit.** `ticket-gate.md` sits on its size ratchet
  and #150 is unresolved. Six live uses are a small change, and it must stay one: if #163 grows
  into a rewrite of the gate, it has escaped its phase.
- **"User level" quietly became "forced on every project".** The sentinel pattern exists precisely
  so it does not, and #165 is the ticket that makes it a convention rather than a habit. Skipping
  #165 because it is only documentation is how that failure arrives.
- **The kit stopped working for a project that declines a group.** Everything here assumes plugin
  registration; a project that installs nothing must still be able to copy components by hand, and
  `scope: project` must keep working exactly as it does today.

## Expected work

`#163` first: it unblocks the rest and is the only one with a measured, bounded scope (six live
uses, two files). Then `#164`, which needs #163 done or the declaration contradicts the tree. Then
`#166`, which has nothing to key on before #164. `#165` is independent documentation and can land
at any point; do it before #166 so the sentinel convention exists when forge-adapt starts pointing
at it.

## Out of scope

- The `ticket-gate` size decision (#150, #103). Its own phase, blocked on the maintainer.
- Anything in Backlog. #161 in particular looks related, since it is also about what an install
  needs, but it is about a DEPENDENCY rather than a scope and pulling it in would grow the phase.
- Retiring `{{GITHUB_REPO}}` from prose that documents the manual-install path. That form is
  correct there, and deleting it would make the manual path undocumented.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-09, outcome **re-shaped**. All four tickets landed, and one acceptance criterion
of #166 did not: `drift` still reports a registered component as missing. It hit the same ratchet
that forced #166's rule into a script, so it moved to #167 rather than being squeezed in at 4am.
That is the circuit breaker working, not a shortfall.

The plan's premortem was right twice. It said the placeholder work must not become a ticket-gate
rewrite, and #163 stayed six lines while SHRINKING the gate. It said `scope: user` must not become
a lie, and a review round then found the scope guard and the placeholder guard contradicting each
other inside one CI job, which is that failure arriving by a route the plan did not name.
