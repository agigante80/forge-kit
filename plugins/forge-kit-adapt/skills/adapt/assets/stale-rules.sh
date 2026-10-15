#!/usr/bin/env bash
# stale-rules-version: 4
# stale-rules.sh: find a RETIRED forge-kit rule where earlier installs and sessions left it (#495).
#
# A rule outlives its source. Version markers find a component that is behind the kit; they cannot
# find a rule restated in a project's own words, prose or memory derived from a component, or
# anything outside the project's .claude/. This scanner reads those places and reports two kinds of
# hit, each with file and line:
#   - a phrasing listed in retired-rules.tsv (beside this script), matched per paragraph;
#   - a rule id comment `<!-- rule: <id> v<M> -->` whose M is below the kit's current N for that id.
# It finds the LISTED phrasings only. A paraphrase that matches no row and carries no id is not
# found, and nothing here claims otherwise.
#
# Usage: stale-rules.sh [--kit <forge-kit dir>] [--project <dir>] [--rules <tsv>]
#        stale-rules.sh [--kit <dir>] [--rules <tsv>] --files-from <file|->
#
#   --kit         the forge-kit checkout whose `rule:` comments under plugins/ give each id's
#                 current version (forge-adapt passes $FORGE_KIT_DIR). Default: the checkout this
#                 script sits in, when it has a plugins/ directory.
#   --project     the project to scan. Default: the current directory.
#   --files-from  scan exactly the listed files (one path per line, `-` for stdin) as prose, and
#                 nothing else. The CI self-check's entry point.
#
# PLACES (an absent path is normal and produces no row). The config dir is $CLAUDE_CONFIG_DIR,
# default ~/.claude.
#   component  the project's .claude/agents, .claude/commands, .claude/skills and the config dir's
#              agents, commands, skills: every *.md beneath.
#   prose      the project's CLAUDE.md, CLAUDE.local.md, .claude/CLAUDE.md, AGENTS.md,
#              CONTRIBUTING.md, docs/**/*.md, and the config dir's CLAUDE.md.
#   memory     the project's .claude/memory and .claude/handoffs (*.md), and the auto memory dir
#              <config dir>/projects/<slug>/memory.
#
# OUTPUT, stdout, tab separated. The matched text is never printed: memory can hold names.
#   stale-rule  <component|prose|memory>  <path>  <line>  <rule id>
#   not-scanned <path>  <symlink|symlink loop|dangling symlink|unreadable|project slug over 200 characters>
#   summary     <files scanned>  <stale rows>  <not-scanned rows>          (always last)
# A project path is relative to the project; any other path under $HOME starts with `~`.
#
# EXIT 0 no hits and everything scanned; 1 at least one stale-rule row; 3 no hits but something was
# not scanned (incomplete is never reported as clean); 2 usage or read error, nothing on stdout.
#
# MATCHING. A paragraph is a run of lines ended by a blank line, a heading or a new list item. Its
# lines are joined after removing leading whitespace and `>` quote prefixes, whitespace runs become
# one space, and case is folded; a match is reported at the line where it starts. A match is
# skipped when any line it spans carries the word `retired-rule-quote` (a deliberate quote).
#
# READ ONLY. A symlink is followed in two cases, each with its own rule (#499, #518):
#   - Under the config dir, anywhere. The config dir is the user's own, and a user skill installed
#     as a link to a checkout is an ordinary shape. Refusing every link there made exit 3 permanent
#     on such a machine, so exit 3 stopped meaning anything. A link met at a named place or inside
#     one is scanned through its target and printed under the link's own path, never the target's.
#   - In the project, only when the link's fully resolved PHYSICAL target is inside the physical
#     project root (compared against PROOT plus a trailing slash, so a sibling `<project>-evil` is
#     outside). The project is a cloned tree that may be untrusted. A link that leaves it
#     (docs/x.md pointing at the config dir's CLAUDE.md, docs/home pointing at $HOME) would print a
#     row under an in-project name, send the refresh fix writing outside the project and walk a huge
#     tree, so it stays `not-scanned <path> symlink`. The same test applies to EVERY link the walk
#     meets, including one nested inside a directory that was itself reached through an in-project
#     link (enter_dir's bound argument); otherwise `docs/x -> ../shared` plus `shared/esc ->
#     <outside>` would reopen the hole #495 closed. A project link whose target is missing is also
#     `symlink`. A link listed through --files-from is never followed: `not-scanned <path> symlink`.
#     A symlinked PARENT directory counts the same: `<project>/.claude -> /elsewhere` is `not-scanned
#     <root> symlink` for every root under it, because testing only the last component would read
#     /elsewhere under an in-project name (#518). --files-from applies that test to each entry (a
#     relative entry from the current directory, judged against --project or the current directory).
# Project loops: a project link whose target is an ancestor of the link's own directory, the project
# root included (docs/loop -> ../docs, docs/up -> ..), is `symlink loop` at the link and nothing is
# re-read under it; so is a chain over 40 hops (docs/self -> self). The ancestors are seeded from the
# physical chain PROOT .. dirname(link), because the project walk uses find and never stacks them.
# A project link to a very large tree INSIDE the project costs a walk of it: accepted (read only,
# bounded by the stack, the seen list and the *.md glob). "Never walked" holds only for links that
# leave the project. A target reached both through a link and directly prints under the LINK's path:
# within one named place the link pass runs before the file pass, and prose places run in the order
# CLAUDE.md ... AGENTS.md, so `CLAUDE.md -> AGENTS.md` prints as CLAUDE.md.
# Cycles and repeats (the config dir, and followed project links): the walker keeps a stack of the
# physical paths of the directories it is inside. Re-entering one of them is `symlink loop` (also a link that points at
# itself or round a chain); reaching any other directory a second time, by two links or by a link to
# a real sibling, is skipped silently because it is not a defect. When one file or directory is
# reached two ways the first in sorted order (named places in script order, entries within a
# directory in LC_ALL=C order) wins and the printed path is that entry's own. A link whose target is
# missing is `dangling symlink`; an unreadable file or directory, linked or not, is `unreadable`; a
# target that is neither a regular file nor a directory is skipped. No `find -L` (it hides loops on
# stderr) and no `readlink -f` (absent on stock macOS). A link into a very large tree costs a walk of
# that tree: accepted, since the config dir is the user's own and the walk is bounded by the stack.
# Portable to bash 3.2 (stock macOS): no mapfile, no associative arrays.
set -uo pipefail
export LC_ALL=C   # byte semantics: the copied slug code needs it, and gawk rejects its octal range otherwise

