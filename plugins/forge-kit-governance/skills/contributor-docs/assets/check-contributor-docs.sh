#!/usr/bin/env bash
# check-contributor-docs-version: 25
# check-contributor-docs.sh: are a repository's contributor entry points TRUE for everyone who
# clones it (#294, amended by #295).
#
# An agent reads AGENTS.md, a person reads CONTRIBUTING.md, and both meet the PR template. Each
# names commands and links other docs, and each rots silently. The trap this exists for is
# agigante80/actual-mcp-server#496: CONTRIBUTING.md named npm scripts that did not exist while
# AGENTS.md was gitignored, so it was present on the maintainer's disk and absent for everyone else.
# Every path here is therefore resolved against the git INDEX, never the disk, and every document,
# Makefile and justfile is READ through safe_open (#309): a tracked one as its index blob, so an
# unstaged edit is not judged and no link, device or file outside the repository is ever opened.
#
# Usage: check-contributor-docs.sh [--docs <file>...] [--max-lines N] [--max-bytes N]
#
# One TSV row per finding, `status<TAB>check<TAB>location<TAB>detail`, status pass, fail or referred.
# Exit 0 when no row is `fail`, 1 when one is, 2 when it could not run, with NOTHING on stdout and
# a reason on stderr (the check-public-leaks.sh posture). Rows are buffered so exit 2 prints none.
#
# It decides nothing about CONTENT. It checks what a machine can check, and where the machine
# cannot settle a question it says `referred` rather than guessing, because a check that fails a
# correct doc gets deleted:
#
#   required   AGENTS.md exists, is in the index, and no ignore rule matches it (check-ignore
#              --no-index, since plain check-ignore never reports a tracked file). A tracked
#              symlink passes only when its target, read from the index, is a relative path that
#              resolves from the link's own directory to a tracked REGULAR file, so AGENTS.md ->
#              CLAUDE.md passes and AGENTS.md -> an untracked CLAUDE.md fails. Any chain, an absolute
#              or escaping target, a directory, a submodule or a dangling name fails, and a
#              rejected AGENTS.md gets that one row: nothing else is built from it. The same rule
#              refuses a symlinked CONTRIBUTING.md, PR template, make or just file and --docs path
#              (one fail row, not read); an untracked --docs path must be a regular file, not a
#              symlink, whose physical directory is inside the repository. Relative links inside a
#              symlinked doc resolve from the link's own directory, as GitHub renders them. Every row
#              field has its control bytes printed as `?`, so no name or link text forges a row.
#   max-lines  AGENTS.md within --max-lines (150, counted as wc -l counts).
#   max-bytes  AGENTS.md within --max-bytes (32768: Codex truncates the file at 32 KiB).
#   command    Only inside code spans and fenced blocks. The FAIL set is a closed allowlist: the two
#              root shapes `npm run X` and `pnpm run X` (`run`, or its alias `run-script`, straight
#              after the package manager, #353; a literal name, no flag but --silent/-s, a tracked
#              root package.json, no cd or pushd earlier in the same scope), plus six workspace
#              spellings resolved against the ONE tracked manifest of that name (#299): npm -w,
#              --workspace and --workspace=, pnpm --filter, -F and --filter=, each followed by
#              `run X` or `run-script X` (#363). Yarn never fails, because yarn falls through to a
#              binary: a defined root script is a pass, anything else referred.
#              Everything else is referred or silent. make and just are read as TEXT and never
#              invoked: make runs recipes while remaking makefiles. npm run X is also referred when a
#              tracked root .npmrc sets workspace or workspaces (#339), or is a symlink.
#              A leading UTF-8 byte-order mark on line 1 of a Makefile or justfile is stripped first
#              (#364), as make and just both ignore it. judge_target runs that awk under LC_ALL=C,
#              as npmrc_scan does (#406): BWK awk, the awk macOS ships, matches the octal strip
#              against no BOM in a UTF-8 locale, so a BOM-led Makefile lost its first target there.
#   script-path  `node|sh|bash <path>`: tracked passes, anything else is referred (a build output
#              is correct and untracked). A path leaving the repository is never read.
#   link       Relative links, images and reference definitions resolve to a tracked path or to a
#              directory some tracked path lies under. `/x` is the repository root, as GitHub
#              renders it; anything else is relative to the containing file. Leaving the
#              repository fails and is never read. In a PR template every relative link is
#              referred, because GitHub copies the template into the PR body and it then resolves
#              against the PR URL.
#   harness-copy  (#300) Never fails. A tracked per-harness copy beside AGENTS.md (CLAUDE.md,
#              GEMINI.md, .github/copilot-instructions.md, .cursor/rules/<name>.mdc, .cursorrules,
#              .junie/guidelines.md, .windsurfrules, the .clinerules file) passes when it reaches
#              AGENTS.md by a mechanism that harness documents, and is referred otherwise. See the
#              check's own section for the table and its limits.
#   import     (#301) Only when the root CLAUDE.md is TRACKED and --docs is not given. Each @-import
#              token CLAUDE.md holds outside spans, fences and HTML comments must name a file a clone has: a
#              tracked, unignored path, resolved from the importing file's directory, with a
#              symlink judged by safe_resolve (the `required` rule). Untracked, absent, ignored or
#              escaping fails; @~/ and @/ are referred and never opened. A markdown import (.md,
#              .markdown, .mdx) is scanned like any doc and its own imports followed, breadth-first,
#              to MAX_IMPORT_HOPS; past it an import is referred. CLAUDE.md itself is read for
#              imports only. A token must START with @ and hold a / or a . (narrower than Claude
#              Code, which tries any token, so @maintainer is prose). Limits: AGENTS.md's own @
#              tokens are never followed, though Claude Code follows them; .claude/CLAUDE.md is not
#              read; a non-markdown import is never opened; @scope/pkg in prose is a false positive.
#
# BLOCK HTML COMMENTS are skipped before anything else is read (#408): no import, link or command
# is taken from inside `<!-- ... -->`, on one line or across lines, as no reader sees it, and a fence
# line inside an open comment opens nothing. A comment inside a fence is fence text.
#
# A SCOPE, for the cd rule: a fenced block is one scope; a code span's scope is its PARAGRAPH, so
# "Run `cd client`, then `npm run dev`." is referred (#295). A cd AFTER the command changes nothing.
# A paragraph ends at a blank line (after a trailing CR is stripped) or at a fence. Inside a fence a
# command must START a segment of a line, split on && || ; | ( ), after an optional `$ ` prompt; a
# VAR=val prefix is skipped to find the runner but refers the row, since npm_config_workspace=client
# rescopes npm. Backticks there are literal, so a backticked name is referred.
#
# EXPORTS AND SUBSTITUTIONS (#296, #346). An `export`, `declare -x` or `typeset -x` of a NAME=value
# whose NAME starts with npm_config_ (any case, any key, an empty value too: referring is the safe
# side) refers every LATER npm, pnpm or yarn runner of the same fence or code-span paragraph, and a
# later segment of its own line, exactly as a cd does and with the same resets. Only those three
# read the variable, so a failing make target or just recipe stays a fail. Also carried: declare or
# typeset with any dash word holding an x (-gx, -g -x), a quoted argument (export "npm_config_x=y")
# and a bare name (npm_config_x=y; export npm_config_x). Only those spellings carry. An npm_config_
# word (a bare name or a NAME=value) after a word starting with # (a comment) or inside a quoted
# value carries nothing, and under export (not declare, where -n means nameref) a dash word holding
# an n anywhere on the line makes the whole line carry nothing; a leading +x option word un-exports
# a declare or typeset in either order with -x. The quote state is parsed, not counted (#387): two
# kinds, a backslash outside single quotes escaping the next byte, so a # or -n inside quotes is
# text. Still limits: a -n after a name under export voids the line (bash would reject it anyway),
# and a quoted ;&|() in a word that is not an assignment value still splits the line. `export FOO=1` and `declare -g npm_config_x=y`
# rescope nothing and still fail. A NAME=value assignment whose value is any mix of plain bytes,
# non-nested $(...) groups, double- or single-quoted runs, backtick runs and backslash-escaped bytes
# (so a value holding a space, or a ;&|() inside quotes) is read as a plain assignment, in one linear
# pass, and refers the row; before #386 a space in the value lost the runner and gave no row, and a
# quoted assignment before a cd hid the cd from the next line.
# Limits: `$VAR` or `${...}` before a substitution (npm_config_workspace=$HOME$(echo c) npm run
# dev) is still a false fail (`export "npm_config_x"=y` carries since the #387 review, as bash
# exports it); an export in a prose code span does not carry into a following fence (the carry resets at
# a fence open, as a cd does); nested-paren substitution values; a value with an UNBALANCED quote,
# which matches no quoted run and is read as before (no row); pnpm_config_*; JUST_JUSTFILE and JUST_WORKING_DIRECTORY; unset; set -a;
# `env VAR=... cmd`.
#
# A TRACKED ROOT .npmrc (#339). npm rescopes `npm run X` when that file sets `workspace` (any value,
# `workspace[]=` and spaces around `=` included) or `workspaces` whose LAST value is not exactly
# `false` (npm takes the last value of a repeated key), so such an `npm run X` is referred whether
# or not the root defines X. Only npm: pnpm and yarn
# ignore those keys, and an explicit -w or --workspace is refused by npm when the last `workspaces`
# value is false, so that form is referred (see below). The file is read from
# the INDEX as data (never executed or expanded) and none of its text is ever printed: the detail
# names only the fixed key. Parsed as npm's ini does: a trailing CR is stripped, `;` and `#` lines
# skipped, the scan stops at a [section] header, the key is case-sensitive. Surrounding quotes on a
# value are stripped, so `workspaces="false"` and `'false'` read as false. An unquoted value is cut
# at the first `;` or `#` (an inline comment, #381), and a numeric zero (`0`, `00`, `-0`, `+0`, `0.0`,
# `.0`, `"0"`) reads as false, as npm 10.9.7 does (the issue's "true" premise was wrong). A key's
# surrounding quote pair is stripped before its `[]`, so `"workspace[]"` is a key. A tracked symlinked
# .npmrc is referred without being read, so a symlinked .npmrc holding `workspaces=false` with an
# explicit -w or --workspace form still passes. Limits: user and global .npmrc, NPM_CONFIG_USERCONFIG
# and a non-root .npmrc are never read (npm never reads a non-root .npmrc for a run from the root;
# the user and global files and NPM_CONFIG_USERCONFIG are outside the repository); safe-side
# referrals where npm would run the root or stop with an error: `workspaces=null`, `workspace []=x`
# and `workspace` with no root `workspaces` field, and `workspaces=undefined` (npm runs the root
# on a plain run). Not modelled, so an explicit -w form passes where npm refuses:
# `workspaces=0x0`, `0b0`, `0o0`, `0e0`, `0e5`, `undefined` and a value with whitespace inside
# quotes (`" false"`), which npm reads as false, and the key-side spellings `workspaces;x=false`
# and `workspaces #c=false`. `workspace#c=client` is a false fail (npm runs the client), and a
# space inside a quoted key is trimmed (`"workspace "=client`, `"workspaces "=true` refer, safe
# side) (#398). An empty value, or one empty after the comment cut, is truthy, as npm reads it,
# and the cut never runs inside a quoted value (`"false # c"` is a truthy string). An ARRAY-form key (`workspaces[]`, quoted, spaced around
# the `=` or valued 0 included) means workspaces on whatever its value and wherever it sits beside a
# scalar line, because npm's ini parser makes the key a list and a non-empty list is truthy (#395,
# measured on npm 10.9.4: a plain run goes to the client, an explicit -w run is not refused). So
# a plain run refers (`sets workspaces`) and an explicit -w run is judged by the manifest.
# `workspaces []=false` (a space before the brackets) is npm's key "workspaces " and leaves the
# key unset; it is read as the scalar, so a plain run still fails, as npm does, and an explicit -w
# run is referred where npm runs the client (safe side). The -w refusal and the last-value rule
# are verified on npm 10.9.7 and 10.9.4 only.
#
# Deliberate limits: code spans and links are found within one line; indented code blocks are
# prose; the paragraph rule is order-dependent ("Run `npm run dev` (after `cd client`)." judges dev
# from the root) and list items with no blank line between them are one paragraph; make's built-in
# implicit rules are not modelled, so `make foo` built from foo.c by no written rule fails; a
# percent-encoded non-ASCII link target is referred rather than decoded.
#
# A leading UTF-8 byte-order mark on line 1 of a doc is stripped before any fence, link or
# reference-definition rule reads it (#374), so a BOM-led doc is judged as if it had none. Without
# it a line-1 fence opener is read as prose and every later fence pairing inverts. Line 2 and later
# are never stripped. Like judge_target, the doc reader runs awk under LC_ALL=C (#406), so the octal
# strip matches bytes on every awk: BWK awk in a UTF-8 locale reads the BOM as one character and the
# regex literal never matched it. CI runs the suite under BWK awk in C.UTF-8 to keep it so.
#
# Needs git; jq only when a command reaches resolution against package.json (#295). Portable to
# bash 3.2 and BWK awk: no associative arrays, no mapfile, no ${x,,}, no readlink -f, and caller
# text reaches awk only through ENVIRON, since -v processes backslash escapes.
set -uo pipefail

