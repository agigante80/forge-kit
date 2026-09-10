# Plan: The unit the budget defends

Phase opened 2026-09-10, written from #176 plus a classification of all 20 fenced blocks in
`adapt/SKILL.md` done before the plan, because the ticket's first acceptance criterion required it
and because the answer decides whether there is any work here at all.

## Goal

Answer whether `adapt`'s word ratchet is defending the right quantity, and act on the answer,
including when the answer is that the file is the size it needs to be.

## Done looks like

The classification is recorded where the next reader meets it. Either fenced blocks have moved into
`references/` and the baseline has dropped, or the reason they cannot is written into
`check-component-size.sh` and the externally anchored measure is at least visible.

## Order, and why

One ticket, so the order is inside it: **classify first, move second, and be willing to move
nothing.** The ticket says so and the classification is what makes the rest decidable.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A step the skill executes was moved into a reference.** The splitting convention forbids it for
  a reason this repo has already paid for: a callee that reads its instructions from a second file
  depends on a copy that can drift. `adapt` is almost entirely such steps, so the temptation here is
  strong and the damage would be silent, showing up as a forge-adapt run that half works.
- **Prose was compressed to make a number move.** The budget's own rationale warns against it, and
  `adapt` is dense already. A word saved by rewriting a sentence tighter is not a saving.
- **A line count became a second ratchet.** #174 settled that the always-on cost is reported and not
  budgeted, for a stated reason. Adding a hard line limit here would contradict that decision two
  days later and would fail components for a number Anthropic calls a tip.
- **The phase ended with nothing recorded.** "We looked and decided not to" is a finished outcome
  only if the next reader can find the reasoning. If it lives in a closed ticket alone, the question
  gets re-asked and re-answered, which is what #170 and #180 both went out of their way to prevent.

## Expected work

One ticket, #176. It may well close as a documented decision plus a reporting change rather than as
a move, and that is a finished outcome.

## Out of scope

- Any change to the word budget or its baselines beyond what a genuine reduction earns.
- Retrofitting `full-review`, which has never had a size retrofit and is not what this phase is
  about.
