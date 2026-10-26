#!/usr/bin/env bash
# Contract test for scripts/forge-adapt-standards-row.sh (#525): the drift row for the project's
# docs/guides/ticket-standards.md, compared on doc-rules-version only.
#
# Every fixture is a throwaway directory. STANDARDS_ROW overrides the script under test, so a mutant
# can be run on a cp copy (put the copy in a directory that also holds forge-adapt-drift-status.sh).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="${STANDARDS_ROW:-$HERE/forge-adapt-standards-row.sh}"
[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
DOC=docs/guides/ticket-standards.md

# mk <name> <doc content or '-' for no doc>: a directory holding the doc; echoes its path.
mk() {
  local d="$T/$1"; mkdir -p "$d"
  if [ "$2" != "-" ]; then mkdir -p "$d/docs/guides"; printf '%b' "$2" > "$d/$DOC"; fi
  echo "$d"
}
# run <project> <kit> [extra args]: sets out, err, rc.
out=""; err=""; rc=""
run() { local p="$1" k="$2"; shift 2; out=$(bash "$SCRIPT" --project "$p" --kit "$k" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

KIT21=$(mk kit21 '<!-- template-version: 6 -->\n<!-- doc-rules-version: 21 -->\n# Ticket standards\n')

echo "== the row =="
run "$(mk p20 '<!-- template-version: 3 -->\n<!-- doc-rules-version: 20 -->\n')" "$KIT21"
expect "behind: the row, v<N> in both version columns" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"
expect "behind: exit 0" 0 "$rc"
expect "behind: nothing on stderr" "" "$err"
run "$(mk p21 '<!-- doc-rules-version: 21 -->\n')" "$KIT21"
expect "current" "ticket-standards (doc-rules) | v21 | v21 | current" "$out"
run "$(mk p22 '<!-- doc-rules-version: 22 -->\n')" "$KIT21"
expect "a project ahead of the kit reads current, not behind" "ticket-standards (doc-rules) | v22 | v21 | current" "$out"
# template-version is deliberately not compared: a project whose templates lag on purpose is not behind here.
run "$(mk ptpl '<!-- template-version: 1 -->\n<!-- doc-rules-version: 21 -->\n')" "$KIT21"
expect "template-version is not compared (project 1, kit 6, rules equal)" "ticket-standards (doc-rules) | v21 | v21 | current" "$out"
run "$(mk pv '<!-- doc-rules-version: v20 -->\n')" "$KIT21"
expect "a v-prefixed project marker is read as 20 (one cell, no vv)" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"

echo "== a local adaptation is recorded beside the marker, never in it (#545) =="
KIT22=$(mk kit22 '<!-- template-version: 6 -->\n<!-- doc-rules-version: 22 -->\n# Ticket standards\n')
ANNOT='<!-- local adaptation: heading renamed -->'
run "$(mk pann1 "<!-- doc-rules-version: 21 -->\n$ANNOT\n")" "$KIT22"
expect "a separate annotation line: the kit moved on, the row reads behind" "ticket-standards (doc-rules) | v21 | v22 | behind" "$out"
expect "a separate annotation line, kit ahead: exit 0" 0 "$rc"
# The annotation sits ABOVE the marker here, so a parser that takes any comment line reads it first.
run "$(mk pann2 "$ANNOT\n<!-- doc-rules-version: 21 -->\n")" "$KIT21"
expect "an annotation line above the marker leaves it readable" "ticket-standards (doc-rules) | v21 | v21 | current" "$out"
expect "an annotation line above the marker: exit 0" 0 "$rc"
run "$(mk pann3 '<!-- doc-rules-version: 21 (local: heading renamed) -->\n')" "$KIT21"
expect "an annotation inside the marker comment is not a marker" "ticket-standards (doc-rules) | none | v21 | unversioned" "$out"
expect "an annotation inside the marker comment: exit 0" 0 "$rc"

echo "== unmarked project doc surfaces, never vanishes (#64) =="
run "$(mk punm '<!-- template-version: 6 -->\n# Ticket standards\n')" "$KIT21"
expect "unmarked: unversioned with none in the local cell" "ticket-standards (doc-rules) | none | v21 | unversioned" "$out"
expect "unmarked: exactly one row" 1 "$(printf '%s\n' "$out" | grep -c .)"
run "$(mk pprose 'The `doc-rules-version` marker says which revision.\n  prose: <!-- doc-rules-version: 99 --> inline\n')" "$KIT21"
expect "a prose mention is not a marker" "ticket-standards (doc-rules) | none | v21 | unversioned" "$out"
run "$(mk pempty '')" "$KIT21"
expect "an empty doc is unversioned" "ticket-standards (doc-rules) | none | v21 | unversioned" "$out"

echo "== no project doc =="
NODOC=$(mk nodoc -)
run "$NODOC" "$KIT21"
expect "no doc: empty stdout" "" "$out"; expect "no doc: empty stderr" "" "$err"; expect "no doc: exit 0" 0 "$rc"
run "$NODOC" "$(mk kitnone -)"
expect "no doc and no kit copy: still silent exit 0 (the kit is not read)" "0|" "$rc|$out$err"

echo "== the kit copy cannot be compared against =="
run "$(mk pk '<!-- doc-rules-version: 20 -->\n')" "$(mk kitmissing -)"
expect "kit copy missing: exit 2" 2 "$rc"; expect "kit copy missing: nothing on stdout" "" "$out"
case "$err" in *"$DOC"*) ok "kit copy missing: stderr names the file" ;; *) bad "kit copy missing: stderr '$err'" ;; esac
run "$(mk pk2 '<!-- doc-rules-version: 20 -->\n')" "$(mk kitunm '<!-- template-version: 6 -->\n')"
expect "kit copy unmarked: exit 2" 2 "$rc"; expect "kit copy unmarked: nothing on stdout" "" "$out"
case "$err" in *"$DOC"*) ok "kit copy unmarked: stderr names the file" ;; *) bad "kit copy unmarked: stderr '$err'" ;; esac

