#!/usr/bin/env bash
# reassess-phases-version: 1
#
# Reshapes docs/roadmap.md itself: the level above /phase review (#244), which asks whether ONE
# phase is still aligned. This asks whether the ROADMAP is still the right plan (#249).
#
#   reassess-phases.sh <op> [op args] [--roadmap FILE] [--check] [--reason TEXT]
#     reorder <phase>  --before <phase>|--end
#     split   <phase>  --into <name> --move <n1,n2,...> [--state STATE] [--before <phase>|--end] [--plan PATH]
#     merge   <loser>  --into <winner>                                    (--reason required)
#     rename  <old> <new>
#     refocus <phase>  --prose TEXT [--plan PATH]
#     delete  <phase>  [--to <phase>|backlog]
#     insert  <name>   --before <phase>|--end --state STATE --prose TEXT [--plan PATH]
#
#   --check    show every act it would perform, with its reason; write nothing
#   --reason   the "why", folded into the roadmap prose a created, deleted or refocused phase carries
#
# Exit codes are distinguishable, because a reassessment is unattended-safe automation:
#   0  done (or, under --check, nothing this reshape would do is refused)
#   2  usage or environment error; the roadmap is malformed; NOTHING was written
#   4  a ticket move failed part-way; the file half was not touched; re-running resumes and is safe
#   5  a policy refusal on a well-formed file (a rule this reshape would break); NOTHING was written
#   N  whatever check-phases.sh's own verdict exits, reported verbatim, as the LAST act of a real run
#
# COMPUTE, THEN REFUSE WHOLE. Every op validates before it writes anything: a rule this reshape
# would break, a done phase it would rewrite, a milestone it would need to delete or reopen. A
# refusal (exit 5) happens before any roadmap-lib.sh writer or forge_issue_milestone call, so the
# roadmap file is byte-identical to before and the host receives no request.
#
# FILE BEFORE HOST, EXCEPT A BLOCK REMOVAL. roadmap_remove refuses without --milestone-empty, which
# asserts the caller already confirmed the milestone is empty ON THE HOST, so a merge's losing block
# and a delete-with-relocation's block cannot be removed from the file until every ticket has
# actually left that milestone. Those two operations are HOST then FILE; every other write is FILE
# then HOST (a rename's heading changes before its milestone is chased; an insert's block lands
# before sync-phases.sh is asked to create its milestone).
#
# NEVER DELETES OR REOPENS A MILESTONE. A merge, rename or delete that empties a milestone leaves it
# on the host, reported as emptied rather than gone: the same rule sync-phases.sh already holds, for
# the same reason, extended here to a milestone this script itself just emptied.
#
# A DONE PHASE'S PROSE IS NEVER REWRITTEN. That prose is a close review's record, not a plan; a
# merge or refocus that would touch one refuses, naming it.
#
# A RE-RUN SKIPS WHATEVER ALREADY LANDED, on the file side as well as the host side. The host calls
# are naturally idempotent (setting a milestone to the value it already holds is a no-op); this
# script makes the file side match by checking each write's INTENDED RESULT before making it: a
# rename whose new heading is already in place, a merge whose target prose already carries the exact
# reason sentence, a block already removed. Re-running after a partial failure resumes from there
# rather than repeating or duplicating a write.
#
# INSERTING AN OPEN PHASE NEEDS A PLAN ALREADY ON DISK, with a "Fails if" section: check-phases.sh
# rule 2 requires it, and writing a premortem is /phase plan's job, not something fabricated here. A
# plan-less insert may still land as `planned`, which rule 2 does not govern.
#
# A PARTIAL TICKET MOVE IS REPORTED, NEVER SILENTLY SWALLOWED. The N sequential
# forge_issue_milestone calls a merge, rename or relocating delete makes stop at the first failure,
# name which tickets moved and which did not, and a milestone is reported emptied only once a fresh
# re-read confirms zero open tickets in it, never on faith that every call in the loop returned 0.

set -uo pipefail

_HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HERE_LIB/roadmap-lib.sh" ]; then
  # shellcheck source=roadmap-lib.sh
  . "$_HERE_LIB/roadmap-lib.sh"
else
  echo "reassess-phases: roadmap-lib.sh not found next to this script. It defines the roadmap format," >&2
  echo "  and its write primitives, so nothing can be reshaped without it. Install it alongside this asset." >&2
  exit 2
fi

SELF="$(abspath "${BASH_SOURCE[0]}")"
HERE="$(cd "$(dirname "$SELF")" && pwd)"

die()    { printf 'reassess-phases: %s\n' "$1" >&2; exit 2; }
refuse() { printf 'reassess-phases: %s\n' "$1" >&2; exit 5; }

usage="usage: reassess-phases.sh <op> ... [--roadmap FILE] [--check] [--reason TEXT]
  ops: reorder, split, merge, rename, refocus, delete, insert"

[ $# -ge 1 ] || die "$usage"
case "$1" in
  --help|-h) awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit 0 ;;
esac
OP="$1"; shift
case "$OP" in
  reorder|split|merge|rename|refocus|delete|insert) ;;
  *) die "unknown op '$OP'. $usage" ;;
esac

ROADMAP=""; CHECK=0; REASON=""
BEFORE=""; END=0; INTO=""; MOVE=""; STATE=""; PLAN=""; PROSE=""; TO=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --roadmap) shift; [ $# -gt 0 ] || die "--roadmap needs a path"; ROADMAP="$1" ;;
    --check)   CHECK=1 ;;
    --reason)  shift; [ $# -gt 0 ] || die "--reason needs text"; REASON="$1" ;;
    --into)    shift; [ $# -gt 0 ] || die "--into needs a phase name"; INTO="$1" ;;
    --move)    shift; [ $# -gt 0 ] || die "--move needs a comma-separated ticket list"; MOVE="$1" ;;
    --before)  shift; [ $# -gt 0 ] || die "--before needs a phase name"; BEFORE="$1" ;;
    --end)     END=1 ;;
    --state)   shift; [ $# -gt 0 ] || die "--state needs one of planned|open|done|backlog"; STATE="$1" ;;
    --plan)    shift; [ $# -gt 0 ] || die "--plan needs a path"; PLAN="$1" ;;
    --prose)   shift; [ $# -gt 0 ] || die "--prose needs text"; PROSE="$1" ;;
    --to)      shift; [ $# -gt 0 ] || die "--to needs a phase name or 'backlog'"; TO="$1" ;;
    --help|-h) awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit 0 ;;
    -*)        die "unknown flag: $1" ;;
    *)         ARGS+=("$1") ;;
  esac
  shift
done

if [ -z "$ROADMAP" ]; then
  for c in docs/roadmap.md roadmap.md; do [ -f "$c" ] && { ROADMAP="$c"; break; }; done
fi
[ -n "$ROADMAP" ] || die "no roadmap at docs/roadmap.md or roadmap.md, and --roadmap was not given"

