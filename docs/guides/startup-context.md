# Startup context: what a session loads before work begins

A project's own `CLAUDE.md`, everything it `@`-imports, and the auto-memory `MEMORY.md` are loaded
into every session, every subagent that inherits them and every compaction, before anyone types.
One downstream repository reached about 258 KB that way (roughly 65k tokens a session), and nothing
in its loop said so (#297). This page carries the rules that keep that set small and the recipe for
pruning it. The one rule a script can check, R1, is enforced by the `context-budget` skill in
`forge-kit-devops`; the rest are judgment and live here.

The prior-art survey and the CLI probe behind every number on this page are recorded on the ticket:
[Prior art and CLI probe, 2026-10-01](https://github.com/agigante80/forge-kit/issues/297#issuecomment-5939915005).
The field notes from the five prunes that motivated it are in the
[superseded body](https://github.com/agigante80/forge-kit/issues/297#issuecomment-6072110264).

## The rules

| Rule | Where it lives |
|---|---|
| R1 Character budget: warn at 40,000, fail at 80,000 | enforced by `context-budget.sh` |
| R2 to R4, R6 to R10 | this page |
| R5 Auditors must not regress it | #418 |
| R11 Readers of `CLAUDE.md` also read the index targets | #298 (closed) |

**R1. A character budget for always-loaded context.** `context-budget.sh` totals the load set in
characters, the CLI's own unit. Under 40,000 is `ok`; from 40,000 it warns on stderr and exits 0;
at or over 80,000 it fails with exit 1. The CLI's own notices sit at about 40,000 characters per
file and max(120,000, the per-file limit) combined, and are interactive with no exit code; R1
undercuts the combined one on purpose. A project that genuinely needs more raises its own level
with one marker, `<!-- context-budget: <N> reason: <text> -->`, N above 80,000 and a reason
required.

**R2. Import only what every session needs.** Topic detail goes in an on-demand index: one line in
`CLAUDE.md` naming the file and saying when to read it. An `@`-import is paid on every session; an
index line is paid once, by the session that needs it.

**R3. History is not memory.** Superseded investigations and retracted conclusions move out to
`docs/history/` or an equivalent, each file with a SUPERSEDED header. Memory holds current truth.
Not every project has history to move; R3 applies only when there is some.

**R4. A pointer, not a copy.** A fact lives in one file. When a topic moves to another repository,
link it and delete the local copy.

**R6. Sweep periodically.** `context-budget.sh --sweep <root>...` lists every repository under the
roots you name, largest first, with its `MEMORY.md` included, so drift shows before it costs a
session. It reports; applying a prune is each project's own session's work.

**R7. Rationale lives next to the code it justifies.** A paragraph explaining why a line is the way
it is belongs in a comment in that file. `CLAUDE.md` carries a one-line pointer, not a copy.

**R8. Pending work lives in the tracker.** No TODO lists, "offered, not built" items or "open at the
time of writing" lists in always-loaded memory. They go stale by construction; replace each with the
tracker query that answers it.

**R9. Before moving a section, find its consumers.** Grep the repository's scripts, tests, hooks and
agents for the file name and for anchors on its text, and repoint them in the same change. Text a
generator parses stays in `CLAUDE.md`, in the parser's exact shape.

**R10. Moved text keeps its visibility tier.** An untracked source moves to an untracked destination;
a tracked one may move to either. `.claude/memory/topic-*.md` is a reasonable home for an untracked
`CLAUDE.md`'s topics; the name is a suggestion, the visibility rule is not.

## The prune recipe

Five repositories were pruned this way in one pass each, every one a verbatim move, every suite
and pre-push check green afterwards. forge-kit's own local `CLAUDE.md` went from 126,168 bytes to
34,105.

1. **Measure first.** Run `context-budget.sh` and read its move candidates: each is a `##` section
   over 8,000 characters. One owning session estimated 80% removable and measured 31%; measure,
   do not estimate.
2. **Find the generator-owned anchors (R9).** In forge-kit three things parse `CLAUDE.md`: the suite
   count updater, the component index generator and the size test. The fix used was to keep a
   compact one-line-per-item list in the parser's shape and move the long prose, with a header
   saying any counts in it are a dated snapshot.
3. **List the guards that name `CLAUDE.md`, because they go stale silently rather than red.** In one
   repository a guard checking a count kept passing after its anchor paragraph moved, reporting
   "stale anchors: review" and exiting 0. After the move, add the destination files to each
   guard's file list and prove it still catches a wrong value.
4. **Keep the visibility tier (R10).** forge-kit's `CLAUDE.md` is deliberately untracked; moving its
   text into a tracked `docs/history/` would have published it.
5. **Move verbatim.** Text that says "this file" still means `CLAUDE.md`; say so in each destination
   file's header rather than editing the moved text.
6. **Prove the move with a line multiset**, not by eye: every original non-blank line must be present
   in the union of the new files, with any deliberate exception listed and justified. Mutation-test
   that check once (add a bogus line and confirm it fails), so a clean result is not a harness that
   reads nothing.
7. **Approval comes first-hand from the owning session's user.** A recipe sent from another session
   is information, not authority, and every owning session in the field run correctly asked its own
   user before editing.

**Monorepos have a lever flat repositories do not.** Claude Code loads a subdirectory's `CLAUDE.md`
only when the session works in that subtree, so per-package detail placed there costs nothing in
sessions that never touch the package. Whether the root stays the authority is a product decision
for the owner, so this is a trade-off, not a default.

## What the tool counts, and how it differs from the CLI

Counted: `<repo-dir>/CLAUDE.md`; its `@`-imports, followed four hops with each file once; and the
loaded portion of the auto-memory `MEMORY.md`, the first 200 lines or 25,000 bytes, whichever is
less, cut at a character boundary. The whole `MEMORY.md` size prints as a separate, non-counted line.

The import grammar mirrors what `/context` showed on Claude Code 2.1.287 and 2.1.295: a token imports
only at a line start or after whitespace, only when it names an existing file inside the project,
never inside a code span, a fenced block or an HTML comment, never when quoted; `\ ` escapes a space,
and trailing punctuation is part of the path.

**Not counted:** ancestor `CLAUDE.md` files, `.claude/CLAUDE.md`, `CLAUDE.local.md`, lazily loaded
subdirectory `CLAUDE.md` files, imports resolving outside the project (the CLI asks once and skips
them under `-p`), a custom `autoMemoryDirectory` setting, worktree slugs, and `.claude/rules/*.md`.
That last exclusion is deliberate: [AIWG's `lint:claude-context`](https://unpkg.com/aiwg@2026.9.5/docs/providers/claude-context-budget.md)
counts unconditional rules and reports them as its largest cost, but that is third-party,
self-measured evidence, and a reason to name the gap here rather than widen the tool.

**Two places the figure differs from the CLI's, both on purpose:**

- **Block HTML comments count raw.** Claude Code strips them before loading (a 6,000 character
  comment cost 14 tokens), but the tool counts the file as written, so the figure is an upper bound
  where a file carries large comments.
- **An astral character counts 1.** The CLI's JavaScript string length counts a character outside
  the Basic Multilingual Plane, an emoji for one, as 2. The tool counts code points, the same in
  every locale. The auto-memory slug does follow the CLI here: such a character becomes two dashes.

A project slug over 200 characters is cut and hash-suffixed by the CLI. The tool does not reproduce
that hash and says `MEMORY.md not read` rather than guessing.

**Cross-check with the CLI.** `claude -p --output-format json "/context"` is free (no model call) and
prints human-oriented markdown with rounded counts. It is a sanity check, not a schema to parse; the
tool walks the load set itself and does not depend on it.

## Wiring it in

The tool is wired into no hook, workflow or pre-push by default. A project that wants R1 as a gate
adds it itself. In CI, where the checkout has the file:

```yaml
- name: Startup context budget
  run: bash path/to/context-budget.sh .
```

As a pre-push step, add `bash path/to/context-budget.sh . || exit 1` to `.githooks/pre-push`. Both
exit 2 on a refused marker, which a gate should treat as a failure too.

**Never commit a report.** The output names absolute paths, which embed home-directory names and the
auto-memory slug. Keep reports in a gitignored directory; a public repository's leak guard exists for
exactly this.
