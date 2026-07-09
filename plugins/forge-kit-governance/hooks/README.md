# forge-kit hooks

Canonical, project-agnostic Claude Code hooks.

**Installed as a plugin.** `hooks.json` in this directory registers `block-dashes` with Claude
Code, anchored to `${CLAUDE_PLUGIN_ROOT}`. No script is copied and no `settings.json` is touched.

This requires installing **this** plugin, which the quick-start flow does not do:

```
/plugin install forge-kit-governance@forge-kit
```

`/plugin install forge-kit-adapt@forge-kit` alone installs only the adapt skill. A plugin's
`hooks.json` is read only when that plugin is enabled, so without the line above nothing here is
registered and `forge-adapt` will install a project-local copy instead.

A plugin hook is live in every project, so `hooks.json` gates in the shell before spawning anything:
`sh` tests for the sentinel and exits, and only reaches `exec python3` where the project opted in.
That costs **1.8 ms** per matched tool call in a project that has not opted in, against **44 ms** if
Python were started first, since the interpreter pays for `site` and the stdlib imports before it
can read its own gate. The gate inside `block-dashes.py` is kept as defence in depth, for the
project-local install shape which has no wrapper.

The wrapper needs `sh` on `PATH`. That is a given on macOS and Linux; on Windows it means Git Bash.
Where `sh` is unavailable, use the project-local install instead.

Because the no-dash rule is opinionated and a plugin hook is live in *every* project, the script
stays dormant until a project opts in:

```bash
mkdir -p .claude && touch .claude/no-dashes   # opt in
rm .claude/no-dashes                          # opt out
```

**Installed from a clone.** With no plugin to register anything, `forge-adapt` copies the script
into the project's `.claude/hooks/` (hook scripts are stack-agnostic, so unlike agents and skills
they are never rewritten for the stack) and merges the `PreToolUse` block below into
`.claude/settings.json`. A copy living under the project root *is* the opt-in, so no sentinel is
needed. The script tells the two cases apart by its own location, which is why pre-existing
project installs keep working unchanged.

Both paths are covered by `scripts/test-hooks.py`, which runs in CI.

| Hook | Event | Version | Purpose |
|---|---|---|---|
| `block-dashes.py` | PreToolUse | 5 | Block em dash (U+2014) and en dash (U+2013) in Write/Edit/MultiEdit/NotebookEdit/Bash payloads. Fails open. |

Kit-wide inventory note: hooks live per plugin group. `forge-kit-devops` ships
`block-legacy-host-push.py` (PreToolUse on `Bash`: deny `git push` to an archived legacy
host after a forge migration; see `plugins/forge-kit-devops/hooks/` and the
`github-to-forgejo` skill Phase 5).

## block-dashes.py

The canonical superset of the four hand-rolled no-dash hooks that drifted across
projects (`no_dashes_hook.py`, `no-dash-check.sh`, `block-dashes.sh`, `check-dashes.sh`).
It covers more tools than any single variant, reports line + context per hit, and
restructure-don't-substitute guidance.

Wiring (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [
          { "type": "command", "command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dashes.py"] }
        ]
      }
    ]
  }
}
```

Version marker: the `# block-dashes-version: N` comment on line 2 lets a project
detect when its copy is behind the canonical.
