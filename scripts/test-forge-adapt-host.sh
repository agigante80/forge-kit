#!/usr/bin/env bash
# Contract test for the Step 1 host probe in plugins/forge-kit-adapt/skills/adapt/SKILL.md (#215).
#
# WHY THIS TESTS PROSE. The probe is an executable decision inside a prose skill: it picks the
# issue-template directory and whether forge.conf.example is offered. It used to be three globs that
# disagreed with forge-lib's authority rule on five URLs (#212). It is now the public forge_host in
# a subshell, and the skill sits on its size ratchet, so the probe cannot move to a script (the
# `FK` resolution would stay inline anyway). The host block is therefore EXTRACTED from the shipped
# SKILL.md and run, so this test cannot drift from the text users install.
#
# Every fixture runs under `env -i` with an empty HOME so the real marketplace checkout cannot
# answer. Every fixture except the "lib cannot be found" ones sets FORGE_KIT_DIR and asserts that NO
# warning is printed: a github expectation would otherwise pass vacuously through the fallback.
#
# ADAPT_SKILL overrides the file under test (used to mutation-test this suite on a cp copy).
#
# Item 2 of #327, stated once so nobody "fixes" it: Setup S2 DISCARDS an exported FORGE_KIT_DIR and
# decides the library itself, while Step 1's probe HONOURS one (candidate order: FORGE_KIT_DIR, then
# the marketplace checkout, then ~/forge-kit). The difference is deliberate: S2 refreshes whichever
# checkout it picks, and Step 1 runs afterwards in a fresh shell, where an exported value is the
# user's explicit choice. #321 (Decided design item 5) owns the rule; the S2 cases below pin S2's
# half and the resolution-order cases pin Step 1's.
#
# SHAPE GUARD (#327). The host block is cut out of the prose by an awk range, and a range that never
# closes runs to end of file, handing `bash -ec` hundreds of lines that are only loud by accident
# (the first prose line that is a syntax error). extract_block refuses before anything executes
# unless the closing marker was reached while the range was open, the block is at most
# BLOCK_MAX_LINES lines, and it holds exactly one ^FK= and one ^FORGE_HOST= line. It REPLACES the
# old `[ -n "$BLOCK" ]` guard: the single guard is `BLOCK=$(extract_block ...) || exit 1`, and the
# suite has no `set -e`, so removing that `|| exit 1` is what the wiring fixture below catches.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SKILL="${ADAPT_SKILL:-$ROOT/plugins/forge-kit-adapt/skills/adapt/SKILL.md}"
WARN="forge-adapt: forge-lib.sh not found or FORGE_HOST invalid; host defaulted to github, verify"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

[ -f "$SKILL" ] || { echo "missing skill: $SKILL"; exit 1; }
[ -f "$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh" ] || { echo "missing forge-lib.sh"; exit 1; }

# extract_block <file>: the host block, from its leading comment to the line before the next block's
# comment, printed on stdout. Returns 1 with a `host block shape check failed: ...` message on stderr
# unless the opening line exists, the closing marker was reached while the range was open (a marker
# above the opening line does not count), the block has at most BLOCK_MAX_LINES lines, and it has
# exactly one ^FK= and one ^FORGE_HOST= line. The current block is 4 lines; 12 leaves headroom.
BLOCK_MAX_LINES=12
extract_block() {
  local f="$1" blk seen n c
  blk=$(awk '/^# (Forge host|Sentinel)/{p=1} /^# Domain\/pattern sample:/{p=0} p' "$f")
  if [ -z "$blk" ]; then echo "host block shape check failed: opening line (# Forge host or # Sentinel) not found in $f" >&2; return 1; fi
  seen=$(awk '/^# (Forge host|Sentinel)/{p=1} /^# Domain\/pattern sample:/{if(p)s=1; p=0} END{print s+0}' "$f")
  if [ "$seen" != 1 ]; then echo 'host block shape check failed: closing marker "# Domain/pattern sample:" not found' >&2; return 1; fi
  n=$(printf '%s\n' "$blk" | wc -l)
  if [ "$n" -gt "$BLOCK_MAX_LINES" ]; then echo "host block shape check failed: block is $n lines, at most $BLOCK_MAX_LINES allowed" >&2; return 1; fi
  c=$(printf '%s\n' "$blk" | grep -c '^FK=')
  if [ "$c" != 1 ]; then echo "host block shape check failed: expected exactly one ^FK= line, found $c" >&2; return 1; fi
  c=$(printf '%s\n' "$blk" | grep -c '^FORGE_HOST=')
  if [ "$c" != 1 ]; then echo "host block shape check failed: expected exactly one ^FORGE_HOST= line, found $c" >&2; return 1; fi
  printf '%s\n' "$blk"
}
BLOCK=$(extract_block "$SKILL") || exit 1

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
EH="$T/emptyhome"; mkdir -p "$EH"
NOLIB="$T/nolib"; mkdir -p "$NOLIB"
MH="$T/mhome/.claude/plugins/marketplaces"; mkdir -p "$MH"; ln -s "$ROOT" "$MH/forge-kit"
CH="$T/chome"; mkdir -p "$CH"; ln -s "$ROOT" "$CH/forge-kit"

