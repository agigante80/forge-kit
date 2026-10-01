<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Installing `check-ticket-mechanics.sh`

This skill ships Step 3A's mechanical checks as `assets/check-ticket-mechanics.sh`. Copy it to
`scripts/` VERBATIM at install time, the way `forge-host` copies `forge-lib.sh`. It IS Step 3A,
not an optimisation: without it, or without `gate-env.sh` beside it, Step 1 stops the run with
`BLOCKED - RUN_FAILED` (#347), because a gate that performed no mechanical checks would read as a
working one.

`assets/gate-env.sh` travels with it (#347): Steps 1, 3A, 5 and 6 each source it, from the
checker's directory, to rebuild what a fresh shell loses and to resolve `forge-lib.sh`.

`assets/count-gate-rounds.sh` travels with it (#192): Step 1 runs it from the same directory to
count the round from posted review comments, and without it the gate cannot count rounds at all,
which is the state that let a body edit reset every round to 1. Both need `forge-lib.sh` beside
them, or `FORGE_LIB` pointing at one.
