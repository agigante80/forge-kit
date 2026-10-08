# Plan: The gate's own friction

Written 2026-10-08, when *Work with no decision left in it* closed. The phase is a bucket filed
2026-10-07 by the roadmap review: the ticket gate's two P2/P3 procedure problems and their
neighbour, with every pick recorded on the tickets that day. Each ticket was read with all its
comments and checked against the tree on 2026-10-08. None is already done, none needs a pick that
is not recorded, and **none is gated at a PASS**: #263 and #286 hold a round 1 NEEDS-WORK whose body
has not been rewritten to the recorded picks, and #213 was never gated. Gating them is the first
step of each, and the phase's only real constraint is words.

## Goal

The ticket gate stops leaking background poll loops, stops re-reading a cache it cannot trust, and
reads its Step 0c synthesis targets from the script that already resolves them, all without
`ticket-gate.md` growing a single word.

## Done looks like

- A sentinel-gated Bash `PreToolUse` hook denies a background `sleep` and `until`/`while` loops
  polling `tasks/*.output` or `subagents/*.jsonl`, with a deny reason that says what to do instead
  (keep working, let the completion notification arrive, never end a turn with a dispatch
  outstanding), fail open, a `--self-test`, cases in `scripts/test-hooks.py` and a hooks README
  entry; `ticket-gate.md` carries no prose about it (#263).
- Step 2.9's cache-skip rule, Step 6's reuse clause and the 2.9 round-table row are gone, so every
  round re-explores and rewrites `gate-context`; the four `gh` snippets name their `forge_*`
  equivalents with one legacy fallback line; Step 3A names where `--template` and `--tpl-version`
  come from; `review-template.md` carries an E2E row (#286, items 1, 2, 4 and 6).
- `check-ticket-mechanics.sh --roles` prints one `<role>\t<label>` line per resolved role,
  `--dump-fields` is unchanged, and Step 0c reads that output for its synthesis targets (#213).
- `check-component-size.sh` passes with the ticket-gate baseline at or below **5742**, lowered to
  the new measure if the net change is a reduction. Every ticket above is closed against a named
  commit and `Validate` is green on `main` after each.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **`ticket-gate.md` grew and the baseline was raised.** The real baseline is **5742**, not the
  5754 the three tickets quote (the file is 5228 words plus the preloaded
  `ticket-gate-reference/SKILL.md` at 514, so headroom is exactly zero). One of #286's items 2 and 4
  or #213's Step 0c edit was written first, before the deletion that pays for it, the ratchet failed
  the build and the fix was a raised baseline, which an agent must never do on its own.
- **The cache came back.** #286 item 1 was implemented as "reuse unless a cited file changed" or as
  a fingerprint, because the gate's round 1 recommended exactly that. The maintainer rejected both
  on 2026-10-07; the decision is delete, and a cache needs a new decision.
- **#263 became a prose fix.** The instruction landed in `ticket-gate.md` (or the companion skill,
  which is charged to the same total) because it is cheaper to write than a hook. The pick is a
  hook and no prose.
- **The hook never ran where the leak is.** It shipped behind a sentinel that nothing creates, so
  the polling loops continued everywhere and the self-test was green. The sentinel's name and who
  creates it were left to the implementer (see the question below), and the answer was never
  written into the ticket or the hooks README.
- **#277's work came back through #286.** A test pinning `gate-context` placement or a cache-skip
  condition was added "for completeness" against a region this phase deletes the reuse of.
- **Three tickets, one version bump collision.** All three touch `forge-kit-governance`, and #213
  and #286 both edit Step 0c's neighbourhood of `ticket-gate.md`; two landed in parallel and the
  second pinned the first's intermediate line numbers or its `plugin.json` semver.
- **Item 5 was folded back.** `forge_issue_comment` was made to print a URL "while we are in
  there"; `w229`, `e237` and the dry-run case pin its silence and the pick is dropped.

## Expected work

In order. **#286 leads because it is the only ticket that frees words, and the other two spend
none from the agent's budget.**

1. **#286** (P2), round 1 NEEDS-WORK, verdict STALE (body changed since). Rewrite the body to the
   recorded scope first, then re-gate: items 1, 2, 4 and 6 only (item 3 landed under #347,
   6f5581f; item 5 is dropped; the 2026-10-07 comment holds both). **Where the words come from:**
   item 1 is a deletion and pays for the rest. Measured 2026-10-08: Step 2.9 sub-step 1 (the
   cache-skip rule, lines 299 to 306) plus its "ALWAYS runs its check" sentence, Step 6 rule 2's
   REUSES clause (about 18 words) and the 2.9 round-table row (21 words), roughly 100 to 110 words
   in all. Items 2 and 4 are word-neutral by construction (a `forge_*` name replaces a `gh` form;
   a variable name replaces a placeholder); item 6 edits `review-template.md`, a reference that is
   not part of the 5742 measure. The four `gh` line numbers in the ticket (85, 169, 186, 484) are
   stale: the snippets are at 84, 170 and 187, and line 544 is prose. Re-grep before writing AC1.
   #283 (the ordering the gate asked for) is closed, so that dependency is gone. Lower the
   baseline by whatever net reduction results.
2. **#213** (P3, P2 for hubbub), **never gated**: gate it first. Implement
   `check-ticket-mechanics.sh --roles` (same resolution as check 3: id, then label pattern), one
   contract case per role in `scripts/test-check-ticket-mechanics.sh`, and change Step 0c's
   target-sections bullet (line 114) to read that output. **Where the words come from:** the
   `--roles` call replaces a field-id list rather than adding one, so the edit should be roughly
   neutral, but it must be net zero or negative **on its own**: step 1 lowers the baseline by
   everything it frees, so nothing is banked for this step, and the ticket names the sentence it
   trims to pay for any residual (settled 2026-10-08 after the #213 gate's round 1 found the two
   clauses contradicted each other; lowering is the only direction an agent may move a baseline).
   It runs after #286 so its measure starts from the lowered baseline. Docs:
   `docs/guides/template-versioning.md` (lines 84 to 87 restate the ids) and the script's
   `--help`; `CLAUDE.md` names none of them.
3. **#263** (P3), round 1 NEEDS-WORK; the maintainer pick (a hook, no prose, the open fact
   verified) is recorded in a comment, but the body still carries the old figures, headings and
   GWT. Rewrite the body to the pick (rename the four headings to the bug.yml v6 labels, replace
   every 5766 and 5754 with the measured 5742, add Condition C and the root-cause evidence, drop
   the prose and companion-skill options), re-gate, then implement the hook under
   `forge-kit-governance/hooks/`. **Where the words come from:** nowhere, by decision: the deny
   reason carries the rule, so `ticket-gate.md` is untouched and the ticket's AC is "exits 0, no
   FAIL line". It does not touch `ticket-gate.md`, so it can run beside #213 in a separate
   worktree if the `plugin.json` semver and hook marker bumps are rebased. It is last because it
   is P3, and because the *Hard rules held by hooks, day and night* phase builds on the sentinel
   and subagent answers it settles.
4. **#277** is closed (NOT_PLANNED, 2026-10-07) and needs no work; it is listed so nobody reopens
   it.

**Maintainer question (not blocking the first two tickets).** #263's pick says "sentinel-gated"
but not which file nor who creates it. Existing guards use `.claude/no-dashes` (block-dashes) and
`.claude/overnight/active.md` (overnight-guard), both written by the user or a skill. A hook behind
a sentinel nothing creates fixes nothing, so the re-gate of #263 needs one line: either the gate's
own run creates and removes the sentinel, or the hook ships armed by `forge-adapt`, or the user
opts in. This is the same question *Hard rules held by hooks, day and night* (#419) asks, so the
answer should be the same one.

## Out of scope

- **Arming a destructive-command matcher by day (#419) and the pipe-hides-exit-code advisory
  (#420)**: *Hard rules held by hooks, day and night*, which waits on #263's sentinel and
  subagent answers.
- **A cache of any kind for `gate-context`**, whether fingerprint-keyed or commit-keyed: rejected
  2026-10-07, needs a new decision before it is reintroduced.
- **`forge_issue_comment` returning a URL (#286 item 5)**: dropped; the silence stays pinned.
- **A prose rule about waiting in `full-review` or `working-overnight`**: the hook covers them;
  a prose follow-up is a new ticket in `backlog`.
- **Raising any baseline**: an agent never does; a shortfall of words is a maintainer question.
