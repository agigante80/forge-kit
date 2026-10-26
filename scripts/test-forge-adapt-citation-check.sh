#!/usr/bin/env bash
# Contract test for forge-adapt's adapt/assets/citation-check.sh (#519).
#
# The script finds the ticket-standards section titles the gate cites (`section "Title"`) that the
# project's own doc has no heading for. Its worst failure is a false clean, so the cases pin every
# way it could report nothing while it did not look (no gate, an unreadable doc, a dangling link)
# next to every way it reports a miss (a renamed section, a substring heading, a fenced heading).
# STREAMS ARE THE CONTRACT: tab-separated rows and a summary row on stdout, exit 0 clean, 1 a
# missing title, 3 incomplete, 2 usage error with nothing on stdout. Every case runs the script as
# a subprocess against throwaway trees; the citation list is built per case, so a mutant that
# hardcodes the kit's titles is caught by the made-up "Zebra rules" title.
#
# EVERY MUTANT AT THE BOTTOM is a sed on a copy of the script that breaks one invariant; the suite
# fails unless the scenario guarding that invariant notices. CHECK_SCRIPT overrides the script.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
S0="${CHECK_SCRIPT:-$ROOT/plugins/forge-kit-adapt/skills/adapt/assets/citation-check.sh}"
S="$S0"

