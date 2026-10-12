#!/usr/bin/env python3
# no-poll-loops-version: 9
"""PreToolUse Bash guard: refuse a shell wait on a dispatched subagent (#263).

A subagent dispatched with the Agent tool returns through the harness: its completion
notification arrives appended to the next tool result. Waiting on it in the shell is
always wrong, and the agent improvises exactly two shapes of it, both seen in gate
transcripts:

  1. A PLACEHOLDER WAITER: a background `sleep 240; echo waited`, queued to keep the turn
     alive until the critic returns. It is a no-op that notifies again when it stops.
  2. A POLL LOOP on the dispatched task's output file or transcript:
     `until [ -s .../tasks/<id>.output ]; do sleep 5; done` (or `while` / `for`).

Neither ever terminates usefully once the run ends, and one held a finished verdict for
five days. Not starting them is the fix; a cleanup step would be a second mechanism that
the run ending early skips. So this hook denies them and the reason says what to do.

EXACT PATTERN. Deny when the Bash `command` is a string and either:
  A. tool_input.run_in_background is true AND the whole command is a bare sleep with an
     optional no-op tail: `sleep <n>[smhd]` then optionally `;` or `&&` and one of
     `echo ...`, `true`, `:`.
  B. the command holds an `until`, `while` or `for` loop with a `sleep` before its `done`
     AND names a subagent artifact: `tasks/<id>.output`, a `subagents/` path or an
     `agent-<id>.jsonl` transcript. Background or not: the harness backgrounds a long
     foreground call.
Everything else is allowed, on purpose: `sleep 2`, a background `sleep 20; gh run watch`
(a CI wait), `until curl ...; do sleep 1; done`, a loop on any other target.
Text that only carries a loop (inside a quoted string or a heredoc body) is allowed, unless
the command executes it (`bash -c`, `sh <<EOF`, `| bash`, `eval`, `source`). The tool is Bash or Monitor, whose
payload field is the same `command`. Known gaps: a loop whose artifact path hides in a
variable set in an EARLIER call; a foreground bare sleep; `tail -f` on a task output; background placeholders wider than the pattern (a
sleep-then-cat, `sleep 60 &`, `/bin/sleep`); waits other than `sleep` inside the loop; a script
written then run; an unrelated sleeping loop followed later in the same call by an artifact
name (a false positive, accepted: a guard errs towards denying); and, in the project-local shape, a payload `cwd` below the project root when
CLAUDE_PROJECT_DIR is unset.

Contract (PreToolUse, same as block-dashes and overnight-guard):
  stdin  <- {"tool_name": "Bash" (or "Monitor"), "tool_input": {"command": ..., "run_in_background": ...}}
            plus "agent_id" (and "agent_type") when a subagent made the call (#475)
  stdout -> deny: hookSpecificOutput.permissionDecision = "deny" ; else nothing
  exit   -> ALWAYS 0. Fails OPEN on anything it cannot parse or judge.

Opt-in: this hook has its OWN sentinel, `.claude/no-poll-loops` (the one-file-per-hook rule,
same shape as `.claude/no-dashes`). hooks.json gates on it in the shell, and the check here
is defence in depth and the only gate for a project-local copy. forge-adapt creates the
sentinel when it installs the hook, so the hook is never installed switched off.

Self-test: `python3 no-poll-loops.py --self-test` runs the verdict matrix against a
throwaway project. It runs in CI via `scripts/test-hooks.py`.
"""
import json
import os
import re
import sys

SENTINEL = os.path.join(".claude", "no-poll-loops")
TOOLS = ("Bash", "Monitor")  # Monitor also takes a shell `command`

