#!/usr/bin/env bash
# The neighbour boundary, enforced (#177).
#
#   check-neighbour-overlap.sh [ROOT]
#   exit 0  no unallowlisted duplicate; collisions may be reported
#   exit 1  a component here is the same file a neighbour ships, and nothing says why
#   exit 2  the guard could not run
#
# WHY THIS EXISTS. forge-kit's stated reason for existing is to complement superpowers and the
# plugin marketplaces around it: decision #69 gives superpowers the inner loop and forge-kit the
# outer. That line lived in prose inside adapt/SKILL.md, and prose is the one thing this repository
# does not trust anywhere else. check-group-isolation.sh fails a build if anything outside the
# roadmap group so much as NAMES it, to keep one optional group optional; the claim that defines
# the project had nothing at all. Five components had crossed it unnoticed.
#
# TWO VERDICTS, AND THE DIFFERENCE IS THE WHOLE DESIGN.
#   duplicate  the two files are the same file. FAILS, unless an allowlist entry says why.
#   collision  two projects picked the same obvious name. REPORTED, never failed.
# `code-reviewer` is a name anyone would pick, and a guard that treated every shared name as a
# defect would be switched off, which is worse than not having one. The measured gap between the
# two populations is 10 differing lines against 103; see the threshold note in
# scripts/neighbour-manifest.sh, which is where the comparison is actually made.
#
# IT READS ONLY THE CHECKED-IN MANIFEST. Never ~/.claude, never the network, never the `claude`
# CLI. The governance layer stays agent-agnostic and CI has none of those things. The cost is that
# the manifest is only as fresh as the last `neighbour-manifest.sh --refresh`, which is a real
# limit, so an ageing manifest says so loudly rather than passing as if it were current.
#
# WHAT IT CANNOT SEE. A component copied from a neighbour under a DIFFERENT name is invisible to
# it, because every row here is keyed on a shared name. Nothing name-based can catch that, and a
# guard that implied otherwise would be the kind this repository keeps having to fix.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
cd "$ROOT" || { echo "check-neighbour-overlap: no such directory: $ROOT" >&2; exit 2; }

MANIFEST=docs/neighbours.tsv
ALLOW=.neighbour-allow
STALE_DAYS=120

[ -f "$MANIFEST" ] || {
  echo "check-neighbour-overlap: no manifest at $MANIFEST, so nothing can be compared." >&2
  echo "  Run: bash scripts/neighbour-manifest.sh --refresh   (needs the marketplaces installed)" >&2
  exit 2
}

# An allowlist entry REQUIRES a reason, the shape check-restatements.sh already uses. An
# unreasoned exemption is how a temporary licence becomes permanent with nobody able to say why.
declare_allow() { :; }
allow_reason() {
  [ -f "$ALLOW" ] || return 1
  awk -F' :: ' -v n="$1" '!/^[[:space:]]*(#|$)/ && $1 == n { print $2; found=1 } END { exit found ? 0 : 1 }' "$ALLOW"
}
if [ -f "$ALLOW" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in
      *' :: '*)
        r=${line#* :: }
        [ -n "${r// /}" ] || { echo "check-neighbour-overlap: $ALLOW entry '${line%% ::*}' has an empty reason." >&2; exit 2; }
        ;;
      *) echo "check-neighbour-overlap: $ALLOW entry '$line' has no reason. Use: <name> :: <why>" >&2; exit 2 ;;
    esac
  done < "$ALLOW"
fi

measured=$(awk -F'\t' '!/^#/ && $1 != "marketplace" && NF>=9 { print $9; exit }' "$MANIFEST")
if [ -n "$measured" ]; then
  now=$(date +%s)
  then_=$(date -d "$measured" +%s 2>/dev/null || echo "$now")
  age=$(( (now - then_) / 86400 ))
  if [ "$age" -gt "$STALE_DAYS" ]; then
    echo "check-neighbour-overlap: the manifest was measured $age days ago ($measured), over the" >&2
    echo "  $STALE_DAYS-day window. Still checking what it holds, because a stale list is weaker" >&2
    echo "  evidence and not no evidence. Refresh it: bash scripts/neighbour-manifest.sh --refresh" >&2
  fi
fi

fails=0; collisions=0; allowed=0; rows=0
while IFS=$'\t' read -r mkt plug kind name theirs ours differing verdict measured_on; do
  case "$mkt" in ''|\#*|marketplace) continue ;; esac
  rows=$((rows + 1))
  case "$verdict" in
    duplicate)
      if reason=$(allow_reason "$name"); then
        echo "allowed   $kind $name: same file as $plug@$mkt ($differing differing lines). $reason"
        allowed=$((allowed + 1))
      else
        echo "FAIL      $kind $name: this is the same file as $plug@$mkt, differing by $differing line(s)." >&2
        echo "          Retire it and point users at the original, or add an entry to $ALLOW saying why it stays." >&2
        fails=$((fails + 1))
      fi
      ;;
    collision)
      echo "collision $kind $name: $plug@$mkt ships the same NAME, $differing lines apart. Not a defect."
      collisions=$((collisions + 1))
      ;;
    *) echo "check-neighbour-overlap: unknown verdict '$verdict' for $name" >&2; exit 2 ;;
  esac
done < "$MANIFEST"

[ "$rows" -gt 0 ] || { echo "check-neighbour-overlap: the manifest has no rows, which cannot be right." >&2; exit 2; }

echo ""
echo "check-neighbour-overlap: $rows name match(es); $fails unallowed duplicate(s), $allowed allowed, $collisions collision(s)."
[ "$fails" -eq 0 ]
