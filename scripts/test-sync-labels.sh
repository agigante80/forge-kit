#!/usr/bin/env bash
# Contract test for forge-host/assets/sync-labels.sh (issue #104).
#
# Driven with a STUBBED forge-lib.sh placed next to a copy of the script, so the script sources the
# stub instead of the real transport. Nothing here touches a network or a real forge. This is the
# same shape as test-forge-lib.sh's stubbed `forge_api`, one level out: there the library was under
# test, here the library IS the seam.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/sync-labels.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$SRC" "$T/sync-labels.sh"

cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf '%s' "${STUB_HOST:-github}"; }
forge_api_paginate() {
  # Mirrors the REAL forge-lib: it short-circuits to [] under dry run. The old stub ignored the
  # flag, which is exactly why H2 (a dry run reporting every label missing) was invisible to the
  # 22 tests. A stub that is kinder than the library it stands in for tests nothing.
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[dry-run] paginate\n' >&2; printf '[]'; return 0; fi
  cat "$HOST_LABELS"
}
forge_api() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >> "$REQLOG"; printf '{}'; }
STUB

# declared <file> <<'Y' ... Y   writes a labels.yml fixture
host_json() { printf '%s' "$1" > "$T/host.json"; }

run() {  # run [args...] -> $out, $rc, and $REQLOG holds every write attempted
  REQLOG="$T/req.log"; : > "$REQLOG"
  out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
        bash ./sync-labels.sh --labels "$T/labels.yml" "$@" 2>&1); rc=$?
}

cat > "$T/labels.yml" <<'Y'
- name: bug
  color: "d73a4a"
  description: Something isn't working

- name: security
  color: "e4e669"
  description: Security vulnerability or hardening
Y

# --- 1. host matches the declaration ----------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"Security vulnerability or hardening"}]'
run --check
[ "$rc" -eq 0 ] && ok "--check passes when the host matches" || bad "--check passes when host matches (rc=$rc: $out)"
[ ! -s "$REQLOG" ] && ok "--check writes nothing" || bad "--check writes nothing (log: $(cat "$REQLOG"))"

# --- 2. a declared label the host lacks -------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"}]'
run --check
[ "$rc" -ne 0 ] && ok "--check fails when a declared label is absent" || bad "--check fails on absent (rc=$rc)"
printf '%s' "$out" | grep -q 'missing  security' && ok "--check names the absent label" || bad "--check names the absent label"
# The load-bearing one: --check must write NOTHING even when a write is exactly what sync would do
# here. The original suite only asserted this against an already-matching host, where neither mode
# writes, so it passed for the wrong reason and a mutant removing both write guards survived.
[ ! -s "$REQLOG" ] && ok "--check writes nothing WHEN A WRITE IS DUE (absent label)" \
  || bad "--check writes nothing when a write is due (log: $(cat "$REQLOG"))"

# --- 3. sync creates it, with the declared colour and description ------------------------------
run
[ "$rc" -eq 0 ] && ok "sync exits 0 after creating" || bad "sync exits 0 (rc=$rc: $out)"
grep -q '^POST /repos/o/r/labels ' "$REQLOG" && ok "sync POSTs the missing label" || bad "sync POSTs the missing label"
grep -q '"name":"security"' "$REQLOG" && grep -q '"color":"e4e669"' "$REQLOG" \
  && ok "the created label carries its declared colour" || bad "created label carries its colour"
grep -q '"description":"Security vulnerability or hardening"' "$REQLOG" \
  && ok "the created label carries its declared description" \
  || bad "created label carries its description (log: $(cat "$REQLOG"))"

# --- 4. drift in the description --------------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"WRONG"}]'
run --check
[ "$rc" -ne 0 ] && ok "--check fails on a drifted description" || bad "--check fails on drifted description"
printf '%s' "$out" | grep -q 'drifted  security' && ok "--check names the drifted label" || bad "--check names the drifted label"
[ ! -s "$REQLOG" ] && ok "--check writes nothing when a label has DRIFTED" \
  || bad "--check writes nothing on drift (log: $(cat "$REQLOG"))"

