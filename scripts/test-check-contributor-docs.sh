#!/usr/bin/env bash
# Contract test for contributor-docs/assets/check-contributor-docs.sh (#294, amended by #295).
#
# The script answers one question per row: is what AGENTS.md, CONTRIBUTING.md or the PR template
# says TRUE for someone who clones the repository. Every case below is a predicate over a throwaway
# git repository, so the same predicate runs twice: once against the shipped script, where it must
# hold, and once against a named MUTANT, where it must not. A case that passes against a mutant
# guards nothing, which is why each mutant names the one case written to kill it.
#
# STREAMS ARE THE CONTRACT: TSV rows on stdout and exit 0 or 1, or nothing on stdout and exit 2.
#
# Portability runs: BASH_UNDER_TEST=/path/to/bash-3.2 runs the script under that bash (by hand, CI
# has no bash 3.2), and AWK_UNDER_TEST=mawk (or gawk, nawk, or `busybox awk` via a wrapper) puts that
# awk first on PATH for every run. CI runs this suite twice, AWK_UNDER_TEST=gawk and =mawk (#386); a
# run that asks for gawk and gets another awk fails the strip mutant instead of skipping it.
#
# ESCAPE_WATCHDOG_SECS (positive integer from 1 to 60, seconds, default 10) is how long c_escape's
# watchdog waits before it releases one extra opener of the FIFO sentinel. It also sets the bound
# on every run of the script under test (that value plus 5 s), so a script that hangs on the
# sentinel fails its case instead of hanging the suite. Any other non-empty value is refused up
# front with exit 1.
#
# HOSTILE_WATCHDOG_SECS (integer from 1 to 60, default 6, #346) bounds the hostile-input cases: a
# long line must be judged within it, so a quadratic rewrite or strip is killed by the bound rather
# than hanging the suite. The same validation as above applies.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/plugins/forge-kit-governance/skills/contributor-docs/assets/check-contributor-docs.sh"
FIX="$HERE/fixtures/check-contributor-docs"
SHELL_UNDER_TEST="${BASH_UNDER_TEST:-bash}"

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

# Validated before any case runs and before `run` uses it as a bound. A string pattern, not
# arithmetic: bash rejects 08 as invalid octal. An empty or unset value means 10.
ESCAPE_WATCHDOG_SECS=${ESCAPE_WATCHDOG_SECS:-10}
case $ESCAPE_WATCHDOG_SECS in
  [1-9]|[1-5][0-9]|60) ;;
  *) echo "ESCAPE_WATCHDOG_SECS must be an integer from 1 to 60, got '$ESCAPE_WATCHDOG_SECS'" >&2; exit 1 ;;
esac

HOSTILE_WATCHDOG_SECS=${HOSTILE_WATCHDOG_SECS:-6}
case $HOSTILE_WATCHDOG_SECS in
  [1-9]|[1-5][0-9]|60) ;;
  *) echo "HOSTILE_WATCHDOG_SECS must be an integer from 1 to 60, got '$HOSTILE_WATCHDOG_SECS'" >&2; exit 1 ;;
esac

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# c_escape records its writer and watchdog here so an interrupted run can kill them (a background
# job of a non-interactive bash ignores SIGINT, and both block on a FIFO nobody will open). The
# watchdog is its own process group, so killing the group takes its `sleep` child with it. KILL by
# recorded PID only, never by pattern; c_escape clears both after its own cleanup so the trap never
# signals a recycled PID.
ESC_WPID=""; ESC_DPID=""
cleanup_escape() {
  [ -n "$ESC_WPID" ] && kill -KILL "$ESC_WPID" 2>/dev/null
  [ -n "$ESC_DPID" ] && kill -KILL -- -"$ESC_DPID" 2>/dev/null
  return 0
}
W=$(mktemp -d); trap 'cleanup_escape; chmod -R u+rw "$W" 2>/dev/null; rm -rf "$W"' EXIT
# A trapped SIGINT runs once the foreground child returns, however that child exited. Without
# this, a direct (not `$( )`) `bounded` call that exits 124 after its own INT trap counts as having
# handled the signal, and bash carries on to the next case (#338 round 2).
trap 'exit 130' INT
export GIT_CEILING_DIRECTORIES="$W"

AWKDIR=""
if [ -n "${AWK_UNDER_TEST:-}" ]; then
  AWKDIR="$W/awk"; mkdir -p "$AWKDIR"
  ln -s "$(command -v "$AWK_UNDER_TEST")" "$AWKDIR/awk" || { echo "no awk: $AWK_UNDER_TEST"; exit 1; }
fi

# A PATH with the tools the script needs and no jq, for the lazy-jq cases.
NOJQ="$W/nojq"; mkdir -p "$NOJQ"
for c in git bash awk tr wc mktemp rm dirname cat readlink env grep sh busybox; do
  p_="$(command -v "$c" 2>/dev/null)"; [ -n "$p_" ] && ln -sf "$p_" "$NOJQ/$c"
done
[ -n "$AWKDIR" ] && ln -sf "$AWKDIR/awk" "$NOJQ/awk"
[ -n "${BASH_UNDER_TEST:-}" ] && ln -sf "$BASH_UNDER_TEST" "$NOJQ/bash"

S="$SCRIPT"   # the script under test; a mutant run points it elsewhere
R=""; n=0
new() {
  n=$((n + 1)); R="$W/r$n"; mkdir -p "$R"
  git init --quiet -b main "$R"
  git -C "$R" config user.email t@t.invalid; git -C "$R" config user.name t
}
# put <path> <text>: write a file (printf %b, so \n and \t work). tput: write and track it.
put()  { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" > "$R/$1"; }
tput_() { put "$1" "$2"; git -C "$R" add -- "$1"; }
agents() { tput_ AGENTS.md "$1"; }
# nlines <n>: a tracked AGENTS.md of exactly n lines.
nlines() { seq 1 "$1" | sed 's/.*/l/' > "$R/AGENTS.md"; git -C "$R" add AGENTS.md; }
pkg() { tput_ package.json "{\"scripts\":{$1}}\n"; }

# bounded <secs> <cmd...>: cmd in its own process group; 124 if the bound kills it. Defined before
# `run`, which bounds the script under test with it. Derived from the helper that
# scripts/test-forge-lib.sh and scripts/test-check-public-leaks.sh carry (stock macOS ships no GNU
# `timeout`), but no longer the same: it adds an INT/TERM trap. With `set -m` the command and the
# watcher sit in their own process groups, which a SIGINT to the suite's group does not reach once
# `run` is bounded; without this trap the suite lingers until the bound expires with processes
# left behind. The trap stops both groups, then re-raises SIGINT on the suite ($$ is the suite's
# PID even in this subshell), whose own INT trap (next to the EXIT trap) then exits 130.
# WHY TERM FOR THE COMMAND AND NOT KILL: the script under test (and a child suite) removes its
# `mktemp -d` directory from an EXIT trap, and SIGKILL skips every trap, so killing the command's
# group with KILL leaks a tmp.* directory into TMPDIR on each interrupt. TERM lets that trap run;
# the wait then reaps it, so the suite exits only once the cleanup is done. The watcher only
# sleeps, so it takes KILL. The bound-expiry path above already sends TERM (a plain `kill`), for
# the same reason. Do not turn either into KILL.
bounded() {
  local secs="$1"; shift
  ( set -m
    "$@" & pid=$!
    ( sleep "$secs"; kill -- -"$pid" 2>/dev/null ) >/dev/null 2>&1 & w=$!
    set +m
    trap 'kill -KILL -- -"$w" 2>/dev/null; kill -TERM -- -"$pid" 2>/dev/null; wait "$pid" 2>/dev/null; trap - INT TERM; kill -INT $$' INT TERM
    wait "$pid" 2>/dev/null; rc=$?
    kill -- -"$w" 2>/dev/null
    [ "$rc" -ge 128 ] && rc=124; exit "$rc" )
}

OUT=""; ERR=""; RC=0
run() {
  local p="$PATH"; [ -n "$AWKDIR" ] && p="$AWKDIR:$PATH"
  OUT=$(cd "$R" && PATH="$p" bounded $((ESCAPE_WATCHDOG_SECS + 5)) "$SHELL_UNDER_TEST" "$S" "$@" 2>"$W/err"); RC=$?
  ERR=$(cat "$W/err")
}
# run_bounded <secs> [args...]: run with a caller-chosen bound (124 when it expires). OUT, ERR and RC
# are set here, in the suite's own shell: only the script's stdout is captured through $( ).
run_bounded() {
  local secs=$1 p="$PATH"; shift; [ -n "$AWKDIR" ] && p="$AWKDIR:$PATH"
  OUT=$(cd "$R" && PATH="$p" bounded "$secs" "$SHELL_UNDER_TEST" "$S" "$@" 2>"$W/err"); RC=$?
  ERR=$(cat "$W/err")
}
run_nojq() {
  OUT=$(cd "$R" && PATH="$NOJQ" bash "$S" "$@" 2>"$W/err"); RC=$?
  ERR=$(cat "$W/err")
}
# Predicates over the last run. `row S C X`: a row with status S, check C and X in its detail.
rc_is() { [ "$RC" -eq "$1" ]; }
row() { S_=$1 C_=$2 X_=$3 awk -F'\t' '$1 == ENVIRON["S_"] && $2 == ENVIRON["C_"] && index($4, ENVIRON["X_"]) { f = 1 } END { exit !f }' <<<"$OUT"; }
at() { S_=$1 L_=$2 X_=$3 awk -F'\t' '$1 == ENVIRON["S_"] && index($3, ENVIRON["L_"]) == 1 && index($4, ENVIRON["X_"]) { f = 1 } END { exit !f }' <<<"$OUT"; }
none() { ! grep -qF -- "$1" <<<"$OUT"; }
nostatus() { ! awk -F'\t' -v s="$1" '$1 == s { f = 1 } END { exit !f }' <<<"$OUT"; }
# nocmd <status>: no command row carries that status (AGENTS.md's own required rows pass).
nocmd() { [ "$(count "$1" command)" = 0 ]; }
count() { awk -F'\t' -v s="$1" -v c="$2" '$1 == s && $2 == c { k++ } END { print k + 0 }' <<<"$OUT"; }

# case_ <predicate function> <label>: must hold against the shipped script.
case_() { S="$SCRIPT"; if "$1"; then ok "$2"; else bad "$2 (rc $RC)"; printf '%s\n%s\n' "$OUT" "$ERR" | sed 's/^/      | /'; fi; }

# ---------------------------------------------------------------- check 1 and 2: AGENTS.md
c_tracked() { new; nlines 40; run
  rc_is 0 && row pass required "is tracked" && row pass max-lines "40 lines"; }
c_untracked() { new; tput_ .gitignore 'AGENTS.md\n'; put AGENTS.md 'x\n'; run
  rc_is 1 && row fail required "not tracked" && none "is missing"; }
c_missing() { new; tput_ README.md 'x\n'; run
  rc_is 1 && row fail required "is missing" && none "not tracked"; }
c_ignored() { new; agents 'x\n'; git -C "$R" commit --quiet -m a; tput_ .gitignore '/AGENTS.md\n'; run
  rc_is 1 && row fail required "ignored"; }
c_symlink() { new; put CLAUDE.md 'x\n'; tput_ .gitignore 'CLAUDE.md\n'; ln -s CLAUDE.md "$R/AGENTS.md"; git -C "$R" add AGENTS.md; run
  rc_is 1 && row fail required "CLAUDE.md, which is not tracked"; }
c_150() { new; nlines 150; run; rc_is 0 && row pass max-lines "150 lines"; }
c_151() { new; nlines 151; run
  rc_is 1 && row fail max-lines "151 lines exceeds the budget of 150"; }
c_bytes() { new; agents "$(printf 'a%.0s' $(seq 1 32768))\n"; run
  rc_is 1 && row fail max-bytes "32769 bytes"; }

echo "== required and size =="
case_ c_tracked "a tracked 40-line AGENTS.md passes required and max-lines"
case_ c_untracked "an untracked, ignored AGENTS.md fails as not tracked"
case_ c_missing "an absent AGENTS.md fails as missing, never as not tracked"
case_ c_ignored "a tracked AGENTS.md that an ignore rule matches fails as ignored"
case_ c_symlink "a tracked symlink to an untracked CLAUDE.md fails"
case_ c_150 "exactly 150 lines passes"
case_ c_151 "151 lines fails naming 151 and 150"
case_ c_bytes "32769 bytes fails naming 32769"

# ---------------------------------------------------------------- #309: one safe read, no outside content
# Every negative asserts the outside token never reaches stdout or stderr, by CONTENT (#305): a read
# of the outside file is caught whatever row it produced. Each repository is $W/rN, so ../outside.md
# names $W/outside.md.
TOKEN=SECRET-TOKEN-abc123
printf 'See [x](%s.md)\n' "$TOKEN" > "$W/outside.md"
mkdir -p "$W/outdir"; printf 'See [x](%s.md)\n' "$TOKEN" > "$W/outdir/z.md"
no_token() { ! grep -qF -- "$TOKEN" <<<"$OUT$ERR"; }
# lnk <target> <name>: a tracked symlink.
lnk() { mkdir -p "$(dirname "$R/$2")"; ln -s "$1" "$R/$2"; git -C "$R" add -- "$2"; }
# four_fields: every output line has exactly four TAB-separated fields and none starts with `::`.
four_fields() { awk -F'\t' 'NF != 4 || /^::/ { f = 1 } END { exit f }' <<<"$OUT"; }
# The awk shim for c_make_awk_fails: exit 1 only for the make and just programs (their text holds
# `unsettled`), the real awk otherwise. REAL_AWK is resolved before the shim directory is on PATH.
REAL_AWK=$(PATH="${AWKDIR:+$AWKDIR:}$PATH" command -v awk)
mkdir -p "$W/shim"; printf '#!/bin/sh\ncase "$*" in *unsettled*) exit 1 ;; esac\nexec "%s" "$@"\n' "$REAL_AWK" > "$W/shim/awk"; chmod +x "$W/shim/awk"

c_symlink_ok() { new; tput_ CLAUDE.md 'x\n'; lnk CLAUDE.md AGENTS.md; run
  rc_is 0 && row pass required "symlink to tracked CLAUDE.md" && [ -z "$ERR" ]; }
c_symlink_chain_escape() { new; lnk ../outside.md l2.md; lnk l2.md AGENTS.md; run
  rc_is 1 && row fail required "l2.md, which is itself a symlink" && no_token && [ "$(count pass max-lines)" = 0 ] && [ "$(count fail max-lines)" = 0 ]; }
c_symlink_chain_inside() { new; tput_ CLAUDE.md 'x\n'; lnk CLAUDE.md l2.md; lnk l2.md AGENTS.md; run
  rc_is 1 && row fail required "l2.md, which is itself a symlink"; }
c_symlink_chain_three() { new; lnk ../outside.md l3.md; lnk l3.md l2.md; lnk l2.md AGENTS.md; run
  rc_is 1 && row fail required "l2.md, which is itself a symlink" && no_token; }
c_symlink_escape_one() { new; lnk ../outside.md AGENTS.md; run
  rc_is 1 && row fail required "escapes the repository" && no_token \
    && [ "$(awk -F'\t' '$3 == "AGENTS.md" || index($3, "AGENTS.md:") == 1' <<<"$OUT" | grep -c .)" = 1 ]; }
c_symlink_abs() { new; tput_ etc/hostname 'x\n'; lnk /etc/hostname AGENTS.md; run
  rc_is 1 && row fail required "/etc/hostname, which is an absolute path a clone does not have" && [ "$(count pass required)" = 0 ] \
    && [ "$(count pass max-bytes)" = 0 ] && [ "$(count fail max-bytes)" = 0 ] || return 1
  # #310: an absolute target whose path minus the slash is tracked as a decoy
  new; tput_ "${W#/}/outside.md" 'decoy\n'; lnk "$W/outside.md" AGENTS.md; run
  rc_is 1 && row fail required "which is an absolute path" && no_token && none decoy; }
c_symlink_subdir() { new; agents 'x\n'; tput_ docs/guide.md 'See [r](../AGENTS.md).\n'; lnk guide.md docs/AGENTS.md; run --docs docs/AGENTS.md
  rc_is 0 && at pass docs/AGENTS.md:1 "../AGENTS.md"; }
c_symlink_dir() { new; tput_ docs/guide.md 'x\n'; lnk docs AGENTS.md; run
  rc_is 1 && row fail required "docs, a directory, which is not a tracked file" && ! grep -q 'cannot read' <<<"$ERR"; }
c_symlink_glob() { new; tput_ CLAUDE.md 'x\n'; lnk 'C*.md' AGENTS.md; run
  rc_is 1 && row fail required "C*.md, which is not tracked" && [ -z "$ERR" ] || return 1
  new; tput_ CLAUDE.md 'x\n'; lnk ':(top)CLAUDE.md' AGENTS.md; run
  rc_is 1 && row fail required ":(top)CLAUDE.md, which is not tracked" && [ -z "$ERR" ]; }
c_symlink_dangling() { new; lnk missing.md AGENTS.md; run
  rc_is 1 && row fail required "missing.md, which is not tracked" && [ -z "$ERR" ]; }
c_contrib_regular() { new; agents 'x\n'; tput_ CONTRIBUTING.md 'See [a](AGENTS.md).\n'; run
  rc_is 0 && at pass CONTRIBUTING.md:1 "AGENTS.md"; }
c_contrib_symlink() { new; agents 'x\n'; lnk ../outside.md CONTRIBUTING.md; run
  rc_is 1 && at fail CONTRIBUTING.md "unsafe link" && ! at pass CONTRIBUTING.md:1 "" && ! at fail CONTRIBUTING.md:1 "" && no_token; }
c_prtemplate_symlink() { new; agents 'x\n'; lnk ../../outside.md .github/PULL_REQUEST_TEMPLATE.md; run
  rc_is 1 && at fail .github/PULL_REQUEST_TEMPLATE.md "unsafe link" && no_token; }
c_docs_regular() { new; agents 'x\n'; tput_ x.md 'See [a](AGENTS.md).\n'; run --docs x.md
  rc_is 0 && at pass x.md:1 "AGENTS.md"; }
c_docs_tracked_symlink() { new; agents 'x\n'; lnk ../outside.md x.md; run --docs x.md
  rc_is 1 && at fail x.md "unsafe link" && no_token; }
c_docs_untracked_symlink() { new; agents 'x\n'; ln -s ../outside.md "$R/y.md"; run --docs y.md
  rc_is 1 && at fail y.md "an untracked symlink" && no_token; }
c_docs_symlinked_parent() { new; agents 'x\n'; ln -s ../outdir "$R/docs"; run --docs docs/z.md
  rc_is 1 && at fail docs/z.md "resolves outside the repository" && no_token; }
c_docs_sibling_prefix() { new; agents 'x\n'; mkdir -p "${R}x"; printf 'See [x](%s.md)\n' "$TOKEN" > "${R}x/z.md"
  ln -s "${R}x" "$R/docs"; run --docs docs/z.md
  rc_is 1 && at fail docs/z.md "resolves outside the repository" && no_token; }
c_docs_dash_parent() { new; agents 'x\n'; ln -s ../outdir "$R/-foo"; run --docs -foo/z.md
  rc_is 1 && at fail -foo/z.md "resolves outside the repository" && no_token; }
c_make_symlink_passwd() { new; lnk /etc/passwd Makefile; agents '`make root`\n\n`make zzqq`\n'; run
  rc_is 1 && row fail command "Makefile is an unsafe link" && ! row pass command "make root" && ! row fail command "no such target"; }
c_just_symlink() { new; lnk ../outside.md justfile; agents '`just build`\n'; run
  rc_is 1 && row fail command "justfile is an unsafe link" && no_token; }
c_make_symlink_devzero() { new; lnk /dev/zero Makefile; agents '`make build`\n'; run_bounded 10
  rc_is 1 && row fail command "Makefile is an unsafe link"; }
c_make_regular() { new; tput_ Makefile 'build:\n\techo b\n'; agents '`make build`\n'; run
  rc_is 0 && row pass command "make build: defined in Makefile"; }
c_make_awk_fails() { new; tput_ Makefile 'build:\n\techo b\n'; agents '`make build`\n'; AWKDIR="$W/shim" run
  rc_is 2 && [ -z "$OUT" ]; }
c_row_plain_target() { new; tput_ CLAUDE.md 'x\n'; lnk CLAUDE.md AGENTS.md; run
  rc_is 0 && four_fields; }
c_row_newline_target() { new; lnk "$(printf 'a\n::warning title=forged::injected')" AGENTS.md; run
  rc_is 1 && four_fields && row fail required "a?::warning title=forged::injected, which holds a control character" || return 1
  new; lnk "$(printf 'a\r\033[2Jb')" AGENTS.md; run
  rc_is 1 && four_fields && row fail required "a??[2Jb" && ! grep -q "$(printf '[\r\033]')" <<<"$OUT"; }
# A file name holding control bytes reaches a row through --docs (an untracked doc is read from disk)
# and through a link row's location: each name's doc links to a missing file, so a row exists.
c_row_newline_name() { new; agents 'x\n'
  local n1 n2; n1=$(printf 'a\n::warning title=forged::x.md') n2=$(printf 'a\033[2J\rb.md')
  printf 'See [m](missing.md).\n' > "$R/$n1"; printf 'See [m](missing.md).\n' > "$R/$n2"; run --docs "$n1" "$n2"
  rc_is 1 && four_fields && [ "$(count fail link)" = 2 ] && ! grep -q "$(printf '[\r\033]')" <<<"$OUT"; }
c_tracked_newline_name() { new; tput_ "$(printf 'z\nCLAUDE.md')" 'x\n'; lnk CLAUDE.md AGENTS.md; run
  rc_is 1 && row fail required "CLAUDE.md, which is not tracked" && [ "$(count pass required)" = 0 ]; }
c_tracked_newline_dir() { new; tput_ "$(printf 'a\nb/c')" 'x\n'; agents 'See [b](b).\n'; run
  rc_is 1 && at fail AGENTS.md:1 "b is not a tracked path"; }
c_tracked_tab_name() { new; tput_ "$(printf '\tCLAUDE.md')" 'x\n'; lnk CLAUDE.md AGENTS.md; run
  rc_is 1 && row fail required "CLAUDE.md, which is not tracked" && [ "$(count pass required)" = 0 ]; }
c_tracked_tab_inner() { new; tput_ "$(printf 'CLAUDE.md\tx')" 'x\n'; lnk CLAUDE.md AGENTS.md; run
  rc_is 1 && row fail required "CLAUDE.md, which is not tracked" && [ "$(count pass required)" = 0 ]; }
c_tracked_tab_shadow() { new; tput_ "$(printf '\tCLAUDE.md')" 'x\n'; lnk ../outside.md CLAUDE.md; lnk CLAUDE.md AGENTS.md; run
  rc_is 1 && row fail required "CLAUDE.md, which is itself a symlink" && no_token; }
c_submodule_doc() { new; agents 'x\n'
  git -C "$R" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,CONTRIBUTING.md; run
  rc_is 1 && at fail CONTRIBUTING.md "a submodule, not a file"; }

echo "== #309 one safe read =="
case_ c_symlink_ok "AGENTS.md -> a tracked regular CLAUDE.md passes, stderr empty"
case_ c_symlink_chain_escape "a two-link chain leaving the repository fails at the first hop, nothing read"
case_ c_symlink_chain_inside "a chain that stays inside the repository still fails"
case_ c_symlink_chain_three "a three-link chain fails naming the first hop, nothing read"
case_ c_symlink_escape_one "a one-level escape gives the required fail as the only AGENTS.md row, nothing read"
case_ c_symlink_abs "an absolute target fails even when the path minus its slash is tracked (#310)"
case_ c_symlink_subdir "a relative target resolves from the link's own directory"
case_ c_symlink_dir "a directory target is a fail row, never exit 2"
case_ c_symlink_glob "a glob or pathspec-magic target is not a tracked file"
case_ c_symlink_dangling "a dangling target fails, stderr empty"
case_ c_contrib_regular "a regular CONTRIBUTING.md is scanned"
case_ c_contrib_symlink "a symlinked CONTRIBUTING.md is one fail row, never read"
case_ c_prtemplate_symlink "a symlinked PR template is one fail row, never read"
case_ c_docs_regular "a regular --docs file is scanned"
case_ c_docs_tracked_symlink "a tracked --docs symlink is refused, never read"
case_ c_docs_untracked_symlink "an untracked --docs symlink is refused, never read"
case_ c_docs_symlinked_parent "a --docs path under a symlinked folder is refused, never read"
case_ c_docs_sibling_prefix "a sibling directory sharing the repository's name prefix is outside"
case_ c_docs_dash_parent "a dash-led --docs folder is resolved, not read as an option"
case_ c_make_symlink_passwd "a Makefile linked to a runner file is refused, no oracle"
case_ c_just_symlink "a justfile linked outside is refused, never read"
case_ c_make_symlink_devzero "a Makefile linked to /dev/zero is refused within the bound"
case_ c_make_regular "a regular Makefile answers targets"
case_ c_make_awk_fails "a make read that fails is exit 2 with nothing on stdout"
case_ c_row_plain_target "every row has four fields"
case_ c_row_newline_target "a newline, CR or ESC in a link target becomes ? and forges no row"
case_ c_row_newline_name "a newline, CR or ESC in a file name becomes ? and forges no row"
case_ c_tracked_newline_name "a newline file name cannot forge CLAUDE.md as tracked"
case_ c_tracked_newline_dir "a newline file name cannot forge a tracked directory"
case_ c_tracked_tab_name "a TAB-led file name cannot forge CLAUDE.md as tracked"
case_ c_tracked_tab_inner "a file name with an inner TAB cannot forge CLAUDE.md as tracked"
case_ c_tracked_tab_shadow "a TAB-led name cannot shadow a tracked CLAUDE.md symlink"
case_ c_submodule_doc "a doc path that is a submodule is a fail row, never read"

# ---------------------------------------------------------------- #301: CLAUDE.md @-imports
# The grammar is Claude Code's, measured on 2.1.287 (see the script header). The exit-0 cases use
# `agents`, since a missing AGENTS.md is itself a fail row.
claudemd() { tput_ CLAUDE.md "$1"; }
# lines <line>...: the lines joined as `put` text, one per argument (keeps an @ off a \n in the source).
lines() { printf '%s\\n' "$@"; }
nimp() { count "$1" import; }
c_imp_pass() { new; agents 'x\n'; claudemd 'See @docs/DEV.md for setup.\n'; tput_ docs/DEV.md 'x\n'; run
  rc_is 0 && at pass CLAUDE.md:1 "docs/DEV.md: tracked (docs/DEV.md)"; }
c_imp_untracked() { new; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ .gitignore 'docs/DEV.md\n'; put docs/DEV.md 'x\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/DEV.md: imported by CLAUDE.md but not in a clone"; }
c_imp_ignored() { new; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md 'x\n'; git -C "$R" commit --quiet -m a; tput_ .gitignore 'docs/DEV.md\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "tracked but ignored"; }
c_imp_scanned() { new; pkg '"build":"x"'; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md 'a\n\n`npm run nope`\n'; run
  rc_is 1 && at pass CLAUDE.md:1 "docs/DEV.md" && at fail docs/DEV.md:3 "npm run nope: no such script"; }
c_imp_scanned_ok() { new; pkg '"build":"x"'; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md '`npm run build`\n'; run
  rc_is 0 && at pass CLAUDE.md:1 "docs/DEV.md" && at pass docs/DEV.md:1 "npm run build"; }
c_imp_relative() { new; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md '@sub/x.md\n'; tput_ docs/sub/x.md 'x\n'; run
  rc_is 0 && at pass docs/DEV.md:1 "sub/x.md: tracked (docs/sub/x.md)"; }
c_imp_relative_neg() { new; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md '@sub/x.md\n'; tput_ sub/x.md 'x\n'; run
  rc_is 1 && at fail docs/DEV.md:1 "sub/x.md: imported by docs/DEV.md but not in a clone"; }
chain() { claudemd '@a1.md\n'; tput_ a1.md '@a2.md\n'; tput_ a2.md '@a3.md\n'; tput_ a3.md '@a4.md\n'; }
c_imp_depth_pos() { new; agents 'x\n'; chain; tput_ a4.md 'See [d](dead.md).\n'; run
  rc_is 1 && at fail a4.md:1 "dead.md is not a tracked path"; }
c_imp_depth_neg() { new; agents 'x\n'; chain; tput_ a4.md '@a5.md\n'; tput_ a5.md 'See [d](dead.md).\n'; run
  rc_is 0 && at referred a4.md:1 "beyond Claude Code's depth of 4; not loaded" && ! at fail a5.md ""; }
bfs() { tput_ a1.md '@a2.md\n'; tput_ a2.md '@a3.md\n'; tput_ a3.md '@f.md\n'; tput_ s.md '@f.md\n'; tput_ f.md '@g1.md\n'; tput_ g1.md 'See [d](dead.md).\n'; }
c_imp_bfs() { new; agents 'x\n'; claudemd "$(lines @s.md @a1.md)"; bfs; run
  rc_is 1 && at fail g1.md:1 "dead.md is not a tracked path"; }
c_imp_bfs_neg() { new; agents 'x\n'; claudemd '@a1.md\n'; bfs; run
  rc_is 0 && at referred f.md:1 "beyond Claude Code's depth" && ! at fail g1.md ""; }
c_imp_cycle() { new; agents 'x\n'; claudemd '@a.md\n'; tput_ a.md '@b.md\n'; tput_ b.md '@a.md\n\nSee [d](dead.md).\n'; run
  rc_is 1 && [ "$(count fail link)" = 1 ] && [ "$(nimp pass)" = 3 ]; }
c_imp_repeat() { new; agents 'x\n'; claudemd "$(lines @a.md @a.md)"; tput_ a.md 'See [d](dead.md).\n'; run
  rc_is 1 && [ "$(nimp pass)" = 2 ] && [ "$(count fail link)" = 1 ]; }
c_imp_punct_ok() { new; agents 'x\n'; claudemd 'Setup: @docs/DEV.md\n'; tput_ docs/DEV.md 'x\n'; run
  rc_is 0 && at pass CLAUDE.md:1 "docs/DEV.md"; }
c_imp_punct() { new; agents 'x\n'; claudemd 'Setup: @docs/DEV.md.\n'; tput_ docs/DEV.md 'x\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/DEV.md.: imported by CLAUDE.md but not in a clone; Claude Code reads the trailing punctuation" && [ "$(nimp pass)" = 0 ]; }
c_imp_not_tokens() { new; agents 'x\n'; claudemd "$(lines 'write to a.b@example.com' 'ask @maintainer' '' '`cat @missing.md now`' '' '```' '@missing.md' '```' '' 'see (@missing.md)')"; run
  rc_is 0 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 0 ]; }
c_imp_escaped_space() { new; agents 'x\n'; claudemd '@docs/My\\ File.md\n'; tput_ "docs/My File.md" 'x\n'; run
  rc_is 0 && [ "$(nimp pass)" = 1 ] && row pass import "docs/My File.md: tracked"; }
c_imp_escaped_space_neg() { new; agents 'x\n'; claudemd '@docs/My\\ File.md\n'; run
  rc_is 1 && [ "$(nimp fail)" = 1 ] && row fail import "docs/My File.md: imported by" && none 'My\'; }
dead='`npm run nope`\n\n[dead](missing.md)\n\n@docs/missing.md\n'
c_imp_nonmd() { new; pkg '"x":"x"'; agents 'x\n'; claudemd '@docs/DEV.md\n@src/x.ts\n'; tput_ docs/DEV.md "$dead"; tput_ src/x.ts "$dead"; run
  rc_is 1 && [ "$(nimp pass)" = 2 ] && at fail docs/DEV.md:1 "npm run nope" && at fail docs/DEV.md:3 "missing.md" && at fail docs/DEV.md:5 "docs/missing.md" && ! at fail src/x.ts ""; }
c_imp_nonmd_only() { new; pkg '"x":"x"'; agents 'x\n'; claudemd '@src/x.ts\n'; tput_ src/x.ts "$dead"; run
  rc_is 0 && [ "$(nimp pass)" = 1 ] && at pass CLAUDE.md:1 "src/x.ts: tracked" && [ "$(grep -c . <<<"$OUT")" = 4 ]; }
c_imp_nonmd_untracked() { new; agents 'x\n'; claudemd '@src/x.ts\n'; put src/x.ts 'x\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "src/x.ts: imported by CLAUDE.md but not in a clone"; }
c_imp_symlink_ok() { new; agents 'x\n'; claudemd '@docs/link.md\n'; tput_ docs/real.md 'x\n'; lnk real.md docs/link.md; run
  rc_is 0 && at pass CLAUDE.md:1 "symlink to tracked docs/real.md"; }
c_imp_symlink_escape() { new; agents 'x\n'; claudemd '@docs/link.md\n'; lnk ../../outside.md docs/link.md; run
  rc_is 1 && at fail CLAUDE.md:1 "escapes the repository" && no_token || return 1
  new; agents 'x\n'; claudemd '@docs/link.md\n'; tput_ .gitignore 'docs/u.md\n'; put docs/u.md 'x\n'; lnk u.md docs/link.md; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/u.md, which is not tracked, so it is local only"; }
c_imp_symlink_chain() { new; agents 'x\n'; claudemd '@docs/link.md\n'; lnk ../../outside.md docs/l2.md; lnk l2.md docs/link.md; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/l2.md, which is itself a symlink" && no_token; }
c_imp_symlink_dir() { new; agents 'x\n'; claudemd '@docs/dir.md\n'; tput_ docs/sub/x.md 'x\n'; lnk sub docs/dir.md; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/sub, a directory, which is not a tracked file"; }
c_imp_symlink_abs() { new; agents 'x\n'; claudemd '@docs/link.md\n'; tput_ "${W#/}/outside.md" 'decoy\n'; lnk "$W/outside.md" docs/link.md; run
  rc_is 1 && at fail CLAUDE.md:1 "which is an absolute path a clone does not have" && no_token; }
c_imp_symlink_target_dir() { new; agents 'x\n'; claudemd '@docs/link.md\n'; tput_ other/real.md '@rel.md\n'; tput_ other/rel.md 'x\n'; lnk ../other/real.md docs/link.md; run
  rc_is 0 && at pass other/real.md:1 "rel.md: tracked (other/rel.md)"; }
c_imp_visited_resolved() { new; agents 'x\n'; claudemd '@docs/link.md\n@docs/real.md\n'; tput_ docs/real.md 'See [d](dead.md).\n'; lnk real.md docs/link.md; run
  rc_is 1 && [ "$(nimp pass)" = 2 ] && [ "$(count fail link)" = 1 ]; }
c_imp_visited_two() { new; agents 'x\n'; claudemd '@docs/a.md\n@docs/b.md\n'; tput_ docs/a.md 'See [d](dead.md).\n'; tput_ docs/b.md 'See [d](dead.md).\n'; run
  rc_is 1 && [ "$(nimp pass)" = 2 ] && [ "$(count fail link)" = 2 ]; }
c_imp_deleted_worktree() { new; agents 'x\n'; claudemd '@docs/DEV.md\n@src/x.ts\n'; tput_ docs/DEV.md 'See [d](dead.md).\n'; tput_ src/x.ts 'x\n'
  rm "$R/docs/DEV.md" "$R/src/x.ts"; run
  rc_is 1 && at pass CLAUDE.md:1 "docs/DEV.md" && at pass CLAUDE.md:2 "src/x.ts" && at fail docs/DEV.md:1 "dead.md"; }
c_imp_home_abs() { new; agents 'x\n'; claudemd '@~/.claude/my-rules.md\n@/etc/local-rules.md\n'; run
  rc_is 0 && at referred CLAUDE.md:1 "home path; a personal import, legitimately local" && at referred CLAUDE.md:2 "absolute path; machine specific"; }
c_imp_escape() { new; agents 'x\n'; claudemd '@../outside.md\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "../outside.md: escapes the repository" && no_token; }
c_imp_agents_not_parsed() { new; agents 'Ask @docs/missing.md and @docs/t.md.\n'; claudemd '@AGENTS.md\n'; tput_ docs/t.md 'See [d](dead.md).\n'; run
  rc_is 0 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 1 ] && at pass CLAUDE.md:1 "AGENTS.md" && ! at fail docs/t.md ""; }
c_imp_no_claude() { new; agents 'Ask @docs/missing.md here.\n'; run
  rc_is 0 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 0 ]; }
c_imp_entry_tracked() { new; agents 'x\n'; claudemd '@docs/missing.md\n'; run
  rc_is 1 && at fail CLAUDE.md:1 "docs/missing.md: imported by CLAUDE.md"; }
c_imp_entry_untracked() { new; agents 'x\n'; tput_ .gitignore 'CLAUDE.md\n'; put CLAUDE.md '@docs/missing.md\n'; run
  rc_is 0 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 0 ]; }
c_imp_docs_flag() { new; agents 'x\n'; claudemd '@docs/missing.md\n'; tput_ docs/g.md 'See [x](https://example.com/).\n'; run --docs docs/g.md
  rc_is 0 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 0 ]; }
c_imp_dedupe() { new; pkg '"x":"x"'; agents '`npm run nope`\n'; claudemd '@AGENTS.md\n'; run
  rc_is 1 && at pass CLAUDE.md:1 "AGENTS.md" && [ "$(count fail command)" = 1 ]; }
c_imp_dedupe_neg() { new; pkg '"x":"x"'; agents 'x\n'; claudemd '@docs/DEV.md\n'; tput_ docs/DEV.md '`npm run nope`\n'; run
  rc_is 1 && [ "$(count fail command)" = 1 ] && at fail docs/DEV.md:1 "nope"; }
c_imp_injection() { new; agents 'x\n'; claudemd '@a$(touch${IFS}pwned).md\n@a;touch${IFS}pwned;.md\n'; run
  rc_is 1 && [ "$(nimp fail)" = 2 ] && row fail import 'a$(touch${IFS}pwned).md' && row fail import 'a;touch${IFS}pwned;.md' && [ ! -e "$R/pwned" ]; }
c_imp_malformed() { new; agents 'x\n'; claudemd "$(lines @ @. @/ '@docs/x\\' '```' @a.md)"; run
  [ "$RC" != 2 ] && [ -z "$ERR" ] || return 1
  new; agents 'x\n'; claudemd '@docs/DEV.md\r\n'; tput_ docs/DEV.md 'x\r\n'; run
  rc_is 0 && at pass CLAUDE.md:1 "docs/DEV.md: tracked"; }
c_imp_claude_symlink() { new; agents '`npm run nope`\n'; pkg '"x":"x"'; lnk AGENTS.md CLAUDE.md; run
  rc_is 1 && [ "$(grep -c "$(printf '\timport\t')" <<<"$OUT")" = 0 ] && [ "$(count fail command)" = 1 ] || return 1
  new; agents 'x\n'; lnk ../outside.md CLAUDE.md; run
  rc_is 1 && at fail CLAUDE.md "CLAUDE.md links to ../outside.md, which escapes the repository" && no_token || return 1
  new; agents 'x\n'; tput_ docs/main.md '@x.md\n'; tput_ docs/x.md 'x\n'; lnk docs/main.md CLAUDE.md; run
  rc_is 0 && at pass docs/main.md:1 "x.md: tracked (docs/x.md)"; }

echo "== #301 CLAUDE.md imports =="
case_ c_imp_pass "a tracked import passes at the importing line"
case_ c_imp_untracked "an import a clone does not have fails"
case_ c_imp_ignored "a tracked import an ignore rule matches fails"
case_ c_imp_scanned "an imported doc's broken command fails at its own line"
case_ c_imp_scanned_ok "an imported doc's defined command passes at its own line"
case_ c_imp_relative "a nested import resolves from the importing file's directory"
case_ c_imp_relative_neg "a nested import is never resolved from the root"
case_ c_imp_depth_pos "the hop-4 file is scanned"
case_ c_imp_depth_neg "an import at hop 5 is referred and never scanned"
case_ c_imp_bfs "a file reachable by a short route is judged at its shortest hop"
case_ c_imp_bfs_neg "the same file reachable only by the long route stops at the cap"
case_ c_imp_cycle "a cycle terminates and scans each file once"
case_ c_imp_repeat "a repeated import gets a row each time and is scanned once"
case_ c_imp_punct_ok "an import with no trailing punctuation passes"
case_ c_imp_punct "trailing punctuation is part of the path, as Claude Code reads it"
case_ c_imp_not_tokens "an email, a handle, a span, a fence and (@x) are not imports"
case_ c_imp_escaped_space "an escaped space stays inside one token"
case_ c_imp_escaped_space_neg "a missing escaped-space target is one fail row"
case_ c_imp_nonmd "only a markdown import is scanned"
case_ c_imp_nonmd_only "a non-markdown import gets its existence row only"
case_ c_imp_nonmd_untracked "a non-markdown import a clone does not have fails"
case_ c_imp_symlink_ok "a symlink import passes by its tracked target"
case_ c_imp_symlink_escape "a symlink import escaping or to an untracked file fails, never read"
case_ c_imp_symlink_chain "a symlink import chain fails at the first hop, never read"
case_ c_imp_symlink_dir "a symlink import to a directory is a fail row"
case_ c_imp_symlink_abs "an absolute symlink import target fails even with a decoy, never read"
case_ c_imp_symlink_target_dir "imports inside a symlinked file resolve from the target's directory"
case_ c_imp_visited_resolved "a link and its target are scanned once"
case_ c_imp_visited_two "two distinct imports are each scanned"
case_ c_imp_deleted_worktree "a tracked import deleted from the worktree is read from the index"
case_ c_imp_home_abs "a home or absolute import is referred and never opened"
case_ c_imp_escape "an escaping import fails and is never read"
case_ c_imp_agents_not_parsed "AGENTS.md's own @ tokens are never followed"
case_ c_imp_no_claude "with no CLAUDE.md there is no import row"
case_ c_imp_entry_tracked "a tracked CLAUDE.md's missing import fails"
case_ c_imp_entry_untracked "an untracked CLAUDE.md is not followed"
case_ c_imp_docs_flag "--docs replaces the set, so imports are not followed"
case_ c_imp_dedupe "@AGENTS.md is scanned once"
case_ c_imp_dedupe_neg "an import's broken command is reported once at its own file"
case_ c_imp_injection "an import holding shell syntax is data, never run"
case_ c_imp_malformed "malformed tokens and CRLF give rows or nothing, never a crash"
case_ c_imp_claude_symlink "a symlinked CLAUDE.md is judged by its target before it is read"

# ---------------------------------------------------------------- check 3: commands
c_build() { new; pkg '"build":"x"'; agents 'Run `npm run build`.\n'; run
  rc_is 0 && row pass command "npm run build"; }
c_contrib() { new; pkg '"x":"x"'; agents 'x\n'; tput_ .github/CONTRIBUTING.md 'Run `npm run lint` and `npm run --silent lint`.\n'; run
  rc_is 1 && at fail .github/CONTRIBUTING.md:1 "npm run lint: no such script" && [ "$(count fail command)" = 2 ] && none "--silent"; }
c_prose() { new; pkg '"x":"x"'; agents 'Before pushing:\nnpm run lint checks style.\n'; run
  rc_is 0 && none lint; }
c_referred() { new; pkg '"x":"x"'
  agents '`yarn prettier`\n\n`yarn run prettier`\n\n`pnpm -r build`\n\n`npm run --prefix pkg lint`\n\n`npm run lint --if-present`\n\n`npm -ws run lint`\n\n`npm run <script>`\n'; run
  rc_is 0 && [ "$(count referred command)" = 7 ] && nostatus fail; }
c_yarn_run() { new; pkg '"x":"x"'; agents '`yarn run prettier`\n'; run
  rc_is 0 && row referred command "yarn run prettier"; }
c_flag_after() { new; pkg '"x":"x"'; agents '`npm run lint --if-present`\n'; run
  rc_is 0 && row referred command "--if-present may change"; }
c_pnpm() { new; pkg '"x":"x"'; agents '`pnpm run lint`\n\n`npm run -s lint.`\n'; run
  rc_is 1 && row fail command "pnpm run lint: no such" && row fail command "npm run lint: no such"; }
c_make_include() { new
  tput_ Makefile 'include common.mk\nbuild:\n\techo b\n'
  tput_ common.rule 'x\n'
  printf 'common.mk:\n\ttouch made-sentinel\n' >> "$R/Makefile"; git -C "$R" add Makefile
  agents '`make release`\n\n`make build`\n'; run
  rc_is 0 && row referred command "make release: not literal" && row pass command "make build" && [ ! -e "$R/made-sentinel" ]; }
c_make_absent() { new; tput_ Makefile 'build:\n\techo b\n'; agents '`make deploy`\n'; run
  rc_is 1 && row fail command "make deploy: no such target in Makefile"; }
c_just() { new; tput_ justfile 'build:\n  echo b\n'; agents '`just build`\n\n`just ship`\n'; run
  rc_is 1 && row pass command "just build" && row fail command "just ship"; }
c_make_bom() { new; tput_ Makefile '\xef\xbb\xbfdev:\n\t@echo x\n'; agents '`make dev`\n'; run
  rc_is 0 && row pass command "make dev: defined in Makefile" && at pass AGENTS.md:1 "make dev: defined in Makefile"; }
c_make_bom_neg() { new; tput_ Makefile '\xef\xbb\xbfbuild:\n\t@echo x\n'; agents '`make deploy`\n'; run
  rc_is 1 && row fail command "make deploy: no such target in Makefile" && at fail AGENTS.md:1 "make deploy: no such target in Makefile"; }
c_make_bom_include() { new; tput_ Makefile '\xef\xbb\xbfinclude common.mk\nbuild:\n\techo b\n'; agents '`make release`\n'; run
  rc_is 0 && row referred command "make release: not literal in Makefile, which includes or imports others" && at referred AGENTS.md:1 "make release"; }
c_make_bom_later_line() { new; tput_ Makefile 'build:\n\t@echo x\n\xef\xbb\xbfdev:\n\t@echo y\n'; agents '`make dev`\n'; run
  rc_is 1 && row fail command "make dev: no such target in Makefile" && at fail AGENTS.md:1 "make dev: no such target in Makefile"; }
c_make_bom_crlf() { new; tput_ Makefile '\xef\xbb\xbfdev:\r\n\t@echo x\r\n'; agents '`make dev`\n'; run
  rc_is 0 && row pass command "make dev: defined in Makefile"; }
c_just_bom() { new; tput_ justfile '\xef\xbb\xbfbuild:\n  echo b\n'; agents '`just build`\n'; run
  rc_is 0 && row pass command "just build: defined in justfile" && at pass AGENTS.md:1 "just build: defined in justfile"; }
c_just_bom_neg() { new; tput_ justfile '\xef\xbb\xbfbuild:\n  echo b\n'; agents '`just ship`\n'; run
  rc_is 1 && row fail command "just ship: no such target in justfile" && at fail AGENTS.md:1 "just ship: no such target in justfile"; }
c_just_bom_fallback() { new; tput_ justfile '\xef\xbb\xbfset fallback\nbuild:\n  echo b\n'; agents '`just ship`\n'; run
  rc_is 0 && row referred command "just ship: not literal in justfile, which includes or imports others" && at referred AGENTS.md:1 "just ship"; }
c_just_bom_set_shell() { new; tput_ justfile '\xef\xbb\xbfset shell := ["bash", "-c"]\nbuild:\n  echo b\n'; agents '`just ship`\n'; run
  rc_is 1 && row fail command "just ship: no such target in justfile" && at fail AGENTS.md:1 "just ship: no such target in justfile"; }
c_doc_bom_fence_neg() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents '\xef\xbb\xbf```sh\nmake nope\n```\n'; run
  rc_is 1 && row fail command "make nope: no such target in Makefile" && at fail AGENTS.md:2 "make nope: no such target in Makefile"; }
c_doc_bom_fence_pos() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents '\xef\xbb\xbf```sh\nmake all\n```\n'; run
  rc_is 0 && row pass command "make all: defined in Makefile" && at pass AGENTS.md:2 "make all: defined in Makefile"; }
# #385: the BOM strip and the CR strip together, a BOM-led doc with CRLF endings.
c_doc_bom_crlf_neg() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents '\xef\xbb\xbf```sh\r\nmake nope\r\n```\r\n'; run
  rc_is 1 && row fail command "make nope: no such target in Makefile" && at fail AGENTS.md:2 "make nope: no such target in Makefile"; }
c_doc_bom_crlf_pos() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents '\xef\xbb\xbf```sh\r\nmake all\r\n```\r\n'; run
  rc_is 0 && row pass command "make all: defined in Makefile" && at pass AGENTS.md:2 "make all: defined in Makefile"; }
c_doc_bom_pairing_neg() { new; tput_ Makefile 'all:\n\t@echo a\n'
  agents '\xef\xbb\xbf```sh\nmake all\n```\n\nRead [guide](missing.md).\n\n```sh\nmake nope\n```\n'; run
  rc_is 1 && at pass AGENTS.md:2 "make all" && at fail AGENTS.md:5 "missing.md is not a tracked path" && at fail AGENTS.md:8 "make nope"; }
c_doc_bom_pairing_pos() { new; tput_ Makefile 'all:\n\t@echo a\n'; tput_ guide.md 'x\n'
  agents '\xef\xbb\xbf```sh\nmake all\n```\n\nRead [guide](guide.md).\n\n```sh\nmake all\n```\n'; run
  rc_is 0 && at pass AGENTS.md:2 "make all" && at pass AGENTS.md:5 "guide.md" && at pass AGENTS.md:8 "make all"; }
c_doc_bom_refdef_neg() { new; agents '\xef\xbb\xbf[g]: missing.md\n'; run
  rc_is 1 && at fail AGENTS.md:1 "missing.md is not a tracked path"; }
c_doc_bom_line2_kept() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents 'intro\n\xef\xbb\xbf```sh\nmake nope\n```\n'; run
  rc_is 0 && nostatus fail && ! grep -q "$(printf '\tcommand\t')" <<<"$OUT"; }