die() { echo "check-contributor-docs: $1" >&2; exit 2; }
usage() { echo "usage: check-contributor-docs.sh [--docs <file>...] [--max-lines N] [--max-bytes N]" >&2; die "$1"; }

max_lines=150 max_bytes=32768 docs_set=0 docs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --docs)
      docs_set=1; shift
      while [ $# -gt 0 ]; do case "$1" in --*) break ;; *) docs+=("$1"); shift ;; esac; done ;;
    --max-lines) [ $# -ge 2 ] || usage "--max-lines needs a number"; max_lines=$2; shift 2 ;;
    --max-bytes) [ $# -ge 2 ] || usage "--max-bytes needs a number"; max_bytes=$2; shift 2 ;;
    *) usage "unknown argument '$1'" ;;
  esac
done
case "$max_lines" in ''|*[!0-9]*) usage "--max-lines must be a number" ;; esac
case "$max_bytes" in ''|*[!0-9]*) usage "--max-bytes must be a number" ;; esac

top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
prefix=$(git rev-parse --show-prefix 2>/dev/null) || die "not inside a git repository"
CDPATH= cd -- "$top" || die "cannot enter the repository root"
set -f

T=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$T"' EXIT
IDX=$T/index ROWS=$T/rows
: > "$ROWS"
# THE INDEX LOADER (#309). Read once, NUL-separated, so no file name can split a record. Each record
# is `<mode> <object> <stage><TAB><path>`, split at its FIRST TAB: an IFS read strips a leading TAB
# from the path and `awk -F'\t' $2` cuts at a second one, and either lets a file named
# `<TAB>CLAUDE.md` forge or shadow CLAUDE.md. Only stage 0 is kept, and a path holding any control
# byte (a TAB or a newline included) is dropped, so it reads as untracked. Two files result:
# `mode<TAB>path` ($IDXM, for safe_open) and the paths alone ($IDX, for everything else); with
# those paths dropped, a whole-line compare on either is exact.
IDXM=$T/indexm
git -c core.quotepath=off ls-files -s -z > "$T/index0" 2>/dev/null || die "git ls-files failed"
while IFS= read -r -d '' rec; do
  meta=${rec%%$'\t'*}; p=${rec#*$'\t'}   # safe_open: split
  [ "${meta##* }" = 0 ] || continue
  if (LC_ALL=C; [[ $p == *[[:cntrl:]]* ]]); then continue; fi
  printf '%s\t%s\n' "${meta%% *}" "$p"
done < "$T/index0" > "$IDXM"
awk '{ print substr($0, index($0, "\t") + 1) }' "$IDXM" > "$IDX"

# row: every field is sanitised (#309): under LC_ALL=C each control byte (0x00 to 0x1f, and 0x7f)
# becomes `?`, so a row stays one four-field line and no file name, link target or doc text can
# plant a row or a `::` workflow command in a CI log.
row() {
  local LC_ALL=C a=$1 b=$2 c=$3 d=$4
  a=${a//[[:cntrl:]]/?} b=${b//[[:cntrl:]]/?} c=${c//[[:cntrl:]]/?} d=${d//[[:cntrl:]]/?}   # row: sanitise
  printf '%s\t%s\t%s\t%s\n' "$a" "$b" "$c" "$d" >> "$ROWS"
}
tracked() { P=$1 awk '$0 == ENVIRON["P"] { f = 1; exit } END { exit !f }' "$IDX"; }
tracked_dir() { P=$1 awk 'index($0, ENVIRON["P"] "/") == 1 { f = 1; exit } END { exit !f }' "$IDX"; }

# normpath <dir> <target>: the repository-relative path, or return 1 when it leaves the repository.
# Pure string work; nothing on disk is consulted, so an escaping target is never opened.
normpath() {
  local path out="" p IFS=/
  case "$2" in /*) path=$2 ;; *) path=$1/$2 ;; esac
  for p in $path; do
    case "$p" in
      ''|.) ;;
      ..) [ -n "$out" ] || return 1
          case "$out" in */*) out=${out%/*} ;; *) out="" ;; esac ;;
      *) out=${out:+$out/}$p ;;
    esac
  done
  printf '%s' "$out"
}

# judge_path <path>: pass when tracked or a directory holding a tracked path. "" is the root.
judge_path() {
  [ -z "$1" ] && { [ -s "$IDX" ]; return; }
  tracked "$1" || tracked_dir "$1"
}

# idx_mode <path>: the index mode of exactly that path, or nothing. A whole-string compare after the
# first TAB, never a pathspec: `git ls-files -- docs` also matches docs/x.md, `C*.md` is a glob and
# `:(top)` is magic, so each would find a file the link does not name.
idx_mode() { P=$1 awk '{ i = index($0, "\t") } substr($0, i + 1) == ENVIRON["P"] { print substr($0, 1, i - 1); exit }' "$IDXM"; }   # safe_open: exact

# safe_open <path> <out> (#309): the ONE place a document, Makefile or justfile is read. On success
# its content is in <out> and SO_LINK holds the target of a safe symlink (empty otherwise); on a
# refusal nothing is read and SO_WHY says why. A tracked path is read as its INDEX blob, which cannot
# follow a link, reach a device or hang on /dev/zero (so an unstaged edit is not judged, as the
# header says). A tracked symlink is accepted only when its target, read from the index too, is a
# relative path that resolves from the link's own directory to a tracked REGULAR file: no chain, no
# absolute target, no escape, no directory, no submodule, no dangling name. An untracked path must
# be a regular file, not a symlink, whose physical directory lies inside the repository.
# safe_resolve <path> does the deciding and reads no content: on success SO_PATH is the tracked
# regular file to read from the index (the path itself, or a safe symlink's target), or empty for an
# untracked regular file read from disk. The import walk (#301) resolves through it too, so there
# is one definition of a safe symlink.
SO_WHY="" SO_LINK="" SO_PATH=""
safe_open() {
  safe_resolve "$1" || return 1
  if [ -n "$SO_PATH" ]; then git cat-file blob ":0:$SO_PATH" > "$2" 2>/dev/null || die "cannot read $SO_PATH from the index"
  else cat < "./$1" > "$2" 2>/dev/null || die "cannot read $1"; fi
}
safe_resolve() {
  local p=$1 mode tgt np tmode real
  SO_WHY="" SO_LINK="" SO_PATH=""
  mode=$(idx_mode "$p")
  case "$mode" in
    100644|100755) SO_PATH=$p; return 0 ;;
    160000) SO_WHY="a submodule, not a file"; return 1 ;;
    120000)
      tgt=$(git cat-file blob ":0:$p" 2>/dev/null; printf x) || die "cannot read $p from the index"; tgt=${tgt%x}
      if [ -z "$tgt" ]; then SO_WHY="an empty link"; return 1; fi
      if (LC_ALL=C; [[ $tgt == *[[:cntrl:]]* ]]); then SO_WHY="links to $tgt, which holds a control character"; return 1; fi
      case "$tgt" in /*) SO_WHY="links to $tgt, which is an absolute path a clone does not have"; return 1 ;; esac   # safe_open: absolute
      np=${p%/*}; [ "$np" = "$p" ] && np=""
      np=$(normpath "$np" "$tgt") || { SO_WHY="links to $tgt, which escapes the repository"; return 1; }
      tmode=$(idx_mode "$np")
      case "$tmode" in
        100644|100755) ;;
        120000) SO_WHY="links to $np, which is itself a symlink"; return 1 ;;   # safe_open: chain
        '') if [ -n "$np" ] && tracked_dir "$np"; then SO_WHY="links to $np, a directory, which is not a tracked file"
            elif [ -n "$np" ] && { [ -e "$np" ] || [ -L "$np" ]; }; then SO_WHY="links to $np, which is not tracked, so it is local only"
            else SO_WHY="links to ${np:-the repository root}, which is not tracked"; fi
            return 1 ;;
        *) SO_WHY="links to $np, which is not a tracked file"; return 1 ;;
      esac
      SO_LINK=$np SO_PATH=$np; return 0 ;;
  esac
  [ -L "$p" ] && { SO_WHY="an untracked symlink"; return 1; }
  { [ -e "$p" ] || [ -L "$p" ]; } || die "cannot read $p"
  [ -f "$p" ] || { SO_WHY="not a regular file"; return 1; }
  # The ./ and the -- keep a dash-led path (-foo/z.md) from reading as an option, and CDPATH= keeps
  # cd from resolving through, or echoing, the caller's CDPATH. An empty result refuses.
  real=$(CDPATH= cd -- "$(dirname -- "./$p")" 2>/dev/null && pwd -P)   # safe_open: dash
  [ -n "$real" ] || { SO_WHY="its directory cannot be resolved"; return 1; }
  if [ "$real" != "$top" ]; then
    case "$real" in "$top"/*) ;; *) SO_WHY="resolves outside the repository"; return 1 ;; esac   # safe_open: contain
  fi
}

# ---- check 1: required and published, and check 2: size ----
# A rejected AGENTS.md gets exactly one row, the required fail, and is never opened: no size row and
# no doc-loop read is built from it (agents_ok stays 0).
agents_ok=0 agents_link=""
if tracked AGENTS.md; then
  if git check-ignore -q --no-index AGENTS.md 2>/dev/null; then
    row fail required AGENTS.md "AGENTS.md is tracked but ignored; a fresh clone's tooling treats it as local"
  elif ! safe_open AGENTS.md "$T/agents"; then
    row fail required AGENTS.md "AGENTS.md $SO_WHY"
  elif [ -n "$SO_LINK" ]; then
    row pass required AGENTS.md "AGENTS.md is tracked (symlink to tracked $SO_LINK)"; agents_ok=1 agents_link=$SO_LINK
  else
    row pass required AGENTS.md "AGENTS.md is tracked"; agents_ok=1
  fi
elif [ -e AGENTS.md ] || [ -L AGENTS.md ]; then
  row fail required AGENTS.md "AGENTS.md exists but is not tracked, so nobody else has it"
  safe_open AGENTS.md "$T/agents" && agents_ok=1
else
  row fail required AGENTS.md "AGENTS.md is missing"
fi
if [ "$agents_ok" = 1 ]; then   # safe_open: size
  n=$(wc -l < "$T/agents" | tr -d ' ') b=$(wc -c < "$T/agents" | tr -d ' ')
  if [ "$n" -le "$max_lines" ]; then row pass max-lines AGENTS.md "$n lines, budget $max_lines"
  else row fail max-lines AGENTS.md "$n lines exceeds the budget of $max_lines"; fi
  if [ "$b" -le "$max_bytes" ]; then row pass max-bytes AGENTS.md "$b bytes, budget $max_bytes"
  else row fail max-bytes AGENTS.md "$b bytes exceeds the budget of $max_bytes"; fi
fi

# ---- the doc set ----
if [ "$docs_set" = 0 ]; then
  tracked AGENTS.md && [ "$agents_ok" = 1 ] && docs+=(AGENTS.md)
  while IFS= read -r d; do docs+=("$d"); done < <(awk '
    { l = tolower($0) }
    l == "contributing.md" || l == ".github/contributing.md" || l == "docs/contributing.md" { print; next }
    l ~ /^(docs\/|\.github\/)?pull_request_template(\.md|\.txt)?$/ { print; next }
    l ~ /^(docs\/|\.github\/)?pull_request_template\/[^\/]+\.(md|txt)$/ { print }' "$IDX")
fi

is_template() {
  local l
  l=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$l" in
    pull_request_template|pull_request_template.md|pull_request_template.txt) return 0 ;;
    docs/pull_request_template|docs/pull_request_template.md|docs/pull_request_template.txt) return 0 ;;
    .github/pull_request_template|.github/pull_request_template.md|.github/pull_request_template.txt) return 0 ;;
    pull_request_template/*|docs/pull_request_template/*|.github/pull_request_template/*) return 0 ;;
  esac
  return 1
}

# One pass per doc. Emits `C<TAB>line<TAB>cdflag<TAB>segment` for each command-shaped segment of a
# code span or fenced line, and `L<TAB>line<TAB>target<TAB>flag` for each relative link target,
# already stripped of its anchor and query and percent-decoded.
EXTRACT='
NR == 1 { sub(/^\357\273\277/, "") }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function code(text, infence,    n, i, j, k, nw, ws, segs, seg, w, env, carry, isx, unx, hit, unexp, q, qs, nq) {
  # A command substitution in an assignment VALUE rescopes npm like any other value
  # (npm_config_workspace=$(echo client) npm run dev, #296), but the split below would cut it at
  # its parentheses and leave a bare runner. Rewrite the value of a NAME=value WORD to X when it
  # holds one or more $(...) groups whose parentheses do not nest, with optional literal text
  # before, between and after them (pre$(a), $(a)$(b), #346), so the assignment strip sets env.
  # A value holding a SPACE is the same problem (#386): a double- or single-quoted run, a
  # backslash-escaped byte or a backtick run can carry one, and the split and the strip below cut at
  # it, so `FOO="a b" npm run nope` lost its runner and gave no row at all, and `FOO="a b" cd x`
  # hid the cd from the next line. So the whole value, any mix of plain bytes, non-nested $(...)
  # groups, quoted runs, backtick runs and escaped bytes, becomes X. A `;&|()` inside a quoted run
  # is inside the X too. An UNBALANCED quote matches no run, so the value stops at it and the line
  # is read as before (a stated limit, pinned by a case).
  # THE RUNS ARE PAIRED FIRST, left to right as the shell pairs them (#386 review round 1): every
  # balanced quoted run, backtick run and escaped byte is wrapped in \002...\003, and a value may
  # take a run only through its opening \002. A word-start NAME= INSIDE a quoted argument
  # (`git commit -m "set retries=3" && npm run nope && echo "x"`) is still marked, but its value
  # cannot reach past the closing quote of that argument, which carries no \002; reading that quote as
  # the opener of a new run swallowed `&& npm run nope && echo ` into X and silenced a broken command.
  # ONE left-to-right pass per step, linear in the line: the wrap, a marker byte (\001) after each
  # word-start NAME=, each marked value to X, then every marker byte (any real one removed first)
  # goes. A restart-from-the-front loop is quadratic on a hostile line. Anchored at the start of a
  # word, so --workspace=$(...) is left alone. A $( anywhere else rescopes nothing and stays judged.
  # The quote is \047 because this program sits inside a single-quoted shell variable.
  if (index(text, "=")) {
    gsub(/[\001\002\003]/, "", text)
    gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047|`[^`]*`|\\./, "\002&\003", text)
    # A leading space stands in for the start of the line: `(^|[ \t;&|(])` sends gawk in a UTF-8
    # locale to its slow matcher, quadratic on one long word (400k bytes took 9 s, now 0.04 s).
    text = " " text; gsub(/[ \t;&|(][A-Za-z_][A-Za-z0-9_]*=/, "&\001", text); text = substr(text, 2)
    gsub(/\001([^ \t;&|()$"\047`\\\001\002\003]|\$\([^()]*\)|\002[^\003]*\003)+/, "X", text)
    gsub(/[\001\002\003]/, "", text)
  }
  gsub(/&&|\|\||[;|()]/, "\n", text)
  n = split(text, segs, "\n")
  for (i = 1; i <= n; i++) {
    seg = trim(segs[i])
    sub(/^\$[ \t]+/, "", seg)
    # A backtick in a fence is a literal character: strip a leading run so the runner is still
    # seen, and the one left on the name makes it non-literal, hence referred (#295).
    if (infence) sub(/^`+/, "", seg)
    # An assignment in front can rescope the run (npm_config_workspace=client), so it refers the
    # row as a directory change does. The flag is 1 for a cd, 2 for an assignment, 3 for both.
    env = 0
    # One match, not a loop: a loop copies the segment once per leading word, quadratic (#346).
    if (match(seg, /^([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)+/)) { seg = substr(seg, RLENGTH + 1); env = 1 }
    w = seg; sub(/[ \t].*/, "", w)
    # An exported npm_config_ variable (any case, any key, an empty value too) rescopes every later
    # npm in the same fence or paragraph, so it is carried like a cd and applied from the NEXT
    # segment on, never to an earlier one (#296). export, declare -x and typeset -x set it, and so
    # do the spellings #346 added: any leading dash word holding an x (-gx, or -g -x), a quoted
    # name ("npm_config_x=y"), and a bare name (npm_config_x, which exports an earlier assignment).
    # The quote class is \047 because this program sits inside a single-quoted shell variable.
    nw = split(seg, ws, /[ \t]+/)
    # A leading option word starting with + and holding an x (declare +x, in either order with -x)
    # un-exports the line, as bash does (#387).
    isx = (w == "export"); unx = 0
    if (w == "declare" || w == "typeset") for (j = 2; j <= nw && ws[j] ~ /^[-+]/; j++) { if (ws[j] ~ /^-[A-Za-z]*x/) isx = 1; if (ws[j] ~ /^[+][A-Za-z]*x/) unx = 1 }
    if (unx) isx = 0
    if (isx) {
      # Three guards keep an npm_config_ match honest, each applied only to a word OUTSIDE any
      # quote: a word starting with # ends the command (a comment), a word inside a quoted value is
      # not a name, and under export (only: for declare, -n means nameref and the line still
      # exports) a dash word holding an n anywhere on the line un-exports it. The quotes are PARSED
      # (#387), linearly: a quoted npm_config_ word keeps its name; then every balanced double- or
      # single-quoted run and escaped byte becomes Q (one gsub, paired left to right, two kinds, a
      # backslash outside single quotes escaping the next byte), so `export "a # b" ...` is one
      # word; then an UNBALANCED quote cuts the rest, which sits inside a quoted value. A
      # per-character loop was quadratic on a hostile export line on BWK, busybox and gawk in a
      # UTF-8 locale (#387 review round 1); the old guards counted quote characters of either kind.
      q = seg
      gsub(/["\047][Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*(=[^"\047]*)?["\047]/, "npm_config_q=X", q)
      gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047|\\./, "Q", q)
      if (match(q, /["\047]/)) q = substr(q, 1, RSTART - 1)
      nq = split(q, qs, /[ \t]+/)
      hit = 0; unexp = 0
      for (j = 2; j <= nq; j++) {
        if (qs[j] ~ /^#/) break
        if (w == "export" && qs[j] ~ /^-[A-Za-z]*n/) unexp = 1
        if (qs[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*(=|$)/) hit = 1
      }
      if (hit && !unexp) { if (infence) fenv = 1; else penv = 1 }
      continue
    }
    carry = infence ? fenv : penv
    # Only the package managers that read npm_config_ are rescoped by it; make and just are not,
    # and carrying it there would mask a failing target (#346).
    if (w != "npm" && w != "pnpm" && w != "yarn") carry = 0
    if (w == "cd" || w == "pushd") { if (infence) fcd = 1; else pcd = 1; continue }
    if (w == "npm" || w == "pnpm" || w == "yarn" || w == "make" || w == "just" || w == "node" || w == "sh" || w == "bash")
      printf "C\t%d\t%d\t%s\n", NR, (infence ? fcd : pcd) + 2 * (env || carry), seg
  }
}
function pdec(s,    out, i, h, v) {
  out = ""
  while ((i = index(s, "%")) > 0) {
    h = tolower(substr(s, i + 1, 2))
    if (h ~ /^[0-9a-f][0-9a-f]$/) {
      v = 16 * (index(HEX, substr(h, 1, 1)) - 1) + index(HEX, substr(h, 2, 1)) - 1
      if (v >= 32 && v < 127) { out = out substr(s, 1, i - 1) sprintf("%c", v); s = substr(s, i + 3); continue }
      if (v >= 128) nonascii = 1
    }
    out = out substr(s, 1, i); s = substr(s, i + 1)
  }
  return out s
}
function target(s,    j, c, depth) {
  sub(/^[ \t]+/, "", s)
  if (substr(s, 1, 1) == "<") { j = index(s, ">"); return j ? substr(s, 2, j - 2) : "" }
  depth = 0
  for (j = 1; j <= length(s); j++) {
    c = substr(s, j, 1)
    if (c == " " || c == "\t") break
    if (c == "(") depth++
    else if (c == ")") { if (depth == 0) break; depth-- }
  }
  return substr(s, 1, j - 1)
}
function link(t,    i) {
  if (t == "" || t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ || substr(t, 1, 2) == "//" || substr(t, 1, 1) == "#") return
  i = index(t, "#"); if (i) t = substr(t, 1, i - 1)
  i = index(t, "?"); if (i) t = substr(t, 1, i - 1)
  if (t == "") return
  nonascii = 0; t = pdec(t)
  printf "L\t%d\t%s\t%s\n", NR, t, (nonascii ? "nonascii" : "-")
}
# Code spans on one line: an opening run of N backticks closes at the next run of exactly N. Their
# contents go to code(); the returned line has each span blanked, so a link in a span is no link.
function spans(s,    out, i, n, rest, pos, j, m, found) {
  out = ""
  while ((i = index(s, "`")) > 0) {
    out = out substr(s, 1, i - 1)
    n = 0; while (substr(s, i + n, 1) == "`") n++
    rest = substr(s, i + n); pos = 1; found = 0
    while ((j = index(substr(rest, pos), "`")) > 0) {
      j = pos + j - 1
      m = 0; while (substr(rest, j + m, 1) == "`") m++
      if (m == n) { found = 1; break }
      pos = j + m
    }
    if (!found) { out = out substr(s, i, n); s = rest; continue }
    code(substr(rest, 1, j - 1), 0)
    out = out " "; s = substr(rest, j + m)
  }
  return out s
}
# imports(s): one `I<TAB>line<TAB>target<TAB>-` record per @-import token in a line whose spans are
# already blanked and that sits outside a fence (#301). A token is a whitespace-delimited word whose
# FIRST character is @ (so user@host and (@x.md) are not imports), an escaped space stays inside
# it, and it is a path candidate only when what follows the @ holds a / or a . (so @maintainer is
# prose). Trailing punctuation is KEPT: Claude Code 2.1.287 loads nothing for `@x.md.`.
# The fourth field is `own` when the token is the whole line once trimmed, the form harness-copy
# credits (#300), and `-` otherwise.
function imports(s,    n, i, w, ws, k) {
  gsub(/\\ /, "\001", s)
  n = split(s, ws, /[ \t]+/)
  k = 0; for (i = 1; i <= n; i++) if (ws[i] != "") k++
  for (i = 1; i <= n; i++) {
    w = ws[i]
    if (substr(w, 1, 1) != "@") continue   # import: token start
    w = substr(w, 2); gsub(/\001/, " ", w)
    if (index(w, "/") == 0 && index(w, ".") == 0) continue   # import: path candidate
    printf "I\t%d\t%s\t%s\n", NR, w, (k == 1 ? "own" : "-")
  }
}
# uncomment(s): s without its block HTML comments (#408). Nothing inside a comment is an import, a
# link or a command, since GitHub hides it and Claude Code 2.1.287 strips it before reading
# imports; an unclosed `<!--` sets `incomment` and the comment runs on to the next `-->`. A `<!--`
# after an odd number of backticks sits in a code span and opens nothing (a stated limit: a span
# delimited by a run of two backticks is not told apart).
function uncomment(s,    out, i, j, pre, bt) {
  out = ""; bt = 0
  while ((i = index(s, "<!--")) > 0) {
    pre = substr(s, 1, i - 1); bt += gsub(/`/, "`", pre)
    if (bt % 2) { out = out substr(s, 1, i + 3); s = substr(s, i + 4); continue }   # html comment: span
    j = index(substr(s, i + 4), "-->")
    if (!j) { incomment = 1; return out pre }
    out = out pre " "; s = substr(s, i + 4 + j + 2)
  }
  return out s
}
BEGIN { HEX = "0123456789abcdef"; infence = 0; pcd = 0; penv = 0; fenv = 0; incomment = 0 }
{ sub(/\r$/, "") }
# A comment is tested BEFORE fences and spans: a fence line inside an open comment opens no fence,
# and a comment opened inside a fence is fence text.
{
  if (incomment) { k = index($0, "-->"); if (!k) next; $0 = substr($0, k + 3); incomment = 0 }   # html comment: close
  if (!infence) $0 = uncomment($0)
}
{
  line = $0; lead = line; sub(/^ ? ? ?/, "", lead)
  c3 = substr(lead, 1, 3)
  if (infence) {
    if (substr(lead, 1, 1) == fch) {
      n = 0; while (substr(lead, n + 1, 1) == fch) n++
      if (n >= flen && trim(substr(lead, n + 1)) == "") { infence = 0; pcd = 0; penv = 0; next }
    }
    code(line, 1); next
  }
  if (c3 == "```" || c3 == "~~~") {
    fch = substr(c3, 1, 1); flen = 0; while (substr(lead, flen + 1, 1) == fch) flen++
    infence = 1; fcd = 0; fenv = 0; pcd = 0; penv = 0; next
  }
  if (trim(line) == "") { pcd = 0; penv = 0; next }
  rest = spans(line)
  if (ENVIRON["IMPORTS"] == 1) imports(rest)
  if (substr(lead, 1, 1) == "[" && substr(lead, 2, 1) != "^" && (k = index(lead, "]:")) > 2) {
    label = substr(lead, 2, k - 2)
    if (index(label, "[") == 0 && index(label, "]") == 0) { link(target(substr(lead, k + 2))); next }
  }
  while ((i = index(rest, "](")) > 0) { rest = substr(rest, i + 2); link(target(rest)) }
}'

MAKE_AWK='
NR == 1 { sub(/^\357\273\277/, "") }
{ sub(/\r$/, "") }
/^\t/ { next }
/^[ \t]*(-?include|sinclude)[ \t]/ { unsettled = 1; next }
{
  line = $0; sub(/[ \t]*#.*/, "", line)
  k = index(line, ":"); if (!k) next
  if (substr(line, k + 1, 1) == "=") next
  pre = substr(line, 1, k - 1)
  if (index(pre, "=")) next
  if (index(pre, "%") || index(pre, "$")) { unsettled = 1; next }
  n = split(pre, t, /[ \t]+/)
  for (i = 1; i <= n; i++) if (t[i] == ENVIRON["TGT"]) found = 1
}
END { print (found ? "found" : (unsettled ? "unsettled" : "absent")) }'

JUST_AWK='
NR == 1 { sub(/^\357\273\277/, "") }
{ sub(/\r$/, "") }
/^[ \t]/ { next }
/^(import|mod)[ \t?]/ || /^set[ \t]+fallback/ { unsettled = 1; next }
/^alias[ \t]/ { l = $0; sub(/^alias[ \t]+/, "", l); sub(/[ \t]*:=.*/, "", l); if (l == ENVIRON["TGT"]) found = 1; next }
{
  k = index($0, ":"); if (!k || substr($0, k + 1, 1) == "=") next
  pre = substr($0, 1, k - 1)
  if (pre ~ /^[#\[]/) next
  w = pre; sub(/[ \t].*/, "", w); sub(/^@/, "", w)
  if (w == ENVIRON["TGT"]) found = 1
}
END { print (found ? "found" : (unsettled ? "unsettled" : "absent")) }'

# Checked once, and only when a command reaches resolution (#295). The INDEX blob is read, not the
# working tree, so the scripts judged are the ones a clone gets.
pkg_ok=""
resolve_script() {
  if [ -z "$pkg_ok" ]; then
    command -v jq >/dev/null 2>&1 || die "jq is required to resolve '$1' against package.json"
    git show :package.json > "$T/package.json" 2>/dev/null || die "cannot read package.json from the index"
    jq -e 'type == "object" and ((.scripts // {}) | type == "object")' "$T/package.json" >/dev/null 2>&1 \
      || die "package.json is malformed"
    pkg_ok=1
  fi
  NAME=$1 jq -e '(.scripts // {}) | has(env.NAME)' "$T/package.json" >/dev/null 2>&1
}

# Workspace resolution (#299). The match is by `name` among tracked manifests, read from the INDEX.
# The table is built on first use, into <manifest path><TAB><name>, and only when a non-root
# manifest exists, so jq is still needed only when a command reaches resolution. It is called
# DIRECTLY, never through $(...): die is exit 2 and would end a subshell alone. Results come back in
# WS_STATE (defined, undefined, unreadable, nomatch or ambiguous), WS_PATH and WS_COUNT.
# A candidate is a file named exactly package.json, outside node_modules, not the root (a workspace
# form never reads the root), with no TAB in its path. `@tsv` escapes a TAB, a newline and a
# backslash in a manifest-side name, so a name cannot forge a second row.
ws_built="" WS_STATE="" WS_PATH="" WS_COUNT=0
build_ws_table() {
  local p nm
  awk '
    $0 == "package.json" { next }
    index($0, "\t") { next }
    $0 !~ /(^|\/)node_modules\// && $0 ~ /(^|\/)package\.json$/ { print }' "$IDX" > "$T/wscand"
  : > "$T/wstable"
  if [ -s "$T/wscand" ]; then
    command -v jq >/dev/null 2>&1 || die "jq is required to resolve workspace '$1' against package.json"
    while IFS= read -r p; do
      nm=$(git show ":0:$p" 2>/dev/null | jq -r 'select(type=="object" and ((.scripts // {}) | type=="object")) | select(.name|type=="string") | [.name] | @tsv' 2>/dev/null)
      [ -n "$nm" ] && printf '%s\t%s\n' "$p" "$nm" >> "$T/wstable"
    done < "$T/wscand"
  fi
  ws_built=1
}
resolve_workspace() {   # <name> <script>
  local res
  [ -n "$ws_built" ] || build_ws_table "$1"
  res=$(WS=$1 awk -F'\t' '$2 == ENVIRON["WS"] { c++; p = $1 } END { print c + 0; print p }' "$T/wstable")
  WS_COUNT=${res%%$'\n'*}; WS_PATH=${res#*$'\n'}
  case "$WS_COUNT" in
    0) WS_STATE=nomatch; WS_PATH=""; return ;;
    1) ;;
    *) WS_STATE=ambiguous; return ;;
  esac
  # exit 0 defined, 1 undefined, anything else (jq exits 5 on a non-object scripts) is never a fail
  git show ":0:$WS_PATH" 2>/dev/null | NAME=$2 jq -e '(.scripts // {}) | has(env.NAME)' >/dev/null 2>&1
  case $? in 0) WS_STATE=defined ;; 1) WS_STATE=undefined ;; *) WS_STATE=unreadable ;; esac
}

# why_cd <flag>: what precedes a command whose flag is not 0.
why_cd() { if [ "$1" = 2 ]; then printf 'an environment assignment precedes it'; else printf 'a directory change precedes it'; fi; }

# trim_punct <word>: the word without its trailing punctuation, in the global TP (#326). It is the
# one definition of the punctuation class, so a change to the set cannot miss a copy. Like
# resolve_workspace it is called DIRECTLY, never through $(...), and a caller copies TP out at once.
# A script name that trims to nothing (`npm run .`) keeps its raw word at the three name sites, so the
# row is never malformed (#353): `[ -n "$TP" ] && name=$TP`.
TP=""
trim_punct() { TP=$1; while :; do case "$TP" in *[.,\;:!?]) TP=${TP%?} ;; *) break ;; esac; done; }

# first_file <candidates...>: the first one that is tracked.
first_file() { local f; for f in "$@"; do tracked "$f" && { printf '%s' "$f"; return 0; }; done; return 1; }

# npmrc_scan: sets NPMRC_KEY to `workspace`, `workspaces`, `symlink` or empty, and NPMRC_LAST to
# `wsfalse` when the LAST `workspaces` value is exactly `false`, once (#339, #357). Called DIRECTLY,
# never through $(...), so the memo survives. The awk prints only fixed literals, never file text,
# and its stderr is discarded, so no .npmrc content can reach either stream. A symlinked .npmrc is
# detected from the index mode and never read or followed: the link target could be a user's
# ~/.npmrc holding a token, so the checker resolves nothing from disk and refers.
# npm takes the LAST value of a repeated key (verified on npm 10.9.7 only), so the awk records
# whether any `workspace` key exists and the last `workspaces` value, and judges them in END.
NPMRC_DONE="" NPMRC_KEY="" NPMRC_LAST="" NPMRC_MODE=""
npmrc_scan() {
  [ -n "$NPMRC_DONE" ] && return
  NPMRC_DONE=1
  tracked .npmrc || return
  NPMRC_MODE=$(git ls-files -s -- .npmrc 2>/dev/null); NPMRC_MODE=${NPMRC_MODE%% *}
  if [ "$NPMRC_MODE" = 120000 ]; then NPMRC_KEY=symlink; return; fi
  local out
  # npm splits on a lone CR too and trims a leading byte-order mark, and only a `[` that starts the
  # line opens a section, so the header test runs before the indentation trim (#339 review M1).
  out=$(git show :.npmrc 2>/dev/null | tr '\r' '\n' | LC_ALL=C awk '
    NR == 1 { sub(/^\357\273\277/, "") }
    /^\[[^]]*\][ \t]*$/ { exit }
    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    $0 == "" || /^[;#]/ { next }
    {
      eq = index($0, "="); key = eq ? substr($0, 1, eq - 1) : $0; val = eq ? substr($0, eq + 1) : ""
      sub(/[ \t]+$/, "", key); kn = length(key); kc = substr(key, 1, 1)
      if (kn > 1 && (kc == "\"" || kc == "\047") && substr(key, kn, 1) == kc) key = substr(key, 2, kn - 2)
      if (key == "workspaces[]") wsarr = 1
      sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)
      sub(/^[ \t]+/, "", val); n = length(val); c = substr(val, 1, 1)
      if (n > 1 && (c == "\"" || c == "\047") && substr(val, n, 1) == c) val = substr(val, 2, n - 2)
      else if (match(val, /[;#]/)) { val = substr(val, 1, RSTART - 1); sub(/[ \t]+$/, "", val) }
      if (val ~ /^[-+]?(0+\.?0*|\.0+)$/) val = "false"
      if (key == "workspace") hasws = 1
      if (key == "workspaces") { last = val; seen = 1 }
      if (wsarr) { last = "true"; seen = 1 }
    }
    END { print (hasws ? "workspace" : seen && last != "false" ? "workspaces" : "none"), (seen && last == "false" ? "wsfalse" : "-") }' 2>/dev/null)
  read -r NPMRC_KEY NPMRC_LAST <<<"$out"
  [ "$NPMRC_KEY" = none ] && NPMRC_KEY=""
}

# is_run <word>: is it the run verb or its alias run-script (#363). Exact words only, so run-scripts
# and the aliases rum and urn stay unjudged. Used by the workspace arms and the flag-between loop.
is_run() { [ "$1" = run ] || [ "$1" = run-script ]; }

judge_pm() {   # <loc> <cd> <pm> <args...>
  local loc=$1 cd=$2 pm=$3 w name="" flag="" extra wsv="" wsn=0 v=run skip=0
  shift 3
  if [ $# -eq 0 ]; then return; fi
  case "$1" in
    run|run-script) v=$1; shift ;;   # the doc's own verb is printed in every row (#353)
    -*) # The six workspace spellings, each with `run` or `run-script` straight after the value (#299, #363).
        case "$pm:$1" in
          npm:-w|npm:--workspace|pnpm:--filter|pnpm:-F) [ $# -ge 3 ] && is_run "$3" && { wsv=$2; wsn=3; } ;;
          npm:--workspace=*) [ $# -ge 2 ] && is_run "$2" && { wsv=${1#--workspace=}; wsn=2; } ;;
          pnpm:--filter=*) [ $# -ge 2 ] && is_run "$2" && { wsv=${1#--filter=}; wsn=2; } ;;
        esac
        if [ "$wsn" != 0 ]; then judge_ws "$loc" "$cd" "$pm $*" "$pm" "$wsv" "${@:$((wsn + 1))}"; return; fi
        # The flag prefix ends at the first word that is neither a flag nor a flag's value (#390): a
        # run or run-script after it (`npm -g install run`) is an argument, not the verb, and a
        # flag's VALUE (`npm --prefix run-script run build`) is never the verb either. Exactly
        # these eight take a value (npm -C is --prefix's alias, #390 review); every other dash word is read as a boolean, as npm 10.9.7 reads
        # an unknown --flag and pnpm 10.33.3 refuses one, so `npm --loglevel verbose run x` ends
        # the search at `verbose` (silent, never a fail). Words are compared to literals only.
        for w in "$@"; do
          if [ "$skip" = 1 ]; then skip=0; continue; fi
          is_run "$w" && { row referred command "$loc" "$pm $*: a flag between $pm and $w may change which script runs"; return; }
          case "$pm:$w" in
            npm:-w|npm:--workspace|npm:--prefix|npm:-C|pnpm:--filter|pnpm:-F|pnpm:-C|pnpm:--dir) skip=1 ;;
            *:-*) ;;
            *) break ;;
          esac
        done
        # pnpm runs a bare word as a script, so `pnpm -r build` may be one; npm never does.
        [ "$pm" = pnpm ] && for w in "$@"; do case "$w" in -*) ;; *) row referred command "$loc" "pnpm $*: may be a script, a built-in or a binary"; return ;; esac; done
        return ;;
    # Only this arm trims: `case "$1"` stays on the raw word, so `run.` is never trimmed into `run)`
    # and `npm run. build` cannot become a false pass (#326). The rows print the raw word.
    *) trim_punct "$1"; w=$TP
       case "$w" in
         test|start|t|tst) row referred command "$loc" "$pm $1: runs a lifecycle script; not checked"; return ;;
       esac
       [ "$pm" = pnpm ] || return
       case "$w" in
         install|i|add|remove|rm|update|up|exec|dlx|create|init|store|audit|outdated|list|ls|why|link|unlink|publish|pack|prune|rebuild|import|fetch|env|setup|config|patch|patch-commit|deploy|licenses|server|root|bin|help|approve-builds|self-update|dedupe) return ;;
       esac
       row referred command "$loc" "pnpm $1: may be a script, a built-in or a binary"; return ;;
  esac
  for w in "$@"; do
    [ "$w" = -- ] && break
    case "$w" in
      '#'*|'\') break ;;
      --silent|-s) ;;
      -*) flag=$w; break ;;
      *) [ -z "$name" ] && name=$w ;;
    esac
  done
  [ -n "$flag" ] && { row referred command "$loc" "$pm $v ${name:-...}: $flag may change which script runs"; return; }
  [ -z "$name" ] && return
  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  local re='^[A-Za-z0-9][A-Za-z0-9:_.-]*$'
  [[ $name =~ $re ]] || { row referred command "$loc" "$pm $v $name: not a literal script name"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$pm $v $name: $(why_cd "$cd")"; return; }
  if [ "$pm" = npm ]; then
    npmrc_scan
    [ "$NPMRC_KEY" = symlink ] && { row referred command "$loc" "npm $v $name: a tracked .npmrc is a symlink"; return; }
    [ -n "$NPMRC_KEY" ] && { row referred command "$loc" "npm $v $name: a tracked .npmrc sets $NPMRC_KEY"; return; }
  fi
  tracked package.json || { row referred command "$loc" "$pm $v $name: no root package.json is tracked"; return; }
  if resolve_script "$name"; then row pass command "$loc" "$pm $v $name: defined in package.json"
  else row fail command "$loc" "$pm $v $name: no such script in package.json"; fi
}

