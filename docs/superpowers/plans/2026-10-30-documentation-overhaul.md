# Documentation overhaul: plan

Drafted 2026-10-30 from the documentation review on umbrella ticket [#572](https://github.com/agigante80/forge-kit/issues/572) (linked from the roadmap
phase once it opens). Each work package below is written to become ONE GitHub ticket: it has a
goal, the concrete failure it removes, the files it touches, acceptance criteria and its
dependencies. Nothing here is committed work until the tickets are filed and gated.

**Status (2026-10-30):** WP1, WP2 and WP4 are done. They were filed, gated and shipped before
the external plan reviews, because each removed real harm whatever the reviews conclude. The
other work packages wait for those reviews.

## Goal

A stranger landing on the repository can tell in one screen what forge-kit does, whether it is for
them, and how to try it; a user can find the reference and the upgrade path without reading
history; a contributor can find how to run the checks; and the project's own working records stop
posing as user documentation.

## Constraints the plan must respect

- **Generated regions.** `scripts/update-component-index.py` writes the `plugin-catalogue` and
  `component-index` regions into `README.md`, and CI's freshness step fails on a stale region.
  Moving either region means changing the generator's `REGIONS` table and its contract test
  (`scripts/test-update-component-index.sh`) in the same commit.
- **`docs/plans/` is a convention, not a hardcoded path.** No asset hardcodes it (checked
  2026-10-30): the roadmap's 47 `plan:` lines carry the path as data, and `forge-kit-roadmap`
  documents `docs/plans/<phase>.md` as its convention. Moving it is possible (rewrite the `plan:`
  lines in the same commit) but makes forge-kit diverge from the convention it ships, so the
  default is to keep the path and add an index (WP8).
- **`docs/guides/ticket-standards.md` is canonical and version-locked** (`check-template-lockstep.sh`,
  `check-restatements.sh`, `citation-check.sh` read it). Renaming or moving it is out of scope.
- **Doc-drift and leak guards apply.** `check-doc-drift.sh`, `check-public-leaks.sh` and
  `check-private-leaks.sh` run on every new document; no downstream project names.
- **No em or en dashes** (the `block-dashes` hook runs on this repository).
- **Agent instructions stay local** (2026-09-16 decision): `CLAUDE.md` and `AGENTS.md` remain
  unpublished. A public `CONTRIBUTING.md` is a different document for human contributors and does
  not reverse that decision; WP4 must say so in the file.

## Target structure

```text
README.md                    landing page, about 900 to 1,200 words (from 5,025)
LICENSE                      new (WP1)
SECURITY.md                  new (WP4)
CONTRIBUTING.md              new (WP4)
CODE_OF_CONDUCT.md           new, optional (WP4)
CHANGELOG.md                 user-facing release notes (WP6)
docs/
  README.md                  new: the documentation map, by audience and by Diataxis type
  getting-started.md         new tutorial: install, gate a first ticket, read the verdict
  install-and-upgrade.md     moved from README: install, dependencies, inert-until-asked,
                             updating, the dependency upgrade note, manual install, uninstall
  plugins.md                 new reference: one section per plugin group (what it holds, what it
                             needs, what it acts on, sentinels), plus the generated catalogue
  components.md              new reference: the generated 68-row component index
  when-to-run-what.md        moved from README: the sequencing table plus overnight mode
  scenarios.md               moved from README: the GWT scenarios, as "what you get"
  neighbours.md              moved from README: overlap with superpowers, wshobson, official
  guides/                    unchanged paths; each guide gains a one-line audience header
  plans/README.md            new: what these files are, that they are working records, and how
                             they relate to docs/roadmap.md
  superpowers/README.md      new: same, for the design specs and implementation plans
```

The README keeps: the one-sentence pitch, a "what it looks like" example, who it is for and not
for, a three-command quick start with a "you should see" check, the plugin group table (generated,
short form), a docs map of links, license, sponsor.

## Work packages

### WP1. Add a license (blocker for everything public)

