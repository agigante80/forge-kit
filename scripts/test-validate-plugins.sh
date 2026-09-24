#!/usr/bin/env bash
# Contract test for validate-plugins.sh (#169, #173).
#
# WHY THIS SUITE EXISTS AT ALL. validate-plugins.sh has been the kit's structural gate since the
# beginning and had NO contract test, which scripts/test-producer-stamps.sh already noted when it
# declined to extend it. Two tickets then needed to add rules to it in the same week, so the suite
# is created here rather than deferred again: this repo's record is that an untested guard grows
# rules nobody can prove fire.
#
# WHAT IT DRIVES. The script as a subprocess against throwaway trees, one per case. Each tree is a
# minimal marketplace (a marketplace.json plus one or more plugin.json files) with no components in
# it, so the marker rule has nothing to say and the case under test is the only thing that can fail.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/validate-plugins.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$1"; then bad "$3 (found '$1' in output)"; else ok "$3"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required by validate-plugins.sh and by this test"; exit 2; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# One tree per case, built from scratch so no case can inherit another's state.
tree() {
  rm -rf "$T/tree"; mkdir -p "$T/tree/.claude-plugin"
  cat > "$T/tree/.claude-plugin/marketplace.json" <<'M'
{ "name": "forge-kit", "owner": { "name": "probe" },
  "plugins": [
    { "name": "forge-kit-alpha", "source": "./plugins/forge-kit-alpha", "description": "a" },
    { "name": "forge-kit-beta",  "source": "./plugins/forge-kit-beta",  "description": "b" } ] }
M
  # Check 7 (#253) needs the tiers doc. The default carries every role a case uses and no
  # components; a case adds the rows its components need with row().
  mkdir -p "$T/tree/docs/guides"
  cat > "$T/tree/docs/guides/model-tiers.md" <<'D'
# Model tiers

### Roles

| Role | Models | Effort | Reason |
|---|---|---|---|
| judgment | inherit, sonnet, opus | high..xhigh | r |
| bounded-analysis | sonnet | low..medium | r |
| knowledge | none | none | r |

### Components

| Component | Role | Reason |
|---|---|---|
D
}
row() { printf '| %s | %s | r |\n' "$1" "$2" >> "$T/tree/docs/guides/model-tiers.md"; }
plugin() {  # plugin <group> <extra-json-fields-or-empty>
  mkdir -p "$T/tree/plugins/$1/.claude-plugin"
  printf '{ "name": "%s", "version": "0.1.0", "description": "d", "author": { "name": "someone" }%s }\n' \
    "$1" "${2:+, $2}" > "$T/tree/plugins/$1/.claude-plugin/plugin.json"
}
raw() {  # raw <group> <whole-plugin.json-body>: for the cases about the author field itself
  mkdir -p "$T/tree/plugins/$1/.claude-plugin"
  cat > "$T/tree/plugins/$1/.claude-plugin/plugin.json"
}
out=""; rc=0
run() { out=$(cd "$T/tree" && bash "$SCRIPT" 2>&1); rc=$?; }

echo "== the baseline tree passes, so a later failure is the rule under test =="
tree; plugin forge-kit-alpha; plugin forge-kit-beta
run
expect "a well-formed tree with no dependencies passes" 0 "$rc"

echo "== a resolvable dependency passes (#169) =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-beta@forge-kit"]'; plugin forge-kit-beta
run
expect "a dependency listed in marketplace.json passes" 0 "$rc"

echo "== an unresolvable dependency fails, naming both sides (#169) =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-nonesuch@forge-kit"]'; plugin forge-kit-beta
run
expect "a dependency absent from marketplace.json fails" 1 "$rc"
contains "forge-kit-nonesuch" "$out" "and names the missing plugin"
contains "forge-kit-alpha" "$out" "and names the group that declared it"

