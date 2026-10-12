#!/usr/bin/env bash
# Contract test for review-mechanics.sh (#272): the mechanical half of /phase review steps 1 to 4.
#
# HOW. A copy of the script sits in a bin directory beside a STUB forge-lib.sh (the transport, so no
# network and no token), a stub check-phases.sh whose stdout, stderr and rc each case chooses, and
# the real roadmap-lib.sh. Each case runs it as a subprocess from a throwaway git repository whose
# history is the fixture: a plan added in commit P, then commits naming tickets in their message or
# only in their diff. The stub's issue listing honours its state argument, so a script reading open
# issues only loses the closed ticket, and it logs every call so the suite can see nothing writes.
#
# MUTANTS (the last section; each must fail its named case and must not crash, #330/#360): the
# `([^0-9]|$)` boundary dropped from both searches; its end-of-line half `|$` dropped from both;
# the -S half dropped; forge_issue_list all swapped back to forge_issue_milestone_list; the
# superseded marker matched on any line rather than the first; the derived range written `P..HEAD`;
# an empty override treated as unset; a failed listing's cause dropped from its message; a shell
# trace injected into the missing-roadmap refusal (caught by the refusal log, see run()).
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
REAL="$ASSETS/review-mechanics.sh"
MARK='## Superseded body (phase review)'

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

[ -f "$REAL" ] || { echo "missing script: $REAL"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE FORGE_LIB ROADMAP_LIB CHECK_PHASES FORGE_DRY_RUN
TAB="$(printf '\t')"

# The minimum is READ from the script, so no number is restated here.
MIN=$(sed -n 's/^FORGE_LIB_MIN=\([0-9]*\)$/\1/p' "$REAL")
[ -n "$MIN" ] || { echo "no FORGE_LIB_MIN constant in $REAL"; exit 1; }

# stub_lib <version>: the transport. state `all` returns every fixture issue; anything else filters.
stub_lib() {
  cat <<LIB
# forge-lib-version: $1
forge_issue_list() {
  echo "issue_list \$1" >> "\$CALLS"
  [ -n "\${FAIL_LIST:-}" ] && { printf '%s\n' "\$FAIL_LIST" >&2; return 22; }
  [ "\${FORGE_DRY_RUN:-0}" = 1 ] && return 0
  case "\${1:-open}" in all) cat "\$FX/issues.json" ;; *) jq --arg s "\${1:-open}" 'map(select(.state == \$s))' "\$FX/issues.json" ;; esac
}
forge_issue_milestone_list() {
  echo "milestone_list" >> "\$CALLS"
  jq 'map(select(.state == "open"))' "\$FX/issues.json"
}
forge_issue_comments() {
  echo "comments \$1" >> "\$CALLS"
  [ -n "\${FAIL_COMMENTS:-}" ] && { printf '%s\n' "\$FAIL_COMMENTS" >&2; return 22; }
  [ "\${FORGE_DRY_RUN:-0}" = 1 ] && return 0
  if [ -f "\$FX/c\$1.json" ]; then cat "\$FX/c\$1.json"; else echo '[]'; fi
}
LIB
}
# bin <dir> [script]: the script (or a mutant), the stub transport, the stub guard, the real parser.
bin() {
  mkdir -p "$1"; cp "${2:-$REAL}" "$1/review-mechanics.sh"; cp "$ASSETS/roadmap-lib.sh" "$1/"
  stub_lib "$MIN" > "$1/forge-lib.sh"
  printf '%s\n' '#!/usr/bin/env bash' '[ -n "${CP_OUT:-}" ] && printf "%s\n" "$CP_OUT"' \
    '[ -n "${CP_ERR:-}" ] && printf "%s\n" "$CP_ERR" >&2' 'exit "${CP_RC:-0}"' > "$1/check-phases.sh"
}
BIN="$T/bin"; bin "$BIN"

