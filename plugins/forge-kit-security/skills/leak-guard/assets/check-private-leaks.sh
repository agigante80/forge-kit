#!/usr/bin/env bash
# check-private-leaks-version: 1
#
# The PRIVATE half of the leak guard (forge-kit issue #99, split as #156): private project and
# folder NAMES reaching a repository that is about to be made public. Its companion,
# check-public-leaks.sh, catches path shapes and addresses without needing to know anything; this
# one cannot, because deciding that "acme-migration" is private requires knowing that it is.
#
#   check-private-leaks.sh [--staged | --range <base> | --all] [--list <path>] [--show-names] [paths...]
#
# Exit 0 clean, 1 on a finding, 2 when it could not run. One line per finding:
#   <file>:<line>: private-name: <redacted>
#
# WHY THE LIST IS NOT IN THE REPOSITORY. A committed file enumerating the names you have been
# hiding tells a reader exactly what to search the history for. It converts a guard into an index.
# So the list lives in the unpublished agent config directory, and this runs LOCALLY ONLY. Putting
# it in a CI secret is the same mistake in a place with more readers and worse access controls.
#
# WHY THE REPORT REDACTS BY DEFAULT. The class of leak this component exists to stop is pasted
# output: a traceback, a shell transcript, a failing hook. This hook's own output is exactly that
# kind of text, and printing the matched name in full makes pasting it into a public issue the next
# leak. The file and line are enough to act on; --show-names is there for when you need certainty
# and are not about to paste.
#
# THREE BEHAVIOURS THAT LOOK LIKE LENIENCY AND ARE NOT. Every one of them fails in the direction of
# the guard being REMOVED, which is the only failure mode that matters for something nobody is
# forced to keep:
#
#   - A MISSING LIST exits 0 and says so. A guard that blocks every fresh clone gets uninstalled.
#   - THE OWNING ACCOUNT'S NAME is dropped with a warning rather than obeyed. It is in the
#     repository's own clone URL, so a list containing it refuses every commit that touches the
#     README. Public identity and private identity are different sets.
#   - A VERY SHORT ENTRY refuses the run. Two characters match nearly every file, and a guard that
#     fires on everything is one its owner switches off within a day.

set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
MIN_NAME_LEN=3

MODE=all
BASE=""
LIST="${HOME}/.claude/forge-kit/private-names.txt"
SHOW_NAMES=0
PATHS=()

die()  { printf 'check-private-leaks: %s\n' "$1" >&2; exit 2; }
warn() { printf 'check-private-leaks: %s\n' "$1" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --all)         MODE=all ;;
    --staged)      MODE=staged ;;
    --range)       MODE=range; shift; [ $# -gt 0 ] || die "--range needs a base ref"; BASE="$1" ;;
    --list)        shift; [ $# -gt 0 ] || die "--list needs a path"; LIST="$1" ;;
    --show-names)  SHOW_NAMES=1 ;;
    --help|-h)     sed -n '3,32p' "$SELF"; exit 0 ;;
    --)            shift; while [ $# -gt 0 ]; do PATHS+=("$1"); shift; done; break ;;
    -*)            die "unknown flag: $1" ;;
    *)             PATHS+=("$1") ;;
  esac
  shift
done

# --- the list ---------------------------------------------------------------
if [ ! -f "$LIST" ]; then
  warn "no private-name list at $LIST, so NAMES ARE NOT BEING CHECKED."
  warn "  this is not an error: the list is deliberately outside the repository, and a machine"
  warn "  that never had one must not be blocked. Copy private-names.txt.template there to enable it."
  exit 0
fi

# The account that owns this repository is public by definition: it is in the clone URL. A list
# entry matching it would fire on the README, the workflows, and the install instructions.
OWNER=""
remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$remote_url" ]; then
  u="${remote_url%.git}"
  u="${u#*://}"; u="${u#*@}"          # strip scheme and any ssh user
  u="${u#*[:/]}"                      # strip host
  OWNER="${u%%/*}"
fi