c_doc_bom_prose() { new; agents '\xef\xbb\xbfJust prose, no fence.\n'; run
  rc_is 0 && [ "$(grep -c . <<<"$OUT")" = 3 ] && row pass required "" && nostatus fail; }
c_doc_bom_contributing() { new; tput_ Makefile 'all:\n\t@echo a\n'; agents 'x\n'
  tput_ CONTRIBUTING.md '\xef\xbb\xbf```sh\nmake nope\n```\n'; run --docs CONTRIBUTING.md
  rc_is 1 && at fail CONTRIBUTING.md:2 "make nope: no such target in Makefile"; }
c_cd_forms() { new; pkg '"x":"x"'
  agents '`cd x && npm run y`\n\n```\n(cd x; npm run y)\n```\n\n```sh\npushd x\n$ npm run y\n```\n'; run
  rc_is 0 && [ "$(count referred command)" = 3 ] && [ "$(grep -c 'directory change precedes' <<<"$OUT")" = 3 ]; }
c_cd_other_fence() { new; pkg '"x":"x"'; agents '```\ncd x\n```\n\n```\nnpm run y\n```\n'; run
  rc_is 1 && row fail command "npm run y: no such"; }
c_nopkg() { new; agents '`npm run lint`\n'; run
  rc_is 0 && row referred command "no root package.json is tracked"; }
c_node() { new; tput_ scripts/seed.js 'x\n'; put dist/index.js 'x\n'
  agents '`node scripts/seed.js`\n\n`node dist/index.js`\n'; run
  rc_is 0 && row pass script-path "scripts/seed.js" && row referred script-path "may be a build output"; }

echo "== commands =="
case_ c_build "npm run build, defined, passes"
case_ c_contrib "npm run lint undefined fails in .github/CONTRIBUTING.md, --silent is never the name"
case_ c_prose "a command named only in prose gets no row"
case_ c_referred "seven undecidable shapes are each referred, none fails"
case_ c_yarn_run "yarn run X is referred, since yarn also runs a .bin binary"
case_ c_flag_after "a flag after the script name is referred"
case_ c_pnpm "pnpm run lint fails; npm run -s lint. fails as lint"
case_ c_make_include "make with include is referred, a literal target passes, make never runs"
case_ c_make_absent "make with no such target fails"
case_ c_just "just: a defined recipe passes, an absent one fails"
case_ c_make_bom "a leading byte-order mark does not hide a Makefile's first target"
case_ c_make_bom_neg "a BOM Makefile still fails an absent target"
case_ c_make_bom_include "a BOM before include is referred, never failed"
case_ c_make_bom_later_line "a BOM on a later Makefile line is not stripped"
case_ c_make_bom_crlf "a Makefile with a BOM and CRLF line endings passes"
case_ c_just_bom "a leading byte-order mark does not hide a justfile's first recipe"
case_ c_just_bom_neg "a BOM justfile still fails an absent recipe"
case_ c_just_bom_fallback "a BOM before set fallback is referred, never failed"
case_ c_just_bom_set_shell "a BOM before a set that is not fallback still fails"
case_ c_doc_bom_fence_neg "a leading BOM does not hide a doc's line-1 fence, so a broken command fails"
case_ c_doc_bom_fence_pos "a BOM-led doc's fenced command that is defined passes"
case_ c_doc_bom_pairing_neg "fence pairing after a BOM-led fence is not inverted (commands and a link fail)"
case_ c_doc_bom_pairing_pos "fence pairing after a BOM-led fence is not inverted (commands and a link pass)"
case_ c_doc_bom_refdef_neg "a BOM before a line-1 reference definition still yields its link row"
case_ c_doc_bom_line2_kept "a BOM on line 2 is not stripped"
case_ c_doc_bom_prose "no-regression: a BOM-led doc with no fence emits only the three required rows (passes with or without the strip)"
case_ c_doc_bom_contributing "the BOM strip covers a doc passed with --docs"
case_ c_doc_bom_crlf_neg "a BOM-led doc with CRLF endings still fails a broken fenced command (#385)"
case_ c_doc_bom_crlf_pos "a BOM-led doc with CRLF endings passes a defined fenced command (#385)"
case_ c_cd_forms "cd in a span, a subshell in a fence and pushd in a fence each refer"
case_ c_cd_other_fence "a cd in an earlier fence does not reach a later fence"
case_ c_nopkg "no tracked root package.json refers"
case_ c_node "node: a tracked path passes, an untracked build output refers"

# ---------------------------------------------------------------- check 4: links
c_link_parent() { new; agents 'x\n'; tput_ docs/TESTING.md 'x\n'; tput_ .github/CONTRIBUTING.md 'See [t](../docs/TESTING.md).\n'; run
  rc_is 0 && at pass .github/CONTRIBUTING.md:1 "../docs/TESTING.md: tracked"; }
c_link_ignored() { new; tput_ .gitignore 'CLAUDE.md\n'; put CLAUDE.md 'x\n'; agents 'See [c](CLAUDE.md).\n'; run
  rc_is 1 && at fail AGENTS.md:1 "CLAUDE.md exists on disk but is not tracked"; }
c_link_dir() { new; tput_ docs/guide.md 'x\n'; agents 'See [d](docs/) and [r](/).\n'; run
  rc_is 0 && row pass link "docs/: tracked" && row pass link "/: tracked (repository root)"; }
