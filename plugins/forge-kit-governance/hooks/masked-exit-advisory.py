#!/usr/bin/env python3
# masked-exit-advisory-version: 1
"""PostToolUse Bash advisory: a check's exit code is masked by the filter it is piped into (#420).

`bash scripts/test-x.sh | tail -5` exits with the status of `tail`, not of the suite, so a
failing check looks green and an agent reports it as passing. This hook never denies and never
judges whether the check passed. When a Bash command pipes a recognised check into a recognised
filter and neither neutraliser is present, it adds one fixed advisory to the model's context.

RECOGNISER. The command is tokenised with shlex (quotes honoured, comments dropped, heredoc
bodies blanked) and split into pipelines on `;`, `&&`, `||`, `&`, newlines and parentheses, then
into stages on `|` and `|&`. A pipeline matches when ANY non-last stage is a recognised check and
the LAST stage is a recognised filter. What follows the pipeline (`&& echo ok`) is ignored.
A `bash -c '...'` argument is analysed too (depth 2).
  Checks (first word after env assignments, `time` and an interpreter prefix): `scripts/test-*`
  and `scripts/check-*` paths, pytest, tox, nox, `python -m pytest|tox|nox|mypy|ruff`, npm, pnpm
  and yarn `test` (optionally via `run`), `make test|check`, `cargo test|check|clippy`,
  `go test|vet`, `git apply --check`, `git diff --check`, jest, vitest, bats, shellcheck, ruff,
  mypy, tsc, eslint.
  Filters: tail, head, grep, egrep, fgrep, rg, sed, awk, cut, wc, tee, sort, uniq.
NEUTRALISERS (no advisory), on tokens only: `-o pipefail` (any flag word with a leading `-` that
contains `o`, so `set -eo pipefail` counts), `setopt pipefail`, and a variable READ of PIPESTATUS
or pipestatus (`$PIPESTATUS`, `${PIPESTATUS[0]}`). The bare word in a string or a comment does not.

RESIDUAL LIMITS, stated rather than implied. The hook never sees the exit code, so it also
advises on green runs. PostToolUse does NOT fire for a Bash call that exits non-zero (Claude Code
runs the separate PostToolUseFailure event), so `check | grep FAIL` with no match (exit 1) is
never seen: the reachable domain is exactly the masked, exit-0 case. A `pipefail` set in the
user's shell profile is invisible. Indirection evades it: aliases, xargs, wrapper functions, a
pipeline inside `$(...)` within double quotes, a script written then run. A quote inside a comment
makes the command unparseable (silent). shlex drops quoting, so a single-quoted
'${PIPESTATUS[0]}' reads as a neutraliser and a quoted lone `|` reads as an operator. A pipefail
set AFTER the pipeline still neutralises. A command over 65536 characters is not analysed.

Contract (PostToolUse, advisory only):
  stdin  <- {"tool_name": "Bash", "tool_input": {"command": ...}, "tool_response": {...}, ...}
            (a subagent's payload also carries agent_id and agent_type; the same path serves it)
  stdout -> a match: hookSpecificOutput.additionalContext (fixed text, never the command);
            otherwise nothing
  exit   -> ALWAYS 0. Fails OPEN and SILENT on anything it cannot parse or judge; no exception
            path writes the command anywhere. Never emits a deny field.
  A missing script is the one exception to exit 0 and is not this file's doing: `python3 /x.py`
  exits 2, which on PostToolUse blocks nothing and shows stderr to the model.

Opt-in: this hook has its OWN sentinel, `.claude/masked-exit` (the one-file-per-hook rule, same
shape as `.claude/no-dashes`). The file is only a sentinel; its content is never read.
hooks.json gates on it in the shell (no Python start-up when absent), and the check here is
defence in depth and the only gate for a project-local copy. forge-adapt creates the sentinel when
it installs the hook, so the hook is never installed switched off.

Self-test: `python3 masked-exit-advisory.py --self-test` runs the verdict matrix against a
throwaway project. It runs in CI via `scripts/test-hooks.py`.
"""
import json
import os
import re
import shlex
import sys

SENTINEL = os.path.join(".claude", "masked-exit")
MAX_COMMAND = 65536
MAX_DEPTH = 2

