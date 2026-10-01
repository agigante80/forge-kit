#!/usr/bin/env bash
# check-contributor-docs-version: 3
# check-contributor-docs.sh: are a repository's contributor entry points TRUE for everyone who
# clones it (#294, amended by #295).
#
# An agent reads AGENTS.md, a person reads CONTRIBUTING.md, and both meet the PR template. Each
# names commands and links other docs, and each rots silently. The trap this exists for is
# agigante80/actual-mcp-server#496: CONTRIBUTING.md named npm scripts that did not exist while
# AGENTS.md was gitignored, so it was present on the maintainer's disk and absent for everyone else.
# Every path here is therefore resolved against the git INDEX, never the disk.
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
#              symlink is judged by its target, so AGENTS.md -> an untracked CLAUDE.md fails.
#   max-lines  AGENTS.md within --max-lines (150, counted as wc -l counts).
#   max-bytes  AGENTS.md within --max-bytes (32768: Codex truncates the file at 32 KiB).
#   command    Only inside code spans and fenced blocks. The FAIL set is a closed allowlist: the two
#              root shapes `npm run X` and `pnpm run X` (`run` straight after the package manager, a
#              literal name, no flag but --silent/-s, a tracked root package.json, no cd or pushd
#              earlier in the same scope), plus six workspace spellings resolved against the ONE
#              tracked manifest of that name (#299): npm -w, --workspace and --workspace=, pnpm
#              --filter, -F and --filter=, each followed by `run X`. Yarn never fails, because yarn
#              falls through to a binary: a defined root script is a pass, anything else referred.
#              Everything else is referred or silent. make and just are read as TEXT and never
#              invoked: make runs recipes while remaking makefiles.
#   script-path  `node|sh|bash <path>`: tracked passes, anything else is referred (a build output
#              is correct and untracked). A path leaving the repository is never read.
#   link       Relative links, images and reference definitions resolve to a tracked path or to a
#              directory some tracked path lies under. `/x` is the repository root, as GitHub
#              renders it; anything else is relative to the containing file. Leaving the
#              repository fails and is never read. In a PR template every relative link is
#              referred, because GitHub copies the template into the PR body and it then resolves
#              against the PR URL.
#
# A SCOPE, for the cd rule: a fenced block is one scope; a code span's scope is its PARAGRAPH, so
# "Run `cd client`, then `npm run dev`." is referred (#295). A cd AFTER the command changes nothing.
# A paragraph ends at a blank line (after a trailing CR is stripped) or at a fence. Inside a fence a
# command must START a segment of a line, split on && || ; | ( ), after an optional `$ ` prompt; a
# VAR=val prefix is skipped to find the runner but refers the row, since npm_config_workspace=client
# rescopes npm. Backticks there are literal, so a backticked name is referred.
#
# EXPORTS AND SUBSTITUTIONS (#296). An `export`, `declare -x` or `typeset -x` of a NAME=value whose
# NAME starts with npm_config_ (any case, any key, an empty value too: referring is the safe side)
# refers every LATER runner of the same fence or code-span paragraph, and a later segment of its own
# line, exactly as a cd does and with the same resets. `export FOO=1` rescopes nothing and still
# fails. A NAME=$(...) assignment value whose parentheses do not nest is read as a plain assignment.
# Limits: an export in a prose code span does not carry into a following fence (the carry resets at
# a fence open, as a cd does); nested-paren and backtick substitution values; pnpm_config_*;
# JUST_JUSTFILE and JUST_WORKING_DIRECTORY; unset; set -a; `env VAR=... cmd`; a .npmrc (#339).
#
# Deliberate limits: code spans and links are found within one line; indented code blocks are
# prose; the paragraph rule is order-dependent ("Run `npm run dev` (after `cd client`)." judges dev
# from the root) and list items with no blank line between them are one paragraph; make's built-in
# implicit rules are not modelled, so `make foo` built from foo.c by no written rule fails; a
# percent-encoded non-ASCII link target is referred rather than decoded.
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
cd "$top" || die "cannot enter the repository root"
set -f

T=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$T"' EXIT
IDX=$T/index ROWS=$T/rows
: > "$ROWS"
git -c core.quotepath=off ls-files -z > "$T/index0" 2>/dev/null || die "git ls-files failed"
tr '\0' '\n' < "$T/index0" > "$IDX"

row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$ROWS"; }
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

