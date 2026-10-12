#!/usr/bin/env bash
# Contract test for scripts/build-mac-shell-harness.sh (#220). It builds NOTHING and touches no
# network: every case runs the script through its seams (HARNESS_DIR, the source URL and digest, the
# awk repository and commit, a sandbox PATH with or without `cc`) against `file://` fixtures, with
# logging stubs for cc, make, bison and curl wherever a case must prove nothing compiled or fetched.
# The real build is verified by hand (the documented command in the script's --help).
# Its count line in the root CLAUDE.md is added by hand and its number written by
# update-suite-counts.py. NOTHING catches the line's absence: --check and the pre-push hook's
# --changed run verify only claims that already exist.
set -uo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/.." && pwd)"
SCRIPT="$HERE/build-mac-shell-harness.sh"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (no '$3' in: $2)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 ('$3' present in: $2)" ;; *) ok "$1" ;; esac; }
T=$(mktemp -d); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
BASHBIN="$(command -v bash)"

# The sandbox PATH: the real tools the script needs, linked one by one, so a case can leave `cc` out.
mkdir -p "$T/tools" "$T/stubs" "$T/logs"
for t in sh git dirname cat ls uname rm rmdir mkdir cut curl sha256sum head tail cp mv tar gzip touch; do
  p="$(command -v "$t")" || { echo "test prerequisite missing: $t"; exit 1; }
  ln -s "$p" "$T/tools/$t"
done
# Logging stubs: each records its call and fails, so a non-empty log means something compiled.
for t in cc make bison curl; do
  printf '#!%s\necho "%s $*" >> "%s/logs/%s"\nexit 1\n' "$BASHBIN" "$t" "$T" "$t" > "$T/stubs/$t"
  chmod +x "$T/stubs/$t"
