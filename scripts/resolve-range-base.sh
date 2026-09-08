#!/usr/bin/env bash
# resolve-range-base.sh: work out what the range guards should diff against, or refuse (#158).
#
# WHY IT EXISTS. Both range guards (check-version-bump.sh, check-plugin-version-bump.sh) were wired
# `pull_request`-only. That was right while every change arrived as a PR; since 2026-09-08 work
# lands on develop and merges to main directly, so they ran on NO path at all and .githooks/pre-push
# was the only thing enforcing them.
#
# WHY IT IS A SCRIPT. The obvious fix is one YAML line: add `push` to the trigger and pass
# `github.event.before`. That is wrong in two shapes, and both fail in the same direction:
#
#   - `before` is the ALL-ZEROES sha when a ref is created. `git diff 000...000...HEAD` errors, and
#     a caller that reads an errored diff as "nothing changed" passes VACUOUSLY.
#   - `before` may name an object the server no longer has after a FORCE PUSH.
#
# A vacuous pass is worse than the honest gap #158 describes, because it leaves the claim true on
# paper and false in fact. So this resolves a base or REFUSES, and never prints a ref it is not sure
# of: a caller that greps stdout for a ref gets nothing on a refusal.
#
# Reads its inputs from the environment so CI can pass GitHub's context and the tests can pass
# anything:
#   EVENT_NAME       pull_request | push
#   BASE_REF         the PR's target branch          (pull_request only)
#   BEFORE           github.event.before             (push only)
#   DEFAULT_BRANCH   the repo's default branch name
#   REF_NAME         the branch being pushed
#
# Exit 0 and print the base on stdout, or exit 2 and explain on stderr.
set -uo pipefail

ZERO=0000000000000000000000000000000000000000
EVENT_NAME="${EVENT_NAME:-}"
BASE_REF="${BASE_REF:-}"
BEFORE="${BEFORE:-}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
REF_NAME="${REF_NAME:-}"

refuse() {
  echo "resolve-range-base: $1" >&2
  echo "  The range guards cannot run, and they must NOT report clean instead." >&2
  exit 2
}

resolves() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

# The fallback: "does this branch bump what it changed against the default branch" is the same
# question a pull request asks, so it is a real answer rather than a way of avoiding one. It is
# only available to a branch that IS NOT the default branch, and only if the ref is present.
fallback() {
  [ "$REF_NAME" != "$DEFAULT_BRANCH" ] || return 1
  resolves "origin/$DEFAULT_BRANCH" || return 1
  printf 'origin/%s' "$DEFAULT_BRANCH"
}

case "$EVENT_NAME" in
  pull_request)
    [ -n "$BASE_REF" ] || refuse "pull_request with no BASE_REF"
    resolves "origin/$BASE_REF" \
      || refuse "origin/$BASE_REF is not present locally (fetch it; a shallow checkout cannot answer this)"
    printf 'origin/%s' "$BASE_REF"
    ;;

  push)
    if [ -n "$BEFORE" ] && [ "$BEFORE" != "$ZERO" ] && resolves "$BEFORE"; then
      printf '%s' "$BEFORE"
      exit 0
    fi

    # Distinguish the two causes, because the operator's response differs.
    if [ -z "$BEFORE" ] || [ "$BEFORE" = "$ZERO" ]; then
      why="this ref was just created, so it has no previous tip"
    else
      why="the previous tip $BEFORE could not be resolved, which is what a force push leaves behind"
      echo "resolve-range-base: $why; falling back to the default branch." >&2
    fi

    if base="$(fallback)"; then
      printf '%s' "$base"
      exit 0
    fi

    # No base at all. This is creating or force-pushing the DEFAULT branch, which is exactly when
    # the check is most wanted and least available. Refuse; do not invent a range.
    if [ "$REF_NAME" = "$DEFAULT_BRANCH" ]; then
      refuse "no base for a push to the default branch ($REF_NAME): $why, and it cannot be compared against itself"
    fi
    refuse "no base: $why, and origin/$DEFAULT_BRANCH is not present to fall back to"
    ;;

  *)
    refuse "unknown or missing EVENT_NAME '$EVENT_NAME' (want pull_request or push)"
    ;;
esac
