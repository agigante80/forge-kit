---
name: release-automation
description: Enforce and automate releases in CI so a promotion to the production branch can never silently ship without a version bump. Installs a release gate (block a PR that did not bump the version past the last release) plus, on the same shared version<->tag primitive, optional auto-release lanes (auto-release a dependency-bot update; auto-release every merge on a CD trunk). The enforced/automated sibling of the invoked `release` skill. Generic template - forge-adapt tailors the production branch, version source, and CI provider. Use when the user asks to "enforce version bumps", "block merge without a release", "auto release on merge", "auto-release dependency updates", or "stop forgetting to tag releases".
---

<!-- release-automation-version: 8 -->

# Release automation

Make the missing release impossible. The `release` skill is the *invoked* ship someone runs;
this is the *unattended* CI layer that runs without being invoked, so a merge to the production
branch with no version bump is **blocked** (or, where appropriate, auto-bumped), never silently
shipped. It is a generic template: `forge-adapt` tailors the production branch, the version
source, and the CI provider.

> **Composition, not duplication.** Semver rules and the version source live in
> `docs/versioning.md` and the `release` skill. This skill *enforces* them, it does not restate
> them. See `references/semver-operator-contract.md` and `references/source-of-truth.md`.

## The one mechanism: version vs latest tag

All lanes share a single primitive (`assets/version-lib.sh`) that compares the working-tree
version against the latest **released tag** (not the previous commit; the tag is the only truth
for "what is released") and prints one verdict:

| Verdict | Meaning | What a lane does with it |
|---|---|---|
| `first-release` | no release tag yet | allow |
| `ahead` | version > latest tag, already bumped deliberately | **ship as-is, never re-bump** |
| `equal` | version == latest tag, nobody bumped | the lane's policy decides (block, or auto-patch) |
| `behind` | version < latest tag, branch is stale | **hard stop (regression)** |

The `ahead`/`behind` handling is the load-bearing part: it is what stops a naive "always patch on
merge" from double-bumping a deliberate `1.5.0` into `1.5.1`, and what refuses to publish a
regression. Build the comparison once (this script); each lane is a thin policy on top.

Two scripts, single-sourced: **`version-lib.sh`** is the pure read-only verdict (used directly by
the gate); **`release-run.sh`** is the shared side-effecting driver for the write-lanes (B and C):
recursion guard, optional dependency scope gate, decide+bump, idempotent tag+release. Lanes B and C
are thin YAML wrappers that set env and call `release-run.sh`, so a mechanics fix lands once, not
copy-pasted. `release-run.sh` also honours `DRY_RUN=1` (print would-be actions, write nothing).
Every source reader yields *empty* (never a sentinel) when the version is absent, and the verdict
validates the value is semver-shaped, so a misconfigured source fails closed with a clear error
rather than tagging garbage (e.g. `vundefined`).

## The three lanes (route by who authored the change)

| Lane | Trigger | Policy on `equal` | Default? |
|---|---|---|---|
| **A (Gate)** | PR to the production branch | **block the merge** | yes, every project |
| **B (Auto-release on dependency)** | bot PR (Dependabot/Renovate), CI green | auto-patch + tag + release | yes, if a dep bot is present |
| **C (Auto-release on merge)** | every merge to the production branch, CI green | auto-patch + tag + release | opt-in, true CD trunks only |

The routing rule: **auto-bump only where there is no human author and impact is bounded**
(dependency updates); **gate where a human must declare impact** (feature/fix PRs). A gate fails
loud and early and needs no tokens; auto-bump needs an App token + a recursion guard + concurrency
control, so it is confined to the lanes that genuinely earn it.

> **Status:** all three lanes ship (**A (gate)**, **B (auto-release on dependency)**, and
> **C (auto-release on merge)**) on the shared `version-lib.sh`. The write-lanes (B/C) carry the
> App-token + recursion-guard handling (`references/github-token-gotcha.md`). Tag-derived Python
> projects (`setuptools-scm`/`hatch-vcs`) are supported via `VERSION_SOURCE=git`
> (`references/python-tag-derived.md`).

## Lane A: the release gate (install this)

`assets/lane-a-gate.yml` runs on every PR to the production branch: it checks out full history +
tags, runs `version-lib.sh`, and **fails unless the verdict is `ahead`/`first-release`**. `equal`
means "you didn't bump: do it (patch/minor/major per `docs/versioning.md`)"; `behind` means "this
branch is stale, rebase". This is exactly the `release` skill's "bumped past the last tag"
precondition, moved from *checked when you run release* to *enforced on every PR*.

Zero machinery: no tokens, no recursion, no concurrency. It only reads.

## Lane B: auto-release on dependency update

`assets/lane-b-auto-release-on-dependency.yml` is the one auto-bump that is safe by construction:
the author is a dependency bot (no human to make the bump call) and the impact is bounded
(consume an upstream release → PATCH). On `workflow_run` after CI is green it checks out the
validated `head_sha`, confirms the change is **bot-authored and confined to dependency
manifests/lockfiles**, then acts on the `version-lib.sh` verdict: `equal` → auto-patch + commit +
push; `ahead`/`first-release` → release the current version as-is (a first release must not be
patched, or the initial version is skipped); `behind` → refuse (regression). Then it tags and cuts
the release (idempotently, so a re-run never double-tags).

