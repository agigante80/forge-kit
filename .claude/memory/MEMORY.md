<!-- Memory index. Each line: - [Title](file.md) - one-line description (~150 chars max) -->
<!-- Add entries here as Claude Code builds up project memory across conversations. -->

- [Hook install model](hook-install-model.md) - plugin-registered vs project-local; why block-legacy-host-push is never plugin-registered; why the dormant gate lives in sh, not python
- [Sister project: vibe-coding-prompts](sister-project-vibe-coding-prompts.md) - Same author's prompt library; shares forge-kit's version-gate DNA and has mechanisms worth borrowing; cross-review 2026-08-28 filed tickets both ways
- [Recovering findings from a dead code-review fork](code-review-fork-recovery.md) - Subagent transcripts under subagents/agent-*.jsonl hold complete reports; recover rather than re-run, and check which SHA was reviewed
- [The review-loop trip wire in practice](bounded-review-loop-in-practice.md) - Fired 3 times in one day; close out by fixing merge-blockers only and ticketing the rest, and say so in the commit
- [Inventory drift and component size](generated-index-and-size-budget.md) - Four hand-maintained inventories and 5-7k-word components are the root cause behind repeated review findings; #95 then #96 then #97
