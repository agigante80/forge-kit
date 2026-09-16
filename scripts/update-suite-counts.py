#!/usr/bin/env python3
"""Rewrite the suite counts CLAUDE.md states from the suites' own printed totals, or check them.

Issue #201. CLAUDE.md says `scripts/test-X.sh`, N tests for eleven contract suites, and nothing
checked N. Two gate rounds (#199, and 965d7e0 before it) had already been spent on those numbers
when running the suites found three MORE stale: 25 for a suite printing 45, 79 for 80, 22 for 81.
The drift is silent and one-directional (suites grow, prose does not), so the numbers are now
generated the way the component index is (#96): this script is the only thing that writes them,
and --check fails CI when one is stale.

N is the suite's PRINTED total, pass plus fail from its summary line, which counts assertions
rather than case sections (test-sync-labels.sh has 24 sections and prints 81). That is the one
number a suite reports for itself, so it is the one this keeps.

The anchor is the existing prose shape, with no inline markers: a backticked scripts/test-*.sh or
.py path, a comma, at most one line break, digits, at most one line break, the word tests. Only
that number is a claim. A later "N tests" in the same bullet (line 97's "24 downstream tests") is
prose and is never touched, and a suite named with no count is not a claim at all.

The total is read from the COMBINED stdout+stderr stream, because python's unittest reports on
stderr with an empty stdout, and from the LAST line matching any of the three shapes the tree
uses. A suite that is missing, or prints no recognisable total, REFUSES: exit 2 and nothing
written. A generator that writes 0 where it could not read is the drift it exists to end.

The path read from the doc is an input. It is matched by an anchored pattern, resolved under
--root/scripts, and run without a shell, so nothing in a doc can name a command.

Usage:
  update-suite-counts.py [--check | --list] [--doc FILE] [--root DIR]

  default   run each named suite and rewrite its number in place, reporting what changed
  --check   run each named suite; exit 1 naming every stale claim, write nothing (for CI)
  --list    parse and print the claims (path, line, stated N); run nothing
"""
import argparse
import os
import re
import subprocess
import sys

# One `, N tests` directly after the backticked path, each gap allowed one line break so a claim
# that wraps (CLAUDE.md line 130 breaks between the digits and "tests") is still one claim.
CLAIM_RE = re.compile(
    r"`(scripts/test-[a-z0-9-]+\.(?:sh|py))`,[ \t]*\n?[ \t]*(\d+)[ \t]*\n?[ \t]*tests\b"
)

# The three summary shapes in the tree today, in the order they are tried on each line.
SHAPES = [
    re.compile(r"(\d+) passed, (\d+) failed"),          # <label>: N passed, M failed
    re.compile(r"passed: (\d+)\s+failed: (\d+)"),      # passed: N  failed: M
    re.compile(r"^Ran (\d+) tests?\b"),                 # unittest, on stderr
]

TIMEOUT = 600


def claims(text):
    """Every claim in the doc: (path, stated N, match span of N, line number)."""
    out = []
    for m in CLAIM_RE.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        out.append((m.group(1), int(m.group(2)), m.span(2), line))
    return out


def printed_total(root, path):
    """Run one suite and return the total it prints, or None when it cannot be read."""
    full = os.path.realpath(os.path.join(root, path))
    if not full.startswith(os.path.realpath(os.path.join(root, "scripts")) + os.sep):
        return None
    if not os.path.isfile(full):
        return None
    interp = "python3" if path.endswith(".py") else "bash"
    try:
        proc = subprocess.run(
            [interp, full], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=TIMEOUT, text=True, errors="replace",
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    total = None
    for line in proc.stdout.splitlines():
        for shape in SHAPES:
            m = shape.search(line)
            if m:
                total = sum(int(g) for g in m.groups())
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="exit 1 if any claim is stale; write nothing")
    mode.add_argument("--list", action="store_true", help="print the claims and run nothing")
    ap.add_argument("--doc", default=None, help="the doc to read (default: <root>/CLAUDE.md)")
    ap.add_argument("--root", default=None, help="repo root the suites run from (default: git toplevel)")
    args = ap.parse_args()

    root = args.root or subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], stdout=subprocess.PIPE, text=True, check=True
    ).stdout.strip()
    root = os.path.realpath(root)
    doc = args.doc or os.path.join(root, "CLAUDE.md")

    # An absent doc is SKIPPED, loudly, and is never a failure. CLAUDE.md stopped being published
    # on 2026-09-16 (a maintainer decision: assistant instructions are local working state), so the
    # claims live on a maintainer's machine and in no CI checkout. Failing here would fail every
    # build over a file the repository has decided not to carry; saying nothing would let the
    # claims rot unnoticed. The counts are still checked wherever the doc exists, which is where
    # they can be wrong. An explicit --doc that is missing is still an error, since the caller
    # named a file it expected to be there.
    if args.doc is not None and not os.path.isfile(doc):
        print("update-suite-counts: no such doc: %s. Nothing checked." % doc, file=sys.stderr)
        return 2
    if args.doc is None and not os.path.isfile(doc):
        print("update-suite-counts: %s is not in this checkout, so no claim was checked."
              % os.path.relpath(doc, root))
        return 0
    with open(doc, encoding="utf-8") as fh:
        text = fh.read()
    found = claims(text)

    if args.list:
        for path, stated, _, line in found:
            print(f"{path}\t{line}\t{stated}")
        return 0

    stale = []
    for path, stated, span, line in found:
        total = printed_total(root, path)
        if total is None:
            print(f"update-suite-counts: cannot read a total from {path} (line {line}); "
                  f"missing, outside scripts/, or no recognisable summary line. Nothing written.",
                  file=sys.stderr)
            return 2
        if total != stated:
            stale.append((path, stated, total, span, line))

    if args.check:
        for path, stated, total, _, line in stale:
            print(f"stale: {path} (line {line}) says {stated} tests, prints {total}. "
                  f"Run scripts/update-suite-counts.py to fix.")
        if stale:
            return 1
        print(f"suite counts current: {len(found)} claims match")
        return 0

    # Rewrite from the end so earlier spans stay valid.
    for path, stated, total, (a, b), line in sorted(stale, key=lambda s: s[3][0], reverse=True):
        text = text[:a] + str(total) + text[b:]
        print(f"{path} (line {line}): {stated} to {total}")
    if stale:
        with open(doc, "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        print(f"suite counts current: {len(found)} claims match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
