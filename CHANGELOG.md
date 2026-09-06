# Changelog

Umbrella versions for the forge-kit marketplace as a whole. Individual plugin groups carry their
own semver in `plugins/<group>/.claude-plugin/plugin.json` and move independently; see
[docs/guides/versioning.md](docs/guides/versioning.md) for what each version level means.

Note that a release tag does not gate distribution. `/plugin marketplace add agigante80/forge-kit`
tracks the repository, so users are already served from the default branch.

## Unreleased

### Added

- **The component inventory is generated from the tree** and CI fails on a stale region (#96).
  `README.md` and `CLAUDE.md` carry marker-delimited regions filled by
  `scripts/update-component-index.py` from `forge-adapt-catalogue.sh --tsv`. It was already stale
  when this landed: the README claimed 14 skills and omitted `mutation-sweep`. Do not hand-edit
  inside the markers.
- A hand-written "when to run what" sequencing table in the README, deliberately not generated.
- `--tsv` mode on `forge-adapt-catalogue.sh`, adding the file path for machine consumers. The
  default output is unchanged and byte-stable, because forge-adapt reads it.
- **A component size budget** with visible word counts (#97). `scripts/check-component-size.sh`
  warns above a per-type word budget (agent and command 2000, skill 2500), fails above a hard
  ceiling of 1.5x, and holds the three already-oversized components (`adapt`, `ticket-gate`,
  `full-review`) to a **ratchet**: they may shrink freely and may not grow. Word counts are a
  column in the generated index. A test fails if CLAUDE.md's documented numbers and the script's
  enforced numbers disagree. Framed as a smell detector, not a quality metric.
- **`ticket-standards.md` carries two version markers instead of one overloaded integer** (#94,
  question 2). `template-version` says which FORM the doc describes and stays locked to the five
  work templates; the new `doc-rules-version` says which revision the RULES TEXT is at and moves
  freely. Before this, a prose clarification implied a `template-version` bump, which forced the
  templates along and made `ticket-gate` re-synthesise every open ticket, so a clarification cost
  a migration. That is why the gate and the doc were allowed to fork.
- **Every shipped executable now has a contract test, and all of them run in CI** (#76). The last
  two gaps were `version-lib.sh` (19 tests: the four verdicts, fail-closed paths, and the
  prerelease and sibling-branch traps its own comments call out) and `release-run.sh` (19 tests
  of the lane policy, driven with `DRY_RUN=1` so no forge is touched). `test-closing-sessions-memory.py`
  was also wired in; it existed but nothing ran it on a PR.
- **The enforced path set now agrees across all four consumers** (#112). `validate-plugins.sh`
  used `find -path`, where `*` crosses `/`, so it matched component paths at ANY depth while
  the other three matched one level. A nested reference file would have been required to carry
  a version marker that the catalogue could never see. It now shares the same ERE as
  `check-version-bump.sh` and `.githooks/pre-commit`, and `scripts/test-component-paths.sh`
  fails if the four ever disagree again. Latent before this: no component had a subdirectory.
- **The local hooks are split by stage** (#98 item 3). `.githooks/pre-commit` keeps the staged
  checks; the new `.githooks/pre-push` runs the range guards against the remote's default
  branch, the same question CI asks on a PR. It is the only local gate on a direct push to
  main, which both range guards miss by being `pull_request`-only. Skips are loud and never
  block a push. Same one-time enablement: `git config core.hooksPath .githooks`.
- **`ticket-gate.md` rules now live at the step they govern** (#109, partial). Rules went from
  17 bullets to 6 cross-cutting ones; 5794 to 5726 words, with the ratchet baseline lowered to
  match. The `references/` split that ticket proposed is blocked by #112.
- A splitting convention for components that outgrow the budget, naming the main file as canonical
  so a split cannot restate a rule in two places.

## v0.1.0 (2026-09-06)

First tagged release. 270 commits since 2026-04-23, previously untagged.

**40 components across 7 plugin groups:** 14 subagents, 15 skills, 4 commands, 4 hooks, and 3
versioned shell assets.

| Plugin group | Version | Components |
|---|---|---|
| `forge-kit-governance` | 0.7.11 | 7 |
| `forge-kit-devops` | 0.6.6 | 12 |
| `forge-kit-adapt` | 0.3.4 | 1 |
| `forge-kit-review` | 0.3.3 | 7 |
| `forge-kit-security` | 0.2.2 | 4 |
| `forge-kit-testing` | 0.2.1 | 4 |
| `forge-kit-backend` | 0.1.0 | 5 |

### Governance

- **`ticket-gate`**, the readiness gate: deterministic mechanical checks plus one critic agent
  returning PASS, NEEDS-WORK, or BLOCKED, with label-routed lenses. This replaced an earlier
  5-agent 10/10 scoring committee, which produced a number rather than a decision.
- **Ticket standard v5** across the five work issue templates: GWT scenarios, unit and E2E test
  specs, GDPR considerations, security checklist, documentation impact, required reviews.
  `ticket-gate` auto-synthesizes missing sections from earlier-version tickets.
- **The rules live in one place.** `docs/guides/ticket-standards.md` is canonical; the templates
  carry only form fields, and `check-template-lockstep.sh` keeps the two on one shared version so
  they cannot drift apart.
- **`working-overnight`**: governed unattended work, shipped as branch-plus-PR and never merging,
  deferring you-only decisions instead of guessing. Backed by the `overnight-guard` hook for
  mechanical enforcement and `overnight-continue` for resumption.
- **`closing-sessions`**: persists durable facts and resume state before a session ends.

### forge-adapt

The entry point, and the only component a project installs by hand.

- Recommender-style flow: analyze the project, recommend the top 1 to 2 components per category
  with a short reason each, install and adapt the chosen ones to the stack.
- **Secondary modes**: `drift` reports which installed components lag forge-kit by marker
  comparison and writes nothing; `refresh <name>` deep-compares one component and merges in
  improvements while preserving project adaptation, report-first and never blind-overwriting;
  `contributions` surfaces project-only components worth contributing back; `templates` audits
  issue templates and can install the repo-level template governance.
- **Superpowers coexistence mode**: where the obra/superpowers plugin is present, superpowers owns
  the inner loop and forge-kit the outer loop, applied at install time rather than argued about.
- The component catalogue ships as a tested script the skill runs verbatim, because an LLM
  executor kept reintroducing fixed bugs when it paraphrased an inline block.

### Review, security, and testing

- `code-reviewer`, `architect-review`, `backend-architect`, `code-simplifier`,
  `coding-standards-auditor`, and the 5-phase `/full-review` command, positioned as a pre-merge
  audit rather than the per-task reviewer.
- **An iteration contract for review loops**, with a reporter and loop-owner split, a `--since`
  delta round, and a trip wire for bad-fix injection. Review-until-green has no natural end; this
  bounds it.
- **The assertions-that-cannot-fail dimension** for rotten-green tests. It found a real defect in
  this repo's own test suite within days of shipping.
- `security-auditor`, `backend-security-coder`, `api-security-tester`, and the
  `owasp-api-security` skill.
- `tdd-orchestrator`, `test-automator`, `performance-engineer`, and `mutation-sweep`, which
  targets coverage's blind spot: tests that cannot fail.

### DevOps and host awareness

- **`forge-host`**: a `forge_*` adapter making governance host-aware across GitHub and Forgejo, so
  components call one interface rather than hardcoding a host. Includes the
  `github-to-forgejo` migration playbook and the `block-legacy-host-push` hook, which is installed
  project-locally only and deliberately ships no `hooks.json`.
- **`release`** and **`release-automation`**: the invoked ship and its enforced sibling, a CI gate
  blocking a merge unless the version moved past the last release, built on a shared
  version-to-tag primitive.
- `dep-auditor`, `health-check`, `find-dead-code`, and the `/ci-health` command.

### Backend knowledge

`api-design-principles`, `architecture-patterns`, `microservices-patterns`,
`cqrs-implementation`, and `saga-orchestration`.

### Enforcement machinery

The part that makes the rest hold. Three enforcement points share one marker-parsing rule:

- `validate-plugins.sh` (structure, semver, marker presence), `check-version-bump.sh` (a changed
  component must bump its marker), `check-plugin-version-bump.sh` (a changed group must bump its
  `plugin.json` semver), `check-template-lockstep.sh`.
- **Five contract suites in CI** covering every shipped executable that has a real contract, plus
  the repo's own guards.
- A committed `.githooks/pre-commit`, opt-in per clone, covering the same rules locally, since
  both range guards run at PR time only.
- **`block-dashes` runs against this repo itself**, deliberate dogfooding of a governance hook.

### Hook install model

Hooks reach a project three ways, and the script tells them apart by its own path shape rather
than by environment variables: plugin-level registration gated on a project opt-in file, a
project-local copy that is itself the opt-in, and this repo running a hook against its own tree.
Plugin hooks gate in the shell rather than the interpreter, 1.8 ms against 44 ms per unmatched
call, because a plugin hook is live in every project. Every hook bug in this repo's history came
from the copy-and-mutate path, which is why plugin registration is preferred where it applies.

### Known gaps at this release

Tracked and open, listed so the release is not read as claiming more than it does:

- `closing-sessions/scripts/memory.py` is the one shipped executable with no CI test and no
  version marker, because `skills/*/scripts/` is outside the enforced path set. Its test exists
  and must be run by hand.
- `release-automation`'s two shell assets have no contract tests.
- The component inventory is hand-maintained in several places with nothing checking it against
  the tree (#96).
- The local hook still runs range checks at commit time rather than at push (#98, item 3).
- forge-kit ships no guard against a developer's home paths or private project names leaking into
  a repository it governs (#99).
