# Session handoff: the history mode, shipped without a Mac

Date: 2026-09-14 (same day as the previous handoff; this is the second close)

## Summary

#191 shipped as option D. The maintainer had no Mac, so the probe the ticket waited on became a
substitute verification (Apple's own awk source and bash 3.2.57 built on Linux) plus a README
statement of what that does not prove. Two review rounds, five Criticals found and fixed in round 1,
one behavioural hole in round 2, stopped there.

## Done this session

- Research: Apple's awk is its own fork with `length()` as `strlen` (bytes in every locale) and a
  multibyte layer only in regex and case conversion; built it (awk-40) with two shims and ran the
  ticket's probe: PASS, identical counts to gawk, mawk, busybox. Built bash 3.2.57 (bison via
  `apt-get download` + `dpkg -x`); both suites green with it first on PATH.
- Ticket #191: maintainer decision and design points recorded; gate round 2 (fifteen items, all
  folded, no third run); phase "The history the guard never read" opened and closed.
- Implementation: `--history`, `--orphans`, `--show-evidence` (public) / `--show-names` (private);
  POSIX awk byte-counting reader with no regex over content or path lines; every-path rule with a
  `-c`-pinned `git log -m --raw -z` map and a shape check that refuses; refusals for alternates,
  `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, partial clones, grafts, unreadable
  objects, any failed pipeline stage; `GIT_NO_REPLACE_OBJECTS=1`; `--remotes` in the publishable
  set; redaction by default, longest-name-first in the private half. Suites 83 to 179 and 43 to 88.
- Review loop: round 1 two reviewers (generalist + forge-kit code-reviewer), round 2 one on the
  fix commit; fixes in a940953 and 65a863c; mutants named in both suites.
- Tickets: #206 (one copy of the reader, shared `leak-lib.sh`), #207 (what this repository says
  about its own 159 historical example-root findings). #204 and #205 arrived from elsewhere with
  no milestone and were put in Backlog so rule 1 passes; placement is the maintainer's.
- Memory: build the platform source when you lack the platform; a scanner premortem enumerates
  uncontrolled inputs.

## In progress (where we left off)

Nothing. `main` = `develop` = `03a8663`, Validate green on both. This close is committed with it.

## Next steps

1. **#204 and #205** (filed outside this session, about `check-ticket-mechanics.sh` gaps found
   gating twelve tickets in another repo): triage them into a phase; they read like one phase.
2. **#207** is a decision (A: allow the historical example roots; B: a `--since` bound; C: accept
   exit 1 here). Decide before the next release.
3. **#206** when the next change to the shared block comes, not before.
4. A release: v0.5.0 was cut 2026-09-12; since then #199 to #203 and #191 shipped, and
   `forge-kit-security` moved 0.9.2 to 0.10.0. Worth a v0.6.0.
5. If a Mac ever appears: run both suites there and `--history` on any repository; a report is a
   ticket.

## Decisions and why

- **Ship without a Mac** (maintainer): substitute verification against the platform's own source
  is stronger than a document and weaker than hardware, and the README says which.
- **`--remotes` in the publishable set** (deviation from AC 9 as written): a remote-only branch is
  already on a forge; with several remotes it over-reports, the safe side.
- **The review's allow-file twin scenario was not encoded as written**: `skip zzz.md` plus
  `aaa.lock` skips every path under the every-path rule the review itself endorsed; pinned with a
  third unskipped path instead.
- **No round 3**: round 2 found defects in round 1's fix (one behavioural, the rest coverage), none
  high; the trip wire needs two consecutive such rounds. Reported in the close.
- **Two reviewers in round 1** on a security tool: their Critical sets barely overlapped.

## Open questions / blocked on

- Whether `--history` should be run as part of `release` here (it exits 1 today: #207).
- Whether #204/#205 belong in one phase now or wait.

## Key context to reload

- `gh issue list --state open` (five, all Backlog: #196, #204, #205, #206, #207)
- `docs/plans/the-history-the-guard-never-read.md` (the premortem and what it missed),
  `docs/roadmap.md` last close
- `.claude/memory/build-the-platform-source-when-you-lack-the-platform.md`,
  `scanner-premortem-enumerate-uncontrolled-inputs.md`
- The scratchpad builds are gone with the session; the memory says how to rebuild them.