# scan_script <silent-ok> <args...>: the first non-flag word is the script; a `-` flag before `--`
# (past the script name too) is SC_FLAG. --silent and -s are exempt only for npm and pnpm.
scan_script() {
  local ok=$1 w
  shift
  SC_NAME="" SC_FLAG=""
  for w in "$@"; do
    [ "$w" = -- ] && break
    case "$w" in
      '#'*|'\') break ;;
      --silent|-s) [ "$ok" = 1 ] || { SC_FLAG=$w; break; } ;;
      -*) SC_FLAG=$w; break ;;
      *) [ -z "$SC_NAME" ] && SC_NAME=$w ;;
    esac
  done
}

# judge_ws <loc> <cd> <label> <pm> <workspace> <args from the script name on...> (#299)
# npm and pnpm error on a missing script, so `undefined` fails there; yarn falls through to a
# binary, so it is referred. A workspace name is NEVER punctuation-trimmed: it is matched whole.
judge_ws() {
  local loc=$1 cd=$2 lab=$3 pm=$4 ws=$5 name
  shift 5
  local wre='^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*$'
  local sre='^[A-Za-z0-9][A-Za-z0-9:_.-]*$'
  [[ $ws =~ $wre ]] || { row referred command "$loc" "$lab: not a literal package name"; return; }
  # a pnpm filter ending in `...` selects dependencies, and the regex above allows dots
  [ "$pm" = pnpm ] && case "$ws" in *...*) row referred command "$loc" "$lab: not a literal package name"; return ;; esac
  if [ "$pm" = yarn ]; then scan_script 0 "$@"; else scan_script 1 "$@"; fi
  [ -n "$SC_FLAG" ] && { row referred command "$loc" "$lab: $SC_FLAG may change which script runs"; return; }
  name=$SC_NAME
  [ -z "$name" ] && return
  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: $name is not a literal script name"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }
  if [ "$pm" = npm ]; then npmrc_scan; [ "$NPMRC_LAST" = wsfalse ] && { row referred command "$loc" "$lab: a tracked .npmrc sets workspaces=false"; return; }; fi
  resolve_workspace "$ws" "$name"
  case "$WS_STATE" in
    defined) row pass command "$loc" "$lab: $name is defined in $WS_PATH" ;;
    undefined)
      if [ "$pm" = yarn ]; then
        row referred command "$loc" "$lab: workspace $ws ($WS_PATH) does not define $name; yarn may run a binary"
      else
        row fail command "$loc" "$lab: $name is not a script of $ws ($WS_PATH)"
      fi ;;
    unreadable) row referred command "$loc" "$lab: could not read the scripts of workspace $ws ($WS_PATH)" ;;
    ambiguous) row referred command "$loc" "$lab: $WS_COUNT tracked manifests are named $ws" ;;
    *) row referred command "$loc" "$lab: no tracked manifest is named $ws" ;;
  esac
}

