# Plan: Choosing a model and an effort on purpose

Written 2026-09-24 with the maintainer, from the roadmap prose, the four tickets already in the
milestone, the installed Claude Code (2.1.281) and Anthropic's own `claude-security` plugin. The
phase stays `planned` until the maintainer opens it.

## Goal

Every model tier and thinking effort in this kit is a decision with a reason, enforced by a check,
rather than a value a fork left behind. The point is cost: menial work stops running on the top
model at high effort, and judgment work keeps the model it needs.

## Done looks like

Three layers, each decided and each checkable:

1. **A baseline by role, in frontmatter.** Every agent declares a model and an effort by ROLE KIND:
   judgment roles `inherit`, bounded analysis and mechanical roles a named cheaper tier with a
   lower effort. Mechanical skills and commands adopt a tier only through the mechanism the probe
   shows is safe for the main session, preferring `context: fork` (#250, #279).
2. **The instance decides at the dispatch.** Every dispatch site in `plugins/` names a model and the
   one condition that raises it, since only the site knows the diff's size and risk (#251).
3. **The amount of work fits the input.** `/full-review` sizes its pipeline to the range, so a small
   diff dispatches one reviewer rather than five phases, the way `claude-security` does (#278).

Underneath all three: one table in `docs/guides/model-tiers.md` gives every one of the 28 components
(9 agents, 15 skills, 4 commands) a row with an allowed model set and effort range, and
`validate-plugins.sh` check 7 fails a component with no row or a value outside its range (#253).
Each tier decision is backed by a measured pair of runs, in turns as well as tokens (#280), and
forge-adapt carries the decisions into the projects it installs into (#281).

## Fails if

A premortem, from the maintainer's own concern: it is the end of this phase and it failed. What
happened?

- **Menial work still ran on the top model at high effort**, because `inherit` was mistaken for a
  fix. `inherit` passes on the session's model; an Opus session still ran every inheriting agent on
  Opus, and the bill did not move.
- **The work was pushed below the mid-tier floor**, took two or three times the turns, and cost more
  than it did before. Price per token was measured and turns were not.
- **The pipeline still dispatched five agents for a three-line diff.** Every tier was right and the
  number of agents was the cost.
- **A component relied on a key the CLI ignores**, because the probe was skipped or read from
  documentation rather than from a run, and the saving existed only in the frontmatter.
- **A skill's `model:` downgraded the user's main session** in the middle of hard work, because a
  main-session override was adopted without checking that it reverts.

## Expected work

In order, because each answer shapes the next:

1. **#252**, the probe. First, because every other ticket depends on which keys take effect.
2. **#280**, the measurement harness, so #250's decision is measured rather than asserted. A hand
   measurement is enough to unblock #250 if this is not ready.
3. **#250**, model and effort by role for the nine agents.
4. **#251**, every dispatch site names a model and its escalation condition.
5. **#278**, `/full-review` sizes itself to the diff. Independent of the tiers, so it can run in
   parallel with 3 and 4.
6. **#253**, the table for all 28 components and check 7.
7. **#279**, skills and commands, from #253's table and #252's answers.
8. **#281**, forge-adapt preserves the decisions and contributions state one.

## Out of scope

- **Per-dispatch effort through Workflow scripts** (#282, Backlog). The Agent tool takes a `model`
  and no effort; only a Workflow script can set effort per call. Porting the two orchestrators is an
  architecture change and ties the governance layer to a newer Claude Code feature, so it waits for
  the probe and the harness to show frontmatter effort is not enough.
- **The user's own controls.** `maxEffortLevel` and the Advisor (`advisorModel`, `/advisor`) are
  user and session settings. #253's guide documents them; the kit sets neither.
- Everything in the roadmap-management phases, which are closed.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-24, outcome **done**. All eight planned tickets landed in the planned order (#252,
#280, #250, #251, #278, #253, #279, #281), and two appeared: #288, the audit #287's live-forge leak
asked for, and #289, the re-measurement #250 left open for the security roles. None of the
premortem's clauses fired. Bounded and mechanical agents moved to a named `sonnet` rather than to
`inherit`, Haiku was measured and refused on turns, `/full-review` dispatches `code-reviewer` alone for
a small safe range, every adopted key was probed on the installed CLI, and no skill or command sets a
tier. #289 kept both security roles on `inherit` by its cost rule: Sonnet found every planted issue
and cost more. The rule could not judge the tester, because no run of either tier wrote a test for the
hard-coded secret, so the criterion itself goes to `backlog` (#292) along with the reviews' lows
(#293). #282 stays in `backlog` as planned.

Opened as a bucket 2026-09-23, when the maintainer adopted superpowers' and Anthropic's guidance on
model selection as guidelines this kit follows rather than references. Both say the same thing from
different ends: Anthropic's `agent-development` skill recommends `inherit` unless an agent needs
specific capabilities, and superpowers' `subagent-driven-development` says to use the least powerful
model that can handle each role, warns that an omitted model at a dispatch silently inherits the
session's most expensive one, and warns in the other direction that turn count beats token price, so
the cheapest tier is not the cheap answer.

Measured against that, this kit is wrong twice. Eight agents declare `model: opus`, one declares `model: sonnet`, and none
declares `inherit`, and those lines are a fork artefact rather than a decision: `architect-review` is a
verified duplicate of an upstream file that declares it (#250). And no dispatch site in the kit names
a model at all, so every critic, thin-check and lens runs on whatever the caller happens to be, which
on this repository's own runs means Opus for a step whose whole job is to call a shell script (#251).
Beside them: an `effort:` key Anthropic ships on eight of its own agents and documents nowhere, worth
a probe before an adoption (#252), and the guard without which all of it goes stale again (#253).
The probe's answers are in `docs/guides/model-tiers.md`: `effort:` is honoured on agents, a dispatch
site's model beats the agent's, and a skill or command tier binds only on a slash invocation.

Planned 2026-09-24, and reshaped by what the installed CLI and Anthropic's `claude-security` showed.
`inherit` is not a cost fix, since it passes on the session's model, so #250 became a split by role;
`effort:` is real on agents, skills and commands, so it became a second axis; and the probe (#252)
moved from last to first, because every other ticket depends on which keys take effect. Four tickets
joined: `/full-review` sizing its pipeline to the diff, the largest single saving because the cost
was the number of agents rather than their tier (#278); skills and commands, where a tier can
downgrade the user's own session (#279); a measurement in turns as well as tokens (#280); and
forge-adapt carrying the decisions into installed copies (#281). Per-dispatch effort through Workflow
scripts was considered and deferred to Backlog (#282).
