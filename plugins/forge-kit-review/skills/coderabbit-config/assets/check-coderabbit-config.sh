#!/usr/bin/env bash
# check-coderabbit-config-version: 1
# check-coderabbit-config.sh: fail when a .coderabbit.yaml lets the reviewer do more than advise (#598).
#
# The CodeRabbit pull request app is installed with write access, and several of its features are
# ON by vendor default: a commenter can ask it to commit to a branch, and one key lets it approve.
# The template beside this script pins those off. This script is what keeps them pinned: a config
# nobody checks drifts the first time somebody tidies it.
#
# Needs jq and python3 with PyYAML, the one shell asset in the kit that needs a module outside
# the standard library. Where either is missing it exits 2 and says which.
#
# Usage: check-coderabbit-config.sh [--file <path>] [--branch <name>] [--allow-ignored <login>]...
#                                  [--schema <file>]
#
#   --file           the config to read (default: .coderabbit.yaml in the current directory)
#   --branch         also require that an entry of reviews.auto_review.base_branches matches this
#                    branch. The vendor reads each entry as a regex, so the entry is applied as
#                    one, anchored at both ends: a pass here holds under a looser reading too.
#   --allow-ignored  a login allowed in reviews.auto_review.ignore_usernames although it does not
#                    end in [bot]. That suffix is GitHub's convention for an app account; a bot on
#                    another host is named here, one option per login.
#   --schema         a copy of the vendor's schema.v2.json the CALLER downloaded; also fail on every
#                    pinned key path that schema no longer defines (a renamed key still satisfies a
#                    presence check while meaning nothing). This script never touches the network.
#
# Exit 0: every pin holds IN THIS FILE; one summary line on stdout. It says nothing about settings
#         made in the vendor's web interface or in an organisation-level config, which this script
#         cannot see.
# Exit 1: one line per broken pin on stderr, `<file>: <key path>: <what is wrong>`, ALL of them.
# Exit 2: usage error, a missing file, no YAML parser, or a file that did not parse. The last two
#         say `cannot parse`. It never exits 0 without having read every pin.
#
# The pins, in five groups (a key marked REQUIRED fails when missing, because the vendor default
# is the unsafe value or because a default can change; every other key may be absent):
#   0. the file itself    `inheritance` not true (a parent layer would fill every absent key);
#                         `version` is absent (schema.v2 defines no such key and rejects it)
#   1. nothing may push   reviews.finishing_touches.<five built-ins>.enabled REQUIRED false;
#                         reviews.finishing_touches.custom and reviews.post_merge_actions
#                         REQUIRED empty lists. (`docstrings` is retired by the vendor and has no
#                         effect, so it is not pinned.)
#   2. never a gate       reviews.auto_approvals.enabled, .allow_author_approval and
#                         reviews.fail_commit_status REQUIRED false; the two legacy aliases
#                         reviews.request_changes_workflow and reviews.allow_author_approval not
#                         true; reviews.auto_approvals.overrides REQUIRED to hold {enabled: false}; no `mode` under
#                         reviews.pre_merge_checks equal to `error`
#   3. scope              base_branches REQUIRED, a non-empty list without the template
#                         placeholder; every ignore_usernames entry ends in [bot] or was allowed;
#                         drafts not true
#   4. quiet              labels, reviewers, issue enrichment and labeling not true;
#                         issue_enrichment.planning.enabled, its auto_planning.enabled and
#                         chat.auto_reply REQUIRED false (their vendor default is true)
#   5. one rule source    reviews.path_instructions empty; code_guidelines.enabled not false
#
# YAML is read by python3 with PyYAML and checked as JSON with jq. The read is STRICTER than
# PyYAML's default, so that this script never reads a key more kindly than another parser would:
# a duplicate key is a parse failure (PyYAML alone keeps the last one silently), and only
# true/false are booleans (PyYAML alone reads `no` and `off` as false, a YAML 1.2 parser reads
# them as strings), so `enabled: no` FAILS its pin. A tag (`!!bool no`, `! false`), a merge key
# (`<<`) and the three line breaks only YAML 1.1 honours are parse failures for the same reason. There is no second parser and no hand-written
# subset parser on purpose: each would read some file differently.
#
# Portable to bash 3.2 (stock macOS): no associative arrays, no mapfile, no ${x,,}.
set -uo pipefail

