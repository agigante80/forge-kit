# forge-kit hooks

Canonical, project-agnostic Claude Code hooks. Unlike agents/skills/commands, hooks
are not yet auto-installed by `forge-adapt` (Phase 4). Copy the script into a project's
`.claude/hooks/` and wire it in `.claude/settings.json` manually. forge-adapt hook
installation is a planned enhancement.

| Hook | Event | Version | Purpose |
|---|---|---|---|
| `block-dashes.py` | PreToolUse | 1 | Block em dash (U+2014) and en dash (U+2013) in Write/Edit/MultiEdit/NotebookEdit/Bash payloads. Fails open. |

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
          { "type": "command", "command": "python3 .claude/hooks/block-dashes.py" }
        ]
      }
    ]
  }
}
```

Version marker: the `# block-dashes-version: N` comment on line 2 lets a project
detect when its copy is behind the canonical.
