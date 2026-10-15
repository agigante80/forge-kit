# Drift: the inputs to the status script

`drift` and `refresh` print one row per installed component, and the word in the last column
comes from `forge-adapt-drift-status.sh`, never from your own reading of the two markers. It takes
VALUES, not paths (#504). Passing the installed or catalogue file makes it exit 2 with
`is not a version`.

| Input | Value |
|---|---|
| `--local <installed>` | the local copy's marker number; `none` when the copy has no marker; `absent` when there is no local copy. `none` and `absent` are different things: `none` is the install base that predates markers, `absent` is a component the plugin provides. |
| `--catalogue <catalogue>` | the number from the S3 catalogue row (`v3` is accepted as 3), or `none` when the catalogue entry carries no marker. Never `absent`. |
| `--group-enabled` | append it when the component's plugin group is live in this project. Without it every registered component reads `missing`, the false report the flag exists to stop (#167). |

## The group answer

Read the group from the `=== <group> ===` header the row sits under in the S3 catalogue (it already reads `forge-kit-governance`, so use it verbatim), and ask once
per group:

```bash
"${FORGE_KIT_DIR:?}"/scripts/forge-adapt-plugin-active.sh <group>@forge-kit
```

`yes` appends `--group-enabled`. `no`, `unknown` and a library without that script omit it. S2's
`governance-plugin-active=` line covers the governance group only, so it is not the answer for the
others.

## What comes back

One bare word: `current`, `behind`, `unversioned`, `registered` or `missing`. A marker over nine
digits is refused (exit 2, `is too large to compare`) instead of being called `current`; STOP and
report that row, since a marker that long is a typo in the component.

## An unmarked copy of a kit asset (#522)

The Step 1 probe lists a shell asset in `scripts/` when it carries a version marker, or when the
catalogue ships an asset of that name. A copy with no marker therefore prints `vnone` and reads
`unversioned`, which is how a pre-marker install surfaces instead of vanishing. That includes a
project's own script that happens to share a kit asset's name: it also reads `unversioned`, and this
is accepted. Drift writes nothing; `refresh <name>` deep-compares the file and asks before replacing it.

## The ticket-standards doc row (#525)

`docs/guides/ticket-standards.md` is a doc, not a component, so the marker comparison never reaches
it. Print its row in the same table:

```bash
"${FORGE_KIT_DIR:?}"/scripts/forge-adapt-standards-row.sh --project "$PWD" --kit "$FORGE_KIT_DIR"
```

For example `ticket-standards (doc-rules) | v20 | v21 | behind`. It compares `doc-rules-version`
only: the install sets the doc's `template-version` to the project's own, so comparing that to the
kit's would read `behind` on every project whose templates lag on purpose (the Step 1 probe already
reports the templates). The script prints nothing when the project has no such doc, shows an unmarked
doc as `none | v<N> | unversioned`, and exits 2 when the kit copy is missing or unmarked: report that
and keep the rest of the table. The comparison word comes from `forge-adapt-drift-status.sh`.

## The http-steps scan (#528)

forge-lib refuses an `http://` forge URL unless `FORGE_ALLOW_HTTP` is exactly `1` (#442, forge-lib
v36). A project on a LAN Forgejo works in a local session and then fails in CI. Run the scan on every
`drift` and `refresh`:

```bash
"${FORGE_KIT_DIR:?}"/scripts/forge-adapt-http-steps.sh --project "$PWD"
```

`--project` defaults to the repository root. The URL comes from the environment, else the first
non-empty `FORGE_API_URL` line of `.forge.conf` (the same parse as forge-lib: read, never sourced;
first line wins). It stays silent unless the URL starts `http://` and `FORGE_HOST` is not `github`. A
step qualifies when its `run:` text names a `scripts/*.sh` that sources forge-lib (or `gate-env`,
`phase-env`, `roadmap-lib`), calls a `forge_*` function, or names `forge-lib`, and neither the step,
its job nor the workflow sets `FORGE_ALLOW_HTTP` to exactly `1`.

Rows are tab separated: `forge-url` (credentials stripped), one `step <workflow> <job / step>` per
qualifying step labelled by workflow dir (`forgejo=runs` for `.forgejo/workflows`, `forgejo=ignored`
for the others), `not-scanned`, `warning`, `local-session` (names only `.claude/settings.local.json`)
and a final `summary`. When the URL is http and no step qualifies it says so. Exit 0 is clean or
reported, 3 means a workflow dir or file was unreadable (report it, keep the rest), 2 is usage.

The script prints; editing a workflow is the user's act. Never edit one, and never write the variable
into settings.

## The marker delta in `refresh <name>` (#529)

The library is a depth-1 marketplace checkout, so the history behind an installed marker is usually
absent. Ask the helper for the upstream delta:

```bash
"${FORGE_KIT_DIR:?}"/scripts/forge-adapt-marker-delta.sh <library> <component path> <name> <installed version>
```

It finds the commit that set `<name>-version: <N>`, deepening the library ONCE (`fetch --unshallow`,
else one `--deepen`) when that commit is missing, and prints the diff from that commit to HEAD for
the one file. It skips deepening while `.git/shallow.lock` exists, and `forge-adapt-refresh.sh`
re-shallows the library later, which is accepted. Exit 1 prints `marker-delta: unavailable
(<reason>)`: show that line and carry on with the content diff. It never fails the refresh. The delta
is display only and never a 3-way merge base; the two-way classification is unchanged.
