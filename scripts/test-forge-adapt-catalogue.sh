#!/usr/bin/env bash
# Contract test for forge-adapt-catalogue.sh, run against this repo (which IS a forge-kit library).
# Guards the exact regressions LLM executors kept reintroducing: SKILL.md-instead-of-name and a
# non-zero exit on a hookless group.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCRIPT="$HERE/forge-adapt-catalogue.sh"

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

out=$(bash "$SCRIPT" "$ROOT"); rc=$?

[ "$rc" -eq 0 ] && ok "exits 0 (hookless groups do not fail)" || bad "exits 0 (got rc=$rc)"

# Binds to a DIGIT, not a bare "v": "vnone" starts with v, so the old `| v` form was satisfied by
# the very failure it existed to detect (issue #95). Every version assertion below does the same.
grep -qP '^skill: adapt \| v[0-9]+' <<< "$out" \
  && ok "skills print their DIRECTORY name and a real marker (skill: adapt)" \
  || bad "skills print their directory name and a real marker"

if grep -q 'SKILL.md' <<< "$out"; then
  bad "no row prints SKILL.md as the name"
else
  ok "no row prints SKILL.md as the name"
fi

grep -qP '^subagent: ticket-gate \| v[0-9]+' <<< "$out" \
  && ok "a known agent appears with its marker (ticket-gate)" \
  || bad "a known agent appears with its marker"

# owasp-api-security rather than api-design-principles: the latter was retired with the whole
# forge-kit-backend group in #178, and a test pinned to a component that no longer exists tells you
# nothing about the catalogue.
grep -qP '^skill: owasp-api-security \| v[0-9]+' <<< "$out" \
  && ok "a known skill appears with its marker" \
  || bad "a known skill appears with its marker"

grep -qP '^hook: block-dashes \| v[0-9]+' <<< "$out" \
  && ok "a known hook appears with its marker (block-dashes)" \
  || bad "a known hook appears with its marker"

# Versioned shell assets (issue #64): the catalogue must list them, or drift/refresh has no
# forge-kit-side version to compare an installed scripts/forge-lib.sh against.
grep -qP '^asset: forge-lib \| v[0-9]+' <<< "$out" \
  && ok "a versioned shell asset appears with its marker (forge-lib)" \
  || bad "a versioned shell asset appears with its marker (forge-lib)"
# #206: a sourced library is an asset like any other, so it is catalogued with its marker too.
grep -qP '^asset: leak-lib \| v1$' <<< "$out" \
  && ok "a sourced shell library appears with its marker (leak-lib)" \
  || bad "a sourced shell library appears with its marker (leak-lib)"

# #506: the lockstep guard is a catalogued, versioned asset, so drift can compare an installed copy.
grep -qP '^asset: check-template-lockstep \| v1$' <<< "$out" \
  && ok "the template lockstep guard appears with its marker (check-template-lockstep)" \
  || bad "the template lockstep guard appears with its marker (check-template-lockstep)"

# No row may print "vnone". The catalogue walks exactly the five path shapes that
# validate-plugins.sh requires a <name>-version marker on, so every row it prints has a marker in
# its file by construction; a "vnone" therefore means the catalogue FAILED TO READ a marker that is
# provably there, never that the component is genuinely unversioned. That is what issue #95 was:
# skills/adapt/SKILL.md carries "forge-adapt-version" while the row name is its directory, "adapt".
if grep -q '| vnone$' <<< "$out"; then
  bad "no row prints vnone ($(printf '%s\n' "$out" | grep -c '| vnone$') found)"
else
  ok "no row prints vnone (every catalogued file carries a marker by construction)"
fi

# --tsv mode (issue #96): a second consumer (update-component-index.py) needs the file PATH, which
# the default rows do not carry. It is a mode on THIS script rather than a second walk elsewhere,
# so "what counts as a component" keeps exactly one definition.
tsv=$(bash "$SCRIPT" --tsv "$ROOT"); trc=$?

[ "$trc" -eq 0 ] && ok "--tsv exits 0" || bad "--tsv exits 0 (got rc=$trc)"

if grep -q '^=== ' <<< "$tsv"; then
  bad "--tsv emits no === group === headers"
else
  ok "--tsv emits no === group === headers"
fi

# Every row: exactly 5 tab-separated fields, and the last one is a file that exists.
tsv_rows=$(printf '%s\n' "$tsv" | grep -c .)
tsv_ok=$(printf '%s\n' "$tsv" | awk -F'\t' 'NF==5' | wc -l)
[ "$tsv_rows" -gt 0 ] && [ "$tsv_rows" -eq "$tsv_ok" ] \
  && ok "--tsv rows all have 5 fields ($tsv_rows rows)" \
  || bad "--tsv rows all have 5 fields ($tsv_ok of $tsv_rows)"

missing=$(printf '%s\n' "$tsv" | awk -F'\t' 'NF==5 {print $5}' | while read -r f; do [ -f "$f" ] || echo "$f"; done)
[ -z "$missing" ] && ok "--tsv path field points at a real file" \
  || bad "--tsv path field points at a real file (missing: $(printf '%s' "$missing" | head -1))"

# The version field is bare digits here (no "v" prefix), and never "none" for the same
# reason the default mode never prints vnone.
if grep -q . <<< "$(printf '%s\n' "$tsv" | awk -F'\t' 'NF==5 && $4 !~ /^[0-9]+$/')"; then
  bad "--tsv version field is bare digits"
else
  ok "--tsv version field is bare digits"
fi

# Both modes must describe the SAME component set, or the two consumers disagree about what
# forge-kit contains, which is the drift #96 exists to remove.
text_n=$(printf '%s\n' "$out" | grep -c '^[a-z]*: ')
[ "$text_n" -eq "$tsv_rows" ] \
  && ok "--tsv and default mode agree on component count ($text_n)" \
  || bad "--tsv and default mode agree on count (text=$text_n tsv=$tsv_rows)"

