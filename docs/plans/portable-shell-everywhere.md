# Plan: Portable shell, everywhere

Written 2026-10-01 from the roadmap prose and the five tickets in the bucket, opened when *The
gate's own correctness* closed. It opens ahead of *Tests that can be believed*, which sits before
it in the roadmap, because every ticket here is mechanical while that phase's flakes still lack a
load recipe two gate rounds could agree on; the order of the two is recorded, not changed.

## Goal

A shipped or repository shell script behaves the same in any caller's shell: no `cd` echoes under
`CDPATH`, no awk operand is read as an assignment, no Bash call reads a variable a previous call
set, and no count moves with the caller's locale.

## Done looks like

- Every `cd` inside a command substitution or before a stdout row is CDPATH-safe (#377), and a CI
  guard fails a new bare one in shipped and repository scripts (#379).
- No awk program in a shipped asset takes a caller-controlled file operand that a `name=value`
  shape turns into an assignment, and the zero-`awk -v` counts cover the spellings they missed
  (#405).
- `/phase`'s `CP` and `SP`, and every other Bash block a command or agent spans across calls, are
  rebuilt in the call that uses them; `NO_MARKETPLACE` is assigned or removed (#407). ticket-gate's
  share already landed with #347's `gate-env.sh`.
- The component-size word count is the same under `LC_ALL=C` and a UTF-8 locale (#410).

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The guard was a grep that the fixes then had to dodge.** #379 matched text, not the shell's
  meaning, and the phase ended with `# not a cd` comments sprinkled through the tree to quiet it.
- **The sweep fixed the instances and not the class.** Each ticket found five sites and fixed five,
  and the sixth shipped next week because nothing fails on it.
- **A portability fix broke the platform it was not tested on.** `C.UTF-8` does not exist on macOS;
  a `--` that BSD tools reject; a `readlink -f`. The suites ran on Ubuntu only and said nothing.
- **#407's sweep re-did #347.** ticket-gate's lost variables are fixed; reopening them would spend
  the ratchet a second time.

## Expected work

In order:

1. **#410**, the locale-independent word count. Small, and every later commit touching a
   component is measured by it.
2. **#377**, the CDPATH sweep, then **#379**, the guard that keeps it swept.
3. **#405**, awk operands and the `-v` counts.
4. **#407**, the remaining lost-variable sites (`/phase`, `NO_MARKETPLACE`).

## Out of scope

- **The test-harness flakes** (#404, #378, #331, #219, #360): *Tests that can be believed*.
- **The startup-context budget** (#297): *What a session loads before work begins*.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-10-01, outcome **done**. All five planned tickets landed, in the planned order: #410 (one word-count rule, the index generator's, in every locale; no baseline moved), #377 (30 `cd` sites to `CDPATH= cd --`, pinned by `scripts/test-cdpath.sh`), #379 (the `check-cdpath-cd.sh` CI guard; the four sites #377 had called immune were converted rather than exempted), #405 (31 awk file operands to redirects, and one shared `scripts/awkv-count.sh` for the zero-`-v` and no-operand rules), and #407 (`/phase`'s values through the shipped `phase-env.sh`; forge-adapt's `NO_MARKETPLACE` assigned from S2). Two tickets appeared: #411, a parallel-copy flake found while gathering load evidence for the next phase, landed there ahead of it; #412, roadmap-lib's 11 remaining `awk -v` values, which #405 pinned as a ratchet, went to backlog. The premortem held: #379's guard is a stated text rule with no `# not a cd` exemptions; each sweep closed its class with a guard or a shared check, not a list (#379, #405's `awk_operand_lines`); the guard runs under gawk, mawk, BWK awk and busybox, which caught a BWK `match()` bug on a `substr()` temporary before it shipped; and #407 verified #347's ticket-gate share rather than redoing it.

Opened 2026-10-01, when *The gate's own correctness* closed, ahead of *Tests that can be believed*: every ticket here is mechanical, while that phase's flakes still need a load recipe two gate rounds could not settle. #410 joined the bucket the day it opened, and #347 already landed ticket-gate's share of #407.

A bucket, filed 2026-10-01. The sweeps #259 and #321 started and did not finish: a cd that echoes under CDPATH (#377) and the guard that would stop it coming back (#379), awk file operands shaped name=value and the blind spots in the zero-awk-v count (#405), and the lost-variable class outside forge-adapt (#407). Each is a class, so each wants a guard, not just a fix.
