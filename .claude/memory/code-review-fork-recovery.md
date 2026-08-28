---
name: code-review-fork-recovery
description: Subagent transcripts under subagents/agent-*.jsonl hold complete reports; recover rather than re-run, and check which SHA was reviewed
metadata:
  type: project
---

When the `/code-review` skill fork dies before producing its final report (rate limit, credit exhaustion, or simply ending its turn mid-verify), the findings are NOT lost. Each finder and verifier subagent writes a full transcript to `~/.claude/projects/<project-slug>/<session-id>/subagents/agent-*.jsonl`; the last assistant text block in each file is that agent's complete report, usually a JSON findings array.

Recover with a small python pass over the newest transcripts (filter by mtime against the orchestrator's own file, then print the last `message.content[].text` per file).

**Why:** this happened six or more times in the 2026-08-28 session (one fork hit a Fable 5 credit limit, several ended their turn while verifiers were still running). Every one of those rounds was fully recoverable, so a dead fork is a reporting failure, not a review failure. Re-running the review instead would burn the work twice and, on a quota error, fail again.

**How to apply:** when a review fork reports `failed` or completes with narration like "waiting on the last verifier", do not re-run it. Read the transcripts, treat the recovered findings as that round's output, and note in the fix commit that the round was recovered. Watch one trap: a recovered report may have been written against a commit you have since pushed over, so check which SHA it reviewed before treating a finding as live.
