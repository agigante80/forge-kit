---
name: ticket-gate-reference
description: |
  Reference material the ticket-gate agent reads once per run: the review output template it
  composes, the specialist lens definitions with their result contract, the comment templates
  it posts, and the `forge_*` call mapping every forge operation looks up. Preloaded into
  ticket-gate through that agent's `skills:` frontmatter. Not a standalone workflow: it decides
  nothing, and the only rules it carries are the ones a lens itself obeys.
---

<!-- ticket-gate-reference-version: 7 -->

# ticket-gate reference

**`ticket-gate.md` is canonical for every ORCHESTRATOR rule.** It carries the artifacts that agent
reads once per run: an output template, the lens briefs, the comment templates and the `forge_*`
call mapping. The dividing line is who obeys a rule:
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

## Comment templates

These are PAYLOADS only. WHEN each is posted, and what blocks or proceeds after it, is decided in
`ticket-gate.md`. Post them through the call mapping below, under the rule and the legacy fallback
`ticket-gate.md` states: they left that file in #130, so the inline "GitHub reference form" caveat
no longer reaches them.

**Synthesis void (Step 0c-v, template auto-upgraded).**

```markdown
Template auto-upgraded to v<CURRENT_TPL_VER> - content synthesised

Issue was filed against template v<old> (current: v<CURRENT_TPL_VER>).
The following sections were synthesised from the existing issue content:

- <section id>: <what was synthesised for it, or N/A - <reason>>

Enriched existing sections: <list or "none">

Any previous gate verdict is void. Re-reviewing now against the enriched body.
Review the synthesised content and re-run /gate-ticket <N> if corrections are needed.
```

**Clarification (Step 1.5, thin ticket).**

```markdown
## ticket-gate: clarification needed before review

This ticket lacks enough implementation detail to review accurately. Please answer the
following questions in the ticket body (not in comments) before re-running the gate:

1. [Question 1]
2. [Question 2]
3. [Question 3 (up to 5 questions)]

Answering in the body ensures the next gate run can review the complete spec.
```

**Remediation guide (Step 6, option 2).**

```markdown
## ticket-gate: remediation guide

### <Blocking / Advisory>
- [ ] <required change 1>
- [ ] <required change 2>
```

## forge_* call mapping

Which adapter call serves each need. The RULE, that every forge call goes through `forge_*` and
never through `gh` directly, is in `ticket-gate.md`; this is the lookup.

| Need | Call |
|---|---|
| view an issue (body/labels/title) | `forge_issue_view <N>` → JSON `{number,title,body,state,labels[].name}` |
| comment on an issue | `forge_issue_comment <N> "<body>"` |
| close an issue | `forge_issue_close <N>` |
| edit an issue body | `forge_api PATCH "/repos/$REPO/issues/<N>" "$(jq -nc --arg b "<body>" '{body:$b}')"` |
| create a follow-up issue | `forge_issue_create "<title>" "<body>"`, then `forge_issue_label <N> <name…>` for labels (refuse-all on Forgejo: an unresolvable name fails the WHOLE call non-zero and applies nothing, so check the exit and create missing labels first) |
| list/search issues | `forge_issue_list [state]`, filter client-side |
