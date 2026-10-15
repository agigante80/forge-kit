#!/usr/bin/env bash
# Contract test for scripts/forge-adapt-http-steps.sh (#528): with an http forge URL, name the CI steps
# that run a script sourcing forge-lib and so will hit forge-lib's http refusal (v36, #442).
#
# Every fixture is a throwaway project directory. HTTP_STEPS overrides the script under test, so a
# mutant can be run on a cp copy. The script prints only: the tree is hashed before and after.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${HTTP_STEPS:-$HERE/forge-adapt-http-steps.sh}"
[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (missing '$2' in: $3)" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1 (found '$2' in: $3)" ;; *) ok "$1" ;; esac; }

T=$(mktemp -d); trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
unset FORGE_API_URL FORGE_HOST FORGE_ALLOW_HTTP FORGE_TOKEN

HTTPURL='http://192.168.1.10:3000/api/v1'
# mk <name> [conf line]: a project with scripts/check-phases.sh sourcing forge-lib; echoes its path.
mk() {
  local d="$T/$1"; mkdir -p "$d/scripts"
  printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/forge-lib.sh"\n' > "$d/scripts/check-phases.sh"
  printf '#!/usr/bin/env bash\necho hello\n' > "$d/scripts/plain.sh"
  [ -z "${2-}" ] || printf '%s\n' "$2" > "$d/.forge.conf"
  echo "$d"
}
# wf <project> <dir> <file> <content>
wf() { mkdir -p "$1/$2"; printf '%b' "$4" > "$1/$2/$3"; }
GH=.github/workflows
# A workflow with one step: wf1 <project> <step lines>
wf1() { wf "$1" "$GH" ci.yml "name: ci\non: push\njobs:\n  build:\n    runs-on: x\n    steps:\n$2"; }
STEP='      - name: Phases\n        run: bash scripts/check-phases.sh\n'

out=""; err=""; rc=""
run() { local p="$1"; shift; out=$(env "$@" bash "$SCRIPT" --project "$p" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
steps_of() { printf '%s\n' "$out" | grep -c '^step'; }
tree_hash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum); }

