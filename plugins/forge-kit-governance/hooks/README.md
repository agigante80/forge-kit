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

**The opt-in sentinel convention (#165).** A plugin hook is live in *every* project that enables
the group, so behaviour a project has not asked for is gated on a file the project owns, one file
per hook (`.claude/no-dashes`, `.claude/no-poll-loops`, `.claude/no-destructive`,
`.claude/masked-exit`). `hooks.json` tests it in the shell and exits before `python3` starts: about
1.8 ms per matched tool call in a project that has not opted in, against about 44 ms if the
interpreter started first. The gate inside each script is defence in depth and the only gate for a
project-local copy. A skill or command has no wrapper and can only gate in its own prose.

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
| `no-poll-loops.py` | PreToolUse | 5 | Deny a shell wait on a dispatched subagent in a Bash call: a background `sleep N; echo waited` or a `sleep` loop on a task output file or transcript. Fails open. |
| `overnight-guard.py` | PreToolUse | 8 | Deny destructive git discards and `rm -rf` of a dangerous target in a Bash call. Two arms: an overnight run (full Tier-3 list) and a daytime opt-in (git discards plus bulk delete, no secrets or pipe-to-shell). Fails open by day. |
| `masked-exit-advisory.py` | PostToolUse | 2 | Advise, never deny, when a Bash command pipes a recognised check (`scripts/test-*`, `pytest`, `npm test`, `git apply --check`, and the like) into a filter (`tail`, `head`, `grep`, and the like): the exit code shown is the filter's. Fails open and silent. |

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
The deny reason carries the rule (keep doing independent work and let the notification arrive; with none
left, end the turn and the notification resumes you; it names no blocking call, because the installed harness offers
none, #433), so no agent prose says it. It covers `ticket-gate`,
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

## overnight-guard.py

Two arms behind one script. The overnight arm is armed by a run's `.claude/overnight/active.md` and
denies the whole Tier-3 list. The daytime arm (#419) is armed by its own sentinel,
`.claude/no-destructive`, and denies only the git discards (`reset --hard`, `clean -f`, `checkout .`,
`restore` and the like) and bulk delete: `rm -rf` of a dangerous target (any absolute path, `~`, `$HOME`, or `..`), or of a
relative target ending in a wildcard (`tmp/*`, `./*`, `dir/*`). `rm -rf tmp/some-dir` stays allowed.
Secrets and pipe-to-shell are overnight-only. When both sentinels exist the overnight arm wins. The
daytime arm fails open on a malformed payload; the overnight arm still fails closed.

**forge-adapt creates the sentinel when it installs the hook, in both install shapes.** The
`hooks.json` gate runs Python only when either sentinel exists.

```bash
mkdir -p .claude && touch .claude/no-destructive   # opt in (forge-adapt does this)
rm .claude/no-destructive                          # opt out
```

The sentinel lives under `.claude/`, which is often gitignored, so a fresh clone or `git worktree add`
starts with the daytime arm off. Re-run forge-adapt or `touch` the file there.

## masked-exit-advisory.py

`bash scripts/test-x.sh | tail -5` exits with the status of `tail`, so a failing suite looks green
and an agent reports it as passing (#420). This is a `PostToolUse` hook on `Bash` that adds one
fixed advisory to the model's context when a command pipes a recognised check into a recognised
filter without `-o pipefail`, `setopt pipefail` or a `$PIPESTATUS` read. The advisory says the exit
code shown belongs to the filter, and suggests reading the check's own status in the same command
(`check | tail -5; echo "check rc=${PIPESTATUS[0]}"`) or redirecting the check to a file and
tailing the file. It never suggests `pipefail` with `head` or `grep -q`, which can SIGPIPE the
check to 141 (#413).

It is advisory only: it never denies, always exits 0, never echoes the command and fails open
silently on anything it cannot parse. The recogniser tokenises with `shlex` (a quoted pipe is
data), matches a check in ANY non-last stage when the LAST stage is a filter, and ignores what
follows the pipeline (`&& echo ok`). The built-in check and filter sets are module-level constants
at the top of the script and listed in its docstring, which also lists the residual limits. Two
matter most: the hook never sees the exit code, so it also advises on green runs, and PostToolUse
does not fire for a Bash call that exits non-zero (Claude Code runs `PostToolUseFailure` instead),
so the hook sees only the masked, exit-0 case. Verified on Claude Code 2.1.294 for the main
session and for a subagent's Bash call.

**Its sentinel is its own file, `.claude/masked-exit`**, and nothing more: the content is never
read and there is no project check list. It is shell-gated in `hooks.json`. **forge-adapt creates
it when it installs the hook, in both install shapes.** Opt out by deleting it.
`python3 masked-exit-advisory.py --self-test` runs the verdict matrix.

```bash
mkdir -p .claude && touch .claude/masked-exit   # opt in (forge-adapt does this)
rm .claude/masked-exit                          # opt out
```
