---
description: "Check every CI workflow (GitHub Actions, or Forgejo Actions through forge-lib) for failures, create P0 tickets, gate each ticket, and auto-fix safe failures on GitHub."
---

<!-- ci-health-version: 14 -->

# CI Health Monitor

Check every CI workflow for failures, create P0 tickets, gate each ticket, and auto-fix safe
failures. On GitHub this reads GitHub Actions with `gh`. On a Forgejo host it goes through
`scripts/forge-lib.sh` and is detect-and-ticket only (#552): one verdict per branch, no job logs,
no auto-fix.

## Process

Execute these phases in order. Stop early if every workflow is passing.

### Phase 0: Host

Test for the adapter BEFORE sourcing it; without it, read the origin host with no library at all
(scheme, `user:token@` and `:port` stripped, scp form handled), so a refusal never prints a token:

```bash
if [ -f scripts/forge-lib.sh ]; then
  . scripts/forge-lib.sh || exit 1
  declare -F forge_url_check >/dev/null || { echo "ci-health: scripts/forge-lib.sh has no forge_url_check; update it (forge-adapt refresh)"; exit 1; }
  forge_url_check && HOST=$(forge_host) || exit 1
else
  ORIGIN_HOST=$(git remote get-url origin 2>/dev/null | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#/.*##; s#^.*@##; s#:.*##' | tr '[:upper:]' '[:lower:]')
  case "$ORIGIN_HOST" in
    github.com|ssh.github.com) HOST=github ;;
    *) echo "ci-health needs scripts/forge-lib.sh on a non-GitHub host (host: $ORIGIN_HOST)"; exit 1 ;;
  esac
fi
```

A refusal stops the command: no `gh` call, no ticket. `forge_url_check` runs the `.forge.conf`
default-branch pin first, so a branch that edits `FORGE_HOST` cannot choose the `gh` path; a
library too old to have it is refused with a request to update it. Known limitation: a Forgejo remote with
`FORGE_API_URL` unset is read as `github` by `forge_host`, so it takes the GitHub path.

### Phase 1: Discover and assess workflows

Discover the workflow files. On GitHub only `.github/workflows` counts, whatever else exists. On
Forgejo, `forge_workflow_dir` prints the first of `.forgejo/workflows`, `.gitea/workflows`,
`.github/workflows` that EXISTS (Forgejo's own rule: an existing but empty directory still wins):

```bash
if [ "$HOST" = github ]; then WF_DIR=.github/workflows; else WF_DIR=$(forge_workflow_dir) || WF_DIR=""; fi
[ -n "$WF_DIR" ] && ls "$WF_DIR"/*.yml "$WF_DIR"/*.yaml 2>/dev/null
```

If that lists nothing, report "No workflows found (no workflows in <WF_DIR>; searched .forgejo/workflows, .gitea/workflows, .github/workflows)" and stop without querying the host. It is neither a pass nor a refusal.

Detect the default branch into `BRANCH`, which every later step reads (the full ref, because
`--short` turns ambiguous when a local branch is named `origin/...`; no `origin/HEAD` means `main`; run `git remote set-head origin -a` if that is wrong):

```bash
BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); BRANCH=${BRANCH#refs/remotes/origin/}; BRANCH=${BRANCH:-main}
```

**On GitHub**, check the latest run of each workflow on that branch, then the failed jobs and logs:

```bash
# GitHub path
gh run list --workflow <workflow-file> --branch <branch> --limit 1 --json databaseId,conclusion,createdAt,name -q '.[0]'
gh run view <RUN_ID> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name'
gh run view <RUN_ID> --log-failed 2>&1 | tail -150
```

Report a summary table:

| Workflow | Status | Failed jobs |
|---|---|---|
| ci.yml | pass/fail | job1, job2 |
| deploy.yml | pass/fail | - |

**On Forgejo**, read ONE verdict for the branch; the sha is the one `forge_ci_status` judges.
Report the branch, `$WF_DIR` and the verdict, never a per-workflow or per-job result:

```bash
VERDICT=$(forge_ci_status "$BRANCH")   # its stderr passes through untouched
SHA=$(git rev-parse --verify "$BRANCH" 2>/dev/null)
```

| Verdict | Report | Ticket |
|---|---|---|
| `success` | green | not ticketed |
| `failure` | red | ticketed (Phase 2) |
| `cancelled` | "cancelled (superseded), no failure" (#193) | not ticketed |
| `none` | "no CI run found", not green | not ticketed |
| `pending` | "pending", not green | not ticketed |
| `not_configured` | "CI status unavailable (not_configured)" plus its stderr line, not green | not ticketed |
| any other word | `unknown status <word>`, not green | not ticketed |

If ALL workflows are passing (on Forgejo: the verdict is `success`), report "All workflows green" and stop.

**Classify governance workflows separately (GitHub).** A red **release / version-gate** workflow
(e.g. `Release Gate`, or any version-bump enforcement from the `release-automation` skill) is an
*intentional governance signal* (the PR author must bump the version), **not** a CI breakage.
Do not file a P0 bug for it and do not carry it into the fix phases; surface it as "action: bump
the version per docs/versioning.md" and move on (see Phase 4). Forgejo limitation: release or
version-gate classification is not done on Forgejo, because `forge_ci_status` carries no workflow
name; every red Forgejo branch is ticketed by the one branch rule.

### Phase 2: Create tickets for failures

With `.claude/forge-write-consent` present (#565), tickets past the session's ticket budget need
the user's `allow-ticket` in the prompt (`/ci-health allow-ticket`); on a deny, list the tickets
you would file and ask.

**On GitHub**, for each failing job:

1. **Check for an existing open ticket** to avoid duplicates:
```bash
# GitHub path
gh issue list --search "fix(ci): <job-name-keyword>" --state open --limit 1
```

2. **If no ticket exists**, create one:
   - Title: `fix(ci): <workflow> - <job-name> failing on <branch>`
   - Labels: `bug`, `infrastructure`
   - Priority: P0
   - Body must include:
     - Error logs (last 100 lines of failed job)
     - Link to the failing run
     - Affected files (if identifiable from logs)
     - the CURRENT `<!-- template-version: N -->` marker (never a hardcoded number). Resolve it
       ONCE for the whole run, not per ticket, with the same host-aware read dep-auditor
       documents (template dir loop + `sed -n 's/.*template-version: \([0-9][0-9]*\).*/\1/p' | sort -un | tail -1`;
       shared resolver tracked in #77); when it resolves empty (no versioned templates), OMIT
       the marker line rather than stamping a blank or invented number
     - Acceptance criteria: "CI job passes on `<branch>`"
     - Documentation impact: "None: CI repair, no user-visible surface" unless the fix changes
       documented workflows

3. **If a ticket already exists**, replace the error logs in its BODY with the latest ones. Never
   add them as a comment: a ticket is read by its body.
```bash
# GitHub path
gh issue edit <N> --body-file <updated-body>
```

**On Forgejo**, one ticket per red BRANCH, titled `CI failure: <branch> (<WF_DIR>)`, for example
`CI failure: main (.forgejo/workflows)`. The dedupe key is the prefix `CI failure: <branch> (`,
`(` included so `main-old` never matches `main`, plus ci-health's own status region in the body, so
an issue someone opened by hand under that title is never taken over; matched locally over
`forge_issue_list` output:

```bash
EXISTING=$(forge_issue_list open | jq -r --arg k "CI failure: $BRANCH (" '[.[] | select((.title | startswith($k)) and ((.body // "") | contains("<!-- ci-health-status:start -->")))][0].number // empty')
```

- **An open match is updated in its BODY, never a comment and never a second ticket:**
  `forge_body_region_set "$EXISTING" ci-health ci-health-status "<verdict word> at <sha>"`, with
  no run URL and no logs, and `forge_issue_create` is not called. Print "existing ticket #<N> updated".
- **No match:** `forge_issue_create` with the title above and a body naming the branch, `$WF_DIR`,
  the verdict word and the sha inside a `<!-- ci-health-status:start -->` / `<!-- ci-health-status:end -->`
  region (no log excerpt; the stamp and sections as on GitHub), then label it.
  `forge_issue_label` refuses the whole call on one unknown name, so read the repo's labels first
  and pass only those that exist; report every skipped name in the summary:

```bash
HAVE=$(forge_api_paginate "/repos/$(forge_repo)/labels" | jq -r '.[].name'); USE=(); SKIP=()
for l in bug infrastructure; do if printf '%s\n' "$HAVE" | grep -qxF -- "$l"; then USE+=("$l"); else SKIP+=("$l"); fi; done
```

  With `USE` empty, do not call `forge_issue_label`. A non-zero `forge_issue_label "$N" "${USE[@]}"`
  is reported as "ticket #<N> created but labels were refused: <stderr line>", never retried and
  never reported as fully filed. Org-level labels are not in that list, so they read as skipped.

### Phase 3: Gate each new ticket

Run the ticket-gate agent on each newly created ticket. Fix and re-run until it returns PASS.

Use parallel agents if multiple tickets were created.

### Phase 4: Implement fixes

On Forgejo, skip this phase: job logs are not reachable on Forgejo, so there is nothing safe to fix from.

For each gated ticket:

**AUTO-IMPLEMENT** (fix and push):
- Lint failures
- Type-check failures
- Unit test failures
- Build failures
- Dependency issues
- Configuration errors

**DO NOT AUTO-IMPLEMENT** (investigate only, leave a comment):
- E2E test failures: comment "E2E: investigation complete, manual review required before fix"
- Security scan findings: comment with findings summary, do not auto-fix
- Release / version-gate failures: the bump is the PR author's call (patch/minor/major per
  `docs/versioning.md`). Never auto-bump the version to make the gate pass; that defeats the
  gate's entire purpose. Comment the required action, or skip it entirely per Phase 1.

After implementing, run the project's lint and test commands (check CLAUDE.md for the
exact commands, e.g. `pnpm lint && pnpm typecheck && pnpm test:unit`), then:

```bash
git add <specific-files>
git commit -m "fix(ci): <description>"
git push origin <branch>
```

### Phase 5: Verify

After pushing, wait 30 seconds then check whether a new run was triggered:

```bash
# GitHub path
gh run list --workflow <workflow-file> --branch <branch> --limit 1 --json databaseId,status,conclusion -q '.[0]'
```

On Forgejo, read `forge_ci_status "$BRANCH"` again instead. Report whether the fix was pushed and
a new run is in progress.

---

## Rules

- **Never hard-code workflow file names:** always discover them from `$WF_DIR` (Phase 1)
- **Never hard-code branch names:** always detect from git or ask the user
- **No `gh run` or `gh issue` on a non-GitHub host:** those live only in the GitHub path blocks
- **The gate must return PASS** before implementing any fix
- **One commit per fix:** not one big commit for everything
- **Only push to the working branch:** never to `main` directly unless that is the working branch
- **No duplicate tickets:** always search before creating
- **Never use `pnpm.overrides`** to resolve dependency conflicts
