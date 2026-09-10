#!/usr/bin/env bash
# Contract test for check-component-size.sh (issue #97).
#
# Two halves. The threshold behaviour runs against a throwaway fixture tree, so a real component
# landing in this repo can never make the suite pass or fail for the wrong reason. The policy
# agreement half runs against THIS repo, because its whole purpose is that CLAUDE.md's stated
# numbers and the script's enforced numbers cannot drift apart.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
CHECK="$HERE/check-component-size.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/scripts" "$FIX/plugins/fix-g/agents" "$FIX/plugins/fix-g/commands" \
         "$FIX/plugins/fix-g/skills/small-skill" "$FIX/plugins/fix-g/hooks"
cp "$HERE/forge-adapt-catalogue.sh" "$HERE/forge-adapt-agent-skills.sh" "$FIX/scripts/"

# words <n> <file> <marker-name>: a file of n words carrying a valid version marker, and a
# frontmatter description, because since #174 an agent or skill without one FAILS. A fixture that
# failed for that reason would make every threshold case below unreadable.
words() {
  { echo "---"
    echo "name: $3"
    echo "description: Use when exercising the size guard against a fixture component."
    echo "---"
    echo "<!-- $3-version: 1 -->"
    yes lorem | head -n "$1" | tr '\n' ' '; echo; } > "$2"
}

# An agent comfortably inside the 2000-word budget.
words 100 "$FIX/plugins/fix-g/agents/tiny-agent.md" tiny-agent
# A hook, which must be skipped entirely (a word count on code is meaningless).
printf '#!/usr/bin/env python3\n# huge-hook-version: 1\n%s\n' "$(yes x | head -5000 | tr '\n' ' ')" \
  > "$FIX/plugins/fix-g/hooks/huge-hook.py"
words 100 "$FIX/plugins/fix-g/skills/small-skill/SKILL.md" small-skill

run() { bash "$CHECK" --root "$FIX" 2>&1; }

# --- 1. everything inside budget: clean pass ---------------------------------------------------
out=$(run); rc=$?
[ "$rc" -eq 0 ] && ok "all-within-budget exits 0" || bad "all-within-budget exits 0 (rc=$rc)"
printf '%s' "$out" | grep -qE '^(warn|FAIL)' && bad "no warnings when all within budget" \
  || ok "no warnings when all within budget"
printf '%s' "$out" | grep -q 'huge-hook' && bad "hooks are skipped (not word-counted)" \
  || ok "hooks are skipped (not word-counted)"

# --- 2. over budget but under ceiling: WARN, still exit 0 --------------------------------------
words 2400 "$FIX/plugins/fix-g/agents/tiny-agent.md" tiny-agent
out=$(run); rc=$?
[ "$rc" -eq 0 ] && ok "over budget under ceiling still exits 0" \
  || bad "over budget under ceiling still exits 0 (rc=$rc)"
printf '%s' "$out" | grep -q '^warn .*tiny-agent' && ok "over budget produces a warning" \
  || bad "over budget produces a warning"

# --- 3. over the hard ceiling: FAIL ------------------------------------------------------------
words 3200 "$FIX/plugins/fix-g/agents/tiny-agent.md" tiny-agent
out=$(run); rc=$?
[ "$rc" -ne 0 ] && ok "over the hard ceiling exits non-zero" \
  || bad "over the hard ceiling exits non-zero (rc=$rc)"
printf '%s' "$out" | grep -q '^FAIL .*tiny-agent' && ok "over the ceiling reports FAIL" \
  || bad "over the ceiling reports FAIL"
words 100 "$FIX/plugins/fix-g/agents/tiny-agent.md" tiny-agent

# --- 4. skills get the higher budget -----------------------------------------------------------
words 2400 "$FIX/plugins/fix-g/skills/small-skill/SKILL.md" small-skill
out=$(run)
printf '%s' "$out" | grep -q 'small-skill' \
  && bad "a skill at 2400 words is inside the 2500 skill budget" \
  || ok "a skill at 2400 words is inside the 2500 skill budget"
words 100 "$FIX/plugins/fix-g/skills/small-skill/SKILL.md" small-skill