usage() {
  echo "stale-rules: $1" >&2
  echo "usage: stale-rules.sh [--kit <dir>] [--project <dir>] [--rules <tsv>] [--files-from <file|->]" >&2
  exit 2
}

HERE=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd -P) || usage "cannot locate the script directory"
KIT=""; PROJECT=""; RULES="$HERE/retired-rules.tsv"; LIST=""; HAVE_LIST=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --kit)        [ "$#" -ge 2 ] || usage "--kit needs a value";        KIT="$2"; shift 2 ;;
    --project)    [ "$#" -ge 2 ] || usage "--project needs a value";    PROJECT="$2"; shift 2 ;;
    --rules)      [ "$#" -ge 2 ] || usage "--rules needs a value";      RULES="$2"; shift 2 ;;
    --files-from) [ "$#" -ge 2 ] || usage "--files-from needs a value"; LIST="$2"; HAVE_LIST=1; shift 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done

[ -f "$RULES" ] && [ -r "$RULES" ] || usage "cannot read the data file '$RULES'"
if [ -z "$KIT" ]; then KIT="$HERE/../../../../.."; fi
[ -d "$KIT/plugins" ] || usage "'$KIT' is not a forge-kit checkout (no plugins/); pass --kit"
if [ "$HAVE_LIST" -eq 1 ] && [ "$LIST" != "-" ]; then
  [ -f "$LIST" ] && [ -r "$LIST" ] || usage "cannot read the file list '$LIST'"
fi

# physdir <dir>: the physical absolute path of a directory, or nothing.
physdir() { (CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P); }

