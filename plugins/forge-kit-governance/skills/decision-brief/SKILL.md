---
name: decision-brief
description: Re-validate a stalled ticket, classify what is actually being decided, cost the options against measured numbers, and rewrite the ticket body so the decision can be made from it. Use when a ticket is waiting on a human decision, when asked for a decision brief on an issue, when a ticket has stalled through several nudges, or when someone asks which option to pick on a ticket.
---

<!-- decision-brief-version: 1 -->

# Decision brief

A ticket stalls waiting on a human, and the human is handed the ticket as it was written. That is
the worst moment to read it: the premise may have drifted since, the options are rarely costed, and
the obvious answer often turns on practice outside this repo that nobody has looked up.

This skill produces the artifact that unsticks it. The pattern is not invented here. Four tickets in
one session (#94, #102, #103, #120) each ended as a hand-written version of it, and #94 had sat
through five nudges as "the maintainer must decide" when one verify-then-research pass answered it.

## What this is not

**It is not a second ticket-gate, and it does not quote one either.** The gate asks *is this ready
to implement* and answers PASS, NEEDS-WORK or BLOCKED. This asks *which option should the maintainer
choose*. Reach for `/gate-ticket` before implementation; reach for a brief when implementation is
not the question.

The way to get the gate's analysis is to **run the gate**, never to cite a previous run and never to
restate its bars. Carrying a copy of the gate's rules here is the restatement drift this repo keeps
finding, and it is a different thing from re-running the analysis.

It does not decide product or architecture direction, does not implement, and does not merge.

## Host access, and what this skill depends on

**Depends on `forge-kit-devops`, for `forge-host`'s `forge-lib.sh`.** The dependency runs one way:
nothing in devops knows what a decision brief is. Install it alongside.

Read and write through the `forge_*` functions, never `gh` directly, so a brief works on GitHub and
Forgejo alike: `forge_issue_view <n>` to read, `forge_issue_comment <n> <body>` for a correction
comment, `forge_issue_edit <n> <body>` for the rewrite. Set `FORGE_DRY_RUN=1` while drafting;
`forge_issue_edit` REPLACES the body and the host's edit history is the only other copy.

`forge_issue_edit` arrived in `forge-lib.sh` v13, added for this skill. **On an older copy the
rewrite step has no primitive**, and a GitHub-only fallback (`gh issue edit`) silently costs the
Forgejo half. Refresh the asset rather than falling back: check the marker, and say so plainly
rather than quietly posting a comment instead, which is the failure step 7 exists to prevent.

## Step 1: re-validate. This step BLOCKS

Run `ticket-gate` on the ticket now, against the current standard. **A stored verdict is evidence of
nothing**: in a single day this repo moved `template-version` 5 to 6, rewrote a rule to name no
jurisdiction, moved six gate-only bars into the canonical doc, and added six entries to the
restatement set. Every review written before that describes a standard that no longer exists.

Then check the ticket's own factual claims against the tree. Report **what was checked and where**:
the claim, the file and line, and the result. Roughly half the tickets examined in the session that
motivated this had drifted.

If the premise is dead, say so FIRST and either rebuild the decision around what survives or
recommend closing. A brief built on a stale premise is worse than no brief, because it is read as
analysis.

## Step 2: classify what is being decided

These are not the same and must not be presented alike.

| Shape | What the human is actually choosing |
|---|---|
| Choose between options | which design |
| A guard forbids the work | whether to bend a rule they set |
| The premise is dead | whether to close |
| **No decision needed** | nothing; just implement it |

**The fourth is a real outcome.** If there is no genuine decision, say so and offer to implement.
Manufacturing a choice to justify the brief is the failure mode this row exists to name.

## Step 3: a GWT scenario per option

State what would be TRUE after each option, so they are compared on outcomes rather than adjectives.
This is also the guard against a persuasive brief for a bad option: outcomes are harder to sell than
adjectives.

## Step 4: research current practice

WebSearch it, cite sources as links, prefer primary ones, and **mark where the evidence is weak or
contested** rather than overclaiming. A confident brief citing a weak source is worse than no
research. This repo had to walk back a "lost in the middle" citation that turned out to be about
retrieval rather than instruction following; say that kind of thing out loud.

## Step 5: pros, cons, and the cost, MEASURED

Where a cost is measurable, measure it: word counts against a budget, files touched, tests needed,
install paths affected. "+173 words against a 5680-word ratchet" is a decision input. "This may be
expensive" is not.

## Step 6: recommend, and say what happens if they do nothing

The do-nothing branch is usually the status quo, is usually worse than it looks, and is the option
that gets taken by default when a brief does not name it.

## Step 7: REWRITE the ticket body

Not a comment. A reader triaging a batch of tickets reads bodies and does not open comments unless
told to, so an analysis parked in a comment is invisible exactly when several tickets are being read
at once. This repo already settled it in practice: #94, #99 and #101 each open with a dated
rewritten-preamble, and the host keeps the edit history, so the audit trail survives.

The rewrite MUST:

- open with `> **Rewritten <YYYY-MM-DD>.**` naming what changed and what was disproven;
- keep every part of the original argument that still holds, **in the author's framing**;
- state explicitly what was removed and why, rather than quietly dropping it;
- post a separate correction COMMENT first when a factual claim is being retracted, so the public
  record shows the correction independently of the rewrite.

**Region ownership, so two writers never contend.** The gate appends its own required-changes
section and writes into the template's sections during auto-remediation. The brief owns exactly two
regions, the preamble and a `### Decision` section, and touches nothing else. Do not run a brief and
a gate remediation on one ticket at the same time.

## Step 8: print a short summary in the conversation

The question in one sentence, the options in a table, the recommendation, and what stays blocked
until they answer. Short enough to act on without opening the ticket.

## What makes a brief wrong

- It presented options as if the original premise held, when step 1 had found otherwise.
- It manufactured a decision because a brief was requested.
- It made the choice instead of costing it. Costing is the job; choosing is the maintainer's.
- It measured nothing and called that a cost.
- It restated a gate rule instead of running the gate.
