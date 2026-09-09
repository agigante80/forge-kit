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

### Why there is no per-plugin tag, and why `claude plugin tag` is not in the release lane (#171)

The CLI ships `claude plugin tag [path]`, which creates a `{name}--v{version}` git tag and
validates "that plugin.json and any enclosing marketplace entry agree". Probed on 2.1.267 against
this repository:

```
$ claude plugin tag plugins/forge-kit-governance --dry-run
Marketplace entry: plugins[1] in <repo>/.claude-plugin/marketplace.json
Tag:     forge-kit-governance--v0.12.1
✔ Dry run, would create tag forge-kit-governance--v0.12.1 at HEAD
```

**Two reasons forge-kit does not adopt it, and the first was a surprise.**

The agreement it validates is **vacuous here**. It fires only when a marketplace entry carries its
own `version` field, which forge-kit's deliberately do not (section 1: no mirror with nothing to
check it against). Probed on a throwaway repo where the entry did carry one:

```
✘ Version mismatch: plugin.json says "0.1.0" but marketplace.json plugins[0].version says
  "9.9.9". plugin.json wins at install time, so update the marketplace entry.
```

So `claude plugin tag` and `check-plugin-version-bump.sh` do **not** check the same invariant, as
this ticket assumed when it was filed. Ours asks whether a changed group's version INCREASED, at
build time, on every push. Its asks whether two copies of a version agree, at tag time, and this
repo keeps only one copy on purpose. Calling it in the release lane as a verification step would
add a hard dependency on the `claude` CLI to buy a check that cannot fail here.

Second, **nothing would consume the tags**. Eight groups is eight tags per release, which buries
the umbrella tag that people actually refer to. The one real use, "check out
`forge-kit-governance` as it was at 0.10.0", is served by `git log` on that group's `plugin.json`,
which needs no tag and no tooling. If a consumer ever appears, that is the moment to revisit this,
and `--force` must never be passed when it does: it skips the dirty-tree and existing-tag checks,
which are the two integrity checks a release path has.

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

Nor is `doc-rules-version: N`, the second marker on that same doc (issue #94). It records the
revision of the RULES TEXT, where `template-version` records which FORM the doc describes. They
are separate because they have different consumers moving at different rates: bumping
`template-version` makes `ticket-gate` re-synthesise every open ticket, so tying a prose
clarification to it made the cheap change expensive. The lockstep guard ignores the rules marker
by matching `template-version:` literally. See `docs/guides/template-versioning.md`.

## Cutting a release

1. Confirm main is green and every intended PR is merged.
2. Update `CHANGELOG.md`: add the new version section, thematic rather than a commit dump.
3. Tag `vX.Y.Z` on main and push the tag.
4. Create the GitHub release from that tag, with the changelog section as its body.
5. Close the tickets the release shipped.

Plugin semvers are **not** touched by cutting a release. They move when their group changes, on
the PR that changes it, which is the only time the guard can see it.
