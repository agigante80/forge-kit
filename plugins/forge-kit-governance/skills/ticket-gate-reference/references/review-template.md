<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Review output template

Step 4 composes this, Step 5 writes it as the body's `gate-review` region. Never a numeric scorecard.

```markdown
### Gate review (round <ROUND>)

**Issue:** <title>
**Date:** <today>
**Template version:** v<N> (current: v<M>)
**Review set:** mechanical checks + critic[, Security lens (label: security)]

**Verdict: PASS / NEEDS-WORK** - <one-sentence reason>

#### Mechanical checks
| Check | Result | Evidence |
|---|---|---|
| Template version current | pass/fail | ... |
| Labels valid | pass/fail | ... |
| Required sections present | pass/fail | ... |
| GWT structure | pass/fail | ... |
| Test specs concrete (unit) | pass/fail | ... |
| Test specs concrete (E2E) | pass/fail | ... |
| Documentation impact present | pass/fail | ... |

#### Critique
<per-section pushback>

#### GWT review
<judgement against the quality bar, plus improved scenarios where written>

#### Pros and cons
<of the proposed approach>

#### Best practices
<researched, with sources; or the stated reason research was skipped>

#### Suggested approach
<the concrete way forward>

[#### Security lens
<specialist findings, when the lens ran>]

[#### Architecture alternatives
<2 to 3 options, each with why it resolves the objection; only on a fundamental verdict>]

```

This is the whole `gate-review` region (#581): the heading is the round marker `count-gate-rounds.sh`
reads, so keep it exactly. The blocking items are NOT repeated here: Step 6 writes them as the
`gate-required-changes` checklist. The region holds no `<!-- gate-... -->` marker line, because
markers do not nest, so never quote one in it. The legacy `gate-items` pair is retired.