pass=0; fail=0; QUIET=0; SCFAIL=0
ok()  { if [ "$QUIET" = 1 ]; then return; fi; echo "  ok: $1"; pass=$((pass + 1)); }
bad() { if [ "$QUIET" = 1 ]; then SCFAIL=1; return; fi; echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { if grep -qxF -- "$1" <<< "$out"; then ok "$2"; else bad "$2 (no row '$1' in: $out)"; fi; }
nrows() { printf '%s\n' "$out" | grep -c "^$1	" | tr -d ' '; }

[ -f "$S0" ] || { echo "missing script: $S0"; exit 1; }

T=$(mktemp -d); trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
T=$(CDPATH= cd -P -- "$T" && pwd -P)
TAB=$(printf '\t')
KIT="$T/kit"; P="$T/p"; CFG="$T/cfg"
GATE_REL="plugins/forge-kit-governance/agents/ticket-gate.md"
MECH_REL="plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"

put() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
# fresh: an empty project, an empty kit and an empty config dir.
fresh() { rm -rf "$KIT" "$P" "$CFG" "$T/home" "$T/cache"; mkdir -p "$KIT/plugins" "$P" "$CFG" "$T/home"; }
# gate <title>...: the kit's ticket-gate.md citing exactly those titles.
gate() { local t body=""; for t in "$@"; do body="$body\nCheck section \"$t\" first.\n"; done; put "$KIT/$GATE_REL" "---\nname: ticket-gate\n---$body"; }
# doc <heading line>...: the project's ticket-standards doc.
doc() { local h body=""; for h in "$@"; do body="$body$h\n\nbody\n\n"; done; put "$P/docs/guides/ticket-standards.md" "# Standards\n\n$body"; }

out=""; err=""; rc=0
run() { out=$(cd "$P" && env HOME="$T/home" CLAUDE_CONFIG_DIR="$CFG" bash "$S" --kit "$KIT" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }

sc_match() {
  echo "== every cited title is a heading =="
  fresh; gate "Unit test specs" "E2E test specs"; doc "### 2. Unit test specs" "### 3. E2E test specs"; run
  expect "no citation-missing row" 0 "$(nrows citation-missing)"
  has "summary${TAB}2${TAB}0${TAB}0" "summary counts two checked, none missing, none unscanned"
  expect "exit 0" 0 "$rc"
  expect "summary is the last row" "summary" "$(printf '%s\n' "$out" | tail -1 | cut -f1)"

  echo "== a downstream shape: renamed sections =="
  fresh; gate "Unit test specs" "E2E test specs"; doc "### 2. Verification steps" "### 3. Sources and citations"; run
  has "citation-missing${TAB}\"Unit test specs\"" "Unit test specs is reported by name"
  has "citation-missing${TAB}\"E2E test specs\"" "E2E test specs is reported by name"
  has "summary${TAB}2${TAB}2${TAB}0" "summary counts two missing"
  expect "exit 1" 1 "$rc"

  echo "== numbering prefix and parenthetical suffix are tolerated =="
  fresh; gate "GWT scenarios"; doc "### 1. GWT scenarios (Given / When / Then)"; run
  expect "numbered heading with a suffix matches" 0 "$(nrows citation-missing)"; expect "exit 0" 0 "$rc"
  fresh; gate "Unit test specs"; doc "## Unit test specs"; run
  expect "an unnumbered heading matches" 0 "$(nrows citation-missing)"; expect "exit 0" 0 "$rc"
  fresh; gate "Unit test specs"; doc "### 2. Unit test specs (the rules)"; run
  expect "a suffix alone matches" 0 "$(nrows citation-missing)"
  fresh; gate "GWT scenarios"; doc "### GWT scenarios (Given / When / Then)"; run
  expect "a suffix on an unnumbered heading matches" 0 "$(nrows citation-missing)"

  echo "== only the whole title matches =="
  fresh; gate "Unit test specs"; doc "### 2. Unit test specs for the API layer"; run
  has "citation-missing${TAB}\"Unit test specs\"" "a longer heading is not a match"; expect "exit 1" 1 "$rc"

  echo "== a heading inside a fenced code block does not count =="
  fresh; gate "Unit test specs"; put "$P/docs/guides/ticket-standards.md" '# Standards\n\n```\n### 2. Unit test specs\n```\n'; run
  has "citation-missing${TAB}\"Unit test specs\"" "a fenced heading is reported missing"; expect "exit 1" 1 "$rc"
  fresh; gate "Unit test specs"; put "$P/docs/guides/ticket-standards.md" '# Standards\n\n```\ncode\n```\n\n### 2. Unit test specs\n'; run
  expect "a heading after a closed fence counts" 0 "$(nrows citation-missing)"; expect "exit 0" 0 "$rc"

  echo "== the hitchrail shape: a renamed section also cited by the mechanics output =="
  fresh; gate "Unit test specs"
  put "$KIT/$MECH_REL" '#!/bin/bash\nrow docs_impact referred "section \\"Documentation currency\\" is the critic"\n'
  doc "### 2. Unit test specs" "### 7. Documentation impact"; run
  has "citation-missing${TAB}\"Documentation currency\"" "the mechanics script's escaped citation is found"
  expect "and only that one is missing" 1 "$(nrows citation-missing)"

  echo "== a wrapped citation is one title =="
  fresh; put "$KIT/$GATE_REL" '---\nname: ticket-gate\n---\nsee section "GWT\nscenarios" and\n# the section "E2E\n# test specs" too\n'
  doc "### 1. GWT scenarios" "### 3. E2E test specs"; run
  has "summary${TAB}2${TAB}0${TAB}0" "both wrapped citations are checked and found"
}

sc_source() {
  echo "== the list comes from the component, never a hardcoded copy =="
  fresh; gate "Zebra rules"; doc "### 1. GWT scenarios"; run
  has "citation-missing${TAB}\"Zebra rules\"" "a made-up cited title is reported"; expect "exit 1" 1 "$rc"
  has "summary${TAB}1${TAB}1${TAB}0" "and it is the only title checked"

  echo "== one title cited by several components is checked once =="
  fresh; gate "Unit test specs"
  put "$KIT/$MECH_REL" 'x "section \\"Unit test specs\\""\n'
  put "$P/.claude/skills/privacy-regime/SKILL.md" 'section "Unit test specs"\n'
  doc "### 2. Verification steps"; run
  expect "one row for the title" 1 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}1${TAB}0" "the summary counts distinct titles"

  echo "== privacy-regime is read from the project's own copy only; adapt's skills.md is not a citer (#547) =="
  fresh; gate "Unit test specs"
  put "$P/.claude/skills/privacy-regime/SKILL.md" 'section "Personal data handling"\n'
  doc "### 1. Unit test specs"; run
  has "citation-missing${TAB}\"Personal data handling\"" "a project copy of privacy-regime is checked"
  has "summary${TAB}2${TAB}1${TAB}0" "and counted"; expect "exit 1" 1 "$rc"
  fresh; gate "Unit test specs"
  put "$KIT/plugins/forge-kit-security/skills/privacy-regime/SKILL.md" 'section "Personal data handling"\n'
  put "$T/cache/sec/skills/privacy-regime/SKILL.md" 'section "Personal data handling"\n'
  put "$CFG/plugins/installed_plugins.json" "{\"plugins\":{\"forge-kit-security@forge-kit\":[{\"scope\":\"user\",\"installPath\":\"$T/cache/sec\"}]}}"
  doc "### 1. Unit test specs"; run
  expect "a kit-only or registry-only privacy-regime is not a citer" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "only the gate's title is checked"; expect "exit 0" 0 "$rc"
  fresh; gate "Unit test specs"; put "$T/elsewhere.md" 'section "Personal data handling"\n'
  mkdir -p "$P/.claude/skills/privacy-regime"; ln -s "$T/elsewhere.md" "$P/.claude/skills/privacy-regime/SKILL.md"
  doc "### 1. Unit test specs"; run
  expect "a symlinked project privacy-regime is ignored" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "and contributes nothing"
  fresh; gate "Unit test specs"
  put "$KIT/plugins/forge-kit-adapt/skills/adapt/references/skills.md" 'section "Personal data handling"\n'
  doc "### 1. Unit test specs"; run
  expect "adapt's references/skills.md is not a citer" 0 "$(nrows citation-missing)"; expect "exit 0" 0 "$rc"
  put "$KIT/$MECH_REL" 'x "section \\"Documentation currency\\""\n'; run
  has "citation-missing${TAB}\"Documentation currency\"" "the other citers stay in force"
  expect "and only that one" 1 "$(nrows citation-missing)"; expect "exit 1" 1 "$rc"

  echo "== no gate anywhere: incomplete, never clean =="
  fresh; doc "### 2. Unit test specs"; run
  has "not-scanned${TAB}ticket-gate${TAB}not installed" "the missing gate is named"
  has "summary${TAB}0${TAB}0${TAB}1" "the summary counts it"
  expect "exit 3, never 0" 3 "$rc"

  echo "== the live plugin copy beats the kit copy =="
  fresh; gate "Kit title"; doc "### 1. Plugin title"
  put "$T/cache/v2/agents/ticket-gate.md" 'section "Plugin title"\n'
  put "$T/cache/v1/agents/ticket-gate.md" 'section "Old cached title"\n'
  put "$CFG/plugins/installed_plugins.json" "{\"version\":2,\"plugins\":{\"forge-kit-governance@forge-kit\":[{\"scope\":\"user\",\"installPath\":\"$T/cache/v2\",\"version\":\"2\"}]}}"; run
  expect "the registered install path is read" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "only the plugin's title was checked"
  fresh; gate "Kit title"; doc "### 1. Plugin title"
  put "$T/cache/v2/agents/ticket-gate.md" 'section "Plugin title"\n'
  put "$CFG/plugins/installed_plugins.json" "{\"plugins\":{\"forge-kit-governance@forge-kit\":[{\"scope\":\"project\",\"projectPath\":\"$T/other\",\"installPath\":\"$T/cache/v2\"}]}}"; run
  has "citation-missing${TAB}\"Kit title\"" "a project-scoped entry for another project is ignored"
  fresh; gate "Kit title"; doc "### 1. Plugin title"
  put "$T/cache/v2/agents/ticket-gate.md" 'section "Plugin title"\n'
  put "$CFG/plugins/installed_plugins.json" "{\"plugins\":{\"forge-kit-governance@forge-kit\":[{\"scope\":\"local\",\"projectPath\":\"$P\",\"installPath\":\"$T/cache/v2\"}]}}"; run
  expect "a local-scope entry for this project is read" 0 "$(nrows citation-missing)"
  fresh; gate "Kit title"; doc "### 1. Kit title"; put "$CFG/plugins/installed_plugins.json" 'not json'; run
  expect "a malformed registry falls back to the kit" 0 "$(nrows citation-missing)"; expect "and exits 0" 0 "$rc"

  echo "== a project copy beats both =="
  fresh; gate "Kit title"; doc "### 1. Local title"
  put "$P/.claude/agents/ticket-gate.md" 'section "Local title"\n'; run
  expect "the project's own gate is read" 0 "$(nrows citation-missing)"
  fresh; gate "Kit title"; doc "### 1. Kit title"
  put "$T/elsewhere.md" 'section "Linked title"\n'; mkdir -p "$P/.claude/agents"; ln -s "$T/elsewhere.md" "$P/.claude/agents/ticket-gate.md"; run
  expect "a symlinked project copy is ignored" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "and the kit's title was the one checked"
}

sc_kit() {
  echo "== the kit's own gate is clean against the kit's own doc =="
  out=$(cd "$ROOT" && env HOME="$T/home" CLAUDE_CONFIG_DIR="$CFG" bash "$S" --kit "$ROOT" 2>&1); rc=$?
  expect "no citation-missing row" 0 "$(nrows citation-missing)"
  expect "exit 0" 0 "$rc"
  expect "it checked at least five titles" yes "$(printf '%s\n' "$out" | awk -F'\t' '$1=="summary" {print ($2 >= 5 ? "yes" : "no")}')"
}

sc_nodoc() {
  echo "== no doc: one skip line, however many titles =="
  fresh; gate "A" "B" "C" "D" "E"; run
  has "skipped${TAB}no ticket-standards doc" "one skipped row"
  expect "exactly one" 1 "$(nrows skipped)"; expect "no per-title rows" 0 "$(nrows citation-missing)"; expect "exit 0" 0 "$rc"

  echo "== a doc that exists but cannot be read is not a skip =="
  if [ "$(id -u)" != 0 ]; then
    fresh; gate "A"; doc "### 1. A"; chmod 000 "$P/docs/guides/ticket-standards.md"; run
    chmod 644 "$P/docs/guides/ticket-standards.md"
    has "not-scanned${TAB}docs/guides/ticket-standards.md${TAB}unreadable" "an unreadable doc is named"
    expect "no skipped row" 0 "$(nrows skipped)"; expect "exit 3" 3 "$rc"
  fi
  fresh; gate "A"; mkdir -p "$P/docs/guides"; ln -s "$T/nowhere.md" "$P/docs/guides/ticket-standards.md"; run
  has "not-scanned${TAB}docs/guides/ticket-standards.md${TAB}dangling symlink" "a dangling link is named"
  expect "no skipped row" 0 "$(nrows skipped)"; expect "exit 3" 3 "$rc"
  fresh; gate "A"; mkdir -p "$P/docs/guides/ticket-standards.md"; run
  has "not-scanned${TAB}docs/guides/ticket-standards.md${TAB}not a file" "a directory is not a doc"; expect "exit 3" 3 "$rc"

  echo "== a missing title outranks an unscanned one =="
  fresh; put "$KIT/$MECH_REL" 'section "Zebra rules"\n'; doc "### 1. A"; run
  expect "exit 1 when both" 1 "$rc"
}

sc_usage() {
  echo "== usage errors: stderr only, exit 2 =="
  fresh; gate "A"; doc "### 1. A"
  run --bogus; expect "unknown flag: exit 2" 2 "$rc"; expect "unknown flag: nothing on stdout" "" "$out"
  expect "unknown flag: says why" yes "$(case "$err" in *"unknown argument"*) echo yes ;; *) echo no ;; esac)"
  run --project "$T/nonexistent"; expect "missing project: exit 2" 2 "$rc"; expect "missing project: nothing on stdout" "" "$out"
  run --project; expect "a flag without a value: exit 2" 2 "$rc"
  out=$(cd "$P" && env HOME="$T/home" CLAUDE_CONFIG_DIR="$CFG" bash "$S" --kit "$T/nokit" 2>"$T/err"); rc=$?
  expect "a kit with no plugins/: exit 2" 2 "$rc"; expect "and nothing on stdout" "" "$out"
  echo "== read only =="
  fresh; gate "A"; doc "### 2. Other"; before=$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum); run
  expect "the tree is unchanged" "$before" "$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum)"
  run --doc "$P/docs/guides/ticket-standards.md" --project "$P"; expect "--doc and --project are accepted" 1 "$rc"
}

