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
last, because it is cosmetic next to the rest and touches every agent file.

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
  the phase ends without a shorter, clearer answer to "why would I install this next to the
  official plugins", it failed whatever the diff says.

## Expected work

Four tickets. The guard, the retirement set with its deprecation path, the official-plugin
coexistence rows in forge-adapt, and the agent naming convention. Any of them may end as a
documented decision rather than a change; that is a finished outcome.

## Out of scope

- Redesigning `full-review`, `code-reviewer` or any component whose content genuinely diverged.
- Chasing the official plugins' surface area. They will always ship more agents.
- #176, the `adapt` line-count question, which stays in the backlog and is unrelated.