echo "== #327: the host block is shape-checked before anything executes =="
# check <name> <message>: extract_block on $T/shape-<name>.md must fail with exactly that message.
check() {
  local e rc
  e=$(extract_block "$T/shape-$1.md" 2>&1 >/dev/null); rc=$?
  expect "#327 $1: refused with the named message" "$2" "$e"
  expect "#327 $1: extract_block returns 1" 1 "$rc"
}
M='host block shape check failed:'
expect "#327 the shipped block passes the shape check silently" "" "$(extract_block "$SKILL" 2>&1 >/dev/null)"
expect "#327 the shipped block is 4 lines" 4 "$(extract_block "$SKILL" 2>/dev/null | wc -l)"
sed 's/^# Domain\/pattern sample:/# Domain\/pattern sampleX:/' "$SKILL" > "$T/shape-renamed.md"
check renamed "$M closing marker \"# Domain/pattern sample:\" not found"
awk '/^FK=/{print; print; next} 1' "$SKILL" > "$T/shape-dupfk.md"
check dupfk "$M expected exactly one ^FK= line, found 2"
awk '/^FORGE_HOST=/{print; print; next} 1' "$SKILL" > "$T/shape-duphost.md"
check duphost "$M expected exactly one ^FORGE_HOST= line, found 2"
sed '/^FORGE_HOST=/d' "$SKILL" > "$T/shape-nohost.md"
check nohost "$M expected exactly one ^FORGE_HOST= line, found 0"
sed '/^FK=/d' "$SKILL" > "$T/shape-nofk.md"
check nofk "$M expected exactly one ^FK= line, found 0"
awk '/^FK=/{print; for(i=0;i<20;i++) print "# pad"; next} 1' "$SKILL" > "$T/shape-cap.md"
check cap "$M block is 24 lines, at most $BLOCK_MAX_LINES allowed"
awk '/^# Domain\/pattern sample:/{next} /^# Sentinel/{print "# Domain/pattern sample:"} 1' "$SKILL" > "$T/shape-above.md"
check above "$M closing marker \"# Domain/pattern sample:\" not found"
sed 's/^# Sentinel/# Sentinal/' "$SKILL" > "$T/shape-noopen.md"
check noopen "$M opening line (# Forge host or # Sentinel) not found in $T/shape-noopen.md"
# Wiring: the whole suite as a child on the renamed-marker copy must stop at the guard. The suite has
# no `set -e`, so only the `|| exit 1` stops it; without it the child runs every fixture on an empty
# BLOCK and prints ok:/FAIL: lines. HOST_SUITE_CHILD is the re-entry guard: the child skips this
# fixture, so a child that gets past a removed guard cannot spawn children without bound.
if [ -z "${HOST_SUITE_CHILD:-}" ]; then
  cout=$(HOST_SUITE_CHILD=1 ADAPT_SKILL="$T/shape-renamed.md" bash "$HERE/$(basename "$0")" 2>&1); crc=$?
  case "$cout" in *"$M closing marker"*) ok "#327 wiring: the child prints the shape message" ;; *) bad "#327 wiring: no shape message in the child: $cout" ;; esac
  expect "#327 wiring: the child exits 1" 1 "$crc"
  expect "#327 wiring: the child printed no ok: or FAIL: fixture line" 0 "$(grep -cE '^ +(ok|FAIL):' <<< "$cout")"
fi