# --- 5. the exemption RATCHET: an exempt component may not grow --------------------------------
# full-review's baseline is 3998. Above it must fail even though it is exempt from the budget.
words 4200 "$FIX/plugins/fix-g/commands/full-review.md" full-review
out=$(run); rc=$?
[ "$rc" -ne 0 ] && ok "an exempt component above its baseline fails" \
  || bad "an exempt component above its baseline fails (rc=$rc)"
printf '%s' "$out" | grep -q 'MAY NOT GROW' && ok "the ratchet failure explains itself" \
  || bad "the ratchet failure explains itself"

# --- 6. an exempt component below its baseline passes, and says so -----------------------------
words 3000 "$FIX/plugins/fix-g/commands/full-review.md" full-review
out=$(run); rc=$?
[ "$rc" -eq 0 ] && ok "an exempt component below its baseline exits 0" \
  || bad "an exempt component below its baseline exits 0 (rc=$rc)"
printf '%s' "$out" | grep -q 'below its 3998 baseline' \
  && ok "a shrunk exempt component is reported so the baseline can be lowered" \
  || bad "a shrunk exempt component is reported"
# ...and it is NOT warned about despite being over the 2000-word command budget.
printf '%s' "$out" | grep -q '^warn .*full-review' \
  && bad "an exempt component is not also warned against the budget" \
  || ok "an exempt component is not also warned against the budget"

# --- 7. no components at all is an error, not a vacuous pass -----------------------------------
EMPTY=$(mktemp -d)
mkdir -p "$EMPTY/scripts" "$EMPTY/plugins"
cp "$HERE/forge-adapt-catalogue.sh" "$EMPTY/scripts/"
bash "$CHECK" --root "$EMPTY" >/dev/null 2>&1
[ $? -ne 0 ] && ok "an empty tree is an error, not a vacuous pass" \
  || bad "an empty tree is an error, not a vacuous pass"
rm -rf "$EMPTY"

