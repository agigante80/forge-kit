#!/usr/bin/env bash
# close-shipped-version: 3
# close-shipped.sh: close the tickets a release shipped, or report the ones still open (#496).
# Closing shipped tickets was a step someone had to remember (the `release` skill's step 5), and on
# a two branch model the host's own auto close never fires, because the feature PRs target the
# development branch. This makes the step mechanical, and makes a skipped step visible.
#
# Usage:
#   close-shipped.sh <tag> [--to <ref>]       comment "Released in <tag>" on, then close, every
#                                             open issue the release shipped
#   close-shipped.sh --report <tag>           read only: list shipped issues that are still open
#   close-shipped.sh --report --last <N>      the same for the N highest release tags in the
#                                             repository (run `git fetch --tags` first)
#   close-shipped.sh --help
#
# THE MANIFEST is read from commit SUBJECTS only, `git log --no-merges --pretty=%s <prev>..<end>`,
# over all parents (`--first-parent` would hide feature commits under a merge-commit promotion).
# Only the TRAILING run of groups at the end of a subject counts, each one either `(#N)` (shipped:
# close) or `(refs #N)` (the opt-out: shipped in part, keep open). A `(#N)` anywhere else in a
# subject, and anything in a body (bodies cite CVE and alert numbers), is never read. A number cited
# as `(#N)` anywhere in the range is closed even if another subject cites it as `(refs #N)`. A
# commit reverted inside the same range ships nothing: a subject quoted by a `Revert "<subject>"`
# subject in the range is dropped, once per revert, before the matcher runs. A reapply (git's
# `Reapply "<subject>"`, or a revert of the revert) is dropped with it, so a reapplied ticket needs
# its own trailing `(#N)` on the reapply commit to be closed. NOT detected: reverting a whole
# merged PR (`git revert -m 1`, or the host's Revert button on a --no-ff merge), because that
# revert quotes the MERGE subject, which --no-merges excludes; mark such a ticket with the
# `(refs #N)` opt-out or reopen it by hand (follow-up #498). Close mode and report mode share this
# one matcher, so they cannot disagree. A squash-promoted range
# whose subject carries only a PR number yields that number, which is skipped as a pull request:
# resolving a PR to its linked issues is out of scope.
#
# THE RANGE starts at the highest release tag (TAG_GLOB, default `${TAG_PREFIX}*`, TAG_PREFIX
# default `v`, the defaults version-lib.sh uses) REACHABLE from the range end, excluding the tag
# being released and skipping prereleases and non-semver names. Reachability means a higher tag on
# an unmerged sibling branch is never chosen. A first release (no previous tag) closes nothing; it
# never scans from the root. The range end is the tag; `--to <ref>` names it when the tag does not
# exist yet (release-run.sh's dry-run preview). A missing tag without `--to` is a usage error.
#
# PER TICKET, close mode: view it (404 or 410 is `skip #N: not found`, not a failure); a pull
# request is `skip #N: pull request` and is never written to (decided from the host's
# `.pull_request`, never guessed); a closed issue is skipped silently. An open issue gets the
# comment only if no comment with exactly that body exists, so a run that commented and then
# failed to close converges on rerun with no duplicate; then it is closed. A close is never
# attempted after a failed comment. Every failure prints `::warning::<step> #N failed (rc=R)` and
# the loop goes on; the run exits 1 at the end if any ticket failed. It runs AFTER the tag, so a
# red run means: rerun THIS script by hand (`close-shipped.sh <tag>`), which converges. Never rerun
# the release lane, which would cut another release.
#
# The owner/repo is resolved ONCE, before the first host call, and a failure exits 2 with
# forge-lib's own error: an unresolved repo would otherwise build `repos//issues/N`, which the
# host answers with a 404 that reads as `not found`, a green run that closed nothing.
#
# DRY_RUN=1 (or an inherited FORGE_DRY_RUN=1) still READS, with FORGE_DRY_RUN scoped to 0 on the
# reads so they return real data, and prints `[dry-run] would comment and close #N for <tag>`
# instead of writing. An empty manifest makes no host call at all.
#
# Report mode never writes. It costs one issue read per manifest number per tag, which is fine at
# release scale; a large --last N multiplies it.
#
# Exit: close mode 0 all done, 1 a ticket failed. Report mode 0 nothing open, 1 a released issue is
# still open, 2 a read failed and nothing was found open. Both modes: 2 for usage and environment.
#
# All host calls go through forge-lib.sh (GitHub or Forgejo), resolved as gate-status.sh resolves
# it: FORGE_LIB, else beside this script (a forge-adapt install), else the source checkout's
# forge-host copy. Absent all three it refuses. The token needs issue write: a GitHub App needs
# Issues: Read and write (see references/github-token-gotcha.md).
set -uo pipefail

