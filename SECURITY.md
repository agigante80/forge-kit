# Security policy

forge-kit ships code that runs on your machine and writes to your forge: Claude Code hooks, shell
assets, a leak guard and CI workflows. A flaw in any of them is a security issue, and this page
says how to report one privately.

## Supported versions

Fixes land on `main` and ship in the next release. Supported:

- the latest published release, as listed on the
  [releases page](https://github.com/agigante80/forge-kit/releases);
- `main`, because a plugin marketplace install follows the default branch.

Release tags cover the whole repository. The plugin groups carry their own versions, so report
the group and its `plugin.json` version as well as the tag or commit.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:
[report a vulnerability](https://github.com/agigante80/forge-kit/security/advisories/new).
Do not open a public issue, and do not post details in a discussion or a pull request.

Include what you can of:

- the component and file, and the version or commit;
- the steps to reproduce, or a proof of concept;
- what an attacker gains, and what they need first.

## Scope

In scope:

- the hooks under `plugins/*/hooks/`, including the ones that guard forge writes
  (`forge-write-consent.py`, `scan-forge-writes.py`);
- the shell assets under `plugins/*/skills/*/assets/` and `scripts/`, including `forge-lib.sh`,
  which writes to GitHub and Forgejo;
- the leak guard (`check-public-leaks.sh`, `check-private-leaks.sh`): a bypass that lets a home
  path, an email address or a private name reach a public repository;
- the CI workflows under `.github/workflows/`, for example `gate-staleness.yml`, which holds
  `issues: write`;
- prompt injection: text in an issue, a pull request or a comment that makes a forge-kit agent
  write to the forge, run a command or leak data it should not.

Out of scope: bugs in Claude Code, GitHub, Forgejo or another tool forge-kit calls. Report those
to their vendors. A forge-kit component that relies on such a bug in an unsafe way is in scope.

## What to expect

forge-kit is maintained by one person in their own time. Reports are handled on a best effort
basis, with no fixed response or fix time. You will get an answer in the private advisory, and a
confirmed issue is fixed on `main`, released, and credited to you in the advisory unless you ask
otherwise.
