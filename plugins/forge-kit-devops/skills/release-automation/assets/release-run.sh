#!/usr/bin/env bash
# release-run-version: 5
# release-run.sh: the shared side-effecting driver for the auto-release lanes (B and C). It
# single-sources the release MECHANICS so a fix lands once, not copy-pasted per lane. `version-lib.sh`
# (sourced) decides the version<->tag verdict; this applies the lane policy: recursion guard, an
# optional dependency scope gate (lane B), decide the version (file: bump+commit+push; tag-derived
# git: gate on unreleased commits, tag-only), then tag + create the release idempotently (an
# existing tag is accepted only at HEAD, #497), then close the tickets the release shipped through
# close-shipped.sh beside it (#496).
#
# Driven entirely by env (the lane YAML sets these):
#   VERSION_SOURCE VERSION_FILE TAG_GLOB TAG_PREFIX  (passed through to version-lib.sh)
#   BRANCH            (production branch, from workflow_run.head_branch)
#   BUMP_SUBJECT      (reserved commit subject for our own bump: recursion guard AND commit msg)
#   REQUIRE_DEP_SCOPE ("1" to require a bot-authored, dependency-only change on lane B; else "0")
#   BOT_LOGINS DEP_PATHS ACTOR  (used only when REQUIRE_DEP_SCOPE=1)
#   GH_TOKEN          (for `gh release create`, and for close-shipped.sh's issue comments and closes,
#                     so a GitHub App token needs Issues: Read and write as well as Contents: write)
#   DRY_RUN           ("1" prints would-be actions instead of pushing/tagging/releasing; testable)
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=version-lib.sh
source "$HERE/version-lib.sh"

BRANCH="${BRANCH:?BRANCH required}"
BUMP_SUBJECT="${BUMP_SUBJECT:-chore(release): automated version bump}"
REQUIRE_DEP_SCOPE="${REQUIRE_DEP_SCOPE:-0}"
DRY_RUN="${DRY_RUN:-0}"
TAG_PREFIX="${TAG_PREFIX:-v}"

# --- Git identity for a clean CI runner (no pre-existing config) ---
# The COMMIT needs author+committer; the annotated TAG (`git tag -a`) needs the committer identity.
# Setting all four env vars covers both git calls without mutating .git/config (forge-adapt can
# override RELEASE_BOT_NAME/EMAIL). This is what stops the tag-derived (VERSION_SOURCE=git) path,
# which tags WITHOUT a preceding commit, from dying with "empty ident name" on a fresh runner.
: "${RELEASE_BOT_NAME:=github-actions[bot]}"
: "${RELEASE_BOT_EMAIL:=41898282+github-actions[bot]@users.noreply.github.com}"
export GIT_AUTHOR_NAME="$RELEASE_BOT_NAME"    GIT_AUTHOR_EMAIL="$RELEASE_BOT_EMAIL"
export GIT_COMMITTER_NAME="$RELEASE_BOT_NAME" GIT_COMMITTER_EMAIL="$RELEASE_BOT_EMAIL"

# --- Recursion guard: never act on our own bump commit (quoted case = literal match, no regex) ---
case "$(git log -1 --pretty=%s)" in
  "$BUMP_SUBJECT"*) echo "::notice::own auto-bump commit, nothing to do."; exit 0 ;;
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
    grep -qxF "$b" <<< "$authors" && is_bot=true
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
    echo "::notice::not a bot-authored dependency-only change (bot=$is_bot deps-only=$only_deps hits=$dep_hits); leaving it to the lane-A gate."
    exit 0
  fi
fi

# --- Decide the version to release ---
version=""
committed=0
if [ "$VERSION_SOURCE" = git ]; then
  # Tag-derived: there is no file to bump, so the release IS the next tag. The verdict is always
  # `equal`, so it carries no signal; gate on whether there are commits since the latest tag,
  # else a CI re-run on an already-tagged HEAD would cut a phantom tag every time.
  cur=$(read_version)
  if [ -z "$cur" ]; then
    echo "::notice::tag-derived project with no release tag reachable from HEAD; push an initial tag (e.g. ${TAG_PREFIX}0.1.0) to bootstrap."; exit 0
  fi
  if [ "$(unreleased_commits)" -eq 0 ]; then
    echo "::notice::no commits since the latest tag (${TAG_PREFIX}${cur}); nothing to release."; exit 0
  fi
  version=$(next_patch)
