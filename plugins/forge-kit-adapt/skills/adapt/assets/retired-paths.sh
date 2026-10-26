#!/usr/bin/env bash
# retired-paths-version: 2
# retired-paths.sh: find a file forge-kit RETIRED and an earlier install left behind, and remove it
# together with the ONE workflow step that still runs it (#521).
#
# A version marker finds a component that is behind. It cannot find a file the kit stopped shipping:
# nothing names it any more, so drift never lists it. The motivating case is the template-lockstep
# guard's contract test. Before #506 forge-adapt copied scripts/test-template-lockstep.sh into every
# project and wired it into CI; the test is kit-only now, and the installed copy is orphaned, never
# refreshed, and still run by a workflow step the project owns.
#
# Usage: retired-paths.sh [--project <dir>] [--rules <tsv>]                 (scan, read only)
#        retired-paths.sh [--project <dir>] [--rules <tsv>] --remove <path> (write, one path)
#
#   --project  the project to scan. Default: the current directory.
#   --rules    the data file. Default: retired-paths.tsv beside this script. Tab separated columns:
#              path (relative to the project), issue that retired it, date, note. `#` lines and blank
#              lines are skipped. A path must be relative, with no `..` component and no leading `-`.
#   --remove   delete one listed file and the workflow step that runs it. Only the confirmed branch
#              of the main flow calls this, after a `yes` for that file. See the refusals below.
#
# THE KIT CHECKOUT IS EXEMPT. A project holding plugins/forge-kit-adapt/.claude-plugin/plugin.json IS
# forge-kit, where the retired path is a live file the build runs. A scan prints `exempt` and the
# summary and exits 0; --remove refuses.
#
# WHAT IT SCANS. For each listed path that exists as a regular file under the project, two sets of
# files, read once, never through a symlink (#540):
#   - the workflow files directly inside .github/workflows, .forgejo/workflows and .gitea/workflows
#     (*.yml, *.yaml), read as steps (the form below);
#   - the other callers: package.json, Makefile, makefile, GNUmakefile, justfile, Justfile, .justfile,
#     and every regular file directly inside .githooks/ and .husky/ (the directory `_` is skipped).
#     A line there counts as a caller when the BASENAME of the path stands at a token boundary (so
#     `cd scripts && ./x.sh` matches), unless the line starts with `#` (a tab or space first is fine).
# It does NOT scan a pre-commit config, lefthook, a Taskfile, a core.hooksPath directory other than
# the two above, another CI system or a wrapper script, so a row whose caller is `-` and no
# caller-unscanned row means "none of the files above names it", never "nothing runs it".
#
# OUTPUT, stdout, tab separated:
#   retired      <path>  <caller>  <line>  <form>   one row per workflow line naming the path; the
#                                                    caller is the workflow file, relative to the
#                                                    project. With no such line: caller, line, form `-`.
#   caller-unscanned <path> <file> <line>            one per line of a non-workflow caller file naming the
#                                                    path, after that path's retired rows. A removal
#                                                    refuses on every one (see below).
#   not-scanned  <path>  <symlink|unreadable>       a path, workflow location or caller file it did not
#                                                    read (the last two only when a listed path exists,
#                                                    once per file, however many paths are listed)
#   exempt       kit checkout                       (instead of a scan, see above)
#   summary      <retired paths found>  <not-scanned rows>                            (always last)
#
# FORM is `step` only for an exact one-line run step, `- run: bash|sh [./]<path>`, with no deeper line
# under it (an if:/env:/name: key belongs to the step) and a sibling step at the same indentation
# inside the same `steps:` block (so deleting it cannot leave a job with no steps). Anything else is
# `other`: a multi-line or `run: |` step, a quoted command, `./<path>` run directly, a line that
# merely mentions the path, a `name:`/`if:` block around it. A `#` comment line is not a caller.
# A mention counts when the path is not part of a longer file name (`.bak`, `-old` do not match).
#
# EXIT (scan): 0 nothing found; 1 at least one retired row; 3 no retired row but something was not
# scanned (incomplete is never clean); 2 usage or data-file error, nothing on stdout.
#
# REMOVAL (--remove). Every caller row must be `step`, or nothing at all is written:
#   - a `step` row: that exact line is deleted from its workflow file, then the script is deleted;
#   - caller `-` and no caller-unscanned row: the script is deleted alone (the callers listed under
#     WHAT IT SCANS found nothing; a caller outside that list can still run it: say so);
#   - any `other` row, a caller-unscanned row, a symlinked path, or a workflow or caller file it could
#     not read or write: NOTHING is changed, the script stays so CI never runs a missing file, and one
#     line per blocker is printed:
#       not removed: <file>:<line> is not a one-line run step; delete it by hand, then remove <path>
#       not removed: <file>:<line> names <path> outside a workflow; delete it by hand, then remove <path>
#       not removed: <file> was not scanned (<why>); check it for a step that runs <path>, then remove it by hand
#     A workflow step that would otherwise have been deleted stays too: the refusal is all or nothing.
#   - a workflow FILE is never deleted. Editing is by removing one recognised line, never by parsing
#     and re-serialising, which would lose comments and formatting.
# EXIT (remove): 0 removed; 1 refused, nothing changed; 2 usage error or a path that is not listed or
# not present.
set -uo pipefail
export LC_ALL=C

