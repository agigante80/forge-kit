#!/usr/bin/env bash
# Pin the job's `awk` to mawk and assert it, or fail loudly (#489).
#
# Usage: pin-awk.sh [--assert-only]
#
# WHY. validate.yml once said the runner's default awk was mawk. Run 38331185657 showed
# ubuntu-latest resolves `awk` to /usr/bin/gawk until a later step installs gawk and sets the
# alternative back to mawk, so every suite above that step ran under gawk only, and a mawk-only
# defect (#485's fence indent) shipped green. mawk is the default `awk` users on Debian and Ubuntu
# get, and the stricter of the two, so the job pins it as its first step after checkout.
#
# Default mode sets the `awk` alternative to mawk, then asserts. `--assert-only` never calls
# update-alternatives; it re-checks the pin after a step that could undo it (installing gawk).
# The assertion compares the BASENAME of the resolved path with `mawk` exactly, so a file named
# `mawk-wrapper` or `gawk` does not pass.
set -uo pipefail

mode=pin
case "${1:-}" in
  '') ;;
  --assert-only) mode=assert ;;
  *) echo "::error::pin-awk.sh: unknown argument: $1" >&2; exit 2 ;;
esac

if [ "$mode" = pin ]; then
  mawk_path="$(command -v mawk 2>/dev/null || true)"
  if [ -z "$mawk_path" ]; then
    echo "::error::mawk is not installed"
    exit 1
  fi
  sudo update-alternatives --set awk "$mawk_path" || {
    echo "::error::update-alternatives could not set awk to $mawk_path"
    exit 1
  }
fi

awk_cmd="$(command -v awk 2>/dev/null || true)"
if [ -z "$awk_cmd" ]; then
  echo "::error::awk resolves to nothing, expected mawk"
  exit 1
fi
resolved="$(readlink -f "$awk_cmd")"
if [ "$(basename "$resolved")" != mawk ]; then
  echo "::error::awk resolves to $resolved, expected mawk"
  exit 1
fi
echo "$resolved"
mawk -W version 2>/dev/null | head -1 || true
exit 0
