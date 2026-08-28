# Session handoff: governance batches, the superpowers boundary, and the sister-project cross-review

Date: 2026-08-28 (session began 2026-08-27)

## Summary

Two long autonomous batches plus a cross-project review. Closed 13 tickets across
eight merged PRs, retired the ticket-gate scoring committee, upstreamed the bounded
review loop, and finished the whole #69 superpowers-boundary arc. Ended with a full
read of the sister project `agigante80/vibe-coding-prompts` and tickets filed in both
directions.

## Done this session

**Batch 1 (bug fixes, autonomous backlog workflow):**
- #61 Forgejo template dir casing; guard now resolves legacy lowercase, host-grouped order (PR #74)
- #62 / #63 / #64 forge-lib: Forgejo pagination, atomic label refusal, version markers on shipped shell assets, plus `scripts/test-forge-lib.sh` (13 cases) wired into CI (PR #75)
- #65 closed as already shipped (verified on main)
- #79 `check-plugin-version-bump.sh`: a changed plugin group must bump its `plugin.json` semver, CI + pre-commit, 15-case test (PR #82)
- #80 root `AGENTS.md` pointer; #81 static portability audit spec (both direct to main)

**Batch 2 (the #69 boundary arc, my chosen order):**
- #73 ticket standard v5: GWT quality bar, rule 7 documentation currency, `docs_impact` field on all five templates (PR #83)
- #70 ticket-gate: 5-agent 10/10 committee replaced by mechanical checks + ONE critic + label-triggered lenses (PR #85)
- #66 iteration contract split reporter/loop-owner across code-reviewer and full-review (PR #87)
- #71 full-review repositioned as a pre-merge audit with a defined findings handoff (PR #89)
- #72 forge-adapt superpowers coexistence mode (PR #90)
- #69 closed: boundary paragraph recorded in CLAUDE.md (commit 7e14cb0)
- #86 gate hardening (PR #91), #68 rotten-green dimension (PR #92), #67 mutation-sweep skill (PR #93)

**Cross-project review (sister repo `vibe-coding-prompts`):**
- Read all 14 prompts, 4 docs, the authoring guide and the tooling
- Filed there: #51, #52, #53, #54 plus a research comment on their #41
- Filed here from what they do better: #96, #97, #98
- Found #95 here by applying their `prove-your-tests-can-fail` method to our own tooling

## In progress (where we left off)

Nothing is half-done. `main` is clean, in sync with origin, no open PRs, no stray
branches, all gates green. The session ended at a natural boundary.

## Next steps

1. **#95 first** (bug, small): `forge-adapt-catalogue.sh` reports the adapt skill as
   `vnone`, and its contract test asserts `| v`, which `vnone` satisfies. This blocks
   #96, because a generated index would publish the wrong version for the flagship skill.
2. **#96** generated component inventory with a `--check` CI gate, then **#97** the size
   budget (the index provides the visibility the budget needs).
3. **#98** CI self-hardening (SHA-pin our own actions, concurrency group, push-stage hook).
4. Then the remaining implementables: #94, #88, #84, #78, #77, #76.

## Decisions and why

- **Retired the ticket-gate committee** (#70) because consensus across many agents
  underperforms one grounded critique, and the maintainer's own experience matched:
  multi-agent pre-review did not prevent downstream mistakes, well-researched GWT tickets did.
- **Split the iteration contract** (#66): the agent REPORTS (delta target, in-prior-fix
  tagging, trajectory), the caller DECIDES (rounds, gates, hard stop, trip wire).
- **`in-prior-fix` means fix-induced damage, not delta membership.** Delta-membership
  semantics made the trip wire subsume the round gates and left the hard stop unreachable.
- **Stopped three review loops at the trip wire** and ticketed the remainder (#86, #88, #94)
  rather than iterating. See the memory `bounded-review-loop-in-practice`.
- **Did not adopt the sister project's pre-commit framework** in #98: it would make Python
  the first tool dependency in a repo that deliberately has none. Borrow the stage split,
  not the framework. This is a maintainer call to confirm.

## Open questions / blocked on

Four things need the maintainer, not more implementation:

1. **Part 2 of the ticket-standard spec** (the CI docs-currency gate: `.forge/docs-map.json`
   plus `check-docs-currency.sh`). Approved-or-not was never answered; the spec's own status
   header still says AWAITING APPROVAL. Part 1 is implemented and the header records that.
2. **#20 broaden-or-not verdict.** The portability audit
   (`docs/superpowers/specs/2026-08-27-portability-audit.md`) frames it: 7 portable,
   5 path-bound, 24 Claude-native. Only the tool-map experiment and the decision remain.
3. **#94 item 5, the `template-version` overloading question.** One integer currently means
   both "form fields changed, re-synthesise every open ticket" and "rules text changed,
   refresh installs". Until that is split (or prose-only doc changes are declared bumpless),
   six gate-only bars cannot move into the canonical doc.
4. **#21** stays parked behind #20.

Hygiene note: `.private-journal/` was untracked but not ignored; added to `.gitignore`
in the checkpoint commit that carries this note, so it can no longer be committed by accident.

## Checkpoint

This note, the four memory files and the `.gitignore` fix were committed and pushed at
session close, so nothing from this session lives only in a working tree.

## Key context to reload

- `.claude/memory/MEMORY.md` and its four entries, especially `code-review-fork-recovery`
  (review forks died six or more times today and every round was recoverable from the
  subagent transcripts) and `bounded-review-loop-in-practice`
- `CLAUDE.md`: the superpowers boundary paragraph, the marker-parsing rules, the four
  enforcement points (`validate-plugins.sh`, `check-version-bump.sh`,
  `check-plugin-version-bump.sh`, `.githooks/pre-commit`)
- `docs/superpowers/specs/2026-07-16-ticket-standard-improvements-design.md` (Part 2 gate)
  and `docs/superpowers/specs/2026-08-27-portability-audit.md` (the #20 input)
- Open backlog: `gh issue list --repo agigante80/forge-kit` (11 open: #94 #95 #96 #97 #98
  #88 #84 #78 #77 #76, plus #20 and #21 awaiting decisions)
- Sister repo for the reverse view: https://github.com/agigante80/vibe-coding-prompts
- Full local gate suite before any commit:
  `bash scripts/validate-plugins.sh && bash scripts/check-template-lockstep.sh &&
   python3 scripts/test-hooks.py && bash scripts/test-template-lockstep.sh &&
   bash scripts/test-forge-adapt-catalogue.sh && bash scripts/test-forge-lib.sh &&
   bash scripts/test-check-plugin-version-bump.sh &&
   python3 scripts/test-closing-sessions-memory.py`
