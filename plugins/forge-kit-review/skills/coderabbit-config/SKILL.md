---
name: coderabbit-config
description: |
  A hardened `.coderabbit.yaml` template and a checker that fails when a pinned key is loosened,
  removed or renamed by the vendor, for a project that fills the independent reviewer slot with the
  CodeRabbit pull request app. Use when installing or auditing CodeRabbit on a repository, when
  asked whether the CodeRabbit bot can push, approve or block a merge, or when
  check-coderabbit-config.sh reports a finding.
---

<!-- coderabbit-config-version: 3 -->

# CodeRabbit config

The CodeRabbit pull request app is one adapter of the independent reviewer slot (`coderabbit-pr`).
It is installed with write access, and its vendor defaults let a commenter ask it to commit to a
branch. This skill ships two files that keep it advisory: a template with those features pinned
off, and a checker that fails when a pin is loosened.

It ships no reviewer and states no rule about the review itself. How the one outside review joins
round 1, how long it is waited for, how its findings are triaged and what an unattended run does
are the contract in `forge-kit-review:independent-reviewer`; read that skill and declare
`Independent reviewer: coderabbit-pr` as it says. No benefit rate has been measured, so quote none.

## Before installing the app

- **It needs pull requests.** The app reviews a pull request and nothing else. A project that
  lands work by direct commit gets nothing from it: use a local adapter of the slot instead
  (`codex-local`, `coderabbit-local`).
- **It costs time.** The one project that trialled it measured 24 to 58 minutes added per ticket
  by the pull request and the wait. That is one project's number, not a forecast.
- **Hosts, plan, what the vendor receives and keeps:** the `coderabbit-pr` pointer in the
  `independent-reviewer` skill's `references/adapters.md` holds them with dated sources. A project
  with private or regulated code reads that pointer and decides before the app is installed,
  because the app reads the whole repository, commit author names and emails included.
- **The config limits features, not the vendor.** The app keeps its write permission whatever this
  file says. No key here protects against a compromise on the vendor's side. Three limits on the
  project's side do, and the config replaces none of them:
  1. install the app on selected repositories only, never the whole account;
  2. protect the default and the integration branch, so a push from the app cannot land there;
  3. never make its status a required check. It is advisory, and a required check turns a vendor
     outage into a blocked merge.
- **The file is one of several places settings live.** The vendor's web interface and an
  organisation-level config can set the same keys, and the checker sees neither. The template sets
  `inheritance: false` so a parent layer fills nothing in; check the web interface settings by
  hand at install. What the app does with a file its own schema rejects: not stated by the vendor.
- **Some writing stays on.** The review itself, its summary in the pull request description
  (`reviews.high_level_summary`) and the label of the vendor's low-quality pull request detection
  (`reviews.slop_detection`) are not pinned, nor are `reviews.auto_title_placeholder` and
  `chat.integrations` (issue trackers): they write to the pull request or a tracker, never to
  the code.

## Install

1. Copy [assets/coderabbit.yaml](assets/coderabbit.yaml) to `.coderabbit.yaml` at the repository
   root.
2. Replace `<integration-branch>` with the branch pull requests target (each entry is read by the
   vendor as a regex), and adjust the bot list to the dependency bots the project uses. Only bot
   accounts belong there: a person listed in `ignore_usernames` silently loses their review.
   The checker accepts a login ending in `[bot]`, GitHub's form for an app account; on another
   host, pass each bot's login with `--allow-ignored <login>`.
3. Copy [assets/check-coderabbit-config.sh](assets/check-coderabbit-config.sh) to `scripts/` and
   run it. Wire it into CI on the paths that can change the config, so a later edit cannot loosen
   a pin unseen.

```bash
bash scripts/check-coderabbit-config.sh --branch <integration-branch>
```

4. Install the app, open one pull request, and confirm four things once: one advisory review
   arrives; a comment asking the bot to fix something is declined; a comment by someone other
   than the author asking it to approve is declined; the app pushed no commit and opened no
   branch.

## What the checker pins

