# Design: `closing-sessions` skill

Date: 2026-07-11
Status: approved design, pending spec review then implementation plan

## Problem

A conversation's context is finite and lossy. When it grows long the harness
summarises older turns, and when a session ends the chat is gone entirely: a new
session starts blind. Anything decided, learned, or left half-done that was never
written to a durable file is living on borrowed time. Today nothing moves from the
conversation into persistent storage automatically; it depends on the agent
happening to write a memory file mid-flight.

This skill gives the user one deliberate action, taken at the end of a working
session, that sweeps the conversation and persists what mattered before it is lost.

## Goal

On invocation, extract capture-worthy material from the current conversation,
sort each item by how long it stays useful, and write it to the right place:

- durable atomic facts to the project's `.claude/memory/` store, and
- transient "where we left off" state to a dated handoff note.

## Non-goals

- Not a full transcript dump. Per the handoff research, save just enough for the
  next session to make good decisions quickly, not everything.
- Not a git wrapper. It writes files and stops; the user reviews with `git diff`
  and commits per the repo's own workflow rule.
- Not an automatic trigger. It is manually invoked (see Reliability, below).

## Resolved decisions

| Decision | Choice | Rationale |
|---|---|---|
| Home | `forge-kit-governance` plugin group | Governance already holds agent-discipline components; session-memory hygiene is the same category. No new group to register. |
| Output | Both memory files and a handoff note, skill classifies each item | One conversation scan feeds both; splitting into two skills would duplicate the scan. |
| Write mode | Fully autonomous (create, update, delete) with no confirmation | User preference: lowest friction at the moment of leaving. Risk is accepted and documented below, reviewed after the fact via `git diff`. |
| Naming | `closing-sessions` (gerund form) | Strict adherence to Anthropic's naming guidance. |
| Mechanical writes | A deterministic helper script | Anthropic: deterministic code for deterministic work. Frontmatter and index-line integrity are mechanical and easy to get subtly wrong by hand. |
| Rubric source | Reference the existing `.claude/memory/` convention, do not restate it | Avoids a second copy of the memory rules that would drift from the global instructions; keeps the skill concise. |
| Handoff location | `.claude/handoffs/` | Keeps all agent/session state under `.claude/`; nothing agent-related leaks into `docs/`. |

## Accepted risk: fully autonomous destructive writes

The dedup step can update or delete an existing memory file. Fully autonomous means
a misjudged "this supersedes that" can overwrite or remove a real memory with no
prompt. The mitigation is entirely after the fact: every run reports exactly what it
touched, and the user reviews with `git diff` before committing. Because memory lives
in git, any bad write is recoverable from the last commit. This is a deliberate
speed-over-safety trade, not an oversight.

## Component layout

```
plugins/forge-kit-governance/skills/closing-sessions/
  SKILL.md                     # trigger + procedure + rubric (references memory convention)
  scripts/
    memory.py                  # deterministic memory-file + index writer/remover
```

Outputs, in the target project (or in forge-kit itself when it dogfoods the skill):

```
.claude/memory/<slug>.md       # one durable fact per file (existing convention)
.claude/memory/MEMORY.md       # index, one line appended per new memory
.claude/handoffs/YYYY-MM-DD-<topic>.md   # transient resume note, dated, accumulating
```

## SKILL.md shape

- `name: closing-sessions`
- `description`: third person, carries trigger terms so it activates at the right
  moment. Covers phrases like "close the session", "wrap up", "before I go",
  "end of session", "save what we discussed", plus what it does (persist durable
  facts to `.claude/memory/` and a handoff note to `.claude/handoffs/`).
- Version marker `<!-- closing-sessions-version: 1 -->` within the first few lines
  (positional-parse rule shared by validate-plugins.sh, check-version-bump.sh, and
  the pre-commit hook).
- Body kept well under the 500-line guidance; no nested references.

## Procedure (what the skill instructs the agent to do)

1. Scan the conversation from session start (or since the last `closing-sessions`
   run) for capture-worthy material.
2. Classify each item by lifespan (rubric below).
3. Dedup durable items against existing `.claude/memory/` files: update the matching
   file rather than create a duplicate, and delete any memory this session proved
   wrong.
