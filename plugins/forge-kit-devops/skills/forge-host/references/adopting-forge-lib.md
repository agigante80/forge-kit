# Adopting forge-lib.sh across the GitHub-coupled components

Phase 1 (this skill) ships the adapter. This is the migration map for the follow-on work,
verified against the live catalogue (a `grep` for `gh `, `api.github.com`, `{{GITHUB_REPO}}`).

## Which components are coupled (and how much)

| Component | Coupling | Adopt by |
|---|---|---|
| `ci-health` (command) | `gh run list`, `gh issue` | `forge_workflow_dir`, `forge_ci_status`, `forge_issue_*`, `forge_body_region_set`. Detect and ticket on Forgejo (#552); no auto-fix there, because job logs are not API-reachable |
| `release-automation` (lanes) | `actions/create-github-app-token`, `secrets.RELEASE_APP_*`, `gh release`, `GITHUB_TOKEN` | **Hardest.** No Forgejo App-token equivalent; needs a Forgejo Actions backend. **CI-dependent** |
| `release` (skill) | "pipeline green" check, tag/release/close | `forge_ci_status` + `forge_release_create` + `forge_issue_close` |
| `ticket-gate` (agent) | `gh issue`, `{{GITHUB_REPO}}`, posts the review | `forge_issue_*`; replace `{{GITHUB_REPO}}` with `forge_repo` |
| `gate-ticket` (command) | "fetch GitHub issue", post comment | `forge_issue_view` + `forge_issue_comment` |
| `dep-auditor` (agent) | files `gh` tickets | `forge_issue_*` (create via `forge_api POST /repos/.../issues`) |
| `health-check` (agent) | checks **`gh` is installed** | check the forge token/CLI for the detected host instead |
| forge-adapt `templates` mode | writes `.github/ISSUE_TEMPLATE/` | also target `.forgejo/ISSUE_TEMPLATE/` when host=forgejo |
| forge-adapt setup | self-update + catalogue via `gh api repos/agigante80/forge-kit` | separate axis: where *forge-kit itself* is hosted, vs the repo being governed |

Not coupled (verified, no `gh`/API calls): the review commands that only generate text for a human
to paste). **`full-review`** WAS uncoupled; since v7 its Completion files the Low findings
whose outcome is a ticket via `forge_issue_create`/`forge_issue_label` with a `gh issue create` fallback, so
a Forgejo project should wire `forge-lib.sh` for it or the fallback files against the
wrong host.

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

The original instinct was `ci-health`/`release` first, but those depend on a Forgejo runner you may
not have. Re-order by what works on a runner-less Forgejo **today**:

1. **This skill**: `forge-lib.sh` + `.forge.conf` marker (done).
2. **Issues-API components** (`gate-ticket`/`ticket-gate`, `dep-auditor`, and `release`'s
   tag/release/issue-close steps): deliver immediately, no runner needed.
