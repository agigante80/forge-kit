# working-overnight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `working-overnight` bundle in forge-kit-governance: a skill that runs governed unattended overnight work (driven by `/loop`) plus a sentinel-gated, fail-open `overnight-continue` Stop hook that keeps a single cycle from halting on a question.

**Architecture:** `/loop working-overnight` is the loop engine (fresh context per cycle). The skill holds the policy: pre-flight arming, a per-cycle unit of work (pull, self-resolve, tier, run the governance pipeline, land as branch-plus-PR never merge, checkpoint, backstop), and wind-down (report, disarm, stop the loop). The hook is a per-cycle idle-stop net. The only mechanically testable part is the hook; the skill is verified structurally and by a behavioral dry-run.

**Tech Stack:** Python 3 standard library (hook), markdown (skill + references), the existing `scripts/test-hooks.py` harness, `validate-plugins.sh` / `check-version-bump.sh`.

## Global Constraints

- No em dash (U+2014) or en dash (U+2013) in any created or edited file. The `block-dashes` hook denies the tool call otherwise. Use the ASCII hyphen. In `scripts/test-hooks.py`, literal dash characters are built with `chr()`; do not add literal em/en dashes there.
- Python scripts use `python3` and the standard library only. No third-party packages, no network.
- All file paths use forward slashes.
- The hook carries `# overnight-continue-version: 1` as the first version-shaped token in the file. The skill carries `<!-- working-overnight-version: 1 -->` as the first version-shaped token, within the first few lines.
- Verified `Stop`-hook contract (Claude Code CLI 2.1.207): to continue, exit 0 and print `{"decision": "block", "reason": "<why>"}` on stdout; to allow a normal stop, exit 0 with no stdout; exit codes and JSON are mutually exclusive, so never use exit 2 for continuation. Claude Code caps a Stop hook at 8 consecutive blocks, and `stop_hook_active` is true once it is already continuing.
- The hook fails OPEN as allow-stop: on any error, non-dict payload, `stop_hook_active` true, or missing manifest, it exits 0 with no stdout.
- `hooks.json` uses exec form (`command: python3`, `args: [...]`) with `${CLAUDE_PLUGIN_ROOT}`.
- Governance `plugin.json` version bumps (a new skill and a new hook are added).

---

### Task 1: `overnight-continue` Stop hook, registration, and contract tests

**Files:**
- Create: `plugins/forge-kit-governance/hooks/overnight-continue.py`
- Modify: `plugins/forge-kit-governance/hooks/hooks.json` (add a `Stop` entry)
- Modify: `scripts/test-hooks.py` (add an overnight-continue section + registration checks; update the header)

**Interfaces:**
- Produces: a Stop hook that, given a Stop payload on stdin, prints `{"decision":"block","reason":...}` and exits 0 when `.claude/overnight/active.md` exists under the project dir and `stop_hook_active` is falsey; otherwise prints nothing and exits 0.

- [ ] **Step 1: Write the failing tests**

In `scripts/test-hooks.py`, add this section immediately before the final failures-summary / `sys.exit(...)` block at the end of the file:

```python
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
```

Also update the module docstring's first line from "Contract tests for forge-kit's PreToolUse hooks." to "Contract tests for forge-kit's PreToolUse and Stop hooks."

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 scripts/test-hooks.py`
Expected: FAIL. `OVERNIGHT` does not exist yet so the subprocess exits non-zero (the `f"exit{p.returncode}"` branches fire), and `spec["hooks"]["Stop"]` raises `KeyError` because `hooks.json` has no `Stop` entry yet.

- [ ] **Step 3: Write the hook**

Create `plugins/forge-kit-governance/hooks/overnight-continue.py`:

```python
#!/usr/bin/env python3
# overnight-continue-version: 1
"""Stop hook for the working-overnight run.

Keeps a single overnight cycle from idling to a stop on a question. It is a
safety net, not the loop engine: /loop drives the run across cycles, and Claude
Code caps a Stop hook at 8 consecutive blocks, so this hook never tries to
sustain the loop by itself.

Contract (verified against Claude Code CLI 2.1.207):
  stdin  <- Stop payload JSON (cwd, stop_hook_active, ...)
  stdout -> continue: {"decision": "block", "reason": "..."} ; else nothing
  exit   -> ALWAYS 0. Continuation is signalled on stdout, never by exit code.

Fail-open means ALLOW STOP: on any error, a non-dict payload, an already-active
continuation, or a missing manifest, emit nothing and exit 0. A broken hook must
never be able to hold a session open.
"""
import json
import os
import sys

