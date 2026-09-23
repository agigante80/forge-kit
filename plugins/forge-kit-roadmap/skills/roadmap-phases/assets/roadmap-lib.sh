#!/usr/bin/env bash
# roadmap-lib-version: 2
#
# The roadmap format, defined ONCE and sourced by both roadmap assets (issue #162).
#
# WHY THIS IS A LIBRARY AND NOT DUPLICATED CODE. parse_roadmap is not two similar behaviours that
# happen to look alike; it is ONE definition of a file format with two consumers. If check-phases.sh
# and sync-phases.sh ever parsed the roadmap differently, the guard would pass a file the sync then
# mis-applies. Divergence is a defect BY DEFINITION rather than a possibility, and that is exactly
# what separates a shared specification from the incidental similarity the Rule of Three warns
# against extracting too early.
#
# It shipped duplicated, guarded by a byte-identity test, on a precedent that did not apply: #112
# and #77 guard copies because extraction is IMPOSSIBLE there (a glob is not a regex; the prose
# sites need an inline fallback). Here it is possible, and sync-labels.sh sourcing forge-lib.sh is
# the pattern already proven in this repo.
#
# Source it, do not execute it. Anchor to ${BASH_SOURCE[0]}, never the working directory.
#
# v2 (#246) adds the WRITE half. Until it existed the kit could read the roadmap and not
# reshape it, so every phase move was a hand edit and the two consumers that need one
# (a phase review, a roadmap reassessment) would each have had to learn the format again.
# See the block above the primitives for the return codes and the invariant they all verify.

# --- portability ------------------------------------------------------------
# macOS still ships bash 3.2 and a BSD readlink with no -f, and this is installed into other
# people's repositories. A guard that dies on a contributor's laptop is a guard they remove.
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  set_lower() { LOWER="${1?}"; LOWER="${LOWER,,}"; }
else
  set_lower() { LOWER="$(printf '%s' "${1?}" | tr '[:upper:]' '[:lower:]')"; }
fi
abspath() {
  local d b
  d="$(dirname -- "$1")"; b="$(basename -- "$1")"
  d="$(cd -- "$d" 2>/dev/null && pwd -P)" || { printf '%s' "$1"; return; }
  printf '%s/%s' "$d" "$b"
}

# parse_roadmap <file> -> name<TAB>state<TAB>plan, one row per phase, in roadmap order.
#
# REFUSES the whole file rather than skipping a block. A silently ignored phase is a phase the guard
# reports as compliant, which is the drift it exists to end. A malformed row is emitted with a
# MALFORMED marker so the caller can report every problem at once rather than only the first.
#
parse_roadmap() {
  awk '
    /^## Phase:/ {
      if (seen) emit()
      name = $0; sub(/^## Phase: */, "", name); sub(/[ \t]+$/, "", name)
      seen = 1; state = ""; plan = ""; next
    }
    /^state:/ { state = value(); next }
    /^plan:/  { plan  = value(); next }
    END { if (seen) emit() }
    function value(   v) {
      v = $0; sub(/^[a-z]+:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); return v
    }
    function emit() {
      if (state == "") { printf("MALFORMED\t%s\tno state line\n", name); return }
      if (state != "planned" && state != "open" && state != "done" && state != "backlog") {
        printf("MALFORMED\t%s\tunknown state \"%s\"\n", name, state); return
      }
      printf("%s\t%s\t%s\n", name, state, plan)
    }
  ' "$1"
}

