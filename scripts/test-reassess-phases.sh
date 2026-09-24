#!/usr/bin/env bash
# test-reassess-phases-version: 2
#
# Contract test for reassess-phases.sh (#249): the reshape script that answers whether the
# ROADMAP itself is still the right plan, one level above /phase review's single-phase question.
# Runs the real script as a subprocess against a stubbed forge-lib.sh, the same shape
# test-sync-phases.sh uses, extended with mutable ticket state so a merge/rename/delete's
# move-then-reread sequence is exercised for real rather than assumed.

set -uo pipefail
# #287: an inherited environment must not steer resolution. FORGE_LIB is consulted before anything
# else, and GIT_DIR/GIT_WORK_TREE (which git exports into hooks, and pre-push runs this suite) override
# the ceiling below.
unset FORGE_LIB GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
SRC="$ASSETS/reassess-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
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
T=$(mktemp -d) && T=$(cd "$T" && pwd -P) || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$(dirname "$T")"
mkdir -p "$T/shim"
for c in gh curl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/shim/live.log"\nexit 1\n' "$c" "$T" > "$T/shim/$c"
  chmod +x "$T/shim/$c"
done
PATH="$T/shim:$PATH"
mkdir -p "$T/docs/plans"
cp "$SRC" "$T/reassess-phases.sh"
cp "$ASSETS/roadmap-lib.sh" "$T/roadmap-lib.sh"
cp "$ASSETS/sync-phases.sh" "$T/sync-phases.sh"
cp "$ASSETS/check-phases.sh" "$T/check-phases.sh"

cat > "$T/forge-lib.sh" <<'STUB'
#!/usr/bin/env bash
# forge-lib-version: 1
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list() { cat "$STUB_MILESTONES"; }
forge_milestone_create() {
  printf 'CREATE %s\n' "$1" >> "$REQLOG"
  local maxid
  maxid=$(jq '[.[].id] | max // 0' "$STUB_MILESTONES")
  jq --arg t "$1" --argjson id "$((maxid + 1))" '. + [{id:$id, title:$t, state:"open"}]' \
    "$STUB_MILESTONES" > "$STUB_MILESTONES.tmp" && mv "$STUB_MILESTONES.tmp" "$STUB_MILESTONES"
}
forge_milestone_close() {
  printf 'CLOSE %s\n' "$1" >> "$REQLOG"
  jq --arg t "$1" 'map(if .title == $t then .state = "closed" else . end)' \
    "$STUB_MILESTONES" > "$STUB_MILESTONES.tmp" && mv "$STUB_MILESTONES.tmp" "$STUB_MILESTONES"
}
forge_issue_milestone() {
  local n="$1" title="$2"
  if [ -n "${FAIL_MOVE:-}" ] && [ "$n" = "$FAIL_MOVE" ]; then
    echo "stub: forced failure moving #$n" >&2
    return 1
  fi
  jq --arg n "$n" --arg t "$title" \
    '(.[] | select(.number == ($n|tonumber)) | .milestone) = $t' \
    "$STUB_ISSUES" > "$STUB_ISSUES.tmp" && mv "$STUB_ISSUES.tmp" "$STUB_ISSUES"
  printf 'MOVE %s %s\n' "$n" "$title" >> "$REQLOG"
}
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB

goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }
goodplan Zeta > "$T/docs/plans/zeta.md"
goodplan Alpha > "$T/docs/plans/alpha.md"
goodplan Gamma > "$T/docs/plans/gamma.md"

roadmap() { cat > "$T/docs/roadmap.md"; }

# The baseline every test starts from unless it says otherwise: two open buckets, one closed
# phase with a real plan (for the "done is never rewritten" refusals), one backlog phase (for
# --to backlog's resolution).
base_roadmap() {
  roadmap <<'MD'
## Phase: Alpha
state: planned

Alpha's prose.

## Phase: Beta
state: planned

Beta's prose.

## Phase: Zeta
state: done
plan: docs/plans/zeta.md

Zeta's prose, already closed.

## Phase: Cellar
state: backlog

Backlog phase, never closes.
MD
}
base_milestones() {
  cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Beta","state":"open"},
 {"id":3,"title":"Zeta","state":"closed"},{"id":4,"title":"Cellar","state":"open"}]
JSON
}
base_issues() { printf '[]' > "$T/iss.json"; }

out=""; rc=0; REQLOG="$T/req.log"
run() {
  : > "$REQLOG"
  out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" REQLOG="$REQLOG" \
        FAIL_MOVE="${FAIL_MOVE:-}" bash ./reassess-phases.sh "$@" 2>&1); rc=$?
}

