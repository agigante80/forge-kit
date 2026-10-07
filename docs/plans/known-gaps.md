# Plan: Known gaps in shipped assets

Phase opened 2026-09-09, written from the roadmap prose plus the tickets already in the bucket.

## Goal

Close the gaps that shipped components are already known to have, so that what a component claims
and what it does are the same thing.

## Done looks like

#161, #159, #131, #134 and #167 closed, or explicitly decided and recorded. Each one either stops
being a gap or stops being described as something the component handles.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A gap was closed by narrowing the claim instead of the gap, without saying so.** Some of these
  SHOULD be answered by documenting the limit rather than by code, and that is a legitimate
  outcome. It fails only if the doc change is quiet: the limit has to be stated where a reader
  meets it, not buried in a ticket comment.
- **A fix was written for an unreachable case.** #131 and #134 are both defence in depth for
  situations neither host permits. Effort spent making those elegant is effort not spent on #161,
  which affects a real install today.
- **The phase became a general backlog.** These five share a cause. A sixth ticket that merely
  happens to be small does not belong, and adding it is how a phase stops meaning anything.
- **A LOW finding was fixed without a test, because it was low.** Every one of these was found by
  review rather than by use, which means nothing else will notice if the fix is wrong.

## Expected work

#161 first: it is the only one affecting a real install today, and it is the one an outside user
would hit first. Then #167, which is the same shape (an install path that misreports itself). Then
#159, #134, #131, which are all defence in depth and can be answered by documentation if the code
is not worth it.

## Out of scope

- The ticket-gate size decision (#150, #103), still blocked on the maintainer.
- #129 and #88, which are design work rather than gaps.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-09, outcome **done**. All six closed: #161, #167, #131, #134, #159 and #168, the
last of which did not exist when the phase opened. It was found by ARMING the overnight run against
this repo's own workflow, which the guard then made impossible; the phase's own subject is a shipped
asset whose behaviour is broader than it claims, and that is a textbook instance found by use rather
than by review.

#159 closed as working-as-intended by maintainer decision, with the limit documented beside the
reach statement it qualifies. The plan's premortem warned against closing a gap by narrowing the
claim quietly; this one is narrowed loudly.

Tickets filed at a review trip wire against components that already shipped. Each was reported as
LOW or latent, fixed nowhere, and recorded so the next reader would not rediscover it. They belong
together because they share a cause: a shipped asset whose stated behaviour is broader than what it
actually does.

The kit installs into a project by copying, and CLAUDE.md already says the opposite is better:
plugin registration "owns no user config and so has no wiring to drift, duplicate, or clobber, and
that copy-and-mutate path was the origin of every hook bug in this repo's history." The preference
is stated and not followed, because nothing makes it followable.

The blocker turns out to be small. A component pinned to one project is one with a value baked in at
INSTALL time; one that resolves at RUNTIME is already correct everywhere. The kit has exactly one
install-time placeholder, `{{GITHUB_REPO}}`, with six live uses across two files, and `forge_repo`
already replaces it at runtime elsewhere in those same files.

This phase is a bucket while the current one runs. Its plan gets written from this prose plus
whatever has accumulated by the time it opens, and the honest question it will have to answer is
whether forge-adapt's adaptation is doing as much work as its description claims.
