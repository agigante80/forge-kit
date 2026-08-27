# Static portability audit of the component catalogue

**Status: audit complete (issue #81). The broaden-or-not decision and the tool-map
experiment remain on issue #20.**

Date: 2026-08-27. Tree: `main` after PR #75. Scope: every shipped component (14 agents,
14 skills, 4 commands, 4 hooks), classified by what binds it to Claude Code, with the
binding quoted rather than asserted. Method: per-file scan for the runtime vocabulary that
does not survive a harness change (`.claude/` paths, `settings.json`, `subagent`/Agent-tool
invocation, `AskUserQuestion`, slash-command mechanics, plugin frontmatter) and for
host-tool vocabulary that survives it (`gh`, `forge_*`, `{{GITHUB_REPO}}`), which is a
FORGE binding, not an agent binding; forge-host exists to make that axis portable already.

## Classification scheme

- **portable**: no agent-runtime vocabulary at all; the file is knowledge any harness can
  inject as context.
- **path-bound**: the mechanism is generic, but concrete `.claude/` paths or one
  Claude-specific reference would need mechanical rebinding at install time (the same kind
  of rewrite forge-adapt already performs for stacks).
- **Claude-native**: depends on Claude Code's orchestration surface (subagent invocation
  model, agent frontmatter `model:`/`tools:`, hook JSON protocol, slash commands, plugin
  machinery). Porting means redesign, not rebinding.

## Skills (14)

| Skill | Class | Binding evidence |
|---|---|---|
| api-design-principles | portable | zero runtime references (0 hits on every probe) |
| architecture-patterns | portable | zero |
| cqrs-implementation | portable | zero |
| microservices-patterns | portable | zero |
| saga-orchestration | portable | zero |
| owasp-api-security | portable | zero |
| release-automation | portable (agent-agnostic; CI-host-specific) | zero agent-runtime refs; its assets are GitHub-Actions lanes + shell, a CI binding, not an agent binding |
| find-dead-code | path-bound | one reference: "never remove a symbol the project's `CLAUDE.md` marks as load-bearing" (SKILL.md:94); rebinds to any instruction file |
| release | path-bound | 8 `forge_*`/`gh` calls, zero `.claude/` refs; forge-tool-bound via the adapter, agent-agnostic shell |
| forge-host | path-bound | 3 Claude refs, all install-context (e.g. "Claude Code sessions: a settings `env` block reaches every Bash call", SKILL.md:90); the adapter itself is plain shell |
| github-to-forgejo | path-bound | `.claude/hooks/` + `settings.json` wiring in the cutover phase (SKILL.md:174-176); the migration playbook around it is host prose |
| closing-sessions | path-bound | `.claude/memory/` + `.claude/handoffs/` targets and `memory.py`; the persist-facts mechanism is generic files, the paths rebind |
| working-overnight | Claude-native | state files (`.claude/overnight/*.md`) would rebind, but the loop is armed by the overnight-guard/overnight-continue HOOKS and subagent delegation (SKILL.md:25,67,77); without the hook protocol the governance is unenforced prose |
| adapt (forge-adapt) | Claude-native | 56 runtime references: plugin cache/marketplace layout, `settings.json` wiring, `.claude/` install targets, slash invocation; this skill IS Claude Code machinery |

## Agents (14): all Claude-native

Every agent carries plugin frontmatter (`model:`, `tools:`) and is invoked through the
Agent tool with `subagent_type`; ticket-gate additionally orchestrates other agents and
posts scorecards. The *knowledge* inside several (code-reviewer's dimensions,
security-auditor's checklists) is portable prose that a port would extract into skills,
but the components as shipped are orchestration containers.

## Commands (4): all Claude-native

Slash-command mechanics; `full-review.md` and `gate-ticket.md` are the two catalogue files
that reference `subagent_type`/Agent-tool dispatch directly, and full-review additionally
depends on AskUserQuestion checkpoints and `.full-review/` session state.

## Hooks (4): all Claude-native

The PreToolUse contract (JSON payload on stdin, `permissionDecision` on stdout, exit-code
semantics) is Claude Code's hook protocol. No other harness consumes it.

## Counts

| Class | Count | Share |
|---|---|---|
| portable | 7 | 19% |
| path-bound | 5 | 14% |
| Claude-native | 24 | 67% |

## Recommendation (consistent with the #69 boundary)

The catalogue splits exactly along #69's outer-loop line: the 12 portable plus path-bound
components are the governance and knowledge layer; the 24 Claude-native ones are the
automation layer. Broadening therefore means **publishing the 12 to other harnesses via
AGENTS.md and generic-actions conventions**, not porting agents, commands, or hooks, whose
value is inseparable from Claude Code's orchestration surface. Two consequences:

1. The root `AGENTS.md` pointer (issue #80) is the zero-cost first step and is justified
   by this table alone: a third of the catalogue is consumable by any agent today.
2. #21's multi-channel machinery, if ever unparked, has a concrete target list: the 12,
   plus the issue templates and label taxonomy, which were host-agnostic from the start.

## What this audit deliberately does not settle (stays on #20)

- The practical tool-map experiment on a mid-portability component (`find-dead-code` or
  `closing-sessions`), which needs a real non-Claude harness to validate against.
- The final broaden-or-not decision, which is the maintainer's.