# ---------------------------------------------------------------------------------------------
echo "== a rule-breaking reshape is refused whole, and nothing is written (AC2) =="
base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run reorder Ghost --end
expect "an unknown phase refuses" 5 "$rc"
contains "no phase named" "$out" "and names the problem"
expect "and the roadmap file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"
expect "and nothing was sent to the host" "" "$(cat "$REQLOG")"

echo "== reorder moves a phase (positive) =="
base_roadmap; base_milestones; base_issues
run reorder Beta --before Alpha
expect "reorder exits 0" 0 "$rc"
first="$(grep -m1 '^## Phase:' "$T/docs/roadmap.md")"
expect "Beta now comes first" "## Phase: Beta" "$first"

echo "== refocus rewrites prose (positive), never a done phase (negative, AC5-adjacent) =="
base_roadmap; base_milestones; base_issues
run refocus Alpha --prose "Alpha now covers different ground"
expect "refocus exits 0" 0 "$rc"
contains "Alpha now covers different ground" "$(cat "$T/docs/roadmap.md")" "the new prose landed"

before="$(cat "$T/docs/roadmap.md")"
run refocus Zeta --prose "trying to rewrite a closed phase"
expect "refocusing a done phase refuses" 5 "$rc"
contains "done" "$out" "and says why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== insert-and-open gate (AC7) =="
base_roadmap; base_milestones; base_issues
run insert Gamma --before Beta --state open --plan docs/plans/gamma.md --prose "New open work"
expect "insert with a real plan exits 0" 0 "$rc"
contains "## Phase: Gamma" "$(cat "$T/docs/roadmap.md")" "the phase landed"
contains "CREATE Gamma" "$(cat "$REQLOG")" "and its milestone was created"

base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run insert Gamma --end --state open --prose "no plan given"
expect "insert open with no plan refuses" 5 "$rc"
contains "rule 2" "$out" "citing the rule it would break"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

roadmap <<'MD'
## Phase: Alpha
state: open
plan: docs/plans/alpha.md

Alpha is already open.

## Phase: Beta
state: planned

Beta's prose.
MD
cat > "$T/ms.json" <<'JSON'
[{"id":1,"title":"Alpha","state":"open"},{"id":2,"title":"Beta","state":"open"}]
JSON
base_issues
before="$(cat "$T/docs/roadmap.md")"
run insert Gamma --end --state open --plan docs/plans/gamma.md --prose "a second open phase"
expect "inserting a second open phase refuses" 5 "$rc"
contains "already open" "$out" "citing rule 3's at-most-one-open"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== split moves named tickets into a new phase (positive), never out of done (negative) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run split Alpha --into AlphaB --move 10 --end
expect "split exits 0" 0 "$rc"
contains "## Phase: AlphaB" "$(cat "$T/docs/roadmap.md")" "the new phase landed"
contains "CREATE AlphaB" "$(cat "$REQLOG")" "its milestone was created"
contains "MOVE 10 AlphaB" "$(cat "$REQLOG")" "and the named ticket moved"
expect "the ticket now shows the new phase" "AlphaB" "$(jq -r '.[0].milestone' "$T/iss.json")"

base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Zeta"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
run split Zeta --into ZetaB --move 10 --end
expect "splitting a done phase refuses" 5 "$rc"
contains "done" "$out" "citing why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== merge composes under policy (positive), refuses on either side being done (negative, AC5) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run merge Alpha --into Beta --reason "consolidating scope"
expect "merge exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the losing phase is gone"
contains 'Merged "Alpha" in: consolidating scope' "$(cat "$T/docs/roadmap.md")" "the reason is recorded in the winner's prose"
contains "MOVE 10 Beta" "$(cat "$REQLOG")" "and its ticket moved to the winner"
contains "Alpha" "$(jq -c '.' "$T/ms.json")" "the loser's milestone is left on the host, not deleted"

base_roadmap; base_milestones; base_issues
before="$(cat "$T/docs/roadmap.md")"
run merge Zeta --into Beta --reason "should refuse"
expect "merging a done loser refuses" 5 "$rc"
contains "done" "$out" "citing why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

