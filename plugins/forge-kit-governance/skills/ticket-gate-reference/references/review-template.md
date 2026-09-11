<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Review output template

Step 4 composes this. Never a numeric scorecard.

```markdown
## Ticket Readiness Review - #<NUMBER>

**Issue:** <title>
**Date:** <today>
**Round:** <ROUND>
**Template version:** v<N> (current: v<M>)
**Review set:** mechanical checks + critic[, Security lens (label: security)]

**Verdict: PASS / NEEDS-WORK** - <one-sentence reason>

### Mechanical checks
| Check | Result | Evidence |
|---|---|---|
| Template version current | pass/fail | ... |
| Labels valid | pass/fail | ... |
| Required sections present | pass/fail | ... |
| GWT structure | pass/fail | ... |
| Test specs concrete | pass/fail | ... |
| Documentation impact present | pass/fail | ... |

### Critique
<per-section pushback>

### GWT review
<judgement against the quality bar, plus improved scenarios where written>

### Pros and cons
<of the proposed approach>

### Best practices
<researched, with sources; or the stated reason research was skipped>

### Suggested approach
<the concrete way forward>

[### Security lens
<specialist findings, when the lens ran>]

[### Architecture alternatives
<2 to 3 options, each with why it resolves the objection; only on a fundamental verdict>]


### Required changes (when NEEDS-WORK)
- [ ] <blocking change, specific>
```
