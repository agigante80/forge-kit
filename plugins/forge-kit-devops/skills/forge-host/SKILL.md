---
name: forge-host
description: Make governance components forge-host-aware (GitHub or self-hosted Forgejo/Gitea) instead of GitHub-only. Ships a thin shell adapter (forge-lib.sh) that detects the host per-repo and exposes host-agnostic forge_* operations (issues, comments, releases/tags, CI status) backed by `gh` for GitHub and `curl`+REST for Forgejo. Additive and backward-compatible: a repo with no Forgejo config behaves exactly as before. Use when a project is migrating repos from GitHub to a self-hosted Forgejo, when a component shells out to `gh` but the repo may be on Forgejo, or when you need deterministic per-repo host detection.
---

<!-- forge-host-version: 6 -->

# forge-host: host-aware forge operations

Several forge-kit components assume GitHub: they shell out to `gh`, hit `api.github.com`, read
`.github/workflows/`, or carry a `{{GITHUB_REPO}}` placeholder. When a repo moves to a self-hosted
**Forgejo** (or Gitea) instance, those stop working. This skill makes the forge operations
**host-aware** behind one adapter, so the same governance logic runs on either host.

> **One adapter, not two skills.** Closing an issue, cutting a release, or checking CI is the *same
> contract* with a *different transport*, an adapter concern. A single `forge-lib.sh` (the analogue
> of `release-automation`'s `version-lib.sh`) keeps the contract in one place; per-host quirks live
> in `references/`, not a second skill.

## The model

- **Detect the host per-repo** (never assume GitHub), deterministically, so it works unattended in
  CI/hooks, not just interactively.
- **Abstract the operations** the components need (issues, comments, releases/tags, CI status)
  behind `forge_*` functions with two backends: **GitHub (`gh`)** and **Forgejo (`curl` + REST)**.
- **Additive:** a repo with no `.forge.conf` defaults to GitHub and behaves exactly as today.

Both backends speak **REST** (GitHub via `gh api`, Forgejo via `curl`), *not* `gh`'s porcelain,
because Forgejo's API is the Gitea API, whose JSON shapes for issues/releases/comments closely
match GitHub's REST, so callers' `jq` parsing stays identical across hosts.

## Host detection (first match wins, deterministic)

1. `$FORGE_HOST` env var: explicit override (e.g. in CI).
2. A committed **`.forge.conf`** at the repo root (`assets/forge.conf.example`).
3. The git remote URL: `github.com` → github; otherwise forgejo **iff** a Forgejo API URL is
   configured, else github.

The committed `.forge.conf` is the canonical answer for a repo that has **both** remotes during
migration: detection must not "ask" in automation. A GitHub-only repo needs no config.

## The adapter (`assets/forge-lib.sh`)

Source it; call `forge_*` instead of `gh` directly:

| Function | Purpose |
|---|---|
| `forge_host` / `forge_repo` / `forge_api_base` | detection + identity |
| `forge_api <METHOD> <path> [body]` | authenticated REST call (the low-level primitive) |
| `forge_issue_view <n>` / `forge_issue_list [state]` | read issues |
| `forge_issue_comment <n> <body>` / `forge_issue_close <n>` | act on issues |
| `forge_issue_create <title> <body>` | open an issue (labels omitted, added with the next op) |
| `forge_issue_label <n> <name…>` | add labels by name (resolves names→IDs on Forgejo) |
| `forge_tag_exists <tag>` / `forge_release_create <tag> [title] [notes]` | releases/tags |
| `forge_ci_status <branch>` | `success\|failure\|pending\|none\|not_configured` (Forgejo via the combined commit-status API; github via `gh run list`, also passing raw GH conclusions like `cancelled` through) |

`FORGE_DRY_RUN=1` prints would-be requests (to stderr) instead of sending them. Run
`bash forge-lib.sh detect` for a one-line host/repo/api/ci diagnostic.

**CI status degrades gracefully.** On Forgejo with no runner yet, `forge_ci_status` returns
`not_configured` (rather than failing), so a caller can fall back to a local gate (e.g. `make
test`) instead of hard-failing. **The Forgejo branch is implemented** via the combined commit-status
endpoint (`/commits/{sha}/status`): Forgejo Actions writes a commit status per job, so one call
yields `success`/`failure`/`pending`, and `total_count: 0` (no statuses, e.g. no runner) →
`not_configured`. Only confirming that a real green run flips the status still wants a runner
(`references/forgejo-ci.md`). GitHub's combined status does NOT reflect Actions (those are Checks),
so the github path stays on `gh run list`.

## Install (what forge-adapt does)

1. Copy `assets/forge-lib.sh` into the project (e.g. `scripts/forge-lib.sh`), `chmod +x`.
2. For a **Forgejo** repo (or a dual-remote repo mid-migration), copy `assets/forge.conf.example`
   to `.forge.conf`, fill it in, and commit it. Export the token in the runtime env (never commit
   it). A GitHub-only repo needs neither.
3. Components adopt the adapter by replacing direct `gh` calls with `forge_*`; see
   `references/adopting-forge-lib.md` for the per-component swaps.

## Scope (phase 1 vs later)

This skill is the **foundation**: detection + the marker + the adapter contract, with the
runner-free operations (issues, comments, releases/tags) implemented for both hosts. Adopting it
across the GitHub-coupled components (`ci-health`, `release`/`release-automation`, `ticket-gate`,
`gate-ticket`, `dep-auditor`, `health-check`, forge-adapt's `templates` mode) is the follow-on
work; the CI/Actions backend (and porting `release-automation`'s GitHub-App-token lanes) is gated
on a Forgejo runner, designed in `references/forgejo-ci.md`. See `references/adopting-forge-lib.md`
for the per-component swaps. (The invoked `release` skill is already host-aware for its tag/release/
ticket-close steps; only its remote-CI-green check is runner-gated and degrades to `not_configured`.)

## Notes for forge-adapt

- Detect the host from the remote during analysis; if a non-GitHub remote has no `.forge.conf`,
  offer to create one (don't silently assume GitHub for a clearly-Forgejo remote).
- Preserve the `<!-- forge-host-version: N -->` marker when adapting.
- `forge-lib.sh` is stack-agnostic: copy it verbatim like a hook, don't rewrite it.
