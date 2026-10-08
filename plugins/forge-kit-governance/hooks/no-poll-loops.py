#!/usr/bin/env python3
# no-poll-loops-version: 4
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
# agent could not do, and "never end the turn" forbade the only correct wait. So the reason names
# no blocking call at all and stays correct whichever way a release falls. Not verified: a
# one-shot headless `claude -p` run. Do not re-add a foreground instruction without re-probing.
REASON = (
    "no-poll-loops: do not wait on a dispatched subagent in the shell. A subagent returns "
    "through the harness: its completion notification is appended to the next tool result. "
    "Keep doing independent work and let the notification arrive; with none left, end your "
    "turn and the completion notification resumes you. Never queue a background sleep or a "
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
    return "$" in tail and bool(
        re.search(r"\b\w+=\S*" + SUBAGENT_ARTIFACT.pattern, blanked[:m.start()]))


def judge(command, background):
    """True when this command is a shell wait on a subagent."""
    if background is True and BARE_SLEEP.search(command):
        return True
    return poll_loop_on_artifact(command)


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
        return deny()
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
