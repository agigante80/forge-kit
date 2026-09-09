<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

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