FX="$T/fx"; mkdir -p "$FX"
# issue <n> <state> <milestone> <title> <body>
issues=""
issue() { issues="$issues$(jq -nc --argjson n "$1" --arg s "$2" --arg m "$3" --arg t "$4" --arg b "$5" \
  '{number: $n, state: $s, title: $t, body: $b, milestone: (if $m == "" then null else {title: $m} end)}')
"; }
# comments <n> <id> <text> [<id> <text>...]
comments() { local n="$1" a="[]"; shift; while [ $# -gt 0 ]; do
  a=$(jq -c --argjson i "$1" --arg b "$2" '. + [{id: $i, body: $b}]' <<< "$a"); shift 2; done; printf '%s\n' "$a" > "$FX/c$n.json"; }
M="Alpha one"
issue 5 open "$M" "five" "B5"
issue 6 closed "$M" "six" "B6"
issue 7 open "$M" "seven" "B7"
issue 8 open "$M" "eight" "B8"
issue 9 closed "Other" "nine" "B9"
issue 10 open "$M" "ten" "B10"
issue 11 open "$M" "eleven" "$(printf 'keep\nme\n\n')"
issue 12 open "$M" "twelve" "$(printf 'keep\nme!')"
issue 13 open "$M" "$(printf 'x $(touch pwned) `touch pwned2` a\tb\nc')" "B13"
issue 27 open "$M" "twenty-seven" "B27"
printf '[%s]\n' "$(printf '%s' "$issues" | paste -sd, -)" > "$FX/issues.json"
comments 7 71 "$(printf '%s\nold body' "$MARK")" 72 "Shipped in abc1234"
comments 10 101 "$(printf 'Previously:\nx\n%s\nold' "$MARK")"
# A body ending in newlines: the comparison must keep them (a shell variable would strip them).
B11="$(printf 'keep\nme\n\nX')"; B11="${B11%X}"
comments 11 111 "$MARK
$B11"
comments 12 121 "$(printf '%s\nkeep\nme' "$MARK")"
comments 13 131 "$(printf 'line one\tTAB\nline two $(touch pwned3)')"
# issue 11's body as served must be byte-equal to $B11: rebuild it with jq from the same string.
jq --arg b "$B11" 'map(if .number == 11 then .body = $b else . end)' "$FX/issues.json" > "$FX/i.tmp" && mv "$FX/i.tmp" "$FX/issues.json"

# newrepo <kind>: the history fixture; sets R and P (the plan's add commit).
commit() { ( cd "$R" && git add -A && git commit -qm "$1" ) >/dev/null 2>&1; }
newrepo() {
  R=$(mktemp -d "$T/repo.XXXXXX")
  ( cd "$R" && git init -q . && git config user.email t@t.invalid && git config user.name t && git config commit.gpgsign false )
  mkdir -p "$R/docs/plans"
  printf '## Phase: %s\nstate: open\nplan: docs/plans/alpha.md\n\n## Phase: Other\nstate: planned\n' "$M" > "$R/docs/roadmap.md"
  case "$1" in
    first) printf '# alpha\n' > "$R/docs/plans/alpha.md"; commit "plan (#5)"; P=$(git -C "$R" rev-parse HEAD); return ;;
    noplan) commit "roadmap only"; P=""; return ;;
  esac
  printf 'x\n' > "$R/README.md"; commit "init, before the phase (#5)"
  printf '# alpha\n' > "$R/docs/plans/alpha.md"; commit "plan for the phase (#5)"; P=$(git -C "$R" rev-parse HEAD)
  printf 'a\n' > "$R/a"; commit "feat: x (#7)"; A=$(git -C "$R" rev-parse HEAD)
  printf 'b\n' > "$R/b"; commit "fix: y (#7)"; B=$(git -C "$R" rev-parse HEAD)
  printf -- '- thing (#7)\n' > "$R/CHANGELOG.md"; commit "docs: changelog"; C=$(git -C "$R" rev-parse HEAD)
  printf 'd\n' > "$R/d"; commit "fix #80"
  printf 'see #80\n' > "$R/e"; commit "notes"
  printf 'f\n' > "$R/f"; commit "feat: z (#272)"
  # The end-of-line half of the boundary: a SUBJECT ending in #7, and a diff line ending in #7 whose
  # message names nothing. Without `|$` neither matches.
  printf 'h\n' > "$R/h"; commit "refactor: tidy #7"; H=$(git -C "$R" rev-parse HEAD)
  printf 'closes #7\n' > "$R/i"; commit "docs: notes"; I=$(git -C "$R" rev-parse HEAD)
  printf 'g\n' > "$R/g"; commit "chore: tidy (#7)"; G=$(git -C "$R" rev-parse HEAD)
}
# run [args]: the script from the fixture repo; sets out, err, rc. RUN_BIN picks a mutant's bin.
# Every refusal's stderr (rc 2) is appended to $T/refusals, so one grep covers them all.
: > "$T/refusals"
TRACE_RE='line [0-9]+:|syntax error|command not found'
run() { : > "$T/calls"
  out=$(cd "$R" && CALLS="$T/calls" FX="$FX" bash "${RUN_BIN:-$BIN}/review-mechanics.sh" "$@" 2>"$T/err"); rc=$?
  err=$(cat "$T/err"); [ "$rc" = 2 ] && cat "$T/err" >> "$T/refusals"; return 0; }
