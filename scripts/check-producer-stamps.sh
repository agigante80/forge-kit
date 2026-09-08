#!/usr/bin/env bash
# check-producer-stamps.sh: no component may HARDCODE a template-version stamp (issue #84).
#
# THE DEFECT. A component that emits ticket bodies used to write the version literally.
# `dep-auditor` and `/ci-health` both did, still stamping v4 after the v5 bump, and
# check-template-lockstep.sh could not see it: its scope is the issue-template dir plus the
# canonical doc, not the producers. So every machine-filed ticket was born stale and triggered a
# synthesis round-trip against a ticket the kit itself had just created. PR #83 fixed the two
# instances by making both read the CURRENT version; this is what stops the next one.
#
# THE RULE, and it has no allowlist on purpose. Inside the scanned tree, `template-version:`
# followed by a digit is always wrong. A producer resolves the version at runtime, and prose refers
# to the marker in the `N` form, which the repo has followed everywhere since #83. A guard with an
# allowlist would be argued with; this one cannot be.
#
# NOT the component markers. Every component carries `<!-- <name>-version: N -->` with a real
# digit, so this anchors on the literal word `template-version` and nothing else.
#
# Usage: check-producer-stamps.sh [ROOT]      (default: this repo's plugins/ tree)
# Exit: 0 clean, 1 a hardcoded stamp was found, 2 the root is unreadable.
set -uo pipefail

if [ "$#" -ge 1 ]; then
  ROOT="$1"
else
  TOP="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-producer-stamps: not a git checkout and no root given" >&2; exit 2; }
  ROOT="$TOP/plugins"
fi
[ -d "$ROOT" ] || { echo "check-producer-stamps: '$ROOT' is not a directory" >&2; exit 2; }

# grep's three exit statuses are all meaningful here and must stay distinguishable: 0 found, 1 a
# clean tree (a project may legitimately ship no producers), anything else a READ ERROR. Collapsing
# them with `|| true` made an unreadable subtree containing an offending producer pass clean, which
# is the same vacuous pass the missing-root check exists to prevent.
#
# grep's own stderr is deliberately NOT captured. Routing it through a mktemp file reintroduced
# exactly that vacuous pass by a different door: with TMPDIR unusable, mktemp failed, the redirect
# failed, grep never ran, and status 1 read as "clean" while a violation sat in the tree. Letting
# stderr through needs no temp file, and CI shows it either way.
# WHICH files, from guard-lib.sh: the tracked set inside a checkout, the original recursive grep
# outside one (#140). This is about scope, not amnesty: the no-allowlist rule below is untouched,
# and the same content tracked still fails.
#
# The fallback is deliberately the ORIGINAL call. It fails closed on an unreadable subtree, which a
# `find`-based listing does not, and reopening that vacuous pass is precisely what the paragraph
# above warns against.
. "$(dirname "$0")/guard-lib.sh"
PAT='template-version:[[:space:]]*[0-9]'
if guard_in_checkout "$ROOT"; then
  files=()
  while IFS= read -r -d '' f; do files+=("$f"); done < <(guard_tracked_files "$ROOT")
  if [ "${#files[@]}" -eq 0 ]; then
    hits=""; grc=1
  else
    # -H because grep omits the filename when handed exactly one file, and every message below
    # names the path. One invocation rather than xargs, which collapses grep's "no match" (1) into
    # its own 123 and would destroy the three statuses this file depends on.
    hits="$(grep -nHE "$PAT" -- "${files[@]}")"; grc=$?
  fi
else
  hits="$(grep -rnE "$PAT" "$ROOT")"; grc=$?
fi

# A scan error is reported AFTER any hits, never instead of them: grep exits 2 on a read error even
# when it matched elsewhere, so discarding what it found would hide a real violation behind an
# unrelated permissions problem.
scan_failed=0
[ "$grc" -gt 1 ] && scan_failed=1

if [ -n "$hits" ]; then
  echo "check-producer-stamps: hardcoded template-version stamp(s) found." >&2
  echo "" >&2
  printf '%s\n' "$hits" | sed 's|^|  x |' >&2
  cat >&2 <<'MSG'

A component that emits a ticket body must resolve the CURRENT version at runtime
(read it from the issue-template dir), never write the number. Prose referring to the
marker uses the N form: <!-- template-version: N -->.
MSG
  [ "$scan_failed" -eq 1 ] && echo "NOTE: part of the tree could not be read (grep exit $grc); there may be more." >&2
  exit 1
fi

if [ "$scan_failed" -eq 1 ]; then
  echo "check-producer-stamps: could not scan all of '$ROOT' (grep exit $grc); see the error above." >&2
  exit 2
fi

n="$(find "$ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "check-producer-stamps: $n file(s) under $ROOT, no hardcoded template-version stamps."