# --- #543 and #547: the acknowledgement and alias markers, one parser (shared marker rules).
# Every Given has a scanned ticket-gate (the gate helper) citing only the titles it names, unless the
# case says the gate is absent.
# sd <printf %b text>: the doc, written raw.
sd() { put "$P/docs/guides/ticket-standards.md" "$1"; }
ACK() { printf '<!-- citation-acknowledged: "%s" -->' "$1"; }
ALIAS() { printf '<!-- citation-alias: "%s" = "%s" -->' "$1" "$2"; }
# body: every row but the summary, in printed order, one per line.
body() { printf '%s\n' "$out" | grep -v "^summary${TAB}"; }
noerr() { expect "$1: nothing on stderr" "" "$err"; }

sc_ack() {
  echo "== an acknowledged absent title is reported and does not fail the run (#543) =="
  fresh; gate "E2E test specs"; doc "### 2. Verification steps" "$(ACK "E2E test specs")"; run
  has "citation-acknowledged${TAB}\"E2E test specs\"" "the acknowledged row is printed"
  expect "no citation-missing row" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "checked, not missing"; expect "exit 0" 0 "$rc"
  expect "summary is last" "summary" "$(printf '%s\n' "$out" | tail -1 | cut -f1)"
  fresh; gate "Unit test specs" "E2E test specs"; doc "$(ACK "Unit test specs")" "$(ACK "E2E test specs")"; run
  expect "two acknowledged rows" 2 "$(nrows citation-acknowledged)"; has "summary${TAB}2${TAB}0${TAB}0" "both checked, none missing"; expect "exit 0" 0 "$rc"
  fresh; gate "Zebra rules"; doc "$(ACK "Zebra rules")"; run
  has "citation-acknowledged${TAB}\"Zebra rules\"" "a made-up title is acknowledged (no hardcoded list)"; expect "exit 0" 0 "$rc"

  echo "== --doc names the file the markers are read from =="
  fresh; gate "E2E test specs"; doc "### 1. Other"; put "$T/other.md" "# S\n\n$(ACK "E2E test specs")\n"; run --doc "$T/other.md"
  has "citation-acknowledged${TAB}\"E2E test specs\"" "the --doc file's marker is read"; expect "exit 0" 0 "$rc"

  echo "== an acknowledgement never hides another title =="
  fresh; gate "Unit test specs" "E2E test specs"; doc "$(ACK "E2E test specs")"; run
  has "citation-missing${TAB}\"Unit test specs\"" "the unacknowledged title is still missing"
  has "citation-acknowledged${TAB}\"E2E test specs\"" "the other is acknowledged"
  has "summary${TAB}2${TAB}1${TAB}0" "one missing"; expect "exit 1" 1 "$rc"

  echo "== a real heading wins and the marker is stale =="
  fresh; gate "E2E test specs"; doc "### 2. E2E test specs" "$(ACK "E2E test specs")"; run
  expect "no missing row" 0 "$(nrows citation-missing)"; expect "no acknowledged row" 0 "$(nrows citation-acknowledged)"
  has "citation-marker-stale${TAB}\"E2E test specs\"" "the marker is stale"; expect "exactly one stale row" 1 "$(nrows citation-marker-stale)"; expect "exit 0" 0 "$rc"

  echo "== a marker title is normalised like a heading =="
  fresh; gate "GWT scenarios" "E2E test specs" "Unit test specs"
  doc "$(ACK "GWT scenarios (Given / When / Then)")" "$(ACK "E2E  test specs")" "$(ACK "2. Unit test specs")"; run
  has "citation-acknowledged${TAB}\"GWT scenarios\"" "a trailing parenthetical is dropped"
  has "citation-acknowledged${TAB}\"E2E test specs\"" "whitespace is collapsed"
  has "citation-acknowledged${TAB}\"Unit test specs\"" "a leading N. is dropped"
  expect "no stale row" 0 "$(nrows citation-marker-stale)"; expect "exit 0" 0 "$rc"
  fresh; gate "E2E test specs"; doc "$(ACK "e2e test specs")"; run
  has "citation-missing${TAB}\"E2E test specs\"" "the compare is case sensitive"

  echo "== lines are split on newline only (maintainer decision 2, 2026-10-16) =="
  fresh; gate "E2E test specs"; sd "# Standards\r\n\r\n$(ACK "E2E test specs")\r\n"; run
  has "citation-acknowledged${TAB}\"E2E test specs\"" "a CRLF doc with a well-formed marker is acknowledged"; expect "exit 0" 0 "$rc"
  fresh; gate "E2E test specs"; sd "# Standards\n\n<!-- citation-acknowledged: \"E2E test\xe2\x80\xa8specs\" -->\n"; run
  has "citation-acknowledged${TAB}\"E2E test specs\"" "a U+2028 inside a marker does not split its line"; expect "exit 0" 0 "$rc"
  fresh; gate "E2E test specs"; sd "# Standards\na\fb\n<!-- citation-acknowledged: \"E2E test specs\"\n"; run
  has "citation-marker-invalid${TAB}line 3" "a form feed does not start a line"
}

sc_ack_stale() {
  echo "== a marker for a title nothing cites is stale and informational (#543) =="
  fresh; gate "Unit test specs"; doc "### 2. Unit test specs" "$(ACK "Zebra rules")"; run
  has "citation-marker-stale${TAB}\"Zebra rules\"" "the stale marker is reported"
  has "summary${TAB}1${TAB}0${TAB}0" "it changes no count"; expect "exit 0" 0 "$rc"
  fresh; gate "A"; doc "### 1. Other" "$(ACK "Zebra rules")"; run
  expect "missing first, then stale" "citation-missing${TAB}\"A\"|citation-marker-stale${TAB}\"Zebra rules\"" "$(body | paste -sd'|' -)"
  expect "summary last" "summary" "$(printf '%s\n' "$out" | tail -1 | cut -f1)"; expect "exit 1, unchanged" 1 "$rc"
  fresh; gate "E2E test specs"; doc "$(ACK "E2E test specs")"; run
  expect "an acknowledgement of a cited title is not stale" 0 "$(nrows citation-marker-stale)"; expect "exit 0" 0 "$rc"

  echo "== stale rows are suppressed on an incomplete scan =="
  fresh; put "$KIT/$MECH_REL" 'x "section \\"Unit test specs\\""\n'; doc "### 1. Unit test specs" "$(ACK "E2E test specs")"; run
  has "not-scanned${TAB}ticket-gate${TAB}not installed" "the gate is absent"
  expect "no stale row" 0 "$(nrows citation-marker-stale)"; has "summary${TAB}1${TAB}0${TAB}1" "summary 1 0 1"; expect "exit 3" 3 "$rc"
  fresh; put "$KIT/$MECH_REL" 'x "section \\"Unit test specs\\""\n'
  sd "# S\n\n### 1. Unit test specs\n\n$(ACK "E2E test specs")\n\n<!-- citation-acknowledged: \"X\"\n"; run
  has "citation-marker-invalid${TAB}line 7" "an invalid row is still printed"
  expect "still no stale row" 0 "$(nrows citation-marker-stale)"; expect "invalid outranks unscanned: exit 1" 1 "$rc"
}

