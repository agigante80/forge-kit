---
name: surviving-mutant-check-the-mutant-first
description: "2026-09-14: four survivors on one suite, zero were code defects; check that the mutant applied and the fixture can tell, before touching the code"
metadata:
  type: feedback
---

On 2026-09-14, writing `update-suite-counts.py` under #201, fourteen named mutants were run against a 47-case suite and four survived on the first pass. None of the four was a defect in the generator: one was an equivalent mutant (a `break` that only left the inner loop), one was a noise line in the stub that matched no summary shape so the last-line rule was never exercised, one was a near-miss word (`testers`) that does not actually contain the needle (`tests`), and on #200 the day before a case-sensitive `grep -v` deleted nothing from a header that spelled the phrase in lowercase. Every fix went into the TEST or the MUTANT; the code under test was right each time.

**Why:** a surviving mutant is evidence that something cannot fail, and the first candidate is the mutation itself (did it apply, did it change behaviour), then the test fixture (does the noise actually exercise the rule), and only then the code. Reading a survivor as a code hole first leads to "fixing" working code.

**How to apply:** for each survivor, in order: confirm the mutant applied and is not equivalent ([[mutation-harness-quoting]]); confirm the fixture can distinguish the mutant (a near-miss must contain the needle, a noise line must match the shape); then look at the code. Restore from a `cp` backup, never `git checkout` ([[never-git-checkout-uncommitted-work]]).
