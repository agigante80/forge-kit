# Plan: The sweep the gate finished

Phase opened 2026-09-14 for #203, the one-phrase sweep ticket #202's close filed, which the gate
turned into a three-phrase one: my sweep grepped for spelled-out numbers before a component noun
and missed "six copies" and "six sites" (the guard prints 7).

## Goal

Remove the last live counts in `CLAUDE.md` that no script anchors, and the same counts from the
three script comment headers, so the only numbers left in prose are ones the tree can check.

## Done looks like

- `grep -cE 'thirty-eight|six copies|six sites' CLAUDE.md` prints 0; each of the three script
  headers greps 0 for its phrase.
- The number is REMOVED, never corrected to 28 or 7.
- `update-suite-counts.py --check` still 12 claims; every guard the edited files belong to green.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The number was corrected instead of removed.** "All 28 components" is the same defect one
  bump later, and nothing greps for it. AC 1 forbids the digit form.
- **A comment edit broke a sentence across two lines** ("every / components"), because the
  header wraps and the edit looked only at the line with the number.
- **The sweep was declared complete a third time on the same grep.** This phase's grep is the
  gate's, over both files and the script headers; anything it misses is a new ticket, not a
  claim that nothing is left.

## Expected work

#203. Nothing else.

## Out of scope

- `README.md:173` "six collisions" and `README.md:8` "the last six phases": unanchored, accurate
  today, and named here so the next sweep starts from them rather than from zero.
- #191, #196.
