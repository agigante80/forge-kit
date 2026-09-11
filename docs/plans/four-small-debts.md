# Plan: Four small debts from the gate runs

Phase opened 2026-09-11, written from four tickets already in the bucket, all filed by gate runs
in the last two phases and none of them larger than a morning.

## Goal

Pay the four gate-machinery debts the last twelve gate runs filed, and let this phase's own gate
runs be the first driven by the new Step 1 prose without an override.

## Done looks like

- `check-ticket-mechanics.sh` on a body with `##` headings emits `referred` once for the heading
  level, never a `fail` per section; its header rule ("narrower than the doc, so refer rather than
  fail on a heuristic miss") is what the test asserts. Its 41-case suite grows by the cases that
  pin it.
- Step 1's provenance line reads `mechanics: none` on the empty path, prints the path relative to
  `~`, and the tie-break direction ("lexically last") is stated where the order is described (the
  Step 1 comment and the memory note). `/phase` gets the same `${CP:-none}`.
- `adapt/SKILL.md` says `<semver>` for the cache leaf, at no growth to its ratchet.
- The gate's body file is `<scratch>/gate-<NUMBER>/body.md`, and a body whose number is not the
  argument's is refused before Step 3A.
- Every review comment posted in this phase carries a `**Round:**` line and a `mechanics:` line
  that the AGENT printed, with no override in the dispatch prompt.

## Order, and why

#197 first, because it is the one that can corrupt the other three's gate runs if they are run
together, and because its fix is the smallest. Then #190, the only one with a suite behind it.
Then #194 and #195, which are line edits.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **#190 was fixed by loosening the checker.** The obvious edit makes the heading match accept `##`
  as well as `###`, which passes a body the template never produced and is exactly the "fix" #184's
  premortem refused. The correct behaviour is to DETECT the heading level and refer once, which is
  what the script's own rule says; the checker still rules on nothing it cannot see.
- **The new prose was never actually exercised.** The plugin was updated but the session was not
  restarted, so every gate run in this phase still ran the old agent, and the `**Round:**` and
  `mechanics:` lines in the comments were written by hand from the ticket text as they were in the
  last phase. The check is whether the lines appear when the dispatch prompt is the bare number.
- **#194's relative path broke the resolver on a machine where `HOME` is unset or the path has no
  `~` prefix.** A `sed "s|$HOME|~|"` is display only and must never feed the path back into the
  run; if the printed form is the one that gets used, the fix introduced the bug it was cosmetic
  about.
- **#197's refusal fired on a legitimate body.** A body edited by Step 0c carries the gate's own
  markers and sometimes quotes other issue numbers; a check that greps for ANY `#N` will refuse its
  own synthesis. The check is against the fetched JSON's `number`, not the body text.
- **`adapt` grew.** `<sha>` to `<semver>` is a one-token change; if the edit adds a word the ratchet
  fails and the temptation is to ask for a raise for a cosmetic fix, which is the wrong precedent.

## Expected work

#197, #190, #194, #195. Nothing else; a fifth ticket arriving from these gate runs goes to
`backlog` unless it blocks one of the four.

## Out of scope

- #196, restoring round MEMORY from the latest review comment. A design choice, not a debt; stays in
  `backlog` until someone wants it.
- #191, the leak guard's history mode. Still blocked on the bash 3.2 contradiction.
- Any change to what the checker RULES on. #190 is about how it reports a miss, not what it checks.
