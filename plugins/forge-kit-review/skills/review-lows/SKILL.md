---
name: review-lows
description: |
  Canonical triage rule for review findings: severity and whether the finding is related to the
  change decide fix, ticket, note or drop, in the same batch. Named by code-reviewer, /full-review
  and the overnight pipeline.
---

<!-- review-lows-version: 2 -->

# Review lows

A shared rule, not a companion: three components name it rather than restate it. Round rules stay
in `/full-review`'s Iteration contract. The name predates v3, which triages every severity.

<!-- rule: review-lows v3 -->

- Brief a reviewer for Critical, High and Medium plus at most three defensible Lows.
- Every finding names its failure (these inputs or this state, this wrong output or crash), or it
  is dropped.
- **Related** means the finding sits in the changed lines, or in code the change now calls or
  relies on differently. Anything else seen in the area is **unrelated**, even inside a touched
  file. For an audit with no change, the audited scope is the change.
- **Easy** means roughly 15 minutes and inside the files already touched.
- Each finding gets exactly one outcome, in the same batch:

| Severity | Related | Unrelated |
|---|---|---|
| Critical, High | fix now | ticket, after reproducing the failure and searching open tickets; tell the user about a Critical at once (unattended: top of the report) |
| Medium | fix now | fix when easy, otherwise one line under "Noticed, not filed" in the summary |
| Low | fix when easy, otherwise drop with one line | drop, unrecorded |

- **A fix's own review files only Critical or High.** When the reviewed change is itself the fix
  for a ticket or a previous round, a Medium or Low it finds is fixed in that round or dropped,
  never ticketed. Each fix's review filing the next ticket is the chain this stops.
- A ticket needs a failure a user or operator could really hit; "could be cleaner" never earns
  one. One problem per ticket, never a bundle. Search open tickets before filing.
- Anything unfixed when the loop ends takes the same triage; a ticket, a note or a drop is finished.
- Report the stopping reason, rounds that found defects in a prior fix, one outcome line per
  related finding below High, the fixed, ticketed and dropped counts, and the "Noticed, not
  filed" list.
- When a phase opens, each review ticket below High in its area joins the plan or is closed with
  the reason.
