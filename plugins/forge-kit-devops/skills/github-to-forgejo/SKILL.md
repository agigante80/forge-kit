---
name: github-to-forgejo
description: >
  Migrate a repository from GitHub to a self-hosted Forgejo instance: push the repo,
  adopt the forge-host adapter, resolve the .github/workflows dual-execution surprise,
  port CI to .forgejo/workflows with Forgejo-specific rules (services-by-name,
  docker-out-of-docker compose, gate expensive jobs), register a runner, and optionally
  push-mirror back to GitHub. Generic and portable; host-specific runner/storage tuning
  is delegated to a project infra reference. Use when moving one or more repos to your
  own Forgejo.
---

<!-- github-to-forgejo-version: 5 -->

# github-to-forgejo

Move a repo from GitHub to a self-hosted Forgejo: git hosting, governance, and
(optionally) CI. Built on forge-kit's `forge-host` adapter. **Portable:** anything
specific to the *target host* (runner registration, slow-storage tuning) is delegated to
that project's infra reference; this skill is the stack-agnostic playbook.

Draft origin: distilled from a real end-to-end migration (repo + self-hosted CI + a
docker-compose e2e job to green + a downstream consumer cutover). The non-obvious steps
below (esp. Phases 3 to 4) are the ones that actually bit.

## When to use
- "migrate <repo> to Forgejo", "move this project off GitHub to my Forgejo",
  "self-host this repo's git and CI".

## Prerequisites
- A reachable Forgejo instance, and either shell/Docker access to it or admin in its UI
  (to mint a token).
- forge-kit's `forge-host` skill. If missing, `/forge-kit-adapt:adapt` installs it.

## Phase 0: Preflight
- Reachable? `curl -fsS "$FORGE_API_URL/api/v1/version"` (private instances need a token).
- **Mint a token.** Self-hosted with Docker access (password-free):
  ```sh
  docker exec -u git <forgejo-container> forgejo admin user \
    generate-access-token --username <you> --scopes all --raw
  ```
  Otherwise: Web UI → Settings → Applications → Generate Token.
  **Store it machine-globally so every project gets it**: the recommended default is the
  `env` block of `~/.claude/settings.json` (user-global, never committed), so each further
  migrated repo needs only its committed `.forge.conf` and auth comes for free:
  ```json
  { "env": { "FORGEJO_TOKEN": "<token>" } }
  ```
  Alternatives (keyring/pass + profile or direnv, per-project settings.local.json, the
  git-credential fallback): forge-host `references/local-auth.md`. A plain
  `export FORGEJO_TOKEN=…` works for the current shell only.
  **Capture the FULL token verbatim.** Some Forgejo token types (OAuth2/base64url) contain
  `-`/`_`/`.`, so a greedy `[A-Za-z0-9]+` capture can truncate them and the server 401s the short
  token as *malformed* (reads like a missing header, a debugging trap). `--raw` prints the token as
  one line; copy it whole.
- Write `.forge.conf` at the repo root (committed, the deterministic signal for forge-host):
  ```
  FORGE_HOST=forgejo
  FORGE_API_URL=http://<host>:<port>     # base, no /api/v1
  FORGE_REPO=<owner>/<repo>
  FORGE_TOKEN_ENV=FORGEJO_TOKEN
  FORGE_REMOTE=forgejo
  ```

## Phase 1: Create + push the repo
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

## Phase 2: Adopt the forge-host adapter
- `/forge-kit-adapt:adapt` → install/refresh `forge-host` + the host-aware components
  (release, ci-health, gate-ticket, ticket-gate, dep-auditor, health-check). Retire any
  project-local forge adapter in favour of `scripts/forge-lib.sh`.
- Sanity: `bash scripts/forge-lib.sh detect` → `host=forgejo repo=… api=… ci=not_configured`.
- **No runner yet?** `forge_ci_status` returns `not_configured` (empty combined status);
  treat that as "no CI, use local gates (`make test`)" until a runner exists.

