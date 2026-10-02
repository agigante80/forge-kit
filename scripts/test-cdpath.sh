#!/usr/bin/env bash
# Contract test for #377: every shipped asset and repository script behaves the same under an
# exported CDPATH as without one. A bare `cd <relative>` consults CDPATH: it can enter a same-named
# directory elsewhere, and it echoes the directory it entered, which corrupts a `$(cd ... && pwd)`
# capture and a stdout rows contract. The fix at every site is `CDPATH= cd -- ...`; #379's guard
# keeps a new bare one out.
#
# HOW. The working tree is mirrored into a throwaway git repository, and a DECOY tree holds an empty
# copy of every directory in it, so `CDPATH=<decoy>` resolves any relative `cd` into the decoy.
# Each probe runs an entry point twice, with CDPATH unset and with it set, and the two runs must
# agree byte for byte (stdout, stderr and rc). Then each fixed file is reverted in the mirror, one
# at a time, and its own probe must disagree: a mutant per file, so a probe that never reaches the
# fixed line cannot pass for one that does. The leak-guard self-skip pairs, the roadmap write
# target and check-doc-drift's rows run as named cases.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unset CDPATH

# The mirror: tracked files as they are on disk now (uncommitted edits included), committed twice so
# a range exists, plus a decoy holding every directory of it and a decoy `repo`.
M="$W/repo"; DECOY="$W/decoy"; mkdir -p "$M" "$DECOY/repo"
git -C "$ROOT" ls-files -z | tar -C "$ROOT" --null -T - -cf - 2>/dev/null | tar -C "$M" -xf -
( cd "$M" && git init -q . && git config user.email t@t.invalid && git config user.name t \
  && git add -A && git commit -qm one && git commit -q --allow-empty -m two ) || { echo "could not build the mirror"; exit 1; }
( cd "$M" && find . -type d -not -path './.git*' ) | while IFS= read -r d; do mkdir -p "$DECOY/$d" "$DECOY/repo/$d"; done
RANGE="$(git -C "$M" rev-parse HEAD~1)..$(git -C "$M" rev-parse HEAD)"

# same <dir> <cmd...>: run <cmd> from <dir> without and with CDPATH=$DECOY; 0 when both agree. The
# set arm reads ${CDP_SET:-$DECOY}, so cdp_live can set an empty directory instead, and the unset
# arm is kept in $W/same-a, so cdp_live can compare it with the genuine file's (#360).
same() {
  local d=$1; shift
  local a b
  a=$(cd "$d" && env -u CDPATH "$@" 2>&1 </dev/null; echo "rc=$?")
  b=$(cd "$d" && CDPATH="${CDP_SET:-$DECOY}" "$@" 2>&1 </dev/null; echo "rc=$?")
  printf '%s\n' "$a" > "$W/same-a"
  [ "$a" = "$b" ]
}

