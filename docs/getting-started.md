# Getting started

From nothing installed to a first verdict from the ticket gate on one of your own issues. The gate
reads an issue, checks it against a written standard, argues with it, and writes its verdict into
the issue body: PASS when the ticket is ready to implement, NEEDS-WORK with the exact changes when
it is not. Nothing here changes your code or your CI.

## What you need

- **Claude Code**, signed in.
- **`git` and `jq`** on your `PATH`. The gate's forge adapter needs both.
- **A clone of the repository whose issues you gate**, with its forge as a git remote. The gate
  finds the repository from that remote and reads the issue templates from the working tree, so
  start Claude Code from inside the clone.
- **Access to edit that repository's issues.** On GitHub, `gh` signed in (`gh auth status` says
  so) as an account that can edit issues there. On Forgejo, a token in `FORGEJO_TOKEN`; the
  `forge-host` skill covers the details. Never put the token in a file.

## 1. Install the governance group

```bash
claude plugin marketplace add agigante80/forge-kit
claude plugin install forge-kit-governance@forge-kit
```

The second command also installs `forge-kit-devops`, `forge-kit-review` and `forge-kit-security`,
which the gate depends on, and says so. Restart Claude Code afterwards. `claude plugin list` should
now show the four groups with the status enabled.

Installing enforces nothing and touches no project. What the four states (installed, enabled,
active, enforcing) mean, and what uninstalling leaves behind, is in
[install-and-upgrade.md](install-and-upgrade.md#after-you-install-a-group).

## 2. Put the issue templates in place

The gate measures a ticket against your project's own work templates, which carry a
`template-version` marker. It looks for them in `.forgejo/ISSUE_TEMPLATE`, `.gitea/ISSUE_TEMPLATE`
or `.github/ISSUE_TEMPLATE` (lowercase `issue_template` works for the first two). With none, it
stops with `BLOCKED - NO_TEMPLATES` before writing anything.

Either let forge-adapt install them, adapted to your project:

```bash
claude plugin install forge-kit-adapt@forge-kit
```

then, in Claude Code, say "forge-adapt templates" and pick what it offers. It can also install the
CI guard that keeps the templates and the standard on one version.

Or copy the five work templates by name. Leave out forge-kit's own `config.yml` and
`contribution.yml`: they would send your reporters to forge-kit.

```bash
mkdir -p .github/ISSUE_TEMPLATE
for t in feature bug security infrastructure design; do
  curl -fsSL -o ".github/ISSUE_TEMPLATE/$t.yml" \
    "https://raw.githubusercontent.com/agigante80/forge-kit/main/.github/ISSUE_TEMPLATE/$t.yml"
done
```

Commit and push them, so your forge's new-issue form offers them too.

## 3. Open an issue with an area label

File an issue with one of the five forms, or take an existing one. A hand-written issue works: the
gate adds the sections it lacks (see [When it stops](#when-it-stops)).

Give it an **area label**, which says what part of the project it touches. If your project has a
`docs/guides/labels.md`, its areas are the list. Otherwise the gate accepts its built-in areas:
`api`, `privacy`, `web`, `mobile`, `backend`, `database`, `components`, `tooling`, `governance`;
a label of your own instead is left to the critic to judge. A type label such as `enhancement` or
`bug` is recommended, and its absence is only a warning.

```bash
gh label create tooling            # once, if the label does not exist yet
gh issue edit <N> --add-label tooling
```

## 4. Run the gate

In Claude Code, from inside the clone:

```
/gate-ticket <N>
```

It takes a few minutes. It checks the mechanics first (template version, labels, sections, test
scenarios), then dispatches agents: one to judge whether the ticket is too thin to review, one to
map the code it touches, and one critic that reads the ticket and pushes back on it. A ticket
labelled `security` or `critical` also gets a security reviewer.

## 5. What you should see

The gate **edits the issue body. It posts no comment.** Reload the issue and you will find new
sections in the body, each between a pair of `<!-- gate-...:start -->` and
`<!-- gate-...:end -->` markers:

| Section | What it holds |
|---|---|
| `Gate verdict (round 1)` | The verdict, then one line per item: `significant` or `fundamental` items block, `advisory` items do not |
| `Codebase context (gate)` | The files, tests and constraints the gate found for this ticket |
| `Gate review (round 1)` | The full review: the mechanical checks table, the critique, the scenario review, pros and cons, and a suggested approach |
| `Required changes (gate)` | On NEEDS-WORK only: the blocking items as a checklist |
| `Architecture alternatives` | Only when the critic rejects the approach itself: two or three other ways to do it |

Claude Code prints the same verdict when the run ends. For a real example of a NEEDS-WORK round,
see [the round 2 verdict on this repository's issue 576](https://github.com/agigante80/forge-kit/issues/576).

## 6. Read the verdict

- **PASS:** nothing blocks. The ticket is ready to implement; the advisories are worth reading and
  are yours to take or leave.
- **NEEDS-WORK:** the `Required changes (gate)` checklist names what must change. `significant`
  means the approach stands but the ticket has gaps; `fundamental` means the approach itself was
  rejected, and the alternatives section offers others.
- **BLOCKED:** the gate could not review the ticket at all. [When it stops](#when-it-stops) says
  why and what to do.

## 7. Fix the ticket and run it again

Edit the issue body **outside** the gate's sections: each round rewrites everything between its
markers, and the previous round stays in the forge's edit history. Then run `/gate-ticket <N>`
again. Round 2 checks the mechanics in full and rechecks the previous round's blocking items.
Repeat until it returns PASS.

Where a project runs the staleness workflow (this repository does, as issue 576 shows; see
[the guide](guides/without-claude-code.md)), an edit outside the gate's sections marks the verdict
`STALE` in its heading, and the `Judged body:` line under it fingerprints the text the verdict judged. A stale
verdict is a prompt to run the gate again, not an error.

## When it stops

| What you see | Why | What to do |
|---|---|---|
| `BLOCKED - NO_TEMPLATES` | No issue template with a `template-version` marker in the working tree | Do [step 2](#2-put-the-issue-templates-in-place), then run it again |
| `BLOCKED - LABELS_REQUIRED` | The issue has no area label: none from your `docs/guides/labels.md`, or, without that file, no label at all outside the built-in area and type sets (a label of your own is referred to the critic instead) | Add one from [step 3](#3-open-an-issue-with-an-area-label), then run it again |
| `BLOCKED - #<N> needs clarification before review` | The ticket is too thin to review: three or more questions that would change the review. They are written into the body under `Gate clarification` | Answer them in the body, then run it again |
| `BLOCKED - RUN_FAILED` with one error line | A step's own check stopped the run. Common causes: `gh` not signed in (`gh auth status`), `jq` missing, or `forge-lib.sh not found` because `forge-kit-devops` is not installed or not enabled | Fix what the line names, then run it again |
| Sections you did not write appear in your issue, with `Template auto-upgraded` at the top of the review | The issue had no `template-version` marker, or an older one, so the gate filled in the current template's sections from what you wrote. Any earlier verdict is void | Read what it added, correct it in the body, and run it again |

## Next

- [When to run what](when-to-run-what.md): the gate is one step; this is the rest of the cycle.
- [Install and upgrade](install-and-upgrade.md): the other groups, uninstalling, staying current.
- [The ticket standard](guides/ticket-standards.md): the rules the gate holds a ticket to.
- [Using forge-kit without Claude Code](guides/without-claude-code.md): the same standard, with
  another agent or none.
