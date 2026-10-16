#!/usr/bin/env python3
# forge-write-consent-version: 1
"""Deny forge comments and new tickets unless the user's own prompt granted them (#565).

Two written rules, neither held by prose alone. A ticket is read by its BODY: decisions, gate
answers and corrections are rewritten into the body, and a comment is only a retraction or a
closing note. A finding becomes a ticket only when a user or operator could really hit it AND it
is too big to fix now. One session filed 25 tickets in a day and parked decisions in 12
comments, so the kit enforces both mechanically.

ONE SCRIPT, TWO EVENTS.
  UserPromptSubmit: records the grant. Every REAL prompt overwrites
    ${CLAUDE_CONFIG_DIR:-~/.claude}/forge-write-consent/<session_id>.json with
    {"comment": bool, "ticket": bool}, each true only when the prompt holds the literal word
    `allow-comment` / `allow-ticket`. So a grant lasts until the next real prompt, and a prompt
    without the word revokes it. A prompt the HARNESS injected neither grants nor revokes: a
    background task's completion (`<task-notification>`), a peer session's message and a
    cross-session idle notice. Probed on Claude Code 2.1.301: all three fire this event, and a
    peer message is how one session would otherwise grant another.
  PreToolUse Bash: denies a comment or ticket write that has no grant. A subagent's payload
    carries its parent's session_id (probed on 2.1.301), so a grant covers the subagents of the
    turn it was given in.

WHAT IS JUDGED. Quoted strings and heredoc bodies are blanked first, so a body that only
MENTIONS `gh issue comment` is not a write; text the shell executes (`bash -c`, `eval`, `| sh`)
is judged raw. The blanked view is split into segments on `; & | newline`, and each segment is
matched against its RAW text (blanking keeps offsets), so a quoted API path still counts.
  comment: gh issue|pr [flags] comment, gh pr review --comment, forge_issue_comment, tea comment,
           and a gh api / forge_api / curl write naming a /comments path.
  ticket:  gh issue [flags] create, forge_issue_create, tea issue(s)|i create, and a gh api /
           forge_api / curl write whose path ends in repos/<owner>/<repo>/issues.
  A write is per tool: gh api with -f/-F/--field/--raw-field/--input or -X POST, unless -X GET;
  curl with -d/--data*/-F/--form/--json or -X POST, unless -G/-X GET (curl's -f is --fail);
  forge_api POST|PATCH|PUT. A command inside a double-quoted "$(...)" is judged, and a segment
  asking for --help or -h is not a write.
  never denied: body rewrites (gh issue edit, forge_issue_edit, the body-region primitives),
           closes (a `gh issue close --comment` is a closing note), reads.
  exempt:  a release closing note whose whole body is `Released in <version>`, nothing after it
           (`forge_issue_comment <n> "Released in v1.2.3"`, `gh issue comment <n> --body "..."`).
  unseen:  writes made inside a function or script, not in the typed text. ticket-gate posts its
           templates with forge_gate_comment (gate-env.sh), which accepts only a file whose first
           line is one of the gate's exact headings, so that function holds the line itself;
           close-shipped.sh posts its release notes the same way.

Known limits, stated rather than implied: a script written to a file and then run, a body or
path held in a variable set in an earlier call, a forge_api POST hidden in a function, an inline
function shadowing forge_gate_comment, `gh issue close --comment` carrying a whole decision, and
the model writing the grant file itself. This guards a habit, not an adversary. A user prompt that
merely quotes the word grants it, `not-allow-comment` included. The hook sees the TYPED prompt, so
`/ci-health allow-ticket` grants and a command's expanded body never does. It never echoes
prompt text anywhere.

Contract:
  stdin  <- the hook payload (hook_event_name, session_id, prompt | tool_name + tool_input)
  stdout -> PreToolUse deny: hookSpecificOutput.permissionDecision = "deny" ; else nothing
  exit   -> ALWAYS 0. An unparseable payload fails OPEN; a missing or corrupt grant is NO grant.

Opt-in: its own sentinel, `.claude/forge-write-consent`. hooks.json gates on it in the shell;
the check here is defence in depth and the only gate for a project-local copy.

Self-test: `python3 forge-write-consent.py --self-test`; CI runs it via `scripts/test-hooks.py`.
"""
import json
import os
import re
import sys
import time

SENTINEL = os.path.join(".claude", "forge-write-consent")
GRANT_WORDS = {"comment": "allow-comment", "ticket": "allow-ticket"}
INJECTED = ("<task-notification>", "Another Claude session sent a message:", "[Cross-session")
SESSION_ID = re.compile(r"\A[A-Za-z0-9_-]{1,128}\Z")
PRUNE_SECONDS = 7 * 24 * 3600