# #433 REVERSES the #263 pick "dispatch the critic in the FOREGROUND". The installed Claude Code
# (2.1.294) offers no foreground switch in a stock install: the Agent schema drops
# run_in_background and every dispatch comes back "launched in the background", at top level
# and inside a subagent. A reason (or Step 3B) that commanded a blocking call named something the
# agent could not do, and "never end the turn" forbade the only correct wait. So neither reason
# names a blocking call and each stays correct whichever way a release falls. That reading was
# of 2.1.294. Re-probed by #477 on 2.1.296: interactive dispatches run in the background, and
# `-p` dispatches run in the foreground unless run_in_background is set (#475 set it), so the
# `-p`-scoped foreground wording in Step 3B and gate-ticket.md stands on that probe. Do not
# widen it beyond `-p` without re-probing.
#
# What happens when an agent ends its turn with a dispatch outstanding depends on WHO ends it,
# and for a subagent on the MODE. Probed on 2.1.296 (#458, #475, #477; evidence on each ticket):
#   - The TOP-LEVEL session is resumed by the completion notification: seen interactively on
#     2.1.294, and verified for a one-shot headless `claude -p` on 2.1.296 (text and stream-json
#     output alike). That is REASON below.
#   - A SUBAGENT in a headless `-p` run whose child was dispatched with run_in_background is NOT
#     resumed. Its parent's Agent result is only the subagent's last text, no second
#     notification under its task id follows, and the child's result reaches the top-level
#     session as a separate notification (#475 Q1 and Q2, 2 of 2). Without run_in_background a
#     `-p` subagent's dispatch returns inline, so the shape does not arise (#477, 2 of 2).
#   - A SUBAGENT in an INTERACTIVE session IS resumed by each child's notification, inside the
#     same context: a real gate ended its turn four times with dispatches running and went on to
#     post its review (#477); its parent was the top level. A subagent resumed after its parent
#     has already taken its first result delivers the second to the top-level session, not the
#     parent: seen once, at depth 2 with background SHELL work (#477 point 4). Whether a depth-2
#     Agent dispatch behaves the same is not probed.
# SUBAGENT_REASON names both modes, and its instruction (end the turn naming what still runs)
# is right in both: interactive at depth 1 it costs one line, and headless, or deeper than depth
# 1, it is how the parent learns a result arrives separately.
# A subagent's hook payload carries agent_id and agent_type, the top level's neither (#475 Q3).
# Only agent_id, as a non-empty string, selects the subagent text; anything else gets REASON.
# This deliberately reverses #475's "either field counts": the 2.1.296 hook schema documents
# agent_id as "Absent for the main thread, even in --agent sessions. Use this field (not
# agent_type) to distinguish subagent calls", and sets agent_type on the main thread of a
# `claude --agent` session too. Counting agent_type alone would tell that top-level session it
# is a subagent that will not be resumed, which is false (review round 1 of #475).
REASON = (
    "no-poll-loops: do not wait on a dispatched subagent in the shell. A subagent returns "
    "through the harness: its completion notification is appended to the next tool result. "
    "Keep doing independent work and let the notification arrive; with none left, end your "
    "turn and the completion notification resumes you. Never queue a background sleep or a "
    "poll loop on a task's output file or transcript to wait for it."
)
SUBAGENT_REASON = (
    "no-poll-loops: do not wait on a dispatched subagent in the shell. You are a subagent. In an "
    "interactive session you are resumed when an agent you dispatched finishes. In a headless "
    "(`-p`) run, if you end your turn while an agent you dispatched with run_in_background is "
    "still running, you are not resumed: its result reaches the top-level session as a separate "
    "notification, and your parent receives only your last text. Keep doing independent work; "
    "with none left, end your turn with a line naming each agent still running and what it was "
    "asked, so your parent knows where that result goes. Never queue a background sleep or a "
    "poll loop on a task's output file or transcript to wait for it."
)

# A background sleep that does nothing: the whole command, nothing else.
BARE_SLEEP = re.compile(
    r"\A\s*sleep\s+\d+(?:\.\d+)?[smhd]?\s*"
    r"(?:(?:;|&&)\s*(?:echo\b[^\n;&|]*|true|:)\s*)?;?\s*\Z"
)
# A loop that sleeps: loop keyword ... sleep ... done. DOTALL on purpose, loops span lines.
# Deliberately untempered: a nested loop, an `echo done` or a comment must not hide a wait.
SLEEP_LOOP = re.compile(r"\b(?:until|while|for)\b.*?\bsleep\b.*?\bdone\b", re.S)
# What a dispatched subagent leaves behind.
SUBAGENT_ARTIFACT = re.compile(
    r"\btasks/[\w.-]+\.output\b|\bsubagents/|\bagent-[\w-]+\.jsonl\b"
)


def deny(reason=REASON):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


# Text that only CARRIES a loop (a forge comment body, a commit message, a data heredoc) must
# not be denied (#168 precedent). The command is BLANKED in place (same length, so offsets
# line up): heredoc bodies and quoted strings become spaces, delimiters stay.
HEREDOC = re.compile(
    r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*\n)(.*?)(\n[ \t]*\3[ \t]*(?=\n|\Z))", re.S)
# A single quote right after a word character is an apostrophe (`critic's`), not an opener.
QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|(?<![\w])'[^']*'", re.S)
# Text a shell will EXECUTE is code, not prose: `bash -c`, `sh <<EOF`, `| bash`, `eval`,
# `source`. Tested on the BLANKED command, so these words inside a quoted comment do not count.
EXECUTES = re.compile(
    r"(?<![\w.-])(?:ba|z|da)?sh\b(?![.\w-])[^\n]*?(?:\s-\w*c\b|<<)"
    r"|\|\s*(?:\S*/)?(?:ba|z|da)?sh\b"
    r"|\beval\b|\bsource\b"
)