SENTINEL = os.path.join(".claude", "overnight", "active.md")

REASON = (
    "working-overnight run active: continue the loop. Pull the next work item, "
    "defer you-only decisions to .claude/overnight/decisions.md, and wind down "
    "at queue-empty or the backstop."
)


def project_dir(payload):
    return (os.environ.get("CLAUDE_PROJECT_DIR")
            or payload.get("cwd")
            or os.getcwd())


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # fail open: unparseable input allows the stop
    if not isinstance(payload, dict):
        return 0  # not a hook payload: allow stop
    if payload.get("stop_hook_active"):
        return 0  # already continuing from a prior block: do not push the cap
    if not os.path.exists(os.path.join(project_dir(payload), SENTINEL)):
        return 0  # no armed run: dormant
    print(json.dumps({"decision": "block", "reason": REASON}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Add the `Stop` entry to hooks.json**

Replace the contents of `plugins/forge-kit-governance/hooks/hooks.json` with (adds `Stop` alongside the existing `PreToolUse`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "sh",
            "args": [
              "-c",
              "[ -n \"$CLAUDE_PROJECT_DIR\" ] && [ -f \"$CLAUDE_PROJECT_DIR/.claude/no-dashes\" ] || exit 0; exec python3 \"$0\"",
              "${CLAUDE_PLUGIN_ROOT}/hooks/block-dashes.py"
            ]
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3",
            "args": [
              "${CLAUDE_PLUGIN_ROOT}/hooks/overnight-continue.py"
            ]
          }
        ]
      }
    ]
  }
}
```

Note: no `sh` guard wrapper here. The Stop hook fires once per turn (not once per tool call), so the interpreter-startup optimization that `block-dashes` needs does not apply; the Python self-gates on the sentinel and fails open.

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 scripts/test-hooks.py`
Expected: PASS (all existing block-dashes / block-legacy-host-push cases plus the new overnight-continue cases and registration checks). Exit 0.

- [ ] **Step 6: Confirm no banned dashes**

Run: `grep -nP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/hooks/overnight-continue.py plugins/forge-kit-governance/hooks/hooks.json`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add plugins/forge-kit-governance/hooks/overnight-continue.py plugins/forge-kit-governance/hooks/hooks.json scripts/test-hooks.py
git commit -m "feat(working-overnight): sentinel-gated fail-open overnight-continue Stop hook"
```

---

### Task 2: `working-overnight` skill and references

**Files:**
- Create: `plugins/forge-kit-governance/skills/working-overnight/SKILL.md`
- Create: `plugins/forge-kit-governance/skills/working-overnight/references/safety.md`
- Create: `plugins/forge-kit-governance/skills/working-overnight/references/pipeline.md`

**Interfaces:**
- Consumes: the `overnight-continue` hook and the `.claude/overnight/` manifest from Task 1.
- Produces: a triggerable skill named `working-overnight`, driven by `/loop`.

- [ ] **Step 1: Write SKILL.md**

Create `plugins/forge-kit-governance/skills/working-overnight/SKILL.md`:

````markdown
---
name: working-overnight
description: Run governed, unattended overnight work. Pulls from a defined work source (gated tickets, tickets to gate, or investigations like full/security reviews that create tickets), implements safe work as branch-plus-PR without ever merging, defers you-only decisions instead of guessing, and writes a morning report. Use when the user says to work overnight, run unattended, keep going while they are away, or asks to set up autonomous overnight work. Driven by /loop; not a single unbounded session.
---

<!-- working-overnight-version: 1 -->

# Working overnight

Governed unattended work while the user is away. The engine is `/loop`: the user
launches `/loop working-overnight` and each cycle does one unit of work and returns
with fresh context. This skill holds the policy: what to pull, how to stay safe,
when to defer, and when to wind down. The `overnight-continue` hook keeps a single
cycle from halting on a question; it is not the engine.

Read `references/safety.md` (the tier model and the never-list) and
`references/pipeline.md` (the per-task governance pipeline) before the first cycle.
They are binding.

## Two modes, told apart by the manifest

- **Pre-flight** (interactive, once, when the user sets up the night): arm the run.
- **Cycle** (each `/loop` iteration, unattended): do one unit of work.

If `.claude/overnight/active.md` is absent, this is pre-flight. If it is present,
this is a cycle.

## Pre-flight (arming)

Do this with the user present. Never start autonomous work until they confirm.

1. Agree the work source and scope: which tickets, which investigations, and any
   no-go areas (paths, systems, ticket labels to avoid).
2. Agree the budget (token or cost ceiling) and the investigation-depth cap (how
   many new tickets an investigation may create before implementation must catch up).
3. Confirm the safety config in `references/safety.md`: the allowed tools and the
   Tier-3 never-list. Do not proceed if the requested work would need anything on
   the never-list.
4. Ensure `.claude/overnight/` is gitignored.
5. Write the manifest to `.claude/overnight/active.md` (scope, budget, caps, no-go
   list, start time) and seed `.claude/overnight/queue.md` with the initial items.
   Creating the manifest arms the hook.
6. Tell the user to run `/loop working-overnight` and leave. Stop here.

## Cycle (one unit of work)

1. Re-read `.claude/overnight/active.md`, `.claude/overnight/queue.md`, and the
   project rules (CLAUDE.md, docs/coding-standards.md). Fresh every cycle: this is
   why rule-drift does not accumulate.
2. Pick the next item by priority: a cleanly-gated ready ticket, else an ungated
   ticket to gate, else a bounded investigation. If no safe item remains, go to
   Wind-down.
3. Classify the item by tier (`references/safety.md`). A Tier-3 action is never
   performed: park it as needs-human and pick another item.
4. Resolve any question. Try web search, the code, and the project rules first.
   Only a genuine you-only decision blocks: if it is low-stakes and reversible,
   record the assumption for the report and continue; otherwise append it to
   `.claude/overnight/decisions.md` (item, options, your recommendation) and pick
   another item.
5. Do the work through `references/pipeline.md`.
6. Implementation lands in a per-item git worktree as a branch and a PR, never
   merged. Investigations write findings and create/gate tickets.
7. Update `.claude/overnight/queue.md` (done, parked, or newly created items).
8. Backstop: if context or the budget is near its limit, go to Wind-down now rather
   than starting another item.

Delegate the heavy work (implementation, review) to subagents so their tool output
does not fill this cycle's context.

## Wind-down

Reached at queue-empty (the goal) or the backstop.

1. Write `.claude/overnight/report.md`: PRs opened (links), decisions deferred (with
   options), investigations done, assumptions to verify, suggested next steps. Use
   the handoff shape from the `closing-sessions` skill.
2. Remove `.claude/overnight/active.md` to disarm the hook.
3. Stop the loop: call `ScheduleWakeup` with `stop: true` so no further cycle fires.
4. Print a one-line summary pointing at the report.
````

- [ ] **Step 2: Write references/safety.md**

Create `plugins/forge-kit-governance/skills/working-overnight/references/safety.md`:

```markdown
# working-overnight: safety model

