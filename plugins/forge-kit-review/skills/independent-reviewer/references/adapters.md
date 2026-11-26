# Adapters for the independent reviewer slot

Each adapter is a pointer to a tool forge-kit does not ship. It says how ONE round is called and by
whom, the reviewer's family, and what leaves the machine. The rules a round obeys are in the
skill's contract and are not repeated here. Vendor facts carry the date they were read; re-read the
page before relying on one. "Not stated" means the pages read are silent, never that the answer is
no.

A route is always a documented command. Never call a plugin's internal script.

## `codex-local`

- **Tool:** the OpenAI Codex CLI. Family: OpenAI.
- **Route an agent can run:** `codex review --base <branch>`, or `codex review --uncommitted` before
  a commit (CLI 0.169.0, read 2026-11-26). It reviews without changing files.
- **Human route:** `/codex:review --wait` from the `codex@openai-codex` plugin. That command is
  marked `disable-model-invocation: true` (plugin 1.0.6, read 2026-11-26), so no agent or unattended
  run can call it; they use the CLI.
- **Hosts:** any. It reads the local worktree.
- **What leaves the machine:** the change and the files the tool reads around it, sent to OpenAI.
  `--uncommitted` covers "staged, unstaged, and untracked changes" (`codex review --help`, CLI
  0.169.0, read 2026-11-26), so an untracked file that git does not ignore is sent too. The
  vendor's CLI pages do not state the exact content. With an API key the API organisation's
  retention and data-sharing settings apply; with a ChatGPT sign-in the workspace's permissions
  apply, and retention and residency settings are described for ChatGPT Enterprise
  (learn.chatgpt.com/docs/auth, read 2026-11-26 through a summary, not verbatim: re-read it).
  Storage location and a deletion route specific to Codex: not stated.

## `coderabbit-local`

- **Tool:** the CodeRabbit CLI. Family: not stated by the vendor ("Ensemble of models & tools", coderabbit.ai, read
  2026-11-26).
- **Route an agent can run:** `coderabbit review --agent --base <branch>`. Passing `--base` also
  avoids the lookup of the repository's origin that default-branch detection can make
  (docs.coderabbit.ai/cli/network-requirements, read 2026-11-26).
- **Human route:** `/coderabbit:code-review` from the `coderabbit@claude-plugins-official` plugin,
  which wraps the same CLI and can also be called by an agent (its skill carries no
  `disable-model-invocation` field, read 2026-11-26).
- **Hosts:** the vendor says a local review needs only a git worktree and names no host
  requirement. Unconfirmed on a Forgejo or Gitea clone.
- **Limits:** 3 CLI reviews per developer per hour on the free and open source plans
  (docs.coderabbit.ai/management/plans, read 2026-11-26). A refusal is the rate-limited outcome.
- **What leaves the machine:** "the CLI sends code diffs to the CodeRabbit API for analysis" (the
  vendor's `code-review` skill file, read 2026-11-26); files not added to git are skipped unless
  `--include-untracked` is passed. Whether commit author details are sent: not stated. Storage,
  retention, encryption and erasure: not stated by the vendor for the CLI (its product-wide
  statements are under `coderabbit-pr` below). Separate US and EU endpoints exist, and from CLI
  0.9.6 an EU review does not switch to the US service (docs.coderabbit.ai/cli/network-requirements,
  read 2026-11-26).

## `coderabbit-pr`

- **Tool:** the CodeRabbit pull request app. Family: not stated by the vendor ("Ensemble of models & tools", coderabbit.ai, read
  2026-11-26).
- **Route:** the app reviews a pull request by itself; the caller reads its review through the
  forge once CI has ended. Nobody mentions the bot.
- **Hosts:** GitHub, GitLab, Bitbucket and Azure DevOps (docs.coderabbit.ai/platforms, read
  2026-11-26). Forgejo and Gitea are not listed.
- **What leaves the machine:** the app is installed on the repository with read and write access to
  code, pull requests, checks, commit statuses, issues and workflows, so it reads the repository,
  not only the change. Its defaults enable features that push commits. Pin them off with a
  reviewed `.coderabbit.yaml` before the first review.
- **Retention:** the vendor "does not retain your source code after a review completes, except
  when review caching is enabled" (coderabbit.ai/faq, read 2026-11-26). Caching is on by default,
  caches are encrypted except for open source projects and expire within seven days
  (docs.coderabbit.ai/reference/caching, read 2026-11-26). An opt-out of data storage exists
  (the same FAQ). A deletion-request
  route and the storage region: not stated.
- **Plans:** full pull request reviews need a paid plan or the vendor's open source plan on a
  public repository; the free plan gives summaries only (read 2026-11-26).
