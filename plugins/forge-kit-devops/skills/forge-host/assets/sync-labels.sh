#!/usr/bin/env bash
# sync-labels-version: 4
# sync-labels.sh: make the host's labels match `.github/labels.yml`, or report that they do not.
#
# WHY THIS EXISTS (issue #104). forge-kit shipped a label taxonomy, documented that labels drive
# ticket-gate's lens routing, and never imported it into its own repository: 18 labels declared,
# 4 present. `security`, `critical` and `api` are executable inputs to the gate, so the kit's most
# distinctive mechanism was unexercisable in the one repo guaranteed to be running it. The taxonomy
# was a declarative file with no applier and no checker.
#
# Host-aware via forge-lib.sh, because labels are already a forge_* concern (#63): GitHub takes
# label NAMES on update, Forgejo takes label IDs, and this hides that difference the way
# forge_issue_label does.
#
# Usage:
#   sync-labels.sh [--check] [--labels FILE] [--repo OWNER/NAME]
#     default   create missing labels and update drifted ones
#     --check   change nothing; list what is missing or drifted
#   FORGE_DRY_RUN=1  print what would be written and send nothing
#
# Exit codes are distinguishable, because this runs from automation:
#   0  in sync (or synced successfully)
#   1  --check found drift (the repo needs syncing; nothing is wrong with the tooling)
#   2  usage or environment error (bad flag, no labels file, no jq, unresolvable repo)
#   3  the declaration is malformed; NOTHING was written
#   4  a write failed part-way; the host may be partially synced
#
# NEVER DELETES. A label on the host that is not declared is reported and left alone: GitHub ships
# stock defaults (duplicate, help wanted, invalid, question, wontfix), projects add their own, and
# a sync script that deletes what it does not recognise is a footgun aimed at other people's data.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=forge-lib.sh
if [ -f "$HERE/forge-lib.sh" ]; then . "$HERE/forge-lib.sh"
else echo "sync-labels: forge-lib.sh not found next to this script" >&2; exit 2; fi

MODE=sync
LABELS_FILE=""
REPO_OVERRIDE=""
need_arg() { [ $# -ge 2 ] || { echo "sync-labels: $1 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check)  MODE=check; shift ;;
    --labels) need_arg "$@"; LABELS_FILE="$2"; shift 2 ;;
    --repo)   need_arg "$@"; REPO_OVERRIDE="$2"; shift 2 ;;
    *) echo "sync-labels: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$LABELS_FILE" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  for c in "$root/.github/labels.yml" "$root/.forgejo/labels.yml" "$root/.gitea/labels.yml"; do
    [ -f "$c" ] && { LABELS_FILE="$c"; break; }
  done
fi
[ -n "$LABELS_FILE" ] && [ -f "$LABELS_FILE" ] || {
  echo "sync-labels: no labels file found (looked for .github/labels.yml)" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "sync-labels: jq is required" >&2; exit 2; }

REPO="${REPO_OVERRIDE:-$(forge_repo)}"
[ -n "$REPO" ] || { echo "sync-labels: could not resolve the repo" >&2; exit 2; }

