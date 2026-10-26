#!/usr/bin/env bash
# Contract test for usage-report/scripts/usage-report.py (#566).
#
# The script reports where Claude Code usage went from the transcripts under ~/.claude/projects, and
# the obvious counting method is wrong by a factor of two (#280), so the accounting rule is the
# contract and every wrong method is a MUTANT below that must lose at least one assertion. Every
# case runs it as a subprocess over a SYNTHETIC root built in a throwaway directory: hand-written
# records whose shape follows the keys #280's trimmed real fixtures carry, with the four inputs a
# real machine hits on the first run (a truncated last line, a non-UTF-8 byte, an empty file and a
# 3 MB line). The numbers below are hand-computed once from the last line per id and written out
# beside each record. STREAMS ARE THE CONTRACT: the tables or one JSON object on stdout and exit 0,
# or nothing on stdout and exit 2; warnings name a file by its project name and the rest of its
# root-relative path, plus the line, never the root and never the slug.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-devops/skills/usage-report/scripts/usage-report.py"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { if grep -qF -- "$2" <<< "$3"; then ok "$1"; else bad "$1 (no '$2' in output)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$3"; then bad "$1 ('$2' present)"; else ok "$1"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(cd -P "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
[ -n "$T" ] || { echo "mktemp -d failed (TMPDIR=${TMPDIR:-unset})"; exit 1; }
# A far-from-UTC zone, so a build that buckets by local day changes the day table (the local-day
# mutant); the report must not depend on it, and one row compares two zones.
export HOME="$T/home" TZ=Pacific/Kiritimati; mkdir -p "$HOME"
FX="$T/root"

SCRIPT="$SRC"
out=""; err=""; rc=0
# run also appends its stderr to $T/mut-err.log, the log mutant() classifies a crash on (#360).
run() { out=$(python3 "$SCRIPT" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); cat "$T/err" >> "$T/mut-err.log"; }
# j <expr>: one value of the JSON in $out, through python so the suite needs no jq. The eval runs
# only the literal expressions written in this file, never anything read from the report.
j() { python3 -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" <<< "$out" 2>/dev/null; }
# row <table> <python filter>: the first row of a --json table matching the filter, as "turns context output".
row() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d[sys.argv[1]]:
    if eval(sys.argv[2]): print(r["turns"], r["context"], r["output"]); break' "$1" "$2" <<< "$out" 2>/dev/null
}
# line <text> : the first stdout line holding the text.
line() { grep -F -m1 -- "$1" <<< "$out"; }

# The synthetic root. Window used throughout: --days 7 --until 2026-03-10, so
# [2026-03-04T00:00Z, 2026-03-11T00:00Z). Hand count of the 14 turns inside it, context being
# input + cache write + cache read, LAST line per id:
#   a1 1110/50   a2 2220/60   b1 3330/70 (subagent; the parent's copy with 999s is skipped)
#   b2 4440/80   a4 6/4       a5 250000/10 (the 3 MB line)   n1 100/1 (nested subagent)
#   c1 50000/5   c2 60000/5   d1 10/1   d2 21/1   e1 3/1   e3 6/0 (no output_tokens)   e4 0/0 (usage null)
#   context 371246 = uncached 104 + cache write 1005 + cache read 370137; output 288
#   o1 is outside the window, c3's LAST line is past the window end though its first is inside,
#   e5's timestamp is at the calendar's edge, syn1 and syn2 are <synthetic>, s4's mtime is before
#   the window.
python3 - "$FX" <<'PY'
import json, os, sys
root = sys.argv[1]
A = "-srv-work-demo-alpha"; B = "-srv-work-demo-beta"
S1 = "s1000000-0000-4000-8000-000000000001"; S2 = "s2000000-0000-4000-8000-000000000002"
S3 = "s3000000-0000-4000-8000-000000000003"; S4 = "s4000000-0000-4000-8000-000000000004"
S5 = "s5000000-0000-4000-8000-000000000005"; S6 = "s6000000-0000-4000-8000-000000000006"
OPUS, SONNET, HAIKU_D, HAIKU = "claude-opus-5-5", "claude-sonnet-5", "claude-haiku-4-5-20251001", "claude-haiku-5-5"
WEIRD = "x`$(echo pwn){}%s{0}"

