# Plan: What the tree modes could not read

Phase opened 2026-09-16 for #208 (P1) and #209, the first two tickets from the overnight security
audit of the leak guard, both gated to PASS (or to a folded final item) overnight and this morning.

## Goal

Make the TREE modes fail closed the way `--history` already does, and make the private half's
owner drop apply only where its rationale is true.

## Done looks like

- #208: a renamed-and-edited file, a typechange, a staged path shaped `0:x`, a file named `-v` or
  `-`, a `chmod 000` file, a failed `mktemp`, a failed blob write: each reported or refused, never
  exit 0, in both halves; a staged gitlink still scans the rest.
- #209: the owner is dropped only in tree modes and only when origin's host is exactly one of the
  four public forges; never in `--history`; the parser follows git's URL grammar by form; a
  relative or local origin yields no owner; `2222` listed with a port-carrying URL is reported.
- Suites green under bash 5 and 3.2 with Apple's awk; markers and the group semver moved; both
  headers, the `--init` template, SKILL.md and CLAUDE.md say the new rule.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A refusal became a false negative's twin.** `die` on a gitlink, or on a file git cannot show
  for an ordinary reason, and every commit with a submodule refuses. The cause test
  (`cat-file -e ":0:$f"`) is what separates "absent object" from "could not write".
- **The URL parser was written by heuristic, not by form.** A digit test for the port took an
  all-digit GitHub owner for a port; `*@` was stripped after `:port` and a token containing a
  colon moved the host. Form first, then userinfo, then port; fixtures for every form.
- **A message printed what it exists to hide.** A `$TMPD` path, or the owner name unredacted, in
  stderr that will be pasted somewhere public.
- **The public half was fixed and the private half was not**, or the other way round. Every case
  runs in both suites.

## Expected work

#208, #209. Nothing else.

## Out of scope

- #210, #211 (same audit, separate phases), #206, #212.
