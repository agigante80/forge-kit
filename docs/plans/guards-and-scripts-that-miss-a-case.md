# Plan: Guards and scripts that miss a case

Written 2026-10-11, when *What a session loads before work begins* closed, during an autonomous
overnight run the maintainer started with "Follow your suggestions, it's a overnight process, be
autonomous. Merge to main and release at the end". Every open ticket was read against the tree at
02deb2b. The tickets taken in share one shape: a shipped guard or script is right for the case it
was written for and wrong for a neighbouring case nobody fed it. Three are P2 (two of them security),
the rest P3 in the same areas, taken in under the review-loop rule that a low in an opening phase's
area is planned or closed, never left waiting.

## Goal

Each guard and script below gives the right answer for the case it currently misses, pinned by a
contract-test row that fails on the old code and a mutant that dies.

## Done looks like

- `overnight-guard` denies destructive git under any git global option (`-C`, `-c`, `--git-dir`,
  `--work-tree`, `-p`, `--bare`, `--no-pager`, quoted and separate-argument values) in both arms, and
  judges a 200-token `-c` run in under 100ms (#457).
- `overnight-guard` denies `rm -rf` aimed at the worktree itself: `$PWD` and `$(pwd)` in every
  spelling, `$CLAUDE_PROJECT_DIR` and `$(git rev-parse --show-toplevel)` (#467).
- The private leak scanner's tree mode finds a listed name in a non-UTF-8 file under a UTF-8 locale,
  keeps non-ASCII case folding, and its tree-mode rows run in every locale (#456).
- `reassess-phases` keeps a multi-line merge or delete reason whole (#460), and its `--check` refuses
  exactly what the real run refuses for renames, inserts, splits and reorders (#464).
- `roadmap-lib` refuses a plan path carrying a control character, so a TAB can no longer corrupt the
  phase row (#463, after #464 for its `--check` rows).
- `check-ticket-mechanics` reads a bare `na` mention as prose, while `N/A`, `n/a`, `not applicable`
  and a leading `NA` remain N/A claims (#459).
- forge-adapt's labels block accepts an uppercase area name and compares fixed and duplicate labels
  case-insensitively (#465), and writes every file through a scratch file beside its real target,
  keeping a symlink, its mode and all-or-nothing (#466).
- The two `no-poll-loops` cases left unverified by #433 are probed on a named Claude Code release and
  recorded, or a refuted one has its own follow-up ticket (#458).
- Each ticket is closed against a named commit, `Validate` is green on `main`, and no component
  baseline is raised.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **The fix guarded the listed spellings and missed the next one.** Every ticket here exists because
  a matcher was written from examples. #457's first acceptance list named six git options and the
  gate found four more bypasses within minutes; #467's named four `rm` targets and the gate found four
  more. A fix written to the list ships the same defect one spelling over. Each matcher is written
  from the grammar (git's usage line, shell word splitting), and each test file carries a near-miss
  that must stay allowed.
- **The guard became slow enough to stop guarding.** A hook that times out does not deny. #457's naive
  prefix regex backtracked exponentially on repeated `-c` tokens. The timing row is a criterion, not
  an advisory.
- **The `--check` and the real run disagreed again.** #464 is the third time a dry run approved what
  the write refused. If `--check` keeps its own validation instead of driving the real writers into a
  scratch file, the next new validation reopens it. The dry run calls the wrapped file half.
- **A locale fix broke case folding.** The obvious fix for #456 (`LC_ALL=C` on that grep) makes
  `JOSÉ` stop matching `josé`. Only a test pins that, so the folding row lands with the fix.
- **A narrowed N/A rule turned a legitimate ticket into a fail.** #459's first wording would have
  read `this is N/A for a docs-only change` as no claim and failed the row. The slash forms stay
  global; only slashless `na` narrows.
- **The safer write lost the user's file.** Writing through a symlink with `cat >` keeps the link but
  truncates the doc on a failed write. #466 keeps atomicity by renaming beside the resolved target.
- **The probe ran once and was called verified.** #458's answer depends on the release and the
  output format. One session, one format, is an anecdote; the record names the release and needs a
  second session.

## Expected work

One ticket at a time per plugin group, because the markers and the plugin semver serialize them.
Gate each first; a gate that needs a judgment call the overnight run cannot make parks the ticket.

1. **#457** (P2, security), **#467**, **#469** and **#470** (P3): all `overnight-guard.py`, so one after
   the other.
2. **#456** (P2, security): `check-private-leaks.sh`, independent.
3. **#460** (P2), then **#464**, then **#463**: the roadmap assets, in that order (#463's TAB
   `--check` rows need #464's dry run).
4. **#459**: `check-ticket-mechanics.sh`.
5. **#465**, then **#466**: the forge-adapt labels block in `references/templates-labels.md`; the
   `adapt` SKILL.md is at its no-growth baseline and must not gain a word.
6. **#458**: the probe, last, because it touches no logic.

## Taken in or closed at opening

- Taken in: #457, #456, #460, #467, #463, #464, #459, #465, #466, #458.
- Filed inside the phase and taken in: #469 (#457's review stopped on the trip wire leaving its
  32-option cap failing open; P3, fail closed at the cap). #470 (#467's review found `rm -rf 2>&1 /` allowed because the
  segment is cut at the `&` of a redirection; P3). #471 (a backslash-newline joins words the guard
  reads apart; P3). #472 (an uppercase area label misses the gate's lens routing; P3). #473 and #474
  (two redirection spellings #470's review found still allowed; P3).
- Left in the backlog with its reason: #454 (health-check step 9 and the credential helper; a
  report-wording fix in another area, still real after #468).
- Closed as moot after #468: #451, #452.

## Out of scope

- The UTF-16 skip the #456 security lens found (a NUL-bearing text file is treated as binary in every
  locale): pre-existing, no reported user, recorded in the run's decisions file.
- The overnight arm judging only the first `rm` in a compound command (#467 states it as a known
  limit).