c_link_misc() { new; tput_ docs/X.md 'x\n'; tput_ 'docs/a b.md' 'x\n'
  tput_ .github/CONTRIBUTING.md '[r](/docs/X.md) [p](../docs/a%20b.md) [q](<../docs/a b.md>) ![i](../docs/X.md#top)\n\n[id]: gone.md\n\n`[x](nope.md)`\n'
  agents 'x\n'; run
  rc_is 1 && row pass link "/docs/X.md: tracked" && row pass link "a b.md: tracked" \
    && [ "$(count pass link)" = 4 ] && row fail link "gone.md is not a tracked path" && none nope.md; }
# A read of a path outside the repository is proved by a FIFO, never by file timestamps and never
# by content. Access time is vacuous on a mount that records no reads, which made this suite
# falsely RED there (#305); content cannot work either, because the mutant below discards what it
# reads. So the sentinel is a named pipe with a writer parked on it: that writer blocks in open()
# until something opens the FIFO for read. The shipped script classifies the escape lexically and
# never opens the path, so after the run the writer is still parked and a bounded probe read
# succeeds. A script that opens the path (cat, head, read, even `: <`) consumes the writer, so the
# probe finds none and times out, and the case fails. A stat is deliberately not an open.
# The probe and the cleanup run BEFORE the assertion chain, so a failing assertion cannot skip them.
# A script that opens the path TWICE would block its second open forever and hang `run`, so a
# watchdog releases that opener after a bound; the probe then finds no writer and fails the case
# instead of hanging the suite. The sentinel is removed before mkfifo because this case runs twice
# (shipped script, then mutant) in one $W. The watchdog cannot release a third opener or a
# write-open, so `run` also bounds the script under test (ESCAPE_WATCHDOG_SECS + 5 s, see
# `bounded`): a hang is killed, RC becomes 124 and the case fails by name. A TMPDIR without FIFO support fails mkfifo, and the case
# fails loudly with it.
c_escape() { new; agents 'See [s](../sentinel) and [h](../../etc/hosts) and [g](docs/guide.md).\n'; tput_ docs/guide.md 'x\n'
  rm -f "$W/sentinel"; mkfifo "$W/sentinel" || return 1
  { printf 'secret\n' > "$W/sentinel"; } & ESC_WPID=$!
  ESC_DPID=$( set -m; { sleep "$ESCAPE_WATCHDOG_SECS"; printf 'x\n' > "$W/sentinel"; } >/dev/null 2>&1 & echo $! )
  run
  kill -KILL -- -"$ESC_DPID" 2>/dev/null; ESC_DPID=""
  local probe=0; bounded 2 cat "$W/sentinel" >/dev/null 2>&1 && probe=1
  { kill -KILL "$ESC_WPID"; wait "$ESC_WPID"; } 2>/dev/null; ESC_WPID=""
  [ "$probe" = 1 ] && rc_is 1 && row fail link "../sentinel: escapes the repository" \
    && row fail link "../../etc/hosts: escapes" && row pass link "docs/guide.md" && none secret; }
c_ref_title() { new; tput_ docs/guide.md 'x\n'; agents '[g]: docs/guide.md "Guide"\n'; run
  rc_is 0 && row pass link "docs/guide.md" && none Guide; }
c_ref_title_fail() { new; agents "[g]: gone.md 'Guide'\n"; run
  rc_is 1 && row fail link "gone.md is not a tracked path" && none Guide; }

echo "== links =="
case_ c_link_parent "a link resolves against its own file's directory"
case_ c_link_ignored "a link to a gitignored file on disk fails as untracked"
case_ c_link_dir "a directory link passes when a tracked path lies under it, / is the root"
case_ c_link_misc "root-relative, %20, <...>, image and anchor pass; a dead reference fails; a span link is no link"
case_ c_escape "an escaping link fails with exit 1 and the outside sentinel is never read"
case_ c_ref_title "a reference title is ignored for a tracked target"
case_ c_ref_title_fail "a reference title is ignored for an untracked target"

# ---------------------------------------------------------------- PR templates
c_tmpl() { new
  agents 'x\n'
  tput_ .github/PULL_REQUEST_TEMPLATE.md 'See [a](../AGENTS.md) and [x](../../x).\n'
  tput_ docs/pull_request_template.md 'See [a](../AGENTS.md).\n'
  tput_ .github/PULL_REQUEST_TEMPLATE/x.md 'See [a](../../AGENTS.md).\n'
  tput_ PULL_REQUEST_TEMPLATE 'See [a](AGENTS.md).\n'; run
  rc_is 0 && [ "$(count referred link)" = 5 ] && [ "$(count pass link)" = 0 ] \
    && [ "$(grep -c 'PR URL' <<<"$OUT")" = 5 ]; }
c_tmpl_txt() { new; agents 'x\n'; tput_ .github/pull_request_template.txt 'See [a](../AGENTS.md).\n'; run
  rc_is 0 && at referred .github/pull_request_template.txt:1 "PR URL"; }
c_tmpl_abs() { new; agents 'x\n'; tput_ .github/pull_request_template.txt 'See [a](https://github.com/o/r/blob/main/AGENTS.md).\n'; run
  rc_is 0 && none github.com; }

echo "== PR templates =="
case_ c_tmpl "relative links in four template locations refer, never pass, escape included"
case_ c_tmpl_txt "a .txt PR template is scanned and refers"
case_ c_tmpl_abs "an absolute link in a template gets no row"

# ---------------------------------------------------------------- #295 amendments
c_para_span() { new; pkg '"x":"x"'; agents 'Run `cd client`, then `npm run dev`.\n'; run
  rc_is 0 && row referred command "npm run dev: a directory change precedes it" && nostatus fail; }
c_para_next() { new; pkg '"x":"x"'; agents 'Run `cd client` first.\n\nThen `npm run dev`.\n'; run
  rc_is 1 && row fail command "npm run dev: no such"; }
c_para_crlf() { new; pkg '"x":"x"'; agents 'Run `cd client` first.\r\n\r\nThen `npm run dev`.\r\n'; run
  rc_is 1 && row fail command "npm run dev: no such"; }
c_cd_root_defined() { new; pkg '"build":"x"'; agents '```\ncd packages/api\nnpm run build\n```\n'; run
  rc_is 0 && row referred command "npm run build: a directory change" && ! row pass command "npm run build"; }
c_cd_after() { new; pkg '"x":"x"'; agents '```\nnpm run lint\ncd packages/api\n```\n'; run
  rc_is 1 && row fail command "npm run lint: no such"; }
c_pkg_tracked() { new; pkg '"lint":"x"'; agents '`npm run lint`\n'; run; rc_is 0 && row pass command "npm run lint"; }
c_pkg_untracked() { new; put package.json '{"scripts":{"lint":"x"}}\n'; agents '`npm run lint`\n'; run
  rc_is 0 && row referred command "no root package.json" && ! row pass command lint; }
c_index_blob() { new; pkg '"x":"x"'; put package.json '{"scripts":{"lint":"x"}}\n'; agents '`npm run lint`\n'; run
  rc_is 1 && row fail command "npm run lint: no such"; }
# #299 moved both: `yarn run lint` now resolves against package.json, so it needs jq, and the
# early-referred shapes below are what still decide without it.
c_nojq_yarn() { new; pkg '"x":"x"'
  agents '`yarn --cwd p build`\n\n`pnpm --filter "web*" run x`\n\n`npm -ws run lint`\n'; run_nojq
  rc_is 0 && [ "$(count referred command)" = 3 ] && [ -z "$ERR" ]; }
c_nojq_npm() { new; pkg '"x":"x"'; agents '`yarn --cwd p a`\n\n`npm run lint`\n'; run_nojq
  rc_is 2 && [ -z "$OUT" ] && grep -q jq <<<"$ERR"; }
c_malformed() { new; tput_ package.json '[1, 2]\n'; agents '`npm run lint`\n'; run
  rc_is 2 && [ -z "$OUT" ] && grep -q malformed <<<"$ERR"; }
c_fence_closed() { new; pkg '"x":"x"'; agents '```\nnpm run nope\n```\n\n[x](missing.md)\n'; run
  rc_is 1 && row fail command "npm run nope" && row fail link "missing.md"; }
c_fence_unclosed() { new; pkg '"x":"x"'; agents '```\nnpm run nope\n\n[x](missing.md)\n'; run
  rc_is 1 && row fail command "npm run nope" && none missing.md; }
c_fence_backtick() { new; pkg '"x":"x"'; agents '```\n`npm run nope`\n```\n'; run
  rc_is 0 && row referred command "not a literal script name" && nostatus fail; }
c_env_prefix() { new; pkg '"x":"x"'; agents '```\nnpm_config_workspace=client npm run dev\n```\n\n`FOO=1 pnpm run y`\n'; run
  rc_is 0 && row referred command "npm run dev: an environment assignment" && row referred command "pnpm run y: an environment" && nostatus fail; }
c_env_bare() { new; pkg '"x":"x"'; agents '```\n$ npm run dev\n```\n'; run; rc_is 1 && row fail command "npm run dev: no such"; }

echo "== #295 amendments =="
case_ c_para_span "a cd span earlier in the same paragraph refers a span command"
case_ c_para_next "a cd in the previous paragraph does not"
case_ c_para_crlf "a CRLF blank line ends the paragraph too"
case_ c_cd_root_defined "a preceding cd refers even when the root defines the script"
case_ c_cd_after "a cd after the command changes nothing"
case_ c_pkg_tracked "a tracked root package.json defining the script passes"
case_ c_pkg_untracked "an untracked package.json on disk refers, never passes"
case_ c_index_blob "scripts resolve from the index blob, not the working tree"
case_ c_nojq_yarn "no jq and nothing reaching resolution: exit 0"
case_ c_nojq_npm "no jq and a command reaching resolution: exit 2, empty stdout, jq named"
case_ c_malformed "a malformed package.json: exit 2, empty stdout"
case_ c_fence_closed "after a closed fence, the command and the dead link both fail"
case_ c_fence_unclosed "an unclosed fence runs to EOF, so its tail is never a link"
case_ c_fence_backtick "a backticked command inside a fence refers"
case_ c_env_prefix "an assignment before npm run refers the row"
case_ c_env_bare "a bare npm run after a prompt still fails"


