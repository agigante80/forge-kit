# Plan: The sentence that matters more

Phase opened 2026-09-13 for #200, the follow-up #199's close filed: the "never looks at history"
sentence, the leak guard's most important reach statement (#185), is pinned in neither suite.

## Goal

Pin each scanner's history limit, and its pointer to a history-aware scanner, the way #199 pinned
the `grep -a` sentence: by that scanner's own suite, through `--help`.

## Done looks like

- Two cases per suite (`never looks at history`, `history-aware scanner`), each needle occurring
  exactly once in that scanner's `--help`; totals 83 and 43.
- The private suite's `--help` section comment no longer says it pins "only" the `grep -a`
  sentence.
- Deleting either sentence from a scratch copy of either scanner fails exactly that suite by
  exactly one case.
- `CLAUDE.md` says 83 and 43. Nothing under `plugins/` changes.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A needle that occurs twice was chosen** (`gitleaks` appears twice in the public `--help`), so
  the mutation check passed with one occurrence still standing and the pin was half a pin.
- **The two wordings were forced into one shared needle**, and the header was edited to fit the
  test, which #199's plan already forbade.
- **The comment #199 wrote in the private suite was left saying "only"**, which was true for one
  day and would then mislead the next reader into moving the history case elsewhere.
- **The `CLAUDE.md` counts drifted again**, the third time. If it happens, the answer is a guard,
  not a fourth manual edit.

## Expected work

#200. Nothing else.

## Out of scope

- A mechanical check on the `CLAUDE.md` suite counts (the gate's advisory 3): a decision for the
  maintainer, not this phase.
- #191, #196.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-13, outcome **done**. One ticket, one gate round (PASS first time, the first hand-filed
ticket here to do so), no follow-up filed. Two of the gate's advisories were taken: two needles per
suite rather than one, since `gitleaks` is named twice in the public help and would have broken the
exactly-once mutation property, and the private suite's comment that #199 wrote the day before,
which said "only" and would have been false by the afternoon. One mutation run survived on the
first pass, and it was the mutation that was wrong, not the test: the private header spells its
pointer in lowercase and the mutant was case-sensitive. The gate's third advisory, a mechanical
check on `CLAUDE.md`'s hand-maintained suite counts after two round-1 findings on them, is left as
a question for the maintainer rather than a ticket.

Opened 2026-09-13 for #200, the follow-up #199's close filed. Same shape as the last phase, for
the sentence the leak guard's whole limit rests on (#185).
