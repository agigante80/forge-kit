#!/usr/bin/env bash
# check-private-leaks-version: 8
#
# The private half of the leak guard: project and folder NAMES that must not become public.
#
# Its companion, check-public-leaks.sh, catches path shapes and addresses without needing to know
# anything about you; this one cannot, because deciding that a name is private requires knowing
# that it is (forge-kit issue #99, split as #156). The first line above is deliberately one whole
# sentence: the component index renders it verbatim.
#
# HONEST STATEMENT OF REACH. This header carried none until #185, which is its own small lesson:
# the public half states four limits carefully and this one stated nothing, so a reader comparing
# them would reasonably infer this half had none.
#
# IT NEVER LOOKS AT HISTORY. `--all` enumerates tracked files in the WORKING TREE, `--staged` reads
# the index, and `--range` enumerates two endpoints and reads each file at HEAD, so a name added and
# removed inside the range is invisible at both ends. A private folder name committed once and
# deleted later stays readable forever in a public repository and this scanner will never say so.
# That matters more here than for the public half: a NAME is exactly the thing someone scrubs from
# the tree and forgets in the history.
#
# IT SEES ONLY FILE CONTENT, never a commit message, a branch name or a tag. On this repository the
# object store holds 527 commit objects, and a private name in any of their messages is unreached.
# Scanning the store by hand (#198): pass `grep -a` over a `git cat-file --batch` stream, since
# tree objects contain NUL and a grep then treats it as binary; GNU replaces matched lines with
# "binary file matches", and a wrapper passing `-I` skips the stream and reports no match at all.
#
# IT MATCHES LITERAL NAMES, not shapes. A name shortened, hyphenated differently, or embedded in a
# larger word is a different string and is not found. That is the price of the list being exact, and
# the alternative, matching loosely on names this short, would fire on ordinary prose.
#
# For the going-public case, run a history-aware scanner as well. `gitleaks git .` walks the whole
# history, though it hunts CREDENTIALS rather than identity, so it is a companion and not a
# substitute.
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

# --- portability ------------------------------------------------------------
# macOS still ships bash 3.2 and a BSD readlink with no -f, and this component is installed into
# other people's repositories. A guard that dies on a contributor's laptop is a guard they remove.
# The lowercase helper assigns to a variable rather than returning a string, so the fast path on
# bash 4 costs no fork at all; the slow path pays one, on the platform that has no alternative.
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  set_lower() { LOWER="${1?}"; LOWER="${LOWER,,}"; }
else
  set_lower() { LOWER="$(printf '%s' "${1?}" | tr '[:upper:]' '[:lower:]')"; }
fi
# POSIX stand-in for `readlink -f`, which is enough here: every path this resolves exists, so the
# only job is to make two spellings of the same file compare equal.
abspath() {
  local d b
  d="$(dirname -- "$1")"; b="$(basename -- "$1")"
  d="$(cd -- "$d" 2>/dev/null && pwd -P)" || { printf '%s' "$1"; return; }
  printf '%s/%s' "$d" "$b"
}

SELF="$(abspath "${BASH_SOURCE[0]}")"
MIN_NAME_LEN=3

MODE=all
BASE=""
LIST="${HOME}/.claude/forge-kit/private-names.txt"
SHOW_NAMES=0
DO_INIT=0
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
    --init)        DO_INIT=1 ;;
    # Prints the whole comment header, rather than a hardcoded line range. The range was the bug:
    # growing the header by seven lines truncated --help mid-sentence and dropped the synopsis, and
    # help text that rots silently is worse than none because it still reads as current.
    --help|-h)    awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit 0 ;;
    --)            shift; while [ $# -gt 0 ]; do PATHS+=("$1"); shift; done; break ;;
    -*)            die "unknown flag: $1" ;;
    *)             PATHS+=("$1") ;;
  esac
  shift
done

# --- --init: write a starter list ------------------------------------------
# The template is HERE rather than in a .txt beside this script, because forge-adapt installs a
# skill's `assets/*.sh` and nothing else: a separate template file would never reach the project,
# and the guidance would point at a file that was not installed. One asset, one marker, and no
# second copy of this text to drift out of step with the rules the script actually enforces.
if [ "$DO_INIT" = 1 ]; then
  [ -e "$LIST" ] && die "refusing to overwrite the existing list at $LIST"
  mkdir -p "$(dirname "$LIST")" || die "could not create $(dirname "$LIST")"
  cat > "$LIST" <<'TEMPLATE'
