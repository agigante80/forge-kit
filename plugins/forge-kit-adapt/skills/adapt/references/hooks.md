# forge-kit hooks: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/hooks/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why" and the wiring.
Hooks are copied verbatim (never rewritten) and wired into `.claude/settings.json`.

| Signal in the project | Hook | Group | Event | Canonical "why" (≤60) | Wiring matcher |
|---|---|---|---|---|---|
| CLAUDE.md states a no-em/en-dash or strict writing rule | `block-dashes.py` | governance | PreToolUse | enforce the no-dash writing rule | `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` |
| `.forge.conf` present (repo migrated off GitHub to a self-hosted forge) | `block-legacy-host-push.py` | devops | PreToolUse | deny git push to the archived legacy host | `Bash` |

## Install detail (block-dashes.py)

1. Copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/block-dashes.py` →
   `.claude/hooks/block-dashes.py` verbatim, preserving the `# block-dashes-version: N` marker.
2. Merge into `.claude/settings.json` without clobbering existing hooks (see Step 3 of SKILL.md
   for the `jq` merge). Skip if an equivalent PreToolUse entry already exists.
3. Confirm: `✓ block-dashes (hook): installed and wired in .claude/settings.json`.

When NOT to recommend: if CLAUDE.md has no writing-style rule, do not surface this hook. It is
opinionated and only valuable where the project has adopted the no-dash convention.

## Install detail (block-legacy-host-push.py)

1. Copy `$FORGE_KIT_DIR/plugins/forge-kit-devops/hooks/block-legacy-host-push.py` →
   `.claude/hooks/block-legacy-host-push.py` verbatim, preserving the
   `# block-legacy-host-push-version: N` marker.
2. Wire with matcher `Bash` ONLY (it reads `tool_input.command`; do not copy the
   block-dashes five-tool matcher). Same `jq` merge as above.
3. Confirm the repo is actually migrated: `.forge.conf` exists and the legacy host is
   archived/read-only. Optionally sanity-run `python3 .claude/hooks/block-legacy-host-push.py
   --self-test`.

When NOT to recommend: a repo still hosted on GitHub (no `.forge.conf`), or one that
deliberately dual-pushes during migration (install only at cutover, per the
`github-to-forgejo` skill Phase 5).