# Description comparison is exact, case included: a case change IS drift, unlike colour.
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"SECURITY VULNERABILITY OR HARDENING"}]'
run --check
[ "$rc" -ne 0 ] && ok "a case-only description change is drift" || bad "a case-only description change is drift"

# --- 5. drift in the colour -------------------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"000000","description":"Security vulnerability or hardening"}]'
run --check
[ "$rc" -ne 0 ] && ok "--check fails on a drifted colour" || bad "--check fails on drifted colour"

# --- 6. colour CASE is not drift --------------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"D73A4A","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"#E4E669","description":"Security vulnerability or hardening"}]'
run --check
[ "$rc" -eq 0 ] && ok "colour case and a leading # are not drift" || bad "colour case is not drift (rc=$rc: $out)"

# --- 7. an undeclared label is reported and NEVER deleted -------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"Security vulnerability or hardening"},
            {"id":9,"name":"wontfix","color":"ffffff","description":"stock default"}]'
run
printf '%s' "$out" | grep -q 'extra    wontfix' && ok "an undeclared label is reported" || bad "an undeclared label is reported"
grep -qi 'DELETE' "$REQLOG" && bad "sync never DELETEs" || ok "sync never DELETEs"
[ "$rc" -eq 0 ] && ok "an undeclared label is not itself a failure" || bad "an undeclared label is not a failure (rc=$rc)"

# The extra report matches whole lines: `bug` declared must not suppress `bugfix` on the host.
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"Security vulnerability or hardening"},
            {"id":3,"name":"bugfix","color":"ffffff","description":"x"}]'
run
printf '%s' "$out" | grep -q 'extra    bugfix' \
  && ok "a host label that merely CONTAINS a declared name is still reported extra" \
  || bad "substring host label reported extra (out: $out)"

# --- 8. update addresses the label by NAME on github, by ID on forgejo -------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":42,"name":"security","color":"e4e669","description":"WRONG"}]'
run
grep -q '^PATCH /repos/o/r/labels/security ' "$REQLOG" \
  && ok "github updates a label by name" || bad "github updates by name (log: $(cat "$REQLOG"))"
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" STUB_HOST=forgejo \
      bash ./sync-labels.sh --labels "$T/labels.yml" 2>&1); rc=$?
grep -q '^PATCH /repos/o/r/labels/42 ' "$REQLOG" \
  && ok "forgejo updates a label by id" || bad "forgejo updates by id (log: $(cat "$REQLOG"))"

# --- 9. dry run sends nothing -----------------------------------------------------------------
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"}]'
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" FORGE_DRY_RUN=1 \
      bash ./sync-labels.sh --labels "$T/labels.yml" 2>&1); rc=$?
[ ! -s "$REQLOG" ] && ok "FORGE_DRY_RUN=1 sends nothing" || bad "dry run sends nothing (log: $(cat "$REQLOG"))"
printf '%s' "$out" | grep -q "\[dry-run\] create label 'security'" \
  && ok "dry run says what it would create" || bad "dry run says what it would create"

# --- 8b. value cleaning: a file a maintainer could plausibly commit ----------------------------
# Each of these is valid YAML that the first version wrote to the host verbatim, creating phantom
# labels ("bug " with a trailing space) or never converging (a re-PATCH on every run).
clean_case() {  # clean_case <desc> <printf-format-for-labels.yml> <expected-json-fragment>
  printf -- "$2" > "$T/labels.clean.yml"
  host_json '[]'
  REQLOG="$T/req.log"; : > "$REQLOG"
  (cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
     bash ./sync-labels.sh --labels "$T/labels.clean.yml" >/dev/null 2>&1)
  grep -qF "$3" "$REQLOG" && ok "$1" || bad "$1 (log: $(cat "$REQLOG"))"
}
clean_case "trailing whitespace is trimmed, not made part of the name" \
  '- name: bug \n  color: "d73a4a" \n  description: Something \n' \
  '{"name":"bug","color":"d73a4a","description":"Something"}'