sc_ack_fence() {
  echo "== a marker between two closed fences counts; one inside a fence does not =="
  fresh; gate "E2E test specs"; sd "# S\n\n\`\`\`\na\n\`\`\`\n\n$(ACK "E2E test specs")\n\n~~~\nb\n~~~\n"; run
  has "citation-acknowledged${TAB}\"E2E test specs\"" "between fences: acknowledged"; expect "exit 0" 0 "$rc"
  for f in '```' '~~~'; do
    fresh; gate "E2E test specs"; sd "# S\n\n$f\n$(ACK "E2E test specs")\n$f\n"; run
    has "citation-missing${TAB}\"E2E test specs\"" "inside $f: still missing"
    expect "inside $f: no marker row" 0 "$(body | grep -c '^citation-\(acknowledged\|marker\|aliased\)')"
    has "summary${TAB}1${TAB}1${TAB}0" "inside $f: summary 1 1 0"; expect "inside $f: exit 1" 1 "$rc"
  done
  fresh; gate "E2E test specs"; sd "# S\n\n\`\`\`\n<!-- citation-acknowledged: \"E2E test specs\"\n\`\`\`\n"; run
  expect "an unterminated marker inside a fence is ignored" 0 "$(nrows citation-marker-invalid)"

  echo "== only the strict one-line grammar is a marker; other lines are silent =="
  for m in '<!-- citation-acknowledged: E2E test specs -->' \
           '<!-- citation-acknowledged: "E2E test specs" extra -->' \
           '<!-- citation-acked: "E2E test specs" -->' \
           '<!-- citation-acknowledged: "E2E test specs" --> after' \
           'text <!-- citation-acknowledged: "E2E test specs" -->' \
           '<!-- citation-acknowledged: "E2E test specs" --> <!-- citation-acknowledged: "E2E test specs" -->' \
           '<!-- citation-acknowledged: " " -->' \
           '<!-- citation-alias: "E2E test specs" "Other" -->' \
           '<!-- citation-alias: "E2E test specs" -->'; do
    fresh; gate "E2E test specs"; doc "### 1. Other" "$m"; run
    expect "off-grammar [$m]: missing, no marker row" "citation-missing${TAB}\"E2E test specs\"" "$(body)"
    expect "off-grammar [$m]: exit 1" 1 "$rc"; noerr "off-grammar [$m]"
  done
  fresh; gate "E2E test specs"; doc "$(printf '\t<!--\tcitation-acknowledged:\t"E2E test specs"\t-->\t')"; run
  has "citation-acknowledged${TAB}\"E2E test specs\"" "tabs and spaces around the parts are tolerated"

  echo "== an unterminated marker is invalid, after the missing rows and before the summary =="
  fresh; gate "E2E test specs"; sd "# S\n\n<!-- citation-acknowledged: \"E2E test specs\"\n"; run
  expect "missing, then invalid" "citation-missing${TAB}\"E2E test specs\"|citation-marker-invalid${TAB}line 3" "$(body | paste -sd'|' -)"
  has "summary${TAB}1${TAB}1${TAB}0" "summary 1 1 0"; expect "exit 1" 1 "$rc"; noerr "unterminated"
  expect "no acknowledged row" 0 "$(nrows citation-acknowledged)"
  fresh; gate "Unit test specs"; sd "# S\n\n### 1. Unit test specs\n\n<!-- citation-acknowledged: \"E2E test\nspecs\" -->\n"; run
  has "citation-marker-invalid${TAB}line 5" "a marker split over two lines is invalid"; expect "and alone makes exit 1" 1 "$rc"
}

sc_alias() {
  echo "== an alias clears a plugin-sourced citation (#547) =="
  fresh; gate; put "$KIT/$MECH_REL" 'x "section \\"Documentation currency\\""\n'
  doc "### 3. Documentation impact" "$(ALIAS "Documentation currency" "Documentation impact")"; run
  has "citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "the aliased row names both"
  expect "no missing row" 0 "$(nrows citation-missing)"; has "summary${TAB}1${TAB}0${TAB}0" "checked, not missing"; expect "exit 0" 0 "$rc"
  gate "Unit test specs"; run
  has "citation-missing${TAB}\"Unit test specs\"" "an alias does not cover a different title"
  has "citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "while the alias still applies"; expect "exit 1" 1 "$rc"

  echo "== whitespace inside the alias comment is tolerated; titles are normalised =="
  fresh; gate "Documentation currency"
  doc "### 3. Documentation impact" "$(printf '<!--  citation-alias:\t "Documentation currency"  =\t"Documentation impact"  -->')"; run
  has "citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "extra spaces and tabs"; expect "exit 0" 0 "$rc"
  fresh; gate "Documentation currency"; doc "### 3. Documentation impact" "$(ALIAS "Documentation currency (x)" "Documentation impact (y)")"; run
  has "citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "both sides are normalised like a heading"

  echo "== stale and invalid aliases =="
  fresh; gate "Unit test specs"; doc "### 1. Unit test specs" "### 2. Blast radius" "$(ALIAS "Zebra rules" "Blast radius")"; run
  has "citation-marker-stale${TAB}\"Zebra rules\"" "an alias for an uncited title is stale"; expect "exit 0" 0 "$rc"
  fresh; gate "Unit test specs"; doc "### 1. Unit test specs" "$(ALIAS "Zebra rules" "Nowhere")"; run
  has "citation-marker-stale${TAB}\"Zebra rules\"" "uncited with a missing target: stale"
  expect "not invalid" 0 "$(nrows citation-marker-invalid)"; expect "exit 0" 0 "$rc"
  fresh; gate "Personal data handling"; doc "### 1. Other" "$(ALIAS "Personal data handling" "Blast radius")"; run
  expect "cited with a missing target: missing then invalid" "citation-missing${TAB}\"Personal data handling\"|citation-marker-invalid${TAB}\"Personal data handling\"${TAB}\"Blast radius\"" "$(body | paste -sd'|' -)"
  expect "exit 1" 1 "$rc"
  fresh; gate "A"; doc "### 1. C" "$(ALIAS "A" "B")" "$(ALIAS "B" "C")"; run
  has "citation-marker-invalid${TAB}\"A\"${TAB}\"B\"" "an alias chain is not followed"; has "citation-missing${TAB}\"A\"" "A stays missing"
  has "citation-marker-stale${TAB}\"B\"" "the uncited link is stale"

  echo "== a real heading beats an alias =="
  fresh; gate "Documentation currency"
  doc "### 1. Documentation currency" "### 2. Blast radius" "$(ALIAS "Documentation currency" "Blast radius")"; run
  expect "stale only" "citation-marker-stale${TAB}\"Documentation currency\"" "$(body)"; expect "exit 0" 0 "$rc"

  echo "== duplicates: the first applied alias wins =="
  fresh; gate "Documentation currency"
  doc "### 3. Documentation impact" "### 2. Blast radius" "$(ALIAS "Documentation currency" "Documentation impact")" "$(ALIAS "Documentation currency" "Blast radius")"; run
  expect "the conflicting one invalid, the first aliased" "citation-marker-invalid${TAB}\"Documentation currency\"${TAB}\"Blast radius\"|citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "$(body | paste -sd'|' -)"
  has "summary${TAB}1${TAB}0${TAB}0" "nothing missing"; expect "exit 1 from the marker alone" 1 "$rc"
  fresh; gate "Documentation currency"
  doc "### 3. Documentation impact" "$(ALIAS "Documentation currency" "Documentation impact")" "$(ALIAS "Documentation currency" "Documentation impact")"; run
  expect "an identical duplicate is one aliased row and nothing else" "citation-aliased${TAB}\"Documentation currency\"${TAB}\"Documentation impact\"" "$(body)"; expect "exit 0" 0 "$rc"

  echo "== a first alias that was not applied is never replaced by a later one =="
  fresh; gate "Documentation currency"
  doc "### 3. Documentation impact" "$(ALIAS "Documentation currency" "Nowhere")" "$(ALIAS "Documentation currency" "Documentation impact")"; run
  expect "missing, invalid, stale" "citation-missing${TAB}\"Documentation currency\"|citation-marker-invalid${TAB}\"Documentation currency\"${TAB}\"Nowhere\"|citation-marker-stale${TAB}\"Documentation currency\"" "$(body | paste -sd'|' -)"
  has "summary${TAB}1${TAB}1${TAB}0" "summary 1 1 0"; expect "exit 1" 1 "$rc"
  fresh; gate "Unit test specs"; doc "### 1. Unit test specs" "### 2. Foo" "$(ALIAS "Zebra rules" "Nowhere")" "$(ALIAS "Zebra rules" "Foo")"; run
  expect "uncited: one stale row per marker, nothing else" "citation-marker-stale${TAB}\"Zebra rules\"|citation-marker-stale${TAB}\"Zebra rules\"" "$(body | paste -sd'|' -)"
  has "summary${TAB}1${TAB}0${TAB}0" "summary 1 0 0"; expect "exit 0" 0 "$rc"

  echo "== an unterminated alias is invalid by line =="
  fresh; gate "Documentation currency"; sd "# S\n\n### 3. Documentation impact\n\n<!-- citation-alias: \"Documentation currency\" = \"Documentation impact\"\n"; run
  expect "missing, then the invalid line" "citation-missing${TAB}\"Documentation currency\"|citation-marker-invalid${TAB}line 5" "$(body | paste -sd'|' -)"; expect "exit 1" 1 "$rc"

  echo "== a title is compared as a string, never a pattern =="
  fresh; gate "AxxB"; doc "### 1. Other" "$(ACK "A.*B")"; run
  has "citation-missing${TAB}\"AxxB\"" "a regex in a marker matches nothing"; has "citation-marker-stale${TAB}\"A.*B\"" "and is stale"
}