def rec(mid, model, ts, i, cw, cr, o, side=False, split=None, **extra):
    usage = {"input_tokens": i, "cache_creation_input_tokens": cw, "cache_read_input_tokens": cr, "output_tokens": o}
    if split is not None:
        usage["cache_creation"] = {"ephemeral_5m_input_tokens": split[0], "ephemeral_1h_input_tokens": split[1]}
    r = {"type": "assistant", "timestamp": ts, "isSidechain": side, "requestId": "req-" + mid, "version": "2.1.310",
         "message": {"id": mid, "model": model, "usage": usage, "content": [{"type": "text", "text": "SENTINEL-" + mid}]}}
    r.update(extra)
    return r

def write(rel, records, tail=b""):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        for r in records:
            f.write((r if isinstance(r, str) else json.dumps(r)).encode("utf-8") + b"\n")
        f.write(tail)

a1 = lambda o: rec("a1", OPUS, "2026-03-05T10:00:00Z", 10, 100, 1000, o, split=(40, 60))
write(f"{A}/{S1}.jsonl", [
    {"type": "ai-title", "title": "SENTINEL-title"},
    {"type": "user", "timestamp": "2026-03-05T09:59:00Z", "message": {"content": "SENTINEL-prompt"}},
    a1(5), a1(5), a1(5), a1(50),
    rec("b1", SONNET, "2026-03-05T10:03:00Z", 999, 999, 999, 999),
    rec("a2", OPUS, "2026-03-05T10:05:00Z", 20, 200, 2000, 60, split=(0, 200)),
    rec("o1", OPUS, "2026-02-20T10:00:00Z", 7, 7, 7, 7),
    rec("syn1", "<synthetic>", "2026-03-05T10:05:30Z", 500, 500, 500, 500, isApiErrorMessage=True),
    "[1, 2]", '"a string"', "",
    rec("a4", HAIKU_D, "2026-03-06T01:00:00Z", 1, 2, 3, 4),
    rec("a5", OPUS, "2026-03-06T02:00:00Z", 0, 0, 250000, 10, split=(0, 0), pad="x" * 3000000),
])
# b1 is stamped BEFORE a1, so a build that measures growth over every kind (a mutant) sees a
# different first turn for S1.
write(f"{A}/{S1}/subagents/agent-b.jsonl", [
    rec("b1", SONNET, "2026-03-05T09:58:00Z", 30, 300, 3000, 70, side=True, split=(300, 0)),
    rec("b2", SONNET, "2026-03-05T10:04:00Z", 40, 400, 4000, 80, side=True, split=(400, 0)),
    rec("b2", SONNET, "2026-03-05T10:04:00Z", 40, 400, 4000, 80, side=True, split=(400, 0)),
], tail=b'{"type":"assistant","message":{"id":"zz')
write(f"{A}/{S1}/subagents/agent-b.meta.json", ['{"agentType": "general-purpose", "spawnDepth": 1}'])
write(f"{A}/{S1}/subagents/workflows/wf_1/agent-nested.jsonl", [
    rec("n1", OPUS, "2026-03-05T10:07:00Z", 0, 0, 100, 1, side=True, split=(0, 0)),
])
write(f"{A}/{S2}.jsonl", [
    rec("c1", OPUS, "2026-03-04T23:30:00Z", 0, 0, 50000, 5, split=(0, 0)),
    rec("c2", OPUS, "2026-03-05T00:30:00Z", 0, 0, 60000, 5, split=(0, 0)),
    rec("c3", OPUS, "2026-03-10T23:59:59Z", 0, 0, 10, 1),
    rec("c3", OPUS, "2026-03-11T00:00:01Z", 0, 0, 20, 1),
])
write(f"{A}/{S3}.jsonl", [])
write(f"{A}/{S3}/subagents/agent-only-syn.jsonl", [
    rec("syn2", "<synthetic>", "2026-03-05T10:06:00Z", 123, 123, 123, 123, side=True, isApiErrorMessage=True),
])
write(f"{A}/{S4}.jsonl", [rec("f1", OPUS, "2026-03-05T10:00:00Z", 0, 0, 77777, 7)])
os.utime(os.path.join(root, f"{A}/{S4}.jsonl"), (1767225600, 1767225600))  # 2026-01-01T00:00:00Z
with open(os.path.join(root, f"{A}/{S5}.jsonl"), "wb") as f:
    f.write(json.dumps(rec("d1", HAIKU, "2026-03-07T08:00:00Z", 0, 0, 10, 1)).encode() + b"\n")
    f.write(b'{"type":"assistant","timestamp":"2026-03-07T08:01:00Z","message":{"id":"dx","model":"\xff\xfe"}}\n')
    f.write(json.dumps(rec("d2", HAIKU, "2026-03-07T08:02:00Z", 0, 0, 21, 1)).encode() + b"\n")
    f.write(b'{"type":"assistant","nested":' + b"[" * 100000 + b"]" * 100000 + b"}\n")  # past the recursion limit
