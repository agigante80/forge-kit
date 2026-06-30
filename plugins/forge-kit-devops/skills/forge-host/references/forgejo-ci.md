# Forgejo CI / auto-release — the runner-gated path (design; verify against a live runner)

The runner-FREE forge operations (issues, tags, releases via `forge_*`) are done and verified. The
CI-execution pieces below need a **Forgejo Actions runner** to build and test, which is why they are
a documented design rather than shipped, verified code. Implement + verify each against a live runner
before relying on it. Use placeholders (`https://forge.example.com`) — never commit a private host.

## Forgejo Actions in one screen

- GitHub-Actions-compatible. Reads **`.forgejo/workflows/`** *and* `.github/workflows/`.
- Runners are **self-hosted and optional** — a repo can have none (then nothing runs; the
  governance components fall back to local gates, e.g. `make test`).
- Each job gets an **automatic token** (`${{ secrets.GITHUB_TOKEN }}` / `FORGEJO_TOKEN`) scoped to
  the repo. **There is no GitHub-Apps equivalent** and no `actions/create-github-app-token`.

## `forge_ci_status` — the Forgejo branch to implement

Today `forge_ci_status` returns `not_configured` on Forgejo (graceful). When a runner exists,
replace that arm with a query against the **Gitea/Forgejo Actions API**. Candidate (verify the exact
shape on your version — the Actions API is newer and less complete than GitHub's):

```sh
# GET /repos/{owner}/{repo}/actions/tasks  (or .../runs on newer Forgejo) -> list of runs/tasks.
# Map the latest run for $branch: status (waiting|running|success|failure) -> our vocabulary.
forge_api GET "/repos/$(forge_repo)/actions/tasks" \
  | jq -r --arg b "$1" 'first(.workflow_runs[]? // .tasks[]? | select(.head_branch==$b))
      | (if .status=="success" then "success"
         elif .status=="failure" then "failure"
         else "pending" end) // "none"'
```

**Must verify before shipping:** that the endpoint exists on the target Forgejo version, that it
exposes per-workflow run **conclusion** *and* the branch, and (for `ci-health`) whether failed-job
**logs** are reachable via the API at all — if not, `ci-health` can report failure but not auto-fix.

## Auto-release lanes (B/C) on Forgejo

The lane workflows are GitHub-Actions-specific in three places; the Forgejo mirror lives in
`.forgejo/workflows/` and differs as follows:

| GitHub lane | Forgejo equivalent |
|---|---|
| `actions/create-github-app-token` (so the pushed tag triggers the publish workflow) | **No App.** Use a **PAT stored as a repo/org secret** for the push + API. Whether a tag pushed with it re-triggers a downstream workflow is **version-dependent — verify**; if it doesn't, trigger publish in the same job or via a Forgejo `workflow_dispatch`/`repository_dispatch` equivalent. |
| `gh release create --generate-notes` | `forge_release_create <tag> <title> "<notes from git log>"` (no auto-notes on Forgejo — build notes from `git log $PREV..HEAD`). `release-run.sh` should call `forge_*` when `VERSION_SOURCE`/host is Forgejo. |
| `on: workflow_run` (chain off the CI workflow) | Confirm Forgejo supports `workflow_run`; if not, gate the release job inside the CI workflow itself (a final job) rather than a separate chained workflow. |

The **recursion guard** (`chore(release): automated version bump` subject), **concurrency**, the
**idempotent tag/release**, and the **version-vs-tag logic** (`version-lib.sh`) are all host-agnostic
and carry over unchanged — only the token, the release-create call, and the trigger model differ.

## de-`gh` the inline snippets (carry-over from phase 2)

Independent of the runner: the adopted components (`ticket-gate`, `dep-auditor`) keep inline `gh …`
snippets as the GitHub reference form behind their host-aware preamble. A cleanup pass should replace
those inline snippets with their `forge_*` equivalents so an agent can't pattern-match a raw `gh`
command and run it on Forgejo. Runner-free; do it any time.

## Order of operations once a runner is up

1. Stand up a Forgejo Actions runner; confirm a trivial `.forgejo/workflows/ci.yml` runs.
2. Implement + verify the `forge_ci_status` Forgejo branch (above) against real runs.
3. Mirror the auto-release lane(s) into `.forgejo/workflows/` with the token/notes/trigger
   differences; verify a real dependency merge produces a tag + release.
4. Then `ci-health`'s Forgejo path (needs run logs) — only if the API exposes them.