sc_ack_precedence() {
  echo "== an alias beats an acknowledgement (#543, #547) =="
  fresh; gate "E2E test specs"; doc "### 2. Verification steps" "$(ALIAS "E2E test specs" "Verification steps")" "$(ACK "E2E test specs")"; run
  expect "aliased, then the acknowledgement stale" "citation-aliased${TAB}\"E2E test specs\"${TAB}\"Verification steps\"|citation-marker-stale${TAB}\"E2E test specs\"" "$(body | paste -sd'|' -)"
  expect "exit 0" 0 "$rc"
  fresh; gate "E2E test specs"; doc "$(ACK "E2E test specs")" "### 2. Verification steps" "$(ALIAS "E2E test specs" "Verification steps")"; run
  has "citation-aliased${TAB}\"E2E test specs\"${TAB}\"Verification steps\"" "whichever comes first in the doc"; expect "no acknowledged row" 0 "$(nrows citation-acknowledged)"
  fresh; gate "E2E test specs"; doc "$(ALIAS "E2E test specs" "Nowhere")" "$(ACK "E2E test specs")"; run
  expect "an alias with a missing target still beats it (maintainer decision 3)" "citation-missing${TAB}\"E2E test specs\"|citation-marker-invalid${TAB}\"E2E test specs\"${TAB}\"Nowhere\"|citation-marker-stale${TAB}\"E2E test specs\"" "$(body | paste -sd'|' -)"
  expect "exit 1" 1 "$rc"

  echo "== a repeated acknowledgement is one row =="
  fresh; gate "E2E test specs"; doc "$(ACK "E2E test specs")" "$(ACK "E2E test specs")"; run
  expect "one acknowledged row, nothing else" "citation-acknowledged${TAB}\"E2E test specs\"" "$(body)"; expect "exit 0" 0 "$rc"

  echo "== row order: missing, invalid, aliased, acknowledged, stale, each in marker line order =="
  fresh; gate "M" "V" "W" "K"
  doc "### 1. Real" "$(ACK "Old")" "$(ACK "K")" "$(ALIAS "W" "Real")" "$(ALIAS "V" "Gone")" "$(ALIAS "W" "Other")" "### 2. Other"; run
  expect "the full order" "citation-missing${TAB}\"M\"|citation-missing${TAB}\"V\"|citation-marker-invalid${TAB}\"V\"${TAB}\"Gone\"|citation-marker-invalid${TAB}\"W\"${TAB}\"Other\"|citation-aliased${TAB}\"W\"${TAB}\"Real\"|citation-acknowledged${TAB}\"K\"|citation-marker-stale${TAB}\"Old\"" "$(body | paste -sd'|' -)"
  expect "summary last" "summary${TAB}4${TAB}2${TAB}0" "$(printf '%s\n' "$out" | tail -1)"
}

sc_markers_safe() {
  echo "== a marker is data: nothing is evaluated, nothing is written =="
  fresh; gate "A"; doc "### 1. A" "$(ACK '$(touch pwned) x')" "$(ACK '`touch pwned2`')" "$(ALIAS 'A' '$(touch pwned3)')"
  before=$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum); run
  expect "no file was created" "" "$(cd "$T" && find . -name 'pwned*')"
  expect "the tree is unchanged" "$before" "$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum)"
  has "citation-marker-stale${TAB}\"\$(touch pwned) x\"" "the title is echoed as text"; expect "exit 0" 0 "$rc"
  echo "== no doc: one skip line and no marker rows =="
  fresh; gate "A"; run
  expect "only the skip row" "skipped${TAB}no ticket-standards doc" "$(body)"
}

# --- #544: rename candidates, by order against the kit's own doc.
# kitdoc <heading line>...: the kit's docs/guides/ticket-standards.md (the doc helper writes the project's).
kitdoc() { local h body=""; for h in "$@"; do body="$body$h\n\nbody\n\n"; done; put "$KIT/docs/guides/ticket-standards.md" "# Standards\n\n$body"; }
K1="### 1. GWT scenarios"; K2="### 2. Unit test specs"; K3="### 3. E2E test specs"; K4="### 4. Personal data handling"
K5="### 5. Security checklist"; K6="### 6. Required reviews"; K7="### 7. Documentation currency"
KITSEVEN() { kitdoc "$K1" "$K2" "$K3" "$K4" "$K5" "$K6" "$K7"; }
CAND() { printf 'citation-rename-candidate\t"%s"\t"%s"' "$1" "$2"; }
INT="Integration / subprocess test specs"