write(f"{A}/notes.txt", ['{"type":"assistant","timestamp":"2026-03-05T10:00:00Z","message":{"id":"t1","model":"m","usage":{"input_tokens":5}}}'])
e3 = rec("e3", SONNET, "2026-03-08T11:00:00Z", 2, 2, 2, 0); del e3["message"]["usage"]["output_tokens"]
e4 = rec("e4", SONNET, "2026-03-08T12:00:00Z", 0, 0, 0, 0); e4["message"]["usage"] = None
nots = rec("e2", SONNET, "2026-03-08T10:30:00Z", 5, 5, 5, 5); del nots["timestamp"]
write(f"{B}/{S6}.jsonl", [
    rec("e1", WEIRD, "2026-03-08T12:00:00+02:00", 1, 1, 1, 1),
    nots, e3, e4,
    rec("e5", SONNET, "0001-01-01T00:00:00+01:00", 9, 9, 9, 9),  # parses, overflows on the way to UTC
])
PY
S1=s1000000-0000-4000-8000-000000000001; S3=s3000000-0000-4000-8000-000000000003

WIN=(--root "$FX" --days 7 --until 2026-03-10)

# The assertions every mutant is run against. Each echoes FAIL lines through bad(), so a mutant is
# killed when the fail count grows while it runs.
core_checks() {
  run "${WIN[@]}" --json
  expect "14 turns: distinct ids, last line each, inside the window" 14 "$(j 'd["summary"]["turns"]')"
  expect "context re-sent is the hand count" 371246 "$(j 'd["summary"]["context"]')"
  expect "output is the last line per id" 288 "$(j 'd["summary"]["output"]')"
  expect "the three tiers sum to the context" "104 1005 370137" "$(j 'd["summary"]["uncached"]') $(j 'd["summary"]["cache_write"]') $(j 'd["summary"]["cache_read"]')"
  expect "8 transcripts opened: the old-mtime file is not" 8 "$(j 'd["summary"]["transcripts"]')"
  expect "the opus main row: 5 turns, a1 a2 a5 c1 c2" "5 363330 130" "$(row by_model 'r["model"] == "claude-opus-5-5" and r["kind"] == "main"')"
  expect "the sonnet subagent row: b1 counted once, as the subagent's" "2 7770 150" "$(row by_model 'r["model"] == "claude-sonnet-5" and r["kind"] == "subagent"')"
  expect "the sonnet main row holds e3 and e4 only" "2 6 0" "$(row by_model 'r["model"] == "claude-sonnet-5" and r["kind"] == "main"')"
  expect "the nested subagent is a subagent" "1 100 1" "$(row by_model 'r["model"] == "claude-opus-5-5" and r["kind"] == "subagent"')"
  expect "a model with no cache_creation prints no split" "None None" \
    "$(j 'next(r for r in d["by_model"] if r["model"] == "claude-haiku-4-5-20251001")["cache_write_5m"]') $(j 'next(r for r in d["by_model"] if r["model"] == "claude-haiku-4-5-20251001")["cache_write_1h"]')"
  expect "the opus main split sums the 5m and 1h tiers" "40 260" \
    "$(j 'next(r for r in d["by_model"] if r["model"] == "claude-opus-5-5" and r["kind"] == "main")["cache_write_5m"]') $(j 'next(r for r in d["by_model"] if r["model"] == "claude-opus-5-5" and r["kind"] == "main")["cache_write_1h"]')"
  expect "the project name is the slug's last two components" "demo-alpha demo-beta" "$(j '" ".join(r["project"] for r in d["by_project"])')"
  expect "the synthetic-only session is listed with zeros" "0 0 0" "$(row by_session 'r["session"] == "'"$S3"'"')"
  expect "the old-mtime session is not listed" "" "$(row by_session 'r["session"].startswith("s4")')"
  expect "a session's growth is last over first main turn" "225.23" "$(j 'next(r for r in d["by_session"] if r["session"] == "'"$S1"'")["growth"]')"
  expect "the day table is by UTC date" "2026-03-04:50000 2026-03-05:71200 2026-03-06:250006 2026-03-07:31 2026-03-08:9" \
    "$(j '" ".join(r["day"] + ":" + str(r["context"]) for r in d["by_day"])')"
}

