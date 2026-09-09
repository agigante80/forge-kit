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
