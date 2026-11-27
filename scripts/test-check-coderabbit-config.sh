#!/usr/bin/env bash
# Contract test for coderabbit-config/assets/check-coderabbit-config.sh and the template beside it (#598).
#
# The checker is the only thing standing between a tidied .coderabbit.yaml and a reviewer that can
# push or approve, so its two failure directions are not equal: a pin it misses is the defect, and
# an exit 0 on a file it could not read is the worst form of it. The cases pin every key at its
# wrong value, every REQUIRED key at missing, and the three ways of not being able to parse.
# Configs are written as JSON, which is YAML, so a mutation is one jq expression.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-review/skills/coderabbit-config/assets/check-coderabbit-config.sh"
TPL="$ROOT/plugins/forge-kit-review/skills/coderabbit-config/assets/coderabbit.yaml"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if grep -qF -- "$1" <<< "$2"; then bad "$3 ('$1' in output)"; else ok "$3"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }
[ -f "$TPL" ] || { echo "missing template: $TPL"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "python3 with PyYAML is required: the checker reads YAML with it"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
C="$T/c.yaml"

# The passing config every mutation starts from: the template's pins, as JSON.
GOOD='{
  "inheritance": false,
  "reviews": {
    "fail_commit_status": false,
    "auto_approvals": {"enabled": false, "allow_author_approval": false},
    "auto_apply_labels": false, "auto_assign_reviewers": false, "path_instructions": [],
    "auto_review": {"drafts": false, "base_branches": ["develop"], "ignore_usernames": ["dependabot[bot]"]},
    "finishing_touches": {
      "unit_tests": {"enabled": false}, "simplify": {"enabled": false},
      "autofix": {"enabled": false}, "fix_ci": {"enabled": false}, "resolve_merge_conflict": {"enabled": false},
      "custom": []},
    "post_merge_actions": []},
  "issue_enrichment": {"auto_enrich": {"enabled": false},
    "planning": {"enabled": false, "auto_planning": {"enabled": false}},
    "labeling": {"auto_apply_labels": false}},
  "chat": {"auto_reply": false},
  "knowledge_base": {"code_guidelines": {"enabled": true}}
}'