echo "== the object shape fails, because the CLI itself rejects it (#169) =="
# Probed on 2.1.267: `dependencies: {"x": "^0.1.0"}` fails `claude plugin validate` with
# `dependencies: Invalid input`. A guard laxer than the thing it protects is worse than none.
tree; plugin forge-kit-alpha '"dependencies": {"forge-kit-beta": "^0.1.0"}'; plugin forge-kit-beta
run
expect "an object rather than an array fails" 1 "$rc"
contains "array" "$out" "and says the shape must be an array"

echo "== a malformed identifier fails =="
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-beta"]'; plugin forge-kit-beta
run
expect "an identifier with no @marketplace fails" 1 "$rc"
contains "plugin@marketplace" "$out" "and names the shape it wanted"

echo "== the name match is exact, not a substring =="
# A substring match would resolve a typo'd 'forge-kit-alph' against 'forge-kit-alpha' and report a
# broken declaration as healthy, which is the one thing this check exists to prevent.
tree; plugin forge-kit-alpha '"dependencies": ["forge-kit-alph@forge-kit"]'; plugin forge-kit-beta
run
expect "a prefix of a real plugin name fails" 1 "$rc"
contains "forge-kit-alph@" "$out" "and names the identifier it could not resolve"

echo "== a foreign marketplace is reported as unverifiable, not failed =="
# The one honest limit: this script can only resolve names in the marketplace it is standing in.
# Failing a legitimate cross-marketplace dependency would be a guard inventing a violation.
tree; plugin forge-kit-alpha '"dependencies": ["someone-else@their-marketplace"]'; plugin forge-kit-beta
run
expect "a dependency on another marketplace does not fail the build" 0 "$rc"
contains "their-marketplace" "$out" "but is reported, so it is not silently trusted"

echo "== an empty dependencies array is fine =="
tree; plugin forge-kit-alpha '"dependencies": []'; plugin forge-kit-beta
run
expect "an empty array passes" 0 "$rc"

echo "== the author field is required, and its shape is the CLI's (#173) =="
# PROBED ON 2.1.267, not read: `author` must be an OBJECT with a non-empty `name`. A bare string
# fails with `author: Invalid input`; an empty name fails with `author.name: Author name cannot be
# empty`; `url` is optional and accepted. Requiring it here rather than leaving it to the advisory
# `claude plugin validate` step is the kit's standing preference for a build failure over a warning
# nobody reads, and the warning is the thing this ticket was filed about.
tree; plugin forge-kit-alpha; plugin forge-kit-beta
run
expect "an author object with a name passes" 0 "$rc"

tree; plugin forge-kit-beta
raw forge-kit-alpha <<'J'
{ "name": "forge-kit-alpha", "version": "0.1.0", "description": "d" }
J
run
expect "a manifest with no author fails" 1 "$rc"
contains "forge-kit-alpha" "$out" "and names the group that is missing it"

tree; plugin forge-kit-beta
raw forge-kit-alpha <<'J'
{ "name": "forge-kit-alpha", "version": "0.1.0", "description": "d", "author": "agigante80" }
J
run
expect "a bare string author fails, as the CLI itself rejects it" 1 "$rc"
contains "object" "$out" "and says the shape must be an object"

tree; plugin forge-kit-beta
raw forge-kit-alpha <<'J'
{ "name": "forge-kit-alpha", "version": "0.1.0", "description": "d", "author": { "name": "" } }
J
run
expect "an empty author name fails" 1 "$rc"
contains "empty" "$out" "and says the name is empty rather than missing"

tree; plugin forge-kit-beta
raw forge-kit-alpha <<'J'
{ "name": "forge-kit-alpha", "version": "0.1.0", "description": "d", "author": { "url": "https://example.invalid" } }
J
run
expect "an author object with a url but no name fails" 1 "$rc"

