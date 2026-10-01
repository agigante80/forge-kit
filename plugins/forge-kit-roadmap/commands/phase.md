---
description: Work the roadmap. status, plan, review, reassess, close or triage a phase.
argument-hint: status | plan <name> | review [name] | reassess <op> ... | close <name> | triage
---

<!-- phase-version: 13 -->

# /phase

Rolling wave planning against `docs/roadmap.md`. The `roadmap-phases` skill is canonical for every
rule below; this command is the entry point, not a second copy of the rules. Read the skill before
acting, and when a guard refuses something, quote its message rather than paraphrasing it.

## Resolving the scripts

**Never use `$CLAUDE_PLUGIN_ROOT`.** It is exported to hook processes, not to an agent's Bash, so
here it expands to nothing. Resolve by
search, in this order: the project's own copy; a forge-kit checkout's tree, which is newer than
anything installed; then the highest `<name>-version` marker across installed copies, lexically
last path as the tie-break. Print the pick.

```bash
resolve() {  # resolve <asset.sh>
  [ -f "scripts/$1" ] && { echo "scripts/$1"; return; }
  ls "$(git rev-parse --show-toplevel 2>/dev/null)"/plugins/*/skills/*/assets/"$1" 2>/dev/null && return
  find ~/.claude/plugins -name "$1" -exec grep -m1 -Ho "${1%.sh}-version: [0-9]*" {} + 2>/dev/null \
    | sort -t: -k3,3n -k1,1 | tail -1 | cut -d: -f1
}
CP=$(resolve check-phases.sh); SP=$(resolve sync-phases.sh); echo "using ${CP:-none}, ${SP:-none}" | sed "s|$HOME|~|g"
```

If either is missing, say so and stop. Do not reimplement the checks in prose.

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
plan is written from.

Write the five sections the skill defines: Goal, Done looks like, Fails if, Expected work, Out of
scope.

**Fails if is a premortem, not a risk list.** Put the question to the user in that form: *it is the
end of this phase and it failed badly; what happened?* A failure imagined as past surfaces more
causes. Write their answers, not a generic risk register.

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

**Abandoned is the one people skip.** Write it down.

Finish by running `bash "$CP"` and reporting the result. If it refuses, the phase is not closed.

## `/phase review [name]`

The mid-phase alignment review. The `roadmap-phases` skill is canonical for every rule, including
which phase is reviewed, what a rewrite may destroy, and when a ticket is re-gated. This is the
order of work and the mechanism only.

Resolve three more assets the same way and for the same reason:

```bash
FL=$(resolve forge-lib.sh); RL=$(resolve roadmap-lib.sh); DD=$(resolve check-doc-drift.sh)
echo "using ${FL:-none}, ${RL:-none}, ${DD:-none}" | sed "s|$HOME|~|g"
```

If `FL` or `RL` is empty, say which and stop before the next block: sourcing an empty path fails
with a shell error rather than the missing-asset message the resolve above already printed.

```bash
grep -m1 -o 'forge-lib-version: [0-9]*' "$FL"
. "$FL"; . "$RL"
```

The two libraries are SOURCED, not run, and the version that prints must be 25 or higher.
`${DD:-none}` is often `none`, and the skill says what the review does then.

1. Run `bash "$CP"` and report its verdict verbatim. Then, before any write, snapshot
   the local paths the second-run proof covers: `docs/roadmap.md`, the plan `docs/plans/<phase>.md`
   and each document of step 4's `<documents>` (computed here, once). The listing is a FILE under the
   git dir (a shell variable does not survive the tool calls a run spans) holding one
   `<hash>  <path>` line per path from `git hash-object -- "<path>"`, or `absent  <path>` when the
   path is missing (`git hash-object` exits 128). Hashes, because `git status --porcelain`
   reads ` M <path>` both before and after a second write. Each run owns the file named by the
   `run id: <id>` it prints; carry `<id>` into steps 4 and 7 as a literal, like `ACTS=N`. A
   shared file let overlapping runs clobber each other's baseline into a false `held` (#394);
   refusing a young file would still share the name. Files two or more days old
   are orphans of aborted runs and are deleted.

```bash
( cd "$(git rev-parse --show-toplevel)" && G="$(git rev-parse --git-path phase-review)" &&
  { find "$(dirname "$G")" -maxdepth 1 -name 'phase-review.*' -mtime +1 -delete 2>/dev/null || true; } &&
  SNAP="$(mktemp "$G.XXXXXX")" &&
  printf '%s\n' docs/roadmap.md "<plan>" "<doc>"... | LC_ALL=C sort | while IFS= read -r p; do
    if [ -e "$p" ]; then printf '%s  %s\n' "$(git hash-object -- "$p")" "$p"; else printf 'absent  %s\n' "$p"; fi
  done > "$SNAP" && echo "run id: ${SNAP##*.}" )
```
2. Read the plan, the phase's roadmap prose, and EVERY ticket in the milestone, open and closed,
   including its comments through `forge_issue_comments`, excluding any comment whose first line is
   exactly `## Superseded body (phase review)`: that is a body a past rewrite replaced, not
   something that happened during this phase.