sc_rename() {
  echo "== one title and one heading in a gap: a candidate, after the missing row =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K2" "### 3. $INT" "$K4" "$K5" "$K6" "$K7"; run
  expect "missing, then the candidate (no number field)" "citation-missing${TAB}\"E2E test specs\"
$(CAND "E2E test specs" "$INT")" "$(body)"
  has "summary${TAB}1${TAB}1${TAB}0" "the summary is unchanged by the candidate"; expect "exit 1" 1 "$rc"; noerr "candidate"
  rm -f "$KIT/docs/guides/ticket-standards.md"; run
  expect "no kit doc: the missing row alone" "citation-missing${TAB}\"E2E test specs\"" "$(body)"
  has "summary${TAB}1${TAB}1${TAB}0" "no kit doc: same summary"; expect "no kit doc: exit 1" 1 "$rc"
  kitdoc "$K1" "$K2" "$K4" "$K5" "$K6" "$K7"; run
  expect "a kit doc lacking the title: no candidate" 0 "$(nrows citation-rename-candidate)"

  echo "== the kit's own doc, renamed as the downstream shape did =="
  fresh; gate "E2E test specs" "Personal data handling"; mkdir -p "$KIT/docs/guides" "$P/docs/guides"
  cp "$ROOT/docs/guides/ticket-standards.md" "$KIT/docs/guides/ticket-standards.md"
  sed -e "s|^### 3\. E2E test specs\$|### 3. $INT|" -e 's|^### 4\. Personal data handling$|### 4. Data handling|' \
    "$ROOT/docs/guides/ticket-standards.md" > "$P/docs/guides/ticket-standards.md"
  run
  expect "two missing rows, then the two candidates in kit order" "citation-missing${TAB}\"E2E test specs\"
citation-missing${TAB}\"Personal data handling\"
$(CAND "E2E test specs" "$INT")
$(CAND "Personal data handling" "Data handling")" "$(body)"
  expect "exit 1" 1 "$rc"
  cp "$ROOT/docs/guides/ticket-standards.md" "$P/docs/guides/ticket-standards.md"; run
  expect "the kit doc against itself: nothing missing, no candidate" "" "$(body)"; expect "exit 0" 0 "$rc"

  echo "== a dropped section: unequal counts, no candidate (the named miss) =="
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "### 3. Data handling" "### 4. Security checklist" "$K6" "$K7"; run
  expect "no candidate" 0 "$(nrows citation-rename-candidate)"; expect "both missing" 2 "$(nrows citation-missing)"; expect "exit 1" 1 "$rc"

  echo "== duplicate numbering: order pairs, numbers never do =="
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "### 3. $INT" "### 3. Data handling" "$K5" "$K6" "$K7"; run
  has "$(CAND "E2E test specs" "$INT")" "the first 3. pairs the first title"
  has "$(CAND "Personal data handling" "Data handling")" "the second 3. pairs the second title"
  doc "$K1" "$K2" "### 3. $INT" "### 3. Data handling" "### 3. Extra" "$K5" "$K6" "$K7"; run
  expect "three headings for two titles: no candidate" 0 "$(nrows citation-rename-candidate)"

  echo "== the kit title plus a parenthetical is a match, not a candidate =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K2" "### 3. E2E test specs (integration / subprocess)" "$K4" "$K5" "$K6" "$K7"; run
  expect "nothing printed but the summary" "" "$(body)"; expect "exit 0" 0 "$rc"

  echo "== a fenced heading in the gap is not offered =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K2" '```' "### 3. $INT" '```' "$K4" "$K5" "$K6" "$K7"; run
  expect "no candidate" 0 "$(nrows citation-rename-candidate)"; has "citation-missing${TAB}\"E2E test specs\"" "still missing"

  echo "== a real heading, an alias or an acknowledgement suppresses the candidate =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K2" "### 3. $INT" "$(ALIAS "E2E test specs" "$INT")" "$K4" "$K5" "$K6" "$K7"; run
  expect "aliased: no candidate" "citation-aliased${TAB}\"E2E test specs\"${TAB}\"$INT\"" "$(body)"; expect "aliased: exit 0" 0 "$rc"
  doc "$K1" "$K2" "### 3. $INT" "$(ACK "E2E test specs")" "$K4" "$K5" "$K6" "$K7"; run
  expect "acknowledged: no candidate" "citation-acknowledged${TAB}\"E2E test specs\"" "$(body)"; expect "acknowledged: exit 0" 0 "$rc"

  echo "== a renamed uncited neighbour still pairs; only the cited title gets a row =="
  fresh; gate "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "$K3" "### 4. Data handling" "### 5. Security" "$K6" "$K7"; run
  expect "one candidate, for the cited title" "citation-missing${TAB}\"Personal data handling\"
$(CAND "Personal data handling" "Data handling")" "$(body)"
  expect "exit 1" 1 "$rc"
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "### 3. $INT" "### 4. Data handling" "### 5. Security" "$K6" "$K7"; run
  expect "two cited renames beside an uncited one: two candidates" 2 "$(nrows citation-rename-candidate)"
  expect "the missing rows come first" "citation-missing" "$(printf '%s\n' "$out" | head -1 | cut -f1)"

  echo "== a partly accepted alias keeps the sibling candidate =="
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN
  doc "$K1" "$K2" "### 3. Extra notes" "### 3. $INT" "### 4. Data handling" "$(ALIAS "E2E test specs" "$INT")" "$K5" "$K6" "$K7"; run
  expect "aliased, missing, and the sibling's candidate" "citation-missing${TAB}\"Personal data handling\"
$(CAND "Personal data handling" "Data handling")
citation-aliased${TAB}\"E2E test specs\"${TAB}\"$INT\"" "$(body)"
  expect "exit 1" 1 "$rc"

  echo "== an acknowledged neighbour leaves the kit side =="
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "$(ACK "E2E test specs")" "### 4. Data handling" "$K5" "$K6" "$K7"; run
  expect "the renamed title pairs; the acknowledged one gets no candidate" "citation-missing${TAB}\"Personal data handling\"
$(CAND "Personal data handling" "Data handling")
citation-acknowledged${TAB}\"E2E test specs\"" "$(body)"

  echo "== anchors out of order: no candidate anywhere =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K5" "$K2" "### 3. $INT" "$K4" "$K6" "$K7"; run
  expect "no candidate" 0 "$(nrows citation-rename-candidate)"; has "citation-missing${TAB}\"E2E test specs\"" "still missing"; expect "exit 1" 1 "$rc"

  echo "== row order: missing, candidates, invalid markers, summary =="
  fresh; gate "E2E test specs" "Personal data handling"; KITSEVEN
  doc "$K1" "$K2" "### 3. $INT" "### 4. Data handling" "$K5" "$K6" "$K7" '<!-- citation-alias: "X" = "Y"'; run
  expect "the documented order" "citation-missing${TAB}\"E2E test specs\"
citation-missing${TAB}\"Personal data handling\"
$(CAND "E2E test specs" "$INT")
$(CAND "Personal data handling" "Data handling")
citation-marker-invalid${TAB}line 31" "$(body)"
  expect "summary last" "summary" "$(printf '%s\n' "$out" | tail -1 | cut -f1)"

  echo "== a hostile heading is data =="
  fresh; gate "E2E test specs"; KITSEVEN; doc "$K1" "$K2" '### 3. -x\t$(touch x) y `touch x2`' "$K4" "$K5" "$K6" "$K7"
  before=$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum); run
  has "$(CAND "E2E test specs" '-x $(touch x) y `touch x2`')" "the tab is one space, the rest is text"
  expect "exactly three fields" 3 "$(printf '%s\n' "$out" | grep '^citation-rename-candidate' | awk -F'\t' '{print NF}')"
  expect "nothing was executed" "" "$(cd "$T" && find . -name 'x' -o -name 'x2')"
  expect "the tree is unchanged" "$before" "$(cd "$T" && find p kit cfg -type f | sort | xargs cksum | cksum)"
  fresh; gate "Personal data handling"; KITSEVEN; doc "$K1" "$K2" "$K3" '### 4. Data "handling"' "$K5" "$K6" "$K7"; run
  expect "a double quote in the heading: no candidate" 0 "$(nrows citation-rename-candidate)"
  doc "$K1" "$K2" "$K3" '### 4. Data \001handling' "$K5" "$K6" "$K7"; run
  expect "a control character in the heading: no candidate" 0 "$(nrows citation-rename-candidate)"
  has "citation-missing${TAB}\"Personal data handling\"" "it stays missing"

  echo "== the install-time carrier: the kit doc says to keep the titles =="
  intro=$(awk '/^## Required sections/{f=1; next} /^### /{f=0} f' "$ROOT/docs/guides/ticket-standards.md")
  case "$intro" in *"must keep each section title"*) ok "the Required sections intro carries the keep-the-title sentence" ;;
    *) bad "the Required sections intro lacks the keep-the-title sentence" ;; esac
}

sc_rename_kitfence() {
  echo "== a fenced heading in the kit doc is not a kit heading =="
  fresh; gate "E2E test specs"; kitdoc "$K1" "$K2" '```' "### 3. Fake" '```' "$K3" "$K4" "$K5" "$K6" "$K7"
  doc "$K1" "$K2" "### 3. $INT" "$K4" "$K5" "$K6" "$K7"; run
  has "$(CAND "E2E test specs" "$INT")" "the fenced kit heading does not unbalance the gap"
}

