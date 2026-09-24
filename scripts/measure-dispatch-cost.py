#!/usr/bin/env python3
"""measure-dispatch-cost.py: what each subagent dispatch in a Claude Code session cost (#280).

Usage: measure-dispatch-cost.py <session.jsonl>
       measure-dispatch-cost.py --compare <A.jsonl> <B.jsonl>

A tier decision made on price per token alone is how a model choice goes wrong: the cheaper model
routinely takes several times the turns. This reads the transcripts Claude Code already writes and
prints what a dispatch actually cost, so the decision can be checked, and checked again when the
CLI or a model changes. It REPORTS and never judges: whether a tier was right is the reader's call.

The layout, verified on transcripts written by CLI 2.1.274 to 2.1.281:
  ~/.claude/projects/<slug>/<session>.jsonl            the parent; it gets NO row
  <session>/subagents/agent-<id>.jsonl                 one dispatch, grandchildren included (flat)
  <session>/subagents/agent-<id>.meta.json             agentType, spawnDepth, optional toolUseId

The accounting rule, and each wrong method is a mutant in the contract test:
  - a TURN is one distinct message.id on an assistant record whose model is not <synthetic>;
  - its usage is the LAST line carrying that id. One response is streamed as several lines that
    each repeat the usage, so summing lines doubled a real sample's cache reads (18.9M for 9.8M),
    and the first line undercounts output;
  - <synthetic> records (CLI-generated, e.g. an API error) add no turn and no token, and a file
    holding only those is a real dispatch that did no work: a row of zeros, never an error;
  - the model is read from the dispatch's own message.model values, never meta.model, which is
    only the requested override and is usually absent;
  - every non-assistant record is ignored: user, attachment, and the session-file records with no
    timestamp (ai-title, last-prompt, permission-mode, cost-state, file-history-snapshot, ...).

Streams are the contract. A line that is not JSON is skipped with one stderr warning, because a
transcript still being written ends in a truncated one. Exit 2 with NOTHING on stdout when a file
has zero records, an assistant record or a meta file lacks a required field, or a subagent file
has no meta file: a partial table would read as a complete one.

--compare prints every row of both runs, then one B-minus-A row per agentType over SUMMED columns,
because a session routinely dispatches one type several times and rows cannot be paired one to
one. If the two sets of types differ it says so on stderr and still exits 0.
"""
import glob
import json
import os
import sys
from datetime import datetime

PROG = "measure-dispatch-cost"
USAGE_KEYS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
COLUMNS = ("agentType", "model", "effort", "turns", "input", "output", "cache_read", "cache_creation", "wall_s")
NUMERIC = ("turns", "input", "output", "cache_read", "cache_creation", "wall_s")
DIFFERENT_TYPES = (PROG + ": the two runs dispatch different agent types; "
                   "the difference compares different work")


class Refuse(Exception):
    pass


def read_records(path):
    records = []
    try:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    print(f"{PROG}: {path}:{n}: not JSON, skipped", file=sys.stderr)
                    continue
                if isinstance(r, dict):
                    records.append(r)
    except OSError as e:
        raise Refuse(f"cannot read {path}: {e.strerror}")
    if not records:
        raise Refuse(f"{path} holds no records")
    return records


def require(obj, dotted, path):
    cur = obj
    for key in dotted.split("."):
        if not isinstance(cur, dict) or key not in cur:
            raise Refuse(f"{path}: an assistant record has no {dotted}")
        cur = cur[key]
    return cur


def seconds(ts, path):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        raise Refuse(f"{path}: unreadable timestamp {ts!r}")