# ---------------------------------------------------------------- #296: exports and substitutions
# Every case here uses a root with no `dev` and no `nope`, so a `referred` row can only come from
# the carry (a bare `npm run dev` would fail), and a `fail` row proves the carry did NOT apply.
exp() { new; pkg '"x":"x"'; agents "$1"; run; }
c_export_carry() { exp '```\nexport npm_config_workspace=client\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_other_neg() { exp '```\nexport FOO=1\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_gap() { exp '```\nexport npm_config_workspace=client\necho building\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev" && nostatus fail; }
c_export_next_fence() { exp '```\nexport npm_config_workspace=client\n```\n\nthen\n\n```\nnpm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script"; }
c_export_mixed() { exp '```\nexport NPM_Config_Workspace=client\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev" && nostatus fail; }
c_export_node_env_neg() { exp '```\nexport NODE_ENV=production\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_loglevel() { exp '```\nexport npm_config_loglevel=warn\nnpm run nope\n```\n'
  rc_is 0 && row referred command "npm run nope: an environment assignment" && nostatus fail; }
c_export_name_neg() { exp '```\nexport MY_NPM_CONFIG_WORKSPACE=client\nnpm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script" && nocmd referred; }
c_export_empty() { exp '```\nexport npm_config_workspace=\nnpm run nope\n```\n'
  rc_is 0 && row referred command "npm run nope: an environment assignment" && nostatus fail; }
c_export_span() { exp 'Run `export npm_config_workspace=client`, then `npm run dev`.\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_span_blank_neg() { exp 'Run `export npm_config_workspace=client`, then `npm run dev`.\n\nThen run `npm run dev`.\n'
  rc_is 1 && row fail command "npm run dev: no such script" && [ "$(count fail command)" = 1 ]; }
# The stated limit: a prose export does not reach a following fence. Pinned so it is not mistaken
# for coverage and so a change to it is a decision.
c_export_span_fence() { exp 'Run `export npm_config_workspace=client`.\n```\nnpm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script"; }
c_export_andand() { exp '```\nexport npm_config_workspace=client && npm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev" && nostatus fail; }
c_export_after_neg() { exp '```\nnpm run dev && export npm_config_workspace=client\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script"; }
c_export_cd() { exp '```\ncd client\nexport npm_config_workspace=client\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: a directory change precedes it" && nostatus fail; }
# Scenario 8's negative: with no cd, the reason names only the assignment.
c_export_no_cd_reason() { exp '```\nexport npm_config_workspace=client\nnpm run nope\n```\n'
  rc_is 0 && row referred command "npm run nope: an environment assignment precedes it" \
    && none "a directory change" && nostatus fail; }
c_export_declare() { exp '```\ndeclare -x npm_config_workspace=client\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_typeset() { exp '```\ntypeset -x npm_config_workspace=client\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
# declare without -x makes a shell variable that npm never sees.
c_declare_plain_neg() { exp '```\ndeclare npm_config_workspace=client\nnpm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script"; }
c_subst_value() { exp '```\nnpm_config_workspace=$(echo client) npm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_subst_other_neg() { exp '```\necho $(date); npm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_subst_after_neg() { exp '```\nnpm run nope $(echo x)\n```\n'
  rc_is 1 && row fail command "npm run nope" && nocmd referred; }
# The rewrite is anchored at the start of a word: a --workspace=$(...) flag value is not an
# assignment and its row detail must stay as written.
c_subst_flag_value() { exp '```\nnpm run dev --workspace=$(echo client)\n```\n'
  rc_is 0 && row referred command "--workspace=$" && none "--workspace=X"; }
# Doc text is read, never run: neither export nor value substitution may execute its body.
c_pwned() { exp '```\nexport npm_config_workspace=$(touch pwned)\nnpm_config_workspace=$(touch pwned) npm run dev\n```\n'
  [ ! -e "$R/pwned" ] && [ ! -e "$HERE/pwned" ] && rc_is 0 && row referred command "npm run dev" && nostatus fail; }
# Malformed shapes give a row or none, never an awk error: exit 0 or 1, nothing on stderr.
c_export_malformed() {
  exp '```\nexport\nexport npm_config_workspace=$(echo\nexport npm_config_workspace=client\r\nnpm run dev\r\n```\n\n`export` and `x=$(`.\n'
  { rc_is 0 || rc_is 1; } && [ -z "$ERR" ] && row referred command "npm run dev"; }

echo "== #296 exports and substitutions =="
case_ c_export_carry "an export of npm_config_workspace refers a later fence line"
case_ c_export_other_neg "export FOO=1 rescopes nothing: the later runner still fails"
case_ c_export_gap "the carry survives intervening lines of the fence"
case_ c_export_next_fence "the carry does not reach the next fence"
case_ c_export_mixed "the prefix matches in any case"
case_ c_export_node_env_neg "export NODE_ENV=production still fails"
case_ c_export_loglevel "any key under the prefix refers, naming the assignment"
case_ c_export_name_neg "the prefix is anchored at the start of the name"
case_ c_export_empty "an empty-valued export refers, deliberately"
case_ c_export_span "an export in a code span refers a later span in its paragraph"
case_ c_export_span_blank_neg "the paragraph carry ends at the blank line"
case_ c_export_span_fence "a prose export does not carry into a following fence (stated limit)"
case_ c_export_andand "an export refers a later segment of its own line"
case_ c_export_after_neg "an export after the runner changes nothing"
case_ c_export_cd "an export plus a cd keeps the directory-change reason"
case_ c_export_no_cd_reason "an export with no cd names only the assignment"
case_ c_export_declare "declare -x carries like export"
case_ c_export_typeset "typeset -x carries like export"
case_ c_declare_plain_neg "declare without -x exports nothing, so the runner still fails"
case_ c_subst_value "an assignment value that is a substitution refers the row"
case_ c_subst_other_neg "a substitution that is not an assignment value still fails"
case_ c_subst_after_neg "a substitution argument after the runner still fails"
case_ c_subst_flag_value "a flag value substitution is not rewritten"
case_ c_pwned "a substitution body in the document is never executed"
case_ c_export_malformed "bare, unterminated and CRLF shapes yield no awk error"

# ---------------------------------------------------------------- #346: follow-ups to #296
# Same convention as the #296 block: a root with no `dev` and no `nope`, so `referred` can only come
# from a carry or a rewrite and `fail` proves it did not apply.
# rep_ <count> <unit>: <unit> repeated <count> times, for the hostile lines.
rep_() { awk -v n="$1" -v u="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", u }'; }
# anc <fence line>: a NAME=$(...) assignment that must be found after the anchor the line holds.
anc() { exp "\`\`\`\n$1\n\`\`\`\n"
  rc_is 0 && at referred AGENTS.md:2 "npm run dev: an environment assignment precedes it" && nostatus fail; }

# Item 1: only npm, pnpm and yarn read npm_config_, so the carry must not mask make or just.
c_export_make_neg() { new; pkg '"x":"x"'; tput_ Makefile 'build:\n\t@:\n'; agents '```\nexport npm_config_prefix=x\nmake nosuch\n```\n'; run
  rc_is 1 && row fail command "make nosuch: no such target in Makefile" && nocmd referred; }
c_export_just_neg() { new; pkg '"x":"x"'; tput_ justfile 'build:\n  echo b\n'; agents '```\nexport npm_config_prefix=x\njust ship\n```\n'; run
  rc_is 1 && row fail command "just ship: no such target in justfile" && nocmd referred; }
c_export_pnpm() { exp '```\nexport npm_config_workspace=c\npnpm run dev\n```\n'
  rc_is 0 && row referred command "pnpm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_yarn() { exp '```\nexport npm_config_workspace=c\nyarn dev\n```\n'
  rc_is 0 && row referred command "yarn dev: an environment assignment precedes it" && nostatus fail; }

# Item 2: a value with literal text around, or several, substitutions is one assignment. Backtick
# values are not rewritten: no space inside is an ordinary assignment word, a space inside leaves
# no runner (no row at all). The header and SKILL.md say so.
c_subst_prefix_value() { exp '```\nnpm_config_workspace=pre$(echo c) npm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_subst_double_value() { exp '```\nnpm_config_workspace=$(echo a)$(echo b) npm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_subst_backtick_nospace() { exp '```\nnpm_config_workspace=`x` npm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
# #386 review round 1: a NAME= inside a quoted ARGUMENT must not reach past that argument's closing
# quote. These three were silent (fail-open) after #386's first form and fail again now.
c_quoted_arg_name_neg() { exp '```\ngit commit -m "chore: set retries=3" && npm run nope && git push origin "main"\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script in package.json" && nocmd referred; }
c_quoted_arg_name_sq_neg() { exp "\`\`\`\npsql -c 'SELECT * FROM t WHERE id=1' && npm run nope && echo 'done'\n\`\`\`\n"
  rc_is 1 && row fail command "npm run nope: no such script in package.json" && nocmd referred; }
c_quoted_arg_name_end_neg() { exp '```\ngrep "foo=" f && npm run nope && echo "x"\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script in package.json" && nocmd referred; }
c_quoted_arg_name_span_neg() { exp 'Run `git commit -m "set v=2" && npm run nope && echo "ok"` here.\n'
  rc_is 1 && row fail command "npm run nope: no such script in package.json"; }
# Hostile single long words: the word-start marker pass and the export parse are linear on every awk
# (a `(^|...)` alternation sent gawk in a UTF-8 locale to its quadratic matcher, #387 review).
c_long_word_export_linear() { new; pkg '"x":"x"'; agents "\`\`\`\nexport $(head -c 300000 /dev/zero | tr '\0' x) npm_config_workspace=c\nnpm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_long_word_assign_linear() { new; pkg '"x":"x"'; agents "\`\`\`\nFOO=$(head -c 300000 /dev/zero | tr '\0' x) npm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_quoted_arg_hostile_linear() { new; pkg '"dev":"x"'; agents "\`\`\`\n$(rep_ 12000 'g -m "a b=1" ')&& npm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 0 && row pass command "npm run dev" && nostatus fail; }
c_vskip_npm_C() { new; pkg '"x":"x"'; agents '`npm -C run-script run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm -C run-script run x: a flag between npm and run may change which script runs" && ! row referred command "and run-script"; }
c_subst_backtick_space() { exp '```\nnpm_config_workspace=`echo c` npm run dev\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run dev: an environment assignment precedes it" && nostatus fail; }
# #386: an assignment value holding a SPACE (quoted, escaped or in backticks, with or without a
# $(..)) refers the row; it used to give no row at all, so a broken command exited 0.
c_subst_quoted_space_value() { exp '```\nnpm_config_workspace="a b$(echo c)" npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: an environment assignment precedes it" && nostatus fail; }
c_quoted_space_nosubst() { exp '```\nFOO="a b" npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: an environment assignment precedes it" && nostatus fail; }
c_single_quoted_space() { exp '```\nFOO=\047a b$(echo c)\047 npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: an environment assignment precedes it" && nostatus fail; }
c_escaped_space() { exp '```\nFOO=a\\ b npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: an environment assignment precedes it" && nostatus fail; }
c_quoted_meta_value() { exp '```\nFOO="a;b|c" npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: an environment assignment precedes it" && nostatus fail; }
c_quoted_space_defined() { exp '```\nFOO="a b" npm run x\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run x: an environment assignment precedes it" && nostatus fail; }
# The swallowed cd: `FOO="a b" cd x` hid the cd, so a correct doc got a wrong fail on the next line.
# The cd line itself emits no row, as any cd does.
c_swallowed_cd() { exp '```\nFOO="a b" cd x\nnpm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:3 "npm run nope: a directory change precedes it" && nostatus fail && [ "$(count referred command)" = 1 ]; }
c_swallowed_cd_oneline() { exp '```\nFOO="a b" cd x && npm run nope\n```\n'
  rc_is 0 && at referred AGENTS.md:2 "npm run nope: a directory change precedes it" && nostatus fail; }
# Stated limit, pinned: an UNBALANCED quote matches no quoted run, so the value is not rewritten and
# the line is read as before (no row).
c_unbalanced_quote_limit() { exp '```\nFOO="a b npm run nope\n```\n'
  rc_is 0 && nocmd fail && nocmd referred; }
# The export quote-parity guard still matters where the rewrite cannot reach: an unbalanced quote.
c_export_unbalanced_quote_neg() { exp '```\nexport MSG="set npm_config_workspace\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_quoted_space_hostile_linear() { new; pkg '"x":"x"'; agents "\`\`\`\n$(rep_ 24000 'a="x y$(z)" ')npm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 0 && at referred AGENTS.md:2 "npm run dev: an environment assignment precedes it" && nostatus fail; }

# Item 3: the other spellings of an npm_config_ export.
c_export_declare_gx() { exp '```\ndeclare -gx npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_declare_g_x() { exp '```\ndeclare -g -x npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_declare_g_plain_neg() { exp '```\ndeclare -g npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script"; }
c_export_quoted_dq() { exp '```\nexport "npm_config_workspace=c"\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_quoted_sq() { exp "\`\`\`\nexport 'npm_config_workspace=c'\nnpm run dev\n\`\`\`\n"
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_bare_name() { exp '```\nnpm_config_workspace=c; export npm_config_workspace\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_bare_name_lines() { exp '```\nnpm_config_workspace=c\nexport npm_config_workspace\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_bare_quoted() { exp '```\nexport "npm_config_workspace"\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_export_bare_other_neg() { exp '```\nexport FOO\nexport "FOO=c"\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }

# Item 3 follow-up: a bare-name match must not accept a later word of an export line that is a
# comment, sits inside a quoted value, or follows an un-exporting -n.
c_export_comment_neg() { exp '```\nexport PATH=$PATH:bin  # unlike npm_config_prefix\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_span_comment_neg() { exp 'Run `export NODE_ENV=dev # not npm_config_x`, then `npm run nope`.\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_quoted_value_neg() { exp '```\nexport MSG="set npm_config_workspace"\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
# #387: the export guards parse quotes (two kinds, backslash escapes), -n un-exports only under
# export, and a leading +x un-exports a declare.
c_export_quoted_hash() { exp '```\nexport A="x # y" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_quoted_dash_n() { exp '```\nexport A="a -n" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_quoted_word_hash() { exp '```\nexport "a # b" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_quoted_word_dash_n() { exp '```\nexport "a -n" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_declare_nx() { exp '```\ndeclare -nx npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_declare_x_n() { exp '```\ndeclare -x -n npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_mixed_quotes() { exp '```\nexport A="it\047s" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_sq_holds_dq() { exp '```\nexport \047a"b\047 npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_escaped_quote() { exp '```\nexport A=\\" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_bare_escaped_quote() { exp '```\nexport \\" npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_sq_backslash() { exp '```\nexport A=\047a\\\047 npm_config_workspace=c\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_declare_x_trailing_plus() { exp '```\ndeclare -x npm_config_workspace=c +x\nnpm run dev\n```\n'
  rc_is 0 && row referred command "npm run dev: an environment assignment" && nostatus fail; }
c_export_apostrophe_value_neg() { exp '```\nexport A="it\047s npm_config_workspace=c"\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_escaped_in_dq_neg() { exp '```\nexport A="\\" npm_config_workspace=c"\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_declare_plus_x_neg() { exp '```\ndeclare -x +x npm_config_workspace=c\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_declare_plus_first_neg() { exp '```\ndeclare +x -x npm_config_workspace=c\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }
c_export_n_neg() { exp '```\nexport -n npm_config_workspace\nnpm run nope\n```\n'
  rc_is 1 && row fail command "npm run nope: no such script" && nocmd referred; }

# Item 4: the rewrite and the strip are linear. The hostile lines are a few hundred KB, past the
# default 32768-byte AGENTS.md budget, hence --max-bytes. run_bounded kills a quadratic script.
c_subst_hostile_linear() { new; pkg '"x":"x"'; agents "\`\`\`\n$(rep_ 24000 'a=$(x) ')npm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 0 && at referred AGENTS.md:2 "npm run dev: an environment assignment precedes it" && nostatus fail; }
c_subst_hostile_arg_neg() { new; pkg '"x":"x"'; agents "\`\`\`\n$(rep_ 24000 'a=$(x); ')npm run nope\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 1000000
  rc_is 1 && row fail command "npm run nope: no such script in package.json" && nocmd referred; }
c_strip_hostile_linear() { new; pkg '"x":"x"'; agents "\`\`\`\n$(rep_ 192000 'a=b ')npm run dev\n\`\`\`\n"
  run_bounded "$HOSTILE_WATCHDOG_SECS" --max-bytes 9000000
  rc_is 0 && at referred AGENTS.md:2 "npm run dev: an environment assignment precedes it" && nostatus fail; }

# Item 5: every member of the anchor class, and a line needing more than one rewrite.
c_anchor_start() { anc 'npm_config_workspace=$(echo c) npm run dev'; }
c_anchor_space() { anc 'A=1 npm_config_workspace=$(echo c) npm run dev'; }
c_anchor_tab() { anc 'A=1\tnpm_config_workspace=$(echo c) npm run dev'; }
c_anchor_semi() { anc 'echo hi;npm_config_workspace=$(echo c) npm run dev'; }
c_anchor_amp() { anc 'echo hi&&npm_config_workspace=$(echo c) npm run dev'; }
c_anchor_pipe() { anc 'echo hi|npm_config_workspace=$(echo c) npm run dev'; }
c_anchor_paren() { anc '(npm_config_workspace=$(echo c) npm run dev)'; }
c_subst_while_multi() { anc 'A=$(echo a) npm_config_workspace=$(echo c) npm run dev'; }
c_subst_multi_neg() { exp '```\necho $(date); echo $(date); npm run dev\n```\n'
  rc_is 1 && row fail command "npm run dev: no such script in package.json" && nocmd referred; }

echo "== #346 follow-ups to #296 =="
case_ c_export_make_neg "an npm_config_ export does not mask a failing make target"
case_ c_export_just_neg "an npm_config_ export does not mask a failing just recipe"
case_ c_export_pnpm "an npm_config_ export refers a later pnpm run"
case_ c_export_yarn "an npm_config_ export refers a later yarn script, naming the assignment"
case_ c_subst_prefix_value "a value with literal text before a substitution is an assignment"
case_ c_subst_double_value "a value of two substitutions is one assignment"
case_ c_subst_backtick_nospace "a backtick value with no space is an ordinary assignment word"
case_ c_subst_backtick_space "a backtick value with a space inside refers the row (#386)"
case_ c_quoted_arg_name_neg "a NAME= inside a quoted argument cannot swallow the next runner (#386 review)"
case_ c_quoted_arg_name_sq_neg "a NAME= inside a single-quoted argument cannot swallow the next runner (#386 review)"
case_ c_quoted_arg_name_end_neg "a NAME= right before a closing quote cannot swallow the next runner (#386 review)"
case_ c_quoted_arg_name_span_neg "the same holds in a prose code span (#386 review)"
case_ c_long_word_export_linear "a 300 KB word on an export line is parsed within the bound (#387 review)"
case_ c_long_word_assign_linear "a 300 KB assignment value is rewritten within the bound (#386 review)"
case_ c_quoted_arg_hostile_linear "12000 quoted arguments holding NAME= are read within the bound (#386 review)"
case_ c_vskip_npm_C "npm -C (the --prefix alias) skips its value (#390 review)"
case_ c_subst_quoted_space_value "a quoted value with a space and a substitution refers the row (#386)"
case_ c_quoted_space_nosubst "a quoted value with a space refers the row (#386)"
case_ c_single_quoted_space "a single-quoted value with a space refers the row (#386)"
case_ c_escaped_space "a backslash-escaped space in a value refers the row (#386)"
case_ c_quoted_meta_value "a ; or | inside a quoted value stays inside the value (#386)"
case_ c_quoted_space_defined "a quoted value with a space before a defined script refers, never fails (#386)"
case_ c_swallowed_cd "a cd after a quoted assignment still refers the next line (#386)"
case_ c_swallowed_cd_oneline "a cd after a quoted assignment refers the same line's runner (#386)"
case_ c_unbalanced_quote_limit "an unbalanced quote in a value gives no row (stated limit, #386)"
case_ c_export_unbalanced_quote_neg "a name after an unbalanced quote in an export rescopes nothing"
case_ c_quoted_space_hostile_linear "24000 quoted-space-substitution words are rewritten within the bound (#386)"
case_ c_export_declare_gx "declare -gx carries"
case_ c_export_declare_g_x "declare -g -x carries"
case_ c_declare_g_plain_neg "declare -g without an x exports nothing"
case_ c_export_quoted_dq "a double-quoted export argument carries"
case_ c_export_quoted_sq "a single-quoted export argument carries"
case_ c_export_bare_name "assignment then export of the bare name on one line carries"
case_ c_export_bare_name_lines "assignment then export of the bare name on two lines carries"
case_ c_export_bare_quoted "a quoted bare name carries"
case_ c_export_bare_other_neg "export of other bare or quoted names rescopes nothing"
case_ c_export_comment_neg "a name in a trailing comment of an export line rescopes nothing"
case_ c_export_span_comment_neg "a name in a trailing comment of a code-span export rescopes nothing"
case_ c_export_quoted_value_neg "a name inside a quoted export value rescopes nothing"
case_ c_export_quoted_hash "a # inside a quoted export value does not end the line (#387)"
case_ c_export_quoted_dash_n "a -n inside a quoted export value does not un-export (#387)"
case_ c_export_quoted_word_hash "a # inside a quoted export WORD does not end the line (#387)"
case_ c_export_quoted_word_dash_n "a -n inside a quoted export WORD does not un-export (#387)"
case_ c_export_declare_nx "declare -nx carries: for declare -n is nameref (#387)"
case_ c_declare_x_n "declare -x -n carries (#387)"
case_ c_export_mixed_quotes "an apostrophe inside a double-quoted value is not a quote (#387)"
case_ c_export_sq_holds_dq "a double quote inside single quotes is not a quote (#387)"
case_ c_export_escaped_quote "an escaped quote in a value does not open a quote (#387)"
case_ c_export_bare_escaped_quote "an escaped quote as its own word does not open a quote (#387)"
case_ c_export_sq_backslash "a backslash inside single quotes escapes nothing (#387)"
case_ c_declare_x_trailing_plus "a +x after a name does not un-export (#387)"
case_ c_export_apostrophe_value_neg "a name inside a double-quoted value holding an apostrophe rescopes nothing (#387)"
case_ c_export_escaped_in_dq_neg "a name after an escaped quote inside a double-quoted value rescopes nothing (#387)"
case_ c_declare_plus_x_neg "declare -x +x un-exports (#387)"
case_ c_declare_plus_first_neg "declare +x -x un-exports (#387)"
case_ c_export_n_neg "export -n of the name un-exports it and rescopes nothing"
case_ c_subst_hostile_linear "24000 NAME=\$(..) words are rewritten within the bound"
case_ c_subst_hostile_arg_neg "24000 separate NAME=\$(..); commands still leave a failing runner failing, within the bound"
case_ c_strip_hostile_linear "192000 leading assignment words are stripped within the bound"
case_ c_anchor_start "the rewrite anchor holds at the start of a line"
case_ c_anchor_space "the rewrite anchor holds after a space"
case_ c_anchor_tab "the rewrite anchor holds after a tab"
case_ c_anchor_semi "the rewrite anchor holds after a semicolon"
case_ c_anchor_amp "the rewrite anchor holds after &&"
case_ c_anchor_pipe "the rewrite anchor holds after a pipe"
case_ c_anchor_paren "the rewrite anchor holds after an open parenthesis"
case_ c_subst_while_multi "a line needing a second rewrite gets it"
case_ c_subst_multi_neg "substitutions that are not assignment values still fail"

# ---------------------------------------------------------------- #339: a tracked root .npmrc
# npm rescopes `npm run X` when the project .npmrc sets workspace(s), so the root manifest cannot
# judge X. npmrc_case <.npmrc text, "-" for none> [doc line, default `npm run dev`] builds the shared
# repository: a root without dev, a tracked client defining it, the doc, then runs the checker.
npmrc_case() { new; pkg '"x":"x"'; tput_ client/package.json '{"name":"client","scripts":{"dev":"x"}}\n'
  [ "$1" = - ] || tput_ .npmrc "$1"
  agents "\`\`\`\n${2:-npm run dev}\n\`\`\`\n"; run; }
c_npmrc_ws_undef() { npmrc_case 'workspace=client\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspace" && ! row referred command "sets workspaces" && nostatus fail; }
c_npmrc_ws_defined() { new; pkg '"dev":"x"'; tput_ client/package.json '{"name":"client","scripts":{"dev":"x"}}\n'; tput_ .npmrc 'workspace=client\n'
  agents '```\nnpm run dev\n```\n'; run
  rc_is 0 && row referred command "npm run dev" && ! row pass command "npm run dev"; }
c_npmrc_workspaces() { npmrc_case 'workspaces=true\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail; }
c_npmrc_spaced() { npmrc_case 'workspace = client\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspace" && nostatus fail; }
c_npmrc_bracket() { npmrc_case 'workspace[]=client\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspace"; }
c_npmrc_no_final_newline() { npmrc_case 'registry=x\nworkspace=client'; rc_is 0 && row referred command "a tracked .npmrc sets workspace"; }
c_npmrc_index_blob() { npmrc_case 'workspace=client\n'; put .npmrc 'registry=x\n'; run
  rc_is 0 && row referred command "a tracked .npmrc sets workspace"; }
c_npmrc_none_neg() { npmrc_case -; rc_is 1 && row fail command "npm run dev: no such script in package.json" && nostatus referred; }
c_npmrc_pnpm_unchanged() { npmrc_case 'workspace=client\n' 'pnpm run dev'
  rc_is 1 && row fail command "pnpm run dev: no such script in package.json" && nostatus referred; }
c_npmrc_ws_false() { npmrc_case 'workspaces=false\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_ws_false_crlf() { npmrc_case 'workspaces=false\r\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_case_neg() { npmrc_case 'WORKSPACE=client\n'; rc_is 1 && row fail command "no such script"; }
c_npmrc_bom() { npmrc_case '\xef\xbb\xbfworkspace=client\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspace"; }
c_npmrc_indented_section() { npmrc_case '  [s]\nworkspace=client\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspace"; }
c_npmrc_section_neg() { npmrc_case '[section]\nworkspace=client\n'; rc_is 1 && row fail command "no such script"; }
c_npmrc_registry_neg() { npmrc_case 'registry=https://registry.example/\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_comment_neg() { npmrc_case '; workspace=client\n# workspace=client\n'; rc_is 1 && row fail command "no such script"; }
c_npmrc_key_neg() { npmrc_case 'include-workspace-root=true\n'; rc_is 1 && row fail command "no such script"; }
c_npmrc_untracked() { npmrc_case -; put .npmrc 'workspace=client\n'; run; rc_is 1 && row fail command "no such script"; }
c_npmrc_subdir_neg() { npmrc_case -; tput_ client/.npmrc 'workspace=client\n'; run; rc_is 1 && row fail command "no such script"; }
# The token sits on its own line, and the matched line is checked too, so an echo of either dies.
c_npmrc_token() { npmrc_case '//registry.example/:_authToken=SECRETTOKEN\nworkspace=client\n'
  row referred command "npm run dev" && none SECRETTOKEN && none "workspace=client" && ! grep -qF SECRETTOKEN <<<"$ERR" && ! grep -qF "workspace=client" <<<"$ERR"; }
c_npmrc_unchanged_forms() { npmrc_case 'workspace=client\n' 'npm -w client run nope'
  rc_is 1 && row fail command "npm -w client run nope: nope is not a script of client (client/package.json)" && nostatus referred; }

# #357: a symlinked root .npmrc is referred from the index mode and never followed or printed.
# npmrc_link <text the link target holds> [doc line] [target path, default cfg/npmrc]: as npmrc_case,
# but .npmrc is a tracked mode 120000 link. A relative target is tracked too; an absolute one lies
# outside the repository and is only ever written to disk.
npmrc_link() { local t=${3:-cfg/npmrc}; new; pkg '"x":"x"'; tput_ client/package.json '{"name":"client","scripts":{"dev":"x"}}\n'
  case "$t" in /*) printf '%b' "$1" > "$t" ;; *) tput_ "$t" "$1" ;; esac
  ln -s "$t" "$R/.npmrc"; git -C "$R" add .npmrc
  agents "\`\`\`\n${2:-npm run dev}\n\`\`\`\n"; run; }
linkmode() { [ "$(git -C "$R" ls-files -s -- .npmrc | cut -d' ' -f1)" = 120000 ]; }
c_npmrc_symlink() { npmrc_link 'workspace=client\n'
  linkmode && rc_is 0 && row referred command "npm run dev: a tracked .npmrc is a symlink" && nocmd fail && nocmd pass && none "cfg/npmrc"; }
c_npmrc_symlink_nofollow() { npmrc_link '_authToken=SECRETTOKEN\nworkspace=client\n' 'npm run dev' "$W/outside$n"
  linkmode && row referred command "is a symlink" && ! row referred command "sets workspace" && none SECRETTOKEN && none "$W/outside" \
    && ! grep -qF SECRETTOKEN <<<"$ERR" && ! grep -qF "$W/outside" <<<"$ERR"; }
c_npmrc_symlink_text_neg() { npmrc_case 'cfg/npmrc\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_symlink_subdir_neg() { npmrc_case -; tput_ cfg/npmrc 'workspace=client\n'; ln -s ../cfg/npmrc "$R/client/.npmrc"; git -C "$R" add client/.npmrc; run
  rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_symlink_pnpm_unchanged() { npmrc_link 'workspace=client\n' 'pnpm run dev'
  linkmode && rc_is 1 && row fail command "pnpm run dev: no such script in package.json" && nostatus referred; }
c_npmrc_symlink_explicit_limit() { npmrc_link 'workspaces=false\n' 'npm -w client run dev'
  linkmode && rc_is 0 && row pass command "npm -w client run dev"; }

# #357: quote stripping and the leading-space trim.
c_npmrc_ws_false_quoted() { npmrc_case 'workspaces="false"\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_ws_false_squoted() { npmrc_case "workspaces='false'\n"; rc_is 1 && row fail command "no such script" && nostatus referred; }
c_npmrc_quote_mismatch() { npmrc_case "workspaces=\"false'\n"; rc_is 0 && row referred command "a tracked .npmrc sets workspaces"; }
c_npmrc_indented_key() { npmrc_case '  workspace=client\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspace" && nostatus fail; }
c_npmrc_indented_key_tab() { npmrc_case '\tworkspace=client\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspace" && nostatus fail; }
c_npmrc_indented_nonkey_neg() { npmrc_case '  registry=x\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }

# #357: workspaces=false refuses an explicit workspace run; npm takes the LAST value (npm 10.9.7).
# #395: an array-form `workspaces[]` line means workspaces on, whatever its value, because npm's ini
# parser makes the key a list and a non-empty list is truthy (measured on npm 10.9.4).
c_npmrc_wsarray_plain() { npmrc_case 'workspaces[]=false\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_rootdef() { new; pkg '"dev":"x"'; tput_ client/package.json '{"name":"client","scripts":{"dev":"x"}}\n'; tput_ .npmrc 'workspaces[]=false\n'
  agents '```\nnpm run dev\n```\n'; run
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_explicit() { npmrc_case 'workspaces[]=false\n' 'npm -w client run dev'
  rc_is 0 && row pass command "npm -w client run dev: dev is defined in client/package.json" && nocmd referred && nostatus fail; }
c_npmrc_wsarray_true_then() { npmrc_case 'workspaces=true\nworkspaces[]=false\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_scalar_false_neg() { npmrc_case 'workspaces=false\nworkspaces[]=false\n'
  rc_is 0 && row referred command "sets workspaces" && nostatus fail || return 1
  npmrc_case 'workspaces[]=false\nworkspaces=false\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_scalar_false_explicit() { npmrc_case 'workspaces[]=false\nworkspaces=false\n' 'npm -w client run dev'
  rc_is 0 && row pass command "npm -w client run dev: dev is defined in client/package.json" && nocmd referred && nostatus fail; }
c_npmrc_wsarray_spaced() { npmrc_case 'workspaces[] = false\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_quoted() { npmrc_case '"workspaces[]"=false\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
c_npmrc_wsarray_zero() { npmrc_case 'workspaces[]=0\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail && nocmd pass; }
# `workspaces []=false` is npm's key "workspaces " and leaves workspaces unset: the root runs.
c_npmrc_wsarray_space_before_brackets_neg() { npmrc_case 'workspaces []=false\n'
  rc_is 1 && row fail command "npm run dev: no such script in package.json" && ! row referred command "sets workspaces"; }
c_npmrc_wsfalse_explicit_w() { npmrc_case 'workspaces=false\n' 'npm -w client run dev'
  rc_is 0 && row referred command "npm -w client run dev: a tracked .npmrc sets workspaces=false" && nocmd pass && nostatus fail; }
c_npmrc_wsfalse_explicit_workspace() { npmrc_case 'workspaces=false\n' 'npm --workspace client run dev'
  rc_is 0 && row referred command "npm --workspace client run dev: a tracked .npmrc sets workspaces=false" && nocmd pass && nostatus fail; }
c_npmrc_wsfalse_explicit_eq() { npmrc_case 'workspaces=false\n' 'npm --workspace=client run dev'
  rc_is 0 && row referred command "npm --workspace=client run dev: a tracked .npmrc sets workspaces=false" && nocmd pass && nostatus fail; }
c_npmrc_wsfalse_last_true_then_false() { npmrc_case 'workspaces=true\nworkspaces=false\n' 'npm -w client run dev'
  rc_is 0 && row referred command "sets workspaces=false"; }
c_npmrc_wsfalse_last_false_then_true() { npmrc_case 'workspaces=false\nworkspaces=true\n' 'npm -w client run dev'
  rc_is 0 && row pass command "npm -w client run dev" && nostatus referred; }
c_npmrc_wsfalse_with_wskey_explicit() { npmrc_case 'workspaces=false\nworkspace=client\n' 'npm -w client run dev'
  rc_is 0 && row referred command "sets workspaces=false"; }
c_npmrc_wsfalse_explicit_neg() { npmrc_case 'workspaces=true\n' 'npm -w client run dev'
  rc_is 0 && row pass command "npm -w client run dev"; }
c_npmrc_wsfalse_pnpm_unchanged() { npmrc_case 'workspaces=false\n' 'pnpm --filter client run dev'
  rc_is 0 && row pass command "pnpm --filter client run dev" && nostatus referred; }
# The named, minimal statement of the no-.npmrc contract (#381): the older plain `npm -w` cases that
# set no .npmrc die under the same mutant, so this one is partly redundant on purpose.
c_npmrc_wsfalse_none_neg() { npmrc_case - 'npm -w client run dev'; rc_is 0 && row pass command "npm -w client run dev" && nostatus referred; }
c_npmrc_plain_false_then_true() { npmrc_case 'workspaces=false\nworkspaces=true\n'; rc_is 0 && row referred command "a tracked .npmrc sets workspaces"; }
c_npmrc_plain_true_then_false_wskey() { npmrc_case 'workspaces=true\nworkspaces=false\nworkspace=client\n'
  rc_is 0 && row referred command "a tracked .npmrc sets workspace" && ! row referred command "sets workspaces"; }
c_npmrc_plain_true_then_false_neg() { npmrc_case 'workspaces=true\nworkspaces=false\n'; rc_is 1 && row fail command "no such script" && nostatus referred; }

# #381: numeric-zero values, inline comments and quoted keys, each checked against npm 10.9.7 (the
# differential matrix is in the issue). A numeric zero reads as false (nopt coerces with !!(+val)).
EXPL='npm -w client run dev'
c_npmrc_zero_plain() { npmrc_case 'workspaces=0\n'
  rc_is 1 && row fail command "npm run dev: no such script in package.json" && nostatus referred; }
c_npmrc_zero_explicit() { npmrc_case 'workspaces=0\n' "$EXPL"
  rc_is 0 && row referred command "npm -w client run dev: a tracked .npmrc sets workspaces=false" && nocmd pass; }
c_npmrc_zero_spellings_explicit() { local v
  for v in 00 -0 +0 0.0 .0 '"0"'; do npmrc_case "workspaces=$v\n" "$EXPL"
    row referred command "npm -w client run dev: a tracked .npmrc sets workspaces=false" || { printf '      | spelling %s\n' "$v"; return 1; }; done; }
c_npmrc_one_neg() { npmrc_case 'workspaces=1\n' "$EXPL"
  row pass command "npm -w client run dev: dev is defined in client/package.json" && nostatus referred || return 1
  npmrc_case 'workspaces=1\n'; rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces"; }
# Documented limit: npm reads 0x0 and 0e0 as false and refuses the explicit form; the asset does not model it.
# #398: the comment cut never runs inside a quoted value (npm 10.9.7 reads "false # c" as a truthy
# string and runs the client), and an empty value, or one empty after the cut, is truthy.
c_npmrc_quoted_value_hash_explicit() { npmrc_case 'workspaces="false # c"\n' "$EXPL"
  row pass command "npm -w client run dev: dev is defined in client/package.json" && nostatus referred; }
c_npmrc_empty_after_cut() { npmrc_case 'workspaces= # c\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail; }
# #398 stated limits, each pinned at the asset's current row (npm 10.9.7's verdict in the label).
c_npmrc_key_hash_limit() { npmrc_case 'workspace#c=client\n'
  rc_is 1 && row fail command "npm run dev: no such script in package.json"; }
c_npmrc_key_semicolon_limit() { npmrc_case 'workspaces;x=false\n' "$EXPL"
  row pass command "npm -w client run dev: dev is defined in client/package.json"; }
c_npmrc_key_space_hash_limit() { npmrc_case 'workspaces #c=false\n' "$EXPL"
  row pass command "npm -w client run dev: dev is defined in client/package.json"; }
c_npmrc_more_zero_limit() { local v
  for v in 0b0 0o0 0e5; do npmrc_case "workspaces=$v\n" "$EXPL"
    row pass command "npm -w client run dev: dev is defined in client/package.json" || { printf '      | value %s\n' "$v"; return 1; }; done; }
c_npmrc_undefined_limit() { npmrc_case 'workspaces=undefined\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail || return 1
  npmrc_case 'workspaces=undefined\n' "$EXPL"; row pass command "npm -w client run dev: dev is defined in client/package.json"; }
c_npmrc_quoted_key_trim_limit() { npmrc_case '"workspace "=client\n'
  row referred command "npm run dev: a tracked .npmrc sets workspace" || return 1
  npmrc_case '"workspaces "=true\n'; row referred command "a tracked .npmrc sets workspaces" && nostatus fail; }
c_npmrc_zero_hex_limit() { local v
  for v in 0x0 0e0; do npmrc_case "workspaces=$v\n" "$EXPL"
    row pass command "npm -w client run dev" && nostatus referred || return 1
    npmrc_case "workspaces=$v\n"; row referred command "npm run dev: a tracked .npmrc sets workspaces" || return 1; done; }
c_npmrc_inline_comment_explicit() { local v
  for v in 'false # c' 'false;c' 'false#c' '0 ; c'; do npmrc_case "workspaces=$v\n" "$EXPL"
    row referred command "npm -w client run dev: a tracked .npmrc sets workspaces=false" || { printf '      | value %s\n' "$v"; return 1; }
    npmrc_case "workspaces=$v\n"; rc_is 1 && row fail command "no such script" || { printf '      | plain %s\n' "$v"; return 1; }; done; }
c_npmrc_inline_comment_true_neg() { npmrc_case 'workspaces=true # c\n'
  rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspaces" && nostatus fail; }
# npm reads `"false" # c` as a truthy string, so the explicit form is not refused.
c_npmrc_quoted_value_comment_neg() { npmrc_case 'workspaces="false" # c\n' "$EXPL"
  row pass command "npm -w client run dev: dev is defined in client/package.json" && nostatus referred; }
# Regression pin, no killing mutant: a value holding a backslash is never false in either parser.
c_npmrc_escaped_comment_neg() { npmrc_case 'workspaces=false\;x\n' "$EXPL"; row pass command "npm -w client run dev"; }
c_npmrc_quoted_key_explicit() { local k
  for k in '"workspaces"' "'workspaces'" '"workspaces" '; do npmrc_case "$k=false\n" "$EXPL"
    row referred command "npm -w client run dev: a tracked .npmrc sets workspaces=false" || { printf '      | key %s\n' "$k"; return 1; }; done; }
# One file per key: in one file the plain `workspace` key would mask a mutant that fails to unquote the second.
c_npmrc_quoted_key_ws() { local k
  for k in '"workspace"' '"workspace[]"'; do npmrc_case "$k=client\n"
    rc_is 0 && row referred command "npm run dev: a tracked .npmrc sets workspace" && nostatus fail || { printf '      | key %s\n' "$k"; return 1; }; done; }
c_npmrc_quoted_key_mismatch_neg() { npmrc_case "\"workspace'=client\n"
  rc_is 1 && row fail command "no such script" && nostatus referred; }
# Documented limit: npm reads `" false"` as false and refuses the explicit form; the asset does not model it.
c_npmrc_quoted_space_limit() { npmrc_case 'workspaces=" false"\n' "$EXPL"; row pass command "npm -w client run dev"; }

echo "== #339 a tracked root .npmrc =="
case_ c_npmrc_ws_undef "workspace=client refers an npm run the root lacks, naming the key"
case_ c_npmrc_ws_defined "workspace=client refers an npm run the root defines, never a pass"
case_ c_npmrc_workspaces "workspaces=true refers, naming the plural key"
case_ c_npmrc_spaced "workspace = client (spaces around =) refers"
case_ c_npmrc_bracket "workspace[]=client refers"
case_ c_npmrc_no_final_newline "a workspace line with no trailing newline refers"
case_ c_npmrc_index_blob "the index blob is judged, not an overwritten working tree"
case_ c_npmrc_none_neg "no .npmrc: the root lacks dev, so it fails"
case_ c_npmrc_pnpm_unchanged "pnpm run is untouched by the rc key and still fails"
case_ c_npmrc_ws_false "workspaces=false keeps the root in charge"
case_ c_npmrc_ws_false_crlf "workspaces=false with CRLF endings still fails"
case_ c_npmrc_case_neg "an uppercase WORKSPACE key does not refer"
case_ c_npmrc_bom "a leading UTF-8 byte-order mark does not hide the key"
case_ c_npmrc_indented_section "an indented [s] line is a key to npm, not a section"
case_ c_npmrc_section_neg "a workspace key under a [section] header does not refer"
case_ c_npmrc_registry_neg "an .npmrc without the key does not refer"
case_ c_npmrc_comment_neg "comment lines naming workspace do not refer"
case_ c_npmrc_key_neg "include-workspace-root=true does not refer"
case_ c_npmrc_untracked "an untracked .npmrc is not read"
case_ c_npmrc_subdir_neg "a non-root .npmrc is not read"
case_ c_npmrc_token "no .npmrc text, token or matched line, reaches stdout or stderr"
case_ c_npmrc_unchanged_forms "the explicit npm -w form is judged as before"
case_ c_npmrc_symlink "a tracked symlinked .npmrc is referred, never read"
case_ c_npmrc_symlink_nofollow "a symlinked .npmrc never leaks its target path or text"
case_ c_npmrc_symlink_text_neg "a regular .npmrc whose text looks like a path is judged normally"
case_ c_npmrc_symlink_subdir_neg "a symlinked non-root .npmrc is not read"
case_ c_npmrc_symlink_pnpm_unchanged "pnpm run is untouched by a symlinked .npmrc"
case_ c_npmrc_symlink_explicit_limit "pinned limit: a symlinked .npmrc with an explicit -w form passes"
case_ c_npmrc_ws_false_quoted "workspaces=\"false\" is stripped to false, no referral"
case_ c_npmrc_ws_false_squoted "workspaces='false' is stripped to false, no referral"
case_ c_npmrc_quote_mismatch "mismatched quotes are not stripped, so it refers"
case_ c_npmrc_indented_key "an indented workspace key refers"
case_ c_npmrc_indented_key_tab "a tab-indented workspace key refers"
case_ c_npmrc_indented_nonkey_neg "an indented unrelated key does not refer"
case_ c_npmrc_wsfalse_explicit_w "workspaces=false refers npm -w"
case_ c_npmrc_wsfalse_explicit_workspace "workspaces=false refers npm --workspace"
case_ c_npmrc_wsfalse_explicit_eq "workspaces=false refers npm --workspace="
case_ c_npmrc_wsfalse_last_true_then_false "true then false: the last value refers an explicit form"
case_ c_npmrc_wsarray_plain "workspaces[]=false refers a plain run (#395)"
case_ c_npmrc_wsarray_rootdef "workspaces[]=false refers a plain run the root defines, never a pass (#395)"
case_ c_npmrc_wsarray_explicit "workspaces[]=false judges an explicit -w run by the manifest (#395)"
case_ c_npmrc_wsarray_true_then "workspaces=true then workspaces[]=false refers, never fails (#395)"
case_ c_npmrc_wsarray_scalar_false_neg "a scalar false before or after an array form does not turn it false (#395)"
case_ c_npmrc_wsarray_scalar_false_explicit "an array form after or before a scalar false lets an explicit -w run pass (#395)"
case_ c_npmrc_wsarray_spaced "workspaces[] = false is the array form (#395)"
case_ c_npmrc_wsarray_quoted "a quoted workspaces[] key is the array form (#395)"
case_ c_npmrc_wsarray_zero "workspaces[]=0 is the array form, never false (#395)"
case_ c_npmrc_wsarray_space_before_brackets_neg "workspaces []=false is another key, so the root runs and the row fails (#395)"
case_ c_npmrc_wsfalse_last_false_then_true "false then true: the last value passes an explicit form"
case_ c_npmrc_wsfalse_with_wskey_explicit "workspaces=false plus a workspace key still refers an explicit form"
case_ c_npmrc_wsfalse_explicit_neg "workspaces=true leaves an explicit form a pass"
case_ c_npmrc_wsfalse_pnpm_unchanged "pnpm --filter ignores workspaces=false"
case_ c_npmrc_wsfalse_none_neg "no .npmrc: an explicit form is a pass"
case_ c_npmrc_plain_false_then_true "false then true refers a plain run"
case_ c_npmrc_plain_true_then_false_wskey "true, false, then a workspace key refers a plain run"
case_ c_npmrc_plain_true_then_false_neg "true then false with no workspace key is judged at the root"
case_ c_npmrc_zero_plain "workspaces=0 reads as false: a plain run is judged at the root"
case_ c_npmrc_zero_explicit "workspaces=0 refers an explicit -w form"
case_ c_npmrc_zero_spellings_explicit "00, -0, +0, 0.0, .0 and \"0\" read as false and refer an explicit form"
case_ c_npmrc_one_neg "workspaces=1 is not false: explicit passes, plain refers"
case_ c_npmrc_zero_hex_limit "pinned limit: 0x0 and 0e0 are not modelled"
case_ c_npmrc_quoted_value_hash_explicit "a # inside a quoted value is no comment, so the value is truthy (#398)"
case_ c_npmrc_empty_after_cut "an empty value after the comment cut is truthy (#398)"
case_ c_npmrc_key_hash_limit "pinned limit: workspace#c=client is a false fail, npm runs the client (#398)"
case_ c_npmrc_key_semicolon_limit "pinned limit: workspaces;x=false passes the explicit form npm refuses (#398)"
case_ c_npmrc_key_space_hash_limit "pinned limit: workspaces #c=false passes the explicit form npm refuses (#398)"
case_ c_npmrc_more_zero_limit "pinned limit: 0b0, 0o0 and 0e5 are not modelled (#398)"
case_ c_npmrc_undefined_limit "pinned limit: workspaces=undefined refers a plain run and passes an explicit one (#398)"
case_ c_npmrc_quoted_key_trim_limit "pinned limit: a space inside a quoted key is trimmed, safe side (#398)"
case_ c_npmrc_inline_comment_explicit "an inline ; or # comment after a false value is cut"
case_ c_npmrc_inline_comment_true_neg "a comment after true never makes the value false"
case_ c_npmrc_quoted_value_comment_neg "a quoted false followed by a comment is truthy to npm"
case_ c_npmrc_escaped_comment_neg "false\\;x is not false"
case_ c_npmrc_quoted_key_explicit "a quoted workspaces key is read, double and single"
case_ c_npmrc_quoted_key_ws "a quoted workspace key and a quoted workspace[] key refer, never fail"
case_ c_npmrc_quoted_key_mismatch_neg "mismatched key quotes are not stripped"
case_ c_npmrc_quoted_space_limit "pinned limit: whitespace inside quotes is not modelled"

# ---------------------------------------------------------------- #299: yarn and workspaces
# mf <path> <name> <scripts-json>: write and track a workspace manifest.
mf() { tput_ "$1" "{\"name\":\"$2\",\"scripts\":{$3}}\n"; }
# A jq that counts its own invocations, for the linear-cost cases (a counting stub, never a timer).
STUB="$W/stubjq"; mkdir -p "$STUB"
printf '#!/bin/sh\necho x >> "$JQ_COUNT"\nexec %s "$@"\n' "$(command -v jq)" > "$STUB/jq"; chmod +x "$STUB/jq"
run_stub() {
  local p="$PATH"; [ -n "$AWKDIR" ] && p="$AWKDIR:$PATH"
  : > "$W/count"
  OUT=$(cd "$R" && JQ_COUNT="$W/count" PATH="$STUB:$p" "$SHELL_UNDER_TEST" "$S" "$@" 2>"$W/err"); RC=$?
  ERR=$(cat "$W/err"); JQN=$(wc -l < "$W/count" | tr -d ' ')
}

c_y_bare() { new; pkg '"build":"x"'; agents '`yarn build`\n'; run
  rc_is 0 && row pass command "yarn build: defined in package.json"; }
c_y_bare_neg() { new; pkg '"build":"x"'; agents '`yarn prettier`\n'; run
  rc_is 0 && row referred command "yarn prettier" && nocmd fail && nocmd pass; }
c_y_run() { new; pkg '"lint":"x"'; agents '`yarn run lint`\n'; run
  rc_is 0 && row pass command "yarn run lint: defined in package.json"; }
c_y_run_neg() { new; pkg '"build":"x"'; agents '`yarn run lint`\n'; run
  rc_is 0 && row referred command "yarn run lint" && nocmd fail && nocmd pass; }
c_y_install() { new; pkg '"install":"x"'; agents '`yarn run install`\n\n`yarn install`\n'; run
  rc_is 0 && row pass command "yarn run install: defined" && none "yarn install" && [ "$(count pass command)" = 1 ] \
    && [ "$(count referred command)" = 0 ]; }
c_y_classic() { new; pkg '"check":"x","install":"x"'; agents '`yarn run check`\n\n`yarn check`\n\n`yarn check.`\n\n`yarn install.`\n'; run
  rc_is 0 && row pass command "yarn run check: defined" && row referred command "yarn check: may be a yarn built-in" \
    && row referred command "yarn check.: may be a yarn built-in" && none "yarn install" \
    && [ "$(count pass command)" = 1 ] && nocmd fail; }
c_yws() { new; mf packages/web/package.json web '"build":"x"'; agents '`yarn workspace web run build`\n\n`yarn workspace web build`\n'; run
  rc_is 0 && [ "$(count pass command)" = 2 ] && [ "$(grep -c 'defined in packages/web/package.json' <<<"$OUT")" = 2 ]; }
c_yws_neg() { new; mf packages/web/package.json web '"x":"x"'; agents '`yarn workspace web run build`\n'; run
  rc_is 0 && row referred command "does not define build" && nocmd fail && nocmd pass; }
# #317 items 1, 2 and 5: the yarn root with no manifest, the silent-flag exemption in both directions,
# and the Berry built-ins (none of which yarn can fail on, so the effect is a stray referred or a false pass).
c_y_noroot() { new; agents '`yarn run build`\n'; run
  rc_is 0 && row referred command "yarn run build: no root package.json is tracked" && nocmd pass && nocmd fail; }
c_silent_npm_ws() { new; mf packages/web/package.json web '"build":"x"'
  agents '`npm -w web run build --silent`\n\n`pnpm --filter web run build -s`\n'; run
  rc_is 0 && [ "$(count pass command)" = 2 ] && nocmd fail && none "may change which script runs"; }
c_silent_yarn() { new; pkg '"build":"x"'; agents '`yarn run build -s`\n'; run
  rc_is 0 && row referred command "yarn run build: -s may change which script runs" && nocmd pass; }
c_y_berry() { new; pkg '"stage":"x"'; mf packages/web/package.json web '"x":"x"'
  agents '`yarn unplug lodash`\n\n`yarn stage`\n\n`yarn patch-commit -s x`\n\n`yarn workspace web unplug x`\n\n`yarn search foo`\n'; run
  rc_is 0 && nocmd pass && nocmd referred && nocmd fail; }
# The built-in list is for the BARE form only: `yarn run stage` still reads the root script.
c_y_berry_run() { new; pkg '"stage":"x"'; agents '`yarn run stage`\n'; run
  rc_is 0 && row pass command "yarn run stage: defined in package.json" && nocmd referred; }
c_yws_builtin() { new; mf packages/web/package.json web '"add":"x","check":"x"'
  agents '`yarn workspace web add lodash`\n\n`yarn workspace web check`\n\n`yarn workspace web check.`\n\n`yarn workspace web add.`\n'; run
  rc_is 0 && none "workspace web add" && row referred command "check may be a yarn built-in" \
    && row referred command "web check.: check may be a yarn built-in" && none "check. may" && none "add." && nocmd pass; }
c_scoped() { new; mf packages/api/package.json @acme/api '"test":"x"'; agents '`yarn workspace @acme/api run test`\n'; run
  rc_is 0 && row pass command "test is defined in packages/api/package.json"; }
c_scoped_neg() { new; mf packages/api/package.json @acme/apis '"test":"x"'; agents '`yarn workspace @acme/api run test`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named @acme/api" && nocmd pass && nocmd fail; }
c_npm_ws() { new; mf packages/web/package.json web '"build":"x"'
  agents '`npm -w web run build`\n\n`npm --workspace web run build`\n\n`npm --workspace=web run build`\n'; run
  rc_is 0 && [ "$(count pass command)" = 3 ] && nocmd fail; }
c_npm_ws_neg() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm --workspace=web run deploy`\n'; run
  rc_is 1 && row fail command "deploy is not a script of web (packages/web/package.json)" && nocmd pass; }
c_pnpm_ws() { new; mf packages/web/package.json web '"build":"x"'
  agents '`pnpm --filter web run build`\n\n`pnpm -F web run build`\n\n`pnpm --filter=web run build`\n'; run
  rc_is 0 && [ "$(count pass command)" = 3 ] && nocmd fail; }
c_pnpm_ws_neg() { new; mf packages/web/package.json web '"build":"x"'; agents '`pnpm -F web run deploy`\n'; run
  rc_is 1 && row fail command "deploy is not a script of web" && nocmd pass; }
# Manifests literally carry the selector text, so equality alone would match; only the literal-name
# gate refers. The npm spans die a regex-only removal on a status, the `web...` span the pnpm-only test.
c_selectors() { new
  mf packages/a1/package.json 'web*' '"x":"x"'; mf packages/a2/package.json '...web' '"x":"x"'
  mf packages/a3/package.json 'web...' '"x":"x"'; mf packages/a4/package.json '^web' '"x":"x"'
  mf packages/a5/package.json '!web' '"x":"x"'
  agents '`pnpm --filter web* run deploy`\n\n`pnpm --filter ...web run deploy`\n\n`pnpm --filter web... run deploy`\n\n`pnpm --filter ^web run deploy`\n\n`pnpm --filter !web run deploy`\n\n`npm -w web* run deploy`\n\n`npm -w ^web run deploy`\n'; run
  rc_is 0 && [ "$(count referred command)" = 7 ] && [ "$(grep -c 'not a literal package name' <<<"$OUT")" = 7 ] \
    && nocmd pass && nocmd fail; }
c_quoted() { new; mf packages/web/package.json web '"x":"x"'; agents '`pnpm --filter "web" run deploy`\n'; run
  rc_is 0 && row referred command "not a literal package name" && nocmd fail && nocmd pass; }
c_dot_eq() { new; mf packages/ab/package.json a.b '"build":"x"'; agents '`npm -w a.b run build`\n'; run
  rc_is 0 && row pass command "build is defined in packages/ab/package.json"; }
c_dot_regex() { new; mf packages/axb/package.json axb '"build":"x"'; agents '`npm -w a.b run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named a.b" && nocmd pass; }
c_ghost() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w ghost run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named ghost" && nocmd fail; }
c_dupe() { new; mf a/package.json web '"build":"x"'; mf b/package.json web '"x":"x"'; agents '`npm -w web run build`\n'; run
  rc_is 0 && row referred command "2 tracked manifests are named web" && nocmd pass && nocmd fail; }
c_ws_notrim() { new; mf packages/web/package.json web '"build":"x"'
  agents '`npm -w web. run build`\n\n`yarn workspace web, run build`\n'; run
  rc_is 0 && nocmd pass && nocmd fail && [ "$(count referred command)" = 2 ]; }
# #326: judge_pm trims only in its `*)` arm; the dispatch word is raw, so a mistyped `run` stays unknown.
c_pm_trim_lifecycle() { new; pkg '"x":"x"'; agents '`npm test.`\n'; run
  rc_is 0 && row referred command "npm test.: runs a lifecycle script" && [ "$(count referred command)" = 1 ]; }
c_pm_trim_pnpm_builtin() { new; pkg '"x":"x"'; agents '`pnpm install.`\n'; run
  rc_is 0 && none "pnpm install" && nocmd referred; }
c_pm_trim_edges() { new; pkg '"x":"x"'; agents '`npm test.,`\n\n`npm .`\n\n`pnpm .`\n'; run
  rc_is 0 && row referred command "npm test.,: runs a lifecycle script" && row referred command "pnpm .: may be a script, a built-in or a binary" \
    && [ "$(count referred command)" = 2 ] && nocmd pass && nocmd fail; }
c_pm_run_untrimmed() { new; pkg '"build":"x"'; agents '`npm run. build`\n\n`pnpm run. build`\n'; run
  rc_is 0 && nocmd pass && nocmd fail; }
# One case per trim site, so removing exactly one trim kills exactly one case (#317 item 3).
c_pm_trim_site() { new; pkg '"build":"x"'; agents '`npm run build.`\n'; run
  rc_is 0 && row pass command "npm run build: defined in package.json"; }
c_ws_trim_site() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run build.`\n'; run
  rc_is 0 && row pass command "npm -w web run build.: build is defined in packages/web/package.json"; }
c_yroot_trim_site() { new; pkg '"build":"x"'; agents '`yarn run build.`\n'; run
  rc_is 0 && row pass command "yarn run build: defined in package.json"; }
# #353: a name that trims to nothing keeps its raw word, one case per site, so a row is never
# malformed (`npm run : ...`) and always greps back to its doc line.
c_pm_empty_name_raw() { new; pkg '"x":"x"'; agents '`npm run .`\n\n`npm run .,`\n'; run
  rc_is 0 && row referred command "npm run .: not a literal script name" && row referred command "npm run .,: not a literal script name" \
    && none "npm run : " && nocmd pass && nocmd fail; }
c_ws_empty_name_raw() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run .`\n'; run
  rc_is 0 && row referred command "npm -w web run .: . is not a literal script name" && none ":  is not" && nocmd pass && nocmd fail; }
c_yroot_empty_name_raw() { new; pkg '"x":"x"'; agents '`yarn run .`\n\n`yarn .`\n'; run
  rc_is 0 && row referred command "yarn run .: not a literal script name" && row referred command "yarn .: not a literal script name" \
    && none "yarn : not" && none "yarn run : not" && nocmd pass && nocmd fail; }
# #353: run-script is npm's canonical name for run (pnpm accepts it too), so it is judged like run and
# every judge_pm row prints the doc's own verb. One case per row, each using the run-script spelling.
c_pm_run_script_defined() { new; pkg '"x":"x"'; agents '`npm run-script x`\n\n`pnpm run-script x`\n'; run
  rc_is 0 && row pass command "npm run-script x: defined in package.json" && row pass command "pnpm run-script x: defined in package.json" \
    && none "runs a lifecycle script"; }
c_pm_run_script_undefined() { new; pkg '"x":"x"'; agents '`npm run-script build`\n\n`pnpm run-script build`\n'; run
  rc_is 1 && row fail command "npm run-script build: no such script in package.json" && row fail command "pnpm run-script build: no such script in package.json" \
    && none "runs a lifecycle script"; }
c_pm_run_script_dispatch_raw() { new; pkg '"x":"x"'; agents '`npm run-script. x`\n\n`npm run-script`\n'; run
  rc_is 0 && nocmd pass && nocmd fail && nocmd referred; }
# #363: the workspace spelling of run-script is judged like the workspace run, in all six forms.
# The three rows below pin the pnpm and npm arms separately, so each arm has a case of its own (the four-flag arm fails both the npm and the pnpm case).
c_pm_run_script_ws_npm() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run-script nope`\n\n`npm --workspace web run-script nope`\n\n`npm --workspace=web run-script nope`\n\n`npm -w web run-script build`\n'; run
  rc_is 1 && row fail command "npm -w web run-script nope: nope is not a script of web (packages/web/package.json)" \
    && row fail command "npm --workspace web run-script nope: nope is not a script of web" \
    && row fail command "npm --workspace=web run-script nope: nope is not a script of web" \
    && row pass command "npm -w web run-script build: build is defined in packages/web/package.json" && [ "$(count fail command)" = 3 ]; }
c_pm_run_script_ws_pnpm() { new; mf packages/web/package.json web '"build":"x"'; agents '`pnpm -F web run-script nope`\n\n`pnpm --filter web run-script nope`\n\n`pnpm --filter=web run-script nope`\n\n`pnpm -F web run-script build`\n'; run
  rc_is 1 && row fail command "pnpm -F web run-script nope: nope is not a script of web" \
    && row fail command "pnpm --filter web run-script nope: nope is not a script of web" \
    && row fail command "pnpm --filter=web run-script nope: nope is not a script of web" \
    && row pass command "pnpm -F web run-script build: build is defined in packages/web/package.json" && [ "$(count fail command)" = 3 ]; }
c_pm_run_script_ws_near() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run-scripts nope`\n\n`pnpm -F web run-scripts nope`\n\n`npm -w web rum nope`\n'; run
  rc_is 0 && nocmd pass && nocmd fail && row referred command "pnpm -F web run-scripts nope: may be a script, a built-in or a binary" \
    && [ "$(count referred command)" = 1 ]; }
c_pm_run_script_ws_guards() { new; mf packages/web/package.json 'web*' '"build":"x"'; agents '`npm -w web* run-script nope`\n\n`pnpm --filter web* run-script nope`\n\n```\ncd packages && npm -w web run-script nope\n```\n'; run
  rc_is 0 && nocmd pass && nocmd fail && [ "$(count referred command)" = 3 ] \
    && row referred command "npm -w web* run-script nope: not a literal package name" \
    && row referred command "pnpm --filter web* run-script nope: not a literal package name" \
    && row referred command "npm -w web run-script nope: a directory change precedes it"; }
c_pm_run_script_ws_noname() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run-script`\n\n`pnpm -F web run-script`\n\n`yarn workspace web run-script nope`\n'; run
  rc_is 0 && nocmd pass && nocmd fail && none "npm -w web run-script" && none "pnpm -F web run-script"; }
c_run_script_flag_between() { new; pkg '"x":"x"'; agents '`pnpm -r run-script build`\n\n`npm -s run-script x`\n\n`npm -w web --silent run-script nope`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm -r run-script build: a flag between pnpm and run-script may change which script runs" \
    && row referred command "npm -s run-script x: a flag between npm and run-script may change which script runs" \
    && row referred command "npm -w web --silent run-script nope: a flag between npm and run-script may change which script runs"; }
# #390: the flag prefix ends at the first word that is neither a flag nor a flag's value.
c_flag_between_stops_at_word() { new; pkg '"x":"x"'; agents '`npm -g install run-script`\n\n`npm -g install run`\n\n`npm -g install foo -- run`\n\n`npm -g # run`\n'; run
  rc_is 0 && nocmd fail && nocmd referred && nocmd pass; }
c_flag_between_value_unchanged() { new; pkg '"x":"x"'; agents '`npm --prefix dir run build`\n\n`npm -w web --silent run nope`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm --prefix dir run build: a flag between npm and run may change which script runs" \
    && row referred command "npm -w web --silent run nope: a flag between npm and run may change which script runs"; }
c_flag_between_prefix_value_verb() { new; pkg '"x":"x"'; agents '`npm --prefix run-script run build`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm --prefix run-script run build: a flag between npm and run may change which script runs" && ! row referred command "and run-script"; }
c_flag_between_unknown_value_flag() { new; pkg '"x":"x"'; agents '`npm --loglevel verbose run x`\n'; run
  rc_is 0 && nocmd fail && nocmd referred; }
c_flag_between_pnpm_install_bareword() { new; pkg '"x":"x"'; agents '`pnpm -g install run`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm -g install run: may be a script, a built-in or a binary" && ! row referred command "a flag between pnpm"; }
c_vskip_npm_w() { new; pkg '"x":"x"'; agents '`npm -w run-script --silent run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm -w run-script --silent run x: a flag between npm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_npm_workspace() { new; pkg '"x":"x"'; agents '`npm --workspace run-script --silent run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm --workspace run-script --silent run x: a flag between npm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_npm_prefix() { new; pkg '"x":"x"'; agents '`npm --prefix run-script run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "npm --prefix run-script run x: a flag between npm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_pnpm_filter() { new; pkg '"x":"x"'; agents '`pnpm --filter run-script --silent run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm --filter run-script --silent run x: a flag between pnpm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_pnpm_F() { new; pkg '"x":"x"'; agents '`pnpm -F run-script --silent run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm -F run-script --silent run x: a flag between pnpm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_pnpm_C() { new; pkg '"x":"x"'; agents '`pnpm -C run-script run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm -C run-script run x: a flag between pnpm and run may change which script runs" && ! row referred command "and run-script"; }
c_vskip_pnpm_dir() { new; pkg '"x":"x"'; agents '`pnpm --dir run-script run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm --dir run-script run x: a flag between pnpm and run may change which script runs" && ! row referred command "and run-script"; }
c_run_flag_between_unchanged() { new; pkg '"x":"x"'; agents '`pnpm -r run build`\n\n`npm -s run x`\n'; run
  rc_is 0 && nocmd fail && row referred command "pnpm -r run build: a flag between pnpm and run may change which script runs" \
    && row referred command "npm -s run x: a flag between npm and run may change which script runs"; }
c_pm_run_script_flag() { new; pkg '"x":"x"'; agents '`npm run-script --foo x`\n'; run
  rc_is 0 && row referred command "npm run-script ...: --foo may change which script runs" && none "npm run ..."; }
c_pm_run_script_cd() { new; pkg '"x":"x"'; agents '```\ncd client\nnpm run-script x\n```\n'; run
  rc_is 0 && row referred command "npm run-script x: a directory change precedes it" && nocmd pass && nocmd fail; }
c_pm_run_script_not_literal() { new; pkg '"x":"x"'; agents '`npm run-script a/b`\n'; run
  rc_is 0 && row referred command "npm run-script a/b: not a literal script name"; }
c_pm_run_script_npmrc() { npmrc_case 'workspace=client\n' 'npm run-script dev'
  rc_is 0 && row referred command "npm run-script dev: a tracked .npmrc sets workspace" && nocmd pass && nocmd fail; }
c_pm_run_script_npmrc_link() { npmrc_link 'workspace=client\n' 'npm run-script dev'
  linkmode && rc_is 0 && row referred command "npm run-script dev: a tracked .npmrc is a symlink"; }
c_pm_run_script_no_pkg() { new; agents '`npm run-script x`\n'; run
  rc_is 0 && row referred command "npm run-script x: no root package.json is tracked"; }
# The punctuation class is spelled once in the code (comments stripped), as the trim_punct body.
c_trim_once() { [ "$(grep -v '^[[:space:]]*#' "$S" | grep -oF '*[.,\;:!?])' | wc -l | tr -d ' ')" = 1 ]; }
# Index, never the working tree: the blob and the file on disk disagree, in both directions.
c_idx_ws_fail() { new; mf packages/web/package.json web '"x":"x"'; put packages/web/package.json '{"name":"web","scripts":{"deploy":"x"}}\n'
  agents '`npm -w web run deploy`\n'; run
  rc_is 1 && row fail command "deploy is not a script of web"; }
c_idx_ws_pass() { new; mf packages/web/package.json web '"deploy":"x"'; put packages/web/package.json '{"name":"web","scripts":{}}\n'
  agents '`npm -w web run deploy`\n'; run
  rc_is 0 && row pass command "deploy is defined in"; }
c_idx_ws_name() { new; mf packages/web/package.json web '"deploy":"x"'; put packages/web/package.json '{"name":"other","scripts":{"deploy":"x"}}\n'
  agents '`npm -w web run deploy`\n'; run
  rc_is 0 && row pass command "deploy is defined in"; }
c_ws_untracked() { new; put packages/web/package.json '{"name":"web","scripts":{"build":"x"}}\n'; agents '`npm -w web run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named web" && nocmd pass; }
c_nm_pos() { new; mf packages/web/package.json web '"build":"x"'; mf node_modules/web/package.json web '"x":"x"'
  agents '`npm -w web run build`\n'; run
  rc_is 0 && row pass command "build is defined in packages/web/package.json"; }
c_nm_neg() { new; mf packages/x/node_modules/web/package.json web '"build":"x"'; agents '`npm -w web run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named web" && nocmd fail && nocmd pass; }
c_notpkg() { new; mf packages/web/notpackage.json web '"build":"x"'; agents '`npm -w web run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named web" && nocmd pass; }
# The manifest-side name is untrusted too: a forged second row would point `ghost` at web, which lacks build.
c_forged() { new; mf packages/web/package.json web '"x":"x"'
  printf '%s\n' '{"name":"a\tb\npackages/web/package.json\tghost","scripts":{}}' > "$R/packages/evil.json"
  mkdir -p "$R/packages/evil"; mv "$R/packages/evil.json" "$R/packages/evil/package.json"; git -C "$R" add packages/evil/package.json
  agents '`npm -w ghost run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named ghost" && nocmd fail && [ -z "$ERR" ]; }
c_scripts_obj() { new; mf packages/web/package.json web '"build":"x"'; agents '`pnpm -F web run build`\n'; run
  rc_is 0 && row pass command "build is defined"; }
c_scripts_nonobj() { new; tput_ packages/web/package.json '{"name":"web","scripts":[]}\n'; agents '`pnpm -F web run build`\n'; run
  rc_is 0 && row referred command "pnpm -F web run build" && nocmd fail && nocmd pass; }
c_root_not_cand() { new; tput_ package.json '{"name":"acme","scripts":{"build":"x"}}\n'; agents '`yarn workspace acme run build`\n'; run
  rc_is 0 && row referred command "no tracked manifest is named acme" && nocmd pass; }
c_root_unread() { new; tput_ package.json '[1, 2]\n'; mf packages/web/package.json web '"build":"x"'; agents '`npm -w web run build`\n'; run
  rc_is 0 && row pass command "build is defined in packages/web/package.json"; }
c_junk_manifest() { new; tput_ packages/junk/package.json '[1, 2]\n'; mf packages/web/package.json web '"build":"x"'
  agents '`npm -w web run build`\n'; run
  rc_is 0 && row pass command "build is defined in packages/web/package.json"; }
c_malformed_yarn() { new; tput_ package.json '[1, 2]\n'; agents '`yarn build`\n'; run
  rc_is 2 && [ -z "$OUT" ] && grep -q malformed <<<"$ERR"; }
c_shapes_pos() { new; mf packages/web/package.json web '"build":"x"'
  agents '`npm run build -w web`\n\n`npm run build --workspace=web`\n'; run
  rc_is 0 && [ "$(count referred command)" = 2 ] && nocmd pass && nocmd fail; }
# build is defined in the root AND in web, so a flag ignored after the name yields a pass or a fail.
c_shapes_neg() { new; pkg '"build":"x"'; mf packages/web/package.json web '"build":"x"'
  agents '`pnpm --filter web deploy`\n\n`yarn workspace web build --watch`\n\n`yarn build --foo`\n\n`npm -w web run deploy --if-present`\n'; run
  rc_is 0 && [ "$(count referred command)" = 4 ] && nocmd pass && nocmd fail; }
c_cd_yarn() { new; pkg '"build":"x"'; mf packages/web/package.json web '"build":"x"'
  agents '```\ncd client\nyarn build\nyarn workspace web run build\n```\n\n```\nFOO=1 yarn build\n```\n'; run
  rc_is 0 && [ "$(grep -c 'a directory change precedes it' <<<"$OUT")" = 2 ] && row referred command "yarn build: an environment assignment" \
    && nocmd pass; }
c_cd_ws_env() { new; mf packages/web/package.json web '"build":"x"'
  agents '```\nnpm_config_workspace=other npm -w web run build\n```\n'; run
  rc_is 0 && row referred command "an environment assignment precedes it" && nocmd pass && nocmd fail; }
c_nojq_ws() { new; mf packages/web/package.json web '"build":"x"'; agents '`yarn workspace web run build`\n'; run_nojq
  rc_is 2 && [ -z "$OUT" ] && grep -q jq <<<"$ERR"; }
c_nojq_nocand() { new; pkg '"x":"x"'; agents '`yarn workspace web run build`\n'; run_nojq
  rc_is 0 && row referred command "no tracked manifest is named web" && [ -z "$ERR" ]; }
manifests200() { local i; for i in $(seq 1 200); do put "packages/w$i/package.json" "{\"name\":\"w$i\",\"scripts\":{\"build\":\"x\"}}\n"; done; git -C "$R" add -A; }
c_count_linear() { new; manifests200
  agents "$(for i in $(seq 1 50); do printf '`yarn workspace w%d run build`\n\n' "$i"; done)"; run_stub
  rc_is 0 && [ "$(count pass command)" = 50 ] && [ "$JQN" -ge 1 ] && [ "$JQN" -le 300 ]; }
c_count_zero() { new; manifests200; agents '`yarn --cwd p build`\n'; run_stub
  rc_is 0 && [ "$JQN" = 0 ]; }
c_edge_silent() { new; mf packages/web/package.json web '"build":"x"'; agents '`yarn workspace web`\n\n`npm -w`\n'; run
  rc_is 0 && [ "$(count referred command)" = 0 ] && nocmd pass && nocmd fail; }
c_edge_referred() { new; mf packages/web/package.json web '"build":"x"'; agents '`npm -w run build`\n\n`pnpm --filter= run build`\n'; run
  rc_is 0 && [ "$(count referred command)" = 1 ] && row referred command "pnpm --filter= run build: not a literal package name" && nocmd pass && nocmd fail; }

echo "== #299 yarn and workspaces =="
case_ c_y_bare "a bare yarn X defined in the root passes"
case_ c_y_bare_neg "a bare yarn X the root lacks is referred, never a fail"
case_ c_y_run "yarn run X defined in the root passes"
case_ c_y_run_neg "yarn run X the root lacks is referred, never a fail"
case_ c_y_install "yarn run install passes; a bare yarn install is the built-in and gets no row"
case_ c_y_classic "a Yarn Classic built-in is referred even when the root defines it"
case_ c_yws "yarn workspace <name> [run] X passes, naming the manifest"
case_ c_yws_neg "yarn workspace with a script the manifest lacks is referred, never a fail"
case_ c_y_noroot "a yarn root span with no tracked root package.json is referred, never an exit 2"
case_ c_silent_npm_ws "npm and pnpm workspace spans exempt --silent and -s"
case_ c_silent_yarn "yarn run X -s is referred, never a pass"
case_ c_y_berry "Berry built-ins unplug, stage, patch-commit and search get no command row"
case_ c_y_berry_run "the built-in list is bare-form only: yarn run stage passes"
case_ c_yws_builtin "yarn workspace: a built-in stays silent, a Classic built-in refers"
case_ c_scoped "a scoped workspace name resolves"
case_ c_scoped_neg "a scoped name is never matched by prefix"
case_ c_npm_ws "npm -w, --workspace and --workspace= pass"
case_ c_npm_ws_neg "npm --workspace=web run deploy fails when web lacks it"
case_ c_pnpm_ws "pnpm --filter, -F and --filter= pass"
case_ c_pnpm_ws_neg "pnpm -F web run deploy fails when web lacks it"
case_ c_selectors "a glob, selector or exclusion is referred even when a manifest is literally so named"
case_ c_quoted "a quoted filter is never resolved"
case_ c_dot_eq "a dotted name matches itself"
case_ c_dot_regex "a workspace name is equality, not a pattern"
case_ c_ghost "a name matching no manifest is referred"
case_ c_dupe "a name matching two manifests is referred"
case_ c_ws_notrim "a workspace name is never punctuation-trimmed"
case_ c_pm_trim_lifecycle "npm test. gets the lifecycle row, printed with the raw word"
case_ c_pm_trim_pnpm_builtin "pnpm install. is silent like pnpm install"
case_ c_pm_trim_edges "several marks trim, and a punctuation-only word never loops or prints a malformed row"
case_ c_pm_run_untrimmed "a mistyped run is never trimmed into a pass or a fail"
case_ c_pm_trim_site "npm run build. trims its script name (judge_pm)"
case_ c_ws_trim_site "npm -w web run build. trims its script name (judge_ws)"
case_ c_yroot_trim_site "yarn run build. trims its script name (judge_yarn_root)"
case_ c_pm_empty_name_raw "a punctuation-only npm script name keeps its raw word (judge_pm)"
case_ c_ws_empty_name_raw "a punctuation-only workspace script name keeps its raw word (judge_ws)"
case_ c_yroot_empty_name_raw "a punctuation-only yarn script name keeps its raw word (judge_yarn_root)"
case_ c_pm_run_script_defined "run-script is judged like run: a defined script passes, with the doc's verb"
case_ c_pm_run_script_undefined "run-script is judged like run: an undefined script fails, with the doc's verb"
case_ c_pm_run_script_dispatch_raw "run-script. and a bare run-script are never judged"
case_ c_pm_run_script_ws_npm "the npm workspace spellings judge run-script like run (#363)"
case_ c_pm_run_script_ws_pnpm "the pnpm workspace spellings judge run-script like run (#363)"
case_ c_pm_run_script_ws_near "run-scripts is not widened in the workspace forms"
case_ c_pm_run_script_ws_guards "a non-literal selector and a preceding cd still refer for run-script"
case_ c_pm_run_script_ws_noname "a workspace run-script with no name is silent, and yarn workspace stays unjudged"
case_ c_run_script_flag_between "a flag before run-script refers, printing run-script"
case_ c_run_flag_between_unchanged "a flag before run still refers, printing run"
case_ c_pm_run_script_flag "the flag row keeps the run-script verb"
case_ c_pm_run_script_cd "the cd row keeps the run-script verb"
case_ c_pm_run_script_not_literal "the not-literal row keeps the run-script verb"
case_ c_pm_run_script_npmrc "the .npmrc workspace row keeps the run-script verb"
case_ c_pm_run_script_npmrc_link "the .npmrc symlink row keeps the run-script verb"
case_ c_pm_run_script_no_pkg "the no-package.json row keeps the run-script verb"
case_ c_trim_once "the trailing-punctuation class is defined once"
case_ c_idx_ws_fail "the index lacks the script, the disk has it: fail"
case_ c_idx_ws_pass "the index has the script, the disk lacks it: pass"
case_ c_idx_ws_name "the index name decides, not the disk name"
case_ c_ws_untracked "an untracked manifest is not a manifest"
case_ c_nm_pos "a tracked node_modules manifest is excluded, so one match remains"
case_ c_nm_neg "a node_modules manifest alone matches nothing"
case_ c_notpkg "only a file named exactly package.json is a manifest"
case_ c_forged "a manifest-side name cannot forge a table row"
case_ c_scripts_obj "an object scripts passes"
case_ c_scripts_nonobj "a non-object scripts never fails"
case_ c_root_not_cand "the root is not a workspace candidate"
case_ c_root_unread "a workspace form never reads a malformed root"
case_ c_junk_manifest "a malformed non-target manifest is ignored"
case_ c_malformed_yarn "a malformed root exits 2 for a yarn root form"
case_ c_shapes_pos "flag-after npm spellings stay referred"
case_ c_shapes_neg "a flag after the script name refers, never passes or fails"
case_ c_cd_yarn "a preceding cd or assignment keeps yarn rows referred"
case_ c_cd_ws_env "an assignment keeps a workspace row referred"
case_ c_nojq_ws "no jq and a resolving workspace command: exit 2, empty stdout"
case_ c_nojq_nocand "no jq and no candidate manifest: nomatch, exit 0"
case_ c_count_linear "200 manifests and 50 commands cost a bounded number of jq calls"
case_ c_count_zero "no command reaching resolution means no table and no jq call"
case_ c_edge_silent "yarn workspace with no script and a bare npm -w are silent"
case_ c_edge_referred "an empty --filter= is referred, and npm -w run build is silent (run is the workspace value, #390)"
case_ c_flag_between_stops_at_word "a run after an install target, a positional or a # word is not the verb (#390)"
case_ c_flag_between_value_unchanged "the flag-between rows for --prefix dir and -w web --silent are unchanged (#390)"
case_ c_flag_between_prefix_value_verb "a flag's value is never printed as the verb (#390)"
case_ c_flag_between_unknown_value_flag "an unknown value flag ends the search, silent and never a fail (#390)"
case_ c_flag_between_pnpm_install_bareword "pnpm -g install run takes the bare-word row (#390)"
case_ c_vskip_npm_w "npm -w skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_npm_workspace "npm --workspace skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_npm_prefix "npm --prefix skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_pnpm_filter "pnpm --filter skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_pnpm_F "pnpm -F skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_pnpm_C "pnpm -C skips its value, so its run-script value is not the verb (#390)"
case_ c_vskip_pnpm_dir "pnpm --dir skips its value, so its run-script value is not the verb (#390)"

# ---------------------------------------------------------------- could not run, and arguments
c_nogit() { R="$W/plain"; mkdir -p "$R"; run; rc_is 2 && [ -z "$OUT" ] && [ -n "$ERR" ]; }
c_usage() { new; agents 'x\n'; run --max-lines abc; rc_is 2 && [ -z "$OUT" ]; }
c_docs_subdir() { new; agents 'x\n'; tput_ docs/g.md 'See [a](../AGENTS.md).\n'
  OUT=$(cd "$R/docs" && "$SHELL_UNDER_TEST" "$S" --docs g.md 2>/dev/null); RC=$?
  rc_is 0 && at pass docs/g.md:1 "../AGENTS.md: tracked"; }
c_docs_outside() { new; agents 'x\n'; run --docs ../elsewhere.md; rc_is 2 && [ -z "$OUT" ]; }

echo "== could not run =="
case_ c_nogit "outside a git repository: exit 2, empty stdout, a reason"
case_ c_usage "a non-numeric budget: exit 2, empty stdout"
case_ c_docs_subdir "--docs resolves against the caller's directory"
case_ c_docs_outside "--docs outside the repository: exit 2"

# ---------------------------------------------------------------- real-world fixtures
fixture() { new; cp -R "$FIX/$1/." "$R/"; git -C "$R" add -A; }
c_ea() { fixture ea508164; run
  rc_is 1 && [ "$(count fail command)" = 3 ] \
    && at fail .github/CONTRIBUTING.md:193 "npm run test:unit" && at fail .github/CONTRIBUTING.md:245 "npm run format" \
    && at fail .github/CONTRIBUTING.md:248 "npm run lint"; }
c_becf() { fixture becf395d; run
  rc_is 0 && nostatus fail && [ "$(count referred link)" = 2 ] \
    && at referred .github/PULL_REQUEST_TEMPLATE.md:7 "../AGENTS.md" && row pass command "test:e2e:docker:full"; }

echo "== actual-mcp-server fixtures =="
case_ c_ea "ea508164 fails on test:unit, format and lint in .github/CONTRIBUTING.md"
case_ c_becf "becf395d exits 0 with its two PR-template links referred"

# ---------------------------------------------------------------- mutants
# mutant <label> <case> <old> <new> [<old2> <new2> [<old3> <new3>]]: the case must FAIL against the script with
# <old> replaced by <new> (and <old2> by <new2>, <old3> by <new3>, for a defect that needs two or three edits). A replacement that matches nothing is itself a failure, so a refactor cannot quietly turn
# a mutant into a no-op that "dies" for the wrong reason.
M="$W/mutant.sh"
# build_mutant <src> <dst> <old> <new> [<old> <new>...]: write <dst> as <src> with each <old> replaced
# by its <new>. Exit 2 with `unpaired` on stderr, and no file, for an odd or a zero count of edit
# arguments (#346: the python zip below would silently drop a trailing <old>, building and running
# a mutant with fewer edits than the caller wrote). Exit 1 when an <old> is not in <src>.
build_mutant() {
  local src=$1 dst=$2; shift 2
  if [ $# -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then echo "build_mutant: unpaired argument" >&2; return 2; fi
  python3 - "$src" "$dst" "$@" <<'EOF'
import sys
src, dst, *pairs = sys.argv[1:]
s = open(src).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if old not in s: sys.exit(1)
    s = s.replace(old, new)
open(dst, "w").write(s)
EOF
}
mutant() {
  local brc
  build_mutant "$SCRIPT" "$M" "${@:3}" 2>/dev/null; brc=$?
  if [ "$brc" = 2 ]; then bad "mutant '$1': unpaired argument"; return; fi
  if [ "$brc" != 0 ]; then bad "mutant '$1': its anchor no longer matches the script"; return; fi
  S="$M"; if "$2"; then bad "mutant '$1' survived $2"; else ok "mutant '$1' dies on $2"; fi; S="$SCRIPT"
}
# mutant_needs <tool> <label> <case> <old> <new> [...]: mutant, but on a machine without <tool> the
# mutant is skipped and counted as passed, so the printed total is the same everywhere (#346). The
# guard is existence by `command -v`, deliberately: a stub that exits 127 is FOUND.
mutant_needs() {
  local tool=$1; shift
  if command -v "$tool" >/dev/null 2>&1; then mutant "$@"; else ok "mutant '$1' needs $tool: skipped"; fi
}
# have_gawk: the awk `run` uses is GNU Awk. mawk is only mildly superlinear on the strip site, so a
# mutant that needs a clear margin over the bound is skipped there. The probe prepends AWKDIR like
# `run` does; a bare `awk --version` would see the system gawk under AWK_UNDER_TEST=mawk.
have_gawk() { PATH="${AWKDIR:+$AWKDIR:}$PATH" awk --version 2>&1 | grep -q 'GNU Awk'; }
# gawk_gate: run, skip, or refuse (#386). A run that ASKED for gawk (AWK_UNDER_TEST=gawk, as CI does)
# and got an awk that is not GNU Awk must fail, never print a skip that counts as a pass.
gawk_gate() { if have_gawk; then echo run; elif [ "${AWK_UNDER_TEST:-}" = gawk ]; then echo refuse; else echo skip; fi; }
# bwk_gate: the same for the #406 locale-pin mutants, which only BWK awk (the one macOS ships) in a
# UTF-8 locale can kill. BWK is named by its `awk --version` line, `awk version <date>`, probed
# through AWKDIR as `run` resolves it; the locale by `locale charmap`. A run that asked for
# original-awk (as CI does) and got another awk refuses rather than printing a skip.
is_bwk() { PATH="${AWKDIR:+$AWKDIR:}$PATH" awk --version 2>&1 | grep -q '^awk version [0-9]'; }
bwk_gate() {
  if is_bwk && [ "$(locale charmap 2>/dev/null)" = UTF-8 ]; then echo run
  elif [ "${AWK_UNDER_TEST:-}" = original-awk ] && ! is_bwk; then echo refuse
  else echo skip; fi
}
# Pinned with a non-GNU awk first on PATH (mawk, the Ubuntu default): asked for gawk, it refuses;
# not asked, it skips.
NONGNU="$(command -v mawk || true)"
if [ -n "$NONGNU" ]; then
  mkdir -p "$W/nongnu"; ln -sf "$NONGNU" "$W/nongnu/awk"
  g="$(AWKDIR="$W/nongnu" AWK_UNDER_TEST=gawk gawk_gate)"
  [ "$g" = refuse ] && ok "a requested gawk that is not GNU Awk refuses the strip mutant (#386)" || bad "a requested non-GNU gawk gave '$g', not refuse"
  g="$(AWKDIR="$W/nongnu" AWK_UNDER_TEST= gawk_gate)"
  [ "$g" = skip ] && ok "an unrequested non-GNU awk skips the strip mutant (#386)" || bad "an unrequested non-GNU awk gave '$g', not skip"
  g="$(AWKDIR="$W/nongnu" AWK_UNDER_TEST=original-awk bwk_gate)"
  [ "$g" = refuse ] && ok "a requested original-awk that is not BWK awk refuses the locale-pin mutants (#406)" || bad "a requested non-BWK original-awk gave '$g', not refuse"
  g="$(AWKDIR="$W/nongnu" AWK_UNDER_TEST= bwk_gate)"
  [ "$g" = skip ] && ok "an unrequested non-BWK awk skips the locale-pin mutants (#406)" || bad "an unrequested non-BWK awk gave '$g', not skip"
else
  ok "a requested gawk that is not GNU Awk refuses the strip mutant: no mawk here, skipped"
  ok "an unrequested non-GNU awk skips the strip mutant: no mawk here, skipped"
  ok "a requested original-awk that is not BWK awk refuses the locale-pin mutants: no mawk here, skipped"
  ok "an unrequested non-BWK awk skips the locale-pin mutants: no mawk here, skipped"
fi

# #346 harness cases. They sit here, after the helpers above, because a function must be defined
# before the line that calls it runs. Neither can be killed by a mutant (mutant() mutates only the
# checker, never this suite); each was proved by deleting the guard from a cp copy of the suite.
c_mutant_not_run() { : > "$W/mutant_ran"; return 0; }
c_mutant_odd_pairs() {
  local dst="$W/odd.sh" err rc out p0 f0
  rm -f "$dst" "$W/mutant_ran"
  build_mutant "$SCRIPT" "$dst" 'usage() {' 'usage2() {' 'die() {' 'die2() {' 2>/dev/null; rc=$?
  [ "$rc" = 0 ] && [ "$(diff "$SCRIPT" "$dst" | grep -c '^>')" = 2 ] && grep -q 'usage2() {' "$dst" && grep -q 'die2() {' "$dst" || return 1
  rm -f "$dst"
  err=$(build_mutant "$SCRIPT" "$dst" 'old1' 'new1' 'old2' 2>&1 >/dev/null); rc=$?
  [ "$rc" = 2 ] && grep -q unpaired <<<"$err" && [ ! -e "$dst" ] || return 1
  err=$(build_mutant "$SCRIPT" "$dst" 2>&1 >/dev/null); rc=$?
  [ "$rc" = 2 ] && grep -q unpaired <<<"$err" && [ ! -e "$dst" ] || return 1
  rm -f "$M"; p0=$pass f0=$fail
  out=$(mutant "odd label" c_mutant_not_run 'old1' 'new1' 'old2'; echo "inside: $pass $fail")
  [ ! -e "$M" ] && [ ! -e "$W/mutant_ran" ] && grep -q "FAIL: mutant 'odd label': unpaired argument" <<<"$out" \
    && [ "$pass" = "$p0" ] && [ "$fail" = "$f0" ]
}
c_mutant_skip_absent() {
  local out p0
  rm -f "$M" "$W/mutant_ran"; p0=$pass
  out=$(mutant_needs nosuchtool_346 "absent label" c_mutant_not_run 'old' 'new'; echo "inside: $pass")
  [ ! -e "$M" ] && [ ! -e "$W/mutant_ran" ] && grep -qF "ok: mutant 'absent label' needs nosuchtool_346: skipped" <<<"$out" \
    && ! grep -q 'FAIL' <<<"$out" && grep -qF "inside: $((p0 + 1))" <<<"$out"
}
echo "== #346 mutant harness =="
case_ c_mutant_odd_pairs "an unpaired mutant argument fails loudly and builds nothing"
case_ c_mutant_skip_absent "a mutant that needs an absent tool is skipped as a pass, never built"

echo "== mutants =="
# The export-name test in code(), for the mutants that edit it. \047 is literal: the awk program sits
# inside a single-quoted shell variable.
XRE='qs[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*(=|$)/'
if command -v python3 >/dev/null 2>&1; then
  # #309: each guard line carries a `# safe_open: <name>` or `# row: sanitise` tag, so no anchor can
  # match an unrelated line.
  mutant "chain check dropped" c_symlink_chain_escape '120000) SO_WHY="links to $np, which is itself a symlink"; return 1 ;;   # safe_open: chain' '120000) ;;'
  mutant "absolute accepted" c_symlink_abs 'case "$tgt" in /*) SO_WHY="links to $tgt, which is an absolute path a clone does not have"; return 1 ;; esac   # safe_open: absolute' ':'
  mutant "size guard bypassed" c_symlink_escape_one 'if [ "$agents_ok" = 1 ]; then   # safe_open: size' 'if [ -f AGENTS.md ]; then' 'n=$(wc -l < "$T/agents" | tr -d '"' '"') b=$(wc -c < "$T/agents" | tr -d '"' '"')' 'n=$(wc -l < AGENTS.md | tr -d '"' '"') b=$(wc -c < AGENTS.md | tr -d '"' '"')'
  mutant "doc-loop guard bypassed" c_contrib_symlink 'safe_open "$d" "$T/doc" || { row fail link "$d" "$d: unsafe link ($SO_WHY), not read"; continue; }   # safe_open: loop' 'cat "$d" > "$T/doc"'
  mutant "make read unguarded" c_make_symlink_passwd 'safe_open "$f" "$T/mk" || { row fail command "$loc" "$f is an unsafe link ($SO_WHY), not read"; return; }   # safe_open: make' 'cat "$f" > "$T/mk"'
  mutant "control bytes echoed" c_row_newline_target 'a=${a//[[:cntrl:]]/?} b=${b//[[:cntrl:]]/?} c=${c//[[:cntrl:]]/?} d=${d//[[:cntrl:]]/?}   # row: sanitise' ':'
  mutant "row fields unsanitised" c_row_newline_name 'a=${a//[[:cntrl:]]/?} b=${b//[[:cntrl:]]/?} c=${c//[[:cntrl:]]/?} d=${d//[[:cntrl:]]/?}   # row: sanitise' 'b=${b//[[:cntrl:]]/?} d=${d//[[:cntrl:]]/?}'
  mutant "tracked list newline-split" c_tracked_newline_dir 'awk '"'"'{ print substr($0, index($0, "\t") + 1) }'"'"' "$IDXM" > "$IDX"' 'git ls-files -z | tr '"'"'\0'"'"' '"'"'\n'"'"' > "$IDX"'
  mutant "control-byte names kept" c_tracked_newline_dir '  if (LC_ALL=C; [[ $p == *[[:cntrl:]]* ]]); then continue; fi' '  :'
  mutant "index lookup by prefix" c_symlink_dir 'substr($0, i + 1) == ENVIRON["P"] { print' 'index(substr($0, i + 1), ENVIRON["P"]) == 1 { print'
  mutant "awk failure swallowed" c_make_awk_fails 'verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk") || die "could not read $f"   # safe_open: awk' 'verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk")'
  mutant "containment without separator" c_docs_sibling_prefix 'case "$real" in "$top"/*) ;;' 'case "$real" in "$top"*) ;;'
  mutant "index read-back by IFS" c_tracked_tab_name 'meta=${rec%%$'"'"'\t'"'"'*}; p=${rec#*$'"'"'\t'"'"'}   # safe_open: split' 'IFS=$'"'"'\t'"'"' read -r meta p <<<"$rec"'
  mutant "dash-led dirname" c_docs_dash_parent 'CDPATH= cd -- "$(dirname -- "./$p")"' 'CDPATH= cd "$(dirname "$p" 2>/dev/null)"'
  # #301: the import walk. Each guard line carries an `# import: <name>` tag.
  mutant "import: presence instead of tracked" c_imp_untracked 'if [ -z "$mode" ]; then   # import: tracked' 'if [ -z "$mode" ] && [ ! -e "$np" ]; then'
  mutant "import: a span is extracted" c_imp_not_tokens '  if (ENVIRON["IMPORTS"] == 1) imports(rest)' '  if (ENVIRON["IMPORTS"] == 1) imports(line)'
  mutant "import: a fence is extracted" c_imp_not_tokens '    code(line, 1); next' '    if (ENVIRON["IMPORTS"] == 1) imports(line); code(line, 1); next'
  mutant "import: token-start anchor removed" c_imp_not_tokens 'if (substr(w, 1, 1) != "@") continue   # import: token start' 'sub(/^[^@]*/, "", w); if (w == "") continue'
  mutant "import: path-candidate test removed" c_imp_not_tokens 'if (index(w, "/") == 0 && index(w, ".") == 0) continue   # import: path candidate' ''
  mutant "import: depth cap removed" c_imp_depth_neg 'if [ "$h" -ge "$MAX_IMPORT_HOPS" ] && ! {' 'if false && ! {' '  [ "$h" -lt "$MAX_IMPORT_HOPS" ] || return' ''
  mutant "import: depth cap off by one" c_imp_depth_neg 'MAX_IMPORT_HOPS=4' 'MAX_IMPORT_HOPS=5'
  mutant "import: queue taken last-in-first-out" c_imp_bfs 'while [ "$qi" -lt "${#docs[@]}" ]; do
  d=${docs[$qi]} dmode=${modes[$qi]} dhop=${hops[$qi]}; qi=$((qi + 1))' 'while [ "${#docs[@]}" -gt 0 ]; do
  qi=$((${#docs[@]} - 1)); d=${docs[$qi]} dmode=${modes[$qi]} dhop=${hops[$qi]}; unset "docs[$qi]" "modes[$qi]" "hops[$qi]"'
  mutant "import: visited set removed" c_imp_cycle 'visited() { case "$VIS" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }   # import: visited' 'visited() { return 1; }'
  mutant "import: an escaping import queued" c_imp_escape 'np=$(normpath "$dir" "$t") || { row fail import "$loc" "$t: escapes the repository"; return; }   # import: escape' 'np=$(normpath "$dir" "$t") || { row pass import "$loc" "$t: queued"; return; }'
  mutant "import: escaped space splits the token" c_imp_escaped_space '  gsub(/\\ /, "\001", s)' ''
  mutant "import: a non-markdown import scanned" c_imp_nonmd 'is_md "$rp" || return   # import: markdown only' ':'
  mutant "import: a symlink judged by the link" c_imp_symlink_escape 'safe_resolve "$np" || { row fail import "$loc" "$t: $SO_WHY"; return; }' 'SO_LINK="" SO_PATH=$np'
  mutant "import: chain check dropped" c_imp_symlink_chain '120000) SO_WHY="links to $np, which is itself a symlink"; return 1 ;;   # safe_open: chain' '120000) ;;'
  mutant "import: a directory target passes" c_imp_symlink_dir 'tracked_dir "$np"; then SO_WHY="links to $np, a directory, which is not a tracked file"' 'tracked_dir "$np"; then SO_LINK=$np SO_PATH=$np; return 0'
  mutant "import: visited keyed on the link path" c_imp_visited_resolved '  visited "$rp" && return' '  visited "$np" && return' '  visit "$rp"
' '  visit "$np"
'
  mutant "import: absolute target read as repo-relative" c_imp_symlink_abs 'case "$tgt" in /*) SO_WHY="links to $tgt, which is an absolute path a clone does not have"; return 1 ;; esac   # safe_open: absolute' ':'
  mutant "import: a home path failed" c_imp_home_abs '"~"/*) row referred import' '"~"/*) row fail import'
  mutant "import: AGENTS.md parsed for imports" c_imp_agents_not_parsed 'for d in "${docs[@]+"${docs[@]}"}"; do modes+=(0); hops+=(0); done' 'for d in "${docs[@]+"${docs[@]}"}"; do modes+=(1); hops+=(0); done'
  mutant "import: an import never scanned" c_imp_scanned 'if [ "$rp" = AGENTS.md ]; then docs+=("$rp"); modes+=(0); else docs+=("$rp"); modes+=(1); fi   # import: queue' 'return'
  mutant "import: resolved from the root" c_imp_relative 'np=$(normpath "$dir" "$t") ||' 'np=$(normpath "" "$t") ||'
  mutant "import: the default set not deduped" c_imp_dedupe '  for d in "${docs[@]+"${docs[@]}"}"; do visit "$d"; done' '  :'
  mutant "import: ignore rule not tested" c_imp_ignored 'if git check-ignore -q --no-index -- "$np" 2>/dev/null; then   # import: ignored' 'if false; then'
  mutant "import: trailing punctuation stripped" c_imp_punct '    w = substr(w, 2); gsub(/\001/, " ", w)' '    w = substr(w, 2); gsub(/\001/, " ", w); sub(/[.,;:!?)]+$/, "", w)'
  mutant "import: an untracked CLAUDE.md followed" c_imp_entry_untracked 'if [ -n "$(idx_mode CLAUDE.md)" ]; then   # import: entry' 'if [ -e CLAUDE.md ]; then'
  mutant "presence instead of tracked" c_untracked 'if tracked AGENTS.md; then' 'if [ -e AGENTS.md ]; then'
  mutant "check-ignore without --no-index" c_ignored 'check-ignore -q --no-index' 'check-ignore -q'
  mutant "links resolved from the root" c_link_parent 'np=$(normpath "$dir" "$a")' 'np=$(normpath "" "$a")'
  mutant "commands scanned in prose" c_prose '  rest = spans(line)' '  code(line, 0); rest = spans(line)'
  mutant "referred collapsed into fail" c_referred 'row referred command' 'row fail command'
  mutant "directory link by exact match only" c_link_dir 'tracked "$1" || tracked_dir "$1"' 'tracked "$1"'
  mutant "cd scope widened to the whole file" c_cd_other_fence 'infence = 1; fcd = 0; fenv = 0; pcd = 0; penv = 0; next' 'infence = 1; fenv = 0; pcd = 0; penv = 0; next'
  mutant "paragraph scope narrowed to the span" c_para_span '    code(substr(rest, 1, j - 1), 0)' '    pcd = 0; code(substr(rest, 1, j - 1), 0)'
  mutant "[ -f package.json ] in place of tracked" c_pkg_untracked 'tracked package.json ||' '[ -f package.json ] ||'
  mutant "a cd ignored when the root defines the script" c_cd_root_defined '[ "$cd" != 0 ] && { row referred command "$loc" "$pm $v' '[ "$cd" != 0 ] && ! { tracked package.json && resolve_script "$name"; } && { row referred command "$loc" "$pm $v'
  mutant "a PR-template link that passes" c_tmpl 'if [ "$tmpl" = 1 ]; then' 'if false; then'
  mutant "an undefined yarn script fails (bare)" c_y_bare_neg 'else row referred command "$loc" "$lab $name: not defined' 'else row fail command "$loc" "$lab $name: not defined'
  mutant "an undefined yarn script fails (run)" c_y_run_neg 'else row referred command "$loc" "$lab $name: not defined' 'else row fail command "$loc" "$lab $name: not defined'
  mutant "flags after the name ignored" c_flag_after '-*) flag=$w; break ;;' '-*) ;;'
  mutant "jq checked eagerly" c_nojq_yarn $'set -f\n' $'set -f\ncommand -v jq >/dev/null 2>&1 || die "jq missing"\n'
  mutant "a missing workspace script passes" c_npm_ws_neg 'row fail command "$loc" "$lab: $name is not a script of' 'row pass command "$loc" "$lab: $name is not a script of'
  mutant "yarn workspace emits fail" c_yws_neg '      if [ "$pm" = yarn ]; then
        row referred' '      if false; then
        row referred'
  mutant "literal-name gate removed" c_selectors '[[ $ws =~ $wre ]] || {' 'true || {'
  mutant "pnpm dots selector passes" c_selectors '[ "$pm" = pnpm ] && case "$ws" in *...*)' 'false && case "$ws" in *...*)'
  mutant "workspace match by regex" c_dot_regex '$2 == ENVIRON["WS"]' '$2 ~ ENVIRON["WS"]'
  mutant "workspace match by prefix" c_scoped_neg '$2 == ENVIRON["WS"]' 'index($2, ENVIRON["WS"]) == 1'
  mutant "two manifests resolve to the last" c_dupe '*) WS_STATE=ambiguous; return ;;' '*) WS_STATE=nomatch; return ;;'
  mutant "manifest script read from the working tree" c_idx_ws_fail 'git show ":0:$WS_PATH" 2>/dev/null |' 'cat "$WS_PATH" 2>/dev/null |'
  mutant "manifest script read from the working tree (pass)" c_idx_ws_pass 'git show ":0:$WS_PATH" 2>/dev/null |' 'cat "$WS_PATH" 2>/dev/null |'
  mutant "manifest name read from the working tree" c_idx_ws_name 'git show ":0:$p" 2>/dev/null |' 'cat "$p" 2>/dev/null |'
  mutant "node_modules manifests not excluded" c_nm_pos '$0 !~ /(^|\/)node_modules\// && ' ''
  mutant "basename loosened to a suffix" c_notpkg '$0 ~ /(^|\/)package\.json$/' '$0 ~ /package\.json$/'
  mutant "root manifest taken as a candidate" c_root_not_cand '    $0 == "package.json" { next }
' ''
  mutant "workspace form validates the root" c_root_unread '[ -n "$ws_built" ] || build_ws_table "$1"' 'resolve_script x; [ -n "$ws_built" ] || build_ws_table "$1"'
  mutant "manifest name emitted raw" c_forged '[.name] | @tsv' '.name'
  mutant "a workspace name punctuation-trimmed" c_ws_notrim '  [[ $ws =~ $wre ]] ||' '  while :; do case "$ws" in *[.,]) ws=${ws%?} ;; *) break ;; esac; done; [[ $ws =~ $wre ]] ||'
  mutant "cd flag ignored by judge_yarn" c_cd_yarn 'judge_yarn "$loc" "$a" "$@" ;;' 'judge_yarn "$loc" 0 "$@" ;;'
  mutant "a flag after the script name ignored (scan)" c_shapes_neg '-*) SC_FLAG=$w; break ;;' '-*) ;;'
  mutant "resolver captured with command substitution" c_nojq_ws '  resolve_workspace "$ws" "$name"
' '  _x=$(resolve_workspace "$ws" "$name")
'
  mutant "table rebuilt per command" c_count_linear '[ -n "$ws_built" ] || build_ws_table "$1"' 'build_ws_table "$1"'
  mutant "table built at startup" c_count_zero 'for d in "${docs[@]+"${docs[@]}"}"; do' 'build_ws_table startup
for d in "${docs[@]+"${docs[@]}"}"; do'
  mutant "a yarn built-in resolved as a script" c_y_install 'install|add|remove|upgrade|up|init|dlx' 'add|remove|upgrade|up|init|dlx'
  mutant "a Yarn Classic built-in resolved as a script" c_y_classic 'check|licenses|owner' 'licenses|owner'
  mutant ".txt templates dropped" c_tmpl_txt '(\.md|\.txt)?$' '(\.md)?$'
  mutant "scripts read from the working tree" c_index_blob 'git show :package.json >' 'cat package.json >'
  mutant "CR kept on blank lines" c_para_crlf '{ sub(/\r$/, "") }
{
  line' '{
  line'
  mutant "a fence closed by a blank line" c_fence_unclosed '    code(line, 1); next' '    if (trim(line) == "") { infence = 0; next }
    code(line, 1); next'
  mutant "an escaping link read from disk" c_escape 'row fail link "$loc" "$a: escapes the repository"' 'row fail link "$loc" "$a: escapes the repository"; cat "${dir:-.}/$a" >/dev/null 2>&1'
  # #338. The hang shapes the watchdog cannot release: only the bound in `run` kills them, so each
  # also asserts RC 124 (it dies on the bound, not for an unrelated reason). They run at a watchdog
  # of 3 s, set by plain assignment and restored after: a prefix on the call would expand the sleep
  # below with the old value, because bash expands arguments before a prefix assignment applies.
  # The sleep is expanded by the suite, never left as $((...)) in the mutant text, which would die
  # at once with "unbound variable" under the script's `set -u`.
  ESC_SAVED=$ESCAPE_WATCHDOG_SECS; ESCAPE_WATCHDOG_SECS=3
  ESC_ROW='row fail link "$loc" "$a: escapes the repository"'
  mutant "an escaping link opened three times" c_escape "$ESC_ROW" "$ESC_ROW"'; cat "${dir:-.}/$a" >/dev/null 2>&1; cat "${dir:-.}/$a" >/dev/null 2>&1; cat "${dir:-.}/$a" >/dev/null 2>&1'
  [ "$RC" = 124 ] && ok "the three-open mutant was killed by the run bound (RC 124)" || bad "the three-open mutant was killed by the run bound (RC $RC)"
  mutant "an escaping link opened for writing" c_escape "$ESC_ROW" "$ESC_ROW"'; : > "${dir:-.}/$a" 2>/dev/null'
  [ "$RC" = 124 ] && ok "the write-open mutant was killed by the run bound (RC 124)" || bad "the write-open mutant was killed by the run bound (RC $RC)"
  mutant "an escaping link read twice after the watchdog" c_escape "$ESC_ROW" "$ESC_ROW"'; sleep '"$((ESCAPE_WATCHDOG_SECS + 2))"'; cat "${dir:-.}/$a" >/dev/null 2>&1; cat "${dir:-.}/$a" >/dev/null 2>&1'
  [ "$RC" = 124 ] && ok "the read-twice mutant was killed by the run bound (RC 124)" || bad "the read-twice mutant was killed by the run bound (RC $RC)"
  # Control: one read after the sleep. It sleeps at two links, so it dies through the probe or the bound.
  mutant "an escaping link read late" c_escape "$ESC_ROW" "$ESC_ROW"'; sleep '"$((ESCAPE_WATCHDOG_SECS + 2))"'; cat "${dir:-.}/$a" >/dev/null 2>&1'
  ESCAPE_WATCHDOG_SECS=$ESC_SAVED
  mutant "an assignment prefix skipped silently" c_env_prefix '+ 2 * (env || carry)' '+ 0 * (env || carry)'
  # #326. Each names the case written to kill it.
  mutant "trim_punct trims nothing" c_pm_trim_site 'trim_punct() { TP=$1; ' 'trim_punct() { TP=$1; return; '
  mutant "trim_punct trims once" c_pm_trim_edges 'TP=${TP%?} ;; *) break' 'TP=${TP%?}; break ;; *) break'
  mutant "judge_pm trim removed" c_pm_trim_site '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  local re=' '  local re='
  mutant "judge_ws trim removed" c_ws_trim_site '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: ' '  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: '
  mutant "judge_yarn_root trim removed" c_yroot_trim_site '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab $name' '  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab $name'
  mutant "lifecycle word left raw" c_pm_trim_lifecycle 'trim_punct "$1"; w=$TP' 'w=$1'
  mutant "pnpm silent list matched on the raw word" c_pm_trim_pnpm_builtin '       case "$w" in
         install|i|add' '       case "$1" in
         install|i|add'
  mutant "pnpm first-word row prints the trimmed word" c_pm_trim_edges 'row referred command "$loc" "pnpm $1: may be a script, a built-in or a binary"; return ;;
  esac' 'row referred command "$loc" "pnpm $w: may be a script, a built-in or a binary"; return ;;
  esac'
  mutant "dispatch subject trimmed" c_pm_run_untrimmed '  if [ $# -eq 0 ]; then return; fi
  case "$1" in
    run|run-script) v=$1; shift ;;' '  if [ $# -eq 0 ]; then return; fi
  trim_punct "$1"
  case "$TP" in
    run|run-script) v=$1; shift ;;'
  # #353. Item 1: the lifecycle row's two halves, each killed by the one case that pins it.
  mutant "lifecycle row prints the trimmed word" c_pm_trim_lifecycle '"$pm $1: runs a lifecycle script' '"$pm $w: runs a lifecycle script'
  mutant "lifecycle word tested on the raw word" c_pm_trim_lifecycle 'case "$w" in
         test|start' 'case "$1" in
         test|start'
  # Item 2: two-line per-site anchors (the fixed text is OLD), so each replaces exactly one site.
  mutant "judge_pm empty name printed" c_pm_empty_name_raw '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  local re=' '  trim_punct "$name"; name=$TP
  local re='
  mutant "judge_ws empty name printed" c_ws_empty_name_raw '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: ' '  trim_punct "$name"; name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: '
  mutant "judge_yarn_root empty name printed" c_yroot_empty_name_raw '  trim_punct "$name"; [ -n "$TP" ] && name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab $name' '  trim_punct "$name"; name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab $name'
  # Item 3: both halves are reverted together, because re-adding run-script to the lifecycle list
  # alone is an equivalent mutant (the dispatch matches it first).
  mutant "run-script back in the lifecycle list" c_pm_run_script_defined 'run|run-script) v=$1; shift ;;' 'run) shift ;;' 'test|start|t|tst)' 'test|start|run-script|t|tst)'
  mutant "run-script back in the lifecycle list (undefined)" c_pm_run_script_undefined 'run|run-script) v=$1; shift ;;' 'run) shift ;;' 'test|start|t|tst)' 'test|start|run-script|t|tst)'
  mutant "run-script dispatch matched on the trimmed word" c_pm_run_script_dispatch_raw '  case "$1" in
    run|run-script) v=$1; shift ;;' '  trim_punct "$1"; case "$TP" in
    run|run-script) v=$1; shift ;;'
  # #363: each workspace arm and the flag loop reverted on its own (arm-prefixed anchors occur once).
  mutant "four-flag workspace arm reverted to run only" c_pm_run_script_ws_npm '--filter|pnpm:-F) [ $# -ge 3 ] && is_run "$3"' '--filter|pnpm:-F) [ $# -ge 3 ] && [ "$3" = run ]'
  mutant "npm --workspace= arm reverted to run only" c_pm_run_script_ws_npm 'npm:--workspace=*) [ $# -ge 2 ] && is_run "$2"' 'npm:--workspace=*) [ $# -ge 2 ] && [ "$2" = run ]'
  mutant "pnpm --filter= arm reverted to run only" c_pm_run_script_ws_pnpm 'pnpm:--filter=*) [ $# -ge 2 ] && is_run "$2"' 'pnpm:--filter=*) [ $# -ge 2 ] && [ "$2" = run ]'
  mutant "workspace is_run accepts run-scripts" c_pm_run_script_ws_near 'is_run() { [ "$1" = run ] || [ "$1" = run-script ]; }' 'is_run() { [ "$1" = run ] || case "$1" in run-script*) true ;; *) false ;; esac; }'
  mutant "workspace label rewritten to run" c_pm_run_script_ws_npm 'judge_ws "$loc" "$cd" "$pm $*" "$pm"' 'judge_ws "$loc" "$cd" "$pm run" "$pm"'
  mutant "flag loop reverted to run only" c_run_script_flag_between 'is_run "$w" && { row referred command "$loc" "$pm $*: a flag between' '[ "$w" = run ] && { row referred command "$loc" "$pm $*: a flag between'
  # #390: the flag loop stops at a non-flag word and skips the value of exactly seven flags.
  mutant "flag loop does not stop at a non-flag word" c_flag_between_stops_at_word '            *:-*) ;;' '            *) ;;'
  mutant "flag loop never clears the skip" c_flag_between_value_unchanged 'then skip=0; continue; fi' 'then continue; fi'
  mutant "value skip drops npm -w" c_vskip_npm_w 'npm:-w|npm:--workspace|npm:--prefix|' 'npm:--workspace|npm:--prefix|'
  mutant "value skip drops npm --workspace" c_vskip_npm_workspace 'npm:--workspace|npm:--prefix|' 'npm:--prefix|'
  mutant "value skip drops npm --prefix" c_vskip_npm_prefix 'npm:--prefix|npm:-C|pnpm:--filter|' 'npm:-C|pnpm:--filter|'
  mutant "value skip drops npm -C" c_vskip_npm_C 'npm:--prefix|npm:-C|pnpm:' 'npm:--prefix|pnpm:'
  mutant "value skip drops pnpm --filter" c_vskip_pnpm_filter 'npm:-C|pnpm:--filter|pnpm:-F|' 'npm:-C|pnpm:-F|'
  mutant "value skip drops pnpm -F" c_vskip_pnpm_F 'pnpm:--filter|pnpm:-F|pnpm:-C|' 'pnpm:--filter|pnpm:-C|'
  mutant "value skip drops pnpm -C" c_vskip_pnpm_C 'pnpm:-F|pnpm:-C|pnpm:--dir)' 'pnpm:-F|pnpm:--dir)'
  mutant "value skip drops pnpm --dir" c_vskip_pnpm_dir '|pnpm:-C|pnpm:--dir)' '|pnpm:-C)'
  mutant "flag loop prints a fixed run" c_run_script_flag_between 'a flag between $pm and $w may' 'a flag between $pm and run may'
  mutant "flag loop prints a fixed run-script" c_run_flag_between_unchanged 'a flag between $pm and $w may' 'a flag between $pm and run-script may'
  mutant "flag row prints run" c_pm_run_script_flag '"$pm $v ${name:-...}: $flag may change' '"$pm run ${name:-...}: $flag may change'
  mutant "not-literal row prints run" c_pm_run_script_not_literal '"$pm $v $name: not a literal script name' '"$pm run $name: not a literal script name'
  mutant "cd row prints run" c_pm_run_script_cd '"$pm $v $name: $(why_cd' '"$pm run $name: $(why_cd'
  mutant "npmrc symlink row prints run" c_pm_run_script_npmrc_link '"npm $v $name: a tracked .npmrc is a symlink' '"npm run $name: a tracked .npmrc is a symlink'
  mutant "npmrc row prints run" c_pm_run_script_npmrc '"npm $v $name: a tracked .npmrc sets' '"npm run $name: a tracked .npmrc sets'
  mutant "no-package row prints run" c_pm_run_script_no_pkg '"$pm $v $name: no root package.json' '"$pm run $name: no root package.json'
  mutant "pass row prints run" c_pm_run_script_defined '"$pm $v $name: defined in' '"$pm run $name: defined in'
  mutant "fail row prints run" c_pm_run_script_undefined '"$pm $v $name: no such script' '"$pm run $name: no such script'
  mutant "workspace built-in message prints the raw word" c_yws_builtin '"$lab: $b1 may be a yarn built-in"' '"$lab: $1 may be a yarn built-in"'
  mutant "a second inline copy of the trim loop" c_trim_once 'first_file() {' 'X=; while :; do case "$X" in *[.,\;:!?]) X=${X%?} ;; *) break ;; esac; done
first_file() {'
  # #317. Each names the case written to kill it.
  mutant "yarn root with no manifest dies" c_y_noroot 'tracked package.json || { row referred command "$loc" "$lab $name: no root package.json is tracked"; return; }' 'tracked package.json || die "no root manifest"'
  mutant "yarn root no-manifest guard deleted" c_y_noroot '  tracked package.json || { row referred command "$loc" "$lab $name: no root package.json is tracked"; return; }
' ''
  mutant "yarn stops refusing a silent flag" c_silent_yarn '--silent|-s) [ "$ok" = 1 ] || { SC_FLAG=$w; break; } ;;' '--silent|-s) ;;'
  mutant "npm or pnpm workspace stops exempting a silent flag" c_silent_npm_ws '--silent|-s) [ "$ok" = 1 ] || { SC_FLAG=$w; break; } ;;' '--silent|-s) SC_FLAG=$w; break ;;'
  mutant "yarn workspace undefined script reported as no match" c_yws_neg 'row referred command "$loc" "$lab: workspace $ws ($WS_PATH) does not define $name; yarn may run a binary"' 'row referred command "$loc" "$lab: no tracked manifest is named $ws"'
  mutant "yarn unplug resolved as a script" c_y_berry 'explain|unplug|stage|patch-commit|search)' 'explain|stage|patch-commit|search)'
  mutant "yarn stage resolved as a script" c_y_berry 'explain|unplug|stage|patch-commit|search)' 'explain|unplug|patch-commit|search)'
  mutant "yarn patch-commit resolved as a script" c_y_berry 'explain|unplug|stage|patch-commit|search)' 'explain|unplug|stage|search)'
  mutant "yarn search resolved as a script" c_y_berry 'explain|unplug|stage|patch-commit|search)' 'explain|unplug|stage|patch-commit)'
  mutant "yarn run consults the built-in list" c_y_berry_run 'run) [ $# -ge 2 ] || return; shift; judge_yarn_root' 'run) [ $# -ge 2 ] || return; shift; yarn_builtin "$1"; [ $? = 0 ] && return; judge_yarn_root'
  # #296. Each pair names the case written to kill it.
  mutant "export carry removed" c_export_carry '{ if (infence) fenv = 1; else penv = 1 }' '{ }'
  mutant "export carry widened to every variable" c_export_other_neg "$XRE" 'qs[j] ~ /=/'
  mutant "export carry widened (NODE_ENV)" c_export_node_env_neg "$XRE" 'qs[j] ~ /=/'
  mutant "export carry cleared by an intervening line" c_export_gap 'carry = infence ? fenv : penv' 'carry = infence ? fenv : penv; if (w != "npm") { fenv = 0; penv = 0 }'
  mutant "export carry not reset at fence open" c_export_next_fence 'fcd = 0; fenv = 0; pcd = 0; penv = 0; next' 'fcd = 0; pcd = 0; penv = 0; next'
  mutant "export name match unanchored" c_export_name_neg 'qs[j] ~ /^[Nn][Pp][Mm]_' 'qs[j] ~ /[Nn][Pp][Mm]_'
  mutant "export match lowercase only" c_export_mixed "$XRE" 'qs[j] ~ /^npm_config_[A-Za-z0-9_]*=/'
  mutant "export match workspace key only" c_export_loglevel '[Ff][Ii][Gg]_[A-Za-z0-9_]*(=|' '[Ff][Ii][Gg]_workspace(=|'
  mutant "empty-valued export not carried" c_export_empty '[Ff][Ii][Gg]_[A-Za-z0-9_]*(=|' '[Ff][Ii][Gg]_[A-Za-z0-9_]*(=[^ \t]|'
  mutant "paragraph carry removed" c_export_span 'fenv = 1; else penv = 1' 'fenv = 1; else penv = 0'
  mutant "paragraph carry not reset at blank line" c_export_span_blank_neg 'trim(line) == "") { pcd = 0; penv = 0; next }' 'trim(line) == "") { pcd = 0; next }'
  mutant "prose carry leaks into a following fence" c_export_span_fence 'fcd = 0; fenv = 0; pcd' 'fcd = 0; fenv = penv; pcd'
  mutant "export carry applied only to later lines" c_export_andand '  for (i = 1; i <= n; i++) {' $'  cin_ = infence ? fenv : penv\n  for (i = 1; i <= n; i++) {' 'carry = infence ? fenv : penv' 'carry = cin_'
  mutant "carry applied before the export segment" c_export_after_neg 'carry = infence ? fenv : penv' 'carry = (infence ? fenv : penv) || (text ~ /export[ \t]+[Nn][Pp][Mm]_/)'
  mutant "carry overrides a cd" c_export_cd '(infence ? fcd : pcd) + 2 * (env || carry)' '((env || carry) ? 2 : (infence ? fcd : pcd))'
  mutant "carry reported as a directory change" c_export_no_cd_reason '2 * (env || carry)' '2 * env + 3 * carry'
  mutant "declare -x dropped" c_export_declare 'if (w == "declare" || w == "typeset") for' 'if (w == "typeset") for'
  mutant "typeset -x dropped" c_export_typeset 'if (w == "declare" || w == "typeset") for' 'if (w == "declare") for'
  mutant "declare without -x carried" c_declare_plain_neg 'isx = (w == "export")' 'isx = (w == "export" || w == "declare")'
  mutant "assignment-value rewrite removed" c_subst_value '  if (index(text, "=")) {' '  if (0) {'
  mutant "substitution anywhere refers the row (other)" c_subst_other_neg '  if (index(text, "=")) {' $'  if (text ~ /\\$\\(/) { gsub(/;/, "; X=X ", text); text = "X=X " text }\n  if (index(text, "=")) {'
  mutant "substitution anywhere refers the row (argument)" c_subst_after_neg '  if (index(text, "=")) {' $'  if (text ~ /\\$\\(/) { gsub(/;/, "; X=X ", text); text = "X=X " text }\n  if (index(text, "=")) {'
  mutant "substitution rewrite not word-anchored" c_subst_flag_value 'gsub(/[ \t;&|(][A-Za-z_][A-Za-z0-9_]*=/' 'gsub(/[A-Za-z_][A-Za-z0-9_]*=/'
  mutant "a substitution body executed" c_pwned 'IDX=$T/index ROWS=$T/rows' 'IDX=$T/index ROWS=$T/rows; touch pwned'
  mutant_needs make "make invoked to find a target" c_make_include 'verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk")' 'make -n -f "$f" "$TGT" >/dev/null 2>&1; verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk")'
  # #339. Each names the case written to kill it.
  mutant "npmrc never read" c_npmrc_ws_undef '    npmrc_scan
' ''
  mutant "npmrc never read (a pass)" c_npmrc_ws_defined '    npmrc_scan
' ''
  mutant "npmrc read from the working tree instead of the index" c_npmrc_untracked 'tracked .npmrc || return' '[ -e .npmrc ] || return' 'git show :.npmrc 2>/dev/null |' 'cat .npmrc 2>/dev/null |'
  mutant "npmrc read from the working tree instead of the index (blob)" c_npmrc_index_blob 'git show :.npmrc 2>/dev/null |' 'cat .npmrc 2>/dev/null |'
  mutant "any .npmrc refers regardless of key" c_npmrc_registry_neg '    $0 == "" || /^[;#]/ { next }' '    $0 == "" || /^[;#]/ { next }
    { print "workspace"; exit }'
  mutant "comment lines count as the key" c_npmrc_comment_neg '$0 == "" || /^[;#]/ { next }' '$0 == "" { next }
    { sub(/^[;#][ \t]*/, "") }'
  mutant "substring match on workspace" c_npmrc_key_neg 'if (key == "workspace") hasws = 1' 'if (index(key, "workspace")) hasws = 1'
  # #395: the array form.
  mutant "array flag dropped" c_npmrc_wsarray_plain 'if (key == "workspaces[]") wsarr = 1' 'if (0) wsarr = 1'
  mutant "array read as the scalar on an explicit run" c_npmrc_wsarray_explicit '      if (wsarr) { last = "true"; seen = 1 }
' ''
  mutant "a later scalar false overrides the array" c_npmrc_wsarray_scalar_false_neg '{ last = "true"; seen = 1 }' '{ last = "true"; seen = 1; wsarr = 0 }'
  mutant "array key tested after the bracket strip" c_npmrc_wsarray_plain '      if (key == "workspaces[]") wsarr = 1
      sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)' '      sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)
      if (key == "workspaces[]") wsarr = 1'
  mutant "array key tested before the quote strip" c_npmrc_wsarray_quoted '      if (kn > 1 && (kc == "\"" || kc == "\047") && substr(key, kn, 1) == kc) key = substr(key, 2, kn - 2)
      if (key == "workspaces[]") wsarr = 1' '      if (key == "workspaces[]") wsarr = 1
      if (kn > 1 && (kc == "\"" || kc == "\047") && substr(key, kn, 1) == kc) key = substr(key, 2, kn - 2)'
  mutant "workspaces key ignored" c_npmrc_workspaces 'if (key == "workspaces") { last = val; seen = 1 }' 'if (0) { last = val; seen = 1 }'
  mutant "only a would-be fail becomes referred" c_npmrc_ws_defined '[ -n "$NPMRC_KEY" ] && { row referred' '[ -n "$NPMRC_KEY" ] && ! { tracked package.json && resolve_script "$name"; } && { row referred'
  mutant "a non-root .npmrc is read" c_npmrc_subdir_neg 'tracked .npmrc || return' 'tracked client/.npmrc || return' 'git ls-files -s -- .npmrc' 'git ls-files -s -- client/.npmrc' 'git show :.npmrc 2>/dev/null |' 'git show :client/.npmrc 2>/dev/null |'
  mutant "the whole .npmrc is echoed" c_npmrc_token '"npm $v $name: a tracked .npmrc sets $NPMRC_KEY"; return; }' '"npm $v $name: a tracked .npmrc sets $NPMRC_KEY"; git show :.npmrc; return; }'
  mutant "the matched .npmrc line is echoed" c_npmrc_token 'if (key == "workspace") hasws = 1' 'if (key == "workspace") { hasws = 1; wsl = $0 }' 'print (hasws ? "workspace" :' 'print (hasws ? wsl :'
  mutant "npm-only guard dropped" c_npmrc_pnpm_unchanged '  if [ "$pm" = npm ]; then
    npmrc_scan' '  if true; then
    npmrc_scan'
  mutant "refer on workspaces=false" c_npmrc_ws_false 'seen && last != "false" ? "workspaces"' 'seen ? "workspaces"'
  mutant "CR strip dropped" c_npmrc_ws_false_crlf "| tr '\\r' '\\n' |" '|'
  mutant "section stop dropped" c_npmrc_section_neg '    /^\[[^]]*\][ \t]*$/ { exit }
' ''
  mutant "byte-order mark strip dropped" c_npmrc_bom '    NR == 1 { sub(/^\357\273\277/, "") }
' ''
  mutant "make byte-order mark strip dropped" c_make_bom 'MAKE_AWK='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'MAKE_AWK='\''
'
  mutant "just byte-order mark strip dropped" c_just_bom 'JUST_AWK='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'JUST_AWK='\''
'
  mutant "make strip placed after the include rule" c_make_bom_include 'MAKE_AWK='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'MAKE_AWK='\''
' '/^[ \t]*(-?include|sinclude)[ \t]/ { unsettled = 1; next }
' '/^[ \t]*(-?include|sinclude)[ \t]/ { unsettled = 1; next }
NR == 1 { sub(/^\357\273\277/, "") }
'
  mutant "just strip placed after the set fallback rule" c_just_bom_fallback 'JUST_AWK='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'JUST_AWK='\''
' '/^(import|mod)[ \t?]/ || /^set[ \t]+fallback/ { unsettled = 1; next }
' '/^(import|mod)[ \t?]/ || /^set[ \t]+fallback/ { unsettled = 1; next }
NR == 1 { sub(/^\357\273\277/, "") }
'
  # No just twin of this mutant: #364 declined it, because both readers share the one-line
  # NR == 1 shape and this make case pins it. A just-only drift of that shape would survive.
  mutant "make strip not limited to line 1" c_make_bom_later_line 'MAKE_AWK='\''
NR == 1 { sub(/' 'MAKE_AWK='\''
{ sub(/'
  # #374. EXTRACT=' occurs once, so the opener is a unique anchor (the bare strip line is not: it
  # also sits in npmrc_scan, MAKE_AWK and JUST_AWK, and mutant replaces every occurrence).
  mutant "doc reader byte-order mark strip dropped" c_doc_bom_fence_neg 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (pass)" c_doc_bom_fence_pos 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (CRLF, fail)" c_doc_bom_crlf_neg 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (CRLF, pass)" c_doc_bom_crlf_pos 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (pairing, fail)" c_doc_bom_pairing_neg 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (pairing, pass)" c_doc_bom_pairing_pos 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (reference definition)" c_doc_bom_refdef_neg 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip dropped (--docs)" c_doc_bom_contributing 'EXTRACT='\''
NR == 1 { sub(/^\357\273\277/, "") }
' 'EXTRACT='\''
'
  mutant "doc reader byte-order mark strip applied to every line" c_doc_bom_line2_kept 'EXTRACT='\''
NR == 1 {' 'EXTRACT='\''
{'
  mutant "section test after the indentation trim" c_npmrc_indented_section '    /^\[[^]]*\][ \t]*$/ { exit }
    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }' '    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    /^\[[^]]*\][ \t]*$/ { exit }'
  mutant "case-insensitive key" c_npmrc_case_neg 'if (key == "workspace") hasws = 1' 'if (tolower(key) == "workspace") hasws = 1'
  mutant "[] strip dropped" c_npmrc_bracket 'sub(/\[\]$/, "", key); ' ''
  mutant "detail always workspace" c_npmrc_workspaces 'sets $NPMRC_KEY"' 'sets workspace"'
  mutant "final line without a newline dropped" c_npmrc_no_final_newline 'git show :.npmrc 2>/dev/null |' 'git show :.npmrc 2>/dev/null | while IFS= read -r l; do printf "%s\n" "$l"; done |'
  mutant "exact workspace= string match" c_npmrc_spaced 'sub(/[ \t]+$/, "", key); kn = length(key)' 'kn = length(key)' 'sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)' 'sub(/\[\]$/, "", key)'
  mutant "refers when no .npmrc exists" c_npmrc_none_neg '    [ -n "$NPMRC_KEY" ] && { row referred command "$loc" "npm $v' '    [ -z "$NPMRC_KEY" ] && { row referred command "$loc" "npm $v'
  mutant "the .npmrc rule leaks into the explicit workspace forms" c_npmrc_unchanged_forms '  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }' '  npmrc_scan; [ -n "$NPMRC_KEY" ] && { row referred command "$loc" "$lab: a tracked .npmrc sets $NPMRC_KEY"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }'
  # #357. Anchors are exact substrings of the awk and the functions around it.
  mutant "quote strip dropped" c_npmrc_ws_false_quoted 'if (n > 1 && (c == "\"" || c == "\047") && substr(val, n, 1) == c) val = substr(val, 2, n - 2)' 'if (0) val = substr(val, 2, n - 2)'
  mutant "single quote not stripped" c_npmrc_ws_false_squoted '(c == "\"" || c == "\047")' '(c == "\"")'
  mutant "closing quote not checked" c_npmrc_quote_mismatch '&& substr(val, n, 1) == c) val =' ') val ='
  mutant "leading trim dropped" c_npmrc_indented_key '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }' '{ sub(/[ \t]+$/, "") }'
  mutant "trim narrowed to spaces" c_npmrc_indented_key_tab '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }' '{ sub(/^ +/, ""); sub(/[ \t]+$/, "") }'
  mutant "any .npmrc refers regardless of key (indented)" c_npmrc_indented_nonkey_neg '    $0 == "" || /^[;#]/ { next }' '    $0 == "" || /^[;#]/ { next }
    { print "workspace"; exit }'
  mutant "symlink check removed" c_npmrc_symlink 'if [ "$NPMRC_MODE" = 120000 ]; then' 'if [ "$NPMRC_MODE" = never ]; then'
  mutant "link followed on disk and printed" c_npmrc_symlink_nofollow 'NPMRC_KEY=symlink; return; fi' 'NPMRC_KEY=symlink; cat .npmrc; return; fi'
  mutant "target echoed" c_npmrc_symlink_nofollow 'NPMRC_KEY=symlink; return; fi' 'NPMRC_KEY=symlink; readlink .npmrc; return; fi'
  mutant "link detected by content" c_npmrc_symlink_text_neg 'if [ "$NPMRC_MODE" = 120000 ]; then' 'if [ "$NPMRC_MODE" = 120000 ] || git show :.npmrc 2>/dev/null | grep -q /; then'
  mutant "a non-root .npmrc is read through the mode probe" c_npmrc_symlink_subdir_neg 'tracked .npmrc || return' 'tracked client/.npmrc || return' 'git ls-files -s -- .npmrc' 'git ls-files -s -- client/.npmrc' 'git show :.npmrc 2>/dev/null |' 'git show :client/.npmrc 2>/dev/null |'
  mutant "npm-only guard dropped (symlink)" c_npmrc_symlink_pnpm_unchanged '  if [ "$pm" = npm ]; then
    npmrc_scan' '  if true; then
    npmrc_scan'
  mutant "explicit form not consulted (-w)" c_npmrc_wsfalse_explicit_w '[ "$NPMRC_LAST" = wsfalse ] && { row referred command "$loc" "$lab: a tracked .npmrc sets workspaces=false"; return; }; fi' 'true; fi'
  mutant "explicit form not consulted (--workspace)" c_npmrc_wsfalse_explicit_workspace '[ "$NPMRC_LAST" = wsfalse ] && { row referred command "$loc" "$lab: a tracked .npmrc sets workspaces=false"; return; }; fi' 'true; fi'
  mutant "explicit form not consulted (--workspace=)" c_npmrc_wsfalse_explicit_eq '[ "$NPMRC_LAST" = wsfalse ] && { row referred command "$loc" "$lab: a tracked .npmrc sets workspaces=false"; return; }; fi' 'true; fi'
  mutant "first value wins (true then false)" c_npmrc_wsfalse_last_true_then_false 'if (key == "workspaces") { last = val; seen = 1 }' 'if (key == "workspaces" && !seen) { last = val; seen = 1 }'
  mutant "first value wins (false then true)" c_npmrc_wsfalse_last_false_then_true 'if (key == "workspaces") { last = val; seen = 1 }' 'if (key == "workspaces" && !seen) { last = val; seen = 1 }'
  mutant "first value wins (plain)" c_npmrc_plain_false_then_true 'if (key == "workspaces") { last = val; seen = 1 }' 'if (key == "workspaces" && !seen) { last = val; seen = 1 }'
  mutant "workspace key masks the false state" c_npmrc_wsfalse_with_wskey_explicit '(seen && last == "false" ? "wsfalse" : "-")' '(!hasws && seen && last == "false" ? "wsfalse" : "-")'
  mutant "any workspaces value refers an explicit form" c_npmrc_wsfalse_explicit_neg '(seen && last == "false" ? "wsfalse" : "-")' '(seen ? "wsfalse" : "-")'
  mutant "judge_ws npm-only guard dropped" c_npmrc_wsfalse_pnpm_unchanged 'if [ "$pm" = npm ]; then npmrc_scan; [ "$NPMRC_LAST"' 'if true; then npmrc_scan; [ "$NPMRC_LAST"'
  mutant "workspace key ignored when workspaces ends false" c_npmrc_plain_true_then_false_wskey 'if (key == "workspace") hasws = 1' 'if (key == "workspace" && val != "client") hasws = 1'
  mutant "any seen workspaces value refers a plain run" c_npmrc_plain_true_then_false_neg 'seen && last != "false" ? "workspaces"' 'seen ? "workspaces"'
  # #381. Anchors are exact substrings of npmrc_scan's awk and of judge_ws.
  mutant "both keys report the plural" c_npmrc_plain_true_then_false_wskey 'print (hasws ? "workspace" :' 'print (hasws ? (seen ? "workspaces" : "workspace") :'
  mutant "symlinked .npmrc refuses an explicit form" c_npmrc_symlink_explicit_limit 'npmrc_scan; [ "$NPMRC_LAST" = wsfalse ] && { row referred' 'npmrc_scan; { [ "$NPMRC_LAST" = wsfalse ] || [ "$NPMRC_KEY" = symlink ]; } && { row referred'
  mutant "an explicit form is referred with no .npmrc" c_npmrc_wsfalse_none_neg 'npmrc_scan; [ "$NPMRC_LAST" = wsfalse ] && { row referred' 'npmrc_scan; [ "$NPMRC_LAST" != - ] && { row referred'
  mutant "numeric zero not read as false" c_npmrc_zero_explicit 'if (val ~ /^[-+]?(0+\.?0*|\.0+)$/) val = "false"' 'if (0) val = "false"'
  mutant "any number read as false" c_npmrc_one_neg '/^[-+]?(0+\.?0*|\.0+)$/' '/^[0-9.]+$/'
  mutant "zero regex accepts only a single 0" c_npmrc_zero_spellings_explicit '/^[-+]?(0+\.?0*|\.0+)$/' '/^0$/'
  mutant "inline comment kept in the value" c_npmrc_inline_comment_explicit 'else if (match(val, /[;#]/))' 'else if (0)'
  mutant "inline comment makes the value false" c_npmrc_inline_comment_true_neg 'val = substr(val, 1, RSTART - 1); sub(/[ \t]+$/, "", val) }' 'val = "false" }'
  mutant "comment cut before unquote" c_npmrc_quoted_value_comment_neg 'sub(/^[ \t]+/, "", val); n = length(val); c = substr(val, 1, 1)' 'sub(/^[ \t]+/, "", val); if (match(val, /[;#]/)) { val = substr(val, 1, RSTART - 1); sub(/[ \t]+$/, "", val) } n = length(val); c = substr(val, 1, 1)'
  mutant "quote strip after the [] strip" c_npmrc_quoted_key_ws '      sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)' '      sub(/[ \t]+$/, "", key)' 'kn = length(key); kc = substr(key, 1, 1)' 'sub(/\[\]$/, "", key); kn = length(key); kc = substr(key, 1, 1)'
  mutant "quoted key not unquoted" c_npmrc_quoted_key_explicit 'if (kn > 1 && (kc' 'if (0 && (kc'
  # #398: the three single edits that survived the suite.
  mutant "pre-unquote key trim dropped" c_npmrc_quoted_key_explicit 'sub(/[ \t]+$/, "", key); kn = length(key)' 'kn = length(key)'
  mutant "comment cut inside a quoted value" c_npmrc_quoted_value_hash_explicit 'else if (match(val, /[;#]/))' 'if (match(val, /[;#]/))'
  mutant "empty value read as false" c_npmrc_empty_after_cut 'if (val ~ /^[-+]?(0+\.?0*|\.0+)$/) val' 'if (val ~ /^[-+]?(0+\.?0*|\.0+)$/ || val == "") val'
  mutant "closing key quote not checked" c_npmrc_quoted_key_mismatch_neg '&& substr(key, kn, 1) == kc) key =' ') key ='
  # #346. Anchors are exact substrings of code() in the shipped script.
  mutant "carry applied to every runner" c_export_make_neg '    if (w != "npm" && w != "pnpm" && w != "yarn") carry = 0
' ''
  mutant "carry kept for make" c_export_make_neg 'w != "npm" && w != "pnpm" && w != "yarn"' 'w != "npm" && w != "pnpm" && w != "yarn" && w != "make"'
  mutant "carry kept for just" c_export_just_neg 'w != "npm" && w != "pnpm" && w != "yarn"' 'w != "npm" && w != "pnpm" && w != "yarn" && w != "just"'
  mutant "pnpm dropped from carry" c_export_pnpm 'w != "npm" && w != "pnpm" && w != "yarn"' 'w != "npm" && w != "yarn"'
  mutant "yarn dropped from carry" c_export_yarn 'w != "npm" && w != "pnpm" && w != "yarn"' 'w != "npm" && w != "pnpm"'
  mutant "substitution prefix text not rewritten" c_subst_prefix_value '\001([^ \t;&|()$"\047`\\\001\002\003]|\$\(' '\001(\$\('
  mutant "second substitution of a value not rewritten" c_subst_double_value '|\002[^\003]*\003)+/, "X", text)' '|\002[^\003]*\003)/, "X", text)'
  mutant "assignment value stops at a backtick" c_subst_backtick_nospace '=[^ \t]*[ \t]+)+/' '=[^ \t`]*[ \t]+)+/' '|`[^`]*`|' '|'
  mutant "backtick run not rewritten as a value" c_subst_backtick_space '|`[^`]*`|' '|'
  mutant "double-quoted run not rewritten as a value" c_quoted_space_nosubst 'gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047|`[^`]*`|' 'gsub(/\047[^\047]*\047|`[^`]*`|'
  mutant "single-quoted run not rewritten as a value" c_single_quoted_space '|\047[^\047]*\047|' '|'
  mutant "escaped byte not rewritten as a value" c_escaped_space '|`[^`]*`|\\./, "\002&\003"' '|`[^`]*`/, "\002&\003"'
  mutant "value rewrite only where a substitution is" c_swallowed_cd '  if (index(text, "=")) {' '  if (index(text, "$(")) {'
  mutant "declare -x flag test is exactly -x" c_export_declare_gx '/^-[A-Za-z]*x/' '/^-x$/'
  mutant "declare checks only the first dash word" c_export_declare_g_x 'j <= nw && ws[j] ~ /^[-+]/' 'j <= 2 && ws[j] ~ /^[-+]/'
  mutant "declare carries on any dash word" c_declare_g_plain_neg '/^-[A-Za-z]*x/' '/^-/'
  mutant "double-quoted export argument not accepted" c_export_quoted_dq 'gsub(/["\047][Nn][Pp][Mm]_' 'gsub(/[\047][Nn][Pp][Mm]_'
  mutant "single-quoted export argument not accepted" c_export_quoted_sq 'gsub(/["\047][Nn][Pp][Mm]_' 'gsub(/["][Nn][Pp][Mm]_'
  mutant "bare export name not accepted (same line)" c_export_bare_name '_[A-Za-z0-9_]*(=|$)/' '_[A-Za-z0-9_]*(=)/'
  mutant "bare export name not accepted (two lines)" c_export_bare_name_lines '_[A-Za-z0-9_]*(=|$)/' '_[A-Za-z0-9_]*(=)/'
  mutant "closing quote of a bare name not accepted" c_export_bare_quoted '(=[^"\047]*)?["\047]/, "npm_config_q=X"' '(=[^"\047]*)["\047]/, "npm_config_q=X"'
  mutant "export of any bare name carried" c_export_bare_other_neg "$XRE" 'qs[j] ~ /^[A-Za-z0-9_]*(=|$)/'
  mutant "export comment guard removed" c_export_comment_neg '        if (qs[j] ~ /^#/) break
' ''
  mutant "export comment guard removed (code span)" c_export_span_comment_neg '        if (qs[j] ~ /^#/) break
' ''
  # Since #386 a balanced quoted value is rewritten to X before this guard runs, so only an
  # unbalanced quote reaches it.
  mutant "export quote-parity guard removed" c_export_unbalanced_quote_neg '      if (match(q, /["\047]/)) q = substr(q, 1, RSTART - 1)
' ''
  mutant "export quoted runs not collapsed (#)" c_export_quoted_word_hash '      gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047|\\./, "Q", q)
' ''
  mutant "export quoted runs not collapsed (-n)" c_export_quoted_word_dash_n '      gsub(/"([^"\\]|\\.)*"|\047[^\047]*\047|\\./, "Q", q)
' ''
  mutant "-n un-exports under declare too" c_export_declare_nx 'w == "export" && qs[j] ~ /^-[A-Za-z]*n/' 'qs[j] ~ /^-[A-Za-z]*n/'
  mutant "quote kinds merged" c_export_sq_holds_dq '"([^"\\]|\\.)*"|\047[^\047]*\047|\\./, "Q", q)' '["\047][^"\047]*["\047]|\\./, "Q", q)'
  mutant "escape handling dropped" c_export_bare_escaped_quote '|\\./, "Q", q)' '/, "Q", q)'
  mutant "+x un-export dropped" c_declare_plus_x_neg '    if (unx) isx = 0
' ''
  mutant "+x read beyond the leading option words" c_declare_x_trailing_plus 'j <= nw && ws[j] ~ /^[-+]/; j++)' 'j <= nw; j++)'
  mutant "escaped quote inside a double-quoted value ends it" c_export_escaped_in_dq_neg '"([^"\\]|\\.)*"|' '"[^"]*"|'
  mutant "export -n guard removed" c_export_n_neg '        if (w == "export" && qs[j] ~ /^-[A-Za-z]*n/) unexp = 1
' ''
  # The restart-from-front mutants are quadratic, but mawk is fast enough to finish the 24000-word
  # cases near the watchdog (8.3 s locally, under 6 s on a CI runner, so the mutant survived there):
  # like the strip loop below, they run only where the awk under test is GNU Awk (94 s), which CI
  # covers with its AWK_UNDER_TEST=gawk run, and print a skip elsewhere.
  if [ "$(gawk_gate)" = run ]; then
    mutant "restart-from-start rewrite loop" c_subst_hostile_linear '  if (index(text, "=")) {' $'  while (match(text, /(^|[ \\t;&|(])[A-Za-z_][A-Za-z0-9_]*=\\$\\([^()]*\\)/)) {\n    rs = substr(text, RSTART, RLENGTH); sub(/=\\$\\([^()]*\\)$/, "=X", rs)\n    text = substr(text, 1, RSTART - 1) rs substr(text, RSTART + RLENGTH)\n  }\n  if (index(text, "=")) {'
    mutant "restart-from-start rewrite loop (quoted values)" c_quoted_space_hostile_linear '  if (index(text, "=")) {' $'  while (match(text, /[A-Za-z_][A-Za-z0-9_]*="[^"]*"/)) text = substr(text, 1, RSTART - 1) "X" substr(text, RSTART + RLENGTH)\n  if (index(text, "=")) {'
    mutant "restart-from-start rewrite loop (separate commands)" c_subst_hostile_arg_neg '  if (index(text, "=")) {' $'  while (match(text, /(^|[ \\t;&|(])[A-Za-z_][A-Za-z0-9_]*=\\$\\([^()]*\\)/)) {\n    rs = substr(text, RSTART, RLENGTH); sub(/=\\$\\([^()]*\\)$/, "=X", rs)\n    text = substr(text, 1, RSTART - 1) rs substr(text, RSTART + RLENGTH)\n  }\n  if (index(text, "=")) {'
  else
    for m in "restart-from-start rewrite loop" "restart-from-start rewrite loop (quoted values)" "restart-from-start rewrite loop (separate commands)"; do ok "mutant '$m' needs gawk: skipped"; done
  fi
  # The strip loop is quadratic on gawk only in a way the 6 s bound can see: gawk pre-fix takes
  # about 34 s at 192000 words, but mawk takes about 3.1 s, under the bound, so the restored loop
  # would survive there and the mutant is skipped (re-measured at the 6 s default, #346).
  case "$(bwk_gate)" in
  run)
    mutant "make locale pin dropped" c_make_bom 'verdict=$(TGT=$TGT LC_ALL=C awk "$prog" "$T/mk")' 'verdict=$(TGT=$TGT awk "$prog" "$T/mk")'
    mutant "doc reader locale pin dropped" c_doc_bom_fence_neg 'IMPORTS=$imp LC_ALL=C awk "$EXTRACT"' 'IMPORTS=$imp awk "$EXTRACT"' ;;
  refuse)
    bad "mutant 'make locale pin dropped' cannot run: AWK_UNDER_TEST=original-awk was requested but the awk under test is not BWK awk"
    bad "mutant 'doc reader locale pin dropped' cannot run: AWK_UNDER_TEST=original-awk was requested but the awk under test is not BWK awk" ;;
  *)
    ok "mutant 'make locale pin dropped' needs BWK awk in a UTF-8 locale: skipped"
    ok "mutant 'doc reader locale pin dropped' needs BWK awk in a UTF-8 locale: skipped" ;;
  esac
  case "$(gawk_gate)" in
  run)
    mutant "strip loop restored" c_strip_hostile_linear '    if (match(seg, /^([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)+/)) { seg = substr(seg, RLENGTH + 1); env = 1 }' '    while (seg ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) { sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", seg); env = 1 }'
    ;;
  refuse) bad "mutant 'strip loop restored' cannot run: AWK_UNDER_TEST=gawk was requested but the awk under test is not GNU Awk" ;;
  *) ok "mutant 'strip loop restored' needs gawk: skipped" ;;
  esac
  mutant "rewrite marker pass handles one match" c_subst_while_multi 'gsub(/[ \t;&|(][A-Za-z_][A-Za-z0-9_]*=/, "&\001", text)' 'sub(/[ \t;&|(][A-Za-z_][A-Za-z0-9_]*=/, "&\001", text)'
  mutant "anchor class loses the start of a line" c_anchor_start 'text = " " text; gsub(' 'text = "x" text; gsub('
  mutant "anchor class loses the space" c_anchor_space 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[\t;&|(][A-Za-z_]'
  mutant "anchor class loses the tab" c_anchor_tab 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[ ;&|(][A-Za-z_]'
  mutant "anchor class loses the semicolon" c_anchor_semi 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[ \t&|(][A-Za-z_]'
  mutant "anchor class loses the ampersand" c_anchor_amp 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[ \t;|(][A-Za-z_]'
  mutant "anchor class loses the pipe" c_anchor_pipe 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[ \t;&(][A-Za-z_]'
  mutant "anchor class loses the open parenthesis" c_anchor_paren 'gsub(/[ \t;&|(][A-Za-z_]' 'gsub(/[ \t;&|][A-Za-z_]'
  mutant "substitution anywhere refers the row (two segments)" c_subst_multi_neg '  if (index(text, "=")) {' $'  if (text ~ /\\$\\(/) { gsub(/;/, "; X=X ", text); text = "X=X " text }\n  if (index(text, "=")) {'
else
  bad "python3 is needed to build the mutants"
fi

# ---------------------------------------------------------------- portability
echo "== portability, because this ships into other people's repositories =="
# macOS ships bash 3.2, BSD readlink and a BWK awk. Comments are stripped first, so the prose may
# still NAME what it avoids.
code_() { grep -v '^[[:space:]]*#' "$SCRIPT"; }
for pat in ',,}' '^^}' 'readlink -f' 'mapfile' 'readarray' 'declare -A' 'local -n' 'awk -v' 'gensub' 'sed -i' 'grep -P'; do
  code_ | grep -qF -- "$pat" && bad "avoids $pat" || ok "avoids $pat"
done
grep -q 'check-contributor-docs-version: [0-9]' "$SCRIPT" && ok "carries its version marker" || bad "carries its version marker"

# ---------------------------------------------------------------- ESCAPE_WATCHDOG_SECS (#338)
# Last on purpose: a child suite given a VALID value is cut off after 2 s, long before it reaches
# this section, so the driver cannot recurse. A refused value exits at once, before any case, and
# its child also runs under `bounded 5`, so a validator that wrongly accepted the value would fail
# this check by name after 5 s instead of running the whole suite and recursing.
echo "== ESCAPE_WATCHDOG_SECS =="
for v in abc 0 -1 1.5 08 61; do
  out=$(ESCAPE_WATCHDOG_SECS=$v bounded 5 bash "$0" 2>"$W/wd.err"); wrc=$?
  if [ "$wrc" = 1 ] && grep -qF "ESCAPE_WATCHDOG_SECS must be an integer from 1 to 60, got '$v'" "$W/wd.err" \
     && ! grep -q 'ok:' <<<"$out"; then ok "ESCAPE_WATCHDOG_SECS=$v is refused before any case"
  else bad "ESCAPE_WATCHDOG_SECS=$v is refused before any case (rc $wrc)"; fi
done
for v in 5 60; do
  ESCAPE_WATCHDOG_SECS=$v bounded 2 bash "$0" >"$W/wd.out" 2>"$W/wd.err"
  if grep -qF '== required and size ==' "$W/wd.out" && ! grep -q 'must be an integer' "$W/wd.err"; then
    ok "ESCAPE_WATCHDOG_SECS=$v is accepted"
  else bad "ESCAPE_WATCHDOG_SECS=$v is accepted"; fi
done
if sed -n 1,25p "$0" | grep -q 'ESCAPE_WATCHDOG_SECS' && sed -n 1,25p "$0" | grep -q '1 to 60' \
   && sed -n 1,25p "$0" | grep -q 'default 10'; then ok "the header names ESCAPE_WATCHDOG_SECS, its range and its default"
else bad "the header names ESCAPE_WATCHDOG_SECS, its range and its default"; fi

echo ""
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