rows() { printf '%s\n' "$out" | awk -F'\t' -v k="$1" '$1 == k'; }
has() { grep -qxF -- "$1" <<< "$out"; }
count() { printf '%s\n' "$out" | awk -F'\t' -v k="$1" -v n="$2" '$1 == k && $2 == n { c++ } END { print c + 0 }'; }

newrepo full

echo "== a full run: every row kind, rc 0 =="
run "$M"
expect "exit 0 when check-phases.sh exits 0" 0 "$rc"
has "forge_lib${TAB}$MIN" && ok "the forge_lib row names the version found" || bad "no forge_lib row: $(rows forge_lib)"
has "check_phases${TAB}rc${TAB}0" && ok "the check_phases rc row" || bad "check_phases rc row: $(rows check_phases)"
has "range${TAB}$P^..HEAD${TAB}derived" && ok "the range is derived as <plan add sha>^..HEAD, its kind in its own field" || bad "range: $(rows range)"
has "ticket${TAB}5${TAB}open${TAB}five" && has "ticket${TAB}6${TAB}closed${TAB}six" \
  && ok "open #5 and closed #6 both read (forge_issue_list all, not the open-only listing)" || bad "tickets: $(rows ticket)"
[ "$(count ticket 9)" = 0 ] && ok "closed #9 in another milestone is not read" || bad "#9 was read"
grep -qx 'issue_list all' "$T/calls" && ! grep -q milestone_list "$T/calls" && ok "the listing asked for state all" || bad "calls: $(cat "$T/calls")"
expect "the ticket rows come in number order" "5 6 7 8 10 11 12 13 27" "$(rows ticket | cut -f2 | paste -sd' ' -)"

echo "== step 2: superseded bodies are not history =="
[ "$(count comment 7)" = 1 ] && has "comment${TAB}7${TAB}72${TAB}Shipped in abc1234" \
  && ok "#7: exactly one comment row, carrying 'Shipped in abc1234'" || bad "#7 comments: $(rows comment)"
grep -q 'old body' <<< "$out" && bad "a row carries the superseded 'old body'" || ok "no row carries the superseded 'old body'"
has "superseded${TAB}7${TAB}71" && ok "the marked comment is a superseded row" || bad "superseded: $(rows superseded)"
has "comment${TAB}10${TAB}101${TAB}Previously: x $MARK old" && [ "$(count superseded 10)" = 0 ] && [ "$(count comment 10)" = 1 ] \
  && ok "a marker below the first line stays history: a comment row, no superseded row, count equals comments" || bad "#10: $(rows comment | grep "${TAB}10${TAB}")"

