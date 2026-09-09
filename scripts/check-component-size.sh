#!/usr/bin/env bash
# Component size budget (issue #97). Warns above budget, fails above a hard ceiling, and holds
# already-oversized components to a ratchet so they can shrink but never grow.
#
# WHY A SIZE BUDGET. Not aesthetics. Three review rounds on ticket-gate.md produced findings that
# were all symptoms of size rather than of any single edit: the same rule stated in four places and
# updated in two, a 21-line bullet carrying seven rules, and rules drifting from the steps they
# govern 400 lines away. None of those is fixed by "be more careful"; a budget makes them
# structurally less likely. The context-window research often cited here is weaker than it looks
# ("lost in the middle" is about retrieval, and at least one study finds no position effect for
# instruction following), so the justification is this repo's own defect record first.
#
# It is a SMELL DETECTOR, not a quality metric. A 2,000-word file can still state one rule three
# times. Treat a warning as a prompt to look for duplication, never as a reason to compress prose
# until it is dense but unclear.
#
# ---------------------------------------------------------------------------------------------
# THE ALWAYS-ON COST, MEASURED AND RECORDED (#174).
#
# MEASURED 2026-09-10, CLI 2.1.267, 39 prose components in this tree: 14,711 characters of
# description before the review below, roughly 3,677 tokens paid in every session with all eight
# groups enabled. `claude plugin details` put forge-kit-governance's always-on cost at ~771 tokens
# for six components, which is the same order and is how the character count was sanity checked.
#
# THE REVIEW, and what it changed. Eleven descriptions were over 500 characters. Ten were
# shortened and one was kept:
#
#   ticket-gate 1073 -> 568   adapt 819 -> KEPT   dep-auditor 712 -> 564
#   release-automation 710 -> 384   find-dead-code 627 -> 409   forge-host 614 -> 380
#   mutation-sweep 596 -> 468   coding-standards-auditor 568 -> 341   health-check 557 -> 397
#   privacy-regime 522 -> 395   github-to-forgejo 514 -> 285
#
# Tree total 14,711 -> 12,339 characters, about 590 tokens per session. NOTHING WAS COMPRESSED.
# Every cut was a sentence describing HOW the component works, which its body already said; the
# bodies were checked one by one before the cuts were made. All 48 quoted trigger phrases survive,
# verified mechanically before and after, because a description is a discovery mechanism first and
# a cost second, and a component nobody finds costs its description and delivers nothing.
#
# `adapt` WAS KEPT AT 819 deliberately: almost all of it is trigger material (the secondary mode
# names a user actually types, "refresh", "drift", "contributions", "templates", "upgrade-audit"),
# and the one mechanism clause it carries is what distinguishes it from a copy-paste installer.
# Shortening it would have traded discovery for tokens, which is the trade this ticket forbids.
#
# WHY NO THRESHOLD. A description that is too short stops the component being found, and that
# failure is worse and quieter than a few hundred tokens, so a number to hit would push authors
# the wrong way. The floor is enforced instead: an agent or skill with no description, or an empty
# one, fails. Re-measure and update the numbers above when the tree has moved enough to matter.
# ---------------------------------------------------------------------------------------------
# CROSS-CHECK AGAINST `claude plugin details`, AND WHY IT IS NOT THE METRIC (#170).
#
# The CLI reports a projected token cost per component in two columns, always-on and on-invoke,
# which is the quantity this word count has been approximating since #97. It was probed rather
# than adopted, and it fails the one question that matters here.
#
# QUESTION 1, AND THE ANSWER THAT DECIDED IT. Does it charge an agent for the companion skills it
# PRELOADS? No. Probed on 2.1.267: a throwaway agent declaring one companion, with the companion
# grown from 14 words to 5,000, moved the companion's own on-invoke figure from `< 20` to `~7.2k`
# and left the declaring agent at `~40` throughout. #150 established, against the spawn path
# itself, that every declared skill is rendered into the agent before it runs. So the two measures
# disagree about the quantity #150 was fought over, and ours is the one that matches the verified
# behaviour. Adopting the CLI's number would silently undo that phase.
#
# QUESTION 2. Stable enough to gate a build on? No. It rounds to two significant figures and has a
# `< 20` floor, so a ratchet on it could not see a 200-word edit, and a tokenizer change under it
# would move every number at once for reasons unrelated to this repo.
#
# QUESTION 3. Available without an install or a network round trip? Yes, and this was the one
# favourable answer: `claude --plugin-dir <group> plugin details <group>` reports on a checkout
# with nothing installed. That is what makes a periodic cross-check possible at all.
#
# So: KEEP the word count as the enforced metric, and keep this comparison as a note. Nothing in
# this script reads it, which is deliberate: a cross-check that could fail a build would be an
# adoption wearing a note's clothes, and the governance layer must not grow a hard dependency on
# the `claude` CLI.
#
# MEASURED 2026-09-10 against CLI version 2.1.267, `claude --plugin-dir plugins/<group> plugin
# details <group>` on this tree:
#
#   component              our words   CLI on-invoke   tokens per word
#   adapt                       7314          ~12.7k              1.74
#   ticket-gate (file only)     5264           ~8.4k              1.60
#   ticket-gate-reference        514            ~650              1.26
#   full-review                 3998           ~7.3k              1.83
#
# Two things to read from it. The ratio sits near 1.7, so a word budget and a token budget rank
# components the same way, which is why the proxy has been serviceable. And ticket-gate's enforced
# number here is 5778, the file PLUS its companion, while the CLI's is 8.4k for the file ALONE:
# that gap is question 1, not a rounding difference. Re-measure when the divergence is worth
# knowing again, and update the date and the version above when you do.
# ---------------------------------------------------------------------------------------------
# Usage: check-component-size.sh [--root DIR] [--quiet] [--descriptions]
#   exit 0  every component within budget, or only warnings
#   exit 1  something exceeded the hard ceiling, an exempt component grew past its baseline, or an
#           agent or skill has no description
#   --descriptions  also print every component's description length, largest first
#
# TWO COSTS, AND THIS GUARD MEASURES BOTH (#174). The word count above is the ON-INVOKE cost: the
# body, loaded when a component actually fires. The ALWAYS-ON cost is the description, loaded in
# every session where the group is enabled so the model can decide whether the component is
# relevant. The budget governed only the first for its whole life and was silent about the one you
# pay for installing a component and never using it.
#
# THE ALWAYS-ON HALF IS REPORTED, NOT BUDGETED, and that is deliberate. A description that is too
# short stops the component being found, and an uninvoked component costs its description and
# delivers nothing, so discovery beats economy here and a number to hit would push authors the
# wrong way. What IS enforced is the floor: an agent or skill with no description at all, or an
# empty one, FAILS, because that component can never be selected.
set -uo pipefail

