#!/usr/bin/env bash
# check-public-leaks-version: 7
#
# The public half of the leak guard: home paths, unlisted "~/" roots and reachable addresses.
#
# Stops the developer's own machine leaking into a repository that is about to be made public
# (forge-kit issue #99, split as #155). It catches by SHAPE and by ALLOWLIST, so it needs no list
# of private names and can therefore run in CI, in the open, for every contributor. The first line
# above is deliberately one whole sentence: the component index renders it verbatim.
#
# HONEST STATEMENT OF REACH. This would not have caught the leak that prompted the ticket. That was
# a set of real sibling-project folder names sitting in prose as demo data, and a folder name in
# prose contains no path and no "@". Rules A and C catch the pasted-traceback class, which is the
# one that recurs. Rule B catches the "~/" class, which is the one that survived a full history
# scrub. NOTHING PUBLIC CATCHES A BARE PROJECT NAME: that needs the list, the list cannot live in
# the repository it protects, and so it lives outside it and is checked by the private half. A
# guard that overstates its reach is worse than a narrow one that admits it.
#
# IT NEVER LOOKS AT HISTORY, AND THAT IS THE LIMIT MOST LIKELY TO MATTER (#185). `--all` enumerates
# `git ls-files`: tracked files in the WORKING TREE. `--staged` reads the index. `--range` looks like
# it reaches history and reaches it least: it enumerates `git diff --name-only --diff-filter=ACM`
# between two endpoints and then reads each file as `git show "HEAD:$f"`, so a file added AND deleted
# inside the range is excluded at both ends and would be skipped even if listed.
#
# So a home path committed in one commit and removed in the next is invisible here, in the public
# repository where it stays readable forever. That is exactly the going-public moment this component
# was written for, which is why the omission is worth more words than the rules themselves.
#
# The object store holds more than file contents: on this repository, 1,639 blobs against 527 commit
# objects. A history scan that read blobs alone would still miss every leak in a COMMIT MESSAGE, so
# "reads history" is a claim with two halves and this scanner makes neither. Whoever scans the
# store by hand (#198): pass `grep -a` over a `git cat-file --batch` stream, because tree objects
# contain NUL and a grep then treats the stream as binary, GNU replacing matched lines with "binary
# file matches" and a wrapper that passes `-I` skipping the stream and reporting no match at all.
#
# USE A HISTORY-AWARE SCANNER FOR THAT CASE. `gitleaks git .` walks the full history, and
# `git log --all --diff-filter=A --name-only --format= -- '*.env' '*.env.*'` lists every env-style
# file ever committed including later-deleted ones. Neither is this component's job: gitleaks hunts
# CREDENTIALS and this hunts the developer's IDENTITY, which is a different subject with a different
# false-positive profile. Running both is the answer, and pretending either covers the other is not.
#
# AND BOTH PATH RULES JUDGE THE FIRST SEGMENT ONLY. Rule A asks who "/home/<name>/" belongs to and
# rule B asks whether "~/<root>" may be shown; NEITHER looks below that. So a private directory name
# under an allowed root ("~/work/<client>/repo", "/home/user/clients/<client>/build.log") is
# invisible here, and the segments above the project are exactly what the ticket called the worse
# half of the leak. Catching those needs the name, which is the private half's job. This was found
# by review AFTER the paragraph above shipped, which is the argument for the paragraph.
#
#   check-public-leaks.sh [--staged | --range <base> | --all] [--allow-file <path>] [paths...]
#
# Exit 0 clean, 1 when something was found, 2 when it could not run. One line per violation:
#   <file>:<line>: <rule>: <evidence>
#
# WHY RULE B IS AN ALLOWLIST AND THE OTHER TWO ARE NOT. Shape can decide "/home/alice/" is a person
# and "/home/user/" is a placeholder. Shape cannot decide whether "~/foo" is private, because the
# string carries no marker either way. So the test is inverted: an allowlist of roots a document is
# allowed to show. That catches the case by construction rather than by enumeration, and it needs
# one thing from the project, a canonical example root, agreed once.
#
# WHY BINARIES ARE DETECTED BY PIPING INTO grep -I. The obvious alternative, asking git for a
# numstat, is EMPTY in a full-tree mode because nothing is staged, so every binary then reaches a
# command substitution, which drops null bytes and warns once per occurrence. A full scan prints a
# wall of warnings and reads font files as text.
#
# WHY THE SCRIPT SKIPS ITSELF. Its own source has to carry the patterns, so scanning it would
# report the guard as a leak. Its TEST is not skipped here: it is excluded by an allow-file entry
# in the project that runs it, which keeps the exemption visible in that project's own config
# rather than hidden in this file.

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