ADVISORY = (
    "masked-exit-advisory: the exit code shown for this command belongs to the filter "
    "(tail, head, grep and the like), not to the check piped into it, so a failing check can "
    "look green. Do not report that check as passing from this output. Read the check's own "
    "status in the same command, for example "
    "`check | tail -5; echo \"check rc=${PIPESTATUS[0]}\"` in bash, or redirect the check to a "
    "file, read its status, then tail the file: "
    "`check > out.txt 2>&1; echo \"check rc=$?\"; tail -5 out.txt`."
)

# Words that wrap a command without changing which command it is.
WRAPPERS = {"time", "command", "exec", "env", "nice", "nohup"}
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node", "npx"}
SHELLS = {"bash", "sh", "zsh"}
SCRIPT_CHECK = re.compile(r"(?:^|/)scripts/(?:test|check)-[^/]*$")
SIMPLE_CHECKS = {"pytest", "py.test", "tox", "nox", "jest", "vitest", "bats", "shellcheck",
                 "ruff", "mypy", "tsc", "eslint"}
PY_MODULE_CHECKS = {"pytest", "tox", "nox", "mypy", "ruff"}
PKG_MANAGERS = {"npm", "pnpm", "yarn"}
FILTERS = {"tail", "head", "grep", "egrep", "fgrep", "rg", "sed", "awk", "cut", "wc", "tee",
           "sort", "uniq"}

PUNCT = "();<>|&\n"
REDIRECTS = {"<", ">", ">>", ">&", "<&", "<<", "<<-", "<<<", "&>", "&>>", ">|", "<>"}
ENV_ASSIGN = re.compile(r"^[A-Za-z_]\w*=")
PIPEFAIL_FLAG = re.compile(r"^-[A-Za-z]*o[A-Za-z]*$")
STATUS_READ = re.compile(r"\$\{?!?(?:PIPESTATUS|pipestatus)\b")
SHELL_C_FLAG = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
# Heredoc bodies are data. Keep the opening line and the terminator, drop the body.
HEREDOC = re.compile(
    r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*\n)(.*?)(\n[ \t]*\3[ \t]*(?=\n|\Z))", re.S)


def tokenise(command):
    """Word and operator tokens; comments dropped. Raises ValueError on an unbalanced quote."""
    command = HEREDOC.sub(lambda m: m.group(1) + m.group(5).lstrip("\n"), command)
    lx = shlex.shlex(command, posix=True, punctuation_chars=PUNCT)
    lx.whitespace_split = True
    lx.whitespace = " \t\r"
    lx.commenters = ""
    out = []
    in_comment = False
    for t in lx:
        if in_comment:
            if "\n" not in t:
                continue
            in_comment = False
        elif t.startswith("#"):
            in_comment = True
            continue
        out.append(t)
    return out


def is_operator(t):
    return all(c in PUNCT for c in t)


def pipelines(tokens):
    """A list of pipelines, each a list of stages, each a list of words."""
    result, stages, words = [], [], []
    for t in tokens:
        if is_operator(t):
            bare = t.replace("\n", "")
            if bare in ("|", "|&"):
                stages.append(words)
                words = []
            elif t in REDIRECTS or bare in REDIRECTS:
                words.append(t)
            else:
                stages.append(words)
                result.append(stages)
                stages, words = [], []
        else:
            words.append(t)
    stages.append(words)
    result.append(stages)
    return result


def command_words(words):
    """The stage's words after env assignments and wrappers."""
    i = 0
    while i < len(words) and (ENV_ASSIGN.match(words[i]) or words[i] in WRAPPERS):
        i += 1
    return words[i:]


def nonflags(args):
    return [a for a in args if not a.startswith("-")]


