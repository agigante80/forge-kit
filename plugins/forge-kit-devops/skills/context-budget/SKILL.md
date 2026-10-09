---
name: context-budget
description: Measure, in characters, how much a project's next Claude Code session loads before the first prompt (CLAUDE.md, its transitive @-imports and the loaded portion of the auto-memory MEMORY.md), against a 40,000 warn and 80,000 fail budget, and sweep several projects for drift. Use when the user asks "how big is my startup context", "is CLAUDE.md too large", "measure context budget", "which of my repos load the most", or before pruning a CLAUDE.md.
---

<!-- context-budget-version: 1 -->

# Context budget

Every `@`-import in `CLAUDE.md` is paid at the start of every session, every subagent that
inherits it, and every compaction. One downstream repository reached about 258 KB that way, and
nothing measured it (#297). Claude Code's own notice is interactive, per session, and has no exit
code. `assets/context-budget.sh` is the number a script or a CI job can read.

It measures and reports. **It never edits**, and neither does anything that calls it: pruning is
the owning project's own session's work, by the recipe in `docs/guides/startup-context.md`.

## Run it

```bash
bash <this skill>/assets/context-budget.sh [<repo-dir>]        # one repository, default .
bash <this skill>/assets/context-budget.sh --sweep <root>...   # one row per repository found
```

A single-repository run prints each counted file with its size and hop, the total, the import
count, the level, the fail level, the whole `MEMORY.md` size as a non-counted line, and any
**move candidate**: a `##` section over 8,000 characters, named by line, size and heading. A
sweep prints rows in descending total and exits 0 whatever the levels; it prints line and size
for a move candidate, never the heading, because it reads other projects' files.

| Total | Level | Exit |
|---|---|---|
| under 40,000 | `ok` | 0 |
| 40,000 to the fail level less one | `warn`, plus a `WARN` line on stderr | 0 |
| the fail level or more (80,000 unless raised) | `FAIL`, plus a `FAIL` line on stderr | 1 |
| a refused marker or a usage error | | 2 |

## What is counted, and what is not

Counted: `<repo-dir>/CLAUDE.md`, its `@`-imports to four hops with each file once, and the first
200 lines or 25,000 bytes of the auto-memory `MEMORY.md`, whichever is less. The unit is
characters, the CLI's own unit, and the figure is the same in every locale.

Not counted: ancestor `CLAUDE.md` files, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
lazily loaded subdirectory `CLAUDE.md` files, imports outside the project, and a custom
`autoMemoryDirectory`. Block HTML comments are counted as written although the CLI strips them,
so the figure is an upper bound there. The guide records each difference.

## Raising one project's level

A project that needs more than 80,000 puts exactly one marker in its root `CLAUDE.md`:

```markdown
<!-- context-budget: 95000 reason: the API reference must load in every session -->
```

N is a whole number above 80,000, and the reason is required. The marker raises the level and
never lowers it or removes it. A marker breaking any rule is refused: stderr names the rule, the
default levels apply, and the exit code is 2. The reason is never printed.

## Wiring

It is wired into **no hook, workflow or pre-push** by default. A project that wants a gate adds
it to its own CI or pre-push; the guide shows both. `health-check` reports the figure as one
advisory row, and `forge-adapt` recommends this skill when a `CLAUDE.md` is large or imports.

**Never commit a report.** Its paths embed home-directory names and the auto-memory slug.