echo "== step 2: the already-preserved comparison =="
has "preserved${TAB}11${TAB}111" && ok "a body equal byte for byte to a marked comment's text after line 1 is preserved (trailing newlines kept)" || bad "#11 preserved: $(rows preserved)"
[ "$(count preserved 12)" = 0 ] && has "superseded${TAB}12${TAB}121" && ok "a body one byte different is not preserved" || bad "#12 preserved: $(rows preserved)"
[ "$(count preserved 7)" = 0 ] && ok "a marked comment holding another body is not preserved" || bad "#7 preserved"

echo "== step 3: commit rows =="
expect "#7: A, B, C (named only in its diff), H and I (#7 at end of line) and G, oldest first, no duplicates" \
  "$A $B $C $H $I $G" "$(rows commit | awk -F'\t' '$2 == 7 { print $3 }' | paste -sd' ' -)"
has "commit${TAB}7${TAB}$A${TAB}feat: x (#7)" && ok "a commit row carries the subject" || bad "commit subject: $(rows commit | head -2)"
[ "$(count commit 8)" = 1 ] && has "commit${TAB}8${TAB}none" && ok "#8: one row reading none; neither #80 commit is attributed to it" || bad "#8: $(rows commit | grep "${TAB}8${TAB}")"
has "commit${TAB}7${TAB}$H${TAB}refactor: tidy #7" && has "commit${TAB}7${TAB}$I${TAB}docs: notes" \
  && ok "#7 at the end of a subject and at the end of an added line both match (the |\$ half)" || bad "end of line: $(rows commit | grep "${TAB}7${TAB}")"
has "commit${TAB}27${TAB}none" && ok "#27 does not match the #272 commit" || bad "#27: $(rows commit | grep "${TAB}27${TAB}")"
expect "#5: the plan's add commit is in the range, the commit before it is not" "$P" "$(rows commit | awk -F'\t' '$2 == 5 { print $3 }' | paste -sd' ' -)"

echo "== rows, never a verdict =="
grep -qwE 'PASS|aligned|done' <<< "$out" && bad "a verdict word in stdout" || ok "no PASS, aligned or done in stdout"
S=$(rows summary)
expect "the summary counts rows by kind" "summary${TAB}forge_lib=1${TAB}check_phases=1${TAB}range=1${TAB}ticket=9${TAB}comment=3${TAB}superseded=3${TAB}preserved=1${TAB}commit=14" "$S"
[ "$(printf '%s\n' "$out" | tail -1)" = "$S" ] && ok "the summary is the last row" || bad "summary not last"
printf '%s\n' "$out" | awk -F'\t' '$1 !~ /^(forge_lib|check_phases|range|ticket|comment|superseded|preserved|commit|summary)$/ { b = 1 } END { exit b }' \
  && ok "stdout carries rows only" || bad "a non-row line on stdout"
first="$out"; run "$M"; [ "$out" = "$first" ] && ok "a second run over an unchanged tree prints the same rows" || bad "second run differs"

echo "== untrusted ticket text =="
[ ! -e "$R/pwned" ] && [ ! -e "$R/pwned2" ] && [ ! -e "$R/pwned3" ] && ok "nothing in a title or comment executes" || bad "a pwned file exists"
[ "$(count ticket 13)" = 1 ] && [ "$(count comment 13)" = 1 ] && ok "#13: one ticket row and one comment row despite tabs and newlines" || bad "#13 rows: $(printf '%s\n' "$out" | grep "${TAB}13${TAB}")"
[ "$(rows ticket | awk -F'\t' '$2 == 13 { print NF }')" = 4 ] && ok "a tab in a title cannot add a field" || bad "#13 field count"