HERE=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd -P) || { echo "retired-paths: cannot locate the script directory" >&2; exit 2; }
usage() {
  echo "retired-paths: $1" >&2
  echo "usage: retired-paths.sh [--project <dir>] [--rules <tsv>] [--remove <path>]" >&2
  exit 2
}

PROJECT="."; RULES="$HERE/retired-paths.tsv"; REMOVE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || usage "--project needs a value"; PROJECT="$2"; shift 2 ;;
    --rules)   [ "$#" -ge 2 ] || usage "--rules needs a value";   RULES="$2"; shift 2 ;;
    --remove)  [ "$#" -ge 2 ] || usage "--remove needs a value";  REMOVE="$2"; shift 2 ;;
    *)         usage "unknown argument '$1'" ;;
  esac
done
[ -d "$PROJECT" ] || usage "'$PROJECT' is not a directory"
[ -f "$RULES" ] && [ -r "$RULES" ] || usage "cannot read the data file '$RULES'"

# The listed paths, validated: a path from a data file is later joined to the project and deleted.
PATHS=()
while IFS= read -r row || [ -n "$row" ]; do
  row=${row%$'\r'}
  case "$row" in ''|'#'*) continue ;; esac
  p=${row%%$'\t'*}
  case "$row" in *$'\t'*) ;; *) usage "data file row has no tab: '$row'" ;; esac
  case "$p" in
    ''|/*|-*|*..*|*[!A-Za-z0-9._/-]*|*//*) usage "data file path '$p' must be relative, without '..', a leading '-' or odd characters" ;;
  esac
  PATHS+=("$p")
done < "$RULES"

WFDIRS=(.github/workflows .forgejo/workflows .gitea/workflows)

# has_link <relative path>: success when the path or any directory component of it is a symlink.
has_link() {
  local acc="" part rest="$1"
  while [ -n "$rest" ]; do
    part=${rest%%/*}
    if [ "$part" = "$rest" ]; then rest=""; else rest=${rest#*/}; fi
    acc="${acc:+$acc/}$part"
    [ -L "$PROJECT/$acc" ] && return 0
  done
  return 1
}

KIT_CHECKOUT=0
[ -f "$PROJECT/plugins/forge-kit-adapt/.claude-plugin/plugin.json" ] && KIT_CHECKOUT=1

