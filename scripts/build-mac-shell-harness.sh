#!/usr/bin/env bash
# build-mac-shell-harness.sh: build the shell and awk macOS ships (bash 3.2.57 and Apple's fork of
# BWK awk) from source on Linux, so the kit's bash 3.2 / Apple awk portability claim can be checked
# by anyone with a compiler instead of by the one person who still has the binaries (#220).
#
# A MAINTAINER TOOL, run deliberately. Nothing in CI, in either git hook or in any shipped component
# invokes it; its only caller there is scripts/test-build-mac-shell-harness.sh, which reaches the
# refusal and reuse paths through the seams below and never compiles or fetches over a network.
# #191 is the reason it exists: this build found two real defects nothing else would have (BWK awk
# refuses a newline inside a `-v` value; Apple's awk aborts with `towc: multibyte conversion
# failure` the moment a regex meets a byte over 0x7F).
#
# WHAT IT PROVES AND WHAT IT DOES NOT. The binaries are built for the HOST architecture, so they
# prove the shell and awk VERSION and behaviour, not macOS: BSD `tr`, Apple's `git` and the macOS
# filesystem are not exercised. The closing output says so every time.
#
# PINNED INPUTS (verified 2026-10-12). A mismatch on either is a refusal before anything is
# extracted or compiled.
#   bash 3.2.57: the GNU tarball, pinned by SHA-256. GNU publishes no checksum file for it (the
#     `.sha256` URL is 404), only a detached `.sig`; the digest below was recorded after
#     `gpgv --keyring gnu-keyring.gpg bash-3.2.57.tar.gz.sig bash-3.2.57.tar.gz` reported a good
#     signature from Chet Ramey (DSA key 7C0135FB088AAF6C66C650B9BB5869F064EA74AB, made
#     2014-11-07). Limits: the keyring came from the same host over HTTPS, and the signature is DSA
#     over SHA-1. This script checks the digest only and needs no gpg.
#   Apple awk: apple-oss-distributions/awk at the full commit tag `awk-40` peels to (resolved with
#     `git ls-remote --tags`; `awk-40` is that repository's newest tag). It is fetched BY SHA and
#     `git rev-parse HEAD` must equal the pin; the tag name is never used, because a tag can move.
#     Apple's source, not upstream BWK awk, is the faithful one: the `towc` abort, the
#     `__collate_lookup_l` call and `fmtcheck` are Apple's additions. A GitHub archive tarball is
#     not pinned by digest because GitHub does not guarantee archive bytes are stable.
#   bison (needed by the bash build): a system `bison` is used as is, on the same trust as the
#     system compiler. Without one it is obtained with `apt-get download bison` and unpacked with
#     `dpkg -x`, no root; the control is apt's own verification (the signed InRelease and the
#     package index's SHA-256), never `--allow-unauthenticated`. A pinned hash is not used because
#     the `.deb` differs by distribution release and architecture. Its name, version and SHA-256
#     are printed so the build is auditable.
#
# BUILD REQUIREMENTS (the traps, each one met below):
#   1. Preflight before any fetch: $CC (default `cc`), make, git, curl, tar, gzip, a SHA-256 tool,
#      and either `bison` or `apt-get`, `dpkg` and `m4` (the unpacked bison runs m4). Every missing
#      one is named in a single refusal.
#   2. Apple awk needs two macOS-only libc symbols glibc lacks, `__collate_lookup_l` and `fmtcheck`
#      (shim.c), an `xlocale.h` (gone from glibc since 2.26) that also brings `wctype_t`, and a
#      `fmtcheck` PROTOTYPE force-included into every file: without it the implicit int return
#      truncates the pointer and segfaults at run time on GCC 13, and is an error on GCC 14.
#   3. `touch awkgram.tab.c awkgram.tab.h proctab.c` before make, so the checked-in generated
#      files are not regenerated.
#   4. bash 3.2.57's shipped `y.tab.c` is stale, so make runs `YACC="<bison> -y"`. An unpacked
#      bison cannot find its data files on its own (it looks in /usr/share/bison), so
#      BISON_PKGDATADIR points into the unpacked tree and M4 names the system m4.
#   5. The C dialect is pinned, never inherited: GCC 14 turned implicit declarations and implicit
#      int into errors and GCC 15 defaults to C23, where bash 3.2.57's 69 `extern f ();`
#      declarations mean "no parameters". bash builds with -std=gnu89 (C89 mode keeps those valid;
#      verified with GCC 13.3 and 14.2, which without it fails), awk with -std=gnu11 (its own
#      dialect: stdnoreturn.h and stdbool.h). bash compiles its build-time helpers (bashversion,
#      mksyntax) with CFLAGS_FOR_BUILD, which defaults to `-g` and never inherits CFLAGS, so make is
#      given it too.
#   6. Both binaries land in one bin/ (awk under the name `awk`), so prepending one directory to
#      PATH swaps both.
#   7. The build happens in <dir>.partial; the completion stamp is written last and the directory
#      renamed to <dir> only on success. A leftover .partial is deleted and the build restarts, and
#      is never reported as ready. A <dir> whose stamp records other pins is rebuilt and replaced;
#      a <dir> with no stamp is not this script's and is refused rather than deleted.
#   8. It writes only inside <dir> and <dir>.partial and puts nothing on any PATH.
#
# OUTPUT DIRECTORY: ${XDG_CACHE_HOME:-$HOME/.cache}/forge-kit/mac-shell-harness, outside any work
# tree, so it outlives the task and no binary can be committed. A HARNESS_DIR inside a git work
# tree that git does not ignore is refused.
#
# STAMP: <dir>/.mac-shell-harness-stamp holds exactly these lines, in this order:
#   format=1
#   bash_url=<url>
#   bash_sha256=<digest>
#   awk_repo=<url>
#   awk_commit=<sha>
# A build is reusable only when the stamp equals the one the current pins produce and bin/bash and
# bin/awk are executable.
#
# TEST SEAMS (read from the environment). Any of them other than HARNESS_DIR prints a WARNING, so a
# seam cannot silently weaken a pin on a real build.
#   HARNESS_DIR                            the output directory
#   HARNESS_BASH_URL, HARNESS_BASH_SHA256  the tarball and its digest (an empty digest is refused)
#   HARNESS_AWK_REPO, HARNESS_AWK_COMMIT   the awk repository and full commit (empty is refused)
#   CC                                     the compiler (default cc)
#
# Usage: build-mac-shell-harness.sh [--bin-dir | --help]
# Stdout, on a build or a reuse, is exactly three lines: HARNESS_BIN=, HARNESS_BASH=, HARNESS_AWK=.
# --bin-dir prints only <dir>/bin for an existing complete build, and exits 1 without building when
# there is none. Every diagnostic goes to stderr.
# Exit: 0 built or reused, 1 refused or failed, 2 usage.
set -uo pipefail

