# Forgejo (and Gitea) specifics

Forgejo is a self-hosted, GitHub-adjacent forge (a Gitea fork). Its API and conventions are
*similar* to GitHub but not identical — these are the differences `forge-lib.sh`'s Forgejo backend
accounts for. Use placeholders (`https://forge.example.com`) — never hard-code a private host/IP/port
into a committed file; put yours in the repo's own (committed) `.forge.conf` and the token in the env.

## API

- Base: `https://<your-forge>/api/v1` (the `forge_api_base` helper appends `/api/v1`).
- Auth: `Authorization: token <TOKEN>` header (same scheme as Gitea).
- Shapes: issues, comments, releases, tags mirror GitHub's REST closely (`number`, `title`, `body`,
  `state`, `tag_name`, `name`). Closing an issue is `PATCH /repos/{o}/{r}/issues/{n}` with
  `{"state":"closed"}` — same as GitHub.
- Differences to watch: pagination headers differ; PRs are issue-backed (a PR also appears under
  `/issues`). Forgejo's `/issues` honours `type=issues` to exclude PRs server-side; **GitHub's
  `/issues` ignores `type=` and still returns PRs**, so `forge_issue_list` filters them out with
  `jq 'select(.pull_request|not)'` on the github path. Some GitHub fields are absent on Forgejo.

## Tokens

Mint an access token (self-hosted, no password needed if you can reach the container):

```
docker exec -u git <forgejo-container> \
  forgejo admin user generate-access-token --username <user> --scopes all --raw
```

Export it under the name your `.forge.conf` declares (`FORGE_TOKEN_ENV`, default `FORGEJO_TOKEN`):

```
export FORGEJO_TOKEN=<token>
```

Never commit the token. Scope it down from `all` to `write:issue,write:repository` for CI use.

## CI — Forgejo Actions

- Forgejo Actions is GitHub-Actions-compatible and reads **`.forgejo/workflows/`** *and*
  `.github/workflows/`. Runners are **self-hosted** and **optional** — there may be none.
- **No GitHub-Apps equivalent.** The `release-automation` lanes' `actions/create-github-app-token`
  + `secrets.RELEASE_APP_*` mechanism does not exist on Forgejo. Forgejo Actions injects an
  automatic token to the runner; whether a tag pushed with it re-triggers downstream workflows
  differs from GitHub and must be verified per Forgejo version before relying on it.
- `gh release create --generate-notes` has no Forgejo equivalent — build notes from `git log`.
- **Until a runner exists, there are no Actions runs to query.** `forge_ci_status` returns
  `not_configured` so callers fall back to a local gate (e.g. `make test` pre-push). Implementing
  the real status against the Forgejo Actions API (`/repos/{o}/{r}/actions/...`) is **phase 2**,
  gated on standing up a runner — and on verifying that API exposes per-workflow run *conclusion*
  and failed-job *logs* (it is newer/less complete than GitHub's).

## Issue templates

Forgejo reads `.forgejo/issue_template/` or `.gitea/ISSUE_TEMPLATE/` (and `.github/ISSUE_TEMPLATE/`
for compatibility in recent versions). forge-adapt's `templates` mode should target the
host-appropriate directory.

## CLI (optional)

No `gh`. `tea` is Gitea's official CLI and works with Forgejo; it is **optional** — `forge-lib.sh`
needs only `git` + `curl` + `jq` + a token, so nothing extra must be installed.
