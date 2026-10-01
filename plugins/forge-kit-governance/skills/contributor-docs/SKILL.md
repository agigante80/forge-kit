---
name: contributor-docs
description: Keep a repository's contributor entry points (AGENTS.md, CONTRIBUTING.md, the PR template) true for everyone who clones it, whatever agent or person reads them. Write AGENTS.md as a map to tracked docs, align CONTRIBUTING and the PR template with it, and run a portable check that fails when a named npm or pnpm script, make or just target, or relative link does not exist in what a clone gets. Use when a project gains a second contributor or a second AI agent, when setting up or auditing AGENTS.md or CONTRIBUTING.md, or when a contributor doc names a command that fails.
---

<!-- contributor-docs-version: 11 -->

# Contributor docs

A project with several contributors, each working through a different agent or none, has three
entry points: `AGENTS.md` for an agent, `CONTRIBUTING.md` for a person, and the PR template for
both. Each names commands and links other docs, and each rots without anyone noticing, because
the author's machine keeps working. The case this skill was built from is
agigante80/actual-mcp-server#496: `CONTRIBUTING.md` named three `npm run` scripts that did not
exist, and `AGENTS.md` was gitignored, so it existed on the maintainer's disk and nowhere else.

**The rule underneath everything here: a contributor doc is judged by what a CLONE gets.** A file
that is ignored, untracked, or only on one machine does not exist for the reader it was written for.

## Writing AGENTS.md: a map, not a copy