PIN_BASH_URL='https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz'
PIN_BASH_SHA256='3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4'
PIN_AWK_REPO='https://github.com/apple-oss-distributions/awk.git'
PIN_AWK_COMMIT='a958d4fe53ff6c37a17d7c0a1875fd2fc5e3ec90'
BASH_CFLAGS='-O2 -std=gnu89'
AWK_CFLAGS='-O2 -std=gnu11'
STAMP_NAME='.mac-shell-harness-stamp'

usage() {
  cat <<'EOF'
Usage: scripts/build-mac-shell-harness.sh [--bin-dir | --help]

Builds bash 3.2.57 and Apple's awk (awk version 20200816) from pinned sources into
${XDG_CACHE_HOME:-$HOME/.cache}/forge-kit/mac-shell-harness (override with HARNESS_DIR), or reuses
an existing complete build. Needs a C compiler, make, git, curl, tar, gzip, a SHA-256 tool, and
bison or apt-get plus dpkg plus m4. Takes a few minutes the first time.

  (no option)  build or reuse; stdout is HARNESS_BIN=, HARNESS_BASH= and HARNESS_AWK= lines
  --bin-dir    print the bin directory of an existing complete build; exit 1 if there is none
  --help       this text

Run both leak suites under the harness (from the repository root):

  H="$(scripts/build-mac-shell-harness.sh --bin-dir)" && PATH="$H:$PATH" bash -c 'echo "harness: bash $BASH_VERSION, $(awk --version)"; bash scripts/test-check-public-leaks.sh && bash scripts/test-check-private-leaks.sh'

The binaries are the HOST architecture: they prove the shell and awk version and behaviour,
not macOS (BSD tr, Apple's git and the macOS filesystem are not exercised).
EOF
}

say()    { printf 'build-mac-shell-harness: %s\n' "$*" >&2; }
refuse() { say "REFUSED: $*"; exit 1; }

MODE=build
case "${1:-}" in
  '') ;;
  --bin-dir) MODE=bindir ;;
  -h|--help) usage; exit 0 ;;
  *) say "unknown argument: $1"; usage >&2; exit 2 ;;