echo "== a dispatch to an agent that does not exist fails (#180) =="
# The failure #178 made live: deleting an agent leaves any component that dispatches it broken at
# RUNTIME, silently, which is #124's class of bug.
tree; plugin forge-kit-alpha; plugin forge-kit-beta
mkdir -p "$T/tree/plugins/forge-kit-alpha/agents" "$T/tree/plugins/forge-kit-alpha/commands"
printf -- '---\nname: real-agent\ndescription: d\nmodel: inherit\n---\n<!-- real-agent-version: 1 -->\n' \
  > "$T/tree/plugins/forge-kit-alpha/agents/real-agent.md"
row real-agent judgment; row runner knowledge
printf -- '<!-- runner-version: 1 -->\nDispatch with subagent_type: "real-agent" when reviewing.\n' \
  > "$T/tree/plugins/forge-kit-alpha/commands/runner.md"
run
expect "dispatching an agent that exists passes" 0 "$rc"

printf -- '<!-- runner-version: 1 -->\nDispatch with subagent_type: "ghost-agent" when reviewing.\n' \
  > "$T/tree/plugins/forge-kit-alpha/commands/runner.md"
run
expect "dispatching an agent that does not exist fails" 1 "$rc"
contains "ghost-agent" "$out" "and names the missing agent"
contains "silently" "$out" "and says why it matters: it fails at runtime, quietly"

printf -- '<!-- runner-version: 1 -->\nDispatch with subagent_type: "general-purpose" for a search.\n' \
  > "$T/tree/plugins/forge-kit-alpha/commands/runner.md"
run
expect "general-purpose is Claude Code's own and is not ours to provide" 0 "$rc"

echo "== a scripts/ copy of a shipped asset fails (#231) =="
# The leak guard was installed into this repository the way it is installed into any other, as a
# scripts/ copy, in the one tree that ships the same file as an asset. The copy drifted the first
# time the asset was bumped and CI ran a stale scanner. Keyed on the MARKER NAME, never on content,
# and scripts/test-*.sh is excluded because four suites carry marker lines as heredoc fixtures.
tree; plugin forge-kit-alpha; plugin forge-kit-beta
mkdir -p "$T/tree/plugins/forge-kit-alpha/skills/guard/assets" "$T/tree/scripts"
printf -- '#!/usr/bin/env bash\n# check-thing-version: 3\necho ok\n' > "$T/tree/plugins/forge-kit-alpha/skills/guard/assets/check-thing.sh"
printf -- '---\nname: guard\ndescription: d\n---\n<!-- guard-version: 1 -->\n' > "$T/tree/plugins/forge-kit-alpha/skills/guard/SKILL.md"
printf -- '#!/usr/bin/env bash\n# unrelated-version: 9\necho ok\n' > "$T/tree/scripts/unrelated.sh"
row guard knowledge
run
expect "a scripts/*.sh whose marker name matches no shipped asset passes" 0 "$rc"

printf -- '#!/usr/bin/env bash\n# check-thing-version: 2\necho stale\n' > "$T/tree/scripts/check-thing.sh"
run
expect "a scripts/ copy carrying a shipped asset's marker name fails" 1 "$rc"
contains "scripts/check-thing.sh" "$out" "and names the copy"
contains "plugins/forge-kit-alpha/skills/guard/assets/check-thing.sh" "$out" "and names the asset it duplicates"
rm -f "$T/tree/scripts/check-thing.sh"

printf -- '#!/usr/bin/env bash\ncat <<EOF\n# check-thing-version: 1\nEOF\n' > "$T/tree/scripts/test-check-thing.sh"
run
expect "a scripts/test-*.sh whose heredoc fixture carries the marker line passes (near miss)" 0 "$rc"

