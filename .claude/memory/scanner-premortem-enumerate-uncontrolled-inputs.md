---
name: scanner-premortem-enumerate-uncontrolled-inputs
description: "#191 reviews found five silent-exit-0 paths the premortem missed (corrupt object, git config, newline path, refs/replace, unchecked pipeline); list input classes, not examples"
metadata:
  type: feedback
---

The #191 phase premortem (2026-09-14) had the clause "a foreign store was read as this one" and named alternates and two environment variables. Two round-1 reviewers then found five more inputs the scanner does not control, each turning a reachable leak into a silent exit 0: a corrupt object (`cat-file --batch-check` prints `missing` and exits 0), user git config reshaping `git log --raw -z` (`log.showSignature`, `log.diffMerges`, `diff.relative`, `log.showRoot`), a newline in a filename, `refs/replace` (honoured by rev-list and cat-file, ignored by push), and an interrupted pipeline with unchecked PIPESTATUS.

**Why:** the premortem named the inputs I could think of, and a scanner`s failure surface is every input it does NOT control. The two reviewers` Critical sets barely overlapped, which is the argument for two in round 1 on a security tool.

**How to apply:** for a scanner or guard premortem, enumerate inputs by class rather than by example: user configuration that reshapes a tool`s output, every ref namespace, every object-store state (corrupt, partial, shared, replaced), every filename byte, and every pipeline stage`s exit status. Pin the output SHAPE of any tool whose output is parsed (`git -c` overrides plus a shape check that refuses). Related: [[bounded-review-loop-in-practice]], [[a-ticket-assertion-is-a-claim-check-it]].