# The probe for each fixed file: entry points by `--help` (their HERE is resolved before it), root-
# taking guards by a relative root the decoy shadows, check-restatements outside any git repo.
probe() {
  case "$1" in
    plugins/*/assets/sync-labels.sh|plugins/*/assets/release-run.sh|plugins/*/assets/count-gate-rounds.sh|\
    plugins/*/assets/forge-gate-mechanics.sh|plugins/*/assets/gate-status.sh|plugins/*/assets/check-phases.sh|\
    plugins/*/assets/reassess-phases.sh|plugins/*/assets/sync-phases.sh|scripts/validate-plugins.sh)
      same "$M" bash "$1" --help ;;
    scripts/guard-lib.sh) same "$W" bash -c '. repo/scripts/guard-lib.sh; guard_tracked_files repo | tr "\0" "\n"' ;;
    scripts/check-label-taxonomy.sh|scripts/check-neighbour-overlap.sh|scripts/check-reference-depth.sh|scripts/check-test-suites-wired.sh)
      same "$W" bash "repo/$1" repo ;;
    scripts/neighbour-manifest.sh) c_manifest ;;
    scripts/check-doc-drift.sh) same "$W" bash "repo/$1" --root repo --range "$RANGE" --docs README.md ;;
    scripts/check-restatements.sh) same "$W" bash "repo/$1" ;;
    plugins/*/assets/roadmap-lib.sh) c_roadmap ;;
    plugins/*/assets/check-public-leaks.sh) c_public_neg ;;
    plugins/*/assets/check-private-leaks.sh) c_private_neg ;;
    scripts/forge-adapt-agent-skills.sh) c_agent_skills ;;
    *) return 2 ;;
  esac
}

# The roadmap write target (#377: _rm_commit resolves a relative symlink): driving roadmap_set_state
# through a symlink must write the real file and leave a decoy of the same relative name untouched.
c_roadmap() {
  local r="$W/rm" lib="$M/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/roadmap-lib.sh"
  rm -rf "$r"; mkdir -p "$r/real" "$r/docs" "$DECOY/real" "$DECOY/docs"
  printf '# Roadmap\n\n## Phase: One\nstate: planned\n\nWhy.\n' > "$r/real/roadmap.md"
  cp "$r/real/roadmap.md" "$DECOY/real/roadmap.md"; ln -s ../real/roadmap.md "$r/docs/roadmap.md"
  ( cd "$r" && CDPATH="${CDP_SET:-$DECOY}" bash -c '. "$1"; roadmap_set_state docs/roadmap.md One open' _ "$lib" ) >/dev/null 2>&1
  grep -q '^state: open$' "$r/real/roadmap.md" && grep -q '^state: planned$' "$DECOY/real/roadmap.md"
}
# The leak guards' self-skip (#377): run by absolute path under CDPATH=. with the scanner's own source
# tracked, it must report only the planted leak, never its own lines.
lg_repo() {  # lg_repo <dir> <scanner>: a repo tracking only a copy of the scanner at assets/
  rm -rf "$1"; mkdir -p "$1/assets"; cp "$2" "$1/assets/"
  ( cd "$1" && git init -q . && git add -A ) >/dev/null 2>&1
}
c_public_pos() {
  local r="$W/lgp" s="$M/plugins/forge-kit-security/skills/leak-guard/assets/check-public-leaks.sh" o rc
  lg_repo "$r" "$s"; o=$(cd "$r" && CDPATH="${CDP_SET:-.}" bash "$PWD/assets/check-public-leaks.sh" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && [ -z "$o" ]; }
c_public_neg() {
  local r="$W/lgp" s="$M/plugins/forge-kit-security/skills/leak-guard/assets/check-public-leaks.sh" o rc
  lg_repo "$r" "$s"; printf 'see /%s/someone/notes\n' home > "$r/notes.txt"; git -C "$r" add notes.txt
  o=$(cd "$r" && CDPATH="${CDP_SET:-.}" bash "$PWD/assets/check-public-leaks.sh" 2>/dev/null); rc=$?
  [ "$rc" = 1 ] && [ -n "$o" ] && ! grep -qv '^notes.txt:1: home-path:' <<< "$o"; }
c_private_pos() {
  local r="$W/lgq" s="$M/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh" o rc
  lg_repo "$r" "$s"; printf 'private-name\nacme-migration\n' > "$W/names.txt"
  o=$(cd "$r" && CDPATH="${CDP_SET:-.}" bash "$PWD/assets/check-private-leaks.sh" --list "$W/names.txt" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && [ -z "$o" ]; }
c_private_neg() {
  local r="$W/lgq" s="$M/plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh" o rc
  lg_repo "$r" "$s"; printf 'private-name\nacme-migration\n' > "$W/names.txt"
  printf 'acme-migration\n' > "$r/notes.txt"; git -C "$r" add notes.txt
  o=$(cd "$r" && CDPATH="${CDP_SET:-.}" bash "$PWD/assets/check-private-leaks.sh" --list "$W/names.txt" 2>/dev/null); rc=$?
  [ "$rc" = 1 ] && [ "$(grep -c . <<< "$o")" = 1 ] && grep -q '^notes.txt:1: private-name:' <<< "$o"; }
# forge-adapt-agent-skills --rewrite resolves an agent file's relative symlink target (line ~156):
# under a decoy holding the same relative directories it must rewrite the real target and leave the
# decoy's copy alone.
c_agent_skills() {
  local r="$W/as" s="$M/scripts/forge-adapt-agent-skills.sh"
  rm -rf "$r"; mkdir -p "$r/agents" "$r/src" "$DECOY/src" "$DECOY/agents"
  printf -- '---\nname: a\nskills:\n  - forge-kit-x:real-skill\n---\nbody\n' > "$r/src/a.md"
  cp "$r/src/a.md" "$DECOY/src/a.md"; ln -s ../src/a.md "$r/agents/a.md"
  ( cd "$r" && CDPATH="${CDP_SET:-$DECOY}" bash "$s" --rewrite agents/a.md ) >/dev/null 2>&1
  grep -q '^  - real-skill$' "$r/src/a.md" && grep -q 'forge-kit-x:real-skill' "$DECOY/src/a.md" && [ -L "$r/agents/a.md" ]
}
# neighbour-manifest enters its --root before writing docs/neighbours.tsv: a relative root the decoy
# shadows must still produce the same rows on stdout and the same file.
c_manifest() {
  local a b
  mkdir -p "$W/mk"
  a=$(cd "$W" && env -u CDPATH bash repo/scripts/neighbour-manifest.sh --refresh --marketplaces "$W/mk" --root repo 2>&1; echo "rc=$?"; cat repo/docs/neighbours.tsv)
  b=$(cd "$W" && CDPATH="${CDP_SET:-$DECOY}" bash repo/scripts/neighbour-manifest.sh --refresh --marketplaces "$W/mk" --root repo 2>&1; echo "rc=$?"; cat repo/docs/neighbours.tsv)
  git -C "$M" checkout -q -- docs/neighbours.tsv 2>/dev/null
  rm -f "$DECOY/repo/docs/neighbours.tsv"
  printf '%s\n' "$a" > "$W/same-a"
  [ "$a" = "$b" ]
}

echo "== every fixed entry point agrees with and without CDPATH =="
FILES="plugins/forge-kit-devops/skills/forge-host/assets/sync-labels.sh
plugins/forge-kit-devops/skills/release-automation/assets/release-run.sh
plugins/forge-kit-governance/skills/ticket-gate-reference/assets/count-gate-rounds.sh
plugins/forge-kit-governance/skills/ticket-gate-reference/assets/forge-gate-mechanics.sh
plugins/forge-kit-governance/skills/ticket-gate-reference/assets/gate-status.sh
plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh
plugins/forge-kit-roadmap/skills/roadmap-phases/assets/reassess-phases.sh
plugins/forge-kit-roadmap/skills/roadmap-phases/assets/roadmap-lib.sh
plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh
plugins/forge-kit-security/skills/leak-guard/assets/check-private-leaks.sh
plugins/forge-kit-security/skills/leak-guard/assets/check-public-leaks.sh
scripts/check-doc-drift.sh
scripts/check-label-taxonomy.sh
scripts/check-neighbour-overlap.sh
scripts/check-reference-depth.sh
scripts/check-restatements.sh
scripts/check-test-suites-wired.sh
scripts/forge-adapt-agent-skills.sh
scripts/guard-lib.sh
scripts/neighbour-manifest.sh
scripts/validate-plugins.sh"
mkdir -p "$W/live" "$W/empty"
live_key() { printf '%s' "$1" | tr / _; }
while IFS= read -r f; do
  rm -f "$W/same-a"
  probe "$f" && ok "$f behaves the same under CDPATH" || bad "$f differs under CDPATH"
  [ -f "$W/same-a" ] && mv "$W/same-a" "$W/live/$(live_key "$f")"
done <<<"$FILES"
c_public_pos && ok "the public leak guard skips its own source under CDPATH=. (clean repo: rc 0, empty)" || bad "the public leak guard reported its own source under CDPATH=."
c_private_pos && ok "the private leak guard skips its own source under CDPATH=. (clean repo: rc 0, empty)" || bad "the private leak guard reported its own source under CDPATH=."

echo "== mutants: each file's fixes reverted, its probe must disagree =="
. "$ROOT/scripts/mutant-crash.sh"
# cdp_live <file>: the reverted file still works where a bare cd behaves as unset, CDPATH set to an
# empty directory (#360). Its probe must pass and, for a same probe, the unset arm must equal the
# genuine file's, since a crash makes both arms agree.
cdp_live() {
  rm -f "$W/same-a"
  CDP_SET="$W/empty" probe "$1" || return 1
  [ -f "$W/same-a" ] || return 0
  cmp -s "$W/same-a" "$W/live/$(live_key "$1")"
}
cdp_mutant() {  # cdp_mutant <file> [<extra sed expr>]: the file's fixes reverted; its probe must disagree
  local f="$1" held=0 why
  cp "$M/$f" "$W/orig"
  sed -e 's/CDPATH= cd -- /cd /g' ${2:+-e "$2"} "$W/orig" > "$M/$f"
  if cmp -s "$W/orig" "$M/$f"; then bad "mutant $f: nothing to revert"; cp "$W/orig" "$M/$f"; return; fi
  probe "$f" && held=1
  why=$(mutant_crash_reason_live "$M/$f" cdp_live "$f")
  if [ -n "$why" ]; then bad "mutant $f crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant $f survived its probe"
  else ok "mutant $f (bare cd restored) dies"; fi
  cp "$W/orig" "$M/$f"
}
while IFS= read -r f; do cdp_mutant "$f"; done <<<"$FILES"
# Crash control (#360): a revert that exits, on a named case that credited it and on a same probe
# that read it as a survivor. cdp_mutant runs in $( ), so its rows stay out of the total.
CRASH_X='1a\
exit 127'
crash_ok=1; crashed=0
for f in scripts/forge-adapt-agent-skills.sh scripts/check-doc-drift.sh; do
  sed -e 's/CDPATH= cd -- /cd /g' -e "$CRASH_X" "$M/$f" > "$W/crash.sh"
  cmp -s "$W/crash.sh" "$M/$f" && crash_ok=0
  cap=$(cdp_mutant "$f" "$CRASH_X")
  case "$cap" in *" dies"*|*"survived its probe"*) crash_ok=0 ;; *"FAIL: mutant $f crashed ("*) crashed=$((crashed + 1)) ;; esac
  cmp -s "$M/$f" "$ROOT/$f" || crash_ok=0
done
[ "$crash_ok" = 1 ] && [ "$crashed" = 2 ] && ok "crash control (#360): cdpath reports a crashing revert as crashed, never as dies or a survivor" \
  || bad "crash control (#360): cdpath credited or missed a crashing revert ($crashed of 2 crashed)"

echo "== no unsafe cd is left in a shipped asset or repository script =="
left=$(cd "$ROOT" && grep -nE '(^|[^A-Za-z_=])cd( |$)' plugins/*/skills/*/assets/*.sh $(ls scripts/*.sh | grep -v '/test-') 2>/dev/null \
  | grep -v 'CDPATH= cd' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | grep -vF 'check-contributor-docs.sh:' | grep -vE 'cd "\$\(git rev-parse --show-toplevel')
[ -z "$left" ] && ok "every remaining bare cd is an absolute or git-toplevel path" || bad "a bare cd remains: $left"

echo ""
echo "cdpath tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
