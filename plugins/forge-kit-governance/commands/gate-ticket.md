Run the ticket readiness gate on a GitHub issue.

## Usage

Accepted argument: `<issue-number>` (required)

Example: `/gate-ticket 44`

## Steps

Use the Agent tool with `subagent_type: ticket-gate`, passing the issue number as the prompt.

The ticket-gate agent handles all steps:
1. Template version check - auto-synthesises missing sections if v < 4 or missing (no BLOCK)
2. Fetches the issue from GitHub
3. Reads project context (CLAUDE.md, architecture docs, labels)
4. Runs 5 core agents + dynamic agents selected by labels and content, sequentially
5. Compiles and posts the scorecard as a GitHub comment
6. Returns PASS or BLOCKED with specific required changes

All agents must score 10/10 for the ticket to be considered implementation-ready.
