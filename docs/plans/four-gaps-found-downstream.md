# Plan: Four gaps found downstream

Phase opened 2026-09-16 for #205, filed by the maintainer after gating twelve hubbub tickets with
the mechanics script: four heuristic misses, each hit by at least one run. Gated twice (round 2
PASS overnight); the gate corrected the diagnosis of gap 1 on the way.

## Goal

Make `check-ticket-mechanics.sh` read the shapes a downstream project actually produces: a long
absent-list, a qualified Positive/Negative marker, a renamed E2E section, and a template whose
defaults carry sub-headings.

## Done looks like

- Gap 1: the sections evidence carries a count prefix and is never truncated for any shipped
  template; a companion asserts the count equals the items listed.
- Gap 2: one marker regex shared by all seven sites; qualified and bold markers count; a prose
  line starting with the bare word does not.
- Gap 3: no `--e2e-label`; role detection by id then label, E2E before integration; a template
  renaming both still gets pass/fail; the three E2E-less templates still refer.
- Gap 4: a template's own `value:`/`placeholder:` sub-headings are content inside THEIR field,
  scoped per field; feature.yml's own E2E placeholder no longer produces two false fails.
- Suite green under bash 5 and 3.2; `check-restatements.sh` green; marker v7; group 0.16.6.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The marker regex admitted prose.** `Positive outcome expected here` read as a block with no
  When and FAILED a compliant ticket, the direction the script forbids. The near-miss fixture is
  the tripwire, and there is one regex, not seven.
- **The id column leaked into check 3.** `read -r label required` took the id as the required
  flag and check 3 failed open. `--dump-fields` keeps two columns; internal readers take three.
- **A sub-heading from another field was treated as content.** Scoping is per field; the case
  where `### Happy path` sits under Unit tests pins it.
- **The bound was widened and the count omitted**, so the next longer template truncates silently
  again. The count prefix is what makes truncation visible, and the companion checks it.

## Expected work

#205. Follow-up to file on close: 0c synthesis keyed on id `e2e_tests` in `ticket-gate.md:116`
cannot synthesise a renamed section (ratcheted file, maintainer decision).

## Out of scope

- #204 (area labels), though it edits the same script; separate phase.
- `ticket-gate.md`.
