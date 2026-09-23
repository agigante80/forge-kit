#!/usr/bin/env bash
# Contract test for roadmap-lib.sh's WRITE primitives (#246).
#
# The library was a parser with no writer, so every reshape of the roadmap was a hand edit and any
# component that reshaped it would have been the format's second definition. These cases pin the
# two properties that make a writer safe to have: it changes only what it meant to change, byte for
# byte, and it can never produce a file its own parser reads differently from what it wrote.
#
# Throwaway files only; nothing here touches a forge, and the library has no host dependency.
#
# MUTANTS KILLED, all fifteen run by hand on 2026-09-23 and each one shown to fail this suite:
# the parse-back comparison removed; the one-open rule removed from both sites; the state and the
# plan ambiguity checks removed, one each; the prose section-opening refusal removed; the
# --milestone-empty assertion no longer required; the writer's extent widened to the parser's
# (`^## ` back to `^## Phase:`); rename's host-consequence report silenced; the duplicate-name
# verdict dropped from _rm_block; _rm_block restored to printing a block line AND then DUPLICATE,
# which is the defect this suite found; insert's duplicate-name check removed; the temp file moved
# into TMPDIR; `cp -p` dropped so the mode is not preserved; the symlink walk skipped; and the
# multi-line prose moved off ENVIRON back onto an awk -v.
#
# Two of those were not hypothetical. The ambiguity cases and the repeated-name case were added
# BECAUSE the first battery left three mutants alive: the state-ambiguity case had been written
# against `open`, so the one-open rule refused first and the case tested neither, and nothing
# covered a repeated phase name at all, which is how the _rm_block defect survived to be found.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
LIB="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/roadmap-lib.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$LIB" ] || { echo "missing library: $LIB"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

fixture() {  # fixture <path>: three phases, prose, and a trailing non-phase section
  cat > "$1" <<'ROADMAP'
# forge-kit roadmap

Prose above every phase, which no primitive may touch.

## Phase: Alpha
state: done
plan: docs/plans/alpha.md

Closed long ago. This paragraph is the record of why, and a writer that reflowed it would erase
the thing the roadmap is for.

## Phase: Beta
state: planned
plan: docs/plans/beta.md

A bucket. Its prose mentions state: done inside a sentence, which is not a keyed line and must
survive every edit untouched.

## Phase: Gamma
state: open
plan: docs/plans/gamma.md

The one open phase.

## Notes

A trailing section that is not a phase. The parser's extent runs past it; the writer's stops here.
ROADMAP
}

run() {  # run <fn> <args...>: call a primitive, capture rc and stderr
  RC=$( ( . "$LIB"; "$@" >/dev/null 2>"$T/err"; echo $? ) ); ERR="$(cat "$T/err")"
}

echo "== set-state: one keyed line moves, nothing else does =="
# Deliberately NOT `open` here: the one-open rule is the next block's subject, and a mechanics case
# that also trips a policy rule tests neither.
fixture "$T/r.md"; cp "$T/r.md" "$T/before.md"
run roadmap_set_state "$T/r.md" Beta backlog
expect "set-state on a planned phase succeeds" 0 "$RC"
expect "and exactly one line differs" 1 "$(diff "$T/before.md" "$T/r.md" | grep -c '^< ')"
contains "state: backlog" "$(sed -n '/^## Phase: Beta/,/^## /p' "$T/r.md")" "and the new state is on the phase's own keyed line"
contains "state: done inside a sentence" "$(cat "$T/r.md")" "and a state mentioned in prose is untouched"
run roadmap_set_state "$T/r.md" Beta backlog
expect "setting the same state again is idempotent, not a refusal" 0 "$RC"

echo "== the one-open rule reaches set-state, not only insert =="
fixture "$T/r.md"; cp "$T/r.md" "$T/before.md"
run roadmap_set_state "$T/r.md" Beta open
expect "opening a second phase while Gamma is open is refused with 5" 5 "$RC"
contains "Gamma" "$ERR" "and names the phase already open"
expect "and the file is byte-identical" "" "$(diff "$T/before.md" "$T/r.md")"
run roadmap_set_state "$T/r.md" Gamma open
expect "re-opening the already-open phase is idempotent" 0 "$RC"

echo "== a malformed file refuses with 3, and a policy refusal is not malformed =="
fixture "$T/bad.md"; sed -i 's/^state: planned$/state: whatever/' "$T/bad.md"; cp "$T/bad.md" "$T/badbefore.md"
run roadmap_set_state "$T/bad.md" Alpha done
expect "an unknown state anywhere in the file refuses with 3" 3 "$RC"
expect "and writes nothing" "" "$(diff "$T/badbefore.md" "$T/bad.md")"

echo "== the writer is stricter than the parser: ambiguity refuses =="
fixture "$T/amb.md"
awk '/^## Phase: Beta/{print; print "state: planned"; next} {print}' "$T/amb.md" > "$T/amb2.md"; mv "$T/amb2.md" "$T/amb.md"
cp "$T/amb.md" "$T/ambbefore.md"
run roadmap_set_state "$T/amb.md" Beta backlog
expect "two column-0 state lines in one block refuse with 5" 5 "$RC"
expect "and write nothing" "" "$(diff "$T/ambbefore.md" "$T/amb.md")"
fixture "$T/ambp.md"
awk '/^## Phase: Beta/{print; print "plan: docs/plans/other.md"; next} {print}' "$T/ambp.md" > "$T/ambp2.md"; mv "$T/ambp2.md" "$T/ambp.md"
cp "$T/ambp.md" "$T/ambpbefore.md"
run roadmap_set_plan "$T/ambp.md" Beta docs/plans/new.md
expect "two column-0 plan lines in one block refuse with 5" 5 "$RC"
expect "and write nothing either" "" "$(diff "$T/ambpbefore.md" "$T/ambp.md")"

echo "== a repeated phase name is ambiguous for THAT phase, and for no other =="
fixture "$T/dup.md"
awk '/^## Phase: Gamma/{print "## Phase: Beta"; print "state: planned"; print "plan: docs/plans/beta-again.md"; print ""} {print}' "$T/dup.md" > "$T/dup2.md"; mv "$T/dup2.md" "$T/dup.md"
cp "$T/dup.md" "$T/dupbefore.md"
run roadmap_set_state "$T/dup.md" Beta backlog
expect "writing to the repeated name is refused with 5, not 3" 5 "$RC"
contains "two phases are named" "$ERR" "and says which ambiguity it hit"
expect "and writes nothing" "" "$(diff "$T/dupbefore.md" "$T/dup.md")"
run roadmap_set_state "$T/dup.md" Alpha backlog
expect "an unambiguous phase in the same file is still writable" 0 "$RC"
run roadmap_rename "$T/dup.md" Alpha Beta
expect "renaming onto an existing name is refused with 5" 5 "$RC"

echo "== set-plan and set-prose, which the consumers need and the five did not have =="
fixture "$T/r.md"
run roadmap_set_plan "$T/r.md" Beta docs/plans/renamed.md
expect "set-plan succeeds" 0 "$RC"
contains "plan: docs/plans/renamed.md" "$(cat "$T/r.md")" "and the plan path is the new one"
fixture "$T/r.md"; cp "$T/r.md" "$T/before.md"
run roadmap_set_prose "$T/r.md" Beta "Refocused on 2026-09-23: the bucket now holds the writer work, and this sentence is why."
expect "set-prose succeeds" 0 "$RC"
contains "Refocused on 2026-09-23" "$(cat "$T/r.md")" "and the new prose is in the block"
contains "state: planned" "$(sed -n '/^## Phase: Beta/,/^## Phase: Gamma/p' "$T/r.md")" "and the keyed lines survive it"
contains "## Notes" "$(cat "$T/r.md")" "and the trailing non-phase section is not absorbed"
contains "The one open phase." "$(cat "$T/r.md")" "and the next phase's prose is untouched"
run roadmap_set_prose "$T/r.md" Beta "A body that opens
## Its Own Section
and so would end the block silently."
expect "prose that would open a new section is refused with 5" 5 "$RC"

echo "== insert, reorder, remove, rename =="
fixture "$T/r.md"
run roadmap_insert_at "$T/r.md" --before Gamma "Delta" planned docs/plans/delta.md "Why Delta exists."
expect "insert before a named phase succeeds" 0 "$RC"
expect "and lands in the right position" "Alpha Beta Delta Gamma" "$(grep '^## Phase:' "$T/r.md" | sed 's/^## Phase: //' | tr '\n' ' ' | sed 's/ $//')"
run roadmap_insert_at "$T/r.md" --before Gamma "Delta" planned docs/plans/delta.md "again"
expect "inserting a duplicate name is refused with 5" 5 "$RC"
run roadmap_insert_at "$T/r.md" --end "Epsilon" open docs/plans/e.md "urgent"
expect "inserting a second open phase is refused with 5" 5 "$RC"
run roadmap_reorder "$T/r.md" Delta --before Beta
expect "reorder succeeds" 0 "$RC"
expect "and the order is the new one" "Alpha Delta Beta Gamma" "$(grep '^## Phase:' "$T/r.md" | sed 's/^## Phase: //' | tr '\n' ' ' | sed 's/ $//')"
run roadmap_remove "$T/r.md" Delta
expect "remove without the caller's emptiness assertion is refused with 5" 5 "$RC"
contains "milestone" "$ERR" "and says the caller must confirm the milestone is empty"
run roadmap_remove "$T/r.md" Delta --milestone-empty
expect "remove with it succeeds" 0 "$RC"
expect "and the phase is gone" "Alpha Beta Gamma" "$(grep '^## Phase:' "$T/r.md" | sed 's/^## Phase: //' | tr '\n' ' ' | sed 's/ $//')"
run roadmap_rename "$T/r.md" Beta "Beta renamed"
expect "rename succeeds" 0 "$RC"
contains "Beta renamed" "$(cat "$T/r.md")" "and the heading carries the new name"
contains "milestone" "$ERR" "and it REPORTS the host consequence it cannot perform"
contains "no milestone rename" "$ERR" "naming the gap plainly: forge-lib has none"

echo "== the parse-back is verified, not asserted =="
fixture "$T/seam.md"
printf 'state: done\n' >> "$T/seam.md"   # a keyed line in the trailing non-phase section
cp "$T/seam.md" "$T/seambefore.md"
run roadmap_set_state "$T/seam.md" Gamma planned
expect "a keyed line the writer's extent cannot see but the parser can refuses with 3" 3 "$RC"
expect "and writes nothing" "" "$(diff "$T/seambefore.md" "$T/seam.md")"

echo "== the atomic write, in the shape forge-adapt-agent-skills.sh already tests =="
fixture "$T/r.md"; chmod 600 "$T/r.md"
run roadmap_set_state "$T/r.md" Alpha planned
expect "a 600 file keeps its mode" 600 "$(stat -c '%a' "$T/r.md" 2>/dev/null || stat -f '%Lp' "$T/r.md")"
fixture "$T/r.md"; chmod 444 "$T/r.md"
run roadmap_set_state "$T/r.md" Alpha planned
expect "a read-only file round-trips" 444 "$(stat -c '%a' "$T/r.md" 2>/dev/null || stat -f '%Lp' "$T/r.md")"
chmod 644 "$T/r.md"
fixture "$T/r.md"
RC=$( ( . "$LIB"; TMPDIR=/nonexistent roadmap_set_state "$T/r.md" Alpha planned >/dev/null 2>&1; echo $? ) )
expect "the temp file sits beside the target, not in TMPDIR" 0 "$RC"
fixture "$T/real.md"; ln -sf "$T/real.md" "$T/link.md"
run roadmap_set_state "$T/link.md" Alpha planned
expect "a symlinked roadmap is written through" 0 "$RC"
[ -L "$T/link.md" ] && ok "and survives as a symlink" || bad "the symlink was replaced by a regular file"

echo "== portability: this library installs onto a bash 3.2 laptop =="
# Scoped to the WRITE half. The parser's `set_lower` uses `${x,,}` on purpose, inside a
# BASH_VERSINFO branch with a `tr` fallback beside it, so a flat ban would fail the very shape the
# file already uses to stay portable. What this pins is that the primitives added no NEW one.
expect "no bash-4 case expansion in the write primitives" 0 "$(sed -n '/--- the WRITE primitives/,$p' "$LIB" | grep -cE '\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}')"
expect "no GNU readlink -f" 0 "$(grep -c 'readlink -f' "$LIB")"
expect "multi-line text reaches awk through ENVIRON, never -v" 0 "$(grep -cE "awk -v [A-Za-z_]+=\"\\\$(prose|text)" "$LIB")"

echo ""
echo "roadmap-lib tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
