# Install and upgrade

Installing a group is one command, listed per group in [plugins.md](plugins.md) and in the
README's catalogue. This page covers what comes after: the states a group can be in, removing
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
dependencies a group pulled in: the CLI says which ones are no longer needed, and
`claude plugin prune` (or `uninstall --prune`) removes them. Prune takes only the groups Claude Code
installed as dependencies; a group you installed yourself, even one a second group also needs,
stays. Uninstalling does not undo what the group already did in a project: components forge-adapt
copied into `.claude/`, hook wiring it merged into a project's `settings.json`, sentinel files, and
what was already written to the forge (the gate's regions in issue bodies, and any ticket a
component filed). [What each path leaves behind](#what-each-path-leaves-behind) lists every file and
setting, per path.

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

**Some groups declare a dependency.** `forge-kit-governance` and `forge-kit-roadmap` both need
`forge-lib.sh` from `forge-kit-devops`. `forge-kit-governance` also declares `forge-kit-security`,
because the ticket gate's security lens dispatches `security-auditor`, and `forge-kit-review`,
because `working-overnight` dispatches `code-reviewer` and `full-review`. `forge-kit-review`
declares `forge-kit-security` too, because `/full-review` dispatches `security-auditor`. A fresh
install pulls each in and says so. Remove a dependency while its dependant is
installed and the CLI succeeds with a warning ("required by forge-kit-governance"), after which
`claude plugin list` shows the dependant as `failed to load` with the error naming the missing
group. The forge-adapt plugin-active check reads the same state: governance is not live in a
project where `forge-kit-review` is absent, because every declared dependency must be installed and
enabled. If you are UPDATING a group you already had, see the upgrade note under
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
installed. This repository's own maintainer ran several minor versions behind for weeks while
developing against the tree, which is why it is stated here rather than left implied.

```bash
claude plugin marketplace update forge-kit    # refresh the local copy of this repo
claude plugin update forge-kit-governance     # move an installed group onto it
```

`claude plugin update` takes one group at a time, so repeat it for each group you have. Restart
Claude Code afterwards; the CLI says so on each update.

**Upgrade note for `forge-kit-governance`, `forge-kit-review` and `forge-kit-roadmap`.** Governance
declares `forge-kit-devops`, `forge-kit-review` and `forge-kit-security`; review declares
`forge-kit-security`; roadmap declares `forge-kit-devops`. Walked on 2026-11-13 with Claude Code
2.1.323, from governance 0.36.4 (which declared only `forge-kit-devops`): `claude plugin update
forge-kit-governance@forge-kit` moved it to the current version and installed the two groups it
newly declared, saying "(+ 2 dependencies: forge-kit-review, forge-kit-security)". Two things stay
your job. A dependency you already had is NOT updated by that command: `forge-kit-devops` stayed at
its old version until it was updated by name, so update every group you have, the dependencies
included. And an older Claude Code behaved differently: measured on 2026-10-26 with 2.1.310 on an
in-place directory marketplace, the updated plugin reported `failed to load: Dependency ... is not
installed`, and merely starting a session did not fix it. If you meet that state, `/reload-plugins`
in an open session resolves and installs the missing dependencies, or install each one yourself:

```bash
claude plugin install forge-kit-devops@forge-kit
claude plugin install forge-kit-review@forge-kit
claude plugin install forge-kit-security@forge-kit
```

The error names the missing plugin, for example `Dependency "forge-kit-devops@forge-kit" is not
installed`, and tells you to run `claude plugin install` for it. The same error appears if you
uninstall a dependency yourself. Auto-update at startup was not walked.

**On a manual install**, `git -C ~/forge-kit pull` is the equivalent. Clone with
`git clone https://github.com/agigante80/forge-kit ~/forge-kit`, then run forge-adapt from your
project: it finds the clone and works from there, adapting components into `.claude/` rather than
registering them, because there is no marketplace to register with.

## What each path leaves behind

Each path below was run on 2026-11-13 with Claude Code 2.1.323, following only the commands in
these docs, in a fresh config directory (`CLAUDE_CONFIG_DIR`) and a throwaway git project, so none
of it comes from a long-used install. "The config directory" is `~/.claude` unless you set that
variable. A version number moves; the files and settings do not.

**Fresh install** (`claude plugin marketplace add agigante80/forge-kit`, then `claude plugin install
forge-kit-governance@forge-kit`). The install said "(+ 3 dependencies: forge-kit-devops,
forge-kit-review, forge-kit-security)" and `claude plugin list` showed all four enabled. Left behind:

- in the config directory, `settings.json` gains `extraKnownMarketplaces` (forge-kit, source
  `agigante80/forge-kit`) and `enabledPlugins` (the four groups, true);
- in the config directory, `plugins/known_marketplaces.json`, `plugins/installed_plugins.json` (the
  three dependencies marked `auto`), a clone of this repository under `plugins/marketplaces/forge-kit/`
  and one copy per group under `plugins/cache/forge-kit/<group>/<version>/`;