# Missing/absent library arg is a graceful exit 0 (read-only, no crash).
bash "$SCRIPT" /nonexistent-forge-kit >/dev/null 2>&1 && ok "missing library dir exits 0" || bad "missing library dir exits 0"

# #533: the marker read must not need GNU grep -P (stock macOS grep rejects it, so every row would read
# vnone and drift would say unversioned). The shim rejects any -P grep and is on PATH ONLY for the script
# under test: this suite's own assertions above use grep -qP. It resolves the real grep with type -P
# BEFORE PATH is changed, because exec-by-name from a shim dir that is first on PATH recurses forever.
REALGREP=$(type -P grep)
case "$REALGREP" in /*) ;; *) echo "FAIL: cannot resolve an absolute grep ($REALGREP)"; exit 1 ;; esac
T533=$(mktemp -d "${TMPDIR:-/tmp}/cat533.XXXXXX"); trap 'rm -rf "$T533"' EXIT
mkdir -p "$T533/shim"
cat > "$T533/shim/grep" <<EOS
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    --) break ;;
    --perl-regexp|-[a-zA-Z]*P*) echo "grep: invalid option -- P" >&2; exit 2 ;;
  esac
done
exec "$REALGREP" "\$@"
EOS
chmod +x "$T533/shim/grep"
shimcat() { PATH="$T533/shim:$PATH" bash "$SCRIPT" "$1"; }
mklib() { local d="$T533/$1"; mkdir -p "$d/plugins/g/agents"; printf '%s\n' "$2" > "$d/plugins/g/agents/code-reviewer.md"; echo "$d"; }
row533() { grep -F 'subagent: code-reviewer |' <<< "$1"; }

L1=$(mklib l1 '<!-- code-reviewer-version: 7 -->')
[ "$(row533 "$(shimcat "$L1")")" = 'subagent: code-reviewer | v7' ] \
  && ok "#533: under a grep that rejects -P the marker still reads v7" || bad "#533: shimmed marker read"
[ "$(shimcat "$L1")" = "$(bash "$SCRIPT" "$L1")" ] \
  && ok "#533: shimmed output is byte-identical to the plain-grep output" || bad "#533: shim and plain output differ"
L2=$(mklib l2 $'<!-- other-version: 2 -->\n<!-- code-reviewer-version: 7 -->')
[ "$(row533 "$(shimcat "$L2")")" = 'subagent: code-reviewer | v7' ] \
  && ok "#533: a foreign marker on an earlier line does not win over the component's own (kills a line-56 revert)" || bad "#533: own marker lost to a foreign one"
L3=$(mklib l3 '<!-- other-version: 2 -->')
[ "$(row533 "$(shimcat "$L3")")" = 'subagent: code-reviewer | v2' ] \
  && ok "#533: the deliberate any-marker fallback still reads v2 under the shim" || bad "#533: fallback row"
L4=$(mklib l4 '<!-- template-version: 6 -->')
[ "$(row533 "$(shimcat "$L4")")" = 'subagent: code-reviewer | vnone' ] \
  && ok "#533: a lone template-version marker is not a component marker (vnone)" || bad "#533: template-version read as a component marker"
L5=$(mklib l5 'no marker here')
[ "$(row533 "$(shimcat "$L5")")" = 'subagent: code-reviewer | vnone' ] \
  && ok "#533: no marker at all reads vnone" || bad "#533: unmarked row"
real_rows=$(shimcat "$ROOT" | grep -c '| vnone$')
[ "$real_rows" -eq 0 ] && ok "#533: over this repository, no row is vnone under the -P-rejecting grep" || bad "#533: $real_rows vnone rows under the shim"
# Drift end to end: what the user sees. Local v7 against the shimmed catalogue v7 is current; v6 is behind.
cv=$(row533 "$(shimcat "$L1")"); cv=${cv##*| }
[ "$(bash "$HERE/forge-adapt-drift-status.sh" --local v7 --catalogue "$cv")" = current ] \
  && ok "#533: drift word is current against the shimmed catalogue read" || bad "#533: drift word current"
[ "$(bash "$HERE/forge-adapt-drift-status.sh" --local v6 --catalogue "$cv")" = behind ] \
  && ok "#533: drift word is behind (not unversioned) for a v6 install" || bad "#533: drift word behind"
# Static ban: no grep flag cluster containing P, separated or not, in the two files this ticket converted.
ban='grep([[:space:]]+-[a-zA-Z]+)*[[:space:]]+(-[a-zA-Z]*P|--perl-regexp)'
for f in "$ROOT/plugins/forge-kit-adapt/skills/adapt/SKILL.md" "$HERE/forge-adapt-catalogue.sh"; do
  hits=$(grep -nE -- "$ban" "$f" || true)
  [ -z "$hits" ] && ok "#533: no grep -P in $(basename "$f")" || bad "#533: grep -P in $(basename "$f"): $hits"
done
for s in 'grep -oP x' 'grep -o -P x' 'grep -hoiP x' 'grep -qP x' 'grep --perl-regexp x'; do
  grep -qE -- "$ban" <<< "$s" && ok "#533: ban pattern catches '$s'" || bad "#533: ban pattern misses '$s'"
done
for s in "grep -hoiE x" "grep -qE x" "sed -nE x" "grep -m1 x"; do
  grep -qE -- "$ban" <<< "$s" && bad "#533: ban pattern wrongly catches '$s'" || ok "#533: ban pattern passes '$s'"
done

echo ""
echo "forge-adapt-catalogue tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
