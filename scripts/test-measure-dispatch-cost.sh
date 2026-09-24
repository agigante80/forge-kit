#!/usr/bin/env bash
# Contract test for scripts/measure-dispatch-cost.py (#280).
#
# The script prices a dispatch from Claude Code's own transcripts, and the obvious counting method
# was wrong by a factor of two, so the accounting rule is the contract and every wrong method is a
# MUTANT below that must lose at least one assertion. The fixtures are trimmed REAL transcripts
# (scripts/fixtures/measure-dispatch-cost/README.md); every scenario that needs another shape
# mutates a throwaway copy of one, never a hand-written record. STREAMS ARE THE CONTRACT: a table
# on stdout and exit 0, or nothing on stdout and exit 2.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/measure-dispatch-cost.py"
FX="$HERE/fixtures/measure-dispatch-cost"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }
[ -d "$FX" ] || { echo "missing fixtures: $FX"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SCRIPT="$SRC"
out=""; err=""; rc=0
run() { out=$(python3 "$SCRIPT" "$@" 2>"$T/err"); rc=$?; err=$(cat "$T/err"); }
# col <agentType> <column>: one cell of the single-run table in $out.
col() {
  printf '%s\n' "$out" | awk -F'\t' -v t="$1" -v c="$2" '
    NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
    $1 == t { print $h[c]; exit }'
}
# dcol <run> <agentType> <column>: one cell of a --compare table in $out.
dcol() {
  printf '%s\n' "$out" | awk -F'\t' -v r="$1" -v t="$2" -v c="$3" '
    NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
    $1 == r && $3 == t { print $h[c]; exit }'
}
rows() { printf '%s\n' "$out" | awk 'NR > 1 && NF' | wc -l | tr -d ' '; }

# copy <fixture> <name>: a throwaway copy of a fixture session, returning its .jsonl path.
copy() { cp -R "$FX/$1" "$T/$2"; cp "$FX/$1.jsonl" "$T/$2.jsonl"; echo "$T/$2.jsonl"; }
# edit <file> <python>: rewrite a jsonl file record by record; `recs` is the list, write it back.
edit() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, code = sys.argv[1], sys.argv[2]
recs = [json.loads(l) for l in open(path) if l.strip()]
exec(code)
open(path, "w").write("".join(json.dumps(r) + "\n" for r in recs))
PY
}
GATE_OPUS=agent-a91a6a0752aa760bf
GATE_CRITIC=agent-ad867be1a23663fc4
HC_SONNET=$(basename "$(ls "$FX"/hc-sonnet/subagents/*.jsonl)" .jsonl)
HC_HAIKU=$(basename "$(ls "$FX"/hc-haiku/subagents/*.jsonl)" .jsonl)

# The assertions every mutant is run against. Each echoes FAIL lines through bad(), so a mutant is
# killed when the fail count grows while it runs.
core_checks() {
  run "$FX/gate.jsonl"
  expect "the gate session has exactly two dispatch rows, the parent none" 2 "$(rows)"
  expect "the ticket-gate row reads its model from message.model" claude-opus-5-5 "$(col forge-kit-governance:ticket-gate model)"
  expect "the depth-2 grandchild has its own row and model" claude-sonnet-5 "$(col general-purpose model)"
  expect "the ticket-gate made 15 turns (distinct message.id)" 15 "$(col forge-kit-governance:ticket-gate turns)"
  expect "the ticket-gate's output is the last line per id" 16499 "$(col forge-kit-governance:ticket-gate output)"
  expect "the ticket-gate's cache reads are the last line per id" 1136604 "$(col forge-kit-governance:ticket-gate cache_read)"
  expect "the critic's synthetic record adds no turn" 4 "$(col general-purpose turns)"
  expect "the critic's output" 12898 "$(col general-purpose output)"
}

echo "== a dispatch's cost is reported =="
core_checks
expect "exit 0" 0 "$rc"
expect "stderr is empty" "" "$err"
expect "the header names every column" \
  "$(printf 'agentType\tmodel\teffort\tturns\tinput\toutput\tcache_read\tcache_creation\twall_s')" \
  "$(printf '%s\n' "$out" | head -1)"
