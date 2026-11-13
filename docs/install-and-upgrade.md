# Install and upgrade

Installing a group is one command, listed per group in [plugins.md](plugins.md) and in the
README's catalogue. This page covers what comes after: the four states a group can be in, removing
a group, what an installed group does in a project that has not asked for it, the declared
dependencies, what forge-adapt does when you run it, and staying current.

## After you install a group

**Four states, and only the last one fails a build.** A group is **installed** once
`claude plugin install` has run. It is **enabled** while `claude plugin list` reports its status as
enabled (`claude plugin disable` and `enable` switch it): its skills, agents and commands are then
in every session. It is **active** in a project only where that project asks, by running its
command or creating the sentinel file a hook waits for (the list is below). It is **enforcing** only
where one of its checks is wired into the project's CI or git hooks, which is a file in the
repository and never a side effect of the install.

`claude plugin list` shows what you have and at which version, and
`claude plugin uninstall <group>@forge-kit` removes a group. Uninstalling does not remove the
dependencies a group pulled in (run `claude plugin prune` for those), and it does not undo what the
group already did in a project: components forge-adapt copied into `.claude/`, hook wiring it merged
into a project's `settings.json`, sentinel files, and what was already written to the forge (the
gate's regions in issue bodies, and any ticket a component filed).

**A group installed at user level loads everywhere but acts only where a project asks.** Its
skills, agents and commands are available in every session. The components that ACT gate
themselves on something the project owns:

- `roadmap-phases` does nothing without a `docs/roadmap.md`;
- each opt-in hook stays dormant until the project creates its sentinel file: `.claude/no-dashes`
  (`block-dashes`), `.claude/no-poll-loops` (`no-poll-loops`), `.claude/masked-exit`
  (`masked-exit-advisory`), `.claude/forge-write-consent` (`forge-write-consent`),
  `.claude/no-destructive` (the daytime arm of `overnight-guard`; forge-adapt never creates it
  unless you say yes, and never recreates it on a refresh) and `.claude/scan-forge-writes`
  (`scan-forge-writes`, in `forge-kit-security`, which also arms when the default branch tracks
  that file);
- the overnight arm of `overnight-guard` and the overnight Stop hook arm only while a run's
  manifest (`.claude/overnight/active.md`) exists; the guard's daytime arm follows
  `.claude/no-destructive`, so removing the manifest does not switch that arm off.

Installing a group is not a commitment to using it everywhere.

**Three groups declare a dependency.** `forge-kit-governance` and `forge-kit-roadmap` both need
`forge-lib.sh` from `forge-kit-devops`. `forge-kit-governance` also declares `forge-kit-security`,
because the ticket gate's security lens dispatches `security-auditor`, and `forge-kit-review`,
because `working-overnight` dispatches `code-reviewer` and `full-review`. `forge-kit-review`
declares `forge-kit-security` too, because `/full-review` dispatches `security-auditor`. A fresh
install pulls each in and says so. Governance reads as not live in a project where
`forge-kit-review` is absent, because the plugin-active check requires every declared dependency
to be installed and enabled. If you are UPDATING a group you already had, see the upgrade note under
[Keeping up to date](#keeping-up-to-date).

## What forge-adapt does

1. **Analyses your project:** stack files, CLAUDE.md, source structure, existing `.claude/` contents
2. **Recommends components:** ranked, with a reason each, and with anything your neighbours already
   cover suppressed or flagged
3. **Waits for your approval:** nothing is written until you choose
4. **Installs what you approved.** Most components are **registered**, by enabling the plugin group
   they live in: they resolve what they need at runtime, so they own no file in your repository that
   could drift, duplicate or clobber. A component is **copied and adapted** into `.claude/` only
   when it must be: when it declares `scope: project`, when you installed from a bare clone with no
   marketplace, or when it is a hook, which reaches a project by its own route. An adapted copy is
   rewritten against your profile, so "check for SQL injection" becomes "check for Prisma
   `$queryRaw` injection in `src/db/`".

Secondary modes: `forge-adapt drift` reports what is behind and writes nothing; `forge-adapt
refresh <name>` deep-compares one component and merges in what it is missing while preserving your
adaptation; `forge-adapt contributions` surfaces project-only components worth contributing back;
`forge-adapt templates` audits issue templates and can install the template governance.

## Keeping up to date

**Adding the marketplace tracks this repository, but by default nothing pulls it for you.**
Claude Code can auto-update a marketplace and its plugins at startup, but auto-update is off by
default for third-party marketplaces such as this one. Turn it on in `/plugin`, under the
Marketplaces tab, for `forge-kit`. Until you do, an installed group stays at the version you
installed. This repository's own maintainer ran four minor versions behind for weeks while
developing against the tree, which is why it is stated here rather than left implied.

```bash
claude plugin marketplace update forge-kit    # refresh the local copy of this repo
claude plugin update forge-kit-governance     # move an installed group onto it
```

`claude plugin update` takes one group at a time, so repeat it for each group you have. Restart
Claude Code afterwards; the CLI says so on each update.

**Upgrade note for `forge-kit-governance`, `forge-kit-review` and `forge-kit-roadmap`.** Governance
declares `forge-kit-devops`, `forge-kit-review` and `forge-kit-security`; review declares
`forge-kit-security`; roadmap declares `forge-kit-devops`. `claude plugin update` alone does NOT
install a dependency a group newly declared. Measured on Claude Code 2.1.310, the updated plugin
reported `failed to load: Dependency ... is not installed`, and merely starting a session did not
fix it. Running `/reload-plugins` in an open session resolves and installs the missing
dependencies, or you can install each one yourself:

```bash
claude plugin install forge-kit-devops@forge-kit
claude plugin install forge-kit-review@forge-kit
claude plugin install forge-kit-security@forge-kit
```

The error names the missing plugin. Claude Code's plugin-dependency documentation says marketplace
auto-update and re-running `claude plugin install` resolve them as well. The measurement used an
in-place directory marketplace and `-p` mode, and did not cover auto-update.

**On a manual install**, `git -C ~/forge-kit pull` is the equivalent. Clone with
`git clone https://github.com/agigante80/forge-kit ~/forge-kit`, then run forge-adapt from your
project: it finds the clone and works from there, adapting components into `.claude/` rather than
registering them, because there is no marketplace to register with.