clean_case "a CRLF file does not produce carriage returns in the values" \
  '- name: bug\r\n  color: "d73a4a"\r\n  description: Something\r\n' \
  '{"name":"bug","color":"d73a4a","description":"Something"}'
clean_case "a trailing # comment is stripped from a quoted value" \
  '- name: bug\n  color: "d73a4a"  # red\n  description: Something # note\n' \
  '{"name":"bug","color":"d73a4a","description":"Something"}'
clean_case "a # INSIDE quotes is data, not a comment" \
  '- name: bug\n  color: "d73a4a"\n  description: "tag #1 issues"\n' \
  '{"name":"bug","color":"d73a4a","description":"tag #1 issues"}'
clean_case "single-quoted YAML is unquoted and '"''"' is unescaped" \
  "- name: bug\n  color: 'd73a4a'\n  description: 'Something isn''t working'\n" \
  '{"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"}'

# A colour that is not 6 hex digits refuses the whole run: that single check catches every
# mangling shape above if the cleaning ever regresses.
printf -- '- name: bug\n  color: "not-a-colour"\n  description: X\n' > "$T/labels.clean.yml"
host_json '[]'; REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
      bash ./sync-labels.sh --labels "$T/labels.clean.yml" 2>&1); rc=$?
[ "$rc" -eq 3 ] && [ ! -s "$REQLOG" ] \
  && ok "a non-hex colour refuses with exit 3 and writes nothing" \
  || bad "non-hex colour refuses (rc=$rc, log: $(cat "$REQLOG"))"

# --- 8c. idempotency (AC2): a second run against the resulting state writes nothing -------------
cat > "$T/labels.idem.yml" <<'Y'
- name: bug
  color: "d73a4a"
  description: Something
