# Where forge-kit overlaps its neighbours

## What forge-kit answers, and what its neighbours answer

Three projects, three different questions. The fastest way to decide what you need is to ask which
one you have.

| Question | Answered by | For example |
|---|---|---|
| **How should this work be done?** | [superpowers](https://github.com/obra/superpowers), installed as `superpowers@claude-plugins-official` | brainstorming, writing-plans, test-driven-development, systematic-debugging, requesting-code-review, verification-before-completion |
| **What tool does this specific task?** | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) and community collections such as [wshobson/agents](https://github.com/wshobson/agents) | code-review, pr-review-toolkit, claude-security, code-simplifier, hookify; tdd-workflows, error-diagnostics, comprehensive-review |
| **What must be true before work starts, and after it lands?** | **forge-kit** | the ticket gate and its standard, the template lockstep, the version and semver guards, the leak guard, governed overnight runs, release enforcement, host awareness, roadmap phases |

The line forge-kit holds itself to: **superpowers owns the inner loop, forge-kit owns the outer.**
The inner loop is how work happens. The outer loop is what must be true on either side of it. Where
the two touch, forge-kit gives way, and since [#177](https://github.com/agigante80/forge-kit/issues/177) that is a build failure rather than an intention.

forge-kit is not a collection of clever agents. It started as one, and the agents turned out to be
the least distinctive thing in it: the tree today carries more guard scripts and contract test
suites than prose components, and the closed phases of work on the roadmap produced guards, versioning
discipline, install scope, measurement and a leak guard rather than new capability. What is left
that nobody else ships is the outer loop, and that is what this is for.

## Where the components overlap

Stated here rather than left to be discovered, and measured rather than asserted:
`scripts/neighbour-manifest.sh --refresh` regenerates `docs/neighbours.tsv` from the marketplaces
installed on a machine, and `scripts/check-neighbour-overlap.sh` fails the build on a duplicate.

**forge-kit's specialist agents share an ancestor with `wshobson/agents`.** Five of them had barely
moved since, so [#178](https://github.com/agigante80/forge-kit/issues/178) retired them rather than maintaining a fork nobody had changed:

| Retired from forge-kit | Install this instead |
|---|---|
| `tdd-orchestrator`, `test-automator`, `performance-engineer` | `tdd-workflows@claude-code-workflows`, `performance-testing-review@claude-code-workflows` |
| `backend-architect` | `backend-development@claude-code-workflows` |
| `backend-security-coder` | `data-validation-suite@claude-code-workflows` |
| `/pr-enhance` | `comprehensive-review@claude-code-workflows` |
| the whole `forge-kit-backend` group and its skills | `backend-development@claude-code-workflows` |

One duplicate stays and `.neighbour-allow` records why: `architect-review` is dispatched by name
from `/full-review`, and pointing that at a plugin we do not ship would fail silently when absent.

What remains that shares a NAME with a neighbour is a handful of collisions, where two projects
picked the same obvious name for different files; [`neighbours.tsv`](neighbours.tsv) lists each one
with the date it was measured. Claude Code namespaces subagent types by plugin, so nothing collides
in practice.

**The counter-example is what this kit is for.** `/full-review` comes from the same ancestor as
wshobson's `comprehensive-review` and has diverged from it. What diverged is the **iteration
contract**: round accounting, the trip wire, bad-fix injection, all of which ours spells out and the
original never mentions. That is outer-loop discipline added to an inner-loop tool.
