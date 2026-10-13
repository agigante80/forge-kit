# Plan: What the last phase turned up

Written 2026-10-12, unattended, at the start of an overnight run whose brief from the maintainer was
to leave no open ticket. *Decided and never done* filed four bugs while doing its own work. Each is
small, each is a case a shipped guard, checker, suite or probe did not cover, and none waits on a
maintainer answer.

## Goal

Each of the four lands with a row that failed first and a mutant that dies, or, for the probe, with
a recorded interactive session whose result reconciles with the wording already shipped.

## Done looks like

- `overnight-guard` denies `rm -rf` of the project root when the root is reached through a shell
  variable alias or after a `cd` in the same command, and still allows the same deletes inside
  `tmp/` (#478).
- `check-ticket-mechanics.sh` refers a lowercase one-line GWT scenario instead of failing it, and a
  correctly cased one still passes (#479).
- `test-check-private-leaks.sh` runs to completion under bash 3.2 at the #439 bash-pin mutant row,
  re-verified on the harness #220 left in the repo (#480).
- An interactive two-session probe records whether a depth-2 subagent's late Agent result reaches
  its parent, and `no-poll-loops`' wording matches what the probe shows (#484).
- Each ticket is gated before work, closed against a named commit, `Validate` is green on `main`,
  and no component baseline is raised.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The guard fix broke a delete the night depends on.** #478 tightens what `overnight-guard`
  refuses. A pattern wide enough to catch `rm -rf "$R"` also catches `rm -rf "$PWD/tmp/x"`, and the
  next overnight run cannot clean its own scratch. The suite pins the allowed `tmp/` deletes beside
  the new denials.
- **The alias check became a shell parser.** Following variables through arbitrary shell is
  unbounded. The fix covers the two shapes the ticket names and says in the hook which shapes it
  does not follow, rather than growing until it is wrong in a new way.
- **Referring hid a real failure.** #479 turns a fail into a refer. If the fold is applied before
  the structural check, a scenario with no Given at all is referred too. The row set includes a
  malformed scenario that must still fail.
- **The hang was fixed by skipping the row.** #480's quickest green is to skip the mutant under
  bash 3.2. That removes the portability evidence the row exists for. The fix makes the row finish,
  and the run that proves it is a real bash 3.2 run.
- **The probe was headless again.** #484 exists because a headless probe was taken as the truth for
  both modes. It runs interactive, in tmux, on a named release, and its session record is posted.

## Expected work

Smallest first; #478 first because a guard that can delete the project is the riskiest open defect.

1. **#478** (governance, `overnight-guard` hook and its tests): S to M.
2. **#479** (governance, `check-ticket-mechanics.sh`): S. After #425, which edits the same asset.
3. **#480** (`scripts/` only): S, needs the bash 3.2 harness.
4. **#484** (governance, probe, maybe `no-poll-loops` wording): S to M.

## Taken in or left in the backlog

- Taken in: #478, #479, #480, #484.
- Left in the backlog with its reason: #282 (a recorded deferral with a review date of 2027-01-11).

## Out of scope

- Any growth of `ticket-gate.md`, `full-review.md` or the `adapt` SKILL.md, the ratchet components.
- A general shell parser in any hook.

## Close record

Closed 2026-10-13, unattended. **Outcome: re-shaped.** Three of the four planned tickets landed, and
the work grew: fixing the gate's own scripts turned up ten more bugs of the same family, filed and
fixed inside the phase. Two tickets moved to the backlog, each parked on the review loop's trip wire
rather than finished on a third revision in a row.

| Ticket | Landed | Notes |
|---|---|---|
| #478 | eac7279, d19cc81, 7b7d5a7 | `overnight-guard` denies the project delete through an alias or after a `cd` |
| #479 | 9a802fa, 1793cf5, 32f479d | A lowercase one-line GWT scenario is referred |
| #480 | 1fb8074, bef77c9, bed0ea0 | The bash 3.2 mutant row finishes on the real harness |
| #485 | b9712ab, 838b5fa, 376e25e, 335572d | A template heading inside a fence is not the section |
| #489 | 335572d, 2025532 | CI runs the suites under mawk where `validate.yml` says so |
| #486 | f74af51, 7c9b107, 69ffabe | A region marker inside a fence is plain text to `forge-lib` |
| #487 | 709cfa4, ac787c9, 54562d0 | A no-When header never hides another block's When count |
| #488 | 4ce390e, 8c902d1 | A 2 or 3 space fence is read under mawk |
| #490 | 56296e2, 9efe266, 513233a, b237f9d | A scenario line inside a fence is plain text to the GWT scans |
| #491 | d54023e, 25e125a | A CRLF ticket body reads as its LF copy |
| #493 | 2bf2c79, a730e9c | A CRLF issue template reads as its LF copy |
| #492 | f985e17, 98c7034 | A quoted template `label:` is compared by its YAML value; filed by another session and taken in |
| #484 | moved to the backlog | Needs an interactive probe; parked on the trip wire |
| #494 | moved to the backlog | Gate round 3 found a gap in the round 2 revision; parked on the trip wire |

**The premortem, clause by clause:**

- *The guard fix broke a delete the night depends on*: did not. #478's suite pins the allowed `tmp/`
  deletes beside the new denials.
- *The alias check became a shell parser*: did not. The hook names the two shapes it follows.
- *Referring hid a real failure*: did not. #479's rows keep a scenario with no Given failing.
- *The hang was fixed by skipping the row*: did not. #480 ran on a real bash 3.2.
- *The probe was headless again*: avoided by not running it. #484 cannot be done headless, so it
  went to the backlog rather than being answered by the wrong kind of session.

**What appeared that the plan did not expect:** ten tickets, most in one family (a checker that
reads a fenced example, a CRLF file or a quoted YAML value as something it is not). Most were found
by reviewing the fix before them. Every low a review raised was fixed, ticketed or dropped with
its reason.