- in your project: nothing. The install touches no repository.

`claude plugin install -s project <group>@forge-kit` instead writes `enabledPlugins` into the
project's own `.claude/settings.json`, a file you commit, so the whole team gets the group; the
marketplace entry stays in your user settings.

**Upgrade across a newly declared dependency.** The commands are in the upgrade note above. Left
behind: the old version's cache directory stays beside the new one, `enabledPlugins` gains the
new dependencies, and `installed_plugins.json` marks them `auto`. Nothing in a project changes.

**A guard, dormant and then armed.** With the groups installed and a project that has no `.claude/`
directory, each opt-in hook was run through the command line its `hooks.json` registers, with a
payload it denies. Every one passed silently, exit 0 and no output, until its sentinel existed:

| Hook | Sentinel that arms it | Armed result on the denied payload |
|---|---|---|
| `block-dashes` | `.claude/no-dashes` | a `block` decision |
| `no-poll-loops` | `.claude/no-poll-loops` | a deny |
| `overnight-guard` | `.claude/no-destructive`, or `.claude/overnight/active.md` | a deny |
| `forge-write-consent` | `.claude/forge-write-consent` | a deny |
| `masked-exit-advisory` | `.claude/masked-exit` | an advisory, never a deny |
| `scan-forge-writes` | `.claude/scan-forge-writes`, or that file tracked on the default branch | a deny |

Deleting the sentinel disarmed each one again, so a hook costs nothing in a project that has not
asked for it, and removing a group leaves only the sentinel files you created. For
`scan-forge-writes` the tracked file counted even with the working-tree copy deleted, and stopped
counting once the default branch no longer tracked it.

**Removal of a marketplace install.** In order, with what remains after each step:

| Step | What remains |
|---|---|
| `claude plugin uninstall forge-kit-governance@forge-kit` | The three dependencies, still enabled, and a line naming them as no longer needed. Cache directories of every group. |
| `claude plugin prune` | Only the dependencies Claude Code installed itself are removed; a group you installed by name, such as one you reinstalled, stays. |
| `claude plugin marketplace remove forge-kit` | Uninstalls every remaining group from that marketplace, at every scope, and empties `extraKnownMarketplaces` and `enabledPlugins` in `settings.json`. The cache directories under `plugins/cache/forge-kit/` and the version folders in them stay on disk. |

A project-scope install leaves `.claude/settings.json` in the project with an empty
`"enabledPlugins": {}` after the last group is gone. Delete it if the project had no such file
before. Sentinel files, `.full-review/`, and whatever the group wrote to the forge are untouched
by all of it.

**Removal of a copied, adapted install.** forge-adapt needs a signed-in Claude Code session, so this
path was walked on its documented shape instead: a hook copy under `.claude/hooks/` wired into
`.claude/settings.json`, plus an agent under `.claude/agents/` and a skill under `.claude/skills/`.
Nothing registers a copy with Claude Code, so nothing uninstalls it. Do these in this order:

1. **Unwire a hook before you delete it.** A hook still wired in `settings.json` whose file is gone
   runs `python3 <missing file>`, which exits 2, and Claude Code reads exit 2 from a `PreToolUse`
   hook as a deny. Every matching tool call is then refused, including the shell call you would use
   to repair it. With forge-kit-adapt installed, `hook-unwire.sh <name>` removes only that hook's
   entries and exits 0; it needs `jq`. It sits under the plugin's `skills/adapt/assets/` in the
   plugin cache (`~/.claude/plugins/cache/forge-kit/forge-kit-adapt/<version>/`) and in a clone of
   this repository. Delete the file only after it exits 0, as in `hook-unwire.sh <name> && rm
   <file>`: any other exit (jq missing, a `settings.json` it cannot rewrite safely, or the hook
   still wired in `settings.local.json`) leaves the wiring in place. Or edit the `hooks` entry out
   of `settings.json` by hand.
2. Delete the hook copy, then the copied agents and skills.
3. Expect to keep what is not yours to delete: the now empty `"PreToolUse": []` in `settings.json`,
   empty `.claude/hooks/`, `.claude/agents/` and `.claude/skills/` directories, and everything the
   components wrote to the forge.

**What was proven where.** The fresh install, the dependency pull on update, the removal commands
and the marketplace removal ran against the GitHub marketplace `agigante80/forge-kit` as a cached
install. The upgrade needs an older version of the repository, which GitHub serves only as a tag
that cannot then move to the current main, so it ran twice against local sources: a git-sourced
marketplace served over HTTP from a local mirror (a cached clone, as GitHub is) and an in-place
directory marketplace. Both gave the result above. The hooks were run as shell commands against the
installed cache, not inside a live session, so a session start with the group enabled was not
walked. The copied install used the documented file shape rather than a forge-adapt run.