def measure_dispatch(path):
    meta_path = path[: -len(".jsonl")] + ".meta.json"
    if not os.path.exists(meta_path):
        raise Refuse(f"{path} has no meta file ({os.path.basename(meta_path)})")
    try:
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        raise Refuse(f"{meta_path} is not readable JSON")
    for key in ("agentType", "spawnDepth"):
        if not isinstance(meta, dict) or key not in meta:
            raise Refuse(f"{meta_path} has no {key}")

    usage_by_id, models, efforts, stamps = {}, [], [], []
    for r in read_records(path):
        if r.get("type") != "assistant":
            continue
        stamps.append(seconds(require(r, "timestamp", path), path))
        mid = require(r, "message.id", path)
        model = require(r, "message.model", path)
        usage = require(r, "message.usage", path)
        for k in USAGE_KEYS:
            require(r, "message.usage." + k, path)
        if model == "<synthetic>":
            continue
        usage_by_id[mid] = usage  # the LAST line for an id wins
        if model not in models:
            models.append(model)
        if r.get("effort") and r["effort"] not in efforts:
            efforts.append(r["effort"])

    row = {
        "agentType": meta["agentType"],
        "model": ",".join(models) or "-",
        "effort": ",".join(efforts) or "-",
        "turns": len(usage_by_id),
        "wall_s": round(max(stamps) - min(stamps), 1) if stamps else 0.0,
        "_first": min(stamps) if stamps else 0.0,
    }
    for col, key in zip(("input", "output", "cache_read", "cache_creation"), USAGE_KEYS):
        row[col] = sum(u[key] or 0 for u in usage_by_id.values())
    return row


def measure_session(session):
    if not session.endswith(".jsonl"):
        raise Refuse(f"{session} is not a .jsonl session file")
    read_records(session)  # the parent gets no row, but an empty or unreadable one is no session
    files = sorted(glob.glob(os.path.join(session[: -len(".jsonl")], "subagents", "agent-*.jsonl")))
    rows = [measure_dispatch(f) for f in files]
    rows.sort(key=lambda r: r["_first"])
    return rows


def cell(v):
    return f"{v:.1f}" if isinstance(v, float) else str(v)


def emit(lines):
    sys.stdout.write("".join("\t".join(cell(v) for v in line) + "\n" for line in lines))


def single(session):
    rows = measure_session(session)
    emit([COLUMNS] + [[r[c] for c in COLUMNS] for r in rows])


def compare(a, b):
    runs = {"A": measure_session(a), "B": measure_session(b)}
    header = ("run", "dispatches") + COLUMNS
    lines = [header]
    for name, rows in runs.items():
        lines += [[name, 1] + [r[c] for c in COLUMNS] for r in rows]

    def summed(rows, t):
        mine = [r for r in rows if r["agentType"] == t]
        out = {c: sum(r[c] for r in mine) for c in NUMERIC}
        out["dispatches"] = len(mine)
        for c in ("model", "effort"):
            vals = []
            for r in mine:
                for v in r[c].split(","):
                    if v != "-" and v not in vals:
                        vals.append(v)
            out[c] = ",".join(vals) or "-"
        return out

    types = []
    for rows in runs.values():
        for r in rows:
            if r["agentType"] not in types:
                types.append(r["agentType"])
    for t in types:
        sa, sb = summed(runs["A"], t), summed(runs["B"], t)
        diff = {c: sb[c] - sa[c] for c in NUMERIC}
        diff["wall_s"] = round(diff["wall_s"], 1)
        line = ["B-A", sb["dispatches"] - sa["dispatches"], t,
                f"A={sa['model']} B={sb['model']}", f"A={sa['effort']} B={sb['effort']}"]
        lines.append(line + [diff[c] for c in NUMERIC])
    emit(lines)
    if {r["agentType"] for r in runs["A"]} != {r["agentType"] for r in runs["B"]}:
        print(DIFFERENT_TYPES, file=sys.stderr)


def main(argv):
    try:
        if len(argv) == 2 and not argv[1].startswith("-"):
            single(argv[1])
        elif len(argv) == 4 and argv[1] == "--compare":
            compare(argv[2], argv[3])
        else:
            print(f"usage: {PROG}.py <session.jsonl> | --compare <A.jsonl> <B.jsonl>", file=sys.stderr)
            return 2
    except Refuse as e:
        print(f"{PROG}: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