# --- 8. POLICY AGREEMENT: CLAUDE.md's table must match the script's enforced numbers ------------
# The whole point of the budget is mechanical enforcement, so the documented numbers may not drift
# from the applied ones.
for pair in "subagent:agent" "command:command" "skill:skill"; do
  ctype=${pair%%:*}; label=${pair##*:}
  # Scoped to budget_for's body: budget_for and baseline_for share a case shape, so an
  # unscoped sed reads one function's arms as the other's.
  script_budget=$(awk '/^budget_for\(\) \{/,/^\}/' "$CHECK" \
                    | sed -n "s/^    $ctype)\s*echo \([0-9]\+\) ;;/\1/p" | head -1)
  doc_line=$(grep -E "^\| $label \| [0-9]+ \| [0-9]+ \|" "$ROOT/CLAUDE.md" | head -1)
  doc_budget=$(printf '%s' "$doc_line" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
  doc_ceiling=$(printf '%s' "$doc_line" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
  if [ -z "$doc_budget" ]; then
    bad "CLAUDE.md documents a budget row for '$label'"
    continue
  fi
  [ "$script_budget" = "$doc_budget" ] \
    && ok "CLAUDE.md and the script agree on the $label budget ($doc_budget)" \
    || bad "CLAUDE.md says $label budget $doc_budget, script says $script_budget"
  [ "$doc_ceiling" = "$(( doc_budget * 3 / 2 ))" ] \
    && ok "the documented $label ceiling is 1.5x its budget" \
    || bad "the documented $label ceiling is 1.5x its budget (got $doc_ceiling)"
done

# Every exempt baseline in the script must be named in CLAUDE.md with the same number.
while read -r name base; do
  grep -q "\`$name\` ($base)" "$ROOT/CLAUDE.md" \
    && ok "CLAUDE.md records the $name ratchet baseline ($base)" \
    || bad "CLAUDE.md records the $name ratchet baseline ($base)"
done < <(awk '/^baseline_for\(\) \{/,/^\}/' "$CHECK" \
           | sed -n 's/^    \([a-z-]\+\))\s*echo \([0-9]\+\) ;;/\1 \2/p')

# --- 9. the index word counts must equal what the budget counts --------------------------------
# Two different counters (python str.split, wc -w) would silently disagree about whether a
# component is over budget.
idx=$(grep -oP '^\| `forge-kit-governance` \| agent \| `ticket-gate` \| v\d+ \| \K\d+' "$ROOT/README.md")
wcw=$(wc -w < "$ROOT/plugins/forge-kit-governance/agents/ticket-gate.md" | tr -d ' ')
[ -n "$idx" ] && [ "$idx" = "$wcw" ] \
  && ok "the index word count equals wc -w ($wcw)" \
  || bad "the index word count equals wc -w (index=$idx wc=$wcw)"

# --- #150: an agent is charged for what it PRELOADS, not just its own file --------------------
# Verified against the installed Claude Code binary (2.1.263): the subagent spawn path renders every
# skill named in `skills:` and pushes it into the agent's message list. So #109's split moved 308
# words from one preloaded file into another and reduced nothing real, while the guard reported a
# win. The metric measured one file; what loads is the file PLUS its companions.
mkdir -p "$FIX/plugins/fix-g/skills/companion"
words 400 "$FIX/plugins/fix-g/skills/companion/SKILL.md" companion
cat > "$FIX/plugins/fix-g/agents/with-companion.md" <<'A'
---
name: with-companion
description: Use when exercising the preload measurement against a fixture agent.
skills:
  - fix-g:companion
---
<!-- with-companion-version: 1 -->
A
# 1800 of its own words is UNDER the 2000 budget, so the old metric said nothing. With a 400-word
# companion it preloads 2200, which is over. That gap is exactly what the old metric could not see,
# and the first version of this fixture used 1500+300, whose total is also under budget: it would
# have passed against the fix as readily as against the bug.
python3 - "$FIX/plugins/fix-g/agents/with-companion.md" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s + ("word " * 1800) + "\n")
PY2
out=$(bash "$CHECK" --root "$FIX" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'with-companion' \
  && ok "an agent's declared companion skill counts toward its size" \
  || bad "an agent is still measured on its own file alone (#150)"
printf '%s' "$out" | grep -qi 'companion\|preload' \
  && ok "and the report says the companion is why" \
  || bad "and the report says the companion is why"

# The companion is still measured on its own too: it is an ordinary component with its own budget.
printf '%s' "$out" | grep -q 'skill companion' \
  && ok "the companion skill is still reported in its own right" \
  || ok "the companion skill is under its own budget, so nothing to report"

# An agent declaring a companion that is not installed must FAIL, not be measured as if it declared
# none. At runtime that shape fails SILENTLY (#124), so the guard is the only thing that can notice.
cat > "$FIX/plugins/fix-g/agents/ghost-companion.md" <<'A'
---
name: ghost-companion
description: Use when exercising an agent whose declared companion is missing.
skills:
  - fix-g:not-installed
---
<!-- ghost-companion-version: 1 -->
A
out=$(bash "$CHECK" --root "$FIX" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "an agent declaring an uninstalled companion fails" \
                || bad "an unresolvable companion was ignored"
printf '%s' "$out" | grep -q 'not-installed' \
  && ok "and names the skill it could not find" || bad "and names the skill it could not find"
rm -f "$FIX/plugins/fix-g/agents/ghost-companion.md"

# An agent that DISPATCHES (its tools declare Agent) is governed by the orchestrator row, not the
# 2000-word agent budget (#150). Membership is mechanical, so a non-dispatching agent of the same
# size must still warn.
cat > "$FIX/plugins/fix-g/agents/dispatcher.md" <<'A'
---
name: dispatcher
description: Use when exercising the orchestrator row against a fixture agent that dispatches.
tools: ["Agent", "Bash"]
---
<!-- dispatcher-version: 1 -->
A
python3 - "$FIX/plugins/fix-g/agents/dispatcher.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s + ("word " * 2500) + "\n")
PY2
out=$(bash "$CHECK" --root "$FIX" 2>&1)
printf '%s' "$out" | grep -q 'orchestrator dispatcher' \
  && bad "2500 words is under the orchestrator budget, so it should say nothing" \
  || ok "a dispatching agent at 2500 words is under the orchestrator budget"
printf '%s' "$out" | grep -q 'subagent dispatcher' \
  && bad "a dispatching agent is not judged against the plain agent budget" \
  || ok "a dispatching agent is not judged against the plain agent budget"
rm -f "$FIX/plugins/fix-g/agents/dispatcher.md"

# A missing resolver must refuse, not measure every agent on its own file and report clean.
mv "$FIX/scripts/forge-adapt-agent-skills.sh" "$FIX/scripts/resolver.hidden"
bash "$CHECK" --root "$FIX" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a missing companion resolver refuses rather than reporting clean" \
               || bad "a missing resolver silently reverted to the old one-file measure"
mv "$FIX/scripts/resolver.hidden" "$FIX/scripts/forge-adapt-agent-skills.sh"

# --- #174: the ALWAYS-ON cost, which is the description and not the body ----------------------
# The budget measured the body for its whole life. The description is what every session pays for
# a component it never invokes, and it was invisible. These cases pin the parser, because a parser
# that misses continuation lines reports a long description as short, and a guard that under-reports
# the thing it was added to reveal is worse than no guard.
DFIX="$FIX/plugins/fix-g/skills/desc-skill/SKILL.md"
mkdir -p "$(dirname "$DFIX")"
desc_len() { bash "$CHECK" --root "$FIX" --descriptions 2>&1 \
  | awk '/Description length/ { f=1 } f && $3 == "desc-skill" { print $1; exit }'; }

cat > "$DFIX" <<'D'
---
name: desc-skill
description: Use when the description sits on one line.
---
<!-- desc-skill-version: 1 -->
body words here
D
got=$(desc_len); want=$(printf '%s' "Use when the description sits on one line." | wc -c | tr -d ' ')
[ "$got" = "$want" ] && ok "a single-line description is measured exactly ($want)"   || bad "a single-line description is measured exactly (want $want, got $got)"

cat > "$DFIX" <<'D'
---
name: desc-skill
description: >
  Use when the description runs across several indented lines,
  because a parser that stops at the first line would report this
  as a fraction of what every session actually pays for it.
---
<!-- desc-skill-version: 1 -->
body words here
D
got=$(desc_len)
[ "$got" -gt 150 ] && ok "a three-line block description counts every line ($got chars)"   || bad "a three-line block description counts every line (got $got)"

cat > "$DFIX" <<'D'
---
name: desc-skill
description: |
  Use when a block scalar has a blank line in it.

  That blank line is exactly where ticket-gate's real description sits, and a parser
  that stopped there would report the largest always-on cost in this tree as one of
  the smaller ones.
---
<!-- desc-skill-version: 1 -->
body words here
D
got=$(desc_len)
[ "$got" -gt 200 ] && ok "a blank line inside a block scalar does not end the description ($got chars)"   || bad "a blank line inside a block scalar does not end the description (got $got)"

cat > "$DFIX" <<'D'
---
name: desc-skill
---
<!-- desc-skill-version: 1 -->
description: this one is in the BODY, where it is an example rather than metadata
D
out=$(bash "$CHECK" --root "$FIX" 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "a skill with no frontmatter description FAILS rather than reporting zero"   || bad "a skill with no frontmatter description FAILS rather than reporting zero (rc=$rc)"
printf '%s' "$out" | grep -q 'desc-skill' && ok "and names the component" || bad "and names the component"
[ "$(desc_len)" = "0" ]   && ok "a description: line in the BODY is not counted (frontmatter only, as in check-component-scope.sh)"   || bad "a description: line in the BODY is not counted"

cat > "$DFIX" <<'D'
---
name: desc-skill
description:
---
<!-- desc-skill-version: 1 -->
body words here
D
bash "$CHECK" --root "$FIX" >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "an empty description FAILS, for the same reason as a missing one"   || bad "an empty description FAILS, for the same reason as a missing one"

# A COMMAND is exempt from the floor: three of this kit's commands carry no frontmatter at all by
# convention, and a slash command is found by its filename rather than by a description.
rm -f "$DFIX"; rmdir "$(dirname "$DFIX")"
cat > "$FIX/plugins/fix-g/commands/bare.md" <<'D'
<!-- bare-version: 1 -->
A command with no frontmatter, which is how three real ones in this kit are written.
D
bash "$CHECK" --root "$FIX" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "a command with no frontmatter does not fail the floor"   || bad "a command with no frontmatter does not fail the floor"
rm -f "$FIX/plugins/fix-g/commands/bare.md"

# The tree total must be reported, or the cost stays invisible, which is the whole ticket. Capture
# first and grep after: `set -o pipefail` is on, so a piped run would report the CHECK's status.
tot=$(bash "$CHECK" --root "$FIX" 2>&1)
printf '%s' "$tot" | grep -q 'always-on:' \
  && ok "the run reports the tree's total always-on cost" \
  || bad "the run reports the tree's total always-on cost"

# --- #176: the line count is REPORTED, and must never become a second ratchet -----------------
# Anthropic states one number for a skill body and it is lines. #176 asked whether adapt's fenced
# blocks could move to get under it, classified all 20, and found every one is a step the skill runs
# or a template it emits. Nothing could move, so the line count ships as a visible cross-check. If
# it ever starts failing a build, that is this decision being reversed by accident.
lfix=$(bash "$CHECK" --root "$FIX" --descriptions 2>&1)
printf '%s' "$lfix" | grep -q 'Line count' \
  && ok "the report shows a line count beside the words (#176)" \
  || bad "the report shows a line count beside the words (#176)"

# A component far over the tip, and well inside its word budget: one word per line, so the two
# measures cannot be confused for each other.
cat > "$FIX/plugins/fix-g/agents/long-agent.md" <<'A'
---
name: long-agent
description: Use when checking that a long file is not failed for its line count alone.
---
<!-- long-agent-version: 1 -->
A
# Mostly BLANK lines: 600 lines carrying about 60 words. A reader that measured words instead of
# lines would report ~60 here, so the two quantities cannot be mistaken for each other.
python3 - "$FIX/plugins/fix-g/agents/long-agent.md" <<'PY2'
import sys
rows = ["prose here" if i % 10 == 0 else "" for i in range(600)]
open(sys.argv[1], "a").write("\n".join(rows) + "\n")
PY2
want_lines=$(wc -l < "$FIX/plugins/fix-g/agents/long-agent.md" | tr -d ' ')
got_lines=$(bash "$CHECK" --root "$FIX" --descriptions 2>&1 \
  | awk '/Line count/ { f=1 } f && $3 == "long-agent" { print $1; exit }')
[ "$want_lines" = "$got_lines" ] \
  && ok "the reported line count equals wc -l ($want_lines)" \
  || bad "the reported line count equals wc -l (want $want_lines, got $got_lines)"
lfix=$(bash "$CHECK" --root "$FIX" --descriptions 2>&1); rc=$?
printf '%s' "$lfix" | grep -q '500-line tip' \
  && ok "and marks a component over the externally stated tip" \
  || bad "and marks a component over the externally stated tip"
[ "$rc" -eq 0 ] \
  && ok "a 900-line component inside its word budget still passes (the tip is not a gate)" \
  || bad "a 900-line component inside its word budget still passes (the tip became a gate)"
rm -f "$FIX/plugins/fix-g/agents/long-agent.md"

grep -q "all 20 fenced blocks were classified" "$CHECK" || grep -qi "classified before any" "$CHECK" \
  && ok "the guard records why adapt's blocks cannot move" \
  || bad "the guard records why adapt's blocks cannot move"

# --- #170: the recorded cross-check must stay dated, or it is an undated claim -----------------
# The outcome of #170 was to KEEP the word count and record `claude plugin details` as a note. A
# note nobody can date is the shape this repo keeps finding: a measurement that reads as current
# and describes a CLI version nobody has run in a year. So the block must name a version and a
# date, and this case is what makes deleting either of them a build failure rather than a tidy-up.
grep -q "claude plugin details" "$CHECK" \
  && ok "the guard records the plugin details cross-check (#170)" \
  || bad "the guard records the plugin details cross-check (#170)"
grep -qE "MEASURED [0-9]{4}-[0-9]{2}-[0-9]{2} against CLI version [0-9]+\.[0-9]+\.[0-9]+" "$CHECK" \
  && ok "and dates it, naming the CLI version it was measured against" \
  || bad "and dates it, naming the CLI version it was measured against"

echo ""
echo "component-size tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