expect "effort comes from the per-record field" high "$(col general-purpose effort)"
expect "wall time is first to last assistant timestamp" 325.7 "$(col forge-kit-governance:ticket-gate wall_s)"
expect "rows are ordered by first timestamp" forge-kit-governance:ticket-gate \
  "$(printf '%s\n' "$out" | awk -F'\t' 'NR == 2 { print $1 }')"
run "$FX/hc-sonnet.jsonl"
expect "the sonnet health-check: 4 turns (the #250 hand count)" 4 "$(col forge-kit-devops:health-check turns)"
expect "the sonnet health-check: 2401 output" 2401 "$(col forge-kit-devops:health-check output)"
run "$FX/hc-haiku.jsonl"
expect "the haiku health-check: 14 turns (the #250 hand count)" 14 "$(col forge-kit-devops:health-check turns)"
expect "a dispatch with no effort field prints -" - "$(col forge-kit-devops:health-check effort)"

S=$(copy gate usage); edit "$T/usage/subagents/$GATE_CRITIC.jsonl" '
a = [r for r in recs if r.get("type") == "assistant"][0]; del a["message"]["usage"]'
run "$S"
expect "a record with no message.usage exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "message.usage" "$err" "stderr names message.usage"
contains "$GATE_CRITIC.jsonl" "$err" "stderr names the file"
S=$(copy gate usage-key); edit "$T/usage-key/subagents/$GATE_CRITIC.jsonl" '
a = [r for r in recs if r.get("type") == "assistant"][0]; del a["message"]["usage"]["cache_read_input_tokens"]'
run "$S"
expect "a usage with no cache_read_input_tokens exits 2" 2 "$rc"
contains "message.usage.cache_read_input_tokens" "$err" "and names the key"
for f in message.id message.model; do
  S=$(copy gate "no-$f"); edit "$T/no-$f/subagents/$GATE_OPUS.jsonl" "
a = [r for r in recs if r.get('type') == 'assistant'][0]; del a['message']['${f#message.}']"
  run "$S"
  expect "a record with no $f exits 2" 2 "$rc"
  contains "$f" "$err" "and names $f"
done

echo "== duplicated message.id lines are counted once =="
S=$(copy hc-sonnet dup); edit "$T/dup/subagents/$HC_SONNET.jsonl" '
a = [r for r in recs if r.get("type") == "assistant"]
for r in a: r["message"]["usage"]["output_tokens"] = 0
first = a[0]; mid = first["message"]["id"]; i = recs.index(first)
recs[:] = [r for r in recs if (r.get("message") or {}).get("id") != mid]
for n, v in enumerate((7, 140, 526)):
    c = json.loads(json.dumps(first)); c["message"]["usage"]["output_tokens"] = v
    recs.insert(i + n, c)'
run "$S"
expect "one id on three lines (7, 140, 526) is one turn" 4 "$(col forge-kit-devops:health-check turns)"
expect "and its output is the last line's 526" 526 "$(col forge-kit-devops:health-check output)"

S=$(copy gate nosyn); edit "$T/nosyn/subagents/$GATE_CRITIC.jsonl" '
recs[:] = [r for r in recs if (r.get("message") or {}).get("model") != "<synthetic>"]'
run "$S"; without=$(printf '%s\n' "$out" | grep general-purpose)
run "$FX/gate.jsonl"; with=$(printf '%s\n' "$out" | grep general-purpose)
expect "a <synthetic> record changes no column" "$without" "$with"
expect "and exits 0" 0 "$rc"
S=$(copy hc-sonnet synonly); edit "$T/synonly/subagents/$HC_SONNET.jsonl" '
recs[:] = [json.loads(l) for l in open("'"$FX/gate/subagents/$GATE_CRITIC.jsonl"'") if "<synthetic>" in l]'
run "$S"
expect "a synthetic-only dispatch is a row, not an error" 0 "$rc"
expect "with 0 turns" 0 "$(col forge-kit-devops:health-check turns)"
expect "0 output" 0 "$(col forge-kit-devops:health-check output)"
expect "0 cache reads" 0 "$(col forge-kit-devops:health-check cache_read)"
expect "and no model" - "$(col forge-kit-devops:health-check model)"

