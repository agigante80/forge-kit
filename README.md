# forge-kit

[![Validate](https://github.com/agigante80/forge-kit/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/agigante80/forge-kit/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/github/license/agigante80/forge-kit)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/agigante80/forge-kit)](https://github.com/agigante80/forge-kit/releases)

**A ticket gate and build guards for repositories where an AI writes much of the code.** Before work
starts, the gate tells you whether a ticket is ready and exactly what to change if it is not. After
work lands, guards you wire into CI fail the build when a rule is broken. It ships as Claude Code
plugins; the rules themselves are plain markdown and YAML that any agent, or none, can follow.

## What it looks like

You run `/gate-ticket 576` in Claude Code. The gate checks the ticket against the
[ticket standard](docs/guides/ticket-standards.md), argues with it, and writes its verdict into the
issue body. Trimmed from [a real ticket](https://github.com/agigante80/forge-kit/issues/576), as it
read on 2026-11-13:

> **Gate verdict (round 2)**
> **Verdict:** NEEDS-WORK
> - significant: Documentation impact names no doc path (mechanical check fails)
> - significant: no-arg (CI) mode is promised but has no scenario or unit case
> - advisory: the repro writes `scratch/` into the repo root; use the ignored scratch folder `tmp/`
>
> **Required changes (gate)**
> - [ ] No-arg (CI) mode: the ticket promises it fails "in explicit and no-arg mode alike" but has
>   no scenario or test for it. Add one negative scenario [...] and one unit case in
>   `scripts/test-template-lockstep.sh` [...]

Fix the body, run it again, and it returns PASS when nothing blocks. Also: a
[forge-adapt recommendation](docs/media/forge-adapt-recommendation.md) and a
[failing guard](docs/media/guard-failing-a-build.md).

## Who it is for

- **For** a maintainer who has an AI agent writing code and wants tickets that are ready before work
  starts, and rules that fail a build rather than rely on the agent remembering them.
- **Not for** you if you want more coding skills or agents. That is the inner loop: how work gets
  done.
- **Alongside [superpowers](https://github.com/obra/superpowers):** superpowers owns the inner loop,
  forge-kit owns the outer loop, what must be true before and after. Where they touch, forge-kit gives
  way. [docs/neighbours.md](docs/neighbours.md) has the full comparison.

## Start here

You need Claude Code, `git`, `jq`, and a clone of a GitHub repository with `gh` signed in and
allowed to edit its issues (a Forgejo host works too, with a token). Then:

```bash
claude plugin marketplace add agigante80/forge-kit
claude plugin install forge-kit-governance@forge-kit    # brings forge-kit-devops, -review and -security with it
```

Restart Claude Code in your repository and run `/gate-ticket <N>` on an issue. The gate needs the
work issue templates in the repository and an area label on the issue; without them it stops with
`BLOCKED - NO_TEMPLATES` or `BLOCKED - LABELS_REQUIRED` and names the fix. **You should see** the
issue body gain a `Gate verdict (round 1)` block reading PASS or NEEDS-WORK, plus the review under
it. The gate edits the body and posts no comment.

[docs/getting-started.md](docs/getting-started.md) walks through it step by step, with what to do
when it stops. To be told which groups fit your project instead, install `forge-kit-adapt@forge-kit`
and say "run forge-adapt".

## What is enforced, and when

Installing a plugin enforces nothing by itself. A group is **installed** once `claude plugin install`
has run, and **enabled** while `claude plugin list` reports it enabled: its skills, agents and commands are
then in every session. It is **active** in a project only where that project asks: you run its
command, or you create the sentinel file a hook waits for. It is **enforcing** only where a check is
wired into your CI or git hooks, which is a file in your repository, never a side effect of the
install.

| Rule | What triggers it | What your project needs |
|---|---|---|
| A ticket meets the standard | You run `/gate-ticket <N>` | The work issue templates and an area label; the result is a verdict, not a build failure |
| Templates and the standard stay on one version | CI, every push | `forge-adapt templates` copies the guard and writes the workflow |
| A release bumps the version | CI, every pull request to the production branch | The `release-automation` skill's release gate |
| No home paths or emails reach a public repository | CI and git hooks | The `leak-guard` skill, set up in the project |
| Session rules: no dashes, no destructive commands, consent before forge writes | A tool call in a Claude Code session | The hook's sentinel file in `.claude/`, listed in [docs/install-and-upgrade.md](docs/install-and-upgrade.md) |

forge-kit's own guards (version markers, plugin semver, the size budget and the rest of its
`Validate` workflow) run in this repository only; [CONTRIBUTING.md](CONTRIBUTING.md) lists them.

`claude plugin uninstall` removes a group but not what it already did in a project: copies
forge-adapt adapted into `.claude/`, hook wiring merged into `settings.json`, sentinel files, and the
regions and tickets it wrote to your forge. [docs/install-and-upgrade.md](docs/install-and-upgrade.md)
covers removal and upgrades.

## Plugin groups

Each group installs independently, at user level by default. Inside Claude Code the same commands
exist as `/plugin install <group>@forge-kit`.

<!-- plugin-catalogue:start -->
<!-- Generated by scripts/update-component-index.py from the plugins/ tree. Do not hand-edit: run the script. CI fails on a stale region. -->

| Plugin group | Install | What you get |
|---|---|---|
| [`forge-kit-adapt`](docs/plugins.md#forge-kit-adapt) | `claude plugin install forge-kit-adapt@forge-kit` | forge-adapt skill: analyses your project, suggests the right forge-kit components to adapt to your needs, and installs… |
| [`forge-kit-devops`](docs/plugins.md#forge-kit-devops) | `claude plugin install forge-kit-devops@forge-kit` | dep-auditor, health-check agents; /ci-health command; find-dead-code, release, release-automation, forge-host… |
| [`forge-kit-governance`](docs/plugins.md#forge-kit-governance) | `claude plugin install forge-kit-governance@forge-kit` | ticket-gate agent, gate-ticket command, block-dashes hook, closing-sessions, working-overnight, ticket-gate-reference… |
| [`forge-kit-review`](docs/plugins.md#forge-kit-review) | `claude plugin install forge-kit-review@forge-kit` | code-reviewer, architect-review, code-simplifier, coding-standards-auditor and architecture-standards-auditor agents… |
| [`forge-kit-roadmap`](docs/plugins.md#forge-kit-roadmap) | `claude plugin install forge-kit-roadmap@forge-kit` | Rolling wave planning: docs/roadmap.md owns which phases exist, the host owns which phase each ticket is in, and four… |
| [`forge-kit-security`](docs/plugins.md#forge-kit-security) | `claude plugin install forge-kit-security@forge-kit` | security-auditor and api-security-tester agents, the OWASP API checklist and opt-in privacy-regime skills, the… |
| [`forge-kit-testing`](docs/plugins.md#forge-kit-testing) | `claude plugin install forge-kit-testing@forge-kit` | mutation-sweep: the defect class line coverage cannot see, which is a covered line whose test cannot fail. |
<!-- plugin-catalogue:end -->

## Documentation

- **Use it:** [getting started](docs/getting-started.md), [install and upgrade](docs/install-and-upgrade.md),
  [when to run what](docs/when-to-run-what.md), [scenarios](docs/scenarios.md).
- **Without Claude Code:** [the portable governance layer](docs/guides/without-claude-code.md).
- **Reference:** [plugin groups](docs/plugins.md), [every component](docs/components.md),
  [the ticket standard](docs/guides/ticket-standards.md), [labels](docs/guides/labels.md),
  [neighbouring projects](docs/neighbours.md).
- **Contribute:** [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md),
  [CHANGELOG.md](CHANGELOG.md).
- **History:** [the roadmap](docs/roadmap.md), the phase plans in [docs/plans/](docs/plans/) and the
  designs in [docs/superpowers/](docs/superpowers/).

Every document, who it is for and what it answers: [docs/README.md](docs/README.md).

## Related project

[**vibe-coding-prompts**](https://github.com/agigante80/vibe-coding-prompts) is the same author's
other answer to the same problem, from the opposite end: versioned, platform-agnostic meta-prompts
you paste into any assistant, where forge-kit is components installed into a project. Take that one
if you want the knowledge without the plumbing; take this one if you want rules that fail a build.

## Sponsor

I build and maintain this in my own time. It is free, it stays free, and it gets maintained either
way. If it saved you some time, you can say thanks at
[github.com/sponsors/agigante80](https://github.com/sponsors/agigante80). Entirely optional.

## License

forge-kit is released under the [MIT License](LICENSE). A few files began as copies of another
MIT-licensed project; [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) names them and carries its notice.
