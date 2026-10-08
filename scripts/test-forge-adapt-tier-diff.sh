#!/usr/bin/env bash
# Contract test for forge-adapt-tier-diff.sh (#281).
#
# `refresh <name>` copies this script's stdout into its report verbatim, so the contract is the
# exact line shape, the fixed key order, silence on equal keys, and an EMPTY stdout whenever it
# cannot answer. The mutants at the end are the wrong ways to read a tier: the whole file
# rather than the frontmatter, a first `---` accepted below line 1, the order dropped, and (#290)
# the CRLF strip removed from guard-lib.sh, which owns the one frontmatter extraction.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$ROOT/scripts/forge-adapt-tier-diff.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { cat > "$T/$1"; }
out=""; err=""; rc=0
# run also appends its stderr to $T/mut-err.log, the per-mutant log mutant() classifies on (#360).
run() { out=$(bash "${S:-$SCRIPT}" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); cat "$T/err" >> "$T/mut-err.log"; }

mk base.md <<'M'
---
name: demo
model: opus
effort: high
---
body
M
mk same.md <<'M'
---
name: demo-adapted
model: opus
effort: high
---
a different body, adapted for the project
M
mk effort-low.md <<'M'
---
name: demo
effort: low
---
body
M
mk no-effort.md <<'M'
---
name: demo
---
body
M
mk all-a.md <<'M'
---
name: demo
model: sonnet
effort: low
context: fork
agent: reviewer
background: true
---
M
mk all-b.md <<'M'
---
name: demo
model: opus
effort: high
context: inherit
agent: other
background: false
---
M
mk body-key.md <<'M'
---
name: demo
model: opus
effort: high
---
An example in the body is not this file's tier:

model: haiku
effort: low
M
mk no-fm.md <<'M'
# A title, not frontmatter
M
mk late-rule.md <<'M'
# No frontmatter on line 1

---
model: opus
---
M
mk unclosed.md <<'M'
---
model: opus
M
mk effort-dash.md <<'M'
---
name: demo
effort: -
---
body
M
mk effort-empty.md <<'M'
---
name: demo
effort:
---
body
M
mk effort-quoted.md <<'M'
---
name: demo
effort: "-"
---
body
M
mk effort-high.md <<'M'
---
name: demo
effort: high
---
body
M
# CRLF fixtures (#290): printf, because a heredoc here would be written with LF only.
printf -- '---\r\nname: demo\r\nmodel: opus\r\neffort: high\r\n---\r\nbody\r\n' > "$T/crlf-base.md"
printf -- '---\r\nname: demo\r\nmodel: sonnet\r\neffort: high\r\n---\r\nbody\r\n' > "$T/crlf-sonnet.md"
printf -- '---\r\nname: demo\r\nmodel: opus\r\n' > "$T/crlf-unclosed.md"
printf -- '---\r\nname: demo\r\nmodel: a\rb\r\neffort: high\r\n---\r\nbody\r\n' > "$T/crlf-midcr.md"
printf -- '---\nname: demo\nmodel: opus\r\neffort: high\r\n---\r\nbody\n' > "$T/mixed.md"
printf '' > "$T/empty.md"
printf -- '---\n' > "$T/only-fence.md"
printf -- '---\r\n' > "$T/only-fence-crlf.md"
mk inject.md <<'M'
---
name: demo
model: $(touch pwned-in-cwd)
effort: `touch pwned-in-cwd`
---
body
M

echo "== equal keys print nothing =="
run "$T/same.md" "$T/base.md"
expect "identical tier keys exit 0" 0 "$rc"
expect "and print nothing, whatever the bodies" "" "$out"

echo "== one fixed line per differing key =="
run "$T/effort-low.md" "$T/no-effort.md"
expect "a differing key exits 0" 0 "$rc"
expect "an absent catalogue key reads (absent)" "tier: effort local=low forge-kit=(absent) (kept)" "$out"
run "$T/no-effort.md" "$T/base.md"
expect "absent locally reads (absent) on the local side, in key order" \
  "tier: model local=(absent) forge-kit=opus (kept)
