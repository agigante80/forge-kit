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