def _blank(m, group=0):
    t = m.group(0)
    if group:
        keep = t[:m.start(group) - m.start()], t[m.end(group) - m.start():]
        return keep[0] + re.sub(r"[^\n]", " ", m.group(group)) + keep[1]
    return t[0] + re.sub(r"[^\n]", " ", t[1:-1]) + t[-1]


def blank_text(command):
    c = HEREDOC.sub(lambda m: _blank(m, 4), command)
    return QUOTED.sub(_blank, c)


def poll_loop_on_artifact(command):
    """The first sleeping loop (blanked view) must itself name a subagent artifact."""
    blanked = blank_text(command)
    view = command if EXECUTES.search(blanked) else blanked
    m = SLEEP_LOOP.search(view)
    if not m:
        return False
    # From the FIRST sleeping loop's keyword to the end: a nested `done` must not cut the
    # artifact off, a later loop is covered, and an artifact named BEFORE the loop (an echo, a
    # comment) does not count.
    tail = command[m.start():]
    if SUBAGENT_ARTIFACT.search(tail):
        return True
    # `F=/t/tasks/x.output; until [ -s $F ]; ...` in the same call.
    if "$" not in tail:
        return False
    before = command[:m.start()]
    return bool(
        re.search(r"\b\w+=\S*" + SUBAGENT_ARTIFACT.pattern, blanked[:m.start()])
        # A QUOTED value (`F="..output"`) is blanked above, so read the raw text, but only where
        # an assignment can start: after a separator, `export`, or the quote opening a
        # `bash -c` script. `echo "F=...output"` (a quote right before F) stays prose (#432).
        or re.search(r"(?:^|[;&|\n(]\s*|\bexport\s+|\s-\w*c\s+[\"'])\w+=[\"']?\S*"
                     + SUBAGENT_ARTIFACT.pattern, before))


def judge(command, background):
    """True when this command is a shell wait on a subagent."""
    if background is True and BARE_SLEEP.search(command):
        return True
    return poll_loop_on_artifact(command)


def is_subagent(payload):
    """agent_id marks a subagent; agent_type alone also appears on an --agent main thread."""
    value = payload.get("agent_id")
    return isinstance(value, str) and value != ""


def enabled(payload):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    return isinstance(root, str) and root != "" and os.path.exists(os.path.join(root, SENTINEL))


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict) or payload.get("tool_name") not in TOOLS:
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str) or not enabled(payload):
        return 0
    if judge(command, tin.get("run_in_background")):
        return deny(SUBAGENT_REASON if is_subagent(payload) else REASON)
    return 0


def self_test():
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory(prefix="npl-test-") as d:
        os.makedirs(os.path.join(d, ".claude"))
        open(os.path.join(d, SENTINEL), "w").close()
        bare = tempfile.mkdtemp(prefix="npl-bare-", dir=d)
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}

        def verdict(cmd, bg=None, proj=d):
            tin = {"command": cmd}
            if bg is not None:
                tin["run_in_background"] = bg
            e = dict(env, CLAUDE_PROJECT_DIR=proj)
            r = subprocess.run([sys.executable, os.path.abspath(__file__)],
                               input=json.dumps({"tool_name": "Bash", "tool_input": tin}),
                               capture_output=True, text=True, env=e)
            return "DENY" if '"deny"' in r.stdout and r.returncode == 0 else "ALLOW"

        cases = [
            ("DENY", "sleep 240; echo waited", True),
            ("DENY", "sleep 60 && true", True),
            ("DENY", "sleep 30", True),
            ("DENY", "until [ -s /t/tasks/ab12.output ]; do sleep 5; done", None),
            ("DENY", "while [ ! -f /t/subagents/agent-ab12.jsonl ]; do sleep 5; done", True),
            ("DENY", "for i in $(seq 1 9); do sleep 15; stat /t/tasks/ab12.output; done", False),
            ("DENY", 'F="/t/tasks/ab12.output"; until [ -s $F ]; do sleep 5; done', None),
            ("DENY", "bash -c 'F=/t/tasks/ab12.output; until [ -s $F ]; do sleep 5; done'", None),
            ("ALLOW", "sleep 2", None),
            ("ALLOW", "sleep 240; echo waited", None),
            ("ALLOW", "sleep 20; gh run watch 123", True),
            ("ALLOW", "until curl -sf localhost:3000; do sleep 1; done", True),
            ("ALLOW", "timeout 600 python3 scripts/test-hooks.py", True),
        ]
        fails = 0
        for want, cmd, bg in cases:
            got = verdict(cmd, bg)
            if got != want:
                fails += 1
                print("self-test FAIL: want %s got %s :: %r" % (want, got, cmd))
        if verdict("sleep 240; echo waited", True, proj=bare) != "ALLOW":
            fails += 1
            print("self-test FAIL: no sentinel must allow")
        print("self-test: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
        return 0 if fails == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)  # fail open
