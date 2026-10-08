# Plan: Hard rules held by hooks, day and night

Written 2026-10-08, when *The gate's own friction* closed. The bucket held #419 (P2) and #420 (P3),
filed that day from a r/ClaudeAI thread whose strongest finding is forge-kit's own thesis: a rule
that must hold every time belongs in a hook, not in prose. #433 (P2) joined at the previous phase's
close, because the hook #263 shipped gives advice the harness may not let an agent follow. Every
ticket was read with its comments on 2026-10-08. #419 and #420 hold a round 1 NEEDS-WORK; #433 was
never gated.

## Goal

The rules this repo states most often in prose (never discard work, never bulk delete, never trust
an exit code a pipe hid, never poll for a subagent) are held by hooks whose advice an agent can
actually follow.

## Done looks like

- `no-poll-loops`' deny reason and ticket-gate Step 3B tell an agent to do something the installed
  harness allows, verified against the installed Claude Code for a top-level session and for a
  subagent, with the fact recorded on the ticket (#433).
- With `.claude/no-destructive` present and no overnight run armed, `overnight-guard.py` denies
  every `GIT_PATTERNS` class, the bulk-delete class and a relative `rm -rf` whose target ends in a
  wildcard (`tmp/*`, `./*`, `dir/*`), with a daytime message; a specific path (`rm -rf
  tmp/impl-213`) stays allowed; the daytime arm fails open while overnight stays fail closed and
  byte-identical, pinned by exact-equality rows; forge-adapt creates the sentinel when it installs
  the hook (#419).
- An advisory `PostToolUse` hook behind `.claude/masked-exit` adds context when a recognised check
  (including `git apply --check` and `git diff --check`) is piped into `tail`, `head` or `grep`
  with no `pipefail` or `PIPESTATUS`; it never denies (#420).
- Each ticket is closed against a named commit, `Validate` is green on `main` after each, and the
  ticket-gate (5648) and `adapt` (7144) baselines are not raised.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **#433 was settled from the docs.** Someone read the `Agent` tool description, decided
  foreground exists or does not, and rewrote the advice; on the next release the other answer
  was true. The fact must be observed on the installed harness, for both a session and a
  subagent, and the advice must stay correct under either answer.
- **The overnight guard changed.** #419's daytime arm was written into the shared matcher, and
  the relative-wildcard rule or the fail-open daytime path leaked into overnight runs. The
  existing rows only check a substring (`decisions.md`), so nothing failed.
- **The relative-glob rule over-reached.** `rm -rf tmp/impl-213` or `rm -rf build` started being
  denied by day, agents learned to route around the hook with `find -delete`, and the hook became
  noise. The maintainer's pick is the trailing wildcard only.
- **A sentinel nothing creates.** #419 or #420 shipped with a sentinel forge-adapt never writes,
  the same failure #263's plan named. The rule is one file per hook, created on install.
- **Words.** #433's Step 3B edit grew `ticket-gate.md`, or a forge-adapt pointer grew `adapt`, and
  the fix raised a baseline. Both have zero headroom; every edit pays for itself.
- **#420 never reached the model.** `additionalContext` on `PostToolUse` was assumed to reach a
  subagent's Bash call; the gate recorded it as verified for both, and the implementer must keep
  the registration row that proves the hook runs, not just that it parses.
- **Collisions.** All three touch `forge-kit-governance`, `hooks.json` and `scripts/test-hooks.py`;
  two ran in parallel and the second clobbered the first's registration or semver.

## Expected work

In order, one at a time (they share `hooks.json`, `test-hooks.py` and the group semver).

1. **#433** (P2), never gated: gate it first. The open fact decides the wording; if foreground
   is unavailable anywhere, the advice becomes "end the turn and let the completion notification
   resume you" wherever it is unavailable. **Words:** any `ticket-gate.md` change is net zero or
   negative on its own against 5648; the hook's reason costs no component words.
2. **#419** (P2), round 1 NEEDS-WORK. The sentinel and relative-glob picks are recorded in the
   2026-10-08 comment; apply them and the three required changes to the body (exact-equality
   overnight rows with mutants, the daytime fail-open contract, a new `overnight-guard` row in
   `adapt/references/hooks.md`), then re-gate. One file, a second arming path, `GIT_PATTERNS` plus
   bulk delete only (no `SECRET_PATTERNS`), as the gate answered. Its daytime message names the
   Write, Read or `--body-file` escape for a command that only quotes a dangerous string.
3. **#420** (P3), round 1 NEEDS-WORK. Its sentinel follows the one-file-per-hook rule:
   `.claude/masked-exit`, the name the gate suggested. Record the built-in check and filter sets
   and the verified Q3 the gate recommended, apply the three required changes, re-gate, implement.

## Out of scope

- **#432** (the `no-poll-loops` trip-wired high and lows): `backlog`, unless #433's fix touches
  the same lines, in which case the implementer may take item 6 with it.
- **Secret-file reads by day** (`SECRET_PATTERNS`): left to overnight; a daytime arm for them is a
  new ticket in `backlog`.
- **A bare `git checkout <file>` and `rm -rf build/`**: #419's evidence over-claimed them; they
  stay allowed by day unless a new ticket decides otherwise (`backlog`).
- **Rewriting or denying a piped check (#420)**: the hook is advisory only.
- **Raising any baseline**: an agent never does; a shortfall is a maintainer question.

## Close record

Closed 2026-10-08. **Outcome: done.** Every expected ticket landed; nothing was moved out.

| Ticket | Landed | Notes |
|---|---|---|
| #433 | 984a5ee, aebf639 | No foreground `Agent` dispatch exists on Claude Code 2.1.294 (verified in the binary and by a probe from a subagent); the hook's reason now says end the turn and let the notification resume you, and Step 3B's foreground clause is deleted (ticket-gate 5648 to 5642) |
| #419 | 75ca07e, bab1821, 15b1954, 2b75481, bf1708d | Daytime arm behind `.claude/no-destructive`, including a relative `rm -rf` ending in a wildcard; overnight unchanged |
| #420 | bbc9aa6, 459cd9f, fb9e8b8 | `masked-exit-advisory` PostToolUse hook behind `.claude/masked-exit`; gate round 2 PASS |

**The premortem, clause by clause:**

- *#433 was settled from the docs*: avoided. The fact was read from the installed binary's schema
  builder and confirmed by a probe dispatch inside a subagent. The new advice holds either way,
  since it never names a blocking call. Headless `claude -p` and a subagent ending its turn with
  a child outstanding stay unverified, recorded in #434.
- *The overnight guard changed*: did not. The three overnight reason strings are now pinned by
  exact equality with mutants, and a differential over the old and new hook found no overnight
  regression.
- *The relative-glob rule over-reached*: held. `rm -rf tmp/impl-213` and `rm -rf build` stay
  allowed by day; a missing pin for a bare `rm -rf .` is in #435.
- *A sentinel nothing creates*: avoided. forge-adapt's `references/hooks.md` creates both new
  sentinels on every install branch.
- *Words*: no baseline was raised; ticket-gate fell to 5642 and `adapt` stayed at 7144.
- *#420 never reached the model*: avoided. `additionalContext` delivery was read from the binary,
  and the registration row proves the hook runs.
- *Collisions*: did not happen; the three ran in sequence.

**What the plan did not foresee:**

- **#433 reversed a maintainer pick.** "Critic in foreground" (2026-10-08) rested on a dispatch
  mode the harness does not offer, so the fix removes it; the reversal is recorded in the hook's
  comment and on #433.
- **A background security review caught #419's round 1 fix.** It reported a control regression and
  a parser differential, which turned out to be one bug: 45 daytime bypasses (a path-qualified
  `rm`, flags after the target). Round 2 fixed them and round 3 found nothing. The code reviewer
  found the same defect independently.
- **PostToolUse never fires on a non-zero exit** (it runs `PostToolUseFailure`), so #420's
  advisory only sees the masked, exit-0 case, and it also fires when the check passed.
- The lows went to #434, #435 and #436 (backlog).
