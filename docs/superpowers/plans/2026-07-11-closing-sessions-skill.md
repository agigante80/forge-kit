# closing-sessions Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `closing-sessions` skill in `forge-kit-governance` that, on invocation, sweeps the conversation and persists durable facts to `.claude/memory/` and transient resume state to a dated `.claude/handoffs/` note.

**Architecture:** A markdown SKILL.md holds the judgment-based procedure (scan, classify by lifespan, route, report). A deterministic `memory.py` helper does the mechanical writes so frontmatter and MEMORY.md index integrity do not depend on the model formatting them by hand. The helper is the only unit-testable surface; SKILL.md is verified through the repo's structural gates and a behavioural install test.

**Tech Stack:** Python 3 standard library only (mirrors `scripts/test-hooks.py`), markdown, jq/GNU-grep-based validation scripts already in the repo.

## Global Constraints

- No em dash (U+2014) or en dash (U+2013) in any created or edited file. The repo's `block-dashes` hook is wired on `Write|Edit` and denies the tool call otherwise. Use the ASCII hyphen.
- Python scripts use `python3` and the standard library only. No third-party packages, no network.
- All file paths use forward slashes.
- Skill name is strictly gerund form: `closing-sessions`.
- SKILL.md carries the marker `<!-- closing-sessions-version: 1 -->` as the first version-shaped token in the file, within the first few lines (positional parse shared by `validate-plugins.sh`, `check-version-bump.sh`, and `.githooks/pre-commit`; `template-version` is skipped only when it leads).
- Memory index line format is `- [<Title>](<slug>.md) - <description>` with an ASCII hyphen separator, matching the existing `.claude/memory/MEMORY.md`.
- Governance `plugin.json` version bumps from `0.1.5` to `0.2.0` (a new feature is added).
- The helper script is an asset of the skill; a material change to it bumps the `closing-sessions` marker (there is no separate marker for the script).

---

### Task 1: memory.py `write` subcommand and MEMORY.md index management

**Files:**
- Create: `plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py`
- Test: `scripts/test-closing-sessions-memory.py`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a CLI `python3 plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py [--project-dir DIR] write --slug SLUG --title TITLE --type {user,feedback,project,reference} --description DESC` that reads the memory body from stdin, writes `<DIR>/.claude/memory/<slug>.md`, and upserts one line in `<DIR>/.claude/memory/MEMORY.md`. `--project-dir` defaults to `.`.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-closing-sessions-memory.py`:

```python
#!/usr/bin/env python3
"""Behavioural tests for the closing-sessions memory.py helper.

Runs the helper as a subprocess against a throwaway project directory, the same
way scripts/test-hooks.py exercises the hooks. Standard library only.
"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(
    HERE, "..", "plugins", "forge-kit-governance",
    "skills", "closing-sessions", "scripts", "memory.py",
)


def run(project_dir, args, body=""):
    return subprocess.run(
        [sys.executable, SCRIPT, "--project-dir", project_dir, *args],
        input=body, capture_output=True, text=True,
    )


def read(project_dir, *parts):
    with open(os.path.join(project_dir, ".claude", "memory", *parts), encoding="utf-8") as f:
        return f.read()


class WriteTests(unittest.TestCase):
    def test_write_creates_memory_file(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                        "--type", "project", "--description", "a short hook"],
                    body="The body.")
            self.assertEqual(r.returncode, 0, r.stderr)
            content = read(d, "my-fact.md")
            self.assertIn("name: my-fact", content)
            self.assertIn("description: a short hook", content)
            self.assertIn("type: project", content)
            self.assertIn("The body.", content)

    def test_write_creates_index_with_header_and_line(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "a short hook"], body="b")
            idx = read(d, "MEMORY.md")
            self.assertIn("Memory index", idx)
            self.assertIn("- [My Fact](my-fact.md) - a short hook", idx)

    def test_write_is_idempotent_and_updates_in_place(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "first"], body="b")
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "second"], body="b2")
            idx = read(d, "MEMORY.md")
            self.assertEqual(idx.count("(my-fact.md)"), 1)
            self.assertIn("- [My Fact](my-fact.md) - second", idx)
            self.assertNotIn("first", idx)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test-closing-sessions-memory.py -v`
Expected: FAIL. The helper does not exist yet, so each subprocess returns nonzero and the `assertEqual(r.returncode, 0)` assertions fail (or the file reads raise FileNotFoundError).

- [ ] **Step 3: Write minimal implementation**

Create `plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py`:

```python
#!/usr/bin/env python3
"""Deterministic writer/remover for .claude/memory/ files and the MEMORY.md index.

