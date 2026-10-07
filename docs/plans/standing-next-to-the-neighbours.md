# Plan: Standing next to the neighbours

Phase opened 2026-09-10, written from the roadmap prose plus a measured comparison of this tree
against the two installed official marketplaces and the superpowers plugin.

## Goal

Make "forge-kit complements superpowers and the official plugins" a property the build checks,
and stop shipping files whose only forge-kit contribution is a version marker.

## Done looks like

A guard fails the build when a component here collides with one the neighbours ship. The five
measured near-duplicates are gone or justified in writing. `forge-adapt` suppresses an official
counterpart the same way it already suppresses a superpowers one. Each retirement names where the
real component lives, so a user losing one is told what to install instead.

## Order, and why

**The guard first, before any retirement.** Every other ticket here is a one-off cleanup, and a
cleanup with nothing holding it is a cleanup that is undone by the next well-meant addition. This
repo has the evidence: the superpowers boundary has been prose since #69 and was violated five
times without anything noticing.

Then the retirements, which the guard will then be enforcing rather than proposing. Then the
forge-adapt coexistence rows, which are the runtime half of the same rule. The naming convention
after that, because it is cosmetic next to the rest and touches every agent file.

**The README rewrite is last, and that is a hard ordering rather than a preference.** It documents
what the other four decide, so running it earlier means describing a boundary that is still moving.
The README is also the least-guarded file in the repository, checked only by the leak scanner and
two generated regions, so a wrong claim there survives longer than anywhere else.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The guard was built against a list nobody can regenerate.** A manifest of what the neighbours
  ship is a snapshot, and a snapshot with no refresh path is a claim that quietly stops being true.
  If the regeneration script is not part of the first ticket, the guard is worse than nothing by
  the second month.
- **The guard fails a build for a name two ecosystems chose independently.** `code-reviewer` is a
  name anyone would pick. A guard that treats every collision as a defect will be switched off. The
  hard part is not detecting overlap, it is deciding which overlaps matter, and the ticket has to
  answer that before it writes a line.
- **A retirement was done by deleting files.** Users have these groups enabled. A delete that
  arrives as a failed load is the failure #169 already caused on the maintainer's own machine
  within an hour of shipping. Deprecation needs a path, and the path needs to be stated before the
  first file moves.
- **The phase turned into a rewrite of the review agents.** `full-review` diverged from its
  upstream by adding the iteration contract, which is exactly what this kit should be doing. It is
  in scope to DOCUMENT that, and out of scope to redesign it.
- **The comparison was taken as an instruction rather than as evidence.** Four of the seven name
  collisions are components with genuinely different content on both sides. Retiring one because
  its name appears elsewhere would lose real material to a tidy table.
- **The kit shrank and nobody could say what it gained.** The measure is not component count. If
  the phase ends without a shorter, clearer answer to "why would I install this next to what I
  already have", it failed whatever the diff says.
- **The README was rewritten from the plan rather than from the tree.** It is the least-guarded
  file here, and the three errors corrected on the day this phase opened had all been wrong for
  months, including one introduced that same afternoon. A rewrite is the easiest place in this
  repository to state something false and the hardest place to notice it.

## Expected work

Five tickets. The guard, the retirement set with its deprecation path, the neighbour coexistence
rows in forge-adapt, the agent naming convention, and the README rewrite that documents the result.
Any of the first four may end as a documented decision rather than a change; that is a finished
outcome. The fifth cannot, because the README is wrong today whatever the others conclude.

## Out of scope

- Redesigning `full-review`, `code-reviewer` or any component whose content genuinely diverged.
- Chasing the official plugins' surface area. They will always ship more agents.
- #176, the `adapt` line-count question, which stays in the backlog and is unrelated.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-10, outcome **done**. All five tickets landed in the plan's order, guard first, and
5,507 lines were deleted.

**The premortem's fifth clause fired, on the ticket it was written about.** It warned against taking
the comparison as an instruction rather than as evidence, and `architect-review` is exactly that
case: the table said retire, and `/full-review` dispatches it by name, so retiring it would have
broken the one component the phase existed to protect. It stayed, allowlisted, with the reason in
the file. The sixth clause fired too, on the README: the first draft claimed 22 guards and 34 test
suites and was wrong on both, which is why criterion 8 asked for every number to be checked against
the tree.

**One thing went wrong that no clause named.** The overlap was measured before its SOURCE was
checked, so the first hour of this phase credited five near-duplicates to Anthropic when they are
wshobson/agents, the upstream forge-kit's specialist agents were forked from. It reached a public
README and two ticket bodies before `known_marketplaces.json` was read. The measurement was right
and the attribution was not, which is a distinct failure from the ones the premortem imagined.

Two to carry forward. `adapt` went 7314 to 7300 to 7209 in one day, every step through the #149
lever, which is now the fourth time converting prose to a tested script on that one file has been
the only way to add a rule to it. And the boundary is now checked in both directions: at build time
by `check-neighbour-overlap.sh`, and at install time by `forge-adapt-neighbour-disposition.sh`.

Opened 2026-09-10 after measuring this tree against the two installed official marketplaces and
superpowers. The kit's stated reason for existing is to complement them, and decision #69 draws the
line: superpowers owns the inner loop, forge-kit the outer.

That line is prose in a skill. Meanwhile `check-group-isolation.sh` fails the build if anything
outside the roadmap group so much as names it, to keep one optional group optional. The claim that
defines the project is the least enforced thing in the repository, and five components have already
crossed it: `tdd-orchestrator` (4 lines differ from the official file, of 185),
`backend-security-coder` (4 of 155), `pr-enhance` (6 lines of about 2,000 words),
`architect-review` (12 of 172) and `backend-architect` (13 of 320).

The counter-example is the one to protect. `full-review` shares an ancestor with wshobson's
`comprehensive-review` and diverged by 174 lines, and what diverged is the ITERATION CONTRACT: round
accounting, the trip wire, bad-fix injection, none of which the original has. That is outer-loop
discipline added to an inner-loop tool, and it is what this kit should be doing wherever it touches
a neighbour.

The attribution matters and was wrong for the first hour of this phase. `claude-code-workflows` is
`wshobson/agents`, a community collection and the upstream these agents were forked from;
`claude-plugins-official` is Anthropic's, and superpowers is distributed through it from
`obra/superpowers`. All five near-duplicates are wshobson's, not Anthropic's. The phase closes with
a README that says so, which is #181.