ROOT="."
QUIET=0
DESCTABLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    --descriptions) DESCTABLE=1; shift ;;
    *) echo "check-component-size: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------------
# THE BUDGET TABLE IS AUTHORITATIVE HERE, and CLAUDE.md documents the same numbers. They are kept
# honest by scripts/test-component-size.sh, which fails if the two disagree, because a policy
# stated in prose that nothing applies is the exact defect this repo keeps finding (see #104).
#
# Numbers chosen from current reality, not aspiration: with these, 5 of 33 prose components are
# over budget and 3 over the ceiling, which is a signal worth reading rather than noise.
# The hard ceiling is 1.5x the budget.
# ---------------------------------------------------------------------------------------------
# AN ORCHESTRATOR HAS ITS OWN NUMBER, and the number is stated rather than left as an exemption
# (#150). An agent that DISPATCHES other agents carries two things a single-purpose agent does not:
# the briefs it sends, which must travel with the dispatch or the callee depends on a copy that can
# drift, and the rules it obeys while coordinating. The 2000-word budget was set for an agent that
# does one job, and applying it to a coordinator produced a permanent breach that meant nothing.
#
# 4000 and a 6000 ceiling, keeping the 1.5x relationship every other row uses. Membership is
# MECHANICAL, not a list: an agent whose `tools:` frontmatter declares `Agent` is one, because that
# is what lets it dispatch. Today that is ticket-gate alone.
#
# The ratchet still applies on top. The ceiling says what the ROLE may cost; the ratchet says THIS
# instance may not drift upward. An exemption without a number was what nobody wanted to say out
# loud, and this says it.
is_orchestrator() {
  [ "$2" = subagent ] || return 1
  awk 'NR==1 && $0 != "---" { exit 1 } NR>1 && $0 == "---" { exit 1 } /^tools:.*"Agent"/ { found=1; exit 0 }
       END { exit found ? 0 : 1 }' "$1"
}