# private-names.txt -- the identity half of forge-kit's leak guard.
#
# Add the names you do not want reaching a public repository: sibling project names, client
# names, an employer, a filing scheme, the folder your projects live in. One per line. Blank
# lines and lines starting with # are ignored.
#
# THIS FILE MUST STAY UNTRACKED. Its entire security property is that it was never published: a
# committed list of the names you are hiding tells a reader exactly what to search the history
# for, which converts a guard into an index. That is also why this half never runs in CI, and why
# the list must not go in a CI secret. The scanner REFUSES to run against a tracked list.
#
# DO NOT ADD THE OWNING ACCOUNT NAME of a repository you work in. It is in that repository's own
# clone URL, so it would fire on the README, the workflows and the install instructions. Public
# identity and private identity are different sets. The scanner drops such an entry with a
# warning rather than obeying it, but it can only do that for the repository it is run in.
#
# Names shorter than three characters are refused: they match nearly every file, and a guard that
# fires on everything is one you switch off within a day.
#
# Matching is case insensitive and matches anywhere in a line, so a short distinctive name also
# catches the longer names built from it. Prefer the shortest name that is still distinctive.
TEMPLATE
  printf 'check-private-leaks: wrote %s. Add your names to it.\n' "$LIST" >&2
  exit 0
fi

# --- the list ---------------------------------------------------------------
if [ ! -f "$LIST" ]; then
  warn "no private-name list at $LIST, so NAMES ARE NOT BEING CHECKED."
  warn "  this is not an error: the list is deliberately outside the repository, and a machine"
  warn "  that never had one must not be blocked. Run this with --init to write a starter list."
  exit 0
fi

# A TRACKED list is the exact disclosure this component exists to prevent: a committed file
# enumerating the names you are hiding points a reader straight at them. REFUSE rather than warn.
# A warning here would be advice about an active leak, and the fix is one command.
#
# The default path is under the home directory, so this can only fire when someone has pointed
# --list at a file inside the repository. That is the precondition the original design wanted a
# forge-adapt step to enforce; checked here, it is enforced everywhere the guard runs rather than
# only where the installer ran.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && git ls-files --error-unmatch -- "$LIST" >/dev/null 2>&1; then
  die "the private-name list at $LIST is TRACKED by this repository.
  That publishes the names you are hiding, which is worse than not checking at all.
  Fix it:  git rm --cached '$LIST'  then add it to .gitignore, or move it to
  ~/.claude/forge-kit/private-names.txt, which no project repository can track."
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
  set_lower "$n";     n_lc="$LOWER"
  set_lower "$OWNER"; owner_lc="$LOWER"
  if [ -n "$OWNER" ] && [ "$n_lc" = "$owner_lc" ]; then
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
  set_lower "$base"
  case "$LOWER" in
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

# The names as a grep pattern file, written once. -F is literal, so nothing in a name is a regex.
PATFILE="$TMPD/names"
printf '%s\n' "${NAMES[@]}" > "$PATFILE"

violations=0
for f in "${FILES[@]}"; do
  skip_by_name "$f" && continue
  case "$MODE" in
    staged) git show ":$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    range)  git show "HEAD:$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    *)      scanfile="$f" ;;
  esac
  [ -f "$scanfile" ] || continue
  # Compared against the NAMED path, never the file being read. In --staged and --range that file
  # is a temp blob, so comparing it here would never match and the scanner would report its own
  # source. Every project that vendors this asset and wires the commit hook hits that on the
  # commit that installs it, which is how it was found.
  # Gated on the basename first: abspath forks three times, and paying that on every file in the
  # tree costs more than the scan itself. Only a file that could BE the script is resolved.
  case "${f##*/}" in
    "${SELF##*/}") [ "$(abspath "$f")" = "$SELF" ] && continue ;;
  esac
  # Read by grep, never through a command substitution: null bytes would be dropped and warned
  # about once per occurrence, so a full scan would print a wall of noise and read fonts as text.
  grep -Iq . "$scanfile" 2>/dev/null || continue

  # ONE grep per file, matching every name at once from a pattern file, rather than one grep per
  # (file x name). At ten names and five thousand files the old shape was fifty thousand process
  # spawns on every push, in a component shipped into other people's repositories.
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    hit="${g#*:}"
    if [ "$SHOW_NAMES" = 1 ]; then shown="$hit"; else shown="$(redact "$hit")"; fi
    printf '%s:%s: private-name: %s\n' "$f" "${g%%:*}" "$shown"
    violations=$((violations + 1))
  done < <(grep -noiF -f "$PATFILE" -- "$scanfile" 2>/dev/null)
done

[ "$violations" -eq 0 ] || exit 1
exit 0
