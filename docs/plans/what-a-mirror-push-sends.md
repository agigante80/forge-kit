# Plan: What a mirror push sends

Phase opened 2026-09-16 for the last two audit tickets: #210 (`--history` enumerates branches,
tags and remotes, and a mirror push ships every ref) and #211 (rule C's email regex is quadratic on
long word-class runs), if its gate passes.

## Goal

`--history` reads every ref a mirror push would send (everything except `refs/stash`, plus every
worktree's HEAD), and the public half's rule C stays linear on a 64 KB token.

## Done looks like

- Both scanners enumerate and map with `--exclude=refs/stash --all`; `refs/original` after a
  filter-branch, `refs/notes`, a detached HEAD and a bare blob ref are reported; the stash is not,
  and `--orphans` reaches it; the path-map case where only the map rescues a renamed blob passes;
  two mutants each lose the finding; headers, SKILL.md and the mutant ledgers say the new set.
- #211: the email regex anchored so a 64 KB alphanumeric run followed by an address reports
  within a bounded time in `--all` and `--history`; every existing rule C case unchanged.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **`--exclude` was placed after `--all`** and the stash was scanned; the argument order is the
  ticket's own round-1 finding and the stash case is the tripwire.
- **A fixture passed against the unfixed scanner** (three did in the ticket's first draft); each
  fixture runs against a mutant that must lose the finding.
- **The anchored email regex dropped a shape rule C used to catch** (an address at line start,
  after a quote, in brackets); the existing rule C cases are the guard, and a new near-miss for
  each shape the anchor touches.
- **The timing case was flaky in CI**; it asserts a bound generous enough (10 s) that only the
  quadratic path can miss it.

## Expected work

#210, #211. On close, file the cosmetic evidence-picker ticket the #210 gate named (the
`unit_tests` evidence printed a leading HTML comment).

## Out of scope

- #206 (shared reader), which moves the block these edit; after this phase.
