#!/usr/bin/env bash
# Contract test for check-template-dir-order.sh (issue #77).
#
# THE DEFECT. The template-directory resolution order is a five-entry, HOST-grouped list that five
# separate sites must agree on: check-template-lockstep.sh twice (its header comment and
# resolve_dir), ticket-gate.md, dep-auditor.md, and adapt/SKILL.md twice. The #61/#74 review found the copies had
# already diverged, case-grouped against host-grouped, before that PR merged, and only a review
# finding re-aligned them. Two of the sites are prose an LLM executor will paraphrase.
#
# WHY A GUARD AND NOT A SHARED SCRIPT. The ticket proposed extracting one implementation, and its
# own trade-off concedes that the prose sites must keep an inline fallback, so the duplication
# would shrink from four sites to two rather than to one. This repo already faced the identical
# shape with the enforced path set (#112), where the catalogue must use globs while the others use
# an ERE, and chose a guard (test-component-paths.sh) precisely because one implementation was
# impossible. A guard covers all six sites; a shared script would have covered two.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-template-dir-order.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

CANON='.forgejo/ISSUE_TEMPLATE .forgejo/issue_template .gitea/ISSUE_TEMPLATE .gitea/issue_template .github/ISSUE_TEMPLATE'

# --- all sites agreeing ------------------------------------------------------------------------
mk "$T/ok/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/ok/b.md" <<M
TPL_DIR=\$(for d in $CANON; do :; done)
M
bash "$SCRIPT" "$T/ok" >/dev/null 2>&1
[ $? -eq 0 ] && ok "sites that agree pass" || bad "agreeing sites pass"

# --- a REORDERED copy is the exact defect #61 shipped -------------------------------------------
# Case-grouped instead of host-grouped: both ISSUE_TEMPLATE dirs first, then both lowercase. A
# migrated repo that kept a stale .github dir then gets the stale one checked, not its live one.
mk "$T/reordered/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/reordered/b.md" <<'M'
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template; do :; done)
M
out=$(bash "$SCRIPT" "$T/reordered" 2>&1); rc=$?
# EXACTLY 1. "Non-zero" would accept exit 2, the unreadable-root status, so a fixture path typo
# would read as a passing divergence test.
[ "$rc" -eq 1 ] && ok "a case-grouped copy fails against the host-grouped canon" || bad "reordered copy exits 1 (got $rc)"
case "$out" in *b.md*) ok "and it names the disagreeing file" ;;
               *) bad "names the file (got: $out)" ;; esac

# --- the DOCUMENTED limit: a copy shortened below five entries leaves the comparison ------------
# Pinned as a test rather than left in a comment, because it is the guard's one real blind spot and
# a reader deserves to meet it here. A five-entry run is an ordering; anything shorter is prose,
# and that threshold is what stops the guard failing builds over documentation. What catches a
# shortened site is the site COUNT asserted at the end of this file, not the order comparison.
for n in 4 3; do
  mk "$T/short-$n/a.sh" <<M
  for d in $CANON; do :; done
M
  case $n in
    4) list='.forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .gitea/issue_template .github/ISSUE_TEMPLATE' ;;
    3) list='.forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE' ;;
  esac
  mk "$T/short-$n/b.md" <<M
TPL_DIR=\$(for d in $list; do :; done)
M
  bash "$SCRIPT" "$T/short-$n" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "a copy cut to $n entries drops out of the comparison (known limit)" \
    || bad "the $n-entry limit behaves as documented"
done

# --- a line-continued copy is the same list, not a different one --------------------------------
mk "$T/wrapped/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/wrapped/b.md" <<'M'
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .forgejo/issue_template \
          .gitea/ISSUE_TEMPLATE .gitea/issue_template .github/ISSUE_TEMPLATE; do :; done)
M
bash "$SCRIPT" "$T/wrapped" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a backslash-continued copy is read as one list" || bad "wrapped copy reads as one list"

# --- a passing mention of one or two dirs in prose is NOT a resolution order ---------------------
mk "$T/prose/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/prose/b.md" <<'M'
Templates write to `.github/ISSUE_TEMPLATE/` on GitHub, or to `.forgejo/ISSUE_TEMPLATE/`
when the host is Forgejo.
M
bash "$SCRIPT" "$T/prose" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a two-directory prose mention is not treated as an ordering" \
  || bad "prose mentions are not orderings"

# --- a tree with NO ordering at all must fail, or the guard can be defeated by deletion ----------
mk "$T/none/a.md" <<'M'
nothing relevant here
M
bash "$SCRIPT" "$T/none" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a tree with no ordering at all fails rather than passing vacuously" \
  || bad "no-ordering tree fails"

# --- round 1: agreement is NOT enough; the canonical order itself must be pinned -----------------
# The guard originally compared the copies to each other only, so a sweep reordering EVERY site to
# case-grouped passed with CI green, reintroducing the exact #61 defect while the error message
# claimed a canon nothing enforced.
mk "$T/allwrong/a.sh" <<'M'
  for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template; do :; done
