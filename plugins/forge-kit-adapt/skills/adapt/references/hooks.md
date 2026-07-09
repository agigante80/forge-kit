# forge-kit hooks: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/hooks/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why" and the wiring.
Hooks are copied verbatim (never rewritten) and wired into `.claude/settings.json`.

| Signal in the project | Hook | Group | Event | Canonical "why" (≤60) | Wiring matcher |
|---|---|---|---|---|---|
| CLAUDE.md states a no-em/en-dash or strict writing rule | `block-dashes.py` | governance | PreToolUse | enforce the no-dash writing rule | `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` |
| `.forge.conf` present (repo migrated off GitHub to a self-hosted forge) | `block-legacy-host-push.py` | devops | PreToolUse | deny git push to the archived legacy host | `Bash` |

## Install detail (block-dashes.py)

**Branch on `$GOVERNANCE_PLUGIN_ACTIVE`, never on `$FORGE_KIT_SRC`.** The library's location says
nothing about which plugins are enabled, and `hooks/hooks.json` loads only when
`forge-kit-governance` itself is installed.

`yes`: the hook is already registered and running in every project. Do NOT copy the script and do
NOT touch `settings.json`; that installs a duplicate that fires alongside it. A plugin-registered
`block-dashes` stays dormant until the project opts in, so the whole install is
`mkdir -p .claude && touch .claude/no-dashes`. Remove any project-local copy an older forge-adapt
left behind (see SKILL.md). Opt out by deleting the sentinel.

`no`: nothing is registering the hook. Either suggest `/plugin install forge-kit-governance@forge-kit`,
or install into the project as below. Never both.

1. Copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/block-dashes.py` →
   `.claude/hooks/block-dashes.py` verbatim, preserving the `# block-dashes-version: N` marker.
   A copy under the project root is itself the opt-in; no sentinel is needed.
2. Merge into `.claude/settings.json` without clobbering existing hooks (see the Hooks step of
   SKILL.md for the `jq` merge). Do NOT skip when an entry already exists: the merge deliberately
   rewrites a legacy relative-path or shell-form entry into exec form in place. Skipping strands
   the project on broken wiring.
3. Confirm: `✓ block-dashes (hook): installed and wired in .claude/settings.json`.

When NOT to recommend: if CLAUDE.md has no writing-style rule, do not surface this hook. It is
opinionated and only valuable where the project has adopted the no-dash convention.

## Install detail (block-legacy-host-push.py)

1. Copy `$FORGE_KIT_DIR/plugins/forge-kit-devops/hooks/block-legacy-host-push.py` →
   `.claude/hooks/block-legacy-host-push.py` verbatim, preserving the
   `# block-legacy-host-push-version: N` marker.
2. Wire with matcher `Bash` ONLY (it reads `tool_input.command`; do not copy the
   block-dashes five-tool matcher). Same `jq` merge as above, with the same exec form and the
   same anchored path. Never a relative path:

   ```json
   { "type": "command", "command": "python3",
     "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-legacy-host-push.py"] }
   ```

   Unlike `block-dashes`, this hook is NOT registered by `hooks/hooks.json`, and must not be. The
   only signal a plugin-level hook could gate on is `.forge.conf`, which `github-to-forgejo` writes
   at the START of a migration, while this hook belongs at cutover. Between the two the skill
   supports a dual-remote / push-mirror window, and an auto-enabled hook would block the very
   legacy pushes that window exists to allow. Installing it into the project IS the cutover signal.
3. Confirm the repo is actually migrated: `.forge.conf` exists and the legacy host is
   archived/read-only. Optionally sanity-run `python3 .claude/hooks/block-legacy-host-push.py
   --self-test`.

When NOT to recommend: a repo still hosted on GitHub (no `.forge.conf`), or one that
deliberately dual-pushes during migration (install only at cutover, per the
`github-to-forgejo` skill Phase 5).