esac
[ $# -le 1 ] || { say "at most one argument"; exit 2; }

# The seams. An override that is SET but empty is refused, never read as "use the pin".
for v in HARNESS_BASH_URL HARNESS_BASH_SHA256 HARNESS_AWK_REPO HARNESS_AWK_COMMIT; do
  if eval "[ -n \"\${$v+x}\" ]"; then
    eval "[ -n \"\${$v}\" ]" || refuse "$v is set but empty; unset it to use the pin"
    say "WARNING: $v overrides a pinned input; this build is NOT the pinned harness"
  fi
done
BASH_URL="${HARNESS_BASH_URL:-$PIN_BASH_URL}"
BASH_SHA256="${HARNESS_BASH_SHA256:-$PIN_BASH_SHA256}"
AWK_REPO="${HARNESS_AWK_REPO:-$PIN_AWK_REPO}"
AWK_COMMIT="${HARNESS_AWK_COMMIT:-$PIN_AWK_COMMIT}"
case "$BASH_SHA256" in
  *[!0-9a-f]*) refuse "the bash digest must be 64 lowercase hex characters: $BASH_SHA256" ;;
esac
[ "${#BASH_SHA256}" -eq 64 ] || refuse "the bash digest must be 64 lowercase hex characters: $BASH_SHA256"
case "$AWK_COMMIT" in
  *[!0-9a-f]*) refuse "the awk commit must be a full 40-character SHA: $AWK_COMMIT" ;;
esac
[ "${#AWK_COMMIT}" -eq 40 ] || refuse "the awk commit must be a full 40-character SHA: $AWK_COMMIT"

if [ -n "${HARNESS_DIR:-}" ]; then
  DIR="$HARNESS_DIR"
else
  [ -n "${HOME:-}" ] || [ -n "${XDG_CACHE_HOME:-}" ] || refuse "neither HOME nor XDG_CACHE_HOME is set; set HARNESS_DIR"
  DIR="${XDG_CACHE_HOME:-$HOME/.cache}/forge-kit/mac-shell-harness"
fi
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
DIR="${DIR%/}"
PARTIAL="$DIR.partial"

