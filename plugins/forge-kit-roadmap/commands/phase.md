---
description: Work the roadmap. status, plan, close or triage a phase.
argument-hint: status | plan <name> | close <name> | triage
---

<!-- phase-version: 2 -->

# /phase

Rolling wave planning against `docs/roadmap.md`. The `roadmap-phases` skill is canonical for every
rule below; this command is the entry point, not a second copy of the rules. Read the skill before
acting, and when a guard refuses something, quote its message rather than paraphrasing it.

## Resolving the scripts

**Never use `$CLAUDE_PLUGIN_ROOT`.** It is exported to hook processes, not to an agent's Bash, so it
expands to nothing here and a leading-slash path silently resolves somewhere else. Resolve by
search, in this order: the project's own copy; a forge-kit checkout's tree, which is newer than
anything installed; then the highest `<name>-version` marker across installed copies, path as the
tie-break. The plugin cache holds versions side by side and `find` lists them in arbitrary order,
so a first hit was a stale copy three runs in four (#189). Print the pick.

```bash
resolve() {  # resolve <asset.sh>
  [ -f "scripts/$1" ] && { echo "scripts/$1"; return; }
  ls "$(git rev-parse --show-toplevel 2>/dev/null)"/plugins/*/skills/*/assets/"$1" 2>/dev/null && return
  find ~/.claude/plugins -name "$1" -exec grep -m1 -Ho "${1%.sh}-version: [0-9]*" {} + 2>/dev/null \
    | sort -t: -k3,3n -k1,1 | tail -1 | cut -d: -f1
}
CP=$(resolve check-phases.sh); SP=$(resolve sync-phases.sh); echo "using $CP, $SP"
```

If either is missing, say so and stop. Do not reimplement the checks in prose: the whole point of
the scripts is that prose cannot be tested.

## `/phase status`

Answers "is the current phase complete, and is it marked done in both places?"

1. Run `bash "$CP"`. Report its verdict verbatim; it is the authority.
2. Name the one `open` phase and its plan.
3. List that phase's tickets, open and closed, via the milestone.
4. Read the plan's **Done looks like** and say plainly whether it is satisfied, and what is left.

**Read only. Change nothing**, not the roadmap, not the host. If the phase looks finished, say so
and suggest `/phase close`; do not close it.

## `/phase plan <name>`

Writes or reviews a phase's plan. Run this before moving a phase to `open`, and again during it.

**Read both inputs.** The roadmap prose saying why the phase exists, AND the tickets already sitting
in its milestone. A `planned` phase is a bucket, and what has accumulated in it is the evidence the
plan is written from, not a distraction from the original intent.

Write the five sections the skill defines: Goal, Done looks like, Fails if, Expected work, Out of
scope.

**Fails if is a premortem, not a risk list.** Put the question to the user in that form: *it is the
end of this phase and it failed badly; what happened?* Imagining a failure that has already
happened, rather than one that might, surfaces more causes and licenses doubts people will not
otherwise raise. Write their answers, not a generic risk register.

When the plan is written and the user agrees, set the phase to `open` in `docs/roadmap.md`. Refuse
if another phase is already `open`: finish or re-shape that one first.

## `/phase close <name>`

The close review. Four steps, and the phase is not closed until all four are done.

1. **Compare the plan against the tickets actually created**, not the ones it expected. The
   difference is the interesting part: work that appeared, work that vanished, work that changed
   shape.
2. **File tickets for skipped or missing work, and prioritise them.** Silently dropped work is what
   this review exists to catch. Assign each new ticket a phase, which is usually the next one or
   `backlog`.
3. **Move every remaining open ticket somewhere explicit.** Rule 4 refuses a `done` phase that still
   holds open tickets, and that refusal is the circuit breaker: the default is to **re-shape, never
   extend**.
4. **Close it in both places**: the milestone via `bash "$SP"`, and the roadmap entry set to `done`.
   One without the other is not closed.

Record which of the three outcomes it was, in the roadmap prose:

- **done**, the work landed.
- **re-shaped**, some landed and the rest moved, with the remainder named.
- **abandoned**, the phase was a wrong turn, and the roadmap says why.

**Abandoned is the one people skip.** Write it down: a phase deleted without a record looks, six
months later, like a phase nobody considered.

Finish by running `bash "$CP"` and reporting the result. If it refuses, the phase is not closed.

## `/phase triage`

1. Run `bash "$CP"` and read rule 1's findings: every open ticket with no phase.
2. For each, propose a phase and say why in one line. A ticket whose home is genuinely unknown goes
   to `backlog`, which is a decision to decide later rather than no decision.
3. **Assign only what the user confirms.** Never bulk-assign.
4. Then look the other way: list `backlog` tickets that now belong in a real phase, and say which.

## After any change to the roadmap

Run `bash "$SP" --check` first and show what it would do, then `bash "$SP"` once the user agrees.
It never deletes a milestone and never reopens a closed one, so anything beyond creating and closing
is a manual step it will report rather than perform.
