---
name: mutation-sweep
description: Adopt and adapt mutation testing for this project. Line coverage is blind to the defect class that reaches review (covered lines whose tests cannot fail); a mutation sweep finds tests that stay green under deliberate defects. Use when the user asks to run or set up mutation testing, when a review keeps finding defects on covered lines, when survivors need triage, or alongside coverage work ("mutation test", "mutants", "survivors", "kill rate"). Ships no engine: it teaches adopting mutmut or cosmic-ray with the project facts that make a sweep honest.
---

<!-- mutation-sweep-version: 1 -->

# Mutation sweep

**A survivor list is a triage queue, not a defect list.** That is the posture everything
below serves. Line coverage certifies that lines ran; a mutation sweep certifies that the
tests would notice if those lines were wrong. The motivating evidence (issue #67): in one
audited session every code-level HIGH sat on an already-covered line, and a nine-second
sweep of one module found the two real defects four review rounds had missed.

This skill deliberately overlaps the code-reviewer agent's "Assertions that cannot fail"
dimension, which is the CANONICAL statement of the five rotten-green shapes: a sweeper
finds shape 3 (only one side of a rule exercised) mechanically and is blind to shapes 1
and 5, which live in the assertion text. Run both; neither replaces the other.

## Tool selection (criteria, not winners)

Adopt a maintained engine; never build one (an engine is exactly the executable this kit's
own discipline would then demand contract tests for). Choose by criteria:

- **Incremental runs and test-targeting** (only re-test mutants whose covering tests
  changed): the difference between a sweep people run and one they abandon. `mutmut`
  carries both.
- **Operator breadth and build-tool integration**: `cosmic-ray`'s strengths.
- Whatever is chosen, pin it as a dev dependency and record the invocation in the project's
  standard commands.

## Project adaptation checklist (each item is a project fact; fill ALL of them)

1. **Runner command**: the exact test invocation the engine should use, including the flags
   the documented workflow always passes. A sweep that runs the suite differently than CI
   does certifies a suite nobody ships.
2. **Per-suite timeout**: measured from a clean run, with headroom. A timeout counts as a
   KILLED mutant.
3. **Kill the process GROUP, and reap.** A suite that spawns the code under test as a
   subprocess leaves grandchildren the suite's death does not touch; a mutant with an
   infinite loop then leaks burning cores. `start_new_session=True` (or `setsid`) plus a
   group kill plus `wait()`. Verify once with a deliberate infinite-loop mutant.
4. **Redirect convention**: how this project routes a module under test (env var, path
   injection, symlink). The mutation must reach the EXECUTED copy; when the suite resolves
   a module indirectly, mutating the checkout while the suite runs a cached or redirected
   copy yields a false "all killed".
5. **Sentinel mutant (delivery check, run FIRST every sweep)**: apply one deliberately
   trivial mutant the suite MUST catch (invert a core comparison). If the sentinel
   SURVIVES, the delivery path is broken: abort the sweep as invalid rather than reporting
   a result. This converts the worst failure mode (false all-killed) into a checked
   precondition.

## CI lanes (a sweep nobody runs twice is a sweep that never ran)

- **Per PR**: mutate only the modules the diff touches, incremental engine state on.
- **Nightly or weekly**: full sweep of the high-risk paths (business rules, money, auth),
  never the framework glue.
- **Never** the whole tree on every push; the first hour-long run is the last run.

## Survivor triage protocol

For each survivor, classify before anything else:

1. **Real gap**: no test distinguishes correct from mutated behaviour. Write the killing
   test (see it fail against the mutant, pass against the original) or file a ticket with
   the mutant diff verbatim; a ticket is a finished outcome.
2. **Killed elsewhere**: a sibling suite the sweep did not run covers it; record which.
3. **Equivalent mutant**: the mutation does not change observable behaviour; record why in
   the engine's ignore list so it never resurfaces.

Report kill rate as context, never as a gate: a score target invites equivalent-mutant
gaming, and the triage queue is where the value is.
