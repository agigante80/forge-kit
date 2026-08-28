<!-- gate-ticket-version: 5 -->

Run the ticket readiness gate on a forge issue (GitHub or self-hosted Forgejo, where the ticket-gate
agent detects the host via the `forge-host` adapter).

## Usage

Accepted argument: `<issue-number>` (required)

Example: `/gate-ticket 44`

## Steps

Use the Agent tool with `subagent_type: ticket-gate`, passing the issue number as the prompt.

The ticket-gate agent handles all steps:
1. Template version check - auto-synthesises missing sections when the ticket's version is older than the CURRENT template version, read from the project's templates, or missing (no BLOCK; never a hardcoded number)
2. Fetches the issue from the forge (GitHub or Forgejo)
3. Reads project context (CLAUDE.md, architecture docs, labels)
4. Runs the deterministic mechanical checks, then ONE critic agent (plus the security
   lens when the `security` or `critical` label is present)
5. Compiles and posts the review (verdict + critique, never a numeric scorecard) as a forge comment
6. Returns PASS or NEEDS-WORK with specific required changes

The ticket is implementation-ready when every mechanical check passes and the critic (and any lens) raises zero blocking items.