echo "== malformed markers =="
run "$(mk pabc '<!-- doc-rules-version: abc -->\n')" "$KIT21"
expect "non-numeric project marker: exit 2" 2 "$rc"; expect "non-numeric: nothing on stdout" "" "$out"
case "$err" in *abc*) ok "non-numeric: stderr names the token" ;; *) bad "non-numeric: stderr '$err'" ;; esac
run "$(mk pbig '<!-- doc-rules-version: 12345678901 -->\n')" "$KIT21"
expect "a marker over nine digits: exit 2" 2 "$rc"
run "$(mk punm2 '# no marker\n')" "$(mk kitabc '<!-- doc-rules-version: abc -->\n')"
expect "a non-numeric KIT marker is refused even with an unmarked project doc" "2|" "$rc|$out"
run "$(mk pdup '<!-- doc-rules-version: 20 -->\n<!-- doc-rules-version: 21 -->\n')" "$KIT21"
expect "a marker twice: the first wins" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"
run "$(mk pcrlf '  <!--   doc-rules-version:   20   -->   \r\n')" "$KIT21"
expect "CRLF, leading and trailing spaces are tolerated" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"
PWN="$T/pwned"
run "$(mk pinj "<!-- doc-rules-version: \$(touch $PWN) -->\n")" "$KIT21"
expect "a spaced command substitution is not a marker (unversioned)" "ticket-standards (doc-rules) | none | v21 | unversioned" "$out"
[ ! -e "$PWN" ] && ok "a command substitution in the marker never runs" || bad "the marker's command substitution ran"
run "$(mk pinj2 "<!-- doc-rules-version: \$(touch\${IFS}$PWN) -->\n")" "$KIT21"
expect "an unspaced command substitution is a non-numeric token: exit 2" 2 "$rc"
[ ! -e "$PWN" ] && ok "the unspaced substitution never runs either" || bad "the unspaced substitution ran"

echo "== paths =="
SP="$T/with space"; mkdir -p "$SP"; PS=$(mk "with space/p" '<!-- doc-rules-version: 20 -->\n'); KS=$(mk "with space/k" '<!-- doc-rules-version: 21 -->\n')
run "$PS" "$KS"; expect "paths with spaces" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"
mk "-dash/p" '<!-- doc-rules-version: 20 -->\n' > /dev/null; mk "-dash/k" '<!-- doc-rules-version: 21 -->\n' > /dev/null
out=$(cd "$T" && bash "$SCRIPT" --project -dash/p --kit -dash/k 2>&1); expect "paths with a leading dash" "ticket-standards (doc-rules) | v20 | v21 | behind" "$out"

echo "== usage =="
run "$T/nonexistent" "$KIT21"; expect "--project not a directory: exit 2" 2 "$rc"
case "$err" in *usage*) ok "--project not a directory: usage on stderr" ;; *) bad "--project not a directory: stderr '$err'" ;; esac
run "$KIT21" "$T/nonexistent"; expect "--kit not a directory: exit 2" 2 "$rc"
out=$(bash "$SCRIPT" --project "$KIT21" 2>&1); rc=$?; expect "--kit missing: exit 2" 2 "$rc"
out=$(bash "$SCRIPT" --kit "$KIT21" 2>&1); rc=$?; expect "--project missing: exit 2" 2 "$rc"
out=$(bash "$SCRIPT" 2>&1); rc=$?; expect "no arguments: exit 2" 2 "$rc"
run "$KIT21" "$KIT21" --bogus; expect "an unknown flag: exit 2" 2 "$rc"
out=$(bash "$SCRIPT" --project 2>&1); rc=$?; expect "a flag with no value: exit 2" 2 "$rc"

echo "== the word comes from forge-adapt-drift-status.sh =="
# A copy of the script beside a stub status script: the row's last cell must be the stub's word.
SD="$T/stubdir"; mkdir -p "$SD"; cp "$SCRIPT" "$SD/forge-adapt-standards-row.sh"
printf '#!/bin/sh\necho "STUB:$*"\n' > "$SD/forge-adapt-drift-status.sh"
out=$(bash "$SD/forge-adapt-standards-row.sh" --project "$(mk pstub '<!-- doc-rules-version: 20 -->\n')" --kit "$KIT21" 2>&1)
expect "the status word is whatever drift-status prints, called with --local and --catalogue" "ticket-standards (doc-rules) | v20 | v21 | STUB:--local 20 --catalogue 21" "$out"
printf '#!/bin/sh\necho "drift-status: refused" >&2; exit 2\n' > "$SD/forge-adapt-drift-status.sh"
out=$(bash "$SD/forge-adapt-standards-row.sh" --project "$(mk pstub2 '<!-- doc-rules-version: 20 -->\n')" --kit "$KIT21" 2>&1); rc=$?
expect "a refusal from drift-status is exit 2 and prints no row" "2|drift-status: refused" "$rc|$out"

echo "== the kit's own doc =="
if [ -f "$ROOT/$DOC" ]; then
  kv=$(sed -n 's/^<!-- doc-rules-version: \([0-9]*\) -->.*/\1/p' "$ROOT/$DOC" | head -n 1)
  run "$ROOT" "$ROOT"
  expect "the kit against itself reads current at its own marker" "ticket-standards (doc-rules) | v$kv | v$kv | current" "$out"
else
  bad "the kit has no $DOC"
fi

echo ""
echo "forge-adapt standards-row tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
