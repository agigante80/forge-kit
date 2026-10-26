# Drift: the inputs to the status script

`drift` and `refresh` print one row per installed component, and the word in the last column
comes from `forge-adapt-drift-status.sh`, never from your own reading of the two markers. It takes
VALUES, not paths (#504). Passing the installed or catalogue file makes it exit 2 with
`is not a version`.

| Input | Value |
|---|---|
| `--local <installed>` | the local copy's marker number; `none` when the copy has no marker; `absent` when there is no local copy. `none` and `absent` are different things: `none` is the install base that predates markers, `absent` is a component the plugin provides. |
| `--catalogue <catalogue>` | the number from the S3 catalogue row (`v3` is accepted as 3), or `none` when the catalogue entry carries no marker. Never `absent`. |
| `--group-enabled` | append it when the component's plugin group is live in this project. Without it every registered component reads `missing`, the false report the flag exists to stop (#167). WITH a local copy it also means the copy duplicates the plugin, so the word is `shadowed` or `kept` whatever the markers say (#550): append it to a row with a local copy only for the rows in "A local copy the live plugin provides" below. |
| `--kept` | append it, together with `--group-enabled`, when the local copy carries `<!-- adapt-kept: shadows-plugin -->` (a skill: in its `SKILL.md`). It turns `shadowed` into `kept`. Ignored without `--group-enabled`; with `--local absent` it exits 2 (`--kept needs a local copy`). |

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

One bare word: `current`, `behind`, `unversioned`, `registered`, `missing`, `shadowed` or `kept`. A marker over nine
digits is refused (exit 2, `is too large to compare`) instead of being called `current`; STOP and
report that row, since a marker that long is a typo in the component.

## A local copy the live plugin provides (#550)

When the group is live the plugin already supplies the component, so a copy under `.claude/` runs
twice: both the plugin's agent, skill or command and the local one are listed. `refresh` used to
compare and update the copy, which kept the duplicate alive. The word is now `shadowed`, or `kept`
once the user chose to keep it.

**Scope.** Only subagent, skill and command rows with a local copy get `--group-enabled` (and
`--kept`). A shell asset keeps its marker words, because CI and hooks run the project's copy. A
component whose frontmatter says `scope: project` never gets the flag. A row with no local copy keeps
`--group-enabled` as before, so it still reads `registered`. A hook copy follows its own rules,
under "A hook copy" below.

**Untouched or edited.** Take the baseline from the installed marker, never from the plugin's current
file, since an old unedited copy always differs from that:

1. Run `forge-adapt-marker-delta.sh` on the component's marker file, passing the bare installed number.
2. On `set in <sha>`, read each file of the copy as `git -C <library> show <sha>:<path>`. A skill's
   file list comes from the LOCAL directory, and the `SKILL.md` sha is used for every file in it.
3. On `is current`, the baseline is the catalogue copy.
4. A copy is untouched when every file matches its baseline once the version-marker line and any
   `adapt-kept` line are ignored. A missing file, exit 2 from the helper, a failing `show`,
   `unavailable`, or `--local none` count as edited. A `SKILL.md` sha that is stale for a sibling file
   fails safe the same way: it reads edited, and the user keeps the copy.

The commit id is a baseline pointer here, and the diff the helper prints stays display only.

**Actions, shown per row, never taken on a plain `drift`.** An untouched copy offers `retire` as the
default; an edited copy shows the diff against its baseline and offers `keep` as the default.

- `retire` runs only under `refresh <name>` and only on a typed `yes`. The name must be non-empty with
  no `/`, no `..` and no leading `-`, and resolve to exactly `.claude/agents/<name>.md`,
  `.claude/commands/<name>.md` or the directory `.claude/skills/<name>/`, which must exist (no glob).
  Print the path and warn that the project's repository may track it, then delete it.
- `keep` appends `<!-- adapt-kept: shadows-plugin -->` to the copy (to `SKILL.md` for a skill). The next
  drift passes `--kept` and prints `kept`.
- `refresh` never merges a `shadowed` copy. On a `kept` row it runs the usual comparison and merge.

### A hook copy (#564)

A hook is shadowed only when the plugin really runs it here, which `--group-enabled` does not say: the
plugin's `hooks/hooks.json` wraps each hook in a sentinel test, so a live group with no sentinel file runs
nothing. Liveness is its own flag, `--hook-live`, passed instead of `--group-enabled` for a hook row that has
a local copy. It is true only when all of these hold:

1. `forge-adapt-plugin-active.sh <group>@forge-kit` prints `yes`.
2. The group's `hooks/hooks.json` has an entry whose last argument ends in `/hooks/<name>.py`.
3. Every sentinel path that entry tests exists in the project. Read them from that entry's `args[1]` with
   `grep -oP '\[ -f "\$CLAUDE_PROJECT_DIR/\K[^"]+(?=" \])'`. The number of `[ -f` occurrences must equal the
   number of paths read, otherwise the hook is not live (an unparseable string fails safe). An entry with no
   `[ -f` is live on the group alone.

`<name>` is the extensionless catalogue name and must match `^[a-z0-9][a-z0-9-]*$`. Its local copy is
`.claude/hooks/<name>.py` or `.claude/hooks/<name>.sh`: exactly one must exist as a regular file, no glob.

Drift prints `shadowed` for any live-shadowed hook copy, and nothing else about it. `refresh <name>` narrows
that: a copy that fails the untouched check above, or whose baseline is `unavailable`, reads `kept`. The hook
baseline is the `# <name>-version: N` marker through `forge-adapt-marker-delta.sh`. Refresh never merges a hook
copy and there is no adapt-kept marker for one. Whatever the word, the project runs the hook twice.

- `shadowed` (untouched): the user chooses removal.
- `kept` (edited or unknown baseline): report the double fire, print the two commands below in this order, and
  take no action.

Removal is always two steps in one order. Unwire first, then delete:

```bash
bash "${FORGE_KIT_DIR:?}"/plugins/forge-kit-adapt/skills/adapt/assets/hook-unwire.sh <name>
rm .claude/hooks/<name>.py
```

A wired hook whose file is gone exits 2 on every matching call, which denies it, so deleting first would also
deny the Bash call that tries to repair it. `hook-unwire.sh` applies the name rule above, edits only
`.claude/settings.json`, keeps any other hook in a shared matcher group, and prints `no wiring found for <name>`
when nothing was wired. `retired-paths.sh --remove` also refuses a file that `.claude/settings.json` or
`.claude/settings.local.json` still names, so it cannot do the delete first either.

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
is display only and never a 3-way merge base; the two-way classification is unchanged. The commit id
it prints is also the baseline pointer for the untouched test under "A local copy the live plugin
provides" (#550).
