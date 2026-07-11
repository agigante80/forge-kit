# Design: `overnight-guard` Tier-3 enforcement hook

Date: 2026-07-11
Status: approved design, pending spec review then implementation plan

## Problem

The `working-overnight` bundle defines a Tier-3 never-list (actions never done
unattended) as prose in `references/safety.md`. The whole-branch review of that
bundle flagged this as its one Important gap: nothing mechanically stops an
autonomous overnight cycle from running a destructive command if the model drifts,
and instruction drift after compaction is a named failure mode of long unattended
runs. The only backstop today is the model re-reading a markdown file.

This hook makes part of the never-list enforced by the harness rather than trusted
to the model.

## Goal

While an overnight run is armed (`.claude/overnight/active.md` present), deny the
destructive Bash commands the project chose to enforce, so a drifting cycle cannot
carry them out. Stay completely dormant when no run is armed, so normal daytime
work is never affected.

## Scope (chosen by the user)

Enforce two categories. Merge and protected-branch push are deliberately left to
GitHub branch protection, not this hook, to avoid duplicating what the platform
already enforces.

- **Destructive git:** local, data-losing git operations.
- **Secrets and bulk delete:** reads/writes of secret files, mass deletes, and
  pipe-to-shell.

## Non-goals

- Not adversary-proof. Matching is on the command string, so a deliberate evasion
  (for example `g""it clean`) defeats it. The threat model is a drifting model
  doing the obvious destructive thing, not an attacker. The prose never-list
  remains; this hook layers under it.
- Not a merge/deploy guard. Merge and protected-branch push are covered by GitHub
  branch protection per the user's choice; deploy/release is out of scope for this
  hook.
- Not active outside an armed run. With no sentinel it is fully dormant.

## Resolved decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fail direction when armed | Fail CLOSED (deny) on an unparseable payload or when safety cannot be determined | User choice. A false deny only parks a recoverable item; a false allow could be irreversible while unattended. |
| Enforcement surface | Destructive git, and secrets plus bulk delete | User choice. Merge/protected-push is left to GitHub branch protection to avoid duplicating platform enforcement. |
| Gating | Sentinel `.claude/overnight/active.md`, via an `sh` wrapper for fast dormancy plus a Python self-gate as defense in depth | Mirrors the battle-tested `block-dashes` wiring: the wrapper exits before Python starts when disarmed; the Python self-gate covers the project-local install shape. |
| Matching | String/regex patterns for the destructive forms only | Read-only siblings (`git status`, `gh pr view`, `kubectl get`) stay allowed. |
| Home and naming | `overnight-guard` hook in forge-kit-governance | Pairs with `overnight-continue`; the governance plugin already owns the overnight bundle. |

## The hook

`plugins/forge-kit-governance/hooks/overnight-guard.py`, a PreToolUse hook matched
on `Bash`.

PreToolUse contract (same as `block-dashes`): deny by printing
`{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision":
"deny", "permissionDecisionReason": "..."}}` on stdout and exiting 0; allow by
printing nothing and exiting 0. Deny is signalled on stdout, never by exit code.

Logic:

1. Parse the payload. If it is not a valid dict, and a run is armed, deny
   (fail-closed). If arming cannot be determined, allow (dormant).
2. Resolve the project dir (CLAUDE_PROJECT_DIR, then the payload cwd, then
   os.getcwd()) and check for `.claude/overnight/active.md`. If absent, allow
   (dormant).
3. If the tool is not Bash, allow (the hook only judges Bash commands).
4. Extract the command string. If it is missing or not a string while armed, deny
   (fail-closed).
5. If the command matches any enforced Tier-3 pattern, deny with a reason naming
   the category and telling the agent to park the item for the human. Otherwise
   allow.

The deny reason is actionable: it names what was blocked and says to record the
item in `.claude/overnight/decisions.md` and move on, not to retry.

## Enforced patterns

Destructive git (deny while armed):

- `git reset --hard`
- `git branch -D` (and `--delete --force`)
- `git push` with `--delete` or a refspec beginning with a colon (`:branch`)
- `git tag -d` / `git tag --delete`
- `git clean` with force (`-f` combined with `-d` or `-x`)
- `git checkout` / `git restore` used to discard working-tree files (a pathspec or
  `.`), which silently destroys uncommitted work
- `git stash drop` / `git stash clear`

Secrets and bulk delete (deny while armed):

- reading or writing secret-like files: `.env` and `.env.*`, names containing
  `secret` or `credential`, `id_rsa`, `*.pem`
- `rm -rf` / `rm -fr` targeting a dangerous location: `/`, `~`, `$HOME`, a path
  containing `..`, or an absolute path
- a pipe to a shell: `curl ... | sh`, `wget ... | bash`, and similar

Read-only siblings stay allowed (for example `git status`, `git log`,
`git stash list`, `gh pr view`, `cat` of a non-secret file, `rm -rf` of a relative
path inside the worktree).

## Wiring

- Add a second PreToolUse entry to `plugins/forge-kit-governance/hooks/hooks.json`,
  matched on `Bash`, wrapped in `sh` so it exits before Python when
  `.claude/overnight/active.md` is absent, then execs the Python. Exec via
  `${CLAUDE_PLUGIN_ROOT}`. The existing block-dashes PreToolUse entry and the
  overnight-continue Stop entry are unchanged.
- Version marker `# overnight-guard-version: 1` as the first version-shaped token in
  the hook.
- Update `working-overnight/references/safety.md` to note that destructive git and
  secrets/bulk-delete are now mechanically enforced by the overnight-guard hook,
  and bump the `working-overnight` skill marker accordingly.
- Bump the governance plugin.json version.

## Testing and acceptance

Contract tests in `scripts/test-hooks.py`:

- disarmed (no sentinel) plus a destructive command -> allow (dormant)
- armed plus each destructive category -> deny
- armed plus a benign command (`git status`, `rm -rf build/` inside the tree) -> allow
- armed plus an unparseable payload -> deny (fail-closed)
- armed plus a non-Bash tool -> allow
- the read-only siblings of blocked commands -> allow
- the plugin registration: the sh wrapper checks the overnight sentinel and the
  exec target is overnight-guard.py with a braced plugin root

Behavioral acceptance is part of the working-overnight dry-run: with a run armed,
confirm a planted `git reset --hard` is denied and parked, and that disarming the
run restores normal behavior.

## Shipping and CI

- `validate-plugins.sh`, `test-hooks.py`, `check-version-bump.sh` against
  origin/main; all files free of em and en dashes.
- The `sh` wrapper requires `sh` on PATH (Git Bash on Windows), same constraint as
  block-dashes; where unavailable, the project-local install shape (Python only)
  applies.

## Follow-ups (out of scope)

- Extend enforcement to deploy/release if a project wants it.
- A forge-adapt recommender note pairing overnight-guard with the working-overnight
  skill.
