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
`.claude/masked-exit`, `.claude/forge-write-consent`). `hooks.json` tests it in the shell and exits before `python3` starts: about
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
| `overnight-guard.py` | PreToolUse | 18 | Deny destructive git discards and `rm -rf` of a dangerous target in a Bash call. Two arms: an overnight run (full Tier-3 list) and a daytime opt-in (git discards plus bulk delete, no secrets or pipe-to-shell). Fails open by day. |
| `forge-write-consent.py` | UserPromptSubmit + PreToolUse | 1 | Deny a forge comment in a Bash call unless the user's own latest prompt said `allow-comment`, and a new ticket once the session's ticket budget (default 3) is spent unless it said `allow-ticket`. Body rewrites, closes, reads, the gate's review post and a release note are never denied. Fails open on an unparseable payload; no grant file means no grant. |
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

## forge-write-consent.py

Two written rules held mechanically (#565): a ticket is read by its BODY, so decisions and
corrections are rewritten into it and a comment is only a retraction or a closing note; and a
finding becomes a ticket only when someone would really hit it and it is too big to fix now. One
session broke both in a day (25 tickets, 12 decision comments), which is the evidence that prose
alone does not hold them.

**One script, two events.** `UserPromptSubmit` records the grant: every real prompt overwrites
`${CLAUDE_CONFIG_DIR:-~/.claude}/forge-write-consent/<session_id>.json` with two booleans, true only
for the literal word `allow-comment` / `allow-ticket` in that prompt, so a grant lasts until the
next real prompt. Prompts the harness injects (a background task's `<task-notification>`, a peer
session's message, a cross-session idle notice) all fire the same event on Claude Code 2.1.301 and
neither grant nor revoke, which is what stops one session granting another. `PreToolUse` `Bash`
denies a comment write with no grant. A ticket create with no grant is allowed while the session's
**ticket budget** lasts, then denied: tickets can be filed when needed without asking, and a
runaway session stops at the cap, the way Dependabot caps open pull requests. A granted ticket
costs nothing. The budget is a `ticket-budget: N` line in the sentinel (default 3; 0 restores the
old rule that every ticket needs `allow-ticket`), counted per session in `<session_id>.tickets`
beside the grant file. A subagent carries its parent's `session_id`, so the grant and the budget
cover the session's subagents, and an overnight run is one session. The exact shapes, exemptions and known
limits are in the script's header. The deny reason teaches the rule and names the word to ask
for.

**Its sentinel is its own file, `.claude/forge-write-consent`**, shell-gated in `hooks.json` on both
entries, and forge-adapt creates it when it installs the hook. A project-local install needs BOTH
`settings.json` entries: without the `UserPromptSubmit` one no grant is ever recorded, so every
comment is denied, and every ticket once the budget is spent. `python3 forge-write-consent.py --self-test` runs a short grant-flow matrix.

```bash
mkdir -p .claude && touch .claude/forge-write-consent   # opt in (forge-adapt does this)
echo 'ticket-budget: 5' > .claude/forge-write-consent     # optional: a different budget
rm .claude/forge-write-consent                          # opt out
```

## overnight-guard.py

Two arms behind one script. The overnight arm is armed by a run's `.claude/overnight/active.md` and
denies the whole Tier-3 list. The daytime arm (#419) is armed by its own sentinel,
`.claude/no-destructive`, and denies only the git discards (`reset --hard`, `clean -f`, `checkout .`,
`restore` and the like) and bulk delete: `rm -rf` of a dangerous target (any absolute path, `~`, `$HOME`, `..`, the worktree itself, or a
relative target that resolves against the tracked cwd to the project or one of its ancestors, see
below), or of a relative target ending in a wildcard (`tmp/*`, `./*`, `dir/*`). `rm -rf tmp/some-dir` stays allowed.
Secrets and pipe-to-shell are overnight-only. When both sentinels exist the overnight arm wins. The
daytime arm fails open on a malformed payload; the overnight arm still fails closed.

`rm -rf` of the worktree itself is denied on both arms (#467): a target word that expands to
`$PWD`, `$CLAUDE_PROJECT_DIR` (braced, quoted or with a trailing slash), `$(pwd)`, a backtick `pwd`,
or `$(git rev-parse --show-toplevel)`. The target words are read by shell word-splitting, so
quoting, `--`, and any target position count (`rm -rf "$PWD/build" "$PWD"` denies), while a
subdirectory (`"$PWD/build"`), a longer name (`$PWDX`, `$(pwd)x`), single-quoted text (`'$PWD'`)
and any substitution the hook cannot follow (`$(find ...)`, `$(mktemp -d)`) stay allowed.

Both arms judge every `rm` of a payload and walk its segments left to right (#478), so a name or a
`cd` set earlier in the same payload counts:

- **Tracked aliases.** `NAME=value` (also after `export`, `declare`, `local`, `readonly`) taints
  `NAME` when the whole value is the worktree, `.`, or another tainted name, and any other value
  clears it. `D=$PWD; rm -rf "$D"` and `A=$PWD; B="$A"; rm -rf "$B"` deny; `D=$PWD/build` does not.
  `$OLDPWD` after a `cd` away from the project is the project.
- **Tracked cwd.** `cd`, `pushd`, `popd`, `builtin cd` and `command cd` move the cwd, which starts at
  the payload's `cwd` (Claude Code carries a `cd` from an earlier Bash call into it; probed on
  2.1.296). A relative target that resolves to the project or an ancestor denies (`cd .. && rm -rf
  <project>`), and so does a glob from an ancestor (`cd .. && rm -rf *`, on both arms), while
  `cd tmp && rm -rf impl-213` stays allowed. The project, cwd and targets are compared after
  `realpath`, so a project reached through a symlink is caught too.
- **Unknown cwd.** `cd -`, `popd`, or a `cd` to any other expansion makes the cwd unknown for the
  rest of the payload. A relative target is then denied only when it names a run of the project's
  path ending at its basename (`cd "$X" && rm -rf <project>`), which is a known false deny when `$X`
  is an unrelated directory with a `<project>` of its own; `cd "$X" && rm -rf tmp` stays allowed.

Not followed, as accepted limits: `read`, `eval`, `set --`, `for`, arrays, `printf -v`, a sourced
file, assignments inside `$( )` or a subshell, inherited variables, `CDPATH`, and symlinks made in the
same payload. A `cd` inside a subshell is treated as persisting, so `(cd ..) && rm -rf <project>` is
a false deny. String matching stays evadable by a deliberate agent. The overnight arm reads the
`rm` command word as the daytime arm does, so `git rm -rf /` and `docker run --rm ...` are not rm
segments on either arm, while `sudo -u git rm -rf ~` (a user named git) and `${RM:-rm} -rf /` are
denied on both, and it still has no general wildcard class (`rm -rf tmp/*` and `rm -rf ./*`
stay allowed overnight).

Git global options are tolerated between `git` and the subcommand (#457): `git -C sub reset --hard`,
`git -c k=v checkout .`, `git --no-pager stash drop` and `git -C "my dir" reset --hard` are denied
exactly like the bare forms, and `git -c reset.hard=1 status` stays allowed because an option value
is never read as the subcommand. A run of more than 32 global options is denied in both arms (#469),
because the scan is bounded at 32 to stay linear and the subcommand beyond the bound is out of
sight; the reason says the command is too long to judge rather than calling it destructive, and a
harmless 33-option command is denied too. Up to 32 options the subcommand decides, as before.
A redirection between `git` and the subcommand, or between options, is part of the same run (#473):
`git 2>&1 reset --hard`, `git >/dev/null clean -fd`, `git &>x stash drop` and
`git>x reset --hard` and `git -C sub 2>&1 reset --hard` are denied like the bare forms on both arms, and each redirection
counts toward the 32 (a 33-token mix of options and redirections is denied as too long to judge).
The noclobber `>|` (with an optional fd and an optional space, #474) is read as a redirection, not a
pipe, by the same flattening step, on both arms: `rm -rf >|log /`, `rm -rf >|log "$PWD"/`,
`git >|x reset --hard` are denied, and overnight `curl u >|f | sh` is denied while `curl x >|bash`
(a file named bash) is allowed. A real pipe still splits (`rm -rf build >|log | cat /` stays allowed).
The flattening step marks those redirections with two control bytes, so a raw `\x01` or `\x02` already
in the command is first replaced by an ordinary character and cannot forge a mark: `rm -rf >`+`\x02`+` /`
is a redirection to a file named `\x02` plus `rm -rf /`, and is denied.
The one gap this leaves is a deliberate one: an alias defined
inline (`git -c alias.x='reset --hard' x`, or `--config-env` pointing at one) runs a destructive
command under another name, and the guard does not defend against evasion.

A backslash-newline continuation is joined before any matcher reads the command (#471), exactly as the shell removes it: with the empty string, so `git \` + newline + `reset --hard` and `gi\` + newline + `t reset --hard` are both `git reset --hard`. An even run of backslashes before the newline is escaped backslashes, not a continuation, so `git \\` + newline + `reset --hard` stays allowed. The join is not quote-aware: a backslash-newline inside single quotes, which the shell keeps, is joined too and can match, the same quoted-text over-match the guard already has. A literal two-character `\n` is unaffected.

A redirection is not a command separator (#470). The `rm` and git matchers share one flattening step in which a `&`
right after `<` or `>` (`2>&1`, `>&2`, `<&0`) or right before `>` (`&>x`) stays inside the segment, so
`rm -rf 2>&1 /` and `git reset 2>&1 --hard` are denied on both arms; any other `&` still splits
(`sleep 1 & rm -rf /`, `echo >&2 & git reset --hard`). Both arms drop redirections before judging an `rm`, so
`rm -rf build > /dev/null`, `2> /dev/null` and `&> /dev/null` stay allowed overnight as they were by day.

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