usage() { echo "check-coderabbit-config: $1" >&2; echo "usage: check-coderabbit-config.sh [--file <path>] [--branch <name>] [--allow-ignored <login>]... [--schema <file>]" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "check-coderabbit-config: jq is required" >&2; exit 2; }

file=".coderabbit.yaml" branch="" schema="" allowed="[]"
while [ $# -gt 0 ]; do
  case "$1" in
    --file)   [ $# -ge 2 ] && [ -n "$2" ] || usage "--file needs a path"; file=$2; shift 2 ;;
    --branch) [ $# -ge 2 ] && [ -n "$2" ] || usage "--branch needs a name"; branch=$2; shift 2 ;;
    --allow-ignored) [ $# -ge 2 ] && [ -n "$2" ] || usage "--allow-ignored needs a login"
              allowed=$(jq -cn --argjson a "$allowed" --arg l "$2" '$a + [$l]') || exit 2; shift 2 ;;
    --schema) [ $# -ge 2 ] && [ -n "$2" ] || usage "--schema needs a file"; schema=$2; shift 2 ;;
    *)        usage "unknown argument: $1" ;;
  esac
done

[ -f "$file" ] || { echo "check-coderabbit-config: $file: no such file" >&2; exit 2; }
if [ -n "$schema" ]; then
  [ -f "$schema" ] || { echo "check-coderabbit-config: $schema: no such schema file" >&2; exit 2; }
  jq -e 'type == "object"' "$schema" >/dev/null 2>&1 \
    || { echo "check-coderabbit-config: $schema: the schema is not a JSON object" >&2; exit 2; }
fi

# The file as JSON. The parser's own message is dropped; the verdict below is the one message.
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "check-coderabbit-config: $file: cannot parse: python3 with PyYAML is required to read YAML" >&2
  exit 2
