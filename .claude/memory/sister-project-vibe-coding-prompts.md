---
name: sister-project-vibe-coding-prompts
description: Same author's prompt library; shares forge-kit's version-gate DNA and has mechanisms worth borrowing; cross-review 2026-08-28 filed tickets both ways
metadata:
  type: reference
---

agigante80/vibe-coding-prompts is a sister project by the same author: a library of 14 versioned, platform-agnostic AI meta-prompts. It shares forge-kit's DNA (version-bump CI gate, no-dashes sentinel, docs standardization) and solved several problems forge-kit has not: a GENERATED README index with a `--check` CI gate (`scripts/update_prompt_index.py`), a per-prompt word budget with live counts, SHA-pinned actions in its own CI, and a two-stage pre-commit/pre-push hook split.

A full cross-review ran 2026-08-28. Filed there: #51 (OWASP Top 10:2025 cited but categories never listed), #52 (no SBOM or build provenance anywhere), #53 (new prompt: AI/LLM security, OWASP LLM Top 10), #54 (new prompt: AGENTS.md generator), plus a research comment on their existing #41 (accessibility). Filed here from what they do better: [[generated-index-and-size-budget]] covers #96 and #97; #98 covers CI self-hardening.

**Why:** the two repos solve the same governance problem from opposite ends (prose prompts pasted into a chat vs Claude-native components installed into a project), so each is the other's best source of borrowable mechanism and of honest scope comparison.

**How to apply:** before proposing anything to them, read their CLOSED issues first: every prompt already had a critical-review issue (#4 to #15) and #33 to #44 are existing prompt proposals, so duplicates are easy to file by accident. Their authoring standard is `docs/prompt-creation-guide.md`.