# --- the WRITE primitives (#246) ---------------------------------------------------------------
#
# The library was a parser with no writer, so reshaping the roadmap was a hand edit and any
# component that reshaped it would have been the format's SECOND definition of this file, which is
# the drift #162 removed. Seven primitives, because five were not enough for the consumers that
# justify them: /phase review must update a phase's prose when scope changes, and a roadmap
# reassessment must merge and refocus a phase and write the reason into the prose.
#
# THEY RETURN, THEY NEVER EXIT. This library is sourced and its own header says so; a library that
# exits kills its caller's shell. Codes: 0 done, 2 usage, 3 the file is malformed or the parser
# disagrees with what was written, 5 a POLICY refusal on a well-formed file. Not 4: sync-phases.sh
# and sync-labels.sh already use 4 for "a write failed part-way; the host may be partially synced",
# which is the opposite of "nothing was written", and every consumer sources those assets.
#
# THE WRITER'S EXTENT IS NARROWER THAN THE PARSER'S, on purpose: a block runs to the next `## `
# line, not the next `## Phase:`, so a trailing `## Notes` section is never absorbed into the prose
# a primitive rewrites. That difference is a seam, and the seam is CHECKED rather than trusted:
# every primitive parses its candidate result before the rename and refuses with 3 if parse_roadmap
# disagrees with what it wrote. An invariant that is verified cannot drift from the parser.
#
# AMBIGUITY REFUSES. Two column-0 `state:` or `plan:` lines in one block, or two phases with one
# name, are files the parser tolerates and a writer cannot act on: it cannot tell which line the
# file means. Refusing is the only honest answer, and it is where the writer is deliberately
# stricter than the parser, which must keep reading an imperfect file.

_rm_die() { printf 'roadmap-lib: %s\n' "$1" >&2; return "${2:-2}"; }