# --- 1. parse the declaration ------------------------------------------------------------------
# Deliberately strict. The accepted shape is what forge-kit ships:
#   - name: <name>
#     color: "<hex>"
#     description: <free text>
# Fields are emitted separated by US (\x1f), NOT tab: tab is IFS whitespace, so `read` collapses a
# run of tabs into one delimiter and an entry missing `color:` would silently shift its description
# into the colour field (issue #104 round-1 finding H1).
# Values are cleaned: CR stripped (CRLF files), surrounding whitespace trimmed, a matched pair of
# double or single quotes removed (with YAML's '' unescaping), and a trailing ` # comment` stripped
# from UNQUOTED values only. Without this, a trailing space or a CRLF file silently creates a
# phantom label and the script never converges.
US=$'\x1f'
declared=$(awk -v US="$US" '
  # SQ/DQ are built from character codes so this program contains no literal quote of either kind:
  # it is embedded in a single-quoted shell string, and nested quoting is where the first attempt
  # at this function went wrong.
  BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92) }
  function clean(v,   i, n, ch, out, raw) {
    sub(/\r$/, "", v)
    raw = v
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
    # A quoted value ends at its CLOSING quote, found from the LEFT; anything after it (a
    # ` # comment`) is discarded. index/substr rather than sub(): POSIX awk has no capture-group
    # backreference in a replacement, so a /^([^"]*)".*$/ form silently inserts a literal \1.
    if (substr(v, 1, 1) == DQ) {
      # YAML escapes a literal quote inside a double-quoted scalar as \" , so index() would cut at
      # the ESCAPE and destroy the rest of the value. Skip an escaped quote the way the single-quote
      # branch skips a doubled one.
      v = substr(v, 2); out = ""; n = length(v)
      for (i = 1; i <= n; i++) {
        ch = substr(v, i, 1)
        if (ch == BS && substr(v, i + 1, 1) == DQ) { out = out DQ; i++; continue }
        if (ch == DQ) break
        out = out ch
      }
      return out
    }
    if (substr(v, 1, 1) == SQ) {
      # YAML doubles a single quote to escape it, so the closing quote is the first SQ NOT
      # followed by another. A plain index() would truncate "isn(SQ)(SQ)t" at the escape.
      v = substr(v, 2); out = ""; n = length(v)
      for (i = 1; i <= n; i++) {
        ch = substr(v, i, 1)
        if (ch == SQ) { if (substr(v, i + 1, 1) == SQ) { out = out SQ; i++ } else break }
        else out = out ch
      }
      return out
    }
    sub(/[[:space:]]+#.*$/, "", raw)
    v = raw; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
    return v
  }
  /^[[:space:]]*#/ || /^[[:space:]]*\r?$/ { next }
  /^-[[:space:]]+name:/ {
    if (seen) print n US c US d
    v = $0; sub(/^-[[:space:]]+name:/, "", v); n = clean(v); c = ""; d = ""; seen = 1; next
  }
  /^[[:space:]]+color:/       { v = $0; sub(/^[[:space:]]+color:/, "", v); c = clean(v)
                                sub(/^#/, "", c); next }
  /^[[:space:]]+description:/ { v = $0; sub(/^[[:space:]]+description:/, "", v); d = clean(v); next }
  { print "sync-labels: unparsable line " NR ": " $0 > "/dev/stderr"; bad = 1 }
  END { if (seen) print n US c US d; if (bad) exit 3 }
' "$LABELS_FILE") || {
  echo "sync-labels: $LABELS_FILE is not in the expected shape; refusing to sync a partial set" >&2
  exit 3; }

[ -n "$declared" ] || { echo "sync-labels: $LABELS_FILE declares no labels" >&2; exit 3; }

# --- 2. validate EVERY entry before writing ANY of them ----------------------------------------
# Validation is a separate pass on purpose: a bad entry halfway down the file must not be
# discovered after the entries above it have already been created on the host.
errs=0
while IFS="$US" read -r name color desc; do
  if [ -z "$name" ]; then
    # Covers a bare `- name:` with no other fields too: skipping empty records here is what let
    # M1's own case through the first time.
    echo "sync-labels: an entry has an empty name" >&2; errs=$((errs + 1)); continue
  fi
  case "$name" in
    .|..) echo "sync-labels: '$name' is a dot path segment; refused because it can escape the URL path" >&2
               errs=$((errs + 1)) ;;
  esac
  case "$color" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    "") echo "sync-labels: '$name' has no color (both hosts require one)" >&2; errs=$((errs + 1)) ;;
    *)  echo "sync-labels: '$name' has color '$color', which is not 6 hex digits" >&2; errs=$((errs + 1)) ;;
  esac
done <<< "$declared"
[ "$errs" -eq 0 ] || {
  echo "sync-labels: $errs invalid entr(y|ies) in $LABELS_FILE; nothing was written" >&2; exit 3; }

# --- 3. read the host's current labels ---------------------------------------------------------
# FORGE_DRY_RUN is cleared around the READ. forge-lib's paginate short-circuits to [] under dry
# run, which would make a dry run report every label as missing on a perfectly synced repo, and
# `--check` a false alarm (round-1 finding H2). Reads have no side effect; only writes are gated.
_dry="${FORGE_DRY_RUN:-0}"
FORGE_DRY_RUN=0
existing=$(forge_api_paginate "/repos/$REPO/labels") || {
  FORGE_DRY_RUN="$_dry"; echo "sync-labels: could not list labels on $REPO" >&2; exit 2; }
