# Plan: The reviews' own crop

Phase opened 2026-09-18 during an unattended run, from the Lows the night's fourteen review rounds
ticketed under the bounded loop. The maintainer was asleep; the premortem is mine and is an
assumption for the morning report.

## Goal

The Lows the review loop refused to fix inside its rounds are fixed the same night, each as its own
gated, reviewed, merged change, so a ticketed finding is a finished outcome rather than a deferred
one.

## Done looks like

- The three writers print their 404 line under a `set -e` caller too, captured in the errexit-safe
  shape `forge_api`'s own comment designs for (#237).
- `forge_repo` never prints a string containing `@` as a slug (#235), decided as refuse or as
  strip, stated in the header.
- The `root` parser refuses a two-segment root, a bare tilde, a value with a leading space, and a
  value ending in a slash after the first strip (#240), and a punctuation-ending entry is refused unless
  it is a known marker (#239 part 1), each with its near miss.
- Rules A and B walk a punctuation tail once, and `/home/<name>` plus 64 KB of dots scans within
  the suite's `bounded` (#239 part 2).
- `forge-call-mapping.md` maps a body edit to `forge_issue_edit` with its signature, and the two
  other drifts #234 names are gone.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The errexit fix changed a writer's success path.** `rc=0; forge_api ... || rc=$?` is the
  shape; a `|| true` or a subshell would swallow the code the callers depend on. The nine #229
  cases are the net and must stay untouched.
- **#235 decided "strip the userinfo" and printed a slug for a URL git itself would not read that
  way.** Refuse is the honest branch; a slug from a shape git cannot clone is a 404 with extra
  steps.
- **The parser guards refused a legitimate entry.** Every guard ships with the entry it must still
  accept: the three markers, `<root>`, dotfile roots, and a root with one trailing slash.
- **The linear walk changed a verdict.** The tail walk is a performance change; the suite's 380
  cases are the proof it changed nothing else, and a timing case under `bounded`, never `timeout`.
- **A docs fix restated a gate rule.** `forge-call-mapping.md` is scanned by
  `check-restatements.sh`; a row that names a rule number needs its anchor.

## Expected work

#237, #235, #240, #239, #234, in that order, each gated (two rounds, fold or file) and reviewed
(bounded loop). #236 is deliberately out: it is a wording decision, not a defect.

## Out of scope

- #236 (a taste call), #222 and #226 (parked on decisions), #206 and #217 (structural), #207,
  #219, #220, #221, #213, #196, #215 and #216's descendants: `backlog`.

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-23, unattended, outcome **done**. All five landed in the plan's order, #237, #235,
#240, #239 and #234, each gated and reviewed. Three follow-ups went to `backlog`: #242 (the
`prefix` key's identical punctuation gap, kept out so #239 stayed on one parser arm), #243 (the
segment strip is a cost change no mutant kills, and rule A's fallback arm is unreachable) and the
#240 review's whitespace shape, which #239 absorbed instead of deferring.

**The run was interrupted for five days by a weekly rate limit, mid-gate on the last ticket, and
that is the interesting part of the close.** Nothing was lost because every finished unit had
already been merged to `main`: the tree, the phase guard and CI were exactly where they had been
left, the folded body of #239 was on the forge, and resuming cost one re-run of a gate round. A
loop that merges per ticket rather than per phase is what made a five-day gap a non-event.

**The premortem's clause about the errexit fix held, and the one it did not write down is the one
that fired twice.** #237's `rc=0; ... || rc=$?` left the nine #229 cases untouched, as the plan
required. What the plan did not anticipate is that BOTH remaining tickets would turn on a measured
fact contradicting the ticket's own text: #239's gate benchmarked the two techniques its author
prescribed and found both quadratic (105 s and 9.6 s at 64 KB) before recommending the anchored
match at 9 ms, and its security lens found that the by-entry-length compare the ticket asked for is
a prefix match without its lower bound, which would have made this repository's own allow-file
suppress every root whose name merely starts with an allowed one. Neither was reachable by reading.

**The review loop earned its bound on #239.** Round 1 found no High or Medium and three Lows; one
was taken because its direction was a false negative on the stated bash floor; round 2 then found a
defect in that three-line fix, an entirely-punctuation segment being walked byte by byte at 33 s
where the commit before it took 0.12 s. Rounds that found a defect in a prior round's fix across
the phase: 1. The loop stopped there rather than opening a third round, and the shape is pinned by
its own bounded case.

Opened 2026-09-18, unattended, for the follow-ups the night's review loops filed as Lows and
refused to fix inside their rounds: #237 (the writers' 404 line is skipped under a `set -e`
caller), #235 (an scp-form `user:token@` prefix reaches stdout as a slug), #240 (three more dead
`root` shapes the punctuation guard does not catch), #239 (a punctuation-ending `root` entry
matches its literal, and rules A and B are quadratic on a punctuation tail), and #234 (three
prose drifts, among them `forge-call-mapping.md` mapping a body edit to a raw PATCH). They belong
together because each is a finding the bounded review loop turned into a ticket rather than a
fourth round, which is the loop working; a phase that pays them the same night is what keeps
"ticket it" from meaning "forget it".