# judge_yarn_root <loc> <cd> <prefix: yarn or yarn run> <args from the script name on...>. Yarn never
# fails: an undefined script may be a node_modules/.bin binary, which yarn runs.
judge_yarn_root() {
  local loc=$1 cd=$2 lab=$3 name
  shift 3
  local sre='^[A-Za-z0-9][A-Za-z0-9:_.-]*$'
  scan_script 0 "$@"
  [ -n "$SC_FLAG" ] && { row referred command "$loc" "$lab ${SC_NAME:-...}: $SC_FLAG may change which script runs"; return; }
  name=$SC_NAME
  [ -z "$name" ] && return
  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab $name: not a literal script name"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$lab $name: $(why_cd "$cd")"; return; }
  tracked package.json || { row referred command "$loc" "$lab $name: no root package.json is tracked"; return; }
  if resolve_script "$name"; then row pass command "$loc" "$lab $name: defined in package.json"
  else row referred command "$loc" "$lab $name: not defined in package.json; yarn may run a node_modules/.bin binary of that name"; fi
}

# yarn_builtin <name>: 0 when a bare `yarn <name>` is a built-in the check stays silent on, 1 when it
# is a Yarn Classic built-in that shadows a script of that name under yarn 1 (so it is referred even
# when the root defines it), 2 otherwise. Both lists apply to the BARE form only.
yarn_builtin() {
  case "$1" in
    check|licenses|owner|tag|team|policies|autoclean|help|versions|import|prune|generate-lock-entry|upgrade-interactive) return 1 ;;
    install|add|remove|upgrade|up|init|dlx|exec|set|config|workspaces|workspace|why|info|cache|global|link|unlink|pack|publish|npm|plugin|version|audit|outdated|list|bin|create|login|logout|constraints|dedupe|node|patch|rebuild|explain|unplug|stage|patch-commit|search) return 0 ;;
  esac
  return 2
}