Because it writes, it needs an **App token** (so the pushed tag triggers the downstream publish
workflow) and therefore a **recursion guard + concurrency**: adopting that token forfeits the
default token's free loop immunity. Dependency **majors**, and anything not bot-authored or not
dependency-only, fall through to the Lane A gate. This is the lane that ships an upstream
security/CVE fix without a human in the loop. See `references/github-token-gotcha.md`.

## Lane C: auto-release on merge (opt-in, CD trunks)

`assets/lane-c-auto-release-on-merge.yml` is the blanket auto-bump: **every** green merge is
released (no dependency scope gate). Same verdict handling and write-lane machinery as Lane B, just
applied to all merges. Use it **only on a true continuous-deployment trunk** where every merge is
genuinely a release. For deliberate/batched releases use the Lane A gate. The two are mutually
exclusive on the `equal` policy (the gate *blocks* an unbumped merge; this *auto-patches* it),
though they can coexist as "gate + auto-tag" (the gate forces every merge to be `ahead`, so this
lane only tags the already-chosen version).

It also supports **tag-derived** projects (`VERSION_SOURCE=git`, e.g. `setuptools-scm`/`hatch-vcs`):
there is no file to bump, so a release is just the next **tag**, no commit. In git mode the verdict
is always `equal`, so it carries no signal; `release-run.sh` instead gates on `unreleased_commits`,
releasing only when there are commits since the latest tag. Otherwise a CI re-run on an
already-tagged HEAD would cut a phantom tag every time. A project with no tags yet is left untouched
until you push an initial tag to bootstrap. See `references/python-tag-derived.md`.

> **Lane C supersedes Lane B: never install both.** Lane C already releases every merge (dependency
> merges included); co-installing makes both fire on the same CI run, share the concurrency group,
> and the second bump conflicts with the first. Choose: the Lane A gate (deliberate releases) **or**
> Lane C (CD); and Lane B only when you have the gate, not Lane C.

## Install (what forge-adapt does)

1. Pick the canonical **version source** (`references/source-of-truth.md`) and set the workflow's
   `env:` block (`VERSION_SOURCE`/`VERSION_FILE`/…) + the `version-lib.sh` path.
2. Copy `assets/version-lib.sh` into the project (e.g. `scripts/version-lib.sh`), stack-agnostic,
   `chmod +x`. Also copy `assets/release-run.sh` alongside it if installing Lane B or C (the gate
   needs only `version-lib.sh`). For a non-file writable source (node/python/cargo), replace
   `release-run.sh`'s file-write bump with the project's bump command (the comment marks the spot).
3. Copy `assets/lane-a-gate.yml` to `.github/workflows/release-gate.yml`, setting the production
   branch. Recommend making the `version-bumped` job a **required status check** on the branch:
   the gate only governs once it can block merges.
4. Generate/update **`docs/versioning.md`** from `references/semver-operator-contract.md`, in the
   project's own terms (its env vars, volumes, platforms).
5. Add **Lane B** (`assets/lane-b-auto-release-on-dependency.yml`, with `release-run.sh`) when
   `dependabot.yml` / `renovate.json` is present: wire the CI workflow `name:`, the production
   branch, the bot logins (`BOT_LOGINS`), the `DEP_PATHS` globs, and the App-token secrets
   (`references/github-token-gotcha.md`).
6. Offer **Lane C** (`assets/lane-c-auto-release-on-merge.yml`, with `release-run.sh`) only for a
   true continuous-deploy trunk, as an *alternative* to the Lane A gate. **Do not co-install Lane B
   and Lane C** (C supersedes B). For a tag-derived Python package set `VERSION_SOURCE=git` and
   follow `references/python-tag-derived.md` (and skip the Lane A file-bump gate, which is moot
   without a version file).
7. Install the `release` skill as the companion **invoked** workflow (the gate enforces; `release`
   is how a human cuts the release).

## Interaction with the rest of the kit

- **`/ci-health`** discovers all workflows and auto-fixes "safe" CI failures, but a red release
  gate is an *intentional governance signal* (the author must bump), not a breakage. `ci-health`
  treats release/version-gate workflows as investigate-only (do **not** auto-fix), the same
  carve-out it uses for E2E and security scans. Never let `ci-health` "fix" a gate by auto-bumping.
- **`dep-auditor`** finds dependency problems and files tickets; **Lane B** ships the bot's update
  once CI is green. They compose (auditor finds → bot updates → Lane B releases).
- **Component markers** (`<name>-version`) and forge-kit's own `check-version-bump.sh` version the
  governance *components*; this skill versions the *product*. Different axes: do not conflate.

## Adapting this skill (notes for forge-adapt)

- Set the production branch, the version source `env:`, the CI provider, and the script path.
- Make the gate a required check; without that it advises but cannot enforce.
- Generate `docs/versioning.md` tailored to the project; leave the bump *level* to the author.
- Preserve the `<!-- release-automation-version: N -->` marker when adapting, so drift stays
  detectable. Honour any project writing rule (e.g. the no-dash hook) in release notes/comments.
