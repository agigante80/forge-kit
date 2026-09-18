# Plan: What a downstream Forgejo found

Phase opened 2026-09-18 for #228 and #229, found on 2026-09-17 by a forge-adapt refresh of a
private downstream repo (Forgejo 11.0.16) from an unmarked 2026-08-15 copy of `forge-lib.sh` to
v16, plus #216, the parser follow-up #212's review left in the same file. The downstream copy is
verbatim and was not patched, so the fix lands here and is pulled down.

## Goal

`forge-lib.sh` v17 fails loudly and quickly on a Forgejo host where v16 fails silently or slowly:
the comments paginator stops on an ignored `page` in seconds rather than at its cap, and a write
to a missing issue says so.

## Done looks like

- `forge_api_paginate` stops when a page is identical to the previous one, returns that page once,
  and names on stderr which end condition it hit; the cap stays as the backstop. Termination on an
  EMPTY page stays as it is, and the `length < limit` rule the source rejects at its line 298 is
  NOT adopted, whatever the ticket's second acceptance criterion says (see Fails if).
- `count-gate-rounds.sh` reports a number rather than `unknown` on the reproduction host, verified
  by the downstream session that holds that host, because this checkout never touches it.
- `forge_issue_comment`, `forge_issue_close` and `forge_issue_edit` each print one stderr line
  naming the function, the issue and the status when `forge_api` returns 44, and propagate
  the code; success stays silent on both streams. `forge_api`'s own 404 arm stays quiet, and the
  org-404 case that pins it stays green.
- `forge_repo` derives its slug from the same authority isolation as `_forge_url_host`, every
  existing fixture prints the same slug, `git@[::1]:o/r` prints `o/r`, and a mutant restoring the
  old `*:*/*` glob fails.
- Every new case in `scripts/test-forge-lib.sh` was shown red against v16 first, with
  `FORGE_PAGINATE_MAX_PAGES` lowered in the identical-page case so red takes seconds.
- `forge-lib.sh` marker 16 to 17, its header changelog says why, `forge-kit-devops` semver bumped.
  (CLAUDE.md states no count for this suite, so there is nothing to regenerate; corrected by #234.)

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The short-page stop went in and a clamped host returned a partial list, exit 0.** #228's
  acceptance criteria ask for "stops when the first page is shorter than `limit`". The source
  refuses exactly that rule at line 298: Forgejo clamps `limit` to its admin-set
  `MAX_RESPONSE_ITEMS`, so a page of 30 against a request for 50 is a FULL page, and stopping on it
  is the silent truncation #62 fixed for issues. The ticket carries a criterion that contradicts
  the file it changes, and the gate is where that gets struck out, not the implementation.
- **"Identical" was byte-identical, and the real host's pages differ by a byte.** The stub
  returns the same string every time; a live response can carry a field that changes between calls
  (a computed `updated_at`, a rate-limit header leaking into the body, ordering), so the stop never
  fires live and the function still spins to the cap. The comparison must be on something the
  ticket's own reproduction shows stable, the id list, and the live check is the downstream
  session's to run before this closes.
- **The writers' new stderr line made a consumer treat success as failure.** Something that
  captures `2>&1` from a writer and tests for empty output now sees the line on a REAL failure and
  nothing on success, which is the intended direction; but a consumer that had been reading rc 44
  as "already closed" and moving on would now log noise it never had. Grep the governance prose
  for every caller before shipping, not after.
- **`forge_repo`'s one parser changed a slug on a real remote no fixture named.** Every listed
  fixture agrees today; the risk is the shape nobody listed. The existing table is the regression
  net and it runs before and after, on bash 5 and 3.2.
- **The phase shipped green here and the downstream host still failed**, because the only Forgejo
  this project may test against is one this checkout is forbidden to touch. The stub is the proof
  the tests can offer; the live run is owed by the session that found the bug, and the close
  review records whether it happened rather than assuming it.

## Expected work

#228, then #229, then #216, in that order: the paginator is the one users are waiting on, the
writers are a contained change with six cases, and #216 is a follow-up that only earns its place
because the file is already open. Each gated first, two rounds at most, remainder folded or filed.

## Out of scope

- #196, restoring the gate's round memory from the latest review comment. It is built on
  `forge_issue_comments` and inherits the fix; it stays in `backlog`.
- The downstream repo's own issues 159 and 160 and its `docs/forgejo.md` sharp edges. They close
  when that project pulls v17 down, and that is its session's work.
- A `forge_api_paginate` rewrite around `Link` headers or `X-Total-Count`. The identical-page
  stop is enough for the failure observed, and the cap remains the backstop.
- Anything in the leak-guard crop (#222 to #227, #230 to #232). Next phase.
