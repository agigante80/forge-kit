---
name: generated-index-and-size-budget
description: "Four hand-maintained inventories and 5-7k-word components are the root cause behind repeated review findings; #95 then #96 then #97"
metadata:
  type: project
---

Two structural weaknesses sit behind a large share of the review findings this repo keeps producing, both tracked as tickets (#96, #97) and both borrowed as diagnoses from [[sister-project-vibe-coding-prompts]]:

1. **The component inventory is hand-maintained in four places** (CLAUDE.md plugin table, README tables, forge-adapt's `references/*.md` maps, plugin.json descriptions) and nothing checks it against the tree. It drifted four separate times in the 2026-08-28 session, caught only by review agents. The extractor already exists (`scripts/forge-adapt-catalogue.sh`); only the rendering half and a `--check` gate are missing.

2. **There is no size budget for components.** `adapt/SKILL.md` is 7,357 words and `ticket-gate.md` is 5,794, against a 1,600-word cap for a whole prompt in the sister project. At that size the same rule ends up stated in four places and updated in two, which is precisely the finding shape that fired the review trip wire three times.

**Why:** both convert a recurring human-caught defect class into something mechanical, which is the repo's own stated preference (mechanical enforcement over prose persuasion, recorded in the CLAUDE.md boundary paragraph).

**How to apply:** when a review finds "this table is stale" or "this rule is stated in N places", treat it as an instance of one of these two, not as an isolated fix. Land #96 before #97 (the index provides the visibility the budget needs), and fix #95 before either, or the generated index will publish `vnone` for the adapt skill.
