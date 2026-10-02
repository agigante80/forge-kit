#!/usr/bin/env bash
# check-pipe-grep-q.sh: no shipped, repository or test script pipes into `grep -q` (#413).
#
# THE DEFECT. Under `set -o pipefail`, `producer | grep -q PATTERN` can answer "no match" when the
# text DOES match. `grep -q` exits at its first match and closes the pipe; a producer still writing
# gets SIGPIPE and exits 141, and pipefail makes 141 the pipeline's status, which `if`, `&&` and
# `||` read as false. The race widens with the text's size, an early match and a busy machine; past
# the pipe buffer (64 KiB on Linux) it fires unloaded. It let four shipped roadmap scripts skip
# their MALFORMED refusal, and it flaked test suites. The fix is one form: `grep -q PATTERN <<< "$x"`
# (or `<<< "$(producer)"`), or `[[ ]]` / `case` for a plain substring test. This guard keeps a new
# pipe into `grep -q` out.
#
# WHICH FILES, exactly: tracked `scripts/*.sh` directly in scripts/ (test suites INCLUDED, since
# that is where it flakes), tracked `plugins/*/skills/*/assets/*.sh` directly in an assets/ folder,
# and tracked `.githooks/*`, enumerated through guard-lib.sh so the local verdict is CI's. An
# untracked file never counts.
#
# THE RULE, one extended regex, no exemption marker. A line is flagged exactly when `grep -E`
# matches it with:
#
#   ^[[:space:]]*([^#[:space:]](.*[^|])?)?\|[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*q|--quiet)
#
# In words: a line whose first non-blank character is not `#`, holding a `|` that is not part of
# `||`, followed by `grep`, any option clusters, and then a cluster that contains `q` or is
# `--quiet`. There is no allow mechanism: quoted text that spells the construct (a mutant's
# replacement text, a fixture) is rewritten, for instance with the bar held in a variable.
#
# ACCEPTED LIMITS, read as text by the rule above: a pipe split over a backslash-continued line with
# `grep` on the next line is not seen; a `grep` reached through a variable or a function is not
# seen; a long option such as `--fixed-strings` placed before `-q` hides the `-q`; and a trailing
# `# comment` that spells the construct IS flagged (only a line that starts with `#` is skipped).
#
# Usage: check-pipe-grep-q.sh [--root DIR]   (default: the git toplevel of this script's directory)
# Exit: 0 clean, 1 one `path:line: text` row per offending line on stdout, 2 the input is unusable.
set -uo pipefail
export LC_ALL=C

RULE='^[[:space:]]*([^#[:space:]](.*[^|])?)?\|[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*q|--quiet)'

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "check-pipe-grep-q: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^# Exit:/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    *) echo "check-pipe-grep-q: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-pipe-grep-q: not a git checkout and no --root given" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "check-pipe-grep-q: '$ROOT' is not a directory" >&2; exit 2; }
PROOT="$(CDPATH= cd -- "$ROOT" && pwd -P)" || { echo "check-pipe-grep-q: cannot resolve '$ROOT'" >&2; exit 2; }

. "$(dirname "$0")/guard-lib.sh"
guard_in_checkout "$PROOT" || { echo "check-pipe-grep-q: '$PROOT' is not inside a git checkout" >&2; exit 2; }

files=()
while IFS= read -r -d '' f; do
  rel=${f#"$PROOT"/}
  case "$rel" in
    scripts/*/*) continue ;;
    scripts/*.sh|.githooks/*) case "$rel" in .githooks/*/*) continue ;; esac ;;
    plugins/*/skills/*/assets/*.sh) case "$rel" in plugins/*/skills/*/assets/*/*) continue ;; esac ;;
    *) continue ;;
  esac
  files+=("$rel")
done < <(guard_tracked_files "$PROOT")

[ "${#files[@]}" -gt 0 ] || exit 0
found=0
for rel in "${files[@]}"; do
  hits=$(grep -naE -- "$RULE" "$PROOT/$rel"); rc=$?
  [ "$rc" -le 1 ] || { echo "check-pipe-grep-q: cannot read '$rel'" >&2; exit 2; }
  [ "$rc" = 0 ] || continue
  found=1
  while IFS= read -r row; do
    printf '%s:%s: %s\n' "$rel" "${row%%:*}" "${row#*:}"
  done <<< "$hits"
done
[ "$found" = 0 ] && exit 0
echo "check-pipe-grep-q: a pipe into grep -q above; write grep -q PATTERN <<< \"\$x\" (or <<< \"\$(producer)\")" >&2
exit 1
