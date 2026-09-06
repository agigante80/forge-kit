# Issue Template Versioning

## What the version marker does

Every issue template in `.github/ISSUE_TEMPLATE/` contains a hidden version marker:

```yaml
- type: markdown
  attributes:
    value: |
      <!-- template-version: 6 -->
```

When a user files an issue, this marker appears in the issue body. The `ticket-gate` agent
reads this marker and compares it to the current template version. If they differ, it
auto-synthesises the missing content (see Step 0c Auto-synthesis below).

## Current version: 6

v6 renamed the privacy section (labelled "GDPR compliance", "GDPR impact" or "GDPR implications", depending on the template) to "Personal data handling" and replaced its
article-numbered prompts with seven regime-agnostic facts (issue #101). forge-kit names no
jurisdiction in any default: for most projects a named regime is the WRONG one, and a gate citing
the wrong statute is worse than one citing none, because it looks authoritative. Projects under a
specific regime install the opt-in `privacy-regime` skill, which names their own. The field `id`
changed from `gdpr` to `personal_data`. The gate's Step 0c synthesis rules table gained a row for it,
and 0c-ii classifies every current section `id` against the issue body and Step 3A check 3 requires a
heading for each, so a pre-v6 ticket would classify the renamed section as Missing. 0c's always-check
list therefore gained `personal_data` with an instruction to recover it from any old heading
matching /GDPR/ first, since the v5 wording differed per template. `dep-auditor`'s stamped heading moved too.

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
5. **Posts a comment** explaining what was synthesised and voiding the prior verdict
6. **Re-runs the full review** against the enriched body (nothing carries forward)

The synthesised content is real and concrete - not placeholder text. The sub-agent reads the
full issue body and any linked external URLs to derive specific test cases.

## Two markers, two consumers (issue #94)

`docs/guides/ticket-standards.md` carries **two** version markers. They exist because one integer
was serving two consumers that move at different rates, which made the cheap change expensive:

| Marker | Answers | Consumer | Cost of a bump |
|---|---|---|---|
| `template-version` | which FORM this doc describes | `ticket-gate` Step 0c, and the lockstep guard | high: re-synthesises every open ticket |
| `doc-rules-version` | which revision the RULES TEXT is at | humans, and `forge-adapt refresh` | none downstream |

**The problem it fixes.** Before this, editing a rule's prose implied bumping `template-version`,
because that integer was also read as "the rules changed, refresh installs". The lockstep guard then
forced the five templates to the same number, `ticket-gate` saw a higher current version, and every
open ticket took an auto-synthesis round trip. A prose clarification cost a migration. That is why
the gate and this doc were allowed to fork: fixing the fork correctly was more expensive than
leaving it.

Worth knowing precisely, because it changes what a fix costs: **`ticket-gate` never reads this
doc.** Its `CURRENT_TPL_VER` is computed from the template directory alone. The expensive coupling
was entirely in `check-template-lockstep.sh`, which requires the templates and this doc to share one
integer.

**The rule.**

- Change a form field (add, remove, or redefine a section the templates collect):
  bump `template-version` in all five work templates AND in `ticket-standards.md`, per the procedure
  below. The synthesis round trip is the point.
- Change only the rules text (clarify a bar, add a rule the forms already collect content for,
  correct the prose): bump `doc-rules-version` alone. The lockstep guard does not look at it, so
  nothing else has to move.
- Fix a typo or reformat: bump nothing.

**Why two markers rather than a "prose-only changes are bumpless" rule.** That was the cheaper
option considered and rejected: "prose only" is a judgment call, and a judgment call inside a
mechanical guard is exactly what this repo refuses. Two markers are mechanical.

**This is the settled practice elsewhere, not a local invention.** 1EdTech's Versioning Framework
states it as a MUST: "A new version of a specification MUST ONLY occur when there is a change in
functionality. Editorial changes in the associated documentation MUST NOT change the specification
version i.e. it is the document version that is changed." W3C draws the same substantive-versus-
editorial line, and OpenAPI ships two version fields (`openapi` for the spec, `info.version` for the
document) for precisely this reason: two things that move at different rates should not share one
version.

- https://www.imsglobal.org/spec/versioning/v1
- https://github.com/OAI/OpenAPI-Specification/issues/3872

## Bumping the template version

When you add new fields or rules:
1. Add the field to all relevant templates
2. Bump `<!-- template-version: N -->` to `N+1` in each work template AND in
   `docs/guides/ticket-standards.md`: the two are version-locked by
   `scripts/check-template-lockstep.sh`, and CI fails when either lags. Do NOT bump
   `doc-rules-version` for this unless the rules TEXT changed too; they are independent
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