echo "== it writes nothing =="
st=$(git -C "$R" status --porcelain); run "$M"
expect "git status is unchanged by a run" "$st" "$(git -C "$R" status --porcelain)"
bad_calls=$(grep -vE '^(issue_list all|comments [0-9]+)$' "$T/calls")
[ -z "$bad_calls" ] && ok "the transport saw reads only" || bad "unexpected calls: $bad_calls"
for w in 'claude ' 'CLAUDE_PLUGIN_ROOT' forge_issue_edit 'forge_issue_comment ' forge_body_ roadmap_set_ forge_issue_close forge_issue_milestone; do
  grep -qF -- "$w" <<< "$(grep -v '^[[:space:]]*#' "$REAL")" && bad "the script names '$w'" || ok "no code line of the script names '$w'"
done
FORGE_TOKEN=SENTINEL-272 GH_TOKEN=SENTINEL-272 run "$M"
grep -q SENTINEL-272 <<< "$out$err" && bad "the token sentinel leaked" || ok "a token in the environment reaches neither stream"
FORGE_DRY_RUN=1; export FORGE_DRY_RUN; run "$M"; unset FORGE_DRY_RUN
[ "$out" = "$first" ] && ok "an exported FORGE_DRY_RUN=1 cannot fake the reads (scoped to 0, #306)" || bad "FORGE_DRY_RUN=1 changed the rows (rc $rc)"

echo "== step 1: the guard's lines, both streams, and the read goes on =="
CP_RC=1 CP_OUT='rule 4: phase "Alpha one" is done but holds 1 open ticket(s).' \
  CP_ERR='check-phases: the host could not be reached, so rules 1, 3 and 4 were SKIPPED.' run "$M"
expect "check-phases.sh exiting 1 makes the run exit 1" 1 "$rc"
has "check_phases${TAB}rc${TAB}1" && has "check_phases${TAB}stdout${TAB}rule 4: phase \"Alpha one\" is done but holds 1 open ticket(s)." \
  && ok "its stdout line is a check_phases row, verbatim" || bad "cp stdout: $(rows check_phases)"
has "check_phases${TAB}stderr${TAB}check-phases: the host could not be reached, so rules 1, 3 and 4 were SKIPPED." \
  && ok "its stderr (the SKIPPED note) is a check_phases row too" || bad "cp stderr: $(rows check_phases)"
[ "$(rows ticket | wc -l | tr -d ' ')" = 9 ] && ok "and every ticket row is still emitted" || bad "ticket rows after rc 1: $(rows ticket | wc -l)"

echo "== the range: derived, refused, overridden =="
newrepo first
run "$M"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'docs/plans/alpha.md' <<< "$err" && grep -q -- '--range is required' <<< "$err" \
  && ok "a first-commit plan exits 2, stdout empty, stderr names the plan and asks for --range" || bad "first-commit: rc $rc out '$out' err '$err'"
