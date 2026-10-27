#!/usr/bin/env bash
# Contract test for check-template-lockstep.sh (shipped from forge-kit-adapt's assets, #506; this suite is
# kit-only and is no longer copied into a project).
# Builds fixture template dirs and asserts the guard's exit code:
#   all markers equal            -> 0 (locked)
#   any marker diverges          -> 1 (drift, listed)
#   unmarked template            -> exempt (e.g. contribution.yml)
#   fewer than 2 versioned files -> 0 (nothing to lock)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../plugins/forge-kit-adapt/skills/adapt/assets/check-template-lockstep.sh"

pass=0
fail=0

# mk <dir> <name> <version|->   ("-" writes a template with NO marker)
mk() {
  local d="$1" name="$2" ver="$3"
  if [ "$ver" = "-" ]; then
    printf 'name: %s\nbody: []\n' "$name" > "$d/$name.yml"
  else
    printf 'name: %s\n        <!-- template-version: %s -->\nbody: []\n' "$name" "$ver" > "$d/$name.yml"
  fi
}

# run <desc> <expected-exit> <dir> [canonical-doc]
run() {
  bash "$SCRIPT" "$3" ${4:+"$4"} >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq "$2" ]; then
    echo "  ok: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1 (expected exit $2, got $rc)"
    fail=$((fail + 1))
  fi
}

t=$(mktemp -d)

d="$t/eq"; mkdir -p "$d"
mk "$d" feature 4; mk "$d" bug 4; mk "$d" security 4
run "all templates at the same version passes" 0 "$d"

d="$t/drift"; mkdir -p "$d"
mk "$d" feature 5; mk "$d" bug 4; mk "$d" security 4
run "one lagging template fails" 1 "$d"

d="$t/exempt"; mkdir -p "$d"
mk "$d" feature 4; mk "$d" bug 4; mk "$d" contribution -
run "an unmarked template is exempt" 0 "$d"

d="$t/single"; mkdir -p "$d"
mk "$d" feature 4
run "a single versioned template has nothing to lock" 0 "$d"

d="$t/mixdrift"; mkdir -p "$d"
mk "$d" feature 4; mk "$d" bug 5; mk "$d" contribution -
run "drift is caught even with an exempt file present" 1 "$d"

d="$t/withdoc"; mkdir -p "$d"
mk "$d" feature 4; mk "$d" bug 4
printf 'canonical\n<!-- template-version: 4 -->\n' > "$t/doc-ok.md"
run "canonical doc at the matching version passes" 0 "$d" "$t/doc-ok.md"

printf 'canonical\n<!-- template-version: 5 -->\n' > "$t/doc-drift.md"
run "canonical doc at a different version fails" 1 "$d" "$t/doc-drift.md"

