# measure-dispatch-cost fixtures

Trimmed REAL Claude Code transcripts for `scripts/test-measure-dispatch-cost.sh` (#280). Hand-written
records would test their author's assumptions about the format; these test the format. Every
scenario that needs another shape mutates a throwaway copy of one of these inside the test.

## Where they came from

All three were written by **Claude Code 2.1.281** on 2026-09-24, and each record keeps its own
`version` field.

| Fixture | What it is |
|---|---|
| `gate` | A `/gate-ticket` run: `ticket-gate` at depth 1 on `claude-opus-5-5` (15 turns over 36 lines), which dispatched a `general-purpose` critic at depth 2 on `claude-sonnet-5`. |
| `hc-sonnet` | The `health-check` agent on `claude-sonnet-5`, effort `low`: 4 turns. |
| `hc-haiku` | The same task on `claude-haiku-4-5-20251001`, no effort field: 14 turns. With `hc-sonnet` it is the pair `docs/guides/model-tiers.md` records. |

Together they hold the four shapes the contract needs: duplicated `message.id` lines, a `<synthetic>`
record, a `spawnDepth` 2 grandchild, and more than one model.

**One record is spliced in.** None of the three sessions hit an API error, so the `<synthetic>`
record at the end of `gate/subagents/agent-ad867be1a23663fc4.jsonl` is a real one taken from
another session's subagent transcript (written by 2.1.270, which its `version` field says), passed
through the same trimmer, with its `timestamp` and `agentId` set to the critic's last record so it
falls inside that dispatch.

## How they were made

`trim.py <session.jsonl> <out-dir> <name>` keeps the ticket's allowlist and nothing else:

- a record's `type`, `timestamp`, `version`, `agentId`, `isApiErrorMessage` and `effort`;
- `message.{id,model,stop_reason,usage}` on an assistant record;
- `message.content` REBUILT to hold only each `Agent` tool_use block's `type`, `id` and
  `input.subagent_type`, so no conversation text survives;
- `toolUseResult.{agentId,resolvedModel}`;
- `meta.{agentType,toolUseId,spawnDepth,parentAgentId,model}`.

Everything else is dropped, which is what keeps home paths, branch names, session and request ids
and conversation text out of a public repository. The contract test fails if any fixture holds a key
outside that list, and feeds `trim.py` a transcript full of sentinel values to prove none survives.
The leak guard's two halves scan these files like every other tracked file.

To add a fixture, run `trim.py` on a real session and record it in the table above.