echo "== the report =="
core_checks
expect "exit 0" 0 "$rc"
expect "--json parses and the three warnings are the only stderr" 3 "$(wc -l <<< "$err" | tr -d ' ')"
has "a truncated last line is one warning naming file and line" "demo-alpha/$S1/subagents/agent-b.jsonl:4: not JSON, skipped" "$err"
has "a non-UTF-8 line is one warning naming file and line" "demo-alpha/s5000000-0000-4000-8000-000000000005.jsonl:2: not UTF-8, skipped" "$err"
has "a line nested past the recursion limit is one warning, not a traceback" "demo-alpha/s5000000-0000-4000-8000-000000000005.jsonl:4: not JSON, skipped" "$err"
hasnt "the warnings never name the root" "$FX" "$err"
hasnt "nor the slug above the project" "work-demo" "$err"
expect "mean context per turn" 26518 "$(j 'd["summary"]["context_per_turn"]')"
expect "output as a share of everything" 0.08 "$(j 'd["summary"]["output_share"]')"
expect "turns at or above 200,000 context: one of 14" "1 7.1 67.3" "$(j 'd["summary"]["big_turns"]') $(j 'd["summary"]["big_turn_share"]') $(j 'd["summary"]["big_context_share"]')"
expect "the window is recorded" "2026-03-04T00:00:00Z 2026-03-11T00:00:00Z 2026-03-10 7" "$(j 'd["summary"]["window_start"]') $(j 'd["summary"]["window_end"]') $(j 'd["summary"]["until"]') $(j 'd["summary"]["days"]')"
expect "isSidechain is carried as a count per row" "2 0" "$(j 'next(r for r in d["by_model"] if r["kind"] == "subagent" and r["model"] == "claude-sonnet-5")["sidechain_turns"]') $(j 'next(r for r in d["by_model"] if r["kind"] == "main" and r["model"] == "claude-opus-5-5")["sidechain_turns"]')"
expect "the session table carries first and last context" "1110 250000" "$(j 'next(r for r in d["by_session"] if r["session"] == "'"$S1"'")["first_context"]') $(j 'next(r for r in d["by_session"] if r["session"] == "'"$S1"'")["last_context"]')"
expect "s2 grew 50000 to 60000" 1.2 "$(j 'next(r for r in d["by_session"] if r["session"].startswith("s2"))["growth"]')"
expect "a session with no main turn has no growth" None "$(j 'next(r for r in d["by_session"] if r["session"] == "'"$S3"'")["growth"]')"
expect "the raw model string travels through --json verbatim" 'x`$(echo pwn){}%s{0}' "$(j 'next(r["model"] for r in d["by_model"] if r["model"].startswith("x"))')"
hasnt "no conversation text is read" "SENTINEL" "$out"
hasnt "no path above the last two components prints" "work-demo" "$out"
expect "sessions are sorted by context" "s1 s2 s5 s6 s3" "$(j '" ".join(r["session"][:2] for r in d["by_session"])')"
expect "model rows are sorted by context, then turns" "claude-opus-5-5:main claude-sonnet-5:subagent claude-opus-5-5:subagent claude-haiku-5-5:main claude-sonnet-5:main claude-haiku-4-5-20251001:main x\`\$(echo pwn){}%s{0}:main" \
  "$(j '" ".join(r["model"] + ":" + r["kind"] for r in d["by_model"])')"
jsonturns=$(j 'd["summary"]["turns"]')