## Phase 3: the `.github/workflows/` question  ← the migration surprise
Forgejo Actions does **not** run both dirs. It looks up workflows in exactly ONE directory, using
the **first that exists**: `.forgejo/workflows/` → `.gitea/workflows/` → `.github/workflows/` (a
fallback, not a merge, verified against Forgejo docs + source). Consequences during migration:
- **Before you add `.forgejo/workflows/`,** Forgejo falls back to your existing `.github/workflows/`
  and runs *those*, and GitHub-specific ones fail on Forgejo (`services:` on `localhost`, GHCR/`gh`
  steps, a version tag re-firing a publisher). That "my GitHub workflows ran and broke on Forgejo"
  is the surprise, **not** double runs.
- **The switch:** the moment a `.forgejo/workflows/` directory exists, Forgejo ignores
  `.github/workflows/` entirely. So **creating `.forgejo/workflows/` IS the mitigation**: your
  GitHub copies stay in the repo (for GitHub) but go dormant on Forgejo. No fences needed for the
  single-remote case.
- **Dual-remote (mirroring to both forges):** Forgejo populates the `github.*` context, so if you
  share one workflow dir, guard GitHub-only steps on the host (e.g.
  `contains(github.server_url, 'github.com')`), or keep separate `.forgejo/` + `.github/` copies.

## Phase 4: Port CI to `.forgejo/workflows/` (optional)
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
the **host daemon** (not the job container) resolves paths and ports. In a CI compose
overlay:
1. **Relative bind mounts fail** (source is on the host; your checkout is in the job
   container) → drop bind mounts / use named volumes.
2. **`container_name:` collisions** with a deployed stack of the same name on that host →
   override to unique CI names.
3. **Published ports are on the host, not the job's `localhost`** → join the job to the
   compose network and address services by name (`app:8000`, `db:5432`):
   ```sh
   # `hostname` is the job container's own id by default. CAVEAT: if your runner sets a
   # custom --hostname, `hostname` is no longer the id, so pass the real id instead (get it
   # from `docker ps` on the host, or `/proc/self/cgroup` on a cgroup-v1 host).
   docker network connect "<project>_default" "$(hostname)"
   ```
4. Give jobs Docker with **`container.docker_host: automount`** (Forgejo docs), not a
   hand-rolled socket mount.

### runner + storage: DELEGATED (host-specific)
Registering the runner (Docker socket access, run-as-root, labels) and tuning it for your
host (slow copy-on-write storage fixes like tmpfs for job temp and Postgres `fsync=off`,
plus cleaning orphaned `FORGEJO-ACTIONS-*` containers) is **environment-specific**. Follow
the target host's own infra reference (e.g. a NAS/self-hosted-runner runbook). Keep it out of
this skill so it stays portable.

## Phase 5: Verify + cut over
- Trigger a run; watch `forge_ci_status` / the Actions tab go green.
- Repoint consumers/deploys to the Forgejo-hosted service/artifacts with a
  **Forgejo-issued** token (full-token capture rule again: a token is pepper-bound to one
  instance and won't validate on another).
- Set the default + protected branches on Forgejo to match.
- **Guard against pushes back to the archived host.** Two layers, git first:
  1. Remove the legacy remote (`git remote remove github`), or keep it fetch-only by
     poisoning its push URL (`git remote set-url --push github no-push://archived`), so git
     itself refuses. GitHub's archive reject is the server-side backstop.
  2. Optionally install the **`block-legacy-host-push` hook**
     (`plugins/forge-kit-devops/hooks/block-legacy-host-push.py`) into the project's
     `.claude/hooks/` and wire it as a PreToolUse/Bash hook in `.claude/settings.json`.
     It tokenizes each command, resolves the REAL push target (explicit remote, URL, or
     the branch's default push destination) to a URL host, and denies iff that host is in
     `FORGE_LEGACY_HOSTS` (defaults to `github.com` when `.forge.conf` exists). Command
     text like a commit message mentioning "push github" can never false-positive, and a
     bare `git push` on a branch whose upstream still points at the legacy host IS caught.
     Optional `FORGE_PUSH_STRICT=1` allows only `FORGE_REMOTE`. Fails open on parse errors.

## Rules
- **Portable only**: never inline host-specific runner/storage steps; link a reference.
- `.forge.conf` committed; the token in the environment, never committed.
- **Additive**: keep GitHub working (mirror) until the Forgejo side is verified green.
- Prefer forge-host `forge_*` ops over raw `gh` in any governance the repo carries.