# parent_out <path> <project root>: success when a directory ABOVE <path> (below the root) is a symlink
# whose physical target is outside the root, or cannot be resolved. Testing only the last component
# misses `<project>/.claude -> /elsewhere`, which would read /elsewhere/agents/*.md under an
# in-project name (#518). A relative path is taken from the current directory; an absolute path
# outside the root is not checked (the caller named it). The config dir walk never calls this.
parent_out() {
  local path="$1" root="$2" rel base dir acc="" part rest link=0 pd
  case "$path" in
    /*) rel="${path#"$root"/}"; [ "$rel" != "$path" ] || return 1; base="$root" ;;
    *)  rel="$path"; base="." ;;
  esac
  dir=$(dirname -- "$rel"); [ "$dir" != "." ] || return 1
  rest="$dir"
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    acc="${acc:+$acc/}$part"
    [ -L "$base/$acc" ] && link=1
  done
  [ "$link" -eq 1 ] || return 1
  pd=$(physdir "$base/$dir"); [ -n "$pd" ] || return 0
  case "$pd" in "$root"|"$root"/*) return 1 ;; esac
  return 0
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/stale-rules.XXXXXX") || usage "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

# The kit's current version of every rule id: the highest `rule: <id> v<N>` under plugins/.
grep -rhoE 'rule: [a-z0-9-]+ v[0-9]+' "$KIT/plugins" 2>/dev/null \
  | awk '{ id = $2; v = substr($3, 2) + 0; if (!(id in m) || v > m[id]) m[id] = v }
         END { for (id in m) printf "%s=%d\n", id, m[id] }' > "$WORK/current"

# The matcher. Reads the data file and the current versions in BEGIN, buffers one file, and prints
# "<line>\t<id>" per hit. Both inputs are read with getline, so no regex passes through -v escape
# processing.
MATCH_AWK='
BEGIN {
  FS = "\t"; n = 0
  while ((getline row < RULES) > 0) {
    if (row ~ /^#/ || row ~ /^[ \t]*$/) continue
    k = split(row, c, "\t")
    if (k < 5) continue
    n++; rid[n] = c[1]; rre[n] = tolower(c[4])
  }
  close(RULES)
  while ((getline row < CURRENT) > 0) { p = index(row, "="); cur[substr(row, 1, p - 1)] = substr(row, p + 1) + 0 }
  close(CURRENT)
}
{ raw[NR] = $0 }
function emit(ln, id) { if (!((ln, id) in seen)) { seen[ln, id] = 1; printf "%d\t%s\n", ln, id } }
function quoted(a, b,   i) { for (i = a; i <= b; i++) if (index(tolower(raw[i]), "retired-rule-quote")) return 1; return 0 }
function norm(s) {
  gsub(/\t/, " ", s); gsub(/\r/, "", s)
  sub(/^ +/, "", s)
  while (s ~ /^>/) { sub(/^> */, "", s) }
  gsub(/  +/, " ", s); sub(/ +$/, "", s)
  return tolower(s)
}
function flush(   t, i, j, s, base, st, en, ls, le, piece, best, id) {
  if (pn == 0) return
  t = ""
  for (i = 1; i <= pn; i++) {
    piece = norm(raw[pl[i]])
    if (t != "" && piece != "") t = t " "
    off[i] = length(t) + 1
    t = t piece
  }
  for (j = 1; j <= n; j++) {
    s = t; base = 0
    while (s != "" && match(s, rre[j])) {
      st = base + RSTART; en = st + (RLENGTH > 0 ? RLENGTH : 1) - 1
      ls = 1; le = 1
      for (i = 1; i <= pn; i++) { if (off[i] <= st) ls = i; if (off[i] <= en) le = i }
      if (!quoted(pl[ls], pl[le]) && (!(rid[j] in best) || pl[ls] < best[rid[j]])) best[rid[j]] = pl[ls]
      base = base + RSTART + (RLENGTH > 0 ? RLENGTH : 1) - 1
      s = substr(t, base + 1)
    }
  }
  for (id in best) emit(best[id], id)   # one row per rule id per paragraph, at its earliest start
  pn = 0
}
END {
  pn = 0
  for (ln = 1; ln <= NR; ln++) {
    line = raw[ln]
    # Rule ids, one line at a time.
    l = tolower(line)
    while (match(l, /rule: [a-z0-9-]+ v[0-9]+/)) {
      tok = substr(l, RSTART + 6, RLENGTH - 6); l = substr(l, RSTART + RLENGTH)
      sp = index(tok, " v"); id = substr(tok, 1, sp - 1); v = substr(tok, sp + 2) + 0
      if ((id in cur) && v < cur[id] && !quoted(ln, ln)) emit(ln, id)
    }
    # Paragraph boundaries.
    if (line ~ /^[ \t]*$/) { flush(); continue }
    if (line ~ /^[ \t]*#+[ \t]/) { flush(); pl[++pn] = ln; flush(); continue }
    if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) flush()
    pl[++pn] = ln
  }
  flush()
}'

