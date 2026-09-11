# Using forge-kit without Claude Code

forge-kit is two layers. The automation layer (agents, skills, slash commands, hooks) needs Claude
Code and cannot be ported: those are Claude Code file formats loaded by Claude Code. The
**governance layer** is plain YAML, markdown and POSIX-ish shell, and it works for any team and any
agent, including none.

This page is for that case. Four questions, in the order you will ask them.

## 1. What are the rules?

**[`docs/guides/ticket-standards.md`](ticket-standards.md).** One file, about 240 lines, and the
thing that makes it usable is that it is **canonical rather than a summary**: forge-kit's own ticket
gate is only permitted to restate it in a short list of enumerated places, and
`scripts/check-restatements.sh` fails the build if the two ever disagree. So an agent reading that
document is reading the same rules the Claude Code gate enforces, not a paraphrase of them.

Point your agent at it directly. It needs no forge-kit vocabulary to be followed.

Two smaller documents support it: [`labels.md`](labels.md) for what each label means and what it
routes, and [`template-versioning.md`](template-versioning.md) for how a ticket filed against an
older template gets brought forward.

## 2. What do I install?

Four things, and it is a copy rather than an installer:

```bash
git clone https://github.com/agigante80/forge-kit /tmp/forge-kit
cp -r /tmp/forge-kit/.github/ISSUE_TEMPLATE  .github/
cp    /tmp/forge-kit/.github/labels.yml      .github/
mkdir -p docs/guides && cp /tmp/forge-kit/docs/guides/ticket-standards.md docs/guides/
```

| What | Why |
|---|---|
| `.github/ISSUE_TEMPLATE/` | Six issue forms carrying GWT scenarios, unit and E2E test specs, personal-data handling, a security checklist and documentation impact |
| `.github/labels.yml` | The label taxonomy that routes issues |
| `docs/guides/ticket-standards.md` | The rules the templates encode |
| the shell assets below | The checks you can actually run |

There is deliberately no bootstrap script. Copying four things is `cp`, and a script for it would be
one more thing to keep working.

## 3. What can I run?

All of these are shell. None of them invokes an AI, and none needs Claude Code installed.

**Put the labels on the host**, so the taxonomy is real rather than declared:

```bash
cp /tmp/forge-kit/plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh   scripts/
cp /tmp/forge-kit/plugins/forge-kit-devops/skills/forge-host/assets/sync-labels.sh scripts/
bash scripts/sync-labels.sh --check    # report only
bash scripts/sync-labels.sh            # create missing, update drifted, delete nothing
```

**Keep the templates and the rules in lockstep**, so a template edit cannot silently diverge from
the document your agent is reading:

```bash
cp /tmp/forge-kit/scripts/check-template-lockstep.sh scripts/
bash scripts/check-template-lockstep.sh
```

**Run the mechanical half of the ticket gate** against a live issue:

```bash
cp /tmp/forge-kit/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh scripts/
cp /tmp/forge-kit/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/forge-gate-mechanics.sh   scripts/
bash scripts/forge-gate-mechanics.sh 182
```

Real output, from this repository, against its own issue #182 (re-measured 2026-09-11, after
#190):

```
template_version           fail      no template-version marker in body (current: v6)
labels                     fail      no area label (one of: api, privacy, web, mobile, backend, database, components, tooling, governance)
sections                   fail      heading absent: Summary; Priority; Area(s) affected; Files to create/modify; Rollback plan; ...
gwt                        fail      needs at least one Positive and one Negative block (found 0 positive, 0 negative)
unit_tests                 referred  no section matched unit tests; the critic must judge rule 2 unaided
e2e_tests                  referred  no section matched E2E; the critic must judge rule 3 unaided
docs_impact                pass      CLAUDE.md's validation list and the shipped-executables section. ...

forge-gate-mechanics: issue #182 against .github/ISSUE_TEMPLATE/infrastructure.yml (ticket vnone, current v6)
  1 pass, 4 fail, 0 warn, 0 n/a, 2 REFERRED
```

Three things to read from that, because they are the whole shape of this tool:

- **`referred` is not a pass.** It means the check could not rule mechanically, so a person or an
  agent still has to. The heuristics here are deliberately narrower than the rules in
  `ticket-standards.md`, because a check that guessed would reject compliant tickets.
- **It prints no verdict.** There is no PASS at the bottom, by design. This is the mechanical half
  of the gate; the reading-and-judging half has not run.
- **That ticket really does fail, and for its own reasons.** It was filed with `gh issue create
  --body-file`, so it carries no `template-version` marker and its headings are the author's own
  `##` lines. The checker reads a template section at `##` or `###` (#190), so the sections it
  does carry are READ: its documentation impact passes on content, its GWT fails on content
  (no Positive and Negative blocks), and the sections row names only the headings that are
  genuinely absent. A body none of whose headings is a template label gets a `never
  template-shaped` notice once, above the rows, and exits 0, because that shape is not a defect
  in the ticket. The full
  gate handles both cases at its Step 0c by synthesising the missing sections and writing the
  enriched body back to the forge before the checks run; this script does not synthesise, because
  that step generates prose and needs a model. If your team files tickets by hand, take the
  `referred` rows and the named absences as the useful signal.

**Count the gate rounds a ticket has had**, which is the number a bounded review loop stops on:

```bash
cp /tmp/forge-kit/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/count-gate-rounds.sh scripts/
bash scripts/count-gate-rounds.sh 182
```

It prints the round the NEXT run would be (posted `## Ticket Readiness Review` comments plus one)
and never reads the issue body for it, because an ordinary body edit erases what the gate wrote
there. If the body's block disagrees, one stderr line says so and the comments win. A count that
cannot run exits 2 and prints nothing, so it can never be mistaken for round 1.

`FORGE_TOKEN` or `GH_TOKEN` is read from the environment by `forge-lib.sh`. It is never written to a
file by any of these scripts, and you should not put it in one.

## 4. What do you NOT get?

This is the honest part, and it is why the rest of the page can be trusted.

| Not available | Why |
|---|---|
| The critic (Step 3B of the gate) | It is an agent reading the ticket and arguing with it. There is no shell equivalent, and the mechanical half does not approximate it. |
| The verdict | PASS / NEEDS-WORK / BLOCKED comes from the critic, so nothing here produces one. |
| Auto-synthesis of missing sections | The gate rewrites an older ticket into the current template. That is generation, and it needs a model. |
| The hooks | `block-dashes`, the overnight guard and the overnight loop are Claude Code hook processes. |
| The size budget and drift detection | They govern Claude Code components, which you do not have. |
| forge-adapt | It is a Claude Code skill whose entire job is reading your project and choosing components. |

So: **the rules are portable and the mechanical checks are portable. The judgement is not.** A team
using another agent can hold every ticket to one written standard and check the machine-checkable
part of it automatically, which is most of the value and not all of it.

## If you have no AI CLI at all

The same author maintains [vibe-coding-prompts](https://github.com/agigante80/vibe-coding-prompts):
14 versioned meta-prompts you paste into any assistant, covering documentation, testing, CI/CD,
security audits and logging. It needs no installation and no CLI, which is the case this page's
governance layer does not cover. It is a different mechanism from forge-kit, not a port of it: no
guard runs, and nothing fails a build.

## Contributing back

If you extend the governance layer, the same repository takes issues. `AGENTS.md` there points an
agent at the repository's own conventions, which are a different subject from this page.