# _rm_block <file> <phase> -> "<start> <end>" (1-based, end exclusive), or refuses.
# The extent: the `## Phase: <name>` line to the next `^## ` line or EOF.
# It prints ONE word or one pair, never a pair followed by a word: the first shape of this function
# printed the block it had already found and then DUPLICATE, so every `case` arm below read the
# two-line string as neither, and a repeated name fell through to the parse-back check and reported
# itself as a malformed file. Collect first, decide at END.
_rm_block() {
  awk -v want="$2" '
    /^## / {
      name = $0; sub(/^## Phase: */, "", name); sub(/[ \t]+$/, "", name)
      if (instart) { s[++n] = instart; e[n] = NR; instart = 0 }
      if ($0 ~ /^## Phase:/ && name == want) instart = NR
      next
    }
    END {
      if (instart) { s[++n] = instart; e[n] = NR + 1 }
      if (n == 0) { print "NONE"; exit }
      if (n > 1)  { print "DUPLICATE"; exit }
      print s[1] " " e[1]
    }
  ' "$1"
}

# _rm_check <file> -> 0 when parse_roadmap reads it cleanly. MALFORMED only.
# A repeated phase NAME is deliberately not checked here. It is not malformed, the parser reads it
# without complaint, and it is only an ambiguity for the phase being written: a writer asked to
# touch Alpha in a file where Beta appears twice knows exactly which lines it means. _rm_block
# reports the repeat for the NAME it was asked about, and that is a policy refusal, a 5.
_rm_check() {
  local out
  out="$(parse_roadmap "$1")" || return 3
  printf '%s\n' "$out" | grep -q '^MALFORMED' && return 3
  return 0
}

# _rm_commit <file> <candidate> -> verify the parse-back, then replace atomically.
# The idiom is scripts/forge-adapt-agent-skills.sh's, which has 45 CI tests behind it: the temp
# sits BESIDE the target (never in TMPDIR, which may be on another filesystem or absent), `cp -p`
# carries the mode across, and the rename is what makes the file either the old one or the new one.
# A symlinked roadmap is written THROUGH, because the link is what a project pointed at on purpose.
# The chain is walked by hand, bounded, because BSD readlink has no -f and this file may not need one.
#
# THE CALLER STATES WHAT THE PARSE MUST SAY, in RM_EXPECT, and this function refuses when it says
# anything else. A structural check alone is not enough, and the case that proves it is the seam:
# the parser's extent runs past a trailing `## Notes` section while the writer's stops there, so a
# stray `state:` line down in that section silently OVERRIDES the keyed line a primitive just set.
# The result is well-formed, reads clean, and does not say what was written. Only comparing the
# whole parse against the intended one catches that, which is why the invariant is computed rather
# than asserted.
_rm_commit() {
  local target="$1" cand="$2" real link tmp got n=0
  real="$target"
  while [ -L "$real" ] && [ "$n" -lt 10 ]; do
    link="$(readlink "$real")"
    case "$link" in
      /*) real="$link" ;;
      *)  real="$(cd "$(dirname "$real")" && pwd -P)/$link" ;;
    esac
    n=$((n + 1))
  done
  _rm_check "$cand" || { _rm_die "the parser disagrees with what that edit would write; nothing changed" 3; return 3; }
  got="$(parse_roadmap "$cand")"
  [ "$got" = "${RM_EXPECT-}" ] || {
    _rm_die "the parser reads the result differently from what that edit meant to write; nothing changed" 3; return 3; }
  tmp="$(dirname "$real")/.roadmap-lib.$$.tmp"
  cp -p "$real" "$tmp" 2>/dev/null || cp "$real" "$tmp" || return 2
  cat "$cand" > "$tmp" || { rm -f "$tmp"; return 2; }
  mv -f "$tmp" "$real" || { rm -f "$tmp"; return 2; }
  return 0
}

# _rm_one_open <file> [exclude] -> the name of the open phase, if any.
_rm_one_open() {
  parse_roadmap "$1" | awk -F'\t' -v x="${2-}" '$2 == "open" && $1 != x { print $1; exit }'
}

# _rm_keyed <file> <start> <end> <key> -> how many column-0 `<key>:` lines the block carries.
_rm_keyed() {
  awk -v s="$2" -v e="$3" -v k="$4" 'NR > s && NR < e && index($0, k ":") == 1 { n++ } END { print n + 0 }' "$1"
}

_rm_prepare() {  # _rm_prepare <file> <phase> -> sets RM_START, RM_END; refuses otherwise
  local blk
  [ -f "$1" ] || { _rm_die "no such roadmap: $1"; return 2; }
  _rm_check "$1" || { _rm_die "the roadmap is malformed; refusing to write to it" 3; return 3; }
  blk="$(_rm_block "$1" "$2")"
  case "$blk" in
    NONE)      _rm_die "no phase named '$2'" 5; return 5 ;;
    DUPLICATE) _rm_die "two phases are named '$2'; a writer cannot tell which the file means" 5; return 5 ;;
  esac
  RM_START="${blk%% *}"; RM_END="${blk##* }"
  return 0
}

# roadmap_set_state <file> <phase> <state>
roadmap_set_state() {
  local f="$1" phase="$2" st="$3" open cand
  case "$st" in planned|open|done|backlog) ;; *) _rm_die "unknown state '$st'" 2; return 2 ;; esac
  _rm_prepare "$f" "$phase" || return $?
  [ "$(_rm_keyed "$f" "$RM_START" "$RM_END" state)" = 1 ] || {
    _rm_die "the '$phase' block carries no single column-0 state line; a writer cannot act on it" 5; return 5; }
  if [ "$st" = open ]; then
    open="$(_rm_one_open "$f" "$phase")"
    [ -z "$open" ] || { _rm_die "'$open' is already open; at most one phase is open at a time" 5; return 5; }
  fi
  RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v OFS='\t' -v p="$phase" -v st="$st" '$1 == p { $2 = st } { print }')"
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v e="$RM_END" -v st="$st" '
    NR > s && NR < e && index($0, "state:") == 1 { print "state: " st; next } { print }
  ' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; local rc=$?; rm -f "$cand"; return $rc
}

# roadmap_set_plan <file> <phase> <path>
roadmap_set_plan() {
  local f="$1" phase="$2" path="$3" cand rc
  [ -n "$path" ] || { _rm_die "a plan path is required" 2; return 2; }
  _rm_prepare "$f" "$phase" || return $?
  [ "$(_rm_keyed "$f" "$RM_START" "$RM_END" plan)" = 1 ] || {
    _rm_die "the '$phase' block carries no single column-0 plan line; a writer cannot act on it" 5; return 5; }
  RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v OFS='\t' -v p="$phase" -v v="$path" '$1 == p { $3 = v } { print }')"
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v e="$RM_END" -v p="$path" '
    NR > s && NR < e && index($0, "plan:") == 1 { print "plan: " p; next } { print }
  ' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"; return $rc
}

# roadmap_set_prose <file> <phase> <text>   replace a phase's prose, keeping its keyed lines.
# The text travels through ENVIRON, never `-v`: Apple's awk refuses a newline in a -v value, which
# is #205's lesson and would make every multi-line prose silently empty on a Mac.
roadmap_set_prose() {
  local f="$1" phase="$2" cand rc
  RM_PROSE="$3"; export RM_PROSE
  case "$RM_PROSE" in *"
## "*|"## "*) _rm_die "that prose opens a '## ' section, which would silently end the block" 5; return 5 ;; esac
  _rm_prepare "$f" "$phase" || return $?
  RM_EXPECT="$(parse_roadmap "$f")"   # prose is not a parsed field: the rows must come back identical
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v e="$RM_END" '
    NR <= s { print; next }
    NR >= e { if (!done) { printf "%s\n\n", ENVIRON["RM_PROSE"]; done = 1 } print; next }
    index($0, "state:") == 1 || index($0, "plan:") == 1 { print; next }
    { next }
    END { if (!done) printf "%s\n", ENVIRON["RM_PROSE"] }
  ' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"; unset RM_PROSE; return $rc
}

# roadmap_insert_at <file> --before <phase>|--end <name> <state> <plan> <prose>
roadmap_insert_at() {
  local f="$1" where="$2" ref name st plan cand rc at open
  case "$where" in
    --before) ref="$3"; name="$4"; st="$5"; plan="$6"; RM_PROSE="$7" ;;
    --end)    ref=""; name="$3"; st="$4"; plan="$5"; RM_PROSE="$6" ;;
    *) _rm_die "insert takes --before <phase> or --end" 2; return 2 ;;
  esac
  export RM_PROSE
  case "$st" in planned|open|done|backlog) ;; *) _rm_die "unknown state '$st'" 2; return 2 ;; esac
  [ -f "$f" ] || { _rm_die "no such roadmap: $f"; return 2; }
  _rm_check "$f" || { _rm_die "the roadmap is malformed; refusing to write to it" 3; return 3; }
  case "$(_rm_block "$f" "$name")" in NONE) ;; *) _rm_die "a phase named '$name' is already in the roadmap" 5; return 5 ;; esac
  if [ "$st" = open ]; then
    open="$(_rm_one_open "$f")"
    [ -z "$open" ] || { _rm_die "'$open' is already open; at most one phase is open at a time" 5; return 5; }
  fi
  if [ -n "$ref" ]; then
    case "$(_rm_block "$f" "$ref")" in
      NONE) _rm_die "no phase named '$ref' to insert before" 5; return 5 ;;
      DUPLICATE) _rm_die "two phases are named '$ref'" 5; return 5 ;;
      *) at="$(_rm_block "$f" "$ref")"; at="${at%% *}" ;;
    esac
  else
    at=0
  fi
  RM_ROW="$(printf '%s\t%s\t%s' "$name" "$st" "$plan")"; export RM_ROW
  if [ -n "$ref" ]; then
    RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v r="$ref" '$1 == r { print ENVIRON["RM_ROW"] } { print }')"
  else
    RM_EXPECT="$(parse_roadmap "$f"; printf '%s\n' "$RM_ROW")"
  fi
  cand="$f.cand.$$"
  awk -v at="$at" -v name="$name" -v st="$st" -v plan="$plan" '
    function block() { printf "## Phase: %s\nstate: %s\nplan: %s\n\n%s\n\n", name, st, plan, ENVIRON["RM_PROSE"] }
    at > 0 && NR == at { block() } { print }
    END { if (at == 0) { print ""; block() } }
  ' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"; unset RM_PROSE; return $rc
}

# roadmap_reorder <file> <phase> --before <phase>|--end
roadmap_reorder() {
  local f="$1" phase="$2" where="$3" ref="${4-}" cand rc body at
  _rm_prepare "$f" "$phase" || return $?
  RM_ROW="$(parse_roadmap "$f" | awk -F'\t' -v p="$phase" '$1 == p')"; export RM_ROW
  case "$where" in
    --before) RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v p="$phase" -v r="$ref" '$1 == p { next } $1 == r { print ENVIRON["RM_ROW"] } { print }')" ;;
    --end)    RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v p="$phase" '$1 != p'; printf '%s\n' "$RM_ROW")" ;;
  esac
  body="$(awk -v s="$RM_START" -v e="$RM_END" 'NR >= s && NR < e' "$f")"
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v e="$RM_END" 'NR < s || NR >= e' "$f" > "$cand.strip" || return 2
  case "$where" in
    --before)
      at="$(awk -v want="$ref" '$0 ~ /^## Phase:/ { n = $0; sub(/^## Phase: */, "", n); sub(/[ \t]+$/, "", n); if (n == want) { print NR; exit } }' "$cand.strip")"
      [ -n "$at" ] || { rm -f "$cand.strip"; _rm_die "no phase named '$ref' to move before" 5; return 5; }
      RM_PROSE="$body"; export RM_PROSE
      awk -v at="$at" 'NR == at { printf "%s\n", ENVIRON["RM_PROSE"] } { print }' "$cand.strip" > "$cand" ;;
    --end)
      RM_PROSE="$body"; export RM_PROSE
      { cat "$cand.strip"; printf '%s\n' "$RM_PROSE"; } > "$cand" ;;
    *) rm -f "$cand.strip"; _rm_die "reorder takes --before <phase> or --end" 2; return 2 ;;
  esac
  rm -f "$cand.strip"
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"; unset RM_PROSE; return $rc
}

