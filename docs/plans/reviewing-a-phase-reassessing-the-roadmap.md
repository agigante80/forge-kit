# Plan: Reviewing a phase, reassessing the roadmap

Phase opened 2026-09-23, directly after "The primitives roadmap management needs" closed, which is
what unblocked it. The maintainer asked for phase and roadmap management to be the highest priority
and described both workflows in his own words; this plan is written against that description plus
the five tickets that have accumulated in the milestone.

## Goal

The two workflows the maintainer runs by hand exist as components that can act, and the three
components that write a ticket body cannot contend over one.

## Done looks like

- **The write-authority contract is enforced at the write, not stated in a doc (#248).** Four
  `forge-lib.sh` primitives, `forge_body_region_get`, `_set`, `_clear` and
  `forge_body_compose_preserving`, splice or compose a body while preserving every byte the caller
  did not ask to change, and refuse a region whose name does not start with the caller's declared
  prefix. All three writers call them instead of `forge_issue_edit`.

  **This bullet named the wrong mechanism when the phase opened, and the correction is the phase's
  first real finding.** The original plan was a rule in `docs/guides/ticket-standards.md` guarded by
  `check-restatements.sh`. #248's gate found that fundamental: the phase review lands in
  `plugins/forge-kit-roadmap/`, which that guard does not scan and cannot be made to scan, because
  the roadmap group owns its own numbered rule vocabulary and because the guard's `[ -r "$f" ] ||
  exit 2` would fail a core CI check in any checkout that declined the optional group. A governance
  guard reaches governance components sideways and does not reach the roadmap group at all. The
  contract therefore moved into `forge-kit-devops`, which BOTH groups already declare as a
  dependency, so it travels down an edge that exists rather than one that would have to be invented.

  This still lands FIRST: both reviews rewrite bodies, and writing either first means inventing the
  rule twice.
- **`/phase review` (#244)** reads the open phase, its plan, and every ticket in its milestone open
  AND closed INCLUDING THE COMMENTS; marks what has been implemented; rewrites a ticket that no
  longer describes the work rather than appending to it; closes, splits or creates tickets as the
  alignment requires; updates the phase and the plan when the scope has moved; and offers to close
  the phase when the plan's Done looks like is satisfied. It checks whether the roadmap change
  requires a root README edit, because that is the step the maintainer says is forgotten.
- **`/roadmap reassess` (#249)** does the same one level up: reprioritise, split, merge, rename,
  refocus and delete phases, and insert a new higher-priority phase ahead of the rest. It writes
  through `roadmap-lib.sh`'s primitives and moves tickets with `forge_issue_milestone`, so it owns
  no second definition of either format.
- **The gate's round memory survives a rewrite (#196).** It becomes load-bearing here rather than
  merely nice: once a component rewrites bodies routinely, the `gate-verdict` block is erased
  routinely, and #192 already made the comments the durable copy so it can be restored from them.
- **The doc-drift check is usable by both reviews (#258).** Today it reports a row for every line
  that merely NAMES a churning path, so a count that is never zero is a count neither review can
  act on.
- Each gated before implementation, reviewed under the bounded loop, merged to `main` on its own
  commit.

## Fails if

Premortem, written before the work: it is the end of this phase and it failed badly.

- **The two workflows turned out to be one, and we shipped two.** A phase review that finds the
  phase itself wrong is already a reassessment; the roadmap prose flagged this when the phase was
  still a bucket and it is still the sharpest question here. If the boundary is not decided in
  #248's contract, #244 and #249 will each grow the other's features and the pair will be a
  maintenance problem rather than two tools.
- **A review rewrote a ticket and lost the author's words.** The maintainer asked explicitly for
  rewriting rather than appending, which makes this the phase's defining risk rather than an edge
  case. The write-authority contract has to say what a rewrite may destroy, and the answer cannot
  be "whatever the model judges stale".
- **A review rewrote a body and erased the `gate-*` regions**, so a gated ticket read as never
  gated and the round counter restarted at one. #196 is in this phase for exactly that reason, and
  sequencing it after #244 rather than before is how it would happen anyway.
- **The reviews were written against a doc-drift count that is always non-zero** (#258), so the
  README check the maintainer says is forgotten stays forgotten, now with a tool that reports it.
- **It ran unattended and rewrote thirty tickets.** Both workflows act on every ticket in a
  milestone. A dry-run mode that shows what would change, and a refusal to act on a ticket whose
  body a human edited since the last review, are cheaper to build now than to retrofit.
- **The phase grew into the model-tier work.** That is the next phase and it is named.

## Expected work

#248 first, because both reviews depend on its contract. Then #258, because both reviews consume
`check-doc-drift.sh` and its output is not yet actionable. Then #244, then #249, which is #244's
shape one level up and is easier to write once the review exists. #196 last, or alongside #244 if
the rewrite path makes it urgent sooner.

## Out of scope

- #250 to #253, the model and effort phase, which is `planned` and named.
- The nineteen `backlog` tickets, including the seven this repository's own review loops filed
  yesterday (#254 to #257, #259 to #261).
- Retro-gating closed tickets. Step 0c rewrites bodies, and #184 already decided that rewriting the
  bodies of shipped work is a decision rather than a tidy-up.
