#!/usr/bin/env bash
# Contract test for release-automation/assets/version-lib.sh (issue #76).
#
# This is the version<->tag primitive every release lane sources and acts on, so a silent bug here
# ships a wrong release. It is side-effect-free and returns a one-word verdict, so it tests like a
# pure function, against real throwaway git repos (the tags ARE the input).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
LIB="$ROOT/plugins/forge-kit-devops/skills/release-automation/assets/version-lib.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# A fresh repo per case. mktemp rather than a counter: mkrepo is called in $( ), so a counter
# incremented here lives in the subshell and every call would reuse one directory. All git chatter
# is silenced, or it lands in the captured path.
mkrepo() {
  local r; r=$(mktemp -d "$TMP/repo.XXXXXX")
  git init --quiet -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email t@example.com >/dev/null 2>&1
  git -C "$r" config user.name test >/dev/null 2>&1
  echo seed > "$r/seed.txt"
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" commit --quiet -m init >/dev/null 2>&1
  printf '%s' "$r"
}

# verdict <repo> [env...]: prints the one-word verdict; sets $rc (only meaningful when called
# outside a command substitution, which is why the fail-closed cases call it bare).
verdict() { local r="$1"; shift; out=$(cd "$r" && env "$@" bash "$LIB" 2>/dev/null); rc=$?; printf '%s' "$out"; }

# --- the four documented verdicts --------------------------------------------------------------
R=$(mkrepo); echo "1.0.0" > "$R/VERSION"
v=$(verdict "$R"); [ "$v" = "first-release" ] && ok "no release tag -> first-release" \
  || bad "no release tag -> first-release (got '$v')"

R=$(mkrepo); echo "1.0.0" > "$R/VERSION"; git -C "$R" tag v1.0.0
v=$(verdict "$R"); [ "$v" = "equal" ] && ok "version == latest tag -> equal" || bad "equal (got '$v')"

echo "1.1.0" > "$R/VERSION"
v=$(verdict "$R"); [ "$v" = "ahead" ] && ok "version > latest tag -> ahead" || bad "ahead (got '$v')"

echo "0.9.0" > "$R/VERSION"
v=$(verdict "$R"); [ "$v" = "behind" ] && ok "version < latest tag -> behind (regression)" || bad "behind (got '$v')"

# --- the sort -V prerelease trap, called out in the source ------------------------------------
# `sort -V` ranks 1.2.0-rc1 ABOVE 1.2.0, so a naive compare reads a prerelease as `ahead` and
# ships it as production. Comparing release cores must make it `equal` instead.
R=$(mkrepo); echo "1.2.0-rc1" > "$R/VERSION"; git -C "$R" tag v1.2.0
v=$(verdict "$R"); [ "$v" = "equal" ] && ok "a prerelease of an already-released core is equal, NOT ahead" \
  || bad "prerelease core comparison (got '$v')"
[ "$(printf '1.2.0-rc1\n1.2.0\n' | sort -V | tail -1)" = "1.2.0-rc1" ] \
  && ok "(and sort -V really does rank the prerelease higher, so the guard is load-bearing)" \
  || bad "sort -V prerelease assumption no longer holds"

# --- fail closed, never ship garbage -----------------------------------------------------------
R=$(mkrepo)                                  # no VERSION file at all
verdict "$R" >/dev/null; [ "$rc" -ne 0 ] && ok "an unreadable version fails closed (non-zero)" \
  || bad "an unreadable version fails closed (rc=$rc)"

R=$(mkrepo); echo "undefined" > "$R/VERSION"; git -C "$R" tag v1.0.0
verdict "$R" >/dev/null; [ "$rc" -ne 0 ] && ok "a non-semver working version fails closed" \
  || bad "a non-semver working version fails closed (rc=$rc)"

R=$(mkrepo); echo "1.0.0" > "$R/VERSION"; git -C "$R" tag vNOTASEMVER
verdict "$R" >/dev/null; [ "$rc" -ne 0 ] && ok "a non-semver tag fails closed" \
  || bad "a non-semver tag fails closed (rc=$rc)"

R=$(mkrepo); echo "1.0.0" > "$R/VERSION"
verdict "$R" VERSION_SOURCE=nonsense >/dev/null
[ "$rc" -ne 0 ] && ok "an unknown VERSION_SOURCE fails closed" || bad "unknown VERSION_SOURCE (rc=$rc)"

# --- TAG_GLOB derives from TAG_PREFIX, so a custom prefix cannot desync them -------------------
R=$(mkrepo); echo "2.0.0" > "$R/VERSION"; git -C "$R" tag rel1.0.0
v=$(verdict "$R" TAG_PREFIX=rel); [ "$v" = "ahead" ] \
  && ok "a custom TAG_PREFIX is matched without setting TAG_GLOB" \
  || bad "custom TAG_PREFIX (got '$v')"
v=$(verdict "$R"); [ "$v" = "first-release" ] \
  && ok "...and the default prefix does not see that tag (proving the prefix drove it)" \
  || bad "default prefix must not match rel1.0.0 (got '$v')"

# --- git (tag-derived) mode is HEAD-relative ON PURPOSE ----------------------------------------
# A higher release tag on an unmerged sibling branch must not make HEAD look `behind`.
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" checkout --quiet -b sibling; echo x > "$R/x"; git -C "$R" add -A
git -C "$R" commit --quiet -m sib; git -C "$R" tag v2.0.0; git -C "$R" checkout --quiet main
v=$(verdict "$R" VERSION_SOURCE=git); [ "$v" = "equal" ] \
  && ok "git mode ignores a higher tag on an unmerged sibling (equal, not behind)" \
  || bad "git mode sibling-branch frame (got '$v')"
echo "1.5.0" > "$R/VERSION"
v=$(verdict "$R"); [ "$v" = "behind" ] \
  && ok "...while file mode compares repo-wide and does report behind" \
  || bad "file mode is repo-wide (got '$v')"

# --- next_patch is pure ------------------------------------------------------------------------
np() { ( set +u; . "$LIB"; next_patch "$1" 2>/dev/null ); }
[ "$(np 1.2.3)" = "1.2.4" ] && ok "next_patch 1.2.3 -> 1.2.4" || bad "next_patch 1.2.3"
[ "$(np 1.2.3-rc1)" = "1.2.4" ] && ok "next_patch drops a prerelease suffix" || bad "next_patch prerelease"
[ "$(np 9.9.9)" = "9.9.10" ] && ok "next_patch carries into two digits" || bad "next_patch 9.9.9"
( set +u; . "$LIB"; next_patch 1.2.3.4 >/dev/null 2>&1 ) \
  && bad "next_patch rejects a 4-part version" || ok "next_patch rejects a 4-part version"
( set +u; . "$LIB"; next_patch nope >/dev/null 2>&1 ) \
  && bad "next_patch rejects a non-semver version" || ok "next_patch rejects a non-semver version"

echo ""
echo "version-lib tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
