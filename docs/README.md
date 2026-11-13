# Documentation map

Every document in this repository, who it is for and what kind of page it is. **Adopters** install
or copy forge-kit into their own project; **maintainers** run a project with it day to day;
**contributors** change forge-kit itself. The kinds follow the usual split: a **tutorial** walks a
newcomer to a first result, a **how-to** gets a task done, a **reference** is looked up, an
**explanation** says why.

## Using forge-kit

| Document | For | Kind | What it answers |
|---|---|---|---|
| [../README.md](../README.md) | adopters | overview | What forge-kit is, who it is for, how to start, and what is enforced and when |
| [getting-started.md](getting-started.md) | adopters | tutorial | From installing the governance group to a first gate verdict on your own issue, and what to do when it stops |
| [install-and-upgrade.md](install-and-upgrade.md) | adopters, maintainers | how-to | The four install states, removing a group, what an installed group does where a project has not asked, declared dependencies, what forge-adapt does, and staying current |
| [plugins.md](plugins.md) | adopters | reference | Each plugin group: description, version, install command, dependencies and components (generated) |
| [components.md](components.md) | adopters, maintainers | reference | Every component the kit ships, with its version marker and size (generated) |
| [when-to-run-what.md](when-to-run-what.md) | maintainers | how-to | Which command or agent to run at each point of the work |
| [scenarios.md](scenarios.md) | adopters | explanation | What happens in concrete situations, as Given, When, Then |
| [neighbours.md](neighbours.md) | adopters | explanation | Which question forge-kit answers and which its neighbours answer, where they overlap, and what was retired in their favour |
| [guides/without-claude-code.md](guides/without-claude-code.md) | adopters | how-to | Using the governance layer with another agent or none: what to copy and what you do not get |

## Guides

| Document | For | Kind | What it answers |
|---|---|---|---|
| [guides/ticket-standards.md](guides/ticket-standards.md) | adopters, maintainers | reference | The canonical ready-ticket rules, version-locked to the issue templates |
| [guides/template-versioning.md](guides/template-versioning.md) | maintainers | explanation | How issue-template versions work and how the gate synthesises missing sections |
| [guides/labels.md](guides/labels.md) | adopters, maintainers | reference | The label taxonomy and how labels route the ticket gate's lenses |
| [guides/versioning.md](guides/versioning.md) | maintainers, contributors | reference | The three version levels and which guard enforces each |
| [guides/model-tiers.md](guides/model-tiers.md) | contributors | reference | What each component may run on and how hard it thinks, by role, with the measurement behind it |
| [guides/startup-context.md](guides/startup-context.md) | maintainers | explanation | What a session loads before work begins, and how to keep it small |
| [guides/review-loop.md](guides/review-loop.md) | maintainers | explanation | Why `/full-review` always runs round 2, the evidence behind it, and how to count its yield |

## Working on forge-kit

| Document | For | Kind | What it answers |
|---|---|---|---|
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | contributors | how-to | How to propose work and open a pull request, and the rules CI enforces |
| [../SECURITY.md](../SECURITY.md) | everyone | how-to | Supported versions and how to report a vulnerability privately |
| [../CHANGELOG.md](../CHANGELOG.md) | adopters, maintainers | reference | Release history: one heading per release, each linking its full notes |
| [changelog-detail/](changelog-detail/) | adopters, maintainers | reference | Each release's full notes, one file per version, moved verbatim from the changelog |
| [roadmap.md](roadmap.md) | contributors | reference | What is being worked on now, and what each closed phase concluded |
| [../scripts/check-doc-drift.sh](../scripts/check-doc-drift.sh) | contributors | reference | Which documents a range of commits made stale, reported per line and never as a build failure |
| Project history: [plans/](plans/) and [superpowers/](superpowers/) | contributors | explanation | Each phase's plan and close record, and the design specs and implementation plans behind shipped components |