if [ "$KIT_CHECKOUT" -eq 1 ]; then
  if [ -n "$REMOVE" ]; then
    echo "not removed: $PROJECT is a forge-kit checkout, where the retired paths are live files" >&2
    exit 1
  fi
  printf 'exempt\tkit checkout\n'
  printf 'summary\t0\t0\n'
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/retired-paths.XXXXXX") || usage "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# The awk finder. For one path it prints "<line>\t<form>" per workflow line naming it. Reads the file
# whole first, because `step` needs to know whether a sibling step exists.
MENTION_AWK='
function is_word(c) { return c ~ /[A-Za-z0-9_.-]/ }
function mentions_from(l, p, start,   k, n, b, e) {
  n = length(p)
  while (start <= length(l)) {
    k = index(substr(l, start), p)
    if (k == 0) return 0
    k = start + k - 1
    b = k - 1; e = k + n
    if ((b == 0 || substr(l, b, 1) !~ /[A-Za-z0-9_-]/) && (e > length(l) || !is_word(substr(l, e, 1)))) return 1
    start = k + 1
  }
  return 0
}'
FIND_AWK="$MENTION_AWK"'
{ sub(/\r$/, "", $0); raw[NR] = $0 }
function skip(l) { return l ~ /^[ ]*$/ || l ~ /^[ ]*#/ }
function indent_of(l) { match(l, /^ */); return RLENGTH }
# step_ok(i, ind): the `- run:` line i, dash at column ind, is removable as one line when (a) nothing
# deeper follows it (an if:, env: or name: under the dash belongs to this step, #521) and (b) another
# `- ` item at the same indent sits inside the SAME `steps:` block, not anywhere in the file (an
# `on: push: branches: - main` would otherwise pass for a sibling).
function step_ok(i, ind,   j, h, e, sib) {
  for (j = i + 1; j <= NR; j++) {
    if (skip(raw[j])) continue
    if (indent_of(raw[j]) > ind) return 0
    break
  }
  h = 0
  for (j = i - 1; j >= 1; j--) {
    if (skip(raw[j])) continue
    if (indent_of(raw[j]) < ind || (indent_of(raw[j]) == ind && substr(raw[j], ind + 1, 2) != "- ")) { h = j; break }
  }
  if (h == 0 || raw[h] !~ /^[ ]*steps:[ ]*(#.*)?$/) return 0
  sib = 0
  for (j = h + 1; j <= NR; j++) {
    if (skip(raw[j])) continue
    e = indent_of(raw[j])
    if (e < ind || (e == ind && substr(raw[j], ind + 1, 2) != "- ")) break
    if (j != i && e == ind && !mentions_from(raw[j], P, 1)) sib = 1   # a retired-script run is no sibling (#521)
  }
  return sib
}
END {
  for (i = 1; i <= NR; i++) {
    l = raw[i]
    if (l ~ /^[ ]*#/) continue
    if (!mentions_from(l, P, 1)) continue
    form = "other"
    t = l; sub(/[ ]+$/, "", t)
    if (match(t, /^[ ]*-[ ]+run:[ ]+/)) {
      rest = substr(t, RLENGTH + 1)
      if (sub(/^(bash|sh)[ ]+/, "", rest)) {
        sub(/^\.\//, "", rest)
        if (rest == P) {
          ind = index(t, "-") - 1
          if (step_ok(i, ind)) form = "step"
        }
      }
    }
    printf "%d\t%s\n", i, form
  }
}'

# The caller finder (#540): one line number per non-comment line naming the basename P. A comment is a
# line whose first non-blank character (space or tab) is `#`.
CALL_AWK="$MENTION_AWK"'
{ sub(/\r$/, "", $0) }
$0 ~ /^[ \t]*#/ { next }
mentions_from($0, P, 1) { printf "%d\n", NR }'

ROWS="$WORK/rows"; NOTSC="$WORK/notscanned"; : > "$ROWS"; : > "$NOTSC"
NFOUND=0
SEEN_PATH=0

# Workflow files to read, once. A symlinked workflow location or file is not followed (the project may
# be untrusted): it is reported, and it blocks a removal because it may hold a caller.
WFFILES="$WORK/wffiles"; : > "$WFFILES"
for d in "${WFDIRS[@]}"; do
  [ -e "$PROJECT/$d" ] || [ -L "$PROJECT/$d" ] || continue
  if has_link "$d"; then printf '%s\tsymlink\n' "$d" >> "$WORK/wfblock"; continue; fi
  [ -d "$PROJECT/$d" ] || continue
  [ -r "$PROJECT/$d" ] && [ -x "$PROJECT/$d" ] || { printf '%s\tunreadable\n' "$d" >> "$WORK/wfblock"; continue; }
  for f in "$PROJECT/$d"/*.yml "$PROJECT/$d"/*.yaml; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    rel="$d/${f##*/}"
    if [ -L "$f" ]; then printf '%s\tsymlink\n' "$rel" >> "$WORK/wfblock"; continue; fi
    [ -f "$f" ] || continue
    [ -r "$f" ] || { printf '%s\tunreadable\n' "$rel" >> "$WORK/wfblock"; continue; }
    printf '%s\n' "$rel" >> "$WFFILES"
  done
done

# Caller files outside a workflow, listed once (#540). A symlinked or unreadable one goes to wfblock, the
# same not-scanned route as a workflow file, so it is reported once however many paths are listed and
# it blocks a removal because it may hold a caller. A directory, or a file that is not there, is skipped.
CANDS="$WORK/cands"; : > "$CANDS"
add_cand() {
  local rel="$1"
  [ -e "$PROJECT/$rel" ] || [ -L "$PROJECT/$rel" ] || return 0
  if has_link "$rel"; then printf '%s\tsymlink\n' "$rel" >> "$WORK/wfblock"; return 0; fi
  [ -f "$PROJECT/$rel" ] || return 0
  [ -r "$PROJECT/$rel" ] || { printf '%s\tunreadable\n' "$rel" >> "$WORK/wfblock"; return 0; }
  printf '%s\n' "$rel" >> "$CANDS"
}
for n in package.json Makefile makefile GNUmakefile justfile Justfile .justfile; do add_cand "$n"; done
for d in .githooks .husky; do
  [ -e "$PROJECT/$d" ] || [ -L "$PROJECT/$d" ] || continue
  if has_link "$d"; then printf '%s\tsymlink\n' "$d" >> "$WORK/wfblock"; continue; fi
  [ -d "$PROJECT/$d" ] || continue
  [ -r "$PROJECT/$d" ] && [ -x "$PROJECT/$d" ] || { printf '%s\tunreadable\n' "$d" >> "$WORK/wfblock"; continue; }
  for f in "$PROJECT/$d"/* "$PROJECT/$d"/.[!.]*; do
    [ "${f##*/}" = _ ] && continue
    [ -e "$f" ] || [ -L "$f" ] || continue
    add_cand "$d/${f##*/}"
  done
done
[ -f "$WORK/wfblock" ] || : > "$WORK/wfblock"

# scan_path <path>: appends this path's retired rows to ROWS. Returns 1 when the path is not a regular
# file in the project (nothing to report).
scan_path() {
  local p="$1" rel hits found=0 base="${1##*/}"
  if has_link "$p"; then printf '%s\tsymlink\n' "$p" >> "$NOTSC"; return 1; fi
  [ -f "$PROJECT/$p" ] || return 1
  NFOUND=$((NFOUND + 1))
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    hits=$(awk -v P="$p" "$FIND_AWK" "$PROJECT/$rel" 2>/dev/null)
    [ -n "$hits" ] || continue
    while IFS=$'\t' read -r ln form; do
      printf 'retired\t%s\t%s\t%s\t%s\n' "$p" "$rel" "$ln" "$form" >> "$ROWS"; found=1
    done <<< "$hits"
  done < "$WFFILES"
  [ "$found" -eq 1 ] || printf 'retired\t%s\t-\t-\t-\n' "$p" >> "$ROWS"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    hits=$(awk -v P="$base" "$CALL_AWK" "$PROJECT/$rel" 2>/dev/null)
    [ -n "$hits" ] || continue
    while IFS= read -r ln; do printf 'caller-unscanned\t%s\t%s\t%s\n' "$p" "$rel" "$ln" >> "$ROWS"; done <<< "$hits"
  done < "$CANDS"
  return 0
}

if [ -z "$REMOVE" ]; then
  for p in "${PATHS[@]+"${PATHS[@]}"}"; do scan_path "$p"; done
  cat "$ROWS"
  # A workflow location is reported only when a listed path exists: with none, there is nothing a
  # step could run, so a symlinked .forgejo/workflows must not turn a clean scan into exit 3.
  [ "$NFOUND" -gt 0 ] || : > "$WORK/wfblock"
  while IFS=$'\t' read -r where why; do printf 'not-scanned\t%s\t%s\n' "$where" "$why"; done < "$WORK/wfblock"
  while IFS=$'\t' read -r where why; do printf 'not-scanned\t%s\t%s\n' "$where" "$why"; done < "$NOTSC"
  NNS=$(( $(grep -c . "$WORK/wfblock") + $(grep -c . "$NOTSC") ))
  printf 'summary\t%d\t%d\n' "$NFOUND" "$NNS"
  [ "$NFOUND" -gt 0 ] && exit 1
  [ "$NNS" -gt 0 ] && exit 3
  exit 0
fi

# ---- --remove ----
listed=0
for p in "${PATHS[@]+"${PATHS[@]}"}"; do [ "$p" = "$REMOVE" ] && listed=1; done
[ "$listed" -eq 1 ] || usage "'$REMOVE' is not a listed retired path"
if has_link "$REMOVE"; then
  echo "not removed: $REMOVE is a symlink; remove it by hand" >&2; exit 1
fi
[ -f "$PROJECT/$REMOVE" ] || usage "'$REMOVE' is not a file in the project"
scan_path "$REMOVE"

refused=0
while IFS=$'\t' read -r where why; do
  echo "not removed: $where was not scanned ($why); check it for a step that runs $REMOVE, then remove it by hand" >&2; refused=1
done < "$WORK/wfblock"
while IFS=$'\t' read -r _ _ file ln form; do
  [ "$form" = other ] || continue
  echo "not removed: $file:$ln is not a one-line run step; delete it by hand, then remove $REMOVE" >&2; refused=1
done < "$ROWS"
while IFS=$'\t' read -r kind _ file ln _; do
  [ "$kind" = caller-unscanned ] || continue
  echo "not removed: $file:$ln names $REMOVE outside a workflow; delete it by hand, then remove $REMOVE" >&2; refused=1
done < "$ROWS"
STEPFILES=$(awk -F'\t' '$5 == "step" { print $3 }' "$ROWS" | sort -u)
for f in $STEPFILES; do
  [ -w "$PROJECT/$f" ] || { echo "not removed: $f is not writable; delete the step by hand, then remove $REMOVE" >&2; refused=1; }
done
[ "$refused" -eq 0 ] || exit 1

for f in $STEPFILES; do
  drop=$(awk -F'\t' -v f="$f" '$3 == f && $5 == "step" { print $4 }' "$ROWS" | paste -sd, -)
  awk -v drop="$drop" 'BEGIN { n = split(drop, a, ","); for (i = 1; i <= n; i++) d[a[i]] = 1 } !(NR in d)' "$PROJECT/$f" > "$WORK/edit" \
    && cat "$WORK/edit" > "$PROJECT/$f" \
    || { echo "not removed: could not edit $f; nothing else was changed" >&2; exit 1; }
done
rm -f -- "$PROJECT/$REMOVE"
if [ -n "$STEPFILES" ]; then
  echo "removed $REMOVE and its step in $(printf '%s\n' $STEPFILES | paste -sd, - | sed 's/,/, /g')"
else
  echo "removed $REMOVE"
fi
exit 0