# Refuse an output directory git would offer to commit. The check runs from the nearest existing
# ancestor, because the directory itself may not exist yet, and asks about a FILE inside each of
# the two directories written, because a `dir/` ignore pattern does not match a path that does
# not exist yet but does match one beneath it.
anc="$DIR"
while [ ! -d "$anc" ]; do anc="$(dirname -- "$anc")"; done
if [ "$(git -C "$anc" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  for d in "$DIR" "$PARTIAL"; do
    git -C "$anc" check-ignore -q -- "$d/bin/bash" \
      || refuse "$d is inside a git work tree and not ignored; a binary there could be committed"
  done
fi

stamp_text() {
  printf 'format=1\nbash_url=%s\nbash_sha256=%s\nawk_repo=%s\nawk_commit=%s\n' \
    "$BASH_URL" "$BASH_SHA256" "$AWK_REPO" "$AWK_COMMIT"
}
reusable() {
  [ -f "$DIR/$STAMP_NAME" ] && [ -x "$DIR/bin/bash" ] && [ -x "$DIR/bin/awk" ] \
    && [ "$(cat "$DIR/$STAMP_NAME")" = "$(stamp_text)" ]
}
caveats() {
  say "these binaries are built for $(uname -m) $(uname -s): they prove the shell and awk VERSION and"
  say "behaviour, not macOS; BSD tr, Apple's git and the macOS filesystem are not exercised."
  say "run the leak suites under them with the command in --help."
}
report() {
  printf 'HARNESS_BIN=%s\nHARNESS_BASH=%s\nHARNESS_AWK=%s\n' "$DIR/bin" "$DIR/bin/bash" "$DIR/bin/awk"
}

if [ "$MODE" = bindir ]; then
  reusable || refuse "no complete build at $DIR; run scripts/build-mac-shell-harness.sh first"
  printf '%s\n' "$DIR/bin"
  exit 0
fi

if reusable; then
  say "reused the existing build at $DIR; nothing rebuilt"
  report; caveats; exit 0
fi

# A <dir> without our stamp is somebody else's directory: never delete it. An empty one is fine.
REPLACE=0
if [ -e "$DIR" ]; then
  if [ -f "$DIR/$STAMP_NAME" ]; then
    REPLACE=1; say "the build at $DIR records other pins or is damaged; rebuilding it"
  elif [ -d "$DIR" ] && [ -z "$(ls -A -- "$DIR")" ]; then
    rmdir -- "$DIR" || refuse "cannot remove the empty $DIR"
  else
    refuse "$DIR exists and is not a harness build (no $STAMP_NAME); remove it or set HARNESS_DIR"
  fi
fi

# Step 1: preflight, before any fetch.
CC="${CC:-cc}"
missing=""
for t in "$CC" make git curl tar gzip; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if command -v sha256sum >/dev/null 2>&1; then SHA() { sha256sum | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then SHA() { shasum -a 256 | cut -d' ' -f1; }
else missing="$missing sha256sum(or-shasum)"; fi
if command -v bison >/dev/null 2>&1; then BISON_FROM=system
else
  BISON_FROM=apt
  for t in apt-get dpkg dpkg-deb m4; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  case "$missing" in *apt-get*|*dpkg*) missing="$missing (or-bison)" ;; esac
fi
[ -z "$missing" ] || refuse "missing required tool(s):$missing"

# Step 2: a clean scratch inside <dir>.partial.
if [ -e "$PARTIAL" ]; then
  say "deleting the leftover $PARTIAL from an interrupted run"
  rm -rf -- "$PARTIAL" || refuse "cannot delete $PARTIAL"
fi
mkdir -p -- "$PARTIAL/bin" "$PARTIAL/src" 2>/dev/null || refuse "cannot create $PARTIAL (read-only?)"
SRC="$PARTIAL/src"
fail() { say "FAILED: $*"; say "the incomplete build is left in $PARTIAL for inspection; the next run deletes it"; exit 1; }

# Step 3: fetch and verify BOTH sources before extracting or compiling anything.
say "fetching $BASH_URL"
curl -fsSL -o "$SRC/bash.tar.gz" "$BASH_URL" || fail "could not fetch $BASH_URL"
got="$(SHA < "$SRC/bash.tar.gz")"
if [ "$got" != "$BASH_SHA256" ]; then
  rm -f -- "$SRC/bash.tar.gz"
  fail "digest mismatch for $BASH_URL: expected $BASH_SHA256, got $got; nothing extracted"
fi
say "bash tarball digest verified ($got)"

say "fetching $AWK_REPO at $AWK_COMMIT"
git init -q "$SRC/awk" || fail "git init failed"
git -C "$SRC/awk" fetch -q --depth 1 "$AWK_REPO" "$AWK_COMMIT" \
  || fail "could not fetch commit $AWK_COMMIT from $AWK_REPO"
git -C "$SRC/awk" -c advice.detachedHead=false checkout -q FETCH_HEAD || fail "checkout of the awk commit failed"
head_sha="$(git -C "$SRC/awk" rev-parse HEAD)"
[ "$head_sha" = "$AWK_COMMIT" ] || fail "awk commit mismatch: expected $AWK_COMMIT, got $head_sha"
say "awk commit verified ($head_sha)"

# Step 4: bison.
if [ "$BISON_FROM" = system ]; then
  BISON="$(command -v bison)"
  say "using the system bison: $("$BISON" --version | head -1)"
else
  mkdir -p "$SRC/bison" || fail "cannot create the bison scratch"
  ( CDPATH= cd -- "$SRC/bison" && apt-get download bison >&2 ) || fail "apt-get download bison failed"
  deb="$(ls "$SRC/bison"/bison_*.deb 2>/dev/null | head -1)"
  [ -n "$deb" ] || fail "apt-get download produced no bison .deb"
  say "bison .deb: $(dpkg-deb -f "$deb" Package) $(dpkg-deb -f "$deb" Version), sha256 $(SHA < "$deb")"
  dpkg -x "$deb" "$SRC/bison/root" || fail "dpkg -x failed"
  BISON="$SRC/bison/root/usr/bin/bison"
  export BISON_PKGDATADIR="$SRC/bison/root/usr/share/bison"
  M4="$(command -v m4)"; export M4
  "$BISON" --version >/dev/null 2>&1 || fail "the unpacked bison does not run"
fi

# Step 5: Apple awk, with the glibc shims.
mkdir -p "$SRC/shim" || fail "cannot create the shim directory"
printf '#include <locale.h>\n#include <wctype.h>\n' > "$SRC/shim/xlocale.h"
printf 'const char *fmtcheck(const char *, const char *);\n' > "$SRC/shim/shim.h"
cat > "$SRC/shim/shim.c" <<'EOF'
/* glibc lacks these two macOS libc symbols. The collation lookup returns the code point as its
   own primary weight, which is what [=c=] needs in the C locale; fmtcheck trusts the format. */
#include <wchar.h>
#include <locale.h>
void __collate_lookup_l(wchar_t *t, int *len, int *prim, int *sec, locale_t loc)
{ (void)loc; *len = 1; *prim = (int)*t; *sec = 0; }
const char *fmtcheck(const char *fmt, const char *def) { (void)def; return fmt; }
EOF
say "building Apple awk (log: $SRC/awk.log)"
( CDPATH= cd -- "$SRC/awk/src" \
  && touch awkgram.tab.c awkgram.tab.h proctab.c \
  && make CC="$CC" HOSTCC="$CC" \
       CFLAGS="$AWK_CFLAGS -I$SRC/shim -include $SRC/shim/shim.h" ALLOC="$SRC/shim/shim.c" ) \
  > "$SRC/awk.log" 2>&1 || { tail -20 "$SRC/awk.log" >&2; fail "the awk build failed"; }
cp "$SRC/awk/src/a.out" "$PARTIAL/bin/awk" || fail "cannot install awk"
awk_ver="$("$PARTIAL/bin/awk" --version 2>&1)" || fail "the built awk does not run"
say "built: $awk_ver"

# Step 6: bash 3.2.57.
say "building bash (log: $SRC/bash.log)"
tar -xzf "$SRC/bash.tar.gz" -C "$SRC" || fail "cannot extract the bash tarball"
bdir="$(ls -d "$SRC"/bash-*/ 2>/dev/null | head -1)"
[ -n "$bdir" ] || fail "the bash tarball holds no bash-* directory"
( CDPATH= cd -- "$bdir" \
  && CC="$CC" CFLAGS="$BASH_CFLAGS" ./configure --disable-nls --without-bash-malloc \
  && make CFLAGS_FOR_BUILD="$BASH_CFLAGS" YACC="$BISON -y" ) \
  > "$SRC/bash.log" 2>&1 || { tail -20 "$SRC/bash.log" >&2; fail "the bash build failed"; }
cp "$bdir/bash" "$PARTIAL/bin/bash" || fail "cannot install bash"
bash_ver="$("$PARTIAL/bin/bash" -c 'echo "$BASH_VERSION"')" || fail "the built bash does not run"
say "built: bash $bash_ver"

# Step 7: stamp last, then the rename that makes it a finished build.
rm -rf -- "$SRC" || fail "cannot remove the build scratch"
stamp_text > "$PARTIAL/$STAMP_NAME" || fail "cannot write the stamp"
if [ "$REPLACE" = 1 ]; then
  rm -rf -- "$DIR" || fail "cannot remove the old build at $DIR"
fi
mv -- "$PARTIAL" "$DIR" || fail "cannot rename $PARTIAL to $DIR"
say "built into $DIR"
report; caveats