# mkrepo <name> [origin-url]: a throwaway git repo; echoes its path.
mkrepo() {
  local d="$T/r-$1"; mkdir -p "$d"
  git -C "$d" init -q 2>/dev/null
  [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"
  echo "$d"
}

# probe <repo> <home> [VAR=value ...]: runs the block in a clean env; sets out, host, brc, warned.
# The block ends with an echo, so its own exit status is 0 by construction and `brc` alone proves
# nothing. Running it under errexit (`bash -ec`) is what makes the "exit 0" assertions able to
# fail: a failing step aborts before BRC is printed, so brc comes back empty (#215 r2).
out=""; host=""; brc=""; warned=""; said=""
probe() {
  local repo="$1" home="$2"; shift 2
  out=$(cd "$repo" && env -i PATH="$PATH" HOME="$home" "$@" bash -ec "$BLOCK"$'\nbrc=$?\nprintf "HOST=[%s]\\n" "$FORGE_HOST"\necho "BRC=$brc"' 2>&1)
  host=$(printf '%s\n' "$out" | sed -n 's/^HOST=\[\(.*\)\]$/\1/p' | tail -1)  # bracketed: a multi-line value yields empty
  said=$(printf '%s\n' "$out" | sed -n 's/^forge-host: //p' | tail -1)
  brc=$(printf '%s\n' "$out" | sed -n 's/^BRC=//p' | tail -1)
  if grep -qF -- "$WARN" <<< "$out"; then warned=yes; else warned=no; fi
}
# resolved <name> <url> <expected>: lib resolved via FORGE_KIT_DIR, answer must be real, never fallback.
resolved() {
  probe "$(mkrepo "$1" "$2")" "$EH" FORGE_KIT_DIR="$ROOT"
  expect "$1: $2 -> $3" "$3" "$host"
  expect "$1: block exit status 0" 0 "$brc"
  expect "$1: the decided host is printed as 'forge-host: <host>'" "$3" "$said"
  expect "$1: no warning (the answer is not the fallback)" no "$warned"
}

echo "== the five divergent URLs from #215 =="
resolved crafted   'https://evil.internal/x/y?z=@github.com/' forgejo
resolved port443   'https://github.com:443/o/r'               github
resolved sshport   'ssh://git@ssh.github.com:443/o/r'        github
resolved scp       'github.com:o/r'                           github
resolved mixedcase 'https://GitHub.com/o/r'                   github

echo "== github.com elsewhere in the URL, and ordinary remotes =="
resolved inpath  'https://forge.example.com/github.com/o/r' forgejo
resolved plain   'https://forge.example.com/o/r'            forgejo
resolved ghhttps 'https://github.com/o/r'                   github
resolved ghscp   'git@github.com:o/r.git'                   github

echo "== no remote =="
probe "$(mkrepo noremote)" "$EH" FORGE_KIT_DIR="$ROOT"
expect "no origin -> github" github "$host"
expect "no origin: exit 0" 0 "$brc"
expect "no origin: no warning" no "$warned"

echo "== a committed .forge.conf now wins over the remote =="
d=$(mkrepo confgh 'https://forge.example.com/o/r'); echo 'FORGE_HOST=github' > "$d/.forge.conf"
probe "$d" "$EH" FORGE_KIT_DIR="$ROOT"
expect ".forge.conf github beside a forgejo remote -> github" github "$host"
expect ".forge.conf github: no warning" no "$warned"

echo "== lib cannot be found: exit 0, github, and a WARNING (never silent) =="
probe "$(mkrepo nolib 'https://forge.example.com/o/r')" "$EH"
expect "Forgejo remote, lib unresolvable -> github" github "$host"
expect "lib unresolvable: exit 0" 0 "$brc"
expect "lib unresolvable: warning printed" yes "$warned"
expect "lib unresolvable: forge-host: github printed" github "$said"
probe "$(mkrepo nolib2 'https://forge.example.com/o/r')" "$EH" FORGE_KIT_DIR="$NOLIB"
expect "FORGE_KIT_DIR without the lib and nothing else -> github" github "$host"
expect "FORGE_KIT_DIR without the lib: warning printed" yes "$warned"
expect "FORGE_KIT_DIR without the lib: forge-host: github printed" github "$said"

echo "== an invalid FORGE_HOST: exit 0, github, and a WARNING =="
d=$(mkrepo bogusconf 'https://forge.example.com/o/r'); echo 'FORGE_HOST=bogus' > "$d/.forge.conf"
probe "$d" "$EH" FORGE_KIT_DIR="$ROOT"
expect ".forge.conf FORGE_HOST=bogus -> github" github "$host"
expect ".forge.conf bogus: exit 0" 0 "$brc"
expect ".forge.conf bogus: warning printed" yes "$warned"
expect ".forge.conf bogus: forge-host: github printed" github "$said"
probe "$(mkrepo bogusenv 'https://forge.example.com/o/r')" "$EH" FORGE_KIT_DIR="$ROOT" FORGE_HOST=bogus
expect "env FORGE_HOST=bogus -> github" github "$host"
expect "env bogus: warning printed" yes "$warned"
expect "env bogus: forge-host: github printed" github "$said"

echo "== the resolution order: FORGE_KIT_DIR, then the marketplace, then ~/forge-kit =="
# Two stub roots that answer differently, so WHICH candidate won is observable.
mkstub() { local r="$T/stub-$1/plugins/forge-kit-devops/skills/forge-host/assets"; mkdir -p "$r"
  printf 'forge_host() { echo %s; }\n' "$2" > "$r/forge-lib.sh"; echo "$T/stub-$1"; }
SA=$(mkstub a forgejo); SB=$(mkstub b github)
mkhome() { local h="$T/home-$1"; mkdir -p "$h/.claude/plugins/marketplaces"; echo "$h"; }
H1=$(mkhome 1); ln -s "$SB" "$H1/.claude/plugins/marketplaces/forge-kit"
probe "$(mkrepo ord1 'https://forge.example.com/o/r')" "$H1" FORGE_KIT_DIR="$SA"
expect "FORGE_KIT_DIR outranks the marketplace checkout" forgejo "$host"
H2=$(mkhome 2); ln -s "$SA" "$H2/.claude/plugins/marketplaces/forge-kit"; ln -s "$SB" "$H2/forge-kit"
probe "$(mkrepo ord2 'https://forge.example.com/o/r')" "$H2"
expect "the marketplace checkout outranks ~/forge-kit" forgejo "$host"
H3=$(mkhome 3); ln -s "$SA" "$H3/forge-kit"
probe "$(mkrepo ord3 'https://forge.example.com/o/r')" "$H3" FORGE_KIT_DIR="$NOLIB"
expect "~/forge-kit is the last candidate" forgejo "$host"
probe "$(mkrepo mk 'https://forge.example.com/o/r')" "$T/mhome"
expect "marketplace checkout under HOME resolves the lib" forgejo "$host"
expect "marketplace: no warning" no "$warned"
probe "$(mkrepo cl 'https://forge.example.com/o/r')" "$CH"
expect "~/forge-kit resolves the lib" forgejo "$host"
expect "clone: no warning" no "$warned"
probe "$(mkrepo fall 'https://forge.example.com/o/r')" "$T/mhome" FORGE_KIT_DIR="$NOLIB"
expect "a FORGE_KIT_DIR lacking the lib falls through to the next candidate" forgejo "$host"
expect "fall-through: no warning" no "$warned"

echo "== the dead code is gone and the template-version read uses the resolved path =="
expect "no CURRENT_REPO assignment in the skill" 0 "$(grep -c '^CURRENT_REPO=' "$SKILL")"
expect "no REMOTE_URL assignment in the skill" 0 "$(grep -c '^REMOTE_URL=' "$SKILL")"
expect "FK_TPL_VER reads \$FK, not the unset \$FORGE_KIT_DIR" 1 "$(grep -c '^FK_TPL_VER=.*"\$FK"/\.github/ISSUE_TEMPLATE' "$SKILL")"

# ==================================================================================================
# #321: every Bash call is a fresh shell, so the library path S2 resolves is gone in later blocks.
# Each later read is `${FORGE_KIT_DIR:?}` (or a head-of-block guard), so an unset value STOPS naming
# the variable instead of reading `/scripts/...`, listing every component as project-only, leaving
# the template version empty, or misdiagnosing a stale library after a `mkdir`. S2 prints the
# library path and the governance flag, which is how a later block learns them.
#
# WHY S2 REFRESHES (moved here from the skill to pay for the #321 words): both library sources are
# plain git checkouts of the repo tracking origin/main, so fetch + `checkout -B <default branch>
# origin/HEAD` makes either current (#502: not reset --hard, which overnight-guard denies in a
# .claude/no-destructive project, and not merge --ff-only, which refuses a depth-1 fetch as
# "unrelated histories"). The marketplace checkout is NOT auto-pulled between manual
# `/plugin marketplace update` runs and pins no SHA (known_marketplaces.json holds only source +
# installLocation), so moving it forward lands exactly what an update would. A stale checkout both mis-catalogues versions and lacks the
# scripts/ and docs/ files a governance install copies.
#
# #501: the refresh itself lives in scripts/forge-adapt-refresh.sh (retry once, then ask the remote), tested
# by test-forge-adapt-refresh.sh. S2 only calls it, and prints the one warning when it exits non-zero or is
# absent (an older library predates it; there is deliberately no inline fallback, so the warning is honest).
#
# S2 FIXTURE RULE: S2's first statement discards an exported FORGE_KIT_DIR, and it runs fetch and
# checkout -B on any git checkout it picks, so every S2 fixture is a NON-git mktemp library placed
# where S2 looks, in a throwaway HOME, never the MH/CH symlinks to this repository; each S2 case
# asserts that no clone ran. GIT_CEILING_DIRECTORIES keeps git from finding an enclosing checkout.
# The one exception is the #502 block, which tests the refresh itself on a throwaway depth-1 clone.
echo "== #321: later blocks stop on an unset library instead of reading a bare path =="
export GIT_CEILING_DIRECTORIES="$T"
# fence <content-pattern>: the one fenced bash block (indented fences included) holding the pattern,
# its indentation removed; exits the suite unless exactly one block matches.
fence() {
  local got n
  got=$(P="$1" awk '
    /^[ \t]*```bash[ \t]*$/ { ind = $0; sub(/```bash.*/, "", ind); inb = 1; buf = ""; next }
    inb && /^[ \t]*```[ \t]*$/ { inb = 0; if (index(buf, ENVIRON["P"])) { k++; keep = buf } next }
    inb { l = $0; if (index(l, ind) == 1) l = substr(l, length(ind) + 1); buf = buf l "\n" }
    END { printf "%s", keep; exit (k == 1 ? 0 : 1) }' "$SKILL") || { echo "fence: no single bash block holds '$1' in $SKILL"; exit 1; }
  printf '%s' "$got"
}
# span <content-pattern>: the one inline code span holding the pattern, backticks removed.
span() {
  local got
  got=$(grep -o '`[^`]*'"$1"'[^`]*`' "$SKILL" | tr -d '`')
  [ "$(printf '%s\n' "$got" | grep -c .)" = 1 ] || { echo "span: no single code span holds '$1' in $SKILL"; exit 1; }
  printf '%s' "$got"
}
fill() { printf '%s' "$1" | sed -e 's/<name>/x/g' -e 's/<file>/plan.txt/g' -e 's/<group>/g/g' -e 's/<installed>/a/g' -e 's/<catalogue>/b/g'; }
# lib [file...]: a valid library (plugins/ present) with stub helpers that print ok.
lib() { local d; d=$(mktemp -d "$T/lib.XXXXXX"); mkdir -p "$d/plugins" "$d/scripts"
  for h in forge-adapt-catalogue.sh forge-adapt-neighbour-disposition.sh forge-adapt-install-plan.sh \
           forge-adapt-agent-skills.sh forge-adapt-drift-status.sh forge-adapt-tier-diff.sh; do
    printf '#!/bin/sh\necho ok\n' > "$d/scripts/$h"; chmod +x "$d/scripts/$h"; done
  echo "$d"; }
