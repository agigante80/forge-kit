# Changelog

Umbrella versions for the forge-kit marketplace as a whole. Individual plugin groups carry their
own semver in `plugins/<group>/.claude-plugin/plugin.json` and move independently; see
[docs/guides/versioning.md](docs/guides/versioning.md) for what each version level means.

Note that a release tag does not gate distribution. `/plugin marketplace add agigante80/forge-kit`
tracks the repository, so users are already served from the default branch.

## Unreleased

### Added

- **Cross-group dependencies are declared in `plugin.json`, not only in prose** (#169). Installing
  `forge-kit-roadmap` alone now brings `forge-kit-devops` with it, probed on CLI 2.1.267. The
  declaration lives in two places on purpose: the manifest for the marketplace path, the prose for
  the bare clone, where nothing resolves anything. `validate-plugins.sh` checks what the CLI does
  not, because an UNRESOLVABLE dependency passes `claude plugin validate` and then installs
  silently, with no dependency line and no error.
- **Every `plugin.json` carries an `author`** (#173), so the advisory `claude plugin validate` step
  reports zero warnings instead of eight nobody read. A handle and its profile URL, no email
  address: the handle is already public in every clone URL, and an address cannot be recalled from
  a public history. `validate-plugins.sh` requires the field, in the CLI's own shape (an object
  with a non-empty name), so a new group cannot be born without it.
- **`scripts/check-reference-depth.sh`**: a skill's `references/` file must be named by its own
  `SKILL.md` (#175). The rule is Anthropic's and its reason is mechanical: an agent meeting a
  reference inside ANOTHER reference may preview it rather than read it whole, so it acts on half a
  file and nothing reports that it did. Three files in this tree were already unreachable, one of
  them the exact nested shape the guidance describes.
- **`scripts/test-validate-plugins.sh`**: the kit's oldest structural guard finally has a contract
  test, created because two tickets needed to add rules to it in the same week.
- **The size guard measures the ALWAYS-ON cost** (#174), the description every session pays for a
  component it never invokes. Reported and not budgeted, because a description that is too short
  stops the component being found; what is enforced is the floor, an agent or skill with no
  description at all. The tree went 14,711 to 12,339 characters of description with all 48 quoted
  trigger phrases intact, by deleting sentences that described how a component works and that its
  own body already said.

- **`decision-brief`, a skill for the ticket that is stalled on a human rather than on work**
  (#129). It re-gates the ticket against the CURRENT standard rather than citing a stored verdict,
  checks the ticket's claims against the tree before presenting anything, classifies what is
  actually being decided (including "no decision needed", which is a real outcome), costs the
  options with measured numbers, and REWRITES the issue body behind a dated preamble rather than
  leaving the analysis in a comment nobody opens while triaging. `check-restatements.sh` scans its
  file, so its promise to run the gate rather than copy the gate's bars is a build failure rather
  than a sentence.
- `forge_issue_edit <n> <body>` in `forge-lib.sh` (v13), the library's first body write. Both hosts
  PATCH the issue, so there is no host branch; it refuses an empty body and sends nothing under
  `FORGE_DRY_RUN`, because it is the one call there that destroys what was already written.

### Changed

- **`claude plugin details`'s token cost is a dated cross-check, not the metric** (#170). Probed:
  it does NOT charge an agent for the companion skills it preloads (a companion grown to 5,000
  words moved the agent's figure by nothing), which is the quantity #150 spent a phase
  establishing. It also rounds to two significant figures. The comparison is recorded with its
  date and CLI version, and a test fails if it loses either.
- **No per-plugin git tags, and `claude plugin tag` stays out of the release lane** (#171). Probing
  it disproved the ticket's own premise: the agreement it validates fires only when a marketplace
  entry carries a version, and forge-kit's deliberately do not, so the check is vacuous here and is
  a different invariant from `check-plugin-version-bump.sh` rather than a duplicate of it.

- **The overnight loop honours the iteration contract it was already calling** (#88). It chains
  rounds with `--since` instead of re-reviewing the whole target every cycle, and it DEFERS on the
  trip wire instead of deciding for the absent human: findings are ticketed, the item is parked with
  the loop's stopping data, and the park leads the morning report. A hard stop is deliberately not a
  defer, because the contract offers no decision there.

## v0.2.0 (2026-09-09)

Two new plugin groups, a leak guard for the moment a private repository is made public, and the
week the guards stopped being taken at their word. The recurring lesson of this release is in the
last group: a guard was wrong on its own first run against this tree more than once, and every
fix in it was verified by breaking the code and watching the test fail.

### Added

- **`forge-kit-roadmap`, an optional eighth plugin group** for rolling wave planning (#160). A
  roadmap owns which PHASES exist and what state each is in; the host owns which phase each ticket
  is in, as the milestone. Different facts, so neither duplicates the other. A phase's plan is
  written when the phase OPENS, never for the whole roadmap at once, and a `planned` phase is a
  bucket you may file tickets against. `check-phases.sh` enforces four rules and `sync-phases.sh`
  reconciles the roadmap with the host's milestones. Deliberately its own group, so a project using
  any other planning method loses nothing by not installing it. forge-kit now runs on it (`docs/roadmap.md`).
- **A leak guard for the public-repository moment** (#155, #156, #157), shipped as the
  `leak-guard` skill in `forge-kit-security`. The public half finds home paths BY SHAPE, `~/` roots
  by allowlist, and email addresses, needing no secret and no configuration, so it runs in CI. The
  private half checks an identity list held OUTSIDE the repository
  (`~/.claude/forge-kit/private-names.txt`) and redacts its own output by default, because a scanner
  that prints what it found is a leak with a progress bar. A machine with no list is told loudly
  that names are not being checked rather than passing quietly.
- **Components declare whether they belong at user level or in a project** (#164, #165), with
  `scope: user` the default and `scope: project` requiring a `scope-reason`. **forge-adapt now
  REGISTERS a user-scoped component instead of copying it** (#166): a registered component owns no
  user config, so it cannot drift, duplicate or clobber, which is the copy-and-mutate path CLAUDE.md
  blames for every hook bug in this repo's history. `drift` gained a `registered` state so a correct
  install no longer reads as missing and invites the copy back (#167).
- **The gate's verdict lives in the ticket body, in an addressable block** (#130, #102), rather than
  only in a comment nobody reads back. The review stays a comment; the state does not. Every body
  region the gate writes now has ONE lifecycle (#145), and the author sections it touches are
  written once or not at all (#147).
- **Step 3A's mechanical checks are a tested script** (#149), `check-ticket-mechanics.sh`, replacing
  544 words of prose with 41 contract tests. It emits one row per check and never decides a verdict:
  where it cannot rule mechanically it emits `referred` and the critic rules instead, because its
  heuristics are deliberately narrower than the canonical rules. Its first run caught the bug that
  argues for the test: the literal `N/A` matched a "contains a slash" path test.
- **An orchestrator word budget, stated rather than left as an exemption** (#150). An agent whose
  `tools:` declares `Agent` gets 4000/6000 instead of 2000/3000, because a coordinator carries the
  briefs it dispatches as well as the rules it obeys. Membership is mechanical, so it cannot rot
  into a maintained list.
- **All round behaviour for `ticket-gate` in one table** (#103), replacing six scattered re-run
  policies. A new step or lens needs a row. Also `check-lens-contract.sh`, which fails the build
  when the lens result contract drifts between the two plugin groups that share it, treating a
  MISSING marker as skew rather than agreement.
- **`sync-labels` reaches a GitHub-only project** (#120) and gained milestone primitives in
  `forge-lib.sh` for the roadmap group's host rules.
- Four guards that did not exist: `check-restatements.sh` derives the doc's Precedence list
  mechanically instead of letting it certify its own completeness (#125), and found a tenth
  restatement on its first run; `check-producer-stamps.sh` fails any component that hardcodes a
  `template-version` stamp, with no allowlist (#84); `check-template-dir-order.sh` keeps the six
  copies of the template-dir order identical (#77); `check-component-scope.sh` and
  `check-live-placeholders.sh` keep #164's declarations and #163's placeholder removal honest.

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
- **`ticket-gate.md` deduplicated where it genuinely repeated** (#109, partial): 5715 to 5680
  words. The `references/` split it also proposes was blocked at the time on #124, which this
  release also closes. The canonical doc's restatement list gained six entries and STOPPED
  claiming to be complete: three review rounds each found it incomplete, so it said so and
  pointed at a guard ticket instead of certifying. That guard is #125, below.
- **The label taxonomy has an applier and a checker** (#104). `forge-host/assets/sync-labels.sh`
  syncs `.github/labels.yml` to the host or reports drift with `--check`. Host-aware, idempotent,
  and it never deletes an undeclared label. It was declarative with no applier for months: 18
  labels declared, 4 present, including `security`, `critical` and `api`, which are executable
  inputs to the gate's lens routing.
- **No jurisdiction is named in any forge-kit default** (#101). Rule 4 becomes "Personal data
  handling" with seven regime-agnostic facts, and the regime ships as an opt-in
  `privacy-regime` skill (forge-kit-security) dispatched by the new `privacy` label. Templates
  bump v5 to v6: the field `id` moves `gdpr` to `personal_data`, and Step 0c gained a rule to
  recover it from a pre-v6 ticket's old heading. `forge-adapt` offers the skill on a
  personal-data signal and never installs it silently.
- **The six gate-only bars moved into the canonical doc, and Precedence gained a third rule**
  (#94, question 1). `ticket-standards.md` rule 2 now enumerates the three auth cases, rule 4
  names encryption at rest and cascading deletion, and a new rule 8 covers implementation and
  dependency concreteness against fields the templates already collect (so no `template-version`
  bump). Precedence now enumerates the REAL restatement set (it wrongly claimed the hard-fail
  bars were the only one) and distinguishes a stricter gate restatement, which is advisory and
  reported as a doc gap rather than blocking, so a gate copy cannot silently out-rule the doc.
- **forge-lib hardening** (#78). The config is parsed once per repo root instead of about four
  times per paginated page; `forge_api` reports the HTTP status as an exit code (44 for 404, 22
  otherwise) instead of `curl -f` flattening everything into 22 with no body, so
  `forge_issue_label` no longer reports an ordinary org-404 as an access failure; and temp files
  live in one per-process directory cleaned by an EXIT trap that is installed only when the
  caller has none. The asset's header now carries a CONTRACT CHANGES list, so a `refresh` diff
  says whether a caller has to change.
- **sync-labels hardening** (#121, #122). It now refuses an unterminated quoted
  value, a duplicate declared name and an empty flag value rather than accepting each silently;
  it builds the host lookup in ONE jq pass instead of three or four per label (62 processes to 3
  for 20 labels); It refuses to run on bash 3, where the associative-array lookup fails with an exit code this
  script reserves for "drift found", so automation would retry forever. And a newline in a HOST
  description no longer splits the record and reports real drift as in-sync. #120 is not included;
  see that ticket.
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
  match. This was the first of several reductions in this release; see Changed for where the
  number ended up, and #150 for why the number it was measured against was wrong.
- A splitting convention for components that outgrow the budget, naming the main file as canonical
  so a split cannot restate a rule in two places.

### Changed

- **Work lands on `develop` and merges to `main`. There are no pull requests.** Both range guards
  were `pull_request`-only, so the change silently left them running on no path at all; #158 moved
  them to `push` and gave them a shared base resolver.
- **The six live `{{GITHUB_REPO}}` uses are gone** (#163), replaced by the `forge_repo` resolution
  those same files already used elsewhere. That install-time placeholder was the only thing pinning
  components to one project, which is what made #166's registration possible.
- `ticket-gate.md`'s reference artifacts moved into a companion skill and then, in the parts that
  are read once rather than preloaded, into `references/` beneath it. 6355 words to 5778, with no
  capability dropped.
- `parse_roadmap` is shared between the two roadmap assets (#162), and the precedent that was
  cited for duplicating it is recorded as not applying.

### Fixed

- **`overnight-guard` blocked branch switching, and blocked writing ABOUT the commands it guards**
  (#168). Its patterns used `[^|;&]*`, which crosses newlines, so a command on one line matched a
  fragment on another. Found by arming an overnight run against this repo's own workflow.
- **Two guards walked the working tree instead of the tracked file set** (#140, #142), so an
  untracked leftover failed a build CI would never see. Fixed together, through a shared helper;
  their FALLBACKS are deliberately not shared, because the two mechanisms differ.
- `forge-lib`'s key-based config tracking cleared a caller's own exported variable (#131).
- `forge-adapt-agent-skills` corrupted rather than refused on symlinked agents and on mapping items
  it did not understand (#134), which matters because a declared-but-missing companion skill fails
  SILENTLY at runtime.
- `check-template-dir-order` reported the wrong line for the second copy in a merged run (#143).
- `sync-labels` test gaps and two behaviour changes left by the #121 lookup rewrite (#127).
- `check-restatements` gained per-item rule coverage and handling for wrapped references (#138).
- The leak guard's public half judged the first path segment only, and the segment below it is the
  worse half of the leak (#159). Closed as working-as-intended by maintainer decision, with the
  limit documented beside the reach statement it qualifies rather than the claim quietly narrowed.

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