`AGENTS.md` is the open, agent-agnostic instruction file ([agents.md](https://agents.md)); Codex,
Cursor, Gemini CLI and others read it, and Claude Code reads it through an import (below). Write it
as a MAP to tracked docs, never as a second copy of them. A copy drifts from the original, and
the original is the one the humans maintain.

Keep only what an agent would otherwise get wrong:

- **Setup and validation commands**, exactly as they run from the root: the install, the build,
  the one command that must pass before a commit. Each must exist; the check below proves it.
- **The rules whose omission breaks things**: generated files not to edit, the branch work goes
  to, how a change is integrated (PR, merge, squash), anything CI rejects.
- **Where tests go** and how to run one test rather than the suite.
- **A precedence order** when two docs disagree, so the agent does not pick one.
- **A documentation map**: one line per tracked doc saying when to read it.

Leave out what the code already says, style an auto-formatter enforces, and anything true only on
the maintainer's machine. Keep it short: the check's default budget is 150 lines and 32 KiB, since
Codex truncates the file at 32 KiB, and a file that long is a copy rather than a map.

## Aligning the other two entry points

- `CONTRIBUTING.md` (at the root, `.github/` or `docs/`) keeps the human process and links
  `AGENTS.md` for the commands, rather than restating them.
- **The PR template needs ABSOLUTE links.** GitHub copies it verbatim into the PR body, where a
  relative link resolves against the PR URL and breaks. Link
  `https://github.com/<owner>/<repo>/blob/<branch>/AGENTS.md`, not `../AGENTS.md`.
- **One source for Claude Code.** A local `CLAUDE.md` that restates `AGENTS.md` forks the shared
  facts. Put `@AGENTS.md` on its own line in `CLAUDE.md` so Claude Code imports it, and keep only
  Claude-specific additions beside the import.

## Before the first commit of AGENTS.md

A doc written from a local instruction file carries local things: home paths, private project
names, an email address. Run the `leak-guard` skill's scanners on it before it is committed,
because a public history cannot be recalled.

## The check

`assets/check-contributor-docs.sh` needs git, plus `jq` only when a command reaches resolution
against `package.json`. It runs under bash 3.2 and any POSIX awk, and prints one TSV row per
finding: `status<TAB>check<TAB>location<TAB>detail`, status `pass`, `fail` or `referred`.

```bash
bash check-contributor-docs.sh                        # the default doc set
bash check-contributor-docs.sh --docs AGENTS.md docs/HACKING.md --max-lines 200
```

Exit 0 when no row fails, 1 when one does, 2 when it could not run, with nothing on stdout. The
default set is `AGENTS.md`, `CONTRIBUTING.md` at its three locations, and every PR template GitHub
reads (`.md`, `.txt` or extensionless, plus files inside a `PULL_REQUEST_TEMPLATE/` directory),
each scanned only if tracked. `--docs` replaces the set; `AGENTS.md` is required regardless.

What it checks, all resolved against the git INDEX, never the disk:

- **required**: `AGENTS.md` is tracked and no ignore rule matches it. A tracked symlink is judged
  by its target, so `AGENTS.md -> CLAUDE.md` fails when `CLAUDE.md` is local only.
- **max-lines**, **max-bytes**: the budget above.
- **command**: inside code spans and fenced blocks only, since prose naming a command is not an
  instruction. Only these shapes can FAIL: `npm run X` and `pnpm run X` from the root (`run-script`
  is an alias, judged the same way), with a literal
  name missing from the tracked `package.json`, and the npm and pnpm workspace forms
  (`npm -w`, `--workspace` and `--workspace=` with `run X` or `run-script X`; `pnpm --filter`, `-F`
  and `--filter=` with `run X` or `run-script X`), which resolve against the one tracked manifest whose `name` equals the given name
  and fail when it lacks X. Yarn never fails, because yarn runs a `node_modules/.bin` binary when no
  script matches. Make and just targets fail when the file plainly lacks them, and are read as text,
  never by invoking `make`, which can run recipes while remaking its makefiles.
- **script-path**: `node`, `sh` or `bash` naming a tracked script passes; an untracked one is
  referred, since `node dist/index.js` is correct after a build.
- **link**: a relative link or reference definition resolves to a tracked file, or a directory
  holding one. `/x` means the repository root, as GitHub renders it. A link leaving the
  repository fails and is never read.

**`referred` means "a person must look", and it never fails the run.** Everything the check cannot
settle is referred rather than guessed. Under yarn, `yarn X` and `yarn run X` with X defined in the
tracked root `package.json` pass; an undefined X is referred, since it may be a binary, and so is a
Yarn Classic built-in name (`yarn check`) even when the root defines it, because yarn 1 runs the
built-in. `yarn workspace <name> [run] X` passes when the one manifest of that name defines X and
is otherwise referred. A workspace name matching no tracked manifest or several is referred, and so
is a filter that is a glob, a selector, a path or quoted. A bare `pnpm X` (a script, a built-in or
a binary), prefix flags, a flag after the script name, a placeholder like `npm run <script>`, a
Makefile using `include` and every relative link in a PR template are referred too. **A directory change makes the
next command referred even when the root defines it**, because what then runs is not the root's
script. Its scope is the fenced block, or for a code span the paragraph, so "Run `cd client`, then
`npm run dev`." is referred and a `cd` in an earlier block reaches nothing. An assignment in front of the
runner refers its own row the same way, since `npm_config_workspace=client npm run dev` runs a
workspace's script, and so does an assignment whose value holds one or more non-nested `$(...)`
substitutions, with or without literal text around them (`pre$(a)`, `$(a)$(b)`; #296, #346). An
`export`, `declare -x` or `typeset -x` of an `npm_config_` variable (any case, any key, an empty
value too, since referring is the safe side) refers every later runner of the same fenced block or
code-span paragraph, and a later segment of its own line, never an earlier one. Also carried:
`declare` or `typeset` with any dash word holding an `x` (`-gx`, or `-g -x`), a quoted argument
(`export "npm_config_x=y"`), and a bare name (`npm_config_x=y; export npm_config_x`). Only a later
`npm`, `pnpm` or `yarn` runner is rescoped, since only those read the variable: a failing `make`
target or `just` recipe stays a `fail`. `export FOO=1`, `export NODE_ENV=production` and
`declare -g npm_config_x=y` (no `x`) rescope nothing and still fail. Only the listed spellings
carry: an `npm_config_` word after a word starting with `#` (a comment) or inside a quoted value
carries nothing, and under `export` a dash word holding an `n` anywhere on the line (`export -n`
un-exports) voids the whole line; for `declare`, `-n` means nameref and still carries, and a leading
`+x` un-exports. Quotes are parsed (two kinds, backslash escapes), so a `#` or `-n` inside quotes is
text. Still a false `fail`: `$VAR` or
`${...}` before a substitution (`npm_config_workspace=$HOME$(echo c) npm run dev`), and
`export "npm_config_x"=y`, whose quote closes before the `=`.
A tracked root `.npmrc` refers every `npm run X`, whether or not the root defines X, because npm then
runs the workspace's script (#339). That happens when it sets `workspace` (any value; `workspace[]=`,
`workspace = x` and a quoted key included) or sets `workspaces` to anything but false. npm takes the
last value of a repeated key, so the last `workspaces` value decides. The detail names only the key,
never the file's text. Only npm: `pnpm run` and the yarn forms are judged as before.

The explicit `-w` and `--workspace` forms are referred only when the last `workspaces` value is false,
because npm then stops with an error ("Can not use --no-workspaces and --workspace at the same time").
False means `false` or a numeric zero (`0`, `00`, `-0`, `+0`, `0.0`, `.0`, `"0"`), which npm reads the
same way; an inline `;` or `#` comment after the value is cut first. That refusal and the last-value
rule are verified on npm 10.9.7 only.

The file is read from the index as data and parsed as npm's ini does: `;` and `#` lines are skipped, the
scan stops at a `[section]` header, the key is case-sensitive and a trailing CR is ignored. A quote pair
around a key or a value is stripped. A symlinked `.npmrc` is referred without being read, so one holding
`workspaces=false` with an explicit `-w` or `--workspace` form still passes.

The limits, stated so they are not mistaken for coverage: spans and links are found within one
line; indented code blocks are prose; the paragraph rule is order-dependent, and list items with
no blank line between them form one paragraph; make's built-in implicit rules are not modelled; a
percent-encoded non-ASCII target is referred. An export in a prose code span does not carry into a
following fence. An assignment value holding a space (quoted, backslash-escaped or in backticks) is
read as one value and refers the row; a value with an UNBALANCED quote is not, and gives no row. Not modelled, so a false `fail`
stays possible: nested-paren substitution values, `pnpm_config_*`, `JUST_JUSTFILE` and `JUST_WORKING_DIRECTORY`, `unset`,
`set -a`, `env VAR=... cmd`, the user and global `.npmrc`, `NPM_CONFIG_USERCONFIG` and a non-root
`.npmrc` (npm never reads it for a run from the root). Where npm would run the root or stop with an error, a tracked `.npmrc` still refers
(safe side): `workspaces=null`, `workspace []=x` and `workspace` with no root `workspaces` field.
Not modelled, so an explicit form passes where npm refuses: `workspaces=0x0`, `0e0` and a value with
whitespace inside quotes (`" false"`). The array form `workspaces[]=false` is unmodelled too, and
other npm versions are not specified. Workspaces are matched by `name` among tracked
manifests, not against `package.json#workspaces` or `pnpm-workspace.yaml`, so a same-named manifest
outside the workspace folders (a fixture or example package) can produce a false `fail` when it lacks
the script, or a false `pass` when it defines one the real package lacks; two such manifests are
ambiguous and referred, and yarn never fails. `npm run build -w web` (the flag after the script) and
`pnpm --filter web build` without `run` stay referred. It checks that what is named EXISTS, never that the
prose is right.

## In the project's CI

The check belongs where contributors' PRs run, not in a hook. Copy the asset into the project
(`scripts/check-contributor-docs.sh`) and add one step:

```yaml
- run: bash scripts/check-contributor-docs.sh
```

Fetch depth does not matter, since it reads the index of the checkout. Install `jq` on a runner
that lacks it, or the first npm command it resolves stops the run with exit 2.

## Boundary with coding-standards-auditor

`coding-standards-auditor` owns WHAT the standards are and writes them to
`docs/coding-standards.md`. This skill owns whether the entry points are TRUE and point there.
`AGENTS.md` links `docs/coding-standards.md` rather than restating it, which is the map rule again.
