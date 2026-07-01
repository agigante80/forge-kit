---
name: github-to-forgejo
description: >
  Migrate a repository from GitHub to a self-hosted Forgejo instance: push the repo,
  adopt the forge-host adapter, resolve the .github/workflows dual-execution surprise,
  port CI to .forgejo/workflows with Forgejo-specific rules (services-by-name,
  docker-out-of-docker compose, gate expensive jobs), register a runner, and optionally
  push-mirror back to GitHub. Generic and portable — host-specific runner/storage tuning
  is delegated to a project infra reference. Use when moving one or more repos to your
  own Forgejo.
---

<!-- github-to-forgejo-version: 1 -->

# github-to-forgejo

Move a repo from GitHub to a self-hosted Forgejo — git hosting, governance, and
(optionally) CI. Built on forge-kit's `forge-host` adapter. **Portable:** anything
specific to the *target host* (runner registration, slow-storage tuning) is delegated to
that project's infra reference; this skill is the stack-agnostic playbook.

Draft origin: distilled from a real end-to-end migration (repo + self-hosted CI + a
docker-compose e2e job to green + a downstream consumer cutover). The non-obvious steps
below (esp. Phases 3–4) are the ones that actually bit.

## When to use
- "migrate <repo> to Forgejo", "move this project off GitHub to my Forgejo",
  "self-host this repo's git and CI".

## Prerequisites
- A reachable Forgejo instance, and either shell/Docker access to it or admin in its UI
  (to mint a token).
- forge-kit's `forge-host` skill. If missing, `/forge-kit-adapt:adapt` installs it.

## Phase 0 — Preflight
- Reachable? `curl -fsS "$FORGE_API_URL/api/v1/version"` (private instances need a token).
- **Mint a token.** Self-hosted with Docker access (password-free):
  ```sh
  docker exec -u git <forgejo-container> forgejo admin user \
    generate-access-token --username <you> --scopes all --raw
  ```
  Otherwise: Web UI → Settings → Applications → Generate Token. Then `export FORGEJO_TOKEN=…`.
  **Capture the FULL token** — it can contain `-`/`_` (it's `token_urlsafe`); a greedy
  `[A-Za-z0-9]+` capture truncates it and the server rejects the short header as *malformed*
  (a 401 that reads like a missing header — a debugging trap).
- Write `.forge.conf` at the repo root (committed — the deterministic signal for forge-host):
  ```
  FORGE_HOST=forgejo
  FORGE_API_URL=http://<host>:<port>     # base, no /api/v1
  FORGE_REPO=<owner>/<repo>
  FORGE_TOKEN_ENV=FORGEJO_TOKEN
  FORGE_REMOTE=forgejo
  ```

## Phase 1 — Create + push the repo
- Create it: `POST /api/v1/user/repos {"name":"<repo>","private":true}` (or the org endpoint).
- Add your SSH key so git-over-SSH is passwordless: `POST /api/v1/user/keys {"title","key"}`.
  Note Forgejo's git-SSH port (frequently **not** 22).
- Push everything and set the remote:
  ```sh
  git remote add forgejo ssh://git@<host>:<ssh-port>/<owner>/<repo>.git
  git push forgejo --all && git push forgejo --tags
  ```
- Optional offsite safety net: keep GitHub as a **push-mirror** (repo → Settings → Mirror,
  or a Forgejo push-mirror to the GitHub URL + a PAT).

## Phase 2 — Adopt the forge-host adapter
- `/forge-kit-adapt:adapt` → install/refresh `forge-host` + the host-aware components
  (release, ci-health, gate-ticket, ticket-gate, dep-auditor, health-check). Retire any
  project-local forge adapter in favour of `scripts/forge-lib.sh`.
- Sanity: `bash scripts/forge-lib.sh detect` → `host=forgejo repo=… api=…`.
- **No runner yet?** `forge_ci_status` returns `not_configured` (empty combined status) —
  treat that as "no CI, use local gates (`make test`)" until a runner exists.

## Phase 3 — Resolve the `.github/workflows/` question  ← the #1 surprise
Forgejo Actions executes **`.github/workflows/` in addition to `.forgejo/workflows/`**.
So your GitHub workflows *also run on Forgejo* — and GitHub-specific ones fail there
(`services:` on `localhost`, GHCR/`gh` steps, a version tag re-firing a publisher). Choose:
- **Fully off GitHub:** remove `.github/workflows/` — CI lives only in `.forgejo/`.
- **Keeping GitHub (mirror):** accept both fire, split by trigger, or fence GitHub-only
  workflows behind conditions. Don't leave duplicate green/red boards.

## Phase 4 — Port CI to `.forgejo/workflows/` (optional)
Forgejo Actions is GitHub-Actions-compatible, but the runner is usually a **container**
(not a VM). Adapt:
- **`runs-on`**: label your runner (e.g. `ubuntu-latest`) so ported jobs match.
- **Service containers reachable by NAME**, not `localhost` (`postgres:5432`).
- **CI-green gate** = `forge_ci_status <branch>` (Forgejo Actions writes a commit status
  per job).
- **Gate expensive jobs** (full image builds, e2e) to on-demand, e.g.
  `if: contains(github.event.head_commit.message, '[e2e]')`, so ordinary pushes stay fast.

### docker-compose / integration tests under a containerized runner (docker-out-of-docker)
If a job runs `docker compose` via the host socket (`container.docker_host: automount`),
the **host daemon** — not the job container — resolves paths and ports. In a CI compose
overlay:
1. **Relative bind mounts fail** (source is on the host; your checkout is in the job
   container) → drop bind mounts / use named volumes.
2. **`container_name:` collisions** with a deployed stack of the same name on that host →
   override to unique CI names.
3. **Published ports are on the host, not the job's `localhost`** → join the job to the
   compose network (`docker network connect <project>_default "$(cat /etc/hostname)"`) and
   address services by name (`app:8000`, `db:5432`).
4. Give jobs Docker with **`container.docker_host: automount`** (Forgejo docs), not a
   hand-rolled socket mount.

### runner + storage — DELEGATED (host-specific)
Registering the runner (Docker socket access, run-as-root, labels) and tuning it for your
host — slow copy-on-write storage fixes like tmpfs for job temp and Postgres `fsync=off`,
plus cleaning orphaned `FORGEJO-ACTIONS-*` containers — is **environment-specific**. Follow
the target host's infra reference (e.g. a `synology-*`/NAS reference). Keep it out of this
skill so it stays portable.

## Phase 5 — Verify + cut over
- Trigger a run; watch `forge_ci_status` / the Actions tab go green.
- Repoint consumers/deploys to the Forgejo-hosted service/artifacts with a
  **Forgejo-issued** token (full-token capture rule again — a token is pepper-bound to one
  instance and won't validate on another).
- Set the default + protected branches on Forgejo to match.

## Rules
- **Portable only** — never inline host-specific runner/storage steps; link a reference.
- `.forge.conf` committed; the token in the environment, never committed.
- **Additive** — keep GitHub working (mirror) until the Forgejo side is verified green.
- Prefer forge-host `forge_*` ops over raw `gh` in any governance the repo carries.
