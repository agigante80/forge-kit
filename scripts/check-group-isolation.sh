#!/usr/bin/env bash
# check-group-isolation.sh: forge-kit-roadmap is OPTIONAL, and this is what keeps that true.
#
# WHY. Rolling wave planning is one opinionated method. The rest of the kit is
# methodology-agnostic: a ticket gate governs a ticket, release-automation governs a version,
# forge-host governs a host, and none of them care how work is grouped. A single convenient
# reference from another group would make the roadmap group optional on paper and mandatory in
# practice. A boundary that is only stated survives exactly until someone needs that reference.
#
# In particular ticket-gate must never learn what a phase is. "Has a phase assigned" LOOKS like a
# ticket-readiness property and is the obvious line to add; adding it couples the gate to this
# methodology.
#
# THE DEPENDENCY RUNS ONE WAY. The roadmap group referring to forge-lib.sh is the declared
# dependency and is fine. This guard only looks for references INTO the group.
#
# IT KEYS ON IDENTIFIERS, never on the English word "roadmap", which appears innocently across the
# kit ("our roadmap", "the roadmap for this"). Only the component names can indicate a dependency.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
GROUP=forge-kit-roadmap
IDS='forge-kit-roadmap|roadmap-phases|check-phases\.sh|sync-phases\.sh'

# EXACTLY ONE EXEMPTION, AND IT CARRIES ITS REASON. forge-kit-adapt is the INSTALLER: it names every
# component in the kit by definition, so a mention there is a catalogue entry rather than a
# dependency. The reason is required here for the same purpose check-restatements.sh requires one:
# an allowlist without a stated reason is one that grows by argument.
EXEMPT_PATH='plugins/forge-kit-adapt/'
EXEMPT_REASON='forge-kit-adapt is the installer and names every component by definition'

[ -d "$ROOT/plugins" ] || { echo "check-group-isolation: no plugins/ under $ROOT" >&2; exit 2; }

hits="$(
  find "$ROOT/plugins" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.json' \) \
       -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do
      rel="${f#"$ROOT"/}"
      case "$rel" in
        plugins/"$GROUP"/*) continue ;;       # the group may of course name itself
        "$EXEMPT_PATH"*)    continue ;;
      esac
      grep -nE "$IDS" "$f" 2>/dev/null | sed "s|^|$rel:|"
    done
)"

if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo ""
  echo "check-group-isolation: $GROUP is referenced from outside itself."
  echo "It is an OPTIONAL plugin group and nothing else may depend on it: rolling wave planning is"
  echo "one method, and the rest of the kit must work for a project that declines it."
  echo "Remove the reference. (Exempt: $EXEMPT_PATH, because $EXEMPT_REASON.)"
  exit 1
fi
exit 0
