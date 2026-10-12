#!/usr/bin/env bash
# review-mechanics-version: 1
#
# The mechanical half of /phase review steps 1 to 4, runnable without the agent harness (#272).
#
#   review-mechanics.sh <phase> [--range <a>..<b>]
#
#   exit 0  every read ran and check-phases.sh exited 0
#   exit 1  every read ran and check-phases.sh exited non-zero (its rc and lines are in the rows)
#   exit 2  could not run: one stderr line, and NOTHING on stdout
#
# WHY THIS EXISTS. /phase review's reads were prose in phase.md, so the rules that had already
# produced review findings (superseded-body exclusion, the no-duplicate-on-retry comparison, the
# range, the commit listing) could only be checked inside a live agent session. phase.md steps 1 to
# 4 now CALL this, so its suite pins what the agent runs rather than a second copy.
#
# IT EMITS ROWS AND DECIDES NOTHING. One fact per row, tab-separated, buffered and printed only once
# every read has run, so a refusal can never leave half a listing that reads as complete:
#
#   forge_lib     <forge-lib-version found>
#   check_phases  rc <n>              then one row per line: stdout <line> | stderr <line>
#   range         <a>..<b>  derived|override     (pass field 2 ALONE to check-doc-drift.sh --range)
#   ticket        <N> <open|closed> <title>
#   comment       <N> <id> <text flattened to one line>
#   superseded    <N> <id>            a comment whose FIRST line is exactly the marker below
#   preserved     <N> <id>            that comment's text after line 1 equals the body byte for byte
#   commit        <N> <sha> <subject>, oldest first; or <N> none
#   summary       <kind>=<count> per kind, never a verdict
#
# check-phases.sh's STDERR is carried too, tagged, because that is where it says rules 1, 3 and 4
# were SKIPPED; a skipped rule must not vanish from the rows. The implemented / partly / superseded
# judgement, the report and every write (steps 5 to 7) stay with the agent: this file calls no
# forge or roadmap writer and writes nothing outside its own mktemp -d directory.
#
# THE RANGE (the skill's rule): the commit that ADDED the plan file, included, to HEAD, so
# `<sha>^..HEAD`. With no add commit, or a plan added in the repository's first commit (`<sha>^`
# does not exist), it REFUSES and asks for --range rather than guessing; a plan that predates the
# phase opening is the agent's judgement, and it passes --range then.
#
# THE COMMITS of ticket N are the union of two searches over the range, both on the `#N` token and
# both bounded as `#N([^0-9]|$)`, so `#27` never matches `#272`: the commit MESSAGE
# (`git log -E --grep`) and the DIFF (`git log -S --pickaxe-regex`, a CHANGELOG line naming the
# ticket when the message does not). A `-S` on the behaviour itself stays the agent's.
#
# COST. Tickets come from `forge_issue_list all` filtered on the milestone title, because
# forge_issue_milestone_list reads open issues only. That listing pages through EVERY issue in the
# repository, open and closed, whatever the milestone; forge-lib offers no milestone filter. Then one
# forge_issue_comments call and two git log calls per ticket in the milestone.
#
# Libraries: FORGE_LIB, ROADMAP_LIB and CHECK_PHASES when set, else beside this script, else across
# plugin groups in a source checkout. One set EMPTY, or to a path that is not a file, refuses before
# anything is sourced (#267 F7). No harness CLI and no $CLAUDE_PLUGIN_ROOT anywhere in this path.
# Needs: bash 3.2+, git, jq, awk, forge-lib.sh at FORGE_LIB_MIN or later.
set -uo pipefail

# The lowest forge-lib-version this needs; the suite reads it from here rather than restating it.
FORGE_LIB_MIN=25
MARK='## Superseded body (phase review)'

die() { printf 'review-mechanics: %s\n' "$1" | sed "s|$HOME|~|g" >&2; exit 2; }
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

