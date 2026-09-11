<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Installing `check-ticket-mechanics.sh`

This skill ships Step 3A's mechanical checks as `assets/check-ticket-mechanics.sh`. Copy it to
`scripts/` VERBATIM at install time, the way `forge-host` copies `forge-lib.sh`. It IS Step 3A,
not an optimisation: without it the gate takes its "record every check as referred" fallback and
performs NO mechanical checks, which reads as a working gate.

`assets/count-gate-rounds.sh` travels with it (#192): Step 1 runs it from the same directory to
count the round from posted review comments, and without it the gate cannot count rounds at all,
which is the state that let a body edit reset every round to 1. Both need `forge-lib.sh` beside
them, or `FORGE_LIB` pointing at one.