echo "== detection =="
P=$(mk d1 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"
run "$P"
expect "http conf: exit 0" 0 "$rc"
expect "http conf: one step row" 1 "$(steps_of)"
has "the row names the workflow file" "$GH/ci.yml" "$out"
has "the row names the step" "Phases" "$out"
has "the row carries the offer" 'FORGE_ALLOW_HTTP: "1"' "$out"
has "the url is shown" "forge-url	$HTTPURL" "$out"
has "the unencrypted-token warning" "unencrypted" "$out"
has "the local-session note names the untracked file" ".claude/settings.local.json" "$out"
expect "the summary row is last" "summary	steps=1	workflows=1	not-scanned=0" "$(printf '%s\n' "$out" | tail -1)"
expect "nothing on stderr" "" "$err"

P=$(mk d2 "FORGE_API_URL=https://forge.example.org/api/v1"); wf1 "$P" "$STEP"
run "$P"; expect "https: empty stdout" "" "$out"; expect "https: exit 0" 0 "$rc"
P=$(mk d3); wf1 "$P" "$STEP"
run "$P"; expect "no url anywhere: empty stdout" "" "$out"; expect "no url: exit 0" 0 "$rc"
P=$(mk d4 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"
run "$P" FORGE_API_URL=https://forge.example.org/api/v1
expect "an exported https url overrides an http conf" "" "$out"
P=$(mk d5 "FORGE_API_URL=https://forge.example.org/api/v1"); wf1 "$P" "$STEP"
run "$P" FORGE_API_URL=http://10.9.9.9/api/v1
has "an exported http url overrides an https conf" "10.9.9.9" "$out"
expect "...and the step is named" 1 "$(steps_of)"

echo "== .forge.conf parsed as forge-lib parses it =="
P=$(mk q1 'FORGE_API_URL = "http://10.1.1.1/api/v1"  # lan'); wf1 "$P" "$STEP"
run "$P"; has "quoted value, spaces around =, inline comment" "forge-url	http://10.1.1.1/api/v1" "$out"
P=$(mk q2); printf 'FORGE_API_URL=http://10.2.2.2/api/v1\r\n' > "$P/.forge.conf"; wf1 "$P" "$STEP"
run "$P"; has "CRLF line endings" "forge-url	http://10.2.2.2/api/v1" "$out"
P=$(mk q3); printf 'FORGE_API_URL=https://first.example/api\nFORGE_API_URL=http://10.3.3.3/api\n' > "$P/.forge.conf"; wf1 "$P" "$STEP"
run "$P"; expect "the FIRST non-empty line wins (forge-lib keeps the first), so https here is silent" "" "$out"
P=$(mk q4); printf 'FORGE_API_URL=\nFORGE_API_URL=http://10.4.4.4/api\n' > "$P/.forge.conf"; wf1 "$P" "$STEP"
run "$P"; has "an empty line does not claim the key; the next one does" "10.4.4.4" "$out"
P=$(mk q5); printf '# FORGE_API_URL=http://10.5.5.5/api\nFORGE_REPO=o/r\n' > "$P/.forge.conf"; wf1 "$P" "$STEP"
run "$P"; expect "a commented-out url line is ignored" "" "$out"
P=$(mk q6 "FORGE_API_URL=$HTTPURL"); printf 'FORGE_HOST=github\n' >> "$P/.forge.conf"; wf1 "$P" "$STEP"
run "$P"; expect "FORGE_HOST=github in the conf: forge-lib never reaches the check, silent" "" "$out"
run "$P" FORGE_HOST=forgejo; has "an exported FORGE_HOST=forgejo wins over the conf" "forge-url" "$out"
P=$(mk q7 "FORGE_API_URL=HTTP://10.7.7.7/api"); wf1 "$P" "$STEP"
run "$P"; expect "an upper-case scheme does not match forge-lib's http://* case arm: silent" "" "$out"
P=$(mk q8 "FORGE_API_URL=http://10.8.8.8/api"); wf1 "$P" "$STEP"
run "$P" FORGE_TOKEN=tok123 FORGE_TOKEN_ENV=tok999
lacks "the token is never printed" "tok123" "$out$err"

echo "== which steps =="
P=$(mk s1 "FORGE_API_URL=$HTTPURL")
wf1 "$P" "$STEP"'      - run: npm test\n      - uses: actions/checkout@v4\n      - run: bash scripts/plain.sh\n'
run "$P"
expect "only the forge-lib step is named (npm test, uses:, a script without forge-lib are not)" 1 "$(steps_of)"
P=$(mk s2 "FORGE_API_URL=$HTTPURL")
wf1 "$P" '      - run: |\n          set -e\n          forge_issue_list\n      - run: forge_repo\n      - run: source scripts/forge-lib.sh\n'
run "$P"; expect "forge_* in a block, forge_* inline, a direct forge-lib source: three steps" 3 "$(steps_of)"
has "an unnamed step is labelled by its first run line" "set -e" "$out"
P=$(mk s3 "FORGE_API_URL=$HTTPURL")
wf1 "$P" '      - run: bash scripts/check-phases.sh.bak\n      - run: bash scripts/mycheck-phases.sh\n      - run: echo xcheck-phases.sh\n'
run "$P"; expect "a script name must stand alone (no .bak suffix, no longer-name prefix)" 0 "$(steps_of)"
P=$(mk s4 "FORGE_API_URL=$HTTPURL")
wf1 "$P" '      - run: echo scripts/gate-env.sh\n'
printf 'source gate-env.sh\n' > "$P/scripts/gate-env.sh"; printf 'echo hi\n' > "$P/scripts/viaenv.sh"
printf 'source "$(dirname "$0")/phase-env.sh"\n' > "$P/scripts/uses-phase-env.sh"
wf1 "$P" '      - run: bash scripts/uses-phase-env.sh\n      - run: bash scripts/viaenv.sh\n'
run "$P"; expect "a script that mentions phase-env counts; one that mentions nothing does not" 1 "$(steps_of)"
has "the phase-env script is the one named" "uses-phase-env" "$out"

echo "== already covered: FORGE_ALLOW_HTTP exactly 1, at step, job or workflow =="
P=$(mk c1 "FORGE_API_URL=$HTTPURL")
wf1 "$P" '      - name: ok\n        env:\n          FORGE_ALLOW_HTTP: "1"\n        run: bash scripts/check-phases.sh\n'
run "$P"; expect "step env 1: not offered" 0 "$(steps_of)"; expect "step env 1: exit 0" 0 "$rc"
has "...and the warning still prints" "unencrypted" "$out"
P=$(mk c2 "FORGE_API_URL=$HTTPURL")
wf "$P" "$GH" ci.yml 'jobs:\n  build:\n    env:\n      FORGE_ALLOW_HTTP: "1"\n    steps:\n      - run: bash scripts/check-phases.sh\n  other:\n    steps:\n      - run: bash scripts/check-phases.sh\n'
run "$P"; expect "job env 1 covers its own job only: the other job's step is offered" 1 "$(steps_of)"
has "...and it is the other job" "job other" "$out"
P=$(mk c3 "FORGE_API_URL=$HTTPURL")
wf "$P" "$GH" ci.yml 'env:\n  FORGE_ALLOW_HTTP: 1\njobs:\n  a:\n    steps:\n      - run: bash scripts/check-phases.sh\n  b:\n    steps:\n      - run: forge_repo\n'
run "$P"; expect "workflow env 1 (unquoted) covers every job" 0 "$(steps_of)"
P=$(mk c4 "FORGE_API_URL=$HTTPURL")
wf "$P" "$GH" ci.yml 'jobs:\n  a:\n    steps:\n      - run: bash scripts/check-phases.sh\n    env:\n      FORGE_ALLOW_HTTP: "1"\n'
run "$P"; expect "job env written AFTER the steps still covers them" 0 "$(steps_of)"
for v in '"0"' 'true' '"yes"' '${{ vars.X }}' '"11"' '""'; do
  P=$(mk "c5$RANDOM" "FORGE_API_URL=$HTTPURL")
  wf1 "$P" "      - name: s\n        env:\n          FORGE_ALLOW_HTTP: $v\n        run: bash scripts/check-phases.sh\n"
  run "$P"; expect "FORGE_ALLOW_HTTP: $v is not 1, so the step is still offered" 1 "$(steps_of)"
done
P=$(mk c6 "FORGE_API_URL=$HTTPURL")
wf1 "$P" "      - env: { FORGE_ALLOW_HTTP: \"1\" }\n        run: bash scripts/check-phases.sh\n      - env:\n          FORGE_ALLOW_HTTP: '1'\n        run: forge_repo\n"
run "$P"; expect "flow-style env and a single-quoted 1 both cover" 0 "$(steps_of)"
P=$(mk c7 "FORGE_API_URL=$HTTPURL")
wf1 "$P" "      - name: ok\n        env:\n          OTHER: x\n          FORGE_ALLOW_HTTP: \"1\"\n        run: bash scripts/check-phases.sh\n      - name: next\n        run: bash scripts/check-phases.sh\n"
run "$P"; expect "a covered step does not leak its env onto the next step" 1 "$(steps_of)"
has "...the next step is the one named" "next" "$out"

echo "== workflow directories =="
P=$(mk w1 "FORGE_API_URL=$HTTPURL")
for d in .forgejo/workflows .gitea/workflows .github/workflows; do
  wf "$P" "$d" ci.yml 'jobs:\n  b:\n    steps:\n      - run: bash scripts/check-phases.sh\n'
done
wf "$P" .gitea/workflows other.yaml 'jobs:\n  b:\n    steps:\n      - run: forge_repo\n'
run "$P"; expect "all three directories and both extensions are scanned" 4 "$(steps_of)"
expect "the directory Forgejo runs is marked runs" 1 "$(printf '%s\n' "$out" | grep -c 'forgejo=runs')"
expect "the others are marked ignored" 3 "$(printf '%s\n' "$out" | grep -c 'forgejo=ignored')"
has ".forgejo is the one Forgejo runs" ".forgejo/workflows/ci.yml	job b / bash scripts/check-phases.sh	FORGE_ALLOW_HTTP: \"1\"	forgejo=runs" "$out"
has ".github is ignored when .forgejo exists" ".github/workflows/ci.yml	job b / bash scripts/check-phases.sh	FORGE_ALLOW_HTTP: \"1\"	forgejo=ignored" "$out"
P=$(mk w2 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"
run "$P"; has "with only .github, it is the one Forgejo runs" "forgejo=runs" "$out"
P=$(mk w3 "FORGE_API_URL=$HTTPURL"); mkdir -p "$P/$GH"
run "$P"; expect "an empty workflow dir: no step rows" 0 "$(steps_of)"; expect "...exit 0" 0 "$rc"
has "...a summary with zero steps" "summary	steps=0	workflows=0	not-scanned=0" "$out"
P=$(mk w4 "FORGE_API_URL=$HTTPURL"); wf "$P" "$GH" empty.yml ''; printf '\001\002\377\n' > "$P/$GH/bin.yml"
run "$P"; expect "an empty and a binary workflow file do not crash" 0 "$rc"
P=$(mk w5 "FORGE_API_URL=$HTTPURL"); wf "$P" "$GH" ci.yml 'jobs:\r\n  b:\r\n    steps:\r\n      - run: bash scripts/check-phases.sh\r\n'
run "$P"; expect "a CRLF workflow is read" 1 "$(steps_of)"
P=$(mk w6 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "      - run: |\n          echo start\n\n          bash scripts/check-phases.sh\n      - run: >-\n          echo folded\n"
run "$P"; expect "a multi-line run block with a blank line is read; the next step is not swallowed" 1 "$(steps_of)"
P=$(mk w7 "FORGE_API_URL=$HTTPURL")
wf "$P" "$GH" ci.yml 'jobs:\n  b:\n    steps:\n    - name: flush\n      run: bash scripts/check-phases.sh\n    - name: second\n      run: forge_repo\n'
run "$P"; expect "a sequence written at the same indent as steps: is read" 2 "$(steps_of)"

echo "== http with no qualifying step =="
P=$(mk n1 "FORGE_API_URL=$HTTPURL"); wf1 "$P" '      - run: npm test\n'
run "$P"; expect "exit 0" 0 "$rc"; expect "no step row" 0 "$(steps_of)"
has "warning present" "unencrypted" "$out"; has "local-session present" "settings.local.json" "$out"
expect "summary shows zero steps" "summary	steps=0	workflows=1	not-scanned=0" "$(printf '%s\n' "$out" | tail -1)"

echo "== credentials =="
P=$(mk u1 "FORGE_API_URL=http://user:secret@10.0.0.5/api/v1"); wf1 "$P" "$STEP"
run "$P"
has "the host is printed" "10.0.0.5" "$out"
lacks "no password in stdout" "secret" "$out$err"; lacks "no userinfo in stdout" "user:" "$out$err"
P=$(mk u2 "FORGE_API_URL=http://us:p@ss@10.0.0.6/api/v1"); wf1 "$P" "$STEP"
run "$P"; lacks "a password containing @ is cut at the LAST @" "ss@" "$out"; has "...host kept" "10.0.0.6" "$out"
P=$(mk u3 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"
run "$P" FORGE_API_URL=http://u2:pw2@10.9.9.9/x
lacks "an exported url is stripped too" "pw2" "$out$err"

echo "== read-only and settings =="
P=$(mk r1 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"; mkdir -p "$P/.claude"; echo '{"permissions":{}}' > "$P/.claude/settings.json"
before=$(tree_hash "$P"); sj=$(sha256sum < "$P/.claude/settings.json")
run "$P"
expect "the tree is byte-identical afterwards (no file created, none changed)" "$before" "$(tree_hash "$P")"
expect ".claude/settings.json is unchanged" "$sj" "$(sha256sum < "$P/.claude/settings.json")"
expect "settings.local.json was not created" "no" "$([ -e "$P/.claude/settings.local.json" ] && echo yes || echo no)"
bare=$(printf '%s\n' "$out" | grep -E 'settings\.json' | grep -vE 'settings\.local\.json' || true)
expect "no output line names the committed settings.json" "" "$bare"

echo "== unreadable input is incomplete, never clean =="
if [ "$(id -u)" = 0 ]; then
  echo "  skip: running as root, chmod 000 does not block it"
else
  P=$(mk x1 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"; chmod 000 "$P/$GH"
  run "$P"; chmod 755 "$P/$GH"
  expect "unreadable workflow dir: exit 3" 3 "$rc"
  has "a not-scanned row names the dir" "not-scanned	$GH" "$out"
  has "the summary counts it" "not-scanned=1" "$out"
  P=$(mk x2 "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"; wf "$P" "$GH" locked.yml 'x: 1\n'; chmod 000 "$P/$GH/locked.yml"
  run "$P"; chmod 644 "$P/$GH/locked.yml"
  expect "unreadable workflow file: exit 3" 3 "$rc"
  has "...named" "not-scanned	$GH/locked.yml" "$out"
  expect "...the readable file in the same dir is still scanned" 1 "$(steps_of)"
fi

echo "== hostile text is data =="
P=$(mk h1 'FORGE_API_URL=http://10.0.0.7/$(touch PWNED1)`touch PWNED2`;touch PWNED3')
wf "$P" "$GH" 'a;touch PWNED4.yml' 'jobs:\n  "j$(touch PWNED5)":\n    steps:\n      - name: "$(touch PWNED6) `x` ; y"\n        run: bash scripts/check-phases.sh; $(touch PWNED7)\n'
run "$P"
expect "exit 0" 0 "$rc"; expect "the step is named" 1 "$(steps_of)"
expect "nothing was executed" "" "$(find "$T" -name 'PWNED*' | head -1)"

echo "== usage =="
run "$T/does-not-exist"; expect "a missing project dir: exit 2" 2 "$rc"; has "...with a one-line message" "forge-adapt-http-steps:" "$err"
out=$(bash "$SCRIPT" --bogus 2>"$T/err"); rc=$?; expect "an unknown flag: exit 2" 2 "$rc"; has "...usage on stderr" "usage:" "$(cat "$T/err")"
out=$(bash "$SCRIPT" --project 2>"$T/err"); rc=$?; expect "--project with no value: exit 2" 2 "$rc"
out=$(bash "$SCRIPT" --project "" 2>"$T/err"); rc=$?; expect "--project with an empty value: exit 2" 2 "$rc"
P=$(mk dflt "FORGE_API_URL=$HTTPURL"); wf1 "$P" "$STEP"
out=$(cd "$P" && bash "$SCRIPT" 2>"$T/err"); rc=$?
expect "no --project: the current directory is used" 1 "$(steps_of)"

echo
echo "forge-adapt-http-steps tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