Y
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something"}]'
REQLOG="$T/req.log"; : > "$REQLOG"
(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.idem.yml" >/dev/null 2>&1)
(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.idem.yml" >/dev/null 2>&1)
[ ! -s "$REQLOG" ] && ok "sync is idempotent: an in-sync host is written to twice, never" \
  || bad "sync is idempotent (log: $(cat "$REQLOG"))"

# --- 8d. the separator and the refusals, which had NO test at all -------------------------------
# Round 2 found that 9 of 17 mutations survived the suite, including US=$'"'"'\\x1f'"'"' -> US=$'"'"'\\t'"'"',
# which reverts H1 and re-commits its original silent wrong write. The gap was that no fixture had
# an EMPTY field, which is the only condition under which the separator choice is observable
# (tab is IFS whitespace, so `read` collapses runs of it and never yields an empty field).
# This description is 6 hex characters on purpose: under the TAB separator it lands in the colour
# field and passes hex validation, so the run would succeed with a wrong write.
exit_case() {  # exit_case <desc> <printf-fmt> <expected-rc> [expected-writes]
  printf -- "$2" > "$T/labels.x.yml"
  host_json '[]'; REQLOG="$T/req.log"; : > "$REQLOG"
  out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
        bash ./sync-labels.sh --labels "$T/labels.x.yml" 2>&1); rc=$?
  # `grep -c` PRINTS 0 and EXITS 1 on no match, so `|| echo 0` appended a second zero.
  w=$(wc -l < "$REQLOG" | tr -d " ")
  if [ "$rc" = "$3" ] && [ "$w" = "${4:-0}" ]; then ok "$1"
  else bad "$1 (rc=$rc want $3; writes=$w want ${4:-0}; $out)"; fi
}
exit_case "an entry with no color: refuses; its description is NOT read as the colour" \
  '- name: bug\n  description: deface\n' 3 0
exit_case "a bare '- name:' with no other fields refuses" \
  '- name: bug\n  color: "d73a4a"\n  description: X\n- name:\n' 3 0
exit_case "an empty name WITH other fields refuses" \
  '- name:\n  color: "ffffff"\n  description: ghost\n' 3 0
exit_case "a dot-only label name refuses (cannot escape a URL path segment)" \
  '- name: ..\n  color: "ffffff"\n  description: X\n' 3 0
exit_case "a #-prefixed colour is accepted, as GitHub shows it in its own UI" \
  '- name: bug\n  color: "#d73a4a"\n  description: X\n' 0 1

# A quoted value ends at its CLOSING quote, not its last one.
clean_case "a comment containing quotes does not extend the value" \
  '- name: bug\n  color: "d73a4a"\n  description: "needs triage" # see "triage" doc\n' \
  '{"name":"bug","color":"d73a4a","description":"needs triage"}'

# --- 8f. round-3 regressions in clean() --------------------------------------------------------
# A6: \" is YAML's escape for a literal quote inside a double-quoted scalar. index() cut at the
# ESCAPE, so `the \"critical\" label` was written as `the \` : a silent wrong write with a green
# suite, and a regression against the version before it.
clean_case "a backslash-escaped quote does not truncate the value" \
  '- name: bug\n  color: "d73a4a"\n  description: "the \\"critical\\" label"\n' \
  '{"name":"bug","color":"d73a4a","description":"the \"critical\" label"}'

# A8: `color: #d73a4a` is a COMMENT in YAML, so the value is null. Trimming before the comment
# strip removed the space the comment rule needs, and the leading-# strip then made it look valid.
# Any real YAML parser reads null here, so accepting it would make two tools disagree on one file.
exit_case "an unquoted # value is a YAML comment, not a colour" \
  '- name: bug\n  color: #d73a4a\n  description: X\n' 3 0
# ...while the QUOTED form stays accepted, which is what A1 was actually about.
exit_case "a QUOTED #-colour is still accepted" \
  '- name: bug\n  color: "#d73a4a"\n  description: X\n' 0 1

# A7: the guard globbed `...*`, which means "starts with three dots", not "dot-only". It refused
# `...and more` with a message calling it dot-only, and validation is all-or-nothing, so ONE such
# name failed the entire file. Only `.` and `..` resolve as path segments.
exit_case "a name merely STARTING with dots is not refused" \
  '- name: ...and more\n  color: "ffffff"\n  description: X\n' 0 1
exit_case "a leading-dot name like .github is not refused" \
  '- name: .github\n  color: "ffffff"\n  description: X\n' 0 1
exit_case "a bare .. is still refused" \
  '- name: ..\n  color: "ffffff"\n  description: X\n' 3 0

# --- 8g. the three silent acceptances from issue #122 ------------------------------------------
# Each of these was accepted with exit 0 and a plausible-looking write. The script's own principle
# is that a recognised line with a malformed VALUE must refuse like an unrecognised line SHAPE.
exit_case "an unterminated double-quoted value refuses" \
  '- name: bug\n  color: "d73a4a"\n  description: "unterminated\n' 3 0
exit_case "an unterminated single-quoted value refuses" \
  "- name: bug\n  color: 'd73a4a'\n  description: 'unterminated\n" 3 0
exit_case "a duplicate declared name refuses before any write" \
  '- name: bug\n  color: "d73a4a"\n  description: X\n- name: bug\n  color: "ffffff"\n  description: Y\n' 3 0
# ...and the boundary: a correctly terminated quote containing an ESCAPED quote still works.
clean_case "an escaped quote is not mistaken for an unterminated value" \
  '- name: bug\n  color: "d73a4a"\n  description: "the \\"x\\" label"\n' \
  '{"name":"bug","color":"d73a4a","description":"the \"x\" label"}'

out=$(cd "$T" && bash ./sync-labels.sh --labels "" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'empty value' \
  && ok "an empty --labels value is a usage error, not silent auto-discovery" \
  || bad "empty --labels value exits 2 (rc=$rc: $out)"
out=$(cd "$T" && HOST_LABELS="$T/host.json" bash ./sync-labels.sh --labels "$T/labels.yml" --repo "" 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "an empty --repo value is a usage error" || bad "empty --repo value exits 2 (rc=$rc)"

# --- 8h. one jq pass, not one per label field (issue #121) --------------------------------------
# host_field used to spawn jq 3 or 4 times per declared label. The lookup must be built once, and
# behaviour must be identical: absent yields empty, a null description yields the empty string.
mkdir -p "$T/bin"
printf '#!/bin/sh\necho x >> "$JQLOG"\nexec %s "$@"\n' "$(command -v jq)" > "$T/bin/jq"; chmod +x "$T/bin/jq"
python3 -c "
import json
labels=[{'id':i,'name':'l%02d'%i,'color':'aabbcc','description':'d%d'%i} for i in range(20)]
open('$T/host.json','w').write(json.dumps(labels))
open('$T/labels.many.yml','w').write(''.join('- name: l%02d\n  color: \"aabbcc\"\n  description: d%d\n\n'%(i,i) for i in range(20)))"
: > "$T/jq.log"; REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && PATH="$T/bin:$PATH" JQLOG="$T/jq.log" HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
      bash ./sync-labels.sh --labels "$T/labels.many.yml" --check 2>&1); rc=$?
n=$(wc -l < "$T/jq.log" | tr -d ' ')
[ "$rc" -eq 0 ] && ok "20 in-sync labels report clean" || bad "20 in-sync labels report clean (rc=$rc: $out)"
[ "$n" -le 5 ] && ok "jq runs a FIXED number of times, not per label ($n for 20 labels)" \
  || bad "jq is not per-label (ran $n times for 20 labels)"
# A null description on the host must still compare equal to an empty declared description.
host_json '[{"id":1,"name":"bare","color":"aabbcc","description":null}]'
printf -- '- name: bare\n  color: "aabbcc"\n  description:\n' > "$T/labels.null.yml"
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.null.yml" --check 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$REQLOG" ] \
  && ok "a null host description equals an empty declared one (no phantom drift)" \
  || bad "null description handling (rc=$rc: $out)"

# --- 8i. round-1 findings on the #121/#122 change ----------------------------------------------
# H1: bash 4 is a real new floor (the pre-#121 version ran on the bash 3.2 macOS ships). Unguarded,
# `declare -A` fails, the script continues without -e, and it exits 1, which this script defines as
# "check found drift" - so automation re-runs forever against a tooling fault. The guard must exit 2.
sed 's/${BASH_VERSINFO\[0\]:-0}/${FAKE_BASH_MAJOR:-9}/' "$SRC" > "$T/sl-fakever.sh"
printf -- '- name: bug\n  color: "ffffff"\n  description: X\n' > "$T/labels.one.yml"
host_json '[]'
out=$(cd "$T" && FAKE_BASH_MAJOR=3 HOST_LABELS="$T/host.json" REQLOG="$T/req.log" \
      bash ./sl-fakever.sh --labels "$T/labels.one.yml" --check 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "bash < 4 is an ENVIRONMENT error (2), never the drift code (1)" \
  || bad "bash < 4 exits 2 (rc=$rc: $out)"
printf '%s' "$out" | grep -q 'requires bash 4' && ok "...and says which version it found" \
  || bad "the bash-version message names the requirement"

# H2: `join` emits one LINE per label but `read` consumes one line, so a newline in a host
# description split the record: the id was lost and real drift was reported as IN SYNC. A declared
# description is single-line by construction, so a multi-line host one is drift by definition.
host_json '[{"id":7,"name":"bug","color":"ffffff","description":"one\ntwo"}]'
printf -- '- name: bug\n  color: "ffffff"\n  description: one\n' > "$T/labels.nl.yml"
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.nl.yml" --check 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a multi-line host description is reported as drift, not as in-sync" \
  || bad "multi-line host description is drift (rc=$rc: $out)"
REQLOG="$T/req.log"; : > "$REQLOG"
(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.nl.yml" >/dev/null 2>&1)
grep -q '^PATCH /repos/o/r/labels/' "$REQLOG" \
  && ok "...and sync repairs it, so the run converges" || bad "multi-line drift is repaired"

# The case that makes the multi-line FLAG load-bearing rather than decorative: newlines are
# flattened to spaces for storage, so a host description of "one\ntwo" flattens to "one two" and
# would compare EQUAL to a declared "one two". The host still differs from the declaration, so
# without the flag this reports in-sync forever. Found because a mutant removing the flag survived
# the test above, which the gsub alone already satisfied.
host_json '[{"id":7,"name":"bug","color":"ffffff","description":"one\ntwo"}]'
printf -- '- name: bug\n  color: "ffffff"\n  description: one two\n' > "$T/labels.nl2.yml"
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" bash ./sync-labels.sh --labels "$T/labels.nl2.yml" --check 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "a host description whose FLATTENED form matches is still drift" \
  || bad "flattened-equal multi-line description is drift (rc=$rc: $out)"

# The drift line must NAME the newline: without it the user sees four identical strings and is
# told a label drifted, in exactly the case the flag exists for.
printf '%s' "$out" | grep -q 'contains a newline' \
  && ok "an ML-forced drift line explains itself" || bad "ML drift line names the newline (got: $out)"

# H3: the duplicate pattern is *US US*, which an empty name always matches, so every empty name
# was reported as a duplicate and the empty-name branch was unreachable.
exit_case "an empty name is diagnosed as empty, not as a duplicate" \
  '- name:\n  color: "ffffff"\n  description: X\n' 3 0
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" \
      bash ./sync-labels.sh --labels "$T/labels.x.yml" 2>&1)
printf '%s' "$out" | grep -q 'empty name' && ok "...with the empty-name message" \
  || bad "empty name message (got: $out)"

# H6: the unterminated sentinel is checked across ALL THREE fields, not just description.
exit_case "an unterminated quote in the NAME refuses" \
  '- name: "bug\n  color: "ffffff"\n  description: X\n' 3 0
exit_case "an unterminated quote in the COLOR refuses" \
  '- name: bug\n  color: "ffffff\n  description: X\n' 3 0

# --- 8e. the four exit codes are DISTINGUISHABLE ------------------------------------------------
# Every assertion above used -ne 0, so all four codes were interchangeable to the suite and three
# separate exit-code mutations survived.
host_json '[]'
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" bash ./sync-labels.sh --labels "$T/labels.yml" --check 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "exit 1 means --check found drift" || bad "exit 1 for check drift (got $rc)"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" bash ./sync-labels.sh --bogus 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "exit 2 means a usage error" || bad "exit 2 for usage (got $rc)"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" bash ./sync-labels.sh --labels 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "exit 2 when a flag is missing its value" || bad "exit 2 for missing flag value (got $rc)"
printf -- 'garbage line\n' > "$T/labels.bad.yml"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" bash ./sync-labels.sh --labels "$T/labels.bad.yml" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "exit 3 means a malformed declaration, nothing written" || bad "exit 3 for malformed (got $rc)"
cat > "$T/forge-lib.fail.sh" <<'FSTUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_api_paginate() { cat "$HOST_LABELS"; }
forge_api() { printf '%s %s %s\n' "$1" "$2" "${3:-}" >> "$REQLOG"; return 22; }
FSTUB
cp "$T/forge-lib.sh" "$T/forge-lib.ok.sh"; cp "$T/forge-lib.fail.sh" "$T/forge-lib.sh"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$T/req.log" bash ./sync-labels.sh --labels "$T/labels.yml" 2>&1); rc=$?
[ "$rc" -eq 4 ] && ok "exit 4 means a write failed part-way" || bad "exit 4 for write failure (got $rc)"
cp "$T/forge-lib.ok.sh" "$T/forge-lib.sh"

# --- 9b. a dry run must read the REAL host state (round-1 finding H2) ---------------------------
# forge-lib's paginate returns [] under dry run, so a script that does not clear the flag around
# the READ believes the host is empty and previews creating every label on a fully-synced repo.
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"Security vulnerability or hardening"}]'
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" FORGE_DRY_RUN=1 \
      bash ./sync-labels.sh --labels "$T/labels.yml" 2>&1); rc=$?
printf '%s' "$out" | grep -q 'dry-run\] create' \
  && bad "a dry run on a SYNCED host previews no creates" \
  || ok "a dry run on a SYNCED host previews no creates"
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" FORGE_DRY_RUN=1 \
      bash ./sync-labels.sh --labels "$T/labels.yml" --check 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "--check under dry run is not a false alarm" \
  || bad "--check under dry run is not a false alarm (rc=$rc: $out)"

# The dry-run guard on the UPDATE branch had no test: only the CREATE branch was covered, so a
# mutant that let a drifted label be PATCHed under FORGE_DRY_RUN survived the whole suite.
host_json '[{"id":1,"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working"},
            {"id":2,"name":"security","color":"e4e669","description":"WRONG"}]'
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" FORGE_DRY_RUN=1 \
      bash ./sync-labels.sh --labels "$T/labels.yml" 2>&1)
