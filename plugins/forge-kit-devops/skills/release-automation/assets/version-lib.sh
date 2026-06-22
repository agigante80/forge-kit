#!/usr/bin/env bash
# version-lib.sh — the shared release primitive. Compares the working-tree version against
# the latest released git tag and classifies the result. Every release-automation lane
# (gate / auto-on-dependency / auto-on-merge) sources this and acts on the one-word verdict,
# so the version<->tag logic lives in exactly one place.
#
# Verdicts (printed to stdout, one word; human detail goes to stderr):
#   first-release  no release tag exists yet — any version may ship
#   ahead          working version > latest tag — already bumped deliberately; ship AS-IS, NEVER re-bump
#   equal          working version == latest tag — nobody bumped; the lane decides (block | auto-patch)
#   behind         working version < latest tag — branch is behind a release; REGRESSION, hard stop
#
# Config via env (forge-adapt sets these for the project's canonical version source):
#   VERSION_SOURCE  file|node|python|cargo|cmd   (default: file)
#   VERSION_FILE    path to a plain-text version  (default: VERSION)
#   VERSION_CMD     shell command printing the version (used when VERSION_SOURCE=cmd)
#   TAG_GLOB        glob matching release tags     (default: v*)
#   TAG_PREFIX      prefix stripped from a tag     (default: v)
#
# Usage:
#   source version-lib.sh            # then call read_version / latest_tag / classify_version
#   bash   version-lib.sh            # prints the verdict (stdout) + detail (stderr); exit 0, or 2 on error
#
# NOTE: callers must check out full history with tags (actions/checkout: fetch-depth: 0,
# fetch-tags: true) or `latest_tag` sees nothing and every release looks like a first-release.
set -uo pipefail

VERSION_SOURCE="${VERSION_SOURCE:-file}"
VERSION_FILE="${VERSION_FILE:-VERSION}"
TAG_GLOB="${TAG_GLOB:-v*}"
TAG_PREFIX="${TAG_PREFIX:-v}"

# read_version — print the project's current (working-tree) canonical version, prefix-free.
read_version() {
  case "$VERSION_SOURCE" in
    file)   [ -f "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" ;;
    node)   node -p "require('./package.json').version" 2>/dev/null ;;
    python) python3 -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb'))['project']['version'])" 2>/dev/null ;;
    cargo)  grep -m1 '^version' Cargo.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' ;;
    cmd)    eval "${VERSION_CMD:?VERSION_CMD must be set when VERSION_SOURCE=cmd}" ;;
    *)      echo "version-lib: unknown VERSION_SOURCE '$VERSION_SOURCE'" >&2; return 2 ;;
  esac
}

# latest_tag — print the highest released semver tag (prefix stripped), or empty if none exist.
latest_tag() {
  git tag --list "$TAG_GLOB" --sort=-v:refname | head -1 | sed "s/^${TAG_PREFIX}//"
}

# classify_version — print one verdict word. Optional args: $1=working version, $2=latest tag.
classify_version() {
  local now tag highest
  now="${1-$(read_version)}"
  tag="${2-$(latest_tag)}"
  if [ -z "$now" ]; then echo "version-lib: could not read the working version (VERSION_SOURCE=$VERSION_SOURCE)" >&2; return 2; fi
  if [ -z "$tag" ]; then echo "first-release"; return 0; fi
  if [ "$now" = "$tag" ]; then echo "equal"; return 0; fi
  highest=$(printf '%s\n%s\n' "$now" "$tag" | sort -V | tail -1)
  if [ "$highest" = "$now" ]; then echo "ahead"; else echo "behind"; fi
}

# next_patch — print the next PATCH version (X.Y.Z -> X.Y.(Z+1)), dropping any -prerelease
# suffix. PURE: prints, never writes. The auto-release lanes use this to compute the bump; the
# gate never calls it (the gate only reads). Arg optional: $1=base version (default read_version).
next_patch() {
  local v="${1:-$(read_version)}"
  v="${v%%-*}"                       # base version, drop any -prerelease/+meta
  case "$v" in
    *.*.*) printf '%s.%s.%s' "${v%%.*}" "$(printf '%s' "$v" | cut -d. -f2)" "$(( ${v##*.} + 1 ))" ;;
    *)     echo "next_patch: not semver: $v" >&2; return 2 ;;
  esac
}

# Executed directly (not sourced): emit the verdict on stdout, a human line on stderr.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _now=$(read_version); _tag=$(latest_tag)
  _verdict=$(classify_version "$_now" "$_tag") || exit $?
  echo "version-lib: working=${_now:-?} latest-tag=${_tag:-none} -> $_verdict" >&2
  echo "$_verdict"
fi
