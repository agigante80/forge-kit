#!/usr/bin/env bash
# Contract test for release-automation/assets/release-run.sh (issue #76).
#
# release-run.sh is the SIDE-EFFECTING release driver, so every case runs with DRY_RUN=1, which
# makes it print what it would do and touch no remote, no tag and no file. What is under test is
# the LANE POLICY: the recursion guard, the dependency scope gate, and which version it decides to
# release. The mechanics after that (push, tag, gh release) are what dry-run stands in for.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-devops/skills/release-automation/assets"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mkrepo() {                      # a repo with version-lib + release-run copied in, one commit
  local r; r=$(mktemp -d "$TMP/repo.XXXXXX")
  git init --quiet -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email t@example.com >/dev/null 2>&1
  git -C "$r" config user.name test >/dev/null 2>&1
  mkdir -p "$r/ci"; cp "$ASSETS/version-lib.sh" "$ASSETS/release-run.sh" "$r/ci/"
  echo "1.0.0" > "$r/VERSION"
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" commit --quiet -m "initial" >/dev/null 2>&1
  printf '%s' "$r"
}
# run <repo> [env...] -> combined output in $out, status in $rc
run() { local r="$1"; shift; out=$(cd "$r" && env DRY_RUN=1 BRANCH=main "$@" bash ci/release-run.sh 2>&1); rc=$?; }

# --- 1. recursion guard: never act on our own bump commit --------------------------------------
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "chore(release): automated version bump to 1.0.1"
run "$R" BUMP_SUBJECT="chore(release): automated version bump"
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'own auto-bump commit' \
  && ok "the recursion guard stops on our own bump commit" \
  || bad "the recursion guard stops on our own bump commit (rc=$rc: $out)"

# A DIFFERENT subject must NOT be swallowed by the guard.
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "feat: a real change"
run "$R" BUMP_SUBJECT="chore(release): automated version bump"
printf '%s' "$out" | grep -q 'own auto-bump commit' \
  && bad "an unrelated commit subject is not treated as our bump" \
  || ok "an unrelated commit subject is not treated as our bump"

# --- 2. the dependency scope gate (lane B) -----------------------------------------------------
mkdep() {   # mkdep <author> <file> -> repo whose HEAD changes <file>, authored by <author>
  local r; r=$(mkrepo); git -C "$r" tag v1.0.0
  mkdir -p "$r/$(dirname "$2")" 2>/dev/null || true
  echo change > "$r/$2"
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" -c user.name="$1" commit --quiet -m "bump dep" >/dev/null 2>&1
  printf '%s' "$r"
}
SCOPE=(REQUIRE_DEP_SCOPE=1 BOT_LOGINS='dependabot[bot]' DEP_PATHS='package-lock.json')

R=$(mkdep 'a-human' 'package-lock.json'); run "$R" "${SCOPE[@]}"
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'bot=false' \
  && ok "a human-authored dependency change does not auto-release" \
  || bad "a human-authored dependency change does not auto-release (rc=$rc: $out)"

R=$(mkdep 'dependabot[bot]' 'src/app.js'); run "$R" "${SCOPE[@]}"
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'deps-only=false' \
  && ok "a bot change touching non-dependency files does not auto-release" \
  || bad "a bot change touching non-dependency files does not auto-release (rc=$rc: $out)"

R=$(mkdep 'dependabot[bot]' 'package-lock.json'); run "$R" "${SCOPE[@]}"
printf '%s' "$out" | grep -q 'leaving it to the lane-A gate' \
  && bad "a bot-authored dependency-only change proceeds past the gate" \
  || ok "a bot-authored dependency-only change proceeds past the gate"

# The hits>0 guard: a bot-authored commit that changes NO files must not release, even though
# "every changed file is a dependency file" is vacuously true for an empty set.
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" -c user.name='dependabot[bot]' commit --quiet --allow-empty -m "empty merge"
run "$R" "${SCOPE[@]}"
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'hits=0' \
  && ok "an empty bot commit does not release (the vacuous deps-only case)" \
  || bad "an empty bot commit does not release (rc=$rc: $out)"

# A monorepo subdirectory path matches on basename too.
R=$(mkdep 'dependabot[bot]' 'packages/web/package-lock.json'); run "$R" "${SCOPE[@]}"
printf '%s' "$out" | grep -q 'leaving it to the lane-A gate' \
  && bad "a nested dependency file matches by basename" \
  || ok "a nested dependency file matches by basename"

# --- 3. the version decision -------------------------------------------------------------------
R=$(mkrepo); git -C "$R" tag v2.0.0; run "$R"
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'refusing to publish a regression' \
  && ok "behind -> hard stop, refuses to publish a regression" \
  || bad "behind -> hard stop (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"; run "$R"
printf '%s' "$out" | grep -q 'would tag v1.1.0' \
  && ok "ahead -> tags the working version as-is" || bad "ahead -> tags as-is ($out)"
printf '%s' "$out" | grep -q 'bump ' \
  && bad "ahead never re-bumps" || ok "ahead never re-bumps"

R=$(mkrepo); run "$R"          # no tag at all
printf '%s' "$out" | grep -q 'would tag v1.0.0' \
  && ok "first-release -> tags the current version" || bad "first-release ($out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R"
printf '%s' "$out" | grep -q 'bump VERSION -> 1.0.1' \
  && ok "equal -> plans a patch bump to 1.0.1" || bad "equal -> patch bump ($out)"
printf '%s' "$out" | grep -q 'would tag v1.0.1' \
  && ok "equal -> tags the bumped version, not the old one" || bad "equal -> tags the bump ($out)"

# --- 4. tag-derived (git) mode -----------------------------------------------------------------
R=$(mkrepo); run "$R" VERSION_SOURCE=git
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'push an initial tag' \
  && ok "git mode with no reachable tag asks for a bootstrap tag" \
  || bad "git mode bootstrap (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R" VERSION_SOURCE=git
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'nothing to release' \
  && ok "git mode with no commits since the tag cuts no phantom tag" \
  || bad "git mode phantom tag guard (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "feat: work"
run "$R" VERSION_SOURCE=git
printf '%s' "$out" | grep -q 'would tag v1.0.1' \
  && ok "git mode with unreleased commits tags the next patch" || bad "git mode next patch ($out)"

# --- 5. dry-run really is inert ----------------------------------------------------------------
R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R"
[ "$(cat "$R/VERSION")" = "1.0.0" ] && ok "dry-run does not write the version file" \
  || bad "dry-run does not write the version file (now $(cat "$R/VERSION"))"
[ "$(git -C "$R" tag --list | tr '\n' ' ')" = "v1.0.0 " ] \
  && ok "dry-run creates no tag" || bad "dry-run creates no tag"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "dry-run leaves the tree clean" \
  || bad "dry-run leaves the tree clean"

echo ""
echo "release-run tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
