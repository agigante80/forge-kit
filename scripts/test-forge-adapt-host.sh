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

# The host block: from its leading comment to the line before the next block's comment.
BLOCK=$(awk '/^# (Forge host|Sentinel)/{p=1} /^# Domain\/pattern sample:/{p=0} p' "$SKILL")
[ -n "$BLOCK" ] || { echo "could not extract the host block from $SKILL"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
EH="$T/emptyhome"; mkdir -p "$EH"
NOLIB="$T/nolib"; mkdir -p "$NOLIB"
MH="$T/mhome/.claude/plugins/marketplaces"; mkdir -p "$MH"; ln -s "$ROOT" "$MH/forge-kit"
CH="$T/chome"; mkdir -p "$CH"; ln -s "$ROOT" "$CH/forge-kit"

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
  if printf '%s' "$out" | grep -qF -- "$WARN"; then warned=yes; else warned=no; fi
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
# plain git checkouts of the repo tracking origin/main, so fetch + reset --hard makes either current.
# The marketplace checkout is NOT auto-pulled between manual `/plugin marketplace update` runs and
# pins no SHA (known_marketplaces.json holds only source + installLocation), so resetting it forward
# lands exactly what an update would. A stale checkout both mis-catalogues versions and lacks the
# scripts/ and docs/ files a governance install copies.
#
# S2 FIXTURE RULE: S2's first statement discards an exported FORGE_KIT_DIR, and it runs fetch and
# reset --hard on any git checkout it picks, so every S2 fixture is a NON-git mktemp library placed
# where S2 looks, in a throwaway HOME, never the MH/CH symlinks to this repository; each S2 case
# asserts that no clone ran. GIT_CEILING_DIRECTORIES keeps git from finding an enclosing checkout.
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
  run_block "$b" FORGE_KIT_DIR="$L"
  case "$bout" in ok*) ok "#321: '$pat' runs from the library" ;; *) bad "#321: '$pat' did not run from the library (out '$bout', rc $brc)" ;; esac
  expect "#321: '$pat' exits 0 with the library" 0 "$brc"
  run_block "$b"
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
KL=$(lib); : > "$KL/scripts/check-template-lockstep.sh"; : > "$KL/scripts/test-template-lockstep.sh"
run_block "$KB" FORGE_KIT_DIR="$KL"
[ "$brc" = 0 ] && [ -f "$PROJ/scripts/check-template-lockstep.sh" ] && ok "#321: lockstep copies the guard from the library" || bad "#321: lockstep did not copy (rc $brc)"
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
s2() { local h="$1"; shift; bout=$(env -i PATH="$PATH" HOME="$h" GIT_CEILING_DIRECTORIES="$T" "$@" bash -c "$SB" 2>&1); brc=$?; }
H=$(s2home); s2 "$H"
case "$bout" in *governance-plugin-active=no*) ok "#321: S2 prints governance-plugin-active=no" ;; *) bad "#321: S2 printed no governance flag: $bout" ;; esac
case "$bout" in *": $H/.claude/plugins/marketplaces/forge-kit"*) ok "#321: S2 prints the library path" ;; *) bad "#321: S2 printed no library path: $bout" ;; esac
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (governance absent): no clone ran" || bad "#321: S2 cloned"
H=$(s2home); mkdir -p "$H/.claude/plugins/cache/forge-kit/forge-kit-governance"; s2 "$H"
case "$bout" in *governance-plugin-active=yes*) ok "#321: S2 prints governance-plugin-active=yes with the plugin installed" ;; *) bad "#321: S2 governance present: $bout" ;; esac
case "$bout" in *governance-plugin-active=no*) bad "#321: S2 also printed =no" ;; *) ok "#321: S2 governance present: no =no line" ;; esac
[ ! -e "$H/forge-kit" ] && ok "#321: S2 (governance present): no clone ran" || bad "#321: S2 cloned"
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
expect "#321: no later text reads \$FORGE_KIT_SRC" 0 "$(printf '%s\n' "$after" | grep -c 'FORGE_KIT_SRC')"
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

echo ""
echo "forge-adapt host probe tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