echo "== the text report =="
run "${WIN[@]}"
expect "exit 0" 0 "$rc"
has "the summary line names the window and the count" "7 days ending 2026-03-10 (UTC), 8 transcripts, 14 API responses" "$out"
expect "the text summary matches the JSON summary" "14 371,246" "$jsonturns $(sed -n 's/^context re-sent \([0-9,]*\) .*/\1/p' <<< "$out")"
has "every tier is shown apart" "context re-sent 371,246 (104 uncached, 1,005 cache write, 370,137 cache read), 26,518 per turn; output 288 (0.08% of everything)" "$out"
has "the big-turn line" "turns at or above 200,000 context: 7.1% of turns, 67.3% of context" "$out"
for t in "by project" "by model" "by session (top 5)" "by day"; do has "the table '$t' is printed" "$t" "$out"; done
l=$(line "opus-5-5 "); expect "the model name is shortened for width only" "main" "$(awk '{print $2}' <<< "$l")"
l=$(line "haiku-4-5 "); expect "the dated model loses its date" "main" "$(awk '{print $2}' <<< "$l")"
expect "a missing cache_creation prints - and never 0" "- -" "$(awk '{print $(NF-1), $NF}' <<< "$l")"
l=$(line "opus-5-5 "); expect "a present split prints its tiers" "40 260" "$(awk '{print $(NF-1), $NF}' <<< "$l")"
l=$(line "${S3:0:8}"); expect "the synthetic-only session is a row of zeros with no growth" "demo-alpha 0 0 -" "$(awk '{print $2, $3, $4, $NF}' <<< "$l")"
l=$(line "${S1:0:8}"); expect "the growth column" "225.23x" "$(awk '{print $NF}' <<< "$l")"
has "a weird model string prints verbatim" 'x`$(echo pwn){}%s{0}' "$out"
hasnt "the session id is cut to 8 characters" "$S1" "$out"
hasnt "no path above the last two components prints" "work-demo" "$out"
hasnt "no conversation text is read" "SENTINEL" "$out"
expect "the day table has five rows" 5 "$(awk '/^by day/{f=1; next} f && /^20/' <<< "$out" | wc -l | tr -d ' ')"
kiri=$out
TZ=America/Anchorage run "${WIN[@]}"
expect "the report is the same in every local timezone" "$kiri" "$out"
run "${WIN[@]}" --top 2
expect "--top cuts the session table" "by session (top 2)" "$(line "by session")"
expect "to two rows" 2 "$(awk '/^by session/{f=1; next} f && /^s[0-9]/' <<< "$out" | wc -l | tr -d ' ')"

echo "== the project name rule: nothing above the project, never a username =="
FX2="$T/root2"
python3 - "$FX2" <<'PY'
import json, os, sys
root = sys.argv[1]
one = {"type": "assistant", "timestamp": "2026-03-05T10:00:00Z", "message": {"id": "p", "model": "claude-opus-5-5",
       "usage": {"input_tokens": 1, "cache_creation_input_tokens": 2, "cache_read_input_tokens": 3, "output_tokens": 4}}}
for i, slug in enumerate(["-home-alice-proj", "-home-alice", "-Users-bob-src-app", "-srv-evil`$(echo pwn){}%s{0}", "-", "--home-carol-x--y-"]):
    os.makedirs(os.path.join(root, slug), exist_ok=True)
    one["message"]["id"] = "p%d" % i
    with open(os.path.join(root, slug, "s%d000000-0000-4000-8000-00000000000%d.jsonl" % (i, i)), "w") as f:
        f.write(json.dumps(one) + "\n")
        if i == 0:
            f.write('{"type":"assistant","message":{"id":"zz')  # the ordinary first run: a truncated last line
