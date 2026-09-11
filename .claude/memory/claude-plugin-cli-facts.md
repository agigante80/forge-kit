---
name: claude-plugin-cli-facts
description: "probed 2.1.265 and 2.1.267: no deprecation field, a broken dependency installs silently and resolves only on install, details ignores preloads and needs --plugin-dir"
metadata:
  type: reference
---

Probed against the installed CLI 2.1.265 on 2026-09-09. These are facts about the harness, not about this repo, so they outlive any ticket here.

**The plugin cache leaf is the SEMVER, not a commit sha.** `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and versions sit side by side (`0.4.1/` and `0.7.11/`). CLAUDE.md said sha for months. The **marketplace checkout** (`~/.claude/plugins/marketplaces/<name>`) is by contrast an ordinary git clone with an `origin` remote, so it is the one of the two that can be compared against a remote.

**Nothing auto-updates.** `claude plugin marketplace update [name]` refreshes the checkout, `claude plugin update <plugin>` the installed copy. There is no `autoUpdate` settings key and no daemon. Every plugin subcommand takes `-y`, documented as required when stdout is not a TTY, which is a scripting affordance rather than automatic behaviour.

**`plugin.json` accepts `dependencies`, and the installer honours it.** An ARRAY of `plugin@marketplace` strings (an object of version ranges is rejected). Installing a dependent prints `+ 1 dependency: <name>` and enables both; `claude plugin prune` finds the orphan after an uninstall. **But an unresolvable dependency installs silently and `claude plugin validate` does not catch it.**

**`author` must be an object** with a `name` (and optional `url`). A bare string fails validation. `userConfig` entries need a `title`.

**`claude plugin details <name>` reports token cost in two columns**, always-on and on-invoke, and it does NOT charge an agent for its preloaded companion skills: a companion grown from 210 to 6k tokens left the declaring agent at under 20. So it disagrees with what [[component-size-is-what-preloads]] established, and it cannot be used as a drop-in for that measurement.

**`claude plugin tag <path>`** creates a `{name}--v{version}` git tag, validating that `plugin.json` and the enclosing marketplace entry agree. It needs a path per plugin; there is no bulk mode.

Related: [[verify-against-installed-artifacts]], which is why every line above was probed rather than read.

**Re-probed 2.1.267 on 2026-09-10, closing #169 to #175.** Everything above holds, plus:

- **`marketplace add` takes no `-y`** in 2.1.267 (`unknown option '-y'`), and it needs an absolute path or `./path`; a bare `.` is rejected as an invalid source format.
- **An unresolvable dependency is caught by NOTHING.** `claude plugin validate` passes it (only the author warning), and `claude plugin install` then succeeds with no dependency line and no error. The CLI validates the SHAPE and never the TARGET. That gap is why `validate-plugins.sh` now resolves declared dependencies against `marketplace.json`.
- **A dependency added to an ALREADY-INSTALLED plugin is not resolved by `update`.** Observed on the maintainer's own machine on 2026-09-10, minutes after #169 shipped: `claude plugin update forge-kit-governance` took it to 0.13.0 and the plugin then reported `✘ failed to load / Dependency "forge-kit-devops@forge-kit" is not installed`. Resolution happens on INSTALL only. The failure is loud and names the fix, which is the right behaviour, but it means adding a `dependencies` entry breaks every existing install until that one command is run. The fresh-install probe could not see this, because a fresh install is the path that works.
- **`author` must be an object with a NON-EMPTY `name`**: a bare string gives `author: Invalid input`, `{"name": ""}` gives `author.name: Author name cannot be empty`, and `url` is optional.
- **`claude plugin details <name>` refuses unless the plugin is INSTALLED**, but `claude --plugin-dir <path> plugin details <name>` reports on a bare checkout with no install and no network. That is the only form usable from CI.
- **`plugin details` still does not charge preloads**, re-confirmed: a companion grown from 14 to 5,000 words moved its own on-invoke figure from `< 20` to `~7.2k` and left the declaring agent at `~40`. Its numbers round to two significant figures with a `< 20` floor, so nothing can ratchet on them.
- **`claude plugin tag <path> --dry-run`** validates plugin.json against the enclosing MARKETPLACE ENTRY's `version` field, and fires only where an entry HAS one (`✘ Version mismatch: plugin.json says "0.1.0" but ... plugins[0].version says "9.9.9"`). forge-kit's entries carry none by design, so the check is vacuous here and is a different invariant from `check-plugin-version-bump.sh`.
- **Probe safely with `CLAUDE_CONFIG_DIR=<tmpdir>`**: every plugin subcommand honours it, so an install probe never touches the real config. Verified afterwards that no probe marketplace reached `~/.claude`.

**There is NO deprecation field, probed 2026-09-10 on 2.1.267.** Both `"deprecated"` and `"supersededBy"` come back as `Unknown field ... Claude Code ignores it at load time` and pass validation WITH A WARNING. Since #173 committed this repo to zero warnings, adding either would break its own rule, so a retirement is communicated by the CHANGELOG, the group description and forge-adapt, and never by a manifest field.

**A dependency added to an ALREADY-INSTALLED plugin is resolved by nothing.** Resolution happens on INSTALL only. Adding a `dependencies` entry therefore breaks every existing install until `claude plugin install <dep>` is run once; the error is loud and names the command, which is the right behaviour, but it is a real upgrade cost. Verified on the maintainer's own machine within an hour of #169 shipping.

## `claude plugin update` does not reach a running session (2026-09-11)

`claude plugin marketplace update forge-kit` and `claude plugin update forge-kit-governance@forge-kit`
both succeeded mid-session (cache went 0.16.0 to 0.16.2, and the CLI printed "Restart to apply
changes"). Five `ticket-gate` dispatches afterwards, in the same session, each reported executing
the installed prose at `ticket-gate` v51, the pre-update copy. The agent definitions are read at
session start and the update is invisible until a restart. Consequence for this repo: a change to
an agent's prose cannot be exercised by a gate run in the session that made it, however many times
the cache is refreshed, so "verified by a live gate run" is a claim only the NEXT session can make.
Two phases (2026-09-11) closed carrying that gap; the first action of the next session is one
`/gate-ticket <N>` with a bare number and a read of the review comment for the `**Round:**` and
`mechanics:` lines the agent itself printed.
