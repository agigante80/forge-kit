# Plan: The leak guard, tightened

Written 2026-10-02 from the backlog, opened when *Tests that can be believed* closed. The only
planned phase, *What a session loads before work begins* (#297), waits on maintainer decisions, so
this phase gathers the leak-guard tickets that can move without one. It opens ahead of #297's phase
for that reason; the order of the two is recorded, not changed.

## Goal

The two leak-guard scanners agree with each other and with their own documentation on every input
a caller can give them: the same verdict in any locale, from any directory, at any size, and from
one shared copy of the code they have in common.

## Done looks like

- Allow-file lines are trimmed with one ASCII byte list in both scanners, so an edge U+2003 reads
  the same under `LC_ALL=C` and a UTF-8 locale (#403).
- A hand-run pre-push with `GIT_DIR`, and the scanners' `--head`/`--all` scope, no longer follow the
  caller's current directory (#401), with the design the gate recommended.
- A short private name can be listed as a whole word, so it stops matching inside ordinary words
  (#222).
- `redact()` is linear in the match length on the default `--history` path (#217).
- The history reader exists once, in a shared asset both scanners source (#206), and the two
  scanners' suites still pass unchanged apart from the rows that pin the sharing.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The shared reader broke one scanner quietly.** #206 moved 130 lines into a library and the
  private scanner's `--history` path lost a branch the public one never had, because only the
  public suite exercised it.
- **A locale fix in one scanner, not the other.** #403's class has now been fixed at three sites
  one at a time (#242, #400, #403); a fourth appears in the other half the week after.
- **#217 went round a fifth time on fixture sizes.** Its gate already hit the trip wire on wall
  times; a fix judged by wall time under load is the #219 trap again.
- **The decision tickets leaked in.** #207, #226 and #391 each need a maintainer pick; implementing
  one on a guessed answer would have to be undone.

## Expected work

In order:

1. **#403**, the trims: smallest, and every later leak-guard change is measured by the parity rows
   it adds.
2. **#401**, the directory anchor, with the gate's recommended design.
3. **#222**, the whole-word entry form in the private scanner.
4. **#217**, `redact()`: re-gate round 4 with the resized fixtures; judge the kill by the bound
   (exit 124, or the escalation's 137 past the grace, as #415 settled), never by wall time alone.
5. **#206**, the shared history reader, last, because it moves the code the others touch.

## Out of scope

- **Maintainer decisions:** #207 (the allow shape for forge-kit's own `--history` findings), #226
  (skip-glob semantics), #391 (the custom redaction marker form). They stay in backlog until picked.
- **The startup-context budget** (#297): *What a session loads before work begins*.