PY
run --root "$FX2" --days 7 --until 2026-03-10 --json
expect "exit 0" 0 "$rc"
has "the truncated line's warning names the project, not the slug" "proj/s0000000-0000-4000-8000-000000000000.jsonl:2: not JSON, skipped" "$err"
hasnt "so no username reaches stderr either" "alice" "$err"
expect "each slug prints its project name, a bare - being the root, so ~" 'proj|src-app|srv-evil`$(echo pwn){}%s{0}|x-y|~|~' "$(j '"|".join(sorted(r["project"] for r in d["by_project"]))')"
hasnt "no username prints" "alice" "$out"; hasnt "in any slug shape" "bob" "$out"; hasnt "even with doubled dashes" "carol" "$out"
expect "every one-turn session grows 1.0" "1.0 1.0 1.0 1.0 1.0 1.0" "$(j '" ".join(str(r["growth"]) for r in d["by_session"])')"
run --root "$FX2" --days 7 --until 2026-03-10
hasnt "the text report prints no username either" "alice" "$out"; hasnt "nor another" "bob" "$out"
hasnt "and its stderr none" "alice" "$err"
has "a hostile slug prints verbatim" 'srv-evil`$(echo pwn){}%s{0}' "$out"
expect "and a one-turn session shows 1.00x" "1.00x" "$(awk '{print $NF}' <<< "$(line "s0000000")")"

echo "== the #280 cross-check: the same subagent file, the same numbers =="
md=$(python3 "$ROOT/scripts/measure-dispatch-cost.py" "$FX/-srv-work-demo-alpha/$S1.jsonl" 2>/dev/null | awk -F'\t' 'NR == 2 {print $4, $5 + $7 + $8, $6}')
expect "measure-dispatch-cost.py agrees on agent-b: turns, context, output" "2 7770 150" "$md"

echo "== the root is only read =="
before=$(find "$FX" -type f | sort | md5sum)
stamp="$T/stamp"; touch "$stamp"
run "${WIN[@]}"; run "${WIN[@]}" --json
expect "no file under the root is added or removed" "$before" "$(find "$FX" -type f | sort | md5sum)"
expect "no file under the root is written" "" "$(find "$FX" -newer "$stamp" -type f)"

echo "== refusals: exit 2 and nothing on stdout =="
run --root "$T/nope" --days 7
expect "a missing root exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"; has "naming the root" "$T/nope" "$err"
mkdir -p "$T/emptyroot"; run --root "$T/emptyroot" --days 7 --until 2026-03-10
expect "a root with no transcript exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
has "naming the window" "7-day window ending 2026-03-10" "$err"; has "and the root" "$T/emptyroot" "$err"
hasnt "and never a traceback" "Traceback" "$err"
run --root "$FX" --days 1 --until 2026-03-01
expect "a window holding no turn exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
has "naming the window" "1-day window ending 2026-03-01" "$err"
run --root "$FX" --days 0
expect "--days 0 exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"; has "with the exact message" "usage-report.py: error: --days must be a positive integer" "$err"
run --root "$FX" --days x
expect "--days x exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
run --root "$FX" --until 2026-13-01
expect "a bad --until exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
run --root "$FX" --days 1000000 --until 2026-03-10
expect "a window starting before the calendar exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
has "with the usage error" "--days and --until must describe a window inside the calendar" "$err"
run --root "$FX" --until 9999-12-31
expect "a window ending past the calendar exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
run --root "$FX" --top 0
expect "--top 0 exits 2" 2 "$rc"
run --root "$FX" --bogus
expect "an unknown option exits 2" 2 "$rc"; expect "with nothing on stdout" "" "$out"
run --root "$FX" --days 7 --until 2026-03-10 "$FX"
expect "a positional argument exits 2" 2 "$rc"
hasnt "no refusal prints a traceback" "Traceback" "$(cat "$T/mut-err.log")"

echo "== the default root and window =="
mkdir -p "$HOME/.claude/projects/-srv-work-demo-gamma"
now=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')
printf '{"type":"assistant","timestamp":"%s","message":{"id":"g1","model":"claude-opus-5-5","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4}}}\n' "$now" \
  > "$HOME/.claude/projects/-srv-work-demo-gamma/s7000000-0000-4000-8000-000000000007.jsonl"
tomorrow() { python3 -c 'from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%dT00:00:00Z"))'; }
before=$(tomorrow); run --json; after=$(tomorrow)
expect "the default root is ~/.claude/projects and the default window 7 days" "1 6 7" "$(j 'd["summary"]["turns"]') $(j 'd["summary"]["context"]') $(j 'd["summary"]["days"]')"
# Read before and after the run, so a run that straddles UTC midnight matches one of the two.
got=$(j 'd["summary"]["window_end"]')
if [ "$got" = "$before" ] || [ "$got" = "$after" ]; then ok "the default window ends at the end of today, UTC"
else bad "the default window ends at the end of today, UTC (expected '$before' or '$after', got '$got')"; fi

