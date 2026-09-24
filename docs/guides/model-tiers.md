# Model tiers and thinking effort

Which model a component runs on, and how hard it thinks, are two separate settings. This page records
what the installed Claude Code actually DOES with them, measured rather than read from the docs, because
the `effort:` key has no official documentation at all and the `model:` keys behave differently depending on
how a component was reached. The phase "Choosing a model and an effort on purpose" (#250 to #253,
#278 to #281) builds its policy on these results; the policy itself belongs to those tickets, not here.

## Probe results

**Probed 2026-09-24 on Claude Code 2.1.281** (#252), parent session `claude-opus-5-5`, headless
(`claude -p`) runs of a throwaway plugin loaded with `--plugin-dir`. Every result below was read from the
session transcript (`~/.claude/projects/<cwd>/<session>.jsonl` and its `subagents/` directory), where each
assistant record carries `message.model` and `effort`, and cross-checked against the `CLAUDE_EFFORT`
variable a Bash call printed inside the component. `effort` is the primary reading; `perTurnEffort` is
supplementary and is empty on the Sonnet models. Each question was re-run in a second session and
reproduced. Re-probe before relying on any of this under a newer CLI.

### Q1. Does an agent's `effort:` frontmatter take effect? Yes.

A subagent's turns run at the declared level, and `CLAUDE_EFFORT` inside it prints that level. The same
fixed task (list the kit's agents that declare `model:`, then print `CLAUDE_EFFORT`), three runs per level,
parent at `medium`:

| Declared | Turns | Output tokens | Wall time | Answer |
|---|---|---|---|---|
| `low` | 3, 3, 3 | 697, 698, 1062 | 22.7 to 24.7 s | the same nine files every run |
| `xhigh` | 6, 4, 4 | 1484, 3098, 2478 | 29.4 to 31.4 s | the same nine files every run |

The ranges do not overlap, so the key is honoured AND made a measurable difference on this task. On this
task the extra effort bought nothing: all seven runs, including one with no `effort:`, returned the same
nine files. That says nothing about harder work, where effort is the point.

**An agent that declares no `effort:` inherits the session's.** With the parent at `medium` it ran at
`medium`; with the parent at `high` it ran at `high`. The Agent tool has no effort parameter, so frontmatter
is the only per-agent override.

### Q2. What happens to an effort the model does not support, and do skills honour `effort:`?

**It is silently clamped.** An agent declaring `model: claude-sonnet-4-6` with `effort: xhigh` (that model
lists `low`, `medium`, `high` and `max`, with no `xhigh`) ran at `high`: downgraded, not rounded up to `max`.
Nothing reported it: stderr was empty in both runs, and nothing in the transcript mentions the downgrade.

**A skill's `effort:` applies only when the USER invokes the skill as a slash command.**

| How the skill was reached | Declared | Session | Ran at |
|---|---|---|---|
| user typed `/probe252:low-skill` | `low` | `high` | `low` |
| user typed `/probe252:xhigh-skill` | `xhigh` | `medium` | `xhigh` |
| the model called the Skill tool | `low` | `high` | `high` (ignored) |
| the model called the Skill tool | `xhigh` | `medium` | `medium` (ignored) |

After a slash-invoked skill, the next user turn in the SAME process returned to the session's effort
(`low` for the skill's turns, then `high` for the following turn).

### Q3. Does a command's `model:` take effect, and does it leak into the next turn?

**Yes, for the command's own turn only, and only on a slash invocation.** `/probe252:sonnet-cmd`
(`model: sonnet`) ran its turn on `claude-sonnet-5` inside an Opus session; the next user message in the
same process ran on `claude-opus-5-5` again. It does not leak. The same command reached by the model through
the Skill tool stayed on `claude-opus-5-5`: the override was ignored.

Together with Q2 this is the decisive fact for skills and commands (#279): a tier or effort declared on
one binds only when a person types the slash command, never when a model reaches for the component
itself, and when it binds it lasts one turn.

### Q4. What does `context: fork` run on, and what does the fork see?

**The fork does not see the parent conversation.** A canary token planted in an earlier parent turn was
invisible to the forked skill in both runs, once with the fallback agent and once with the declared one.

**The `agent:` key must be plugin-qualified, or it silently falls back.** `agent: m-sonnet` in a plugin
skill spawned `general-purpose`, with no error; `agent: probe252:m-sonnet` spawned the declared agent.
With the key resolved, the agent's own `model:` decided the tier: `probe252:m-sonnet` ran on
`claude-sonnet-5` and `probe252:m-opus` on `claude-opus-5-5`, both in an Opus session.

**A fork with no resolvable agent runs on Sonnet, not on the session's model.** The `general-purpose`
fallback ran on `claude-sonnet-5` in an Opus session, at the session's effort, in all three runs. So the
failure mode of a mistyped `agent:` is a silent tier DROP, not merely a lost agent.

### Q5. When the dispatch site and the agent both name a model, which wins?

**The dispatch site wins.** Each cell is the model the subagent actually ran on, with the parent session on
`claude-opus-5-5`:

| Agent tool `model` | agent `model: inherit` | agent `model: sonnet` | agent `model: opus` |
|---|---|---|---|
| absent | opus-5-5 | sonnet-5 | opus-5-5 |
| `sonnet` | sonnet-5 | sonnet-5 | sonnet-5 |
| `opus` | opus-5-5 | opus-5-5 | opus-5-5 |

With no model at the dispatch site, the frontmatter applies, and `inherit` follows the parent. This is
why naming the model at every dispatch site is a policy with teeth rather than a style: it is the one
setting nothing else overrides. Effort does not follow the same rule, since the dispatch site cannot set
it (Q1).

### What this does not cover

Interactive sessions were not probed, only headless ones; Workflow scripts' per-dispatch settings were
not probed (#282); and the effort-to-quality relation was measured on one easy task, which shows the key
works and says nothing about where the higher levels pay for themselves.