[ ! -s "$REQLOG" ] && ok "a dry run does not PATCH a DRIFTED label either" \
  || bad "dry run does not PATCH a drifted label (log: $(cat "$REQLOG"))"
printf '%s' "$out" | grep -q "\[dry-run\] update label 'security'" \
  && ok "...and says which label it would update" || bad "dry run names the update it would make"

# --- 9c. the github PATCH path percent-encodes the name (round-1 finding M2) --------------------
# A raw `help wanted` puts a space in the URL; a raw `a#b` opens a fragment and silently PATCHes
# label `a` with another label's colour and description.
cat > "$T/labels.enc.yml" <<'Y'
- name: help wanted
  color: "ffffff"
  description: D
- name: a#b
  color: "ffffff"
  description: D
Y
host_json '[{"id":1,"name":"help wanted","color":"000000","description":"old"},
            {"id":2,"name":"a#b","color":"000000","description":"old"}]'
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" \
      bash ./sync-labels.sh --labels "$T/labels.enc.yml" 2>&1)
grep -q '^PATCH /repos/o/r/labels/help%20wanted ' "$REQLOG" \
  && ok "a multi-word label name is percent-encoded in the PATCH path" \
  || bad "multi-word name percent-encoded (log: $(cat "$REQLOG"))"
grep -q '^PATCH /repos/o/r/labels/a%23b ' "$REQLOG" \
  && ok "a '#' in a label name cannot open a URL fragment" \
  || bad "'#' in a name is encoded (log: $(cat "$REQLOG"))"