echo "== the model is the dispatch's own, every one of them =="
S=$(copy hc-haiku metamodel); python3 - "$T/metamodel/subagents/$HC_HAIKU.meta.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["model"] = "opus"; json.dump(m, open(p, "w"))
PY
run "$S"
expect "meta.model is only the request, never the column" claude-haiku-4-5-20251001 "$(col forge-kit-devops:health-check model)"
S=$(copy hc-sonnet twomodel); edit "$T/twomodel/subagents/$HC_SONNET.jsonl" '
a = [r for r in recs if r.get("type") == "assistant"]
last = a[-1]["message"]["id"]
for r in a:
    if r["message"]["id"] == last: r["message"]["model"] = "claude-opus-5-5"'
run "$S"
expect "a dispatch that used two models lists both" claude-sonnet-5,claude-opus-5-5 "$(col forge-kit-devops:health-check model)"

echo "== non-assistant records without a timestamp are ignored =="
S=$(copy gate noise); edit "$T/noise.jsonl" '
recs[:0] = [{"type": t} for t in ("ai-title", "last-prompt", "permission-mode", "file-history-snapshot")]'
edit "$T/noise/subagents/$GATE_OPUS.jsonl" 'recs.insert(1, {"type": "attachment"}); recs.insert(1, {"type": "user"})'
run "$S"; noisy=$out
run "$FX/gate.jsonl"
expect "the same rows as without them" "$out" "$noisy"
expect "stderr is empty" "" "$err"
S=$(copy gate nots); edit "$T/nots/subagents/$GATE_CRITIC.jsonl" '
a = [r for r in recs if r.get("type") == "assistant"][0]; del a["timestamp"]'
run "$S"
expect "an assistant record with no timestamp exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "timestamp" "$err" "stderr names timestamp"
contains "$GATE_CRITIC.jsonl" "$err" "and the file"

echo "== meta files and unreadable input =="
S=$(copy gate nometa); rm "$T/nometa/subagents/$GATE_CRITIC.meta.json"
run "$S"
expect "a subagent file with no meta file exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
contains "$GATE_CRITIC.jsonl" "$err" "and names it"
for k in agentType spawnDepth; do
  S=$(copy gate "meta-$k"); python3 - "$T/meta-$k/subagents/$GATE_CRITIC.meta.json" "$k" <<'PY'
import json, sys
p, k = sys.argv[1:]; m = json.load(open(p)); del m[k]; json.dump(m, open(p, "w"))
PY
  run "$S"
  expect "a meta file with no $k exits 2" 2 "$rc"
  contains "$k" "$err" "and names $k"
done
S=$(copy gate meta-tu); python3 - "$T/meta-tu/subagents/$GATE_CRITIC.meta.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["toolUseId"]; json.dump(m, open(p, "w"))
PY
run "$S"
expect "toolUseId is optional" 0 "$rc"
S=$(copy gate trunc); printf '{"type":"assistant","message":{"id":"x' >> "$T/trunc/subagents/$GATE_OPUS.jsonl"
run "$S"
expect "a truncated last line is skipped, exit 0" 0 "$rc"
contains "$GATE_OPUS.jsonl:" "$err" "with a warning naming the file and line"
expect "and the row is unchanged" 15 "$(col forge-kit-governance:ticket-gate turns)"
S=$(copy gate empty); : > "$T/empty/subagents/$GATE_CRITIC.jsonl"
run "$S"
expect "a subagent file with zero records exits 2" 2 "$rc"
expect "and prints nothing on stdout" "" "$out"
S=$(copy gate emptysession); : > "$S"
run "$S"
expect "a session file with zero records exits 2" 2 "$rc"
run
expect "no argument is a usage error" 2 "$rc"
run --compare "$FX/gate.jsonl"
expect "--compare with one run is a usage error" 2 "$rc"

echo "== two tiers are compared =="
run --compare "$FX/hc-sonnet.jsonl" "$FX/hc-haiku.jsonl"
expect "exit 0" 0 "$rc"
expect "stderr is empty when the types match" "" "$err"
expect "run A's row" 4 "$(dcol A forge-kit-devops:health-check turns)"
expect "run B's row" 14 "$(dcol B forge-kit-devops:health-check turns)"
expect "the turn difference is B minus A" 10 "$(dcol B-A forge-kit-devops:health-check turns)"
expect "the output difference" 2505 "$(dcol B-A forge-kit-devops:health-check output)"
expect "the cache-read difference" 487448 "$(dcol B-A forge-kit-devops:health-check cache_read)"
expect "the dispatches difference" 0 "$(dcol B-A forge-kit-devops:health-check dispatches)"
expect "the model cell names both runs" "A=claude-sonnet-5 B=claude-haiku-4-5-20251001" \
  "$(dcol B-A forge-kit-devops:health-check model)"
