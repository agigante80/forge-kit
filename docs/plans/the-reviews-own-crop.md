# Plan: The reviews' own crop

Phase opened 2026-09-18 during an unattended run, from the Lows the night's fourteen review rounds
ticketed under the bounded loop. The maintainer was asleep; the premortem is mine and is an
assumption for the morning report.

## Goal

The Lows the review loop refused to fix inside its rounds are fixed the same night, each as its own
gated, reviewed, merged change, so a ticketed finding is a finished outcome rather than a deferred
one.

## Done looks like

- The three writers print their 404 line under a `set -e` caller too, captured in the errexit-safe
  shape `forge_api`'s own comment designs for (#237).
- `forge_repo` never prints a string containing `@` as a slug (#235), decided as refuse or as
  strip, stated in the header.
- The `root` parser refuses a two-segment root, a bare tilde, a value with a leading space, and a
  value ending in a slash after the first strip (#240), and a punctuation-ending entry is refused unless
  it is a known marker (#239 part 1), each with its near miss.
- Rules A and B walk a punctuation tail once, and `/home/<name>` plus 64 KB of dots scans within
  the suite's `bounded` (#239 part 2).
- `forge-call-mapping.md` maps a body edit to `forge_issue_edit` with its signature, and the two
  other drifts #234 names are gone.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The errexit fix changed a writer's success path.** `rc=0; forge_api ... || rc=$?` is the
  shape; a `|| true` or a subshell would swallow the code the callers depend on. The nine #229
  cases are the net and must stay untouched.
- **#235 decided "strip the userinfo" and printed a slug for a URL git itself would not read that
  way.** Refuse is the honest branch; a slug from a shape git cannot clone is a 404 with extra
  steps.
- **The parser guards refused a legitimate entry.** Every guard ships with the entry it must still
  accept: the three markers, `<root>`, dotfile roots, and a root with one trailing slash.
- **The linear walk changed a verdict.** The tail walk is a performance change; the suite's 380
  cases are the proof it changed nothing else, and a timing case under `bounded`, never `timeout`.
- **A docs fix restated a gate rule.** `forge-call-mapping.md` is scanned by
  `check-restatements.sh`; a row that names a rule number needs its anchor.

## Expected work

#237, #235, #240, #239, #234, in that order, each gated (two rounds, fold or file) and reviewed
(bounded loop). #236 is deliberately out: it is a wording decision, not a defect.

## Out of scope

- #236 (a taste call), #222 and #226 (parked on decisions), #206 and #217 (structural), #207,
  #219, #220, #221, #213, #196, #215 and #216's descendants: `backlog`.
