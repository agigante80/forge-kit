#!/usr/bin/env bash
# check-test-suites-wired.sh: every tracked scripts/test-* suite must have a step in validate.yml (#348).
#
# THE DEFECT. The repo's stated policy is that every `scripts/test-*` suite runs in CI, and nothing
# checked it. #344 found `test-reassess-phases.sh` with no step at all. The local pre-push hook cannot
# catch it either: it runs suites only through `update-suite-counts.py --check --changed`, whose
# `printed_total()` sums passed plus failed and ignores the exit code. This guard is CI-only.
#
# WHICH FILES. A suite is a TRACKED file directly inside <root>/scripts/ whose basename matches
# `test-*.sh` or `test-*.py`. Inside a checkout the set comes from guard-lib.sh (what CI sees);
# outside one it is a plain `find -maxdepth 1`, the sibling guards' fallback. Nested files
# (`scripts/fixtures/test-x.sh`), untracked files and other extensions never count.
#
# THE ROOT IS RESOLVED ONCE, to its physical path (`pwd -P`), before either enumeration path.
# guard_tracked_files emits physical absolute paths, so comparing them with a relative or
# symlinked root as given would match nothing. Using the one resolved value for both paths and for
# the validate.yml location means the two paths cannot disagree.
#
# WHAT COUNTS AS A STEP: an exact line rule, not a regex and not `grep -F -w` (which matches the
# line `run: bash scripts/test-a.sh.bak` for `test-a.sh`). For each line of validate.yml: strip a
# trailing CR, leading whitespace, one optional `- ` and the whitespace after it; the remainder must
# START with the literal `run: bash scripts/` or `run: python3 scripts/` (so a `#` comment is never
# a step); the TOKEN is what follows up to the first whitespace character (the `[[:space:]]`
# cut). The suite is wired when the token EQUALS its basename by string equality and the
# interpreter matches the extension (`bash` wires `.sh`, `python3` wires `.py`). Text after the
# token is ignored. Nothing read from validate.yml or from a file name is evaluated, sourced or
# used to build a pattern.
#
# ACCEPTED LIMITS, each a false failure and never a false pass: a quoted value, a `./scripts/` path,
# a `run: |` or `run: >` block, a compound command (`a && b` wires only a), an `env`- or
# `cd`-prefixed command. A step with `if:` or `continue-on-error: true` still counts as wired,
# because a line rule cannot see sibling keys. An exit-swallowing suffix such as
# `run: bash scripts/test-a.sh || true` counts as wired too, because the token is the only thing
# read, though that step can never fail CI.
#
# No exemption list, on purpose: an allowlist would be argued with.
#
# Usage: check-test-suites-wired.sh [ROOT]   (default: the git toplevel of this script's directory)
# Exit: 0 every suite wired, 1 an unwired suite (all named on stderr), 2 the input is unusable
#       (no root, root is not a directory, validate.yml missing or unreadable, zero suites found).
set -uo pipefail
# Pin the locale: under C.UTF-8 a U+3000 after the path would end the `[[:space:]]` token cut,
# under C it does not. The guard must tokenise identically wherever it runs (#362).
export LC_ALL=C

if [ "$#" -ge 1 ]; then
  ROOT="$1"
else
  ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-test-suites-wired: not a git checkout and no root given" >&2; exit 2; }
fi
[ -d "$ROOT" ] || { echo "check-test-suites-wired: '$ROOT' is not a directory" >&2; exit 2; }
PROOT="$(CDPATH= cd -- "$ROOT" && pwd -P)" || {
  echo "check-test-suites-wired: cannot resolve '$ROOT'" >&2; exit 2; }

WF="$PROOT/.github/workflows/validate.yml"
if [ ! -f "$WF" ] || [ ! -r "$WF" ]; then
  echo "check-test-suites-wired: .github/workflows/validate.yml is missing or unreadable under '$PROOT'" >&2
  exit 2
fi

. "$(dirname "$0")/guard-lib.sh"

# --- enumerate the suites (basenames) ------------------------------------------------------------
suites=()
if guard_in_checkout "$PROOT"; then
  while IFS= read -r -d '' f; do
    case "$f" in
      "$PROOT"/scripts/*/*) continue ;;   # nested: not directly inside scripts/
      "$PROOT"/scripts/*) ;;
      *) continue ;;
    esac
    b="${f##*/}"
    case "$b" in test-*.sh|test-*.py) suites+=("$b") ;; esac
  done < <(guard_tracked_files "$PROOT")
else
  # A symlinked suite counts, as it does in a checkout; a dangling link is not a suite (#362).
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    suites+=("${f##*/}")
  done < <(find "$PROOT/scripts" -maxdepth 1 \( -type f -o -type l \) \( -name 'test-*.sh' -o -name 'test-*.py' \) -print0 2>/dev/null)
fi

if [ "${#suites[@]}" -eq 0 ]; then
  echo "check-test-suites-wired: no suites found (no tracked scripts/test-*.sh or scripts/test-*.py under '$PROOT')" >&2
  exit 2
fi

# --- collect the wired (interpreter, token) pairs from validate.yml ------------------------------
wired=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  case "$line" in "- "*) line="${line#- }"; line="${line#"${line%%[![:space:]]*}"}" ;; esac
  case "$line" in
    "run: bash scripts/"*)    interp=bash;    rest="${line#run: bash scripts/}" ;;
    "run: python3 scripts/"*) interp=python3; rest="${line#run: python3 scripts/}" ;;
    *) continue ;;
  esac
  token="${rest%%[[:space:]]*}"
  wired+=("$interp $token")
done < "$WF"

# --- compare by string equality only -------------------------------------------------------------
unwired=()
for s in "${suites[@]}"; do
  case "$s" in *.py) want="python3 $s" ;; *) want="bash $s" ;; esac
  found=0
  for w in "${wired[@]+"${wired[@]}"}"; do
    if [ "$w" = "$want" ]; then found=1; break; fi
  done
  [ "$found" -eq 1 ] || unwired+=("$s")
done

if [ "${#unwired[@]}" -gt 0 ]; then
  echo "check-test-suites-wired: ${#unwired[@]} suite(s) have no step in .github/workflows/validate.yml:" >&2
  printf '%s\n' "${unwired[@]}" | LC_ALL=C sort | sed 's|^|  x scripts/|' >&2
  cat >&2 <<'MSG'

Add a single-line step `run: bash scripts/<name>` (or `run: python3 scripts/<name>` for a .py
suite). A comment, a quoted value, a `run: |` block and an interpreter that does not match the
extension do not count.
MSG
  exit 1
fi

echo "check-test-suites-wired: ${#suites[@]} suite(s), all wired in validate.yml."
