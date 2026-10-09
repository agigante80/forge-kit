#!/usr/bin/env bash
# context-budget-version: 3
# context-budget.sh: how many characters a project's next session loads before the first prompt (#297).
#
# Every @-import in CLAUDE.md is paid at the start of every session, every inheriting subagent and
# every compaction. One downstream repo reached 258 KB that way and nothing measured it. Claude
# Code's own notice is interactive, per session and has no exit code; this is the number a script
# or a CI job can read.
#
# Usage: context-budget.sh [<repo-dir>]            measure one repository (default: .)
#        context-budget.sh --sweep <root>...       one row per repository found under each root
#
# THE LOAD SET is exactly: <repo-dir>/CLAUDE.md, its transitive @-imports, and the LOADED PORTION
# of the auto-memory MEMORY.md (the first 200 lines or 25,000 bytes, whichever is less, cut at a
# character boundary). Ancestor CLAUDE.md files, .claude/CLAUDE.md, CLAUDE.local.md,
# .claude/rules/*.md and lazily loaded subdirectory CLAUDE.md files are deliberately not counted.
#
# UNIT: characters (code points), counted as the bytes outside 0x80-0xBF under LC_ALL=C, so the
# figure is the same in every locale and malformed input is deterministic (the leak guard's
# char_len, #403 and #416). Block HTML comments are counted RAW, though Claude Code strips them:
# the figure is an upper bound there, the same choice as the CLI's own file-size warning.
#
# LEVELS: under 40,000 ok; from 40,000 warn (a stderr line, exit 0); at or over the fail level
# FAIL (exit 1). The fail level is 80,000 unless one valid marker in the root CLAUDE.md raises it:
#   <!-- context-budget: <N> reason: <text> -->      N a whole number above 80,000, text non-empty
# A marker breaking any rule is REFUSED: the rule goes to stderr, the default levels apply, and the
# exit code is 2 (a configuration error, distinct from a breach). Exit 2 is also every usage error.
#
# --sweep walks each named root (no symlink following; .git and node_modules skipped) for
# directories holding a CLAUDE.md; such a directory is one row and its subtree is not searched.
# Rows run in descending total, path ascending on a tie. A sweep exits 0 whatever the levels,
# because a cross-project report cannot block anything, and 2 only on a usage error.
#
# THE AUTO-MEMORY DIRECTORY derives from ONE input in both modes: the git root of the directory
# holding CLAUDE.md, else that directory (pwd -P). Every character outside [A-Za-z0-9] becomes
# '-' per UTF-16 unit as Claude Code's JavaScript does (a four-byte character gives two dashes),
# case kept, nothing collapsed, under $CLAUDE_CONFIG_DIR or else $HOME/.claude. A slug over 200
# characters is cut and hash-suffixed by the CLI; that suffix is not reproduced, so such a
# directory's MEMORY.md is reported as not read rather than guessed.
#
# NO FILE TEXT IS EVER PRINTED other than a section heading on a single-repository run: paths,
# sizes and levels only. The marker's reason is never echoed. Tokens and names never reach a shell.
#
# Portable to bash 3.2 and POSIX awk: no associative arrays, no mapfile, no readlink -f.
set -uo pipefail
export LC_ALL=C

WARN_AT=40000
FAIL_AT=80000
MAX_HOPS=4
SECTION_FLAG=8000
MEM_LINES=200
MEM_BYTES=25000
SLUG_MAX=200

