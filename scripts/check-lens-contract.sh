#!/usr/bin/env bash
# check-lens-contract.sh: the lens result contract cannot drift between its two plugin groups (#103).
#
# THE DEFECT. ticket-gate dispatches the security lens with a result contract in its prompt. That
# fixes what the auditor is ASKED for; it does not fix whether the auditor UNDERSTANDS the ask. The
# two live in different plugin groups (`forge-kit-governance` and `forge-kit-security`), which are
# versioned and installed independently, so they can drift with no signal at all. The failure is
# silent: the lens returns a shape the gate cannot merge, or merges wrongly.
#
# WHAT THIS FIXES, AND WHAT IT DOES NOT. It keeps the SHIPPED pair honest, moving that failure from
# runtime to CI, which is the same trade `check-template-lockstep.sh` makes for the templates and
# the canonical doc: a version that cannot drift needs no runtime check.
#
# It does NOT cover a user's INSTALLED pair. Someone holding governance at one version and security
# at another still has skew, and only a runtime check in the gate can see that. This guard is
# deliberately the cheap half, and saying which half it is matters more than the half itself.
#
# A MISSING MARKER IS SKEW, NOT AGREEMENT. An unmarked file compared against a marked one is exactly
# the shape that reads as "fine" while meaning "unknown", and this repo has been caught by it before
# (#64: every install predating the markers looked current).
set -uo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-lens-contract: not a git checkout and no root given" >&2; exit 2; }
fi

DEF="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/references/lens-definitions.md"
AUD="$ROOT/plugins/forge-kit-security/agents/security-auditor.md"

for f in "$DEF" "$AUD"; do
  [ -r "$f" ] || { echo "check-lens-contract: cannot read '$f'" >&2; exit 2; }
done

ver_of() { grep -oE 'lens-contract-version:[[:space:]]*[0-9]+' "$1" | grep -oE '[0-9]+' | head -1; }

dv="$(ver_of "$DEF")"
av="$(ver_of "$AUD")"

fail=0
[ -n "$dv" ] || { echo "check-lens-contract: no lens-contract-version in ${DEF#"$ROOT"/}" >&2; fail=1; }
[ -n "$av" ] || { echo "check-lens-contract: no lens-contract-version in ${AUD#"$ROOT"/}" >&2; fail=1; }

if [ "$fail" -eq 0 ] && [ "$dv" != "$av" ]; then
  echo "check-lens-contract: the lens result contract has drifted between its two plugin groups." >&2
  echo "  ${DEF#"$ROOT"/}: lens-contract-version $dv" >&2
  echo "  ${AUD#"$ROOT"/}: lens-contract-version $av" >&2
  echo "  Both sides are named on purpose: knowing THAT they differ does not say which to change." >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "  Bump both to the same number when the contract changes, and bump the plugin semver of" >&2
  echo "  each group, since a user installs them independently." >&2
  exit 1
fi

echo "check-lens-contract: the security lens contract is at version $dv on both sides."
exit 0