3. Report each ticket against the tree: implemented, naming the commit or commits under the
   skill's rule above, partly implemented (naming what is missing), not started, or superseded.
4. Run `bash "$DD" --range <base>^..HEAD --docs <documents>`, read its rows. `<base>` is derived
   by the skill's range rule, never restated here. `<documents>` is a comma-separated
   `<doc>[,<doc>...]`, the project's standing documents for which `git cat-file -e
   HEAD:<doc>` succeeds, read from the snapshot file, not memory:

```bash
RUN=ID; case "$RUN" in ''|*[!A-Za-z0-9]*) RUN=none;; esac
SNAP="$(git rev-parse --git-path "phase-review.$RUN")"
if [ ! -f "$SNAP" ]; then echo "no snapshot from step 1"; else
  D=$(sed 's/^[^ ]*  //' "$SNAP" | grep -vxF -e docs/roadmap.md -e "<plan>" | paste -sd, -)
  echo "${D:-no docs beyond the roadmap and plan}"; fi
```
   Report either message verbatim and skip the drift check. Both flags are required.
5. Report every act the review would perform, on the tickets, on the plan, on the roadmap prose and
   on those documents, each with its reason. Nothing is written before this report exists.
6. Act. The roadmap prose goes through `roadmap_set_prose`; the plan and the documents are ordinary
   edits.
7. Prove it, in a later tool call than step 1. Set `ACTS` to the number of acts step 6 performed.
   Changed paths print on `changed during the run` lines because a concurrent edit is
   indistinguishable from the review's own write; each act prints on a `performed` line.

```bash
( cd "$(git rev-parse --show-toplevel)" &&
  RUN=ID && case "$RUN" in ''|*[!A-Za-z0-9]*) RUN=none;; esac &&
  SNAP="$(git rev-parse --git-path "phase-review.$RUN")" &&
  ACTS=N &&
  if [ ! -f "$SNAP" ]; then echo "second-run proof: unproven, no snapshot from step 1"
  elif case "$ACTS" in ''|*[!0-9]*) true;; *) false;; esac; then echo "second-run proof: unproven, ACTS not set"
  else
    sed 's/^[^ ]*  //' "$SNAP" | while IFS= read -r p; do
      if [ -e "$p" ]; then printf '%s  %s\n' "$(git hash-object -- "$p")" "$p"; else printf 'absent  %s\n' "$p"; fi
    done > "$SNAP.after"
    CHG=$(diff "$SNAP" "$SNAP.after" | sed -n 's/^> [^ ]*  /second-run proof: not held, changed during the run: /p')
    if [ -z "$CHG" ] && [ "$ACTS" -eq 0 ]; then
      echo "second-run proof: held ($(wc -l < "$SNAP" | tr -d ' ') paths unchanged, 0 acts)"
    elif [ -n "$CHG" ]; then printf '%s\n' "$CHG"; fi
    rm -f "$SNAP" "$SNAP.after"
  fi )
```

   For each act print `second-run proof: not held, performed: <act>` (for example `close #<N>`),
   also after an `unproven` line.
   `held` prints alone, and only with zero acts and nothing changed.
8. If every ticket is implemented, hand over to `/phase close`. Do not close it here.

## `/phase reassess`

Reshapes the roadmap itself: reorder, split, merge, rename, refocus, delete or insert a phase: the
plan of phases, where `/phase review` judges one phase. The `roadmap-phases` skill is canonical for every rule
and refusal; this is the mechanism only.

Resolve the script the same way:

```bash
RP=$(resolve reassess-phases.sh); echo "using ${RP:-none}" | sed "s|$HOME|~|g"
```

If empty, say so and stop.

1. Ask the user which op and its arguments; do not guess. `bash "$RP" --help` prints the full
   synopsis of all seven ops (`reorder`, `split`, `merge`, `rename`, `refocus`, `delete`, `insert`)
   and their flags.
2. Run it **with `--check` first**, always, and show the user exactly what it would do before
   running it for real. `--check` writes nothing, on the file or the host.
3. Once the user agrees, run it without `--check`. Its exit code decides what happens next:
   - `0`: done. It ends by running `check-phases.sh` itself and reports that verdict.
   - `4`: a ticket move failed partway through. Nothing on the roadmap file was touched, and the
     report names what moved and what is still to move. Fix the underlying problem and re-run the
     identical command; it resumes rather than repeating what already moved.
   - `5`: refused. A rule this reshape would have broken, most often rewriting a `done` phase or
     leaving a phase with nowhere for its open tickets to go. Nothing was written. Quote the
     message; either change the request or stand down.
   - anything else: a usage or environment error; quote it.
4. Never omit `--reason` on a `merge`: it lands in the surviving phase's prose and is the only
   record of why two phases became one.
5. A merge, rename, or delete that empties a milestone reports it **emptied, not deleted**: the
   milestone stays on the host under its old title. Never try to delete or reopen a milestone by
   hand to "clean up" afterward.

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
