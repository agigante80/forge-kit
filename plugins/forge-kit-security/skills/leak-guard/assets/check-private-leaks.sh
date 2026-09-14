#!/usr/bin/env bash
# check-private-leaks-version: 9
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
# THE TREE MODES NEVER LOOK AT HISTORY; --history DOES, AND IT IS OPT-IN (#185, #191). `--all`
# enumerates tracked files in the WORKING TREE, `--staged` reads the index, and `--range` enumerates
# two endpoints and reads each file at HEAD, so a name added and removed inside the range is
# invisible at both ends. A private folder name committed once and deleted later stays readable
# forever in a public repository, and a NAME is exactly the thing someone scrubs from the tree and
# forgets in the history.
#
# `--history` reads the publishable history: every blob reachable from a branch or a tag, and every
# commit and tag MESSAGE (subject and body). The author, committer and tagger lines are NOT scanned
# by this half either: that identity is what the forge already displays beside every commit, public
# by construction like the owning account this scanner drops from its list. The reader is the public
# half's: one `git cat-file --batch`, a POSIX awk reader that counts each object's declared BYTES
# (so a forged batch header hides nothing) and puts no content byte through a regex, NUL-bearing
# objects dropped whole, and an object scanned unless EVERY path it ever had is skipped. In this
# mode a listed name is redacted inside the printed PATH as well as in the evidence, since a path
# is the likeliest place for such a name to sit; --show-names lifts both. NEVER wired into a hook.
#
# `--history --orphans` also reads objects no branch or tag reaches (amended or reset away, not yet
# pruned). A push, a bundle and a clone over a URL never send them; a clone from a local PATH and
# any copy of the .git directory do. With no path, the self-skip is the weaker content test.
#
# WHAT --history REFUSES, exit 2: an alternates file (a `git clone --shared`, resolved through
# `git rev-parse --git-path`), GIT_ALTERNATE_OBJECT_DIRECTORIES or GIT_OBJECT_DIRECTORY set, and a
# partial clone, which would fetch every missing object during the scan.
#
# Scanning the store by hand (#198):
# pass `grep -a` over a `git cat-file --batch` stream, since tree objects contain NUL and a grep
# then treats it as binary; GNU replaces matched lines with "binary file matches", and a wrapper
# passing `-I` skips the stream and reports no match at all.
#
# IT MATCHES LITERAL NAMES, not shapes. A name shortened, hyphenated differently, or embedded in a
# larger word is a different string and is not found. That is the price of the list being exact, and
# the alternative, matching loosely on names this short, would fire on ordinary prose.
#
# For the going-public case, run a credential scanner as well: `gitleaks git .` walks the whole
# history for SECRETS rather than identity, so it is a companion and not a substitute.
#
#   check-private-leaks.sh [--staged | --range <base> | --all] [--list <path>] [--show-names] [paths...]
#   check-private-leaks.sh --history [--orphans] [--list <path>] [--show-names]
#
# Exit 0 clean, 1 on a finding, 2 when it could not run. One line per finding:
#   <file>:<line>: private-name: <redacted>                    (tree modes)
#   <path>@<oid>:<line>: private-name: <redacted>              (--history; commit@, tag@, or blob@
#                                                               when no path is known)
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
ORPHANS=0

die()  { printf 'check-private-leaks: %s\n' "$1" >&2; exit 2; }
warn() { printf 'check-private-leaks: %s\n' "$1" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --all)         MODE=all ;;
    --staged)      MODE=staged ;;
    --range)       MODE=range; shift; [ $# -gt 0 ] || die "--range needs a base ref"; BASE="$1" ;;
    --history)     MODE=history ;;
    --orphans)     ORPHANS=1 ;;
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

# --history is a mode, and --orphans means nothing without it. Refused rather than ignored: a flag
# that silently does nothing is a scan the user believes ran wider than it did.
if [ "$MODE" = history ]; then
  [ "${#PATHS[@]}" -eq 0 ] || die "--history takes no paths"
else
  [ "$ORPHANS" = 0 ] || die "--orphans is only valid with --history"
fi

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
    history) : ;;
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
[ "$MODE" = history ] || [ "${#FILES[@]}" -gt 0 ] || exit 0

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
BLOB="$TMPD/blob"