MODE=all
BASE=""
ALLOW_FILE=""
PATHS=()

die() { printf 'check-public-leaks: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --all)        MODE=all ;;
    --staged)     MODE=staged ;;
    --range)      MODE=range; shift; [ $# -gt 0 ] || die "--range needs a base ref"; BASE="$1" ;;
    --allow-file) shift; [ $# -gt 0 ] || die "--allow-file needs a path"; ALLOW_FILE="$1" ;;
    # Prints the whole comment header, rather than a hardcoded line range. The range was the bug:
    # growing the header by seven lines truncated --help mid-sentence and dropped the synopsis, and
    # help text that rots silently is worse than none because it still reads as current.
    --help|-h)    awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit 0 ;;
    --)           shift; while [ $# -gt 0 ]; do PATHS+=("$1"); shift; done; break ;;
    -*)           die "unknown flag: $1" ;;
    *)            PATHS+=("$1") ;;
  esac
  shift
done

# --- the allowed sets ------------------------------------------------------
# Roots a document may show. "<root>" is the generic placeholder for projects that have not agreed
# a canonical example root yet; the others are either the canonical root or real, published
# locations that any reader can visit on their own machine.
# The dotfile entries are not a nod to convenience. Every one of them names a location that is
# identical on every machine, so it discloses nothing about whose machine it is, which is the only
# question this rule asks.
ALLOW_ROOTS=(projects .claude .config .local .cache dev code src work '<root>'
             .ssh .bashrc .bash_profile .zshrc .profile .gitconfig .npmrc)
# Segments that are obviously a stand-in for a person rather than a person.
PLACEHOLDER_USERS=(user users username youruser '<user>' '<username>' '<name>' '<you>' '...' '$USER' '${USER}' '$HOME')
ALLOW_PREFIXES=()
ALLOW_EMAILS=()
SKIP_PATHS=()

