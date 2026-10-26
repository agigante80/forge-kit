#!/usr/bin/env bash
# Contract test for plugins/forge-kit-adapt/skills/adapt/assets/hook-unwire.sh (#564).
#
# The script is the first half of retiring a project-local hook copy the plugin now provides: unwire,
# then delete. The failure it exists to prevent is a wired hook whose file is gone (exit 2 on every
# matching call), so the cases that matter are: the right entries go, a neighbour never does, a bad
# name touches nothing, and a file that cannot be edited safely is left byte for byte as it was.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
S="$ROOT/plugins/forge-kit-adapt/skills/adapt/assets/hook-unwire.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hook-unwire-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
cap() { # cap <args...>: sets cout, cerr, crc from one run, stdout and stderr apart
  local e; e=$(mktemp "$T/e.XXXXXX"); cout=$(bash "$S" "$@" 2>"$e"); crc=$?; cerr=$(cat "$e"); rm -f "$e"
}
mk() { # mk <name> <json>: a project dir with that settings.json
  mkdir -p "$T/$1/.claude"; printf '%s' "$2" > "$T/$1/.claude/settings.json"; echo "$T/$1"
}
SJ() { echo "$1/.claude/settings.json"; }

BOTH='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"python3","args":["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dashes.py"]},{"type":"command","command":"python3","args":["${CLAUDE_PROJECT_DIR}/.claude/hooks/my-block-dashes.py"]}]},{"matcher":"Write","hooks":[{"type":"command","command":"sh -c '"'"'exec python3 \"$0\"'"'"' /x/.claude/hooks/block-dashes.py"}]}],"Stop":[{"hooks":[{"type":"command","command":"python3 /a/block-dashes.sh"}]}]},"other":1}'

echo "== removal across events, group handling, path boundary =="
P=$(mk a "$BOTH"); cap block-dashes --project "$P"
[ "$crc" = 0 ] && ok "exit 0 when entries were removed" || bad "exit 0 (got $crc: $cerr)"
case "$cout" in *"removed 3 wiring entries for block-dashes"*) ok "reports the count" ;; *) bad "reports the count: '$cout'" ;; esac
[ "$(jq -c '.hooks.PreToolUse | map(.hooks | length)' "$(SJ "$P")")" = "[1]" ] \
  && ok "PreToolUse keeps the one group that still holds another hook, and drops the emptied one" || bad "PreToolUse groups: $(jq -c .hooks.PreToolUse "$(SJ "$P")")"
[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].args[0]' "$(SJ "$P")")" = '${CLAUDE_PROJECT_DIR}/.claude/hooks/my-block-dashes.py' ] \
  && ok "my-block-dashes.py survives: the match is on a path boundary" || bad "my-block-dashes.py survives"
[ "$(jq -c '.hooks.Stop' "$(SJ "$P")")" = "[]" ] && ok "a Stop entry is removed too (every event is searched)" || bad "Stop entry removed"
[ "$(jq -r .other "$(SJ "$P")")" = 1 ] && ok "a key outside .hooks is untouched" || bad "other key untouched"
cap block-dashes --project "$P"
[ "$crc" = 0 ] && [ "$cout" = "no wiring found for block-dashes" ] && ok "a second run prints 'no wiring found for block-dashes' and exits 0" || bad "second run: rc=$crc '$cout'"

echo "== a group this removal did not touch is kept as it was =="
P=$(mk b '{"hooks":{"PreToolUse":[{"matcher":"X","hooks":[]},{"matcher":"Bash","hooks":[{"type":"command","command":"python3 /h/block-dashes.py"}]}]}}')
cap block-dashes --project "$P"
[ "$(jq -c '[.hooks.PreToolUse[].matcher]' "$(SJ "$P")")" = '["X"]' ] && ok "an already-empty group stays, the emptied one goes" || bad "empty group handling: $(jq -c . "$(SJ "$P")")"