run "$M" --range "$P..HEAD"
[ "$rc" = 0 ] && has "range${TAB}$P..HEAD${TAB}override" && ok "--range overrides, kind override in its own field" || bad "override: rc $rc $(rows range) $err"
run "$M" --range "nonexistent..HEAD"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "'nonexistent'" <<< "$err" && ok "--range with a bad ref exits 2 naming it, no commit row" || bad "bad ref: rc $rc out '$out' err '$err'"
run "$M" --range "$P...HEAD"; [ "$rc" = 2 ] && [ -z "$out" ] && grep -q '...HEAD' <<< "$err" && ok "a three-dot --range exits 2 naming it" || bad "three dots: rc $rc '$err'"
run "$M" --range "$P"; [ "$rc" = 2 ] && [ -z "$out" ] && ok "a --range without .. exits 2" || bad "no dots: rc $rc"
run "$M" --range "--all..HEAD"; [ "$rc" = 2 ] && [ -z "$out" ] && ok "a --range end that is an option exits 2" || bad "option ref: rc $rc"
run "$M" --range; [ "$rc" = 2 ] && grep -q -- '--range needs a value' <<< "$err" && ok "--range with no value exits 2" || bad "no value: rc $rc '$err'"
newrepo noplan
run "$M"; [ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'no commit added the plan docs/plans/alpha.md' <<< "$err" && grep -q -- '--range is required' <<< "$err" \
  && ok "a plan no commit added exits 2 naming it and asking for --range" || bad "no add commit: rc $rc '$err'"
run "Other"; [ "$rc" = 2 ] && grep -q "names no plan" <<< "$err" && ok "a phase with no plan line exits 2 asking for --range" || bad "no plan line: rc $rc '$err'"

echo "== malformed input =="
newrepo full
run; [ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'a phase name is required' <<< "$err" && ok "no phase argument exits 2" || bad "no phase: rc $rc '$err'"
run "Nope"; [ "$rc" = 2 ] && grep -q "phase 'Nope' is not" <<< "$err" && ok "an unknown phase exits 2 naming it" || bad "unknown phase: rc $rc '$err'"
run "$M" --bogus; [ "$rc" = 2 ] && grep -q 'unknown argument: --bogus' <<< "$err" && ok "an unknown flag exits 2" || bad "unknown flag: rc $rc"
mv "$R/docs/roadmap.md" "$T/rm.bak"; run "$M"; mv "$T/rm.bak" "$R/docs/roadmap.md"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'no roadmap' <<< "$err" && ok "a missing roadmap exits 2" || bad "no roadmap: rc $rc '$err'"
issues_bak="$FX/issues.json.bak"; cp "$FX/issues.json" "$issues_bak"; printf 'not json\n' > "$FX/issues.json"; run "$M"; mv "$issues_bak" "$FX/issues.json"
[ "$rc" = 2 ] && [ -z "$out" ] && ok "an unreadable issue listing exits 2 with stdout empty, never an empty phase" || bad "bad listing: rc $rc out '$out'"
FAIL_LIST='forge-lib: HTTP 401 Unauthorized (GET /repos/o/r/issues)' run "$M"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'could not list the repository.s issues: forge-lib: HTTP 401 Unauthorized' <<< "$err" \
  && ok "a failed listing (rc 22, a 401 on stderr) exits 2, stdout empty, the 401 line in the message" || bad "401 listing: rc $rc out '$out' err '$err'"
FAIL_COMMENTS='forge-lib: HTTP 401 Unauthorized (GET comments)' run "$M"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'could not read the comments of #5: forge-lib: HTTP 401 Unauthorized' <<< "$err" \
  && ok "a failed comment read exits 2, stdout empty, the 401 line in the message" || bad "401 comments: rc $rc out '$out' err '$err'"

echo "== an empty milestone =="
cp "$FX/issues.json" "$T/i.bak"; jq 'map(select(.milestone.title != "Alpha one"))' "$T/i.bak" > "$FX/issues.json"; run "$M"; mv "$T/i.bak" "$FX/issues.json"
expect "only forge_lib, check_phases, range and summary rows" "forge_lib check_phases range summary" "$(printf '%s\n' "$out" | cut -f1 | paste -sd' ' -)"

echo "== library resolution stops before sourcing (#267 F7) =="
FORGE_LIB= run "$M"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q 'forge-lib.sh' <<< "$err" && ! grep -qE 'source:|No such file or directory' <<< "$err" \
  && ok "an empty FORGE_LIB exits 2 naming forge-lib.sh, no raw source error" || bad "empty FORGE_LIB: rc $rc '$err'"
ROADMAP_LIB="$T/nonexistent/roadmap-lib.sh" run "$M"
[ "$rc" = 2 ] && grep -q 'roadmap-lib.sh' <<< "$err" && ! grep -qE 'source:|No such file or directory' <<< "$err" \
  && ok "a ROADMAP_LIB that is not a file exits 2 naming roadmap-lib.sh" || bad "bad ROADMAP_LIB: rc $rc '$err'"
CHECK_PHASES= run "$M"; [ "$rc" = 2 ] && grep -q 'check-phases.sh' <<< "$err" && ok "an empty CHECK_PHASES exits 2 naming check-phases.sh" || bad "empty CHECK_PHASES: rc $rc '$err'"
LOW="$T/low"; mkdir -p "$LOW"; stub_lib $((MIN - 1)) > "$LOW/forge-lib.sh"
FORGE_LIB="$LOW/forge-lib.sh" run "$M"
[ "$rc" = 2 ] && [ -z "$out" ] && grep -q "version $((MIN - 1)); this needs $MIN" <<< "$err" && ok "a forge-lib one below FORGE_LIB_MIN exits 2 naming both" || bad "low forge-lib: rc $rc '$err'"
stub_lib "$MIN" > "$LOW/forge-lib.sh"; FORGE_LIB="$LOW/forge-lib.sh" run "$M"
[ "$rc" = 0 ] && has "forge_lib${TAB}$MIN" && ok "a forge-lib exactly at FORGE_LIB_MIN, via FORGE_LIB, is used" || bad "at-min forge-lib: rc $rc '$err'"
SOLO="$T/solo"; mkdir -p "$SOLO"; cp "$REAL" "$SOLO/"
( cd "$R" && bash "$SOLO/review-mechanics.sh" "$M" ) > "$T/o" 2> "$T/e"; rc=$?
[ "$rc" = 2 ] && [ ! -s "$T/o" ] && grep -q 'forge-lib.sh not found' "$T/e" && ok "alone, with nothing beside it, it exits 2 naming forge-lib.sh" || bad "solo: rc $rc '$(cat "$T/e")'"
cat "$T/e" >> "$T/refusals"

echo "== every refusal in this suite is a named message =="
nref=$(grep -c '^review-mechanics: ' "$T/refusals")
[ "$nref" -ge 20 ] && ok "the refusal log holds every refusal above ($nref messages)" || bad "refusal log holds $nref messages"
tr=$(grep -m1 -E "$TRACE_RE" "$T/refusals")
[ -z "$tr" ] && ok "no refusal above carries a shell trace" || bad "a shell trace on a refusal's stderr: $tr"

echo "== mutants, each must fail its named case =="
. "$ROOT/scripts/mutant-crash.sh"
# rm_live: a mutant build still runs the full fixture to rc 0 (so a kill is never a crash).
rm_live() { local o; o=$(cd "$R" && CALLS="$T/calls" FX="$FX" bash "$MB/review-mechanics.sh" "$M" 2>/dev/null) && [ -n "$o" ]; }
# subst <text> <old> <new>: every literal <old> replaced by <new>. The expansion sits in an
# assignment, since bash 3.2 keeps a quoted replacement's quotes inside double quotes, and the
# replacement stays quoted, since bash 5.2's patsub_replacement reads a bare & as the match (#480).
subst() { local r; r=${1//"$2"/"$3"}; printf '%s' "$r"; }
# The shape rows: a fixture a quoted replacement (3.2) and a bare one (5.2) both get wrong.
expect "the mutant build's substitution turns a OLD & b into a N&W & b" 'a N&W & b' "$(subst 'a OLD & b' OLD 'N&W')"
# mutant <name> <old> <new> <check-fn>: <old> must occur exactly once; the check must FAIL.
mutant() {
  local name="$1" old="$2" new="$3" fn="$4" c held=0 why  # [live] as $5
  c="$(cat "$REAL"; printf x)"; c="${c%x}"
  case "$c" in *"$old"*"$old"*) bad "mutant $name: anchor occurs twice"; return ;; *"$old"*) ;; *) bad "mutant $name: anchor not found"; return ;; esac
  MB="$T/mut"; rm -rf "$MB"; subst "$c" "$old" "$new" > "$T/mut.sh"; bin "$MB" "$T/mut.sh"
  RUN_BIN="$MB" "$fn" && held=1
  # live: the kill IS a bash diagnostic on the case's stderr, so liveness gets its own log.
  if [ "${5:-}" = live ]; then why=$(mutant_crash_reason_live "$T/mut.sh" rm_live)
  else why=$(mutant_crash_reason "$T/mut.sh" "$T/err" rm_live); fi
  if [ -n "$why" ]; then bad "mutant $name crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant $name survived"
  else ok "mutant $name dies"; fi
}
chk_boundary() { run "$M"; [ "$(count commit 8)" = 1 ] && has "commit${TAB}8${TAB}none" && has "commit${TAB}27${TAB}none"; }
chk_pickaxe()  { run "$M"; [ "$(rows commit | awk -F'\t' '$2 == 7 { print $3 }' | paste -sd' ' -)" = "$A $B $C $H $I $G" ]; }
chk_closed()   { run "$M"; has "ticket${TAB}6${TAB}closed${TAB}six"; }
chk_anchor()   { run "$M"; [ "$(count superseded 10)" = 0 ] && [ "$(count comment 10)" = 1 ]; }
chk_range()    { run "$M"; [ "$(rows commit | awk -F'\t' '$2 == 5 { print $3 }')" = "$P" ]; }
chk_empty()    { FORGE_LIB= run "$M"; [ "$rc" = 2 ] && ! grep -qE 'source:|No such file or directory' <<< "$err"; }
chk_eol()      { run "$M"; has "commit${TAB}7${TAB}$H${TAB}refactor: tidy #7" && has "commit${TAB}7${TAB}$I${TAB}docs: notes"; }
chk_cause()    { FAIL_LIST='forge-lib: HTTP 401 Unauthorized' run "$M"; [ "$rc" = 2 ] && grep -q 'HTTP 401' <<< "$err"; }
# The refusal log's own check, on one refusal: a trace there must not pass as a named message.
chk_trace()    { : > "$T/refusals"; mv "$R/docs/roadmap.md" "$T/rm.bak"; run "$M"; mv "$T/rm.bak" "$R/docs/roadmap.md"
  [ "$rc" = 2 ] && ! grep -qE "$TRACE_RE" "$T/refusals"; }
grep -qw subst <<< "$(declare -f mutant)" && ok "mutant builds its mutant through subst" || bad "mutant no longer calls subst"
mutant "message boundary dropped" '#$N([^0-9]|\$)" --format=%H "$RANGE" -- &&' '#$N" --format=%H "$RANGE" -- &&' chk_boundary
mutant "diff boundary dropped" '-S"#$N([^0-9]|\$)"' '-S"#$N"' chk_boundary
mutant "boundary without \$" '#$N([^0-9]|\$)" --format=%H "$RANGE" -- &&
    git log --pickaxe-regex -S"#$N([^0-9]|\$)"' '#$N([^0-9])" --format=%H "$RANGE" -- &&
    git log --pickaxe-regex -S"#$N([^0-9])"' chk_eol
mutant "-S half dropped" '    git log --pickaxe-regex -S"#$N([^0-9]|\$)" --format=%H "$RANGE" -- ) > "$W/hits"' '    true ) > "$W/hits"' chk_pickaxe
mutant "open-only listing" 'forge_issue_list all >' 'forge_issue_milestone_list >' chk_closed
mutant "marker on any line" 'if $ls[0] == $mark then' 'if any($ls[]; . == $mark) then' chk_anchor
mutant "P..HEAD" 'RANGE="$P^..HEAD"' 'RANGE="$P..HEAD"' chk_range
# An empty override treated as unset falls through to the search and silently uses another library.
mutant "empty as unset" '\${$1+x}' '\${$1:+x}' chk_empty
mutant "listing cause dropped" ': $(head -1 "$W/issues.err")"' '"' chk_cause
mutant "trace in a refusal" '[ -n "$ROADMAP" ] || die "no roadmap' '[ -n "$ROADMAP" ] || . ./docs/roadmap.md || die "no roadmap' chk_trace live

echo ""
echo "review-mechanics tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
