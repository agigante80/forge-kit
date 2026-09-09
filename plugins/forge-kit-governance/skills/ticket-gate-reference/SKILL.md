---
name: ticket-gate-reference
description: |
  Reference material the ticket-gate agent reads once per run: the review output template it
  composes, the specialist lens definitions with their result contract, the comment templates
  it posts, and the `forge_*` call mapping every forge operation looks up. Preloaded into
  ticket-gate through that agent's `skills:` frontmatter. Not a standalone workflow: it decides
  nothing, and the only rules it carries are the ones a lens itself obeys.
---

<!-- ticket-gate-reference-version: 9 -->

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
reference material (issue #124). This file is PRELOADED into ticket-gate; the files under
`references/` are NOT, and are read on demand. That is the difference #150 turned into a
reduction: #109 moved material from the agent into this skill and reduced nothing, because both
are preloaded, and the size guard reported a win it had not made. Moving the read-once artifacts
one hop further takes 797 words out of every run.

## What is here, and when to read it

Each file below is read at ONE point in a run. Find it with Glob rather than a fixed path, because
this skill lives in the plugin or in a project's `.claude/skills/`, and a hardcoded path is correct
in one of those and wrong in the other:

```
Glob "**/ticket-gate-reference/references/<file>"
```

| File | Read it at | What it is |
|---|---|---|
| `review-template.md` | Step 4 | the output template the review is composed into |
| `lens-definitions.md` | Step 3C | each lens brief and its result contract |
| `comment-templates.md` | Steps 0c, 1.5, 6 | the comment bodies posted to the forge |
| `forge-call-mapping.md` | when a `forge_*` call is unclear or fails | the call mapping |
| `installing-the-mechanics-script.md` | install time only | how the shipped asset reaches a project |

**If a file you need cannot be found, SAY SO AND STOP.** Do not reconstruct it from memory. A
review composed against a remembered template is the silent drift this whole split is at risk of,
and it is the one failure that would make preloading the safer design after all.
