#!/usr/bin/env python3
# overnight-guard-version: 6
"""PreToolUse Bash guard for destructive commands: an overnight arm and a daytime arm.

Two arming paths, one matcher. OVERNIGHT: while .claude/overnight/active.md is present, deny
destructive git and secrets/bulk-delete commands so a drifting overnight cycle cannot run them.
DAYTIME (#419): while .claude/no-destructive is present and no run is armed, deny the git
discards and the bulk deletes (never the secret-file or pipe-to-shell classes). With neither file
the guard is dormant. Overnight wins when both exist. Merge and protected-branch push are
intentionally NOT handled here (left to GitHub branch protection).

Contract (PreToolUse, same as block-dashes):
  stdin  <- {"tool_name": ..., "tool_input": {"command": ...}, "cwd": ...}
  stdout -> deny: hookSpecificOutput.permissionDecision = "deny" ; else nothing
  exit   -> ALWAYS 0.

Overnight fails CLOSED: when a run is armed and the command cannot be judged (unparseable
payload or a non-string command), deny. The daytime arm fails OPEN (exit 0, empty stdout) on an
unparseable payload, a missing or non-string command and a non-Bash tool, because a daytime hook
must not wedge an interactive session. When arming cannot be determined, allow (dormant).

The daytime sentinel is the opt-in in every install shape: this script has no path-shape logic,
so a project-local copy is inert without the file. forge-adapt creates it with the hook.

Not adversary-proof: matching is on the command string and catches a drifting
model doing the obvious thing, not a deliberate evasion.

Known gap: a bare "git checkout <file>" (discarding one file without "--") is
not caught, because a regex cannot tell it apart from "git checkout <branch>";
the modern "git restore <file>" form is caught broadly.
"""
import json
import os
import re
import sys

SENTINEL = os.path.join(".claude", "overnight", "active.md")
DAY_SENTINEL = os.path.join(".claude", "no-destructive")


def env_project_dir():
    return os.environ.get("CLAUDE_PROJECT_DIR")


def armed(project_dir):
    return project_dir is not None and os.path.exists(os.path.join(project_dir, SENTINEL))


def day_armed(project_dir):
    return project_dir is not None and os.path.exists(os.path.join(project_dir, DAY_SENTINEL))


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


# THE CLASS EXCLUDES A NEWLINE, and that is load-bearing (#168). It used to be `[^|;&]*`, which
# matches a newline like any other character, so the pattern ran from a `git checkout` on one line
# to a `-f` on any later line of the same payload. In a real armed run that denied, in order:
# switching branches, writing a ticket ABOUT the command, and a script naming it in a test string.
#
# A guard that blocks the project's own documented workflow, and blocks documenting itself, is one
# people turn off, and an uninstalled guard protects nothing. Bounding to a single line keeps every
# real denial (a discard is written on the line that runs it) and removes the false ones.
#
# IT IS NOT A FULL FIX FOR PROSE, and the test pins that rather than wishing it away: a heredoc BODY
# line that is itself a destructive command still denies, because no regex over a shell payload can
# tell a line that RUNS from a line that is DATA. Writing a document that quotes such a command, in
# the same tool call, is therefore still refused. Write the file with a different tool.
GIT_PATTERNS = [
    ("git reset --hard", re.compile(r"\bgit\s+reset\b[^|;&\n]*--hard\b")),
    ("git branch -D", re.compile(r"\bgit\s+branch\b[^|;&\n]*(-D\b|--delete\b[^|;&\n]*--force\b|--force\b[^|;&\n]*--delete\b)")),
    ("git push --delete / :ref", re.compile(r"\bgit\s+push\b[^|;&\n]*(--delete\b|\s:\S)")),
    ("git tag -d", re.compile(r"\bgit\s+tag\b[^|;&\n]*(-d\b|--delete\b)")),
    ("git clean -f", re.compile(r"\bgit\s+clean\b[^|;&\n]*-\w*f")),
    ("git checkout discards working tree", re.compile(r"\bgit\s+checkout\b[^|;&\n]*(\s--\s|\s\.(\s|$)|-f\b|--force\b)")),
    ("git restore discards working tree", re.compile(r"\bgit\s+restore\b(?![^|;&\n]*--staged)")),
    ("git stash drop/clear", re.compile(r"\bgit\s+stash\s+(drop|clear)\b")),
]

SECRET_PATTERNS = [
    ("secret file access", re.compile(r"(^|[\s=/'\"])\.env(?!\.(example|sample|template|dist)\b)(\.[\w.]+)?(\b|['\"]|$)")),
    ("secret file access", re.compile(r"\bid_rsa\b")),
    ("secret file access", re.compile(r"[\w./-]+\.pem\b")),
    ("secret file access", re.compile(r"/secrets?/")),
    ("pipe to shell", re.compile(r"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python\d?)\b")),
]


