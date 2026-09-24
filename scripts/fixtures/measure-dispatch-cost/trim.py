#!/usr/bin/env python3
"""Trim a real Claude Code session into a fixture for measure-dispatch-cost.py (#280).

Usage: trim.py <session.jsonl> <out-dir> <name>

Writes <out-dir>/<name>.jsonl and <out-dir>/<name>/subagents/agent-<id>.{jsonl,meta.json}.
Keeps a named ALLOWLIST (the #280 ticket's, verbatim) and nothing else, because a transcript carries home paths, branch names,
session and request ids and conversation text, and a fixture that kept any of them would publish
it. A message's content survives only as the Agent tool_use blocks it held, rebuilt to their type,
id and subagent_type, so no conversation text can survive. A line that is not JSON is dropped.
"""
import glob
import json
import os
import sys

RECORD_KEYS = ("type", "timestamp", "version", "agentId", "isApiErrorMessage", "effort")
MESSAGE_KEYS = ("id", "model", "stop_reason", "usage")
RESULT_KEYS = ("agentId", "resolvedModel")
META_KEYS = ("agentType", "toolUseId", "spawnDepth", "parentAgentId", "model")


def trim_record(r):
    out = {k: r[k] for k in RECORD_KEYS if k in r}
    t = r.get("toolUseResult")
    if isinstance(t, dict) and any(k in t for k in RESULT_KEYS):
        out["toolUseResult"] = {k: t[k] for k in RESULT_KEYS if k in t}
    m = r.get("message")
    if r.get("type") == "assistant" and isinstance(m, dict):
        tm = {k: m[k] for k in MESSAGE_KEYS if k in m}
        blocks = [
            {"type": "tool_use", "id": b.get("id"),
             "input": {"subagent_type": (b.get("input") or {}).get("subagent_type")}}
            for b in (m.get("content") if isinstance(m.get("content"), list) else [])
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task")
        ]
        if blocks:
            tm["content"] = blocks
        out["message"] = tm
    return out


def trim_jsonl(src, dst):
    with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as o:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if isinstance(r, dict):
                o.write(json.dumps(trim_record(r), separators=(",", ":")) + "\n")


def main(argv):
    if len(argv) != 4:
        print("usage: trim.py <session.jsonl> <out-dir> <name>", file=sys.stderr)
        return 2
    src, out, name = argv[1], argv[2], argv[3]
    os.makedirs(os.path.join(out, name, "subagents"), exist_ok=True)
    trim_jsonl(src, os.path.join(out, name + ".jsonl"))
    for f in sorted(glob.glob(os.path.join(src[: -len(".jsonl")], "subagents", "agent-*.jsonl"))):
        base = os.path.basename(f)[: -len(".jsonl")]
        trim_jsonl(f, os.path.join(out, name, "subagents", base + ".jsonl"))
        meta = f[: -len(".jsonl")] + ".meta.json"
        if os.path.exists(meta):
            with open(meta, encoding="utf-8") as m:
                d = json.load(m)
            with open(os.path.join(out, name, "subagents", base + ".meta.json"), "w", encoding="utf-8") as o:
                json.dump({k: d[k] for k in META_KEYS if k in d}, o, separators=(",", ":"))
                o.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
