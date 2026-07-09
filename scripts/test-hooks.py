#!/usr/bin/env python3
"""Contract tests for forge-kit's PreToolUse hooks.

Run: python3 scripts/test-hooks.py     (no dependencies, exits 1 on failure)

Why this exists: three consecutive PRs shipped hook defects into a repo whose
whole purpose is enforcing quality gates. The hook has a trivially testable
contract, so test it.

  stdin  <- one JSON object: {"tool_name": ..., "tool_input": {...}}
  stdout -> deny: a JSON object with hookSpecificOutput.permissionDecision
            allow: nothing at all
  exit   -> ALWAYS 0. The script signals deny via stdout, never via exit code.
            A non-zero exit means the interpreter failed to run the script, and
            exit 2 in particular is Claude Code's deny signal, which is how a
            mis-wired path silently turns into "every tool call is blocked".

The dash characters are built with chr() rather than written literally: this
file would otherwise be rejected by the very hook it tests.
"""
import json
import pathlib
import subprocess
import sys

EM = chr(0x2014)
EN = chr(0x2013)

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "plugins/forge-kit-governance/hooks/block-dashes.py"

DENY, ALLOW = "deny", "allow"


def run(payload, *, raw=None, cwd="/"):
    """Invoke the hook exec-style (no shell) from a foreign cwd, as Claude Code does."""
    stdin = raw if raw is not None else json.dumps(payload)
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input=stdin, capture_output=True, text=True, cwd=cwd,
    )
    return p


def verdict(p):
    if p.stdout.strip() == "":
        return ALLOW
    return json.loads(p.stdout)["hookSpecificOutput"]["permissionDecision"]


CASES = [
    # (label, tool_name, tool_input, expected)
    ("Write, em dash",        "Write",        {"content": f"a {EM} b"},                 DENY),
    ("Write, en dash",        "Write",        {"content": f"a {EN} b"},                 DENY),
    ("Write, clean",          "Write",        {"content": "a - b"},                     ALLOW),
    ("Write, hyphen only",    "Write",        {"content": "well-formed"},               ALLOW),
    ("Edit, new_string",      "Edit",         {"new_string": f"x {EM} y"},              DENY),
    ("Edit, old_string only", "Edit",         {"old_string": f"x {EM} y",
                                               "new_string": "clean"},                  ALLOW),
    ("MultiEdit, nested",     "MultiEdit",    {"edits": [{"new_string": "ok"},
                                                         {"new_string": f"b {EN} c"}]}, DENY),
    ("MultiEdit, all clean",  "MultiEdit",    {"edits": [{"new_string": "ok"}]},        ALLOW),
    ("NotebookEdit",          "NotebookEdit", {"new_source": f"# {EM}"},                DENY),
    ("Bash, command",         "Bash",         {"command": f"echo {EM}"},                DENY),
    ("Bash, clean",           "Bash",         {"command": "echo hi"},                   ALLOW),
    ("unmatched tool (Read)", "Read",         {"content": f"a {EM} b"},                 ALLOW),
    ("non-string content",    "Write",        {"content": 123},                         ALLOW),
    ("missing tool_input",    "Write",        {},                                       ALLOW),
]

failures = []


def check(label, got, want, extra=""):
    ok = got == want
    print(f"  {'PASS' if ok else 'FAIL'}  {label:<28} got={got} want={want} {extra}")
    if not ok:
        failures.append(label)


print(f"block-dashes.py contract tests  ({HOOK.relative_to(ROOT)})\n")

for label, tool, tin, want in CASES:
    p = run({"tool_name": tool, "tool_input": tin})
    if p.returncode != 0:
        check(label, f"exit{p.returncode}", want, extra=p.stderr.strip()[:60])
        continue
    check(label, verdict(p), want)

# Exit code is part of the contract: deny is signalled on stdout, never by exiting non-zero.
p = run({"tool_name": "Write", "tool_input": {"content": f"a {EM} b"}})
check("deny still exits 0", p.returncode, 0)

# Fail open: unparseable stdin must never block a real tool call.
p = run(None, raw="{not json")
check("malformed stdin allows", verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)
check("malformed stdin exits 0", p.returncode, 0)

p = run(None, raw="")
check("empty stdin allows", verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)

# The deny payload must carry actionable guidance, not just a refusal.
p = run({"tool_name": "Write", "tool_input": {"content": f"a {EM} b"}})
reason = json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
check("deny reason names the char", "U+2014" in reason, True)
check("deny reason says restructure", "RESTRUCTURE" in reason.upper(), True)
check("deny reason warns off hyphen", "hyphen" in reason.lower(), True)

# Regression guard for #27..#29: the hook must work when cwd is not the repo root.
p = run({"tool_name": "Write", "tool_input": {"content": f"a {EM} b"}}, cwd="/")
check("works from foreign cwd", verdict(p), DENY)

print()
if failures:
    print(f"FAILED: {len(failures)} case(s): {', '.join(failures)}")
    sys.exit(1)
print("all hook contract tests passed")
