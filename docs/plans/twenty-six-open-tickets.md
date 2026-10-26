# Plan: Twenty-six open tickets

Written 2026-10-26, unattended, at the start of a run whose brief from the maintainer was to "implement
everything". On 2026-10-16 one session filed #540 to #564 in a day while reviewing downstream installs,
then shipped #565 so that could not happen again. Every one of them was gated, most of them more than
once, and none sat in a phase. #565 has since shipped and was closed at the start of this run; #566
(a new `usage-report` skill) was filed later and had not been gated.

## Goal

Every open ticket lands with a row that failed first and a mutant that dies, or, for a prose or docs
ticket, with the guard or the sentence it promised, and the backlog holds only what the run could not
finish for a stated reason.

## Done looks like

- `citation-check.sh` accepts alias and acknowledgement markers in a project's ticket-standards doc,
  reads the project's own copy of the mechanics script first, and `check-ticket-mechanics.sh` names
  the aliased section in its evidence (#543, #547, #556, #557, #544, #545).
- forge-adapt reports `shadowed` and `retired` for agents, skills and hooks alike, keeps a local tier
  line consistent after refresh, and `retired-paths --remove` refuses a script something still calls
  (#540, #548, #550, #564).
- `forge-lib` finds the remote when it is not named `origin`, pins every routing key, keeps its detect
  line apart from `forge_ci_status` stderr, lets a project filter an issue body, and its leak scan reads
  the sentinel and allowlist from the default branch rather than the working copy; `/ci-health` reads
  `.forgejo/workflows` (#541, #542, #546, #552, #553, #558, #560).
- Every component that dispatches an agent from another group declares that group, and the security
  lens says so out loud when `security-auditor` is missing (#551, #555, #562, #563, #561).
- `api-security-tester` and `owasp-api-security` stop registering Fastify, Prisma, Zod and Vitest text
  on a stack that has none of them, and the gate's docs stop saying it scores (#549, #559, #554).
- `usage-report` ships in `forge-kit-devops` with a contract-tested asset (#566).
- Validate is green on `main`, no baseline rose, and no ticket was filed (the consent hook denies it,
  and this run holds no grant).

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The streams collided.** Four worktree streams each bumped `forge-kit-devops` or
  `forge-kit-governance`, edited the CHANGELOG and moved suite counts; the merges were resolved by
  hand, a marker went backwards and `check-version-bump.sh` failed on `main`. Each merge is followed by
  the full local check run, the generated regions are regenerated in the main checkout, and a semver
  conflict takes the higher number plus one.
- **The trip wire was ignored rather than decided.** #546, #547, #558, #562 and #564 each stopped
  with the gate saying the next round was the maintainer's call. Implementing them on the last body
  without folding the open items would ship the defects the gate named. Each one gets a dated decision
  in its body first, choosing the shrinking fix where the gate offered one.
- **A security fix weakened the scan it hardened.** #546 and #558 change what the leak scan trusts. A
  pin read from the default branch that fails open on a shallow clone or a detached HEAD would make the
  scan trust nothing it should. The rows pin both refusals and the existing allows.
- **The new skill shipped an unbounded reader.** #566 reads every transcript under `~/.claude/projects`.
  A suite on synthetic transcripts that never meets a truncated line, a huge file or a non-UTF-8 byte
  hides the crash a real machine hits on the first run.
- **External reviewers were trusted as verdicts.** codex and agy findings went in unverified and one
  fix reintroduced the bug it fixed. Every external finding is reproduced against the tree before it
  is acted on, and the review loop's trip wire applies across reviewers.
- **A ratchet component grew.** `adapt`, `ticket-gate` and `full-review` are touched by several of
  these tickets; a declared dependency or a new mode line pushed one past its baseline. Their text moves
  into a reference or an asset instead.

## Expected work

Four streams in parallel worktrees, landed one at a time on `develop`.

1. **Citation family** (forge-kit-adapt, governance): #543 with #547, then #556, #557, #544, #545.
2. **forge-adapt states** (forge-kit-adapt): #540, #548, #550, then #564.
3. **forge-lib and the leak scan** (devops, security): #542 with #560, #553, #541, #546, #558, #552.
4. **Declared dependencies and stack text** (governance, review, security, docs): #551, #555, #563,
   #562, #561, #554, #549, #559.
5. **usage-report** (devops): #566, gated first.

## Taken in or left in the backlog

- Taken in: every open ticket, #540 to #564 and #566.
- Left in the backlog: none at the start. #282 stays a closed deferral with its review date.

## Out of scope

- Any growth of `ticket-gate.md`, `full-review.md` or the `adapt` SKILL.md.
- A release (not requested for this run).
- Folding the old decision comments into bodies for tickets this run closes; a closed ticket is read
  by its closing note and its commits.
