#!/usr/bin/env bash
# Contract test for release-automation/assets/release-run.sh (issue #76).
#
# release-run.sh is the SIDE-EFFECTING release driver, so the policy cases run with DRY_RUN=1, which
# makes it print what it would do and touch no remote, no tag and no file. What is under test is
# the LANE POLICY: the recursion guard, the dependency scope gate, and which version it decides to
# release. Section 6 (#496) covers the close-shipped wiring, including two REAL runs against a
# bare `origin` and a PATH-shim `gh`, so the tag, the release and the close are each observed.
# Every case runs with that shim first on PATH, so no case can reach a real host.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
ASSETS="$ROOT/plugins/forge-kit-devops/skills/release-automation/assets"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FORGE_LIB_SRC="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh"

# The gh shim (the same contract as scripts/test-close-shipped.sh's): issue JSON and comments from
# $GHSTUB, a close PATCH flips the issue, every call is logged and every write is `WRITE ...`.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
S="$GHSTUB"
echo "gh $*" >> "$S/log"
if [ "${1-}" = release ]; then [ "${2-}" = view ] && [ ! -f "$S/release-exists" ] && exit 1; exit 0; fi
shift
method=GET path=""
while [ $# -gt 0 ]; do
  case "$1" in -X) method="$2"; shift ;; --paginate) ;; --input) shift ;; *) path="$1" ;; esac
  shift
done
case "$path" in
  */issues/*/comments) n="${path%/comments}"; n="${n##*/}"; kind=comments ;;
  */issues/*)          n="${path##*/}"; kind=issue ;;
  *) exit 3 ;;
esac
op="$method-$kind"
if [ -f "$S/fail/$op-$n" ]; then echo '{}'; echo "gh: stubbed (HTTP $(cat "$S/fail/$op-$n"))" >&2; exit 1; fi
case "$op" in
  GET-issue) [ -f "$S/issues/$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$S/issues/$n.json" ;;
  GET-comments) if [ -f "$S/c-$n.json" ]; then cat "$S/c-$n.json"; else echo '[]'; fi ;;
  POST-comments) body="$(cat)"; echo "WRITE POST $n $body" >> "$S/log"
    [ -f "$S/c-$n.json" ] || echo '[]' > "$S/c-$n.json"
    jq -c --argjson c "$body" '. + [$c]' "$S/c-$n.json" > "$S/c.tmp" && mv "$S/c.tmp" "$S/c-$n.json"; echo '{}' ;;
  PATCH-issue) echo "WRITE PATCH $n $(cat)" >> "$S/log"
    jq -c '.state = "closed"' "$S/issues/$n.json" > "$S/i.tmp" && mv "$S/i.tmp" "$S/issues/$n.json"; echo '{}' ;;
  *) exit 3 ;;
esac
STUB
chmod +x "$BIN/gh"
GHSTUB="$TMP/ghstate"; mkdir -p "$GHSTUB/issues" "$GHSTUB/fail"; : > "$GHSTUB/log"
newstate() { rm -rf "$GHSTUB"; mkdir -p "$GHSTUB/issues" "$GHSTUB/fail"; : > "$GHSTUB/log"; }
openissue() { printf '{"number":%s,"state":"open","pull_request":null}\n' "$1" > "$GHSTUB/issues/$1.json"; }

mkrepo() {                      # a repo with the four release assets copied in, one commit
  local r; r=$(mktemp -d "$TMP/repo.XXXXXX")
  git init --quiet -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email t@example.com >/dev/null 2>&1
  git -C "$r" config user.name test >/dev/null 2>&1
  mkdir -p "$r/ci"; cp "$ASSETS/version-lib.sh" "$ASSETS/release-run.sh" "$ASSETS/close-shipped.sh" "$FORGE_LIB_SRC" "$r/ci/"
  echo "1.0.0" > "$r/VERSION"
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" commit --quiet -m "initial" >/dev/null 2>&1
  printf '%s' "$r"
}
# run <repo> [env...] -> combined output in $out, status in $rc
run() { local r="$1"; shift; out=$(CDPATH= cd -- "$r" && env -u FORGE_DRY_RUN -u FORGE_LIB PATH="$BIN:$PATH" GHSTUB="$GHSTUB" FORGE_HOST=github FORGE_REPO=o/r DRY_RUN=1 BRANCH=main "$@" bash ci/release-run.sh 2>&1); rc=$?; }
# runreal <repo> [env...]: the same, WITHOUT DRY_RUN
runreal() { local r="$1"; shift; out=$(CDPATH= cd -- "$r" && env -u DRY_RUN -u FORGE_DRY_RUN -u FORGE_LIB PATH="$BIN:$PATH" GHSTUB="$GHSTUB" FORGE_HOST=github FORGE_REPO=o/r BRANCH=main "$@" bash ci/release-run.sh 2>&1); rc=$?; }

