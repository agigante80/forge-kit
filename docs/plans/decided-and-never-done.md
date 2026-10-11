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
- Added the same day, after the maintainer answered the decision brief (each pick is at the top of
  its ticket body, under "Maintainer decision (2026-10-11)"):
  - #477: an interactive two-session probe records whether a subagent waits for its background
    child; if the gate still ends early, Step 3B runs the critic inline, word-neutral or shrinking.
    `no-poll-loops`' subagent wording from #475 matches what the probe shows in both modes.
  - #443: one failing and one clean gate run measured per step with #280's harness, the numbers
    posted, and the decision on running Step 3A first recorded. No behaviour change.
  - #425: with `labels.md` absent, the labels row is `referred` and names the built-in fallback and
    the Templates-mode fix, pinned by four rows and their mutants.
  - #445: round 2 stays `always`; the evidence, the rule that a gated round 2 is never downgraded to
    `sonnet`, and how to count round-2 yield are in a `docs/guides` page. `full-review.md` unchanged.
  - #448: `review-sizing` carries the procedure to offer a filtered default `.full-review-sensitive`,
    written only on approval and never over an existing file; forge-adapt's `references/commands.md`
    points at it.
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
- **One probe was called the truth for both modes.** #475 shipped wording from a headless probe, and
  the docs say interactive differs. #477's probe runs interactive, two sessions, on a named release,
  and its result is reconciled with #475's wording rather than stacked beside it.
- **The inline critic quietly kept the old word count.** #477 option (b) deletes a dispatch and adds
  an inline step; if the deletion is skipped, the ratchet fails, or worse, words are found by
  trimming an unrelated rule. The edit is paid for from Step 3B's own dispatch text.
- **A measurement became the decision.** #443's numbers inform the choice of option A; they do not
  make it. The ticket closes on posted numbers and a recorded decision, not on a reorder of steps.
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
6. **#425** (governance, `check-ticket-mechanics.sh`): S. Decision in the body.
7. **#448** (review, `review-sizing/SKILL.md` and an adapt reference row): S to M.
8. **#445** (docs only): S.
9. **#443** (measurement only, no code): S to M, needs two real gate runs.
10. **#477** (governance): probe first, then (b) only if the interactive gate ends early. M. After
    #425, because both may edit `ticket-gate.md` Step 0b to 3B.
11. **#272** (roadmap, a new asset and suite): L, last. Rewrite to the four answers, gate.

## Taken in or left in the backlog

- Taken in: #476, #261, #454, #302, #220, #272.
- Taken in after the decision brief (2026-10-11): #477, #443, #425, #445, #448.
- Closed as decided: #444 (one critic always; reopen when #443's numbers and a content-keyed section
  fallback exist).
- Left in the backlog with its reason: #226 (option 1 reconfirmed 2026-10-11; waits on the
  maintainer's downstream allow-file audit, whose script is now in its body, then a final gate run),
  #282 (a recorded deferral with a review date of 2027-01-11, not work).

## Out of scope

- Any growth of `ticket-gate.md`, `full-review.md` or the `adapt` SKILL.md, the ratchet components.
  #477 and #425 may edit `ticket-gate.md` only word-neutrally or shrinking; nothing here edits the
  other two.
- Re-opening a recorded decision because a different option now looks better. A finding that the
  pick no longer fits goes to the maintainer as a comment on the ticket.