TAIL = " Do not work around this guard."
REASONS = {
    "comment": (
        "forge-write-consent: no forge comment without the user's explicit go-ahead. A ticket is "
        "read by its BODY: decisions, answers and corrections are rewritten into the body "
        "(forge_issue_edit, the body-region primitives or gh issue edit), never added as a "
        "comment. If a comment is truly needed (a retraction, or a note the user asked for), "
        "stop and ask the user; they grant it by writing allow-comment in their next message. "
        "ticket-gate posts its own templates with forge_gate_comment." + TAIL
    ),
    "ticket": (
        "forge-write-consent: no new ticket without the user's explicit go-ahead. If it can be "
        "fixed now (about 15 minutes, inside files already touched), fix it. If no user or "
        "operator would really hit it, drop it with one line. Search open tickets and extend an "
        "existing body instead of filing a duplicate. Otherwise list each proposed ticket to the "
        "user (title, the failure, why it cannot be fixed now) and ask; they grant it by writing "
        "allow-ticket in their next message." + TAIL
    ),
}

# Blanking, as in no-poll-loops: heredoc bodies and quoted strings become spaces, same length.
HEREDOC = re.compile(
    r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*\n)(.*?)(\n[ \t]*\3[ \t]*(?=\n|\Z))", re.S)
QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|(?<![\w])'[^']*'", re.S)
EXECUTES = re.compile(
    r"(?<![\w.-])(?:ba|z|da)?sh\b(?![.\w-])[^\n]*?(?:\s-\w*c\b|<<)"
    r"|\|\s*(?:\S*/)?(?:ba|z|da)?sh\b"
    r"|\beval\b"
)   # `source` runs a FILE, not inline text, so it does not unblank the command (#565 round 1)
SEPARATORS = re.compile(r"[;&|\n]")

W = r"(?<![\w.-])"   # a command word starts here: not inside another word or path
GH_FLAGS = r"(?:\s+-\S+(?:\s+[^-\s]\S*)?)*"   # `gh issue -R o/r comment`: flags may sit between the words
COMMENT_CMD = re.compile(W + r"(?:gh\s+(?:issue|pr)" + GH_FLAGS + r"\s+comment|gh\s+pr\s+review\b[^\n]*\s--comment"
                         r"|forge_issue_comment|tea\s+comment)\b")
TICKET_CMD = re.compile(W + r"(?:gh\s+issue" + GH_FLAGS + r"\s+create|forge_issue_create|tea\s+(?:issues?|i)\s+create)\b")
HELP = re.compile(r"(?<![\w-])(?:--help|-h)(?![\w-])")
# Write signals differ per tool: curl's -f is --fail, gh api's -f is a field (#565 round 1).
API_WRITES = {
    "gh": (re.compile(W + r"gh\s+api\b"),
           re.compile(r"(?<![\w-])(?:-[fF]|--field(?![\w-])|--raw-field|--input)|(?:-X|--method)[\s=]*(?:POST|PATCH|PUT)\b"),
           re.compile(r"(?:-X|--method)[\s=]*GET\b")),
    "curl": (re.compile(W + r"curl\b"),
             re.compile(r"(?<![\w-])(?:-d|-F|--data(?:-\w+)?|--form|--json)(?![\w-])|(?:-X|--request)[\s=]*(?:POST|PATCH|PUT)\b"),
             re.compile(r"(?<![\w-])(?:-G|--get)(?![\w-])|(?:-X|--request)[\s=]*GET\b")),
    "forge_api": (re.compile(W + r"forge_api\s+(?:POST|PATCH|PUT)\b"), re.compile(r""), re.compile(r"(?!)")),
}
COMMENTS_PATH = re.compile(r"/comments\b")
ISSUES_PATH = re.compile(r"repos/(?:[^/\s\"']+/){1,2}issues/?(?=[\"'\s?]|\Z)")
RELEASE_NOTE = re.compile(
    W + r"(?:forge_issue_comment\s+\S+\s+|gh\s+issue\s+comment\s+\S+\s+(?:--body|-b)[\s=]+)"
    r"([\"'])Released in v?[\w.${}+-]+\1\s*\Z")


def _blank(m, group=0):
    t = m.group(0)
    if group:
        keep = t[:m.start(group) - m.start()], t[m.end(group) - m.start():]
        return keep[0] + re.sub(r"[^\n]", " ", m.group(group)) + keep[1]
    return t[0] + re.sub(r"[^\n]", " ", t[1:-1]) + t[-1]


def _blank_quoted(m):
    # A double-quoted "$(...)" or backtick span RUNS its command, so it stays visible (#565 round 1).
    t = m.group(0)
    return t if t[0] == '"' and ("$(" in t or "`" in t) else _blank(m)


def blank_text(command):
    c = HEREDOC.sub(lambda m: _blank(m, 4), command)
    return QUOTED.sub(_blank_quoted, c)


