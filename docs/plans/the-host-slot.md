# Plan: The host slot

Phase opened 2026-09-16 for #212, found by the #209 gate: `forge_host` decides GitHub with a
`case` glob in which `*` crosses `/`, so `@github.com/` anywhere after the scheme reads as the
host; the lens found the same shape in `_forge_token`, the credential-bearing copy.

## Goal

One host extractor in `forge-lib.sh`, by URL form, used by both `forge_host` and `_forge_token`;
and the same authority cut (first of `/`, `?`, `#`) in the #209 parser, which cut at `/` alone.

## Done looks like

- `forge_host` and `_forge_token` classify by the isolated authority: userinfo stripped first,
  then port (kept for the credential request), compared case-insensitively; every fixture in the
  ticket passes, the three scp/port forms that flip to `github` are recorded as a v16 contract
  change; `https://evil.internal#@github.com` never reaches `git credential fill` as github.com.
- `check-private-leaks.sh`'s parser cuts the authority at `/`, `?` or `#`, with the fixture.
- `adapt/SKILL.md`'s copy of the globs gets a follow-up ticket and a word-neutral comment fix.
- Suites green; markers and both group semvers moved.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The extractor was written by heuristic.** A digit test for the port, or `*@` stripped after
  `:port`, and a token containing a colon moved the host. Form first, userinfo, then port.
- **A bracketed IPv6 authority aborted under `set -u`** or matched nothing and crashed a caller.
  It matches nothing and exits 0.
- **The credential fix was a no-op** because the extractor still cut at `/` alone and `#@` slid
  through. The AC 6 negative fixture ships with the helper, in the suite.
- **The adapt copy diverged further** because the ratchet forbade the fix and nobody filed it.

## Expected work

#212, plus the one-line cut in the #209 parser (a suppression path in a security scanner shipped
today; not widening the ticket, since the two parsers must not disagree on what an authority is).

## Out of scope

- The adapt SKILL.md fix itself (ratcheted; follow-up ticket).