echo "== check 7: every component has a row in the tiers doc (#253) =="
# The Roles and Components tables in docs/guides/model-tiers.md are the ONE definition of what a
# component may run on. Each case below builds a fresh tree, so only the rule under test can fail.
A="$T/tree/plugins/forge-kit-alpha"
skill() {  # skill <name> [frontmatter lines]
  mkdir -p "$A/skills/$1"
  printf -- '---\nname: %s\ndescription: d\n%b---\n<!-- %s-version: 1 -->\n' "$1" "${2:-}" "$1" > "$A/skills/$1/SKILL.md"
}
agent() {  # agent <name> [frontmatter lines]
  mkdir -p "$A/agents"
  printf -- '---\nname: %s\ndescription: d\n%b---\n<!-- %s-version: 1 -->\n' "$1" "${2:-}" "$1" > "$A/agents/$1.md"
}
cmd() {  # cmd <name> <body>: a command with no frontmatter, as three of the kit's are
  mkdir -p "$A/commands"
  printf -- '<!-- %s-version: 1 -->\n\n%s\n' "$1" "$2" > "$A/commands/$1.md"
}
base7() { tree; plugin forge-kit-alpha; plugin forge-kit-beta; }

base7; skill demo; row demo knowledge
run
expect "a skill with a row and no declared keys passes" 0 "$rc"
skill newskill
run
expect "a skill with no row fails" 1 "$rc"
contains "newskill: no row in docs/guides/model-tiers.md" "$out" "and names the skill and the doc"

base7; cmd runner 'Nothing to dispatch here.'
run
expect "a command with no row fails too, so rule 2 is not only about agents" 1 "$rc"
contains "runner: no row" "$out" "and names the command"

base7; row ghost knowledge
run
expect "a Components row naming no component fails" 1 "$rc"
contains "row 'ghost' names no component" "$out" "and names the stale row"

base7; skill demo; row demo nonesuch
run
expect "a row naming an undefined role fails" 1 "$rc"
contains "role 'nonesuch' is not defined" "$out" "and names the role"

echo "== check 7: a declared model and effort sit inside the role's range =="
base7; agent auditor 'model: sonnet\n'; row auditor bounded-analysis
run
expect "a model inside the range passes" 0 "$rc"
agent auditor 'model: opus\n'
run
expect "a model outside the range fails" 1 "$rc"
contains "model 'opus' outside role 'bounded-analysis' (allowed: sonnet)" "$out" "and names the value, role and range"

base7; agent auditor 'model: sonnet\neffort: medium\n'; row auditor bounded-analysis
run
expect "an effort inside the range passes" 0 "$rc"
agent auditor 'model: sonnet\neffort: max\n'
run
# Compared as strings, "max" sorts between "low" and "medium" and would pass: this is the case
# that makes the level ORDER load-bearing rather than decorative.
expect "an effort above the range fails, by level order and not by spelling" 1 "$rc"
contains "effort 'max' outside role 'bounded-analysis' (allowed: low..medium)" "$out" "and names the value, role and range"

base7; skill demo 'effort: low\n'; row demo knowledge
run
expect "a none row whose component declares an effort fails" 1 "$rc"
contains "effort 'low' outside role 'knowledge' (allowed: none)" "$out" "and says the role allows none"

base7; agent judge 'model: inherit\n'; row judge judgment
run
expect "an agent declaring model: inherit inside its range passes" 0 "$rc"
agent judge
run
expect "an agent declaring no model fails" 1 "$rc"
contains "judge: agents must declare model" "$out" "and names the agent"

echo "== check 7: the doc itself =="
base7; rm "$T/tree/docs/guides/model-tiers.md"
run
expect "a tree with no tiers doc fails" 1 "$rc"
contains "docs/guides/model-tiers.md not found" "$out" "and names the missing doc"

base7; sed -i 's/| low..medium |/| medium..low |/' "$T/tree/docs/guides/model-tiers.md"
run
expect "an Effort cell running backwards fails as unparseable" 1 "$rc"
contains "unparseable Effort 'medium..low'" "$out" "and quotes the cell"

