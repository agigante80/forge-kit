# Stale rules: finding a retired rule where markers cannot see it (#495)

A version marker says a component is behind. It cannot find a rule that outlived its source: one
restated in a project's own words, in prose or memory written from a component, or in a copy
outside the project's `.claude/`. `assets/stale-rules.sh` reads those places; this page says when
forge-adapt runs it and what it does with the rows.

## Running it

```bash
"${FORGE_KIT_DIR:?}"/plugins/forge-kit-adapt/skills/adapt/assets/stale-rules.sh \
  --kit "$FORGE_KIT_DIR" --project "$PWD"
```

It is read only. The phrasings it looks for are rows of `assets/retired-rules.tsv` beside it (id,
version, date retired, regex, replacement); a rule id comment `<!-- rule: <id> v<M> -->` whose M is
below the kit's current version is a hit whatever the wording. Exit 0 is clean, 1 has hits, 3 has
no hits but something was not scanned, 2 is a usage error. Treat 3 as incomplete, never as clean.

Rows on stdout, tab separated:

- `stale-rule <place> <path> <line> <id>`: `place` is `component`, `prose` or `memory`. Matches
  of one id in one paragraph merge into one row at the earliest start line; distinct ids and
  separate paragraphs never merge.
- `not-scanned <path> <reason>`: a symlink, an unreadable file, or an auto memory slug too long
  to derive. Print each one; the user must know where nothing was read.
- `summary <files> <stale> <not-scanned>`, always last.

The matched text is never printed: memory can hold names. Read the line yourself when you need it,
and never quote a retired phrasing back into any file.

## Where the rows go

- **`drift` and plain `refresh`** (report only, write nothing): after the marker table, print a
  `Stale rules` table, one row per `stale-rule` row (place, path, line, rule id) with the
  replacement summary from the data file's last column, then every `not-scanned` row. Nothing is
  written, exactly as for the marker table.
- **`refresh <name>`**: a stale-rule row inside that component is classified **behind forge-kit**,
  never adaptation, even when the wording is the project's own. The merge replaces the paragraph
  with the component's current text for that rule.
- **The main flow's Version status block**: when the scan has rows, add one line under the table,
  `<N> places still carry a retired rule: reply "stale rules" to review them.` On that reply, walk
  the prose and memory rows one file at a time: show the line, propose the replacement (for a
  memory note, a rewording or its deletion), and write only on `yes` for that file; a `no` keeps
  the file byte for byte. This is the "confirmed stale-rule fix" SKILL.md's write rule allows, and
  the only write it allows here. A component row in the project's `.claude/` goes through
  `refresh <name>` instead; `refresh` never reads the config dir, so a component row there takes
  this per-file fix like prose. Never edit a file outside the project unless the user confirms
  that file by name.

## What it cannot find

A paraphrase that matches no data-file row and carries no rule id is not found, and nothing here
may claim otherwise. When the user asks whether a project is clean, say "no listed phrasing and no
older rule id", not "clean". A line that deliberately quotes a retired phrasing (a changelog, a
history note) carries the word `retired-rule-quote` and is skipped.