if [ -n "$ALLOW_FILE" ]; then
  [ -f "$ALLOW_FILE" ] || die "allow-file not found: $ALLOW_FILE"
  lineno=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    line="${raw%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"          # strip leading whitespace
    line="${line%"${line##*[![:space:]]}"}"          # strip trailing whitespace
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%% *}"; val="${line#* }"
    [ "$key" != "$val" ] || die "$ALLOW_FILE:$lineno: entry has no value: $line"
    case "$key" in
      # A root is written the way it appears in prose, "~/name", so the config reads like the
      # thing it permits.
      root)   ALLOW_ROOTS+=("${val#\~/}") ;;
      # Rule A matches "/home/<seg>" or "/Users/<seg>" and nothing deeper, so a prefix with more
      # than one segment, or one under any other root, can never equal a match. It would parse
      # cleanly and silently do nothing, which is the config bug every other key here refuses.
      prefix)
        pfx="${val%/}"
        case "$pfx" in
          /home/*|/Users/*) : ;;
          *) die "$ALLOW_FILE:$lineno: prefix must start /home/ or /Users/ (rule A matches no other root): $pfx" ;;
        esac
        rest="${pfx#/*/}"
        case "$rest" in
          */*|'') die "$ALLOW_FILE:$lineno: prefix must name exactly one segment, because rule A matches one segment and nothing deeper: $pfx" ;;
        esac
        ALLOW_PREFIXES+=("$pfx") ;;
      email)  ALLOW_EMAILS+=("$val") ;;
      skip)   SKIP_PATHS+=("$val") ;;
      # REFUSE rather than skip the entry. A silently ignored line in a security config is a guard
      # that reports a coverage it does not have, which is the failure this whole component exists
      # to end.
      *)      die "$ALLOW_FILE:$lineno: unknown key '$key' (want root, prefix, email or skip)" ;;
    esac
  done < "$ALLOW_FILE"
fi

in_list() { local n="$1"; shift; local x; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

# --- which files ------------------------------------------------------------
in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

FILES=()
if [ "${#PATHS[@]}" -gt 0 ]; then
  MODE=paths
  FILES=("${PATHS[@]}")
else
  in_git || die "not inside a git work tree (pass explicit paths to scan without git)"
  case "$MODE" in
    all)
      while IFS= read -r -d '' f; do FILES+=("$f"); done < <(git ls-files -z) ;;
    staged)
      while IFS= read -r -d '' f; do FILES+=("$f"); done \
        < <(git diff --cached --name-only --diff-filter=ACM -z) ;;
    range)
      # Fail CLOSED on a base ref that is not present, rather than passing vacuously. The same
      # posture the repo's other range guards take: a check that cannot run must not report clean.
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

# --- what is not worth scanning --------------------------------------------
skip_by_name() {
  # Suffixes match anywhere in the path; the named lockfiles must match the BASENAME, or a path
  # like "vendor/package-lock.json" slips through while "package-lock.json" at the root is caught.
  local base="${1##*/}"
  set_lower "$base"
  case "$LOWER" in
    *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.ico|*.webp|*.svgz|*.pdf|*.zip|*.gz|*.bz2|*.xz|*.tar \
    |*.woff|*.woff2|*.ttf|*.otf|*.eot|*.mp3|*.mp4|*.mov|*.wav|*.class|*.jar|*.so|*.dylib \
    |*.dll|*.exe|*.pyc|*.o|*.a|*.wasm) return 0 ;;
    # A lockfile is generated, is enormous, and its registry URLs are full of shapes that look
    # like findings. Nobody writes prose in one.
    *.lock|package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|composer.lock \
    |gemfile.lock|poetry.lock|cargo.lock|go.sum|*.lockb) return 0 ;;
  esac
  local s
  for s in ${SKIP_PATHS+"${SKIP_PATHS[@]}"}; do
    [ "$1" = "$s" ] && return 0
    case "$1" in */"$s") return 0 ;; esac
  done
  return 1
}

# --- the three rules --------------------------------------------------------
# The backtick is excluded from both character classes for one reason found by running this over a
# real tree: a markdown code span is the commonest way a path appears in prose, and reading
# "~/name`" as the root means the project's own allow-file entry never matches it.
RE_HOME='(/home|/Users)/[^/[:space:]"`]+/?'
RE_ROOT='~/[^/[:space:]"`]+/?'
RE_MAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
RE_ANY="$RE_HOME|$RE_ROOT|$RE_MAIL"

# Trailing sentence punctuation belongs to the prose, not to the name. Only the tail is stripped,
# so "~/.claude" keeps the dot that is part of the directory name. The angle bracket is deliberately
# NOT in the set: stripping it would turn the "<user>" placeholder into "<user", which no longer
# matches the placeholder list, and the guard would start rejecting the documentation forms it
# exists to permit.
TAIL_PUNCT='.,;:!?)]}"'"'"
strip_tail() {
  local s="$1" c
  while [ -n "$s" ]; do
    c="${s: -1}"
    case "$TAIL_PUNCT" in
      *"$c"*) s="${s%?}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
}

violations=0
report() { printf '%s:%s: %s: %s\n' "$1" "$2" "$3" "$4"; violations=$((violations + 1)); }

