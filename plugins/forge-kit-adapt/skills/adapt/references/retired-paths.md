# Retired files: finding a file the kit stopped shipping (#521)

A version marker says a component is behind. It cannot find a file the kit stopped shipping: nothing
names it any more, so drift never lists it. The motivating case is the template-lockstep guard's
contract test. Before #506 forge-adapt copied it into every project and wired it into CI; it is
kit-only now, and the installed copy is orphaned, never refreshed, and still run by a workflow step
the project owns. `assets/retired-paths.sh` finds it; this page says when forge-adapt runs it and what
it does with the rows.

It is a separate asset from `stale-rules.sh` on purpose. That scanner is read only and matches
phrasings in prose; this one has a write mode (one file plus one workflow line) and a different data
shape (a path, not a regex), and folding both into one row kind would put a delete behind a scanner
whose contract is that it never writes.

## Running it

```bash
"${FORGE_KIT_DIR:?}"/plugins/forge-kit-adapt/skills/adapt/assets/retired-paths.sh --project "$PWD"
```

Read only. The listed files are rows of `assets/retired-paths.tsv` beside it (path, issue that retired
it, date, note); `--rules <tsv>` reads another file. Exit 0 found nothing, 1 found a retired file, 3
found none but something was not scanned (treat 3 as incomplete, never clean), 2 is a usage or data
error. A kit checkout (it holds `plugins/forge-kit-adapt/.claude-plugin/plugin.json`) is exempt: there
the path is a live file, so the scan prints `exempt` and the removal refuses.

Rows on stdout, tab separated:

- `retired <path> <caller> <line> <form>`: one per workflow line naming the path. The caller is the
  workflow file in `.github/workflows`, `.forgejo/workflows` or `.gitea/workflows`. `form` is `step`
  only for an exact one-line `- run: bash|sh [./]<path>` that has a sibling step, else `other`
  (a multi-line step, `./<path>` run directly, a chained or quoted command). With no workflow line the
  caller, line and form are `-`.
- `caller-unscanned <path> <file> <line>`: one per non-comment line of a non-workflow caller file that
  names the path, after that path's `retired` rows (#540). The files are `package.json`, `Makefile`,
  `makefile`, `GNUmakefile`, `justfile`, `Justfile`, `.justfile` and every regular file directly inside
  `.githooks/` and `.husky/` (not `_`). The match is the BASENAME at a token boundary, so
  `cd scripts && ./x.sh` counts; a line whose first non-blank character is `#` does not. The scan exit
  stays 1 and the summary columns are unchanged.
- `not-scanned <path> <symlink|unreadable>`: a symlink (never followed: the project may be untrusted)
  or a workflow location or caller file it could not read, once per file.
- `summary <retired> <not-scanned>`, always last.

## Where the rows go

- **`drift` and plain `refresh`** (write nothing): after the marker table, print a `Retired files`
  table (path, caller, line, form, note), then every `not-scanned` row.
- **`refresh <name>`** ignores retired rows: a retired file belongs to no component.
- **The main flow's Version status block**: when the scan has rows, add one line under the table,
  `<N> installed files are retired: reply "retired" to review them.` On that reply, walk the paths one
  at a time: show each row, say what removal does, and run `retired-paths.sh --project "$PWD" --remove
  <path>` only on `yes` for that path. A `no` keeps everything byte for byte. This is the "confirmed
  retired-file removal" SKILL.md's write rule allows, and the only write it allows here.

## Removal

`--remove <path>` rescans, then either does all of it or none of it:

- every caller row is `step`: that one line is deleted from each workflow file, then the script;
- caller `-` and no `caller-unscanned` row: the script alone goes (say so, because a caller outside the
  scanned files may still run it);
- any `other` row, any `caller-unscanned` row, a symlink, or an unreadable workflow or caller file:
  nothing changes (a workflow step that would have gone stays too) and the script stays, so nothing runs
  a missing file. One line per blocker, exactly:
  `not removed: <file>:<line> is not a one-line run step; delete it by hand, then remove <path>` or
  `not removed: <file>:<line> names <path> outside a workflow; delete it by hand, then remove <path>`.

A workflow file is never deleted and never re-serialised: removal drops one recognised line, so
comments and formatting survive. The real pre-#506 `template-lockstep.yml` had two steps, the live
guard and the retired test; removal drops only the second.

## What it cannot find

It reads workflow files and the caller files listed under "Rows on stdout". A pre-commit config,
lefthook, a Taskfile, a `core.hooksPath` directory other than `.githooks` and `.husky`, another CI
system and a wrapper script that runs the file are not scanned, so caller `-` with no
`caller-unscanned` row means "none of the scanned files names it", never "nothing runs it". When the
user asks whether a project is clean, say "no listed path found", not "clean". A longer file name
(`<path>.bak`, `my-<name>`) is not a match.