# run_block <block> [VAR=value ...]: the block under env -i in a fresh project dir; sets bout, berr, brc, PROJ.
bout=""; berr=""; brc=""; PROJ=""
run_block() { local b="$1"; shift; PROJ=$(mktemp -d "$T/proj.XXXXXX")
  bout=$(cd "$PROJ" && env -i PATH="$PATH" HOME="$EH" GIT_CEILING_DIRECTORIES="$T" "$@" bash -c "$b" 2>"$T/berr"); brc=$?; berr=$(cat "$T/berr"); }
L=$(lib)
for pat in 'forge-adapt-catalogue.sh' 'forge-adapt-neighbour-disposition.sh <name>' 'forge-adapt-install-plan.sh <file>' 'forge-adapt-agent-skills.sh --names'; do
  b=$(fill "$(fence "$pat")")
  run_block "$b" FORGE_KIT_DIR="$L" FORGE_KIT_SRC=marketplace
  case "$bout" in ok*) ok "#321: '$pat' runs from the library" ;; *) bad "#321: '$pat' did not run from the library (out '$bout', rc $brc)" ;; esac
  expect "#321: '$pat' exits 0 with the library" 0 "$brc"
  run_block "$b" FORGE_KIT_SRC=marketplace
  [ "$brc" != 0 ] && ok "#321: '$pat' unset: exits non-zero" || bad "#321: '$pat' unset: exited 0"
  case "$berr" in *FORGE_KIT_DIR*) ok "#321: '$pat' unset: stderr names FORGE_KIT_DIR" ;; *) bad "#321: '$pat' unset: stderr '$berr'" ;; esac
  case "$berr" in *"No such file or directory"*) bad "#321: '$pat' unset: a bare /scripts path was tried" ;; *) ok "#321: '$pat' unset: no bare /scripts path tried" ;; esac
done
for pat in 'forge-adapt-drift-status.sh' 'forge-adapt-tier-diff.sh'; do
  b=$(fill "$(span "$pat")")
  run_block "$b" FORGE_KIT_DIR="$L"; expect "#321: span '$pat' runs from the library" ok "$bout"
  run_block "$b"
  [ "$brc" != 0 ] && case "$berr" in *FORGE_KIT_DIR*) true ;; *) false ;; esac \
    && ok "#321: span '$pat' unset: exits non-zero naming FORGE_KIT_DIR" || bad "#321: span '$pat' unset: rc $brc, stderr '$berr'"
done
# #504: the drift call site names its two required inputs and the reference that explains them, so
# it cannot go back to a bare script name that every guess then fails against.
dspan=$(span 'forge-adapt-drift-status.sh')
case "$dspan" in *"--local <installed>"*"--catalogue <catalogue>"*) ok "#504: the drift span passes --local and --catalogue" ;; *) bad "#504: the drift span is '$dspan'" ;; esac
grep -q 'forge-adapt-drift-status.sh --local <installed> --catalogue <catalogue>` (inputs: `references/drift.md`)' "$SKILL" \
  && ok "#504: the drift call site points at references/drift.md" || bad "#504: the drift call site names no reference"
[ -f "$(dirname "$SKILL")/references/drift.md" ] && ok "#504: references/drift.md exists" || bad "#504: references/drift.md is missing"
grep -q 'forge-adapt-plugin-active.sh <group>@forge-kit' "$(dirname "$SKILL")/references/drift.md" \
  && ok "#504: the reference derives --group-enabled from the plugin-active script" || bad "#504: the reference does not name the group source"
