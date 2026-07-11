---
name: closing-sessions
description: Persist what mattered from the current conversation before the session ends or context is lost. Writes durable facts (user identity, feedback with rationale, ongoing project constraints, references) to the project's .claude/memory/ store and transient resume state (what was done, what is unfinished, next steps, open questions) to a dated .claude/handoffs/ note. Use when the user says to close the session, wrap up, save what we discussed, or before they step away.
---

<!-- closing-sessions-version: 2 -->

# Closing sessions

When the user asks to close out, wrap up, or save the session, capture what is
worth keeping from this conversation before it is summarised away or lost, then
report what was written.

Writes are autonomous: create, update, and delete happen without a confirmation
prompt. Every run ends with a report of exactly what changed so the user can
review with `git diff` and recover from git if a write was wrong.

## Procedure

Copy this checklist and work through it:

```
- [ ] Step 1: Scan the conversation for capture-worthy material
- [ ] Step 2: Classify each item by lifespan
- [ ] Step 3: Dedup durable items against existing .claude/memory/
- [ ] Step 4: Write memory files and one handoff note
- [ ] Step 5: Report what changed
```

### Step 1: Scan

Review the conversation since it began (or since the last time this skill ran).
Collect decisions, stated preferences, constraints, references, and unfinished
work. Skip anything already captured in code, git history, or CLAUDE.md, and
anything that only mattered to this one exchange.

### Step 2: Classify by lifespan

- Durable atomic fact -> a `.claude/memory/` file. This includes who the user is,
  feedback on how to work (with the why), ongoing project constraints or goals not
  derivable from the code, and external references (URLs, dashboards, tickets).
- Transient resume state -> the handoff note. This includes what was done, what is
  in progress, next steps, open questions, and the context the next session should
  reload first.

### Step 3: Dedup

For each durable item, check the existing `.claude/memory/` files. If one already
covers it, update that file rather than create a duplicate. Delete any memory this
session proved wrong.

### Step 4: Write

For memory, follow the standard `.claude/memory/` convention already documented in
the project's instructions (frontmatter with `name`, `description`, and
`metadata.type` of `user`, `feedback`, `project`, or `reference`; the
`**Why:**` and `**How to apply:**` lines for `feedback` and `project`; `[[name]]`
links between related memories; relative dates converted to absolute). Do not
hand-format the file or the index. Run the helper, which writes the file and keeps
`MEMORY.md` in sync:

```bash
printf '%s' "<body text>" | python3 "$CLAUDE_PROJECT_DIR/plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py" \
  --project-dir "$CLAUDE_PROJECT_DIR" \
  write --slug "<kebab-slug>" --title "<Human Title>" --type "<type>" --description "<one-line hook>"
```

To remove a memory the session invalidated:

```bash
python3 "$CLAUDE_PROJECT_DIR/plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py" \
  --project-dir "$CLAUDE_PROJECT_DIR" remove --slug "<kebab-slug>"
```

When the skill is installed project-locally (under `.claude/skills/`), adjust the
script path to where it was installed. When run from the project root, the
`--project-dir` flag can be omitted (it defaults to the current directory).

For the handoff note, write one file at
`.claude/handoffs/<YYYY-MM-DD>-<topic>.md` using this template:

```markdown
# Session handoff: <topic>

Date: <YYYY-MM-DD>

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

Handoff notes accumulate, one per close. Never delete a handoff note; they are the
only record of past sessions and are safe for the user to prune by hand.

### Step 5: Report

Print a short summary and stop. Do not commit. Example:

```
Session-close complete.
  Memory:  2 written, 1 updated, 1 removed  (.claude/memory/)
  Handoff: .claude/handoffs/2026-07-11-<topic>.md
  Skipped: 3 items already in CLAUDE.md or git
Review with: git diff
```