skip_by_name() {  # skip_by_name <path> [<lowercased basename>]
  # The second argument lets --history, which decides thousands of paths in one loop, pass a
  # basename awk already lowercased, so the loop forks nothing on the bash-3 slow path.
  if [ $# -ge 2 ]; then LOWER="$2"; else set_lower "${1##*/}"; fi
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
# --- history mode --------------------------------------------------------------
# The reader. One awk program, POSIX, run under LC_ALL=C over the --batch stream with NUL already
# mapped to \001 by tr. It is in the r<0 state between objects, where the only thing it will accept
# is a header; inside an object it COUNTS: r starts at the declared size plus the newline git adds,
# every line subtracts its length plus one, and the object ends when r reaches zero. A content line
# that looks like a header is therefore content. No regex touches a content line (see the header
# for why); index, substr and length are byte operations. It emits "<label>\t<line>\t<text>" for
# every content line of every object it keeps, and drops an object whole when it contains NUL, or
# when it is the scanner's own source: an oid marked "cand" (some path has this scanner's basename)
# is self when it carries the marker line; under --orphans, with no path, self is the weaker
# content test of shebang plus marker on lines 1 and 2.
# The "r < 0 {" line is the load-bearing one, and the contract test mutates exactly it.
READER='
BEGIN {
  r = -1
  while ((getline l < labels) > 0) { split(l, a, "\t"); label[a[1]] = a[2]; if (a[3] == "cand") cand[a[1]] = 1 }
  close(labels)
}
r < 0 {
  if (NF == 3 && length($1) == 40 && ($2 == "blob" || $2 == "commit" || $2 == "tag") && $3 ~ /^[0-9]+$/) {
    oid = $1; type = $2; r = $3 + 1; n = 0; bin = 0; self = 0; cnt = 0; body = (type == "blob")
    if (type == "blob") { lab = ((oid in label) && label[oid] != "") ? label[oid] "@" oid : "blob@" oid } else lab = type "@" oid
    next
  }
  print "malformed cat-file header: " $0 > "/dev/stderr"; exit 2
}
{
  r -= length($0) + 1; n++
  if (index($0, "\001")) bin = 1
  if (substr($0, 1, 8) == "# check-" && index($0, "-leaks-version: ")) {
    if (oid in cand) self = 1
    else if (orphans && n == 2 && substr(first, 1, 2) == "#!") self = 1
  }
  if (n == 1) first = $0
  if (body) buf[cnt++] = n "\t" $0
  else if ($0 == "") body = 1
  if (r <= 0) {
    if (!bin && !self) for (i = 0; i < cnt; i++) print lab "\t" buf[i]
    split("", buf); r = -1
  }
}
END { if (r > 0) { print "truncated cat-file stream" > "/dev/stderr"; exit 2 } }
'

history_scan() {
  # Refusals first. Each is a store this scanner would read as if it were the repository, and is not.
  [ -z "${GIT_OBJECT_DIRECTORY:-}" ] || die "refusing --history: GIT_OBJECT_DIRECTORY is set"
  [ -z "${GIT_ALTERNATE_OBJECT_DIRECTORIES:-}" ] || die "refusing --history: GIT_ALTERNATE_OBJECT_DIRECTORIES is set"
  local alt promisor
  alt="$(git rev-parse --git-path objects/info/alternates 2>/dev/null)"
  [ -n "$alt" ] && [ -f "$alt" ] && die "refusing --history: objects/info/alternates points outside this repository ($alt)"
  promisor="$(git config --get extensions.partialclone 2>/dev/null || true)"
  [ -n "$promisor" ] || promisor="$(git config --get-regexp '^remote\..*\.promisor$' true 2>/dev/null | sed -n 's/^remote\.\(.*\)\.promisor.*/\1/p' | head -1)"
  [ -z "$promisor" ] || die "refusing --history: this is a partial clone; --history would fetch every missing object from $promisor"

  local objects="$TMPD/objects" types="$TMPD/types" pathmap="$TMPD/paths" labels="$TMPD/labels" oids="$TMPD/oids"
  local tagged="$TMPD/tagged" hits="$TMPD/hits"
  # Enumerate. The publishable set carries one path per object; --batch-all-objects carries none.
  if [ "$ORPHANS" = 1 ]; then
    git cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype)' > "$types" || die "git cat-file failed"
    : > "$objects"
  else
    git rev-list --objects --branches --tags > "$objects" || die "git rev-list failed"
    cut -d' ' -f1 "$objects" | git cat-file --batch-check='%(objectname) %(objecttype)' > "$types" || die "git cat-file failed"
  fi
  # Every path each blob has ever had, from every commit's diff against every parent (-m: a merge
  # resolved to content in neither parent has no other entry). -z then tr, because --raw quotes
  # unusual paths without it. Deletions carry the null oid and drop out with the "D" status.
  git log -m --branches --tags --raw --no-abbrev --no-renames --format= -z 2>/dev/null \
    | LC_ALL=C tr '\0' '\n' \
    | LC_ALL=C awk 'NR % 2 == 1 { split($0, a, " "); oid = a[4]; st = a[5]; next } st != "D" && oid !~ /^0+$/ { print oid "\t" $0 }' \
    | LC_ALL=C sort -u > "$pathmap"
  # Decide, per object, whether it is read and under what label. A blob is read unless EVERY path
  # it ever had is skipped; when its only unskipped paths carry this scanner's basename it is a
  # candidate for the identity test, which the reader completes by looking for the marker line. An
  # object with no path at all (--orphans, or a blob the map never saw) is read.
  # One sorted merge of every (blob, path) pair, the rev-list path first for each blob, then one
  # sequential read: no process runs per object, which is what keeps this under a second.
  local merged="$TMPD/merged"
  {
    LC_ALL=C awk '{ p = $0; sub(/^[0-9a-f]+ ?/, "", p); if (p != "") print $1 "\t0\t" p }' "$objects"
    LC_ALL=C awk -F'\t' '{ print $1 "\t1\t" $2 }' "$pathmap"
  } | LC_ALL=C sort -t'	' -k1,1 -k2,2 -k3,3 -u \
    | LC_ALL=C awk -F'\t' -v types="$types" '
        BEGIN { while ((getline l < types) > 0) { split(l, a, " "); t[a[1]] = a[2] } close(types) }
        t[$1] == "blob" { seen[$1] = 1; n = split($3, b, "/"); print $1 "\t" $3 "\t" tolower(b[n]) }
        END { for (o in t) if (t[o] == "blob" && !(o in seen)) print o "\t\t" }' > "$merged"
  local oid type path lower cur="" keep="" selfnamed=0 first="" selfbase="${SELF##*/}"
  set_lower "$selfbase"; local selflower="$LOWER"
  : > "$labels"
  finish_blob() {
    [ -n "$cur" ] || return 0
    if [ "$keep" = blob ]; then printf '%s\n' "$cur" >> "$labels"
    elif [ -n "$keep" ]; then printf '%s\t%s\t\n' "$cur" "$keep" >> "$labels"
    elif [ "$selfnamed" = 1 ]; then printf '%s\t%s\tcand\n' "$cur" "$first" >> "$labels"
    fi
  }
  while read -r oid type; do
    case "$type" in commit|tag) printf '%s\n' "$oid" >> "$labels" ;; esac
  done < "$types"
  while IFS='	' read -r oid path lower; do
    if [ "$oid" != "$cur" ]; then finish_blob; cur="$oid"; keep=""; selfnamed=0; first=""; fi
    [ -n "$path" ] || { keep=blob; continue; }
    [ -n "$first" ] || first="$path"
    [ -z "$keep" ] || continue
    skip_by_name "$path" "$lower" && continue
    [ "$lower" != "$selflower" ] || { selfnamed=1; continue; }
    keep="$path"
  done < "$merged"
  finish_blob
  cut -f1 "$labels" > "$oids"
  [ -s "$oids" ] || return 0
  # Read. One cat-file, one tr, one awk; then ONE grep over the tagged stream for any name and one
  # more, -o, over the hit lines only, joined back to the label and line by hit-line number in awk.
  # -a on both: the stream carries raw bytes. Names in the printed path are redacted by the same
  # awk, so no process runs per finding.
  git cat-file --batch < "$oids" \
    | LC_ALL=C tr '\0' '\001' \
    | LC_ALL=C awk -v labels="$labels" -v orphans="$ORPHANS" "$READER" > "$tagged"
  local st="${PIPESTATUS[2]}"
  [ "$st" = 0 ] || die "the history reader failed (exit $st)"
  LC_ALL=C grep -aiF -f "$PATFILE" "$tagged" > "$hits" || true
  [ -s "$hits" ] || return 0
  LC_ALL=C grep -aoinF -f "$PATFILE" "$hits" > "$TMPD/matches" || true
  local found
  found="$(LC_ALL=C awk -F'\t' -v matches="$TMPD/matches" -v names="$PATFILE" -v show="$SHOW_NAMES" '
    function redact(n,  i, o) { o = substr(n, 1, 2); for (i = 3; i <= length(n); i++) o = o "*"; return o }
    function hide(p,  k, lp, ln, i, out) {   # redact every listed name inside a path, case-insensitively
      if (show) return p
      lp = tolower(p)
      for (k = 1; k <= nn; k++) {
        ln = tolower(name[k]); out = ""
        while ((i = index(lp, ln)) > 0) { out = out substr(p, 1, i - 1) redact(substr(p, i, length(ln))); p = substr(p, i + length(ln)); lp = substr(lp, i + length(ln)) }
        p = out p; lp = tolower(p)
      }
      return p
    }
    BEGIN {
      while ((getline l < names) > 0) name[++nn] = l; close(names)
      while ((getline l < matches) > 0) { i = index(l, ":"); hit[substr(l, 1, i - 1)] = hit[substr(l, 1, i - 1)] "\n" substr(l, i + 1) } close(matches)
    }
    (NR "") in hit {
      lab = $1; ln = $2; at = index(lab, "@"); path = substr(lab, 1, at - 1); oid = substr(lab, at)
      n = split(substr(hit[NR ""], 2), m, "\n")
      for (i = 1; i <= n; i++) print hide(path) oid ":" ln ": private-name: " (show ? m[i] : redact(m[i]))
    }' "$hits")"
  [ -n "$found" ] || return 0
  printf '%s\n' "$found"
  violations=$(( violations + $(printf '%s\n' "$found" | grep -c .) ))
}

if [ "$MODE" = history ]; then
  history_scan
  [ "$violations" -eq 0 ] || exit 1
  exit 0
fi

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