before="$(cat "$T/docs/roadmap.md")"
run merge Alpha --into Zeta --reason "should also refuse"
expect "merging into a done winner refuses" 5 "$rc"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== a partial move is reported, never swallowed, and a re-run resumes (AC and #249 scenario 6/7) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"},{"number":11,"milestone":"Alpha"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
FAIL_MOVE=11 run merge Alpha --into Beta --reason "test"
expect "the partial failure exits 4" 4 "$rc"
contains "MOVE 10 Beta" "$(cat "$REQLOG")" "the ticket that succeeded is logged"
absent "MOVE 11 Beta" "$(cat "$REQLOG")" "and the one that failed never logged as moved"
contains "moved so far: 10" "$out" "the report names what moved"
contains "still to move: 11" "$out" "and what did not"
expect "the file half was never touched" "$before" "$(cat "$T/docs/roadmap.md")"
expect "ticket 10 already shows the winner on the host" "Beta" "$(jq -r '.[] | select(.number==10) | .milestone' "$T/iss.json")"

FAIL_MOVE="" run merge Alpha --into Beta --reason "test"
expect "the re-run completes" 0 "$rc"
absent "MOVE 10 Beta" "$(cat "$REQLOG")" "and does not repeat the already-succeeded move"
contains "MOVE 11 Beta" "$(cat "$REQLOG")" "only the remaining ticket moves"
merges_recorded="$(grep -c 'Merged "Alpha" in: test' "$T/docs/roadmap.md" || true)"
expect "the merge reason appears exactly once, not duplicated by the retry" 1 "$merges_recorded"

echo "== rename leaves the old milestone emptied, never deleted (AC3/AC8-adjacent) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run rename Alpha NewAlpha
expect "rename exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the old heading is gone"
contains "## Phase: NewAlpha" "$(cat "$T/docs/roadmap.md")" "the new heading landed"
expect "the ticket followed the rename" "NewAlpha" "$(jq -r '.[0].milestone' "$T/iss.json")"
contains "emptied, not deleted" "$out" "the old milestone is reported emptied rather than removed"
contains "Alpha" "$(jq -c '.' "$T/ms.json")" "and it is still present on the host under its old title"

echo "== delete relocates open tickets before removing the block (AC10, --to backlog resolves by state) =="
base_roadmap; base_milestones
printf '[{"number":10,"milestone":"Alpha"}]' > "$T/iss.json"
run delete Alpha --to backlog
expect "delete with a destination exits 0" 0 "$rc"
absent "## Phase: Alpha" "$(cat "$T/docs/roadmap.md")" "the phase is removed"
expect "the ticket landed in the phase whose state is backlog" "Cellar" "$(jq -r '.[0].milestone' "$T/iss.json")"

base_roadmap; base_milestones
printf '[{"number":20,"milestone":"Beta"}]' > "$T/iss.json"
before="$(cat "$T/docs/roadmap.md")"
run delete Beta
expect "deleting a phase with open tickets and no destination refuses" 5 "$rc"
contains "nowhere for them" "$out" "and says why"
expect "and the file is untouched" "$before" "$(cat "$T/docs/roadmap.md")"

echo "== structural: missing libraries, a malformed roadmap, --help, an unknown op =="
base_roadmap; base_milestones; base_issues
mv "$T/roadmap-lib.sh" "$T/roadmap-lib.hidden"
run reorder Alpha --end
expect "a missing roadmap-lib.sh refuses" 2 "$rc"
contains "roadmap-lib.sh" "$out" "and names what is missing"
mv "$T/roadmap-lib.hidden" "$T/roadmap-lib.sh"

mv "$T/forge-lib.sh" "$T/forge-lib.hidden"
mkdir -p "$T/nohome"
out=$(cd "$T" && HOME="$T/nohome" STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
      REQLOG="$REQLOG" bash ./reassess-phases.sh reorder Alpha --end 2>&1); rc=$?
expect "a missing forge-lib.sh refuses" 2 "$rc"
contains "forge-kit-devops" "$out" "and names the plugin group that provides it"
mv "$T/forge-lib.hidden" "$T/forge-lib.sh"

roadmap <<'MD'
## Phase: A
state: nonsense
MD
run reorder A --end
expect "a malformed roadmap exits 3" 3 "$rc"
expect "and nothing is sent to the host" "" "$(cat "$REQLOG")"

out=$(cd "$T" && bash ./reassess-phases.sh --help 2>&1)
contains "reassess-phases.sh" "$out" "--help prints the synopsis"

base_roadmap; base_milestones; base_issues
run bogus-op Alpha
expect "an unknown op is a usage error" 2 "$rc"

echo "== portability =="
code() { grep -v '^[[:space:]]*#' "$1"; }
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
echo "reassess-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
