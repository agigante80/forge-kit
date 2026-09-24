# Model tiers and thinking effort

Which model a component runs on, and how hard it thinks, are two separate settings. This page records
what the installed Claude Code actually DOES with them, measured rather than read from the docs, because
the `effort:` key has no official documentation at all and the `model:` keys behave differently depending on
how a component was reached. The phase "Choosing a model and an effort on purpose" (#250 to #253,
#278 to #281) builds its policy on these results, and the policy #250 set is recorded under Decisions by role.

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

## Decisions by role

**Decided 2026-09-24 on Claude Code 2.1.281** (#250). Judgment roles take the session's model, so a user
who chose a strong session keeps it where it matters and one who chose a cheap session is not overridden;
a role moves to a named cheaper tier only where a measurement on a fixed input showed the cheaper tier
doing the same job. `inherit` alone is not a saving (it passes the session's model on), so the saving is
the named tiers and the lower efforts.

| Agent | Role kind | Model | Effort | Reason |
|---|---|---|---|---|
| `ticket-gate` | judgment | `inherit` | `high` | the only thing between a bad spec and the work; a pinned `opus` would override a user who deliberately runs a cheaper session |
| `architect-review` | judgment | `inherit` | `high` | judgment, not measured, keeps today's behaviour by construction |
| `code-reviewer` | judgment | `inherit` | `high` | as above |
| `security-auditor` | security | `inherit` | `high` | Sonnet passed the criterion and still dropped medium findings (below) |
| `api-security-tester` | security | `inherit` | `high` | as above |
| `coding-standards-auditor` | bounded analysis | `inherit` | `medium` | Sonnet FAILED its criterion: it missed findings Opus rated high |
| `code-simplifier` | bounded analysis | `sonnet` | `medium` | passed; a weak pass, since neither tier found anything at medium or above |
| `dep-auditor` | bounded analysis | `sonnet` | `medium` | passed; a weak pass, since the input has no manifests and neither tier found anything |
| `health-check` | mechanical | `sonnet` | `low` | passed at `low`; Haiku failed and cost more |

### Dispatch sites (#251)

A dispatch with no frontmatter behind it (`general-purpose`, `Explore`) always names a model, because
otherwise it inherits the caller's session. A dispatch of a NAMED agent names nothing, since the
agent's frontmatter above is already an explicit choice and a site value would override it (Q5); the
one exception applies a scaling condition stated once in the dispatching file's rules.

| Tier word | Model value at a dispatch site |
|---|---|
| cheap | `haiku` |
| standard | `sonnet` |
| most capable | `opus` |

`fable` is not used at any site until a probe shows what a dispatch `model` of `fable` resolves to, and
`inherit` is not a dispatch value. Where each site landed:

| Site | Model | Why |
|---|---|---|
| `ticket-gate` 0c synthesis, 1.5 thin check, 2.7 research, 2.9 exploration | `sonnet` | bounded work on one ticket; Haiku cost more on multi-step work (below) |
| `ticket-gate` 3B critic | `sonnet`; `opus` when labelled `critical` or re-reviewing a fundamental item | the round table carries the condition |
| `ticket-gate` Step 4 alternatives | `opus` | architecture, the tier superpowers reserves the most capable model for |
| `full-review` general-purpose phases | `sonnet` | specialist passes beside the named reviewers |
| `full-review` `code-reviewer` in a round-2+ run | `sonnet` | a scoped re-review of a fix diff; round 1 keeps the frontmatter |
| `working-overnight` implementer | `sonnet` | review goes to `code-reviewer`, whose frontmatter decides |

Nothing mechanical catches a site that stops naming its model until #253.

### The measurement

Each run was a fresh headless session whose parent dispatched the agent once with the `Agent` tool's
`model` parameter (which wins over frontmatter, Q5) on the same input, at the effort the row proposes (the
agent inherits the session's effort, Q1). The input was a clone of this repository at `9ba6a55` plus one
seeded commit adding a small HTTP JSON API with an f-string SQL injection at `tools/label_api.py:19`. Every
number is read from the subagent transcript, by hand, because the dispatch-cost harness (#280) has not
landed. Tokens are output tokens and cache reads; the input and cache-write columns barely vary between
tiers and are omitted.

| Agent | Input | Model | Effort | Turns | Output | Cache reads | Wall | Criterion |
|---|---|---|---|---|---|---|---|---|
| `health-check` | the clone | `claude-sonnet-5` | `low` | 4 | 2401 | 176k | 25 s | reference (three items) |
| `health-check` | the clone | `claude-haiku-4-5` | none reported | 14 | 4906 | 664k | 61 s | FAIL: one of three items |
| `code-simplifier` | `4627783..5a8d9d3` | `claude-opus-5-5` | `medium` | 4 | 1969 | 159k | 21 s | reference (none at medium+) |
| `code-simplifier` | `4627783..5a8d9d3` | `claude-sonnet-5` | `medium` | 4 | 888 | 172k | 11 s | pass (weak) |
| `dep-auditor` | the clone | `claude-opus-5-5` | `medium` | 5 | 2851 | 215k | 30 s | reference (no findings) |
| `dep-auditor` | the clone | `claude-sonnet-5` | `medium` | 3 | 1402 | 114k | 15 s | pass (weak) |
| `coding-standards-auditor` | the clone | `claude-opus-5-5` | `medium` | 5 | 6697 | 222k | 64 s | reference (two high, one medium) |
| `coding-standards-auditor` | the clone | `claude-sonnet-5` | `medium` | 4 | 3830 | 175k | 39 s | FAIL: missed a high and the medium |
| `security-auditor` | `9ba6a55..c609818` | `claude-opus-5-5` | `high` | 3, 4 | 4384, 4559 | 138k, 209k | 48, 49 s | reference |
| `security-auditor` | `9ba6a55..c609818` | `claude-sonnet-5` | `high` | 3, 3 | 4057, 3235 | 148k, 148k | 47, 38 s | pass |
| `api-security-tester` | `9ba6a55..c609818` | `claude-opus-5-5` | `high` | 4, 4 | 5231, 3612 | 212k, 203k | 57, 39 s | reference |
| `api-security-tester` | `9ba6a55..c609818` | `claude-sonnet-5` | `high` | 3, 4 | 940, 2304 | 143k, 231k | 18, 33 s | pass |

The criteria were fixed before any run. Mechanical: the same list of missing or broken items as the
stronger tier. Bounded analysis: every finding the stronger tier rated medium or above is also reported.
Security: the seeded finding on both runs, and no finding the stronger tier rated high missed on either.

**Why the security roles stay on `inherit` although Sonnet passed.** Every one of the eight runs reported
the seeded injection (Opus rated it high every time, Sonnet critical three times and high once), and no
Opus run rated anything else high, so the criterion as written was met. It was written too narrowly.
Every Opus run also reported a missing `Host` check that lets a web page reach the loopback server
through DNS rebinding, and a single-threaded server one injected query can freeze: both medium in three
of the four runs, while the fourth rated the `Host` check low and folded the freeze into the injection
finding. On each agent, one of the two Sonnet runs listed the injection as its ONLY finding. For a role
whose output is the finding list and whose one real failure is a missed finding, a pass on the high
findings does not outweigh that. Re-measuring with a criterion that counts medium findings, and more
runs, is the way to move these roles.

**Why not Haiku.** It took 14 turns to Sonnet's 4 and read 3.8 times the cached context, so it cost more
while finding less: the turn-count warning from superpowers, observed.

### Limits of this measurement

- **One or two runs per cell.** One stronger-tier run is a reference, not a distribution. It is enough to
  refuse a move (a missed high finding is a missed high finding) and weak evidence for making one, which
  is why the two bounded-analysis passes are called weak and the security passes were not acted on.
- **Two passes are vacuous.** `code-simplifier` and `dep-auditor` passed because neither tier found
  anything to report; they say the cheaper tier runs the role correctly, not that it finds what Opus finds.
- **The first two `health-check` runs were contaminated and discarded.** The clones sat inside this
  checkout, so the checkout's own `CLAUDE.md` loaded and the agent inspected the real repository instead of
  the clone. The clean runs exclude it with the `claudeMdExcludes` setting and copy it into each clone.
- **A reversed range.** The first `code-simplifier` pair was given `5a8d9d3..3749afa`, newest first. Opus
  noticed and reviewed the intended commits; Sonnet reviewed the reversed diff and reported two findings
  (one high, one medium) that do not exist. The pair was re-run on the correct range, which is the one in
  the table, but the observation stands: the stronger tier recovered from a malformed input and the weaker
  one did not.
- Headless sessions only, and one repository.
