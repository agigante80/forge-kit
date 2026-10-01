#!/usr/bin/env bash
# Contract test for check-cdpath-cd.sh (#379): fixture repositories with tracked scripts, one case per
# rule of the guard's header (command position, the accept rule, the file set), the repository
# itself, every awk on the machine, and a guard mutant the negative fixture must catch.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
G="$HERE/check-cdpath-cd.sh"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"

# fix <path> <content>...: a fresh fixture repo tracking <path> with one line per argument.
fix() { F="$T/f.$RANDOM$RANDOM"; mkdir -p "$F/$(dirname "$1")"; local p="$1"; shift
  printf '%s\n' "$@" > "$F/$p"; git -C "$F" init -q; git -C "$F" add -A; }
run() { out=$(bash "${GUARD:-$G}" --root "$F" 2>"$T/err"); rc=$?; }
# expect <label> <rc> <rows...>: rc and the exact `path:line` prefixes of stdout, in order.
expect() { local label="$1" want="$2"; shift 2; local got
  got=$(printf '%s\n' "$out" | sed -n 's/^\([^:]*:[0-9]*\):.*/\1/p' | paste -sd' ' -)
  [ "$rc" = "$want" ] && [ "$got" = "$*" ] && ok "$label" || bad "$label (rc $rc, rows '$got', want rc $want '$*')"; }

echo "== command position =="
fix plugins/p/skills/s/assets/a.sh '#!/bin/sh' 'set -u' 'HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"'
run; expect "a CDPATH-safe cd in an asset passes" 0
fix plugins/p/skills/s/assets/a.sh '#!/bin/sh' 'set -u' 'HERE="$(cd "$(dirname "$0")" && pwd)"'
run; expect "a bare relative cd in an asset fails, naming its line" 1 plugins/p/skills/s/assets/a.sh:3
NEG="$F"
fix scripts/b.sh '#!/bin/sh' '# cd into the root first' "awk '{ if (w == \"cd\") pcd = 1 }' f" 'echo "now cd into it"'
run; expect "comments, an awk string and prose text are not commands" 0
fix scripts/b.sh '#!/bin/sh' 'x=1; cd "$ROOT" || exit 2'
run; expect "a cd after ; is a command" 1 scripts/b.sh:2
fix scripts/d.sh '#!/bin/sh' 'if cd "$d"; then :; fi' 'while cd "$e"; do break; done'
run; expect "if and while put a bare cd in command position" 1 scripts/d.sh:2 scripts/d.sh:3
fix scripts/d.sh '#!/bin/sh' 'if CDPATH= cd -- "$d"; then :; fi'
run; expect "a guarded safe cd passes" 0
fix scripts/e.sh '#!/bin/sh' 'case $x in a) cd "$d" ;; esac' 'builtin cd "$d"' 'sleep 1 & cd "$d"' 'ok || cd "$d"' 'x=$(cd "$d")'
run; expect "a case arm, builtin, &, || and \$( each put cd in command position" 1 scripts/e.sh:2 scripts/e.sh:3 scripts/e.sh:4 scripts/e.sh:5 scripts/e.sh:6

echo "== the accept rule =="
fix scripts/c.sh '#!/bin/sh' 'cd /tmp' 'cd ./sub' 'pushd ../up' 'cd -- ./x' 'cd ..' 'cd -' 'cd' 'cd "/abs/x"' 'cd -- /abs'
run; expect "literal /, ./, ../, ., .., - and no argument pass without CDPATH=" 0
fix scripts/c.sh '#!/bin/sh' 'cd /tmp' 'cd ./sub' 'top=/abs; cd "$top"' 'pushd "$d"' 'cd sub'
run; expect "a variable argument needs CDPATH= even when absolute at run time; so does a bare relative word" 1 scripts/c.sh:4 scripts/c.sh:5 scripts/c.sh:6

echo "== the file set =="
fix scripts/test-x.sh '#!/bin/sh' 'cd "$d"'
run; expect "a test harness is out of scope" 0
fix .githooks/pre-push '#!/bin/sh' 'cd -- "$ROOT"'
run; expect "a hook is in scope" 1 .githooks/pre-push:2
fix scripts/sub/n.sh '#!/bin/sh' 'cd "$d"'
run; expect "a script nested below scripts/ is out of scope" 0
fix scripts/ok.sh '#!/bin/sh' 'echo hi'; printf 'cd "$d"\n' > "$F/scripts/untracked.sh"
run; expect "an untracked file never counts" 0
F="$T/missing"; run; [ "$rc" = 2 ] && ok "--root naming a missing directory exits 2" || bad "--root missing: rc $rc"
F="$ROOT"; run; [ "$rc" = 0 ] && [ -z "$out" ] && ok "the repository itself is clean (the guard starts green)" || bad "the repository: rc $rc: $out"

echo "== every awk on the machine agrees =="
fix scripts/e.sh '#!/bin/sh' 'if cd "$d"; then :; fi' "w == \"cd\"" 'cd ..' 'cd -- ./x' 'top=/abs; cd "$top"' 'CDPATH= cd -- "$x"' 'case $x in a) cd "$d" ;; esac' "cd '\$q'"
run; ref="$out"
for a in gawk mawk original-awk busybox; do
  command -v "$a" >/dev/null || continue
  mkdir -p "$T/bin-$a"
  if [ "$a" = busybox ]; then printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$T/bin-$a/awk"; else ln -sf "$(command -v "$a")" "$T/bin-$a/awk"; fi
  chmod +x "$T/bin-$a/awk"
  got=$(PATH="$T/bin-$a:$PATH" bash "$G" --root "$F" 2>/dev/null)
  [ "$got" = "$ref" ] && ok "$a gives the same rows" || bad "$a differs: '$got' vs '$ref'"
done

echo "== mutant =="
sed 's/if (t ~ \/CDPATH=$\/) return 1/return 1/' "$G" > "$T/g-mut.sh"; cp "$HERE/guard-lib.sh" "$T/"
if cmp -s "$G" "$T/g-mut.sh"; then bad "mutant: nothing to change"; else
  F="$NEG"; GUARD="$T/g-mut.sh" run
  [ "$rc" = 0 ] && ok "mutant: with the CDPATH= test skipped the negative fixture passes, so its row above catches it" \
    || bad "mutant: the skipped CDPATH= test still failed the fixture (rc $rc)"
fi

echo ""
echo "check-cdpath-cd tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
