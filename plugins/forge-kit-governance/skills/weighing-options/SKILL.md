---
name: weighing-options
description: Use when the user asks in conversation for an opinion, a suggestion, a recommendation, pros and cons, "what do you think", "should we", "which is better", or which approach to take, about code, design, tools, process or anything else, and when the user accepts a recommendation given earlier ("go with that", "agreed", "do C"). Not for a named ticket waiting on a decision (decision-brief), a plain factual question, or designing new work ("let's build X").
---

<!-- weighing-options-version: 1 -->

# Weighing options

An opinion is only useful if it can be acted on: the question restated, the options that are
really on the table, the trade-offs of each, and one recommended way forward. Once the user accepts
that recommendation, it is recorded where the project's next session, and the ticket gate, will
find it.

**Where this stops.** A question about a named ticket that is waiting on a decision belongs to
`decision-brief`, which re-validates and rewrites that ticket. Designing new work ("let's build X")
belongs to a brainstorming skill where one is installed. A plain factual question ("what does X
do", "where is Y") gets a plain answer, not this shape.

**Depends on `forge-kit-review`** for the two auditors that own the files a decision is recorded
in. The governance group declares it; a project that installed components one at a time without
them uses the fallback below.

## Before answering

1. **Check what exists.** Read the code, docs, tickets and memory the question touches, including
   `docs/coding-standards.md` and `docs/architecture/`. If the question is about code already
   written, review that code and name its concrete defects.
2. **Search online whenever an option involves a technology, library, protocol, pattern, tool or
   practice that exists outside the repo** (webhooks versus polling, a framework, an auth scheme, a
   process). Prefer primary sources (specs, official docs, the maintainers) and note each source
   with the date checked. "The trade-offs are well established", "I already know this" and "I don't
   know the provider" are not reasons to skip: current practice is checked, not recalled, and an
   unknown provider means searching the general practice and saying what to check for theirs.
   "Keep it short" or "I'm in a hurry" shortens the answer, never the search. Skip only when every
   option is purely about the code in front of you (a data structure, a function's shape).

## The answer, in this order

1. **The question:** one or two lines, in your words.
2. **What I found:** existing code, prior decisions, defects, research results, ending with a
   **Sources:** line (each source with the date checked, or "none: every option is about this
   code only"). The line is required in every answer, the quick ones included.
3. **Options:** each one lettered, a line on what it is, then its pros and its cons. Every option
   gets both, including "keep what we have" when that is a real option.
4. **Recommendation:** one explicit way forward. It may combine or sequence options: "A now, and a
   ticket for B", "start with A, move to B when X happens", "A plus the cheap part of B".
5. **What would change it:** the fact or condition that would flip the recommendation.
6. **Your call:** only when a decision is left to the user, phrased so it can be answered in a word.

**A quick question gets the same six parts compressed into a few lines without headings.** The
recommendation is never dropped, and never replaced by "tell me which fits".

## When the user accepts

The user accepts when they pick an option or approve the recommendation in their own words ("go
with that", "agreed", "do C"). Implement as usual, and also record the decision. Every record made
here is **accepted**: the user's words are the acceptance.

| Decision type | Where it goes |
|---|---|
| A rule for how code is written (practice, library, pattern, testing) | `docs/coding-standards.md`, added by you in its section: the rule in one line, then `(decided YYYY-MM-DD; sources: ...)`. The auditor rewrites the whole file and has no add-one-rule mode |
| A design or architecture choice (structure, integration, data flow, infrastructure) | An accepted ADR, through the architecture auditor (below) |
| The deferred part of a sequenced recommendation ("ticket B") | A ticket in the project's tracker. If no ticket can be filed (no tracker, or a consent hook denies it), put its trigger under the ADR's Revisit when and say so |

### Recording a design choice

**Auditor installed:** use the Agent tool with `subagent_type: forge-kit-review:architecture-standards-auditor`
twice, in the same turn:

1. Record mode: "Record this architecture decision: <decision>. Options weighed: <options with
   pros and cons>. Sources: <the Sources line>. Deferred: <trigger, if any>." Read the new ADR's
   number from its report (`Written:`).
2. Accept mode: "Accept ADR NNNN. The user accepted it in these words: "<the user's reply,
   quoted>"." The quote is the audit trail: nothing else records who accepted it.

The auditor picks the folder (an existing `docs/adr/`, `doc/adr/`, `.adr-dir` or `docs/decisions/`
stays the home), the number, the index and any supersession of an accepted ADR the decision
contradicts.

**Auditor absent:** write the ADR yourself, once, with `Status: accepted`:

- In the folder that already holds ADRs, in its numbering, format and accepted status word;
  otherwise `docs/architecture/NNNN-<slug>.md`, the next free number.
- In `docs/architecture/`, the auditor's shape exactly: a `# NNNN. <decision>` title, the lines
  `- Status: accepted` and `- Date: YYYY-MM-DD`, then the sections Context, Options considered,
  Decision, Consequences, Sources, Revisit when. Sources cite paths, commit hashes and URLs only.
- If it reverses an accepted ADR, add `Supersedes: NNNN` and set that ADR's status to
  `superseded` with `Superseded by:`, its only allowed edit.
- Tell the user the auditor's next reindex will list it in `docs/architecture/README.md`.

### Edge cases

- **No `docs/coding-standards.md`?** Offer `subagent_type: forge-kit-review:coding-standards-auditor`,
  which owns that file. Do not create it ad hoc, and record the rule only once the file exists.
- **Unclear whether the user accepted?** Any reply to a pending recommendation that neither picks
  an option nor approves it ("interesting", "ok", "makes sense", "thanks") is unclear. Ask once:
  "That sounds like a decision. Should I record it?" Write nothing until the answer.
- **No decision was made?** Record nothing, not even as proposed.
- **End the reply by saying what was recorded and where**, or that nothing was.

## Common mistakes

| Mistake | Fix |
|---|---|
| Pros and cons only for the new option | Every option, including the current one, gets both |
| Ending with "let me know which you prefer" | Give the recommendation, then the question |
| Skipping the search because the trade-offs "are well known" | Search anyway, cite with date |
| Implementing the accepted option and stopping | Record the decision and the deferred part too |
| Leaving the auditor's ADR at `proposed` | Run accept mode with the user's words quoted |
| A table for a yes or no question | Compress, keep the six parts |
