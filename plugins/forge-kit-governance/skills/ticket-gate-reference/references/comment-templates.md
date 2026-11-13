<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Body templates

The gate posts NO comment (#581, the maintainer's third ruling). The file keeps its name because
other files point at it. These are PAYLOADS only, each written into a gate-owned body region with
`forge_body_region_set <N> gate <region> "<content>"` and replaced the next round, never appended.
WHEN each is written, and what blocks or proceeds after it, is decided in `ticket-gate.md`. A
payload holds no `<!-- gate-... -->` marker line: markers do not nest.

**Synthesis void (Step 0c-v, template auto-upgraded).** Written to `$D/void.md` and at once as the review; Step 5 puts it
first inside the `gate-review` region.

```markdown
#### Template auto-upgraded to v<CURRENT_TPL_VER> - content synthesised

Issue was filed against template v<old> (current: v<CURRENT_TPL_VER>).
The following sections were synthesised from the existing issue content:

- <section id>: <what was synthesised for it, or N/A - <reason>>

Enriched existing sections: <list or "none">

Any previous gate verdict is void. Re-reviewing now against the enriched body.
Review the synthesised content and re-run /gate-ticket <N> if corrections are needed.
```

**Clarification (Step 1.5, thin ticket).** The whole `gate-review` region. Its heading carries no
"(round N)", so `count-gate-rounds.sh` does not count a clarification stop as a round.

```markdown
### Gate clarification (needed before review)

This ticket lacks enough implementation detail to review accurately. Please answer the
following questions in this ticket body before re-running the gate:

1. [Question 1]
2. [Question 2]
3. [Question 3 (up to 5 questions)]

Answering in the body ensures the next gate run can review the complete spec.
```

**Remediation guide (Step 6, option 2).** The whole `gate-required-changes` region.

```markdown
### Required changes (gate)

Remediation guide (<Blocking / Advisory>):
- [ ] <required change 1>
- [ ] <required change 2>
```