Binding rules for every cycle. When in doubt, park the item; never guess on
anything irreversible.

## Tiers by output reversibility

- **Tier 1 (free):** investigations, full or security reviews, research, drafting
  and gating tickets. Produces reviewable artifacts, changes no code. Run freely.
- **Tier 2 (park for review):** implementing a cleanly-gated ticket, opening a PR.
  Reversible via review; runs, but the PR waits for the human. Never merged.
- **Tier 3 (never unattended):** merge to a default or protected branch,
  force-push, delete branches/tags/data, deploy or release, read or write secrets,
  disable a CI gate, or anything touching production. Park the item as needs-human.

## Hard never-list (Tier 3)

Do NOT, unattended, under any manifest: merge to main, `git push --force`, delete
remote branches or tags, run a deploy or release, read or write secrets, disable a
CI gate, or act outside the project's repo and its worktrees.

## Gating filters, never self-approves

A ticket this run authored is implemented only if it cleanly passes ticket-gate. A
ticket that needs synthesis, a waiver, or a judgment call to pass is parked, not
forced through. The gate keeps its meaning only if it can say no.

## Isolation

One git worktree per implementation item so parallel work cannot collide and main
is never checked out for edits. Remove the worktree once the PR is open.

## Logging

Every assumption (a Tier-2 low-stakes proceed) and every deferral (a you-only
decision or a Tier-3 park) is written down and appears in the morning report.
Silent choices are not allowed.
```

- [ ] **Step 3: Write references/pipeline.md**

Create `plugins/forge-kit-governance/skills/working-overnight/references/pipeline.md`:

```markdown
# working-overnight: per-task governance pipeline

Every implementation task runs through these in order. Reuse the existing
components; do not reinvent them.

1. **Best practice (research).** Web-search the current best practice for the
   specific change (framework, security, testing idioms). Note what you found.
2. **Project rules.** Apply CLAUDE.md and docs/coding-standards.md. Match the
   surrounding code.
3. **Tests first (TDD).** Derive cases from the ticket's GWT and test specs. Write
   the failing test, then the implementation (superpowers:test-driven-development).
