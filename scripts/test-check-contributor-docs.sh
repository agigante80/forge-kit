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
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/plugins/forge-kit-governance/skills/contributor-docs/assets/check-contributor-docs.sh"
FIX="$HERE/fixtures/check-contributor-docs"
SHELL_UNDER_TEST="${BASH_UNDER_TEST:-bash}"

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

W=$(mktemp -d); trap 'chmod -R u+rw "$W" 2>/dev/null; rm -rf "$W"' EXIT
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

OUT=""; ERR=""; RC=0
run() {
  local p="$PATH"; [ -n "$AWKDIR" ] && p="$AWKDIR:$PATH"
  OUT=$(cd "$R" && PATH="$p" "$SHELL_UNDER_TEST" "$S" "$@" 2>"$W/err"); RC=$?
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
# A read is proved by access time: with atime set BEFORE mtime, even relatime records the next
# read. A noatime mount records nothing, which the calibration below detects and says.
atime() { stat -c %X "$1" 2>/dev/null || stat -f %a "$1"; }
ATIME_OK=0
printf 'c\n' > "$W/calib"; touch -a -t 200001010000 "$W/calib"; a0=$(atime "$W/calib")
cat "$W/calib" >/dev/null; [ "$(atime "$W/calib")" != "$a0" ] && ATIME_OK=1
[ "$ATIME_OK" = 1 ] || echo "  note: this filesystem records no reads; the sentinel's access time proves nothing here"
c_escape() { new; agents 'See [s](../sentinel) and [h](../../etc/hosts) and [g](docs/guide.md).\n'; tput_ docs/guide.md 'x\n'
  printf 'secret\n' > "$W/sentinel"; touch -a -t 200001010000 "$W/sentinel"; local a0; a0=$(atime "$W/sentinel"); run
  rc_is 1 && row fail link "../sentinel: escapes the repository" && row fail link "../../etc/hosts: escapes" \
    && row pass link "docs/guide.md" && none secret && { [ "$ATIME_OK" = 0 ] || [ "$(atime "$W/sentinel")" = "$a0" ]; }; }
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
c_nojq_yarn() { new; pkg '"x":"x"'; agents '`yarn run lint`\n\n`npm run --prefix p lint`\n'; run_nojq
  rc_is 0 && row referred command "yarn run lint"; }
c_nojq_npm() { new; pkg '"x":"x"'; agents '`yarn run a`\n\n`npm run lint`\n'; run_nojq
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
# mutant <label> <case> <old> <new>: the case must FAIL against the script with <old> replaced by
# <new>. A replacement that matches nothing is itself a failure, so a refactor cannot quietly turn
# a mutant into a no-op that "dies" for the wrong reason.
M="$W/mutant.sh"
mutant() {
  if ! python3 - "$SCRIPT" "$M" "$3" "$4" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:]
s = open(src).read()
if old not in s: sys.exit(1)
open(dst, "w").write(s.replace(old, new))
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
  mutant "cd scope widened to the whole file" c_cd_other_fence 'infence = 1; fcd = 0; pcd = 0; next' 'infence = 1; pcd = 0; next'
  mutant "paragraph scope narrowed to the span" c_para_span '    code(substr(rest, 1, j - 1), 0)' '    pcd = 0; code(substr(rest, 1, j - 1), 0)'
  mutant "[ -f package.json ] in place of tracked" c_pkg_untracked 'tracked package.json ||' '[ -f package.json ] ||'
  mutant "a cd ignored when the root defines the script" c_cd_root_defined '[ "$cd" != 0 ] && { row referred command "$loc" "$pm run' '[ "$cd" != 0 ] && ! { tracked package.json && resolve_script "$name"; } && { row referred command "$loc" "$pm run'
  mutant "a PR-template link that passes" c_tmpl 'if [ "$tmpl" = 1 ]; then' 'if false; then'
  mutant "yarn run in the fail set" c_yarn_run 'row referred command "$loc" "yarn run $2' 'row fail command "$loc" "yarn run $2'
  mutant "flags after the name ignored" c_flag_after '-*) flag=$w; break ;;' '-*) ;;'
  mutant "jq checked eagerly" c_nojq_yarn $'set -f\n' $'set -f\ncommand -v jq >/dev/null 2>&1 || die "jq missing"\n'
  mutant ".txt templates dropped" c_tmpl_txt '(\.md|\.txt)?$' '(\.md)?$'
  mutant "scripts read from the working tree" c_index_blob 'git show :package.json >' 'cat package.json >'
  mutant "CR kept on blank lines" c_para_crlf '{ sub(/\r$/, "") }
{
  line' '{
  line'
  mutant "a fence closed by a blank line" c_fence_unclosed '    code(line, 1); next' '    if (trim(line) == "") { infence = 0; next }
    code(line, 1); next'
  mutant "an escaping link read from disk" c_escape 'row fail link "$loc" "$a: escapes the repository"' 'row fail link "$loc" "$a: escapes the repository"; cat "${dir:-.}/$a" >/dev/null 2>\&1'
  mutant "an assignment prefix skipped silently" c_env_prefix '+ 2 * env' '+ 0 * env'
  mutant "make invoked to find a target" c_make_include 'verdict=$(TGT=$TGT awk "$prog" "$f")' 'make -n -f "$f" "$TGT" >/dev/null 2>&1; verdict=$(TGT=$TGT awk "$prog" "$f")'
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

echo ""
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
