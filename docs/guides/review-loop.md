# The review loop: why round 2 always runs

`/full-review` bounds a review-fix-review loop with the rules in its Iteration contract
(`plugins/forge-kit-review/commands/full-review.md`, section "Iteration contract"). This page
records why one of those rules is unconditional, what evidence it rests on, and how to gather the
data that would let it change. It is the rationale only: the contract itself is in the command,
and this page restates none of it beyond one sentence. Decided on issue #445 (maintainer decision
2026-10-11, option B).

## 1. Round 2 always runs

The contract reviews the fix delta (`previous_ref...HEAD`) in round 2 whatever round 1 found,
while rounds 3 and 4 run only after a Critical or High. That asymmetry is deliberate and stays.

One downstream project changed its rule to "round 2 only if round 1 found a High". In the change
that introduced that rule, round 1 found Highs, so round 2 ran, and round 2 found a High *in round
1's fix*. Round 3 then found Mediums in the fixes from rounds 1 and 2, and the trip wire fired.
Fixes inject defects, and a round that checks only the fixes is the one that catches them.

The same data point is also the case against: that round-2 High sat in the fix for a High. A
conditional round 2 would have run there too. Where it would have been skipped, after a
Medium-only round 1, the fixes are smaller and the yield of the delta review is the least measured
part of the loop. Skipping round 2 there would let a defect injected by a Medium fix ship, and
nobody yet knows how often that happens.

## 2. Evidence

- **Fixes are often wrong.** Yin et al., "How Do Fixes Become Bugs?" (ESEC/FSE 2011): 14.8 to
  24.4 percent of sampled fixes for post-release bugs in Linux, OpenSolaris, FreeBSD and a
  commercial OS were incorrect and reached users.
- **Review alone does not catch them.** A study of 97,347 merged Firefox changes (May 2019 to
  January 2025, arXiv 2603.03121) found that about 12 percent still introduced bugs despite
  linting, tests and code review.
- **No round-2 yield data exists yet.** Neither figure measures a delta review of review fixes.
  They say fixes carry defects; they do not say how many a round 2 finds after a Medium-only
  round 1. Section 4 is how to start measuring that.

## 3. If round 2 ever becomes conditional, it is not downgraded

Today a round-2 run is pinned below round 1 in one place. `full-review.md` rule 8 has
`code-reviewer` take its frontmatter model in round 1 (`inherit` at `high` effort: the session's
model) and the standard tier in a rule-7 round, and `docs/guides/model-tiers.md` maps the
standard tier to `sonnet` and lists "`full-review` `code-reviewer` in a round-2+ run" as `sonnet`.
The two agree (verified 2026-10-12). The general-purpose lens phases run at `sonnet` in every
round, so a later round is no cheaper for them.

That pin is right only while round 2 is a routine re-check. Under a gate that runs round 2 only
after a High, every round 2 is the high-stakes one, and the pin would downgrade exactly the review
that matters most. So: **a conditional round 2 runs `code-reviewer` on its frontmatter, as round 1
does, never at the `sonnet` pin**, and the lens phases stay no lower than round 1. Whoever adopts a
conditional round 2 changes rule 8 and the `model-tiers.md` row in the same commit.

## 4. How to count round-2 yield

Each completed run leaves its report at `.full-review/round-<N>/05-final-report.md`, and a
verify-fixes round tags every finding `in-prior-fix: yes/no` (rule 7). For each loop that reached
round 2:

1. Read round 1's report and note the highest severity it found (Critical, High, Medium or Low).
2. Read round 2's report and count findings at High or above, and at Medium, that are in the fix
   delta. Count `in-prior-fix: yes` findings separately: those are the defects the fixes injected.
3. Record one row per loop: round-1 highest severity, round-2 High+ count, round-2 Medium count,
   in-prior-fix count.

Grouped by round-1 severity, the rows answer the open question: how often does a round 2 after a
Medium-only round 1 find something a skipped round 2 would have shipped.

`.full-review/` is a local runtime directory that projects running `/full-review` are told to
gitignore (this repository's `.gitignore` does not list it). The archives exist only where people
keep them, so the count accrues per machine and must be collected by hand.

## 5. Declined for now

- **A: a declared `round-2: always | on-high` setting.** Premature without yield data, and it
  needs words in `full-review.md`, which sits at its size ratchet baseline and may not grow.
- **C: round 2 risk-tiered by declared sensitive paths.** Mostly prose with no mechanical check,
  so it cannot be tested.

Either is revisited once the count in section 4 has data.