**Done:** [#573](https://github.com/agigante80/forge-kit/issues/573), 2026-10-30. MIT, plus
`THIRD_PARTY_NOTICES.md` for three files derived from `wshobson/agents`, a `license` field in every
manifest, and a `validate-plugins.sh` check that fails without it. `marketplace.json` was left
unchanged.

- **Failure removed:** the repository has never had a `LICENSE` file and no `plugin.json` or
  `marketplace.json` has a `license` field, so by default all rights are reserved. An adopter's
  legal review cannot approve installing or forking it, GitHub shows "No license", and the README's
  "it is free, it stays free" is a price statement, not a grant.
- **Decided (maintainer, 2026-10-30):** MIT.
- **Files:** `LICENSE`, every `plugins/*/.claude-plugin/plugin.json` (`license` field, plus a semver
  bump per group), `.claude-plugin/marketplace.json` if the schema accepts it, README license line.
- **Acceptance:** `gh repo view --json licenseInfo` is non-null; `claude plugin validate` passes;
  `validate-plugins.sh` passes.
- **Depends on:** nothing. Do first.

### WP2. Correct the stale facts now (cheap, before the restructure)

**Done:** [#574](https://github.com/agigante80/forge-kit/issues/574), 2026-10-30, with the
repository description and homepage.

- **Failure removed:** readers act on wrong statements. Verified on 2026-10-30:
  - README "thirty closed phases": the roadmap has 47 `done` phases.
  - README "When to run what": "reassessing the whole roadmap is not shipped yet"; `/phase reassess`
    ships (`plugins/forge-kit-roadmap/commands/phase.md`, section `/phase reassess`).
  - `plugins/forge-kit-governance/hooks/README.md`: says the quick start does not install
    governance (it now does) and that `hooks.json` registers `block-dashes` (it registers six hooks).
  - `docs/guides/without-claude-code.md`: "about 240 lines" for `ticket-standards.md` (292 today).
  - `CHANGELOG.md` has a `v0.10.0 (2026-10-27)` section but no `v0.10.0` tag exists (latest tag
    `v0.9.1`), so the tag and the changelog disagree.
  - GitHub repository description still leads with forge-adapt ("Nothing generic"), contains an em
    dash, and the homepage URL points back at the repository itself.
  - The README's "inert until asked" paragraph lists four hook sentinels but not
    `scan-forge-writes`'s.
  - `docs/guides/without-claude-code.md:30-33` copies over `.github/labels.yml`, the issue templates
    and the guides with plain `cp`, with no diff step and no `mkdir -p .github`, so an established
    repository loses its own policy (Codex). Split it into a new-repository route and an
    existing-repository route that stages the copy and shows `git diff` before committing.
  - `without-claude-code.md:4` says the automation layer "cannot be ported"; skills follow the open
    Agent Skills format, so state the support boundary instead (Codex).
  - `README.md:338` "There is no auto-update": Codex reports that Claude Code supports marketplace
    auto-update, off by default for third-party marketplaces. The installed CLI's
    `marketplace --help` shows no such option, so verify the live behaviour first, then reword or
    keep the sentence.
  - `README.md:68` "uninstall reverses any of it" and `README.md:70` "inert": uninstall leaves
    adapted copies, hook wiring and posted comments, and plugin skills and agents load in every
    session while only the acting hooks are marker-gated (Codex). Say which state is which.
- **Files:** `README.md`, `plugins/forge-kit-governance/hooks/README.md` (shipped content: marker
  and semver bumps), `docs/guides/without-claude-code.md`, repo settings via `gh repo edit`, the
  missing tag via the release skill.
- **Acceptance:** each bullet is fixed or the sentence is removed; no new hand-written count is
  introduced (WP7 is how counts stay true).
- **Depends on:** nothing.

### WP3. Rewrite the README as a landing page

- **Failure removed:** at 5,025 words the README is landing page, install guide, reference,
  explanation and history at once (all four Diataxis types). A visitor deciding whether to install
  has to get past a 68-row table, overlap history and an upgrade caveat to find out; the first
  screen describes what forge-kit is NOT ("not a collection of clever agents") and uses internal
  vocabulary ("outer loop", "thirty closed phases", "since #177") before showing one concrete
  result. Issue references like `#177` do not autolink in a rendered repository file, so they read
  as noise to everyone outside the project.
- **Shape:**
  1. Title, one-line pitch in the reader's terms (a ticket gate, guards that fail the build), badges
     (Validate status, license, latest release).
  2. "What it looks like": a short real gate verdict (PASS / NEEDS-WORK with its change list),
     taken from a real gated issue and linked to it; optionally an asciinema or GIF.
  3. Who it is for, who it is not for, and the superpowers boundary in three lines with a link to
     `docs/neighbours.md`.
  4. Quick start: prerequisites (Claude Code version, `gh`, `jq`, `python3`, git host), the two
     install commands, restart, the first `/gate-ticket`, and what you should see, including that
     the gate posts a comment to the forge. The opening's "enforced by a build failure" must be
     backed by a short table (rule, trigger, setup the consumer needs), separating forge-kit's own
     CI guards from what an installing project gets (Codex).
  5. Plugin groups: the generated short table, linking each to `docs/plugins.md`.
  6. Documentation map: links, grouped by audience (use it, without Claude Code, reference,
     contribute, history).
  7. License, sponsor, related project.
- **Files:** `README.md`; the moved sections land in the WP5 files; generator `REGIONS` change if the
  component index moves out (it should).
- **Acceptance:** README at or under 1,200 words; every moved paragraph exists at its new home (no
  content lost: diff the section list); no bare `#NNN` references; every docs entry a link;
  `update-component-index.py --check` and `check-doc-drift.sh` pass.
- **Depends on:** WP5 (the destinations must exist), WP1 (license line and badge).

### WP4. Community health files: SECURITY, CONTRIBUTING, Code of Conduct

**Done:** [#575](https://github.com/agigante80/forge-kit/issues/575), 2026-10-30: `SECURITY.md`,
`CONTRIBUTING.md`, the pull request template, the issue chooser's private security link, and
private vulnerability reporting enabled. The Code of Conduct was left out: it needs an
enforcement contact the maintainer has not chosen, and remains optional.

- **Failure removed:** a security researcher who finds a hole in a hook or the leak guard has no
  private route and may file a public issue, in a kit whose subject is security and leak
  prevention. A contributor cannot find how to run the checks: the validation command list lives
  only in the local `CLAUDE.md`. The kit ships `contributor-docs`, which tells other projects to
  have exactly these entry points, and does not have them itself.
- **Files:** `SECURITY.md` (GitHub private vulnerability reporting enabled, scope, response
  expectations), `CONTRIBUTING.md` (branch model, the checks to run, the version-marker and semver
  rules, the dash rule, the gate-before-work rule, how to propose a component via the contribution
  template), optional `CODE_OF_CONDUCT.md` (Contributor Covenant), and
  `.github/PULL_REQUEST_TEMPLATE.md` for outside PRs (the maintainer's own flow still uses none).
- **Acceptance:** GitHub's community profile shows license, contributing, security and (if chosen)
  code of conduct; `check-contributor-docs.sh` run against this repository passes (dogfooding); the
  file states that agent instructions are deliberately local.
- **Depends on:** WP1. **Decided (maintainer, 2026-10-30):** outside contributions are welcome
  through issues or pull requests.

### WP5. Split reference and explanation out of the README into `docs/`

- **Failure removed:** reference material in the README is only reachable by scrolling, cannot be
  linked per plugin, and pushes the quick start below the fold. The README "Docs" list renders
  paths as code rather than links and omits `startup-context.md`.
- **Files:** create `docs/README.md` (map), `docs/install-and-upgrade.md`, `docs/plugins.md`,
  `docs/components.md`, `docs/when-to-run-what.md`, `docs/scenarios.md`, `docs/neighbours.md`;
  move the generated regions (generator `REGIONS` plus its contract test); add a one-line audience
  header to each existing guide ("For: adopters", "For: maintainers", "Explanation", "Reference").
- **Acceptance:** every guide under `docs/guides/` is reachable from `docs/README.md`; the generator
  check passes on the new targets and the contract test covers them; no section of the old README
  is lost.
- **Depends on:** nothing (can land before WP3; the README then links to it).

### WP6. Make the CHANGELOG readable by a user upgrading

- **Failure removed:** `CHANGELOG.md` is 65,136 words. A single bullet routinely runs 300+ words of
  implementation detail (marker bumps, mutant counts, review rounds). A user upgrading cannot find
  what changed for them, what breaks, or what to do; the Keep a Changelog first principle
  ("changelogs are for humans, not machines") is not met.
- **Shape:** per release, a short user-facing section in Keep a Changelog groups (Added, Changed,
  Deprecated, Removed, Fixed, Security), each bullet one or two sentences with impact and any
  action required, plus an "Upgrade notes" block when a dependency or behaviour changes. The
  engineering detail is not deleted: either keep it under a collapsed `<details>` per release or
  move it to `docs/changelog-detail/<version>.md`, linked. Add compare links per version.
- **Decided (maintainer, 2026-10-30):** separate files under `docs/changelog-detail/`, as
  recommended: the root file then stays scannable and the detail stays greppable.
- **Files:** `CHANGELOG.md`, new `docs/changelog-detail/`, and the `release` skill's guidance only if
  it prescribes the current shape (check before changing a component).
- **Acceptance:** the Unreleased plus latest three releases fit in a screen or two each; every
  release has a date and a compare link; no information lost.
- **Depends on:** nothing.

### WP7. Keep the numbers true: generate or delete every count in public prose

- **Failure removed:** hand-written counts in public docs rot ("thirty closed phases", "292
  plugins", "six collisions", "103 to 529 lines", "173 lines", "Eleven references", "about 240
  lines", "Claude Code 2.1.310"). This is the exact defect class #96 fixed for the inventory, still
  open for prose.
- **Shape:** for each count, either delete it (the default when the sentence works without it),
  date it ("measured 2026-10-30"), or generate it the way the component index is generated. A
  cheap guard is a doc check that flags an undated bare number next to words such as "plugins",
  "phases", "lines" in README and `docs/*.md`; decide whether it is worth a guard or a review
  checklist item.
- **Files:** README and the moved docs; possibly a new `scripts/check-doc-counts.sh` plus its test
  and validate step.
- **Acceptance:** no undated, ungenerated count remains in README or the user-facing docs.
- **Depends on:** WP3 and WP5 (do it on the final text).

### WP8. Label the working records for what they are

- **Failure removed:** `docs/plans/` (46 files, about 50,000 words) and `docs/superpowers/` (10
  files) sit beside the user guides with names like `the-sentence-that-matters-more.md`. A visitor
  browsing `docs/` cannot tell they are the project's own history, not instructions.
- **Shape:** add `docs/plans/README.md` and `docs/superpowers/README.md` explaining what they are,
  with the roadmap as the index; keep the paths (see Constraints). Each index row gives a
  descriptive title, date and status (shipped, superseded, abandoned), because filenames name the
  occasion rather than the subject (Codex). **Decided (maintainer, 2026-10-30):** keep
  `docs/plans/` at the convention path; Copilot's move under `docs/maintainers/` is not taken. Optionally rename
  `docs/superpowers/` to make its purpose obvious, only after checking what references it.
- **Acceptance:** each directory opens with an explanation on GitHub; `docs/README.md` lists them
  under "Project history".
- **Depends on:** WP5.

### WP9. Per-plugin discoverability

- **Failure removed:** in the `/plugin` panel a user sees only each group's one-line `description`;
  there is no per-plugin README, so nothing tells them what a group acts on, what it needs, or
  how to switch on its opt-in hooks. Two catalogue descriptions are cut mid-word by the generator
  ("masked-exit-adviso…", "ships th…").
- **Shape:** `docs/plugins.md` (WP5) is the reference; additionally decide whether each
  `plugins/<group>/README.md` should exist (generated from the same source, so it cannot drift);
  shorten the long `plugin.json` descriptions so the catalogue never truncates; add `homepage`
  and `keywords` to each `plugin.json` if the schema accepts them.
- **Acceptance:** no truncated description in the generated catalogue; every group's description
  says what it does in one sentence.
- **Depends on:** WP5.

### WP10. Show, do not only tell

- **Failure removed:** nowhere in the public docs can a visitor see what forge-kit produces before
  installing it.
- **Shape:** a short recording or a static excerpt of a real `/gate-ticket` run and its posted
  review (link the live issue), one of `forge-adapt` recommending components, and one of a guard
  failing a build. Store media under `docs/media/`.
- **Acceptance:** the README's "What it looks like" section links a real example.
- **Depends on:** WP3.

### Ideas recorded, not yet packaged

From the external reviews, worth a ticket only if the maintainer wants them:

- A disposable demonstration repository with an incomplete ticket, its gate result, the corrected
  ticket and an armed guard (Codex, Copilot).
- A read-only install diagnostic: installed and enabled groups, missing dependencies, forge auth,
  project markers, active guards, each linked to its fix (Codex). `health-check` is the natural home.
- A compatibility matrix: tested Claude Code version, OS, shell and forge (Copilot).
- A troubleshooting page built from real failures (Copilot; part of WP5's `install-and-upgrade.md`).
- A periodic newcomer test: someone new installs, gates, upgrades and removes using only the public
  docs, and every place they stick becomes a doc change (Codex).
- Codex's deeper `tutorials/ how-to/ reference/ explanation/` tree. Not adopted: Diataxis warns
  against restructuring mechanically, and the flatter WP5 tree reaches the same reader split.

## Order

WP1, WP2 and WP4 are done (2026-10-30). Next WP5, then WP3 (the README rewrite needs its
destinations), with WP6 in parallel. WP7, WP8 and WP9 follow on the final text;
WP10 last.

## Fails if (premortem)

- The README rewrite drops a paragraph a user relied on (the dependency upgrade note is the most
  likely casualty). Guard: WP3's acceptance diffs the section list against the old README.
- The generated regions move and CI stops checking them because the generator skips a missing
  file with a notice. Guard: WP5 moves the region and its contract test in one commit, and the
  test asserts the new file is present.
- The CHANGELOG reshape deletes history someone links to. Guard: detail moves, never disappears.
- New counts creep back into the shortened README. Guard: WP7.
- The work stalls on the license choice. Guard: WP1 is a one-line decision, asked first.
