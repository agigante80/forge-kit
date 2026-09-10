# Plan: The half that needs no Claude Code

Phase opened 2026-09-10, written from the portability analysis that ran while #181 rewrote the
README, and from the honest sentence that rewrite had to include: nothing enforces any of it for a
team not using Claude Code.

## Goal

Make the portable half of forge-kit usable by an agent that is not Claude Code, or say plainly and
permanently that it is not.

## Done looks like

Someone on Cursor, Codex, Copilot or no AI CLI at all can hold a ticket to `ticket-standards.md`
with a command rather than with good intentions, and there is one document to point their agent at.
If that turns out to be impossible or not worth it, the reason is written where the claim is made,
and the README's portability section is narrowed to match.

## Order, and why

**The gate first, the document second.** The document describes what the gate makes true, and
writing it first would produce the thing this phase exists to stop: a portability claim with
nothing behind it. That is the same ordering #181 was given for the same reason.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A second gate was built.** `check-ticket-mechanics.sh` already exists, is already shipped, and
  already has 41 contract tests. If this phase writes new checking logic rather than an entry point
  onto that script, it has created the exact duplication the kit fails builds over, and the two
  copies will disagree within a month.
- **The entry point pretended to be the whole gate.** Step 3A is the MECHANICAL half. The critic in
  Step 3B is a judgement no shell script can make, and every `referred` row exists because a
  heuristic was deliberately narrower than the rule. An entry point that printed PASS on mechanics
  alone would be a worse liar than the current silence, because it would look like the real thing.
- **It grew a dependency on the `claude` CLI.** The entire point is a path that does not have one.
  `forge-lib.sh` and `check-ticket-mechanics.sh` are plain shell and must stay that way, and the
  test must run on a machine with no plugins installed.
- **A bootstrap installer was built because it felt tidy.** Copying four artifacts is `cp`. A script
  for it is ceremony until something proves otherwise, and this plan deliberately does not include
  one. If the gate work shows a real need, ticket it then, with the evidence.
- **The README's honest sentence was quietly deleted.** "Nothing enforces any of it for you" is
  currently true. It may be narrowed when it stops being true, and only that far: the hooks, the
  size budget and drift detection are still Claude Code and will still be after this phase.
- **The phase ended with a document nobody outside this repository could follow.** The reader is an
  agent or an engineer with no forge-kit context. If it assumes the plugin vocabulary, it has failed
  even if every sentence in it is accurate.

## Expected work

Two tickets: the mechanical gate's entry point, then the cross-agent document that AGENTS.md and the
README point at. Either may end as a recorded decision.

## Out of scope

- Porting agents, skills, commands or hooks. They are Claude Code components by construction and
  this phase does not pretend otherwise.
- A bootstrap installer, per the premortem.
- Any change to `check-ticket-mechanics.sh`'s checks. This phase gives it a door, not new rules.
