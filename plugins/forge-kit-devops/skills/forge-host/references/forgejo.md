# Forgejo (and Gitea) specifics

Forgejo is a self-hosted, GitHub-adjacent forge (a Gitea fork). Its API and conventions are
*similar* to GitHub but not identical — these are the differences `forge-lib.sh`'s Forgejo backend
accounts for. Use placeholders (`https://forge.example.com`) — never hard-code a private host/IP/port
into a committed file; put yours in the repo's own (committed) `.forge.conf` and the token in the env.

## API

- Base: `https://<your-forge>/api/v1` (the `forge_api_base` helper appends `/api/v1`).
- Auth: `Authorization: token <TOKEN>` header (same scheme as Gitea; `Bearer <TOKEN>` also works).
- Shapes: issues, comments, releases, tags mirror GitHub's REST closely (`number`, `title`, `body`,
  `state`, `tag_name`, `name`). Closing an issue is `PATCH /repos/{o}/{r}/issues/{n}` with
  `{"state":"closed"}` — same as GitHub.
- Differences to watch: pagination headers differ; PRs are issue-backed (a PR also appears under
  `/issues`). Forgejo's `/issues` honours `type=issues` to exclude PRs server-side; **GitHub's
  `/issues` ignores `type=` and still returns PRs**, so `forge_issue_list` filters them out with
  `jq 'select(.pull_request|not)'` on the github path. Some GitHub fields are absent on Forgejo.
- **Labels (verified):** `POST /issues` takes label **IDs** (`[]int64`) — names are not accepted on
  create, which is why `forge_issue_create` omits labels. `POST /issues/{n}/labels` accepts **both
  IDs and names** (`[]any`) on recent Forgejo, so `forge_issue_label` could pass names directly;
  it resolves names→IDs anyway so it also works on older (IDs-only) Forgejo.

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

Never commit the token. `--scopes all` is the **admin-CLI** form (valid there). The token API /
web UI need explicit scopes — strings are `{read|write}:{resource}` (resource ∈ `issue, repository,
user, organization, package, …`). For CI, scope it down, e.g. `write:issue,write:repository`.

## CI — Forgejo Actions

- Forgejo Actions is GitHub-Actions-compatible and reads **`.forgejo/workflows/`**, falling back to
  `.github/workflows/` only when `.forgejo/workflows/` is absent (a fallback, not a merge). Runners
  are **self-hosted** and **optional** — there may be none.
- **No GitHub-Apps equivalent.** The `release-automation` lanes' `actions/create-github-app-token`
  + `secrets.RELEASE_APP_*` mechanism does not exist on Forgejo. The automatic job token suppresses
  downstream triggers (like GitHub's), and **Forgejo does not support the `workflow_run` trigger** —
  so the lanes don't port as-is; see `forgejo-ci.md` for the in-CI-final-job / PAT approach.
- `gh release create --generate-notes` has no Forgejo equivalent — build notes from `git log`.
- **`forge_ci_status` is implemented** via the **combined commit-status API** (`/commits/{sha}/
  status`) — Forgejo Actions writes a commit status per job, so one call answers "is CI green?"
  (simpler than the version-split `/actions/runs`/`/actions/tasks` Actions API). With no runner there
  are no statuses, so it returns `not_configured` and callers fall back to a local gate (e.g. `make
  test` pre-push). **Job logs are not API-reachable** (so `ci-health` on Forgejo is detect-only).
  Confirming a real green run flips the status, and the auto-release lane, still want a runner —
  design in `forgejo-ci.md`.

## Issue templates

Forgejo reads `.forgejo/issue_template/` or `.gitea/ISSUE_TEMPLATE/` (and `.github/ISSUE_TEMPLATE/`
for compatibility in recent versions). forge-adapt's `templates` mode should target the
host-appropriate directory.

## CLI (optional)

No `gh`. `tea` is Gitea's official CLI and works with Forgejo; it is **optional** — `forge-lib.sh`
needs only `git` + `curl` + `jq` + a token, so nothing extra must be installed.
