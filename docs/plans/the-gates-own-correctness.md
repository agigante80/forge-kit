# Plan: The gate's own correctness

Written 2026-10-01 from the roadmap prose and the four tickets in the bucket, opened when *What
contributor-docs still cannot see* closed. Two of the four were partly done by work that landed
while they waited: the #304 review fix (fd05cba) already skips a body region to the end marker of
its own name, which was #335's open choice, and the #259 batch moved every awk value in
`check-ticket-mechanics.sh` to `ENVIRON`.

## Goal

The gate never fails a ticket for a shape its own critic recommends or its own writer produces, and
its procedure carries no state across Bash calls that a fresh shell loses.

## Done looks like

- A scenario label the critic advises (`Positive (control: ...)`) and every label the gate writes
  passes check 4, proven by extracting the documented examples from `ticket-gate.md` and running
  them through the real checker, with a mutant per example (#349).
- Step 5's `FORGE_LIB` resolver refuses an invalid path, Step 3A and Step 6 re-source and re-derive
  what they use in each call, the agent says what it returns after an `exit 2`, and
  `forge_issue_comment` cannot post an empty body or report a false dry-run pass above the argv
  limit (#347).
- A required field never shares a gate-filled field's exemption by label, the region-marker anchor
  has a near-miss case, and the sections evidence names the exempted fields first (#320).
- Nested and mismatched region names have cases, and the header's indent wording is exact (#335).
- `ticket-gate.md` plus its preloaded skill stays at or under the 5754-word ratchet, every word
  added paid for by a named cut.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The ratchet was raised instead of paid.** #347 and #349 both add prose to `ticket-gate.md`,
  which has no headroom; the easy move is a `LOWERED`/raised baseline entry, and the phase ends with
  a bigger gate than it started.
- **#349 moved the checker to fit the advice.** Widening `marker_re` to accept `Control` reopens the
  #205 near misses the anchored grammar exists to refuse. The guidance side was the recommendation.
- **The fresh-shell fixes were prose only.** A sentence telling the agent to re-source is the shape
  #321 replaced with a guard because prose was not followed; a step that still names a variable from
  an earlier call has not been fixed.
- **#347's forge-lib half stalled the prose half.** Item 6 (the argv limit on both hosts) is a
  library change with its own tests; bundled with the procedure items, it held them all.
- **A ticket was closed on a stale reading.** #335's items look done; closing it without the nested
  and mismatched cases it asks for would leave the name-matching rule untested.

## Expected work

In order:

1. **#335**, record that name matching landed in fd05cba, add the nested and mismatched region
   cases and their mutant, fix the indent wording; re-gate first.
2. **#320**, the per-row gate-filled flag, the region-anchor near miss, the evidence wording. Gate
   first; it has none.
3. **#349**, guidance side: Step 3B element 3 and Step 6 item 2 give accepted shapes, an
   extract-and-run test pins them. Its required changes go in, then a re-gate.
4. **#347**, after deciding the scope split the gate advised: the procedure items (1 to 5) here,
   item 6 and the `forge_api` argv limit split to their own ticket if they do not fit.

## Out of scope

- **New ticket-gate features** (#286, #263, #277, #213 in `backlog`); this phase fixes what exists.
- **The test-harness flakes** (#404, #378, #331, #219, #360): *Tests that can be believed*.
- **Portability sweeps** (#377, #379, #405, #407): *Portable shell, everywhere*.
