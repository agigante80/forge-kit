# Session handoff: four one-ticket phases and a generator

Date: 2026-09-14 (session began 2026-09-12)

## Summary

Verified the restart claim the last session could not, then took four tickets through four
one-ticket phases with the gate on each: two pins on the leak-guard headers, a generator for the
suite counts `CLAUDE.md` states, and the removal of every count the generator cannot anchor.

## Done this session

- **Restart verified**: cache `0.16.5/` carries `ticket-gate-version: 55`; the first gate run
  printed `**Round:** 1` then `2`, counted from comments, with a `~`-relative mechanics path.
- **Phase "One sentence, two pins"** (#199): the `grep -a` sentence pinned in both leak-guard
  suites through `--help`, 81/41 cases, mutation-checked. Round 1 caught "Documentation impact:
  None" against the two `CLAUDE.md` counts.
- **Phase "The sentence that matters more"** (#200): `never looks at history` and `history-aware
  scanner` pinned, 83/43. PASS in one round.
- **Researched "hook or script" for count drift** (Cog `--check`, consistency tests, the repo's
  own `update-component-index.py`), and running the suites found three more stale counts.
- **Phase "A number the tree can check"** (#201): `scripts/update-suite-counts.py` (`--check`,
  `--list`, `--doc`, `--root`; combined stdout+stderr, last matching line, three shapes; refuses
  with exit 2 rather than writing 0) plus a 47-case contract test, both in CI. Fourteen mutants
  die. First run fixed 25 to 45, 79 to 80, 22 to 81. Twelve claims now, the suite counting itself.
- **Phase "A count claims completeness"** (#202): six prose edits removing the spelled-out counts
  (line 19, 90, 145, README line 8); "among them" on both name lists. Two rounds, stopped.
- Filed #203 (line 283's "thirty-eight components", the one phrase the sweep found).
- Memory: surviving mutants are first a question about the mutant; the milestone counter lags a
  close; plugin restart verified; six days of gating measured.

## In progress (where we left off)

Nothing. `main` = `develop` = `52886db`, Validate green, no phase open, no background agents. The
memory and handoff files from this close were committed and merged in the same close.

## Next steps

1. **#203** waits for the next gated `CLAUDE.md` change and is folded into it (maintainer chose
   this over its own gate round). It is one sentence: "Every component is user-scoped today, and
   `check-component-scope.sh` prints the count."
2. **#191** still waits on the macOS awk probe in its `### Decision` section. Needs a Mac.
3. **#196** stays in Backlog until someone wants round MEMORY, not only the number.
4. The pre-commit fast path for `update-suite-counts.py --check` was decided OUT in #201; revisit
   only if a count drifts between CI runs.

## Decisions and why

- **Option C for #201** (generate in place, cog-style, anchored on the existing prose shape with
  no inline markers) over A (delete) and B (check-only): the numbers carry a signal the gate
  used as evidence, and the repo already has the generated-region pattern.
- **Option A for #202** (delete the words): a spelled-out number and the eighteen/nineteen split
  cannot be anchored without number-to-word rendering and a split rule nothing defines.
- **"among them" on every name list**: round 1 showed line 19's list was stale by OMISSION (18 of
  40 named), which is invisible, where I had claimed a stale name is visible.
- **Two rounds, hard stop, every time**: #202's round 2 found one defect in round 1's fix; it was
  folded into the body and no third round ran. Defect-in-prior-fix count for the day: one.
- **README line 8 taken into #202's scope** though the gate marked it adjacent: leaving one copy
  of the count is leaving the defect.
- **Mutant survivors fixed in the test, never the generator**: all four survivors were the mutant
  or the fixture (see memory).

## Open questions / blocked on

- BWK awk on macOS (#191). Unchanged.
- Whether one-ticket phases are the right grain: four today, each 20 to 60 minutes of work plus
  two gate runs (~250k tokens per ticket). The gate's catches justified it every time, but the
  ceremony per ticket is now larger than the ticket.

## Key context to reload

- `gh issue list --state open` (three, all Backlog: #191, #196, #203)
- `.claude/memory/gate-new-tickets-from-now-on.md` (six days measured),
  `surviving-mutant-check-the-mutant-first.md`, `milestone-counter-lags-after-close.md`
- `scripts/update-suite-counts.py --list` (the twelve claims), `docs/roadmap.md` last four closes
- `docs/plans/a-number-the-tree-can-check.md` premortem, every clause of which became a test case