HERE="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIB="${FORGE_LIB:-}"
if [ -z "$LIB" ]; then
  if [ -f "$HERE/forge-lib.sh" ]; then LIB="$HERE/forge-lib.sh"
  elif [ -f "$HERE/../../forge-host/assets/forge-lib.sh" ]; then
    LIB="$HERE/../../forge-host/assets/forge-lib.sh"
  fi
fi
[ -n "$LIB" ] && [ -f "$LIB" ] || {
  echo "close-shipped: forge-lib.sh not found beside this script (or via FORGE_LIB); refusing." >&2
  exit 2
}

usage() {
  cat <<'EOF'
usage: close-shipped.sh <tag> [--to <ref>]
       close-shipped.sh --report <tag>
       close-shipped.sh --report --last <N>
Close (or, with --report, list) the open issues a release shipped, read from the trailing
(#N) groups of the commit subjects since the previous release tag. (refs #N) keeps a ticket open.
EOF
}

mode=close tag="" to="" last=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --report)  mode=report ;;
    --to)      [ $# -ge 2 ] || { usage >&2; exit 2; }; to="$2"; shift ;;
    --last)    [ $# -ge 2 ] || { usage >&2; exit 2; }; last="$2"; shift ;;
    -*)        echo "close-shipped: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)         [ -z "$tag" ] || { usage >&2; exit 2; }; tag="$1" ;;
  esac
  shift
done
if [ -n "$last" ]; then
  case "$last" in ''|0|*[!0-9]*) echo "close-shipped: --last needs a positive integer" >&2; exit 2 ;; esac
  [ "$mode" = report ] && [ -z "$tag" ] && [ -z "$to" ] \
    || { echo "close-shipped: --last is a report option and takes no tag" >&2; exit 2; }
elif [ -z "$tag" ]; then
  usage >&2; exit 2
fi
[ -z "$to" ] || [ "$mode" = close ] || { echo "close-shipped: --to is a close-mode option" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || { echo "close-shipped: not inside a git repository" >&2; exit 2; }

# shellcheck source=/dev/null
. "$LIB"

TAG_PREFIX="${TAG_PREFIX:-v}"
TAG_GLOB="${TAG_GLOB:-${TAG_PREFIX}*}"
DRY=0
[ "${DRY_RUN:-0}" = 1 ] && DRY=1
[ "${FORGE_DRY_RUN:-0}" = 1 ] && DRY=1

WORK="$(mktemp -d)" || { echo "close-shipped: cannot create a temp directory" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# _is_release <tag>: true for <prefix>X.Y.Z with optional +build; a prerelease (-...) is not one.
_is_release() {
  local v="${1#"$TAG_PREFIX"}"
  [ "$v" != "$1" ] || [ -z "$TAG_PREFIX" ] || return 1
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+.*)?$ ]]
}