judge_yarn() {   # <loc> <cd> <args...>
  local loc=$1 cd=$2 w lab ws b b1
  shift 2
  lab="yarn $*"
  [ $# -eq 0 ] && return
  case "$1" in
    run) [ $# -ge 2 ] || return; shift; judge_yarn_root "$loc" "$cd" "yarn run" "$@"; return ;;
    workspace)
      shift; [ $# -ge 2 ] || return
      ws=$1; shift
      if [ "$1" = run ]; then shift; [ $# -ge 1 ] || return
      else
        trim_punct "$1"; b1=$TP   # `yarn check.` is still the built-in
        yarn_builtin "$b1"; b=$?
        [ "$b" = 0 ] && return
        [ "$b" = 1 ] && { row referred command "$loc" "$lab: $b1 may be a yarn built-in"; return; }
      fi
      judge_ws "$loc" "$cd" "$lab" yarn "$ws" "$@"; return ;;
    -*) for w in "$@"; do case "$w" in -*) ;; *) row referred command "$loc" "yarn $*: may be a script, a built-in or a binary"; return ;; esac; done
        return ;;
  esac
  trim_punct "$1"; b1=$TP   # trailing punctuation never hides a built-in
  yarn_builtin "$b1"; b=$?
  [ "$b" = 0 ] && return
  [ "$b" = 1 ] && { row referred command "$loc" "yarn $1: may be a yarn built-in, which shadows a script of that name under yarn 1"; return; }
  judge_yarn_root "$loc" "$cd" yarn "$@"
}

