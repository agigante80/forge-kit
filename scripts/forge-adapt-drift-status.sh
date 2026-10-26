#!/usr/bin/env bash
# forge-adapt-drift-status.sh: one word describing one component's install state (#167).
#
#   forge-adapt-drift-status.sh --local <N|none|absent> --catalogue <N|none> [--group-enabled [--kept]]
#
# N may carry one leading `v` (`v3` reads as 3), the form the catalogue prints. Anything else that is
# not a number, and a number over nine digits, exits 2 naming the original token (#504).
#
# Prints exactly one of:
#   current      the local copy is at or above the catalogue
#   behind       the local marker is strictly below the catalogue
#   unversioned  a local copy exists but carries no marker; cannot be compared, deep-compare it
#   registered   no local copy, and none is wanted: the plugin group provides it (#166)
#   missing      no local copy, and nothing provides it
#   shadowed     a local copy exists AND the live plugin group provides the component (#550): it runs
#                twice, so it is neither compared nor refreshed; the caller offers retire or keep
#   kept         the same, and the user already chose to keep the local copy (--kept)
#
# SHADOWED AND KEPT NEED --group-enabled AND A LOCAL COPY. With the group enabled, a local copy
# (a number or `none`) is `kept` under --kept and `shadowed` otherwise, whatever the markers say,
# `--catalogue none` included: the marker comparison no longer applies once the plugin provides the
# component. Without --group-enabled nothing changes and --kept is ignored. `--local absent` stays
# `registered` or `missing`; --kept with it exits 2, because there is no copy to keep. The caller
# decides which components may be shadowed (scope, #550); this script takes values, never paths.
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

LOCAL=""; CATALOGUE=""; ENABLED=0; KEPT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --local)          shift; [ $# -gt 0 ] || { echo "drift-status: --local needs a value" >&2; exit 2; }; LOCAL="$1" ;;
    --catalogue)      shift; [ $# -gt 0 ] || { echo "drift-status: --catalogue needs a value" >&2; exit 2; }; CATALOGUE="$1" ;;
    --group-enabled)  ENABLED=1 ;;
    --kept)           KEPT=1 ;;
    *)                echo "drift-status: unexpected argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$LOCAL" ] && [ -n "$CATALOGUE" ] || { echo "drift-status: --local and --catalogue are required" >&2; exit 2; }

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# A marker is digits, with ONE optional leading v (#504): the catalogue and the drift table print
# `v3`, and a caller should not have to strip it. Nothing looser is read (`vv1`, `V1`, `v` refuse).
# Over nine digits is refused rather than compared: the integer test overflows and the fall-through
# printed `current` with exit 0, a wrong word with a success exit, and a marker that long is a typo.
# The refusal names the ORIGINAL token. LOCAL and CATALOGUE are rewritten to the bare number.
norm() { # norm <token>: prints the bare number, or exits 2 naming the token
  local t="$1" n="$1"
  case "$t" in v?*) n="${t#v}" ;; esac
  is_num "$n" || { echo "drift-status: '$t' is not a version, 'none' or 'absent'" >&2; exit 2; }
  [ "${#n}" -le 9 ] || { echo "drift-status: '$t' is too large to compare" >&2; exit 2; }
  printf '%s' "$n"
}
# The drift table prints an unmarked component as `vnone`; read that cell as `none`.
[ "$LOCAL" = vnone ] && LOCAL=none
case "$LOCAL" in none|absent) ;; *) LOCAL=$(norm "$LOCAL") || exit 2 ;; esac
case "$CATALOGUE" in none|absent) ;; *) CATALOGUE=$(norm "$CATALOGUE") || exit 2 ;; esac
# The catalogue is the library's own copy; it is never "absent" from a library that lists it, and
# treating it as such would hide a broken catalogue behind a per-component verdict.
[ "$CATALOGUE" = absent ] && { echo "drift-status: --catalogue cannot be 'absent'" >&2; exit 2; }

if [ "$LOCAL" = absent ]; then
  [ "$KEPT" -eq 1 ] && { echo "drift-status: --kept needs a local copy, and --local is absent" >&2; exit 2; }
  [ "$ENABLED" -eq 1 ] && { echo registered; exit 0; }
  echo missing; exit 0
fi

# A local copy under a live group is a duplicate, whatever its marker says (#550).
if [ "$ENABLED" -eq 1 ]; then
  [ "$KEPT" -eq 1 ] && echo kept || echo shadowed
  exit 0
fi

# A present copy with no marker cannot be compared. It is NOT behind: every install predating the
# markers looks like this, and calling it behind floods the report with false positives (#64).
[ "$LOCAL" = none ] && { echo unversioned; exit 0; }
[ "$CATALOGUE" = none ] && { echo unversioned; exit 0; }

if [ "$LOCAL" -lt "$CATALOGUE" ]; then echo behind; else echo current; fi