def segments(command):
    """(blanked, raw) pairs, split on separators found in the blanked view."""
    blanked = blank_text(command)
    if EXECUTES.search(blanked):
        blanked = command        # executed text is code: judge it raw
    out, start = [], 0
    for m in SEPARATORS.finditer(blanked):
        out.append((blanked[start:m.start()], command[start:m.start()]))
        start = m.end()
    out.append((blanked[start:], command[start:]))
    return out


def classify(command):
    """The set of grants this command needs: a subset of {"comment", "ticket"}."""
    need = set()
    for blank, raw in segments(command):
        if HELP.search(blank):
            continue   # a help request writes nothing
        if COMMENT_CMD.search(blank) and not RELEASE_NOTE.search(raw):
            need.add("comment")
        if TICKET_CMD.search(blank):
            need.add("ticket")
        for tool, writes, reads in API_WRITES.values():
            if tool.search(blank) and writes.search(raw) and not reads.search(raw):
                if COMMENTS_PATH.search(raw):
                    need.add("comment")
                elif ISSUES_PATH.search(raw):
                    need.add("ticket")
    return need


def grant_dir():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "forge-write-consent")


def grant_path(payload):
    sid = payload.get("session_id")
    if not isinstance(sid, str) or not SESSION_ID.match(sid):
        return None
    return os.path.join(grant_dir(), sid + ".json")


def record_grant(payload):
    prompt = payload.get("prompt")
    path = grant_path(payload)
    if not isinstance(prompt, str) or path is None or prompt.lstrip().startswith(INJECTED):
        return 0
    grant = {k: bool(re.search(r"(?<![\w-])" + re.escape(w) + r"(?![\w-])", prompt))
             for k, w in GRANT_WORDS.items()}
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(grant, f)
        os.replace(tmp, path)
        now = time.time()
        for name in os.listdir(os.path.dirname(path)):
            p = os.path.join(os.path.dirname(path), name)
            if now - os.path.getmtime(p) > PRUNE_SECONDS:
                os.remove(p)
    except OSError:
        pass
    return 0


def granted(payload):
    path = grant_path(payload)
    try:
        with open(path) as f:
            g = json.load(f)
        return {k for k in GRANT_WORDS if isinstance(g, dict) and g.get(k) is True}
    except (OSError, TypeError, ValueError):
        return set()


def enabled(payload):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    return isinstance(root, str) and root != "" and os.path.exists(os.path.join(root, SENTINEL))


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict) or not enabled(payload):
        return 0
    if payload.get("hook_event_name") == "UserPromptSubmit":
        return record_grant(payload)
    if payload.get("tool_name") != "Bash":
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str):
        return 0
    missing = classify(command) - granted(payload)
    for kind in ("ticket", "comment"):
        if kind in missing:
            return deny(REASONS[kind])
    return 0


def self_test():
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory(prefix="fwc-test-") as d:
        os.makedirs(os.path.join(d, ".claude"))
        open(os.path.join(d, SENTINEL), "w").close()
        env = dict(os.environ, CLAUDE_PROJECT_DIR=d, CLAUDE_CONFIG_DIR=os.path.join(d, "cfg"))

        def run(payload):
            r = subprocess.run([sys.executable, os.path.abspath(__file__)],
                               input=json.dumps(payload), capture_output=True, text=True, env=env)
            return "DENY" if '"deny"' in r.stdout and r.returncode == 0 else "ALLOW"

        def prompt(text):
            run({"hook_event_name": "UserPromptSubmit", "session_id": "s1", "prompt": text})

        def bash(cmd):
            return run({"hook_event_name": "PreToolUse", "session_id": "s1",
                        "tool_name": "Bash", "tool_input": {"command": cmd}})

        steps = [
            (None, "DENY", 'gh issue comment 5 --body "x"'),
            (None, "DENY", 'forge_issue_create "t" "b"'),
            (None, "ALLOW", 'gh issue edit 5 --body "see gh issue comment"'),
            (None, "ALLOW", 'forge_gate_comment 5 "$D/review.md"'),
            (None, "DENY", 'forge_issue_comment 5 "Released in v1.2 and we dropped X"'),
            (None, "ALLOW", 'forge_issue_comment 5 "Released in v1.2.3"'),
            ("please allow-comment", "ALLOW", 'gh issue comment 5 --body "x"'),
            (None, "DENY", 'forge_issue_create "t" "b"'),
            ("<task-notification>done</task-notification>", "ALLOW", "forge_issue_comment 5 x"),
            ("thanks", "DENY", "forge_issue_comment 5 x"),
        ]
        fails = 0
        for p, want, cmd in steps:
            if p is not None:
                prompt(p)
            got = bash(cmd)
            if got != want:
                fails += 1
                print("self-test FAIL: want %s got %s :: %r" % (want, got, cmd))
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