FORGE_DRY_RUN="$_dry"
printf '%s' "$existing" | jq -e 'type == "array"' >/dev/null 2>&1 || {
  echo "sync-labels: unexpected label-list response for $REPO" >&2; exit 2; }

host_field() {  # host_field <name> <field>  -> the value, or empty when the label is absent
  printf '%s' "$existing" | jq -r --arg n "$1" --arg f "$2" \
    'map(select(.name == $n)) | if length == 0 then "" else (.[0][$f] // "" | tostring) end'
}
norm_color() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^#//'; }

missing=0 drifted=0 created=0 updated=0
report=""

while IFS="$US" read -r name color desc; do
  [ -n "$name" ] || continue
  if [ -z "$(host_field "$name" name)" ]; then
    missing=$((missing + 1)); report="${report}  missing  $name"$'\n'
    if [ "$MODE" = sync ]; then
      if [ "$_dry" = 1 ]; then
        echo "[dry-run] create label '$name' (#$color) on $REPO" >&2
      else
        body=$(jq -nc --arg n "$name" --arg c "$color" --arg d "$desc" \
                 '{name:$n, color:$c, description:$d}')
        forge_api POST "/repos/$REPO/labels" "$body" >/dev/null || {
          echo "sync-labels: failed to create '$name'; the host may be partially synced" >&2; exit 4; }
      fi
      created=$((created + 1))
    fi
    continue
  fi
  cur_color=$(host_field "$name" color)
  cur_desc=$(host_field "$name" description)
  # Colour comparison ignores case and a leading '#': hosts normalise differently and that is not
  # drift anyone means. Descriptions are compared EXACTLY, case included.
  if [ "$(norm_color "$cur_color")" != "$(norm_color "$color")" ] || [ "$cur_desc" != "$desc" ]; then
    drifted=$((drifted + 1))
    report="${report}  drifted  $name (color '$cur_color' vs '$color'; description '$cur_desc' vs '$desc')"$'\n'
    if [ "$MODE" = sync ]; then
      if [ "$_dry" = 1 ]; then
        echo "[dry-run] update label '$name' on $REPO" >&2
      else
        body=$(jq -nc --arg n "$name" --arg c "$color" --arg d "$desc" \
                 '{name:$n, color:$c, description:$d}')
        case "$(forge_host)" in
          forgejo) id=$(host_field "$name" id)
                   [ -n "$id" ] || { echo "sync-labels: no id for '$name' on forgejo" >&2; exit 4; }
                   forge_api PATCH "/repos/$REPO/labels/$id" "$body" >/dev/null ;;
          # GitHub addresses the label by NAME in the PATH, so it MUST be percent-encoded: a stock
          # name like `help wanted` puts a raw space in the URL, and a `#` would open a fragment
          # and silently target a different label (round-1 finding M2).
          *)       enc=$(jq -rn --arg n "$name" '$n|@uri')
                   forge_api PATCH "/repos/$REPO/labels/$enc" "$body" >/dev/null ;;
        esac || { echo "sync-labels: failed to update '$name'; the host may be partially synced" >&2; exit 4; }
      fi
      updated=$((updated + 1))
    fi
  fi
done <<< "$declared"

# --- 4. labels on the host that nobody declared: report, never touch ---------------------------
undeclared=$(printf '%s' "$existing" | jq -r '.[].name' \
  | grep -vxF -f <(printf '%s\n' "$declared" | cut -d"$US" -f1) || true)
if [ -n "$undeclared" ]; then
  echo "sync-labels: on $REPO but not declared (left alone, never deleted):" >&2
  printf '%s\n' "$undeclared" | sed 's/^/  extra    /' >&2
fi

if [ "$MODE" = check ]; then
  if [ "$missing" -gt 0 ] || [ "$drifted" -gt 0 ]; then
    echo "sync-labels: $REPO is out of sync with $LABELS_FILE"
    printf '%s' "$report"
    echo "Run: sync-labels.sh   (to create the missing labels and fix the drifted ones)"
    exit 1
  fi
  echo "sync-labels: $REPO matches $LABELS_FILE (all declared labels present and current)."
  exit 0
fi

echo "sync-labels: $REPO synced from $LABELS_FILE ($created created, $updated updated)."
exit 0
