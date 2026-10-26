#!/usr/bin/env python3
# usage-report-version: 3
"""usage-report.py: where Claude Code usage went, read from the transcripts it already writes (#566).

Usage: usage-report.py [--days N] [--until YYYY-MM-DD] [--root DIR] [--top N] [--json]

`ccusage` answers what Claude Code cost. This answers WHY, and the answer is almost never the
output: it is the context re-sent on every turn, driven by sessions that were never cleared and by
subagents inheriting the premium model. It prints, for the last N days, context re-sent per turn
split by cache tier, grouped by project, by model with main and subagent rows apart, by session
with each session's growth, and by day. It REPORTS and never judges, and it never edits anything:
no network, no API key, nothing written under the transcript root, and `message.content` is never
read.

The layout, verified on transcripts written by CLI 2.1.301 to 2.1.310:
  <root>/<project slug>/<session>.jsonl                       the main session
  <root>/<project slug>/<session>/subagents/**/agent-*.jsonl  one subagent each, nesting allowed
A path with a `subagents` component is a subagent transcript, and that is what `kind` means in the
output. The project slug is the directory under the root: the session's working directory with
every slash turned into a dash, which is usually under the user's home path. What prints is the
last two dash-separated components after a leading `home-<user>` or `Users-<user>` pair is dropped
(`~` when nothing remains), so neither the username nor anything above the project is shown. The
slug cannot tell a dash in a name from a slash, so a username containing a dash is not recognised
as one component: that is the stated limit of a report meant to be read, never committed.

The accounting rule; each wrong method is a mutant in the contract test:
  - a TURN is one distinct message.id on an assistant record whose model is not <synthetic>;
  - its usage is the LAST line carrying that id: one response is streamed as several lines that
    each repeat the usage, so summing lines doubled a real sample's cache reads (#280, which this
    rule and the <synthetic> and non-JSON rules are a second copy of; the rest below is new here);
  - <synthetic> records (CLI-generated, e.g. an API error) add no turn and no token, and a file
    holding only those is listed with zeros, never an error;
  - subagent files are read FIRST, and a file never replaces an id another file already holds, so
    a response present in both a subagent file and its parent is the subagent's;
  - every non-assistant record and every record without a usable timestamp is ignored; a missing
    or non-integer usage key counts 0;
  - the window is applied to the turn AFTER the last line is chosen, on that line's timestamp, so
    a response whose lines straddle midnight belongs to one day's report, never to two or none;
  - context per turn is input_tokens + cache_creation_input_tokens + cache_read_input_tokens,
    everything the model was given; the three tiers and the output are shown apart everywhere a
    total is, so a reader never mistakes a total for a bill. The 5-minute and 1-hour cache-write
    split is printed where cache_creation carries it and `-` where it does not, never 0;
  - a session's growth is its last main turn's context over its first main turn's, `-` when it
    has no main turn or that first context is 0.

The window is the N whole UTC days ending with --until (inclusive; default today, UTC). A file
whose mtime is before the window start is not opened; every turn is then selected by its own
timestamp, and days bucket by the UTC date of that timestamp. A line that is not UTF-8, not JSON
or nested past the interpreter's recursion limit is skipped with one stderr warning naming the
file and the line, because a transcript still being written ends in a truncated line; the file is
named by its project name and the rest of its root-relative path, so the slug's `home-<user>`
reaches stderr no more than stdout. Exit 2 with NOTHING on stdout when the root is not a
directory, when no turn falls inside the window (a root holding only <synthetic> records has
nothing to report, and the message names the window), or on a usage error, a window outside the
calendar included. A refusal names the root as it was typed (`~/.claude/projects` by default),
never expanded, so the home path is on stderr only when the user typed it. Standard library only,
Python 3.9+.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

PROG = "usage-report"
SYNTHETIC = "<synthetic>"
BIG_TURN = 200000
SPLIT = ("ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens")
HOME_ROOTS = ("home", "Users")


class Refuse(Exception):
    pass


def warn(msg):
    print(f"{PROG}: {msg}", file=sys.stderr)


def parse_args(argv):
    p = argparse.ArgumentParser(prog=PROG + ".py",
                                description="where Claude Code usage went, from the local transcripts")
    p.add_argument("--days", type=int, default=7, help="window length in whole UTC days (default 7)")
    p.add_argument("--until", default=None,
                   help="last day of the window as YYYY-MM-DD, inclusive, UTC (default today)")
    p.add_argument("--root", default=None, help="transcript root (default ~/.claude/projects)")
    p.add_argument("--top", type=int, default=15, help="sessions to list (default 15)")
    p.add_argument("--json", action="store_true", help="one JSON object instead of the tables")
    a = p.parse_args(argv)
    if a.days < 1:
        p.error("--days must be a positive integer")
    if a.top < 1:
        p.error("--top must be a positive integer")
    if a.until is None:
        until = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    else:
        try:
            until = datetime.strptime(a.until, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            p.error("--until must be YYYY-MM-DD")
    a.until = until.strftime("%Y-%m-%d")
    try:
        a.end = until + timedelta(days=1)
        a.start = a.end - timedelta(days=a.days)
    except OverflowError:
        p.error("--days and --until must describe a window inside the calendar")
    a.shown_root = a.root or os.path.join("~", ".claude", "projects")  # as typed, for messages
    a.root = os.path.expanduser(a.shown_root)
    return a


def stamp(ts):
    try:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
        return t.astimezone(timezone.utc)  # OverflowError at the calendar's edge, e.g. year 1 at +01:00
    except (AttributeError, TypeError, ValueError, OverflowError):
        return None


def count(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else 0


def transcripts(root):
    """Every *.jsonl under root, subagent files first so a shared id is attributed to the subagent."""
    found = []
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for f in sorted(files):
            if f.endswith(".jsonl"):
                rel = os.path.relpath(os.path.join(d, f), root)
                found.append((0 if "subagents" in rel.split(os.sep) else 1, rel))
    found.sort()
    return [rel for _, rel in found]


def locate(rel):
    """(project slug, session id, kind) from a root-relative transcript path, or None above a slug."""
    parts = rel.split(os.sep)
    if len(parts) < 2:
        return None
    session = parts[1][:-len(".jsonl")] if len(parts) == 2 else parts[1]
    kind = "subagent" if "subagents" in parts[1:] else "main"
    return parts[0], session, kind


def read_turns(root, start, end):
    """turns: message.id -> turn inside the window; opened: [(slug, session, kind)] per transcript opened."""
    turns, opened = {}, []
    for rel in transcripts(root):
        where = locate(rel)
        if where is None:
            continue
        path = os.path.join(root, rel)
        shown = os.path.join(project_name(where[0]), *rel.split(os.sep)[1:])  # never the slug
        try:
            if datetime.fromtimestamp(os.path.getmtime(path), timezone.utc) < start:
                continue
            fh = open(path, "rb")
        except OSError as e:
            warn(f"{shown}: cannot read ({e.strerror}), skipped")
            continue
        opened.append(where)
        with fh:
            for n, raw in enumerate(fh, 1):
                if not raw.strip():
                    continue
                try:
                    r = json.loads(raw.decode("utf-8"))
                except UnicodeDecodeError:
                    warn(f"{shown}:{n}: not UTF-8, skipped")
                    continue
                except (ValueError, RecursionError):
                    warn(f"{shown}:{n}: not JSON, skipped")
                    continue
                if not isinstance(r, dict) or r.get("type") != "assistant":
                    continue
                m = r.get("message")
                if not isinstance(m, dict) or not isinstance(m.get("id"), str):
                    continue
                if m.get("model") == SYNTHETIC:
                    continue
                t = stamp(r.get("timestamp"))
                if t is None:
                    continue
                mid = m["id"]
                if mid in turns and turns[mid]["file"] != rel:
                    continue  # the parent's copy of a subagent response: counted once, as the subagent's
                u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
                cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else None
                turns[mid] = {  # the LAST line for an id wins
                    "file": rel, "slug": where[0], "session": where[1], "kind": where[2],
                    "model": str(m.get("model")), "time": t, "sidechain": r.get("isSidechain") is True,
                    "uncached": count(u.get("input_tokens")),
                    "cache_write": count(u.get("cache_creation_input_tokens")),
                    "cache_read": count(u.get("cache_read_input_tokens")),
                    "output": count(u.get("output_tokens")),
                    "split": tuple(count(cc.get(k)) for k in SPLIT) if cc else None,
                }
    # The window is applied to the chosen line, not to every line: a response whose first line
    # is inside and whose last line is past midnight belongs to the next day's report.
    return {k: t for k, t in turns.items() if start <= t["time"] < end}, opened


def context(t):
    return t["uncached"] + t["cache_write"] + t["cache_read"]


def project_name(slug):
    """The last two dash-separated components after a home-<user> or Users-<user> prefix is dropped."""
    parts = [p for p in slug.split("-") if p]
    if len(parts) >= 2 and parts[0] in HOME_ROOTS:
        parts = parts[2:]
    return "-".join(parts[-2:]) if parts else "~"


def short_model(model):
    """`claude-` and a trailing date suffix dropped, for column width only; --json keeps the raw name."""
    m = model[len("claude-"):] if model.startswith("claude-") else model
    tail = m.rsplit("-", 1)
    if len(tail) == 2 and len(tail[1]) == 8 and tail[1].isdigit():
        m = tail[0]
    return m


def new_row(**key):
    row = dict(key)
    row.update(turns=0, context=0, uncached=0, cache_write=0, cache_read=0, output=0,
               sidechain_turns=0, big_turns=0, split=None)
    return row


def add(row, t):
    row["turns"] += 1
    row["context"] += context(t)
    for k in ("uncached", "cache_write", "cache_read", "output"):
        row[k] += t[k]
    row["sidechain_turns"] += t["sidechain"]
    row["big_turns"] += context(t) >= BIG_TURN
    if t["split"] is not None:
        a, b = row["split"] or (0, 0)
        row["split"] = (a + t["split"][0], b + t["split"][1])


def finish(rows, total_context):
    out = []
    for row in rows:
        row["context_per_turn"] = round(row["context"] / row["turns"]) if row["turns"] else 0
        row["share"] = round(100.0 * row["context"] / total_context, 1) if total_context else 0.0
        row["cache_write_5m"] = row["split"][0] if row["split"] else None
        row["cache_write_1h"] = row["split"][1] if row["split"] else None
        del row["split"]
        out.append(row)
    out.sort(key=lambda r: (-r["context"], -r["turns"], r.get("sort_key", "")))
    for r in out:
        r.pop("sort_key", None)
    return out


def group(turns, key, make):
    rows = {}
    for t in turns:
        k = key(t)
        if k not in rows:
            rows[k] = make(t)
            rows[k]["sort_key"] = "|".join(str(x) for x in (k if isinstance(k, tuple) else (k,)))
        add(rows[k], t)
    return list(rows.values())


def report(turns, opened, args):
    ts = list(turns.values())
    if not ts:
        raise Refuse(f"no turn in the {args.days}-day window ending {args.until} under {args.shown_root}")
    total_context = sum(context(t) for t in ts)
    total_output = sum(t["output"] for t in ts)
    big = [t for t in ts if context(t) >= BIG_TURN]
    everything = total_context + total_output
    summary = {
        "window_start": args.start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_end": args.end.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "until": args.until,
        "days": args.days,
        "transcripts": len(opened),
        "turns": len(ts),
        "context": total_context,
        "uncached": sum(t["uncached"] for t in ts),
        "cache_write": sum(t["cache_write"] for t in ts),
        "cache_read": sum(t["cache_read"] for t in ts),
        "output": total_output,
        "context_per_turn": round(total_context / len(ts)),
        "output_share": round(100.0 * total_output / everything, 2) if everything else 0.0,
        "big_turn_threshold": BIG_TURN,
        "big_turns": len(big),
        "big_turn_share": round(100.0 * len(big) / len(ts), 1),
        "big_context_share": round(100.0 * sum(context(t) for t in big) / total_context, 1) if total_context else 0.0,
    }
    by_project = finish(group(ts, lambda t: t["slug"],
                              lambda t: new_row(project=project_name(t["slug"]))), total_context)
    by_model = finish(group(ts, lambda t: (t["model"], t["kind"]),
                            lambda t: new_row(model=t["model"], kind=t["kind"])), total_context)
    # Every transcript opened seeds its session, so one holding only <synthetic> records is a row
    # of zeros rather than absent; growth is measured on main turns only, in time order.
    sessions = {}
    for slug, session, _ in opened:
        k = (slug, session)
        if k not in sessions:
            sessions[k] = new_row(session=session, project=project_name(slug), first_context=None, last_context=None)
            sessions[k]["sort_key"] = session
    for t in sorted(ts, key=lambda t: t["time"]):
        s = sessions[(t["slug"], t["session"])]
        add(s, t)
        if t["kind"] == "main":
            if s["first_context"] is None:
                s["first_context"] = context(t)
            s["last_context"] = context(t)
    by_session = finish(list(sessions.values()), total_context)
    for r in by_session:
        r["growth"] = round(r["last_context"] / r["first_context"], 2) if r["first_context"] else None
    by_day = finish(group(ts, lambda t: t["time"].strftime("%Y-%m-%d"),
                          lambda t: new_row(day=t["time"].strftime("%Y-%m-%d"))), total_context)
    by_day.sort(key=lambda r: r["day"])
    return {"summary": summary, "by_project": by_project, "by_model": by_model,
            "by_session": by_session[:args.top], "by_day": by_day}


def n(v):
    return "-" if v is None else f"{v:,}"


def table(title, head, rows):
    widths = [len(h) for h in head]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))

    def fmt(cells):
        return "  ".join(c.ljust(w) if i == 0 else c.rjust(w) for i, (c, w) in enumerate(zip(cells, widths)))
    return "\n".join([title, fmt(head)] + [fmt(r) for r in rows]) + "\n"


TIER_HEAD = ["turns", "context", "ctx/turn", "uncached", "cache write", "cache read", "output", "share"]


def tiers(r):
    return [n(r["turns"]), n(r["context"]), n(r["context_per_turn"]), n(r["uncached"]),
            n(r["cache_write"]), n(r["cache_read"]), n(r["output"]), f"{r['share']:.1f}%"]


def render(rep):
    s = rep["summary"]
    out = [
        f"usage-report: {s['days']} days ending {s['until']} (UTC), {s['transcripts']} transcripts, "
        f"{n(s['turns'])} API responses\n",
        f"context re-sent {n(s['context'])} ({n(s['uncached'])} uncached, {n(s['cache_write'])} cache write, "
        f"{n(s['cache_read'])} cache read), {n(s['context_per_turn'])} per turn; "
        f"output {n(s['output'])} ({s['output_share']:.2f}% of everything)\n",
        f"turns at or above {n(s['big_turn_threshold'])} context: {s['big_turn_share']:.1f}% of turns, "
        f"{s['big_context_share']:.1f}% of context\n\n",
        table("by project", ["project"] + TIER_HEAD, [[r["project"]] + tiers(r) for r in rep["by_project"]]), "\n",
        table("by model", ["model", "kind"] + TIER_HEAD + ["write 5m", "write 1h"],
              [[short_model(r["model"]), r["kind"]] + tiers(r) + [n(r["cache_write_5m"]), n(r["cache_write_1h"])]
               for r in rep["by_model"]]), "\n",
        table(f"by session (top {len(rep['by_session'])})",
              ["session", "project"] + TIER_HEAD + ["first", "last", "growth"],
              [[r["session"][:8], r["project"]] + tiers(r)
               + [n(r["first_context"]), n(r["last_context"]), "-" if r["growth"] is None else f"{r['growth']:.2f}x"]
               for r in rep["by_session"]]), "\n",
        table("by day", ["day"] + TIER_HEAD, [[r["day"]] + tiers(r) for r in rep["by_day"]]),
    ]
    return "".join(out)


def main(argv):
    try:
        args = parse_args(argv)
        if not os.path.isdir(args.root):
            raise Refuse(f"{args.shown_root} is not a directory")
        turns, opened = read_turns(args.root, args.start, args.end)
        rep = report(turns, opened, args)
    except Refuse as e:
        warn(str(e))
        return 2
    if args.json:
        json.dump(rep, sys.stdout, indent=1, sort_keys=True)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
