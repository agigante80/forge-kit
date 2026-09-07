---
name: ticket-gate-reference
description: |
  Reference material the ticket-gate agent reads once per run: the review output template it
  composes, and the specialist lens definitions with their result contract. Preloaded into
  ticket-gate through that agent's `skills:` frontmatter. Not a standalone workflow: it decides
  nothing, and the only rules it carries are the ones a lens itself obeys.
---

<!-- ticket-gate-reference-version: 2 -->

# ticket-gate reference

**`ticket-gate.md` is canonical for every ORCHESTRATOR rule.** It carries the artifacts that agent
reads once per run: an output template and the lens briefs. The dividing line is who obeys a rule:
a rule the LENS follows travels with its brief below, because the brief is dispatched to the lens
verbatim; every rule ticket-gate itself follows (when a lens runs, how results merge, what a re-run
rescopes) stays there and is only POINTED at from here. Nothing is restated across the two, because this repo's own record is that content copied
into a second location drifts from the first (the lens contract across two plugins, the
doc-versus-gate restatement). If a rule appears both here and in `ticket-gate.md`, that is the bug,
and `ticket-gate.md` wins.

Agents cannot carry a `references/` directory of their own: `agents/` is a flat namespace the
Claude Code loader claims at any depth, so a companion skill is the supported way to give an agent
reference material (issue #124). This skill is PRELOADED rather than invoked on demand, so its
content is present for every run exactly as if it were still inline. That means this split
reorganises the material and does not reduce the context the gate loads; see issue #109 for the
follow-up that would make it conditional.

## Review output template

Step 4 composes this. Never a numeric scorecard.

```markdown
## Ticket Readiness Review - #<NUMBER>

**Issue:** <title>
**Date:** <today>
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

## Lens definitions

Step 3C dispatches these.

### Security lens (label `security` or `critical`)
Use agent type: `security-auditor`. Runs AFTER the critic and receives the critic's JSON:
it reports only NET-NEW findings and explicit disagreements, never restatements of items
the critic already raised (the retired committee's sequential-execution dedup, kept). The
personal-data judgment is the critic's alone; the lens confines itself to this checklist:
- Authentication: is auth required specified? Any public endpoints justified?
- Authorization: can users access only their own data? Role checks present?
- Input validation: validation schemas specified? Max lengths? Format validation?
- Data exposure: does the response leak sensitive fields?
- OWASP Top 10: injection, XSS, CSRF, broken access control addressed?
- Rate limiting: is the endpoint rate-limited or does it need to be?
Returns `{verdict, blocking, advisory}`: the critic's shape minus `sections` (that key is
the critic's prose contract), with `class` on each blocking item (fundamental /
significant; the lens judges its own items). Step 3C's dispatch carries this contract
verbatim, so the callee never depends on a copy that can drift. The MERGE rule for these results is a rule and
lives in `ticket-gate.md` at Step 4, not here.
