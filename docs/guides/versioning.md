# Versioning

forge-kit carries **three** version levels plus one unrelated marker. They answer different
questions and must not be conflated. Every one of them is either mechanically enforced or
deliberately has nothing to drift against.

| Level | Where | Answers | Enforced by |
|---|---|---|---|
| Release tag | git tag `vX.Y.Z` | "what state was the whole marketplace in?" | nothing to enforce (see below) |
| Plugin semver | `plugins/<group>/.claude-plugin/plugin.json` `version` | "did this unit of install change?" | `check-plugin-version-bump.sh`, `validate-plugins.sh` |
| Component marker | `<!-- <name>-version: N -->` | "is a cherry-picked copy of this component stale?" | `check-version-bump.sh`, `validate-plugins.sh`, `.githooks/pre-commit` |
| Template version | `template-version: N` in issue templates | "which ticket standard is this?" | `check-template-lockstep.sh` |

## 1. The release tag is the umbrella, and the tag is the source

A release tag names the state of the marketplace as a whole at a point in time. It exists so
humans have something to refer to and a changelog has something to hang off.

**The tag itself is the canonical source. There is deliberately no `VERSION` file and no
`version` field in `marketplace.json`.**

The `release` skill's first rule is that one source is canonical and every other place is a
mirror kept equal to it. forge-kit has seven independently versioned plugins and no natural
single source, so any file claiming a repo-level version would be a mirror with no other source
to check against, and nothing in the repo would guard it. An unguarded mirror is a drift surface,
and this repo's whole argument is mechanical enforcement over remembering. Keeping the tag as the
only source means there is exactly one place to be wrong and no way for two places to disagree.

**What the tag does not do: it does not gate distribution.** Users install with
`/plugin marketplace add agigante80/forge-kit`, which tracks the repository, and
`marketplace.json` points at local `./plugins/...` paths. Everyone is already served from the
default branch. A tag is a communication artifact, not a delivery mechanism, so cutting one never
changes what an existing user receives.

**When to bump it.** Pre-1.0, minor for a release that adds or materially reworks components,
patch for fixes and docs. The umbrella version is not derived from the plugin versions by any
formula; do not try to compute it from them.

## 2. Plugin semver is the unit of install

`version` in each `plugin.json` is the ecosystem-standard version the marketplace and tooling
read. It is per plugin **group**, and the seven groups move independently and at very different
rates. A group at 0.7.x and a group at 0.1.0 is normal and says nothing about quality; it says
one has been revised more often.

Changing anything in a group requires strictly increasing that group's semver, enforced on every
PR by `check-plugin-version-bump.sh` and locally by the pre-commit hook. The guard exists because
this exact rot happened in PRs #74 and #75, where component markers moved and the unit-of-install
version did not.

## 3. Component markers are the drift signal

`<!-- <name>-version: N -->` (or `# <name>-version: N` in hooks and shell assets) is forge-kit's
finer-grained signal. `forge-adapt` cherry-picks a component into a project's `.claude/` and
rewrites it for that stack; divorced from its plugin, that loose file needs its own version, and
adaptation deliberately does not change the marker so staleness stays detectable.

This is what `forge-adapt drift` and `forge-adapt refresh <name>` compare. See CLAUDE.md for the
enforced path set and the positional parsing rule, both of which are duplicated across three
guards and must be changed together.

**A component's marker name is not required to equal its component name.** Exactly one diverges
today: `skills/adapt/SKILL.md` is catalogued as `adapt` but carries `forge-adapt-version`.

## 4. `template-version` is not one of these

The `template-version: N` marker on the five work issue templates tracks the ticket standard, not
a component. `check-template-lockstep.sh` keeps the templates and the canonical
`docs/guides/ticket-standards.md` on one shared value so they cannot drift apart. The marker
parsers skip it explicitly.

## Cutting a release

1. Confirm main is green and every intended PR is merged.
2. Update `CHANGELOG.md`: add the new version section, thematic rather than a commit dump.
3. Tag `vX.Y.Z` on main and push the tag.
4. Create the GitHub release from that tag, with the changelog section as its body.
5. Close the tickets the release shipped.

Plugin semvers are **not** touched by cutting a release. They move when their group changes, on
the PR that changes it, which is the only time the guard can see it.
