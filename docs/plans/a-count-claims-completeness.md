# Plan: A count claims completeness

Phase opened 2026-09-14 for #202, filed by the gate on #201: the spelled-out counts in `CLAUDE.md`
("thirty-seven contract test suites", the eighteen/nineteen split, "all fifteen", "All eight shell
assets") and README's "35 contract test suites", every one stale, none generatable.

## Goal

Remove every hand-maintained count that `update-suite-counts.py` cannot anchor, so the only
numbers left in the prose are the ones the tree can check.

## Done looks like

- The six-phrase grep over `CLAUDE.md` and the README grep both print 0.
- Line 19 still names suites, marked "among them", and keeps its main verb.
- `update-suite-counts.py --check` still says 12 claims; the component index stays green.
- Nothing outside `CLAUDE.md` and `README.md` changes.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A list replaced a count and was read as exhaustive.** Line 19 names 18 of 40 suites; without
  "among them" the list is a count wearing prose. That is round 1's finding and the reason the
  marker is in every replacement.
- **A number was deleted from one copy and left in another**, so README still said 35 after
  CLAUDE.md stopped saying thirty-seven. Round 1 scoped the README in for exactly this reason.
- **A replacement sentence lost its verb** and the edit shipped ungrammatical prose into the file
  every session loads. Round 2's advisory; read each edited sentence aloud.
- **The generator's anchors were disturbed**: an edit near a `` `scripts/test-X`, N tests `` claim
  changed what `--list` reports. The 12-claim check is the tripwire.

## Expected work

#202. On close, file one sweep ticket for any remaining spelled-out or digit count in the two
files that no script anchors (line 283's "thirty-eight components" is already known), rather than
one ticket per phrase.

## Out of scope

- Extending `update-suite-counts.py` to words or to the eighteen/nineteen split (options B and C,
  declined in the ticket).
- #191, #196.