# The catalogue header is already the full plugin name (forge-kit-<x>), so a reference that prefixes it
# again asks for forge-kit-forge-kit-<x>, which the script answers no for: every registered component
# would read missing.
RF="$(dirname "$SKILL")/references/drift.md"
grep -q 'forge-kit-<group>' "$RF" && bad "#504: the reference prefixes the group with forge-kit- again" || ok "#504: the reference does not double-prefix the group"
HL=$(lib); mkdir -p "$HL/plugins/forge-kit-x"
case "$(bash "$ROOT/scripts/forge-adapt-catalogue.sh" "$HL" 2>/dev/null)" in *"=== forge-kit-x ==="*) ok "#504: the catalogue header is the full plugin name" ;; *) bad "#504: the catalogue header is not the directory name" ;; esac
# Contributions: a library shipping ticket-gate, a project holding it and my-local.
CB=$(fence 'comm -23'); CL=$(lib); mkdir -p "$CL/plugins/g/agents"; : > "$CL/plugins/g/agents/ticket-gate.md"
contrib() { PROJ=$(mktemp -d "$T/proj.XXXXXX"); mkdir -p "$PROJ/.claude/agents"; : > "$PROJ/.claude/agents/ticket-gate.md"; : > "$PROJ/.claude/agents/my-local.md"
  bout=$(cd "$PROJ" && env -i PATH="$PATH" HOME="$EH" "$@" bash -c "$CB" 2>"$T/berr"); brc=$?; berr=$(cat "$T/berr"); }
contrib FORGE_KIT_DIR="$CL"; expect "#321: contributions lists only the project-only component" my-local.md "$bout"
contrib; expect "#321: contributions unset: prints nothing" "" "$bout"
[ "$brc" != 0 ] && case "$berr" in *FORGE_KIT_DIR*) true ;; *) false ;; esac && ok "#321: contributions unset: exits non-zero naming FORGE_KIT_DIR" || bad "#321: contributions unset: rc $brc, stderr '$berr'"
case "$berr" in *"basename: missing operand"*) bad "#321: contributions unset: basename ran" ;; *) ok "#321: contributions unset: basename never ran" ;; esac
BADL=$(mktemp -d "$T/bad.XXXXXX"); contrib FORGE_KIT_DIR="$BADL"; expect "#321: contributions set-but-bad: prints nothing" "" "$bout"
[ "$brc" != 0 ] && case "$berr" in *"$BADL"*) true ;; *) false ;; esac && ok "#321: contributions set-but-bad: exits non-zero naming the path" || bad "#321: contributions set-but-bad: rc $brc, stderr '$berr'"
# Templates version.
TB=$(fence 'FORGE_KIT_TEMPLATE_VERSION=')$'\necho "V=$FORGE_KIT_TEMPLATE_VERSION"'
TL=$(lib); mkdir -p "$TL/.github/ISSUE_TEMPLATE"; printf '# template-version: 6\n' > "$TL/.github/ISSUE_TEMPLATE/feature.yml"
run_block "$TB" FORGE_KIT_DIR="$TL"; expect "#321: templates version read from the library" V=6 "$bout"; expect "#321: templates version: exit 0" 0 "$brc"
run_block "$TB"
[ "$brc" != 0 ] && case "$berr" in *FORGE_KIT_DIR*) true ;; *) false ;; esac && ok "#321: templates unset: exits non-zero naming FORGE_KIT_DIR" || bad "#321: templates unset: rc $brc, stderr '$berr'"
case "$berr$bout" in *"grep: /.github"*|*V=*) bad "#321: templates unset: read on or printed an empty version" ;; *) ok "#321: templates unset: never read /.github or set an empty version" ;; esac
run_block "$TB" FORGE_KIT_DIR="$L"
[ "$brc" != 0 ] && case "$berr" in *"$L/.github/ISSUE_TEMPLATE/feature.yml"*) true ;; *) false ;; esac && ok "#321: templates, library without feature.yml: stops naming that path" || bad "#321: templates incomplete library: rc $brc, stderr '$berr'"
# Lockstep install block.
KB=$(fence 'check-template-lockstep.sh" scripts/')
# #506: the guard is an adapt asset (marked, so drift can see it); the kit-only test is not copied downstream.
KL=$(lib); KA="$KL/plugins/forge-kit-adapt/skills/adapt/assets"; mkdir -p "$KA"; : > "$KA/check-template-lockstep.sh"
run_block "$KB" FORGE_KIT_DIR="$KL"
[ "$brc" = 0 ] && [ -f "$PROJ/scripts/check-template-lockstep.sh" ] && ok "#321: lockstep copies the guard from the library" || bad "#321: lockstep did not copy (rc $brc)"
[ -x "$PROJ/scripts/check-template-lockstep.sh" ] && [ ! -e "$PROJ/scripts/test-template-lockstep.sh" ] && ok "#506: the guard is executable and its kit-only test is not copied" || bad "#506: lockstep copy set wrong: $(ls "$PROJ/scripts")"
grep -q 'test-template-lockstep' "$SKILL" && bad "#506: SKILL.md still wires or names the lockstep test" || ok "#506: SKILL.md no longer names the lockstep test"
# #506: drift enumeration lists the unmarked pre-marker guard as 'vnone' so it reads unversioned, but still skips other unmarked scripts.
DB=$(fence 'shell asset (verbatim copy)'); DP=$(mktemp -d "$T/drift.XXXXXX"); mkdir -p "$DP/scripts"
printf '#!/bin/sh\n' > "$DP/scripts/check-template-lockstep.sh"; printf '#!/bin/sh\n' > "$DP/scripts/other.sh"
dout=$(cd "$DP" && env -i PATH="$PATH" HOME="$EH" GIT_CEILING_DIRECTORIES="$T" bash -c "$DB" 2>/dev/null)
case "$dout" in *"  check-template-lockstep | vnone | shell asset (verbatim copy)"*) ok "#506: an unmarked installed guard is listed as vnone" ;; *) bad "#506: unmarked guard row missing: $dout" ;; esac
case "$dout" in *"other | "*) bad "#506: an unrelated unmarked script was listed" ;; *) ok "#506: other unmarked scripts stay skipped" ;; esac
printf '#!/bin/sh\n# check-template-lockstep-version: 1\n' > "$DP/scripts/check-template-lockstep.sh"
dout=$(cd "$DP" && env -i PATH="$PATH" HOME="$EH" GIT_CEILING_DIRECTORIES="$T" bash -c "$DB" 2>/dev/null)
case "$dout" in *"  check-template-lockstep | v1 | shell asset (verbatim copy)"*) ok "#506: a marked installed guard reads its version" ;; *) bad "#506: marked guard row: $dout" ;; esac
run_block "$KB"
[ "$brc" != 0 ] && case "$berr" in *FORGE_KIT_DIR*) true ;; *) false ;; esac && ok "#321: lockstep unset: exits non-zero naming FORGE_KIT_DIR" || bad "#321: lockstep unset: rc $brc, stderr '$berr'"
[ ! -e "$PROJ/scripts" ] && ok "#321: lockstep unset: no scripts/ directory created" || bad "#321: lockstep unset: created scripts/"
case "$bout$berr" in *"(stale)"*|*"git -C  pull"*) bad "#321: lockstep unset: printed the stale misdiagnosis" ;; *) ok "#321: lockstep unset: no stale misdiagnosis" ;; esac
run_block "$KB" FORGE_KIT_DIR="$L"
[ "$brc" != 0 ] && [ ! -e "$PROJ/scripts" ] && case "$berr" in *"marketplace update"*"git pull"*) true ;; *) false ;; esac \
  && ok "#321: lockstep, library missing the guard: one message naming both remedies, nothing created" || bad "#321: lockstep missing guard: rc $brc, stderr '$berr'"