tier: effort local=(absent) forge-kit=high (kept)" "$out"
run "$T/all-a.md" "$T/all-b.md"
expect "all five differing print five lines in the fixed order" \
  "tier: model local=sonnet forge-kit=opus (kept)
tier: effort local=low forge-kit=high (kept)
tier: context local=fork forge-kit=inherit (kept)
tier: agent local=reviewer forge-kit=other (kept)
tier: background local=true forge-kit=false (kept)" "$out"

echo "== absent versus a literal - (#290) =="
run "$T/effort-dash.md" "$T/no-effort.md"
expect "a bare effort: - against no effort key" "tier: effort local=- forge-kit=(absent) (kept)" "$out"
expect "and exits 0" 0 "$rc"
run "$T/effort-empty.md" "$T/no-effort.md"
expect "an empty effort: against no effort key is not a difference" "" "$out"
expect "and exits 0" 0 "$rc"
run "$T/effort-quoted.md" "$T/no-effort.md"
expect "effort: \"-\" keeps its quotes and is not the absent token" 'tier: effort local="-" forge-kit=(absent) (kept)' "$out"
run "$T/effort-high.md" "$T/effort-dash.md"
expect "a literal - upstream prints as -, distinct from absent" "tier: effort local=high forge-kit=- (kept)" "$out"

echo "== CRLF components read like LF ones (#290) =="
run "$T/crlf-base.md" "$T/base.md"
expect "a CRLF installed copy equal to an LF catalogue prints nothing" "" "$out"
expect "and exits 0" 0 "$rc"
run "$T/crlf-sonnet.md" "$T/base.md"
expect "a CRLF difference prints with no carriage return" "tier: model local=sonnet forge-kit=opus (kept)" "$out"
run "$T/base.md" "$T/crlf-sonnet.md"
expect "a CRLF catalogue copy reads the same" "tier: model local=opus forge-kit=sonnet (kept)" "$out"
run "$T/crlf-unclosed.md" "$T/base.md"
expect "a CRLF file with no closing fence still exits 2" 2 "$rc"
expect "with nothing on stdout" "" "$out"
case "$err" in *"has no frontmatter"*) ok "and stderr says has no frontmatter" ;; *) bad "stderr: $err" ;; esac
run "$T/mixed.md" "$T/base.md"
expect "a CRLF closing fence after an LF opening fence still closes" "" "$out"
run "$T/crlf-midcr.md" "$T/base.md"
expect "a mid-value carriage return is kept verbatim (the strip is trailing-only)" \
  "tier: model local=a"$'\r'"b forge-kit=opus (kept)" "$out"

echo "== malformed input and injection (#290) =="
for f in empty only-fence only-fence-crlf; do
  run "$T/$f.md" "$T/base.md"
  expect "$f.md exits 2 with nothing on stdout" "2:" "$rc:$out"
done
pushd "$T" >/dev/null; run "$T/inject.md" "$T/base.md"; popd >/dev/null
case "$out" in *'model local=$(touch pwned-in-cwd) '*) ok "a command substitution in a value prints literally" ;; *) bad "inject: $out" ;; esac
[ ! -e "$T/pwned-in-cwd" ] && [ ! -e pwned-in-cwd ] && ok "and no file was created" || bad "an injected command ran"

echo "== guard_has_frontmatter, the shared helper (#290) =="
has_fm() ( . "$ROOT/scripts/guard-lib.sh"; guard_has_frontmatter "$1" )
has_fm "$T/base.md"; expect "a closed block is frontmatter" 0 "$?"
has_fm "$T/unclosed.md"; expect "an unclosed block is not" 1 "$?"
has_fm "$T/no-fm.md"; expect "a file whose line 1 is a title is not" 1 "$?"
has_fm "$T/crlf-base.md"; expect "a CRLF block is frontmatter" 0 "$?"

echo "== frontmatter only =="
run "$T/body-key.md" "$T/base.md"
expect "a tier key in the body is ignored" "" "$out"
expect "and that exits 0" 0 "$rc"