def is_check(words):
    w = command_words(words)
    if w and os.path.basename(w[0]) in INTERPRETERS:
        interp = os.path.basename(w[0])
        w = w[1:]
        if interp.startswith("python") and len(w) >= 2 and w[0] == "-m":
            return w[1] in PY_MODULE_CHECKS
        while w and w[0].startswith("-"):
            w = w[1:]
    if not w:
        return False
    head, args = w[0], w[1:]
    if SCRIPT_CHECK.search(head):
        return True
    base = os.path.basename(head)
    if base in SIMPLE_CHECKS:
        return True
    rest = nonflags(args)
    if base in PKG_MANAGERS:
        return rest[:1] == ["test"] or (rest[:1] in (["run"], ["run-script"]) and rest[1:2] == ["test"])
    if base == "make":
        return any(a in ("test", "check") for a in rest)
    if base == "cargo":
        return [a for a in rest if not a.startswith("+")][:1] in (["test"], ["check"], ["clippy"])
    if base == "go":
        return rest[:1] in (["test"], ["vet"])
    if base == "git":
        return (rest[:1] == ["apply"] or rest[:1] == ["diff"]) and "--check" in args
    return False


def is_filter(words):
    w = command_words(words)
    return bool(w) and os.path.basename(w[0]) in FILTERS


def shell_c_script(words):
    """The script string of `bash -c '...'`, or None."""
    w = command_words(words)
    if not w or os.path.basename(w[0]) not in SHELLS:
        return None
    for i, a in enumerate(w[1:], 1):
        if SHELL_C_FLAG.match(a):
            return w[i + 1] if i + 1 < len(w) else None
    return None


def neutralised(tokens):
    for i, t in enumerate(tokens):
        if STATUS_READ.search(t):
            return True
        if t == "pipefail" and i > 0 and (
                PIPEFAIL_FLAG.match(tokens[i - 1]) or tokens[i - 1] == "setopt"):
            return True
    return False


def masked(command, depth=0):
    """True when the command pipes a recognised check into a recognised filter, un-neutralised."""
    if len(command) > MAX_COMMAND:
        return False
    tokens = tokenise(command)
    if neutralised(tokens):
        return False
    for stages in pipelines(tokens):
        if len(stages) > 1 and is_filter(stages[-1]) and any(is_check(s) for s in stages[:-1]):
            return True
        if depth < MAX_DEPTH:
            for s in stages:
                inner = shell_c_script(s)
                if inner is not None and masked(inner, depth + 1):
                    return True
    return False


def advise():
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": ADVISORY,
    }}))
    return 0


def enabled(payload):
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    return isinstance(root, str) and root != "" and os.path.exists(os.path.join(root, SENTINEL))


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict) or payload.get("tool_name") != "Bash":
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str) or not enabled(payload):
        return 0
    try:
        hit = masked(command)
    except Exception:
        return 0  # unparseable (an unbalanced quote) or anything unforeseen: silent
    return advise() if hit else 0


def self_test():
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory(prefix="mea-test-") as d:
        os.makedirs(os.path.join(d, ".claude"))
        open(os.path.join(d, SENTINEL), "w").close()
        bare = tempfile.mkdtemp(prefix="mea-bare-", dir=d)
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}

        def verdict(cmd, proj=d):
            e = dict(env, CLAUDE_PROJECT_DIR=proj)
            r = subprocess.run([sys.executable, os.path.abspath(__file__)],
                               input=json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}),
                               capture_output=True, text=True, env=e)
            return "ADVISE" if "additionalContext" in r.stdout and r.returncode == 0 else "QUIET"

        cases = [
            ("ADVISE", "bash scripts/test-x.sh | tail -5"),
            ("ADVISE", 'git apply --check -R wip.patch 2>&1 | head -3 && echo "reverse-applies: already in tree"'),
            ("ADVISE", "pytest -q | grep -v ok | tail"),
            ("ADVISE", "bash -c 'make test | tail'"),
            ("QUIET", "set -o pipefail; bash scripts/test-x.sh | tail -5"),
            ("QUIET", 'bash scripts/test-x.sh | tail -5; echo "${PIPESTATUS[0]}"'),
            ("QUIET", "grep foo file | head"),
            ("QUIET", 'echo "bash scripts/test-x.sh | tail -5"'),
            ("QUIET", "bash scripts/test-x.sh; echo $?"),
        ]
        fails = 0
        for want, cmd in cases:
            got = verdict(cmd)
            if got != want:
                fails += 1
                print("self-test FAIL: want %s got %s :: %r" % (want, got, cmd))
        if verdict("bash scripts/test-x.sh | tail -5", proj=bare) != "QUIET":
            fails += 1
            print("self-test FAIL: no sentinel must stay quiet")
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