# S2 prints the library path and the governance flag, and decides the library itself.
SB=$(fence 'FORGE_KIT_DIR=""; FORGE_KIT_SRC=""')
s2home() { local h; h=$(mktemp -d "$T/s2h.XXXXXX"); mkdir -p "$h/.claude/plugins/marketplaces/forge-kit/plugins"; echo "$h"; }
s2() { local h="$1"; shift; bout=$(cd "$h" && env -i PATH="$PATH" HOME="$h" GIT_CEILING_DIRECTORIES="$T" "$@" bash -c "$SB" 2>&1); brc=$?; }
H=$(s2home); s2 "$H"
case "$bout" in *governance-plugin-active=no*) ok "#321: S2 prints governance-plugin-active=no" ;; *) bad "#321: S2 printed no governance flag: $bout" ;; esac
case "$bout" in *": $H/.claude/plugins/marketplaces/forge-kit"*) ok "#321: S2 prints the library path" ;; *) bad "#321: S2 printed no library path: $bout" ;; esac
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (governance absent): no clone ran" || bad "#321: S2 cloned"
# #500: a leftover cache directory is NOT an installed plugin, and a library without the plugin-active
# script (a stale or non-git library) answers no with a reason line, never the old heuristic's yes.
H=$(s2home); mkdir -p "$H/.claude/plugins/cache/forge-kit/forge-kit-governance"; s2 "$H"
case "$bout" in *governance-plugin-active=no*) ok "#500: S2 prints =no for a leftover cache dir with no registry entry" ;; *) bad "#500: S2 cache dir only: $bout" ;; esac
case "$bout" in *governance-plugin-active=yes*) bad "#500: S2 read the cache dir as installed" ;; *) ok "#500: S2 cache dir only: no =yes line" ;; esac
expect "#500: S2 prints exactly one governance-plugin-active= line" 1 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-active=')"
expect "#500: S2 without the script prints one governance-plugin-reason= line" 1 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-reason=')"
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (cache dir only): no clone ran" || bad "#321: S2 cloned"
# #500: the real script, a registry entry, a manifest and settings make S2 read yes; a local disable makes it no.
H=$(s2home); LIB500="$H/.claude/plugins/marketplaces/forge-kit"; mkdir -p "$LIB500/scripts" "$H/.claude/plugins/cache/g/.claude-plugin" "$H/.claude/plugins/cache/d/.claude-plugin"
cp "$ROOT/scripts/forge-adapt-plugin-active.sh" "$LIB500/scripts/"
echo '{"name":"forge-kit-governance","dependencies":["forge-kit-devops@forge-kit"]}' > "$H/.claude/plugins/cache/g/.claude-plugin/plugin.json"
echo '{"name":"forge-kit-devops"}' > "$H/.claude/plugins/cache/d/.claude-plugin/plugin.json"
jq -n --arg g "$H/.claude/plugins/cache/g" --arg d "$H/.claude/plugins/cache/d" \
  '{version:2,plugins:{"forge-kit-governance@forge-kit":[{scope:"user",installPath:$g}],"forge-kit-devops@forge-kit":[{scope:"user",installPath:$d}]}}' > "$H/.claude/plugins/installed_plugins.json"
