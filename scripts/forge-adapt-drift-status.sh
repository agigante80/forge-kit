#!/usr/bin/env bash
# forge-adapt-drift-status.sh: one word describing one component's install state (#167).
#
#   forge-adapt-drift-status.sh --local <N|none|absent> --catalogue <N|none> [--group-enabled]
#
# Prints exactly one of:
#   current      the local copy is at or above the catalogue
#   behind       the local marker is strictly below the catalogue
#   unversioned  a local copy exists but carries no marker; cannot be compared, deep-compare it
#   registered   no local copy, and none is wanted: the plugin group provides it (#166)
#   missing      no local copy, and nothing provides it
#
# WHY `registered` EXISTS. #166 stopped forge-adapt copying a user-scoped component, so a correctly
# installed component now has NO local copy. Reported as `missing`, a clean install would show a
# page of components the user would then try to install again by copying, which is exactly what
# #166 removed. The distinction is not cosmetic: it is what stops the fix undoing itself.
#
# WHY IT IS A SCRIPT. These rules were prose in adapt/SKILL.md, which sits on its size ratchet, so
# the new rule had nowhere to go. Extracting them is the #149 lever and it left the file smaller
# than before. They are also exactly the kind of rule a test can hold down: five inputs, one word out.
#
# ABSENT IS NOT THE SAME AS NONE, and conflating them is the bug this guards. `absent` means no local
# copy exists; `none` means one exists with no version marker. The second is the whole install base
# that predates markers (#64), and reporting it as missing would hide it.
set -uo pipefail

LOCAL=""; CATALOGUE=""; ENABLED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --local)          shift; [ $# -gt 0 ] || { echo "drift-status: --local needs a value" >&2; exit 2; }; LOCAL="$1" ;;
    --catalogue)      shift; [ $# -gt 0 ] || { echo "drift-status: --catalogue needs a value" >&2; exit 2; }; CATALOGUE="$1" ;;
    --group-enabled)  ENABLED=1 ;;
    *)                echo "drift-status: unexpected argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$LOCAL" ] && [ -n "$CATALOGUE" ] || { echo "drift-status: --local and --catalogue are required" >&2; exit 2; }

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

for v in "$LOCAL" "$CATALOGUE"; do
  case "$v" in
    none|absent) ;;
    *) is_num "$v" || { echo "drift-status: '$v' is not a version, 'none' or 'absent'" >&2; exit 2; } ;;
  esac
done
# The catalogue is the library's own copy; it is never "absent" from a library that lists it, and
# treating it as such would hide a broken catalogue behind a per-component verdict.
[ "$CATALOGUE" = absent ] && { echo "drift-status: --catalogue cannot be 'absent'" >&2; exit 2; }

if [ "$LOCAL" = absent ]; then
  [ "$ENABLED" -eq 1 ] && { echo registered; exit 0; }
  echo missing; exit 0
fi

# A present copy with no marker cannot be compared. It is NOT behind: every install predating the
# markers looks like this, and calling it behind floods the report with false positives (#64).
[ "$LOCAL" = none ] && { echo unversioned; exit 0; }
[ "$CATALOGUE" = none ] && { echo unversioned; exit 0; }

if [ "$LOCAL" -lt "$CATALOGUE" ]; then echo behind; else echo current; fi