# --- the ALWAYS-ON cost: a component's description (#174) --------------------------------------
#
# THE FAILURE THIS PARSER EXISTS TO AVOID. A reader that stops at the first blank line reports
# ticket-gate's 1,073-character block-scalar description as 497, so the guard would call the
# largest always-on cost in the tree one of the smaller ones. Block scalars (`|`, `>`), quoted
# inline scalars and plain indented continuations all have to work.
#
# FRONTMATTER ONLY, matching check-component-scope.sh's rule: a `description:` in the BODY is an
# example, and counting it would let a component inflate or deflate its own measured cost from its
# own documentation.
desc_of() {
  awk '
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && !collecting && /^---[[:space:]]*$/ { exit }
    infm && !collecting && /^description:[[:space:]]*/ {
      val = $0; sub(/^description:[[:space:]]*/, "", val)
      if (val ~ /^[|>][-+]?[[:space:]]*$/) { collecting = 1; next }
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      out = val; collecting = 1; next
    }
    collecting {
      if ($0 ~ /^[[:space:]]*$/) { next }
      if ($0 ~ /^[[:space:]]+[^[:space:]]/) {
        line = $0; sub(/^[[:space:]]+/, "", line)
        out = (out == "" ? line : out " " line); next
      }
      exit
    }
    END { gsub(/[[:space:]]+$/, "", out); printf "%s", out }
  ' "$1"
}

budget_for() {
  case "$1" in
    orchestrator) echo 4000 ;;
    subagent) echo 2000 ;;
    command)  echo 2000 ;;
    skill)    echo 2500 ;;
    *)        echo 0 ;;      # hooks and shell assets are code; a word budget is meaningless
  esac
}

# EXEMPTIONS ARE A RATCHET, NOT A PASS. Each records the component's size when the budget landed.
# An exempt component may shrink freely and may not grow by a single word. Retrofitting these is
# deliberately out of scope here (#150 tracks ticket-gate); the ratchet stops the debt growing
# while that waits. Lower a baseline when a component shrinks, so the gain is locked in.
#
# RAISED 2026-09-10, THE SECOND RAISE EVER, BY MAINTAINER DECISION: adapt 7300 to 7314 (#172).
# The drift report needed one line naming the marketplace staleness check, and there was nothing
# left to pay with: #157, #166 and #167 each searched this file for duplication and each funded
# itself out of what it found. The change is not unpaid, it is underpaid. It already carries 30
# words of payment (a #64 restatement that #167 had moved into forge-adapt-drift-status.sh) and
# its own new prose was compressed from 47 words to 24 before the raise was asked for. The #149
# lever was used first and is why the rule itself lives in forge-adapt-marketplace-status.sh
# rather than here. An agent must NEVER raise a baseline on its own initiative. Ask.
#
# LOWERED 2026-09-10: ticket-gate 5778 to 5709 (#174). Its description was 1,073 characters, the
# largest always-on cost in the tree, and about a third of it enumerated the agent's own workflow
# and repeated it again inside the <example> commentary. Both are in the body already. Every
# trigger phrase survives, which is the only thing that could have made this a loss: a description
# is a discovery mechanism first and a cost second.
#
# LOWERED 2026-09-09: ticket-gate 5782 to 5778 (#103). The round table replaced six scattered
# re-run policies and two void triggers, and paid for itself: the table is bigger than any one of
# them, and removing a DUPLICATE pointer to it covered the difference. Nothing was compressed to
# make this fit, which the budget's own rationale warns against.
#
# LOWERED 2026-09-09: ticket-gate 6355 to 5782 (#150). The companion skill's read-once artifacts
# moved into references/, which are NOT preloaded, so this is a real reduction in what every run
# loads rather than a relocation. 582 words, and no capability was given up for them.
#
# RE-DERIVED 2026-09-09 UNDER A CHANGED METRIC, NOT RAISED: ticket-gate 5259 to 6355 (#150). The
# file did not grow by one word. The measure changed to include what the agent PRELOADS, which is
# its own 5259 plus ticket-gate-reference's 1096, and 6355 is what has been loading all along. The
# old number was not a smaller file, it was a smaller question.
#
# This distinction is the whole point: a raise lets a file grow, and an agent must never do one on
# its own initiative. A re-derivation measures the same thing honestly, and the maintainer
# authorised this one after the preload behaviour was verified against the installed binary.
#
# LOWERED 2026-09-09: adapt 7311 to 7300 (#167). The drift status rules became
# forge-adapt-drift-status.sh, so the new `registered` state had somewhere to live. Same lever as
# #166 and #149, and the third time this week that converting a rule to a tested script was the
# only way to add one without asking for a baseline.
#
# LOWERED 2026-09-09: adapt 7312 to 7311 (#166). The scope rule was measured as prose first: +118
# words, tightened to about +40, with no duplication left to pay with (the one repeated shingle is
# two shell snippets in different execution contexts, the #112 shape). Converting it to a tested
# script instead is the #149 lever, and it SHRANK the file rather than needing a baseline nobody
# authorised.
#
# LOWERED 2026-09-09: ticket-gate 5265 to 5259 (#163). Five `--repo {{GITHUB_REPO}}` uses became
# `--repo "$REPO"`, which is word-neutral, and two prose claims about a placeholder fallback were
# deleted because after the change there is no fallback to describe. A reduction, so the baseline
# follows it down.
#
# LOWERED 2026-09-08: adapt 7316 to 7312 (#157). Its drift table enumerated four shell assets by
# name, which was already missing a fifth; naming the catalogue's `asset:` rows instead is shorter
# AND cannot go stale again. That is what paying for a change out of duplication looks like.
#
# RAISED 2026-09-07, THE FIRST OF THE TWO, BY MAINTAINER DECISION. ticket-gate went 5209 to 5265 for #147, a
# correctness fix that could not be paid for: a seven-shingle scan of the file found no remaining
# duplication after seven consecutive fixes had each paid their own way, and the alternative was
# compressing prose that is already dense, which this budget exists to discourage rather than
# cause. Recorded here because the history is the evidence for #150: apart from the two raises
# above, every edit to these numbers has been a reduction, and an agent must NEVER raise one on
# its own initiative. Ask.
baseline_for() {
  case "$1" in
    adapt)       echo 7314 ;;
    ticket-gate) echo 5709 ;;
    full-review) echo 3998 ;;
    *)           echo 0 ;;
  esac
}