# --- 10. a malformed declaration REFUSES rather than syncing a partial set ---------------------
cp "$T/labels.yml" "$T/labels.good.yml"
printf -- '- name: ok\n  color: "ffffff"\n  description: fine\nthis line is not valid\n' > "$T/labels.yml"
run
[ "$rc" -ne 0 ] && ok "a malformed labels file refuses" || bad "a malformed labels file refuses (rc=$rc)"
[ ! -s "$REQLOG" ] && ok "...and writes nothing (no partial sync)" || bad "malformed file writes nothing"
printf '%s' "$out" | grep -q 'unparsable line 4' && ok "...naming the offending line" || bad "names the offending line"
cp "$T/labels.good.yml" "$T/labels.yml"

# --- 11. the real repo's own labels.yml parses ------------------------------------------------
n=$(awk '/^-[[:space:]]+name:/ {c++} END {print c+0}' "$ROOT/.github/labels.yml")
host_json '[]'
REQLOG="$T/req.log"; : > "$REQLOG"
out=$(cd "$T" && HOST_LABELS="$T/host.json" REQLOG="$REQLOG" FORGE_DRY_RUN=1 \
      bash ./sync-labels.sh --labels "$ROOT/.github/labels.yml" 2>&1); rc=$?
got=$(printf '%s' "$out" | grep -c '\[dry-run\] create label')
[ "$rc" -eq 0 ] && [ "$got" -eq "$n" ] \
  && ok "forge-kit's own labels.yml parses to all $n labels" \
  || bad "forge-kit's own labels.yml parses ($got of $n, rc=$rc)"

