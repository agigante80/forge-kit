#!/usr/bin/env bash
# forge-adapt-standards-row.sh: the drift row for the project's ticket-standards doc (#525).
#
#   forge-adapt-standards-row.sh --project <dir> --kit <dir>
#
# drift and refresh compare components and scripts, so docs/guides/ticket-standards.md at
# doc-rules-version 20 against the kit's 21 never appeared in the table. This prints the one row it
# needs, in the shape of the other drift rows, with `v<N>` in both version columns:
#
#   ticket-standards (doc-rules) | v20 | v21 | behind
#
# WHAT IT COMPARES. `doc-rules-version` only, the marker that says which revision of the RULES TEXT a
# doc is at (docs/guides/template-versioning.md). Never `template-version`: forge-adapt installs the
# doc with the PROJECT's own template-version, so comparing it to the kit's would repeat the
# `issue-templates:` line the Step 1 probe already prints and read `behind` on every project whose
# templates lag on purpose. doc-rules-version is copied, not rewritten, so it is the honest signal.
#
# THE WORD IS NOT DECIDED HERE. It comes from forge-adapt-drift-status.sh beside this script, so every
# comparison rule (behind, current, unversioned, the number checks) lives in one place.
#
# OUTPUT AND EXIT
#   no project doc                       prints nothing, exit 0 (an uninstalled doc is not drift; the
#                                        kit copy is not read)
#   project doc without a marker         `ticket-standards (doc-rules) | none | v<kit> | unversioned`
#                                        (the #64 rule: an unmarked install surfaces, never vanishes)
#   kit copy missing or unmarked         exit 2 naming the file, nothing on stdout
#   a marker that is not a number        exit 2 naming the token (from drift-status)
#   usage error                          exit 2
#
# THE MARKER is the first line of the form `<!-- doc-rules-version: N -->` (leading spaces and a CR
# are tolerated). A prose mention of the name, in backticks or mid-line, is not a marker.
set -uo pipefail

HERE=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd -P) || { echo "standards-row: cannot locate the script directory" >&2; exit 2; }
DOC=docs/guides/ticket-standards.md
usage() { echo "standards-row: $1" >&2; echo "usage: forge-adapt-standards-row.sh --project <dir> --kit <dir>" >&2; exit 2; }

PROJECT=""; KIT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage "--project needs a value"; PROJECT="$2"; shift 2 ;;
    --kit)     [ "$#" -ge 2 ] || usage "--kit needs a value";     KIT="$2"; shift 2 ;;
    *)         usage "unknown argument '$1'" ;;
  esac
done
[ -n "$PROJECT" ] && [ -n "$KIT" ] || usage "--project and --kit are required"
[ -d "$PROJECT" ] || usage "'$PROJECT' is not a directory"
[ -d "$KIT" ] || usage "'$KIT' is not a directory"
[ -f "$HERE/forge-adapt-drift-status.sh" ] || usage "forge-adapt-drift-status.sh is missing beside this script"

# marker_of <file>: the first doc-rules-version value, as written, or nothing.
marker_of() {
  tr -d '\r' < "$1" | sed -n 's/^[[:space:]]*<!--[[:space:]]*doc-rules-version:[[:space:]]*\([^[:space:]]*\)[[:space:]]*-->.*$/\1/p' | head -n 1
}

[ -f "$PROJECT/$DOC" ] || exit 0

[ -f "$KIT/$DOC" ] || { echo "standards-row: the kit copy $DOC is missing under '$KIT'" >&2; exit 2; }
KV=$(marker_of "$KIT/$DOC")
[ -n "$KV" ] || { echo "standards-row: the kit copy $DOC carries no doc-rules-version marker" >&2; exit 2; }
LV=$(marker_of "$PROJECT/$DOC")

# Both values go through drift-status, which validates them and names a bad token. A bad kit token is
# refused even when the project doc is unmarked, so a typo in the kit copy cannot hide.
WORD=$(bash "$HERE/forge-adapt-drift-status.sh" --local "${LV:-none}" --catalogue "$KV") || exit 2
case "$LV" in '') LCELL=none ;; v*) LCELL=$LV ;; *) LCELL="v$LV" ;; esac
case "$KV" in v*) KCELL=$KV ;; *) KCELL="v$KV" ;; esac
echo "ticket-standards (doc-rules) | $LCELL | $KCELL | $WORD"