else
  verdict=$(classify_version)
  case "$verdict" in
    behind)
      echo "::error::version is behind the latest release; refusing to publish a regression."; exit 1 ;;
    ahead|first-release)
      version=$(read_version) ;;            # already at / establishing the version, so tag as-is
    equal)
      version=$(next_patch)
      if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] bump ${VERSION_FILE:-VERSION} -> $version, commit '$BUMP_SUBJECT to $version', push HEAD:$BRANCH"
      else
        # forge-adapt: for non-file sources replace this write with the project's bump,
        # e.g.  npm version "$version" --no-git-tag-version  (node). File-mode default:
        printf '%s\n' "$version" > "${VERSION_FILE:?VERSION_FILE required for file source}"
        git add -A                                   # identity comes from the GIT_*_NAME/EMAIL env set above
        git commit -m "$BUMP_SUBJECT to $version"
        # Re-sync onto the branch tip (it may have advanced since CI validated head_sha) so the push
        # is a fast-forward, never --force. A concurrent bump fails loud (rebase conflict).
        git fetch origin "$BRANCH"
        git rebase FETCH_HEAD
        git push origin "HEAD:$BRANCH"
      fi
      committed=1 ;;
  esac
fi
[ -n "$version" ] || { echo "::error::no version decided"; exit 1; }

# --- Tag + release (idempotent): a retried run converges, never double-tags, never adopts a tag elsewhere ---
tag="${TAG_PREFIX}${version}"

# --- Close what the release shipped (#496) ---
# close-shipped.sh comments "Released in <tag>" on, then closes, every open issue cited as a
# trailing (#N) in the release range's commit subjects. It runs AFTER the tag, and whether or not
# the tag or release already existed; a failure makes this run exit 1 after every ticket was tried.
# RECOVERY IS MANUAL, never a lane rerun (#496 gate round 2): the lanes check out the released
# head_sha, so a rerun starts from the top, where file mode now reads `equal` and cuts a phantom
# patch release, and git mode exits at "no commits since the latest tag" before any close. So a
# failed close prints the one command that converges, `close-shipped.sh <tag>`, which is idempotent.
# A project that refreshed only this script keeps releasing, with a warning.
close_shipped() {
  if [ -f "$HERE/close-shipped.sh" ]; then
    DRY_RUN="$DRY_RUN" TAG_PREFIX="$TAG_PREFIX" bash "$HERE/close-shipped.sh" "$@"
  else
    echo "::warning::close-shipped.sh not found beside release-run.sh; shipped tickets were not closed"
  fi
}

# An existing tag is accepted only AT HEAD, the idempotent rerun (#497). On another commit (a hand
# pushed tag on a side branch, say) the release would point there and close-shipped.sh, which reads
# the TAG's range, would close that branch's tickets. Compare peeled commits, so an annotated tag at
# HEAD is not refused. Checked before the dry-run preview too, so the preview cannot show them.
# In file mode the bump is already pushed by now, so a refusal here leaves an untagged bump commit;
# only a TAG_GLOB that hides the tag from version-lib, or a race, gets here, so it is documented
# rather than reordered.
if tag_at=$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null); then
  head_at=$(git rev-parse HEAD)
  if [ "$tag_at" != "$head_at" ]; then
    echo "::error::tag $tag already exists at $tag_at, not at HEAD $head_at; refusing to release or close anything. Move or delete the tag, or release a higher version."
    exit 1
  fi
fi
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] would tag $tag and create release (committed=$committed)"
  close_rc=0; close_shipped "$tag" --to HEAD || close_rc=$?   # the preview: reads, never writes
  exit "$close_rc"
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "::notice::tag $tag already exists, not re-tagging."
else
  git tag -a "$tag" -m "Release $tag"
  git push origin "$tag"
fi
if gh release view "$tag" >/dev/null 2>&1; then
  echo "::notice::release $tag already exists, nothing to publish."
else
  gh release create "$tag" --title "$tag" --generate-notes
fi
close_rc=0; close_shipped "$tag" || close_rc=$?
if [ "$close_rc" -ne 0 ]; then
  rel="$HERE/close-shipped.sh"; top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$top" ] || rel="${rel#"$top"/}"
  echo "::error::shipped tickets not all closed; run: bash $rel $tag (do not rerun this lane)"
fi
exit "$close_rc"