# roadmap_remove <file> <phase> [--milestone-empty]
#
# The emptiness check is the CALLER'S to make and to assert, because this library has no host
# dependency and must not grow one: rule 4 refuses a done phase holding open tickets, and the
# answer lives on the forge. So the caller passes --milestone-empty after asking, and without it
# the primitive refuses rather than assuming.
roadmap_remove() {
  local f="$1" phase="$2" flag="${3-}" cand rc
  [ "$flag" = --milestone-empty ] || {
    _rm_die "refusing to remove '$phase': pass --milestone-empty once you have confirmed on the host that its milestone holds no open tickets" 5; return 5; }
  _rm_prepare "$f" "$phase" || return $?
  RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v p="$phase" '$1 != p')"
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v e="$RM_END" 'NR < s || NR >= e' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"; return $rc
}

# roadmap_rename <file> <old> <new>
#
# REPORTS the host consequence and performs none, because there is nothing to call: forge-lib.sh
# has no milestone rename at all. And nothing downstream notices: after a roadmap-only rename
# sync-phases.sh creates the new milestone, and all four rules pass while the tickets sit under the
# old title. That silence is the whole reason this report exists.
roadmap_rename() {
  local f="$1" old="$2" new="$3" cand rc
  [ -n "$new" ] || { _rm_die "a new name is required" 2; return 2; }
  _rm_prepare "$f" "$old" || return $?
  case "$(_rm_block "$f" "$new")" in NONE) ;; *) _rm_die "a phase named '$new' is already in the roadmap" 5; return 5 ;; esac
  RM_EXPECT="$(parse_roadmap "$f" | awk -F'\t' -v OFS='\t' -v o="$old" -v n="$new" '$1 == o { $1 = n } { print }')"
  cand="$f.cand.$$"
  awk -v s="$RM_START" -v new="$new" 'NR == s { print "## Phase: " new; next } { print }' "$f" > "$cand" || { rm -f "$cand"; return 2; }
  _rm_commit "$f" "$cand"; rc=$?; rm -f "$cand"
  [ "$rc" = 0 ] && printf 'roadmap-lib: renamed in the roadmap only. forge-lib.sh has no milestone rename, so the host still carries the milestone titled "%s" with its tickets; create "%s" and move them, or the phase reads empty while all four rules pass.\n' "$old" "$new" >&2
  return $rc
}
