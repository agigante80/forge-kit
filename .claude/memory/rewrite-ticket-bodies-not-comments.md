---
name: rewrite-ticket-bodies-not-comments
description: "maintainer 2026-09-12: fold gate rounds and briefs into the body (dated, boxes ticked); a comment is for a retraction or a closing note, not the deliverable"
metadata:
  type: feedback
---

Maintainer instruction, 2026-09-12, on a ticket needing review and options: "update/rewrite tickets as necessary, do not simply add a comment". A ticket is read by its BODY; an analysis parked in a comment is invisible to anyone triaging several tickets at once, which is the reasoning the decision-brief skill already records (#94, #99, #101 opened with a dated rewritten preamble).

**Why:** the maintainer triages from bodies. A comment is the audit trail (a retraction still goes there first, dated, so the record shows it independently), not the deliverable.

**How to apply:** when a gate round, a brief or a review changes what a ticket says, edit the body: fold required changes into the acceptance criteria and the author's own sections marked with the date and the round, keep the gate-owned regions intact, and tick the boxes. Post a comment only for a retraction (first) or a closing note naming the commit. Related: [[a-ticket-assertion-is-a-claim-check-it]].