fi
json=$(python3 -c '
import sys, json, re, yaml

class Strict(yaml.SafeLoader):
    pass

# YAML 1.2 core booleans only, and no timestamps: drop the 1.1 resolvers for both.
Strict.yaml_implicit_resolvers = {
    k: [(tag, rx) for tag, rx in v
        if tag not in ("tag:yaml.org,2002:bool", "tag:yaml.org,2002:timestamp")]
    for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
Strict.add_implicit_resolver(
    "tag:yaml.org,2002:bool", re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF"))

def mapping(loader, node):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=True)
        try:
            dup = key in seen
        except TypeError:
            raise yaml.YAMLError("unhashable key")
        if dup:
            raise yaml.YAMLError("duplicate key %r" % (key,))
        seen.add(key)
    return loader.construct_mapping(node, deep=True)

Strict.add_constructor("tag:yaml.org,2002:map", mapping)

with open(sys.argv[1], encoding="utf-8", newline="") as f:
    text = f.read()
# YAML 1.1 (PyYAML) ends a line at these three characters and YAML 1.2 parsers do not, so a key
# after one is a key here and part of a comment there. Refuse the file instead of choosing.
if any(c in text for c in ("\x85", "\u2028", "\u2029")):
    sys.exit(3)
# A tag changes how a scalar is read, and parsers disagree on it: "!!bool no" and "! false" are
# false to the stock constructor and strings elsewhere. A config needs none, so any tag is refused.
if any(isinstance(t, yaml.TagToken) for t in yaml.scan(text)):
    sys.exit(1)
out = json.dumps(yaml.load(text, Loader=Strict))
sys.stdout.write(out)
' "$file" 2>/dev/null); prc=$?
[ "$prc" -eq 0 ] || json=""
if [ "$prc" -eq 3 ]; then
  echo "check-coderabbit-config: $file: cannot parse: it holds U+0085, U+2028 or U+2029, a line break to some YAML parsers and not to others; remove the character" >&2
  exit 2
fi
if ! printf '%s' "$json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "check-coderabbit-config: $file: cannot parse: it is not one YAML mapping with unique, plain keys and no tags or merge keys" >&2
  exit 2
fi

# One line per broken pin. `at` reads a path from the DOCUMENT, whatever `.` is at the call (the
# pins iterate over name lists), and without failing on a list or scalar in the way: anything
# that is not where the pin expects it reads as missing.
checks='
. as $doc |
def at(p): try ($doc | getpath(p)) catch null;
def name(p): p | map(tostring) | join(".");
def show: tojson;
def req_false(p): at(p) as $v
  | if $v == null then "\(name(p)): missing, and it must be false"
    elif $v != false then "\(name(p)): is \($v | show), and it must be false" else empty end;
def opt_false(p): at(p) as $v
  | if $v == null or $v == false then empty else "\(name(p)): is \($v | show), and it must be false or absent" end;
def req_empty(p): at(p) as $v
  | if $v == null then "\(name(p)): missing, and it must be an empty list"
    elif ($v | type) != "array" or ($v | length) > 0 then "\(name(p)): is \($v | show), and it must be an empty list" else empty end;
def opt_empty(p): at(p) as $v
  | if $v == null or $v == [] then empty else "\(name(p)): is \($v | show), and it must be empty or absent" end;

opt_false(["inheritance"]),
( at(["version"]) as $v
  | if ($doc | has("version") | not) then empty
    else "version: is \($v | show), and the vendor schema these pins were read from defines no such key, so its validator rejects the file; remove it" end ),

( ["unit_tests","simplify","autofix","fix_ci","resolve_merge_conflict"][]
  | . as $t | req_false(["reviews","finishing_touches",$t,"enabled"]) ),
req_empty(["reviews","finishing_touches","custom"]),
req_empty(["reviews","post_merge_actions"]),

req_false(["reviews","auto_approvals","enabled"]),
req_false(["reviews","auto_approvals","allow_author_approval"]),
opt_false(["reviews","request_changes_workflow"]),
opt_false(["reviews","allow_author_approval"]),
req_false(["reviews","fail_commit_status"]),
( at(["reviews","auto_approvals","overrides"]) as $o
  | if $o == null then "reviews.auto_approvals.overrides: missing, and an entry that is exactly {enabled: false} is what withholds an approval asked for in a comment"
    elif ($o | type) != "array" or ($o | index([{enabled: false}])) == null
      then "reviews.auto_approvals.overrides: is \($o | show), and it must hold an entry that is exactly {enabled: false}, which matches every pull request"
    else empty end ),
( at(["reviews","pre_merge_checks"]) as $pm
  | if ($pm | type) != "object" then empty
    else $pm | to_entries[] | select(.key != "custom_checks" and (.value | type) == "object" and .value.mode == "error")
         | "reviews.pre_merge_checks.\(.key).mode: is \"error\", which blocks a merge" end ),
( at(["reviews","pre_merge_checks","custom_checks"]) as $cc
  | if $cc == null then empty
    elif ($cc | type) != "array" then "reviews.pre_merge_checks.custom_checks: is \($cc | show), and it must be a list"
    else $cc[] | select((try .mode catch null) == "error")
         | "reviews.pre_merge_checks.custom_checks: the check \((try .name catch null) | show) is in \"error\" mode, which blocks a merge"
    end ),

( at(["reviews","auto_review","base_branches"]) as $b
  | if $b == null then "reviews.auto_review.base_branches: missing, so only the default branch is reviewed"
    elif ($b | type) != "array" or ($b | length) == 0 then "reviews.auto_review.base_branches: is \($b | show), and it must be a non-empty list"
    elif ($b | index("<integration-branch>")) != null then "reviews.auto_review.base_branches: still holds the template placeholder <integration-branch>"
    elif $branch != "" and ([ $b[] | select(type == "string") | . as $e
                              | select(try ($branch | test("^(?:" + $e + ")$")) catch false) ] | length) == 0
      then "reviews.auto_review.base_branches: no entry matches the branch \($branch | show)"
    else empty end ),
( at(["reviews","auto_review","ignore_usernames"]) as $u
  | if $u == null then empty
    elif ($u | type) != "array" then "reviews.auto_review.ignore_usernames: is \($u | show), and it must be a list"
    else $u[] | select((type != "string") or ((endswith("[bot]") | not) and (. as $l | $allowed | index($l)) == null))
         | "reviews.auto_review.ignore_usernames: \(show) does not end in [bot] and was not passed with --allow-ignored; whoever is listed loses their review"
    end ),
opt_false(["reviews","auto_review","drafts"]),

opt_false(["reviews","auto_apply_labels"]),
opt_false(["reviews","auto_assign_reviewers"]),
opt_false(["issue_enrichment","auto_enrich","enabled"]),
opt_false(["issue_enrichment","labeling","auto_apply_labels"]),
req_false(["issue_enrichment","planning","enabled"]),
req_false(["issue_enrichment","planning","auto_planning","enabled"]),
req_false(["chat","auto_reply"]),

opt_empty(["reviews","path_instructions"]),
( at(["knowledge_base","code_guidelines","enabled"]) as $g
  | if $g == null or $g == true then empty
    else "knowledge_base.code_guidelines.enabled: is \($g | show), and it must be true or absent" end )
'
if ! found=$(printf '%s' "$json" | jq -r --arg branch "$branch" --argjson allowed "$allowed" "$checks" 2>&1); then
  echo "check-coderabbit-config: $file: cannot parse: the checks could not read it ($found)" >&2
  exit 2
fi

# Every pinned path, for --schema. `[]` steps into a list's items.
pinned='
[ ["inheritance"],
  (["unit_tests","simplify","autofix","fix_ci","resolve_merge_conflict"][]
    | ["reviews","finishing_touches",.,"enabled"]),
  ["reviews","finishing_touches","custom"],
  ["reviews","post_merge_actions"],
  ["reviews","auto_approvals","enabled"],
  ["reviews","auto_approvals","allow_author_approval"],
  ["reviews","auto_approvals","overrides","[]","enabled"],
  ["reviews","fail_commit_status"],
  (["title","description","issue_assessment"][] | ["reviews","pre_merge_checks",.,"mode"]),
  ["reviews","pre_merge_checks","custom_checks","[]","mode"],
  ["reviews","auto_review","base_branches"],
  ["reviews","auto_review","ignore_usernames"],
  ["reviews","auto_review","drafts"],
  ["reviews","auto_apply_labels"],
  ["reviews","auto_assign_reviewers"],
  ["reviews","path_instructions"],
  ["issue_enrichment","auto_enrich","enabled"],
  ["issue_enrichment","labeling","auto_apply_labels"],
  ["issue_enrichment","planning","enabled"],
  ["issue_enrichment","planning","auto_planning","enabled"],
  ["chat","auto_reply"],
  ["knowledge_base","code_guidelines","enabled"] ]
'
drift=""
if [ -n "$schema" ]; then
  if ! drift=$(jq -r "
    def step(k): if k == \"[]\" then (try .items catch null) else (try .properties[k] catch null) end;
    (.definitions.schema // .) as \$root
    | $pinned[]
    | . as \$p
    | select((reduce \$p[] as \$k (\$root; if . == null then null else step(\$k) end)) == null)
    | (\$p | join(\".\") | gsub(\"\\\\.\\\\[\\\\]\"; \"[]\")) + \": the vendor schema no longer defines this pinned key\"
  " "$schema" 2>&1); then
    echo "check-coderabbit-config: $schema: the schema could not be read ($drift)" >&2
    exit 2
  fi
fi

rc=0
if [ -n "$found" ]; then
  while IFS= read -r line; do echo "$file: $line" >&2; done <<< "$found"
  rc=1
fi
if [ -n "$drift" ]; then
  while IFS= read -r line; do echo "$schema: $line" >&2; done <<< "$drift"
  rc=1
fi
[ "$rc" -eq 0 ] || exit 1
if [ -n "$schema" ]; then
  echo "check-coderabbit-config: $file: every pin holds in this file, and the schema still defines every pinned key"
else
  echo "check-coderabbit-config: $file: every pin holds in this file"
fi