sc_mech_copy() {
  local SP="$P/scripts/check-ticket-mechanics.sh"
  echo "== the project's scripts/ copy of check-ticket-mechanics is read first (#556) =="
  fresh; gate "GWT scenarios"; put "$SP" 'x "section \\"Zebra rules\\""\n'; doc "### 1. GWT scenarios"; run
  has "citation-missing${TAB}\"Zebra rules\"" "a title only the scripts/ copy cites is reported"
  has "summary${TAB}2${TAB}1${TAB}0" "and counted with the gate's title"; expect "exit 1" 1 "$rc"
  fresh; gate "GWT scenarios"; put "$SP" 'x "section \\"GWT scenarios\\""\n'; doc "### 1. GWT scenarios"; run
  expect "a scripts/ copy citing a present title adds no row" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "and the title is counted once"; expect "exit 0" 0 "$rc"

  echo "== it ranks ahead of the registry and the kit =="
  fresh; gate "GWT scenarios"; put "$SP" 'x "section \\"Project title\\""\n'
  put "$KIT/$MECH_REL" 'x "section \\"Kit title\\""\n'
  put "$T/cache/gov/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh" 'x "section \\"Plugin title\\""\n'
  put "$CFG/plugins/installed_plugins.json" "{\"plugins\":{\"forge-kit-governance@forge-kit\":[{\"scope\":\"user\",\"installPath\":\"$T/cache/gov\"}]}}"
  doc "### 1. GWT scenarios" "### 2. Project title"; run
  expect "titles only the registry and kit copies cite are not reported" 0 "$(nrows citation-missing)"
  has "summary${TAB}2${TAB}0${TAB}0" "only the scripts/ copy's title is checked"; expect "exit 0" 0 "$rc"
  doc "### 1. GWT scenarios" "### 2. Kit title" "### 3. Plugin title"; run
  has "citation-missing${TAB}\"Project title\"" "the scripts/ copy's title is the one checked"
  expect "and only that one" 1 "$(nrows citation-missing)"; expect "exit 1" 1 "$rc"

  echo "== a symlink, a symlinked scripts/ directory or a directory is not the project's copy =="
  fresh; gate "GWT scenarios"; put "$T/elsewhere.sh" 'x "section \\"Linked title\\""\n'
  mkdir -p "$P/scripts"; ln -s "$T/elsewhere.sh" "$SP"
  put "$KIT/$MECH_REL" 'x "section \\"Kit title\\""\n'; doc "### 1. GWT scenarios" "### 2. Kit title"; run
  expect "a symlinked scripts/ copy is ignored" 0 "$(nrows citation-missing)"
  has "summary${TAB}2${TAB}0${TAB}0" "and the kit's title is checked instead"
  fresh; gate "GWT scenarios"; put "$T/outside/check-ticket-mechanics.sh" 'x "section \\"Linked title\\""\n'
  ln -s "$T/outside" "$P/scripts"
  put "$KIT/$MECH_REL" 'x "section \\"Kit title\\""\n'; doc "### 1. GWT scenarios" "### 2. Kit title"; run
  expect "a file below a symlinked scripts/ directory is ignored" 0 "$(nrows citation-missing)"
  has "summary${TAB}2${TAB}0${TAB}0" "and the kit's title is checked instead"
  fresh; gate "GWT scenarios"; mkdir -p "$SP"
  put "$KIT/$MECH_REL" 'x "section \\"Kit title\\""\n'; doc "### 1. GWT scenarios"; run
  has "citation-missing${TAB}\"Kit title\"" "a directory at the path falls through to the kit"
  expect "nothing on stderr" "" "$err"; expect "exit 1" 1 "$rc"

  echo "== an empty or unreadable scripts/ copy =="
  fresh; gate "GWT scenarios"; put "$SP" ''; put "$KIT/$MECH_REL" 'x "section \\"Kit title\\""\n'
  doc "### 1. GWT scenarios"; run
  expect "an empty scripts/ copy adds no title" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "and still wins over the kit"; expect "exit 0" 0 "$rc"
  if [ "$(id -u)" != 0 ]; then
    fresh; gate "GWT scenarios"; put "$SP" 'x "section \\"Zebra rules\\""\n'; chmod 000 "$SP"
    doc "### 1. GWT scenarios"; run; chmod 644 "$SP"
    has "not-scanned${TAB}check-ticket-mechanics${TAB}unreadable" "an unreadable scripts/ copy is named"
    has "summary${TAB}1${TAB}0${TAB}1" "and counted as unscanned"; expect "exit 3" 3 "$rc"
  fi

  echo "== only check-ticket-mechanics has a scripts/ copy =="
  fresh; gate "GWT scenarios"
  put "$P/scripts/ticket-gate.md" 'section "Planted gate title"\n'
  put "$P/scripts/SKILL.md" 'section "Planted privacy title"\n'
  doc "### 1. GWT scenarios"; run
  expect "scripts/ticket-gate.md and scripts/SKILL.md are never read" 0 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}0${TAB}0" "only the gate's title is checked"
}

sc_match; sc_source; sc_kit; sc_nodoc; sc_usage; sc_ack; sc_ack_stale; sc_ack_fence; sc_alias; sc_ack_precedence; sc_markers_safe; sc_rename; sc_rename_kitfence; sc_mech_copy

# --- mutants: each breaks ONE invariant in a copy of the script; the guarding scenario must notice.
mutant() {  # mutant <description> <sed expr> <scenario>
  local m="$T/mutant.sh"
  sed -e "$2" "$S0" > "$m"
  if cmp -s "$m" "$S0"; then bad "mutant did not apply: $1"; return; fi
  S="$m"; QUIET=1; SCFAIL=0; "$3" >/dev/null 2>&1; QUIET=0; S="$S0"
  if [ "$SCFAIL" = 1 ]; then ok "mutant killed: $1"; else bad "mutant SURVIVED: $1"; fi
}
echo "== mutants =="
mutant "the title list is hardcoded, not read from the component" 's/^    for m in SECTIONREF.finditer(text):$/    for m in []:/;s/^titles = \[\]$/titles = ["Unit test specs", "E2E test specs", "GWT scenarios", "Personal data handling", "Documentation currency"]/' sc_source
mutant "a substring heading matches" 's/if t not in headings and t not in covered:/if not any(t in h for h in headings) and t not in covered:/' sc_match
mutant "the numbering prefix is not stripped" "s/^HEADING = .*/HEADING = re.compile(r'^#{1,6}\\\\s+(.+?)\\\\s*#*\\\\s*\$')/" sc_match
mutant "the parenthetical suffix is not stripped" "s/^PAREN = .*/PAREN = re.compile(r'ZZZNEVERZZZ')/" sc_match
mutant "a fenced heading counts" 's/^            if fenced:$/            if False:/' sc_match
mutant "the escaped quote form is not recognised" "s/^SECTIONREF = .*/SECTIONREF = re.compile(r'\\\\b[Ss]ection\\\\s+\"([^\"\\\\\\\\]+?)\"')/" sc_match
mutant "a wrapped citation is not joined" "s/re.sub(r'\\\\s\\*\\\\n\\\\s\\*(?:#\\\\s\\*)?', ' ', t)/t/" sc_match
mutant "a missing doc reads as an empty one" 's/^    skipped = True$/    headings = set()/' sc_nodoc
mutant "a missing gate is not reported" 's/^            not_scanned("ticket-gate", "not installed")$/            pass/' sc_source
mutant "an incomplete scan exits 0" 's/sys.exit(1 if missing or invalid else 3 if unscanned else 0)/sys.exit(1 if missing or invalid else 0)/' sc_nodoc
mutant "an unscanned file outranks a missing title" 's/sys.exit(1 if missing or invalid else 3 if unscanned else 0)/sys.exit(3 if unscanned else 1 if missing or invalid else 0)/' sc_nodoc
mutant "the registry is ignored" 's/^    for root in registry_roots(group):$/    for root in []:/' sc_source
mutant "a project-scoped entry for another project counts" 's/(scope in ("local", "project") and pp and os.path.realpath(pp) == project)/(scope in ("local", "project"))/' sc_source
mutant "the project copy is ignored" 's/^        if not os.path.islink(p):$/        if False:/' sc_source
mutant "a symlinked project copy is read" 's/^        if not os.path.islink(p):$/        if True:/' sc_source
mutant "a dangling doc link reads as a skip" 's/^if os.path.islink(doc_path) and not os.path.exists(doc_path):$/if False:/' sc_nodoc
mutant "an unknown flag is ignored" "s/^    \\*) usage \"unknown argument '\$1'\" ;;\$/    *) shift ;;/" sc_usage
mutant "a missing project directory is ignored" '/^\[ -d "\$PROJECT" \] || usage/d' sc_usage

