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
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

EM = chr(0x2014)
EN = chr(0x2013)

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "plugins/forge-kit-governance/hooks/block-dashes.py"

DENY, ALLOW = "deny", "allow"


def run(payload, *, raw=None, cwd="/", hook=HOOK, project_dir=ROOT):
    """Invoke the hook exec-style (no shell) from a foreign cwd, as Claude Code does.

    project_dir=None simulates Claude Code not exporting CLAUDE_PROJECT_DIR.
    """
    stdin = raw if raw is not None else json.dumps(payload)
    env = dict(os.environ)
    env.pop("CLAUDE_PROJECT_DIR", None)
    if project_dir is not None:
        env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return subprocess.run(
        [sys.executable, str(hook)],
        input=stdin, capture_output=True, text=True, cwd=cwd, env=env,
    )


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

# A JSON array/scalar is not a hook payload; must fail open rather than crash on .get().
p = run(None, raw="[1, 2, 3]")
check("non-dict payload allows", verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)

# No project root discoverable at all: fail open.
p = run({"tool_name": "Write", "tool_input": {"content": f"a {EM} b"}}, project_dir=None)
check("no project root allows", verdict(p), ALLOW)

# --- Opt-in gate -----------------------------------------------------------
# The plugin registers this hook in EVERY project. It must enforce only where the
# project opted in via .claude/no-dashes. A copy installed INTO the project is
# itself the opt-in and always enforces (back-compat for pre-existing installs).
print("\n  -- opt-in gate --")
dash = {"tool_name": "Write", "tool_input": {"content": f"a {EM} b"}}

with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()

    # (a) plugin-style: hook lives OUTSIDE the project root.
    plugin_dir = td / "plugin" / "hooks"
    plugin_dir.mkdir(parents=True)
    plugin_hook = plugin_dir / "block-dashes.py"
    shutil.copy(HOOK, plugin_hook)

    proj = td / "proj"
    (proj / ".claude").mkdir(parents=True)

    p = run(dash, hook=plugin_hook, project_dir=proj, cwd=str(proj))
    check("plugin copy, no sentinel", verdict(p), ALLOW, extra="(opinionated rule stays off)")

    (proj / ".claude" / "no-dashes").touch()
    p = run(dash, hook=plugin_hook, project_dir=proj, cwd=str(proj))
    check("plugin copy, sentinel", verdict(p), DENY, extra="(project opted in)")

    # (b) project-local install: hook lives INSIDE the project root, no sentinel.
    proj2 = td / "proj2"
    (proj2 / ".claude" / "hooks").mkdir(parents=True)
    local_hook = proj2 / ".claude" / "hooks" / "block-dashes.py"
    shutil.copy(HOOK, local_hook)

    p = run(dash, hook=local_hook, project_dir=proj2, cwd=str(proj2))
    check("project copy, no sentinel", verdict(p), DENY, extra="(install IS the opt-in)")

    p = run({"tool_name": "Write", "tool_input": {"content": "clean"}},
            hook=local_hook, project_dir=proj2, cwd=str(proj2))
    check("project copy, clean text", verdict(p), ALLOW)

    # Regression: a project install must enforce regardless of working directory,
    # and regardless of whether CLAUDE_PROJECT_DIR was exported. The previous gate
    # fell back to the payload's `cwd`, which is the session's directory and not
    # the project root, so a session started in a subdirectory silently allowed.
    sub = proj2 / "src" / "deep"
    sub.mkdir(parents=True)

    p = run(dash, hook=local_hook, project_dir=None, cwd=str(sub))
    check("project copy, cwd=subdir", verdict(p), DENY, extra="(no CLAUDE_PROJECT_DIR)")

    payload_with_cwd = dict(dash, cwd=str(sub))
    p = run(payload_with_cwd, hook=local_hook, project_dir=None, cwd=str(sub))
    check("project copy, payload cwd=subdir", verdict(p), DENY)

    p = run(dash, hook=local_hook, project_dir=proj2, cwd=str(sub))
    check("project copy, root set + subdir", verdict(p), DENY)

# --- hooks.json, as Claude Code would run it -------------------------------
# Parse the SHIPPED plugin registration and execute it, rather than a hand-written
# approximation. The sh wrapper exists so a project that never opted in does not pay
# a Python interpreter startup on every matched tool call.
print("\n  -- plugin registration (hooks.json) --")

HOOKS_JSON = ROOT / "plugins/forge-kit-governance/hooks/hooks.json"
spec = json.loads(HOOKS_JSON.read_text())
entry = spec["hooks"]["PreToolUse"][0]
reg = entry["hooks"][0]

check("matcher covers 5 tools", entry["matcher"], "Write|Edit|MultiEdit|NotebookEdit|Bash")
check("exec form (args present)", "args" in reg, True)
check("plugin root is braced", "${CLAUDE_PLUGIN_ROOT}" in " ".join(reg["args"]), True)


def invoke_registered(plugin_root, project_dir, payload):
    """Run hooks.json exactly as configured, substituting the path placeholder."""
    argv = [reg["command"]] + [
        a.replace("${CLAUDE_PLUGIN_ROOT}", str(plugin_root)) for a in reg["args"]
    ]
    env = dict(os.environ)
    env.pop("CLAUDE_PROJECT_DIR", None)
    if project_dir is not None:
        env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return subprocess.run(
        argv, input=json.dumps(payload), capture_output=True, text=True, env=env, cwd="/"
    )


with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    proot = td / "plugin"
    (proot / "hooks").mkdir(parents=True)
    shutil.copy(HOOK, proot / "hooks" / "block-dashes.py")
    proj = td / "proj"
    (proj / ".claude").mkdir(parents=True)

    p = invoke_registered(proot, proj, dash)
    check("registered, no sentinel", verdict(p), ALLOW)
    check("registered, no sentinel exit", p.returncode, 0)

    # The sh guard must SHORT-CIRCUIT, not merely reach the same verdict via the
    # script's own gate. Swap in a poison pill that denies unconditionally: if the
    # interpreter is spawned at all, this denies and the test fails. Without this,
    # deleting the guard is invisible here (same decision, 24x the cost per call).
    poison = proot / "hooks" / "block-dashes.py"
    original = poison.read_bytes()
    poison.write_text(
        "import json,sys\n"
        'print(json.dumps({"hookSpecificOutput":'
        '{"hookEventName":"PreToolUse","permissionDecision":"deny",'
        '"permissionDecisionReason":"POISON: interpreter was spawned"}}))\n'
    )
    p = invoke_registered(proot, proj, dash)
    check("no sentinel spawns no python", verdict(p), ALLOW, extra="(guard short-circuits)")
    poison.write_bytes(original)

    (proj / ".claude" / "no-dashes").touch()
    p = invoke_registered(proot, proj, dash)
    check("registered, opted in", verdict(p), DENY)
    check("stdin reaches the script", "U+2014" in p.stdout, True)

    p = invoke_registered(proot, proj, {"tool_name": "Write", "tool_input": {"content": "a - b"}})
    check("registered, clean text", verdict(p), ALLOW)

    p = invoke_registered(proot, None, dash)
    check("registered, no CLAUDE_PROJECT_DIR", verdict(p), ALLOW, extra="(fail open)")

print()
if failures:
    print(f"FAILED: {len(failures)} case(s): {', '.join(failures)}")
    sys.exit(1)
print("all hook contract tests passed")