usage() {
  echo "context-budget: $1" >&2
  echo "usage: context-budget.sh [<repo-dir>] | context-budget.sh --sweep <root>..." >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/context-budget.XXXXXX") || { echo "context-budget: cannot create a temporary directory" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# chars <file>: characters in a file, 0 when it cannot be read.
chars() { [ -r "$1" ] || { echo 0; return; }; tr -d '\200-\277' < "$1" 2>/dev/null | wc -c | tr -d ' '; }

# physdir <dir>: the physical absolute path of a directory, or nothing.
physdir() { (CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P); }   # CDPATH= : a cd found through CDPATH prints its target (#297 review r2)

# resolve_file <path>: the physical path of a regular file, following at most 8 symlinks, or nothing
# for a missing target, a dangling link, a loop or a non-regular file.
resolve_file() {
  local p="$1" i=0 d b t
  while [ -L "$p" ]; do
    i=$((i + 1)); [ "$i" -gt 8 ] && return 1
    t=$(readlink -- "$p" 2>/dev/null) || return 1
    case "$t" in /*) p="$t" ;; *) p="$(dirname -- "$p")/$t" ;; esac
  done
  [ -f "$p" ] || return 1
  d=$(physdir "$(dirname -- "$p")") || return 1
  [ -n "$d" ] || return 1
  b=$(basename -- "$p")
  printf '%s/%s\n' "$d" "$b"
}

# slug <abs-path>: Claude Code's project slug, one '-' per UTF-16 unit outside [A-Za-z0-9].
slug() {
  printf '%s' "$1" | tr -d '\200-\277' | awk '{ gsub(/[\360-\364]/, "--"); printf "%s", $0 }' | tr -c 'A-Za-z0-9' '-'
}

# memory_file <claude-md-dir>: the auto-memory MEMORY.md path for it (it may not exist), or nothing
# when the slug is over the length the CLI hashes.
memory_file() {
  local d="$1" root s
  root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) && root=$(physdir "$root") || root=""
  [ -n "$root" ] || root=$(physdir "$d")
  s=$(slug "$root")
  [ "${#s}" -le "$SLUG_MAX" ] || return 1
  printf '%s/projects/%s/memory/MEMORY.md\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$s"
}

# memory_loaded <file>: characters in the loaded portion. A byte cut that lands inside a character
# drops that character: its lead byte is the one byte it contributed to the count.
memory_loaded() {
  local f="$1" n next
  head -n "$MEM_LINES" < "$f" > "$WORK/mem" 2>/dev/null || { echo 0; return; }
  n=$(head -c "$MEM_BYTES" < "$WORK/mem" | tr -d '\200-\277' | wc -c | tr -d ' ')
  next=$(tail -c +"$((MEM_BYTES + 1))" < "$WORK/mem" | head -c 1 | od -An -tu1 | tr -d ' ')
  if [ -n "$next" ] && [ "$next" -ge 128 ] && [ "$next" -le 191 ]; then n=$((n - 1)); fi
  echo "$n"
}

# The shared line scanner. Fenced blocks are skipped; on what is left, inline code spans and then
# HTML comments (inline or spanning lines) are removed. MODE=tokens prints each @-import token,
# backslash-space unescaped; MODE=markers prints one line per marker-shaped comment: "ok <N>" or
# "bad <rule>". Neither mode prints anything else from the file.
SCAN_AWK='
# Both scanners jump between the characters that matter with index() rather than walking every
# character: some awks (busybox) make a per-character walk quadratic in the line length.
function strip_spans(s,   out, p, run, rest, q, k, cl, off) {
  out = ""
  while ((p = index(s, "`")) > 0) {
    out = out substr(s, 1, p - 1); s = substr(s, p)
    run = 0; while (substr(s, run + 1, 1) == "`") run++
    rest = substr(s, run + 1); off = run; cl = 0
    while ((q = index(rest, "`")) > 0) {
      k = 0; while (substr(rest, q + k, 1) == "`") k++
      if (k == run) { cl = off + q; break }
      rest = substr(rest, q + k); off += q + k - 1
    }
    if (cl) { out = out " "; s = substr(s, cl + run) } else { out = out substr(s, 1, run); s = substr(s, run + 1) }
  }
  return out s
}
function fence_of(s,   t) {
  t = s; sub(/^ ? ? ?/, "", t)
  if (t ~ /^```/) { match(t, /^`+/); return substr(t, 1, RLENGTH) }
  if (t ~ /^~~~/) { match(t, /^~+/); return substr(t, 1, RLENGTH) }
  return ""
}
{
  line = $0; sub(/\r$/, "", line)
  if (fence != "") {
    f = fence_of(line)
    if (f != "" && substr(f, 1, 1) == substr(fence, 1, 1) && length(f) >= length(fence)) {
      t = line; sub(/^ ? ? ?[`~]+/, "", t); if (t ~ /^[ \t]*$/) fence = ""
    }
    next
  }
  f = fence_of(line); if (f != "") { fence = f; next }
  rest = strip_spans(line); vis = ""
  while (rest != "") {
    if (incomment) {
      p = index(rest, "-->"); if (!p) { if (MODE == "markers") body = body " " rest; rest = ""; break }
      if (MODE == "markers") body = body " " substr(rest, 1, p - 1)
      rest = substr(rest, p + 3); incomment = 0
      if (MODE == "markers") marker(body)
      continue
    }
    p = index(rest, "<!--"); if (!p) { vis = vis rest; rest = ""; break }
    vis = vis substr(rest, 1, p - 1) " "
    rest = substr(rest, p + 4); incomment = 1; body = ""
    q = index(rest, "-->")
    if (q) { body = substr(rest, 1, q - 1); rest = substr(rest, q + 3); incomment = 0; if (MODE == "markers") marker(body) }
    else { body = rest; rest = "" }
  }
  if (MODE == "tokens") tokens(vis)
}
function marker(b,   t, n) {
  t = b; sub(/^[ \t]+/, "", t)
  if (t !~ /^context-budget:/) return
  sub(/^context-budget:[ \t]*/, "", t)
  if (t !~ /^[0-9]/) { print "bad the level is missing or not a whole number"; return }
  match(t, /^[0-9]+/); n = substr(t, 1, RLENGTH); t = substr(t, RLENGTH + 1)
  if (t !~ /^[ \t]+reason:/) { print "bad the reason is missing"; return }
  sub(/^[ \t]+reason:/, "", t); gsub(/[ \t]/, "", t)
  if (t == "") { print "bad the reason is empty"; return }
  sub(/^0+/, "", n)
  if (length(n) < 5 || (length(n) == 5 && n + 0 <= 80000)) { print "bad the level must be above 80000"; return }
  if (length(n) > 15) { print "bad the level is too large"; return }
  print "ok " n
}
function tokens(s,   p, prev, tok, d, i, n) {
  prev = " "
  while ((p = index(s, "@")) > 0) {
    if (p > 1) prev = substr(s, p - 1, 1)
    s = substr(s, p + 1)
    if (prev != " " && prev != "\t") { prev = "@"; continue }
    tok = ""; n = length(s); i = 1
    while (i <= n) {
      d = substr(s, i, 1)
      if (d == "\\" && substr(s, i + 1, 1) == " ") { tok = tok " "; i += 2; continue }
      if (d == " " || d == "\t") break
      tok = tok d; i++
    }
    s = substr(s, i); prev = " "
    if (tok != "" && tok !~ /^["\047~\/]/) print tok
  }
}
'

# Sections: a "## " heading to the next "# " or "## " heading, fences skipped, the size counted on
# the continuation-stripped text so it is characters. Prints "<line>\t<size>" for each section over
# the flag; never anything from the file.
SECTION_AWK='
function fence_of(s,   t) {
  t = s; sub(/^ ? ? ?/, "", t)
  if (t ~ /^```/) { match(t, /^`+/); return substr(t, 1, RLENGTH) }
  if (t ~ /^~~~/) { match(t, /^~+/); return substr(t, 1, RLENGTH) }
  return ""
}
function close_section() { if (start && size > FLAG) printf "%d\t%d\n", start, size; start = 0; size = 0 }
{
  line = $0; f = fence_of(line)
  if (fence != "") {
    if (f != "" && substr(f, 1, 1) == substr(fence, 1, 1) && length(f) >= length(fence)) fence = ""
  } else if (f != "") {
    fence = f
  } else if (line ~ /^##?[ \t]/ || line ~ /^##?$/) {
    close_section()
    if (line ~ /^##([ \t]|$)/) start = NR
  }
  if (start) size += length(line) + 1
}
END { if (start && !nl) size -= 1; close_section() }
'

# measure <claude-md-dir> <mode>: writes the result fields for one repository into $WORK/r.
# mode is "single" (prints the report) or "sweep" (prints nothing; the caller formats a row).
measure() {
  local dir="$1" mode="$2" root cm total imports=0 level failat="$FAIL_AT" marker_rc=0
  local q next hop file rel n mem memf mem_whole="" markers bad
  root=$(physdir "$dir")
  cm="$root/CLAUDE.md"
  : > "$WORK/seen"; : > "$WORK/items"; : > "$WORK/notes"
  printf '%s\n' "$cm" >> "$WORK/seen"
  n=$(chars "$cm"); total=$n
  printf '%s\tCLAUDE.md\t0\n' "$n" >> "$WORK/items"

  # Breadth-first walk: hop 0 is CLAUDE.md, a token found in a hop-h file is at hop h+1, and a
  # file at hop MAX_HOPS is counted but not scanned. Each file is counted once.
  printf '0\t%s\n' "$cm" > "$WORK/queue"
  while [ -s "$WORK/queue" ]; do
    IFS="$(printf '\t')" read -r hop file < "$WORK/queue"
    sed '1d' "$WORK/queue" > "$WORK/queue.n"; mv "$WORK/queue.n" "$WORK/queue"
    [ "$hop" -lt "$MAX_HOPS" ] || continue
    [ -r "$file" ] || continue   # counted as 0 by chars(); an unreadable file has no tokens to read
    awk -v MODE=tokens "$SCAN_AWK" < "$file" > "$WORK/tokens" || scan_failed
    while IFS= read -r tok; do
      next=$(resolve_file "$(dirname -- "$file")/$tok") || continue
      case "$next" in "$root"/*) ;; *) continue ;; esac
      grep -qxF -- "$next" "$WORK/seen" && continue
      printf '%s\n' "$next" >> "$WORK/seen"
      n=$(chars "$next"); total=$((total + n)); imports=$((imports + 1))
      rel=${next#"$root"/}
      printf '%s\t%s\t%s\n' "$n" "$rel" "$((hop + 1))" >> "$WORK/items"
      printf '%s\t%s\n' "$((hop + 1))" "$next" >> "$WORK/queue"
    done < "$WORK/tokens"
  done

  mem=0
  if memf=$(memory_file "$root"); then
    if [ -f "$memf" ]; then
      mem=$(memory_loaded "$memf"); mem_whole=$(chars "$memf")
    fi
  else
    memf=""; printf 'MEMORY.md not read: the project slug is over %s characters\n' "$SLUG_MAX" >> "$WORK/notes"
  fi
  total=$((total + mem))

  markers=$(awk -v MODE=markers "$SCAN_AWK" < "$cm") || scan_failed
  bad=""
  if [ "$(printf '%s\n' "$markers" | grep -c '^ok \|^bad ')" -gt 1 ]; then
    bad="more than one context-budget marker"
  elif grep -q '^bad ' <<< "$markers"; then
    bad=$(printf '%s\n' "$markers" | sed -n 's/^bad //p' | head -1)
  elif grep -q '^ok ' <<< "$markers"; then
    failat=$(printf '%s\n' "$markers" | sed -n 's/^ok //p' | head -1)
  fi
  [ -n "$bad" ] && marker_rc=2

  if [ "$total" -ge "$failat" ]; then level=FAIL
  elif [ "$total" -ge "$WARN_AT" ]; then level=warn
  else level=ok; fi

  awk -v FLAG="$SECTION_FLAG" -v nl="$(grep -qx 10 <<< "$(tail -c 1 "$cm" 2>/dev/null | od -An -tu1 | tr -d ' ')" && echo 1 || echo 0)" \
    "$SECTION_AWK" < <(tr -d '\200-\277' < "$cm") > "$WORK/sections" || scan_failed

  {
    printf 'root=%s\n' "$root"; printf 'total=%s\n' "$total"; printf 'imports=%s\n' "$imports"
    printf 'level=%s\n' "$level"; printf 'failat=%s\n' "$failat"; printf 'bad=%s\n' "$bad"
    printf 'mem=%s\n' "$mem"; printf 'memf=%s\n' "$memf"; printf 'memwhole=%s\n' "$mem_whole"
    printf 'markerrc=%s\n' "$marker_rc"
  } > "$WORK/r"
}

# A scanner that fails must not read as "no imports": that is a silently low total (#297 review).
scan_failed() { echo "context-budget: the scanner failed; no figure is reported" >&2; exit 2; }

field() { sed -n "s/^$1=//p" "$WORK/r" | head -1; }

if [ "${1-}" = "--sweep" ]; then
  shift
  [ $# -gt 0 ] || usage "--sweep needs at least one root"
  : > "$WORK/found"
  for r in "$@"; do
    [ -d "$r" ] || usage "'$r' is not a directory"
    r=$(physdir "$r")   # find does not follow a symlinked starting point (#297 review r1)
    find "$r" \( -name .git -o -name node_modules \) -prune -o -type f -name CLAUDE.md -print 2>/dev/null \
      | while IFS= read -r p; do physdir "$(dirname -- "$p")"; done >> "$WORK/found"
  done
  # A directory holding a CLAUDE.md is one row; anything beneath it is not a row of its own.
  sort -u "$WORK/found" | awk '
    { for (i = 1; i <= k; i++) if (index($0, kept[i] "/") == 1) next; kept[++k] = $0; print }
  ' > "$WORK/dirs"
  : > "$WORK/rows"
  while IFS= read -r d; do
    measure "$d" sweep
    note=""
    [ -n "$(field bad)" ] && note="  marker refused"
    [ "$(field failat)" != "$FAIL_AT" ] && note="  fail level raised to $(field failat) by a context-budget marker"
    printf '%s\t%s\t%s\t%s\n' "$(field total)" "$(field level)" "$(field root)" "$note" >> "$WORK/rows"
    while IFS="$(printf '\t')" read -r ln sz; do
      printf '%s\t~\t%s\t  move candidate: line %s, %s chars\n' "$(field total)" "$(field root)" "$ln" "$sz" >> "$WORK/rows"
    done < "$WORK/sections"
  done < "$WORK/dirs"
  # Descending total, path ascending, each row before its own move candidates (its level sorts
  # before the "~" those carry, since every level token is a letter).
  sort -s -t "$(printf '\t')" -k1,1nr -k3,3 -k2,2 "$WORK/rows" | awk -F '\t' '
    $2 == "~" { print $4; next }
    { printf "%s\t%s\t%s%s\n", $1, $2, $3, $4 }
  '
  exit 0
fi

[ $# -le 1 ] || usage "takes one <repo-dir>, or --sweep <root>..."
dir="${1:-.}"
case "$dir" in -*) usage "unknown option '$dir'" ;; esac
[ -d "$dir" ] || usage "'$dir' is not a directory"
[ -f "$dir/CLAUDE.md" ] || usage "no CLAUDE.md in '$dir'"

measure "$dir" single
root=$(field root)
echo "context-budget: $root"
while IFS="$(printf '\t')" read -r n label hop; do
  if [ "$hop" = 0 ]; then printf '  %s\t%s\n' "$n" "$label"; else printf '  %s\t%s (hop %s)\n' "$n" "$label" "$hop"; fi
done < "$WORK/items"
if [ -n "$(field memf)" ] && [ -n "$(field memwhole)" ]; then
  printf '  %s\tMEMORY.md, loaded portion (%s)\n' "$(field mem)" "$(field memf)"
else
  printf '  0\tMEMORY.md, none\n'
fi
echo "total: $(field total)"
echo "imports: $(field imports)"
echo "level: $(field level)"
if [ "$(field failat)" != "$FAIL_AT" ]; then
  echo "fail level: $(field failat) (fail level raised by a context-budget marker)"
else
  echo "fail level: $FAIL_AT"
fi
[ -n "$(field memwhole)" ] && echo "MEMORY.md whole file: $(field memwhole) (not counted)"
cat "$WORK/notes"
while IFS="$(printf '\t')" read -r ln sz; do
  heading=$(sed -n "${ln}p" "$root/CLAUDE.md" | sed 's/^##[ \t]*//; s/\r$//')
  printf 'move candidate: line %s, %s chars, %s\n' "$ln" "$sz" "$heading"
done < "$WORK/sections"

[ -n "$(field bad)" ] && echo "context-budget: marker refused: $(field bad); the default levels apply" >&2
case "$(field level)" in
  warn) echo "WARN context-budget: $(field total) characters is at or over $WARN_AT" >&2 ;;
  FAIL) echo "FAIL context-budget: $(field total) characters is at or over the fail level $(field failat)" >&2 ;;
esac
[ "$(field markerrc)" = 2 ] && exit 2
[ "$(field level)" = FAIL ] && exit 1
exit 0
