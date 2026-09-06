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
# Usage: check-component-size.sh [--root DIR] [--quiet]
#   exit 0  every component within budget, or only warnings
#   exit 1  something exceeded the hard ceiling, or an exempt component grew past its baseline
set -uo pipefail

ROOT="."
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
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
budget_for() {
  case "$1" in
    subagent) echo 2000 ;;
    command)  echo 2000 ;;
    skill)    echo 2500 ;;
    *)        echo 0 ;;      # hooks and shell assets are code; a word budget is meaningless
  esac
}

# EXEMPTIONS ARE A RATCHET, NOT A PASS. Each records the component's size when the budget landed.
# An exempt component may shrink freely and may not grow by a single word. Retrofitting these is
# deliberately out of scope here (#109 covers ticket-gate); the ratchet stops the debt growing
# while that waits. Lower a baseline when a component shrinks, so the gain is locked in.
baseline_for() {
  case "$1" in
    adapt)       echo 7342 ;;
    ticket-gate) echo 5680 ;;
    full-review) echo 3998 ;;
    *)           echo 0 ;;
  esac
}

CATALOGUE="$ROOT/scripts/forge-adapt-catalogue.sh"
if [ ! -f "$CATALOGUE" ]; then
  echo "check-component-size: no catalogue script at $CATALOGUE" >&2
  exit 2
fi

fails=0
warns=0
checked=0

while IFS=$'\t' read -r group ctype name version path; do
  [ -n "${name:-}" ] || continue
  budget=$(budget_for "$ctype")
  [ "$budget" -gt 0 ] || continue          # skip hooks and shell assets
  [ -f "$path" ] || continue
  words=$(wc -w < "$path" | tr -d ' ')
  checked=$((checked + 1))
  ceiling=$(( budget * 3 / 2 ))
  baseline=$(baseline_for "$name")

  if [ "$baseline" -gt 0 ]; then
    if [ "$words" -gt "$baseline" ]; then
      echo "FAIL  $ctype $name: $words words, above its $baseline-word ratchet baseline."
      echo "      This component is exempt from the ${budget}-word budget but MAY NOT GROW."
      echo "      Reduce it, or split per the convention in CLAUDE.md."
      fails=$((fails + 1))
    elif [ "$words" -lt "$baseline" ] && [ "$QUIET" -eq 0 ]; then
      echo "note  $ctype $name: $words words, below its $baseline baseline. Lower the baseline in"
      echo "      scripts/check-component-size.sh to lock the reduction in."
    fi
    continue
  fi

  if [ "$words" -gt "$ceiling" ]; then
    echo "FAIL  $ctype $name: $words words, over the hard ceiling of $ceiling (budget $budget)."
    fails=$((fails + 1))
  elif [ "$words" -gt "$budget" ]; then
    [ "$QUIET" -eq 1 ] || echo "warn  $ctype $name: $words words, over the $budget-word budget (ceiling $ceiling)."
    warns=$((warns + 1))
  fi
done < <(bash "$CATALOGUE" --tsv "$ROOT")

if [ "$checked" -eq 0 ]; then
  echo "check-component-size: no prose components found under $ROOT" >&2
  exit 2
fi

echo ""
echo "check-component-size: $checked components, $warns over budget, $fails failing."
[ "$fails" -eq 0 ]