# ---- check 1: required and published, and check 2: size ----
if tracked AGENTS.md; then
  if git check-ignore -q --no-index AGENTS.md 2>/dev/null; then
    row fail required AGENTS.md "AGENTS.md is tracked but ignored; a fresh clone's tooling treats it as local"
  elif [ -L AGENTS.md ]; then
    tgt=$(readlink AGENTS.md)
    if ! np=$(normpath "" "$tgt"); then
      row fail required AGENTS.md "AGENTS.md links to $tgt, which escapes the repository"
    elif judge_path "$np"; then
      row pass required AGENTS.md "AGENTS.md is tracked (symlink to tracked $np)"
    else
      row fail required AGENTS.md "AGENTS.md links to $np, which is not tracked, so it is local only"
    fi
  else
    row pass required AGENTS.md "AGENTS.md is tracked"
  fi
elif [ -e AGENTS.md ] || [ -L AGENTS.md ]; then
  row fail required AGENTS.md "AGENTS.md exists but is not tracked, so nobody else has it"
else
  row fail required AGENTS.md "AGENTS.md is missing"
fi
if [ -f AGENTS.md ]; then
  [ -r AGENTS.md ] || die "cannot read AGENTS.md"
  n=$(wc -l < AGENTS.md | tr -d ' ') b=$(wc -c < AGENTS.md | tr -d ' ')
  if [ "$n" -le "$max_lines" ]; then row pass max-lines AGENTS.md "$n lines, budget $max_lines"
  else row fail max-lines AGENTS.md "$n lines exceeds the budget of $max_lines"; fi
  if [ "$b" -le "$max_bytes" ]; then row pass max-bytes AGENTS.md "$b bytes, budget $max_bytes"
  else row fail max-bytes AGENTS.md "$b bytes exceeds the budget of $max_bytes"; fi
fi

