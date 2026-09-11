# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

**The superpowers boundary (issue #69, decided 2026-08-27):** where the obra/superpowers
plugin is present, superpowers owns the INNER loop (how work happens: brainstorm, plan, TDD,
per-round review, verify) and forge-kit owns the OUTER loop (what must be true before and
after: tickets and the gate, hooks and CI guards, versioning, host awareness, overnight
governance). Deliberately kept and not to be "fixed" by contributions: governed unattended
work (approval happens at gate time) and mechanical enforcement over prose persuasion, which
are forge-kit's differentiators. forge-adapt's coexistence mode (#72) applies the boundary at
install time.

A root `AGENTS.md` exists as a thin pointer to this file for non-Claude agents (the open
cross-agent instruction format); keep it a pointer, never duplicate content into it.

**forge-kit** is an AI-assisted project governance scaffold: AI-agnostic at the governance layer (issue templates, labels, GWT scenarios), Claude Code-native at the automation layer (agents, skills, slash commands). It is a template repository, not a buildable application. Its purpose is to be bootstrapped into other projects or used as an upgrade reference via the `forge-adapt` skill. There are no build steps or package managers. The only CI is a governance `Validate` workflow (`.github/workflows/validate.yml`): it runs the structural check, the template lockstep, thirty-seven contract test suites, the component-index freshness check, the component size budget, the two range guards (on `pull_request` AND `push`, #158), plus one advisory `claude plugin validate` step marked `continue-on-error` that can report issues without failing the build. There is no application build/test pipeline. Eighteen of those thirty-seven suites cover shipped executables (hooks, the catalogue script, the agent-skills script, `forge-lib.sh` twice, the component-index generator, both leak scanners, the two roadmap assets, the gate round counter, the install planner and the drift reporter); the other nineteen cover the repo's own guards (`test-validate-plugins.sh`, `test-check-reference-depth.sh`, `test-check-neighbour-overlap.sh`, `test-forge-adapt-neighbour-disposition.sh`, `test-template-lockstep.sh`, `test-check-plugin-version-bump.sh`, `test-component-size.sh`, `test-pre-push-hook.sh`, `test-pre-commit-hook.sh`, `test-component-paths.sh`, `test-check-restatements.sh`, `test-producer-stamps.sh`, `test-template-dir-order.sh`, `test-check-group-isolation.sh`, `test-resolve-range-base.sh`, `test-check-live-placeholders.sh`, `test-check-component-scope.sh`, `test-check-lens-contract.sh`), and all of them run unconditionally.

**Validation approach:** There is no application test runner. Two kinds of validation exist:

1. **Structural / discipline checks** (the same gates CI runs; run these before committing):

   ```bash
   bash scripts/validate-plugins.sh            # plugin.json + marketplace + markers + dependencies + dispatch targets (whole tree)
   bash scripts/test-validate-plugins.sh       # contract test for the structural gate above
   bash scripts/check-template-lockstep.sh     # fail if the work templates + canonical ticket-standards doc drift out of version lockstep
   python3 scripts/test-hooks.py               # behavioural contract tests for the hooks
   bash scripts/test-template-lockstep.sh      # contract test for the lockstep guard above
   bash scripts/check-restatements.sh          # fail if ticket-standards' Precedence list and the gate disagree
   bash scripts/test-check-restatements.sh     # contract test for the restatement guard above
   bash scripts/check-producer-stamps.sh       # fail if any component hardcodes a template-version stamp
   bash scripts/test-producer-stamps.sh        # contract test for the producer-stamp guard above
   bash scripts/check-template-dir-order.sh    # fail if the six copies of the template-dir order disagree
   bash scripts/test-template-dir-order.sh     # contract test for the order guard above
   bash scripts/test-check-ticket-mechanics.sh # contract test for ticket-gate Step 3A's checks
   bash scripts/test-forge-adapt-catalogue.sh  # contract test for the forge-adapt catalogue script
   bash scripts/test-forge-adapt-agent-skills.sh # contract test for the agent companion-skill resolver
   bash scripts/test-forge-lib.sh              # contract test for the forge-host adapter (stubbed transport)
   bash scripts/test-forge-ci-status.sh        # contract test for forge_ci_status's Forgejo path (#193)
   bash scripts/test-update-component-index.sh # contract test for the component-index generator
   python3 scripts/update-component-index.py --check  # fail if the generated inventory regions are stale
   bash scripts/test-component-size.sh          # contract test for the size budget guard
   bash scripts/check-component-size.sh        # warn above the word budget, fail above the ceiling
   bash scripts/test-pre-push-hook.sh          # contract test for the local pre-push range guard
   bash scripts/test-pre-commit-hook.sh        # contract test for the local pre-commit hook, leak scan included
   bash scripts/test-check-public-leaks.sh     # contract test for the leak guard's public half
   bash scripts/test-check-private-leaks.sh    # contract test for the leak guard's identity half
   bash scripts/test-check-phases.sh           # contract test for the roadmap phase guard
   bash scripts/test-sync-phases.sh            # contract test for the roadmap-to-milestone sync
   bash scripts/test-check-group-isolation.sh  # contract test for the isolation guard below
   bash scripts/check-group-isolation.sh       # fail if anything outside forge-kit-roadmap references it
   bash scripts/test-check-live-placeholders.sh # contract test for the placeholder guard below
   bash scripts/check-live-placeholders.sh     # fail if a component bakes a value in at install time
   bash scripts/test-check-component-scope.sh  # contract test for the scope guard below
   bash scripts/check-component-scope.sh       # fail if a component's declared scope contradicts the tree
   bash scripts/test-check-lens-contract.sh    # contract test for the lens-contract lockstep
   bash scripts/check-lens-contract.sh         # fail if the lens result contract drifts between its two groups
   bash scripts/test-check-reference-depth.sh  # contract test for the reference-depth guard below
   bash scripts/check-reference-depth.sh       # fail if a skill's reference is unreachable from its SKILL.md
   bash scripts/test-check-neighbour-overlap.sh # contract test for the neighbour boundary guard
   bash scripts/check-neighbour-overlap.sh     # fail if a component is the same file a neighbour ships
   bash scripts/test-forge-adapt-neighbour-disposition.sh # contract test for the coexistence dispositions
   bash scripts/test-forge-gate-mechanics.sh   # contract test for the mechanical gate's entry point
   bash scripts/test-count-gate-rounds.sh      # contract test for the gate's round counter
   bash scripts/test-check-label-taxonomy.sh   # contract test for the label-taxonomy guard
   bash scripts/check-label-taxonomy.sh        # fail if a copy of the area set disagrees with labels.md
   bash scripts/neighbour-manifest.sh --refresh # maintainer only: re-measure against installed marketplaces
   bash scripts/test-forge-adapt-install-plan.sh # contract test for the register-or-copy decision
   bash scripts/test-forge-adapt-drift-status.sh # contract test for the drift status words
   bash scripts/test-component-paths.sh        # fail if the four path-set consumers disagree
   bash scripts/test-version-lib.sh            # contract test for the release version<->tag primitive
   bash scripts/test-release-run.sh            # contract test for the release lane policy (DRY_RUN)
   bash scripts/test-sync-labels.sh            # contract test for the host-aware label sync
   python3 scripts/test-closing-sessions-memory.py  # contract test for the closing-sessions memory.py helper
   git fetch origin main                       # required: the next script fails closed on a missing base ref
   bash scripts/check-version-bump.sh origin/main   # fail if a changed component didn't bump its <name>-version marker
   bash scripts/test-check-plugin-version-bump.sh   # contract test for the plugin-semver guard below
   bash scripts/check-plugin-version-bump.sh origin/main  # fail if a changed plugin GROUP didn't bump its plugin.json semver
   git config core.hooksPath .githooks         # one-time: enable the local pre-commit version-bump guard
   ```

   `validate-plugins.sh` requires `jq` and `grep -P` (GNU grep). `check-version-bump.sh` diffs `<base>...HEAD` (CI passes `origin/$BASE_REF`) and **exits 1 if the base ref does not exist locally**, rather than passing vacuously, so fetch first. It reads committed blobs via `git show`, not the worktree: an uncommitted marker bump will not satisfy it. The local `.githooks/pre-commit` covers markers with `--diff-filter=AM` on the staged set (CI additionally catches renames, `AMR`) and runs the plugin-semver rule via `check-plugin-version-bump.sh --staged` (`ADM`, `--no-renames` so a cross-group rename charges the source group too). The semver half needs `jq`: a jq-less machine skips it with a loud warning and CI still enforces it. Both range guards run on `pull_request` AND on `push` (#158), with the base resolved by `scripts/resolve-range-base.sh`; the local hook now duplicates CI rather than substituting for it.

   No test script takes a filter argument, so one script is the smallest unit you can run; there is no per-case selector to reach for. The only finer entry point is `python3 plugins/forge-kit-devops/hooks/block-legacy-host-push.py --self-test`, that hook's own verdict matrix, which `test-hooks.py` also drives.

2. **Behavioural validation:** agents, skills, and commands are prose, cannot be run in isolation here, and must be installed into a test project via `forge-adapt` and exercised there. **The exception is anything the kit ships as an executable**, which has a real contract and therefore a real test. Fifteen exist today, and all fifteen are contract-tested in CI, each exercised as a subprocess (throwaway directories, this repo itself, or a stubbed transport, per bullet):

   - **Hooks** (`scripts/test-hooks.py`): JSON payload on stdin, a `permissionDecision` on stdout, always exit 0. The test covers every matched tool, fail-open on unparseable input, deny-signalled-on-stdout-not-exit-code, and a regression guard for the foreign-cwd wiring bugs. It runs in CI. When you change a hook, extend it: three consecutive PRs shipped hook defects before this existed.
   - **`closing-sessions/scripts/memory.py`** (`scripts/test-closing-sessions-memory.py`, 12 tests): the one skill that ships an executable rather than only prose, so the `forge-kit-governance` plugin has a second testable surface. Its own history is the argument for the test (`anchor index matching and escape memory fields`, `treat index-line replacement as literal, not regex`). Wired into CI as of #76; it previously existed but ran only by hand. It still carries **no** `<name>-version: N` marker, because `memory.py` lives in a `scripts/` subdirectory and no marker guard globs that (see the enforced path set below), so a change to it is caught by the test but produces no drift signal for `forge-adapt`.
   - **`scripts/forge-adapt-catalogue.sh`** (`scripts/test-forge-adapt-catalogue.sh`, in CI): the S3 component catalogue the `forge-adapt` skill runs verbatim instead of paraphrasing an inline block (an LLM executor kept reintroducing fixed bugs). Contract: prints `<type>: <name> | v<N>` rows where a skill's name is its *directory* name (every skill file is `SKILL.md`), resolves each version by marker name and then by the first-marker-wins fallback (see the marker-parsing note under Key Conventions), never prints `vnone`, and always exits 0 so a group with no hooks or agents never reads as a failure. Also lists versioned shell assets as `asset:` rows. A `--tsv` mode adds the file path for machine consumers (`update-component-index.py`); the default output is a contract forge-adapt reads, so it is byte-stable and must stay that way.
   - **`scripts/forge-adapt-agent-skills.sh`** (`scripts/test-forge-adapt-agent-skills.sh`, 25 tests, in CI): resolves the companion skills an agent declares in its `skills:` frontmatter, and rewrites the plugin scope to the bare project name at install time. A script for the same reason the catalogue is one, and because the failure it prevents is SILENT: a declared skill that is missing is skipped with only a debug-log warning, so the agent runs with its reference material gone and the project shows no error. It parses two YAML SHAPES rather than YAML, and REFUSES anything else (a multi-line flow list, a plain scalar) instead of guessing, because a half-understood rewrite leaves frontmatter that no longer parses and the agent then stops loading entirely, which is worse than the bug it was avoiding.
   - **`scripts/update-component-index.py`** (`scripts/test-update-component-index.sh`, in CI): renders the component inventory into marker-delimited regions in `README.md` (`component-index`) and `CLAUDE.md` (`plugin-groups`) from the catalogue's `--tsv` output, and `--check` fails a build whose regions have gone stale. **Do not hand-edit inside those markers**; run the script. It is Python rather than bash because it is marker rewriting and diffing rather than globbing, and it shells out to the catalogue rather than re-walking the tree, so "what counts as a component" keeps one definition.
   - **`forge-host/assets/forge-lib.sh`** (`scripts/test-forge-lib.sh`, in CI): the host adapter, driven with a stubbed `forge_api` standing in for the network layer. Covers Forgejo pagination (termination on an EMPTY page, deliberately not `length < limit`, because the server clamps `limit` to `MAX_RESPONSE_ITEMS`), multi-page label resolution, atomic refusal of unresolvable label names, the zero-label message, and dry-run sending nothing.

   - **`forge_ci_status`'s Forgejo path** (`scripts/test-forge-ci-status.sh`, 30 tests, in CI): the second suite on `forge-lib.sh`, for the one function whose wrong answers point the wrong way (#193). The combined commit status flattens a SUPERSEDED run to `failure`, so v13 called 23 of 39 red commits broken when nothing had failed; the fix reads the per-job `description` Forgejo hard-codes ("Has been cancelled") from the response it already holds, so the red path makes no second request and an unknown string falls to v13's answer, never to a false green. Option A, a paginated walk of `/actions/tasks`, was NOT ported: the gate's critic drove it with a server-clamped page and got `cancelled` with a failure on the next page, and the 24 downstream tests were blind to it. `total_count == 0` is no longer `not_configured`, which told the caller to stop looking while the run was queued: one page of `/actions/tasks` says `pending` or `none`, and `not_configured` is RESERVED for "could not ask", the one case that keeps `release`'s local-gate fallback. Ten named mutants die, including `==` relaxed to a prefix and to a contains match, which needed Forgejo's own `Has been skipped` and `Has been cancelled by admin` as fixtures.

   - **`release-automation/assets/version-lib.sh`** (`scripts/test-version-lib.sh`, 19 tests, in CI): the version-versus-tag primitive every release lane sources and acts on. Side-effect-free and returns a one-word verdict, so it tests like a pure function against throwaway repos where the tags ARE the input. Covers the four verdicts, the fail-closed paths, `TAG_GLOB` deriving from `TAG_PREFIX`, and two traps the source calls out: comparing release CORES (because `sort -V` ranks `1.2.0-rc1` above `1.2.0`, so a naive compare would ship a prerelease as production) and git-mode being HEAD-relative on purpose (so a higher tag on an unmerged sibling branch cannot make HEAD look `behind`).
   - **`release-automation/assets/release-run.sh`** (`scripts/test-release-run.sh`, 19 tests, in CI): the side-effecting release driver, run entirely with `DRY_RUN=1` so no forge, push or tag is touched. Covers the LANE POLICY rather than the mechanics: the recursion guard, the dependency scope gate (including the vacuous case, where a bot commit changing no files must not release), the version decision for each verdict, and tag-derived git mode's bootstrap and phantom-tag guards.

   - **`ticket-gate-reference/assets/check-ticket-mechanics.sh`** (`scripts/test-check-ticket-mechanics.sh`, 79 tests, in CI): ticket-gate Step 3A, which was 544 words of prose until #149. It emits one TSV row per check and **never decides a verdict**: where it cannot rule mechanically it emits `referred` and Step 3B rules instead, because its heuristics are deliberately NARROWER than the canonical rules and a check that failed outright on a heuristic miss would reject doc-compliant tickets. The refer paths are therefore what the suite exists to pin down. Its first run caught the bug that argues for the test: the literal `N/A` matches a "contains a slash" path test, so an N/A claim read as a named file path and PASSED the check whose whole job was to refer it. **A section is found at either heading level, and its boundary is a label, not a level (#190)**: `gh issue create --body-file` is a first-class filing path here and produces `##` headings, and keyed on `### ` alone the checker read a doc-compliant `##` body as five absent sections, five FAILs, where the same body at `###` got two and a referred. A heuristic miss that INVERTS the verdict is the exact failure the script's header forbids. The first fix detected one level per body and let `###` win a mixed one; the gate reviewing the ticket found that `dep-auditor` emits `### Priority` beside `##` sections, so that rule inverted the kit's own producer the same way. Now a label is present at `##` or `###`, and its section runs to the next heading at its own level or the next heading that is itself a template label: a `###` subsection inside a `##` section is content, a `### Priority` beside it is a boundary, and a `###` body keeps every boundary it had. Nothing about what a section must CONTAIN moved. `forge-gate-mechanics.sh`'s never-template-shaped notice keys on the same signal (a template label at either level), so a `##` body in the author's own words still gets the notice #184 gave it.

   - **`ticket-gate-reference/assets/forge-gate-mechanics.sh`** (`scripts/test-forge-gate-mechanics.sh`, 32 tests, in CI): the entry point that makes Step 3A runnable WITHOUT the agent harness (#182), which is the whole of forge-kit's portability claim. It is glue and nothing else: fetch the issue through `forge-lib.sh`, resolve the template directory, hand both to `check-ticket-mechanics.sh`. **It never prints a verdict**, because Step 3A is the mechanical half and every `referred` row exists where a heuristic is narrower than the rule; a summary saying PASS would look like the real gate having skipped the half that reads the ticket. `referred` is counted separately from the good news for the same reason. Driven in tests by a stub `forge-lib.sh` beside a copy of the script, so no forge and no token, and one case scans the file to assert nothing in this path names the harness CLI.

   - **`ticket-gate-reference/assets/count-gate-rounds.sh`** (`scripts/test-count-gate-rounds.sh`, 29 tests, in CI): the gate's round number, counted from posted `## Ticket Readiness Review` comments plus one (#192). It exists because the number used to be read from the `gate-verdict` block in the issue body, and an ordinary body edit erases that block: the gate then believed every round was round 1, so the delta rows of its round table never engaged and a caller's trip wire, which counts rounds, **could never fire**. A stopping rule that cannot fire is worse than one that is absent, because it is believed in. The comments are the source and the block is a projection: a disagreeing block is reported on stderr and loses. Only a comment whose FIRST line is the review heading for THIS issue number counts, so a synthesis-void comment, a quoted heading, or a sibling ticket's review is not a round. Exit 2 with nothing on stdout when the listing cannot run, since a count that cannot run must never look like round 1. It never prints a comment author, and a case asserts that. Reads `forge_issue_comments`, which `forge-lib.sh` v14 added for it.

   - **`forge-host/assets/sync-labels.sh`** (`scripts/test-sync-labels.sh`, 22 tests, in CI): makes the host's labels match `.github/labels.yml`, or `--check` reports that they do not. Host-aware through `forge-lib.sh` (GitHub updates a label by NAME, Forgejo by ID) and **never deletes**: an undeclared label is reported and left alone, because GitHub ships stock defaults and a sync that deletes what it does not recognise is a footgun aimed at other people's data. A malformed `labels.yml` line REFUSES the whole run rather than skipping the entry, since a silent partial sync is the drift it exists to end. Driven in tests by a stub `forge-lib.sh` placed beside a copy of the script, so the script sources the stub instead of the transport.

   - **`leak-guard/assets/check-public-leaks.sh`** (`scripts/test-check-public-leaks.sh`, 80 tests,
     in CI): the PUBLIC half of the leak guard (#99, split as #155). Catches home-path shapes,
     unlisted `~/` roots and reachable email addresses, and forge-kit runs it on its own tree the
     way it runs `block-dashes` on itself. Every rule has a NEAR-MISS case as well as a firing one,
     because a shape rule fails by being too eager: a guard that rejects `/home/user/` is a guard
     nobody can write install docs under, and the first response to that is to delete it. Its
     limits are stated in its own source, since **nothing in the public half catches a bare project
     name** and a guard that overstates its reach is worse than a narrow one that admits it. Both
     scanners were the first files here to want bash-4 expansions and GNU `readlink -f`; the suite
     BANS them, because macOS ships bash 3.2 and a component that dies on a contributor's laptop
     gets deleted rather than reported. Both rules judge the FIRST path segment only, so a private
     directory name under an allowed root is invisible to the public half; the source says so,
     because the first version of its reach statement did not and a review found the gap.
     **Neither half looks at HISTORY** (#185): both enumerate the working tree, the index or two
     endpoints of a range, so a leak committed once and removed later is unreached, which is
     precisely the going-public case the component is named for. Neither reads a commit message
     either, and this repository's store holds 527 commit objects against 1,639 blobs. Both headers
     now say so, the private half having carried NO reach statement at all until then, and the
     skill names `gitleaks` for the credential class this guard does not cover.

   - **`leak-guard/assets/check-private-leaks.sh`** (`scripts/test-check-private-leaks.sh`, 40
     tests, in CI): the IDENTITY half of the leak guard (#156). It is the one shipped executable
     that is contract-tested in CI but never RUN there, and that is permanent: it needs the list of
     private names, and a list of the names you are hiding cannot live in the repository it
     protects, nor in a CI secret, which is the same disclosure with more readers. Three of its
     behaviours look like leniency and are the opposite, because all three failures point at the
     guard being UNINSTALLED: a missing list exits 0 and says so, the OWNING ACCOUNT's name is
     dropped with a warning (it is in the clone URL, so obeying it refuses every commit touching
     the README), and an entry under three characters refuses the run. It also REDACTS the matched
     name by default, because a failing hook's output is exactly the pasted text this component
     exists to police.

   **Every shipped executable now has a contract test, and all of them run in CI** (issue #76 closed the last gap, and #155/#156 and #192 kept the invariant when they added the sixth, seventh and eighth shell assets). All eight shell assets carry hook-style `# <name>-version: N` markers, enforced by the same enforcement points as every other component.

## Architecture

The kit is organized into plugin groups under `plugins/<group>/`. This table is generated from the
tree by `scripts/update-component-index.py`; CI fails if it goes stale, so do not hand-edit it. The
Version column is the group's `plugin.json` semver (the unit of install), not a component marker.

<!-- plugin-groups:start -->
<!-- Generated by scripts/update-component-index.py from the plugins/ tree. Do not hand-edit: run the script. CI fails on a stale region. -->

| Plugin group | Version | Contents |
|---|---|---|
| `forge-kit-adapt` | 0.7.0 | skill: adapt |
| `forge-kit-devops` | 0.12.3 | agents: dep-auditor, health-check; command: ci-health; skills: find-dead-code, forge-host, github-to-forgejo, release, release-automation; hook: block-legacy-host-push; shell assets: forge-lib, release-run, sync-labels, version-lib |
| `forge-kit-governance` | 0.16.5 | agent: ticket-gate; command: gate-ticket; skills: closing-sessions, decision-brief, ticket-gate-reference, working-overnight; hooks: block-dashes, overnight-continue, overnight-guard; shell assets: check-ticket-mechanics, count-gate-rounds, forge-gate-mechanics |
| `forge-kit-review` | 0.4.1 | agents: architect-review, code-reviewer, code-simplifier, coding-standards-auditor; command: full-review |
| `forge-kit-roadmap` | 0.8.4 | command: phase; skill: roadmap-phases; shell assets: check-phases, roadmap-lib, sync-phases |
| `forge-kit-security` | 0.9.0 | agents: api-security-tester, security-auditor; skills: leak-guard, owasp-api-security, privacy-regime; shell assets: check-private-leaks, check-public-leaks |
| `forge-kit-testing` | 0.3.0 | skill: mutation-sweep |
<!-- plugin-groups:end -->

Users install via the plugin marketplace (`/plugin marketplace add agigante80/forge-kit`) or by cloning the repo and running `forge-adapt` from within the target project.

## Component Types

**Agents** (`plugins/<group>/agents/*.md`): isolated specialist subagents that run in a separate context window, invoked via the Claude Code `Agent` tool with `subagent_type`. **An agent is always a FLAT file and can never have a `references/` directory**; see the companion-skill rule under Key Conventions before trying to split one. Required YAML frontmatter:

```yaml
---
name: <agent-name>
description: <when to invoke this agent (include trigger phrases)>
model: opus          # or omit for default
tools: ["Agent", "Bash", "Read", "Grep", "Glob"]
color: red           # optional; used in Claude Code UI
---
```

Key agents:
- `ticket-gate`: deterministic mechanical checks plus ONE critic agent (verdict, pushback, GWT review, pros and cons, researched best practices, suggested approach), with a security lens on `security`/`critical` labels; posts the review to the forge and returns PASS, NEEDS-WORK, or BLOCKED (labels/thin-ticket). The former 5-agent 10/10 scoring committee was retired by issue #70.
- `dep-auditor`: scans workspace packages for unused deps, unmaintained libraries, and vulnerabilities; caches results in `docs/audit/dep-audit-cache.json` (30-day window); creates GitHub tickets for every finding.
- `health-check`: verifies the dev environment (runtime, package manager, Docker, TypeScript, env files, GitHub CLI).
- `coding-standards-auditor`: consolidates coding standards from wherever they live (inline CLAUDE.md, CONTRIBUTING.md, STYLE_GUIDE.md, docs/) into a canonical `docs/coding-standards.md`, then replaces the inline standards with a reference line.
- `code-simplifier`: runs proactively after a code change to simplify recently modified code while preserving functionality.
- Specialist agents: `security-auditor`, `architect-review`, `code-reviewer`, `api-security-tester`. **#178 retired five more** (`backend-architect`, `backend-security-coder`, `tdd-orchestrator`, `test-automator`, `performance-engineer`) plus the whole `forge-kit-backend` group, because each was the same file wshobson/agents ships; `scripts/check-neighbour-overlap.sh` now stops that recurring.

Note: the 5-phase `full-review` orchestrator is a **command** (`/full-review`), not an agent (see Commands below). There is no `full-review` agent type.

**Agent names carry no plugin prefix, and that was decided rather than defaulted (#180).** Every neighbouring plugin prefixes its agents (`backend-development-security-auditor`, `tdd-workflows-tdd-orchestrator`); forge-kit's are bare (`security-auditor`). The rename was declined because **Claude Code already namespaces subagent types by plugin**: this repo's own agent is dispatched as `forge-kit-governance:ticket-gate`, so nothing collides and the prefix would buy provenance in a listing most users never see, at the cost of touching every agent file, every marker and every group semver. What did ship is the guard for the failure that ticket identified, because #178 made it live: `validate-plugins.sh` check 5 fails a build where a component dispatches a `subagent_type` no agent in the tree provides, which would otherwise fail at RUNTIME and silently, the same class as #124. `general-purpose` is exempt: it is Claude Code's own built-in.

**Commands** (`plugins/<group>/commands/*.md`): thin slash-command wrappers that delegate to agents. The command name comes from the filename (`full-review.md` → `/full-review`), so YAML frontmatter is optional and inconsistent across the kit: `gate-ticket` and `ci-health` have no frontmatter at all (markdown body only); `full-review` uses `description` + `argument-hint`. Don't assume a `name:` field exists. Users invoke these directly:
- `/gate-ticket <N>`: run the ticket readiness gate on GitHub issue N.
- `/full-review [path] [--since <ref>] [--security-focus] [--performance-critical] [--strict-mode] [--framework name]`: 5-phase code review; `--since` runs a delta-only verify-fixes round under the iteration contract. Positioned as a pre-merge/periodic audit, not the per-task reviewer (that is `code-reviewer` alone under the same contract).
- `/ci-health`: check all GitHub Actions workflows, create P0 tickets for failures, auto-fix safe failures.

Note: `dep-auditor` and `health-check` are agent types, not slash commands. Trigger them by mentioning "health check" or "audit dependencies" in conversation.

**Skills** (`plugins/<group>/skills/*/SKILL.md`): domain knowledge injected into the main conversation (not isolated). Frontmatter requires only `name` and `description`. Skills can have `assets/` (checklists, templates, shipped executables), `references/` (supporting docs), and `scripts/` (helper executables) subdirectories alongside `SKILL.md`. For example, `forge-adapt` (`forge-kit-adapt`) uses `references/` (one signal→component→why map per recommendation category), and `closing-sessions` (`forge-kit-governance`) is the only user of `scripts/`. Only `assets/*.sh` is version-marker enforced; see the enforced path set under Key Conventions before adding an executable anywhere else. Triggered automatically when relevant or by user invocation. Includes: `forge-adapt`, `owasp-api-security`, `find-dead-code` (the source-code counterpart to the `dep-auditor` agent), `mutation-sweep` (coverage's blind spot: tests that cannot fail, engine adopted per stack), `release` (semver bump + version-check guard + tag + close shipped tickets), `release-automation` (the *enforced* sibling of `release`: a CI gate that blocks a merge to the production branch unless the version was bumped past the last release, built on a shared version↔tag primitive, plus optional auto-release lanes), `forge-host` (the `forge_*` adapter that makes governance host-aware across GitHub and Forgejo), `github-to-forgejo` (the GitHub-to-Forgejo migration playbook), `ticket-gate-reference` (the review template and lens definitions `ticket-gate` preloads through its `skills:` field, issue #109), `closing-sessions` (persist durable facts and resume state before a session ends), `working-overnight` (governed unattended overnight work shipped as branch-plus-PR, never merging), `decision-brief` (re-validate a stalled ticket, cost the options, and rewrite its body so the decision can be made from it, issue #129).

**Issue Templates** (`.github/ISSUE_TEMPLATE/*.yml`): six templates. The five *work* templates (`feature.yml`, `bug.yml`, `security.yml`, `infrastructure.yml`, `design.yml`) carry `template-version: 6` and the mandatory sections: GWT scenarios, unit test specs, E2E test specs, personal-data handling, security checklist, documentation impact, and required reviews checkbox. `contribution.yml` is the odd one out: it proposes a component *to forge-kit itself* rather than describing project work, so it carries no `template-version` marker and no GWT sections. Don't "fix" it by adding them. The `ticket-gate` agent auto-synthesizes missing v6 sections from earlier-version tickets. The **rules** those sections must satisfy live in one canonical place, `docs/guides/ticket-standards.md` (the single source of truth): the templates carry the form fields, that doc holds the rules and rationale, `ticket-gate` enforces them, and `scripts/check-template-lockstep.sh` keeps the templates and that doc on one shared `template-version` so they cannot drift apart. That doc carries a **second** marker, `doc-rules-version`, which the lockstep guard deliberately ignores (issue #94): `template-version` says which FORM the doc describes and bumping it re-synthesises every open ticket, while `doc-rules-version` says which revision the RULES TEXT is at and costs nothing downstream. Bump the rules marker alone for a rules edit that changes no form field. See `docs/guides/template-versioning.md` for the versioning scheme and auto-synthesis logic.

## Plugin Structure

Each plugin group has a `.claude-plugin/plugin.json` with `name`, `description`, a semver `version` (the ecosystem-standard plugin version, distinct from the per-component `<name>-version` markers), and an `author`:

```json
{ "name": "forge-kit-<group>", "version": "0.1.0", "description": "...",
  "author": { "name": "agigante80", "url": "https://github.com/agigante80" } }
```

**`author` is required by `validate-plugins.sh`, and its value is a deliberate minimum (#173).** Every group was missing it, so the advisory `claude plugin validate` step printed eight warnings on every build and nobody read any of them; the cheapest way to make an advisory check useful is for it to say nothing when nothing is wrong, and the cheapest way to keep it that way is a build failure rather than a ninth warning. The shape is the CLI's own, probed on 2.1.267: an OBJECT with a non-empty `name` plus an optional `url`. A bare string is rejected there, so accepting one here would make the guard laxer than the thing it stands in front of. **The value is the handle and its profile URL, and no email address**: the handle is already public in every clone URL, which is why `check-private-leaks.sh` drops the owning account from its own list, while an email address is what `check-public-leaks.sh` rule C exists to catch and cannot be recalled from a public history. `marketplace.json`'s `owner` block is the one place an address appears, and it is allowlisted there rather than copied into eight more files.

The root `.claude-plugin/marketplace.json` lists all plugins with their local `source` paths. This is the file the plugin marketplace reads to discover installable plugins.

**A cross-group dependency is declared in BOTH places, and each place serves a different install path (#169).** `plugin.json` takes a `dependencies` array of `plugin@marketplace` identifiers and the installer resolves it: probed against 2.1.267, installing `forge-kit-roadmap` alone prints `+ 1 dependency: forge-kit-devops` and enables both. Exactly two groups declare one, and no others should: `forge-kit-roadmap` and `forge-kit-governance` both need `forge-lib.sh` from `forge-kit-devops`. The manifest is for the marketplace path; the prose in `roadmap-phases/SKILL.md` and `decision-brief/SKILL.md` is for the bare-clone path, where nothing resolves anything and the runtime message from #161 is the only thing a user gets. Neither replaces the other, so a new dependency goes in both. `scripts/validate-plugins.sh` then checks the half the CLI does not: an unresolvable identifier passes `claude plugin validate` and INSTALLS SILENTLY, with no dependency line and no error, so the guard fails a declared dependency `marketplace.json` does not list. One named in a foreign marketplace is reported rather than failed, since this tree cannot resolve it.

**Three versioning levels (don't conflate them):** the **release tag** (`vX.Y.Z` on main) is the umbrella version naming the state of the whole marketplace at a point in time. It is a communication artifact, not a delivery mechanism: `/plugin marketplace add` tracks the repository, so a tag never changes what an existing user receives. The tag itself is the canonical source, and there is deliberately no `VERSION` file and no `version` field in `marketplace.json`, because a repo-level version file would be a mirror with nothing to check it against and no guard watching it. Nothing enforces the tag, and nothing needs to; there is only one place to be wrong. The **plugin** version (`version` in `plugin.json`, semver) is the standard unit-of-install version read by the marketplace/tooling, set per plugin group. The **component** version (`<!-- <name>-version: N -->` markers) is forge-kit's finer-grained signal for detecting drift in a single component that `forge-adapt` cherry-picked and rewrote into a project's `.claude/`. Divorced from its plugin, a loose adapted file needs its own marker. The `Validate` CI workflow enforces both: `scripts/validate-plugins.sh` checks structure + semver + marker presence; `scripts/check-version-bump.sh` fails a PR whose component changed without a marker bump (the authoritative, server-side counterpart to the opt-in `.githooks/pre-commit`); `scripts/check-plugin-version-bump.sh` fails a PR whose plugin GROUP changed without a `plugin.json` semver bump, so the unit-of-install version can no longer rot while markers move (it did exactly that in PRs #74/#75, which is why the guard exists). Cutting a release does **not** touch plugin semvers: those move on the PR that changes their group, which is the only moment a guard can see it. The full model, including when to bump the umbrella and why `template-version` is not one of these levels, is `docs/guides/versioning.md`; `CHANGELOG.md` carries the umbrella history.

## Key Conventions

**Agents vs. Skills vs. Commands:**
- Agents → isolated context, structured output, scoring, auditing
- Skills → injected knowledge, patterns, checklists; no isolation
- Commands → user-facing entry points; delegate to agents

**`{{GITHUB_REPO}}` is retired from every component (#163).** It survives only in prose documenting the manual-install path, where naming it is correct. No component substitutes anything at install time any more: `forge_repo` derives `owner/repo` from the git remote at runtime, which is what lets a component be installed once rather than copied into each project. `scripts/check-live-placeholders.sh` refuses a new one in any component, whatever its scope.

**Installation paths:**
- Plugin marketplace: `/plugin marketplace add agigante80/forge-kit` then `/plugin install forge-kit-adapt@forge-kit`, after which forge-adapt installs everything else. The skill's frontmatter `name` is `forge-adapt`, but its directory is `skills/adapt/`, so the slash form is `/forge-kit-adapt:adapt` (not `/forge-adapt`); in conversation, "run forge-adapt" also triggers it.
- Manual: clone `~/forge-kit`, then run `forge-adapt` from the target project. It reads the codebase, recommends components, and writes adapted versions into `.claude/`
- `.claude/` in a project repo = project-scoped; `~/.claude/` = global across all projects

**forge-adapt flow (v2, recommender-style):** A quiet **Setup** (silent self-update via SHA-diff against the GitHub remote, locate/clone `~/forge-kit`, catalogue components) precedes a clean three-step dialogue: **Analyze** the project (stack, domain, installed components, signal indicators) → **Recommend** the top 1-2 forge-kit components per category (Subagents, Skills, Commands, Hooks), each with a ≤60-char reason → **Install** the chosen ones, adapting agents/skills/commands to the stack and copying hooks verbatim (wiring `block-dashes` into `.claude/settings.json`). Three **secondary modes** stay out of the main flow: `refresh`/`drift` reports which installed components lag forge-kit (version-marker comparison, writes nothing) and `refresh <name>` deep-compares one component and merges in missing forge-kit improvements while preserving project adaptation (report-first, never blind-overwrite); `forge-adapt contributions` surfaces project-only components worth contributing back; `forge-adapt templates` audits issue templates and can install the repo-level template governance (the `check-template-lockstep.sh` guard plus a canonical, host-aware `docs/guides/ticket-standards.md`, adapted with the project's own `template-version` and never clobbering an existing doc). Also responds to "upgrade-audit" for backward compatibility.

**Component version markers:** every agent, skill, and command carries an HTML-comment marker (`<!-- <name>-version: N -->`, e.g. `<!-- ticket-gate-version: 1 -->`); hooks and shipped shell assets (`plugins/*/skills/*/assets/*.sh`) use a `# <name>-version: N` comment. These are the cheap, false-positive-free drift signal forge-adapt's `drift`/`refresh` modes compare against (adaptation does not change the marker; staleness does). This is distinct from the `template-version: N` marker on issue templates. When you materially change a component's behavior, bump its marker. `forge-adapt` preserves the marker when it adapts a component into a project, so a project's installed copy stays detectable.

**The neighbour boundary is enforced, not described (#177).** forge-kit exists to complement superpowers and the marketplaces around it: decision #69 gives superpowers the INNER loop (how work happens) and forge-kit the OUTER (what must be true before and after). That line lived only in `adapt/SKILL.md`'s coexistence table, and five components had crossed it unnoticed. `scripts/check-neighbour-overlap.sh` now fails the build on a **duplicate** (the same file a neighbour ships) and merely REPORTS a **collision** (the same name, different content), because `code-reviewer` is a name anyone would pick and a guard that failed on every shared name would be switched off. The threshold is measured rather than chosen: after normalising away the `name:` line and our version marker, duplicates differ by 1 to 10 lines and the nearest genuine divergence is 103, so nothing sits in the gap. Evidence lives in `docs/neighbours.tsv`, regenerated by `scripts/neighbour-manifest.sh --refresh`, which is a MAINTAINER command reading `~/.claude/plugins/marketplaces`; the guard itself reads only the checked-in file, so it behaves identically in CI, which has no plugins installed. The manifest is therefore only as fresh as the last refresh, and an entry over 120 days old warns loudly rather than passing as current. **A component copied under a different name is invisible to it**, since every row is keyed on a shared name, and the script says so rather than implying a reach it does not have. `.neighbour-allow` exempts a duplicate and REQUIRES a reason, the shape `check-restatements.sh` already uses.

**The coexistence rule is one table in one script, covering both neighbours (#179).** `scripts/forge-adapt-neighbour-disposition.sh` takes a component name and the installed set and returns `recommend`, `caveat` or `suppress` with a reason. It judges the PAIR, never the name: `code-reviewer` exists on three sides as three different agents, and suppressing ours because a string matched would hand the user less than they had, which is the same mistake `check-neighbour-overlap.sh` refuses to make at build time. `suppress` is reserved for the inner-loop boundary (#69), where superpowers owns the process; a neighbour that merely ships a same-named TOOL is a `caveat`. It is a script rather than prose for the #149 reason and for a measured one: as a table `adapt/SKILL.md` could not have held the second half at all, and converting the first half SHRANK the file by 91 words. A missing or malformed install record means no neighbours rather than an error, because that file belongs to another tool.

**`forge-kit-roadmap` is OPTIONAL, and `scripts/check-group-isolation.sh` is what keeps it so.**
Rolling wave planning is one opinionated method; the rest of the kit is methodology-agnostic, so a
project that declines the group must lose nothing. The guard fails the build if any component
outside `plugins/forge-kit-roadmap/` names its identifiers (`forge-kit-roadmap`, `roadmap-phases`,
`check-phases.sh`, `sync-phases.sh`). It keys on those rather than the English word "roadmap", which
appears innocently across the kit. The dependency runs ONE WAY: the group needs `forge-lib.sh`, and
that direction is fine. **`ticket-gate` must never learn what a phase is**: "has a phase assigned"
looks like a readiness property and is the obvious line to add, and adding it would make the group
optional on paper and mandatory in practice. Exactly one exemption, carrying its reason in the
script (`forge-kit-adapt` is the installer and names every component by definition). The guard found
a violation on its first run against this tree, in a comment inside `forge-lib.sh` explaining the
boundary; the comment was reworded rather than exempted.

**The milestone primitives live in `forge-lib.sh`, not in the roadmap group.** Milestones are a host
capability rather than a planning concept, `dep-auditor` already reads them, and a project using any
other method still wants them.

**`drift` reports a registered component as `registered`, never missing (#167).**
`scripts/forge-adapt-drift-status.sh` turns a local version, a catalogue version and whether the
group is enabled into one word. `absent` (no copy) and `none` (a copy with no marker) are
deliberately different inputs: the second is the whole install base predating markers (#64), and
conflating them would hide it. Reporting a registered component as missing would invite the user to
install it again BY COPYING, which is what #166 removed, so the distinction is what stops that fix
undoing itself.

**forge-adapt REGISTERS a user-scoped component rather than copying it (#166).**
`scripts/forge-adapt-install-plan.sh` makes that decision and prints one line, `register` or `copy`,
with its reason; `adapt/SKILL.md` runs it instead of carrying the rule. Three things still copy, and
each is checkable: a `scope: project` component, an install from a bare clone with no marketplace,
and hooks, which reach a project by their own three shapes and which the planner refuses to judge.
It is a script for the #149 reason and for a measured one: as prose the rule was +118 words against
a ratchet with no duplication left to pay with, and as a script the file SHRANK.

**A component declares WHERE IT BELONGS, and absent means `user` (#164).** `scope: user` means it
is correct in every project and is installed once by enabling its plugin group; `scope: project`
means it must be rewritten for the project it lands in, and it **carries a `scope-reason:`**, the
same shape `check-restatements.sh` requires of an allowlist entry, because copying a component into
every project is the cost that field buys. The default is `user` deliberately: a default should
point at the good path, and after #163 that is the case the tree can prove. All thirty-eight
components are user-scoped today. `scripts/check-component-scope.sh` reads FRONTMATTER only (a
`scope:` in the body is an example, and reading it would let a component be scoped by its own
documentation) and refuses ANY component carrying an install-time placeholder, which is the one
contradiction a script can see.

**A component resolves its values at RUNTIME, never at install time (#163).** A component that
reads the project it is running in is correct in every project and can be installed once, by
enabling its plugin group; one with a value baked in by `forge-adapt` is pinned to that project and
forces a copy, which is the copy-and-mutate path this file already calls the origin of every hook
bug in the repo's history. `scripts/check-live-placeholders.sh` refuses a `{{PLACEHOLDER}}` inside
a fenced command while ALLOWING one in prose, because the manual-install path has to stay
documentable and a guard forbidding the explanation would forbid the reason. The single exemption is a
line whose command IS `sed`, word-anchored, because an unanchored match exempted any line
containing "used", "based", "parsed" or "closed" (found by review). **No scope exempts a
component:** round 1 of that review allowed one under `scope: project`, and round 2 found nothing
substitutes a placeholder since #163, so the licence would have installed a broken component. An
unclosed code fence refuses the file rather than guessing, since it cannot then tell command from
prose.

**The leak guard runs FIRST in both hooks, before every early exit.** It was wired in at the
bottom of each, so `pre-commit` skipped it for any commit not touching `plugins/` (which is most
prose, and prose is where a pasted home path lands) and `pre-push` skipped it whenever
`origin/main` was not fetched. Both hooks now scan before their own machinery, keep a separate
counter from it, and distinguish a scanner exit 1 (found something) from exit 2 (could not run):
both block, but telling someone to edit an allow-file they have just broken sends them the wrong
way. `scripts/test-pre-commit-hook.sh` exists because of this: the pre-push hook has had a
contract test since #98 and the pre-commit hook had none.

**Version-bump enforcement, split across two local stages.** `.githooks/pre-commit` checks the STAGED set: it blocks a commit that changes a component's body without bumping its `<name>-version` marker (and flags new components missing a marker), and a commit that changes a plugin group without strictly increasing its `plugin.json` semver (one shared implementation: the hook calls `check-plugin-version-bump.sh --staged`). `.githooks/pre-push` then runs the RANGE guards (`check-version-bump.sh` and `check-plugin-version-bump.sh` against the remote's default branch), which is the question CI asks on a PR and the one that only has an answer once you know what you are pushing. It duplicates CI rather than substituting for it: since #158 both range guards also run server-side on `push`, so the hook's value is giving the same answer BEFORE the push rather than after. Skips are always loud, never silent, and never block the push: a missing base ref or a missing `jq` prints why and defers to CI, the same posture pre-commit already takes for `jq`. Deliberately two committed hooks rather than adopting the `pre-commit` framework, which would give a one-command install and be the first package-manager dependency in a repo that has none. One-time enablement covers both: `git config core.hooksPath .githooks`. Bypass a trivial change with `git commit --no-verify` or `git push --no-verify`.

**The enforced path set is exactly ONE directory level deep, and four consumers implement it.** A file is marker-enforced only if it matches `plugins/*/agents/*.md`, `plugins/*/commands/*.md`, `plugins/*/skills/*/SKILL.md`, `plugins/*/hooks/*.{py,sh}`, or `plugins/*/skills/*/assets/*.sh`, with **no further nesting**: `plugins/<group>/agents/references/x.md` is not a component. Everything else under `plugins/` is unversioned and unguarded by construction: `references/*` (deliberate, they are supporting prose), but also `skills/*/scripts/*.py` and non-`.sh` assets, which is why `closing-sessions/scripts/memory.py` carries no marker today.

Three of the four consumers share one **byte-identical** ERE: `scripts/validate-plugins.sh` (as `find -regextype posix-extended -regex "$COMPONENT_RE"`), `scripts/check-version-bump.sh` and `.githooks/pre-commit` (as a `grep -E` alternation). The fourth, `scripts/forge-adapt-catalogue.sh`, must use shell globs instead, because a glob is not a regex. `scripts/test-component-paths.sh` is what keeps all four agreeing: it fails if the three strings drift apart or if the catalogue's globs stop selecting the same files. Widening the set means editing the same regex in three places and the globs in the fourth, then updating that test.

**Why an ERE and not `find -path` (issue #112).** In `find -path`, unlike a shell glob, `*` **crosses `/`**, so `-path '*/agents/*.md'` matched at any depth. The result was a silent disagreement pointing two ways at once: `validate-plugins.sh` would have *demanded* a version marker on a nested reference file, while the catalogue could never see it, so `drift`, `refresh` and the generated index would never compare the marker it was forced to carry. Latent until something nested appeared; it surfaced while investigating #109's proposed `references/` split.

**Marker parsing is positional.** All three enforcement points (`scripts/validate-plugins.sh`, `scripts/check-version-bump.sh`, `.githooks/pre-commit`) read the marker with the same `ver_of` pipeline, built on `grep -oP '[a-z0-9-]+-version: \d+' | grep -v '^template-version' | head -1`. Change one and you must change all three. Three consequences: the marker must be lowercase-kebab followed by digits; it must be the *first* `<name>-version: N` string anywhere in the file (a version reference in prose above the real marker silently becomes the parsed version); and `template-version` is skipped only when it starts the match. Most components put the marker within the first few lines. `forge-adapt` and `github-to-forgejo` sit lower because of long frontmatter, which is fine as long as nothing version-shaped precedes them.

**A component's marker name is not guaranteed to equal its component name**, and exactly one component diverges: `skills/adapt/SKILL.md` is catalogued as `adapt` (its directory) but carries `forge-adapt-version`. The three enforcement points never notice, because `ver_of` matches any `[a-z0-9-]+-version` and does not care what the file is called. `scripts/forge-adapt-catalogue.sh` did care, and printed `vnone` for it until issue #95: it resolves by name first, anchored to the comment lead-in so a short name cannot substring-match a longer marker, and now falls back to that same first-marker-wins rule when the name lookup misses. Because the catalogue walks exactly the five marker-enforced path shapes, a `vnone` row can only mean a present marker went unread, so its contract test asserts no row prints one. Renaming the directory to match the marker was rejected: it would change the published `/forge-kit-adapt:adapt` invocation and every install path to fix one row.

**This repo runs `block-dashes.py` against itself.** `.claude/settings.json` wires it as a `PreToolUse` hook on `Write|Edit|MultiEdit|NotebookEdit|Bash`, so any tool call whose payload contains an em dash (U+2014) or en dash (U+2013) is denied. This is deliberate dogfooding of a `forge-kit-governance` hook. The correct response to a hit is to **restructure the sentence**, never to substitute a hyphen for the dash.

**Hooks reach a project three ways, and the script tells them apart by its own path shape.** A plugin group ships `hooks/hooks.json`, which Claude Code activates whenever **that plugin** is enabled, anchored to `${CLAUDE_PLUGIN_ROOT}`. That copy is live in *every* project, so an opinionated hook like `block-dashes` stays dormant until the project opts in by creating `.claude/no-dashes`. The other way is a project-local install (`.claude/hooks/<name>.py` plus a `settings.json` entry), which `forge-adapt` does whenever the governance plugin is not enabled; that copy is itself the opt-in and needs no sentinel. The third way is this repo running the hook against its own tree, which is what `.claude/settings.json` does here: it points at `plugins/forge-kit-governance/hooks/block-dashes.py`, a path that is neither a `.claude/hooks/` copy nor outside the project. `enforcement_enabled()` therefore branches three times, in order: a script in a `.claude/hooks/` directory always enforces; otherwise, a script that resolves *under* `CLAUDE_PROJECT_DIR` (falling back to the payload's `cwd`) also always enforces, opt-in implied by its presence in the tree; only a script resolving *outside* the project root is the plugin's own copy, and that is the single branch that consults the `.claude/no-dashes` sentinel. So **this repo has no `.claude/no-dashes` file and the guard is live anyway.** Do not add one to "fix" it, and do not read a missing sentinel as a disabled hook: pipe a payload through the script to find out. The `.claude/hooks/` test is keyed on path shape, so it holds regardless of the working directory or which environment variables were exported. An earlier version keyed on "is the script under the project root," falling back to the payload's `cwd`, which is the *session's* directory rather than the project root, so a session started in a subdirectory silently disabled the guard. One deliberate exception to the plugin path: `block-legacy-host-push.py` (`forge-kit-devops`) ships with **no** `hooks.json`. It must never be live in every project, so it is installed project-locally only, by the `github-to-forgejo` skill's cutover phase. Don't "fix" the missing wrapper.

The governance `hooks.json` wires three hooks in three different shapes, and the differences are deliberate. `block-dashes` is a `PreToolUse` hook shell-gated on a dedicated opt-in file, `.claude/no-dashes`. `overnight-guard` is also `PreToolUse` and shell-gated, but on `.claude/overnight/active.md`, the armed run's own manifest rather than a separate sentinel, so arming a run is the opt-in and no second file can fall out of sync with it; it also matches `Bash` alone, where `block-dashes` matches the full five-tool write set, because it polices commands rather than prose. **Its patterns are bounded to a single line (#168)**: the class was `[^|;&]*`, which matches a newline like any other character, so a `git checkout` on one line reached a `-f` on any later line of the same payload. In a real armed run that denied switching branches, writing a ticket ABOUT the command, and a script naming it in a test string. The residual limit is stated rather than implied: a heredoc BODY line that is itself a destructive command still denies, because no regex over a shell payload can tell a line that runs from a line that is data. `overnight-continue` is the exception to "gate in the shell, not the interpreter": it is a **Stop** hook wired straight to `python3` with no `sh` wrapper, gating internally on the same manifest. A Stop hook fires once per session end rather than once per matched tool call, so the 44 ms interpreter start is paid a handful of times a day instead of thousands, and the wrapper is not worth its own failure mode there. Do not "unify" these three onto one shape. `plugins/forge-kit-governance/hooks/README.md` carries the long form of the install model (sentinel, shell gate, measured costs), though it predates the overnight hooks and documents only the `block-dashes` shape; read it before changing how a hook reaches a project.

Two facts that are easy to conflate and must not be. **Where the component library lives** (`~/.claude/plugins/marketplaces/forge-kit`, or a `~/forge-kit` clone) says nothing about **which plugin groups are enabled**. The plugin *cache* (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) contains only an installed plugin's own files and never a `plugins/` tree, so it can never serve as the library. That leaf is the plugin's SEMVER, not a commit sha, which an earlier revision of this file got wrong; probed against 2.1.265, where the governance cache held `0.4.1/` and `0.7.11/` side by side. **A naive search over that layout is unsafe (#189)**: `find ~/.claude/plugins -name <asset> | head -1` returns whichever copy the filesystem lists first, and on this machine it returned three different copies in three consecutive runs, one of them stale. Every prose resolver (`ticket-gate.md` Step 1, `phase.md`) and both roadmap assets' last-resort search now rank by the asset's `<name>-version` marker, lexically last path as tie-break, and print the pick (`none` when nothing was found, and relative to `~`, since a gate review is a forge comment); a forge-kit checkout's own tree outranks any installed copy, since the tree is by construction newer than what was installed from it. The marketplace checkout is an ordinary git clone with an `origin` remote, so it is the one of the two that can be compared against a remote (#172). `forge-kit-governance` must be installed explicitly (`/plugin install forge-kit-governance@forge-kit`) for its `hooks.json` to load; the quick-start installs `forge-kit-adapt` alone. Prefer plugin registration where it applies, because it owns no user config and so has no wiring to drift, duplicate, or clobber, and that copy-and-mutate path was the origin of every hook bug in this repo's history.

**User level without forcing it on every project: the opt-in sentinel (#165).** A component
installed at user level is available everywhere, which is right for knowledge and wrong for
behaviour a project has not asked for. The answer is NOT a per-project copy, which is the
copy-and-mutate path this file already blames for every hook bug in the repo's history. It is a gate
the project owns. Two shapes, and the choice is not arbitrary:

- **Gate on the feature's own manifest** wherever the feature has one. `overnight-guard` gates on
  `.claude/overnight/active.md`, so arming a run IS the opt-in and no second file can fall out of
  sync with the first. Prefer this.
- **Gate on a dedicated sentinel** only where the feature has no natural manifest. `block-dashes`
  gates on `.claude/no-dashes`. It is one more file to create and one more thing that can disagree
  with reality, which is the whole cost of the shape.

A HOOK gates in the shell; the cost is measured below. A SKILL or COMMAND has no wrapper, so it can
only gate in its own prose: the first instruction reads the sentinel and stops when it is absent.
That is genuinely weaker, because a model can be argued out of an instruction where a shell cannot,
so use it only for components that ACT. **A knowledge skill is inert until invoked and needs no gate
at all**; adding one would be ceremony.

**A plugin hook is live in every project, so gate it in the shell, not in the interpreter.** `hooks.json` runs `sh -c`, which tests for the sentinel and exits before `exec python3` unless the project opted in: 1.8 ms per matched tool call in a project that has not, against 44 ms if Python starts first, because the interpreter pays for `site` and its stdlib imports before it can read its own gate. The gate inside `block-dashes.py` stays as defence in depth, and is the only gate for the project-local install shape, which has no wrapper. The wrapper requires `sh` on `PATH` (Git Bash on Windows); where that is unavailable, install project-locally.

Wire hooks in **exec form** (`"command": "python3"` plus `"args": ["${CLAUDE_PROJECT_DIR}/..."]`), never as a bare command string.

The failure that actually bites is a **relative** path. It resolves only when Claude Code's working directory happens to be the repo root; from a subdirectory `python3` cannot open the script and exits 2, and exit code 2 is precisely the PreToolUse *deny* signal, so every matched `Write`/`Edit`/`Bash` call is blocked with a confusing `can't open file` message. The hook does not go quiet, it wedges the session.

An **unbraced** `$CLAUDE_PROJECT_DIR` in a shell-form command is *not* broken, contrary to what an earlier revision of this file claimed. `${CLAUDE_PROJECT_DIR}` is a placeholder Claude Code substitutes, and separately the same value is exported into every hook process: the [plugins reference](https://code.claude.com/docs/en/plugins-reference) states the path variables are "exported as environment variables to hook processes" and that `${CLAUDE_PROJECT_DIR}` "is the same directory hooks receive in their `CLAUDE_PROJECT_DIR` variable." Shell form runs via `sh -c`, so the shell expands it. Prefer exec form anyway, because it is what the docs recommend and it removes shell quoting from the picture entirely: with `args` present Claude Code spawns the executable directly with no shell, substituting `${CLAUDE_PROJECT_DIR}` into each argument as a plain string.

Two distinct fail-open behaviours, do not conflate them. The script itself denies by printing a `permissionDecision: deny` JSON object on stdout and **always exits 0**, so its `except (json.JSONDecodeError, ValueError): sys.exit(0)` is a real fail-open: unparseable input never blocks a call. A *missing* script never reaches that code, and the interpreter's own exit status is what Claude Code sees.

**Component size budget.** Prose components carry a word budget, enforced by `scripts/check-component-size.sh` and visible as the Words column of the generated index. Hooks and shell assets are code and are not counted.

**A component costs two different things, and the budget governs only one of them (#174).** The **on-invoke** cost is the body, loaded when the component fires; that is what the word budget measures. The **always-on** cost is the `description`, loaded in every session where the group is enabled so the model can decide whether the component is relevant, and it was unmeasured until #174. The guard now reports it: a tree total on every run, and `--descriptions` for the per-component table. **It is reported, not budgeted**, in one sentence: a description that is too short stops the component being found, and an uninvoked component costs its description and delivers nothing, so a number to hit would push authors the wrong way. What is enforced is the floor, an agent or skill with no description or an empty one FAILS, since that component can never be selected. A COMMAND is exempt from the floor because three of this kit's commands carry no frontmatter at all and a slash command is found by its filename. The generated index does not carry the number: it is produced from the catalogue's TSV, and adding it would mean a second description parser, which is the duplication `check-component-size.sh` reusing `forge-adapt-agent-skills.sh` was meant to stop. The measurement, the eleven-component review it drove, and why `adapt` was deliberately kept at 819 characters are recorded in the guard's header with their date and CLI version.

| Type | Budget (warn above) | Hard ceiling (fail above) |
|---|---|---|
| agent | 2000 | 3000 |
| **orchestrator** (an agent whose `tools:` declares `Agent`) | **4000** | **6000** |
| command | 2000 | 3000 |
| skill | 2500 | 3750 |

The ceiling is 1.5x the budget. These numbers are duplicated in `check-component-size.sh`, and `scripts/test-component-size.sh` fails if the two disagree, because a policy stated in prose that nothing applies is the defect this repo keeps finding.

**An ORCHESTRATOR has its own number, stated rather than left as an exemption (#150).** An agent
that dispatches other agents carries two things a single-purpose agent does not: the briefs it
sends, which must travel with the dispatch or the callee depends on a copy that can drift, and the
rules it obeys while coordinating. The 2000-word budget was set for an agent that does one job, and
applying it to a coordinator produced a permanent breach that meant nothing. Membership is
MECHANICAL rather than a list: an agent whose `tools:` frontmatter declares `Agent`, which is what
lets it dispatch. Today that is `ticket-gate` alone. **The ratchet still applies on top**: the
ceiling says what the ROLE may cost, the ratchet says THIS instance may not drift upward.

**An agent is charged for what it PRELOADS (#150).** Verified against the installed Claude Code
(2.1.263): the subagent spawn path renders every skill named in an agent's `skills:` frontmatter and
pushes it into the message list before the run starts, so a companion skill is not somewhere else,
it is in the same context. Measuring one file made #109's split look like a reduction when it had
moved 308 words from one preloaded file into another. `check-component-size.sh` reuses
`forge-adapt-agent-skills.sh` to resolve the declarations rather than parsing frontmatter a fourth
time, and an agent whose companions cannot be resolved is REPORTED rather than measured as if it
declared none. `ticket-gate`'s baseline went 5259 to 6355 when this landed, which is a
**re-derivation and not a raise**: the file did not grow, the question did. It then went to 5782 and
then 5778, which IS a reduction: the companion skill's read-once artifacts moved into `references/`,
which are not preloaded, so 582 words came out of every run and no capability was given up for
them. Under the orchestrator ceiling it now has headroom, and the RATCHET is what still binds it. The
companion's own header had said preloading made #109's split reduce nothing; the knowledge was
recorded and the guard simply was not acting on it.

**The budget counts WORDS, the line count is reported beside it, and neither of those is an accident (#176).** Anthropic states one number for a skill body and it is lines: "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files." `adapt` is 820 lines against that tip, so #176 asked the obvious question and classified all 20 of its fenced blocks before moving any. **Sixteen are commands the skill runs and four are templates it emits. None is reference material.** The splitting convention forbids relocating either kind, since a step or a template read from a second file is a copy the caller depends on, so there is nothing to move and the file is the size the work is. `--descriptions` now reports each component's line count and marks anything over 500, as a visible externally anchored cross-check that gates nothing: a second ratchet on a number its own author calls a tip would fail components for the wrong reason, which is the same call #174 made about the always-on cost. The lever that has actually shrunk this file is the #149 one, converting a rule into a tested script, four times now.

**The CLI reports a token cost, and forge-kit deliberately does not enforce it (#170).** `claude --plugin-dir plugins/<group> plugin details <group>` projects a per-component token cost on a checkout, with no install and no network, in two columns: always-on and on-invoke. It is not adopted as the metric for one decisive reason, probed on 2.1.267 rather than argued: **it does not charge an agent for the companion skills it preloads.** A throwaway companion grown from 14 words to 5,000 moved its own on-invoke figure from `< 20` to `~7.2k` and left the declaring agent at `~40`, which is exactly the quantity #150 spent a phase establishing. It also rounds to two significant figures with a `< 20` floor, so a ratchet on it could not see a 200-word edit. The comparison is recorded in `check-component-size.sh` as a dated note, and `test-component-size.sh` fails if that note loses its date or its CLI version. Nothing in the guard reads it, because a cross-check that could fail a build is an adoption wearing a note's clothes, and the governance layer must not take a hard dependency on the `claude` CLI.

**It is a smell detector, not a quality metric.** The justification is this repo's own defect record, not context-window research: three review rounds on `ticket-gate.md` produced findings that were all symptoms of size rather than of any single edit (the same rule in four places updated in two, a 21-line bullet carrying seven rules, rules drifting from the steps they govern 400 lines away). A 2000-word file can still state one rule three times, so treat a warning as a prompt to hunt duplication, never as a licence to compress prose until it is dense but unclear. The often-cited "lost in the middle" result is about retrieval, and at least one study finds no position effect for instruction following, so do not lean on it.

**Three components are exempt, and the exemption is a ratchet, not a pass:** `adapt` (7209), `ticket-gate` (5767), `full-review` (3998). Each baseline is that component's size when the budget landed. An exempt component may shrink freely and **may not grow by a single word**; growth fails the build exactly as the ceiling does. **Raised three times, each by maintainer decision, and the guard records the reason for each.** On 2026-09-11 (`ticket-gate` 5709 to 5773, for #189): Step 3A's resolver had to rank installed copies by marker and print its pick, a correctness fix in the #147 shape, with 7 words of duplication left to pay with and a shell helper rejected because it would be found by the search it fixes. On 2026-09-07 (`ticket-gate` 5209 to 5265, for #147): a correctness fix that could not be paid for, because seven consecutive fixes had each already funded themselves out of duplication and a seven-word-shingle scan found none left. On 2026-09-10 (`adapt` 7300 to 7314, for #172): the drift report needed one line naming the marketplace staleness check, after #157, #166 and #167 had each already emptied that file of duplication. **That one was given back the same day**, when #178's retirement removed six rows from the file and returned it to 7300. Those three are the only exceptions in the numbers' history, every other edit having been a reduction, and that history is the evidence #150 turns on. `adapt` was lowered 7316 to 7312 on 2026-09-08 for the ordinary reason: #157 needed to name a fifth shell asset in its drift table, and naming the catalogue's `asset:` rows instead was both shorter and immune to going stale again. An agent must never raise a baseline on its own initiative; ask, and record the reason in the guard. Retrofitting them is out of scope of the budget itself, and the ratchet keeps the debt from growing while that waits. `ticket-gate`'s retrofit is the one that ran to a conclusion (#109, then #150): the splitting convention below forbids moving a rule the agent obeys, and what was left was almost entirely such rules, so the levers were scripting a step, dropping a capability, or changing the policy. Two of the three were used, and the third, dropping auto-synthesis, was never needed. `adapt` and `full-review` have had no such retrofit. When one shrinks, lower its baseline in the script to lock the gain in. Note that `full-review` is exempt because it measured 3998 against a 3000 ceiling, not because the ticket proposing the budget listed it; the exemption set was derived from measurement.

**Splitting convention, for when a component outgrows its budget.** Move *reference* material into a `references/` subdirectory beside the component, the pattern `forge-adapt` and `ticket-gate-reference` already use. Reference material is what the orchestrator reads once (lens definitions, checklists, taxonomies), never the step-by-step instructions or the rules governing them. **The main file stays canonical for every rule it obeys itself.** A reference may point at such a rule; it may never restate one, because this repo's review record shows content moved into a second location drifts from the first (the lens contract across two plugins, the doc-versus-gate restatement). If a rule appears in both, that is the bug, and the main file wins. The one refinement, learned splitting `ticket-gate` (#109): the dividing line is WHO OBEYS the rule. A brief dispatched verbatim to another agent carries the rules that agent follows, since separating them from the brief is what makes a callee depend on a copy that can drift.

**A reference must be named by its own SKILL.md, one level deep, and `scripts/check-reference-depth.sh` enforces it (#175).** The rule is Anthropic's and its reason is mechanical rather than stylistic: an agent meeting a reference INSIDE another reference may preview it with something like `head -100` instead of reading it whole, so it acts on half a file and nothing reports that it did. A partially read reference is worse than an absent one. The guard matches the FILENAME, not a link syntax, because this kit names references in prose backticks and one requiring `[x](references/x.md)` would have reported all 21 as orphans on its first run. It walks `skills/*/references/*.md` only: `agents/` has no `references/` and never will (#124), and `assets/` and `scripts/` are executed or copied rather than read into context. **A cross-link between siblings is fine** as long as both are named by SKILL.md, which is what `release-automation` does; the rule is about reachability, not about forbidding cross-links. It found three orphans on its first run against this tree, one of them the exact nested shape the guidance describes (`forge-host`'s `forgejo.md`, reachable only from `adopting-forge-lib.md`). Its honest limit is in its own header: it sees reachability, not liveness, so a SKILL.md naming a reference it no longer uses satisfies it. **`ticket-gate`'s shape is not a violation**: the companion skill's full body is preloaded into the agent at spawn (#150), so from the agent's position that skill's references are one hop from content it already holds. That was luck rather than design, and it is written down here so nobody "fixes" it or copies the shape somewhere it does not hold.

**An agent cannot have a `references/` directory, so it splits into a companion SKILL (issue #124).** `agents/` is a FLAT namespace owned by the Claude Code loader, which claims every `.md` beneath it **at any depth**. Probed against the shipped `claude plugin validate` (2.1.263): with `agents/<name>/AGENT.md` beside `references/lens.md`, only the reference file was reported as the agent and `AGENT.md` was silently skipped; `agents/references/<agent>/lens.md` was itself claimed as an agent; and a flat `agents/x.md` stopped being reported once any nested `.md` existed. An explicit `"agents": [...]` list in `plugin.json` does **not** suppress the glob. The docs agree that agents are flat files and that nested `AGENT.md` is "not supported (unlike skills, which use `skills/<name>/SKILL.md`)", and across ~40 installed plugins none of 251 agent files is directory-shaped. So this is a constraint of Claude Code, not a forge-kit choice, and it is why skills got `references/` and agents did not.

The supported split is the `skills:` frontmatter field, which injects a named skill's **full content** into the subagent at startup, written `plugin-name:skill-name` for a plugin skill. The companion skill is an ordinary component: its own marker, its own budget, already visible to the catalogue, `drift`/`refresh` and the size check, and it may use `references/` itself. The splitting convention above still governs, so the **agent stays canonical for every rule** and the companion skill may point at one but never restate it. forge-kit is early here: 0 of 251 installed agents use `skills:` today, which is why the resolver is a tested script (`scripts/forge-adapt-agent-skills.sh`) rather than prose. **A declared skill that is not installed fails silently**, skipped with only a debug-log warning, so forge-adapt installs an agent's declared skills and rewrites the identifier to the bare project-scope name.

**The area label set has ONE definition, and a copy that does not exist cannot drift (#188).** `docs/guides/labels.md` is canonical; `scripts/check-label-taxonomy.sh` fails the build when `.github/labels.yml` omits a declared area or when `check-ticket-mechanics.sh`'s `AREA_LABELS` default disagrees. **`ticket-gate.md` restates the set nowhere**, and the guard fails if it starts again: Step 0b carried its own copy until the first live gate run in this repository blocked on the first ticket, and that copy had drifted three ways at once, naming `frontend` (never a declared label) and `infrastructure` (declared a TYPE) while omitting `privacy` and `database`. Synchronising it would have been the weaker fix. **Three areas exist for a governance repository** (`components`, `tooling`, `governance`), because the other six are product-application areas describing nothing forge-kit itself works on, which is why every ticket filed here blocked. They route nothing, deliberately: prefer modulating the critic's brief over adding a lens.

**Label → lens routing:** `docs/guides/labels.md` documents the label taxonomy, and `forge-host/assets/sync-labels.sh` is what puts it ON the host (issue #104: it was declarative with no applier for months, so `security`, `critical` and `api` did not exist here and the gate's routing was unexercisable in the repo that ships it). Labels modulate the gate's review set: `security` and `critical` add the security lens (and `critical` puts the critic in maximum scrutiny); `api` adds the API-design checklist to the critic's brief without an extra agent; `privacy` adds the project's installed `privacy-regime` skill the same way. To add routing for a new label, add a row to the lens table in `ticket-gate.md`, preferring a critic-brief modulation over a new agent.

**The Precedence list is verified, not asserted (issue #125).** `docs/guides/ticket-standards.md` enumerates every place `ticket-gate` is allowed to restate a doc rule. That list used to certify its own completeness and was wrong three review rounds running, which is the worst shape for a claim like this: a maintainer edits the rule, edits what the list names, and ships a fork in the exact place the doc calls drift-free. `scripts/check-restatements.sh` now checks both directions, with no fuzzy matching: each item declares literal ANCHORS into the gate, a stale entry is an anchor that no longer resolves, and an unlisted restatement is a `rule N` reference in a section no anchor covers. An item with no anchor fails too, since an unanchored entry is what rotted before. A mention that genuinely restates nothing goes in an allowlist that REQUIRES a reason. It scans the agent, the companion `ticket-gate-reference` skill, **every file under that skill's `references/`** (#150 moved the lens briefs and templates one hop further so they stop being preloaded, and that orphaned an anchor the moment it landed), `check-ticket-mechanics.sh` (#149 moved Step 3A's checks there), and `decision-brief/SKILL.md` (#129, which promises to run the gate rather than copy its bars; this is what keeps that a promise). A restatement that moves ANYWHERE must stay visible to this guard, whether it moves into a reference, into a script or into a neighbouring skill, or relocating prose becomes a way to launder a rule out of its sight. The guard found a tenth location on its first run, rule 3's UI E2E bar restated as Step 3A's mechanical check, which no review round had named. Coverage is per LOCATION (a rule reference must sit within two lines of an anchor covering it), because per-section coverage was tried first and demonstrated worthless: once Step 3B was anchored for a rule anywhere, a new bar for that rule elsewhere in the section inherited the licence. An item naming more than one rule must SCOPE each anchor (`<!-- anchor: "..." :: rules N -->`), and an unscoped one is refused: making the scope merely available would not have closed the hole #138 described, because the items that leak are exactly the ones nobody would bother to scope. An anchor must be on one line (matching only its first line was a prefix match wearing an exact match's clothes), and an item citing no rule number is refused because it covers nothing. **It keys on the literal token `rule N`**, validated against the rule numbers the doc defines, so a paraphrase naming no rule is invisible to it; the doc says so rather than overclaiming, and adds the rule that a restatement must cite its rule number so the next one is detectable.

**Every step's round behaviour is in ONE table in `ticket-gate.md`'s Rules, and a new step or lens
needs a row (#103).** The round NUMBER those rows key on is counted from posted review comments by
`count-gate-rounds.sh` at Step 1, never read from the body (#192): a body edit erases the
`gate-verdict` block, and a count that restarts at 1 never reaches a caller's trip wire. When the
count is above 1 and the block is absent, the delta rows run FULL, the first-time-lens precedent. Six policies and two void triggers were scattered across that list and the
step bodies, so a new step had no defined round-2 behaviour and nothing asked its author for one:
the same shape as #97, a rule stated in N places with no single place that makes an omission
visible. The row that matters most is the one a review found missing: **a lens triggering for the
FIRST time in round 2**, because a label was added between rounds, runs in FULL scope, since delta
scope on a first run reviews nothing and reports clean.

**The lens result contract cannot drift between its two plugin groups (#103).** `ticket-gate`
dispatches the security lens with a result contract in its prompt, which fixes what the auditor is
ASKED for and not whether the installed auditor understands the ask; the two live in groups that are
versioned and installed independently. `scripts/check-lens-contract.sh` fails the build when the
`lens-contract-version` markers in `lens-definitions.md` and `security-auditor.md` disagree, and a
MISSING marker is skew rather than agreement. It keeps the SHIPPED pair honest and says plainly what
it does not do: a user holding the two groups at different versions still has skew, and only a
runtime check could see that.

**`/gate-ticket` versus a decision brief (#129).** They answer different questions and the wrong one wastes a round. The gate asks *is this ready to implement* and answers PASS, NEEDS-WORK or BLOCKED; reach for it before implementation. `decision-brief` asks *which option should the maintainer choose*, and is for a ticket that is stalled because a human has to decide something, not because the ticket is thin. The brief RUNS the gate as its first step rather than citing a stored verdict, because a verdict written before the standard moved describes a standard that no longer exists, and it carries no copy of the gate's bars, which `check-restatements.sh` now enforces on its file too. The two write DISJOINT regions of a ticket body (the brief owns its dated preamble and a `### Decision` section, the gate owns its required-changes section and the template's own sections), so they never contend; do not run a brief and a gate remediation on one ticket at the same time.

**Extending ticket-gate's routing:** The lens table inside `ticket-gate.md` maps labels and body keywords to specialist lenses. Add a lens agent only for a genuinely independent domain perspective; otherwise modulate the critic's brief (the `api` row is the pattern).

**ci-health command** (`/ci-health`) discovers all `.github/workflows/*.yml` files, checks the latest run for each, creates P0 tickets for failures, gates each ticket, and auto-implements safe fixes (lint, type, unit, build failures). It does NOT auto-fix E2E or security scan failures.

**The template-dir resolution order is duplicated at SEVEN sites, kept identical by a guard (issue #77).** The five-entry, HOST-grouped list appears in `check-template-lockstep.sh` twice (its header comment and `resolve_dir`), `ticket-gate.md`, `dep-auditor.md`, `adapt/SKILL.md` twice, and `forge-gate-mechanics.sh` (#182, which resolves a template directory outside the agent). **The guard scans git-TRACKED files, so a new copy is invisible to it until it is staged**, which is how #182's copy passed unseen until it was added. They diverged once already, case-grouped against host-grouped, before PR #74 merged, and only a review finding re-aligned them. `scripts/check-template-dir-order.sh` extracts every copy and fails if any two differ. Host-grouping is the load-bearing part: a repo migrated to Forgejo that kept a stale `.github/ISSUE_TEMPLATE` must resolve its LIVE lowercase Forgejo dir, and case-grouping silently inverts that.

**Why a guard rather than the shared resolver the ticket proposed.** The ticket's own trade-off concedes the prose sites must keep an inline fallback for projects where the script is not installed, so extraction shrinks the duplication from four sites to two, and the two left behind are the ones it calls most fragile. This is the same shape as the enforced path set (#112), where the catalogue must use globs while three consumers use an ERE, answered the same way. An ordering is told from prose by two things together: a run of ALL FIVE entries, separated by punctuation only. Words between the entries mean prose, and a shorter run means prose as well, which is what separates the six sites from the documentation passages that also name several of these directories (one of them enumerates all five with `and` before the last). The guard holds the canonical order as a definition and is deliberately NOT scanned as a copy of it: counting itself made the site list impossible to empty, so a tree with every copy deleted read as agreement. The one blind spot, a site edited below five entries dropping out of the comparison, is caught by the site count its contract test asserts.

**A producer never hardcodes the template version (issue #84).** `check-template-lockstep.sh` scans the template dir and the canonical doc, so a component that EMITS ticket bodies with a literal `template-version: 4` shipped green through CI and every machine-filed ticket was born stale, triggering a synthesis round-trip against a ticket the kit itself had just created. `dep-auditor` and `/ci-health` both did exactly that after the v5 bump. `scripts/check-producer-stamps.sh` now fails the build on `template-version:` followed by a digit anywhere under `plugins/`, with **no allowlist**, because a guard with one gets argued with. A producer resolves the version at runtime; prose refers to the marker in the `N` form. It anchors on the literal word `template-version`, so the per-component `<!-- <name>-version: N -->` markers, which all carry real digits, are untouched.

**Template versioning:** The `template-version: N` HTML comment in issue templates enables the `ticket-gate` agent to detect outdated templates and auto-synthesize missing sections without requiring manual upgrades. `ticket-gate` computes the current version from the **template directory only** and never reads `ticket-standards.md`, so the doc-to-template coupling lives entirely in `check-template-lockstep.sh`. That is why splitting the doc's rules onto `doc-rules-version` needed no change to the gate or the guard.

**`.full-review/` directory** is a runtime artifact created by `/full-review`. It persists state across interruptions so a review can be resumed, and its `round-<N>/` archives are the loop's only cross-round memory (prior reports feed trajectory and trip-wire computation), so deleting it ends the loop's history, not just a session. It is not part of the scaffold; add it to `.gitignore` in projects that run `/full-review`.

**`.claude/overnight/`** is the `working-overnight` runtime store (manifest, queue, decisions, report), gitignored here for the same reason `.full-review/` is: it is per-run state, not scaffold.

**`.superpowers/sdd/`** is the superpowers spec-driven-development runtime store (task briefs, per-task reports, progress files, review diffs). It carries its own `.gitignore` containing `*`, so it self-ignores and never appears in `git status`; do not add it to the root `.gitignore` and do not cite its contents as tracked history. The durable counterpart is `docs/superpowers/`, which **is** tracked.

**`temp/`** is a gitignored scratch folder (`temp/*` ignored, `.gitkeep` tracked). Use it for throwaway analysis output. Anything there is untracked by design, so never cite it as a source of truth or assume a later session can see it.

**Step 0c SYNTHESISES the body and writes it back BEFORE the mechanics run, which is why a raw ticket fails every check (#184).** The gate fetches the issue, and when the body has no `template-version` marker or an outdated one, Step 0c merges the missing sections, `gh issue edit`s the enriched body onto the forge, and only then proceeds to Step 3A. So inside a gate run the mechanical checks always see template-shaped input, and the rule that every FAIL is a blocking item holds. Run `forge-gate-mechanics.sh` against a ticket the gate has NOT processed and every section check fails for one reason, which is correct and not a contradiction: that script deliberately does not synthesise, since synthesis generates prose and needs a model. It detects the shape from TWO signals together, no marker AND no `### ` heading, because either alone is a different situation, and reports it once above the rows rather than per section. **Separately, and this is the finding underneath #184: the gate has never been run on this repository's own tickets.** Not one of the last thirty issues carries a gate review comment, and the only bodies containing `template-version` contain it in prose. Gating them retroactively would rewrite closed issues through `gh issue edit`, so it is a decision rather than a tidy-up.

**`docs/guides/without-claude-code.md` is the entry point for the OTHER audience (#183).** `AGENTS.md` answers "how do I change this repository" and points at CLAUDE.md; that page answers "how do I use this governance in my own project with a different agent, or none" and is written for a reader with no forge-kit vocabulary. It names the four portable artifacts, the shell that can actually be run, and a table of what is NOT available, which is the part that makes the rest credible: the critic, the verdict, auto-synthesis, the hooks, the size budget, drift detection and forge-adapt all need Claude Code. **The rules are portable and the mechanical checks are portable; the judgement is not.** Keep that page honest before making it shorter.

**`docs/roadmap.md`** is forge-kit's own roadmap, and the repo is the first project to install
`forge-kit-roadmap`. It owns which phases exist and their state; the host's milestones own which
phase each ticket is in. Never record phase membership in the roadmap: that is the duplication the
design exists to avoid. `docs/plans/<phase>.md` holds the plan for a phase, written when it opens
and never before, and every plan carries a **Fails if** section written as a premortem. The
`.githooks/pre-push` hook runs the guard's OFFLINE half only, because a push must not depend on the
host being reachable; the three host rules run in CI and from `/phase`.

**`.claude/memory/MEMORY.md`** is the tracked, team-visible project memory index. Durable decisions and in-flight context belong there, one line per entry pointing at a sibling file. **`.claude/handoffs/`** holds dated session-resume notes written by the `closing-sessions` skill; both stores are what that skill targets when a session wraps up.

**`docs/superpowers/`** is the design paper trail: `specs/` (brainstormed designs) and `plans/` (implementation plans) for shipped components such as `closing-sessions`, `working-overnight`, and the overnight-guard hook. Read the relevant spec before redesigning one of those.

## Workflow

**Work happens on `develop` and is merged to `main` when green. No pull requests**
(maintainer decision, 2026-09-08). Commit and merge without waiting to be asked.

**Gate a ticket before implementing it (maintainer decision, 2026-09-10).** Run `/gate-ticket <N>`
on every NEW ticket before work starts. The reason is dogfooding rather than ceremony: #184 found
that this repository ships a ticket gate and had never gated a ticket, with not one of the last
thirty issues carrying a gate review comment, so the kit's most distinctive mechanism was
unexercised on the repository that ships it, exactly as the label taxonomy was before #104. Expect
Step 0c to fire on a hand-filed ticket: it synthesises the missing sections and rewrites that
ticket's body on the forge, which is the behaviour nobody here had seen on a live ticket.
**Existing closed tickets are NOT retro-gated**, because Step 0c would rewrite bodies of work
already shipped.

**Both range guards now run on `push` as well as `pull_request` (#158).** They were
`pull_request`-only, so once work stopped arriving as pull requests they ran on no path at all and
`.githooks/pre-push` was the only thing enforcing them. The base is resolved by
`scripts/resolve-range-base.sh`, a TESTED script rather than a YAML expression, because
`github.event.before` is the all-zeroes sha on a created ref and may name an object discarded by a
force push; either would make the guards pass vacuously, which is worse than the gap they had. It
resolves a base or REFUSES, and prints nothing to stdout when it refuses so a caller cannot
accidentally use its explanation as a revision. The pre-push hook is still worth enabling, since it
gives the same answer before the push rather than after.

`validate.yml` also triggers on `push` to `develop`. It did not at first, and the effect was
worse than the range-guard gap: with `pull_request` never firing and `push` matching only `main`,
**no CI ran on develop at all** and every check ran for the first time after the merge.

1. Branch from `develop` only if the work needs isolation; otherwise commit to `develop` directly.
2. Commit with a conventional-commit subject (`feat(...)`, `fix(review)`, `docs(...)`, `chore(...)`),
   bumping the `<name>-version` marker of every component the commit touches, plus the `plugin.json`
   semver of every plugin group it touches.
3. Run the structural and contract checks above.
4. Push `develop`, watch its `Validate` run, then fast-forward `main` onto it and push.

```bash
git checkout develop
git add <changed files>
git commit -m "feat(<scope>): <concise message>"
git push origin develop          # pre-push runs the range guards and the leak guard
git checkout main && git merge --ff-only develop && git push origin main
```

Do this at the end of every task without waiting to be asked. Watch the `Validate` run on main
(`gh run watch`) rather than assuming it passed: on this path there is no PR check to block a bad
merge, so the run is a report after the fact.
