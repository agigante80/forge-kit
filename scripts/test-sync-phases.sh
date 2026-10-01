#!/usr/bin/env bash
# Contract test for sync-phases.sh, which makes the host's milestones match docs/roadmap.md.
#
# Driven with a STUBBED forge-lib.sh beside a copy of the script, so the script sources the stub
# instead of the real transport. Nothing here touches a network or a real forge. Same seam as
# test-sync-labels.sh, which this script is deliberately modelled on: same exit codes, same
# never-deletes rule, same refusal on a malformed declaration.
set -uo pipefail
# #287: an inherited environment must not steer resolution. FORGE_LIB is consulted before anything
# else, and GIT_DIR/GIT_WORK_TREE (which git exports into hooks, and pre-push runs this suite) override
# the ceiling below. The set is complete for `rev-parse --show-toplevel` (git(1) and git-config(1)
# ENVIRONMENT, 2.43, #288): GIT_DISCOVERY_ACROSS_FILESYSTEM only lets a search cross a mount the
# ceiling still stops, GIT_CONFIG_COUNT and GIT_CONFIG_PARAMETERS act on a repository already found,
# which the ceiling prevents, and GIT_NAMESPACE scopes refs only. All three are ruled out, not missed.
# #269: FORGE_DRY_RUN joins the list, as test-forge-lib.sh does, because the stubs below now honour
# it: an inherited flag from a maintainer shell or the pre-push hook would steer every case. Each
# dry-run case passes it per call (`FORGE_DRY_RUN=1 run ...`).
unset FORGE_DRY_RUN FORGE_LIB GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
SRC="$ASSETS/sync-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
absent()   { if printf '%s' "$2" | grep -qiF -- "$1"; then bad "$3"; else ok "$3"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

# #287: the script under test resolves forge-lib.sh from $FORGE_LIB, beside itself, then the git root
# of its working directory. A case that hides the stub must find NO repository there, or it loads the
# real library and writes to the live host, which once created four milestones on this repository.
# $T is made ABSOLUTE (git ignores a relative ceiling, and mktemp under a relative TMPDIR returns a
# relative path), the ceiling is its parent, and gh/curl are shims that log and fail; the last
# assertion requires their log to be empty. Two steps, not `cd "$(mktemp -d)"`: a failed mktemp would
# make that `cd ""`, a no-op, and the EXIT trap would then remove the working directory.
# #288: three statements, trap before the cd, so a cd that fails after mktemp succeeded still
# removes the directory; the absolute path goes through T_ABS since a failed `T=$(...)` empties $T.
T=$(mktemp -d) || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$T"' EXIT
T_ABS=$(cd "$T" && pwd -P) || { echo "cannot resolve the temp dir"; exit 1; }
T=$T_ABS
export GIT_CEILING_DIRECTORIES="$(dirname "$T")"
mkdir -p "$T/shim"
for c in gh curl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/shim/live.log"\nexit 1\n' "$c" "$T" > "$T/shim/$c"
  chmod +x "$T/shim/$c"
done
PATH="$T/shim:$PATH"
mkdir -p "$T/docs/plans"
cp "$SRC" "$T/sync-phases.sh"
cp "$ASSETS/roadmap-lib.sh" "$T/roadmap-lib.sh" 2>/dev/null || true

cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
# These stubs model the real library under FORGE_DRY_RUN=1 (#269): the paginator returns `[]`
# (forge_api_paginate), a write logs nothing, and forge_milestone_close prints a `[dry-run]` line to
# stderr and returns 0 (forge-lib v28, #254). Without that fidelity no case could fail against
# sync-phases v5, which ignores the flag. STUB_LIST_FAIL=1 fails the list whatever the flag is: a
# stub that failed only under the flag would never fail after the fix, since the read then runs
# with the flag at 0.
forge_milestone_list() {
  [ "${STUB_LIST_FAIL:-0}" = 1 ] && return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[]'; else cat "$STUB_MILESTONES"; fi
}
forge_milestone_create() { [ "${FORGE_DRY_RUN:-0}" = 1 ] || printf 'CREATE %s\n' "$1" >> "$REQLOG"; }
forge_milestone_close() {
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[dry-run] close milestone %s on o/r\n' "$1" >&2; return 0; fi
  printf 'CLOSE %s\n' "$1" >> "$REQLOG"
}
STUB

goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }
goodplan A > "$T/docs/plans/a.md"

out=""; rc=0; REQLOG="$T/req.log"
run() {
  : > "$REQLOG"
  out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" REQLOG="$REQLOG" \
        bash ./sync-phases.sh "$@" 2>&1); rc=$?
}

roadmap() { cat > "$T/docs/roadmap.md"; }

echo "== creating a missing milestone =="
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[]' > "$T/ms.json"
run --check
expect "--check reports drift as exit 1" 1 "$rc"
contains "would create" "$out" "and says what it would do"
expect "and writes nothing" "" "$(cat "$REQLOG")"

run
expect "the default mode exits 0" 0 "$rc"
contains "CREATE A" "$(cat "$REQLOG")" "and creates the milestone"