def _rm_force_recursive(seg):
    # Short flag clusters (-rf, -fR, ...) and the long forms (--force, --recursive).
    short = "".join(re.findall(r"(?:^|\s)-([a-zA-Z]+)\b", seg))
    force = "f" in short or bool(re.search(r"(?:^|\s)--force\b", seg))
    recursive = ("r" in short or "R" in short
                 or bool(re.search(r"(?:^|\s)--recursive\b", seg)))
    return force and recursive


def _rm_dangerous(seg):
    # A dangerous target may be preceded by whitespace, "=", or a quote (a quote
    # before the path must not hide it, mirroring the .env pattern's prefix class).
    return bool(re.search(r"(^|[\s='\"])(/|~|\$\{?HOME)", seg)) or ".." in seg


def is_bulk_delete(cmd):
    # OVERNIGHT rule, unchanged by #419: only the FIRST rm in a payload is judged, so
    # `rm -f a.txt && rm -rf $HOME/x` is allowed overnight (pinned by test-hooks.py).
    m = re.search(r"\brm\b[^|;&\n]*", cmd)
    if not m:
        return False
    seg = m.group(0)
    return _rm_force_recursive(seg) and _rm_dangerous(seg)


def _rm_wildcard(seg):
    # DAYTIME only: a non-flag target whose last character is `*` after stripping one pair of
    # surrounding quotes and one trailing slash (`tmp/*`, `./*`, `*`, `tmp/impl-*`, `tmp/*/`).
    # `tmp/*.log` ends in `.log` and a specific path ends in a name, so both stay allowed.
    for tok in seg.split()[1:]:
        if tok.startswith("-") and tok != "--":
            continue
        t = tok.strip("'\"`)}")
        if t.endswith("/"):
            t = t[:-1]
        if t.endswith("*"):
            return True
    return False


def day_bulk_delete(cmd):
    # DAYTIME judges EVERY rm segment (overnight judges the first only), so
    # `rm -rf build && rm -rf tmp/*` and `cd tmp && rm -rf *` are both caught.
    # Review r1 (#419): a command word `rm` only (not `docker run --rm` or `git rm`), flags
    # read from the leading flag tokens only, redirections dropped, `\<newline>` joined, a
    # trailing `)`/`}`/backtick ignored, and a bare `.` or `./` target is dangerous.
    cmd = cmd.replace("\\\n", " ")
    for m in re.finditer(r"(?<![\w./$-])(?<!git )rm\b[^|;&\n]*", cmd):
        seg = re.sub(r"\d*>>?\s*&?\S+", " ", m.group(0))
        toks = seg.split()[1:]
        flags = []
        for tok in toks:
            if tok.startswith("-") and tok != "--":
                flags.append(tok)
            else:
                break
        if not _rm_force_recursive("rm " + " ".join(flags)):
            continue
        if _rm_dangerous(seg) or any(t.strip("'\"`)}") in (".", "./") for t in toks):
            return "rm -rf dangerous target"
        if _rm_wildcard(seg):
            return "rm -rf wildcard target"
    return None


def match_tier3(cmd):
    for label, rx in GIT_PATTERNS + SECRET_PATTERNS:
        if rx.search(cmd):
            return label
    if is_bulk_delete(cmd):
        return "rm -rf dangerous target"
    return None


def match_day(cmd):
    # GIT_PATTERNS plus bulk delete; SECRET_PATTERNS are deliberately absent (reading .env and
    # `curl ... | sh` installers are routine by day; decided in #419).
    for label, rx in GIT_PATTERNS:
        if rx.search(cmd):
            return label
    return day_bulk_delete(cmd)


PARK = " Do not retry; record it in .claude/overnight/decisions.md and move on."

DAY_TAIL = (" A command that only quotes a dangerous string can go through the Write, Read or Grep"
            " tool or --body-file instead."
            " Do not retry another way; tell the user what you wanted to remove or discard.")


def day_reason(hit):
    return (f"overnight-guard: blocked a destructive command ({hit}); .claude/no-destructive is"
            f" present in this project.{DAY_TAIL}")


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        payload = None
    if not isinstance(payload, dict):
        if armed(env_project_dir()):
            return deny("overnight-guard: unparseable tool payload while a run is armed; blocked (fail closed)." + PARK)
        return 0   # daytime arm: fail open
    proj = env_project_dir() or payload.get("cwd") or os.getcwd()
    overnight = armed(proj)   # overnight takes precedence when both sentinels exist
    if not overnight and not day_armed(proj):
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str):
        if overnight:
            return deny("overnight-guard: Bash call with no readable command while armed; blocked (fail closed)." + PARK)
        return 0   # daytime arm: fail open
    if overnight:
        hit = match_tier3(command)
        if hit:
            return deny(f"overnight-guard: blocked a Tier-3 destructive command ({hit}) during an armed overnight run." + PARK)
        return 0
    hit = match_day(command)
    if hit:
        return deny(day_reason(hit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
