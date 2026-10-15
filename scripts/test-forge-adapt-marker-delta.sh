#!/usr/bin/env bash
# Contract test for scripts/forge-adapt-marker-delta.sh (#529): the upstream delta between an installed
# marker and the library HEAD, deepening a shallow marketplace checkout at most once.
#
# THE FAILURE THIS PREVENTS. The marketplace checkout is depth 1, so `refresh <name>` could not show
# what changed between the installed version and the current one; three sessions fell back to a hand
# diff. Every fixture is a throwaway origin plus a `file://` clone (a plain path clones in full and is
# not shallow). MARKER_DELTA overrides the script under test, so a mutant can run on a cp copy.
# A PATH shim stands in for git where a test needs git to refuse a fetch or to log one.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${MARKER_DELTA:-$HERE/forge-adapt-marker-delta.sh}"
REFRESH="$HERE/forge-adapt-refresh.sh"
[ -f "$S" ] || { echo "missing script: $S"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want '$3', got '$2')"; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (missing '$2' in: $3)" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1 (found '$2' in: $3)" ;; *) ok "$1" ;; esac; }

gx() { GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"; }
REL=plugins/demo/skills/demo/SKILL.md
FALLBACK='; fall back to a full content diff against the catalogue copy'
# mkorigin <versions...>: an origin with one commit per version; commit i sets demo-version: v and adds rule-<i>.
mkorigin() {
  W=$(mktemp -d "$T/f.XXXXXX"); UP="$W/up"
  gx init -q -b main "$UP"; mkdir -p "$UP/$(dirname "$REL")"
  local v i=0 body=""
  for v in "$@"; do
    i=$((i + 1))
    body="${body}rule-${i}"$'\n'
    printf '<!-- demo-version: %s -->\n%s' "$v" "$body" > "$UP/$REL"
    gx -C "$UP" add -A; gx -C "$UP" commit -qm "c$i v$v"
  done
}
shallow() { LB="$W/lib"; gx clone -q --depth "${1:-1}" "file://$UP" "$LB"; }
full()    { LB="$W/lib"; gx clone -q "file://$UP" "$LB"; }
# run <name> <version> [path]: sets out, err, rc.
out=""; err=""; rc=""
run() { out=$(bash "$S" "$LB" "${3:-$REL}" "$1" "$2" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
is_shallow() { git -C "$LB" rev-parse --is-shallow-repository; }

# The git shim: SHIM_LOG records every fetch; SHIM_NO_UNSHALLOW refuses --unshallow; SHIM_NO_FETCH
# refuses every fetch; SHIM_DEEPEN=N turns --deepen=1000 into --deepen=N (a partial deepen).
REALGIT="$(command -v git)"
mkdir -p "$T/shim"
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" fetch "*)
    echo "\$*" >> "\${SHIM_LOG:-/dev/null}"
    [ -z "\${SHIM_NO_FETCH-}" ] || exit 1
    case " \$* " in *" --unshallow "*) [ -z "\${SHIM_NO_UNSHALLOW-}" ] || exit 1 ;; esac
    if [ -n "\${SHIM_DEEPEN-}" ]; then
      args=(); for a in "\$@"; do [ "\$a" = --deepen=1000 ] && a=--deepen=\$SHIM_DEEPEN; args+=("\$a"); done
      exec "$REALGIT" "\${args[@]}"
    fi ;;
esac
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/shim/git"
runshim() { local n="$1" v="$2"; shift 2; out=$(env PATH="$T/shim:$PATH" "$@" bash "$S" "$LB" "$REL" "$n" "$v" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

echo "== a shallow library is deepened, then the delta is shown =="
mkorigin 1 2 3; shallow
eq "the fixture is shallow" "$(is_shallow)" true
run demo 1
eq "v1 to HEAD: exit 0" "$rc" 0
first=$(printf '%s\n' "$out" | head -1)
case "$first" in "marker-delta: demo v1 set in "[0-9a-f]*"; delta v1 to HEAD follows") ok "first line names the commit" ;; *) bad "first line: $first" ;; esac
has "the diff has rule-two" "+rule-2" "$out"; has "the diff has rule-three" "+rule-3" "$out"
eq "the library is no longer shallow after one unshallow" "$(is_shallow)" false
eq "nothing on stderr" "$err" ""
mkorigin 1 2 3; shallow; run demo 2
eq "v2 to HEAD: exit 0" "$rc" 0
has "v2: has rule-three" "+rule-3" "$out"; lacks "v2: not rule-two (the delta starts at the commit that set v2)" "+rule-2" "$out"

echo "== only .git state changes =="
mkorigin 1 2 3; shallow; before=$(git -C "$LB" status --porcelain); head=$(git -C "$LB" rev-parse HEAD)
sumbefore=$(cd "$LB" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
run demo 1
eq "status unchanged" "$(git -C "$LB" status --porcelain)" "$before"; eq "HEAD unchanged" "$(git -C "$LB" rev-parse HEAD)" "$head"
eq "working-tree files unchanged" "$(cd "$LB" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)" "$sumbefore"
echo "== the refresh that follows still works (S2 re-shallows) =="
rm -f "$W/log"; run demo 1
bash "$REFRESH" "$LB"; eq "forge-adapt-refresh.sh on a deepened library: exit 0" "$?" 0
eq "...and it is shallow again" "$(is_shallow)" true

echo "== no network when the history is already here =="
mkorigin 1 2 3; full; rm -rf "$UP"
run demo 1
eq "full clone, origin deleted: exit 0" "$rc" 0; has "full clone: delta printed" "+rule-3" "$out"
mkorigin 1 2 3; full; run demo 3
eq "installed equals HEAD: exit 0" "$rc" 0; eq "...exact line, no diff" "$out" "marker-delta: demo v3 is current"
mkorigin 1 2 3 4; shallow 3; : > "$T/log"
runshim demo 3 SHIM_LOG="$T/log"
eq "depth-3 clone holding the v3 commit: exit 0" "$rc" 0; has "...delta printed" "+rule-4" "$out"
eq "...with no fetch at all" "$(wc -l < "$T/log" | tr -d ' ')" 0
mkorigin 1 2 3; full; : > "$T/log"; runshim demo 1 SHIM_LOG="$T/log"
eq "a full clone makes no fetch" "$(wc -l < "$T/log" | tr -d ' ')" 0

echo "== unavailable, with the fallback named and the refresh not failed =="
mkorigin 1 2 3; shallow; rm -rf "$UP"; run demo 1
eq "shallow, origin unreachable: exit 1" "$rc" 1
eq "...exact line" "$out" "marker-delta: unavailable (cannot deepen the library: origin unreachable)$FALLBACK"
lacks "...no partial diff" "+rule-" "$out"; eq "...git stderr does not leak" "$err" ""
mkorigin 1 2 3; shallow; run demo 9
eq "marker never set (after deepening): exit 1" "$rc" 1
eq "...exact line" "$out" "marker-delta: unavailable (no commit sets demo-version: 9 in $REL)$FALLBACK"
mkorigin 1 2 3; full; rm -rf "$UP"; run demo 9
eq "full clone, unknown marker: exit 1" "$rc" 1
has "...names the marker, not a deepen failure" "unavailable (no commit sets demo-version: 9" "$out"; lacks "...no deepen text" "cannot deepen" "$out"
mkorigin 1 2 3; full; run demo 1 plugins/demo/skills/gone/SKILL.md
eq "component path absent at HEAD: exit 1" "$rc" 1
has "...unavailable" "unavailable (" "$out"; has "...fallback named" "fall back to a full content diff" "$out"

echo "== 8 is not 81 =="
mkorigin 80 81 82; full; run demo 8
eq "history 80, 81, 82 never set 8: exit 1" "$rc" 1; has "...no commit sets demo-version: 8" "no commit sets demo-version: 8 in" "$out"
mkorigin 80 81 82; full; run demo 81
eq "81 resolves to the commit that set 81" "$rc" 0; has "...delta v81 to HEAD" "delta v81 to HEAD follows" "$out"; lacks "...and not the v80 additions" "+rule-1" "$out"
mkorigin 8 81 82; full; run demo 8
eq "history 8, 81, 82: 8 resolves to the commit that set 8" "$rc" 0; has "...the delta carries the later rules" "+rule-2" "$out"

echo "== a deepen git refuses, or a lock another run holds =="
mkorigin 1 2 3; shallow; : > "$T/log"
runshim demo 1 SHIM_NO_UNSHALLOW=1 SHIM_LOG="$T/log"
eq "--unshallow refused: the plain deepen fallback gives the delta, exit 0" "$rc" 0; has "...delta printed" "+rule-3" "$out"
eq "...two fetches, no more (no loop)" "$(wc -l < "$T/log" | tr -d ' ')" 2
mkorigin 1 2 3; shallow; : > "$T/log"
runshim demo 1 SHIM_NO_FETCH=1 SHIM_LOG="$T/log"
eq "every fetch refused: exit 1" "$rc" 1; has "...origin unreachable" "cannot deepen the library: origin unreachable" "$out"
eq "...exactly two attempts, no retry loop" "$(wc -l < "$T/log" | tr -d ' ')" 2
mkorigin 1 2 3; shallow; : > "$LB/.git/shallow.lock"; : > "$T/log"
runshim demo 1 SHIM_LOG="$T/log"
eq "shallow.lock held: exit 1" "$rc" 1; has "...says why" "shallow.lock" "$out"
eq "...no fetch was attempted" "$(wc -l < "$T/log" | tr -d ' ')" 0; eq "...the library is still shallow" "$(is_shallow)" true
eq "...the foreign lock is left alone" "$([ -e "$LB/.git/shallow.lock" ] && echo kept || echo gone)" kept
mkorigin 1 2 3 4; shallow; runshim demo 2 SHIM_DEEPEN=1 SHIM_NO_UNSHALLOW=1
eq "a partial deepen that stops short of the commit: exit 1" "$rc" 1
has "...history stops before it" "history stops before the commit that set demo-version: 2" "$out"
mkorigin 1 2 3 4; shallow; runshim demo 3 SHIM_DEEPEN=1 SHIM_NO_UNSHALLOW=1
eq "a partial deepen that lands ON the commit (a boundary): exit 1, not trusted" "$rc" 1
has "...history stops before it" "history stops before the commit that set demo-version: 3" "$out"
mkorigin 1 2 3 4; shallow; runshim demo 3 SHIM_DEEPEN=2 SHIM_NO_UNSHALLOW=1
eq "a partial deepen that reaches past the commit: exit 0" "$rc" 0; has "...delta printed" "+rule-4" "$out"
eq "...still shallow: the fallback never claims more than it fetched" "$(is_shallow)" true

mkorigin 1 2 2 3; shallow 2; run demo 2
eq "marker unchanged across the boundary (v2 set before it): exit 0" "$rc" 0
has "...the delta starts at the commit that SET v2, not at the boundary" "+rule-3" "$out"
eq "...so the boundary commit was not trusted and the library was deepened" "$(is_shallow)" false

echo "== arguments are validated before any git call =="
mkorigin 1 2 3; full
for n in 'Bad Name' 'demo;rm' 'demo.*' '$(id)' '' '-x' 'a/b'; do
  run "$n" 1; eq "name '$n': exit 2" "$rc" 2
done
run 'Bad Name' 1; eq "...the message" "$err" "forge-adapt-marker-delta: invalid component name 'Bad Name'"
for v in 1x '' -1 1.5 1234567890 ' 1'; do run demo "$v"; eq "version '$v': exit 2" "$rc" 2; done
run demo 1x; has "...the message names the version" "invalid version '1x'" "$err"
for p in ../escape /etc/passwd a/../b ..; do run demo 1 "$p"; eq "path '$p': exit 2" "$rc" 2; done
run demo 1 ../escape; has "...the message" "invalid component path" "$err"
out=$(bash "$S" "$LB" "" demo 1 2>"$T/err"); rc=$?; eq "an empty path: exit 2" "$rc" 2
out=$(bash "$S" "$LB" "$REL" demo 2>"$T/err"); rc=$?; eq "three arguments: exit 2" "$rc" 2; has "...usage" "usage:" "$(cat "$T/err")"
out=$(bash "$S" 2>"$T/err"); rc=$?; eq "no arguments: exit 2" "$rc" 2
out=$(bash "$S" "$LB" "$REL" demo 1 extra 2>"$T/err"); rc=$?; eq "five arguments: exit 2" "$rc" 2
mkdir "$T/plain"; out=$(bash "$S" "$T/plain" "$REL" demo 1 2>"$T/err"); rc=$?
eq "a directory that is not a git repository: exit 2" "$rc" 2; has "...the message" "not a git repository" "$(cat "$T/err")"
out=$(bash "$S" "$T/nowhere" "$REL" demo 1 2>"$T/err"); rc=$?; eq "a missing library dir: exit 2" "$rc" 2

echo
echo "forge-adapt-marker-delta tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
