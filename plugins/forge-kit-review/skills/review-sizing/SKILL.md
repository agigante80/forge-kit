---
name: review-sizing
description: |
  How /full-review decides whether a round needs all five phases or code-reviewer alone: the
  inputs `assets/size-review.sh` reads, the order its rules apply in, the sensitive-path file
  format, and the measurement behind the 5-file, 300-line threshold. Reference for the command
  and for anyone declaring a project's sensitive paths; it decides nothing itself.
---

<!-- review-sizing-version: 1 -->

# Review sizing

`/full-review` runs `assets/size-review.sh` before it dispatches anything and follows the one line
it prints: `full: <reason>` runs every phase, `scoped: <reason>` runs step 1A (`code-reviewer`)
alone and skips 1B and Phases 2 to 4. The cost of a round is the number of agents it dispatches,
not the tier each one runs on, so this is the lever a model choice cannot pull. The shape is
claude-security's scan sizing: a small diff gets the proportionate single-reviewer shape, and says
so before anything runs.

## What it reads

A range, `git diff --numstat --no-renames <base>...HEAD`, where `<base>` is the command's
`previous_ref`. Only a `--since` round or a verify-fixes round has one; round 1 of an audit targets
a path or a description and is always `full`. `--no-renames` makes a rename count as its old path
and its new one, so moving a file OUT of a sensitive directory still matches.

## The order, first match wins

1. `--full` given.
2. `--unattended` given (a working-overnight run is armed): an unattended run is a periodic audit.
3. No range to measure.
4. No sensitive-path file: the fail-safe, so a project that declares nothing keeps what it had.
5. A changed path matches a declared pattern.
6. A binary file: an unknown line count is never small.
7. The previous round found something in a step other than `1A` (`--prior-finders`, step ids from
   `full-review.md`, `unknown` when no prior report exists), so a fix to a security finding is
   re-checked by the security phase.
8. More than 5 files, or more than 300 changed lines (added plus deleted).
9. Otherwise `scoped`.

Rules 1 and 2 never touch the base. An unresolvable base otherwise exits 2 with nothing on stdout,
and the command halts rather than guessing a shape.

## The sensitive-path file

`.full-review-sensitive` at the repository root: one pattern per line, `#` comments and blank lines
ignored, surrounding whitespace trimmed. A pattern is a bash `[[ $path == $pattern ]]` glob, and
**`*` crosses `/`**: `plugins/*/hooks/*` matches `plugins/g/hooks/deep/x.py`. That is the reverse
of a shell glob and the same trap `find -path` set in #112, so write patterns for it. A MISSING file
means full on every round; an EMPTY one is a declaration that nothing is sensitive.

Declare what a small change can still break badly: hooks, security components, CI workflows,
guards, shipped executables.

## The threshold, measured

Measured 2026-09-24 over the last 200 non-merge commits on forge-kit's `develop` (to `cfe5af6`),
each against its first parent. Files changed: median 3, 75th percentile 5, 90th 8. Changed lines:
median 57, 75th percentile 138, 90th 335. 149 of 200 (75%) sit at or under both 5 files and 300
lines. With forge-kit's own sensitive set, 101 touch a sensitive path, leaving 96 of 200 (48%)
`scoped`. The numbers are claude-security's; the measurement says they cut this history near its
75th percentile rather than at an arbitrary point.