echo "== mutants: each wrong accounting method loses an assertion =="
. "$HERE/mutant-crash.sh"
# ur_live <build>: the build still prints its summary line over the fixtures (#360).
ur_live() { local o; o=$(python3 "$1" "${WIN[@]}" 2>/dev/null) || return 1; [ "${o%% *}" = "usage-report:" ]; }
# mutant <name> <old> <new>: a copy of the script with one edit. The old text must exist, so a
# refactor that removes it fails here rather than letting the mutant rot. A failed core_checks is a
# kill only when the build did not crash (#360): it must compile, leave no traceback on any run's
# stderr, and pass ur_live.
mutant() {
  local name=$1 m="$T/mutant-$1.py"
  if ! python3 - "$SRC" "$m" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:]
s = open(src).read()
if old not in s: sys.exit(1)
open(dst, "w").write(s.replace(old, new, 1))
PY
  then bad "mutant $name: its target text is gone from the script"; return; fi
  local before=$fail saved_pass=$pass why
  : > "$T/mut-err.log"
  SCRIPT="$m"; core_checks >/dev/null; SCRIPT="$SRC"
  why=$(mutant_crash_reason "$m" "$T/mut-err.log" ur_live "$m")
  if [ -n "$why" ]; then fail=$before; pass=$saved_pass; bad "mutant $name crashed ($why)"
  elif [ "$fail" -gt "$before" ]; then fail=$before; pass=$saved_pass; ok "mutant $name dies"
  else fail=$before; pass=$saved_pass; bad "mutant $name survives"; fi
}
mutant sum-all-lines \
  'turns[mid] = {  # the LAST line for an id wins' \
  'turns[mid + "/" + str(n)] = {'
mutant first-line-per-id \
  'if mid in turns and turns[mid]["file"] != rel:' \
  'if mid in turns:'
mutant count-synthetic \
  'if m.get("model") == SYNTHETIC:' \
  'if False:'
mutant parent-first \
  '(0 if "subagents" in rel.split(os.sep) else 1, rel)' \
  '(1 if "subagents" in rel.split(os.sep) else 0, rel)'
mutant count-parent-copy \
  'continue  # the parent'"'"'s copy of a subagent response: counted once, as the subagent'"'"'s' \
  'pass'
mutant zero-for-missing-tier \
  'if cc else None,' \
  'if cc else (0, 0),'
mutant ignore-the-window \
  'if start <= t["time"] < end}' \
  'if True}'
mutant window-per-line \
  '                if t is None:
                    continue' \
  '                if t is None or not (start <= t < end):
                    continue'
mutant open-every-file \
  'if datetime.fromtimestamp(os.path.getmtime(path), timezone.utc) < start:' \
  'if False:'
mutant three-path-components \
  'return "-".join(parts[-2:]) if parts else "~"' \
  'return "-".join(parts[-3:]) if parts else "~"'
mutant growth-over-every-kind \
  'if t["kind"] == "main":' \
  'if True:'
mutant local-day \
  'lambda t: new_row(day=t["time"].strftime("%Y-%m-%d"))' \
  'lambda t: new_row(day=t["time"].astimezone().strftime("%Y-%m-%d"))'

# Crash control (#360): a build that exits before measuring, then one that cannot import. mutant
# runs in $( ), so its rows stay out of the total.
crash_ok=1; crashed=0
for x in 'raise SystemExit(2)' 'import nosuchmodule566'; do
  cap=$(mutant crash-control '#!/usr/bin/env python3
' "#!/usr/bin/env python3
$x
")
  case "$cap" in *" dies"*|*" survives"*) crash_ok=0 ;; *"FAIL: mutant crash-control crashed ("*) crashed=$((crashed + 1)) ;; esac
done
[ "$crash_ok" = 1 ] && [ "$crashed" = 2 ] && ok "crash control (#360): a crashing mutant is reported as crashed, never as dies" \
  || bad "crash control (#360): a crashing mutant was credited or missed ($crashed of 2 crashed)"

echo
echo "usage-report: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