# prev_tag <end> <self>: the highest release tag reachable from <end>, other than <self>.
prev_tag() {
  local t
  while IFS= read -r t; do
    [ -n "$t" ] && [ "$t" != "$2" ] && _is_release "$t" && { printf '%s\n' "$t"; return 0; }
  done < <(git tag --merged "$1" --list "$TAG_GLOB" --sort=-v:refname 2>/dev/null)
  return 0
}

# manifest <range>: one line per cited number, `close N` or `refs N`, deduplicated, close winning.
# THE one matcher: only the trailing run of `(#N)` / `(refs #N)` groups of each subject.
manifest() {
  local s re='^(.*)\((refs #|#)([0-9]+)\)[[:space:]]*$'
  git log --no-merges --pretty=%s "$1" -- | _drop_reverted | while IFS= read -r s; do
    while [[ "$s" =~ $re ]]; do
      if [ "${BASH_REMATCH[2]}" = "#" ]; then echo "close $((10#${BASH_REMATCH[3]}))"
      else echo "refs $((10#${BASH_REMATCH[3]}))"; fi
      s="${BASH_REMATCH[1]}"
      s="${s%"${s##*[![:space:]]}"}"
    done
  done | sort -u -k2,2n -k1,1 | awk '!seen[$2]++'   # `close` sorts before `refs`, so close wins
}

# _drop_reverted: stdin subjects minus every subject a `Revert "<subject>"` line quotes, once per
# revert. The quoted subject runs from after `Revert "` to the LAST double quote, so a squash
# suffix such as ` (#25)` after it is not part of it. POSIX awk only.
_drop_reverted() {
  awk '
    { s[NR] = $0
      if (substr($0, 1, 8) == "Revert \"") {
        r = substr($0, 9); q = 0
        for (j = length(r); j > 0; j--) if (substr(r, j, 1) == "\"") { q = j; break }
        if (q > 0) rev[substr(r, 1, q - 1)]++
      } }
    END { for (k = 1; k <= NR; k++) { if (rev[s[k]] > 0) { rev[s[k]]--; continue }; print s[k] } }'
}

# need_repo: resolve owner/repo once, before the first host call; exit 2 with forge-lib's error.
need_repo() {
  [ -z "${_REPO_OK:-}" ] || return 0
  FORGE_REPO="$(forge_repo)" || { echo "close-shipped: cannot resolve owner/repo; set FORGE_REPO or an origin remote" >&2; exit 2; }
  export FORGE_REPO; _REPO_OK=1
}

# view <n>: sets V to notfound | pr | closed | open | fail, and VRC to the read's exit code.
view() {
  local out rc=0 st pr
  out="$(FORGE_DRY_RUN=0 forge_issue_view "$1" 2>"$WORK/err")" || rc=$?
  VRC=$rc
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 44 ] || grep -Eq 'HTTP (404|410)' "$WORK/err"; then V=notfound; return 0; fi
    cat "$WORK/err" >&2; V=fail; return 0
  fi
  st="$(jq -r '.state // empty' <<< "$out" 2>/dev/null)"
  pr="$(jq -r 'if .pull_request == null then "no" else "yes" end' <<< "$out" 2>/dev/null)"
  if [ "$pr" = yes ]; then V=pr
  elif [ "$st" = closed ]; then V=closed
  elif [ "$st" = open ]; then V=open
  else cat "$WORK/err" >&2; V=fail
  fi
}