echo "== refusals: exit 2, empty stdout, the file named =="
run "$T/no-fm.md" "$T/base.md"
expect "an installed file with no frontmatter exits 2" 2 "$rc"
expect "with nothing on stdout" "" "$out"
case "$err" in *no-fm.md*) ok "and stderr names the file" ;; *) bad "stderr does not name the file: $err" ;; esac
run "$T/base.md" "$T/no-fm.md"
expect "a catalogue file with no frontmatter exits 2 too" 2 "$rc"
run "$T/late-rule.md" "$T/base.md"
expect "a body --- rule below line 1 is not frontmatter" 2 "$rc"
expect "and prints nothing" "" "$out"
run "$T/unclosed.md" "$T/base.md"
expect "an unclosed frontmatter is no frontmatter" 2 "$rc"
run "$T/missing.md" "$T/base.md"
expect "an unreadable file exits 2" 2 "$rc"
expect "with nothing on stdout" "" "$out"
case "$err" in *missing.md*) ok "and stderr names it" ;; *) bad "stderr does not name it: $err" ;; esac
run "$T/base.md"
expect "one argument is a usage error" 2 "$rc"

echo "== the key set is the one array =="
expect "TIER_KEYS holds #253's five keys in order" \
  "TIER_KEYS=(model effort context agent background)" "$(grep -m1 '^TIER_KEYS=' "$SCRIPT")"

echo "== mutants die =="
M="$T/mut"; mkdir -p "$M"
. "$ROOT/scripts/mutant-crash.sh"
# td_live <build>: the build still prints its tier lines for two differing files (#360).
td_live() { S="$1" run "$T/all-a.md" "$T/all-b.md"; case "$out" in "tier: "*) return 0 ;; esac; return 1; }
# mutant <name> <python replace: old> <new> <check-fn> [<kill-fn>]: the build goes to ${MD:-$M}. A
# failed check is a kill only when the build did not crash and, given a kill-fn, that holds too.
# MT names the file in the build directory the edit is applied to (default the script itself; #290
# aims it at guard-lib.sh, which owns the frontmatter rule).
# EVERY CALL STARTS BY RECOPYING BOTH PRISTINE FILES (#290), so one mutant's edit never leaks into the
# next: the old mutant() was stateless because it rewrote the script from $SCRIPT each time, and that
# stops being true the moment a second file is mutable. The reset control below proves it.
mutant() {
  local d="${MD:-$M}" held=0 sig=1 why tgt="${MT:-forge-adapt-tier-diff.sh}"
  mkdir -p "$d"
  cp "$ROOT/scripts/guard-lib.sh" "$d/guard-lib.sh"; cp "$SCRIPT" "$d/forge-adapt-tier-diff.sh"
  python3 - "$ROOT/scripts/$tgt" "$d/$tgt" "$2" "$3" <<'P' || { bad "mutant $1 did not apply"; return; }
import sys
src = open(sys.argv[1]).read()
if sys.argv[3] not in src: sys.exit(1)
open(sys.argv[2], "w").write(src.replace(sys.argv[3], sys.argv[4]))
P
  : > "$T/mut-err.log"
  S="$d/forge-adapt-tier-diff.sh" "$4" && held=1
  if [ "$held" = 0 ] && [ -n "${5:-}" ]; then S="$d/forge-adapt-tier-diff.sh" "$5" || sig=0; fi
  why=$(mutant_crash_reason "$d/forge-adapt-tier-diff.sh" "$T/mut-err.log" td_live "$d/forge-adapt-tier-diff.sh")
  if [ -n "$why" ]; then bad "mutant $1 crashed ($why)"
  elif [ "$held" = 1 ]; then bad "mutant $1 survived"
  elif [ "$sig" = 0 ]; then bad "mutant $1 failed without its kill signature"
  else ok "mutant $1 dies"; fi
}
body_is_ignored() { run "$T/body-key.md" "$T/base.md"; [ "$rc" = 0 ] && [ -z "$out" ]; }
late_rule_refused() { run "$T/late-rule.md" "$T/base.md"; [ "$rc" = 2 ] && [ -z "$out" ]; }
# The positive kill of late-first-rule: the mutant ADMITS the late rule as frontmatter. rc 2 with an
# empty stdout is also what a syntax error gives, so late_rule_refused alone cannot tell them apart.
late_rule_admitted() { run "$T/late-rule.md" "$T/base.md"; [ "$rc" = 0 ] && [ "${out%%$'\n'*}" = "tier: model local=(absent) forge-kit=opus (kept)" ]; }
# The CRLF read: a CRLF copy against an LF one prints its one difference with no carriage return.
crlf_read() { run "$T/crlf-sonnet.md" "$T/base.md"; [ "$rc" = 0 ] && [ "$out" = "tier: model local=sonnet forge-kit=opus (kept)" ]; }
crlf_refused() { run "$T/crlf-sonnet.md" "$T/base.md"; [ "$rc" = 2 ] && [ -z "$out" ]; }
order_kept() { run "$T/all-a.md" "$T/all-b.md"; [ "$(printf '%s\n' "$out" | head -1)" = "tier: model local=sonnet forge-kit=opus (kept)" ]; }
mutant whole-file 'a=$(component_frontmatter_field "$1" "$k"); b=$(component_frontmatter_field "$2" "$k")' \
  'a=$(sed -n "s/^$k:[[:space:]]*//p" "$1" | tail -1); b=$(sed -n "s/^$k:[[:space:]]*//p" "$2" | tail -1)' body_is_ignored
