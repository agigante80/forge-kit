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

Today `forge_ci_status` returns `not_configured` on Forgejo (graceful). When a runner exists, replace
that arm with a query against the **Forgejo Actions API**, which is **version-split** (verified
against Forgejo docs/source):

- **Forgejo ≥ v12.0.0:** `GET /repos/{o}/{r}/actions/runs` (and `/actions/runs/{run_id}`) — GitHub-
  style run objects (`head_branch`, status/conclusion).
- **Older Forgejo:** `GET /repos/{o}/{r}/actions/tasks` — `ActionTask` objects with `head_branch`,
  `head_sha`, `status`, `run_number`. **There is no `conclusion` field — `status` carries
  success/failure** (`waiting|running|success|failure|…`). Read `.status`, not `.conclusion`.

```sh
# Older-Forgejo (tasks) form — status carries the result, not a separate conclusion:
# Wrap the whole pipeline in (...) // "none": first() yields an EMPTY STREAM (not null) on no
# match, so the `// "none"` must be OUTSIDE first()/the if — else the no-run case prints '' not none.
forge_api GET "/repos/$(forge_repo)/actions/tasks" \
  | jq -r --arg b "$1" '(first(.tasks[]? | select(.head_branch==$b))
      | (if .status=="success" then "success"
         elif .status=="failure" then "failure"
         else "pending" end)) // "none"'
```

**Hard fact, not a maybe — job LOGS are NOT reachable via the Forgejo API** (the Actions-API PR
explicitly did not add log endpoints; only artifacts via `/actions/artifacts/{id}`). So on Forgejo
`ci-health` can **detect** a failed run but **cannot fetch logs to auto-fix** — its Forgejo path must
be detect-and-ticket only, never auto-fix-from-logs.

## Auto-release lanes (B/C) on Forgejo

The lane workflows are GitHub-Actions-specific in three places; the Forgejo mirror lives in
`.forgejo/workflows/` and differs as follows:

| GitHub lane | Forgejo equivalent |
|---|---|
| `actions/create-github-app-token` (so the pushed tag triggers the publish workflow) | **No App** on Forgejo. The auto job token (`FORGEJO_TOKEN`/`GITHUB_TOKEN` alias) is repo-scoped and, like GitHub's, **suppresses downstream triggers** ("no workflow is triggered as a side effect of a change authored with this token"). To chain a publish off a pushed tag, push with a **PAT stored as a repo/org secret**, not the auto token. |
| `gh release create --generate-notes` | `forge_release_create <tag> <title> "<notes from git log>"` (no auto-notes on Forgejo — build notes from `git log $PREV..HEAD`). `release-run.sh` should call `forge_*` when the host is Forgejo. |
| `on: workflow_run` (chain off the CI workflow) | **Forgejo does NOT support `workflow_run`** (verified — unimplemented). Don't chain a separate release workflow off CI completion. Instead make the release a **final job in the CI workflow itself** (gated on the prior jobs), or use **`workflow_call`** (which Forgejo does support) / `workflow_dispatch`. |

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