3. **forge-adapt**: host detection in analysis + `templates`-mode target dir; fix `health-check`.
4. **CI/Actions backend** (`release`'s pipeline check, the `release-automation`
   lanes; `ci-health` landed detect-and-ticket in #552): **gated on a Forgejo runner existing**, and on confirming the Forgejo Actions API
   exposes run conclusion + logs.

Keep every change additive: GitHub-only repos (no `.forge.conf`) must behave exactly as before.

**Known limitation (phase 2b).** The adopted components carry a host-aware *preamble* (source the
adapter, use `forge_*`), but their many inline `gh …` snippets are kept as the GitHub *reference
form* rather than rewritten in place. A long agent (e.g. `ticket-gate`) relies on the preamble being
applied to each snippet. A future pass should replace the inline `gh` snippets with their `forge_*`
equivalents inline, so an agent can't pattern-match a raw `gh` command and run it on Forgejo.

## The leak scan of caller-supplied text (forge-lib v53, #539)

The #536 hook sees only a body typed into a `gh` command line. Every body write in `forge-lib.sh`
sends JSON through `gh api --input -`, so gate reviews and decision sections reached the forge
unscanned. Seven writers now scan the text their CALLER supplies, at their entry and before their
`FORGE_DRY_RUN` guard: `forge_issue_comment` (`body`), `forge_issue_create` (`title`, `body`),
`forge_issue_edit` (`body`), `forge_release_create` (`tag`, `name`, `notes`), `forge_body_region_set`
(`content`; a clear supplies none, so it is never refused), `forge_body_section_append` (`content`)
and `forge_body_compose_preserving` (`body`, the new text, never the recomposed one). A leak already
in an issue body therefore never blocks the write that removes it.

- **Opt-in:** the sentinel `.claude/scan-forge-writes` at the repository root, or
  `FORGE_LEAK_SCAN=1`, which only this library reads (the hook does not). `FORGE_LEAK_SCAN=0` forces
  it off. Any other value is treated as unset, with one note. With neither, there is no scanner, no
  note and no cost.
- **The default branch decides (#558):** a checked-out branch cannot weaken the scan. The sentinel
  counts when the working copy OR the default branch's tree lists it, and the allowlist is the
  default branch's `.leak-guard-allow` blob only, copied to a 0600 temp file. The remote and ref are
  the pin's (`_forge_default_ref`): an exported `FORGE_REMOTE`, else the sole remote, else `origin`;
  then `HEAD`, `main`, `master`. A working list that differs prints one note. No remote at all, or
  not a git repository: the working copy, silently. A remote with no readable default ref (an
  `actions/checkout` pull_request clone) or a listed allowlist blob that is not local: no allowlist,
  one note, and only when the scan is on. Residual: there, a branch that deletes a committed
  sentinel is not scanned, so CI that scans must fetch the default ref.
- **Return code 110** means a scanner found a leak: nothing was sent, and the stderr line names the
  writer, the rule, the field and the line, never the matched text. It is final for that call. An
  agent stops and reports it to the user, and never sets `FORGE_LEAK_SCAN=0` itself.
  `ticket-gate` needs no change: it already treats any non-zero code from a writer as a failure to
  report.
- **Fail open** (one stderr note per shell, even under `FORGE_LEAK_SCAN=1`): scanners not found, a
  scanner exiting anything but 0 or 1, a timeout, a temp file that cannot be made, a field over 1 MiB.
  The one exception is an explicit `FORGE_LEAK_GUARD_DIR` that does not hold both marked scanners:
  that refuses (110), because the operator asked for those scanners.
- **Discovery** needs both `check-private-leaks.sh` and `check-public-leaks.sh`, each with its
  version marker: `FORGE_LEAK_GUARD_DIR`; forge-lib's own directory (resolved to an absolute physical
  path when the library is loaded, never `.`); the sibling `forge-kit-security` group only when the
  library sits at `forge-kit-devops/skills/forge-host/assets`; then the highest
  `check-private-leaks-version` under `$HOME/.claude/plugins`. forge-kit-devops does not depend on
  forge-kit-security, so a project with neither simply gets the not-found note.
- **Scanner call:** each field goes to its own 0600 temp file, never to an argument; the forge token
  variables are removed from the scanner environment; the default branch's allowlist (above) goes to
  the public scanner; 4 s per scan and 8 s in all when `timeout` exists.
- **Not scanned (known gaps):** `forge_api` direct writes, `forge_milestone_create`,
  `forge_issue_milestone`, label writes and `sync-labels.sh` descriptions, anything run with
  `FORGE_LEAK_SCAN=0` or a custom `FORGE_LEAK_GUARD_DIR`, a field over 1 MiB, and every fail-open case.

## A project's own issue-body addition (forge-lib v58, #541)

`forge-lib.sh` is copied verbatim, and a refresh never merges a local edit into it. A project that
appends its own block to every new issue therefore keeps that block in its own script and exports
`FORGE_BODY_FILTER=/absolute/path/to/that/script`. `forge_issue_create` pipes the body into it and
sends its stdout, byte for byte, as the body. A wrapper function around `forge_issue_create` would not
do the same job: kit components often run in a fresh shell that never sources the wrapper, while an
exported variable reaches them all.

- **Order:** the filter runs before the #539 leak scan, so the scan sees the body that is sent, and a
  leak the filter adds is refused with 110.
- **Return code 111** means the filter refused and nothing was sent: a relative or bare name, a path
  that is not an executable file, a non-zero exit, a 10 s timeout (when `timeout` exists; without it
  the filter runs unbounded after one warning), or empty output for a non-empty body. Whitespace-only
  output is sent as it is.
- **Environment only:** `.forge.conf` cannot set it, so a cloned branch cannot make the library run
  code. The filter runs without the forge token variables, and its stderr reaches the caller.
- **Side effects:** a `FORGE_DRY_RUN=1` call runs the filter too, so a filter must only print.
- **Scope:** `forge_issue_create` only. The title is never filtered, and a later `forge_issue_edit`
  or comment is not filtered either.