s2 "$H"
expect "#500: S2 with a live plugin prints exactly one governance-plugin-active=yes" 1 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-active=yes$')"
expect "#500: S2 with a live plugin prints no governance-plugin-active=no" 0 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-active=no')"
expect "#500: S2 with a live plugin prints no reason line" 0 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-reason=')"
mkdir -p "$H/proj/.claude"; echo '{"enabledPlugins":{"forge-kit-devops@forge-kit":false}}' > "$H/proj/.claude/settings.local.json"
bout=$(cd "$H/proj" && env -i PATH="$PATH" HOME="$H" GIT_CEILING_DIRECTORIES="$T" bash -c "$SB" 2>&1); brc=$?
case "$bout" in *"governance-plugin-reason=dependency forge-kit-devops disabled"*) ok "#500: S2 reads no when a dependency is disabled in the project, with the reason" ;; *) bad "#500: S2 disabled dependency: $bout" ;; esac
expect "#500: S2 with a disabled dependency prints exactly one governance-plugin-active=no" 1 "$(printf '%s\n' "$bout" | grep -c '^governance-plugin-active=no$')"
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (governance present): no clone ran" || bad "#321: S2 cloned"
# #502: S2 refreshes a GIT library without `git reset --hard`, which overnight-guard denies in a
# .claude/no-destructive project. These fixtures are the deliberate exception to the S2 FIXTURE RULE
# above: the refresh itself is what is under test, so the library is a real depth-1 clone of a local
# upstream (file:// URL, because a plain path clones in full and is not shallow), in a throwaway HOME.
gx() { GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"; }
# mk502 <branch>: sets H (home), UP (upstream), LB (the shallow library S2 will pick).
mk502() { H=$(s2home); UP=$(mktemp -d "$T/up.XXXXXX"); LB="$H/.claude/plugins/marketplaces/forge-kit"; rm -rf "$LB"
  gx init -q -b "$1" "$UP"; mkdir -p "$UP/plugins"; echo 1 > "$UP/plugins/f.txt"; echo a > "$UP/g.txt"
  gx -C "$UP" add .; gx -C "$UP" commit -qm c1; echo 2 > "$UP/plugins/f.txt"; gx -C "$UP" commit -qam c2
  gx clone -q --depth 1 "file://$UP" "$LB"
  mkdir -p "$LB/scripts"; cp "$ROOT/scripts/forge-adapt-refresh.sh" "$LB/scripts/"; }
# up502 <file> <content>: one more upstream commit.
up502() { printf '%s\n' "$2" > "$UP/$1"; gx -C "$UP" add -A; gx -C "$UP" commit -qm "more $1"; }
nowarn() { case "$bout" in *"could not refresh"*) bad "$1: warned: $bout" ;; *) ok "$1: no could-not-refresh line" ;; esac; }
mk502 main; expect "#502: the fixture library is shallow" true "$(git -C "$LB" rev-parse --is-shallow-repository)"
up502 plugins/f.txt 3; s2 "$H"
nowarn "#502: shallow library"; expect "#502: shallow refresh exits 0" 0 "$brc"
expect "#502: the shallow library HEAD equals the upstream" "$(git -C "$UP" rev-parse HEAD)" "$(git -C "$LB" rev-parse HEAD)"
# A detached HEAD on a library whose default branch is not main refreshes too (the branch comes from origin/HEAD).
mk502 trunk; git -C "$LB" checkout -q --detach HEAD; up502 plugins/f.txt 3; s2 "$H"
nowarn "#502: detached HEAD, default branch trunk"
expect "#502: detached non-main library HEAD equals the upstream" "$(git -C "$UP" rev-parse HEAD)" "$(git -C "$LB" rev-parse HEAD)"
expect "#502: the refresh leaves the library on the default branch" trunk "$(git -C "$LB" symbolic-ref --short HEAD)"
# A conflicting tracked edit is refused, not overwritten.
mk502 main; echo local > "$LB/plugins/f.txt"; old=$(git -C "$LB" rev-parse HEAD); up502 plugins/f.txt 3; s2 "$H"
case "$bout" in *"forge-adapt: could not refresh the marketplace library at $LB; it may be behind (fix: /plugin marketplace update forge-kit)."*) ok "#502: a conflicting local edit warns with the fix line" ;; *) bad "#502: conflicting edit: $bout" ;; esac
expect "#502: a conflicting local edit survives" local "$(cat "$LB/plugins/f.txt")"
expect "#502: a refused refresh leaves HEAD unchanged" "$old" "$(git -C "$LB" rev-parse HEAD)"
# A non-conflicting tracked edit is carried silently.
mk502 main; echo mine >> "$LB/g.txt"; up502 plugins/f.txt 3; s2 "$H"
nowarn "#502: a non-conflicting edit"
expect "#502: a non-conflicting edit is carried" mine "$(tail -1 "$LB/g.txt")"
expect "#502: a non-conflicting edit still moves HEAD" "$(git -C "$UP" rev-parse HEAD)" "$(git -C "$LB" rev-parse HEAD)"
# An untracked file the new commit adds is refused.
mk502 main; echo mine > "$LB/added.txt"; up502 added.txt theirs; s2 "$H"
case "$bout" in *"could not refresh"*) ok "#502: an untracked file the commit adds warns" ;; *) bad "#502: untracked collision: $bout" ;; esac
expect "#502: the colliding untracked file survives" mine "$(cat "$LB/added.txt")"
# #501: a git library that predates the helper (no scripts/forge-adapt-refresh.sh) warns, still prints the
# library line, and exits 0.
mk502 main; rm -rf "$LB/scripts"; s2 "$H"
case "$bout" in *"could not refresh the marketplace library at $LB"*) ok "#501: a library without the helper warns" ;; *) bad "#501: no-helper library: $bout" ;; esac
case "$bout" in *"forge-adapt: library at "*"(marketplace): $LB"*) ok "#501: the library line still prints" ;; *) bad "#501: library line missing: $bout" ;; esac
expect "#501: a library without the helper exits 0" 0 "$brc"
# #501: a helper that exits 1 (the library is really behind) gives the one warning with the fix text of
# its source, then the library line, nothing on stderr (S2 merges it, so the whole output is checked), rc 0.
mk502 main; printf '#!/bin/sh\nexit 1\n' > "$LB/scripts/forge-adapt-refresh.sh"; s2 "$H"
expect "#501: a behind marketplace library prints exactly one warning" 1 "$(printf '%s\n' "$bout" | grep -c 'could not refresh')"
case "$bout" in *"could not refresh the marketplace library at $LB; it may be behind (fix: /plugin marketplace update forge-kit)."*) ok "#501: the marketplace warning carries its fix" ;; *) bad "#501: marketplace warning: $bout" ;; esac
expect "#501: a behind marketplace library exits 0" 0 "$brc"
mk502 main; printf '#!/bin/sh\nexit 1\n' > "$LB/scripts/forge-adapt-refresh.sh"; mv "$LB" "$H/forge-kit"; s2 "$H"
case "$bout" in *"could not refresh the clone library at $H/forge-kit; it may be behind (fix: git -C $H/forge-kit pull)."*) ok "#501: the clone warning carries its fix" ;; *) bad "#501: clone warning: $bout" ;; esac
case "$bout" in *"No such file"*|*"Permission denied"*) bad "#501: stray shell error: $bout" ;; *) ok "#501: no stray shell error" ;; esac
# The guard: the refresh, as the Bash call S2 makes, passes overnight-guard in a no-destructive project,
# and a reset --hard is still denied by the same unchanged hook.
GP=$(mktemp -d "$T/guard.XXXXXX"); mkdir -p "$GP/.claude"; : > "$GP/.claude/no-destructive"
guard() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | (cd "$GP" && CLAUDE_PROJECT_DIR="$GP" python3 "$ROOT/plugins/forge-kit-governance/hooks/overnight-guard.py"); }
case "$(guard "$SB")" in *deny*) bad "#502: overnight-guard denied the S2 block" ;; *) ok "#502: overnight-guard allows the S2 block in a no-destructive project" ;; esac
case "$(guard 'git -C lib fetch --depth 1 origin --quiet && git -C lib reset --hard origin/HEAD --quiet')" in *'"deny"'*) ok "#502: overnight-guard still denies reset --hard" ;; *) bad "#502: the guard control did not deny" ;; esac
A=$(lib); H=$(s2home); s2 "$H" FORGE_KIT_DIR="$A"
case "$bout" in *": $H/.claude/plugins/marketplaces/forge-kit"*) ok "#321: S2 decides the library itself, ignoring an exported FORGE_KIT_DIR" ;; *) bad "#321: S2 precedence: $bout" ;; esac
case "$bout" in *"$A"*) bad "#321: S2 printed the exported path" ;; *) ok "#321: S2 never printed the exported path" ;; esac
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (precedence): no clone ran" || bad "#321: S2 cloned"
# Structural lint: every fenced bash block after S2 reads the library only through ${FORGE_KIT_DIR:?},
# per occurrence (the Step 1 probe and S2 itself are excluded); later text never reads the old state.
lint=$(awk '
  /^[ \t]*```bash[ \t]*$/ { inb = 1; start = NR; buf = ""; next }
  inb && /^[ \t]*```[ \t]*$/ { inb = 0
    if (index(buf, "FORGE_KIT_DIR=\"\"; FORGE_KIT_SRC=\"\"")) { s2 = 1; next }
    if (!s2 || index(buf, "FK=\"\"; for d in")) next
    t = buf; n = gsub(/\$FORGE_KIT_DIR|\$\{FORGE_KIT_DIR\}|\$\{FORGE_KIT_DIR:-/, "", t)
    if (n) print "block at line " start ": " n " unguarded read(s)"
    next }
  inb { buf = buf $0 "\n" }' "$SKILL")
expect "#321: lint: every later fenced read of the library is \${FORGE_KIT_DIR:?}" "" "$lint"
after=$(awk 'index($0, "echo \"governance-plugin-active=") { on = 1; next } on' "$SKILL")
# #407: later text names FORGE_KIT_SRC only as the fresh-shell prefix or a guarded read.
expect "#407: every later read of \$FORGE_KIT_SRC is \${FORGE_KIT_SRC:?}" 0 \
  "$(printf '%s\n' "$after" | sed -e 's/\${FORGE_KIT_SRC:?}//g' -e 's/FORGE_KIT_SRC=<source>//g' | grep -c 'FORGE_KIT_SRC')"
expect "#321: no later text reads GOVERNANCE_PLUGIN_ACTIVE (the hook branch reads the printed flag)" 0 "$(printf '%s\n' "$after" | grep -c 'GOVERNANCE_PLUGIN_ACTIVE')"
grep -q '^\*\*Branch on S2.s printed `governance-plugin-active=` line' "$SKILL" && ok "#321: the hook branch names the printed flag" || bad "#321: the hook branch does not name the printed flag"
# The lint can fail: one guard reverted on a copy.
cp "$SKILL" "$T/skill-mut.md"; sed -i.bak 's|"${FORGE_KIT_DIR:?}"/scripts/forge-adapt-install-plan.sh|"$FORGE_KIT_DIR"/scripts/forge-adapt-install-plan.sh|' "$T/skill-mut.md"
cmp -s "$SKILL" "$T/skill-mut.md" && bad "#321: the lint mutant did not apply"
mlint=$(SKILL="$T/skill-mut.md" awk '
  /^[ \t]*```bash[ \t]*$/ { inb = 1; start = NR; buf = ""; next }
  inb && /^[ \t]*```[ \t]*$/ { inb = 0
    if (index(buf, "FORGE_KIT_DIR=\"\"; FORGE_KIT_SRC=\"\"")) { s2 = 1; next }
    if (!s2 || index(buf, "FK=\"\"; for d in")) next
    t = buf; n = gsub(/\$FORGE_KIT_DIR|\$\{FORGE_KIT_DIR\}|\$\{FORGE_KIT_DIR:-/, "", t)
    if (n) print "block at line " start ": " n " unguarded read(s)"
    next }
  inb { buf = buf $0 "\n" }' "$T/skill-mut.md")
case "$mlint" in "block at line "*": 1 unguarded read(s)") ok "#321: mutant: a reverted guard fails the lint and names its block" ;; *) bad "#321: mutant: the lint missed a reverted guard ('$mlint')" ;; esac

# #407: Step 3 passes --no-marketplace exactly when S2 printed (clone), with the REAL install-plan
# script and a scope: user agent of this repository, and stops naming FORGE_KIT_SRC when it is unset.
echo "== #407: Step 3 reads S2's library source =="
S3=$(fence 'forge-adapt-install-plan.sh <file>' | sed 's|<file>|plugins/forge-kit-governance/agents/ticket-gate.md|')
s3() { bout=$(cd "$ROOT" && env -i PATH="$PATH" HOME="$EH" "$@" bash -c "$S3" 2>"$T/berr"); brc=$?; berr=$(cat "$T/berr"); }
s3 FORGE_KIT_DIR="$ROOT" FORGE_KIT_SRC=clone
case "$bout" in copy*"installed from a clone, so there is no marketplace to register with"*) ok "#407: a clone library gets copy" ;; *) bad "#407: a clone library: '$bout' (rc $brc)" ;; esac
s3 FORGE_KIT_DIR="$ROOT" FORGE_KIT_SRC=marketplace
case "$bout" in register*) ok "#407: a marketplace library gets register" ;; *) bad "#407: a marketplace library: '$bout' (rc $brc)" ;; esac
s3 FORGE_KIT_DIR="$ROOT"
[ "$brc" != 0 ] && [ -z "$bout" ] && case "$berr" in *FORGE_KIT_SRC*) true ;; *) false ;; esac \
  && ok "#407: FORGE_KIT_SRC unset: exits non-zero naming it, printing neither register nor copy" \
  || bad "#407: FORGE_KIT_SRC unset: rc $brc, out '$bout', stderr '$berr'"
# Mutant: the never-assigned flag restored; a clone install then registers.
S3=$(printf '%s\n' "$S3" | sed -e '/FORGE_KIT_SRC:?/d' -e 's/\${NM:-}/${NO_MARKETPLACE:+--no-marketplace}/')
s3 FORGE_KIT_DIR="$ROOT" FORGE_KIT_SRC=clone
case "$bout" in register*) ok "#407: mutant: the NO_MARKETPLACE form registers a clone install, so the copy row above dies on it" ;; *) bad "#407: mutant did not register: '$bout'" ;; esac

echo ""
echo "forge-adapt host probe tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