release_one() {   # release_one <tag> <end> <label>: one tag's manifest and actions; updates counters
  local tag="$1" end="$2" label="$3" prev m n kind body rc has
  prev="$(prev_tag "$end" "$tag")"
  if [ -z "$prev" ]; then
    if [ "$mode" = close ]; then echo "$tag: no previous tag; nothing closed"
    else echo "$tag: no previous tag; nothing reported"; fi
    return 0
  fi
  m="$(manifest "$prev..$end")"
  echo "manifest: $(grep -c '^close ' <<< "$m") tickets ($prev..$label)"
  [ -n "$m" ] || return 0
  grep -q '^close ' <<< "$m" && need_repo
  body="Released in $tag"
  while read -r kind n; do
    [ -n "$n" ] || continue
    if [ "$kind" = refs ]; then echo "kept open #$n (refs)"; kept=$((kept + 1)); continue; fi
    view "$n"
    case "$V" in
      notfound) echo "skip #$n: not found"; skipped=$((skipped + 1)); continue ;;
      pr)       echo "skip #$n: pull request"; skipped=$((skipped + 1)); continue ;;
      closed)   already=$((already + 1)); continue ;;
      fail)     echo "::warning::view #$n failed (rc=$VRC)"; failed=$((failed + 1)); continue ;;
    esac
    if [ "$mode" = report ]; then echo "released but open: #$n"; open=$((open + 1)); continue; fi
    rc=0; has="$(FORGE_DRY_RUN=0 forge_issue_comments "$n" 2>"$WORK/err")" || rc=$?
    if [ "$rc" -eq 0 ]; then
      has="$(jq --arg b "$body" 'any(.[]?; (.body // "") == $b)' <<< "$has" 2>/dev/null)" || rc=1
      [ "$has" = true ] || [ "$has" = false ] || rc=1
    fi
    if [ "$rc" -ne 0 ]; then
      cat "$WORK/err" >&2; echo "::warning::comments #$n failed (rc=$rc)"; failed=$((failed + 1)); continue
    fi
    if [ "$DRY" = 1 ]; then
      if [ "$has" = true ]; then echo "[dry-run] would close #$n for $tag (comment present)"
      else echo "[dry-run] would comment and close #$n for $tag"; fi
      continue
    fi
    if [ "$has" != true ]; then
      rc=0; forge_issue_comment "$n" "$body" || rc=$?
      if [ "$rc" -ne 0 ]; then echo "::warning::comment #$n failed (rc=$rc)"; failed=$((failed + 1)); continue; fi
    fi
    rc=0; forge_issue_close "$n" || rc=$?
    if [ "$rc" -ne 0 ]; then echo "::warning::close #$n failed (rc=$rc)"; failed=$((failed + 1)); continue; fi
    echo "closed #$n"; closed=$((closed + 1))
  done <<< "$m"
}

closed=0 already=0 kept=0 skipped=0 failed=0 open=0

if [ -n "$last" ]; then
  # Every release tag in the repository, not only those merged into HEAD: run from a development
  # branch, the tags live on the production branch and --merged HEAD found none (review M2).
  # Reachability still bounds each tag's range, inside prev_tag.
  tags="$(git tag --list "$TAG_GLOB" --sort=-v:refname 2>/dev/null \
    | while IFS= read -r t; do _is_release "$t" && printf '%s\n' "$t"; done | head -n "$last")"
  [ -n "$tags" ] || echo "no release tags"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    echo "== $t"
    release_one "$t" "$t" "$t"
  done <<< "$tags"
else
  if git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null 2>&1; then
    release_one "$tag" "$tag" "$tag"
  elif [ -n "$to" ]; then
    git rev-parse -q --verify "$to^{commit}" >/dev/null 2>&1 \
      || { echo "close-shipped: --to '$to' is not a commit" >&2; exit 2; }
    release_one "$tag" "$to" "$to"
  else
    echo "close-shipped: tag '$tag' does not exist (use --to <ref> for a tag not yet created)" >&2; exit 2
  fi
fi

if [ "$mode" = report ]; then
  echo "close-shipped report: released but open $open, already closed $already, kept open $kept, skipped $skipped, failed $failed"
  [ "$open" -eq 0 ] || exit 1
  [ "$failed" -eq 0 ] || exit 2
  exit 0
fi
echo "close-shipped: $tag: closed $closed, already closed $already, kept open $kept, skipped $skipped, failed $failed"
[ "$failed" -eq 0 ]