done
mkdir -p "$T/nocc"; ln -s "$T/stubs/make" "$T/nocc/make"; ln -s "$T/stubs/bison" "$T/nocc/bison"
mkdir -p "$T/build"; for t in cc make bison; do ln -s "$T/stubs/$t" "$T/build/$t"; done
P_NOCC="$T/nocc:$T/tools"          # make and bison present, cc absent
P_BUILD="$T/build:$T/tools"        # every tool present; the compile tools are failing stubs
P_REUSE="$T/stubs:$T/tools"        # curl, cc and make are stubs: a reuse that fetched would log
logs() { cat "$T"/logs/* 2>/dev/null; }
clear_logs() { rm -f "$T"/logs/*; }

# Fixtures: a source tarball with its digest, and a git repository with one commit.
mkdir -p "$T/fx/bash-0"; echo fixture > "$T/fx/bash-0/README"
tar -czf "$T/fx/bash.tar.gz" -C "$T/fx" bash-0
FX_SHA="$(sha256sum < "$T/fx/bash.tar.gz" | cut -d' ' -f1)"
git init -q "$T/fx/awk" && echo a > "$T/fx/awk/f" && git -C "$T/fx/awk" add f \
  && git -C "$T/fx/awk" -c user.email=t@example.invalid -c user.name=t commit -qm fixture
FX_URL="file://$T/fx/bash.tar.gz"
FX_REPO="file://$T/fx/awk"
ABSENT_SHA=0123456789abcdef0123456789abcdef01234567

# run <PATH> <env assignments...> -- <args...>: sets RC, OUT, ERR. The env is cleared of every seam.
run() {
  local path="$1"; shift
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env -u HARNESS_BASH_URL -u HARNESS_BASH_SHA256 -u HARNESS_AWK_REPO -u HARNESS_AWK_COMMIT -u CC \
    PATH="$path" HOME="$T/home" XDG_CACHE_HOME="$T/xdg" ${envs[@]+"${envs[@]}"} \
    "$BASHBIN" "$SCRIPT" "$@" > "$T/out" 2> "$T/err"
  RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
# The stamp the default pins produce, in the format the script header documents.
stamp() {
  printf 'format=1\nbash_url=%s\nbash_sha256=%s\nawk_repo=%s\nawk_commit=%s\n' \
    "${1:-https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz}" \
    "${2:-3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4}" \
    "${3:-https://github.com/apple-oss-distributions/awk.git}" \
    "${4:-a958d4fe53ff6c37a17d7c0a1875fd2fc5e3ec90}"
}
# fake_build <dir> [stamp args]: a complete-looking build, as the script leaves one.
fake_build() {
  local d="$1"; shift
  mkdir -p "$d/bin"; printf '#!/bin/sh\n' > "$d/bin/bash"; printf '#!/bin/sh\n' > "$d/bin/awk"
  chmod +x "$d/bin/bash" "$d/bin/awk"; stamp "$@" > "$d/.mac-shell-harness-stamp"
}

echo "== usage =="
run "$P_NOCC" -- --help
expect "--help exits 0" 0 "$RC"
has "--help carries the documented command" "$OUT" "PATH=\"\$H:\$PATH\" bash -c 'echo \"harness: bash \$BASH_VERSION, \$(awk --version)\"; bash scripts/test-check-public-leaks.sh && bash scripts/test-check-private-leaks.sh'"
has "--help states the host-architecture caveat" "$OUT" "HOST architecture"
run "$P_NOCC" -- --bogus
expect "an unknown argument exits 2" 2 "$RC"

echo "== preflight refuses before any fetch =="
clear_logs
run "$P_NOCC" HARNESS_DIR="$T/o-nocc" --
expect "no compiler: exit 1" 1 "$RC"
has "no compiler: the refusal names cc" "$ERR" "missing required tool(s): cc"
expect "no compiler: stdout is empty" "" "$OUT"
[ ! -e "$T/o-nocc" ] && [ ! -e "$T/o-nocc.partial" ] && ok "no compiler: no output or .partial directory is left" \
  || bad "no compiler: an output directory was created"
run "$P_BUILD" HARNESS_DIR="$T/o-cc" CC=no-such-compiler --
has "a \$CC that does not resolve is the one named" "$ERR" "missing required tool(s): no-such-compiler"
clear_logs

echo "== the seams refuse an empty or malformed pin =="
run "$P_BUILD" HARNESS_DIR="$T/o-e1" HARNESS_BASH_SHA256= --
expect "an empty digest override exits 1" 1 "$RC"
has "an empty digest override is named" "$ERR" "HARNESS_BASH_SHA256 is set but empty"
run "$P_BUILD" HARNESS_DIR="$T/o-e2" HARNESS_AWK_COMMIT= --
has "an empty commit override is refused" "$ERR" "HARNESS_AWK_COMMIT is set but empty"
run "$P_BUILD" HARNESS_DIR="$T/o-e3" HARNESS_AWK_COMMIT=a958d4fe --
has "a short commit is refused (a pin is a full SHA)" "$ERR" "full 40-character SHA"
run "$P_BUILD" HARNESS_DIR="$T/o-e4" HARNESS_BASH_SHA256=XYZ --
has "a malformed digest is refused" "$ERR" "64 lowercase hex"
[ ! -e "$T/o-e1.partial" ] && [ ! -e "$T/o-e3.partial" ] && ok "a refused seam creates nothing" \
  || bad "a refused seam created a .partial"

echo "== a failed fetch refuses and leaves no build =="
clear_logs
run "$P_BUILD" HARNESS_DIR="$T/o-f" HARNESS_BASH_URL="file://$T/fx/missing.tar.gz" HARNESS_BASH_SHA256="$FX_SHA" --
expect "a failed fetch exits 1" 1 "$RC"
has "a failed fetch is named" "$ERR" "could not fetch file://$T/fx/missing.tar.gz"
has "an override prints the WARNING" "$ERR" "WARNING: HARNESS_BASH_URL overrides a pinned input"
[ ! -e "$T/o-f" ] && ok "a failed fetch leaves no output directory" || bad "a failed fetch left $T/o-f"
[ ! -e "$T/o-f.partial/.mac-shell-harness-stamp" ] && ok "a failed fetch writes no stamp" || bad "a failed fetch wrote a stamp"
expect "a failed fetch compiled nothing" "" "$(logs)"

echo "== a digest mismatch refuses before extraction =="
mkdir -p "$T/o-d.partial"; echo leftover > "$T/o-d.partial/marker"
run "$P_BUILD" HARNESS_DIR="$T/o-d" HARNESS_BASH_URL="$FX_URL" HARNESS_BASH_SHA256="$(printf '0%.0s' $(seq 64))" --
expect "a digest mismatch exits 1" 1 "$RC"
has "the mismatch is named" "$ERR" "digest mismatch for $FX_URL"
[ ! -e "$T/o-d.partial/src/bash-0" ] && ok "nothing was extracted" || bad "the tarball was extracted"
[ ! -e "$T/o-d.partial/src/bash.tar.gz" ] && ok "the mismatched tarball is deleted" || bad "the mismatched tarball was kept"
[ ! -e "$T/o-d.partial/src/awk" ] && ok "the awk source is not fetched after a bash mismatch" || bad "awk was fetched after a mismatch"
[ ! -e "$T/o-d" ] && ok "a digest mismatch leaves no output directory" || bad "a digest mismatch left $T/o-d"
[ ! -e "$T/o-d.partial/marker" ] && ok "a leftover .partial is deleted and the build restarts" || bad "the leftover .partial survived"
has "the leftover deletion is announced" "$ERR" "deleting the leftover"
expect "a digest mismatch compiled nothing" "" "$(logs)"

echo "== an awk commit mismatch refuses =="
run "$P_BUILD" HARNESS_DIR="$T/o-a" HARNESS_BASH_URL="$FX_URL" HARNESS_BASH_SHA256="$FX_SHA" \
  HARNESS_AWK_REPO="$FX_REPO" HARNESS_AWK_COMMIT="$ABSENT_SHA" --
expect "an awk commit not in the repository exits 1" 1 "$RC"
has "the bash digest was verified first" "$ERR" "bash tarball digest verified ($FX_SHA)"
has "the absent commit is named" "$ERR" "could not fetch commit $ABSENT_SHA"
[ ! -e "$T/o-a.partial/src/bash-0" ] && ok "nothing extracted when awk fails" || bad "bash was extracted before awk verified"
[ ! -e "$T/o-a" ] && ok "an awk mismatch leaves no output directory" || bad "an awk mismatch left $T/o-a"
expect "an awk mismatch compiled nothing" "" "$(logs)"
hasnt "the default URL is never fetched by an overridden run" "$ERR" "ftp.gnu.org"

echo "== reuse =="
fake_build "$T/o-r"
clear_logs
run "$P_REUSE" HARNESS_DIR="$T/o-r" --
expect "a complete build is reused: exit 0" 0 "$RC"
expect "the stdout contract is exactly three lines" "HARNESS_BIN=$T/o-r/bin
HARNESS_BASH=$T/o-r/bin/bash
HARNESS_AWK=$T/o-r/bin/awk" "$OUT"
has "the reuse is said" "$ERR" "nothing rebuilt"
has "the closing output states the caveat" "$ERR" "not macOS"
hasnt "a pinned run prints no WARNING" "$ERR" "WARNING"
expect "a reuse fetches and compiles nothing" "" "$(logs)"
[ ! -e "$T/o-r.partial" ] && ok "a reuse creates no .partial" || bad "a reuse created a .partial"
run "$P_REUSE" HARNESS_DIR="$T/o-r" -- --bin-dir
expect "--bin-dir with a build exits 0" 0 "$RC"
expect "--bin-dir prints only the bin directory" "$T/o-r/bin" "$OUT"
run "$P_REUSE" XDG_CACHE_HOME="$T/xdg2" -- --bin-dir
expect "--bin-dir with no build exits 1" 1 "$RC"
expect "--bin-dir with no build prints nothing on stdout" "" "$OUT"
has "the default directory is under XDG_CACHE_HOME" "$ERR" "$T/xdg2/forge-kit/mac-shell-harness"
[ ! -e "$T/xdg2" ] && ok "--bin-dir never builds or creates anything" || bad "--bin-dir created $T/xdg2"
fake_build "$T/xdg3/forge-kit/mac-shell-harness"
run "$P_REUSE" XDG_CACHE_HOME="$T/xdg3" --
expect "with no HARNESS_DIR the XDG cache build is the one reused" "$T/xdg3/forge-kit/mac-shell-harness/bin" \
  "$(printf '%s\n' "$OUT" | head -1 | cut -d= -f2-)"

echo "== nothing but a stamped, complete build is ever reported ready =="
fake_build "$T/o-p.partial"
run "$P_REUSE" HARNESS_DIR="$T/o-p" -- --bin-dir
expect "a leftover .partial with a stamp is not a build (--bin-dir exits 1)" 1 "$RC"
expect "and prints nothing" "" "$OUT"
fake_build "$T/o-r2"
run "$P_REUSE" HARNESS_DIR="$T/o-r2" HARNESS_AWK_COMMIT="$ABSENT_SHA" -- --bin-dir
expect "a stamp for other pins is not reused (--bin-dir exits 1)" 1 "$RC"
fake_build "$T/o-o" "" "$(printf '1%.0s' $(seq 64))"
run "$P_NOCC" HARNESS_DIR="$T/o-o" --
expect "a stamp for other pins: a full run goes on to rebuild (refused here for cc)" 1 "$RC"
has "the rebuild is announced" "$ERR" "records other pins"
expect "and nothing is reported on stdout" "" "$OUT"
[ -f "$T/o-o/.mac-shell-harness-stamp" ] && ok "the old build is kept until a new one succeeds" || bad "the old build was deleted before success"
fake_build "$T/o-x"; rm "$T/o-x/bin/awk"
run "$P_REUSE" HARNESS_DIR="$T/o-x" -- --bin-dir
expect "a stamped build missing bin/awk is not reused" 1 "$RC"
mkdir -p "$T/o-n/bin"; printf '#!/bin/sh\n' > "$T/o-n/bin/bash"; cp "$T/o-n/bin/bash" "$T/o-n/bin/awk"; chmod +x "$T/o-n/bin/"*
run "$P_BUILD" HARNESS_DIR="$T/o-n" --
expect "a directory with no stamp is refused" 1 "$RC"
has "the refusal says it is not a harness build" "$ERR" "is not a harness build"
[ -f "$T/o-n/bin/awk" ] && ok "a directory with no stamp is never deleted" || bad "a stampless directory was deleted"
expect "no stamp: stdout is empty" "" "$OUT"

echo "== the output directory =="
git init -q "$T/wt"
run "$P_REUSE" HARNESS_DIR="$T/wt/h" -- --bin-dir
expect "a HARNESS_DIR inside a work tree git does not ignore exits 1" 1 "$RC"
has "the refusal names the reason" "$ERR" "inside a git work tree and not ignored"
printf 'h/\nh.partial/\n' > "$T/wt/.gitignore"
run "$P_REUSE" HARNESS_DIR="$T/wt/h" -- --bin-dir
hasnt "an ignored HARNESS_DIR inside a work tree is accepted (dir/ patterns, dirs not yet created)" "$ERR" "not ignored"
has "and reaches the no-build answer instead" "$ERR" "no complete build at $T/wt/h"
printf 'h/\n' > "$T/wt/.gitignore"
run "$P_REUSE" HARNESS_DIR="$T/wt/h" -- --bin-dir
has "an ignored dir whose .partial is not ignored is refused" "$ERR" "$T/wt/h.partial is inside a git work tree and not ignored"
fake_build "$T/rel/h"
( CDPATH= cd -- "$T/rel" && env -u HARNESS_DIR PATH="$P_REUSE" HARNESS_DIR=h "$BASHBIN" "$SCRIPT" --bin-dir ) > "$T/out" 2>&1
expect "a relative HARNESS_DIR resolves against the working directory" "$T/rel/h/bin" "$(cat "$T/out")"
if [ "$(id -u)" != 0 ]; then
  mkdir -p "$T/ro"; chmod 555 "$T/ro"
  run "$P_BUILD" HARNESS_DIR="$T/ro/h" --
  expect "a read-only output location exits 1" 1 "$RC"
  has "the read-only refusal is named" "$ERR" "cannot create $T/ro/h.partial"
  chmod 755 "$T/ro"
else
  ok "read-only case skipped: running as root, which ignores the permission"
fi

echo "== the pins and the build requirements, as text =="
code() { grep -v '^[[:space:]]*#' "$SCRIPT"; }
has "the bash tarball pin" "$(code)" "PIN_BASH_SHA256='3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4'"
has "the awk commit pin" "$(code)" "PIN_AWK_COMMIT='a958d4fe53ff6c37a17d7c0a1875fd2fc5e3ec90'"
has "the bash C dialect is pinned (GCC 14 and 15)" "$(code)" "BASH_CFLAGS='-O2 -std=gnu89'"
has "the awk C dialect is pinned" "$(code)" "AWK_CFLAGS='-O2 -std=gnu11'"
has "the build-time helpers get the bash dialect too" "$(code)" 'CFLAGS_FOR_BUILD="$BASH_CFLAGS"'
has "an unpacked bison is pointed at its data files" "$(code)" 'export BISON_PKGDATADIR='
has "the stale y.tab.c is regenerated by bison" "$(code)" 'YACC="$BISON -y"'
has "the generated awk files are touched" "$(code)" 'touch awkgram.tab.c awkgram.tab.h proctab.c'
has "the fmtcheck prototype is force-included" "$(code)" '-include $SRC/shim/shim.h'
has "m4 is in the unpacked-bison preflight" "$(code)" 'for t in apt-get dpkg dpkg-deb m4; do'
hasnt "apt is never told to skip its signature check" "$(code)" "allow-unauthenticated"

echo "== no CI step, hook or component invokes the script (exact token) =="
# The token rule: the name not preceded by [A-Za-z0-9_-], so the suite's own `test-` step is not a hit.
TOKEN='(^|[^A-Za-z0-9_-])build-mac-shell-harness\.sh'
refs() { grep -rlE "$TOKEN" "$1/.github/workflows" "$1/.githooks" "$1/plugins" 2>/dev/null; }
expect "the tree has no reference in workflows, hooks or plugins" "" "$(refs "$ROOT")"
has "the suite's own validate.yml step exists" "$(cat "$ROOT/.github/workflows/validate.yml")" \
  "run: bash scripts/test-build-mac-shell-harness.sh"
mkdir -p "$T/ref/.github/workflows" "$T/ref/.githooks" "$T/ref/plugins/g/skills/s"
printf '      - run: bash scripts/test-build-mac-shell-harness.sh\n' > "$T/ref/.github/workflows/v.yml"
expect "the suite's own step is not a reference" "" "$(refs "$T/ref")"
printf '      - run: bash scripts/build-mac-shell-harness.sh\n' > "$T/ref/.github/workflows/w.yml"
expect "MUTANT: a planted workflow reference is caught" "$T/ref/.github/workflows/w.yml" "$(refs "$T/ref")"
rm "$T/ref/.github/workflows/w.yml"
printf 'build-mac-shell-harness.sh --bin-dir\n' > "$T/ref/.githooks/pre-push"
expect "MUTANT: a planted hook reference (bare, at line start) is caught" "$T/ref/.githooks/pre-push" "$(refs "$T/ref")"
rm "$T/ref/.githooks/pre-push"
printf 'Run `scripts/build-mac-shell-harness.sh` first.\n' > "$T/ref/plugins/g/skills/s/SKILL.md"
expect "MUTANT: a planted component reference is caught" "$T/ref/plugins/g/skills/s/SKILL.md" "$(refs "$T/ref")"

echo ""
echo "build-mac-shell-harness tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
