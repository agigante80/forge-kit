# Issue Template Versioning

## What the version marker does

Every issue template in `.github/ISSUE_TEMPLATE/` contains a hidden version marker:

```yaml
- type: markdown
  attributes:
    value: |
      <!-- template-version: 5 -->
```

When a user files an issue, this marker appears in the issue body. The `ticket-gate` agent
reads this marker and compares it to the current template version. If they differ, it
auto-synthesises the missing content (see Step 0c Auto-synthesis below).

## Current version: 5

v5 added the ticket-standard improvements approved 2026-07-16 (see
`docs/superpowers/specs/2026-07-16-ticket-standard-improvements-design.md`): a required
`docs_impact` field on all five work templates (docs affected, README impact, why-not-if-none),
a GWT quality bar with gate-derived scope (rule 1), and the droppable emulator clause on E2E
specs (rule 3).

v4 added three key fields to all templates:
- `scenarios` - Given/When/Then test scenarios (one positive + one negative per condition)
- `unit_tests` - specific test file paths, inputs, and expected outputs
- `e2e_tests` - specific E2E test suite files, setup, and assertions

## What GWT scenarios look like

The GWT (Given/When/Then) format makes test cases concrete and testable:

```
**Condition: User submits form with invalid email**

Positive
- Given: A valid user session and a properly formatted email address
- When: The user submits the profile update form
- Then: The profile is saved and a 200 response is returned with the updated email

Negative
- Given: A valid user session and an email with no @ symbol (e.g. "notanemail")
- When: The user submits the profile update form
- Then: A 400 response is returned with error code "INVALID_EMAIL" and the profile is not updated
```

One positive + one negative per independent condition. For a ticket fixing 3 bugs, write 3 blocks.

## Step 0c: Auto-synthesis (what happens on version mismatch)

When `ticket-gate` finds a version mismatch (issue filed on an older version than the templates currently carry):

1. **Parses** the current template structure to identify all expected sections
2. **Classifies** each section in the issue body: present/thin/missing
3. **Spawns a sub-agent** to synthesise real content for missing sections, using:
   - The issue's problem description
   - The acceptance criteria
   - Referenced files and route names
4. **Updates the issue body** via `gh issue edit` with the synthesised content
5. **Posts a comment** explaining what was synthesised and voiding prior scores
6. **Re-runs the full review** against the enriched body (nothing carries forward)

The synthesised content is real and concrete - not placeholder text. The sub-agent reads the
full issue body and any linked external URLs to derive specific test cases.

## Bumping the template version

When you add new fields or rules:
1. Add the field to all relevant templates
2. Bump `<!-- template-version: N -->` to `N+1` in each work template AND in
   `docs/guides/ticket-standards.md`: the two are version-locked by
   `scripts/check-template-lockstep.sh`, and CI fails when either lags
3. Update `ticket-gate.md` in the same commit: the auto-synthesis target-section list, the
   synthesis table, and the posted-comment section list must know any new section
4. Ticket PRODUCERS never hardcode the version: `dep-auditor` and `ci-health` stamp the
   current marker read from the template dir, so they need no per-bump edit
5. All existing tickets auto-upgrade on next gate run (Step 0c triggers)

No manual ticket updates needed - the auto-synthesis handles it.

## Why this matters

Without versioning, a ticket filed on an old template can pass the gate on structural
grounds but be missing critical test specifications. With versioning + auto-synthesis:
- No human friction from template upgrades
- Every ticket has concrete GWT scenarios and test cases before implementation
- the gate's test-spec checks pass because the specs are always present