judge_target() {   # <loc> <tool> <awk> <files...> ; the target is in $TGT
  local loc=$1 tool=$2 prog=$3 f verdict
  shift 3
  f=$(first_file "$@") || { row referred command "$loc" "$tool $TGT: no tracked $1 to read"; return; }
  safe_open "$f" "$T/mk" || { row fail command "$loc" "$f is an unsafe link ($SO_WHY), not read"; return; }   # safe_open: make
  # An awk failure is exit 2 (could not run), never a `no such target` row built from nothing.
  verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk") || die "could not read $f"   # safe_open: awk
  case "$verdict" in
    found) row pass command "$loc" "$tool $TGT: defined in $f" ;;
    unsettled) row referred command "$loc" "$tool $TGT: not literal in $f, which includes or imports others" ;;
    *) row fail command "$loc" "$tool $TGT: no such target in $f" ;;
  esac
}

judge_make() {   # <loc> <cd> <args...>
  local loc=$1 cd=$2 w
  shift 2
  for w in "$@"; do
    case "$w" in
      '#'*) return ;;
      -C|--directory*|-f|--file*|--makefile*) row referred command "$loc" "make $*: runs another makefile or directory"; return ;;
      -*|*=*) ;;
      *) [ "$cd" != 0 ] && { row referred command "$loc" "make $w: $(why_cd "$cd")"; return; }
         TGT=$w judge_target "$loc" make "$MAKE_AWK" GNUmakefile makefile Makefile; return ;;
    esac
  done
}