CATALOGUE="$ROOT/scripts/forge-adapt-catalogue.sh"
RESOLVER="$ROOT/scripts/forge-adapt-agent-skills.sh"
if [ ! -f "$CATALOGUE" ]; then
  echo "check-component-size: no catalogue script at $CATALOGUE" >&2
  exit 2
fi

fails=0
warns=0
checked=0
desc_total=0
desc_rows=""

while IFS=$'\t' read -r group ctype name version path; do
  [ -n "${name:-}" ] || continue
  effective="$ctype"
  is_orchestrator "$path" "$ctype" && effective=orchestrator
  budget=$(budget_for "$effective")
  [ "$budget" -gt 0 ] || continue          # skip hooks and shell assets
  [ -f "$path" ] || continue
  words=$(wc -w < "$path" | tr -d ' ')

  # THE ALWAYS-ON COST. A COMMAND is exempt from the floor rather than forgiven: three of this
  # kit's commands carry no frontmatter at all, by convention (the name comes from the filename),
  # and a slash command is found by that name rather than by a description. An agent or a skill is
  # selected by its description and by nothing else, so for those an empty one is a defect.
  dlen=$(desc_of "$path" | wc -c | tr -d ' ')
  desc_total=$((desc_total + dlen))
  desc_rows="${desc_rows}${dlen}\t${ctype}\t${name}\n"
  if [ "$ctype" != command ] && [ "$dlen" -eq 0 ]; then
    echo "FAIL  $ctype $name: no description in its frontmatter, so nothing can ever select it."
    echo "      An empty always-on cost is not a saving: the component is invisible."
    fails=$((fails + 1))
  fi

  # AN AGENT IS CHARGED FOR WHAT IT PRELOADS (#150). Verified against the installed Claude Code
  # (2.1.263): the subagent spawn path renders every skill named in `skills:` frontmatter and pushes
  # it into the agent's message list before the run starts. So a companion skill is not somewhere
  # else, it is in the same context.
  #
  # Measuring one file made #109's split look like a reduction when it moved 308 words from one
  # preloaded file into another. The number was smaller and nothing had been reduced. This is the
  # metric change the maintainer authorised rather than a baseline raise: the baselines below are
  # re-derived under the new measure, which is a different thing from letting a file grow.
  #
  # It reuses forge-adapt-agent-skills.sh rather than parsing frontmatter here, because that parser
  # is tested and a fourth copy of it is what #162 was about. A resolver failure is LOUD: an agent
  # whose companions cannot be resolved is reported rather than measured as if it declared none.
  companions=""
  if [ "$ctype" = subagent ]; then
    # A MISSING RESOLVER IS AN ERROR, not a quiet skip. Skipping would measure every agent on its
    # own file again and report the tree clean, which is the vacuous pass this metric change exists
    # to remove.
    [ -f "$RESOLVER" ] || {
      echo "check-component-size: $RESOLVER is missing, so what an agent preloads cannot be" >&2
      echo "  resolved and no agent can be measured. Refusing rather than reporting clean." >&2
      exit 2
    }
  fi
  if [ "$ctype" = subagent ]; then
    if decl=$(bash "$RESOLVER" "$path" 2>/dev/null); then
      for ref in $decl; do
        cname="${ref##*:}"
        cfile="$(find "$ROOT" -path "*/skills/$cname/SKILL.md" -type f 2>/dev/null | head -1)"
        if [ -n "$cfile" ]; then
          words=$(( words + $(wc -w < "$cfile" | tr -d ' ') ))
          companions="${companions:+$companions, }$cname"
        else
          echo "FAIL  $ctype $name: declares companion skill '$ref', which is not installed."
          echo "      It cannot be measured, and at runtime it fails SILENTLY (#124)."
          fails=$((fails + 1))
        fi
      done
    else
      echo "FAIL  $ctype $name: its 'skills:' frontmatter could not be parsed, so what it preloads"
      echo "      is unknown and its size cannot be judged."
      fails=$((fails + 1))
      continue
    fi
  fi
  checked=$((checked + 1))
  ceiling=$(( budget * 3 / 2 ))
  baseline=$(baseline_for "$name")

  if [ "$baseline" -gt 0 ]; then
    if [ "$words" -gt "$baseline" ]; then
      echo "FAIL  $ctype $name: $words words${companions:+ (with preloaded companion: $companions)}, above its $baseline-word ratchet baseline."
      echo "      Its ${budget}-word budget (ceiling $ceiling) applies, and the ratchet MAY NOT GROW."
      echo "      Reduce it, or split per the convention in CLAUDE.md."
      fails=$((fails + 1))
    elif [ "$words" -lt "$baseline" ] && [ "$QUIET" -eq 0 ]; then
      echo "note  $ctype $name: $words words, below its $baseline baseline. Lower the baseline in"
      echo "      scripts/check-component-size.sh to lock the reduction in."
    fi
    continue
  fi

  if [ "$words" -gt "$ceiling" ]; then
    echo "FAIL  $ctype $name: $words words${companions:+ (with preloaded companion: $companions)}, over the hard ceiling of $ceiling (budget $budget)."
    fails=$((fails + 1))
  elif [ "$words" -gt "$budget" ]; then
    [ "$QUIET" -eq 1 ] || echo "warn  $effective $name: $words words${companions:+ (with preloaded companion: $companions)}, over the $budget-word budget (ceiling $ceiling)."
    warns=$((warns + 1))
  fi
done < <(bash "$CATALOGUE" --tsv "$ROOT")

if [ "$checked" -eq 0 ]; then
  echo "check-component-size: no prose components found under $ROOT" >&2
  exit 2
fi

if [ "$DESCTABLE" -eq 1 ]; then
  echo ""
  echo "Description length (the always-on cost, characters), largest first:"
  printf '%b' "$desc_rows" | sort -rn | awk 'NF { printf "  %6s  %-10s %s\n", $1, $2, $3 }'
fi

echo ""
echo "check-component-size: $checked components, $warns over budget, $fails failing."
echo "  always-on: $desc_total characters of description across $checked components (roughly $((desc_total / 4)) tokens"
echo "  in a session with every group enabled). Reported, not budgeted: see the header for why, and"
echo "  pass --descriptions for the per-component table."
[ "$fails" -eq 0 ]