# --- 1. recursion guard: never act on our own bump commit --------------------------------------
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "chore(release): automated version bump to 1.0.1"
run "$R" BUMP_SUBJECT="chore(release): automated version bump"
[ "$rc" -eq 0 ] && grep -q 'own auto-bump commit' <<< "$out" \
  && ok "the recursion guard stops on our own bump commit" \
  || bad "the recursion guard stops on our own bump commit (rc=$rc: $out)"

# A DIFFERENT subject must NOT be swallowed by the guard.
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "feat: a real change"
run "$R" BUMP_SUBJECT="chore(release): automated version bump"
grep -q 'own auto-bump commit' <<< "$out" \
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
[ "$rc" -eq 0 ] && grep -q 'bot=false' <<< "$out" \
  && ok "a human-authored dependency change does not auto-release" \
  || bad "a human-authored dependency change does not auto-release (rc=$rc: $out)"

R=$(mkdep 'dependabot[bot]' 'src/app.js'); run "$R" "${SCOPE[@]}"
[ "$rc" -eq 0 ] && grep -q 'deps-only=false' <<< "$out" \
  && ok "a bot change touching non-dependency files does not auto-release" \
  || bad "a bot change touching non-dependency files does not auto-release (rc=$rc: $out)"

R=$(mkdep 'dependabot[bot]' 'package-lock.json'); run "$R" "${SCOPE[@]}"
grep -q 'leaving it to the lane-A gate' <<< "$out" \
  && bad "a bot-authored dependency-only change proceeds past the gate" \
  || ok "a bot-authored dependency-only change proceeds past the gate"

# The hits>0 guard: a bot-authored commit that changes NO files must not release, even though
# "every changed file is a dependency file" is vacuously true for an empty set.
R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" -c user.name='dependabot[bot]' commit --quiet --allow-empty -m "empty merge"
run "$R" "${SCOPE[@]}"
[ "$rc" -eq 0 ] && grep -q 'hits=0' <<< "$out" \
  && ok "an empty bot commit does not release (the vacuous deps-only case)" \
  || bad "an empty bot commit does not release (rc=$rc: $out)"

# A monorepo subdirectory path matches on basename too.
R=$(mkdep 'dependabot[bot]' 'packages/web/package-lock.json'); run "$R" "${SCOPE[@]}"
grep -q 'leaving it to the lane-A gate' <<< "$out" \
  && bad "a nested dependency file matches by basename" \
  || ok "a nested dependency file matches by basename"

# --- 3. the version decision -------------------------------------------------------------------
R=$(mkrepo); git -C "$R" tag v2.0.0; run "$R"
[ "$rc" -ne 0 ] && grep -q 'refusing to publish a regression' <<< "$out" \
  && ok "behind -> hard stop, refuses to publish a regression" \
  || bad "behind -> hard stop (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"; run "$R"
grep -q 'would tag v1.1.0' <<< "$out" \
  && ok "ahead -> tags the working version as-is" || bad "ahead -> tags as-is ($out)"
grep -q 'bump ' <<< "$out" \
  && bad "ahead never re-bumps" || ok "ahead never re-bumps"

R=$(mkrepo); run "$R"          # no tag at all
grep -q 'would tag v1.0.0' <<< "$out" \
  && ok "first-release -> tags the current version" || bad "first-release ($out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R"
grep -q 'bump VERSION -> 1.0.1' <<< "$out" \
  && ok "equal -> plans a patch bump to 1.0.1" || bad "equal -> patch bump ($out)"
grep -q 'would tag v1.0.1' <<< "$out" \
  && ok "equal -> tags the bumped version, not the old one" || bad "equal -> tags the bump ($out)"

# --- 4. tag-derived (git) mode -----------------------------------------------------------------
R=$(mkrepo); run "$R" VERSION_SOURCE=git
[ "$rc" -eq 0 ] && grep -q 'push an initial tag' <<< "$out" \
  && ok "git mode with no reachable tag asks for a bootstrap tag" \
  || bad "git mode bootstrap (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R" VERSION_SOURCE=git
[ "$rc" -eq 0 ] && grep -q 'nothing to release' <<< "$out" \
  && ok "git mode with no commits since the tag cuts no phantom tag" \
  || bad "git mode phantom tag guard (rc=$rc: $out)"

R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" commit --quiet --allow-empty -m "feat: work"
run "$R" VERSION_SOURCE=git
grep -q 'would tag v1.0.1' <<< "$out" \
  && ok "git mode with unreleased commits tags the next patch" || bad "git mode next patch ($out)"

# --- 5. dry-run really is inert ----------------------------------------------------------------
R=$(mkrepo); git -C "$R" tag v1.0.0; run "$R"
[ "$(cat "$R/VERSION")" = "1.0.0" ] && ok "dry-run does not write the version file" \
  || bad "dry-run does not write the version file (now $(cat "$R/VERSION"))"
[ "$(git -C "$R" tag --list | tr '\n' ' ')" = "v1.0.0 " ] \
  && ok "dry-run creates no tag" || bad "dry-run creates no tag"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "dry-run leaves the tree clean" \
  || bad "dry-run leaves the tree clean"

