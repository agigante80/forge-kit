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

**The opt-in sentinel convention lives in CLAUDE.md**, under "user level without forcing it on every
project" (#165): why a plugin hook gates in the shell rather than the interpreter, the measured cost
of each, which of the two sentinel shapes to choose, and why a skill or command gates differently
from a hook. It is stated there once and deliberately not restated here, because this file used to
carry a copy and a copy is what drifts.

What is specific to this hook: the no-dash rule is opinionated and a plugin hook is live in *every*
project, so the script stays dormant until a project opts in:

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
| `no-poll-loops.py` | PreToolUse | 3 | Deny a shell wait on a dispatched subagent in a Bash call: a background `sleep N; echo waited` or a `sleep` loop on a task output file or transcript. Fails open. |

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

## no-poll-loops.py

A subagent dispatched with the `Agent` tool returns through the harness: its completion
notification is appended to the next tool result. Waiting on it in the shell is always wrong, and
the ticket gate improvised two shapes of it (#263): a background `sleep 240; echo waited`
placeholder to keep the turn alive, and an `until [ -s .../tasks/<id>.output ]; do sleep 5; done`
poll loop. Neither ends usefully once the run does, and one held a finished verdict for five days.
The deny reason carries the rule (keep doing independent work, let the notification arrive, never
end the turn with a dispatch outstanding; with no independent work, dispatch in the foreground), so no agent prose says it. It covers `ticket-gate`,
`full-review` and `working-overnight` alike.

It denies a Bash call when either:

1. `run_in_background` is true and the whole command is a bare `sleep <n>[smhd]`, optionally
   followed by `;` or `&&` and `echo ...`, `true` or `:`; or
2. the command holds an `until`, `while` or `for` loop that calls `sleep` before its `done` AND names
   a subagent artifact: `tasks/<id>.output`, a `subagents/` path or an `agent-<id>.jsonl`
   transcript (background or not, because the harness backgrounds a long foreground call).

Everything else is allowed: `sleep 2`, a background `sleep 20; gh run watch ...`, a loop polling
anything else. Text that only CARRIES a loop (a quoted string or a heredoc body, such as a forge
comment or commit message) is allowed too, unless the command executes it (`bash -c`, `sh <<EOF`,
`| bash`, `eval`, `source`). The matcher is `Bash|Monitor`: Monitor's payload field is the same `command`. Known gaps: a
loop whose artifact path sits in a variable set in an earlier call, a foreground bare `sleep`, `tail -f` on a
task output, background placeholders wider than the pattern (a sleep-then-cat, `sleep 60 &`),
waits other than `sleep` inside a loop, a script written then run, an artifact named after an unrelated sleeping loop in the same call (denied), and a project-local copy whose
payload `cwd` is below the root with `CLAUDE_PROJECT_DIR` unset.

**Its sentinel is its own file, `.claude/no-poll-loops`** (the one-file-per-hook rule, same shape as
`.claude/no-dashes`), shell-gated in `hooks.json` like the other two. **forge-adapt creates it when
it installs the hook, in both install shapes**, so the hook is never installed switched off. Opt out
by deleting it. `python3 no-poll-loops.py --self-test` runs the verdict matrix.

```bash
mkdir -p .claude && touch .claude/no-poll-loops   # opt in (forge-adapt does this)
rm .claude/no-poll-loops                          # opt out
```