scanned=0; stale=0; unscanned=0
: > "$WORK/rows"; : > "$WORK/seen"

# show <abs path>: the printed form. Project paths are relative; HOME becomes ~.
show() {
  local p="$1"
  if [ -n "$PROOT" ] && [ "${p#"$PROOT"/}" != "$p" ]; then printf '%s' "${p#"$PROOT"/}"; return; fi
  if [ -n "${HOME:-}" ] && [ "${p#"$HOME"/}" != "$p" ]; then printf '~%s' "/${p#"$HOME"/}"; return; fi
  printf '%s' "$p"
}
not_scanned() { printf 'not-scanned\t%s\t%s\n' "$1" "$2" >> "$WORK/rows"; unscanned=$((unscanned + 1)); }

# scan_file <place> <path on disk> <printed path> [followed]: a fourth argument says the path is a
# physical one reached by following a config dir link, so the symlink refusal does not apply.
scan_file() {
  local place="$1" f="$2" disp="$3" followed="${4:-}"
  if grep -qxF -- "$f" "$WORK/seen"; then return 0; fi
  printf '%s\n' "$f" >> "$WORK/seen"
  if [ -z "$followed" ] && [ -L "$f" ]; then not_scanned "$disp" symlink; return 0; fi
  [ -f "$f" ] || return 0
  if [ ! -r "$f" ]; then not_scanned "$disp" unreadable; return 0; fi
  scanned=$((scanned + 1))
  awk -v RULES="$RULES" -v CURRENT="$WORK/current" "$MATCH_AWK" < "$f" > "$WORK/hits" \
    || { echo "stale-rules: the matcher failed on '$disp'" >&2; exit 2; }
  while IFS="$(printf '\t')" read -r ln id; do
    printf 'stale-rule\t%s\t%s\t%s\t%s\n' "$place" "$disp" "$ln" "$id" >> "$WORK/rows"
    stale=$((stale + 1))
  done < <(sort -t "$(printf '\t')" -k1,1n -k2,2 "$WORK/hits")
}