# Issue #61: forge-adapt (v<=34) installed Forgejo templates to the LOWERCASE
# .forgejo/issue_template, which resolve_dir did not accept, so on such repos the guard
# printed "nothing to check" and exited 0 over drifted templates. Legacy lowercase
# installs must be resolved. Needs the no-arg (CI) invocation, so fixtures are git repos.
lc="$t/lowercase-repo"; mkdir -p "$lc/.forgejo/issue_template"
git -C "$lc" init -q
mk "$lc/.forgejo/issue_template" feature 4
mk "$lc/.forgejo/issue_template" bug 99
out=$( (cd "$lc" && bash "$SCRIPT" 2>&1) ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'DRIFT' <<< "$out"; then
  echo "  ok: lowercase .forgejo/issue_template is resolved and drift is caught"
  pass=$((pass + 1))
else
  echo "  FAIL: lowercase .forgejo/issue_template drift (expected exit 1 + DRIFT report, got exit $rc)"
  fail=$((fail + 1))
fi

# Ordering is HOST-grouped, not case-grouped: a repo migrated GitHub->Forgejo that kept a
# stale .github/ISSUE_TEMPLATE while its live templates sit in legacy .forgejo/issue_template
# must have the LIVE Forgejo dir checked, not the stale GitHub one.
mg="$t/migrated-repo"; mkdir -p "$mg/.github/ISSUE_TEMPLATE" "$mg/.forgejo/issue_template"
git -C "$mg" init -q
mk "$mg/.github/ISSUE_TEMPLATE" feature 4
mk "$mg/.github/ISSUE_TEMPLATE" bug 4
mk "$mg/.forgejo/issue_template" feature 4
mk "$mg/.forgejo/issue_template" bug 99
out=$( (cd "$mg" && bash "$SCRIPT" 2>&1) ); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'forgejo/issue_template' <<< "$out"; then
  echo "  ok: live legacy Forgejo dir outranks a stale .github dir (host-grouped order)"
  pass=$((pass + 1))
else
  echo "  FAIL: migrated-repo ordering (expected exit 1 checking .forgejo/issue_template, got exit $rc)"
  fail=$((fail + 1))
fi

# When BOTH casings exist, uppercase is canonical and wins; a warning names the other dir.
# Uppercase in lockstep + lowercase drifted must pass (proves uppercase was selected) and
# warn (proves the duplicate is surfaced rather than silently first-matched).
bc="$t/bothcase-repo"; mkdir -p "$bc/.forgejo/ISSUE_TEMPLATE" "$bc/.forgejo/issue_template"
git -C "$bc" init -q
if [ "$bc/.forgejo/ISSUE_TEMPLATE" -ef "$bc/.forgejo/issue_template" ]; then
  # Case-insensitive filesystem (macOS/Windows): the two casings are ONE directory, so the
  # both-casings scenario cannot be constructed here. The guard itself handles that FS via
  # the -ef check; skip rather than fail.
  echo "  ok: both-casings case skipped (case-insensitive filesystem)"
  pass=$((pass + 1))
else
mk "$bc/.forgejo/ISSUE_TEMPLATE" feature 4
mk "$bc/.forgejo/ISSUE_TEMPLATE" bug 4
mk "$bc/.forgejo/issue_template" stale 99
out=$( (cd "$bc" && bash "$SCRIPT" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'WARNING.*issue_template' <<< "$out"; then
  echo "  ok: with both casings, uppercase wins and the duplicate dir is warned about"
  pass=$((pass + 1))
else
  echo "  FAIL: both-casings case (expected exit 0 + WARNING, got exit $rc)"
  fail=$((fail + 1))
fi
fi

# --- doc-rules-version is NOT locked (issue #94) --------------------------------------------
# ticket-standards.md carries two markers. `template-version` says which FORM it describes and IS
# locked to the templates; `doc-rules-version` says which revision its RULES TEXT is at and must be
# free to move on its own, or a prose clarification costs an auto-synthesis round trip over every
# open ticket, which is the coupling #94 removed.
mkdoc() {   # mkdoc <path> <template-version> <doc-rules-version|-> [reversed]
  { if [ "${4:-}" = reversed ]; then
      [ "$3" = "-" ] || printf '<!-- doc-rules-version: %s -->\n' "$3"
      printf '<!-- template-version: %s -->\n' "$2"
    else
      printf '<!-- template-version: %s -->\n' "$2"
      [ "$3" = "-" ] || printf '<!-- doc-rules-version: %s -->\n' "$3"
    fi
    printf '\n# Ticket standards\n'; } > "$1"
}

d="$t/two-markers"; mkdir -p "$d"
mk "$d" feature 5; mk "$d" bug 5
mkdoc "$t/doc-a.md" 5 1
run "a doc carrying both markers, in lockstep, passes" 0 "$d" "$t/doc-a.md"

mkdoc "$t/doc-b.md" 5 9
run "doc-rules-version may differ from template-version without drift" 0 "$d" "$t/doc-b.md"

# ORDER-REVERSED on purpose. With template-version written first, a loose `[a-z-]*-version`
# pattern still finds it, so the assertion would pass for the wrong reason and could not detect
# the very mutation it exists to catch (verified: that mutant survived until this fixture existed).
# Putting doc-rules-version first makes the guard's LITERAL pattern the only reason it passes.
mkdoc "$t/doc-c.md" 5 9 reversed
run "the guard reads template-version by name, not by position" 0 "$d" "$t/doc-c.md"

mkdoc "$t/doc-c2.md" 4 5 reversed
run "...and still catches drift when the markers are reversed" 1 "$d" "$t/doc-c2.md"

mkdoc "$t/doc-d.md" 4 1
run "template-version drift is still caught when both markers are present" 1 "$d" "$t/doc-d.md"

# --- #538: bash 3.2 and POSIX grep/sed -------------------------------------------------------
# The guard once used `grep -P` and `declare -A`. Under a grep without -P, or under stock macOS bash
# 3.2, it printed an error and then "fewer than 2 versioned files; nothing to lock" and EXITED 0 over
# drift. Every case below therefore asserts exit 1 with the DRIFT report, not merely "no crash".
mkdir -p "$t/shim"
REALGREP="$(command -v grep)"
# Rejects -P in any spelling (-P, -oP, -o -P, --perl-regexp); delegates every other call to the real grep.
cat > "$t/shim/grep" <<SHIM
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    --perl-regexp|-P|-[A-Za-z]*P*) echo "grep: invalid option -- P" >&2; exit 2 ;;
  esac
done
exec "$REALGREP" "\$@"
SHIM
chmod +x "$t/shim/grep"

d="$t/shim-drift"; mkdir -p "$d"
mk "$d" feature 6; mk "$d" bug 5
out=$(PATH="$t/shim:$PATH" bash "$SCRIPT" "$d" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'template-version DRIFT' <<< "$out" && ! grep -q 'invalid option' <<< "$out"; then
  echo "  ok: under a grep that rejects -P a 6 vs 5 fixture exits 1 with the DRIFT report"; pass=$((pass + 1))
else
  echo "  FAIL: -P-rejecting grep shim, drifted fixture (expected exit 1 + DRIFT, got exit $rc): $out"; fail=$((fail + 1))
fi
d="$t/shim-eq"; mkdir -p "$d"
mk "$d" feature 6; mk "$d" bug 6
out=$(PATH="$t/shim:$PATH" bash "$SCRIPT" "$d" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'all 2 versioned files at template-version 6\.' <<< "$out"; then
  echo "  ok: under the same shim a locked fixture prints the lockstep line"; pass=$((pass + 1))
else
  echo "  FAIL: -P-rejecting grep shim, locked fixture (expected exit 0 + 'all 2 versioned files'): $out"; fail=$((fail + 1))
fi

# First marker on a line wins; the marker needs exactly one space (the gate's readers agree).
d="$t/twomark"; mkdir -p "$d"
printf 'name: a\n<!-- template-version: 5 --> <!-- template-version: 6 -->\n' > "$d/a.yml"
mk "$d" b 5
run "a line carrying markers 5 then 6 is read as 5 (first wins), beside a 5" 0 "$d"
d="$t/twomark-drift"; mkdir -p "$d"
printf 'name: a\n<!-- template-version: 5 --> <!-- template-version: 6 -->\n' > "$d/a.yml"
mk "$d" b 6
out=$(bash "$SCRIPT" "$d" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -q '  v5  .*a\.yml' <<< "$out"; then
  echo "  ok: 5 then 6 beside a 6 is drift and the template is listed at v5"; pass=$((pass + 1))
else
  echo "  FAIL: two markers beside a 6 (expected exit 1 listing v5, got exit $rc): $out"; fail=$((fail + 1))
fi
d="$t/nospace"; mkdir -p "$d"
printf 'name: a\n<!-- template-version:7 -->\n' > "$d/a.yml"
mk "$d" b 6; mk "$d" c 6
run "template-version:7 with no space is unversioned, so it cannot cause drift" 0 "$d"

# The bash 3.2 proof. Run the guard by EXPLICIT PATH under the harness bash: running this whole suite
# with the harness bash proves nothing, because run() takes bash from PATH (use
# PATH="$H:$PATH" bash scripts/test-template-lockstep.sh for that). Skipped, and counted as a pass,
# when the harness is not built, so CI does not depend on it.
H="$(bash "$HERE/build-mac-shell-harness.sh" --bin-dir 2>/dev/null || true)"
if [ -z "$H" ] || [ ! -x "$H/bash" ]; then
  echo "  ok: bash 3.2 drift case skipped (mac shell harness not built)"; pass=$((pass + 1))
else
  d="$t/b32-drift"; mkdir -p "$d"
  mk "$d" feature 6; mk "$d" bug 5
  printf 'canonical\n<!-- template-version: 6 -->\n' > "$t/b32-doc.md"
  out=$("$H/bash" "$SCRIPT" "$d" "$t/b32-doc.md" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'template-version DRIFT' <<< "$out" && grep -q '  v5  .*bug\.yml' <<< "$out" \
     && ! grep -q 'declare:' <<< "$out" && ! grep -q 'nothing to lock' <<< "$out"; then
    echo "  ok: under bash 3.2 (explicit harness path) a drifted fixture exits 1 and lists v5"; pass=$((pass + 1))
  else
    echo "  FAIL: bash 3.2 drifted fixture (expected exit 1 + DRIFT + v5, got exit $rc): $out"; fail=$((fail + 1))
  fi
fi

# Static ban, comment-stripped (the header names the banned tools on purpose). Mutants prove each ban bites.
ban_count() { grep -v '^[[:space:]]*#' "$1" | grep -cE "$2"; }
BAN_P='grep [^|]*-[A-Za-z]*P'
BAN_A='declare -A'
if [ "$(ban_count "$SCRIPT" "$BAN_P")" -eq 0 ]; then echo "  ok: the guard's code has no grep -P"; pass=$((pass + 1))
else echo "  FAIL: the guard's code uses grep -P"; fail=$((fail + 1)); fi
if [ "$(ban_count "$SCRIPT" "$BAN_A")" -eq 0 ]; then echo "  ok: the guard's code has no associative array"; pass=$((pass + 1))
else echo "  FAIL: the guard's code uses declare -A"; fail=$((fail + 1)); fi
for spelling in 'grep -oP x' 'grep -o -P x' 'grep -P x' 'grep -E -oP x'; do
  { cat "$SCRIPT"; printf '%s\n' "$spelling"; } > "$t/mut.sh"
  if [ "$(ban_count "$t/mut.sh" "$BAN_P")" -ge 1 ]; then echo "  ok: mutant '$spelling' trips the grep -P ban"; pass=$((pass + 1))
  else echo "  FAIL: mutant '$spelling' slipped past the grep -P ban"; fail=$((fail + 1)); fi
done
{ cat "$SCRIPT"; printf 'declare -A m=()\n'; } > "$t/mut.sh"
if [ "$(ban_count "$t/mut.sh" "$BAN_A")" -ge 1 ]; then echo "  ok: mutant 'declare -A' trips the associative-array ban"; pass=$((pass + 1))
else echo "  FAIL: mutant 'declare -A' slipped past the ban"; fail=$((fail + 1)); fi
{ cat "$SCRIPT"; printf '# grep -oP and declare -A named in a comment\n'; } > "$t/mut.sh"
if [ "$(ban_count "$t/mut.sh" "$BAN_P")" -eq 0 ] && [ "$(ban_count "$t/mut.sh" "$BAN_A")" -eq 0 ]; then
  echo "  ok: a comment naming the banned tools does not trip the bans"; pass=$((pass + 1))
else echo "  FAIL: the bans fire on comments"; fail=$((fail + 1)); fi

rm -rf "$t"

# The no-arg path is what CI invokes: it resolves the template dir and the canonical doc
# itself. Exercise it against the real repo (which is in lockstep) so a regression in
# resolve_dir or the default-doc wiring cannot ship green.
if bash "$SCRIPT" >/dev/null 2>&1; then
  echo "  ok: no-arg run resolves the real repo and passes"
  pass=$((pass + 1))
else
  echo "  FAIL: no-arg run against the real repo (expected exit 0)"
  fail=$((fail + 1))
fi

# #506: the guard is a shipped asset, so it carries the version marker drift compares.
if grep -qE '^# check-template-lockstep-version: [0-9]+$' "$SCRIPT"; then
  echo "  ok: the guard carries its version marker"; pass=$((pass + 1))
else
  echo "  FAIL: the guard has no '# check-template-lockstep-version: N' line"; fail=$((fail + 1))
fi

# #506: a repository root that cannot be entered fails closed (exit 2) instead of running from the
# wrong directory and reporting "no ISSUE_TEMPLATE directory found; nothing to check" as a pass.
st=$(mktemp -d); mkdir -p "$st/bin" "$st/cwd"
printf '#!/bin/sh\necho "%s/does-not-exist"\n' "$st" > "$st/bin/git"; chmod +x "$st/bin/git"
out=$(cd "$st/cwd" && PATH="$st/bin:$PATH" bash "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "  ok: an unenterable repository root exits 2"; pass=$((pass + 1))
else
  echo "  FAIL: an unenterable repository root (expected exit 2, got $rc)"; fail=$((fail + 1))
fi
case "$out" in
  *"check-template-lockstep: cannot enter the repository root"*) echo "  ok: ...and says why"; pass=$((pass + 1)) ;;
  *) echo "  FAIL: no 'cannot enter the repository root' line: $out"; fail=$((fail + 1)) ;;
esac
case "$out" in
  *"nothing to check"*) echo "  FAIL: it still reported a vacuous pass: $out"; fail=$((fail + 1)) ;;
  *) echo "  ok: ...and never reports a vacuous pass"; pass=$((pass + 1)) ;;
esac
rm -rf "$st"

# #568: the guard compares integers, never text; that limit is stated where a vendored copy and
# the rules doc are read, so a downstream editor knows copied wording is kept in step by hand.
if grep -qF 'compares the template-version INTEGERS only, never the text' "$SCRIPT"; then
  echo "  ok: the guard header states it never compares text"; pass=$((pass + 1))
else
  echo "  FAIL: the guard header lacks the integers-only scope sentence"; fail=$((fail + 1))
fi
if grep -qF 'The lockstep guard compares the two integers, never the' "$HERE/../docs/guides/ticket-standards.md"; then
  echo "  ok: ticket-standards states the guard never compares text"; pass=$((pass + 1))
else
  echo "  FAIL: ticket-standards lacks the integers-only sentence"; fail=$((fail + 1))
fi

echo ""
echo "template-lockstep tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
