# Forgejo CI / auto-release: what's implemented vs runner-gated

The runner-FREE forge operations (issues, tags, releases via `forge_*`) are done and verified, and
**`forge_ci_status`'s Forgejo branch is implemented AND live-verified**: against a real
`forgejo-runner` (v12) on Forgejo 11, a pushed `.forgejo/workflows/` job went `pending` then
flipped the combined commit status to `success`, and `forge_ci_status` returned `success` for
both the SHA and the branch ref. The only remaining **runner-gated** item is the auto-release
lane (below). Use placeholders (`https://forge.example.com`). Never commit a private host.

## Forgejo Actions in one screen

- GitHub-Actions-compatible. Reads **`.forgejo/workflows/`** *and* `.github/workflows/`.
- Runners are **self-hosted and optional**: a repo can have none (then nothing runs; the
  governance components fall back to local gates, e.g. `make test`).
- Each job gets an **automatic token** (`${{ secrets.GITHUB_TOKEN }}` / `FORGEJO_TOKEN`) scoped to
  the repo. **There is no GitHub-Apps equivalent** and no `actions/create-github-app-token`.

## `forge_ci_status`: the Forgejo branch (implemented: commit-status)

**Implemented (`forge-lib.sh`): the combined commit-status API, not the Actions API.** Forgejo
Actions writes a **commit status** per job (verified in Forgejo source `services/actions/
commit_status.go`: `toCommitStatus` maps each Actions status onto a commit-status state), and
Forgejo exposes the same `GET /repos/{o}/{r}/commits/{sha}/status` combined endpoint GitHub has. So
"is CI green?" is **one rolled-up call**, simpler and more robust than listing/aggregating the
version-split `/actions/runs` (v12+) vs `/actions/tasks` Actions API. `forge_ci_status`'s Forgejo
branch does exactly this:

```sh
# Resolve to a SHA (combined status has quirks on branch/tag refs), then read .state/.total_count.
sha=$(git rev-parse "$BRANCH"); cs=$(forge_api GET "/repos/$(forge_repo)/commits/$sha/status")
# total_count==0 -> no statuses -> not_configured (no CI / no runner); else map .state:
#   success->success | pending->pending | failure|error->failure
```

Mapping caveats baked in: pass a **SHA**, not a branch; Actions maps `skipped→success` and
`cancelled→failure` (so those don't surface distinctly); `warning` never appears from Actions; and
**`total_count: 0`/no-statuses means "not run", not "failed"**, so a runner-less repo stays
`not_configured` and callers keep the local-gate fallback. **Runner-gated remainder:** confirming a
real *green* run actually flips the combined status to `success` needs a live runner to produce one.

**Hard fact: job LOGS are NOT reachable via the Forgejo API** (the Actions-API PR added no log
endpoints; only artifacts via `/actions/artifacts/{id}`). So on Forgejo `ci-health` can **detect** a
failed run (via the commit status) but **cannot fetch logs to auto-fix**: its Forgejo path must be
detect-and-ticket only, never auto-fix-from-logs.

## Auto-release lanes (B/C) on Forgejo

The lane workflows are GitHub-Actions-specific in three places; the Forgejo mirror lives in
`.forgejo/workflows/` and differs as follows:

| GitHub lane | Forgejo equivalent |
|---|---|
| `actions/create-github-app-token` (so the pushed tag triggers the publish workflow) | **No App** on Forgejo. The auto job token (`FORGEJO_TOKEN`/`GITHUB_TOKEN` alias) is repo-scoped and, like GitHub's, **suppresses downstream triggers** ("no workflow is triggered as a side effect of a change authored with this token"). To chain a publish off a pushed tag, push with a **PAT stored as a repo/org secret**, not the auto token. |
| `gh release create --generate-notes` | `forge_release_create <tag> <title> "<notes from git log>"` (no auto-notes on Forgejo, so build notes from `git log $PREV..HEAD`). `release-run.sh` should call `forge_*` when the host is Forgejo. |
| `on: workflow_run` (chain off the CI workflow) | **Forgejo does NOT support `workflow_run`** (verified: unimplemented). Don't chain a separate release workflow off CI completion. Instead make the release a **final job in the CI workflow itself** (gated on the prior jobs), or use **`workflow_call`** (which Forgejo does support) / `workflow_dispatch`. |

The **recursion guard** (`chore(release): automated version bump` subject), **concurrency**, the
**idempotent tag/release**, and the **version-vs-tag logic** (`version-lib.sh`) are all host-agnostic
and carry over unchanged: only the token, the release-create call, and the trigger model differ.

## de-`gh` the inline snippets (carry-over from phase 2)

Independent of the runner: the adopted components (`ticket-gate`, `dep-auditor`) keep inline `gh …`
snippets as the GitHub reference form behind their host-aware preamble. A cleanup pass should replace
those inline snippets with their `forge_*` equivalents so an agent can't pattern-match a raw `gh`
command and run it on Forgejo. Runner-free; do it any time.

## Order of operations once a runner is up

1. DONE: runner stood up (`forgejo-runner` v12, native binary + systemd, `docker_host:
   automount`, labels `docker` + `ubuntu-latest`); a trivial `.forgejo/workflows/ci.yml` ran.
   Note: Forgejo queues Actions tasks even with no runner, so pre-existing pushes execute the
   moment a matching runner appears (a repo's CI can go live retroactively).
2. DONE: `forge_ci_status` live-verified: the passing job flipped the combined commit status
   `pending` then `success`, and the function returned `success` for both SHA and branch refs.
3. Mirror the auto-release lane(s) into `.forgejo/workflows/` with the token/notes/trigger
   differences; verify a real dependency merge produces a tag + release.
4. Then `ci-health`'s Forgejo path (needs run logs), only if the API exposes them.