judge_just() {   # <loc> <cd> <args...>
  local loc=$1 cd=$2 w
  shift 2
  for w in "$@"; do
    case "$w" in
      '#'*) return ;;
      -f|--justfile*|-d|--working-directory*) row referred command "$loc" "just $*: runs another justfile or directory"; return ;;
      -*) return ;;
      *) [ "$cd" != 0 ] && { row referred command "$loc" "just $w: $(why_cd "$cd")"; return; }
         TGT=$w judge_target "$loc" just "$JUST_AWK" justfile Justfile .justfile; return ;;
    esac
  done
}

judge_script() {   # <loc> <cd> <tool> <args...>
  local loc=$1 cd=$2 tool=$3 w np
  shift 3
  for w in "$@"; do
    case "$w" in
      -e|-c|--eval|-p|--print|'#'*) return ;;
      -*) ;;
      /*|'~'*|*'$'*|*'<'*|*'{'*) return ;;
      *) case "$w" in */*|*.js|*.mjs|*.cjs|*.ts|*.sh|*.bash) ;; *) return ;; esac
         case "$cd" in 1|3) ;; *) false ;; esac && { row referred script-path "$loc" "$tool $w: a directory change precedes it"; return; }
         np=$(normpath "" "$w") || { row referred script-path "$loc" "$tool $w: escapes the repository; not read"; return; }
         if tracked "$np"; then row pass script-path "$loc" "$tool $np: tracked"
         else row referred script-path "$loc" "$tool $np: not tracked; may be a build output"; fi
         return ;;
    esac
  done
}

