# Session handoff: three phases, a release, and a decision brief

Date: 2026-09-12 (session began 2026-09-11; resumed after an unexpected close)

## Summary

Paid the gate's own debts and a downstream contribution, cut v0.5.0, paid four more small debts,
and turned #191 from "blocked on three contradictions" into a costed decision waiting on one probe.
Fourteen gate runs in total; the gate changed one design and retracted five false facts, three of
them mine.

## Done this session

- **Phase "The gate's own debt, and one contribution"**: #189 (marker-ranked asset resolver, four
  sites), #192 (`count-gate-rounds.sh`, rounds counted from posted comments; `forge-lib.sh` v14
  `forge_issue_comments`), #193 (`forge_ci_status` Option B: `cancelled` from the combined status's
  description, `total_count == 0` is `pending`/`none`, `not_configured` reserved for could-not-ask;
  `forge-lib.sh` v15). Closed, outcome done.
- **v0.5.0** tagged and released, ten tickets stamped.
- **Phase "Four small debts from the gate runs"**: #197 (per-issue gate scratch dir, foreign body is
  a stop), #190 (sections found at either heading level, bounded by template labels; the gate
  killed the per-body-level design because `dep-auditor` emits `### Priority` beside `##`
  sections), #194 (`mechanics: none`, `~`-relative path, tie-break direction, ratchet LOWERED
  5773 to 5767), #195 (`<sha>` to `<semver>`). Closed, outcome done, no follow-ups.
- **#191 decision brief**: gated once, body rewritten twice (preamble + `### Decision`; the gate's
  seven items folded into the author's sections), correction comment posted first. Recommendation
  D: POSIX awk byte-counting reader over `rev-list --objects` (publishable set, with paths),
  tested against the forged header, NUL blobs and commit messages, 0.47 s on this store.
- **Phase "What a push does not send"**: #198 (the free half of #191: a push never sends orphans,
  tested; the prune step with its scope INCLUDING that it empties the stash stack; the `grep -a`
  trap in both headers). Closed, outcome done.
- Memory: plugin update is invisible to a running session; the Bash tool's grep is a `-I` wrapper;
  rewrite ticket bodies rather than comment; day two and three of gating measured.

## In progress (where we left off)

Nothing. Tree clean, `main` = `develop` = `a049eb7`, CI green on both, no phase open, no
background agents.

## Next steps

1. **Restart the session, then run one `/gate-ticket <N>` with a bare number** and read the review
   comment for `**Round:**` and `mechanics:` lines the AGENT printed. Every gate run across three
   phases executed the installed v51 prose despite the cache being updated to 0.16.2 (then 0.16.5):
   "restart to apply" is literal. Three phase closes carry this gap; it is the only unverified
   claim on the board.
2. **#191 waits on the macOS awk probe** written into its `### Decision` section (pass criterion:
   content + headers == total lines; 389193 + 5002 == 394195 here with gawk). PASS means D goes
   into a phase with ACs 1 to 10 as written; FAIL means E (`cat-file -Z` coprocess, git 2.42 floor).
   Needs a real Mac; cannot be done from this machine.
3. #199 (pin the `grep -a` header sentence in both suites, two cases) is a twenty-minute ticket.
4. #196 stays in Backlog until someone wants round MEMORY restored, not just the number.
5. Sister project `agigante80/vibe-coding-prompts` #51 (OWASP Top 10:2025 cited without its
   categories) is still the sharpest open item on either board.

## Decisions and why

- **Ratchet raised 5709 to 5773 for #189** (maintainer, the #147 shape: a correctness fix with 7
  words of duplication left), then **lowered to 5767 after #194**, per the rule that a shrink locks
  in. #192 and #197 were paid entirely from restated sentences; the second raise was never asked.
- **Option B for #193**, because the gate's critic REPRODUCED a false green in the downstream
  `/actions/tasks` walk under a server-clamped page. `none` and `cancelled` stop `release` with a
  named next action; the local-gate fallback is reserved for `not_configured`.
- **Gates run one at a time** since #197 showed three concurrent runs sharing one body file.
- **Two rounds per ticket, hard stop**, every time. #190, #194 and #198 each had round 2 find a
  defect in round 1's fix (one round each, never two consecutive); leftovers became ticket text
  folded in, or #199.
- **The brief's own research is a claim**: the gate corrected two version facts I cited from a
  stale page and one grep observation made through a wrapper. Reproduce, cite primary, date it.

## Open questions / blocked on

- Whether BWK awk on macOS counts bytes correctly after `tr '\0' '\001'` under `LC_ALL=C`. The
  whole of #191's recommendation turns on it.
- Whether "gate every new ticket" should narrow to "gate what is about to be implemented". Three
  days in, the ratio is about one real catch per ticket and the cost 100k to 220k tokens per run;
  no reason to change it yet.

## Key context to reload

- `gh issue list --state open` (three, all Backlog: #191, #196, #199)
- `.claude/memory/claude-plugin-cli-facts.md` (the restart fact), `bash-tool-grep-is-a-wrapper.md`,
  `rewrite-ticket-bodies-not-comments.md`, `gate-new-tickets-from-now-on.md` (three days measured)
- `docs/roadmap.md`, the last three phase closes; `docs/plans/four-small-debts.md` (premortem
  clause two fired exactly as written)
- #191's `### Decision` section for the probe and the option table
