---
name: review-lows
description: |
  Canonical rule for review findings below Medium: fix, ticket or drop, in the same batch.
  Named by code-reviewer, /full-review and the overnight pipeline.
---

<!-- review-lows-version: 1 -->

# Review lows

A shared rule, not a companion: three components name it rather than restate it. Round rules stay
in `/full-review`'s Iteration contract.

<!-- rule: review-lows v2 -->

- Brief a reviewer for Critical, High and Medium plus at most three defensible Lows.
- Every finding names its failure (these inputs or this state, this wrong output or crash), or it
  is dropped.
- Critical, High and Medium are fixed. Each Low gets exactly one outcome, in the same batch:
  - **fix** when small (roughly 15 minutes) and inside the files already touched;
  - **ticket** only when a user or operator could really hit its failure and it is too big now;
  - **drop** with one line in the review summary or commit message.
- An out-of-target observation, a Low twin outside the swept files included, gets a ticket or a
  drop by the same test, never a ticket by default.
- One problem per ticket, never a bundle. Search open tickets before filing.
- Anything unfixed when the loop ends takes the same triage; a ticket or a drop is finished.
- Report the stopping reason, rounds that found defects in a prior fix, one outcome line per Low,
  and the fixed, ticketed and dropped counts.
- When a phase opens, each Low ticket in its area joins the plan or is closed with the reason.