MT=guard-lib.sh mutant late-first-rule 'NR==1 && $0 != "---" { exit 1 }' '' late_rule_refused late_rule_admitted
# Reset control (#290): it runs AFTER the guard-lib mutant, while the leak hazard is live. A no-op
# edit (old text equal to new) of the script must SURVIVE late_rule_refused, which the leaked edit
# would break (it admits a late rule). order_kept, the check the ticket named, cannot see this leak:
# a build without the line-1 test still orders its keys. Were mutant() not to recopy guard-lib.sh, the
# late-first-rule edit would still sit in the build and the no-op would be reported as dying. Its survival is observed by capturing the output, so the
# expected survivor is not booked as a suite failure.
cap=$(mutant noop-after-guard-lib 'for k in "${TIER_KEYS[@]}"; do' 'for k in "${TIER_KEYS[@]}"; do' late_rule_refused)
case "$cap" in *"FAIL: mutant noop-after-guard-lib survived"*) ok "reset control (#290): a no-op mutant after the guard-lib mutant survives, so no edit leaks between mutants" ;;
  *) bad "reset control (#290): a no-op mutant did not survive: $cap" ;; esac
mutant order-dropped 'for k in "${TIER_KEYS[@]}"; do' 'for k in $(printf "%s\n" "${TIER_KEYS[@]}" | sort); do' order_kept
MT=guard-lib.sh mutant crlf-not-stripped 'awk '"'"'{ sub(/\r$/, "") }' 'awk '"'"'{ }' crlf_read crlf_refused

# Crash control (#360): a `fi fi` build in its own directory exits 2 with an empty stdout, exactly
# what late_rule_refused expects. mutant runs in $( ), so its rows stay out of the total.
mkdir -p "$T/crash"; cp "$ROOT/scripts/guard-lib.sh" "$T/crash/"
{ sed -n 1p "$SCRIPT"; echo 'fi fi'; sed 1d "$SCRIPT"; } > "$T/crash/forge-adapt-tier-diff.sh"
crash_ok=1; crashed=0
cmp -s "$T/crash/forge-adapt-tier-diff.sh" "$SCRIPT" && crash_ok=0
for c in late_rule_refused body_is_ignored order_kept; do
  cap=$(MD="$T/crash" mutant crash-control $'#!/usr/bin/env bash\n' $'#!/usr/bin/env bash\nfi fi\n' "$c")
  case "$cap" in *" dies"*|*" survived"*) crash_ok=0 ;; *"FAIL: mutant crash-control crashed ("*) crashed=$((crashed + 1)) ;; esac
done
[ "$crash_ok" = 1 ] && [ "$crashed" = 3 ] && ok "crash control (#360): tier-diff reports an rc 2 syntax-error build as crashed, never as dies" \
  || bad "crash control (#360): tier-diff credited or missed a syntax-error build ($crashed of 3 crashed)"

echo ""
echo "tier-diff tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