# ---- check: import (#301) ----
# A tracked root CLAUDE.md's @-imports are followed, BREADTH-first, so each file is judged at its
# shortest hop: the root CLAUDE.md is hop 0, read for imports only, and a markdown import that a
# clone has (.md, .markdown, .mdx) is scanned like any doc and its own imports followed, up to
# MAX_IMPORT_HOPS. Every other import gets its existence row only and is never opened. The walk is
# the doc queue below: docs[i] with mode[i] (0 scan, 1 scan and follow imports, 2 follow imports
# only) and hop[i], plus VIS, the resolved paths already queued, so a cycle or a repeat is scanned
# once. Measured on Claude Code 2.1.287, 2026-10-01, in a scratch project: an import is loaded to
# four hops; `\ ` keeps a space in the path; a quoted path, a token after (, a code span and a fence
# load nothing; trailing punctuation is part of the path (`@x.md.` loads nothing); a relative
# import inside a symlinked file resolves from the TARGET's directory.
MAX_IMPORT_HOPS=4
NL=$'\n' VIS=$'\n'
visited() { case "$VIS" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }   # import: visited
visit() { VIS=$VIS$1$NL; }
modes=() hops=()
is_md() { case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in *.md|*.markdown|*.mdx) return 0 ;; esac; return 1; }
# judge_import <loc> <importing file> <its dir> <target> <its hop>: one row, and the resolved
# path queued when it is markdown and within the cap.
judge_import() {
  local loc=$1 f=$2 dir=$3 t=$4 h=$5 np mode rp tp
  case "$t" in
    "~"/*) row referred import "$loc" "$t: home path; a personal import, legitimately local"; return ;;
    /*) row referred import "$loc" "$t: absolute path; machine specific"; return ;;
  esac
  np=$(normpath "$dir" "$t") || { row fail import "$loc" "$t: escapes the repository"; return; }   # import: escape
  mode=""; [ -n "$np" ] && mode=$(idx_mode "$np")
  # Past the cap nothing is loaded, unless a shorter route already reached the file.
  if [ "$h" -ge "$MAX_IMPORT_HOPS" ] && ! { [ -n "$mode" ] && visited "$np"; }; then   # import: cap
    row referred import "$loc" "$t: beyond Claude Code's depth of $MAX_IMPORT_HOPS; not loaded"; return
  fi
  if [ -z "$mode" ]; then   # import: tracked
    tp=$t; trim_punct "$t"
    if [ "$TP" != "$t" ] && [ -n "$TP" ] && np=$(normpath "$dir" "$TP") && [ -n "$np" ] && [ -n "$(idx_mode "$np")" ]; then
      row fail import "$loc" "$tp: imported by $f but not in a clone; Claude Code reads the trailing punctuation as part of the path, so $np is not loaded"
    else
      row fail import "$loc" "$tp: imported by $f but not in a clone"
    fi
    return
  fi
  if git check-ignore -q --no-index -- "$np" 2>/dev/null; then   # import: ignored
    row fail import "$loc" "$t: tracked but ignored; a fresh clone's tooling treats it as local"; return
  fi
  safe_resolve "$np" || { row fail import "$loc" "$t: $SO_WHY"; return; }
  rp=$SO_PATH
  if [ -n "$SO_LINK" ]; then row pass import "$loc" "$t: tracked (symlink to tracked $rp)"
  else row pass import "$loc" "$t: tracked ($rp)"; fi
  is_md "$rp" || return   # import: markdown only
  visited "$rp" && return
  [ "$h" -lt "$MAX_IMPORT_HOPS" ] || return
  visit "$rp"
  # The root AGENTS.md is never parsed for imports, however it is reached (a stated limit).
  if [ "$rp" = AGENTS.md ]; then docs+=("$rp"); modes+=(0); else docs+=("$rp"); modes+=(1); fi   # import: queue
  hops+=($((h + 1)))
}

for d in "${docs[@]+"${docs[@]}"}"; do modes+=(0); hops+=(0); done
if [ "$docs_set" = 0 ]; then
  for d in "${docs[@]+"${docs[@]}"}"; do visit "$d"; done
  [ -n "$agents_link" ] && visit "$agents_link"
  if [ -n "$(idx_mode CLAUDE.md)" ]; then   # import: entry
    if ! safe_resolve CLAUDE.md; then row fail import CLAUDE.md "CLAUDE.md $SO_WHY"
    elif [ "$SO_PATH" != AGENTS.md ] && ! visited "$SO_PATH"; then
      visit "$SO_PATH"; docs+=("$SO_PATH"); modes+=(2); hops+=(0)
    fi
  fi
fi

qi=0
while [ "$qi" -lt "${#docs[@]}" ]; do
  d=${docs[$qi]} dmode=${modes[$qi]} dhop=${hops[$qi]}; qi=$((qi + 1))
  case "$d" in
    "$top"/*) d=${d#"$top"/} ;;
    /*) die "$d is outside the repository" ;;
    *) [ "$dmode" = 0 ] && d=$prefix$d ;;
  esac
  d=$(normpath "" "$d") || die "$d is outside the repository"
  if [ "$d" = AGENTS.md ] && tracked AGENTS.md && [ "$agents_ok" = 0 ]; then continue; fi   # its required row says why
  safe_open "$d" "$T/doc" || { row fail link "$d" "$d: unsafe link ($SO_WHY), not read"; continue; }   # safe_open: loop
  dir=$(dirname "$d"); [ "$dir" = . ] && dir=""
  tmpl=0; is_template "$d" && tmpl=1
  imp=0; [ "$dmode" != 0 ] && imp=1
  IMPORTS=$imp LC_ALL=C awk "$EXTRACT" "$T/doc" > "$T/rec" || die "could not scan $d"
  while IFS=$'\t' read -r kind ln a b c; do
    loc="$d:$ln"
    if [ "$kind" = I ]; then
      judge_import "$loc" "$d" "$dir" "$a" "$dhop"; continue
    fi
    [ "$dmode" = 2 ] && continue   # the root CLAUDE.md is read for imports only
    if [ "$kind" = C ]; then
      # shellcheck disable=SC2086
      set -- $b
      case "$1" in
        npm|pnpm) judge_pm "$loc" "$a" "$@" ;;
        yarn) shift; judge_yarn "$loc" "$a" "$@" ;;
        make) shift; judge_make "$loc" "$a" "$@" ;;
        just) shift; judge_just "$loc" "$a" "$@" ;;
        node|sh|bash) t=$1; shift; judge_script "$loc" "$a" "$t" "$@" ;;
      esac
    else
      if [ "$tmpl" = 1 ]; then
        row referred link "$loc" "$a: resolves against the PR URL in a PR body; use an absolute URL"
      elif [ "$b" = nonascii ]; then
        row referred link "$loc" "$a: percent-encoded non-ASCII target; check it by hand"
      elif ! np=$(normpath "$dir" "$a"); then
        row fail link "$loc" "$a: escapes the repository"
      elif judge_path "$np"; then
        row pass link "$loc" "$a: tracked (${np:-repository root})"
      elif [ -e "$np" ] || [ -L "$np" ]; then
        row fail link "$loc" "$a: $np exists on disk but is not tracked"
      else
        row fail link "$loc" "$a: $np is not a tracked path"
      fi
    fi
  done < "$T/rec"
done

# ---- check: harness-copy (#300) ----
# A tracked per-harness instruction file beside AGENTS.md passes only when it reaches the root
# AGENTS.md by a mechanism THAT harness documents, and is otherwise `referred`: it never fails, since
# a file of harness-specific rules alone is legitimate. Credited (vendor docs, 2026-10-01): a
# symlink for every harness (the filesystem resolves it first); an own-line `@path` import for
# CLAUDE.md, GEMINI.md and .cursor/rules/<name>.mdc; a Markdown link for
# .github/copilot-instructions.md, which reads an @ line as text. Everything comes from the index:
# the mode, a symlink's target blob and a regular file's blob, so an uncommitted import does not
# count. It runs whenever AGENTS.md is tracked, --docs or not, and the harness files never join the
# doc set. Limits: a link or import is weak evidence (a copy may import AGENTS.md and still restate
# it); a symlink chain is referred, not followed; only the own-line @ form counts; a nested
# .cursor/rules/<dir>/x.mdc, the .clinerules directory form and differently cased names are not
# read.
harness_credit() {
  case "$1" in
    CLAUDE.md|GEMINI.md|.cursor/rules/*.mdc) HC_IMP=1 HC_LINK=0 ;;
    .github/copilot-instructions.md) HC_IMP=0 HC_LINK=1 ;;
    *) HC_IMP=0 HC_LINK=0 ;;
  esac
}
# harness_judge_doc <path>: judge the blob already in $T/hdoc. Fences, spans and HTML comments are
# skipped by EXTRACT (#408), so a commented-out @AGENTS.md does not pass.
harness_judge_doc() {
  local h=$1 hdir np kind ln a b c imp=0 lnk=0 abs=0 uimp=0 ulnk=0 why
  hdir=${h%/*}; [ "$hdir" = "$h" ] && hdir=""
  harness_credit "$h"
  IMPORTS=1 LC_ALL=C awk "$EXTRACT" "$T/hdoc" > "$T/hrec" || die "could not scan $h"
  while IFS=$'\t' read -r kind ln a b c; do
    case "$kind" in
      I) [ "$b" = own ] || continue
         case "$a" in /*) abs=1; continue ;; esac   # harness: absolute import
         np=$(normpath "$hdir" "$a") || continue   # harness: import from dir
         [ "$np" = AGENTS.md ] || continue
         if [ "$HC_IMP" = 1 ]; then imp=1; else uimp=1; fi ;;
      L) np=$(normpath "$hdir" "$a") || continue
         [ "$np" = AGENTS.md ] || continue
         if [ "$HC_LINK" = 1 ]; then lnk=1; else ulnk=1; fi ;;
    esac
  done < "$T/hrec"
  if [ "$imp" = 1 ] || [ "$lnk" = 1 ]; then row pass harness-copy "$h" "points at AGENTS.md"; return; fi
  if [ "$abs" = 1 ]; then row referred harness-copy "$h" "absolute import path; Claude Code reads it as a filesystem path"; return; fi
  if [ "$uimp" = 1 ]; then row referred harness-copy "$h" "reaches AGENTS.md by an import; import not documented for this harness"; return; fi
  if [ "$ulnk" = 1 ]; then row referred harness-copy "$h" "reaches AGENTS.md by a link; link not documented for this harness"; return; fi
  why="a separate copy of the project's instructions; it may diverge from AGENTS.md"
  [ "$h" = CLAUDE.md ] && why="$why. Claude Code reads only CLAUDE.md when both exist, so this file shadows AGENTS.md by default"
  row referred harness-copy "$h" "$why"
}
judge_harness() {
  local h=$1 mode tgt np hdir
  hdir=${h%/*}; [ "$hdir" = "$h" ] && hdir=""
  if [ -n "$agents_link" ] && [ "$agents_link" = "$h" ]; then row pass harness-copy "$h" "AGENTS.md is a symlink to this file"; return; fi   # harness: agents link
  mode=$(idx_mode "$h")
  case "$mode" in
    120000)
      tgt=$(git cat-file blob ":0:$h" 2>/dev/null; printf x) || die "cannot read $h from the index"; tgt=${tgt%x}
      case "$tgt" in /*) row referred harness-copy "$h" "absolute symlink target"; return ;; esac   # harness: absolute target
      np=$(normpath "$hdir" "$tgt") || { row referred harness-copy "$h" "symlink target leaves the repository"; return; }   # harness: escape
      if [ "$np" = AGENTS.md ]; then row pass harness-copy "$h" "symlink to AGENTS.md"
      else row referred harness-copy "$h" "symlink to a different file"; fi ;;
    100644|100755)
      git cat-file blob ":0:$h" > "$T/hdoc" 2>/dev/null || die "cannot read $h from the index"   # harness: index blob
      harness_judge_doc "$h" ;;
    *) return ;;   # harness: untracked
  esac
}
if tracked AGENTS.md; then   # harness: entry
  awk '{ p = $0 }
    p == ".github/copilot-instructions.md" || p == ".cursorrules" || p == ".junie/guidelines.md" || p == "GEMINI.md" ||
    p == ".windsurfrules" || p == ".clinerules" || p == "CLAUDE.md" || p ~ /^\.cursor\/rules\/[^\/]+\.mdc$/ { print $0 }' "$IDX" > "$T/harness"
  while IFS= read -r h; do judge_harness "$h"; done < "$T/harness"
fi

cat "$ROWS"
awk -F'\t' '$1 == "fail" { f = 1 } END { exit f }' "$ROWS" || exit 1
exit 0
