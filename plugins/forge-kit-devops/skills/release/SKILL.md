---
name: release
description: Cut a versioned release - bump the project's semver across all version sources, keep doc version markers in sync, verify CI is green, tag, and close the tickets the release shipped. Includes a version-check guard (fail if version sources disagree) for CI/pre-commit. Generic skill - forge-adapt tailors the version files, branching model, tag format, and publish pipeline to the project. Use when the user asks to "release", "cut a release", "bump the version", "ship vX.Y.Z", or "tag a release".
---

<!-- release-version: 3 -->

# Release

Promote the current code to a versioned release: bump semver, keep every version source in
sync, verify the pipeline is green, tag, and close the tickets the release ships. Honest
reporting throughout - **never claim "released" until the publish/CI pipeline is actually green.**

> **Generic template.** `forge-adapt` adapts the version sources, branching model (trunk vs
> develop-to-main), tag format, and publish-pipeline checks to the project.
>
> **This skill is the *invoked* ship.** To make its "bumped past the last tag" precondition
> *unforgettable* — enforced on every PR, not just when someone runs a release — install the
> `release-automation` skill (the CI gate + auto-release lanes built on the same version↔tag math).

## Version sources (single source of truth + mirrors)

A project has one canonical version and usually several places that must agree. Identify them
during adaptation:

| Ecosystem | Canonical | Mirrors that must match |
|---|---|---|
| Node / TS | `package.json` `version` (or a `VERSION` file) | lockfile, doc markers (`**Version:**`), container labels |
| Python | `pyproject.toml` `project.version` (or `__version__`) | `__init__.py`, docs |
| Rust | `Cargo.toml` `package.version` | `Cargo.lock`, docs |
| Go / generic | a `VERSION` file or git tag | docs, embedded build var |

**Rule:** one source is canonical; everything else is derived and must be kept equal to it.

## The version-check guard (wire into CI + pre-commit)

The cheap, high-value piece: a script that **fails if the version sources disagree**, so drift is
caught before release, not during. Generic shape - adapt to the project's actual sources; with a
single source there is nothing to cross-check, so the guard is a no-op:

```bash
# Two-mirror example: package.json is canonical, VERSION mirrors it. (Node-specific - swap the
# files for pyproject.toml/__init__.py, Cargo.toml/Cargo.lock, etc.) Compares the base version,
# ignoring any pre-release metadata after the first '-'.
[ -f package.json ] && [ -f VERSION ] || { echo "single source; nothing to cross-check"; exit 0; }
a=$(jq -r '.version // "missing"' package.json); b=$(cat VERSION)
[ "${a%%-*}" = "${b%%-*}" ] || { echo "version mismatch: package.json=$a VERSION=$b"; exit 1; }
```

Run it in the `Validate` CI workflow and/or pre-commit. This is exactly the pattern proven in
actual-mcp-server's `version-check.js`.

## Bump modes (semver)

| Mode | Effect |
|---|---|
| `patch` / `minor` / `major` | bump the canonical version, propagate to all mirrors, sync doc markers |
| `sync` | do NOT bump; only re-sync mirrors + doc markers to the current canonical (fixes drift) |

Choose the level per the project's `docs/versioning.md` — the single semver authority (the
operator-contract: breaking the deployment → major, opt-in feature → minor, fix/CVE/dep → patch).
Bumping is a single committed step (`chore(release): bump version to X.Y.Z`) BEFORE the release
runs. The bump *level* is a human judgement; do not auto-infer it.

## Release flow

1. **Preconditions (verify, never force):**
   - the version was bumped past the last published tag (else: bump first),
   - the version sources agree (run the version-check guard),
   - CI is green on the HEAD being released (a red or in-progress pipeline is not releasable).
   Report exactly which precondition failed and the single next action; do not `--force` past it.
2. **Compute the release manifest:** the tickets this release ships. Read them from commit
   **subjects** in the release range (`git log <range> --pretty=%s`), matching the
   Conventional-Commit suffix `(#N)`. Do NOT scan commit **bodies** - they reference CVE/alert
   numbers and cross-links that are not tickets to close.
3. **Integrate + tag:** advance the release branch per the project's branching model
   (`git merge --ff-only` for develop-to-main; tag directly on trunk otherwise). If integration is
   not a clean fast-forward, STOP - the branches diverged and need manual reconciliation.
4. **Verify green, then claim:** pushing fires a fresh CI run on the new commit/tag. Wait for it
   to conclude `success` before reporting the release as shipped. Never report "released" on an
   in-progress or red run.
5. **Close shipped tickets:** close each ticket from step 2 with a comment referencing the
   release version. This is the step most easily forgotten by hand.

## Output / reporting

Report: version bumped (old → new), tickets shipped + closed, tag created, pipeline status.
If a precondition blocked the release, report the blocker and the one next action instead.

## Scope boundary

This is the release/versioning workflow. It is distinct from the per-component
`<name>-version` markers forge-kit uses for adapt-drift detection - those version individual
governance components, this versions the *product*.

## Adapting this skill (notes for forge-adapt)

- Identify the canonical version source + mirrors; generate the project's `version-bump` and
  `version-check` scripts (wire version-check into the `Validate`/CI workflow and pre-commit).
- Set the branching model (trunk-tag vs develop-to-main) and the tag format (`vX.Y.Z` vs `X.Y.Z`).
- Set the publish-pipeline check (which workflow/run must be green before claiming released).
- If the project gates work behind tickets, keep the `(#N)`-subjects manifest + close step;
  otherwise drop it.
- Enforce the project's writing rules (e.g. the no-dash hook) in release notes/comments.