echo "== an in-sync roadmap is a no-op =="
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
run --check
expect "--check on an in-sync repo exits 0" 0 "$rc"
run
expect "and the default mode writes nothing" "" "$(cat "$REQLOG")"

echo "== closing the milestone of a done phase =="
roadmap <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
run --check
expect "--check reports the close as drift" 1 "$rc"
contains "would close" "$out" "and says so"
run
contains "CLOSE A" "$(cat "$REQLOG")" "and closes it"

# The near-miss: an already-closed milestone for a done phase must not be closed again.
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
run
expect "an already-closed milestone is left alone" "" "$(cat "$REQLOG")"

echo "== a phase that went back to open is REPORTED, never reopened =="
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
run
expect "reopening is not attempted" "" "$(cat "$REQLOG")"
contains "closed" "$out" "and the disagreement is reported"

echo "== the milestone read is real under FORGE_DRY_RUN=1, the writes are not (#269) =="
# Dependency: #269 must not reach main before #254 (forge-lib v28) has: #254 closed, or its commit an
# ancestor of this one. The stub's close mirrors v28, so the close case below cannot prove it.
# Mutants, each shown to fail by the cases named:
#   "drop the clear (v5)": the --check positive, the done-phase --check, the closed-milestone note
#     and the dry-run close case (the suppressed-create case does NOT kill it: B is missing either
#     way and nothing logs CREATE under the flag).
#   "unscoped top-level clear" (`FORGE_DRY_RUN=0; MS=...`): the suppressed-create case, because the
#     write then sees the cleared flag and logs CREATE B.
# A second stub further down (the versioned copies under ~/.claude/plugins) ignores the flag; it is
# only used by the resolution cases, which never set it, and the unset at the top covers it.
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
FORGE_DRY_RUN=1 run --check
expect "dry-run --check on an in-sync host exits 0" 0 "$rc"
absent "would create milestone" "$out" "and does not report an existing milestone as missing"
printf '[]' > "$T/ms.json"
FORGE_DRY_RUN=1 run --check
expect "dry-run --check still reports genuine drift (exit 1)" 1 "$rc"
expect "with exactly the would-create line" 'would create milestone "A"' "$(printf '%s\n' "$out" | grep 'would create')"
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
STUB_LIST_FAIL=1 FORGE_DRY_RUN=1 run --check
expect "a failed list under the flag exits 2" 2 "$rc"
contains "could not list milestones" "$out" "and says so"
STUB_LIST_FAIL=1 run --check
expect "a failed list with the flag unset also exits 2" 2 "$rc"
run --check
expect "flag unset, in-sync roadmap: --check exits 0" 0 "$rc"
absent "could not list milestones" "$out" "and does not claim a list failure"
roadmap <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
FORGE_DRY_RUN=1 run --check
expect "dry-run --check on a done phase with an open milestone exits 1" 1 "$rc"
contains 'would close milestone "A"' "$out" "and reports the close"
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
FORGE_DRY_RUN=1 run --check
expect "dry-run --check on an open phase with a closed milestone exits 1" 1 "$rc"
contains 'phase "A" is open but its milestone is closed' "$out" "and reports the note"
# Writes stay held under the flag, and flow when it is off.
roadmap <<'MD'
## Phase: B
state: open
plan: docs/plans/a.md
MD
printf '[]' > "$T/ms.json"
FORGE_DRY_RUN=1 run
expect "a dry run with a missing milestone exits 0" 0 "$rc"
absent "CREATE B" "$(cat "$REQLOG")" "and logs no CREATE (the flag reached the write)"
run
expect "the same state with the flag unset exits 0" 0 "$rc"
expect "and logs exactly one CREATE B" 1 "$(grep -c '^CREATE B$' "$REQLOG")"
contains 'created milestone "B"' "$out" "and reports it"
# The #254 coupling: a done phase with an open milestone reaches forge_milestone_close for the
# first time under the flag, and must not turn a dry run into exit 4.
roadmap <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
FORGE_DRY_RUN=1 run
expect "a dry run closing a done phase exits 0, not 4" 0 "$rc"
absent "CLOSE A" "$(cat "$REQLOG")" "and logs no CLOSE"
contains "[dry-run] close milestone A on o/r" "$out" "and reports the would-close through the library's line"
absent "no milestone titled" "$out" "and never says the milestone is missing"

echo "== NEVER deletes =="
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"Ghost","state":"open"}]' > "$T/ms.json"
run
expect "an undeclared milestone does not fail the run" 0 "$rc"
contains "Ghost" "$out" "an undeclared milestone is reported"
absent "DELETE" "$(cat "$REQLOG")" "and is never deleted"

echo "== a malformed roadmap refuses the run and writes nothing =="
roadmap <<'MD'
## Phase: A
state: nonsense
MD
printf '[]' > "$T/ms.json"
run
expect "a malformed roadmap exits 3" 3 "$rc"
expect "and sends nothing" "" "$(cat "$REQLOG")"