echo "== the end of the name is a boundary too =="
P=$(mk bd '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 /h/block-dashes.python"},{"type":"command","command":"python3 /h/block-dashes.shx"}]}]}}'); before=$(cat "$(SJ "$P")")
cap block-dashes --project "$P"
[ "$cout" = "no wiring found for block-dashes" ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && ok "block-dashes.python and block-dashes.shx are not block-dashes" || bad "end boundary: '$cout'"

echo "== the .sh form and the command-only form =="
P=$(mk c '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"/p/hooks/masked-exit-advisory.sh"}]}]}}')
cap masked-exit-advisory --project "$P"
[ "$(jq -c '.hooks.PostToolUse' "$(SJ "$P")")" = "[]" ] && ok "a .sh command is matched" || bad ".sh matched"

echo "== nothing wired =="
P=$(mk d '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"python3 /h/other.py"}]}]}}'); before=$(cat "$(SJ "$P")")
cap block-dashes --project "$P"
[ "$crc" = 0 ] && [ "$cout" = "no wiring found for block-dashes" ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && ok "an unrelated settings.json is byte for byte unchanged" || bad "unrelated: rc=$crc '$cout'"
P=$(mk e '{"permissions":{}}'); before=$(cat "$(SJ "$P")")
cap block-dashes --project "$P"
[ "$crc" = 0 ] && [ "$cout" = "no wiring found for block-dashes" ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && ok "no .hooks key: unchanged, exit 0" || bad "no .hooks: rc=$crc '$cout'"
mkdir -p "$T/f"; cap block-dashes --project "$T/f"
[ "$crc" = 0 ] && [ "$cout" = "no wiring found for block-dashes" ] && [ ! -e "$T/f/.claude/settings.json" ] && ok "no settings.json: exit 0 and none created" || bad "no file: rc=$crc '$cout'"
P=$(mk g '{"hooks":{"PreToolUse":"oops","Stop":[7,{"hooks":"x"}]}}'); before=$(cat "$(SJ "$P")")
cap block-dashes --project "$P"
[ "$crc" = 0 ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && ok "odd shapes under .hooks are skipped, not a crash" || bad "odd shapes: rc=$crc '$cerr'"

echo "== a settings.json that cannot be edited safely is left alone =="
P=$(mk h '{not json'); before=$(cat "$(SJ "$P")")
cap block-dashes --project "$P"
[ "$crc" = 1 ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && ok "invalid JSON: exit 1, file unchanged" || bad "invalid JSON: rc=$crc"
case "$cerr" in *"not valid JSON"*) ok "and says so on stderr" ;; *) bad "says so: '$cerr'" ;; esac
P=$(mk i "$BOTH"); mv "$(SJ "$P")" "$T/real.json"; ln -s "$T/real.json" "$(SJ "$P")"; before=$(cat "$T/real.json")
cap block-dashes --project "$P"
[ "$crc" = 1 ] && [ "$(cat "$T/real.json")" = "$before" ] && ok "a symlinked settings.json: exit 1, target unchanged" || bad "symlink: rc=$crc"
ls "$T/i/.claude" | grep -q '^\.settings\.' && bad "no temp file left behind (symlink)" || ok "no temp file left behind (symlink)"
P=$(mk j "$BOTH"); ls -a "$P/.claude" > "$T/j.before"; cap block-dashes --project "$P"; ls -a "$P/.claude" > "$T/j.after"
cmp -s "$T/j.before" "$T/j.after" && ok "a successful run leaves no temp file in .claude" || bad "temp file left behind"

echo "== mode is kept =="
P=$(mk k "$BOTH"); chmod 640 "$(SJ "$P")"; cap block-dashes --project "$P"
[ "$(stat -c %a "$(SJ "$P")" 2>/dev/null || stat -f %Lp "$(SJ "$P")")" = 640 ] && ok "mode 640 is kept" || bad "mode kept"

echo "== the name guard: refused before anything is read or written =="
P=$(mk n "$BOTH"); before=$(cat "$(SJ "$P")")
for nm in block-dashes.py block-dashes.sh ../x a/b -x X Block "block dashes" ""; do
  cap "$nm" --project "$P"
  if [ "$crc" = 2 ] && [ "$(cat "$(SJ "$P")")" = "$before" ] && [ -z "$cout" ]; then ok "'$nm' exits 2 and touches nothing"; else bad "'$nm' (rc=$crc, '$cout')"; fi
  case "$cerr" in *hook-unwire:*) ok "'$nm' stderr carries the hook-unwire: prefix" ;; *) bad "'$nm' stderr: '$cerr'" ;; esac
done
cap "block-dashes.py" --project "$P"
case "$cerr" in *block-dashes.py*) ok "the refusal names the refused name" ;; *) bad "refusal names the name: '$cerr'" ;; esac
cap --project "$P"; [ "$crc" = 2 ] && ok "no name exits 2" || bad "no name (rc=$crc)"
cap a b --project "$P"; [ "$crc" = 2 ] && ok "two names exits 2" || bad "two names (rc=$crc)"
cap block-dashes --nonsense; [ "$crc" = 2 ] && ok "an unknown flag exits 2" || bad "unknown flag (rc=$crc)"
cap block-dashes --project; [ "$crc" = 2 ] && ok "--project without a value exits 2" || bad "--project no value (rc=$crc)"

echo "== it edits nothing but .claude/settings.json =="
P=$(mk o "$BOTH"); mkdir -p "$P/.claude/hooks"; echo x > "$P/.claude/hooks/block-dashes.py"; echo '{"a":1}' > "$P/.claude/settings.local.json"
cap block-dashes --project "$P"
[ -f "$P/.claude/hooks/block-dashes.py" ] && ok "the hook file is never deleted" || bad "hook file deleted"
[ "$(cat "$P/.claude/settings.local.json")" = '{"a":1}' ] && ok "settings.local.json is never edited" || bad "settings.local.json edited"

echo ""
echo "hook-unwire tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