Used by the closing-sessions skill so frontmatter and index integrity do not
depend on the model formatting them by hand each time. Standard library only.
"""
import argparse
import os
import re
import sys

MEMORY_SUBDIR = os.path.join(".claude", "memory")
INDEX_NAME = "MEMORY.md"
INDEX_HEADER = (
    "<!-- Memory index. Each line: - [Title](file.md) - one-line description (~150 chars max) -->\n"
    "<!-- Add entries here as Claude Code builds up project memory across conversations. -->\n"
)


def memory_dir(project_dir):
    return os.path.join(project_dir, MEMORY_SUBDIR)


def index_path(project_dir):
    return os.path.join(memory_dir(project_dir), INDEX_NAME)


def memory_path(project_dir, slug):
    return os.path.join(memory_dir(project_dir), slug + ".md")


def render_memory(slug, mem_type, description, body):
    return (
        "---\n"
        f"name: {slug}\n"
        f"description: {description}\n"
        "metadata:\n"
        f"  type: {mem_type}\n"
        "---\n\n"
        f"{body.rstrip()}\n"
    )


def index_line(title, slug, description):
    return f"- [{title}]({slug}.md) - {description}\n"


def read_index(project_dir):
    path = index_path(project_dir)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def write_index(project_dir, content):
    os.makedirs(memory_dir(project_dir), exist_ok=True)
    with open(index_path(project_dir), "w", encoding="utf-8") as f:
        f.write(content)


def line_pattern(slug):
    return re.compile(
        r"^- \[.*\]\(" + re.escape(slug) + r"\.md\).*$",
        re.MULTILINE,
    )


def upsert_index_line(project_dir, title, slug, description):
    existing = read_index(project_dir)
    line = index_line(title, slug, description)
    if existing is None:
        write_index(project_dir, INDEX_HEADER + "\n" + line)
        return
    pattern = line_pattern(slug)
    if pattern.search(existing):
        write_index(project_dir, pattern.sub(line.rstrip("\n"), existing))
        return
    if not existing.endswith("\n"):
        existing += "\n"
    write_index(project_dir, existing + line)


def remove_index_line(project_dir, slug):
    existing = read_index(project_dir)
    if existing is None:
        return
    pattern = re.compile(
        r"^- \[.*\]\(" + re.escape(slug) + r"\.md\).*\n?",
        re.MULTILINE,
    )
    write_index(project_dir, pattern.sub("", existing))


def cmd_write(args):
    body = sys.stdin.read()
    os.makedirs(memory_dir(args.project_dir), exist_ok=True)
    with open(memory_path(args.project_dir, args.slug), "w", encoding="utf-8") as f:
        f.write(render_memory(args.slug, args.type, args.description, body))
    upsert_index_line(args.project_dir, args.title, args.slug, args.description)


def cmd_remove(args):
    path = memory_path(args.project_dir, args.slug)
    if os.path.exists(path):
        os.remove(path)
    remove_index_line(args.project_dir, args.slug)


def build_parser():
    p = argparse.ArgumentParser(
        description="Write or remove .claude/memory/ files and keep MEMORY.md in sync.")
    p.add_argument("--project-dir", default=".",
                   help="Project root containing .claude/ (default: current directory)")
    sub = p.add_subparsers(dest="command", required=True)

    w = sub.add_parser("write", help="Create or overwrite a memory file and upsert its index line")
    w.add_argument("--slug", required=True)
    w.add_argument("--title", required=True)
    w.add_argument("--type", required=True,
                   choices=["user", "feedback", "project", "reference"])
    w.add_argument("--description", required=True)
    w.set_defaults(func=cmd_write)

    r = sub.add_parser("remove", help="Delete a memory file and its index line")
    r.add_argument("--slug", required=True)
    r.set_defaults(func=cmd_remove)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test-closing-sessions-memory.py -v`
Expected: PASS for the three `WriteTests` (the `remove` subcommand is defined but not yet tested until Task 2).

- [ ] **Step 5: Commit**

```bash
git add scripts/test-closing-sessions-memory.py plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py
git commit -m "feat(closing-sessions): deterministic memory.py write + index upsert"
```

---

### Task 2: memory.py `remove` subcommand

**Files:**
- Modify: `scripts/test-closing-sessions-memory.py` (add `RemoveTests`)
- Modify: `plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py` (already contains `remove`; this task proves it)

**Interfaces:**
- Consumes: the `write` CLI from Task 1.
- Produces: `... remove --slug SLUG` deletes `<DIR>/.claude/memory/<slug>.md` and removes its index line; a remove of a slug that does not exist exits 0 and changes nothing.

- [ ] **Step 1: Write the failing test**

Append to `scripts/test-closing-sessions-memory.py`, before the `if __name__` block:

```python
class RemoveTests(unittest.TestCase):
    def test_remove_deletes_file_and_index_line(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "gone", "--title", "Gone",
                    "--type", "user", "--description", "temp"], body="b")
            r = run(d, ["remove", "--slug", "gone"])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(
                os.path.join(d, ".claude", "memory", "gone.md")))
            self.assertNotIn("(gone.md)", read(d, "MEMORY.md"))

    def test_remove_missing_slug_is_noop(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, ["remove", "--slug", "never-existed"])
            self.assertEqual(r.returncode, 0, r.stderr)
```

- [ ] **Step 2: Run test to verify the new tests pass and nothing regressed**

Run: `python3 scripts/test-closing-sessions-memory.py -v`
Expected: PASS for all five tests. `remove` was implemented in Task 1's script, so these pass immediately; if `test_remove_missing_slug_is_noop` fails with a nonzero exit, confirm `remove_index_line` and `cmd_remove` return cleanly when the file and index are absent.

Note: this task has no separate red phase because `remove` shipped whole in Task 1. If you prefer a strict red, temporarily rename the `remove` subparser, watch the tests fail with an argparse error, then restore it.

- [ ] **Step 3: Commit**

```bash
git add scripts/test-closing-sessions-memory.py
git commit -m "test(closing-sessions): cover memory.py remove and no-op removal"
```

---

### Task 3: Author SKILL.md

**Files:**
- Create: `plugins/forge-kit-governance/skills/closing-sessions/SKILL.md`

**Interfaces:**
- Consumes: the `memory.py` CLI from Tasks 1 and 2.
- Produces: a triggerable skill named `closing-sessions`.

- [ ] **Step 1: Write SKILL.md**

Create `plugins/forge-kit-governance/skills/closing-sessions/SKILL.md`:

````markdown
---
name: closing-sessions
description: Persist what mattered from the current conversation before the session ends or context is lost. Writes durable facts (user identity, feedback with rationale, ongoing project constraints, references) to the project's .claude/memory/ store and transient resume state (what was done, what is unfinished, next steps, open questions) to a dated .claude/handoffs/ note. Use when the user says to close the session, wrap up, save what we discussed, or before they step away.
---

<!-- closing-sessions-version: 1 -->

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
````

- [ ] **Step 2: Verify the marker parses and the plugin structure is valid**

Run: `bash scripts/validate-plugins.sh`
Expected: PASS, with no complaint about a missing or malformed `closing-sessions` marker. If it reports the marker missing, confirm `<!-- closing-sessions-version: 1 -->` is the first `<name>-version: N` string in the file.

- [ ] **Step 3: Confirm no banned dashes slipped in**

Run: `grep -nP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/skills/closing-sessions/SKILL.md`
Expected: no output (exit 1). Any match must be rewritten with an ASCII hyphen or restructured. Note the `block-dashes` hook would also have denied the Write if a dash were present.

- [ ] **Step 4: Commit**

```bash
git add plugins/forge-kit-governance/skills/closing-sessions/SKILL.md
git commit -m "feat(closing-sessions): add SKILL.md procedure and handoff template"
```

---

### Task 4: Wire into forge-kit and pass all gates

**Files:**
- Modify: `plugins/forge-kit-governance/.claude-plugin/plugin.json` (version and description)
- Create: `.claude/handoffs/.gitkeep`
- Modify: `.gitignore` (keep the handoffs directory tracked but note it holds session artifacts)

**Interfaces:**
- Consumes: the completed skill from Tasks 1 to 3.
- Produces: a governance plugin at version `0.2.0` that includes the skill, plus a tracked `.claude/handoffs/` directory for forge-kit's own dogfooding.

- [ ] **Step 1: Bump the governance plugin version and description**

Edit `plugins/forge-kit-governance/.claude-plugin/plugin.json`:

```json
{
  "name": "forge-kit-governance",
  "description": "ticket-gate agent, gate-ticket command, block-dashes hook, closing-sessions skill",
  "version": "0.2.0"
}
```

- [ ] **Step 2: Create the handoffs directory for dogfooding**

```bash
mkdir -p .claude/handoffs
: > .claude/handoffs/.gitkeep
```

- [ ] **Step 3: Keep the handoffs directory tracked**

Edit `.gitignore` to add, near the existing `temp/` entries:

```
# session handoff notes written by the closing-sessions skill (kept tracked)
!.claude/handoffs/
```

Only add this if a broader ignore rule would otherwise swallow the directory; if `.claude/` is already fully tracked, the `.gitkeep` alone is enough and this step is a no-op. Confirm with `git status` that `.claude/handoffs/.gitkeep` is stageable.

- [ ] **Step 4: Run the full gate suite**

```bash
bash scripts/validate-plugins.sh
python3 scripts/test-closing-sessions-memory.py
git fetch origin main
bash scripts/check-version-bump.sh origin/main
```

Expected: `validate-plugins.sh` passes (structure, semver, markers). The memory test passes all five cases. `check-version-bump.sh` passes: the new skill carries a `closing-sessions` marker at version 1, and the governance `plugin.json` semver moved from `0.1.5` to `0.2.0`. If `check-version-bump.sh` complains that the base ref is missing, re-run the `git fetch origin main` first.

- [ ] **Step 5: Commit**

```bash
git add plugins/forge-kit-governance/.claude-plugin/plugin.json .claude/handoffs/.gitkeep .gitignore
git commit -m "feat(closing-sessions): register skill in governance plugin and dogfood handoffs dir"
```

---

## Manual acceptance (behavioural, outside this repo)

forge-kit cannot run a skill in isolation, so after the tasks above, validate the
end-to-end behaviour once:

1. Install the skill into a throwaway project (via forge-adapt, or copy the skill
   directory into that project's `.claude/skills/`).
2. Hold a short working conversation there, then invoke the skill ("close the
   session").
3. Confirm the memory files, the `MEMORY.md` index line, and the dated handoff note
   are written correctly, and that `git diff` in that project shows exactly what the
   run reported.

## Follow-ups (out of scope)

- Add a forge-adapt recommender-reference row so `drift`/install surfaces the skill.
- Consider a lightweight SessionEnd reminder hook that nudges the user to run the
  skill (a hook cannot do the sweep itself, only remind).
