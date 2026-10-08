# forge-kit hooks: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/hooks/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why" and the wiring.
Hooks are copied verbatim (never rewritten) and wired into `.claude/settings.json`.

| Signal in the project | Hook | Group | Event | Canonical "why" (≤60) | Wiring matcher |
|---|---|---|---|---|---|
| CLAUDE.md states a no-em/en-dash or strict writing rule | `block-dashes.py` | governance | PreToolUse | enforce the no-dash writing rule | `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` |
| the project dispatches subagents (`ticket-gate`, `/full-review` or `working-overnight` installed) | `no-poll-loops.py` | governance | PreToolUse | stop shell waits on dispatched subagents | `Bash\|Monitor` |
| `working-overnight` is installed, or CLAUDE.md states a rule against destructive commands (`rm -rf`, `git reset --hard`, discarding uncommitted work) | `overnight-guard.py` | governance | PreToolUse | deny destructive git and rm -rf, day and night | `Bash` |
| the project has a test or check runner (`scripts/test-*` or `scripts/check-*`, a `package.json` test script, `pytest`, a `Makefile` test target, `Cargo.toml`, `go.mod`) | `masked-exit-advisory.py` | governance | PostToolUse | flag a check whose exit code a pipe masks | `Bash` |
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

## Install detail (no-poll-loops.py)

The hook has its OWN sentinel, `.claude/no-poll-loops` (one file per hook, same shape as
`.claude/no-dashes`), and **forge-adapt creates it on every install, in both shapes**, so the hook
can never be installed switched off. A hook behind a sentinel nothing creates fixes nothing. The
script checks the sentinel itself, so a project-local copy is NOT opted in by its location the way
`block-dashes` is: without the file it is inert.

Branch on `$GOVERNANCE_PLUGIN_ACTIVE`, as for `block-dashes`:

`yes`: the plugin's `hooks.json` already registers the hook, shell-gated on the sentinel. Do NOT
copy the script and do NOT touch `settings.json`. The whole install is:

```bash
mkdir -p .claude && touch .claude/no-poll-loops
```

`no`: copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/no-poll-loops.py` verbatim to
`.claude/hooks/no-poll-loops.py` (keep the `# no-poll-loops-version: N` marker), merge a `Bash|Monitor`
entry into `.claude/settings.json` with the same `jq` merge and exec form as `block-dashes`
(`"command": "python3"`, `"args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/no-poll-loops.py"]`), then
create the sentinel with the command above.

Confirm: `✓ no-poll-loops (hook): armed via .claude/no-poll-loops`. Opt out later by deleting the
sentinel. Optionally sanity-run `python3 .claude/hooks/no-poll-loops.py --self-test` (project-local
shape). The deny pattern is in the hook's own header and `hooks/README.md`; do not restate it.

When NOT to recommend: a project that installs none of the components that dispatch subagents.

## Install detail (overnight-guard.py)

The hook has two arms behind one script: the overnight arm (armed by a `working-overnight` run's
own `.claude/overnight/active.md`) and a daytime arm armed by its OWN sentinel,
`.claude/no-destructive` (one file per hook, same shape as `.claude/no-poll-loops`). **forge-adapt
creates the daytime sentinel on every install, in both shapes**, so the hook can never be installed
switched off. The script checks the sentinels itself and has no path-shape logic, so a project-local
copy is NOT opted in by its location: without the file it is inert by day. The daytime arm denies
the git discards and `rm -rf` of a dangerous or wildcard target; the patterns are in the hook's own
header and `hooks/README.md`, so do not restate them. Tell the user the daytime arm exists and how
to switch it off before creating the file.

Branch on `$GOVERNANCE_PLUGIN_ACTIVE`, as for `block-dashes`:

`yes`: the plugin's `hooks.json` already registers the hook, shell-gated on both sentinels. Do NOT
copy the script and do NOT touch `settings.json`. The whole install is:

```bash
mkdir -p .claude && touch .claude/no-destructive
```

`no`: copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/overnight-guard.py` verbatim to
`.claude/hooks/overnight-guard.py` (keep the `# overnight-guard-version: N` marker), merge a `Bash`
entry into `.claude/settings.json` with the same `jq` merge and exec form as `block-dashes`
(`"command": "python3"`, `"args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/overnight-guard.py"]`),
then create the sentinel with the command above.

Confirm: `✓ overnight-guard (hook): daytime arm armed via .claude/no-destructive`. Opt out later by
deleting the sentinel. An overnight run arms the hook with or without it.

When NOT to recommend: a project with no `working-overnight` and no CLAUDE.md rule about
destructive commands, since the daytime arm denies even a command the user asked for.

## Install detail (masked-exit-advisory.py)

The hook has its OWN sentinel, `.claude/masked-exit` (one file per hook, same shape as
`.claude/no-poll-loops`), and **forge-adapt creates it on every install, in both shapes**, so the
hook can never be installed switched off. The sentinel is only a sentinel: the file's content is
never read and it is not a list of the project's checks. The script checks it itself, so a
project-local copy is NOT opted in by its location: without the file it is inert. The hook is
advisory only (it never denies) and fires on `PostToolUse`, so it adds a short note to context
when a check is piped into `tail`, `head` or `grep`; tell the user that before creating the file.

Branch on `$GOVERNANCE_PLUGIN_ACTIVE`, as for `block-dashes`:

`yes`: the plugin's `hooks.json` already registers the hook, shell-gated on the sentinel. Do NOT
copy the script and do NOT touch `settings.json`. The whole install is:

```bash
mkdir -p .claude && touch .claude/masked-exit
```

`no`: copy `$FORGE_KIT_DIR/plugins/forge-kit-governance/hooks/masked-exit-advisory.py` verbatim to
`.claude/hooks/masked-exit-advisory.py` (keep the `# masked-exit-advisory-version: N` marker), merge
a `Bash` entry under `PostToolUse` (not `PreToolUse`) into `.claude/settings.json` with the same
`jq` merge and exec form as `block-dashes` (`"command": "python3"`,
`"args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/masked-exit-advisory.py"]`), then create the
sentinel with the command above.

Confirm: `✓ masked-exit-advisory (hook): armed via .claude/masked-exit`. Opt out later by deleting
the sentinel. Optionally sanity-run `python3 .claude/hooks/masked-exit-advisory.py --self-test`
(project-local shape). The recognised checks and filters are in the hook's own header and
`hooks/README.md`; do not restate them.

When NOT to recommend: a project with no test or check runner, since there is nothing to mask.

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
