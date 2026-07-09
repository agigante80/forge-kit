# Hook install model (decided 2026-07-09, PRs #27 to #36)

A hook reaches a project two ways, and this is the load-bearing distinction.

**Plugin-registered.** `plugins/<group>/hooks/hooks.json` activates the hook whenever
*that plugin group* is installed. Anchored to `${CLAUDE_PLUGIN_ROOT}`. Owns no user
config, so there is no wiring to drift, duplicate, or clobber. Only `block-dashes`
uses this. It requires `/plugin install forge-kit-governance@forge-kit`; the
quick-start installs `forge-kit-adapt` alone, so it is NOT on by default.

**Project-local.** `.claude/hooks/<name>.py` plus a `settings.json` entry, written by
`forge-adapt`. `block-dashes.py` distinguishes the two by its own path shape (does it
sit in a `.claude/hooks/` directory), never by the project root or by which env vars
happen to be exported.

## Decisions that must not be re-litigated

- **`block-legacy-host-push` must never be plugin-registered.** The only signal a
  `hooks.json` could gate on is `.forge.conf`, which `github-to-forgejo` writes at the
  *start* of a migration, while the hook belongs at *cutover*. Between them the skill
  supports a dual-remote / push-mirror window that depends on legacy pushes working.
  Installing it into the project IS the cutover signal. `scripts/test-hooks.py` asserts
  this so nobody "fixes" it.
- **A plugin hook is live in every project, so gate in the shell, not the interpreter.**
  Python pays ~40ms for `site` and stdlib imports before it can read its own gate.
  `hooks.json` runs `sh -c`, tests for the sentinel, and reaches `exec python3` only
  where the project opted in: 1.8ms dormant. Needs `sh` on PATH (Git Bash on Windows).
- **Exec form (`command` + `args`) with `${CLAUDE_PROJECT_DIR}`, never a relative path.**
  A relative path resolves only when cwd is the project root; from a subdirectory
  `python3` exits 2, which is the PreToolUse *deny* code, so every matched tool call is
  blocked with `can't open file`. It wedges the session rather than going quiet.

## Where the truth lives

`CLAUDE.md` (conventions), `plugins/forge-kit-governance/hooks/README.md` (both shapes),
`plugins/forge-kit-adapt/skills/adapt/references/hooks.md` (install branch),
`scripts/test-hooks.py` (43 assertions, runs in CI).
