# forge-kit hooks — signal → component → why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/hooks/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why" and the wiring.
Hooks are copied verbatim (never rewritten) and wired into `.claude/settings.json`.

| Signal in the project | Hook | Group | Event | Canonical "why" (≤60) | Wiring matcher |
|---|---|---|---|---|---|
| CLAUDE.md states a no-em/en-dash or strict writing rule | `block-dashes.py` | governance | PreToolUse | enforce the no-dash writing rule | `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` |

## Install detail (block-dashes.py)

1. Copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/block-dashes.py` →
   `.claude/hooks/block-dashes.py` verbatim, preserving the `# block-dashes-version: N` marker.
2. Merge into `.claude/settings.json` without clobbering existing hooks (see Step 3 of SKILL.md
   for the `jq` merge). Skip if an equivalent PreToolUse entry already exists.
3. Confirm: `✓ block-dashes (hook) — installed and wired in .claude/settings.json`.

When NOT to recommend: if CLAUDE.md has no writing-style rule, do not surface this hook — it is
opinionated and only valuable where the project has adopted the no-dash convention.