`check-coderabbit-config.sh [--file <path>] [--branch <name>] [--allow-ignored <login>]... [--schema <file>]`
reads `.coderabbit.yaml` (the vendor reads other file names too; pass `--file` for one) and exits
0 only when every pin holds in that file. Exit 1 lists every broken pin as
`<file>: <key path>: <what is wrong>`. Exit 2 means it could not answer: a usage error, a missing
file, or `cannot parse`. Treat exit 2 as a failure, never as a pass.

It needs `jq` and `python3` with PyYAML, and has no other parser on purpose. Its read is stricter
than PyYAML's own, so it never reads a key more kindly than another parser would: a duplicate key
is `cannot parse`, so are a tag, a merge key (`<<`) and a line break only some parsers honour
(U+0085, U+2028, U+2029), and
only `true` and `false` are booleans, so `enabled: no` fails its pin. Write `false`.

| Group | Keys | Rule |
|---|---|---|
| The file itself | `inheritance` | false or absent |
| | `version` | absent |
| Nothing may push | `reviews.finishing_touches.{unit_tests,simplify,autofix,fix_ci,resolve_merge_conflict}.enabled` | present and false |
| | `reviews.finishing_touches.custom`, `reviews.post_merge_actions` | present and empty |
| Never a gate | `reviews.auto_approvals.enabled`, `.allow_author_approval`, `reviews.fail_commit_status` | present and false |
| | the legacy aliases `reviews.request_changes_workflow`, `reviews.allow_author_approval` | false or absent |
| | `reviews.auto_approvals.overrides` | present, holding an entry that is exactly `{enabled: false}` and every entry setting `enabled: false` |
| | every `mode` under `reviews.pre_merge_checks`, custom checks included | never `error` |
| Scope | `reviews.auto_review.base_branches` | present, a non-empty list, the placeholder replaced, one entry matching `--branch` when given |
| | `reviews.auto_review.ignore_usernames` | every entry ends in `[bot]` or was passed with `--allow-ignored` |
| | `reviews.auto_review.drafts` | false or absent |
| Quiet | `reviews.auto_apply_labels`, `reviews.auto_assign_reviewers`, `issue_enrichment.auto_enrich.enabled`, `issue_enrichment.labeling.auto_apply_labels` | false or absent |
| | `issue_enrichment.planning.enabled`, `issue_enrichment.planning.auto_planning.enabled`, `chat.auto_reply` | present and false |
| One source of rules | `reviews.path_instructions` | empty or absent |
| | `knowledge_base.code_guidelines.enabled` | true or absent |

"Present" is deliberate. Several of these are on by vendor default, so a deleted key turns the
feature on, and a key that matches today's default is still written out because a default can
change. `--branch` applies each entry as a regex anchored at both ends, so a pass holds under a
looser reading too. The vendor's `docstrings` finishing touch is retired and has no effect,
so it is not pinned. The override entry matches every pull request and, by the vendor's schema
text, withholds an approval that someone other than the author asks for in a comment; that was
read from the schema, not observed on the app, so step 4 above checks it once. The last group keeps the project's own `AGENTS.md` and `CLAUDE.md` as the one place its
review rules live; the app reads them through `code_guidelines`.

The pin list was read from the vendor's schema on 2026-11-26. A project that loosens a pin on
purpose edits its copy of the checker and says why in the config, so the next reader finds the
decision next to the key.

## When the vendor changes its schema

A renamed key stays in the file and means nothing. `--schema` catches that: it fails on every
pinned key path that a copy of the vendor's schema no longer defines. The checker never touches
the network, so the caller fetches the copy:

```bash
curl -fsSL https://coderabbit.ai/integrations/schema.v2.json -o coderabbit-schema.json
bash scripts/check-coderabbit-config.sh --schema coderabbit-schema.json
```

Run it when the vendor announces a config change, or on a schedule the project owns. It reports
keys that disappeared. It cannot report a NEW key that pushes or approves: read the vendor's
changelog for those, and report one to forge-kit so the pin list gains it.
