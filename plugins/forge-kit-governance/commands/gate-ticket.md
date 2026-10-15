---
description: "Run the ticket readiness gate on a forge issue (GitHub or self-hosted Forgejo)."
argument-hint: "<issue number>"
---

<!-- gate-ticket-version: 10 -->

Run the ticket readiness gate on a forge issue (GitHub or self-hosted Forgejo, where the ticket-gate
agent detects the host via the `forge-host` adapter).

## Usage

Accepted argument: `<issue-number>` (required)

Example: `/gate-ticket 44`

## Steps

Use the Agent tool with `subagent_type: ticket-gate`, passing the issue number as the prompt.

**Headless limit (#477).** Interactively the gate is resumed when each agent it dispatched finishes. In a
`-p` run keep the gate's dispatches in the foreground (the default there; `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`
forces it, untested): a `run_in_background` dispatch is never heard from again by the gate, its result reaches
the top level instead, and the review is not posted.

The ticket-gate agent handles all steps:
1. Template version check - auto-synthesises missing sections when the ticket's version is older than the CURRENT template version, read from the project's templates, or missing (no BLOCK; never a hardcoded number)
2. Fetches the issue from the forge (GitHub or Forgejo)
3. Reads project context (CLAUDE.md, architecture docs, labels)
4. Runs the deterministic mechanical checks, then ONE critic agent (plus the security
   lens when the `security` or `critical` label is present)
5. Compiles and posts the review (verdict + critique, never a numeric scorecard) as a forge comment
6. Returns PASS or NEEDS-WORK with specific required changes, or BLOCKED (missing required labels, or a ticket too thin to review: fix labels / answer the posted questions, then re-run; `NO_TEMPLATES` when the project has no versioned issue template: run `forge-adapt templates` (`/forge-kit-adapt:adapt`), then re-run; `RUN_FAILED` when a step's own guard stops the run, its stderr line relayed: fix what it names, then re-run)

The ticket is implementation-ready when every mechanical check passes and the critic (and any lens) raises zero blocking items.
