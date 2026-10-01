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

echo ""
echo "forge-adapt host probe tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
