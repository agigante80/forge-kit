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