# --- #127 H6: a host label with an EMPTY name must not register a phantom entry -----------------
# Defence in depth: neither GitHub nor Forgejo permits an empty label name. It is covered because
# the guard survived a mutation sweep untested, and an untested guard is this repo's own defect.
cat > "$T/labels.yml" <<'Y'
- name: bug
  color: "d73a4a"
  description: Something isn't working
Y
host_json '[{"name":"","color":"ffffff","description":"phantom","id":9},
            {"name":"bug","color":"d73a4a","description":"Something isn'"'"'t working","id":1}]'
run --check
[ "$rc" -eq 0 ] && ok "an empty-named host label is ignored, not treated as a label" \
                || bad "an empty-named host label reached the comparison (rc=$rc: $out)"
printf '%s' "$out" | grep -q "''" \
  && bad "and it is not reported as an undeclared label" \
  || ok "and it is not reported as an undeclared label"

# --- #127 H7: the UNTERMINATED sentinel was carried IN BAND ------------------------------------
# A description containing a raw 0x01 followed by the literal text UNTERMINATED was refused with
# exit 3, because that is what clean() returned for a genuinely unterminated quote. Theoretical (it
# needs a control byte in hand-written YAML) and fixed anyway: a verdict smuggled inside a value is
# the same class as the in-band signalling this repo has already been bitten by.
printf -- '- name: bug\n  color: "d73a4a"\n  description: \001UNTERMINATED stuff\n' > "$T/labels.yml"
host_json '[{"name":"bug","color":"d73a4a","description":"\u0001UNTERMINATED stuff","id":1}]'
run --check
[ "$rc" -ne 3 ] && ok "a value that merely LOOKS like the sentinel is not refused" \
                || bad "the in-band sentinel still causes a false refusal (rc=$rc: $out)"

# ...and a genuinely unterminated quote is still refused.
printf -- '- name: bug\n  color: "d73a4a"\n  description: "never closed\n' > "$T/labels.yml"
host_json '[]'
run --check
[ "$rc" -eq 3 ] && ok "a genuinely unterminated quote is still refused" \
                || bad "an unterminated quote stopped being refused (rc=$rc)"

# --- #127 H8: duplicate host label names are FIRST-wins, as before #121 -------------------------
# Unreachable on either host, and recorded because it was a behaviour change inside a commit that
# asserted behaviour was unchanged. Restoring it costs one line and removes the discrepancy rather
# than documenting it.
cat > "$T/labels.yml" <<'Y'
- name: bug
  color: "d73a4a"
  description: first
Y
host_json '[{"name":"bug","color":"d73a4a","description":"first","id":1},
            {"name":"bug","color":"000000","description":"second","id":2}]'
run --check
[ "$rc" -eq 0 ] && ok "a duplicate host label compares against the FIRST, as before #121" \
                || bad "duplicate host labels compare against the last (rc=$rc: $out)"

echo ""
echo "sync-labels tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