4. **Security.** Run the security-auditor over the change. For anything touching
   auth, input handling, or data exposure, treat findings as blocking.
5. **Verify.** Drive the real behavior (superpowers:verification-before-completion),
   not just the test suite. Unattended work over-verifies.
6. **Land.** Commit on a branch in the item's worktree, open a PR whose body links
   the ticket and lists what was verified. Never merge.

To gate a ticket, run ticket-gate: a clean pass moves it to the ready queue; a
non-pass parks it with the gate's scorecard.

For an investigation, run the relevant review (full-review or security-review),
write findings, and create tickets for actionable items within the
investigation-depth cap, then let a later cycle gate and implement them.
```

- [ ] **Step 4: Verify structure and the marker**

Run: `bash scripts/validate-plugins.sh`
Expected: PASS with no complaint about the `working-overnight` marker. If it flags the marker, confirm `<!-- working-overnight-version: 1 -->` is the first `<name>-version: N` string in SKILL.md and sits just after the frontmatter.

- [ ] **Step 5: Confirm no banned dashes**

Run: `grep -rnP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/skills/working-overnight/`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add plugins/forge-kit-governance/skills/working-overnight/
git commit -m "feat(working-overnight): skill policy plus safety and pipeline references"
```

---

### Task 3: Wire into forge-kit and pass all gates

**Files:**
- Modify: `plugins/forge-kit-governance/.claude-plugin/plugin.json` (version and description)
- Modify: `.gitignore` (ignore the runtime `.claude/overnight/` artifacts)

**Interfaces:**
- Consumes: the completed hook (Task 1) and skill (Task 2).
- Produces: a governance plugin at a bumped version that includes the new skill and hook.

- [ ] **Step 1: Bump the governance plugin version and description**

Read `plugins/forge-kit-governance/.claude-plugin/plugin.json`, then set `version` to the next minor (from its current value; e.g. `0.2.0` becomes `0.3.0`) and update `description` to mention the working-overnight skill and overnight-continue hook. Example result:

```json
{
  "name": "forge-kit-governance",
  "description": "ticket-gate agent, gate-ticket command, block-dashes hook, closing-sessions and working-overnight skills, overnight-continue hook",
  "version": "0.3.0"
}
```

Use the actual current version as the base for the bump; do not assume it is 0.2.0 if the file says otherwise.

- [ ] **Step 2: Ignore the runtime artifacts**

Edit `.gitignore` to add, near the existing `temp/` entries:

```
# working-overnight runtime artifacts (manifest, queue, decisions, report)
.claude/overnight/
```

- [ ] **Step 3: Run the full gate suite**

```bash
bash scripts/validate-plugins.sh
python3 scripts/test-hooks.py
git fetch origin main
bash scripts/check-version-bump.sh origin/main
```

Expected: `validate-plugins.sh` passes (structure, semver, markers). `test-hooks.py` passes all cases including the new overnight-continue section. `check-version-bump.sh` passes: the new SKILL.md carries a `working-overnight` marker at 1, the new hook carries an `overnight-continue` marker at 1, and the governance `plugin.json` semver moved up. If it reports the base ref missing, re-run `git fetch origin main` first.

- [ ] **Step 4: Confirm no banned dashes in the changed files**

Run: `grep -nP '[\x{2013}\x{2014}]' plugins/forge-kit-governance/.claude-plugin/plugin.json .gitignore`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/forge-kit-governance/.claude-plugin/plugin.json .gitignore
git commit -m "feat(working-overnight): register skill and hook in governance plugin"
```

---

## Manual acceptance (behavioral, outside CI)

forge-kit cannot run a skill in isolation, and it cannot unit-test the end-to-end
loop. After the tasks above, validate once in a throwaway project:

1. Seed the project with two cleanly-gated tickets, one ungated ticket, and one
   investigation target.
2. Run pre-flight (arm the manifest), then `/loop working-overnight`, and let it run.
3. Confirm: it opens PRs and never merges; a planted you-only decision lands in
   `.claude/overnight/decisions.md` and the cycle moves on rather than stalling; the
   hook keeps a cycle going past a question but the run still winds down; and
   `.claude/overnight/report.md` is coherent at queue-empty.
4. Confirm the loop actually stops after wind-down (no further `/loop` cycle fires).

## Follow-ups (out of scope)

- A forge-adapt recommender row so the bundle surfaces during install.
- A headless/phased substrate variant (fresh `claude -p` per phase) for container
  isolation instead of a live session.
- Optional integration with the `minion` (Pi) as the executor.
