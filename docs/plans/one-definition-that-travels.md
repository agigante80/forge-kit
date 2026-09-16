# Plan: One definition that travels

Phase opened 2026-09-16 for #204, filed by the maintainer from the hubbub adoption: `labels.md`
promises project-specific area labels and the mechanics script never learns them.

## Goal

The area set the gate checks against is the project's own `docs/guides/labels.md` table, passed
explicitly by both callers, replacing the compiled-in nine wherever a table exists.

## Done looks like

- `check-ticket-mechanics.sh --labels-doc <path>` reads the `### Area labels` table's first
  column with the same awk `check-label-taxonomy.sh` uses; REPLACEMENT semantics; explicit
  `--area-labels` wins; no doc or no table means the compiled-in nine, never a wider set.
- `ticket-gate.md` Step 3A and `forge-gate-mechanics.sh` both pass `--labels-doc`; the agent does
  not grow (the drifted type-set parenthetical at Step 0b pays for it).
- `labels.md`'s "Adding project-specific labels" says the table is where the set comes from;
  `check-label-taxonomy.sh` rule 2's comment says what the default now is.
- Cases in the mechanics suite (protocol-only passes; a compiled-in area absent from the table
  fails; precedence; missing doc; empty table) and in the harness-free suite (the flag is passed).

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The set widened.** A doc the gate could not read fell back to the union of both sets, or a
  malformed table row became an area. A missing or empty table narrows to the nine; a row is an
  area only if it is a backticked first column.
- **The agent grew past its ratchet** and the build failed, or the parenthetical came back as a
  restatement that `check-label-taxonomy.sh` rule 3 then flagged.
- **The two callers diverged**: the agent passed the flag and the harness-free entry point did
  not, so `forge-gate-mechanics.sh` judged a different taxonomy from Step 3A.

## Expected work

#204. #214 (forge-adapt installs neither labels file) is already filed by the gate.

## Out of scope

- #214, #213, #206.