# #543 and #547: the markers.
mutant "an acknowledged title still counts as missing" 's/if t not in headings and t not in covered:/if t not in headings:/' sc_ack
mutant "any acknowledgement silences every absent title" 's/if t not in headings and t not in covered:/if t not in headings and not covered:/' sc_ack
mutant "an acknowledged title is dropped from the checked count" 's/^        checked += 1$/        checked += t not in covered/' sc_ack
mutant "a real heading no longer wins over a marker" "s/^    if t not in cited or t in headings:/    if t not in cited:/" sc_ack
mutant "a real heading no longer wins over an alias" "s/^    if t not in cited or t in headings:/    if t not in cited:/" sc_alias
mutant "lines are split by splitlines() again" 's/enumerate(doc.split("\\n"), 1)/enumerate(doc.splitlines(), 1)/' sc_ack
mutant "a stale marker is not reported" "s/^        outcome.append((\"stale\", n, f'\"{t}\"'))                  # nothing cites it, or a heading wins/        pass/" sc_ack_stale
mutant "a stale marker changes the exit code" 's/sys.exit(1 if missing or invalid else/sys.exit(1 if missing or invalid or any(o[0] == "stale" for o in outcome) else/' sc_ack_stale
mutant "stale rows print on an incomplete scan" 's/^if unscanned: .*/if False:/' sc_ack_stale
mutant "a marker inside a fence is read" 's/^            if fenced:$/            if fenced and not line.lstrip().startswith("<!--"):/' sc_ack_fence
mutant "the acknowledgement grammar loses its closing --> anchor" "s/^\\(ACKNOWLEDGED = .*\\)\\\\s\\*-->\\\\s\\*\\\$')\$/\\1')/" sc_ack_fence
mutant "marker rows print before the missing rows" 's/^rows\[nmiss:nmiss\] = candidate_rows + marker_rows$/rows[0:0] = candidate_rows + marker_rows/' sc_ack_fence
mutant "an acknowledgement beats an alias" 's/^    elif t in first_alias: .*/    elif False:/' sc_ack_precedence
mutant "the superseded acknowledgement prints no stale row" "s/^        outcome.append((\"stale\", n, f'\"{t}\"'))\$/        pass/" sc_ack_precedence
mutant "privacy-regime is read from the registry or the kit again" 's/"skills\/privacy-regime\/SKILL.md", False)/"skills\/privacy-regime\/SKILL.md", True)/' sc_source
mutant "adapt's references/skills.md is a citer again" 's/^    ("privacy-regime", .*$/&\n    ("adapt-skills", "forge-kit-adapt", "skills\/adapt\/references\/skills.md", True),/' sc_source
mutant "the alias marker is ignored" 's/^            a, k = ALIAS.match(line), ACKNOWLEDGED.match(line)$/            a, k = None, ACKNOWLEDGED.match(line)/' sc_alias
mutant "an alias is honoured without its target heading" 's/^    elif kind == "alias" and target in headings:$/    elif kind == "alias":/' sc_alias
mutant "the last duplicate alias wins" 's/^        first_alias.setdefault(t, target)$/        first_alias[t] = target/' sc_alias
mutant "a later valid alias is promoted over a first that was not applied" 's/^        first_alias.setdefault(t, target)$/        first_alias[t] = target if target in headings or t not in first_alias else first_alias[t]/' sc_alias
mutant "an invalid marker does not set exit 1" 's/sys.exit(1 if missing or invalid else/sys.exit(1 if missing else/' sc_alias

# #544: rename candidates. A candidate implies a citation-missing row, so the exit code is 1 either
# way: a mutant letting the candidate move it is equivalent and not listed; the summary one is.
mutant "the equal-counts guard is dropped" 's/^                if len(K) != len(Pl):$/                if False:/' sc_rename
mutant "pairing keys on the position, as a section number would" 's/^            pu = \[(lv, t) for j, (lv, t) in enumerate(proj\[j0 + 1:j1\], j0 + 1) if j not in used\]$/            pu = list(proj[i0 + 1:i1])/' sc_rename
mutant "an uncited title is offered" 's/if k in missing_titles and k != h/if k != h/' sc_rename
mutant "a gap counts only the cited titles" 's/^                K = \[(i, t) for i, lv, t in ku if lv == level\]$/                K = [(i, t) for i, lv, t in ku if lv == level and t in titles]/' sc_rename
mutant "anchor order is ignored" 's/^    if \[j for i, j in anchors\] == sorted(j for i, j in anchors):$/    if True:/' sc_rename
mutant "a candidate is counted in the summary" 's/^print(f"summary\\t{checked}\\t{missing}\\t{unscanned}")$/print(f"summary\\t{checked}\\t{missing + len(candidate_rows)}\\t{unscanned}")/' sc_rename
mutant "a heading with a double quote is offered" "s/ and '\"' not in h and / and /" sc_rename
mutant "a heading with a control character is offered" "s/ and not re.search(r'\[\\\\x00-\\\\x1f\\\\x7f\]', h):/:/" sc_rename
mutant "an acknowledged title stays on the kit side" 's/^            if not (t in acked and t not in pos and t not in alias_to)\]$/            if True]/' sc_rename
mutant "an alias target is not an anchor" 's/^        j = pos.get(t, pos.get(alias_to.get(t)))$/        j = pos.get(t)/' sc_rename
mutant "candidates print after the marker rows" 's/^rows\[nmiss:nmiss\] = candidate_rows + marker_rows$/rows[nmiss:nmiss] = marker_rows + candidate_rows/' sc_rename
mutant "a fenced kit heading counts" 's/^        h = None if fenced else HEADING.match(line)$/        h = HEADING.match(line)/' sc_rename_kitfence
mutant "the project's scripts/ copy is ignored" 's/^        if not os.path.islink(sp) and not os.path.islink(os.path.dirname(sp)):$/        if False:/' sc_mech_copy
mutant "a symlinked scripts/ copy is read" 's/^        if not os.path.islink(sp) and not os.path.islink(os.path.dirname(sp)):$/        if True:/' sc_mech_copy
mutant "a file below a symlinked scripts/ directory is read" 's/^        if not os.path.islink(sp) and not os.path.islink(os.path.dirname(sp)):$/        if not os.path.islink(sp):/' sc_mech_copy
mutant "the scripts/ copy ranks after the registry and the kit" '/^            yield sp$/d;s/^        yield os.path.join(kit, "plugins", group, rel)$/&\n    if label in PROJECT_SCRIPT: yield os.path.join(project, "scripts", os.path.basename(rel))/' sc_mech_copy
mutant "the scripts/ copy is read for every citer" 's/^    if label in PROJECT_SCRIPT:$/    if True:/' sc_mech_copy
echo ""
echo "forge-adapt citation check tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
