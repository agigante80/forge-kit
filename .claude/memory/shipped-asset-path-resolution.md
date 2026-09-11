---
name: shipped-asset-path-resolution
description: An agent's Bash never gets CLAUDE_PLUGIN_ROOT; a missing asset degrades silently, and forge-adapt copies assets only because the write step says so
metadata:
  type: project
---

Verified 2026-09-07 while shipping `check-ticket-mechanics.sh` (#149). `$CLAUDE_PLUGIN_ROOT` is exported to HOOK processes, not to an agent's Bash. CLAUDE.md states that in its hooks paragraph, and I still used it four hundred lines later to resolve a shipped asset from inside `ticket-gate`, where it expands to nothing.

Under a marketplace install that produced a leading-slash path, the run failed, and the gate's own fallback turned the failure into every mechanical check `referred`. Step 3A was silently disabled for every plugin-installed user, which is the exact outcome the script existed to prevent.

A shipped asset resolves by SEARCH, never by that variable, and the search RANKS (#189, 2026-09-11):
the project copy, then a forge-kit checkout's own tree, then the highest `<name>-version` marker
across `~/.claude/plugins`, lexically LAST path as tie-break (`sort | tail -1`), and the pick printed, `none` when nothing was found and relative to `~` (`${MECH/#$HOME/\~}`: the
backslash is load-bearing, an unescaped `~` re-expands to `$HOME`). The earlier form of this note
ended in `find ~/.claude/plugins -name <name>.sh | head -1`, which picked a stale cached copy in
three gate runs of four, because the cache holds versions side by side and `find` order is
arbitrary. The canonical snippet is `ticket-gate.md` Step 1 (moved there from 3A by #192); `phase.md` carries
the same order as a function.

Two facts make this worse than an ordinary broken path. A missing asset is not an error anyone sees: the component degrades to its fallback and keeps returning verdicts, so it reads as working. And forge-adapt writes a skill as `SKILL.md` ALONE unless told otherwise, so an executable shipped in `assets/` is not installed at all until the write step copies it; naming the asset in a dependency list is the fragile version of that fix, because the list is what a new asset falls off.

**Why:** the failure is silent in both directions, so nothing surfaces it except reading the code or a review round that reproduces the install. Two consecutive rounds on PR #152 found a different face of it.

**How to apply:** when a component gains an executable, resolve its path under BOTH install shapes before shipping, and confirm forge-adapt actually copies it rather than assuming the skill carries it. [[hook-install-model]] is the hook-shaped version of the same three-install-shapes problem.