NAMES=()
lineno=0
while IFS= read -r raw || [ -n "$raw" ]; do
  lineno=$((lineno + 1))
  n="${raw%$'\r'}"
  n="${n#"${n%%[![:space:]]*}"}"
  n="${n%"${n##*[![:space:]]}"}"
  case "$n" in ''|'#'*) continue ;; esac
  if [ "${#n}" -lt "$MIN_NAME_LEN" ]; then
    die "$LIST:$lineno: '$n' is too short (under $MIN_NAME_LEN characters). It would match almost
  every file, and a guard that fires on everything is one you switch off. Use the full name."
  fi
  if [ -n "$OWNER" ] && [ "${n,,}" = "${OWNER,,}" ]; then
    warn "$LIST:$lineno: dropping '$n': it is the OWNING ACCOUNT of this repository, so it appears"
    warn "  in the clone URL and would refuse every commit touching the README. Public identity and"
    warn "  private identity are different sets."
    continue
  fi
  NAMES+=("$n")
done < "$LIST"

[ "${#NAMES[@]}" -gt 0 ] || exit 0

# --- which files ------------------------------------------------------------
FILES=()
if [ "${#PATHS[@]}" -gt 0 ]; then
  MODE=paths
  FILES=("${PATHS[@]}")
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "not inside a git work tree (pass explicit paths to scan without git)"
  case "$MODE" in
    all)    while IFS= read -r -d '' f; do FILES+=("$f"); done < <(git ls-files -z) ;;
    staged) while IFS= read -r -d '' f; do FILES+=("$f"); done \
              < <(git diff --cached --name-only --diff-filter=ACM -z) ;;
    range)
      # Fail CLOSED on an absent base, rather than passing vacuously.
      git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
        || die "base ref not found: $BASE (fetch it first)"
      while IFS= read -r -d '' f; do FILES+=("$f"); done \
        < <(git diff --name-only --diff-filter=ACM -z "$BASE...HEAD") ;;
  esac
fi
[ "${#FILES[@]}" -gt 0 ] || exit 0

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
BLOB="$TMPD/blob"

skip_by_name() {
  local base="${1##*/}"
  case "${base,,}" in
    *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.ico|*.webp|*.svgz|*.pdf|*.zip|*.gz|*.bz2|*.xz|*.tar \
    |*.woff|*.woff2|*.ttf|*.otf|*.eot|*.mp3|*.mp4|*.mov|*.wav|*.class|*.jar|*.so|*.dylib \
    |*.dll|*.exe|*.pyc|*.o|*.a|*.wasm) return 0 ;;
    *.lock|package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|composer.lock \
    |gemfile.lock|poetry.lock|cargo.lock|go.sum|*.lockb) return 0 ;;
  esac
  return 1
}

# Two leading characters and the length, which is enough for the owner to recognise their own name
# and not enough for a reader of a pasted transcript to learn it.
redact() {
  local n="$1" out="${1:0:2}" i
  for ((i = 2; i < ${#n}; i++)); do out+='*'; done
  printf '%s' "$out"
}

violations=0
for f in "${FILES[@]}"; do
  skip_by_name "$f" && continue
  case "$MODE" in
    staged) git show ":$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    range)  git show "HEAD:$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    *)      scanfile="$f" ;;
  esac
  [ -f "$scanfile" ] || continue
  [ "$(readlink -f "$scanfile" 2>/dev/null || echo "$scanfile")" = "$SELF" ] && continue
  # Read by grep, never through a command substitution: null bytes would be dropped and warned
  # about once per occurrence, so a full scan would print a wall of noise and read fonts as text.
  grep -Iq . "$scanfile" 2>/dev/null || continue

  for n in "${NAMES[@]}"; do
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      if [ "$SHOW_NAMES" = 1 ]; then shown="$n"; else shown="$(redact "$n")"; fi
      printf '%s:%s: private-name: %s\n' "$f" "${g%%:*}" "$shown"
      violations=$((violations + 1))
    done < <(grep -niF -- "$n" "$scanfile" 2>/dev/null)
  done
done

[ "$violations" -eq 0 ] || exit 1
exit 0