find_beside() {  # find_beside <filename> <source-tree-relative-fallback>
  if [ -f "$HERE/$1" ]; then printf '%s\n' "$HERE/$1"; return 0; fi
  if [ -f "$HERE/../../../../$2" ]; then
    printf '%s/%s\n' "$(CDPATH= cd -- "$HERE/../../../../$(dirname "$2")" && pwd)" "$(basename "$2")"
    return 0
  fi
  return 1
}
# lib <VAR> <filename> <fallback>: the override when SET (an empty one refuses), else the search.
lib() {
  local v
  if eval "[ -n \"\${$1+x}\" ]"; then
    eval "v=\"\${$1}\""
    [ -n "$v" ] || die "$2: $1 is set but empty (an unresolved asset), so nothing was read"
    [ -f "$v" ] || die "$2: $1=$v is not a file, so nothing was read"
    printf '%s\n' "$v"; return 0
  fi
  find_beside "$2" "$3" || die "$2 not found beside this script; set $1 to it. Nothing was read"
}

PHASE=""; RANGE=""; HAVE_RANGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --range) [ $# -ge 2 ] || die "--range needs a value (<a>..<b>)"; RANGE="$2"; HAVE_RANGE=1; shift 2 ;;
    -h|--help) sed -n '2,/^# Needs:/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [ -z "$PHASE" ] || die "one phase name only (got '$PHASE' and '$1')"; PHASE="$1"; shift ;;
  esac
done
[ -n "$PHASE" ] || die "a phase name is required: review-mechanics.sh <phase> [--range <a>..<b>]"

FLIB=$(lib FORGE_LIB forge-lib.sh forge-kit-devops/skills/forge-host/assets/forge-lib.sh) || exit 2
RLIB=$(lib ROADMAP_LIB roadmap-lib.sh forge-kit-roadmap/skills/roadmap-phases/assets/roadmap-lib.sh) || exit 2
CPH=$(lib CHECK_PHASES check-phases.sh forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh) || exit 2
FVER=$(grep -m1 -o 'forge-lib-version: [0-9]*' "$FLIB" | grep -o '[0-9]*$')
[ -n "$FVER" ] || die "forge-lib.sh at $FLIB carries no forge-lib-version marker (need $FORGE_LIB_MIN or later)"
[ "$FVER" -ge "$FORGE_LIB_MIN" ] || die "forge-lib.sh is version $FVER; this needs $FORGE_LIB_MIN or later"
command -v jq >/dev/null 2>&1 || die "jq is required"

top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
CDPATH= cd -- "$top" || die "cannot enter $top"

# shellcheck source=/dev/null
. "$FLIB"
# shellcheck source=roadmap-lib.sh
. "$RLIB"

W=$(mktemp -d) || die "cannot make a scratch directory"
trap 'rm -rf "$W"' EXIT
OUT="$W/rows"; : > "$OUT"
row() { local IFS="$(printf '\t')"; printf '%s\n' "$*" >> "$OUT"; }

ROADMAP=""
for c in docs/roadmap.md roadmap.md; do [ -f "$c" ] && { ROADMAP="$c"; break; }; done
[ -n "$ROADMAP" ] || die "no roadmap at docs/roadmap.md or roadmap.md"
PLAN=$(parse_roadmap "$ROADMAP" | P="$PHASE" awk -F'\t' '$1 != "MALFORMED" && $1 == ENVIRON["P"] { f = 1; print $3; exit } END { exit !f }') \
  || die "phase '$PHASE' is not a well-formed phase of $ROADMAP"

# --- the range (step 4's input), decided before any host read -----------------------------------
if [ "$HAVE_RANGE" = 1 ]; then
  case "$RANGE" in *...*|..*|*..) die "--range '$RANGE' must be <a>..<b> with two dots and both ends" ;;
                   *..*) ;; *) die "--range '$RANGE' must be <a>..<b>" ;; esac
  for ref in "${RANGE%%..*}" "${RANGE#*..}"; do
    case "$ref" in -*) die "--range: '$ref' is not a commit" ;; esac
    git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "--range: '$ref' is not a commit"
  done
  KIND=override
else
  [ -n "$PLAN" ] || die "phase '$PHASE' names no plan, so the range cannot be derived; --range is required"
  P=$(git log --diff-filter=A --format=%H -- "$PLAN" | tail -1)
  [ -n "$P" ] || die "no commit added the plan $PLAN, so the range cannot be derived; --range is required"
  git rev-parse --verify --quiet "$P^" >/dev/null \
    || die "the plan $PLAN was added in the repository's first commit ($P has no parent); --range is required"
  RANGE="$P^..HEAD"; KIND=derived