# run [args...]: the checker on $C. Sets rc, out (stdout) and err (stderr).
run() { out=$(bash "$SRC" --file "$C" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
# mut <jq expression>: $C becomes the passing config with that change.
mut() { jq "$1" <<< "$GOOD" > "$C"; }
# breaks <label> <jq expression> <text the one finding must hold>: exit 1, exactly one line, naming it.
breaks() {
  mut "$2"; run
  expect "$1: exits 1" 1 "$rc"
  contains "$3" "$err" "$1: names $3"
  expect "$1: is the only finding" 1 "$(grep -c . <<< "$err")"
  expect "$1: prints nothing on stdout" "" "$out"
}
# holds <label> <jq expression>: still exit 0.
holds() { mut "$2"; run; expect "$1: exits 0" 0 "$rc"; expect "$1: is silent on stderr" "" "$err"; }

echo "the baseline and the shipped template"
mut '.'; run
expect "the passing config exits 0" 0 "$rc"
contains "every pin holds" "$out" "it says every pin holds"
contains "$C" "$out" "it names the file"
expect "it prints one line" 1 "$(grep -c . <<< "$out")"
run --branch develop
expect "--branch naming a listed branch exits 0" 0 "$rc"

cp "$TPL" "$C"; run
expect "the template as shipped exits 1" 1 "$rc"
contains "reviews.auto_review.base_branches" "$err" "it names base_branches"
contains "<integration-branch>" "$err" "it names the placeholder"
expect "the placeholder is its only finding" 1 "$(grep -c . <<< "$err")"
sed 's/<integration-branch>/develop/' "$TPL" > "$C"; run --branch develop
expect "the template with the branch filled exits 0" 0 "$rc"
if grep -q "$(printf '\t')" "$TPL"; then bad "the template holds a tab"; else ok "the template holds no tab"; fi
if grep -q "^ *overrides:" "$TPL"; then bad "the template writes an overrides key"; else ok "the template writes no overrides key (#600)"; fi

echo "the file itself"
breaks "inheritance on" '.inheritance = true' "inheritance: is true"
holds "inheritance absent" 'del(.inheritance)'
holds "version 2, which the vendor reads as V2" '.version = 2'
holds "version 2.0, the same number" '.version = 2.0'
breaks "version 3, another schema" '.version = 3' "version: is 3, and that selects the vendor V3 schema"
breaks "version 3 as a string" '.version = "3"' 'version: is "3", and the vendor reports a version error'
breaks "version 1" '.version = 1' "version: is 1, and the vendor reports a version error"
breaks "version with no value" '.version = null' "version: is null, and the vendor reports a version error"

echo "group 1: nothing may push"
for t in unit_tests simplify autofix fix_ci resolve_merge_conflict; do
  breaks "$t enabled" ".reviews.finishing_touches.$t.enabled = true" "reviews.finishing_touches.$t.enabled: is true"
  breaks "$t missing" "del(.reviews.finishing_touches.$t)" "reviews.finishing_touches.$t.enabled: missing"
done
breaks "a quoted false is not false" '.reviews.finishing_touches.autofix.enabled = "false"' 'reviews.finishing_touches.autofix.enabled: is "false"'
breaks "a custom recipe" '.reviews.finishing_touches.custom = [{"name": "r"}]' "reviews.finishing_touches.custom: is"
breaks "custom missing" 'del(.reviews.finishing_touches.custom)' "reviews.finishing_touches.custom: missing"
breaks "custom as a mapping" '.reviews.finishing_touches.custom = {}' "reviews.finishing_touches.custom: is {}"
breaks "a post-merge action" '.reviews.post_merge_actions = [{"name": "a"}]' "reviews.post_merge_actions: is"
breaks "post_merge_actions missing" 'del(.reviews.post_merge_actions)' "reviews.post_merge_actions: missing"
mut 'del(.reviews.finishing_touches)'; run
expect "the whole finishing_touches block deleted exits 1" 1 "$rc"
expect "it reports all five built-ins and custom" 6 "$(grep -c 'reviews.finishing_touches\..*: missing' <<< "$err")"
mut '.reviews.finishing_touches = [1, 2]'; run
expect "finishing_touches as a list exits 1, not a crash" 1 "$rc"
expect "and still reports six keys" 6 "$(grep -c 'reviews.finishing_touches\..*: missing' <<< "$err")"

echo "group 2: never a gate"
for k in auto_approvals.enabled auto_approvals.allow_author_approval fail_commit_status; do
  breaks "$k true" ".reviews.$k = true" "reviews.$k: is true"
  breaks "$k missing" "del(.reviews.$k)" "reviews.$k: missing"
done
for k in request_changes_workflow allow_author_approval; do
  breaks "the legacy alias $k true" ".reviews.$k = true" "reviews.$k: is true"
  holds "the legacy alias $k false" ".reviews.$k = false"
done
holds "overrides absent" 'del(.reviews.auto_approvals.overrides)'
holds "an empty overrides list" '.reviews.auto_approvals.overrides = []'
holds "a disabled override with paths" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"]}]'
holds "a disabled override with teams" '.reviews.auto_approvals.overrides = [{"enabled": false, "teams": ["o/t"]}]'
holds "a disabled override with both and a risk limit" '.reviews.auto_approvals.overrides = [{"enabled": false, "teams": ["o/t"], "paths": ["src/**"], "max_merge_risk": "low"}]'
breaks "the entry with no selector that 0.10.2 shipped" '.reviews.auto_approvals.overrides = [{"enabled": false}]' 'reviews.auto_approvals.overrides[0]: is {"enabled":false}, and it names no paths or teams; the vendor requires one, and such an entry was reported to make the app drop the whole file'
breaks "a bare overrides key" '.reviews.auto_approvals.overrides = null' 'reviews.auto_approvals.overrides: is null, and the vendor types it as a list'
breaks "overrides as a mapping" '.reviews.auto_approvals.overrides = {"enabled": false}' 'reviews.auto_approvals.overrides: is {"enabled":false}, and it must be a list'
breaks "an empty paths list" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": []}]' 'and paths and teams must each be a non-empty list'
breaks "an empty teams list beside filled paths" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"], "teams": []}]' 'and paths and teams must each be a non-empty list'
breaks "paths given as a string" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": "**"}]' 'and paths and teams must each be a non-empty list'
breaks "teams given as a string beside filled paths" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"], "teams": "o/t"}]' 'and paths and teams must each be a non-empty list'
breaks "a null selector element" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": [null]}]' 'and paths and teams must each be a non-empty list'
breaks "a risk limit that is a number" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"], "max_merge_risk": 3}]' 'max_merge_risk must be a string when given'
breaks "a security risk limit with no value" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"], "max_security_risk": null}]' 'max_security_risk must be a string when given'
breaks "an enabling override" '.reviews.auto_approvals.overrides = [{"enabled": true, "paths": ["**"]}]' 'and every entry must set enabled: false'
breaks "an entry that leaves enabled out" '.reviews.auto_approvals.overrides = [{"paths": ["src/**"], "max_merge_risk": "low"}]' 'and every entry must set enabled: false'
breaks "a scalar entry" '.reviews.auto_approvals.overrides = ["x"]' 'reviews.auto_approvals.overrides[0]: is "x", and it must be a mapping'
breaks "a bad second entry beside a good first" '.reviews.auto_approvals.overrides = [{"enabled": false, "paths": ["**"]}, {"enabled": false}]' 'reviews.auto_approvals.overrides[1]: is'
for c in title description issue_assessment a_check_added_later; do
  breaks "pre-merge $c in error mode" ".reviews.pre_merge_checks.$c.mode = \"error\"" "reviews.pre_merge_checks.$c.mode: is \"error\""
done
holds "the retired docstrings finishing touch left enabled" '.reviews.finishing_touches.docstrings.enabled = true'
holds "a pre-merge check in warning mode" '.reviews.pre_merge_checks.title.mode = "warning"'
holds "a pre-merge check that is off" '.reviews.pre_merge_checks.title.mode = "off"'
breaks "a custom check in error mode" '.reviews.pre_merge_checks.custom_checks = [{"name": "w", "mode": "warning"}, {"name": "x", "mode": "error"}]' 'custom_checks: the check "x"'
holds "custom checks in warning mode" '.reviews.pre_merge_checks.custom_checks = [{"name": "w", "mode": "warning"}]'
breaks "custom_checks as a mapping" '.reviews.pre_merge_checks.custom_checks = {"mode": "error"}' "reviews.pre_merge_checks.custom_checks: is"
mut '.reviews.pre_merge_checks.custom_checks = [{"name": "x", "mode": "error"}, {"name": "y", "mode": "error"}]'; run
expect "two custom checks in error mode are two findings" 2 "$(grep -c 'custom_checks' <<< "$err")"

echo "group 3: scope"
breaks "base_branches missing" 'del(.reviews.auto_review.base_branches)' "reviews.auto_review.base_branches: missing"
breaks "base_branches empty" '.reviews.auto_review.base_branches = []' "reviews.auto_review.base_branches: is []"
breaks "base_branches as a string" '.reviews.auto_review.base_branches = "develop"' 'reviews.auto_review.base_branches: is "develop"'
breaks "the placeholder beside a real branch" '.reviews.auto_review.base_branches = ["develop", "<integration-branch>"]' "template placeholder"
mut '.'; run --branch release
expect "--branch naming an unlisted branch exits 1" 1 "$rc"
contains 'no entry matches the branch "release"' "$err" "it says no entry matches"
mut '.reviews.auto_review.base_branches = ["main", "develop|release/.*"]'
run --branch develop;      expect "--branch matches an alternation entry" 0 "$rc"
run --branch release/1.2;  expect "--branch matches a pattern entry" 0 "$rc"
run --branch developx;     expect "the match is anchored at the end" 1 "$rc"
run --branch my-develop;   expect "the match is anchored at the start" 1 "$rc"
mut '.reviews.auto_review.base_branches = ["(", 7]'; run --branch develop
expect "an entry that is not a valid regex matches nothing and does not crash" 1 "$rc"
expect "and is one finding" 1 "$(grep -c . <<< "$err")"
run; expect "without --branch the entries are not matched" 0 "$rc"
breaks "a person in ignore_usernames" '.reviews.auto_review.ignore_usernames = ["dependabot[bot]", "alice"]' '"alice" does not end in [bot]'
breaks "a number in ignore_usernames" '.reviews.auto_review.ignore_usernames = [3]' "3 does not end in [bot]"
breaks "ignore_usernames as a string" '.reviews.auto_review.ignore_usernames = "renovate[bot]"' "reviews.auto_review.ignore_usernames: is"
mut '.reviews.auto_review.ignore_usernames = ["dependabot[bot]", "project_1_bot", "alice"]'
run --allow-ignored project_1_bot --allow-ignored alice
expect "--allow-ignored, once per login, lets them through" 0 "$rc"
run --allow-ignored project_1_bot
expect "a login not allowed still fails" 1 "$rc"
contains '"alice"' "$err" "and is the one named"
lacks "project_1_bot" "$err" "the allowed one is not named"
holds "ignore_usernames absent" 'del(.reviews.auto_review.ignore_usernames)'
holds "ignore_usernames empty" '.reviews.auto_review.ignore_usernames = []'
breaks "drafts reviewed" '.reviews.auto_review.drafts = true' "reviews.auto_review.drafts: is true"
holds "drafts absent" 'del(.reviews.auto_review.drafts)'

echo "group 4: quiet"
for k in reviews.auto_apply_labels reviews.auto_assign_reviewers issue_enrichment.auto_enrich.enabled issue_enrichment.labeling.auto_apply_labels; do
  breaks "$k true" ".$k = true" "$k: is true"
  holds "$k absent" "del(.$k)"
done
for k in issue_enrichment.planning.enabled issue_enrichment.planning.auto_planning.enabled chat.auto_reply; do
  breaks "$k true" ".$k = true" "$k: is true"
  breaks "$k missing" "del(.$k)" "$k: missing"
done
mut 'del(.issue_enrichment) | del(.chat)'; run
expect "issue_enrichment and chat deleted are three findings" 3 "$(grep -c ': missing' <<< "$err")"

echo "group 5: one source of rules"
breaks "a path instruction" '.reviews.path_instructions = [{"path": "a", "instructions": "b"}]' "reviews.path_instructions: is"
holds "path_instructions absent" 'del(.reviews.path_instructions)'
breaks "code guidelines off" '.knowledge_base.code_guidelines.enabled = false' "knowledge_base.code_guidelines.enabled: is false"
holds "knowledge_base absent" 'del(.knowledge_base)'

echo "every finding is reported, not only the first"
mut '.reviews.finishing_touches.autofix.enabled = true | .reviews.auto_approvals.enabled = true | .chat.auto_reply = true | .reviews.auto_review.drafts = true'; run
expect "four broken pins exit 1" 1 "$rc"
expect "and are four lines" 4 "$(grep -c . <<< "$err")"
expect "each line opens with the file" 4 "$(grep -c "^$C: " <<< "$err")"
printf '{}\n' > "$C"; run
expect "an empty mapping exits 1" 1 "$rc"
expect "and reports the fourteen required keys" 14 "$(grep -c . <<< "$err")"

echo "what it cannot read"
printf 'reviews: [\n' > "$C"; run
expect "invalid YAML exits 2" 2 "$rc"
contains "cannot parse" "$err" "invalid YAML says cannot parse"
expect "invalid YAML prints nothing on stdout" "" "$out"
printf -- '- a\n- b\n' > "$C"; run
expect "a top-level list exits 2" 2 "$rc"
contains "cannot parse" "$err" "a top-level list says cannot parse"
: > "$C"; run
expect "an empty file exits 2" 2 "$rc"
contains "cannot parse" "$err" "an empty file says cannot parse"
printf 'just a string\n' > "$C"; run
expect "a scalar document exits 2" 2 "$rc"
printf 'chat:\n  auto_reply: false\nchat:\n  auto_reply: true\n' > "$C"; run
expect "a duplicate key exits 2, whichever copy a parser would keep" 2 "$rc"
contains "cannot parse" "$err" "a duplicate key says cannot parse"
printf 'reviews:\n  finishing_touches:\n    autofix: {enabled: false}\n    autofix: {enabled: true}\n' > "$C"; run
expect "a nested duplicate key exits 2" 2 "$rc"
printf 'a: &x {k: 1}\nb:\n  <<: *x\n' > "$C"; run
expect "a merge key exits 2: another parser reads it as a literal key" 2 "$rc"
printf 'chat:\n  auto_reply: false\n---\nchat:\n  auto_reply: true\n' > "$C"; run
expect "a second document exits 2" 2 "$rc"
# A line break only YAML 1.1 honours: PyYAML would see the key, a YAML 1.2 parser a comment.
for u in 'c2 85' 'e2 80 a8' 'e2 80 a9'; do
  b=$(printf "$(printf '\\x%s' $u)")
  sed 's/<integration-branch>/develop/' "$TPL" | awk -v b="$b" '
    $1 == "autofix:" { printf "    # no fixes%s    autofix:%s      enabled: false\n", b, b; getline; next } { print }' > "$C"; run
  expect "a line break of bytes $u exits 2" 2 "$rc"
  contains "cannot parse: it holds U+0085, U+2028 or U+2029" "$err" "bytes $u say cannot parse and name the cause"
  expect "bytes $u print nothing on stdout" "" "$out"
done
for v in '!!bool no' '!!bool false' '! false' '!!str false'; do
  sed 's/<integration-branch>/develop/' "$TPL" | sed "s/auto_reply: false/auto_reply: $v/" > "$C"; run
  expect "the tagged value '$v' exits 2" 2 "$rc"
  contains "cannot parse" "$err" "'$v' says cannot parse"
done
sed 's/<integration-branch>/develop/' "$TPL" > "$C"; printf 'reviews:\n  x: 1\n' >> "$C"; run
expect "a duplicate top-level block exits 2" 2 "$rc"
printf '? [a, b]\n: 1\n' > "$C"; run
expect "a key that is not a plain scalar exits 2, without a traceback" 2 "$rc"
lacks "Traceback" "$err" "no traceback reaches the caller"
for w in no off No OFF n; do
  sed -e 's/<integration-branch>/develop/' -e "s/auto_reply: false/auto_reply: $w/" "$TPL" > "$C"; run
  expect "'$w' is not false: exits 1" 1 "$rc"
  contains "chat.auto_reply: is \"$w\"" "$err" "'$w' is reported as the string it is"
done
for w in False FALSE; do
  sed -e 's/<integration-branch>/develop/' -e "s/auto_reply: false/auto_reply: $w/" "$TPL" > "$C"; run
  expect "'$w' is false: exits 0" 0 "$rc"
done
sed 's/<integration-branch>/develop/' "$TPL" > "$C"; printf 'tone_instructions: 2026-01-01\n' >> "$C"; run
expect "a bare date elsewhere in the file is read, not a crash" 0 "$rc"
out=$(bash "$SRC" --file "$T/absent.yaml" 2>&1); rc=$?
expect "a missing file exits 2" 2 "$rc"
contains "no such file" "$out" "it says no such file"
out=$(cd "$T" && rm -f .coderabbit.yaml && bash "$SRC" 2>&1); rc=$?
expect "the default file, when absent, exits 2" 2 "$rc"
contains ".coderabbit.yaml" "$out" "the default is .coderabbit.yaml"
( cd "$T" && jq . <<< "$GOOD" > .coderabbit.yaml && bash "$SRC" >/dev/null 2>&1 ); expect "the default file, when present and passing, exits 0" 0 "$?"

echo "usage"
mut '.'
for a in "--nope" "--file" "--branch" "--schema" "--allow-ignored" "extra"; do
  # shellcheck disable=SC2086
  out=$(bash "$SRC" --file "$C" $a 2>&1 >/dev/null); rc=$?
  expect "'$a' exits 2" 2 "$rc"
  contains "usage:" "$out" "'$a' prints the usage"
done
# An empty value is an unset variable in somebody's CI line, never a request to skip the check.
for a in --file --branch --schema --allow-ignored; do
  out=$(bash "$SRC" --file "$C" "$a" "" 2>&1 >/dev/null); rc=$?
  expect "'$a' with an empty value exits 2" 2 "$rc"
  contains "usage:" "$out" "'$a' with an empty value prints the usage"
done

echo "the parser: a PATH holding only what each case allows"
JQ=$(command -v jq)
mk() { rm -rf "$T/$1"; mkdir -p "$T/$1"; ln -s "$JQ" "$T/$1/jq"; }
runp() { out=$(PATH="$T/$1" "$BASH" "$SRC" --file "$C" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
mut '.'
mk none; runp none
expect "no python3 exits 2" 2 "$rc"
contains "cannot parse" "$err" "no python3 says cannot parse"
contains "python3 with PyYAML" "$err" "it names what it needs"
expect "no python3 prints nothing on stdout" "" "$out"
# A python3 that cannot import yaml is not a parser either, and neither is a yq beside it.
mk nopy; printf '#!/bin/sh\nexit 1\n' > "$T/nopy/python3"; chmod +x "$T/nopy/python3"
printf '#!/bin/sh\nfor a; do f=$a; done\nexec /bin/cat "$f"\n' > "$T/nopy/yq"; chmod +x "$T/nopy/yq"; runp nopy
expect "a python3 without PyYAML exits 2, even with a yq on PATH" 2 "$rc"
contains "cannot parse" "$err" "and says cannot parse"
# A yaml.py in the checked repository is never imported: it would run and could forge the verdict.
mkdir -p "$T/evil"; printf 'import os\nopen(os.path.join(os.path.dirname(__file__), "ran"), "w").close()\ndef __getattr__(n): raise ImportError(n)\n' > "$T/evil/yaml.py"
mut '.'; out=$(cd "$T/evil" && bash "$SRC" --file "$C" 2>"$T/err"); rc=$?
expect "a yaml.py in the current directory does not change the verdict" 0 "$rc"
[ ! -e "$T/evil/ran" ]; expect "and is not executed" 0 "$?"
# A python3 that imports yaml and then dies mid-read.
mk dies; printf '#!/bin/sh\ncase "$2" in *"import yaml") exit 0;; esac\n/bin/cat "%s"; exit 1\n' "$C" > "$T/dies/python3"; chmod +x "$T/dies/python3"; runp dies
expect "a parser that fails after starting exits 2" 2 "$rc"
mk junk; printf '#!/bin/sh\ncase "$2" in *"import yaml") exit 0;; esac\necho "[1]"\n' > "$T/junk/python3"; chmod +x "$T/junk/python3"; runp junk
expect "a parser that returns something other than a mapping exits 2" 2 "$rc"
out=$(PATH="$T/empty-path-dir" "$BASH" "$SRC" --file "$C" 2>&1); rc=$?
expect "no jq exits 2" 2 "$rc"
contains "jq is required" "$out" "and says jq is required"

echo "--schema: the pinned keys against a copy of the vendor schema"
# leaf <type>: a schema node. The stub has the vendor's shape, properties under properties.
S="$T/schema.json"
SCHEMA='def en: {type: "object", properties: {enabled: {type: "boolean"}}};
def md: {type: "object", properties: {mode: {type: "string"}}};
{type: "object", properties: {
  inheritance: {},
  reviews: {type: "object", properties: {
    request_changes_workflow: {}, fail_commit_status: {}, auto_apply_labels: {}, auto_assign_reviewers: {},
    path_instructions: {}, post_merge_actions: {},
    auto_approvals: {properties: {enabled: {}, allow_author_approval: {}, overrides: {type: "array", items: en}}},
    pre_merge_checks: {properties: {docstrings: md, title: md, description: md, issue_assessment: md,
      custom_checks: {type: "array", items: md}}},
    auto_review: {properties: {drafts: {}, base_branches: {}, ignore_usernames: {}}},
    finishing_touches: {properties: {docstrings: en, unit_tests: en, simplify: en, autofix: en, fix_ci: en,
      resolve_merge_conflict: en, custom: {}}}}},
  issue_enrichment: {properties: {auto_enrich: en, labeling: {properties: {auto_apply_labels: {}}},
    planning: {properties: {enabled: {}, auto_planning: en}}}},
  chat: {properties: {auto_reply: {}}},
  knowledge_base: {properties: {code_guidelines: en}}}}'
sch() { jq -n "$SCHEMA | $1" > "$S"; }
mut '.'
sch '.'; run --schema "$S"
expect "a schema that defines every pinned key exits 0" 0 "$rc"
contains "schema still defines every pinned key" "$out" "and says so"
sch '{definitions: {schema: .}}'; run --schema "$S"
expect "the same schema under definitions.schema exits 0" 0 "$rc"
sch 'del(.properties.reviews.properties.finishing_touches.properties.fix_ci)'; run --schema "$S"
expect "a schema without fix_ci exits 1" 1 "$rc"
contains "reviews.finishing_touches.fix_ci.enabled" "$err" "it names the pinned key"
contains "schema no longer defines" "$err" "it says the schema no longer defines it"
contains "$S: " "$err" "the line opens with the schema file"
expect "it is the only finding" 1 "$(grep -c . <<< "$err")"
sch 'del(.properties.reviews.properties.pre_merge_checks.properties.custom_checks.items.properties.mode)'; run --schema "$S"
expect "a schema whose custom check lost its mode exits 1" 1 "$rc"
contains "reviews.pre_merge_checks.custom_checks[].mode" "$err" "it names the list item key"
sch 'del(.properties.reviews.properties.auto_approvals.properties.overrides.items.properties.enabled)'; run --schema "$S"
expect "a schema whose override entry lost enabled exits 1" 1 "$rc"
contains "reviews.auto_approvals.overrides[].enabled" "$err" "it names the override item key"
sch 'del(.properties.chat)'; run --schema "$S"
contains "chat.auto_reply" "$err" "a removed top-level block names its pinned key"
sch '.properties.reviews.properties.auto_review.properties.base_branches = null'; run --schema "$S"
expect "a key present but null in the schema is not defined" 1 "$rc"
sch 'del(.properties.reviews.properties.request_changes_workflow)'; run --schema "$S"
expect "a deprecated alias leaving the schema is not drift" 0 "$rc"
printf '{}\n' > "$S"; run --schema "$S"
expect "an empty schema exits 1" 1 "$rc"
expect "and names all twenty-eight pinned keys" 28 "$(grep -c 'schema no longer defines' <<< "$err")"
sch 'del(.properties.chat)'; mut '.reviews.fail_commit_status = true'; run --schema "$S"
expect "a broken pin and a drifted key exit 1" 1 "$rc"
expect "and are two lines" 2 "$(grep -c . <<< "$err")"
mut '.'
printf '[]\n' > "$S"; run --schema "$S"
expect "a schema that is not an object exits 2" 2 "$rc"
printf 'not json\n' > "$S"; run --schema "$S"
expect "a schema that is not JSON exits 2" 2 "$rc"
run --schema "$T/absent.json"
expect "a missing schema file exits 2" 2 "$rc"
contains "no such schema file" "$err" "and says so"
lacks "every pin holds" "$out" "and does not report the pins as holding"

echo ""
echo "check-coderabbit-config tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
