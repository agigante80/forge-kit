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
  put "$KIT/plugins/forge-kit-security/skills/privacy-regime/SKILL.md" 'section "Unit test specs"\n'
  doc "### 2. Verification steps"; run
  expect "one row for the title" 1 "$(nrows citation-missing)"
  has "summary${TAB}1${TAB}1${TAB}0" "the summary counts distinct titles"

  echo "== the privacy-regime and adapt citations are scanned =="
  fresh; gate "Unit test specs"
  put "$KIT/plugins/forge-kit-security/skills/privacy-regime/SKILL.md" 'section "Personal data handling"\n'
  put "$KIT/plugins/forge-kit-adapt/skills/adapt/references/skills.md" 'section "Security checklist"\n'
  doc "### 2. Unit test specs"; run
  has "citation-missing${TAB}\"Personal data handling\"" "privacy-regime's citation is checked"
  has "citation-missing${TAB}\"Security checklist\"" "adapt's citation is checked"

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

sc_match; sc_source; sc_kit; sc_nodoc; sc_usage

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
mutant "a substring heading matches" 's/if t not in headings:/if not any(t in h for h in headings):/' sc_match
mutant "the numbering prefix is not stripped" "s/^HEADING = .*/HEADING = re.compile(r'^#{1,6}\\\\s+(.+?)\\\\s*#*\\\\s*\$')/" sc_match
mutant "the parenthetical suffix is not stripped" "s/^PAREN = .*/PAREN = re.compile(r'ZZZNEVERZZZ')/" sc_match
mutant "a fenced heading counts" 's/^            if fenced:$/            if False:/' sc_match
mutant "the escaped quote form is not recognised" "s/^SECTIONREF = .*/SECTIONREF = re.compile(r'\\\\b[Ss]ection\\\\s+\"([^\"\\\\\\\\]+?)\"')/" sc_match
mutant "a wrapped citation is not joined" "s/re.sub(r'\\\\s\\*\\\\n\\\\s\\*(?:#\\\\s\\*)?', ' ', t)/t/" sc_match
mutant "a missing doc reads as an empty one" 's/^    skipped = True$/    headings = set()/' sc_nodoc
mutant "a missing gate is not reported" 's/^            not_scanned("ticket-gate", "not installed")$/            pass/' sc_source
mutant "an incomplete scan exits 0" 's/sys.exit(1 if missing else 3 if unscanned else 0)/sys.exit(1 if missing else 0)/' sc_nodoc
mutant "an unscanned file outranks a missing title" 's/sys.exit(1 if missing else 3 if unscanned else 0)/sys.exit(3 if unscanned else 1 if missing else 0)/' sc_nodoc
mutant "the registry is ignored" 's/^    for root in registry_roots(group):$/    for root in []:/' sc_source
mutant "a project-scoped entry for another project counts" 's/(scope in ("local", "project") and pp and os.path.realpath(pp) == project)/(scope in ("local", "project"))/' sc_source
mutant "the project copy is ignored" 's/^        if not os.path.islink(p):$/        if False:/' sc_source
mutant "a symlinked project copy is read" 's/^        if not os.path.islink(p):$/        if True:/' sc_source
mutant "a dangling doc link reads as a skip" 's/^if os.path.islink(doc_path) and not os.path.exists(doc_path):$/if False:/' sc_nodoc
mutant "an unknown flag is ignored" "s/^    \\*) usage \"unknown argument '\$1'\" ;;\$/    *) shift ;;/" sc_usage
mutant "a missing project directory is ignored" '/^\[ -d "\$PROJECT" \] || usage/d' sc_usage

echo ""
echo "forge-adapt citation check tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