# ---- the doc set ----
if [ "$docs_set" = 0 ]; then
  tracked AGENTS.md && docs+=(AGENTS.md)
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
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function code(text, infence,    n, i, j, k, nw, ws, segs, seg, w, env, carry, rs) {
  # A command substitution as an assignment VALUE rescopes npm like any other value
  # (npm_config_workspace=$(echo client) npm run dev, #296), but the split below would cut it at
  # its parentheses and leave a bare runner. Rewrite a NAME=$(...) WORD, whose parentheses do not
  # nest, to NAME=X first, so the assignment strip sets env. Anchored at the start of a word, so
  # --workspace=$(...) is left alone. A $( anywhere else rescopes nothing and stays judged.
  while (match(text, /(^|[ \t;&|(])[A-Za-z_][A-Za-z0-9_]*=\$\([^()]*\)/)) {
    rs = substr(text, RSTART, RLENGTH); sub(/=\$\([^()]*\)$/, "=X", rs)
    text = substr(text, 1, RSTART - 1) rs substr(text, RSTART + RLENGTH)
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
    while (seg ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) { sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", seg); env = 1 }
    w = seg; sub(/[ \t].*/, "", w)
    # An exported npm_config_ variable (any case, any key, an empty value too) rescopes every later
    # npm in the same fence or paragraph, so it is carried like a cd and applied from the NEXT
    # segment on, never to an earlier one (#296). export, declare -x and typeset -x set it.
    nw = split(seg, ws, /[ \t]+/)
    if (w == "export" || ((w == "declare" || w == "typeset") && ws[2] == "-x")) {
      for (j = 2; j <= nw; j++)
        if (ws[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*=/) { if (infence) fenv = 1; else penv = 1 }
      continue
    }
    carry = infence ? fenv : penv
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
BEGIN { HEX = "0123456789abcdef"; infence = 0; pcd = 0; penv = 0; fenv = 0 }
{ sub(/\r$/, "") }
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
  if (substr(lead, 1, 1) == "[" && substr(lead, 2, 1) != "^" && (k = index(lead, "]:")) > 2) {
    label = substr(lead, 2, k - 2)
    if (index(label, "[") == 0 && index(label, "]") == 0) { link(target(substr(lead, k + 2))); next }
  }
  while ((i = index(rest, "](")) > 0) { rest = substr(rest, i + 2); link(target(rest)) }
}'

MAKE_AWK='
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

# first_file <candidates...>: the first one that is tracked.
first_file() { local f; for f in "$@"; do tracked "$f" && { printf '%s' "$f"; return 0; }; done; return 1; }

judge_pm() {   # <loc> <cd> <pm> <args...>
  local loc=$1 cd=$2 pm=$3 w name="" flag="" extra wsv="" wsn=0
  shift 3
  if [ $# -eq 0 ]; then return; fi
  case "$1" in
    run) shift ;;
    test|start|run-script|t|tst) row referred command "$loc" "$pm $1: runs a lifecycle script; not checked"; return ;;
    -*) # The six workspace spellings, each with `run` straight after the value (#299).
        case "$pm:$1" in
          npm:-w|npm:--workspace|pnpm:--filter|pnpm:-F) [ $# -ge 3 ] && [ "$3" = run ] && { wsv=$2; wsn=3; } ;;
          npm:--workspace=*) [ $# -ge 2 ] && [ "$2" = run ] && { wsv=${1#--workspace=}; wsn=2; } ;;
          pnpm:--filter=*) [ $# -ge 2 ] && [ "$2" = run ] && { wsv=${1#--filter=}; wsn=2; } ;;
        esac
        if [ "$wsn" != 0 ]; then judge_ws "$loc" "$cd" "$pm $*" "$pm" "$wsv" "${@:$((wsn + 1))}"; return; fi
        for w in "$@"; do [ "$w" = run ] && { row referred command "$loc" "$pm $*: a flag between $pm and run may change which script runs"; return; }; done
        # pnpm runs a bare word as a script, so `pnpm -r build` may be one; npm never does.
        [ "$pm" = pnpm ] && for w in "$@"; do case "$w" in -*) ;; *) row referred command "$loc" "pnpm $*: may be a script, a built-in or a binary"; return ;; esac; done
        return ;;
    *) [ "$pm" = pnpm ] || return
       case "$1" in
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
  [ -n "$flag" ] && { row referred command "$loc" "$pm run ${name:-...}: $flag may change which script runs"; return; }
  [ -z "$name" ] && return
  while :; do case "$name" in *[.,\;:!?]) name=${name%?} ;; *) break ;; esac; done
  local re='^[A-Za-z0-9][A-Za-z0-9:_.-]*$'
  [[ $name =~ $re ]] || { row referred command "$loc" "$pm run $name: not a literal script name"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$pm run $name: $(why_cd "$cd")"; return; }
  tracked package.json || { row referred command "$loc" "$pm run $name: no root package.json is tracked"; return; }
  if resolve_script "$name"; then row pass command "$loc" "$pm run $name: defined in package.json"
  else row fail command "$loc" "$pm run $name: no such script in package.json"; fi
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
  while :; do case "$name" in *[.,\;:!?]) name=${name%?} ;; *) break ;; esac; done
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: $name is not a literal script name"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }
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
  while :; do case "$name" in *[.,\;:!?]) name=${name%?} ;; *) break ;; esac; done
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
    install|add|remove|upgrade|up|init|dlx|exec|set|config|workspaces|workspace|why|info|cache|global|link|unlink|pack|publish|npm|plugin|version|audit|outdated|list|bin|create|login|logout|constraints|dedupe|node|patch|rebuild|explain) return 0 ;;
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
        b1=$1; while :; do case "$b1" in *[.,\;:!?]) b1=${b1%?} ;; *) break ;; esac; done   # `yarn check.` is still the built-in
        yarn_builtin "$b1"; b=$?
        [ "$b" = 0 ] && return
        [ "$b" = 1 ] && { row referred command "$loc" "$lab: $1 may be a yarn built-in"; return; }
      fi
      judge_ws "$loc" "$cd" "$lab" yarn "$ws" "$@"; return ;;
    -*) for w in "$@"; do case "$w" in -*) ;; *) row referred command "$loc" "yarn $*: may be a script, a built-in or a binary"; return ;; esac; done
        return ;;
  esac
  b1=$1; while :; do case "$b1" in *[.,\;:!?]) b1=${b1%?} ;; *) break ;; esac; done   # trailing punctuation never hides a built-in
  yarn_builtin "$b1"; b=$?
  [ "$b" = 0 ] && return
  [ "$b" = 1 ] && { row referred command "$loc" "yarn $1: may be a yarn built-in, which shadows a script of that name under yarn 1"; return; }
  judge_yarn_root "$loc" "$cd" yarn "$@"
}

judge_target() {   # <loc> <tool> <awk> <files...> ; the target is in $TGT
  local loc=$1 tool=$2 prog=$3 f verdict
  shift 3
  f=$(first_file "$@") || { row referred command "$loc" "$tool $TGT: no tracked $1 to read"; return; }
  verdict=$(TGT=$TGT awk "$prog" "$f")
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

for d in "${docs[@]+"${docs[@]}"}"; do
  case "$d" in
    "$top"/*) d=${d#"$top"/} ;;
    /*) die "$d is outside the repository" ;;
    *) d=$prefix$d ;;
  esac
  d=$(normpath "" "$d") || die "$d is outside the repository"
  { [ -f "$d" ] && [ -r "$d" ]; } || die "cannot read $d"
  dir=$(dirname "$d"); [ "$dir" = . ] && dir=""
  tmpl=0; is_template "$d" && tmpl=1
  awk "$EXTRACT" "$d" > "$T/rec" || die "could not scan $d"
  while IFS=$'\t' read -r kind ln a b c; do
    loc="$d:$ln"
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

cat "$ROWS"
awk -F'\t' '$1 == "fail" { f = 1 } END { exit f }' "$ROWS" || exit 1
exit 0