fi

row forge_lib "$FVER"

# --- step 1: the guard, both streams -------------------------------------------------------------
FORGE_LIB="$FLIB" bash "$CPH" > "$W/cp.out" 2> "$W/cp.err"; CPRC=$?
row check_phases rc "$CPRC"
tr '\t\r' '  ' < "$W/cp.out" | while IFS= read -r l || [ -n "$l" ]; do row check_phases stdout "$l"; done
tr '\t\r' '  ' < "$W/cp.err" | while IFS= read -r l || [ -n "$l" ]; do row check_phases stderr "$l"; done
row range "$RANGE" "$KIND"

# --- step 2: every ticket in the milestone, open and closed, with its comments --------------------
# FORGE_DRY_RUN=0 is scoped to each read (#306): a dry run short-circuits GET too, and an exported
# flag would fake an empty phase with rc 0. Nothing here writes, so a flagged run reads the same.
FORGE_DRY_RUN=0 forge_issue_list all > "$W/issues.json" 2> "$W/issues.err" || die "could not list the repository's issues"
P="$PHASE" jq -c '[.[] | select((.milestone.title // null) == env.P)] | sort_by(.number) | .[]' \
  < "$W/issues.json" > "$W/tickets" 2>/dev/null || die "the issue listing is not a JSON array"

while IFS= read -r t; do
  N=$(printf '%s' "$t" | jq -r '.number')
  case "$N" in ''|*[!0-9]*) die "an issue number is not numeric: '$N'" ;; esac
  printf '%s' "$t" | jq -r '[.state, .title // ""] | map(gsub("[\t\r\n]"; " ")) | join("\t")' > "$W/t"
  row ticket "$N" "$(cat "$W/t")"
  FORGE_DRY_RUN=0 forge_issue_comments "$N" > "$W/c.json" 2>/dev/null || die "could not read the comments of #$N"
  # One jq program over the raw JSON strings: the preserved comparison never passes through a shell
  # variable, which would strip trailing newlines and change the bytes compared.
  printf '%s' "$t" | jq -r --arg mark "$MARK" --arg n "$N" --slurpfile c "$W/c.json" '
    (.body // "") as $body
    | $c[0][] | (.body // "") as $cb | ($cb | split("\n")) as $ls
    | if $ls[0] == $mark then
        ["superseded", $n, (.id | tostring)],
        (if ($ls[1:] | join("\n")) == $body then ["preserved", $n, (.id | tostring)] else empty end)
      else ["comment", $n, (.id | tostring), ($cb | gsub("[\t\r\n]"; " "))] end
    | join("\t")' >> "$OUT" 2>/dev/null || die "the comments of #$N are not a JSON array"

  # --- step 3, the scriptable half: commits naming #N, in message or diff, oldest first ----------
  ( git log -E --grep="#$N([^0-9]|\$)" --format=%H "$RANGE" -- &&
    git log --pickaxe-regex -S"#$N([^0-9]|\$)" --format=%H "$RANGE" -- ) > "$W/hits" 2>/dev/null \
    || die "git log failed over $RANGE"
  git log --reverse --format='%H%x09%s' "$RANGE" -- 2>/dev/null > "$W/order" || die "git log failed over $RANGE"
  N="$N" awk 'FILENAME == ARGV[1] { h[$0] = 1; next }
    { sha = substr($0, 1, index($0, "\t") - 1); t = substr($0, index($0, "\t") + 1); gsub(/[\t\r]/, " ", t) }
    (sha in h) && !s[sha]++ { printf "commit\t%s\t%s\t%s\n", ENVIRON["N"], sha, t; k++ }
    END { if (!k) printf "commit\t%s\tnone\n", ENVIRON["N"] }' "$W/hits" "$W/order" >> "$OUT"
done < "$W/tickets"

awk -F'\t' '{ n[$1]++ } END {
  split("forge_lib check_phases range ticket comment superseded preserved commit", k, " ")
  s = "summary"; for (i = 1; i <= 8; i++) s = s "\t" k[i] "=" (n[k[i]] + 0); print s }' "$OUT" > "$W/summary"
cat "$OUT" "$W/summary"
[ "$CPRC" = 0 ] || exit 1
exit 0
