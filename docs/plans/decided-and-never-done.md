# Plan: Decided and never done

Written 2026-10-11, when *Guards and scripts that miss a case* closed, after the maintainer asked to
review the roadmap and tickets and start a new phase. Every open ticket (fourteen, all in the
backlog) was read against `develop` at 2f45c47. They split cleanly in two: tickets whose decision is
already recorded or not needed, waiting only for the work, and tickets that wait on a maintainer
answer. This phase takes the first kind. A decision recorded and never acted on decays: the line
numbers it cites drift, the body still describes the options rather than the pick, and the next
reader re-litigates it.

## Goal

Each ticket below lands as its recorded decision says, with its body rewritten to that decision and
gated before the work starts, so no backlog ticket remains whose only blocker is that nobody did it.

## Done looks like

- `forge-gate-mechanics.sh` picks the template with the label case folded, so a `Bug`-labelled
  ticket is checked against `bug.yml`, pinned by a row and a mutant (#476).
- The three copies of `bounded()` (public leaks, forge-lib, contributor-docs suites) each carry the
  two notes and a pointer to the other two, plus one comment saying why there is no shared helper
  or lockstep guard (#261, the 2026-10-07 pick, option 3).
- `health-check` step 9 no longer warns falsely when the token comes from a git credential helper,
  and never prints the token (#454).
- `check-contributor-docs.sh` reports `max-lines` as `referred`, never failing the run, while
  `max-bytes` stays a fail (#302, the 2026-10-07 pick, option B).
- The bash 3.2 and Apple awk harness has a recipe in the repo, so the README's portability claim can
  be re-verified by someone other than the session that first built it (#220).
- `/phase review` steps 1 to 4 call a contract-tested entry point, per the four answers recorded on
  2026-10-07 (#272).
- Each ticket is closed against a named commit, `Validate` is green on `main`, and no component
  baseline is raised.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The body was rewritten to a pick the maintainer did not make.** Three of these tickets (#261,
  #272, #302) carry a decision in a comment and a body that still lists options. Rewriting the body
  is where a paraphrase drifts: a "comments only" pick becomes a shared helper, a read-side-only
  fixture rule becomes a write. Each rewrite quotes the recorded answer and the gate checks the body
  against that comment, not against the old options.
- **The recorded decision was stale and nobody checked.** Every decision here predates at least one
  release. #302's line numbers moved (the asset is at version 24), #454's "allowlisted" wording is
  obsolete after #468. The ticket is re-read against the tree before the rewrite, and a decision the
  tree has since made moot goes back to the maintainer instead of being implemented to the letter.
- **#272 swallowed the phase.** It is the one L, a new shell asset with a new suite and a rewiring of
  `/phase review`. Started first, it leaves five small tickets undone at the end. It runs last, and if
  it does not fit, the phase closes re-shaped with #272 named, not extended.
- **The harness was claimed without being built.** #220's value is a recipe someone else can run.
  A script written and never executed to a working bash 3.2 reproduces the original defect: a claim
  with no evidence. The ticket closes only on a run that builds the toolchain and runs the suites.
- **The token leaked into a report.** #454 probes a credential helper. A probe that echoes what
  `git credential fill` returns, or logs it under `set -x`, prints a secret into a health report.
  The test pins that the token value never appears in output.
- **A one-line fix grew into a gate change.** #476 is one fold in the template picker. If the fix
  reaches into `ticket-gate.md`, the ratchet component, it is out of scope here.

## Expected work

Smallest first, one ticket at a time per plugin group, because the markers and the plugin semver
serialize them. Gate each before work; a gate that needs a judgment call the maintainer has not made
parks the ticket in the backlog with the question named.

1. **#476** (governance, `forge-gate-mechanics.sh`): S, no decision needed.
2. **#261** (three test suites, comments only): S. Rewrite the body to option 3, gate.
3. **#454** (devops, `health-check.md`, maybe `forge-lib.sh`): S to M.
4. **#302** (governance, `check-contributor-docs.sh` and its skill): S to M. Rewrite to option B, gate.
5. **#220** (`scripts/` only, no plugin group): M, needs a real toolchain build.
6. **#272** (roadmap, a new asset and suite): L, last. Rewrite to the four answers, gate.

## Taken in or left in the backlog

- Taken in: #476, #261, #454, #302, #220, #272.
- Left in the backlog, waiting on a maintainer answer: #477 (which of three recovery paths), #443
  (gate step order, measure first), #444 (an agent-free route, A or C), #425 (five gate questions),
  #445 (round-2 gate, A, B or C), #448 (five gate questions). The first four share `ticket-gate.md`'s
  step order and are the natural next phase once answered.
- Left in the backlog with its reason: #226 (decided 2026-10-07, but waits on the maintainer's
  downstream allow-file audit and a final gate run), #282 (a recorded deferral, not work).

## Out of scope

- Any change to `ticket-gate.md`, `full-review.md` or the `adapt` SKILL.md: the ratchet components,
  and every ticket that needs them is waiting on a decision.
- Re-opening a recorded decision because a different option now looks better. A finding that the
  pick no longer fits goes to the maintainer as a comment on the ticket.
