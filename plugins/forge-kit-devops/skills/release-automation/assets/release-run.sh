#!/usr/bin/env bash
# release-run.sh — the shared side-effecting driver for the auto-release lanes (B and C). It
# single-sources the release MECHANICS so a fix lands once, not copy-pasted per lane. `version-lib.sh`
# (sourced) decides the version<->tag verdict; this applies the lane policy: recursion guard, an
# optional dependency scope gate (lane B), decide the version (file: bump+commit+push; tag-derived
# git: gate on unreleased commits, tag-only), then tag + create the release idempotently.
#
# Driven entirely by env (the lane YAML sets these):
#   VERSION_SOURCE VERSION_FILE TAG_GLOB TAG_PREFIX  — passed through to version-lib.sh
#   BRANCH            — production branch (workflow_run.head_branch)
#   BUMP_SUBJECT      — reserved commit subject for our own bump (recursion guard AND commit msg)
#   REQUIRE_DEP_SCOPE — "1" to require a bot-authored, dependency-only change (lane B); else "0"
#   BOT_LOGINS DEP_PATHS ACTOR — used only when REQUIRE_DEP_SCOPE=1
#   GH_TOKEN          — for `gh release create`
#   DRY_RUN           — "1" prints would-be actions instead of pushing/tagging/releasing (testable)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=version-lib.sh
source "$HERE/version-lib.sh"

BRANCH="${BRANCH:?BRANCH required}"
BUMP_SUBJECT="${BUMP_SUBJECT:-chore(release): automated version bump}"
REQUIRE_DEP_SCOPE="${REQUIRE_DEP_SCOPE:-0}"
DRY_RUN="${DRY_RUN:-0}"
TAG_PREFIX="${TAG_PREFIX:-v}"

# --- Recursion guard: never act on our own bump commit (quoted case = literal match, no regex) ---
case "$(git log -1 --pretty=%s)" in
  "$BUMP_SUBJECT"*) echo "::notice::own auto-bump commit — nothing to do."; exit 0 ;;
esac

# --- Optional dependency scope gate (lane B): bot author + dependency-only diff, at least one dep file ---
if [ "$REQUIRE_DEP_SCOPE" = 1 ]; then
  if git rev-parse -q --verify HEAD~1 >/dev/null 2>&1; then
    authors=$(git log --format='%an' HEAD~1..HEAD); changed=$(git diff --name-only HEAD~1 HEAD)
  else
    authors=$(git log -1 --format='%an'); changed=$(git show --name-only --pretty='' HEAD)
  fi
  set -f                                   # keep [bot] / *.txt literal during word-split
  is_bot=false
  for b in ${BOT_LOGINS:-}; do
    printf '%s\n' "$authors" | grep -qxF "$b" && is_bot=true
    [ "${ACTOR:-}" = "$b" ] && is_bot=true
  done
  only_deps=true; dep_hits=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    m=false
    for g in ${DEP_PATHS:-}; do
      case "$f" in $g) m=true;; esac          # full path
      case "${f##*/}" in $g) m=true;; esac    # or basename (monorepo subdirs)
    done
    if $m; then dep_hits=$((dep_hits + 1)); else only_deps=false; fi
  done <<< "$changed"
  set +f
  # Require at least one matched dependency file: an empty/no-file-change merge must NOT release.
  if ! { [ "$is_bot" = true ] && [ "$only_deps" = true ] && [ "$dep_hits" -gt 0 ]; }; then
    echo "::notice::not a bot-authored dependency-only change (bot=$is_bot deps-only=$only_deps hits=$dep_hits) — leaving it to the lane-A gate."
    exit 0
  fi
fi

# --- Decide the version to release ---
version=""
committed=0
if [ "$VERSION_SOURCE" = git ]; then
  # Tag-derived: there is no file to bump, so the release IS the next tag. The verdict is always
  # `equal`, so it carries no signal — gate on whether there are commits since the latest tag,
  # else a CI re-run on an already-tagged HEAD would cut a phantom tag every time.
  cur=$(read_version)
  if [ -z "$cur" ]; then
    echo "::notice::tag-derived project with no release tag reachable from HEAD — push an initial tag (e.g. ${TAG_PREFIX}0.1.0) to bootstrap."; exit 0
  fi
  if [ "$(unreleased_commits)" -eq 0 ]; then
    echo "::notice::no commits since the latest tag (${TAG_PREFIX}${cur}) — nothing to release."; exit 0
  fi
  version=$(next_patch)
else
  verdict=$(classify_version)
  case "$verdict" in
    behind)
      echo "::error::version is behind the latest release — refusing to publish a regression."; exit 1 ;;
    ahead|first-release)
      version=$(read_version) ;;            # already at / establishing the version — tag as-is
    equal)
      version=$(next_patch)
      if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] bump ${VERSION_FILE:-VERSION} -> $version, commit '$BUMP_SUBJECT to $version', push HEAD:$BRANCH"
      else
        # forge-adapt: for non-file sources replace this write with the project's bump,
        # e.g.  npm version "$version" --no-git-tag-version  (node). File-mode default:
        printf '%s\n' "$version" > "${VERSION_FILE:?VERSION_FILE required for file source}"
        git config user.name 'github-actions[bot]'
        git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
        git add -A
        git commit -m "$BUMP_SUBJECT to $version"
        # Re-sync onto the branch tip (it may have advanced since CI validated head_sha) so the push
        # is a fast-forward — never --force. A concurrent bump fails loud (rebase conflict).
        git fetch origin "$BRANCH"
        git rebase FETCH_HEAD
        git push origin "HEAD:$BRANCH"
      fi
      committed=1 ;;
  esac
fi
[ -n "$version" ] || { echo "::error::no version decided"; exit 1; }

# --- Tag + release (idempotent): a half-finished or retried run converges, never double-tags ---
tag="${TAG_PREFIX}${version}"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] would tag $tag and create release (committed=$committed)"; exit 0
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "::notice::tag $tag already exists — not re-tagging."
else
  git tag -a "$tag" -m "Release $tag"
  git push origin "$tag"
fi
if gh release view "$tag" >/dev/null 2>&1; then
  echo "::notice::release $tag already exists — nothing to publish."
else
  gh release create "$tag" --title "$tag" --generate-notes
fi
