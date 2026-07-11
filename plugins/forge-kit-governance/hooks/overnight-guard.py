#!/usr/bin/env python3
# overnight-guard-version: 1
"""PreToolUse Bash guard for an armed working-overnight run.

While .claude/overnight/active.md is present, deny destructive git and
secrets/bulk-delete commands so a drifting overnight cycle cannot run them.
Dormant when no run is armed. Merge and protected-branch push are intentionally
NOT handled here (left to GitHub branch protection).

Contract (PreToolUse, same as block-dashes):
  stdin  <- {"tool_name": ..., "tool_input": {"command": ...}, "cwd": ...}
  stdout -> deny: hookSpecificOutput.permissionDecision = "deny" ; else nothing
  exit   -> ALWAYS 0.

Fail CLOSED: when armed and the command cannot be judged (unparseable payload or a
non-string command), deny. When arming cannot be determined, allow (dormant), so
daytime work is never affected.

Not adversary-proof: matching is on the command string and catches a drifting
model doing the obvious thing, not a deliberate evasion.
"""
import json
import os
import re
import sys

SENTINEL = os.path.join(".claude", "overnight", "active.md")


def env_project_dir():
    return os.environ.get("CLAUDE_PROJECT_DIR")


def armed(project_dir):
    return project_dir is not None and os.path.exists(os.path.join(project_dir, SENTINEL))


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


GIT_PATTERNS = [
    ("git reset --hard", re.compile(r"\bgit\s+reset\b[^|;&]*--hard\b")),
    ("git branch -D", re.compile(r"\bgit\s+branch\b[^|;&]*(-D\b|--delete\b[^|;&]*--force\b|--force\b[^|;&]*--delete\b)")),
    ("git push --delete / :ref", re.compile(r"\bgit\s+push\b[^|;&]*(--delete\b|\s:\S)")),
    ("git tag -d", re.compile(r"\bgit\s+tag\b[^|;&]*(-d\b|--delete\b)")),
    ("git clean -f", re.compile(r"\bgit\s+clean\b[^|;&]*-\w*f")),
    ("git checkout discards working tree", re.compile(r"\bgit\s+checkout\b[^|;&]*(\s--\s|\s\.(\s|$)|-f\b|--force\b)")),
    ("git restore discards working tree", re.compile(r"\bgit\s+restore\b(?![^|;&]*--staged)")),
    ("git stash drop/clear", re.compile(r"\bgit\s+stash\s+(drop|clear)\b")),
]

SECRET_PATTERNS = [
    ("secret file access", re.compile(r"(^|[\s=/'\"])\.env(\.[\w.]+)?(\b|['\"]|$)")),
    ("secret file access", re.compile(r"\bid_rsa\b")),
    ("secret file access", re.compile(r"[\w./-]+\.pem\b")),
    ("secret file access", re.compile(r"/secrets?/")),
    ("pipe to shell", re.compile(r"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python\d?)\b")),
]


def is_rm_rf(cmd):
    m = re.search(r"\brm\b((?:\s+-\S+)+)", cmd)
    if not m:
        return False
    joined = "".join(re.findall(r"-(\w+)", m.group(1)))
    return "r" in joined and "f" in joined


def is_bulk_delete(cmd):
    if not is_rm_rf(cmd):
        return False
    return bool(re.search(r"(\s|=)(/|~|\$HOME)", cmd)) or ".." in cmd


def match_tier3(cmd):
    for label, rx in GIT_PATTERNS + SECRET_PATTERNS:
        if rx.search(cmd):
            return label
    if is_bulk_delete(cmd):
        return "rm -rf dangerous target"
    return None


PARK = " Do not retry; record it in .claude/overnight/decisions.md and move on."


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        payload = None
    if not isinstance(payload, dict):
        if armed(env_project_dir()):
            return deny("overnight-guard: unparseable tool payload while a run is armed; blocked (fail closed)." + PARK)
        return 0
    proj = env_project_dir() or payload.get("cwd") or os.getcwd()
    if not armed(proj):
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str):
        return deny("overnight-guard: Bash call with no readable command while armed; blocked (fail closed)." + PARK)
    hit = match_tier3(command)
    if hit:
        return deny(f"overnight-guard: blocked a Tier-3 destructive command ({hit}) during an armed overnight run." + PARK)
    return 0


if __name__ == "__main__":
    sys.exit(main())