M
mk "$T/allwrong/b.md" <<'M'
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template; do :; done)
M
out=$(bash "$SCRIPT" "$T/allwrong" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "sites that AGREE on the wrong order still fail" \
  || bad "a uniform case-grouped sweep is caught (rc=$rc)"
case "$out" in *"Host-grouped is canonical"*) ok "and it says which order is canonical" ;;
               *) bad "names the canonical order (got: $out)" ;; esac

# --- round 1: two back-to-back copies are two sites, not one ten-entry site ---------------------
# The copies must be separated by PUNCTUATION ONLY to reproduce the merge: two `for` loops have
# the words "do" and "done" between them, which already stops the run.
mk "$T/backtoback/a.sh" <<M
# $CANON
# $CANON
M
bash "$SCRIPT" "$T/backtoback" >/dev/null 2>&1
[ $? -eq 0 ] && ok "adjacent identical copies read as two sites, not one merged run" \
  || bad "back-to-back copies do not merge"

# --- round 1: a shipped component named test-* is not a fixture ---------------------------------
# The skip was filename-based, so plugins/forge-kit-testing/agents/test-automator.md was excluded
# from the scan entirely. Only this directory's own contract tests are fixtures.
mk "$T/named/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/named/plugins/g/agents/test-automator.md" <<'M'
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template; do :; done)
M
bash "$SCRIPT" "$T/named" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a component whose name starts with test- is still scanned" \
  || bad "test-named components are scanned"

# --- round 2: a divergent copy must never VANISH from the comparison ----------------------------
# Splitting a run at the canon's first entry dropped any resulting group below the threshold, so a
# host-reordered copy (Gitea first) produced only sub-threshold fragments and disappeared: the
# guard then reported "1 sites, all carrying the same order" and exited 0. That is the #61 defect
# class passing green, which is strictly worse than the merge the split was added to fix.
mk "$T/vanish/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/vanish/b.md" <<'M'
TPL_DIR=$(for d in .gitea/ISSUE_TEMPLATE .gitea/issue_template .github/ISSUE_TEMPLATE .forgejo/ISSUE_TEMPLATE .forgejo/issue_template; do :; done)
M
out=$(bash "$SCRIPT" "$T/vanish" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a host-reordered copy is compared, not dropped" \
  || bad "a reordered copy vanishes from the comparison (rc=$rc)"
case "$out" in *b.md*) ok "and the vanishing copy is named" ;;
               *) bad "names the reordered copy (got: $out)" ;; esac

# --- round 2: prose that enumerates the directories with "and" is not a site ---------------------
# A sentence listing them comma-separated with "and" before the last leaves a four-token run of
# pure punctuation, which the guard read as a divergent 4-entry ordering. forge-host's reference
# already has a sentence of that shape.
mk "$T/andprose/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/andprose/b.md" <<'M'
Forgejo reads `.forgejo/ISSUE_TEMPLATE`, `.forgejo/issue_template`, `.gitea/ISSUE_TEMPLATE`,
`.gitea/issue_template` and `.github/ISSUE_TEMPLATE` depending on version.
M
bash "$SCRIPT" "$T/andprose" >/dev/null 2>&1
[ $? -eq 0 ] && ok "prose enumerating the dirs with 'and' is not flagged" \
  || bad "an 'and' list in prose is not a site"

# --- round 2: a copy laid out as a markdown table must still be seen ----------------------------
mk "$T/table/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/table/b.md" <<'M'
| .gitea/ISSUE_TEMPLATE | .gitea/issue_template | .github/ISSUE_TEMPLATE | .forgejo/ISSUE_TEMPLATE | .forgejo/issue_template |
M
bash "$SCRIPT" "$T/table" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a table-formatted copy is scanned, not invisible" || bad "table copies are scanned"

# --- round 3: a correct copy followed by a SHORT mention must not read as one divergent site ----
# The merged-run fallback reported the whole run whenever the split did not yield all-full groups,
# so a canonical copy trailed by a two-directory mention became one seven-entry "site" and failed
# the build on content that is correct.
mk "$T/tail/a.sh" <<M
  for d in $CANON; do :; done
M
mk "$T/tail/b.md" <<M
# $CANON
# .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE
M
bash "$SCRIPT" "$T/tail" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a canonical copy followed by a short mention still passes" \
  || bad "a trailing short mention does not corrupt the copy before it"

# --- round 3: deleting every copy must NOT read as agreement ------------------------------------
# Scanning the guard's own CANON tuple meant the site list was never empty, so a tree with every
# real copy removed exited 0 saying "1 sites, all carrying the same order", contradicting the
# guard's own header. The definition is not a copy and is no longer counted as one.
mk "$T/onlyguard/x.md" <<'M'
nothing here names a template directory
M
bash "$SCRIPT" "$T/onlyguard" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a tree with no copies fails even though the guard knows the canon" \
  || bad "an empty tree must not read as agreement"

