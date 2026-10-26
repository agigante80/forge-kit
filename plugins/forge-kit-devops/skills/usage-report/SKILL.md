---
name: usage-report
description: Report where Claude Code usage went over the last N days, read from the transcripts it already writes under ~/.claude/projects, as context re-sent per turn split by cache tier and grouped by project, by model with main and subagent rows apart, by session with its growth, and by day. Use when the user asks "where did my Claude usage go", "why is my usage so high", "which project or model is eating my quota", "which sessions grew the most", or wants the figure behind a usage warning without a dashboard or an API key.
---

<!-- usage-report-version: 1 -->

# Usage report

`ccusage` and the dashboards answer what Claude Code cost. This answers why, and on every machine
measured so far the answer is not the output: output tokens are well under one percent of
everything sent, and the rest is context re-sent on every turn. Two things drive that: sessions
that were never cleared, so each turn carries everything before it, and subagents that inherit
the premium model. `scripts/usage-report.py` prints that split for the last N days so the reader
can see which project, model, session or day the usage went to.

It reads and reports. **It never edits**: no network, no API key, nothing written under the
transcript root, and `message.content` is never read, so no conversation text can reach the
report.

## Run it

```bash
python3 <this skill>/scripts/usage-report.py                  # the last 7 days, ending today (UTC)
python3 <this skill>/scripts/usage-report.py --days 30        # a longer window
python3 <this skill>/scripts/usage-report.py --until 2026-03-10 --days 7   # a fixed window
python3 <this skill>/scripts/usage-report.py --json           # one JSON object, raw model names
python3 <this skill>/scripts/usage-report.py --root <dir> --top 25
```

Standard library only, Python 3.9 or later. The root defaults to `~/.claude/projects`; `--until`
names the last day of the window, inclusive, in UTC, and `--days N` is then the N whole UTC days
ending with it. `--top N` sizes the session table (default 15).

| Outcome | Stdout | Exit |
|---|---|---|
| at least one turn in the window | the summary line and four tables, or one JSON object | 0 |
| the root is not a directory, or no turn falls in the window | nothing; stderr names the root and the window | 2 |
| a bad option (`--days 0`, an unknown flag, a positional) | nothing; stderr holds the usage error | 2 |

A line that is not UTF-8 or not JSON is skipped with one stderr warning naming the file relative
to the root and the line, and the report is otherwise normal: a transcript still being written
ends in a truncated line, and that must never be a crash. A file whose mtime is before the window
start is not opened at all, so a long history costs nothing.

## What it prints

The summary line: the window, the transcripts opened, the API responses, the context re-sent
with its three tiers apart, the mean context per turn, the output and its share of everything,
and the share of turns at or above 200,000 context with the share of context they hold. Then:

- **by project**: one row per project slug, so the reader sees which repository the usage went to.
- **by model**: one row per model and kind, `main` and `subagent` apart, so a subagent that
  inherited the premium model shows as its own row. The 5-minute and 1-hour cache-write split is
  printed where the usage carries it and `-` where it does not, never 0.
- **by session**: the top N sessions by context re-sent, with the project, the context of the first
  and last main turn and the growth between them, so the sessions that were never cleared are the
  ones at the top with the highest growth.
- **by day**: one row per UTC date, so a jump is dated.

Every row carries the same columns: turns, context, context per turn, uncached, cache write,
cache read, output and the row's share of all context. The three tiers and the output are shown
apart everywhere a total is, because they are priced differently and a reader must never mistake
a total for a bill. The model name is shortened for width only (`claude-` and a trailing date
suffix dropped); `--json` keeps the raw name.

## The accounting rule

- A turn is one distinct `message.id` on an assistant record whose model is not `<synthetic>`, and
  its usage is the last line carrying that id: one response is streamed as several lines that each
  repeat its usage, so summing lines doubles the result. This rule, the `<synthetic>` rule and the
  one-warning-per-bad-line rule are a second copy of `scripts/measure-dispatch-cost.py` (#280),
  kept in step by a cross-check row in the suite; everything below is new here.
- A `<synthetic>` record (CLI-generated, for instance an API error) adds no turn and no token; a
  transcript holding only those is listed with zeros, never as an error.
- Subagent files are read first, and a file never replaces an id another file already holds, so a
  response present in both a subagent file and its parent is the subagent's.
- Context per turn is `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`: every
  token the model was given. A missing or non-integer usage key counts 0.
- Every non-assistant record, every record without a usable timestamp and every record outside the
  window is ignored, and days bucket by the UTC date of the record's own timestamp.
- A session's growth is its last main turn's context over its first main turn's, `-` when it has
  no main turn or that first context is 0.

The layout was verified on transcripts written by CLI 2.1.301 to 2.1.310: `<root>/<slug>/<session>.jsonl`
is the main session, and `<root>/<slug>/<session>/subagents/**/agent-*.jsonl` is one subagent each,
nesting allowed. `kind` in the output is derived from that path; `sidechain_turns` in `--json` counts the
records whose `isSidechain` was true and is not printed in the text report.

## What a project name is

The slug is the session's working directory with every `/` turned into `-`, so it usually starts
with the home path. What prints is the last two dash-separated components after a leading
`home-<user>` or `Users-<user>` pair is dropped, or `~` when nothing remains: neither the username
nor anything above the project is shown. The slug cannot tell a dash in a name from a slash, so a
username containing a dash is not recognised as one component; that is the stated limit of a report
meant to be read on the machine it describes.

**Never commit a report.** Its session ids and project names describe one machine, and the
numbers in this skill are generic for the same reason.

## Wiring

It is wired into no hook, workflow or pre-push: a usage report is something a person reads when a
usage warning arrives or a quota is near, not a gate. `docs/guides/model-tiers.md` ("Where usage
went") places it next to the per-dispatch measurement, and `docs/guides/startup-context.md` links
it from the startup-context recipe, because a large always-loaded context is one of the two
drivers it makes visible.