for f in "${FILES[@]}"; do
  skip_by_name "$f" && continue

  case "$MODE" in
    staged) git show ":$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    range)  git show "HEAD:$f" > "$BLOB" 2>/dev/null || continue; scanfile="$BLOB" ;;
    *)      scanfile="$f" ;;
  esac
  [ -f "$scanfile" ] || continue

  # Never report the guard's own source: it has to contain the patterns to apply them.
  # Compared against the NAMED path, never the file being read. In --staged and --range that file
  # is a temp blob, so comparing it here would never match and the scanner would report its own
  # source. Every project that vendors this asset and wires the commit hook hits that on the
  # commit that installs it, which is how it was found.
  # Gated on the basename first: abspath forks three times, and paying that on every file in the
  # tree costs more than the scan itself. Only a file that could BE the script is resolved.
  case "${f##*/}" in
    "${SELF##*/}") [ "$(abspath "$f")" = "$SELF" ] && continue ;;
  esac

  # Binary detection reads the file, never a shell variable, so null bytes are neither dropped nor
  # warned about. -I makes grep treat a binary file as non-matching, so an empty result means
  # "binary or empty", and both are nothing to scan.
  grep -Iq . "$scanfile" 2>/dev/null || continue

  # ONE grep per file, not one per rule. The rules are distinguished by the SHAPE of the match,
  # which they already are: only rule A's starts with a slash and only rule B's with a tilde. Three
  # passes cost three process spawns per file, and process spawn is the whole cost here.
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    n="${g%%:*}"; m="${g#*:}"
    case "$m" in
      /*)
        raw="${m%/}"; seg="${raw##*/}"
        # Checked against BOTH forms: "..." is entirely punctuation, so stripping the trailing dots
        # would leave nothing to compare and the guard would reject its own documented placeholder.
        in_list "$seg" "${PLACEHOLDER_USERS[@]}" && continue
        in_list "$(strip_tail "$seg")" "${PLACEHOLDER_USERS[@]}" && continue
        # Punctuation is stripped here for the same reason as the placeholder check above, and
        # its absence was a real false positive: with `prefix /home/runner`, an allowed path at
        # the end of a sentence or inside brackets still reported a leak.
        allowed=0
        rawt="$(strip_tail "$raw")"
        for p in ${ALLOW_PREFIXES+"${ALLOW_PREFIXES[@]}"}; do
          case "$rawt" in "$p"|"$p"/*) allowed=1; break ;; esac
        done
        [ "$allowed" = 1 ] && continue
        report "$f" "$n" home-path "$m" ;;
      '~'/*)
        root="$(strip_tail "${m%/}")"; root="${root#\~/}"
        in_list "$root" "${ALLOW_ROOTS[@]}" && continue
        report "$f" "$n" home-root "$m" ;;
      *)
        addr="$(strip_tail "$m")"
        local_part="${addr%%@*}"; domain="${addr#*@}"
        # An address that cannot reach a mailbox is not a leak. noreply is the convention; the rest
        # are the TLDs reserved by RFC 2606 and RFC 6761 precisely so documentation can use them.
        set_lower "$local_part"
        case "$LOWER" in
          noreply*|no-reply*|donotreply*) continue ;;
          # "git@host" is the SSH clone user, not a mailbox. It is in the clone URL of essentially
          # every repository, so leaving it to each project's allow-file would make the first run of
          # this guard noise rather than signal.
          git) continue ;;
        esac
        set_lower "$domain"
        case "$LOWER" in
          *.example|*.invalid|*.test|*.localhost|*.local) continue ;;
          example.com|example.org|example.net|*.example.com|*.example.org|*.example.net) continue ;;
        esac
        in_list "$addr" ${ALLOW_EMAILS+"${ALLOW_EMAILS[@]}"} && continue
        report "$f" "$n" email "$addr" ;;
    esac
  done < <(grep -onE "$RE_ANY" "$scanfile" 2>/dev/null)
done

[ "$violations" -eq 0 ] || exit 1
exit 0