4. Write autonomously: run `scripts/memory.py` for each durable item, and write one
   handoff note for the transient state.
5. Report a summary and stop. No commit.

## Routing rubric

The skill does not restate the memory schema; it points at the standard
`.claude/memory/` convention (frontmatter with `type: user | feedback | project |
reference`, the `**Why:** / **How to apply:**` lines for feedback and project, the
`[[name]]` links, and the skip rules for anything already in code, git, or CLAUDE.md).

The only new logic the skill adds is the lifespan split:

- Durable atomic fact (identity, feedback with why, ongoing project constraint,
  external reference) goes to `.claude/memory/` via the helper script.
- Transient resume state (what we did, what is unfinished, next steps, open
  questions, key context to reload) goes to a single dated handoff note.
- Anything already recorded elsewhere, or that only mattered to this one chat, is
  skipped.

## Handoff note template

Following the convergent handoff-message guidance (what was in progress, what was
decided and why, what needs attention next, what can safely wait, what we are
waiting on):

```markdown
# Session handoff: <topic>

Date: YYYY-MM-DD

## Summary
One or two sentences on what this session was about.

## Done this session
- ...

## In progress (where we left off)
- ...

## Next steps
1. ...

## Decisions and why
- Decided X because Y.

## Open questions / blocked on
- ...

## Key context to reload
- Files, commands, links the next session should pull up first.
```

Notes accumulate (one per close). They are safe to prune by hand; the skill never
deletes them, so no handoff history is ever lost silently.

## Helper script: `scripts/memory.py`

Deterministic, so frontmatter and index integrity do not depend on the model being
careful each time. Two subcommands:

- `write --slug <slug> --type <user|feedback|project|reference> --description <text>`
  with the body on stdin: creates or overwrites `.claude/memory/<slug>.md` with
  correct frontmatter, then ensures exactly one matching line exists in
  `.claude/memory/MEMORY.md` (creating `MEMORY.md` with its header if absent).
- `remove --slug <slug>`: deletes the memory file and removes its index line.

Per Anthropic's "solve, do not punt": if `MEMORY.md` is missing the script creates
it; if the index directory is missing it is created; a re-run for an existing slug
updates in place rather than duplicating the index line. No voodoo constants.

The script is an asset of the skill, so a material change to it bumps the
`closing-sessions` version marker (there is no separate marker for the script).

## Reliability gap (stated honestly, not fixed)

The skill only runs when the user remembers to invoke it, which is the same failure
mode it exists to prevent. A Claude Code SessionEnd hook could fire automatically,
but a hook is a plain shell process with no view of the conversation, so it cannot do
the intelligent sweep; it could at most leave a breadcrumb reminder. Therefore the
smart work stays a manually-invoked skill and this gap is real. A future
lightweight SessionEnd reminder hook is a possible follow-up, out of scope here.

## Shipping and CI

- Bump `forge-kit-governance` `plugin.json` version (a new component is added).
- Add `.claude/handoffs/.gitkeep` and a `.gitignore` note if the project wants the
  directory tracked but empty, mirroring how `temp/` is handled. In forge-kit itself,
  create `.claude/handoffs/` so the dogfooded skill has somewhere to write.
- `bash scripts/validate-plugins.sh` (checks the version marker is present).
- `git fetch origin main` then `bash scripts/check-version-bump.sh origin/main`.
- All files free of em and en dashes (this repo blocks them on write).

## Testing and acceptance

forge-kit cannot run a skill in isolation (only hooks have a mechanical harness
here), so evaluation is behavioural: install the skill into a throwaway project via
forge-adapt, hold a short working conversation, invoke `closing-sessions`, and
confirm the memory files, the `MEMORY.md` index line, and the handoff note are all
written correctly and that `git diff` shows exactly what the run reported. The helper
script's index logic (create-if-missing, no-duplicate-on-rerun, clean removal) is the
one piece that could be exercised directly with a small fixture.

## Follow-ups (out of scope)

- Add a forge-adapt recommender-reference row so `drift`/install surfaces the skill.
- Consider the SessionEnd reminder hook noted under Reliability.