# --- fail closed on a missing root ---------------------------------------------------------------
bash "$SCRIPT" "$T/does-not-exist" >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing root fails closed with exit 2" || bad "missing root fails closed"

# --- the real repo must agree across all its sites ----------------------------------------------
out=$(bash "$SCRIPT" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "this repo's sites all carry the same order" || bad "repo sites agree ($out)"
# EXACTLY six, which pins the count as well as the agreement. Without this, a site edited down to
# three entries would simply drop out of the comparison and the guard would report agreement among
# the survivors. The ticket said four; the guard found dep-auditor.md and the lockstep header too.
# Anchored: a bare substring also matched "16 sites", which is the opposite of pinning a count.
# EXACTLY six, which pins the count as well as the agreement. The guard holds the definition and
# is not scanned as a copy of it: counting itself made the site list impossible to empty, so a tree
# with every copy deleted read as agreement.
case "$out" in "check-template-dir-order: 6 sites,"*) ok "and it finds exactly the six copies" ;;
               *) bad "finds exactly six sites (got: $out)" ;; esac

# --- inside a git checkout, only TRACKED files are in scope (#142) ------------------------------
# Latent when filed, and the hand-maintained exclude list is why: it had to be extended every time
# a new gitignored runtime store appeared, and a copy of a diff written into .superpowers/sdd/ by
# /full-review had already made this guard report three bogus orders on content git never carries.
# The list is now DELETED rather than extended, which is the acceptance criterion.
R="$T/repo"
mkdir -p "$R"
( cd "$R" && git init -q . && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1
mk "$R/a.sh" <<M
TPL_DIR=\$(for d in $CANON; do :; done)
M
mk "$R/b.sh" <<M
resolve order: $CANON
M
( cd "$R" && git add -A && git commit -q -m base ) >/dev/null 2>&1
bash "$SCRIPT" "$R" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "two tracked sites that agree pass inside a checkout" \
                || bad "two tracked sites that agree pass inside a checkout"

# A gitignored runtime store carrying a REORDERED copy: exactly the shape that produced bogus
# failures, on content CI will never see.
# A directory that is NOT on the guard's hand-maintained exclude list, so this case is red against
# the current implementation rather than passing because someone already added the name.
mk "$R/.gitignore" <<'M'
vendor/
M
mk "$R/vendor/diff.md" <<'M'
TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template; do :; done)
M
( cd "$R" && git add .gitignore && git commit -q -m ignore ) >/dev/null 2>&1
bash "$SCRIPT" "$R" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "a gitignored copy with a DIFFERENT order does not fail the guard" \
                || bad "a gitignored copy still makes the local verdict differ from CI's"

# The same content tracked must still fail. Scope, not amnesty.
( cd "$R" && git add -f vendor/diff.md && git commit -q -m tracked ) >/dev/null 2>&1
bash "$SCRIPT" "$R" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "and the identical content TRACKED still fails" \
                || bad "a tracked divergent order stopped failing"
( cd "$R" && git rm -q --cached vendor/diff.md && git commit -q -m untrack ) >/dev/null 2>&1

# The exclude list is deleted, not extended: the guard must no longer name those directories.
# Keyed on the CONSTRUCT, not on the directory names: those still appear in the comment explaining
# why the list was deleted, and a test that forbade the explanation would be forbidding the reason.
grep -q 'dirnames\[:\]' "$SCRIPT" \
  && bad "the hand-maintained exclude list is gone, not extended" \
  || ok "the hand-maintained exclude list is gone, not extended"

# --- the reported LINE for the second copy in a merged run (#143) -------------------------------
# Two copies separated only by punctuation are ONE regex match, and the line number was computed
# once per match and reused for every site extracted from it. The verdict and the file were right;
# only the line was wrong, which costs the reader time in exactly the moment the guard is trying to
# save it.
L="$T/lines"
mk "$L/a.md" <<M
first line of filler
second line of filler
$CANON,
.forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE .forgejo/issue_template .gitea/issue_template
M
out=$(bash "$SCRIPT" "$L" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a divergent second copy still fails" || bad "a divergent second copy still fails (rc=$rc)"
printf '%s' "$out" | grep -q 'a\.md:4' \
  && ok "and is reported at ITS line, not the first copy's" \
  || bad "the second copy is reported at the wrong line (want a.md:4, got: $(printf '%s' "$out" | grep -o 'a\.md:[0-9]*' | tr '\n' ' '))"
printf '%s' "$out" | grep -q 'a\.md:3' \
  && ok "and the canonical copy keeps its own line" || bad "the canonical copy lost its line"

echo ""
echo "template-dir-order tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
