# Where forge-kit overlaps its neighbours

Stated here rather than left to be discovered, and measured rather than asserted:
`scripts/neighbour-manifest.sh --refresh` regenerates `docs/neighbours.tsv` from the marketplaces
installed on a machine, and `scripts/check-neighbour-overlap.sh` fails the build on a duplicate.

**forge-kit's specialist agents share an ancestor with `wshobson/agents`.** Five of them had barely
moved since, so #178 retired them rather than maintaining a fork nobody had changed:

| Retired from forge-kit | Install this instead |
|---|---|
| `tdd-orchestrator`, `test-automator`, `performance-engineer` | `tdd-workflows@claude-code-workflows`, `performance-testing-review@claude-code-workflows` |
| `backend-architect` | `backend-development@claude-code-workflows` |
| `backend-security-coder` | `data-validation-suite@claude-code-workflows` |
| `/pr-enhance` | `comprehensive-review@claude-code-workflows` |
| the whole `forge-kit-backend` group, 5 skills | `backend-development@claude-code-workflows` |

One duplicate stays and `.neighbour-allow` records why: `architect-review` is dispatched by name
from `/full-review`, and pointing that at a plugin we do not ship would fail silently when absent.

What remains that shares a NAME with a neighbour is six collisions, where two projects picked the
same obvious name and the files are 103 to 529 lines apart. Claude Code namespaces subagent types by
plugin, so nothing collides in practice.

**The counter-example is what this kit is for.** `/full-review` comes from the same ancestor as
wshobson's `comprehensive-review` and has diverged by 173 lines. What diverged is the **iteration
contract**: round accounting, the trip wire, bad-fix injection. Eleven references in ours, none in
the original. That is outer-loop discipline added to an inner-loop tool.
