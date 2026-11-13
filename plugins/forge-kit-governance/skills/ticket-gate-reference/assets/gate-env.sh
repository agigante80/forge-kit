# gate-env-version: 6
# gate-env.sh: what each ticket-gate Bash call must rebuild, because every call is a fresh shell
# (#347). SOURCED, never run: Step 0 sources it right after writing $D/mech, and Steps 3A, 5 and 6
# each open with
#
#   D=<scratchpad>/gate-<NUMBER>; . "$(dirname "$(cat "$D/mech")")/gate-env.sh" || exit 2
#
# On success it sets MECH (the checker Step 0 chose), A (its directory) and GS (gate-status.sh),
# sources forge-lib.sh and EXPORTS FORGE_LIB as an absolute path, so count-gate-rounds.sh and
# gate-status.sh, run after it, use the same copy. That also covers a plugin-cache install, where
# their own `../../../../forge-kit-devops` fallback names a path that does not exist. On failure it
# returns 2 with one stderr line and sources nothing. A $D/mech that is missing, empty or names a
# missing file never reaches this file at all: the caller's `. .../gate-env.sh` fails on the path,
# rc 2, nothing sourced; the guard below covers a direct source with D unset.
#
# FORGE_LIB, when set and non-empty, must name a file: an invalid one is REFUSED, never passed over,
# as count-gate-rounds.sh and gate-status.sh refuse it (it is sourced code). Empty means unset.
# Otherwise the search is: beside the checker (a forge-adapt `scripts/` install); a source
# checkout's forge-kit-devops; the highest `forge-lib-version` marker under ~/.claude/plugins, the
# lexically last path breaking a tie. That search splits at the END of each line, so a path holding
# a colon keeps its version (the `sort -t:` it replaces read a colon path as version 0).
#
# v4 (#581): forge_gate_comment is gone. The gate posts NO comment: its review, the synthesis void,
# the clarification questions and the remediation guide are gate-owned body regions written with
# forge_body_region_set, because agents read the body and the forge keeps its edit history.
#
# Needs: bash (sourced from the gate's Bash calls), find, grep, sed, sort.

if [ -z "${D:-}" ] || [ ! -s "$D/mech" ]; then
  echo "ticket-gate: no checker path in ${D:-<unset D>}/mech; run Step 0 first" >&2; return 2
fi
MECH=$(cat "$D/mech"); A=$(dirname "$MECH"); GS=$A/gate-status.sh
[ -f "$MECH" ] || { echo "ticket-gate: $D/mech names $MECH, which does not exist" >&2; return 2; }

if [ -n "${FORGE_LIB:-}" ]; then
  [ -f "$FORGE_LIB" ] || { echo "ticket-gate: FORGE_LIB=$FORGE_LIB is not a file; refusing to fall back" >&2; return 2; }   # gate-env: strict
  _ge_lib=$FORGE_LIB
else
  _ge_lib=$A/forge-lib.sh
  [ -f "$_ge_lib" ] || _ge_lib=$A/../../../../forge-kit-devops/skills/forge-host/assets/forge-lib.sh
  [ -f "$_ge_lib" ] || _ge_lib=$(find "$HOME/.claude/plugins" -name forge-lib.sh -exec grep -m1 -Ho 'forge-lib-version: [0-9]*' {} + 2>/dev/null \
    | sed 's/:forge-lib-version: \([0-9]*\)$/	\1/' | sort -t'	' -k2,2n -k1,1 | tail -1 | cut -f1)   # gate-env: colon-safe
fi
[ -n "$_ge_lib" ] && [ -f "$_ge_lib" ] || { echo "ticket-gate: forge-lib.sh not found (set FORGE_LIB, or install forge-kit-devops)" >&2; return 2; }
_ge_lib=$(CDPATH= cd -- "$(dirname -- "$_ge_lib")" && pwd)/$(basename "$_ge_lib")
. "$_ge_lib" || { echo "ticket-gate: could not source $_ge_lib" >&2; return 2; }
export FORGE_LIB=$_ge_lib   # gate-env: export
unset _ge_lib

# gate_write_review <n>: write "$D/review.md" as the body's `gate-review` region (#581), the ONE
# place the review, the 0c void note and the 1.5 clarification are written, so a body near the
# forge's cap can never lose a write to prose an agent must remember (round 1 review).
# GitHub rejects a body over 65,536 characters. The size that counts is the CURRENT body with its
# gate-review region taken out, plus the new review, plus ~8,000 characters of headroom for Step 6's
# later writes: above 60,000 in all, the review is cut at its `#### Mechanical checks` subsection
# (what stays: heading, issue, date, verdict, and any void note) plus one line saying it was cut.
# Never a comment. Needs $D, forge_issue_view and forge_body_region_set (forge-lib). rc 2 on bad
# input or a read failure; otherwise forge_body_region_set's rc.
gate_write_review() {
  local n=${1-} cur body rest review cut room=52000
  [[ $n =~ ^[0-9]+$ ]] && [ -n "${D-}" ] && [ -s "$D/review.md" ] || { echo "gate_write_review: needs an issue number and a non-empty \$D/review.md" >&2; return 2; }
  cur=$(forge_issue_view "$n") || return 2
  body=$(printf '%s' "$cur" | jq -r '.body // ""') || return 2
  rest=$(printf '%s\n' "$body" | awk '
    { l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l) }
    l == "<!-- gate-review:start -->" { skip = 1; next }
    l == "<!-- gate-review:end -->" { skip = 0; next }
    !skip')
  review=$(cat "$D/review.md")
  if [ $(( ${#rest} + ${#review} )) -gt "$room" ]; then
    cut=$(printf '%s\n' "$review" | awk '/^#### Mechanical checks/ { exit } { print }')
    if [ "${#cut}" -lt "${#review}" ]; then
      review="$cut

Cut: the full review would pass the forge's body size cap. The verdict and the required changes are in the regions below."
    fi
  fi
  forge_body_region_set "$n" gate gate-review "$review"
}