# --- 6. closing what the release shipped (#496) -------------------------------------------------
newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"
git -C "$R" commit --quiet -am "fix(a): x (#10)"; openissue 10; run "$R"
[ "$rc" -eq 0 ] && grep -q '^\[dry-run\] would comment and close #10 for v1.1.0$' <<< "$out" \
  && ! grep -q '^WRITE' "$GHSTUB/log" \
  && ok "a dry run previews the close and writes nothing" \
  || bad "a dry run previews the close and writes nothing (rc=$rc: $out)"

newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"; run "$R"
[ "$rc" -eq 0 ] && grep -q '^manifest: 0 tickets' <<< "$out" && [ ! -s "$GHSTUB/log" ] \
  && ok "an empty manifest in a dry run makes no host call" \
  || bad "an empty manifest in a dry run makes no host call (rc=$rc: $out)"

newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"; rm "$R/ci/close-shipped.sh"; run "$R"
[ "$rc" -eq 0 ] && grep -q '^::warning::close-shipped.sh not found beside release-run.sh' <<< "$out" \
  && ok "a missing close-shipped.sh warns and the release still succeeds" \
  || bad "a missing close-shipped.sh warns (rc=$rc: $out)"

mkorigin() {   # mkorigin <repo>: a bare origin holding main
  local o; o=$(mktemp -d "$TMP/origin.XXXXXX"); git init --quiet --bare "$o"
  git -C "$1" remote add origin "$o"; git -C "$1" push --quiet origin main >/dev/null 2>&1
  printf '%s' "$o"
}
newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"
git -C "$R" commit --quiet -am "fix(a): x (#10)"; O=$(mkorigin "$R"); openissue 10; runreal "$R"
rel=$(grep -n '^gh release create v1.1.0' "$GHSTUB/log" | cut -d: -f1)
cls=$(grep -n '^WRITE PATCH 10 ' "$GHSTUB/log" | cut -d: -f1)
[ "$rc" -eq 0 ] && git -C "$O" rev-parse -q --verify refs/tags/v1.1.0 >/dev/null && [ -n "$rel" ] && [ -n "$cls" ] && [ "$rel" -lt "$cls" ] \
  && ok "a real run tags, creates the release, then closes the shipped ticket" \
  || bad "a real run tags, releases, then closes (rc=$rc rel=$rel cls=$cls: $out)"

newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"
git -C "$R" commit --quiet -am "fix(a): x (#10)"; O=$(mkorigin "$R"); openissue 10
echo 403 > "$GHSTUB/fail/PATCH-issue-10"; runreal "$R"
[ "$rc" -eq 1 ] && git -C "$O" rev-parse -q --verify refs/tags/v1.1.0 >/dev/null \
  && grep -q '^::warning::close #10 failed (rc=1)$' <<< "$out" \
  && grep -q '^::error::shipped tickets not all closed; run: bash ci/close-shipped.sh v1.1.0 (do not rerun this lane)$' <<< "$out" \
  && ok "a failed close turns the run red after the tag exists and prints the recovery command" \
  || bad "a failed close turns the run red after the tag and prints the recovery command (rc=$rc: $out)"

rm -f "$GHSTUB/fail/PATCH-issue-10"
out=$(CDPATH= cd -- "$R" && env -u DRY_RUN -u FORGE_DRY_RUN -u FORGE_LIB PATH="$BIN:$PATH" GHSTUB="$GHSTUB" FORGE_HOST=github FORGE_REPO=o/r bash ci/close-shipped.sh v1.1.0 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c '^WRITE POST 10 ' "$GHSTUB/log")" = 1 ] && grep -q '^closed #10$' <<< "$out" \
  && ok "manual recovery with the printed command converges with no second comment" \
  || bad "manual recovery converges (rc=$rc: $out)"

newstate; R=$(mkrepo); git -C "$R" tag v1.0.0; echo "1.1.0" > "$R/VERSION"
git -C "$R" commit --quiet -am "fix(a): x (#10)"; O=$(mkorigin "$R"); openissue 10; : > "$GHSTUB/release-exists"; runreal "$R"
[ "$rc" -eq 0 ] && grep -q 'release v1.1.0 already exists' <<< "$out" && grep -q '^closed #10$' <<< "$out" \
  && ok "an existing release still closes" \
  || bad "an existing release still closes (rc=$rc: $out)"

# The tag already existed (here: the next patch was tagged on a sibling commit): the close still runs.
newstate; R=$(mkrepo); git -C "$R" tag v1.0.0
git -C "$R" checkout --quiet -b side; git -C "$R" commit --quiet --allow-empty -m "fix: side (#11)"; git -C "$R" tag v1.0.1
git -C "$R" checkout --quiet main; git -C "$R" commit --quiet --allow-empty -m "feat: work"
openissue 11; runreal "$R" VERSION_SOURCE=git
[ "$rc" -eq 0 ] && grep -q 'tag v1.0.1 already exists' <<< "$out" && grep -q '^WRITE PATCH 11 ' "$GHSTUB/log" \
  && ok "the close runs when the tag already existed" \
  || bad "the close runs when the tag already existed (rc=$rc: $out)"

echo ""
echo "release-run tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