# A partial sync is the drift this exists to end, so ONE bad block stops the whole file.
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: typo
MD
run
expect "one malformed block stops the whole file" 3 "$rc"
expect "and the good phase is not created either" "" "$(cat "$REQLOG")"

echo "== no roadmap at all is not an error =="
rm -f "$T/docs/roadmap.md"
run
expect "a project with no roadmap exits 0" 0 "$rc"
contains "no roadmap" "$out" "and says so rather than passing silently"

echo "== usage =="
roadmap <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[]' > "$T/ms.json"
run --nonsense
expect "an unknown flag refuses the run" 2 "$rc"
out=$(cd "$T" && bash ./sync-phases.sh --help 2>&1)
contains "sync-phases.sh" "$out" "--help prints the synopsis"
grep -q "sed -n '[0-9]*,[0-9]*p'" "$T/sync-phases.sh" \
  && bad "--help does not print a hardcoded line range" \
  || ok "--help does not print a hardcoded line range"

echo "== the shared parser library (#162) =="
# There is nothing left to compare: parse_roadmap is defined once and sourced. The byte-identity
# test this replaces was a mitigation, not a justification, and it could never have caught the
# interesting failure, which is two copies that are identical and both wrong.
defs=$(grep -lc '^parse_roadmap() {' "$ASSETS"/*.sh 2>/dev/null | wc -l | tr -d ' ')
expect "parse_roadmap is defined in exactly one asset" 1 "$defs"

mv "$T/roadmap-lib.sh" "$T/roadmap-lib.hidden"
run
expect "a missing roadmap-lib.sh refuses the run rather than degrading" 2 "$rc"
contains "roadmap-lib.sh" "$out" "and names what is missing"

mv "$T/roadmap-lib.hidden" "$T/roadmap-lib.sh"

# #161: the same for the cross-group dependency. HOME is redirected so the resolver's last resort,
# ~/.claude/plugins, finds nothing either.
mv "$T/forge-lib.sh" "$T/forge-lib.hidden"
mkdir -p "$T/nohome"
out=$(cd "$T" && HOME="$T/nohome" STUB_MILESTONES="$T/ms.json" REQLOG="$REQLOG" \
      bash ./sync-phases.sh 2>&1); rc=$?
expect "a missing forge-lib.sh refuses the run" 2 "$rc"
contains "forge-kit-devops" "$out" "and names the plugin group that provides it"
mv "$T/forge-lib.hidden" "$T/forge-lib.sh"

# #189: the last-resort search over ~/.claude/plugins ranks copies by `forge-lib-version` marker
# and prints the pick, instead of `head -1` over whatever order `find` returns. Same fixture shape
# as test-check-phases.sh: two stale v1 copies and one v9, the v9 one the only one that answers.
mv "$T/forge-lib.sh" "$T/forge-lib.hidden"
H="$T/home189"; rm -rf "$H"; mkdir -p "$H/.claude/plugins/cache/g/0.1.0" "$H/.claude/plugins/cache/g/0.2.0" "$H/.claude/plugins/marketplaces/m"
for d in cache/g/0.1.0 cache/g/0.2.0; do
  cat > "$H/.claude/plugins/$d/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 1
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list() { echo 'STALE COPY' >&2; return 2; }
STUB
done
cat > "$H/.claude/plugins/marketplaces/m/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 9
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list()   { cat "$STUB_MILESTONES"; }
forge_milestone_create() { echo "create $1" >> "$REQLOG"; }
forge_milestone_close()  { echo "close $1" >> "$REQLOG"; }
STUB
out=$(cd "$T" && HOME="$H" STUB_MILESTONES="$T/ms.json" REQLOG="$REQLOG" \
      bash ./sync-phases.sh --check 2>&1); rc=$?
[ "${out#*STALE COPY}" = "$out" ] && ok "the highest-marker copy is sourced, not a stale first hit" || bad "a stale copy ran: $out"
contains "marketplaces/m/forge-lib.sh" "$out" "and the run prints the path it chose"
contains "forge-lib-version: 9" "$out" "with its marker"
mv "$T/forge-lib.hidden" "$T/forge-lib.sh"

echo "== portability =="
code() { grep -v '^[[:space:]]*#' "$1"; }
n="$(code "$SRC" | grep -c ',,}')"
[ "${n:-0}" -le 1 ] && ok "the bash-4 lowercase expansion appears at most once" \
                    || bad "the bash-4 lowercase expansion appears $n times"
code "$SRC" | grep -q 'readlink -f' \
  && bad "avoids GNU-only readlink -f" || ok "avoids GNU-only readlink -f"
grep -qE '^# [a-z0-9-]+-version: [0-9]+$' "$SRC" \
  && ok "carries a version marker" || bad "carries a version marker"

if [ -s "$T/shim/live.log" ]; then
  bad "a suite case reached a live forge: $(head -3 "$T/shim/live.log" | tr '\n' ';')"
else
  ok "no live forge call (the gh/curl shim log is empty)"
fi

echo ""
echo "sync-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
