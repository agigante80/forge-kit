#!/usr/bin/env bash
# check-cdpath-cd.sh: no shipped or repository shell script enters a directory with a bare `cd` (#379).
#
# THE DEFECT. A bare relative `cd` consults an exported CDPATH: it can enter a same-named directory
# elsewhere, and it echoes the directory it entered, which corrupts a `$(cd ... && pwd)` capture or
# a stdout rows contract. #377 swept every site to `CDPATH= cd --`; this guard keeps a new bare one
# out, and scripts/test-cdpath.sh proves the swept sites behave.
#
# WHICH FILES, exactly: tracked `plugins/*/skills/*/assets/*.sh`, tracked `scripts/*.sh` directly in
# scripts/ except `scripts/test-*.sh`, and tracked `.githooks/*`, enumerated through guard-lib.sh so
# the local verdict is CI's. Test harnesses are out of scope: they run under CI's own environment
# and are not shipped. An untracked file never counts.
#
# COMMAND POSITION, as text. A line whose first non-blank character is `#` is never read. On any
# other line, a `cd` or `pushd` word is a command when it starts the line (after whitespace) or
# follows, with only whitespace between, one of `;`, `&` (so `&&` too), `|` (so `||` too), `(`
# (so `$(` too), `)` (a case arm), `{`, `!`, `CDPATH=`, or one of the words `then`, `do`, `else`,
# `if`, `elif`, `while`, `until`, `builtin`, `command`. A `cd` directly after a quote character
# (`"cd"`, `'cd'`) is never a command, so the awk string `w == "cd"` in check-contributor-docs.sh
# is not counted.
#
# THE ACCEPT RULE, one text rule, no exemption marker. A command passes only when `CDPATH=` (empty)
# is written immediately before it, or its first argument, after one optional `--`, is a literal
# (bare, or the first characters inside its quotes) beginning `/`, `./` or `../`, or is exactly
# `.`, `..` or `-` (none consults CDPATH), or it has no argument. A non-literal argument (`"$x"`,
# `$(...)`) always needs `CDPATH=`, even when its value is absolute at run time: the guard never
# guesses a value.
#
# ACCEPTED LIMITS, read as text by the rules above: a `cd` on a backslash-continued line (the
# continuation is read as its own line), inside a heredoc body (it can be flagged, and is then
# fixed, not exempted), inside a backtick substitution, or reached through `eval` or an alias.
#
# Usage: check-cdpath-cd.sh [--root DIR]   (default: the git toplevel of this script's directory)
# Exit: 0 clean, 1 one `path:line: text` row per offending line on stdout, 2 the input is unusable.
set -uo pipefail
export LC_ALL=C

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "check-cdpath-cd: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^# Exit:/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    *) echo "check-cdpath-cd: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-cdpath-cd: not a git checkout and no --root given" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "check-cdpath-cd: '$ROOT' is not a directory" >&2; exit 2; }
PROOT="$(CDPATH= cd -- "$ROOT" && pwd -P)" || { echo "check-cdpath-cd: cannot resolve '$ROOT'" >&2; exit 2; }

. "$(dirname "$0")/guard-lib.sh"
guard_in_checkout "$PROOT" || { echo "check-cdpath-cd: '$PROOT' is not inside a git checkout" >&2; exit 2; }

files=()
while IFS= read -r -d '' f; do
  rel=${f#"$PROOT"/}
  case "$rel" in
    scripts/test-*) continue ;;
    scripts/*/*) continue ;;
    scripts/*.sh|.githooks/*) ;;
    plugins/*/skills/*/assets/*.sh) case "$rel" in plugins/*/skills/*/assets/*/*) continue ;; esac ;;
    *) continue ;;
  esac
  files+=("$rel")
done < <(guard_tracked_files "$PROOT")

[ "${#files[@]}" -gt 0 ] || exit 0
out=$(CDPATH= cd -- "$PROOT" && SQ="'" awk '
  BEGIN { QC = "[\"" ENVIRON["SQ"] "]"; ENDARG = "^(\\.|\\.\\.|-)([ \t;&|)\"" ENVIRON["SQ"] "]|$)" }
  function cmdpos(pre,   t, w) {
    t = pre; sub(/[ \t]+$/, "", t)
    if (t == "") return 1
    if (t ~ /(CDPATH=|[;&|({)!])$/) return 1
    w = t; sub(/^.*[^A-Za-z]/, "", w)
    if (length(w) < length(t) && substr(t, length(t) - length(w), 1) ~ QC) return 0
    return (w ~ /^(then|do|else|if|elif|while|until|builtin|command)$/)
  }
  function accepted(pre, rest,   t, a, q) {
    t = pre; sub(/[ \t]+$/, "", t)
    if (t ~ /CDPATH=$/) return 1
    a = rest; sub(/^[ \t]+/, "", a)
    if (a ~ /^--([ \t]|$)/) { a = substr(a, 3); sub(/^[ \t]+/, "", a) }
    if (a == "" || a ~ /^[;&|)]/) return 1
    q = substr(a, 1, 1); if (q ~ QC) a = substr(a, 2)
    if (a ~ /^(\/|\.\/|\.\.\/)/) return 1
    if (a ~ ENDARG) return 1
    return 0
  }
  FNR == 1 { file = FILENAME }
  /^[ \t]*#/ { next }
  {
    # Padded with a space on each side so the word boundary and the end are plain bracket classes.
    # match() is given a variable, never a substr() result: the BWK awk CI runs returned RSTART -1
    # for a temporary string here, and read `CDPATH` as a `cd` at column 1.
    line = " " $0 " "; off = 0; bad = 0
    while ((seg = substr(line, off + 1)) != "" && match(seg, /[^A-Za-z0-9_.\/-](cd|pushd)[ \t;&|)]/)) {
      s = off + RSTART + 1
      wl = (substr(line, s, 2) == "cd") ? 2 : 5
      lhs = substr(line, 2, s - 2); rhs = substr(line, s + wl)
      if (substr(lhs, length(lhs), 1) !~ QC && cmdpos(lhs) && !accepted(lhs, rhs)) bad = 1
      off = s + wl - 1
    }
    if (bad) printf "%s:%d: %s\n", file, FNR, $0
  }' "${files[@]}")
[ -z "$out" ] && exit 0
printf '%s\n' "$out"
echo "check-cdpath-cd: a bare cd or pushd above; write it CDPATH= cd -- (or give a literal /, ./ or ../ path)" >&2
exit 1
