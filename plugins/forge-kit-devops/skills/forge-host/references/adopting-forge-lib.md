# Adopting forge-lib.sh across the GitHub-coupled components

Phase 1 (this skill) ships the adapter. This is the migration map for the follow-on work —
verified against the live catalogue (a `grep` for `gh `, `api.github.com`, `{{GITHUB_REPO}}`).

## Which components are coupled (and how much)

| Component | Coupling | Adopt by |
|---|---|---|
| `ci-health` (command) | `gh run list`, `gh issue` | `forge_ci_status`, `forge_issue_*`. **CI-dependent** — blocked on a Forgejo runner |
| `release-automation` (lanes) | `actions/create-github-app-token`, `secrets.RELEASE_APP_*`, `gh release`, `GITHUB_TOKEN` | **Hardest.** No Forgejo App-token equivalent; needs a Forgejo Actions backend. **CI-dependent** |
| `release` (skill) | "pipeline green" check, tag/release/close | `forge_ci_status` + `forge_release_create` + `forge_issue_close` |
| `ticket-gate` (agent) | `gh issue`, `{{GITHUB_REPO}}`, posts scorecard | `forge_issue_*`; replace `{{GITHUB_REPO}}` with `forge_repo` |
| `gate-ticket` (command) | "fetch GitHub issue", post comment | `forge_issue_view` + `forge_issue_comment` |
| `dep-auditor` (agent) | files `gh` tickets | `forge_issue_*` (create via `forge_api POST /repos/.../issues`) |
| `health-check` (agent) | checks **`gh` is installed** | check the forge token/CLI for the detected host instead |
| forge-adapt `templates` mode | writes `.github/ISSUE_TEMPLATE/` | also target `.forgejo/issue_template/` when host=forgejo |
| forge-adapt setup | self-update + catalogue via `gh api repos/agigante80/forge-kit` | separate axis — where *forge-kit itself* is hosted, vs the repo being governed |

Not coupled (verified — no `gh`/API calls): **`pr-enhance`** (generates PR text for a human to
paste) and **`full-review`** (writes a `.full-review/` report file). They need no change.

## The swap pattern

Before:
```bash
gh issue close "$N" --comment "Released in v$VERSION"
```
After:
```bash
source scripts/forge-lib.sh
forge_issue_comment "$N" "Released in v$VERSION"
forge_issue_close "$N"
```

`forge_issue_list`/`forge_issue_view` return REST JSON on both hosts, so existing `jq` filters
mostly carry over (mind the PR-vs-issue and pagination differences in `references/forgejo.md`).

## Recommended order (value-first, not CI-first)

The original instinct was `ci-health`/`release` first — but those depend on a Forgejo runner you may
not have. Re-order by what works on a runner-less Forgejo **today**:

1. **This skill** — `forge-lib.sh` + `.forge.conf` marker (done).
2. **Issues-API components** (`gate-ticket`/`ticket-gate`, `dep-auditor`, and `release`'s
   tag/release/issue-close steps) — deliver immediately, no runner needed.
3. **forge-adapt** — host detection in analysis + `templates`-mode target dir; fix `health-check`.
4. **CI/Actions backend** (`ci-health`, `release`'s pipeline check, the `release-automation`
   lanes) — **gated on a Forgejo runner existing**, and on confirming the Forgejo Actions API
   exposes run conclusion + logs.

Keep every change additive: GitHub-only repos (no `.forge.conf`) must behave exactly as before.

**Known limitation (phase 2b).** The adopted components carry a host-aware *preamble* (source the
adapter, use `forge_*`), but their many inline `gh …` snippets are kept as the GitHub *reference
form* rather than rewritten in place. A long agent (e.g. `ticket-gate`) relies on the preamble being
applied to each snippet. A future pass should replace the inline `gh` snippets with their `forge_*`
equivalents inline, so an agent can't pattern-match a raw `gh` command and run it on Forgejo.
