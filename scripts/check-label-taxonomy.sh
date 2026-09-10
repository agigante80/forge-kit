#!/usr/bin/env bash
# The area label set has ONE definition, and this fails the build when a copy disagrees (#188).
#
#   check-label-taxonomy.sh [ROOT]
#   exit 0  every copy agrees with the canonical set
#   exit 1  a copy disagrees, and both sides are named
#   exit 2  the guard could not run
#
# WHY. The first live run of the ticket gate in this repository blocked on the first ticket it was
# pointed at, and the reason was drift nobody had noticed. The area set was stated in four places
# and three of them disagreed:
#
#   docs/guides/labels.md          api privacy web mobile backend database          (canonical)
#   check-ticket-mechanics.sh      api privacy web mobile backend database          (agreed)
#   ticket-gate.md Step 0b         api web mobile backend frontend infrastructure   (three errors)
#   .github/labels.yml             the six, and nothing said so
#
# Step 0b omitted `privacy` and `database`, which are declared areas. It added `frontend`, which
# has never been a declared label, a fact check-ticket-mechanics.sh already recorded in its own
# comment while the gate carried on naming it. And it added `infrastructure`, which labels.md
# declares a TYPE. So the gate's blocking step and the gate's own mechanical checks applied
# different definitions of the same word, and neither matched the document that is canonical.
#
# THE FIX WAS TO REMOVE A COPY, NOT TO SYNCHRONISE ONE. Step 0b now points at labels.md and states
# no set at all, which is why this guard checks three files rather than four. That is the cheaper
# shape wherever it is available: a copy that does not exist cannot drift.
#
# WHAT IT COMPARES:
#   docs/guides/labels.md      the Area labels table, and it is canonical
#   .github/labels.yml         what sync-labels.sh puts on the host
#   check-ticket-mechanics.sh  the AREA_LABELS default the gate passes to the mechanical checks
#
# WHAT IT DOES NOT DO. It says nothing about TYPE or PRIORITY labels, which have no second copy to
# drift against, and nothing about whether the host actually carries them. That second one is
# sync-labels.sh --check, and it is a different question: this asks whether the repo agrees with
# itself, that one asks whether the forge agrees with the repo. #104 is what happens when only one
# of those is asked.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
cd "$ROOT" || { echo "check-label-taxonomy: no such directory: $ROOT" >&2; exit 2; }

DOC=docs/guides/labels.md
YML=.github/labels.yml
MECH=plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh

for f in "$DOC" "$YML" "$MECH"; do
  [ -f "$f" ] || { echo "check-label-taxonomy: $f is missing, so nothing can be compared." >&2; exit 2; }
done

# The canonical set: the rows of the Area labels table, in order, read as `| \`name\` |`.
canon=$(awk '
  /^### Area labels/ { inside = 1; next }
  inside && /^### / { exit }
  inside && /^\| `/ { gsub(/^\| `/, ""); sub(/`.*/, ""); print }
' "$DOC")
[ -n "$canon" ] || { echo "check-label-taxonomy: no Area labels table found in $DOC. It is the definition, so an empty read is an error rather than agreement." >&2; exit 2; }

fails=0
report() {  # report <source> <set>
  echo "  $1:" >&2
  diff <(printf '%s\n' "$canon" | sort) <(printf '%s\n' "$2" | sort) \
    | sed -n 's/^< /      only in labels.md: /p; s/^> /      only here: /p' >&2
}

# 1. labels.yml must DECLARE every canonical area. It may carry more (types, priorities), so this
#    is containment rather than equality: an area the host never gets is the #104 failure.
missing_yml=""
while IFS= read -r l; do
  [ -n "$l" ] || continue
  grep -q "^- name: $l\$" "$YML" || missing_yml="${missing_yml}${missing_yml:+ }$l"
done <<< "$canon"
if [ -n "$missing_yml" ]; then
  echo "check-label-taxonomy: $YML declares no entry for: $missing_yml" >&2
  echo "  sync-labels.sh reads that file, so an area missing there never reaches the host." >&2
  fails=$((fails + 1))
fi

# 2. AREA_LABELS in the mechanical checks must EQUAL the canonical set. It is the value the gate
#    passes when it does not override, so a difference here is a check judging a different taxonomy.
mech=$(grep -oP '^AREA_LABELS="\K[^"]+' "$MECH" | head -1 | tr ' ' '\n')
if [ -z "$mech" ]; then
  echo "check-label-taxonomy: no AREA_LABELS default found in $MECH" >&2
  fails=$((fails + 1))
elif [ "$(printf '%s\n' "$canon" | sort)" != "$(printf '%s\n' "$mech" | sort)" ]; then
  echo "check-label-taxonomy: AREA_LABELS in check-ticket-mechanics.sh disagrees with $DOC." >&2
  report "check-ticket-mechanics.sh" "$mech"
  fails=$((fails + 1))
fi

# 3. ticket-gate.md must NOT restate the set. The copy that used to live there is what drifted, and
#    the fix was deletion, so its return is the regression this catches.
GATE=plugins/forge-kit-governance/agents/ticket-gate.md
if [ -f "$GATE" ]; then
  n=$(grep -c '`api`.*`web`\|`api`.*`backend`' "$GATE")
  if [ "$n" -ne 0 ]; then
    echo "check-label-taxonomy: $GATE appears to restate the area set again." >&2
    echo "  Step 0b points at $DOC on purpose (#188). A copy that does not exist cannot drift." >&2
    fails=$((fails + 1))
  fi
fi

if [ "$fails" -ne 0 ]; then
  echo "" >&2
  echo "check-label-taxonomy: $fails disagreement(s). $DOC is canonical; change it first." >&2
  exit 1
fi

echo "check-label-taxonomy: $(printf '%s\n' "$canon" | grep -c .) area labels, and every copy agrees."