# project_link <place> <link> <glob>: one symlink in the PROJECT. Followed only when its physical
# target is inside PROOT; a loop (an ancestor target, PROOT included, or over 40 hops) is
# `symlink loop`; a missing or outside target is `symlink`. See the header. Defined before
# scan_tree, which calls it.
project_link() {
  local place="$1" l="$2" glob="$3" tp rc d chain="" name
  grep -qxF -- "$l" "$WORK/seen" && return 0
  printf '%s\n' "$l" >> "$WORK/seen"
  tp=$(resolve_link "$l"); rc=$?
  if [ "$rc" -eq 1 ]; then not_scanned "$(show "$l")" "symlink loop"; return 0; fi
  if [ "$rc" -ne 0 ] || [ -z "$tp" ]; then not_scanned "$(show "$l")" symlink; return 0; fi
  case "$tp" in
    "$PROOT"|"$PROOT"/*) ;;
    *) not_scanned "$(show "$l")" symlink; return 0 ;;
  esac
  if [ -d "$tp" ]; then
    d=$(dirname -- "$l")
    while :; do
      chain="$d$NL$chain"
      if [ "$d" = "$PROOT" ] || [ "$d" = "/" ] || [ "$d" = "." ]; then break; fi
      d=$(dirname -- "$d")
    done
    ANC="$chain"
    enter_dir "$place" "$(show "$l")" "$tp" "$glob" "$PROOT"
    ANC=""
  elif [ -f "$tp" ]; then
    name=$(basename -- "$l")
    # shellcheck disable=SC2254
    case "$name" in $glob) scan_file "$place" "$tp" "$(show "$l")" followed ;; esac
  fi
}

# scan_tree <place> <abs path> <glob>: a named file or directory in the PROJECT. A symlink met is
# followed only when its physical target is inside the project (project_link); the config dir goes
# through scan_followed.
scan_tree() {
  local place="$1" root="$2" glob="$3" p
  if parent_out "$root" "$PROOT"; then not_scanned "$(show "$root")" symlink; return 0; fi
  if [ -L "$root" ]; then
    project_link "$place" "$root" "$glob"
    return 0
  fi
  [ -e "$root" ] || return 0
  if [ -f "$root" ]; then scan_file "$place" "$root" "$(show "$root")"; return 0; fi
  [ -d "$root" ] || return 0
  # A directory find cannot list or enter hides whatever is in it, and find says so only on
  # stderr: report it as unreadable, or a hit inside it reads as a clean scan.
  find "$root" -type d 2>/dev/null | LC_ALL=C sort > "$WORK/dirs"
  while IFS= read -r p; do
    if [ -r "$p" ] && [ -x "$p" ]; then continue; fi
    grep -qxF -- "$p" "$WORK/seen" && continue
    printf '%s\n' "$p" >> "$WORK/seen"; not_scanned "$(show "$p")" unreadable
  done < "$WORK/dirs"
  # The link pass runs BEFORE the file pass, so a target reached both ways prints under the link.
  find "$root" -type l 2>/dev/null | LC_ALL=C sort > "$WORK/links"
  while IFS= read -r p; do project_link "$place" "$p" "$glob"; done < "$WORK/links"
  find "$root" -type f -name "$glob" 2>/dev/null | LC_ALL=C sort > "$WORK/files"
  while IFS= read -r p; do scan_file "$place" "$p" "$(show "$p")"; done < "$WORK/files"
}

# resolve_link <link>: print the physical path of what a link chain ends at. Returns 1 for a loop
# (over 40 hops), 2 for a missing target. A relative target is taken from the link's own directory.
resolve_link() {
  local p="$1" n=0 t d
  while [ -L "$p" ]; do
    n=$((n + 1)); [ "$n" -gt 40 ] && return 1
    t=$(readlink -- "$p") || return 2
    case "$t" in /*) p="$t" ;; *) p="$(dirname -- "$p")/$t" ;; esac
  done
  [ -e "$p" ] || return 2
  # A directory cd cannot enter (mode 000) has no physical path by cd; take its parent's instead.
  if [ -d "$p" ] && d=$(physdir "$p") && [ -n "$d" ]; then printf '%s' "$d"; return 0; fi
  d=$(physdir "$(dirname -- "$p")") || return 2
  printf '%s/%s' "$d" "$(basename -- "$p")"
}

ANC=""     # newline separated physical paths of the directories being walked (the ancestors)
DSEEN=""   # newline separated physical paths of every directory entered or refused so far
in_list() { case "$1" in *"$NL$2$NL"*) return 0 ;; esac; return 1; }
NL=$'\n'

# enter_dir <place> <printed path> <physical dir> <glob> [bound]: walk a directory reached by
# following links. A directory already on the stack is a loop; one seen before is skipped without a
# row. With a bound (the project root) EVERY link met inside must resolve under it, else
# `not-scanned <path> symlink`; without one (the config dir) outside targets are allowed.
enter_dir() {
  local place="$1" shown="$2" phys="$3" glob="$4" bound="${5:-}"
  if in_list "$NL$ANC" "$phys"; then not_scanned "$shown" "symlink loop"; return 0; fi
  if in_list "$NL$DSEEN" "$phys"; then return 0; fi
  DSEEN="$DSEEN$phys$NL"
  if [ ! -r "$phys" ] || [ ! -x "$phys" ]; then not_scanned "$shown" unreadable; return 0; fi
  local saved="$ANC" entries e name ep fp tp rc
  ANC="$ANC$phys$NL"
  entries=$(find "$phys" -mindepth 1 -maxdepth 1 2>/dev/null | LC_ALL=C sort)
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name="${e#"$phys"/}"; ep="$e"; fp="$shown/$name"
    if [ -L "$ep" ]; then
      tp=$(resolve_link "$ep"); rc=$?
      if [ "$rc" -eq 1 ]; then not_scanned "$fp" "symlink loop"; continue; fi
      if [ "$rc" -ne 0 ] || [ -z "$tp" ]; then
        if [ -n "$bound" ]; then not_scanned "$fp" symlink; else not_scanned "$fp" "dangling symlink"; fi
        continue
      fi
      if [ -n "$bound" ]; then
        case "$tp" in "$bound"|"$bound"/*) ;; *) not_scanned "$fp" symlink; continue ;; esac
      fi
    else
      tp="$ep"
    fi
    if [ -d "$tp" ]; then
      enter_dir "$place" "$fp" "$tp" "$glob" "$bound"
    elif [ -f "$tp" ]; then
      # shellcheck disable=SC2254
      case "$name" in $glob) scan_file "$place" "$tp" "$fp" followed ;; esac
    fi
  done <<< "$entries"
  ANC="$saved"
}

# scan_followed <place> <abs path> <glob>: scan_tree for the config dir, where links are followed.
scan_followed() {
  local place="$1" root="$2" glob="$3" tp rc
  ANC=""
  if [ -L "$root" ]; then
    tp=$(resolve_link "$root"); rc=$?
    if [ "$rc" -eq 1 ]; then not_scanned "$(show "$root")" "symlink loop"; return 0; fi
    if [ "$rc" -ne 0 ] || [ -z "$tp" ]; then not_scanned "$(show "$root")" "dangling symlink"; return 0; fi
  else
    [ -e "$root" ] || return 0
    tp=$(physdir "$root"); [ -n "$tp" ] || tp="$root"   # a mode 000 directory: enter_dir reports it
  fi
  if [ -d "$tp" ]; then enter_dir "$place" "$(show "$root")" "$tp" "$glob"
  elif [ -f "$tp" ]; then scan_file "$place" "$tp" "$(show "$root")" followed; fi
}

# Auto memory slug, COPIED from forge-kit-devops' context-budget.sh (`slug`, `memory_file`): no
# dependency is declared between forge-kit-adapt and forge-kit-devops, and declaring one to reuse
# two functions would make every adapt install pull devops. Keep the two in step by hand.
SLUG_MAX=200
slug() {
  printf '%s' "$1" | tr -d '\200-\277' | awk '{ gsub(/[\360-\364]/, "--"); printf "%s", $0 }' | tr -c 'A-Za-z0-9' '-'
}

PROOT=""
if [ "$HAVE_LIST" -eq 1 ]; then
  if [ "$LIST" = "-" ]; then cat > "$WORK/list"; else cat -- "$LIST" > "$WORK/list"; fi
  LROOT=$(physdir "${PROJECT:-.}")
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -n "$LROOT" ] && parent_out "$p" "$LROOT"; then not_scanned "$p" symlink; continue; fi
    scan_file prose "$p" "$p"
  done < "$WORK/list"
else
  [ -n "$PROJECT" ] || PROJECT=.
  [ -d "$PROJECT" ] || usage "no such project directory '$PROJECT'"
  PROOT=$(physdir "$PROJECT"); [ -n "$PROOT" ] || usage "cannot resolve '$PROJECT'"
  CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  CFG="${CFG%/}"

  for d in agents commands skills; do scan_tree component "$PROOT/.claude/$d" '*.md'; done
  for d in agents commands skills; do scan_followed component "$CFG/$d" '*.md'; done
  for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md CONTRIBUTING.md; do scan_tree prose "$PROOT/$f" '*.md'; done
  scan_tree prose "$PROOT/docs" '*.md'
  scan_followed prose "$CFG/CLAUDE.md" '*.md'
  scan_tree memory "$PROOT/.claude/memory" '*.md'
  scan_tree memory "$PROOT/.claude/handoffs" '*.md'

  mroot=$(unset GIT_DIR GIT_WORK_TREE; git -C "$PROOT" rev-parse --show-toplevel 2>/dev/null) && mroot=$(physdir "$mroot") || mroot=""
  [ -n "$mroot" ] || mroot="$PROOT"
  s=$(slug "$mroot"); [ -n "$s" ] || usage "cannot derive the project slug for '$mroot'"
  if [ "${#s}" -le "$SLUG_MAX" ]; then
    scan_followed memory "$CFG/projects/$s" '*.md'
  else
    not_scanned "$(show "$CFG/projects")/<slug>" "project slug over 200 characters"
  fi
fi

cat "$WORK/rows"
printf 'summary\t%s\t%s\t%s\n' "$scanned" "$stale" "$unscanned"
if [ "$stale" -gt 0 ]; then exit 1; fi
if [ "$unscanned" -gt 0 ]; then exit 3; fi
exit 0
