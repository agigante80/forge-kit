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

## Gate citations the project's doc lacks (#519)

Since #510 the gate cites `docs/guides/ticket-standards.md` sections by title, as `section "Unit
test specs"`. A project that renamed those sections has a gate pointing at headings that are not
there, and neither the markers nor `stale-rules.sh` can see it. After the marker table, run (read
only, writes nothing):

```bash
"${FORGE_KIT_DIR:?}"/plugins/forge-kit-adapt/skills/adapt/assets/citation-check.sh \
  --kit "$FORGE_KIT_DIR" --project "$PWD"
```

It reads the citing files from the project's own copy, else the live plugin copy the registry
names, else the kit, and prints tab-separated rows:

- `citation-missing "<Title>"`: the gate cites a title the doc has no heading for. Print a
  `Gate citations` table, one row per title, and offer the user two fixes: restore or rename that
  section in the doc, or, only for a COPIED gate (`scope: project`, or a bare-clone install), map
  the citation in the adapted copy. A registered gate is the plugin cache's file, replaced on every
  plugin update: never edit it, restore the doc section instead. Say which section titles the gate
  cites that the doc lacks, never which section "replaces" them: that is the user's mapping.
- `skipped no ticket-standards doc`: print one line, nothing per title.
- `not-scanned <what> <reason>`: print it; the gate was not found or the doc was unreadable.
- `summary <checked> <missing> <not-scanned>`, always last.

Exit 0 is clean (a skipped doc counts), 1 has a missing title, 3 is incomplete and is never clean,
2 is a usage error. A heading matches on its whole title, ignoring a leading `N. ` and a trailing
parenthetical; a title only inside a longer heading, or only inside a code fence, is missing.