run --compare "$FX/hc-sonnet.jsonl" "$FX/gate.jsonl"
expect "different type sets still exit 0" 0 "$rc"
expect "stderr carries exactly the fixed line" \
  "measure-dispatch-cost: the two runs dispatch different agent types; the difference compares different work" "$err"
expect "a type only in A is differenced against zero" -4 "$(dcol B-A forge-kit-devops:health-check turns)"
expect "a type only in B is differenced against zero" 15 "$(dcol B-A forge-kit-governance:ticket-gate turns)"

# many <name> <src-fixture> <src-agent> <type:count>...: a session dispatching each type count
# times, every dispatch a copy of one real subagent transcript with its meta retyped.
many() {
  local name=$1 src=$2 agent=$3; shift 3
  mkdir -p "$T/$name/subagents"; cp "$FX/$src.jsonl" "$T/$name.jsonl"
  local n=0 spec t c i
  for spec in "$@"; do
    t=${spec%:*}; c=${spec#*:}
    for ((i = 0; i < c; i++)); do
      n=$((n + 1))
      cp "$FX/$src/subagents/$agent.jsonl" "$T/$name/subagents/agent-$n.jsonl"
      python3 - "$FX/$src/subagents/$agent.meta.json" "$T/$name/subagents/agent-$n.meta.json" "$t" <<'PY'
import json, sys
src, dst, t = sys.argv[1:]; m = json.load(open(src)); m["agentType"] = t; json.dump(m, open(dst, "w"))
PY
    done
  done
}
echo "== compare pairs repeated agent types =="
many ra hc-sonnet "$HC_SONNET" general-purpose:2 Explore:1
many rb hc-haiku "$HC_HAIKU" general-purpose:2 Explore:1
run --compare "$T/ra.jsonl" "$T/rb.jsonl"
expect "every row of both runs plus exactly two difference rows" 8 "$(rows)"
expect "general-purpose differs by summed turns" 20 "$(dcol B-A general-purpose turns)"
expect "with dispatches 0" 0 "$(dcol B-A general-purpose dispatches)"
expect "Explore differs by its own turns" 10 "$(dcol B-A Explore turns)"
expect "stderr is empty" "" "$err"
many ca hc-sonnet "$HC_SONNET" general-purpose:1
many cb hc-sonnet "$HC_SONNET" general-purpose:3
run --compare "$T/ca.jsonl" "$T/cb.jsonl"
expect "one difference row for a count mismatch" 5 "$(rows)"
expect "with dispatches 2" 2 "$(dcol B-A general-purpose dispatches)"
expect "and summed turns 12 - 4" 8 "$(dcol B-A general-purpose turns)"
expect "a count mismatch within a type is not signalled on stderr" "" "$err"
expect "exit 0" 0 "$rc"

echo "== the fixtures hold the allowlist and the four shapes =="
leaked=$(python3 - "$FX" <<'PY'
import glob, json, os, sys
fx = sys.argv[1]
RECORD = {"type", "timestamp", "version", "agentId", "isApiErrorMessage", "effort", "message", "toolUseResult"}
MESSAGE = {"id", "model", "stop_reason", "usage", "content"}
META = {"agentType", "toolUseId", "spawnDepth", "parentAgentId", "model"}
bad = []
for f in glob.glob(os.path.join(fx, "**", "*.json*"), recursive=True):
    if f.endswith(".meta.json"):
        extra = set(json.load(open(f))) - META
        bad += [f"{f}: meta.{k}" for k in extra]
        continue
    for n, line in enumerate(open(f), 1):
        r = json.loads(line)
        bad += [f"{f}:{n}: {k}" for k in set(r) - RECORD]
        m = r.get("message", {})
        bad += [f"{f}:{n}: message.{k}" for k in set(m) - MESSAGE]
        for b in m.get("content", []):
            if set(b) != {"type", "id", "input"} or set(b["input"]) != {"subagent_type"}:
                bad.append(f"{f}:{n}: message.content beyond an Agent block")
        if set(r.get("toolUseResult", {})) - {"agentId", "resolvedModel"}:
            bad.append(f"{f}:{n}: toolUseResult beyond the allowlist")
print("\n".join(bad))
PY
)
expect "no fixture holds a key outside the allowlist" "" "$leaked"
shapes=$(python3 - "$FX" <<'PY'
import collections, glob, json, os, sys
fx = sys.argv[1]
dup = syn = depth2 = 0; models = set()
for f in glob.glob(os.path.join(fx, "*", "subagents", "*.jsonl")):
    ids = collections.Counter()
    for line in open(f):
        m = json.loads(line).get("message", {})
        if "id" in m: ids[m["id"]] += 1
        if m.get("model") == "<synthetic>": syn += 1
        elif m.get("model"): models.add(m["model"])
    dup += any(c > 1 for c in ids.values())
    depth2 += json.load(open(f[:-6] + ".meta.json"))["spawnDepth"] == 2
print(bool(dup), syn >= 1, bool(depth2), len(models) >= 2)
PY
)
expect "duplicated ids, a synthetic, a depth-2 grandchild, two models" "True True True True" "$shapes"
contains "2.1.281" "$(cat "$FX/README.md" 2>/dev/null)" "the README records the CLI version"

S="$T/sentinel"; mkdir -p "$S/subagents"
cat > "$S.jsonl" <<'J'
{"type":"user","cwd":"SENTINEL-cwd","message":{"content":"SENTINEL-prompt"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","sessionId":"SENTINEL-sid","gitBranch":"SENTINEL-br","message":{"id":"m1","model":"x","usage":{},"content":[{"type":"text","text":"SENTINEL-text"},{"type":"tool_use","name":"Agent","id":"tu1","input":{"subagent_type":"general-purpose","prompt":"SENTINEL-brief","description":"SENTINEL-d"}}]}}
{"type":"user","toolUseResult":{"agentId":"a1","resolvedModel":"x","content":"SENTINEL-result"}}
J
printf '{"type":"assistant","requestId":"SENTINEL-req","message":{"id":"m2","model":"x","usage":{}}}\n' > "$S/subagents/agent-a1.jsonl"
printf '{"agentType":"general-purpose","spawnDepth":1,"description":"SENTINEL-desc"}\n' > "$S/subagents/agent-a1.meta.json"
python3 "$FX/trim.py" "$S.jsonl" "$T/trimmed" s >/dev/null 2>&1
expect "trim.py drops every sentinel field" "" "$(grep -r SENTINEL "$T/trimmed")"
contains '"subagent_type": "general-purpose"' "$(sed 's/":"/": "/g' "$T/trimmed/s.jsonl")" "and keeps the Agent block's subagent_type"
contains '"resolvedModel"' "$(cat "$T/trimmed/s.jsonl")" "and toolUseResult.resolvedModel"

echo "== mutants: each wrong accounting method loses an assertion =="
# mutant <name> <python-literal old> <python-literal new>: a copy of the script with one edit. The
# old text must exist, so a refactor that removes it fails here rather than letting the mutant rot.
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
  local before=$fail saved_pass=$pass
  SCRIPT="$m"; core_checks >/dev/null; SCRIPT="$SRC"
  if [ "$fail" -gt "$before" ]; then fail=$before; pass=$saved_pass; ok "mutant $name dies"
  else fail=$before; pass=$saved_pass; bad "mutant $name survives"; fi
}
mutant sum-per-line \
  'usage_by_id[mid] = usage  # the LAST line for an id wins' \
  'usage_by_id[len(usage_by_id)] = usage'
mutant first-line-per-id \
  'usage_by_id[mid] = usage  # the LAST line for an id wins' \
  'usage_by_id.setdefault(mid, usage)'
mutant count-synthetic \
  'if model == "<synthetic>":' \
  'if False:'
mutant model-from-meta \
  '"model": ",".join(models) or "-",' \
  '"model": meta.get("model") or "-",'
mutant skip-subagents-walk \
  'rows = [measure_dispatch(f) for f in files]' \
  'rows = [measure_dispatch(f) for f in files if 0]'

echo ""
echo "measure-dispatch-cost tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
