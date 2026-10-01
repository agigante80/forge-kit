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
# Portability runs, by hand, because CI has neither: BASH_UNDER_TEST=/path/to/bash-3.2 runs the
# script under that bash, and AWK_UNDER_TEST=mawk (or nawk, or `busybox awk` via a wrapper) puts
# that awk first on PATH for every run.
#
# ESCAPE_WATCHDOG_SECS (positive integer from 1 to 60, seconds, default 10) is how long c_escape's
# watchdog waits before it releases one extra opener of the FIFO sentinel. It also sets the bound
# on every run of the script under test (that value plus 5 s), so a script that hangs on the
# sentinel fails its case instead of hanging the suite. Any other non-empty value is refused up
# front with exit 1.
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
  rc_is 0 && row referred command "workspace web" && row referred command "build" && nocmd fail && nocmd pass; }
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
  rc_is 0 && [ "$(count referred command)" = 2 ] && nocmd pass && nocmd fail; }

echo "== #299 yarn and workspaces =="
case_ c_y_bare "a bare yarn X defined in the root passes"
case_ c_y_bare_neg "a bare yarn X the root lacks is referred, never a fail"
case_ c_y_run "yarn run X defined in the root passes"
case_ c_y_run_neg "yarn run X the root lacks is referred, never a fail"
case_ c_y_install "yarn run install passes; a bare yarn install is the built-in and gets no row"
case_ c_y_classic "a Yarn Classic built-in is referred even when the root defines it"
case_ c_yws "yarn workspace <name> [run] X passes, naming the manifest"
case_ c_yws_neg "yarn workspace with a script the manifest lacks is referred, never a fail"
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
case_ c_edge_referred "npm -w run build and an empty --filter= are referred"

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
# mutant <label> <case> <old> <new> [<old2> <new2>]: the case must FAIL against the script with
# <old> replaced by <new> (and <old2> by <new2>, for a defect that needs two edits). A replacement that matches nothing is itself a failure, so a refactor cannot quietly turn
# a mutant into a no-op that "dies" for the wrong reason.
M="$W/mutant.sh"
mutant() {
  if ! python3 - "$SCRIPT" "$M" "${@:3}" <<'EOF'
import sys
src, dst, *pairs = sys.argv[1:]
s = open(src).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if old not in s: sys.exit(1)
    s = s.replace(old, new)
open(dst, "w").write(s)
EOF
  then bad "mutant '$1': its anchor no longer matches the script"; return; fi
  S="$M"; if "$2"; then bad "mutant '$1' survived $2"; else ok "mutant '$1' dies on $2"; fi; S="$SCRIPT"
}

echo "== mutants =="
if command -v python3 >/dev/null 2>&1; then
  mutant "presence instead of tracked" c_untracked 'if tracked AGENTS.md; then' 'if [ -e AGENTS.md ]; then'
  mutant "check-ignore without --no-index" c_ignored 'check-ignore -q --no-index' 'check-ignore -q'
  mutant "links resolved from the root" c_link_parent 'np=$(normpath "$dir" "$a")' 'np=$(normpath "" "$a")'
  mutant "commands scanned in prose" c_prose '  rest = spans(line)' '  code(line, 0); rest = spans(line)'
  mutant "referred collapsed into fail" c_referred 'row referred command' 'row fail command'
  mutant "directory link by exact match only" c_link_dir 'tracked "$1" || tracked_dir "$1"' 'tracked "$1"'
  mutant "cd scope widened to the whole file" c_cd_other_fence 'infence = 1; fcd = 0; fenv = 0; pcd = 0; penv = 0; next' 'infence = 1; fenv = 0; pcd = 0; penv = 0; next'
  mutant "paragraph scope narrowed to the span" c_para_span '    code(substr(rest, 1, j - 1), 0)' '    pcd = 0; code(substr(rest, 1, j - 1), 0)'
  mutant "[ -f package.json ] in place of tracked" c_pkg_untracked 'tracked package.json ||' '[ -f package.json ] ||'
  mutant "a cd ignored when the root defines the script" c_cd_root_defined '[ "$cd" != 0 ] && { row referred command "$loc" "$pm run' '[ "$cd" != 0 ] && ! { tracked package.json && resolve_script "$name"; } && { row referred command "$loc" "$pm run'
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
  mutant "judge_pm trim removed" c_pm_trim_site '  trim_punct "$name"; name=$TP
  local re=' '  local re='
  mutant "judge_ws trim removed" c_ws_trim_site '  trim_punct "$name"; name=$TP
  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: ' '  [[ $name =~ $sre ]] || { row referred command "$loc" "$lab: '
  mutant "judge_yarn_root trim removed" c_yroot_trim_site '  trim_punct "$name"; name=$TP
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
    run) shift ;;' '  if [ $# -eq 0 ]; then return; fi
  trim_punct "$1"
  case "$TP" in
    run) shift ;;'
  mutant "workspace built-in message prints the raw word" c_yws_builtin '"$lab: $b1 may be a yarn built-in"' '"$lab: $1 may be a yarn built-in"'
  mutant "a second inline copy of the trim loop" c_trim_once 'first_file() {' 'X=; while :; do case "$X" in *[.,\;:!?]) X=${X%?} ;; *) break ;; esac; done
