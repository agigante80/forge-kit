# Local auth: getting the token into FORGE_TOKEN_ENV

The adapter's contract is simple: `forge-lib.sh` reads the API token from the env var named
by `FORGE_TOKEN_ENV` in `.forge.conf` (default `FORGEJO_TOKEN`). The token itself is never
committed. This reference covers how the token durably gets INTO that env var on each kind
of machine, and the credential-helper fallback built into the adapter. Use placeholders
(`forge.example.com`) in anything committed; never a private host.

## 1. Mint the most restrictive token that works

Forgejo user tokens carry scopes and an optional per-repository restriction. For the
governance components (issues, comments, releases, CI status), this is enough:

- Scopes: `read:issue, write:issue, read:repository, write:repository`
- Repository access: restrict to the specific repos where possible.

Mint in the UI (Settings, Applications, Generate Token), via the API
(`POST /users/{name}/tokens` with BasicAuth), or password-free on the host:

```sh
docker exec -u git <forgejo-container> forgejo admin user \
  generate-access-token --username <you> \
  --scopes write:issue,write:repository --raw
```

Hygiene facts worth knowing: Forgejo PATs do NOT expire (rotation is manual: mint new,
swap, delete old), and there is no OAuth device flow yet, so a scoped static PAT is the
practical credential for CLIs and agents. Capture the token verbatim (some token types
contain `-`/`_`/`.`).

## 2. Supply it, per context

### Humans (shells): OS keyring or pass, surfaced by profile or direnv

Store encrypted once, export by lookup. Never keep the literal token in a dotfile.

```sh
# store once (libsecret; GNOME/KDE keyrings)
secret-tool store --label="Forgejo token" service forgejo host forge.example.com
# then in ~/.bashrc, or in a gitignored per-project .envrc (direnv):
export FORGEJO_TOKEN=$(secret-tool lookup service forgejo host forge.example.com)
```

Headless machines: `pass` (GPG-encrypted) instead:
`export FORGEJO_TOKEN=$(pass show forgejo/forge.example.com)`.
direnv adds per-project scoping and an allow-gate (`direnv allow`); combine it with the
keyring lookup rather than pasting the token into `.envrc`.

### Claude Code sessions: settings env block (global or per-project)

Claude Code applies a settings `env` block to every session and every subprocess it spawns
(Bash calls, hooks), regardless of how it was launched. Two scopes:

```json
{ "env": { "FORGEJO_TOKEN": "<token>" } }
```

- **`~/.claude/settings.json`** (user-global, lives in your home, never committed): set it
  ONCE and every project on the machine gets the token. The right default when one machine
  hosts several repos talking to the same Forgejo instance: a newly migrated project then
  needs only its committed `.forge.conf` (the URL), and auth comes for free.
- **`.claude/settings.local.json`** (per-project, auto-gitignored): use instead when a
  project needs a different (e.g. more narrowly scoped) token than the machine default.

Both are plaintext on disk (same posture as a gitignored `.envrc`); prefer the keyring
lanes above where a shell profile is in play, since shell-inherited vars take precedence
anyway.

**Warning: only the TOKEN belongs in a global env block.** Do not add `FORGE_HOST` or
`FORGE_API_URL` next to it: environment beats `.forge.conf` in host detection, so a
machine-global `FORGE_HOST=forgejo` silently routes EVERY repo (including GitHub ones)
down the forgejo path and breaks their `gh`-backed operations. The URL is per-repo data
and lives in each repo's committed `.forge.conf`.

### CI (Forgejo Actions): repository or org secrets

Map a secret to the env var the components expect, in the workflow:

```yaml
env:
  FORGEJO_TOKEN: ${{ secrets.FORGEJO_TOKEN }}
```

Use a repo-scoped PAT with only the scopes above. Remember the automatic job token
(`GITHUB_TOKEN`/`FORGEJO_TOKEN` alias) suppresses downstream triggers; chained workflows
need a PAT secret (see `forgejo-ci.md`).

## 3. The built-in fallback: git's credential helper

If `FORGE_TOKEN_ENV` is empty, `_forge_token` asks git's configured credential helper for
the instance host before erroring (`git credential fill`, non-interactive, read-only).
That is the same encrypted store (libsecret, osxkeychain, Windows Credential Manager)
already holding your git-over-HTTPS password for the instance, so if `git push` works over
HTTPS, the API calls work with zero extra setup. To seed it explicitly:

```sh
printf 'protocol=https\nhost=forge.example.com\nusername=<you>\npassword=<token>\n\n' \
  | git credential approve
```

Notes: helpers key on protocol+host (port included), not per-repo; `git-credential-store`
is a plaintext backend, prefer libsecret/osxkeychain; the fallback never prompts and never
writes, it only reads. **Opt out** with `FORGE_NO_GIT_CREDENTIALS=1` (env or `.forge.conf`)
to restore strict env-only behavior: the token must then come explicitly from
`FORGE_TOKEN_ENV`, and an unset token fails closed instead of being auto-discovered.

## 4. CLIs (fj, tea): convenient, but not the canonical store

- `fj` (forgejo-cli, incubating as the official Forgejo CLI) and `tea` (Gitea's CLI,
  Forgejo-compatible) both work against Forgejo and are fine as interactive tools.
- Both store their tokens in PLAINTEXT config files (`~/.local/share/.../keys.json` for
  fj, `~/.config/tea/config.yml` for tea). Scripts can read those back out, but do not
  make them the canonical store for forge-kit components; use the lanes above. If you
  already use fj daily, minting one extra scoped PAT for the components keeps blast
  radius per-tool.