# Resolving forge-lib.sh: BESIDE, then by SEARCH, never by \$CLAUDE_PLUGIN_ROOT. Byte-identical to
# check-phases.sh and sync-phases.sh's own copy (see their headers for why each branch exists).
find_forge_lib() {
  [ -n "${FORGE_LIB:-}" ] && [ -f "$FORGE_LIB" ] && { printf '%s' "$FORGE_LIB"; return 0; }
  [ -f "$HERE/forge-lib.sh" ] && { printf '%s' "$HERE/forge-lib.sh"; return 0; }
  local root p
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    for p in "$root"/scripts/forge-lib.sh \
             "$root"/plugins/*/skills/forge-host/assets/forge-lib.sh; do
      [ -f "$p" ] && { printf '%s' "$p"; return 0; }
    done
  fi
  p="$(find "$HOME/.claude/plugins" -name forge-lib.sh 2>/dev/null | while IFS= read -r f; do
         v="$(grep -m1 -o '^# forge-lib-version: [0-9][0-9]*' "$f" 2>/dev/null | grep -o '[0-9]*$')"
         [ -n "$v" ] && printf '%s\t%s\n' "$v" "$f"
       done | sort -t "$(printf '\t')" -k1,1n -k2,2 | tail -1 | cut -f2-)"
  [ -n "$p" ] && {
    echo "reassess-phases: forge-lib.sh from $p ($(grep -m1 -o 'forge-lib-version: [0-9]*' "$p"))" >&2
    printf '%s' "$p"; return 0
  }
  return 1
}
LIB="$(find_forge_lib)" || {
  echo "reassess-phases: forge-lib.sh not found, so nothing can be reshaped." >&2
  echo "  This group DEPENDS on forge-kit-devops, which ships forge-lib.sh. Install it:" >&2
  echo "      /plugin install forge-kit-devops@forge-kit" >&2
  echo "  or point FORGE_LIB at a copy." >&2
  exit 2
}
# shellcheck source=forge-lib.sh
. "$LIB"

PHASES="$(parse_roadmap "$ROADMAP")"
if printf '%s\n' "$PHASES" | grep -q '^MALFORMED'; then
  printf '%s\n' "$PHASES" \
    | awk -F'\t' -v f="$ROADMAP" '/^MALFORMED/ {printf("reassess-phases: %s: phase \"%s\": %s\n", f, $2, $3)}' >&2
  echo "reassess-phases: state must be one of: planned, open, done, backlog." >&2
  echo "  NOTHING was written." >&2
  exit 3
fi
MS="$(forge_milestone_list)" || die "could not list milestones; check the token and the forge configuration"
ISS="$(forge_issue_milestone_list)" || die "could not list issue milestones; check the token and the forge configuration"

# --- read-only helpers over $PHASES / $MS / $ISS, all fixed as of this run's start ---------------
phase_exists()      { printf '%s\n' "$PHASES" | awk -F'\t' -v n="$1" '$1==n{f=1} END{exit !f}'; }
phase_state()       { printf '%s\n' "$PHASES" | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'; }
next_phase_name()    { printf '%s\n' "$PHASES" | awk -F'\t' -v n="$1" '{a[NR]=$1} a[NR]==n{f=NR} END{if(f && a[f+1]!="") print a[f+1]}'; }
open_ticket_numbers() { printf '%s' "$ISS" | jq -r --arg t "$1" '.[] | select(.milestone==$t) | .number'; }
resolve_dest() {
  local raw="$1"
  if [ "$raw" = backlog ] && ! phase_exists backlog; then
    local bp; bp="$(printf '%s\n' "$PHASES" | awk -F'\t' '$2=="backlog"{print $1; exit}')"
    [ -n "$bp" ] || refuse "no phase with state: backlog exists, so '--to backlog' cannot be resolved"
    printf '%s' "$bp"; return 0
  fi
  printf '%s' "$raw"
}
_read_prose() {  # _read_prose <phase> -> its current prose text, trimmed
  local blk s e
  blk="$(_rm_block "$ROADMAP" "$1")"
  case "$blk" in NONE|DUPLICATE) return 1 ;; esac
  s="${blk%% *}"; e="${blk##* }"
  awk -v s="$s" -v e="$e" '
    NR<=s{next} NR>=e{next}
    index($0,"state:")==1 || index($0,"plan:")==1 {next}
    {lines[++n]=$0}
    END{
      st=1; while (st<=n && lines[st]=="") st++
      en=n; while (en>=st && lines[en]=="") en--
      for(i=st;i<=en;i++) print lines[i]
    }' "$ROADMAP"
}

# --- write-gated helpers: --check reports, otherwise performs and reports ------------------------
act() {  # act <description> <command...>
  local desc="$1"; shift
  if [ "$CHECK" = 1 ]; then echo "would $desc"; return 0; fi
  echo "$desc"; "$@"
}
record_note() {  # append a "- <line>" under a trailing "## Notes" section, once
  local line="$1" cand
  grep -qxF -- "- $line" "$ROADMAP" 2>/dev/null && { echo "already recorded: $line"; return 0; }
  if [ "$CHECK" = 1 ]; then echo "would record: $line"; return 0; fi
  cand="$(_rm_tmp "$ROADMAP")"; [ -n "$cand" ] || die "cannot create a temp file beside '$ROADMAP'"
  cp -p "$ROADMAP" "$cand" 2>/dev/null || cp "$ROADMAP" "$cand"
  if grep -qx '## Notes' "$cand" 2>/dev/null; then
    printf -- '- %s\n' "$line" >> "$cand"
  else
    printf '\n## Notes\n\n- %s\n' "$line" >> "$cand"
  fi
  _rm_check "$cand" || { rm -f "$cand"; die "that note would leave the roadmap malformed; nothing written"; }
  mv -f "$cand" "$ROADMAP" || { rm -f "$cand"; die "cannot write notes to '$ROADMAP'"; }
  echo "recorded: $line"
}
move_tickets() {  # move_tickets <dest-title> <ticket...> -> 0 all moved, 1 stopped partway
  local dest="$1"; shift
  local tickets=("$@") moved=() i n
  for ((i = 0; i < ${#tickets[@]}; i++)); do
    n="${tickets[$i]}"
    if [ "$CHECK" = 1 ]; then
      echo "would move #$n to \"$dest\""; moved+=("$n"); continue
    fi
    if forge_issue_milestone "$n" "$dest"; then
      echo "moved #$n to \"$dest\""; moved+=("$n")
    else
      echo "reassess-phases: failed moving #$n; moved so far: ${moved[*]:-none}; still to move: ${tickets[*]:$i}" >&2
      return 1
    fi
  done
  return 0
}
confirm_emptied() {  # confirm_emptied <title> -> 0 confirmed empty (or --check), 1 still holds tickets
  local title="$1" remaining
  if [ "$CHECK" = 1 ]; then echo "would confirm \"$title\" holds zero open tickets before continuing"; return 0; fi
  remaining="$(forge_issue_milestone_list | jq -r --arg t "$title" '[.[] | select(.milestone==$t)] | length')" \
    || { echo "reassess-phases: could not re-read milestone \"$title\"" >&2; return 1; }
  if [ "${remaining:-1}" = 0 ]; then
    echo "\"$title\" is now emptied, not deleted: left on the host."; return 0
  fi
  echo "reassess-phases: \"$title\" still holds $remaining open ticket(s) after moving; not proceeding. Re-run once fixed." >&2
  return 1
}
sync_milestones() {  # runs sync-phases.sh so a newly-declared or renamed phase has a real milestone
  if [ "$CHECK" = 1 ]; then
    echo "would run sync-phases.sh to reconcile milestones"
  else
    bash "$HERE/sync-phases.sh" --roadmap "$ROADMAP" >/dev/null \
      || echo "reassess-phases: sync-phases.sh reported a problem reconciling milestones; continuing" >&2
  fi
}
finalize() {
  if [ "$CHECK" = 1 ]; then
    echo "-- dry run: would then run sync-phases.sh --check and check-phases.sh --"
    bash "$HERE/sync-phases.sh" --check --roadmap "$ROADMAP" || true
    exit 0
  fi
  sync_milestones
  echo "-- check-phases.sh --"
  bash "$HERE/check-phases.sh" --roadmap "$ROADMAP"
  exit $?
}

# --- ops -------------------------------------------------------------------------------------------
op_reorder() {
  local phase="${ARGS[0]-}"
  [ -n "$phase" ] || die "usage: reassess-phases.sh reorder <phase> --before <phase>|--end"
  phase_exists "$phase" || refuse "no phase named '$phase'"
  { [ -n "$BEFORE" ] || [ "$END" = 1 ]; } || die "usage: reassess-phases.sh reorder <phase> --before <phase>|--end"
  if [ -n "$BEFORE" ]; then
    phase_exists "$BEFORE" || refuse "no phase named '$BEFORE' to reorder before"
    act "reorder '$phase' before '$BEFORE'" roadmap_reorder "$ROADMAP" "$phase" --before "$BEFORE" || refuse "reorder failed"
  else
    act "reorder '$phase' to the end" roadmap_reorder "$ROADMAP" "$phase" --end || refuse "reorder failed"
  fi
  finalize
}

op_refocus() {
  local phase="${ARGS[0]-}"
  [ -n "$phase" ] || die "usage: reassess-phases.sh refocus <phase> --prose TEXT [--plan PATH] [--reason TEXT]"
  phase_exists "$phase" || refuse "no phase named '$phase'"
  [ -n "$PROSE" ] || die "refocus needs --prose TEXT describing the new work"
  [ "$(phase_state "$phase")" = done ] && refuse "'$phase' is done; its prose is a close review's record and is never rewritten"
  local prose="$PROSE"
  [ -n "$REASON" ] && prose="$PROSE

Refocused: $REASON"
  act "refocus '$phase' with new prose" roadmap_set_prose "$ROADMAP" "$phase" "$prose" || refuse "refocus failed"
  if [ -n "$PLAN" ]; then
    act "point '$phase' at plan $PLAN" roadmap_set_plan "$ROADMAP" "$phase" "$PLAN" || refuse "setting the plan failed"
  fi
  finalize
}

op_insert() {
  local name="${ARGS[0]-}"
  [ -n "$name" ] || die "usage: reassess-phases.sh insert <name> --before <phase>|--end --state STATE --prose TEXT [--plan PATH] [--reason TEXT]"
  [ -n "$STATE" ] || die "insert needs --state planned|open|done|backlog"
  case "$STATE" in planned|open|done|backlog) ;; *) die "unknown state '$STATE'" ;; esac
  [ -n "$PROSE" ] || die "insert needs --prose TEXT"
  { [ -n "$BEFORE" ] || [ "$END" = 1 ]; } || die "insert needs --before <phase>|--end"
  local prose="$PROSE"
  [ -n "$REASON" ] && prose="$PROSE

Why now: $REASON"
  if [ "$STATE" = open ]; then
    local open; open="$(printf '%s\n' "$PHASES" | awk -F'\t' '$2=="open"{print $1; exit}')"
    [ -z "$open" ] || refuse "'$open' is already open. At most one phase may be open at a time"
  fi
  if [ "$STATE" = open ] || [ "$STATE" = done ]; then
    [ -n "$PLAN" ] || refuse "state '$STATE' for '$name' needs check-phases.sh rule 2's plan file already on disk. Pass --plan PATH"
    [ -f "$PLAN" ] || refuse "state '$STATE' for '$name' needs plan $PLAN to exist first (rule 2)"
    grep -qiE '^#{1,4}[[:space:]]*Fails if' "$PLAN" \
      || refuse "state '$STATE' for '$name' needs plan $PLAN to carry a \"Fails if\" section first (rule 2)"
  fi
  if phase_exists "$name"; then
    echo "'$name' is already in the roadmap; skipping the insert (idempotent re-run)"
  elif [ -n "$BEFORE" ]; then
    phase_exists "$BEFORE" || refuse "no phase named '$BEFORE' to insert before"
    act "insert '$name' before '$BEFORE'" roadmap_insert_at "$ROADMAP" --before "$BEFORE" "$name" "$STATE" "${PLAN:-}" "$prose" || refuse "insert failed"
  else
    act "insert '$name' at the end" roadmap_insert_at "$ROADMAP" --end "$name" "$STATE" "${PLAN:-}" "$prose" || refuse "insert failed"
  fi
  sync_milestones
  finalize
}

op_split() {
  local phase="${ARGS[0]-}"
  [ -n "$phase" ] || die "usage: reassess-phases.sh split <phase> --into <name> --move <n1,n2,...> [--state STATE] [--before <phase>|--end] [--plan PATH] [--reason TEXT]"
  phase_exists "$phase" || refuse "no phase named '$phase'"
  [ -n "$INTO" ] || die "split needs --into <name>"
  [ -n "$MOVE" ] || die "split needs --move <ticket,ticket,...>"
  local state="${STATE:-planned}"
  case "$state" in planned|open|done|backlog) ;; *) die "unknown state '$state'" ;; esac
  [ "$(phase_state "$phase")" = done ] && refuse "'$phase' is done; splitting it would rewrite a closed record"
  if [ "$state" = open ]; then
    local open; open="$(printf '%s\n' "$PHASES" | awk -F'\t' '$2=="open"{print $1; exit}')"
    [ -z "$open" ] || refuse "'$open' is already open. At most one phase may be open at a time"
  fi
  local tks=(); IFS=',' read -r -a tks <<<"$MOVE"
  if [ "$state" = done ] && [ "${#tks[@]}" -gt 0 ]; then
    refuse "a new phase cannot be inserted 'done' while holding open tickets (rule 4)"
  fi
  if [ "$state" = open ] || [ "$state" = done ]; then
    [ -n "$PLAN" ] && [ -f "$PLAN" ] && grep -qiE '^#{1,4}[[:space:]]*Fails if' "$PLAN" \
      || refuse "state '$state' for '$INTO' needs a plan file already on disk with a \"Fails if\" section (rule 2). Pass --plan PATH"
  fi
  local prose="Split from \"$phase\""
  [ -n "$REASON" ] && prose="$prose: $REASON"
  if phase_exists "$INTO"; then
    echo "'$INTO' already exists; skipping the insert (idempotent re-run)"
  elif [ -n "$BEFORE" ]; then
    phase_exists "$BEFORE" || refuse "no phase named '$BEFORE' to insert before"
    act "insert '$INTO' before '$BEFORE'" roadmap_insert_at "$ROADMAP" --before "$BEFORE" "$INTO" "$state" "${PLAN:-}" "$prose" || refuse "insert failed"
  elif [ "$END" = 1 ]; then
    act "insert '$INTO' at the end" roadmap_insert_at "$ROADMAP" --end "$INTO" "$state" "${PLAN:-}" "$prose" || refuse "insert failed"
  else
    local succ; succ="$(next_phase_name "$phase")"
    if [ -n "$succ" ]; then
      act "insert '$INTO' right after '$phase' (before '$succ')" roadmap_insert_at "$ROADMAP" --before "$succ" "$INTO" "$state" "${PLAN:-}" "$prose" || refuse "insert failed"
    else
      act "insert '$INTO' right after '$phase' (at the end)" roadmap_insert_at "$ROADMAP" --end "$INTO" "$state" "${PLAN:-}" "$prose" || refuse "insert failed"
    fi
  fi
  sync_milestones
  if [ "${#tks[@]}" -gt 0 ]; then
    move_tickets "$INTO" "${tks[@]}" || { echo "reassess-phases: moving tickets into '$INTO' failed partway; re-run once fixed" >&2; exit 4; }
  fi
  finalize
}

op_merge() {
  local loser="${ARGS[0]-}"
  [ -n "$loser" ] || die "usage: reassess-phases.sh merge <loser> --into <winner> --reason TEXT"
  [ -n "$INTO" ] || die "merge needs --into <winner>"
  [ -n "$REASON" ] || die "merge needs --reason TEXT to append to the surviving phase's prose"
  local winner="$INTO" gone=0
  phase_exists "$loser" || gone=1
  if [ "$gone" = 0 ]; then
    phase_exists "$winner" || refuse "no phase named '$winner'"
    local lstate wstate; lstate="$(phase_state "$loser")"; wstate="$(phase_state "$winner")"
    if [ "$lstate" = done ] || [ "$wstate" = done ]; then
      refuse "a done phase's prose is never rewritten: $([ "$lstate" = done ] && printf '%s' "$loser" || printf '%s' "$winner") is done"
    fi
  else
    phase_exists "$winner" || refuse "no phase named '$winner' (and '$loser' is not in the roadmap either)"
  fi
  local tickets=()
  [ "$gone" = 0 ] && tickets=($(open_ticket_numbers "$loser"))
  if [ "${#tickets[@]}" -gt 0 ]; then
    move_tickets "$winner" "${tickets[@]}" || { echo "reassess-phases: moving tickets from '$loser' to '$winner' failed partway; re-run once fixed" >&2; exit 4; }
  fi
  if [ "$gone" = 0 ]; then
    confirm_emptied "$loser" || exit 4
    local wprose sentence newprose
    wprose="$(_read_prose "$winner")" || wprose=""
    sentence="Merged \"$loser\" in: $REASON"
    if printf '%s\n' "$wprose" | grep -qxF -- "$sentence"; then
      echo "'$winner' prose already carries the merge reason; not appending again"
    else
      if [ -n "$wprose" ]; then newprose="$wprose

$sentence"; else newprose="$sentence"; fi
      act "append the merge reason to '$winner' prose" roadmap_set_prose "$ROADMAP" "$winner" "$newprose" || refuse "updating '$winner' prose failed"
    fi
    record_note "\"$loser\"'s milestone is left on the host, emptied by the merge into \"$winner\". Its plan file, if any, is left on disk and is no longer pointed to."
    act "remove '$loser' from the roadmap" roadmap_remove "$ROADMAP" "$loser" --milestone-empty || refuse "removing '$loser' failed"
  else
    echo "'$loser' is already merged away; skipping the file half (idempotent re-run)"
  fi
  finalize
}

op_rename() {
  local old="${ARGS[0]-}" new="${ARGS[1]-}"
  { [ -n "$old" ] && [ -n "$new" ]; } || die "usage: reassess-phases.sh rename <old> <new>"
  local already=0
  if ! phase_exists "$old"; then
    phase_exists "$new" || refuse "no phase named '$old' (and none named '$new' either)"
    already=1
  else
    phase_exists "$new" && refuse "a phase named '$new' is already in the roadmap"
  fi
  if [ "$already" = 0 ]; then
    act "rename '$old' to '$new' in the roadmap" roadmap_rename "$ROADMAP" "$old" "$new" || refuse "rename failed"
  else
    echo "'$old' is already renamed to '$new'; skipping the file half (idempotent re-run)"
  fi
  sync_milestones
  local tickets=(); tickets=($(open_ticket_numbers "$old"))
  if [ "${#tickets[@]}" -gt 0 ]; then
    move_tickets "$new" "${tickets[@]}" || { echo "reassess-phases: moving tickets from '$old' to '$new' failed partway; re-run once fixed" >&2; exit 4; }
  fi
  confirm_emptied "$old" || exit 4
  finalize
}

op_delete() {
  local phase="${ARGS[0]-}"
  [ -n "$phase" ] || die "usage: reassess-phases.sh delete <phase> [--to <phase>|backlog] [--reason TEXT]"
  local gone=0
  phase_exists "$phase" || gone=1
  if [ "$gone" = 0 ]; then
    local tickets=(); tickets=($(open_ticket_numbers "$phase"))
    if [ "${#tickets[@]}" -gt 0 ]; then
      [ -n "$TO" ] || refuse "'$phase' holds ${#tickets[@]} open ticket(s) (${tickets[*]}) and names nowhere for them. Pass --to <phase>|backlog"
      local dest; dest="$(resolve_dest "$TO")"
      phase_exists "$dest" || refuse "no destination phase named '$dest'"
      [ "$(phase_state "$dest")" = done ] && refuse "destination '$dest' is done; moving open tickets there would break rule 4"
      move_tickets "$dest" "${tickets[@]}" || { echo "reassess-phases: moving tickets from '$phase' to '$dest' failed partway; re-run once fixed" >&2; exit 4; }
      confirm_emptied "$phase" || exit 4
    fi
    record_note "Deleted phase \"$phase\"${REASON:+: $REASON}"
    act "remove '$phase' from the roadmap" roadmap_remove "$ROADMAP" "$phase" --milestone-empty || refuse "removing '$phase' failed"
  else
    echo "'$phase' is already removed from the roadmap; skipping (idempotent re-run)"
  fi
  finalize
}

case "$OP" in
  reorder) op_reorder ;;
  split)   op_split ;;
  merge)   op_merge ;;
  rename)  op_rename ;;
  refocus) op_refocus ;;
  delete)  op_delete ;;
  insert)  op_insert ;;
esac