first_file() {'
  # #296. Each pair names the case written to kill it.
  mutant "export carry removed" c_export_carry '{ if (infence) fenv = 1; else penv = 1 }' '{ }'
  mutant "export carry widened to every variable" c_export_other_neg 'ws[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*=/' 'ws[j] ~ /=/'
  mutant "export carry widened (NODE_ENV)" c_export_node_env_neg 'ws[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*=/' 'ws[j] ~ /=/'
  mutant "export carry cleared by an intervening line" c_export_gap 'carry = infence ? fenv : penv' 'carry = infence ? fenv : penv; if (w != "npm") { fenv = 0; penv = 0 }'
  mutant "export carry not reset at fence open" c_export_next_fence 'fcd = 0; fenv = 0; pcd = 0; penv = 0; next' 'fcd = 0; pcd = 0; penv = 0; next'
  mutant "export name match unanchored" c_export_name_neg 'ws[j] ~ /^[Nn][Pp][Mm]_' 'ws[j] ~ /[Nn][Pp][Mm]_'
  mutant "export match lowercase only" c_export_mixed 'ws[j] ~ /^[Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_[A-Za-z0-9_]*=/' 'ws[j] ~ /^npm_config_[A-Za-z0-9_]*=/'
  mutant "export match workspace key only" c_export_loglevel '[Ff][Ii][Gg]_[A-Za-z0-9_]*=/' '[Ff][Ii][Gg]_workspace=/'
  mutant "empty-valued export not carried" c_export_empty '[Ff][Ii][Gg]_[A-Za-z0-9_]*=/' '[Ff][Ii][Gg]_[A-Za-z0-9_]*=[^ \t]/'
  mutant "paragraph carry removed" c_export_span 'fenv = 1; else penv = 1' 'fenv = 1; else penv = 0'
  mutant "paragraph carry not reset at blank line" c_export_span_blank_neg 'trim(line) == "") { pcd = 0; penv = 0; next }' 'trim(line) == "") { pcd = 0; next }'
  mutant "prose carry leaks into a following fence" c_export_span_fence 'fcd = 0; fenv = 0; pcd' 'fcd = 0; fenv = penv; pcd'
  mutant "export carry applied only to later lines" c_export_andand '  while (match(text, /(^|' $'  cin_ = infence ? fenv : penv\n  while (match(text, /(^|' 'carry = infence ? fenv : penv' 'carry = cin_'
  mutant "carry applied before the export segment" c_export_after_neg 'carry = infence ? fenv : penv' 'carry = (infence ? fenv : penv) || (text ~ /export[ \t]+[Nn][Pp][Mm]_/)'
  mutant "carry overrides a cd" c_export_cd '(infence ? fcd : pcd) + 2 * (env || carry)' '((env || carry) ? 2 : (infence ? fcd : pcd))'
  mutant "carry reported as a directory change" c_export_no_cd_reason '2 * (env || carry)' '2 * env + 3 * carry'
  mutant "declare -x dropped" c_export_declare '((w == "declare" || w == "typeset")' '((w == "typeset")'
  mutant "typeset -x dropped" c_export_typeset '((w == "declare" || w == "typeset")' '((w == "declare")'
  mutant "declare without -x carried" c_declare_plain_neg ' && ws[2] == "-x"))' '))'
  mutant "assignment-value rewrite removed" c_subst_value '  while (match(text, /(^|' '  while (0 && match(text, /(^|'
  mutant "substitution anywhere refers the row (other)" c_subst_other_neg '  while (match(text, /(^|' $'  if (text ~ /\\$\\(/) { gsub(/;/, "; X=X ", text); text = "X=X " text }\n  while (match(text, /(^|'
  mutant "substitution anywhere refers the row (argument)" c_subst_after_neg '  while (match(text, /(^|' $'  if (text ~ /\\$\\(/) { gsub(/;/, "; X=X ", text); text = "X=X " text }\n  while (match(text, /(^|'
  mutant "substitution rewrite not word-anchored" c_subst_flag_value '/(^|[ \t;&|(])[A-Za-z_][A-Za-z0-9_]*=\$\(' '/[A-Za-z_][A-Za-z0-9_]*=\$\('
  mutant "a substitution body executed" c_pwned 'IDX=$T/index ROWS=$T/rows' 'IDX=$T/index ROWS=$T/rows; touch pwned'
  mutant "make invoked to find a target" c_make_include 'verdict=$(TGT=$TGT awk "$prog" "$f")' 'make -n -f "$f" "$TGT" >/dev/null 2>&1; verdict=$(TGT=$TGT awk "$prog" "$f")'
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
  mutant "substring match on workspace" c_npmrc_key_neg 'if (key == "workspace") {' 'if (index(key, "workspace")) {'
  mutant "workspaces key ignored" c_npmrc_workspaces 'if (key == "workspaces" && val != "false")' 'if (0)'
  mutant "only a would-be fail becomes referred" c_npmrc_ws_defined '[ -n "$NPMRC_KEY" ] && { row referred' '[ -n "$NPMRC_KEY" ] && ! { tracked package.json && resolve_script "$name"; } && { row referred'
  mutant "a non-root .npmrc is read" c_npmrc_subdir_neg 'tracked .npmrc || return' 'tracked client/.npmrc || return' 'git show :.npmrc 2>/dev/null |' 'git show :client/.npmrc 2>/dev/null |'
  mutant "the whole .npmrc is echoed" c_npmrc_token '"npm run $name: a tracked .npmrc sets $NPMRC_KEY"; return; }' '"npm run $name: a tracked .npmrc sets $NPMRC_KEY"; git show :.npmrc; return; }'
  mutant "the matched .npmrc line is echoed" c_npmrc_token 'if (key == "workspace") { print "workspace"; exit }' 'if (key == "workspace") { print "workspace " $0; exit }'
  mutant "npm-only guard dropped" c_npmrc_pnpm_unchanged '  if [ "$pm" = npm ]; then
    npmrc_scan' '  if true; then
    npmrc_scan'
  mutant "refer on workspaces=false" c_npmrc_ws_false 'key == "workspaces" && val != "false"' 'key == "workspaces"'
  mutant "CR strip dropped" c_npmrc_ws_false_crlf "| tr '\\r' '\\n' |" '|'
  mutant "section stop dropped" c_npmrc_section_neg '    /^\[[^]]*\][ \t]*$/ { exit }
' ''
  mutant "byte-order mark strip dropped" c_npmrc_bom '    NR == 1 { sub(/^\357\273\277/, "") }
' ''
  mutant "section test after the indentation trim" c_npmrc_indented_section '    /^\[[^]]*\][ \t]*$/ { exit }
    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }' '    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    /^\[[^]]*\][ \t]*$/ { exit }'
  mutant "case-insensitive key" c_npmrc_case_neg 'if (key == "workspace") {' 'if (tolower(key) == "workspace") {'
  mutant "[] strip dropped" c_npmrc_bracket 'sub(/\[\]$/, "", key); ' ''
  mutant "detail always workspace" c_npmrc_workspaces 'sets $NPMRC_KEY"' 'sets workspace"'
  mutant "final line without a newline dropped" c_npmrc_no_final_newline 'git show :.npmrc 2>/dev/null |' 'git show :.npmrc 2>/dev/null | while IFS= read -r l; do printf "%s\n" "$l"; done |'
  mutant "exact workspace= string match" c_npmrc_spaced 'sub(/[ \t]+$/, "", key); sub(/\[\]$/, "", key); sub(/[ \t]+$/, "", key)' 'sub(/\[\]$/, "", key)'
  mutant "refers when no .npmrc exists" c_npmrc_none_neg '    [ -n "$NPMRC_KEY" ] && { row referred command "$loc" "npm run' '    [ -z "$NPMRC_KEY" ] && { row referred command "$loc" "npm run'
  mutant "the .npmrc rule leaks into the explicit workspace forms" c_npmrc_unchanged_forms '  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }' '  npmrc_scan; [ -n "$NPMRC_KEY" ] && { row referred command "$loc" "$lab: a tracked .npmrc sets $NPMRC_KEY"; return; }
  [ "$cd" != 0 ] && { row referred command "$loc" "$lab: $(why_cd "$cd")"; return; }'
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
