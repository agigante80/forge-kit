---
name: bounded-review-loop-in-practice
description: Fired 3 times in one day; close out by fixing merge-blockers only and ticketing the rest, and say so in the commit
metadata:
  type: feedback
---

The bounded review loop from the global CLAUDE.md is not a theoretical safeguard here: across four PRs on 2026-08-28 the TRIP WIRE fired three times (PR #85 at round 3, #87 at round 2, #89 at round 3), each time because two consecutive rounds found defects inside the previous round's fixes.

The close-out pattern that worked, and that should be the default when the wire fires:

1. Fix ONLY the merge-blockers surgically (a rule contradicting its own step, a guarantee with no mechanism, a check that cannot fail).
2. File everything else as one consolidated ticket with the verified findings quoted, rather than iterating (this produced #86, #88, #94).
3. Say in the commit message that the loop stopped at the trip wire and why, so the next session does not read the remaining findings as neglect.

**Why:** prose state machines (ticket-gate.md, full-review.md) accumulate contradictions faster than a review loop converges on them; the third round consistently found defects introduced by the second. Iterating further removed value, exactly as the rule predicts.

**How to apply:** when a round's findings are mostly "this new clause contradicts an older clause it did not update", stop and ticket. That signal usually means the component is too large ([[generated-index-and-size-budget]] tracks the size half of this problem), not that the reviewer is being picky.