echo "== check 7: a dispatch with no frontmatter behind it names a model =="
base7; row runner knowledge
cmd runner 'Launch a `general-purpose` sub-agent (`model: sonnet`) with the diff.'
run
expect "a general-purpose dispatch naming a model passes" 0 "$rc"
cmd runner 'Launch a `general-purpose` sub-agent with the diff.'
run
expect "a general-purpose dispatch naming no model fails" 1 "$rc"
contains "commands/runner.md:3: general-purpose dispatch names no model" "$out" "and names the file and line"

cmd runner 'Launch Explore agent (`model: haiku`) to map the callers.'
run
expect "an Explore dispatch naming a model passes" 0 "$rc"
cmd runner 'Launch Explore agent to map the callers.'
run
expect "an Explore dispatch naming no model fails" 1 "$rc"
contains "commands/runner.md:3: Explore dispatch names no model" "$out" "and names the type"

cmd runner 'If any item is fundamental, launch a `general-purpose`
sub-agent NOW to generate alternatives.'
run
expect "a dispatch wrapped across two lines is one paragraph, and fails with no model" 1 "$rc"

cmd runner '| Signal | Action |
|---|---|
| Wide change | Launch Explore agent (`model: sonnet`) to map it |
| Architecture | Launch Explore agent to verify patterns |'
run
# A joined table would let the first row's model cover the second: each row is its own unit.
expect "a table row with no model fails even when another row names one" 1 "$rc"
contains "commands/runner.md:6: Explore dispatch names no model" "$out" "and names that row's line"

echo "== check 7: near misses that are not dispatches =="
cmd runner '5. **Use only local agents.** All `subagent_type` references use agents bundled with this plugin or `general-purpose`.'
run
# `subagent_type` is not the WORD subagent; matching it as a substring would flag a policy sentence.
expect "full-review's policy sentence naming general-purpose is not a dispatch" 0 "$rc"
cmd runner 'Delegate the heavy work to subagents so their output does not fill this context.'
run
expect "delegation naming no agent type is guidance, not a dispatch" 0 "$rc"

echo "== check 7: a named-agent dispatch follows the Agent tool's precedence =="
# Probed on 2.1.281: a dispatch-site model wins over frontmatter, and with none the frontmatter
# governs. So naming nothing is correct here; naming a model outside the agent's range is not.
base7; agent code-reviewer 'model: inherit\n'; row code-reviewer judgment; row runner knowledge
cmd runner 'Use the Agent tool with `subagent_type: code-reviewer`, passing the diff.'
run
expect "a named-agent dispatch naming no model passes" 0 "$rc"
cmd runner 'Use the Agent tool with `subagent_type: code-reviewer` (`model: haiku`), passing the diff.'
run
expect "a named-agent dispatch naming a model outside the agent's range fails" 1 "$rc"
contains "commands/runner.md:3: dispatch of 'code-reviewer' names model 'haiku' outside role 'judgment' (allowed: inherit, sonnet, opus)" "$out" "and names the site, agent, model and range"

echo "== check 7: a YAML dispatch block reads its model at key indentation only =="
base7; row runner knowledge
cmd runner '```
Task:
  subagent_type: "general-purpose"
  description: "x"
  prompt: |
    Review it.
  model: "sonnet"
```'
run
expect "a model key after the prompt text, at key indentation, is seen" 0 "$rc"
cmd runner '```
Task:
  subagent_type: "general-purpose"
  prompt: |
    Review it.
    model: sonnet
```'
run
expect "a model line inside the prompt text is prompt content, so the block names no model" 1 "$rc"
contains "commands/runner.md:4: general-purpose dispatch names no model" "$out" "and names the Task line"

echo "== this repository's own manifests satisfy every rule above =="
# The regression test that keeps the eight real manifests honest, and the one case that would have
# caught the drift this ticket describes had it existed.
out=$(cd "$ROOT" && bash "$SCRIPT" 2>&1); rc=$?
expect "the real tree passes" 0 "$rc"

echo ""
echo "test-validate-plugins: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
