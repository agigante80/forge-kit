# Changelog

Umbrella versions for the forge-kit marketplace as a whole. Individual plugin groups carry their
own semver in `plugins/<group>/.claude-plugin/plugin.json` and move independently; see
[docs/guides/versioning.md](docs/guides/versioning.md) for what each version level means.

Note that a release tag does not gate distribution. `/plugin marketplace add agigante80/forge-kit`
tracks the repository, so users are already served from the default branch.

## Unreleased

### Fixed

- **The mechanical checks find a section at either heading level, bounded by labels rather than
  by a level** (#190). `gh issue create --body-file` produces `##` headings, and the checker, keyed
  on `### ` alone, read a doc-compliant `##` body as five absent sections where the same body at
  `###` got two and a referred: a heuristic miss that inverted the verdict instead of referring it.
  A first fix detected one level per body; the gate found `dep-auditor` emits `### Priority` beside
  `##` sections, which that rule inverted the same way. A section now runs to the next heading at
  its own level or the next heading that is a template label, so a `###` subsection is content and
  a `### Priority` beside it is a boundary. No content check moved. `forge-gate-mechanics.sh`'s
  never-template-shaped notice keys on the same signal, and the worked example in
  `without-claude-code.md` was re-measured: #182's documentation impact passes on content and its
  GWT fails on content.
- **Concurrent gate runs no longer share one body file by name** (#197). Step 1 writes the fetched
  issue to `<scratchpad>/gate-<NUMBER>/` and Step 3A refuses, posting nothing, when that file's
  `.number` is not the run's argument. Three runs in one session had read each other's bodies
  twice and were saved both times by a reviewer reading the evidence column.
## v0.5.0 (2026-09-11)

The release where the gate was pointed at the repository that ships it, and at itself. Twelve
gate runs across two phases found the label taxonomy blocking every ticket here, a resolver that
picked a stale copy of its own checker three runs in four, and a round counter that any body edit
reset to one. All three are fixed and the mechanical half of the gate now runs without Claude Code
at all. Minor rather than patch: two `forge-lib.sh` contract changes (v14 adds
`forge_issue_comments`; v15 makes `forge_ci_status` say `cancelled` and reserves `not_configured`
for "could not ask", which `release` acts on), two new shell assets, and a new guide for teams on
another agent or none. Ten tickets.

### Added

- **The mechanical half of the ticket gate runs without Claude Code** (#182).
  `forge-gate-mechanics.sh` fetches an issue through `forge-lib.sh` on either host, resolves the
  template directory, and hands both to `check-ticket-mechanics.sh`, which already had 41 contract
  tests. It never prints a verdict: Step 3A is the mechanical half, every `referred` row is a check
  that could not rule, and a summary saying PASS would look like the real gate with the reading half
  skipped.
- **`forge-gate-mechanics.sh` reports an unsynthesised body once rather than as seven failures**
  (#184). The gate's Step 0c synthesises the missing sections and writes the enriched body back to
  the forge BEFORE the mechanics run, so inside a gate run the checks always see template-shaped
  input and the blocking rule holds. A raw hand-filed ticket now opens with a `never
  template-shaped` notice and exits 0, because that shape is not a defect in the ticket. The shape
  needs BOTH signals, no marker AND no `### ` heading, since either alone is a different situation.
- **`docs/guides/without-claude-code.md`** (#183), the entry point for a team on another agent or
  none: the four portable artifacts, what to copy, what to run with real output, and a table of what
  is not available. `AGENTS.md` now distinguishes its two audiences rather than serving only
  contributors.
- **A finding names an instance, so `code-reviewer` sweeps for its family** (#187). Inside the files
  the diff touches, each instance is treated per the iteration contract's severity rule. Outside
  them, do not fix it **and do not confirm its extent**: naming a suspicion needs no scan, and
  establishing how far it reaches is the scan this agent does not do. The out-of-target list now
  exists in every round, not only round 2+, which is a gap the rule exposed.
- **The overnight loop asks whether a ticket is still true** before implementing it (#186), as a
  step 0 in the per-item pipeline. Implement or park, nothing else, and a PARTLY fixed ticket parks,
  because implementing only the surviving criteria is re-scoping. The check is specified as the Grep
  and Read tools rather than shell greps, and that is a security decision: `overnight-guard.py`
  matches its patterns inside a quoted search term, so a shell grep for a ticket quoting `git reset
  --hard` is denied and records a destructive-command deferral that never happened.
- **`scripts/check-label-taxonomy.sh`** (#188): one definition of the area label set, and a guard
  that fails when a copy disagrees. `ticket-gate.md` restates the set nowhere and the guard fails if
  a copy returns, because a synchronised copy is one edit from a drifted one. Three area labels now
  describe this repository's own work (`components`, `tooling`, `governance`), without which every
  ticket filed here blocked at the gate.
- **The gate counts its rounds from posted review comments, never from the issue body** (#192).
  `count-gate-rounds.sh` prints the round the next run should use, and `forge-lib.sh` v14 gains
  `forge_issue_comments` for it. The body's `gate-verdict` block used to carry the number, and any
  ordinary body edit erased it, so the gate believed every round was round 1: delta scope never
  engaged and a caller's trip wire, which counts rounds, could never fire. A stopping rule that
  cannot fire is worse than one that is absent, because it is believed in. The block is now a
  projection of the count, every review comment states its `**Round:**`, and 29 contract cases pin
  what counts as a round and what does not.

### Fixed

- **`forge_ci_status` on Forgejo tells a superseded run from a broken one, and a queued run from
  no CI at all** (#193, a downstream contribution). The combined commit status flattens a
  cancelled run to `failure`, so pushing twice in quick succession left a healthy branch red with no
  failing step anywhere: wrong on 23 of 39 red commits in the sample the ticket measured. The fix
  reads the per-job `description` Forgejo already returns ("Has been cancelled"), so the red path
  makes no second request and an unknown string falls to the old answer, never to a false green.
  The paginated `/actions/tasks` walk the downstream copy carried was not ported: under a
  server-clamped page it reported `cancelled` with a failure on the next page. `total_count == 0`
  is now `pending` or `none` rather than `not_configured`, which is reserved for "could not ask";
  `release` stops on `none` ("wait, or confirm there is no CI") and on `cancelled` ("re-dispatch"),
  and falls back to its local gate only when the forge could not be asked. `forge-lib.sh` v15,
  30 contract cases, ten named mutants killed.
- **A shipped asset is resolved by its version marker, never by the first `find` hit** (#189).
  `~/.claude/plugins` holds plugin versions side by side, so `find ... | head -1` returned an
  arbitrary copy, and on the filing machine three different ones in three consecutive runs, one of
  them stale enough to contradict #188 during a live gate. `ticket-gate.md` Step 3A, `/phase`, and
  the last-resort search in `check-phases.sh` and `sync-phases.sh` now prefer a project copy, then
  a forge-kit checkout's own tree, then the highest `<name>-version` marker with the path as
  tie-break, and every one of them prints the copy it chose. Two contract cases pin the shell half.
- **Both halves of the leak guard now state that they never look at history** (#185). Every mode
  reads the working tree, the index, or two endpoints of a range, so a leak committed once and
  removed later is unreached, which is exactly the going-public moment the component is named for.
  The private half had carried no reach statement at all. Both also say they read file content only:
  a commit message is unreached, and this repository's store holds 527 commit objects. The skill
  names `gitleaks` for the credential class, which this guard does not cover.

## v0.4.0 (2026-09-10)

The release where forge-kit stopped shipping other people's files. Five components here turned out
to be, after normalising away the name and the version marker, between one and ten lines from the
originals in `wshobson/agents`, which is where this kit's specialist agents came from. Eleven
components and one whole plugin group are gone, each naming its replacement, and a guard now fails
the build if another one appears.

The boundary that made those retirements obvious was itself only a paragraph in a skill until this
release. It is now checked twice: at build time by `check-neighbour-overlap.sh`, and at install time
by forge-adapt, which knows about both neighbours rather than only superpowers. The README was
rewritten around what the tree actually is, a governance harness for the outer loop, rather than the
component library it started as.


### Added

- **`scripts/check-neighbour-overlap.sh`**, which fails the build when a component here is the same
  file a neighbouring marketplace ships (#177). A DUPLICATE fails; a COLLISION, the same name with
  different content, is reported and never fails, because `code-reviewer` is a name anyone would
  pick. The threshold is measured rather than chosen: duplicates differ by 1 to 10 lines and the
  nearest genuine divergence is 103. Evidence lives in `docs/neighbours.tsv`, refreshed by
  `scripts/neighbour-manifest.sh --refresh`; the guard reads only the checked-in file, so CI needs
  no plugins installed.
- **The README names the plugin groups and how to install one.** A generated `plugin-catalogue`
  region gives one row per group: its semver, a copy-pasteable `claude plugin install` command, and
  the group's own description. Until now the install command for a group existed nowhere in the
  docs, so finding one meant reading `plugin.json`.

- **forge-adapt's coexistence rule covers both neighbours** (#179), in one tested script rather
  than a table in a skill. It returns `recommend`, `caveat` or `suppress` with a reason, judging
  the pair and never the name: `code-reviewer` exists on three sides as three different agents.
- **`validate-plugins.sh` fails a build where a component dispatches a `subagent_type` no agent
  provides** (#180). That failure is silent at runtime, and #178's retirement of six agents made it
  possible. Agent names stay unprefixed: Claude Code already namespaces subagent types by plugin,
  and the reason is recorded so the question is not re-asked.
- **The size report shows a line count beside the word count** (#176), marking anything over the
  500-line tip Anthropic states for a skill body. Reported and never budgeted: `adapt`'s 20 fenced
  blocks were classified first, and sixteen are commands the skill runs while four are templates it
  emits, so none of them can move without making the caller depend on a copy. The file is the size
  the work is, and the reasoning is in the guard rather than in a closed ticket.
- **The README was rewritten around what forge-kit actually is** (#181): a governance harness, the
  outer loop, with the three-way neighbour table, ten Given/When/Then scenarios, the overlap stated
  rather than discovered, and a real path for a team not using Claude Code.

### Removed

- **Eleven components retired, and one whole plugin group** (#178), because each was the same file
  `wshobson/agents` ships and forge-kit had not changed it. `forge-kit-backend` is gone entirely
  (`api-design-principles`, `architecture-patterns`, `cqrs-implementation`,
  `microservices-patterns`, `saga-orchestration`); so are `tdd-orchestrator`, `test-automator`,
  `performance-engineer`, `backend-architect`, `backend-security-coder` and `/pr-enhance`. Every
  one names its replacement, all of them in `claude-code-workflows`. There is no deprecation field
  to use: probed on 2.1.267, both `deprecated` and `supersededBy` are unknown fields that Claude
  Code ignores at load time and that our own zero-warning rule would then break, so the mechanism
  is this entry, the group descriptions, and forge-adapt.
- `architect-review` STAYS, allowlisted with its reason: `/full-review` dispatches it by name, and
  pointing that at a plugin we do not ship would fail silently when it is absent.
- `mutation-sweep` survives its group-mates. It has no counterpart anywhere and is a quality gate
  rather than a way of working.

### Fixed

- **The README's headline described the pre-#166 install model.** "Rewritten for your stack, not
  copy-pasted" holds only for a bare-clone install or a `scope: project` component, and there are
  none: with a marketplace present, every user-scoped component is REGISTERED. The pitch, the
  four-step summary and the worked example now say what actually happens.
- **"Keeping up to date" promised an auto-update that does not exist**, which was the half of #172
  documented in `adapt/SKILL.md` and never in the README. It now states that registration tracks
  the repository but pulls nothing, names both commands, and carries the dependency upgrade note.
- Smaller README corrections: the gate example cited template v5 (v6 today), the contributions
  section used forge-adapt v1 phase numbers, and the labels row did not mention that
  `sync-labels.sh` is what puts the taxonomy on the host.
- `forge-kit-roadmap`'s manifest described itself as self-contained while depending on
  `forge-kit-devops`.

## v0.3.0 (2026-09-10)

The release where the kit measured itself against the tooling Claude Code now ships, and mostly
kept its own. Three comparisons came back the same shape: the first-party check validates less
than its help text suggests, so `plugin validate` accepts a dependency that then installs
silently, `plugin details` does not charge an agent for what it preloads, and `plugin tag`
validates an agreement this repo's manifests cannot even express. Nothing was replaced; three were
kept with the reason recorded where the next reader meets it, and two became real work.

The other half is the handover. The overnight loop now defers on the trip wire instead of deciding
for the absent human, and `decision-brief` is the artifact that deferral produces.

### Added

- **Cross-group dependencies are declared in `plugin.json`, not only in prose** (#169). Installing
  `forge-kit-roadmap` alone now brings `forge-kit-devops` with it, probed on CLI 2.1.267. The
  declaration lives in two places on purpose: the manifest for the marketplace path, the prose for
  the bare clone, where nothing resolves anything. `validate-plugins.sh` checks what the CLI does
  not, because an UNRESOLVABLE dependency passes `claude plugin validate` and then installs
  silently, with no dependency line and no error.
  **Upgrade note:** resolution happens on INSTALL, not on UPDATE. If you already had
  `forge-kit-governance` or `forge-kit-roadmap` and you `claude plugin update` it, the group
  reports `failed to load` until you run `claude plugin install forge-kit-devops@forge-kit` once.
  The error names that command. Found on the maintainer's own machine within the hour, because a
  fresh-install probe cannot see the upgrade path.
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
