# Changelog

Umbrella versions for the forge-kit marketplace as a whole. Individual plugin groups carry their
own semver in `plugins/<group>/.claude-plugin/plugin.json` and move independently; see
[docs/guides/versioning.md](docs/guides/versioning.md) for what each version level means.

Note that a release tag does not gate distribution. `/plugin marketplace add agigante80/forge-kit`
tracks the repository, so users are already served from the default branch.

## Unreleased

### Added

- **`check-contributor-docs.sh` reports per-harness instruction copies that neither link, import nor symlink `AGENTS.md`, and SKILL.md says how to keep them one source** (`check-contributor-docs-version` 22 to 23, `contributor-docs-version` 16 to 17, `forge-kit-governance` 0.29.2 to 0.30.0; #300; `scripts/test-check-contributor-docs.sh` goes from 736 to 793 passed, 0 failed). A project that ships `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/<name>.mdc`, `.cursorrules`, `.junie/guidelines.md`, `.windsurfrules` or a `.clinerules` file as a SEPARATE copy has a second source of its rules that drifts silently. A new `harness-copy` check, which never fails, runs whenever `AGENTS.md` is tracked (`--docs` or not): a tracked harness file passes only when it reaches the root `AGENTS.md` by a mechanism that harness documents (vendor docs, 2026-10-01): a symlink for every harness; an own-line `@path` import for `CLAUDE.md`, `GEMINI.md` and `.cursor/rules/*.mdc`; a Markdown link for Copilot, which reads `@` as text. Everything else is `referred` with a distinct reason (a symlink to a different file, a target leaving the repository, an absolute target or import, an import or link not documented for this harness, or a separate copy, which for `CLAUDE.md` adds that Claude Code then reads only `CLAUDE.md`). `AGENTS.md -> CLAUDE.md` passes `CLAUDE.md`. Mode, symlink target and content all come from the index, so an uncommitted import does not count, and fences and spans are skipped through the same `EXTRACT` pass, whose import record now marks the own-line form. SKILL.md gains a "Per-harness copies" section with the mechanism table and the Windows symlink caveat (a committed symlink is a text file on a clone without `core.symlinks`), corrects how Claude Code reads `AGENTS.md` (natively when there is no `CLAUDE.md`, through an import otherwise), and stays at 2487 words by tightening the #309 and #301 bullets; `docs/guides/without-claude-code.md` says harness copies are referred, never failed. 36 new cases and 21 mutants (the twenty the ticket names, with Copilot's import credit split out).

- **`check-contributor-docs.sh` follows a tracked `CLAUDE.md`'s `@`-imports and fails an import a clone does not have** (`check-contributor-docs-version` 19 to 20, `contributor-docs-version` 14 to 15, `forge-kit-governance` 0.28.32 to 0.29.0; #301; `scripts/test-check-contributor-docs.sh` goes from 654 to 721 passed, 0 failed). SKILL.md tells users to put `@AGENTS.md` in `CLAUDE.md`, and Claude Code loads every file an `@path` names, but the check never read `CLAUDE.md`, so an import of a file only on the maintainer's disk was the #294 failure one hop out. A new `import` check runs when the root `CLAUDE.md` is tracked and `--docs` is not given: each `@path` token outside spans and fences (a word starting with `@` whose path holds a `/` or a `.`) passes when it names a tracked, unignored file from the importing file's directory, and fails when it is untracked, absent, ignored or escaping; `@~/` and `@/` are referred and never opened. A symlink import goes through #309's `safe_resolve`, so there is one definition of a safe link. A markdown import is scanned like any doc (commands, links, its own imports), breadth-first with a visited set keyed on the resolved path, to `MAX_IMPORT_HOPS` (4); past it an import is referred. `CLAUDE.md` itself is read for imports only, and `AGENTS.md`'s own `@` tokens are never followed (a stated limit). Probed on Claude Code 2.1.287 in a scratch project, and two of the ticket's rules changed to match: trailing punctuation is part of the path (`@x.md.`, `@x.md,` and `(@x.md)` load nothing), so such an import fails, with a hint when the path minus the punctuation is tracked; and a relative import inside a symlinked file resolves from the target's directory, which the queue of resolved paths gives. A quoted path is not an import, an escaped space stays in the token, and spans and fences are skipped, as the ticket assumed. Since #309 reads tracked docs from the index, a markdown import deleted from the worktree is scanned from its blob rather than exiting 2. 42 new cases and 25 mutants (presence for tracked, span and fence extraction, the token-start anchor, the path-candidate test, the cap removed and off by one, a last-in-first-out queue, the visited set, an escaping import queued, the escaped space, a non-markdown import scanned, a link judged as itself, the chain test, a directory target, the visited key, an absolute target, a home path failed, `AGENTS.md` parsed, an import never queued, root-relative resolution, the default-set dedupe, the ignore test, punctuation stripped, an untracked `CLAUDE.md` followed).

### Fixed

- **`check-contributor-docs.sh` reads nothing inside a block HTML comment** (`check-contributor-docs-version` 23 to 24, `contributor-docs-version` 17 to 18, `forge-kit-governance` 0.30.0 to 0.30.1; #408, found by #297's research; `scripts/test-check-contributor-docs.sh` goes from 793 to 805 passed, 0 failed). Claude Code 2.1.287 strips block HTML comments before it reads `@`-imports, but #301's `import` check followed `<!-- @docs/old.md -->` and failed a commented-out import of a deleted file, and #300's `harness-copy` passed a `CLAUDE.md` whose only `@AGENTS.md` was commented out. `EXTRACT` now removes `<!-- ... -->` (on one line or across lines, an unclosed one running to the end) before fences and spans are read, so no import, link or command is taken from inside a comment, which no reader sees on GitHub either; a fence line inside an open comment opens nothing, a comment inside a fence stays fence text, a `<!--` inside a code span opens nothing, and a token after `-->` is read. Eight cases and four mutants (the skip removed, the whole `-->` line skipped, a fence winning inside a comment, a span's `<!--` opening a comment); the `CR kept on blank lines` anchor moves with the new rule.
- **`check-contributor-docs.sh` pins the three `.npmrc` parse edits its suite missed, and states the npm ini spellings it does not model** (`check-contributor-docs-version` 21 to 22, `contributor-docs-version` 15 to 16, `forge-kit-governance` 0.29.1 to 0.29.2; #398, the #381 review Lows; `scripts/test-check-contributor-docs.sh` goes from 725 to 736 passed, 0 failed). Three single edits to `npmrc_scan`'s awk survived the suite: dropping the key trim before the unquote (`"workspaces" =false`), turning the `else` before the inline-comment cut into an `if` (so the cut ran inside a quoted value), and reading an empty value as false. Each now has a case that kills it: `c_npmrc_quoted_key_explicit` gains the `"workspaces" ` element, `workspaces="false # c"` passes the explicit form (npm 10.9.7 reads a truthy string), and `workspaces= # c` refers a plain run. The npm ini spellings the asset does not model are listed in the header and SKILL.md and each pinned at its current row: `workspace#c=client` (a false `fail`, npm runs the client), `workspaces;x=false` and `workspaces #c=false` (false passes), `0b0`, `0o0` and `0e5` beside `0x0` and `0e0`, `workspaces=undefined` (a plain run refers, an explicit one passes), and the trim inside a quoted key (`"workspace "=client`, `"workspaces "=true`, safe side). `"workspaces"=false` is not a limit (already referred correctly).
- **`check-contributor-docs.sh` strips a byte-order mark under BWK awk in a UTF-8 locale, and CI now runs its suite under that awk** (`check-contributor-docs-version` 20 to 21, `forge-kit-governance` 0.29.0 to 0.29.1; #406, found validating #386; `scripts/test-check-contributor-docs.sh` goes from 721 to 725 passed, 0 failed, under gawk, and under BWK awk in `C.UTF-8`). BWK awk, the awk macOS ships, reads a UTF-8 byte-order mark as one character in a UTF-8 locale, so the octal strip `sub(/^\357\273\277/, "")` never matched there: on a Mac a BOM-led Makefile or justfile lost its first target (a false `fail`) and a BOM-led doc whose line 1 opens a fence had every fence pairing inverted (a broken command passed silently). 15 cases failed under BWK in `C.UTF-8`. The two awk calls that run the strips, `judge_target`'s make and just read and the doc loop's `EXTRACT`, now run under `LC_ALL=C`, as `npmrc_scan` already did, so every awk matches bytes. Not taken: the dynamic-regex string form (works on BWK but leaves the other byte-versus-character differences and moves 14 mutant anchors), a strip in shell (a process per read), and `index()`/`substr()` arithmetic (wrong on BWK in UTF-8). CI installs `original-awk` (it registers no `awk` alternative, so mawk stays the default) and runs the suite a third time with `AWK_UNDER_TEST=original-awk` and `LC_ALL=C.UTF-8`; the job timeout goes from 20 to 25 minutes. Two mutants dropping each locale pin run only under BWK in UTF-8, through a `bwk_gate` that names its probes (`awk --version` printing `awk version <date>`, `locale charmap` printing `UTF-8`) and refuses when `original-awk` was requested but another awk resolves, both paths pinned; the `awk failure swallowed` and `make invoked to find a target` anchors move with the call.
- **`check-contributor-docs.sh` reads every document through one safe helper, so no tracked or untracked symlink can make it read, measure or print a file outside the repository** (`check-contributor-docs-version` 18 to 19, `contributor-docs-version` 13 to 14, `forge-kit-governance` 0.28.31 to 0.28.32; #309, security, which also covers #310; `scripts/test-check-contributor-docs.sh` goes from 607 to 654 passed, 0 failed, under gawk, and under mawk and BWK awk in the C locale). The `required` check followed one `readlink` hop, and the size checks and the doc loop then opened the path through every link whatever `required` decided, so a two-link chain, a one-level escape, a symlinked `CONTRIBUTING.md`, PR template or `--docs` path each printed link text and line and byte counts from an outside file; an absolute target was read as repo-relative (#310: a false `pass` when the path minus its slash was tracked); a `Makefile` linked to `/etc/passwd` was a yes/no oracle on the runner, and one linked to `/dev/zero` hung the job; raw link text and file names could plant a row or a `::warning` line; and a file name holding a newline forged index membership. Now: the index is loaded once from `ls-files -s -z`, each record split at its first TAB, stage 0 only, any path holding a control byte dropped; `safe_open` is the one read site (the size checks, the doc loop for every document and `--docs` path, and the make and just read), reading a tracked file as its index blob and accepting a tracked symlink only when its target, also read from the index, is relative and resolves from the link's own directory to a tracked regular file, so any chain, an absolute, escaping, empty or control-byte target, a directory, a submodule and a dangling, glob or pathspec-magic name each give one `fail` row and nothing is read; an untracked path must be a regular file, not a symlink, whose physical directory (resolved with `CDPATH= cd -- ./...`, then a separator-anchored containment test) is inside the repository. A rejected `AGENTS.md` gets its `required` fail as its only row. `row()` prints every field's control bytes as `?`. A failed make or just read is exit 2, never a `no such target` row. Consequence, intended and now stated: an unstaged edit to a tracked doc is not judged. 33 new cases, each negative asserting by content that an outside token never reaches stdout or stderr, and 14 mutants, each tagged on its guard line (chain, absolute, size, loop, make, the sanitiser twice, the newline-split list, the control-byte drop, a prefix index lookup, the swallowed awk failure, containment without the separator, an IFS read-back and an unguarded dash-led `dirname`); the `make` mutant is re-anchored. SKILL.md's `required` bullet now describes the rule, and its CI section warns that a `pull_request_target` job or a self-hosted runner widens what is in reach.
- **forge-adapt stops on an unset library in every later step instead of reading a bare path, and S2 prints what later steps need** (`forge-adapt-version` 69 to 70, `forge-kit-adapt` 0.8.0 to 0.8.1; #321, found implementing #215; `scripts/test-forge-adapt-host.sh` goes from 34 to 121 passed, 0 failed; the adapt baseline is LOWERED from 7199 to 7154 words). Every Bash call is a fresh shell, so `FORGE_KIT_DIR`, `FORGE_KIT_SRC` and `GOVERNANCE_PLUGIN_ACTIVE`, assigned only in S2, were unset in every later block: the seven helper calls ran `/scripts/<name>` (exit 127), the contributions `comm` listed every installed component as project-only with exit 0, the templates version came back empty with exit 0, the lockstep block ran `mkdir -p scripts` and then misdiagnosed a "stale" library with a `git -C  pull` fix, and the governance flag was never visible to Step 3's hook branch. Every later read is now `${FORGE_KIT_DIR:?}` (the shell stops naming the variable), the contributions and templates blocks open with a guard on the path they actually read (so a set-but-bad value stops too, naming the path), and the lockstep block resolves first, creates `scripts/` only when copying, and fails with one stderr message naming both remedies instead of branching on `FORGE_KIT_SRC`. S2 prints the library path on its success line and a `governance-plugin-active=<yes|no>` line after the assignment; Step 3's hook branch reads that printed line, and one rule after S2's stop rule says every Bash call is a fresh shell and to prefix the printed path. S2 still decides the library itself, discarding an exported `FORGE_KIT_DIR` (unchanged, and now pinned). The host suite extracts each helper block, the two inline spans, the contributions, templates and lockstep blocks and S2 by content pattern and runs them under `env -i` with a valid library, unset, and set-but-bad; S2 fixtures are non-git libraries in a throwaway HOME with no clone allowed; a structural lint fails any later fenced read of the library that is not `${FORGE_KIT_DIR:?}` (per occurrence, with a reverted-guard mutant), and no text after S2 reads `FORGE_KIT_SRC` or `GOVERNANCE_PLUGIN_ACTIVE`. Run against a copy of the unfixed skill the suite fails 30 cases. S2's refresh rationale moved into the suite's header to pay for the words. Out of scope, as the ticket records: the same lost-variable class in `/phase` (`CP`, `SP`) and in ticket-gate Step 1, and `NO_MARKETPLACE`, which nothing assigns.
- **`check-contributor-docs.sh` no longer lets a `NAME=` inside a quoted argument swallow the next runner, and its export and marker passes are linear on every awk** (`check-contributor-docs-version` 17 to 18, `contributor-docs-version` 12 to 13, `forge-kit-governance` 0.28.30 to 0.28.31; review round 1 of #386, #387 and #390; `scripts/test-check-contributor-docs.sh` goes from 598 to 607 passed, 0 failed, under gawk, mawk and busybox awk, and BWK awk in the C locale). **High, a fail-open regression from #386:** the value rewrite marked a word-start `NAME=` even inside a quoted argument and then read that argument's closing quote as the opener of a new quoted run, so `git commit -m "chore: set retries=3" && npm run nope && git push origin "main"` (and the same shape in single quotes, before a closing quote, or in a prose code span) turned `&& npm run nope && ...` into X and exited 0 over a broken command. The balanced quoted runs, backtick runs and escaped bytes are now paired first, left to right as the shell pairs them, and wrapped in marker bytes, and a value may take a run only through its opening marker, so a value can never reach past a closing quote; all three shapes fail again and are pinned. **Medium:** #387's per-character quote loop was quadratic on a hostile export line (BWK awk over 120 s at 200 KB); the export parse is now three linear `gsub`s (a quoted `npm_config_` word keeps its name, every balanced run collapses to one word, an unbalanced quote cuts the rest), which also makes `export "npm_config_x"=y` carry as bash does, removed from the stated limits. And the word-start marker's `(^|[ \t;&|(])` alternation sent gawk in a UTF-8 locale to its quadratic matcher once #386 ran it on every `=` (a 400 KB word took 9 s); a leading space now stands in for the line start (0.3 s). Hostile 300 KB export and assignment words and 12000 quoted arguments are pinned under the watchdog. **Low (#390):** `npm -C`, npm's alias for `--prefix`, now skips its value, with a case and a mutant. The 35 mutants whose anchors moved are retargeted; the export quote-parity, collapsed-run, merged-kinds and escape mutants now target the new parse.
- **`/phase review` gives each run its own snapshot file, so an overlapping run can no longer print a false `held`** (`phase-version` 12 to 13, `forge-kit-roadmap` 0.15.5 to 0.15.6; #394, found reviewing #373; new suite `scripts/test-phase-review-snapshot.sh`, 16 passed, 0 failed, wired into CI). The snapshot was one fixed file, `phase-review.snapshot`, so run B's step 1 overwrote run A's baseline and A's step 7 printed `second-run proof: held` over a path that changed during A's run, and a run that finished first deleted the other's file. Step 1 now creates `phase-review.<id>` with `mktemp` and prints `run id: <id>`; the agent carries `<id>` into steps 4 and 7 as a literal, as it does `ACTS=N` (a shell variable does not survive the tool calls a run spans), and both validate it, so a missing, placeholder, mistyped or path-shaped id (`RUN=../x`) reads the existing `unproven, no snapshot from step 1` and deletes nothing. Step 1 also deletes `phase-review.*` files two or more days old (`find -mtime +1`), which clears aborted runs and the legacy fixed file. Refusing to overwrite a young file was rejected because it keeps the shared name; the reason is in `phase.md`. This supersedes the #373 entry's note that the shared-file behaviour was unchanged. The new suite extracts the three snippets from `phase.md` (failing loudly unless each marker matches exactly one block) and runs them in throwaway repositories: single run held and not held, overlap held and the reported defect, a finished other run, four wrong ids, orphan cleanup, a live run kept, and step 4 reading its own list; four mutants (the shared name restored with the markers kept, step 7's `rm` widened to a glob, `-mtime +1` dropped, step 4 pinned to another name) each fail their case. To fit the 2000-word budget `phase.md` drops the #189 `find` rationale, the "prose cannot be tested" clause, and four other explanatory clauses; it is at 1993 words.
- **`check-public-leaks.sh` refuses a `root` allow entry for the same whitespace bytes in every caller locale** (`check-public-leaks-version` 26 to 27, `forge-kit-security` 0.14.5 to 0.14.6; #400, the twin of #242, its round-2 Low 5; `scripts/test-check-public-leaks.sh` goes from 616 to 634 passed, 0 failed). The `root` arm refused whitespace with the case pattern `*[[:space:]]*`, evaluated in the caller's locale, while RE_ROOT runs under `LC_ALL=C`: so a `root` entry whose name holds U+2003 (EM SPACE) was accepted under `LC_ALL=C` and refused with exit 2 under a UTF-8 locale (the GitHub runner default), although the entry is live (without it the same scan reports that root's `home-root` row). The pattern is now the byte list the `prefix` arm uses since #242, `*[$' \t\n\v\f\r']*`, with a comment saying why. New cases: a tab, VT, FF and CR root each exit 2 and name the rule; a U+2003 root is accepted under `LC_ALL=C` and the first UTF-8 locale and suppresses its live row there; a mutant restoring `[[:space:]]` is refused under UTF-8 and a space-only mutant accepts a tab root, each with its ledger. `check-private-leaks.sh` carries no such refusal: its `[[:space:]]` uses are the allow-file line trims, which share the edge-U+2003 locale dependence tracked separately in #403.
- **`check-contributor-docs.sh` reads an array-form `workspaces[]` line in a tracked `.npmrc` as workspaces on, as npm does** (`check-contributor-docs-version` 16 to 17, `contributor-docs-version` 11 to 12, `forge-kit-governance` 0.28.29 to 0.28.30; #395, the #381 follow-up; `scripts/test-check-contributor-docs.sh` goes from 583 to 598 passed, 0 failed, under gawk and mawk). `npmrc_scan` stripped the `[]` and read `workspaces[]=false` as the scalar `false`, so a plain `npm run dev` the root defines was a false `pass` while npm ran the client's script, one the root does not define was a false `fail`, and `npm -w client run dev` was referred as "sets workspaces=false" although npm runs it. Measured on npm 10.9.4 in a throwaway project (user and global config pointed at absent files), with `npm run dev` versus `npm -w client run dev`: `workspaces[]=false`, `workspaces[]=true`, the two together, a scalar `false` before or after an array line, `workspaces=true` then `workspaces[]=false`, `workspaces[] = false`, `"workspaces[]"=false` and `workspaces[]=0` all run the client on both forms; scalar `workspaces=false` runs the root and refuses `-w`; `workspaces []=false` (a space before the brackets, npm's key `"workspaces "`) runs the root on a plain run and the client on `-w`. Two lines model it: an exact `workspaces[]` key (after the quote strip and trim) sets a flag, and once set every later line keeps the key on, so a plain run refers (`sets workspaces`) and an explicit `-w` run is judged by its manifest. `workspaces []=false` is still read as the scalar, so a plain run fails as npm does and an explicit run stays referred where npm runs the client (safe side). The #381 entry below said `workspaces[]=false` was "pinned as a documented limit, with a case"; the suite had no `workspaces[]` case, so that claim was untrue (the entry itself is left as written). Ten new cases and five mutants (the flag dropped, the explicit-run model dropped, a later scalar false overriding the array, the key tested after the bracket strip or before the quote strip); the header and SKILL.md now describe the modelled behaviour.
- **`check-contributor-docs.sh` ends the flag prefix at the first word that is neither a flag nor a flag's value** (`check-contributor-docs-version` 15 to 16, `forge-kit-governance` 0.28.28 to 0.28.29; #390, a Low of #363's review; `scripts/test-check-contributor-docs.sh` goes from 562 to 583 passed, 0 failed, under gawk and mawk). `judge_pm`'s flag-between loop referred the first `run` or `run-script` ANYWHERE in the arguments, so `npm -g install run-script` and `npm -g install run` were referred as "a flag between npm and run may change which script runs", and `npm --prefix run-script run build` printed the flag's value `run-script` as the doc's verb. The loop now skips the value of exactly seven flags (npm `-w`, `--workspace`, `--prefix`; pnpm `--filter`, `-F`, `-C`, `--dir`), reads every other dash word as a boolean (as npm 10.9.7 and pnpm 10.33.3 do), and stops at the first other word; the row text is byte-for-byte unchanged. Three outcomes move, all fail-open: an install target, a positional after `--` or a `#` word ends the search (no row); an unknown value flag ends it too (`npm --loglevel verbose run x` is silent); `pnpm -g install run` takes the bare-word row, and `npm -w run build` is silent because `run` is the workspace value, so `c_edge_referred` now counts one referred row. New cases cover each outcome and each value flag with a `run-script` value; one mutant per set member, plus "does not stop at a non-flag word" and "never clears the skip", and the "reverted to run only" mutant is re-anchored.
- **`check-contributor-docs.sh` parses quotes on an export line instead of counting them, reads `-n` as un-export only under `export`, and lets a leading `+x` un-export a `declare`** (`check-contributor-docs-version` 14 to 15, `contributor-docs-version` 10 to 11, `forge-kit-governance` 0.28.27 to 0.28.28; #387, the round-2 Lows of #346's review; `scripts/test-check-contributor-docs.sh` goes from 538 to 562 passed, 0 failed, under gawk and mawk, and the shapes were checked under busybox and BWK awk against bash 5.2's own `env`). The export guards counted quote characters of either kind, so `export "a # b" npm_config_workspace=c` and `export "a -n" ...` carried nothing (false fail), and `export A="\" npm_config_workspace=c"` carried (false pass). The quote state is now parsed in the one pass over the words, double and single quotes as separate kinds and a backslash outside single quotes escaping the next byte, and each guard applies only to a word that starts outside any quote. `-n` voids the line only under `export` (for `declare`, `-n` is nameref, so `declare -nx` and `declare -x -n` carry), and a leading option word `+x` un-exports a `declare` or `typeset` in either order with `-x`, as bash does; a `+x` after a name does not. The #386 value rewrite now honours a backslash-escaped quote inside a double-quoted run. `hit`, `unexp` and the quote-state names are `code()` locals. Most of the shapes the ticket listed (`export A="x # y" ...`, `A="it's"`, `A=\"`, and `A="x;y"`) were already fixed by #386's value rewrite and are pinned here. Sixteen new cases; the three guard mutants are re-anchored, and new ones drop the quote state from each guard, apply `-n` to `declare`, merge the quote kinds, drop the escape, drop the `+x` un-export, read `+x` past the option words, and let an escaped quote end a double-quoted run.
- **`check-contributor-docs.sh` reads an assignment value holding a space as one value, and CI runs its suite under gawk and mawk** (`check-contributor-docs-version` 13 to 14, `contributor-docs-version` 9 to 10, `forge-kit-governance` 0.28.26 to 0.28.27; #386, the Lows of #346's review; `scripts/test-check-contributor-docs.sh` goes from 520 to 538 passed, 0 failed, under gawk, mawk, busybox awk, and BWK awk in the C locale). Any assignment value containing a space (`FOO="a b"`, `FOO='a b'`, `FOO=a\ b`, a backtick value, with or without a `$(`) lost its runner at the split and gave no row, so `npm_config_workspace="a b$(echo c)" npm run nope` exited 0 silently; and `FOO="a b" cd x` hid the cd, so a correct `npm run nope` on the next line got a wrong `fail`. `code()` now rewrites every word-start `NAME=` value that is a mix of plain bytes, non-nested `$(...)` groups, double- or single-quoted runs, backtick runs and escaped bytes to `X` in the same single linear pass the `$(` rewrite used, so each refers the row (`an environment assignment precedes it`, or `a directory change precedes it` after the cd), a `;` or `|` inside quotes stays in the value, and only an unbalanced quote remains a stated limit (no row, pinned). The backtick-with-space limit is gone, so `c_subst_backtick_space` flips to a pinned `referred` row; the header and the SKILL.md limits say so. Twelve new cases, including a 24000-word hostile-linearity case; the `$(`-anchored mutants are retargeted, and new mutants drop each quoted-run, backtick-run and escaped-byte alternative, restore the `$(`-only trigger, and add a restart-from-front loop. The export quote-parity guard's mutant moves to a new unbalanced-quote case, since a balanced quoted value is now rewritten before the guard runs. CI prints which awk the runner resolves before and after installing gawk (whose install repoints Ubuntu's `awk` alternative, set back to mawk so no other step changes), and runs the suite twice, `AWK_UNDER_TEST=gawk` and `=mawk`, so the strip-loop mutant that needs gawk finally runs in CI; a run that asks for gawk and gets another awk now fails that mutant instead of printing a skip, pinned with mawk posing as the requested awk. The job timeout goes from 15 to 20 minutes for the second run.
- **Both leak scanners report a committed finding under any `TMPDIR`: their temp paths reach awk through `ENVIRON`, never `-v`** (`check-public-leaks-version` 25 to 26, `check-private-leaks-version` 16 to 17, `forge-kit-security` 0.14.4 to 0.14.5; #259, part 4 of 4, which closes the audit; `scripts/test-check-public-leaks.sh` goes from 602 to 610 and `scripts/test-check-private-leaks.sh` from 218 to 226 passed, 0 failed). The `types`, `labels` and (private) `names` files live under `mktemp -d`, so their paths carry the caller's `TMPDIR`. Under a `TMPDIR` named `t\tx` (backslash, t) `awk -v` read them back with a TAB, every `getline` failed, and `--history` exited 0 with no output over a committed home path or listed name: a silent false negative. All five sites in the private scanner and three in the public one now pass `LG_*` environment values, the 0-or-1 `orphans` and `show` flags included as hardening. Each header records its sites, and each suite counts zero `awk ... -v` code lines with a mutant, plus a `--history` fixture under a `tA` and a `t\tx` `TMPDIR` that finds the leak in both (the unmoved scanners exit 0 under the second) and a clean-history negative. With this, every in-scope asset in #259 carries no `awk -v`; `roadmap-lib.sh` (the worked example) and `forge-gate-mechanics.sh` (fixed outcome words only) are excluded as the ticket records.
- **`check-ticket-mechanics.sh` passes every value to awk through `ENVIRON`, never `-v`** (`check-ticket-mechanics-version` 15 to 16, `forge-kit-governance` 0.28.25 to 0.28.26; #259, part 3 of 4; `scripts/test-check-ticket-mechanics.sh` goes from 274 to 279 passed, 0 failed). A template field label is caller text, and under `-v` a label `Steps\tx` was looked up as `Steps<TAB>x`, so its filled section read as empty and check 3 failed it. All ten flags on eight lines now travel as `CTM_*` environment values: `want` and `l` (labels, the live defect), and `p`, `any`, `neg` and `pos` (literal patterns and `marker_re` output) as hardening, which also removes the trap where a future `\.` in one of those regexes would silently become `.`. The header classifies each site and the `marker_re` comment no longer says the string travels through `-v`. The suite counts zero `awk ... -v` code lines with a mutant that adds one, and pins the backslash label both filled (pass) and empty (fail, named as typed).
- **`sync-labels.sh` passes its field separator to awk through `ENVIRON`, never `-v`** (`sync-labels-version` 10 to 11, `forge-kit-devops` 0.20.2 to 0.20.3; #259, part 2 of 4; `scripts/test-sync-labels.sh` goes from 92 to 94 passed, 0 failed). The one site carried the compiled-in `$'\x1f'`, which has no backslash, so the move is hardening only and recorded as not reproducible; the header says so, and the suite counts zero `awk ... -v` code lines with a mutant that adds one.
- **The three roadmap scripts pass caller text to awk through `ENVIRON`, never `-v`** (`check-phases-version` 6 to 7, `sync-phases-version` 7 to 8, `reassess-phases-version` 3 to 4, `forge-kit-roadmap` 0.15.4 to 0.15.5; #259, part 1 of 4; `scripts/test-check-phases.sh` goes from 79 to 86, `scripts/test-sync-phases.sh` from 85 to 92 and `scripts/test-reassess-phases.sh` from 164 to 173 passed, 0 failed). `awk -v` runs a backslash-escape pass over its value, the defect #246 fixed in `roadmap-lib.sh`. A `--roadmap` path named `r\tmap.md` was printed in the MALFORMED diagnostic with a real TAB by all three scripts, and `reassess-phases.sh` refused an existing phase named `a\tb` as unknown (exit 5) because `phase_exists`, `phase_state` and `next_phase_name` compared against the mangled name. All seven sites now use a command-prefix assignment read back through `ENVIRON`, the `_read_prose` line bounds included as hardening. Each header records its sites, and each suite counts zero `awk ... -v` code lines (a pattern that also sees `awk -F'\t' -v`, which a fixed-string check misses) with a mutant that adds one, plus the backslash fixtures that fail against the unmoved scripts.
- **`check-ticket-mechanics.sh` anchors the gate-filled mark to the template's structure and skips a body region instead of ending the section at it** (`check-ticket-mechanics-version` 13 to 14, `forge-kit-governance` 0.28.23 to 0.28.24, #304 review round 1; `scripts/test-check-ticket-mechanics.sh` goes from 251 to 258 passed, 0 failed). Three Mediums in the first #304 change. A `# gate-owned` comment was matched at any indent and held until the next `- type:`, so one written above a field (the usual YAML habit) exempted the field before it, and one inside a `placeholder: |` block exempted that author field; it now counts only at the field's key indent (four spaces). And ending a section at a region start marker hid any author text below the region, so an N/A claim or a malformed scenario block after one could move a row to pass, contrary to the header; `section_of()` now skips a region's lines up to its matching end marker and resumes reading, an unterminated region running to the end of the body, and the header says region text is excluded as if absent. New cases cover block-scalar text and a comment above the next field, an N/A and a malformed block below a region, and two mutants that drop the description-line anchor and widen the comment indent.
- **The ticket gate writes scenario labels in a shape its own check 4 reads** (`ticket-gate-version` 65 to 66, `forge-kit-governance` 0.28.22 to 0.28.23, #273; `scripts/test-check-ticket-mechanics.sh` goes from 240 to 251 passed, 0 failed). In #267 round 1 the gate wrote `Negative *(gate-written, round 1 critic)*` and `Positive, changed body *(gate-written, round 1 critic)*`, which `marker_re` does not read as markers, so round 2 failed `gwt` on a ticket the gate had edited itself. Option 1 was chosen: constrain the writer and leave `marker_re` and `check-ticket-mechanics.sh` untouched, because widening it would reopen the #205 near misses. Step 6 item 2 now gives the shape inline, `**Negative:** <title> (gate-written, round N)` or `**Positive:**`, and the Step 0c-iii `scenarios` row says label lines are `**Positive:** <title>` or `**Negative:** <title>`, keeping its "Apply the rule-1 quality bar" anchor. The 13 added words are paid for by trims in the critic's concern list, its best-practices item and the class re-ask sentence, so `ticket-gate.md` plus its preloaded skill stay at the 5754-word ratchet. The suite pins the two accepted shapes, the four rejected ones (the #267 literal strings, a comma inside the bold, a colon inside the bold followed by text) with their exact rows, and a drift case that extracts the documented example from Step 6 item 2 and runs it through the real checker, failing loudly if the example is missing.
- **`check-ticket-mechanics.sh` no longer charges the author for an absent gate-filled heading, and a body region is never read as author text** (`check-ticket-mechanics-version` 12 to 13, `forge-kit-governance` 0.28.21 to 0.28.22, #304; `scripts/test-check-ticket-mechanics.sh` goes from 218 to 240 passed and `scripts/test-forge-gate-mechanics.sh` from 34 to 37, 0 failed). A hand-filed body with every heading but `### Codebase Context` got `sections fail heading absent (1): Codebase Context`, a field every work template describes as "Auto-populated by ticket-gate. Do not edit manually."; operators had added the heading by hand on #294, #295, #299 and #300. `template_fields()` now emits a fourth column marking a field gate-filled, read from the TEMPLATE only (a `description:` line carrying the fixed, case-sensitive substring "Auto-populated by ticket-gate", or a whole-line `# gate-owned` YAML comment in the field block), and check 3 skips the absent-heading charge for such a field unless it is `required: true`, naming it in the pass evidence (`; gate-filled, not charged: Codebase Context`). Body text cannot trigger it and a template that loses the mark gets the old charge. Separately, `section_of()` now ends a section at any whole-line region start marker (forge-lib's `<!-- <name>:start -->` grammar, trailing CR or blank tolerated), because the gate's appended `gate-context` region read as content of the author's last `##` section and its paths passed a vague `## Documentation impact`; `brief-*` and `phase-*` regions are covered by the same rule. The #205 gap 1 assertion is re-anchored on `Documentation impact`, the last charged feature.yml label, and two named mutants (the gate-filled clause, the region boundary) each flip their case. `ticket-gate.md` is untouched.
- **`.githooks/pre-push` changes to the work-tree root, failing closed, so a hand run from a subdirectory scans the whole tree** (`.githooks/pre-push` and `scripts/test-pre-push-hook.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 158 to 176 passed, 0 failed; the #388 subdirectory case and its `full-tree-dropped` mutant are replaced, because the `cd` makes that mutant equivalent). `git rev-parse --show-toplevel` was never followed by a `cd`, so from `sub/` both `--head` scans listed only that subdirectory and the hook exited 0 over a committed root leak. The line `[ -n "$ROOT" ] && cd -- "$ROOT" || { ...could not RUN...; exit 1; }` now sits straight after `ROOT` is set and fixes every directory-relative step: the allow-file probe, both scans, the roadmap guard (`check-phases.sh` reads `docs/roadmap.md` from the working directory, so from `sub/` it said "nothing to check" over a plan lacking `Fails if`) and the suite-count pathspec at the `git diff --name-only ... -- 'scripts/test-*'` line. A stale-count case run from `sub/` pins that last step. It fails closed because from `.git` `ROOT` is empty and a bare `cd ""` returns 0 without moving. The `--full-tree` probe flag stays as defence in depth with no test of its own. New cases cover a root leak from `sub/`, the roadmap guard from `sub/`, the suite-count path from `sub/` and the `.git` run, with mutants `cd-dropped`, `cd-unguarded`, `cd-undone-before-roadmap` and `cd-undone-before-counts`, each killed. A hand-exported `GIT_DIR` from a subdirectory still skips both scanners (pre-existing, tracked in #401) (#396).

### Changed

- **The contributor-docs suite runs its restart-from-front rewrite mutants only under GNU Awk** (`scripts/test-check-contributor-docs.sh` only, repo-only, no component or plugin change, so no marker or semver bump; the suite stays at 607 passed, 0 failed). Since #386 CI runs the suite under both gawk and mawk, and on a fast runner mawk finished the quadratic "restart-from-start rewrite loop" mutant inside the 6 s watchdog, so the mutant survived and `develop` went red from the #402 push on (measured here: mawk 8.3 s, gawk 94 s). Like the strip-loop mutant, the three restart mutants now run where the awk under test is GNU Awk, which CI's `AWK_UNDER_TEST=gawk` run guarantees, and print a skip elsewhere.
- **`bounded()` escalates to SIGKILL after a 3 s grace, and a watcher-gone row pins the early-return cleanup** (`scripts/test-check-public-leaks.sh` and `scripts/test-forge-lib.sh`, repo-only, no component or plugin change, so no marker or semver bump; #402, the #315 review Lows; `scripts/test-check-public-leaks.sh` goes from 610 to 616 and `scripts/test-forge-lib.sh` from 424 to 430 passed, 0 failed). A command that ignores or takes over SIGALRM ran past the bound and hung the suite with no tally (`bounded 1 bash -c 'trap "" ALRM; sleep 35'` returned 0 after 35 s); the watcher now sends SIGKILL to the command's group 3 s after the ALRM, so such a survivor reads 137 (only 142 maps to 124, so the escalation cannot pass as the bound) and is stopped in about 4 s, while `bounded 1 sleep 30` still reads 124 in about 1 s. Once the command exits, `kill -- -"$w"` takes the watcher's group, its grace sleep included, so the KILL never reaches a recycled group. A new row asserts no watcher survives an early return (`bounded 47 true`, then no `sleep 47` process; 53 in the forge-lib suite so two suites running at once cannot see each other's), and three mutants built from `declare -f bounded` (the escalation removed, the watcher kill removed, the watcher spawned after `set +m`) each fail a row; the stdio-detach-only mutant is recorded as equivalent, and the prompt-capture row is described as pinning only the both-safeguards-removed form. The comment names the residuals (KILL skips the command's EXIT trap, a child moved to another group escapes). The third, TERM-based `bounded()` in `scripts/test-check-contributor-docs.sh` is deliberately untouched (#261).
- **`test-forge-lib.sh` pins the dry-run scan's ORPHAN branch and column-0 `}` reset, and `dr_mutant` resets at that `}` too** (`scripts/test-forge-lib.sh` and `CHANGELOG.md`, repo-only, no component or plugin change, so no marker or semver bump; #399, the two Lows of #380's review; the suite goes from 419 to 424 passed, 0 failed). The scan program is now the variable `DR_SCAN_AWK` run by `dr_scan <file>`, so a new row runs it on a fixture holding an orphan before any header, a recognised function, an orphan after its `}` and a guard under `function f {`, pins the exact output, and runs two mutated programs (the `}` reset deleted, the ORPHAN branch reduced to `n++`) that each change it; the library itself has no orphan guard, so reverting either used to leave the suite green. `dr_mutant`'s in-function flag now clears at a column-0 `}` as the scan's name does, so a `}` inside a heredoc above a guard reads as the end of the function to both (pinned: the scan reports ORPHAN and `dr_mutant` exits 1). The #370 comment names all three shared patterns (`DR_GUARD`, `DR_HDR`, `DR_CMT`) and all three consumers. Two nits: the probe is `( bad ... ) >/dev/null` rather than an unread `probe=$(...)`, and the stray blank line after the #380 entry below is gone.
- **The contributor-docs suite pins a BOM-led doc with CRLF endings** (`scripts/test-check-contributor-docs.sh` only, repo-only, no component or plugin change, so no marker or semver bump; #385, #374 review Low; the suite goes from 516 to 520 passed, 0 failed, under the default awk and `AWK_UNDER_TEST=mawk`). The `c_doc_bom_*` cases were LF-only and the CRLF doc case had no BOM, so a change breaking only the combination of the line-1 BOM strip and the CR strip in `EXTRACT` would have passed. `c_doc_bom_crlf_neg` (a fenced `make nope` fails at `AGENTS.md:2`, exit 1) and `c_doc_bom_crlf_pos` (`make all` passes, exit 0) cover it, and each has a strip-dropped mutant anchored on the unique `EXTRACT='` opener that dies on it.
- **`template-versioning.md` states its thin-section rule as a reading of the agent's Thin row, and both sides are pinned** (`docs/guides/template-versioning.md` and `scripts/test-check-ticket-mechanics.sh`, repo-only, no component or plugin change, so no marker or semver bump; #392, #383 review Low 2; the suite goes from 261 to 274 passed, 0 failed). The Step 0c paragraph said a GDPR-headed section with fewer than seven facts "is thin" and the append goes "under the author's section", rules `ticket-gate.md` does not state in those words. It now says it is a reading of the Thin row and of the seven-facts definition of `personal_data`, exempts a section that states N/A with a reason, and places the append after the author's text, inside the author's section. `ticket-gate.md` is deliberately not edited (zero headroom at the 5754-word ratchet); instead the suite pins the three doc phrases through one newline-joining helper and the agent's three anchor lines (the Thin row, the seven-facts line, the thin definition) with single-line greps, each with a sed mutant and a named "did not apply" guard, plus a re-wrap case.
- **The `check-ticket-mechanics.sh` header says where check 4's block polarity comes from, and the `wc1` and `wc5` suite cases assert their outcome** (`check-ticket-mechanics-version` 14 to 15 for comment text only, `forge-kit-governance` 0.28.24 to 0.28.25, #371, the Lows of #359's review; `scripts/test-check-ticket-mechanics.sh` goes from 258 to 261 passed, 0 failed). A new header paragraph states that the When-count evidence names a block Negative through the anchored `MARK_NEG`, built by the same `marker_re` as `MARK_ANY` and `MARK_POS`, and why a substring test is not used; the #205 "ONE marker regex" sentence stays. `wc1` and `wc5` now also assert outcome `fail` (and `wc1` the absence of `Positive: 2 When lines`), so a mutant that turns the multi-When row into `pass` with the same text now fails both; previously only the evidence text was checked. Two nits are gone: `wc_ev` lost its identity `printf '%s'` wrapper (a new `wc_run` returns the whole run), and `wc5`'s first case arm, subsumed by the second, is dropped. No executable line of the checker changed.
- **`/phase review` step 4 reports an empty document list instead of printing nothing** (`phase-version` 11 to 12, `forge-kit-roadmap` 0.15.3 to 0.15.4, #393): the snapshot read-back was a one-line `&&` chain that printed nothing when the snapshot was missing and an empty line when it listed no documents beyond the roadmap and plan, leaving the reader to guess which. It is now a shell if/else like step 7's: an absent snapshot prints `no snapshot from step 1`, an empty list prints `no docs beyond the roadmap and plan`, and the review reports either message as printed and skips the drift check. A zero-byte snapshot counts as present. Checked in throwaway repos on four cases (absent, zero-byte, roadmap and plan only, a snapshot listing `README.md`). `phase.md` is at 1999 words, so the budget is untouched.
- **`template-versioning.md` describes Step 0c's body write as the forge-host adapter's, not a raw `gh issue edit`** (`docs/guides/template-versioning.md` item 4 of the Step 0c list only, repo-only, no component or plugin change, so no marker or semver bump). The line now says the gate clears its own regions with `forge_body_region_clear` (synthesis voids the prior verdict) and writes the body with `forge_body_compose_preserving`, which re-threads every other marked region the new body does not restate, so it holds on GitHub and Forgejo alike. It does not claim every region is preserved, because 0c-iv clears the gate's own first. Item 3 is untouched and no regression pin is added (#397).
- **`check-contributor-docs.sh` models a numeric-zero `workspaces` value, inline comments and quoted keys in a tracked `.npmrc`, and the suite gains the mutants #357's review asked for** (`check-contributor-docs-version` 12 to 13, `contributor-docs-version` 8 to 9, `forge-kit-governance` 0.28.20 to 0.28.21, #381): on npm 10.9.7 `workspaces=0` (and `00`, `-0`, `+0`, `0.0`, `.0`, `"0"`) reads as FALSE, not true as the ticket assumed, so an explicit `-w` run under it is now referred and a plain run is judged at the root. An unquoted value is cut at the first `;` or `#`, and a quote pair around a key is stripped before its `[]`, so `"workspace"=client` and `"workspaces"=false` are read (the first was a false `fail`). Pinned as documented limits, each with a case: `0x0`, `0e0` and `" false"` (npm reads false, the asset passes an explicit form), plus `workspaces[]=false`, which is unmodelled and tracked in #395. The loose `sets workspaces` needle is closed with a mutant, the two cases that no mutant killed (`c_npmrc_symlink_explicit_limit`, `c_npmrc_wsfalse_none_neg`) get one each, the `(decision A)` label leaves the asset comment and the SKILL wording is reflowed. The suite goes from 491 to 516 passed, 0 failed (13 cases, 12 mutants), and one existing mutant is re-anchored. The review's remaining Lows are tracked in #398.
- **The `check-doc-drift.sh` suite's ledger names the six rows the (c) fallback placement fails, and two comment lines are rewrapped** (`scripts/test-check-doc-drift.sh` comments only, repo-only, no component or plugin change, so no marker or semver bump; the suite stays at 261 passed, 0 failed). The #382 ledger said only meta-subst-unresolved and meta-glob-absent fail with the four bare-dup rows still green; measured at 5363792 under GNU Awk 5.2.1 the fallback gives 247 passed, 6 failed, and the six are bare-dup's "the full path in the same document still yields exactly one row" (3 rows for 1), meta-subst-unresolved's three rows and meta-glob-absent's two, and against the suite with the #382 rows it gives 7 (254 passed, 7 failed), the seventh being bare-root-dup's "a range changing only a candidate yields no row". The two over-wide `bare-root-dup` comment lines are wrapped to 100 columns. No assertion or runtime line changed (#389).
- **`check-doc-drift.sh` documents that a changed root file wins ahead of an ambiguous bare name, and its suite pins that and records two ledger mutants literally** (`scripts/check-doc-drift.sh` header comment only and `scripts/test-check-doc-drift.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 253 to 261 passed, 0 failed). The root-level exception sentence now says that in a range changing the root file no ambiguity line prints either, and that a root file is never listed as a candidate (the table is limited to catalogue assets and `scripts/*.sh`, the #372 Option A decision). A new `bare-root-dup` fixture, with the token beside TWO table candidates, pins all three ranges (root only gives its row and no ambiguity, a candidate only gives the two-candidate ambiguity line without the root file, both gives the root file's row), plus a header row and a `col4_is` control for its empty-sha guard. Ledger entries (c) and (d) now carry the literal edit, its anchor and the measured count (15 and 7, with (c)'s fallback placement at 6 and its 17 against the new suite), (a) says its two placements are one mutant, and a `#382 ADDED TWO MORE (so forty-three in all)` paragraph records the two new mutants, each surviving the old suite and dying on the new rows. No runtime line changed (#382).
- **`check-doc-drift.sh` resolves a bare `<name>.sh` citation** (`scripts/check-doc-drift.sh` and `scripts/test-check-doc-drift.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 143 to 182 passed, 0 failed). A backticked `<name>.sh` with no path separator was neither a tracked path nor a catalogue name, so a claim citing it was never flagged when that script changed. It now resolves to the one shipped asset (catalogue type `asset`, by basename) or tracked `scripts/<name>.sh` (read from HEAD) it names, and the ordinary line-age test runs on that path, so a `.doc-drift-allow` `mention` is keyed on the resolved path. A name matching two or more candidates is AMBIGUOUS: no row, one stderr line `ambiguous bare name '<name>.sh' (matches <path>, <path>); cite the full path`, once per token per document, decided from what exists and never from the range, exit still 0. No document is rewritten. The three `ranges_expect` README counts rise from 3, 1, 1 to 4, 2, 2 by design: the added row is the README line citing `forge-lib.sh`. The report-only posture is unchanged, and exempting done-phase roadmap history as a class is #340 (#332).

- **The `check-doc-drift.sh` bare-name suite pins the resolved file, and the awk takes the program name through `-v`** (`scripts/check-doc-drift.sh` and `scripts/test-check-doc-drift.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 224 to 247 passed, 0 failed). The three live-range assertions now pin the resolved file: column 4 of the `forge-lib.sh` row must equal the newest commit in the range that changed the asset, with a doctored right-token, wrong-sha control, because column 3 is only the token as cited and a wrong-file resolution still prints it. New fixtures prove a `$(...)` code span and a glob-character `scripts/` name are neither executed nor expanded (`meta-subst`, `meta-subst-unresolved`, `meta-glob-literal`, `meta-glob-absent`), the root-level `<name>.sh` exception (it resolves only when the range changed it) is stated in the script header and pinned by a negative range, and the `bare-none` near-miss is now `demo-checkXsh` so an anchored-regex lookup can no longer survive. The ambiguity line takes its program name from `-v prog="$PROG"` instead of a literal, shown by a scratch copy whose `PROG` is edited. The mutant ledger gains a `#372 ADDED SEVEN MORE (so thirty-eight in all)` paragraph. No behaviour changes in the shipped output (#372).

### Fixed

- **`bounded()` in the leak-guard and forge-lib suites reads only its own SIGALRM kill as 124, the pagination-cap assertion demands 2, and the #243 comments carry measured figures** (`check-public-leaks-version` 24 to 25 for comment edits only, `forge-kit-security` 0.14.3 to 0.14.4; #315, the four Lows of #243's round-1 review; `scripts/test-check-public-leaks.sh` goes from 598 to 607 passed, 0 failed, and `scripts/test-forge-lib.sh` from 418 to 419 passed, 0 failed). `[ "$rc" -ge 128 ] && rc=124` read every signal death as the bound's kill, so a crashing mutant looked killed. The watcher now sends `kill -s ALRM` and only status 142 maps to 124; a self-SIGTERM keeps 143, USR1 138 and KILL 137, and each helper's comment records the choice (a bound kill and a self-SIGTERM both arrive as raw 143 on bash 5.2.21, so mapping 143 cannot discriminate) and its residual (a command dying of its own SIGALRM also reads 124, now pinned by a row). The leaks suite gains nine rows (bound kill, exit 3, exit 0, USR1, KILL, TERM, the SIGALRM residual, and a prompt `OUT="$(bounded 5 true)"` capture); the forge-lib suite gains the USR1 row and its pagination assertion tightens from `-ne 0 && -ne 124` to `-eq 2`, the page cap's own return, which the old form let a USR1 crash satisfy. Mutants run on copies: `-ge 128` restored fails the USR1, KILL and TERM rows in the leaks suite and the USR1 row in forge-lib; a watcher sending plain TERM fails seven rows (143 where 124 is expected); a `forge_api` stub running `kill -USR1 $$` fails the new `-eq 2` assertion and passes the old one under the new `bounded()` (under the old `bounded()` it read 124 and failed). The measured figures went into the suite's #243 block and the overshoot sentence under `bounded()` (the scanner header was only reflowed): the scanner takes about 1 s unloaded and under 3 s at load 35 on 8 cores, and the mutant's kill lands late under load (seen at load 35, not reproduced at load 14 on bash 5.2.21), so both bash 3.2 only claims are corrected. The scanner's `RE_HOME` comment now says a shortest-match `#` stops at the first matching prefix whatever the segment holds, that excluding `/` makes it equal the old per-root `case` rather than making it fast, and that the speed relies on the early match; the header comment is reflowed. No executable line of the scanner changed. The third `bounded()` in `scripts/test-check-contributor-docs.sh` keeps its `-ge 128` mapping: it carries an INT and TERM trap on purpose (#338) and is owned by #261.
- **`check-public-leaks.sh` refuses an allow-file `prefix` that could never match** (`check-public-leaks-version` 23 to 24, `leak-guard-version` 21 to 22, `forge-kit-security` 0.14.2 to 0.14.3; #242, the companion of #239; `scripts/test-check-public-leaks.sh` goes from 527 to 598 passed, 0 failed). A `prefix` segment ending in a `TAIL_PUNCT` byte (`/home/alice.` is the model case, and a bracketed segment is refused too, with no bracketed exception) parsed cleanly and matched nothing, because rule A strips the match and compares it exactly against the unstripped entry; a segment holding an ASCII whitespace byte (space, tab, VT, FF, CR), a double quote or a backtick could never be yielded by rule A's match class at all. Both now exit 2 naming the line and saying the entry could never match, and where both apply the whitespace message wins. Security impact: none, the refusal only narrows the allow side and a refused entry suppressed nothing. An allow-file carrying such a line now exits 2 until the line is deleted, and the likeliest line to hit is `prefix /home/${USER}` or any other entry copied with a trailing period or bracket (the #239 precedent). `judge()` is unchanged, and so is every prefix form that worked (punctuation inside a name, a trailing slash). The suite adds the two refusal loops, an overlap loop, an accept loop with a suppression case, and six ledger mutants, five asserted to exit 0 and M242D asserted by its refusal message, so a crashing mutant is not counted as a kill, and each with its target line counted in the ledger (punctuation refusal dropped, whitespace refusal dropped, tab untested, "contains" instead of "ends in", bracketed exemption copied from root, trailing single quote exempted). The whitespace test is spelled as bytes so it gives the same verdict under any caller locale, pinned by a U+2003 parity case. A few unrelated SKILL.md sentences were also trimmed to stay inside the word budget.
- **`test-forge-lib.sh` closes the five #370 round-2 Lows: one comment pattern for all three guard recognisers, orphan guards fail by line, the uniqueness row runs last and covers itself, and `bad()`'s recorder is checked** (`scripts/test-forge-lib.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 417 to 418 passed, 0 failed). `DR_CMT` now sits beside `DR_GUARD` and `DR_HDR` and `dr_mutant`, the completeness scan and the reference count all read it, so a comment carrying the guard text above a real guard no longer makes the kill rows blame the ledger. The scan clears the function name at a column-0 `}`, so a guard before the first header, under `function f {` or under `f () {` prints `ORPHAN <line>` and fails once by line, never credited to the previous function. The uniqueness row moved after the TMPDIR-empty row so it covers that row's text, and it greps its own text in the recorder (`expect` evaluates before it records), with `2>/dev/null` ahead of `<` so a missing recorder no longer leaks stderr. A new row calls `bad()` in a subshell on a probe text and checks the recorder holds it, so dropping the `printf` from `bad()` alone now fails (#380). The review's two remaining Lows are tracked in #399.
- **The pre-push hook's `--full-tree` probe flag is pinned by a subdirectory run, the dead symlink assertion is gone, and the lazy-fetch cases say which git they need** (`check-public-leaks-version` 22 to 23 for a rewrapped header comment, `forge-kit-security` 0.14.1 to 0.14.2; #388, the four Lows of #384's review; `scripts/test-pre-push-hook.sh` goes from 154 to 158 passed, 0 failed). A new case runs the real hook with `sub/` as its working directory over a committed leak that the root allow-file skips: rc 0 with no finding line, while the `full-tree-dropped` mutant (the probe without `--full-tree`) exits 1 with the finding, so the flag is no longer an untested survivor (superseded by #396: the hook's `cd` to the root made `full-tree-dropped` equivalent, so this case and mutant were replaced). The case says it pins the flag only: git runs the hook from the root, and from `sub/` the `--head` scan is relative to `sub/`. The `entry has no value` assertion on the entry-shaped symlink, which could not fail, is deleted (with its unread `SYMOUT` variable), not moved, because the plain-text symlink case already carries `entry has no value` with its `symlink-mode-unchecked-b` mutant. The `GIT_NO_LAZY_FETCH=1` cases in both scanner suites now name git 2.45.0, the 2.39.4 and later security releases and distro backports, and say an older git fails loudly (exit 0 where 2 is expected). The header comment lines over 100 columns that #384 touched are rewrapped; eleven older ones stay out of scope.
- **The body-region guards #248 left untested now have tests that die without them, and `forge_issue_edit`'s dry run counts characters** (`forge-lib-version` 31 to 32, forge-kit-devops 0.20.1 to 0.20.2; #264; the suite goes from 405 to 417 passed, 0 failed). The end-before-start refusal in `_forge_splice` (set and clear) and the exact-prefix arm `"$prefix"-*|"$prefix")` in `_forge_region_write` each get a case that passes against the library and fails against a copy with that guard removed (run through `FORGE_LIB_UNDER_TEST`): the first mutant fails the two L1 cases, the second fails the L2 case. The 'byte for byte' row now has a real file-byte comparison beside it and its message says only what its matcher checks. `forge_issue_edit`'s dry-run line says `characters` instead of `bytes`, tested under an explicit `C.UTF-8` whose availability the suite asserts first. The header now states that the splice writes LF markers into a CRLF body and gives an empty body one leading blank line, both pinned by characterization cases. No caller changes: a contract-changes line records v32 as such.
- **`/phase review` sets `SNAP` itself in step 4, anchors steps 1 and 7 at the repo root, and states which proof line wins** (`phase-version` 10 to 11, `roadmap-phases-version` 12 to 13, `forge-kit-roadmap` 0.15.2 to 0.15.3). Step 4's read-back sets `SNAP` and prints nothing when the snapshot is missing, so the agent reports `no snapshot from step 1` instead of calling `check-doc-drift.sh` with an empty `--docs`. Steps 1 and 7 run in a subshell that first `cd`s to the toplevel, so a subdirectory no longer records every path `absent` or prints a false `held`. With a missing snapshot or unset `ACTS` and acts performed, the `unproven` line and the `performed` lines print together, and `held` prints alone. The `held` count pipes `wc -l` through `tr -d ' '` (BSD padding), and SKILL.md now names the unset or non-numeric `ACTS` case and counts the acts step 6 performed. To stay at 1998 words (warn budget 2000, ceiling 3000) the step 1 prose trim drops the sentence "the earlier one reports changed or unproven, never held" about overlapping runs sharing one snapshot file; the shared-file behaviour itself is unchanged (#373).
- **ticket-gate Step 0c adds the pointer above a GDPR-headed `personal_data` section, and the label assertion in the placeholder suite compares the first line** (`ticket-gate-version` 64 to 65, `forge-kit-governance` 0.28.19 to 0.28.20, #383, the #361 round-2 findings). The 0c-iv pointer rule said "Only outside Step 0c's target set", which left a GDPR-headed section with no `## Personal data handling` heading, so check 3 failed with `heading absent`; it now reads "Except for `scenarios`, `unit_tests`, `e2e_tests`, `docs_impact`" (six words for six, so `ticket-gate.md` stays at 5240 words and the ratchet total at 5754) and lines 118 to 119 and 148 to 152 are rewrapped under 100 columns. `docs/guides/template-versioning.md` states the same rule and the thin GDPR path. `scripts/test-check-ticket-mechanics.sh` moves the scope pin to the new phrase with an absence pin for the old one, adds the GDPR checker cases (pointer passes, bare rename fails) and a doc pin searched across wrapped lines, and replaces the weak `grep -qxF "### <label>"` label assertion with `label_ok`, whose mutant (a `ph.py` that always reports `Unit tests`) the old grep let through for bug, feature and security. No other marker moves.
- **`check-contributor-docs.sh` judges the workspace spelling of `run-script` like the workspace `run`** (`check-contributor-docs-version` 11 to 12, `contributor-docs-version` 7 to 8, `forge-kit-governance` 0.28.18 to 0.28.19, #363): `npm -w`, `--workspace` and `--workspace=`, and `pnpm --filter`, `-F` and `--filter=`, followed by `run-script X` now fail when the workspace lacks X, through a new `is_run` helper that also widens the flag-between loop (which now prints the doc's own verb). `run-scripts`, `rum` and `urn` stay unjudged. Changed rows: `pnpm -F web run-script` with no name goes from referred to silent; `pnpm -r run-script build` moves from the "may be a script" row to the flag-between row; `npm -s run-script x` goes from silent to referred. The suite goes from 478 to 491 passed, 0 failed, and replaces the pinned-gap case `c_pm_run_script_ws_silent` and its mutant with seven cases and seven named mutants.
- **`check-contributor-docs.sh` judges `run-script` like `run`, keeps the raw word for a punctuation-only script name, and names the two lifecycle-row mutants** (`check-contributor-docs-version` 10 to 11, `contributor-docs-version` 6 to 7, `forge-kit-governance` 0.28.17 to 0.28.18; #353, from #326's review; `scripts/test-check-contributor-docs.sh` goes from 448 to 478 passed, 0 failed). `npm run-script X` and `pnpm run-script X` were answered "runs a lifecycle script; not checked", so an undefined script written that way never failed. `run-script` now dispatches with `run`, leaves the lifecycle list, and every `judge_pm` row prints the doc's own verb. A name that trims to nothing (`npm run .`) used to print an empty name, with a double space in the workspace row; all three trim sites now keep the raw word. The workspace `run-script` spelling stays a pinned gap (#363). Thirteen cases and seventeen named mutants were added, each killed by its case, and seven existing mutant anchors were re-anchored.
- **`forge_api_paginate` and `forge_issue_label` release the temp directory when their file `mktemp` fails** (`forge-lib-version` 30 to 31, forge-kit-devops 0.20.0 to 0.20.1; the suite goes from 401 to 405 passed, 0 failed). Both sites ran `_forge_tmp_init`, then `tmp="$(mktemp ...)" || return 2`, so a failing file `mktemp` returned 2 and left the empty directory behind whenever the caller had its own EXIT trap. Each now runs `{ _forge_tmp_done ""; return 2; }`, which rmdirs only an empty directory, so a concurrent holder's file is untouched. Four new cases in `scripts/test-forge-lib.sh`, each with a `mktemp` shim failing only its own template and a per-case TMPDIR: one red-first per site (rc 2, empty directory) and one holder case per site. Removing either fix turns that site's case red, and replacing either with `rm -rf` of the directory turns that site's holder case red (#303).
- **A committed symlink `.leak-guard-allow` no longer suppresses a leak at the pre-push scan, and the allow-file probe tells absent from failed** (`.githooks/pre-push`, `check-public-leaks.sh` 21 to 22 and `check-private-leaks.sh` 15 to 16 for rewrapped comments, `leak-guard` 20 to 21, `forge-kit-security` patch 0.14.0 to 0.14.1). Security impact: this failed OPEN. #375 read the allow-file with `git show HEAD:.leak-guard-allow`, which returns a symlink's link text, so a link whose text was itself a valid entry (`skip docs-leak.md`) was applied as a skip and the hook exited 0 over a committed leak. The probe is now `git ls-tree --full-tree HEAD -- .leak-guard-allow`: empty is absent, a failure is could-not-RUN, only modes 100644 and 100755 are read (by the oid from that same line), and any other mode is refused as could-not-RUN with its own message. SKILL.md now says `--head` fetches blobs lazily in a partial clone. Both hook suites run with an isolated `HOME`, so the private-name list consulted is the fixture's and not the developer's. The hook suite pins the entry-shaped and plain-text symlink cases, a 100755 file and a failing probe, with mutants `symlink-mode-unchecked`, `probe-error-as-absent` and `home-not-isolated`; both scanner suites pin the partial-clone cases with a `read-error-swallowed` mutant (#384).
- **`check-contributor-docs.sh` carries an `npm_config_` export only to npm, pnpm and yarn, handles three more export spellings and prefix or chained `$(..)` values, and does its rewrite and strip in linear time** (`check-contributor-docs-version` 9 to 10, `contributor-docs-version` 5 to 6, forge-kit-governance 0.28.16 to 0.28.17; #346, the seven Lows of the #296 review; the suite goes from 379 to 448 passed, 0 failed). An `export npm_config_prefix=x` no longer refers a later `make` or `just` row, so a failing target stays a `fail`. `declare -gx` and `declare -g -x`, a quoted `export "npm_config_x=y"` and a bare `export npm_config_x` now carry, while `declare -g` without an `x` does not. `pre$(..)` and `$(..)$(..)` values are rewritten rather than listed as limits, and the header and SKILL.md now state the real backtick behaviour (no space: referred; a space inside: no row). The rewrite is one marker pass and the leading-assignment strip one `match`, replacing two loops that were quadratic on a hostile line (gawk did not finish 192000 words in 30 s before; 0.25 s after). The suite pins every anchor member and the multi-match rewrite, bounds the hostile cases by `HOSTILE_WATCHDOG_SECS` (default 6), makes `mutant` fail loudly on an unpaired argument (`build_mutant`), and skips the make mutant on a make-less machine (`mutant_needs`) instead of going falsely RED. The strip mutant is skipped under mawk, whose pre-fix time at 192000 words (about 3.1 s) is under the 6 s bound, so the restored loop would survive there. A bare export name is not carried after a `#` comment word, inside a quoted value, or after a `-n` dash word, each pinned by a negative case and a mutant; `$VAR` before a substitution and `export "npm_config_x"=y` are stated limits.
- **`check-ticket-mechanics.sh` joins three or more multi-When blocks with `; `** (`check-ticket-mechanics` marker 11 to 12, `forge-kit-governance` 0.28.15 to 0.28.16; `scripts/test-check-ticket-mechanics.sh` goes from 198 to 203 passed, 0 failed). Check 4 joined its offending-block evidence with `paste -sd'; ' -`, but `paste -d` cycles its delimiter list one character per join, so three blocks read `Positive: 2 When lines;Negative: 2 When lines Positive: 2 When lines`. The join is now `awk 'NR>1{printf "; "} {printf "%s", $0} END{print ""}'`, the separator the script already uses elsewhere, and the `head -3` cap is unchanged. The #359 two-block pin is rewritten to the `; ` form and the two-, three- and four-block evidence is pinned by whole-field equality rather than a substring glob, with a mutant that restores `paste` and flips the three- and four-block pins (#365).
- **`check-contributor-docs.sh` strips a leading byte-order mark from every doc it reads** (`check-contributor-docs-version` 8 to 9, forge-kit-governance 0.28.14 to 0.28.15; #374, split from #364). The `EXTRACT` doc reader (AGENTS.md, CONTRIBUTING.md, PR templates and anything passed with `--docs`) stripped only a trailing CR, so a BOM on line 1 hid a line-1 fence opener, every later fence pairing inverted, and fenced commands and prose links were lost or misjudged: a `make nope` in a BOM-led AGENTS.md was a silent exit 0, and a line-1 reference definition yielded no link row. `NR == 1 { sub(/^\357\273\277/, "") }` is now the first rule of `EXTRACT`, the octal form `npmrc_scan` and the other readers use, so only line 1 is affected; the header's limits comment says so. Eight new cases (a fenced command that fails and one that passes, fence pairing after a BOM-led fence both ways, a BOM-led reference definition, a BOM on line 2 left alone, a BOM-led prose-only doc, a BOM-led CONTRIBUTING.md via `--docs`) and seven mutants anchored on the unique `EXTRACT='` opener (strip dropped, killed by each of the six strip-dependent cases, and strip applied to every line); the suite goes from 364 to 379 passed, 0 failed. SKILL.md is unchanged.
- **`gate-status.sh` header line 45 is back under 100 columns** (`forge-kit-governance` `0.28.13` to `0.28.14`, `gate-status-version` 7 to 8). The #369 rewrap kept the `stale round <R> <VERDICT> (fingerprint <old>, now <current>)` code span whole but left the next header line at 117 columns. Lines 45 to 47 are re-wrapped at 97, 95 and 96 columns with word-identical text and the file stays 275 lines; no executable line changed (#376).
- **`check-doc-drift.sh` says "missing its path" for an allow entry that has no path** (`scripts/check-doc-drift.sh` and `scripts/test-check-doc-drift.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 247 to 253 passed, 0 failed). `mention README.md` was refused as `entry is missing its anchor`, because the path split consumed nothing and returned the document itself, which then passed as the path; the same entry with a trailing space already said `missing its path`. The path split now carries the same consumed-nothing guard as the document split above it, so both spellings give the one message, and the exit code stays 2. Three mutants each die on their case (#308).
- **The pre-push leak scan reads HEAD's committed tree, so an uncommitted edit can no longer hide a committed leak** (new `--head` mode in `check-public-leaks.sh` 20 to 21 and `check-private-leaks.sh` 14 to 15, `.githooks/pre-push`, `leak-guard` 19 to 20, `forge-kit-security` minor 0.13.0 to 0.14.0). The hook also reads `.leak-guard-allow` from HEAD, and a failed read is a could-not-run, never a dropped allow-file. Both suites and the hook suite pin the masked, uncommitted-only, deleted-file, subdirectory and allow-file cases, with mutants for each (#375).
- **`check-contributor-docs.sh` strips a leading byte-order mark from a tracked Makefile and justfile** (`check-contributor-docs-version` 7 to 8, forge-kit-governance 0.28.12 to 0.28.13; #364, split from #357). GNU make and just (since 0.10.4) both ignore a leading UTF-8 BOM, but `MAKE_AWK` and `JUST_AWK` stripped only a trailing CR, so the BOM stayed glued to the first word and a documented `make dev` or `just dev` was a false `fail ... no such target`, and a BOM before `include` or `set fallback` was a `fail` instead of `referred`. `NR == 1 { sub(/^\357\273\277/, "") }` is now the first rule of both programs, the form `npmrc_scan` already uses, so only line 1 is affected. The header notes that `judge_target` runs awk without `LC_ALL=C` and that BSD awk is untested. Nine new cases (BOM with a defined, an absent, an include, a later-line and a CRLF Makefile; a defined, an absent, a `set fallback` and a `set shell` justfile) and five mutants anchored on each program's opener (strip dropped in each reader, strip placed after the include or `set fallback` rule, `NR == 1` dropped); the suite goes from 350 to 364 passed, 0 failed. SKILL.md is unchanged. The same BOM gap in the doc reader is tracked in #374.
- **ticket-gate Step 0c tells the synthesis sub-agent the template's labels and scenario format, and has a rule for variant headings** (`ticket-gate-version` 63 to 64, forge-kit-governance 0.28.11 to 0.28.12; #361). The 0c-iii dispatch now names the absolute `$PWD/$TPL_DIR/<type>.yml` path (0a's `$TPL_DIR` is relative) and a label instruction placed before the inline `docs_impact` fast path tells both paths to write each section as `## <label>` copied verbatim from the template's `label:`, scenarios following its `placeholder:` shape and never placeholder text, so the first synthesis passes checks 3 and 4 without a second copy of the format. A new rule, scoped to sections outside Step 0c's target set, counts a non-target author section under a variant heading as present when exactly one template label fits and adds `## <label>` plus one `See "<variant>" below.` line above it; a target section under another heading is Missing and synthesised under the label with no pointer, since checks 4 to 7 read only the text under the label. The word ratchet holds at 5754 (ticket-gate.md plus its preloaded SKILL.md): the 33 words of the old sub-agent sentence and 44 of named cuts, plus about 30 words of other 0c wording tightened, pay for the additions. `scripts/test-check-ticket-mechanics.sh` gains cases that run the checker on each of the five work templates' own scenarios `placeholder:` under its `label:` (pass, referred, fail), the heading-absent evidence, the pointer-under-`## Unit tests` failure the scoped rule prevents, and prose pins, each with a mutant on a scratch copy.
- **`check-contributor-docs.sh` refers a symlinked root `.npmrc`, follows npm's last-value rule for `workspaces`, and refers an explicit `-w` run npm would refuse** (`check-contributor-docs-version` 6 to 7, `contributor-docs-version` 4 to 5, forge-kit-governance 0.28.10 to 0.28.11; #357, the low findings of the #339 review). A tracked `.npmrc` with index mode 120000 is referred from the mode alone, so the link target (which may be a `~/.npmrc` holding a token) is never read, followed or printed. The scan now keeps the LAST `workspaces` value: `workspaces=false` with `npm -w`, `--workspace` or `--workspace=` is referred (npm stops with "Can not use --no-workspaces and --workspace at the same time"), and `true` then `false` with no `workspace` key is judged at the root instead of referred. Both rules are verified on npm 10.9.7 only. Quote stripping and the leading-space trim are now pinned, and the header and SKILL.md wording is corrected. The suite goes from 303 to 350 passed, 0 failed; mutants cover the new cases except the pinned symlink limit and the false-without-key negative (tracked in a follow-up), four existing mutants were re-anchored on the rewritten awk, and the non-root `.npmrc` mutant gained a third pair. A symlinked `.npmrc` holding `workspaces=false` with an explicit `-w` form still passes, a stated and pinned limit. The Makefile and justfile byte-order mark is tracked in #364.
- **`test-forge-lib.sh` makes every row text unique, enforces that in the suite, and fails when a `FORGE_DRY_RUN` guard has no mutant ledger** (`scripts/test-forge-lib.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 399 to 401 passed, 0 failed). Four row texts repeated across the output (`and sends no PATCH` three times, `and sends nothing` twice, and the two rows in the `for v in 0 true` loop), so a failing row could not be told from its twin; each now carries its site or flag value. `ok()` and `bad()` also record each text under the suite's temp dir, and a new row fails the suite if any two share one. A new completeness row derives the guarded functions from the library, using `dr_mutant`'s own recognition (the header regex and guard spelling are defined once and both awks read them through `ENVIRON`), and fails by name for any recognised function not in `DR_SITES` or the #319 ledger (a guard outside a recognised header is reported as an orphan by line, #380), for any function with more than one guard (`dr_mutant` mutates only the first), and when it recognises none; it also cross-counts every non-comment `FORGE_DRY_RUN` occurrence against the recognised guards so a guard in another spelling, or a second reference on a guard line, cannot hide. The uniqueness row fails if the recorder file is missing or holds fewer rows than the counters, and the recorder encodes embedded newlines so a multi-line text is one row. The `dr_mutant` comment no longer overclaims: an unreadable library exits 2, an unwritable outfile exits 1 (#370).
- **The pre-push hook's leak message no longer claims this push published the leak, and the suite pins the qualifiers it left untested** (#368, `.githooks/pre-push` and `scripts/test-pre-push-hook.sh`; neither is a versioned component, so no marker or semver bump; the suite goes from 103 to 107 passed, 0 failed). `check-public-leaks.sh --all` scans the working tree, so a leak that exists only in an uncommitted edit is blocked but never published by the push: the message now says "but only once it is published" and "--no-verify can publish it", and the hook comment records why and the two declined review items (the "when the run reaches that step" clause and the scanner labels). New pins: `once it is published` and `with no pull request triggers no CI scan` in the leak loop, `though an open PR for it still triggers one` in the range loop, an absence check for `this push has published it`, and `--no-verify can publish it` replacing `--no-verify publishes it`; each is proven by a mutant on a scratch clone. The `-eq 1` test comment now gives the real rationale (a crash or exit 2 must not pass as a block) (#368).
- **`check-doc-drift.sh` says so when it cannot resolve component names** (`scripts/check-doc-drift.sh` and `scripts/test-check-doc-drift.sh`, repo-only, no component or plugin change, so no marker or semver bump; the suite goes from 182 to 224 passed, 0 failed). With `forge-adapt-catalogue.sh` not beside the script the component-name lookup was skipped without a word (5 rows instead of 18 in the measured run), so a degraded run read as a clean one. It now prints one stderr line `check-doc-drift: forge-adapt-catalogue.sh not found beside the script; component-name claims were not checked` when a `plugins/` directory exists, and a separate `... failed; ...` line when the catalogue exists but exits non-zero. Both are warnings: exit stays 0, path rows print unchanged, they come before the summary line, and a tree with no `plugins/` stays silent (warn over fail closed, assumed and reversible). The script's own directory is now resolved before the `--root` cd, so a relative script path plus `--root` no longer misses a catalogue sitting beside it. The catalogue lookup now runs only after every document is validated, so a refused run prints no catalogue warning, and the script directory is resolved with `CDPATH` cleared. Seven new mutants each die on their case (#354).
- **The pre-push hook's header and missing-base-ref stderr now say an open PR still triggers CI, and the suite pins the three claims it left untested** (#366, `.githooks/pre-push` and `scripts/test-pre-push-hook.sh`; neither is a versioned component, so no marker or semver bump; the suite goes from 96 to 103 passed, 0 failed). Both said a push to any other branch gets no push-time CI run with no exception, but `validate.yml` has an unfiltered `pull_request:`, so a branch with an open PR does get a run; each now ends ", though an open PR for it still triggers one", as the stdout sibling already did. New assertions: `'open PR'` in the stderr fragment loop, `'push-time CI run'` and `'open PR'` on the header, and a negative grep for `host rules run in CI` on the roadmap-failure output. Each is proven by a permanent in-suite mutant on a scratch copy of the hook under `$TMP`, behind a `grep -q` ledger (scoped to the header for the header mutant, since the caveat also sits on stdout) and a `cmp -s` guard so a `sed` matching nothing cannot pass. The roadmap line at `.githooks/pre-push:117` is left unwrapped: 16 lines of the hook passed 100 columns at HEAD.
- **`check-contributor-docs.sh` knows four more Berry built-ins, and its yarn paths gain the missing test pins** (`check-contributor-docs-version` 5 to 6, forge-kit-governance 0.28.9 to 0.28.10; #317, the low findings of the #299 review). `yarn unplug`, `yarn stage`, `yarn patch-commit` and `yarn search` joined the silent built-in list, so a mention of one no longer yields a spurious `referred` row or, when the root defines a script of that name, a false `pass` (yarn never emits `fail`, so no run could start failing). New cases pin the yarn root with no tracked `package.json`, the `-s`/`--silent` exemption in both directions, the Berry names and the bare-form-only rule, and `c_yws_neg` now asserts the data-carrying `does not define build` instead of the row label; ten new mutants each die on their case, and the suite goes from 288 to 303 passed, 0 failed (gawk, mawk and busybox awk). Finding 3 (the `judge_ws` trim) was already closed by #326.
- **The tier-probe fixture's comment and README are accurate** (`scripts/fixtures/tier-probe-security-tester/reference_test.py` comment and `README.md` opening paragraph, repo-only, no component or plugin change, so no marker or semver bump). The readiness-loop comment said it accepts "any 401" while the loop catches every `urllib.error.HTTPError`; it now says any HTTP error response. The README opening paragraph said a bare `python3 -m pytest` reports `3 failed` by design without the reason; it now says `SERVER_FILE` defaults to the vulnerable `server.py`. No executable line and neither server changed (#367).
- `test-gate-status.sh` now runs the third `;touch x` case inside the scratch dir `$T` like the first
  two, and the `gate-status.sh` header keeps two markdown code spans each on a single comment line
  (`gate-status-version` 6 to 7, `forge-kit-governance` patch). No behaviour change (#369).
- **`check-test-suites-wired.sh` and its suite: the seven Lows from the #348 review** (`scripts/check-test-suites-wired.sh`, `scripts/test-check-test-suites-wired.sh`, `scripts/test-producer-stamps.sh` and `scripts/test-template-dir-order.sh`, repo-only, no component or plugin change, so no marker or semver bump). The guard now pins `LC_ALL=C` so a U+3000 after the path cannot end the token under a UTF-8 locale, the walk path counts a symlinked suite (and drops a dangling link) as the checkout path does, and the header documents the `|| true` limit. The suite gains a CRLF fixture that can fail (with the CR strip and the narrowed token cut as one compound mutant), a locale fixture run under `C.UTF-8`, symlink and dangling-link fixtures, tracked `docs/test-x.sh` and `test-y.py` fixtures, and a fixed-byte binary-input fixture that tells a crash from a finding. All three suites export `GIT_CEILING_DIRECTORIES` for their fixture root, so they pass with `TMPDIR` inside this checkout (they passed only 75 of 80, 11 of 24 and 15 of 28 before). `check-test-suites-wired` 80 to 91 passed, 0 failed; `test-producer-stamps` 24 and `test-template-dir-order` 28, both 0 failed under any TMPDIR (#362).
- **`test-check-contributor-docs.sh` bounds a hung `c_escape` run, cleans up after Ctrl-C, and documents `ESCAPE_WATCHDOG_SECS`** (#338, `scripts/test-check-contributor-docs.sh`, test-only, no component or plugin version change). `run` now bounds the script under test at `ESCAPE_WATCHDOG_SECS` + 5 s, so a third read, a write-open or a slow run followed by a second open fails the case with RC 124 instead of hanging until CI's timeout. `bounded` gains an INT/TERM trap that sends TERM to the command's group (so its own EXIT trap removes its `tmp.*` directory; KILL would leak one per interrupt) and KILL to the watcher, then re-raises SIGINT, which a suite-level INT trap turns into exit 130 so the run stops even after a direct `bounded` call, and the EXIT trap kills the recorded writer and the watchdog's process group, so an interrupted run leaves no process and no temp entry behind. The refused-value checks run their child under `bounded 5`, so a validator that wrongly accepted a value fails by name instead of recursing. The variable is validated (integer 1 to 60, else exit 1 before any case) and named in the header. The suite grows from 272 to 288 passing checks (four mutants, three RC assertions, nine validation and header checks).
- `/phase review`'s second-run proof compares a step 1 snapshot of the local paths (per-path
  `git hash-object`, kept in a file under the git dir) with the state after step 6, and also requires
  an empty act list (wording superseded by #373: step 6 must have performed no acts), instead of requiring a clean `git status --porcelain` that a first run's
  uncommitted writes made impossible; a missing snapshot, or an `ACTS` count never set, reports unproven, never held (#271).
- `check-ticket-mechanics.sh`'s multi-When check (check 4) named a Negative block Positive in its
  evidence whenever the block's label contained the word (`Negative (the Positive path is
  blocked)`), because it tested polarity with a substring search. It now uses the anchored
  `MARK_NEG` regex its sibling checks already use, so the evidence names the right block. The
  suite pins the labelled-Negative, bold-Negative, mirror and both-blocks cases and a mutant that
  restores the substring test. `check-ticket-mechanics` 10 to 11 (#359).
- `scripts/test-forge-lib.sh`: the #334 and #319 `dr_mutant` ledger rows now name the mutant form, so
  the n and b rows are distinct. The `dr_mutant` contract comment now states its exit status, and the
  comments no longer carry a guard count. Test-only, suite count unchanged (#358).
- **`gate-status.sh` dates its v5 shape rule and `test-gate-status.sh` makes the shape loop's `--mark-stale` rows able to fail** (#356, `gate-status-version` 5 to 6 (header comment only, no behaviour change), `forge-kit-governance` 0.28.6 to 0.28.7; the suite goes from 176 to 181 passed, 0 failed). The v5 sentence now opens "(v5, #342) Only two shapes" and the `THE TAG` paragraph is reflowed so no line passes 100 columns (line 50 was 125). The seven non-writer shapes now carry the stale hash `sha256:0000000000000000`, because with the current hash a misread shape read `current` and its `--mark-stale sends nothing for it` row could not fail; a new `probe_shape_patch` plus an `m` line keeps the catch-all-deleted kill permanent. Three new cases: metacharacters outside the parentheses and a newline splitting the text after the hash both read `unrecorded round 2` (the catch-all mutant kills both), and a newline after a complete stamp reads `current`, labelled a sanity check together with the absent-file `x` check, since neither can be failed by a plausible mutant.
- The pre-push hook's leak message no longer says "NOT one of the CI checks; nothing server-side will
  catch it for you", which was false for the public scan: CI runs `check-public-leaks.sh --all`. The
  counter is shared by both scanners, so the message is now conditional: the private-name scan runs
  only on this machine, the public scan is also run by CI on pull requests and pushes to main and
  develop but only after publication, and a push to another branch triggers no CI scan. The test
  asserts the wording on stdout, pins exit code 1, and keeps the old phrases as absence patterns
  (#313).
- `reference_test.py` in the tier-probe fixture now waits for the server child with
  `proc.wait(timeout=1)` instead of a single `proc.poll()`. A listener appearing after the port
  probe (a concurrent run) could answer the test while this run's child had already lost the bind,
  giving a wrong answer key; it now gives `3 errors`. The fixture README's opening paragraph is
  rewrapped and says a bare repo-root `python3 -m pytest` reports `3 failed` by design (#355).
- The pre-push hook no longer presents itself as a preview of CI. It names where CI's base differs
  (the PR's target branch on a pull request, the previous tip on a push), says a push to any other
  branch gets no push-time run (corrected by #366: unless an open PR exists for it), and stops
  claiming the roadmap guard's host rules run in CI: they run from `/phase`. A stale component
  index now prints WHICH region is stale, as "<file> (<region id>)", instead of a summary
  pointing at nothing (#311).
- `check-doc-drift.sh` accepted no allow-file entry whose anchor equals its path: the
  missing-anchor test compared the anchor with the path, so the real fourth field read as absent.
  It now compares with the remainder, and CRLF line endings in the allow-file are stripped before
  the blank and comment checks, so a Windows-edited allow-file behaves as LF. Test-only plus
  script; `scripts/test-check-doc-drift.sh` pins both (#265).
- **`test-forge-lib.sh` stops crediting a crashing mutant as a kill in the #334 dry-run ledger** (#350, `scripts/test-forge-lib.sh`, test-only, no `forge-lib.sh` change, no marker bump; the suite goes from 396 to 399 passed, 0 failed). The two kill lines used `dr_site ... real && bad || ok`, and `dr_site` exits 1 on any failure, so a mutant that crashed (rc 127 from a missing function) printed `ok: ... is killed by FORGE_DRY_RUN=0`. A kill now requires a clean dry run (`dr_site ... dry`), as `mc_cleanly_dry` does for #319, and one crash control per mutant form at `forge_issue_list` pins that a crash is rejected in both modes. A revert of the kill lines is caught by the manual mutation check, not by a permanent assertion.
- **`check-test-suites-wired.sh` fails CI when a tracked `scripts/test-*` suite has no step in `validate.yml`** (#348, new `scripts/check-test-suites-wired.sh` and `scripts/test-check-test-suites-wired.sh`, two new `Validate` steps, no component or plugin change, so no marker or semver bump). #344 found `test-reassess-phases.sh` unwired although the stated policy is that every suite runs in CI, and the pre-push hook cannot catch it because `update-suite-counts.py` ignores a suite's exit code. A suite is a tracked file directly inside `scripts/` named `test-*.sh` or `test-*.py` (enumerated through `guard-lib.sh`, root resolved physically once; a plain `find -maxdepth 1` outside a checkout). It counts as wired only when a line of `validate.yml`, after stripping indentation and one `- `, starts with the literal `run: bash scripts/` or `run: python3 scripts/` and its first whitespace-delimited token equals the basename, with `bash` wiring only `.sh` and `python3` only `.py`; a comment, a `.bak` sibling, a quoted value, a `./scripts/` path and a `run: |` block wire nothing. Exit 0 all wired, 1 names every unwired suite, 2 for an unusable input (root not a directory, `validate.yml` missing or unreadable, zero suites). CI-only: a pre-push wiring would be its own ticket.
- **`test-check-phases.sh` closes four Low findings from the #336 review** (#352, `scripts/test-check-phases.sh` and `scripts/test-reassess-phases.sh`, test-only, no `check-phases.sh` or `reassess-phases.sh` change, no plugin marker bump; `test-check-phases.sh` goes from 78 to 79 passed, 0 failed, `test-reassess-phases.sh` stays at 164 passed, 0 failed). The failed-read comment now says B is planned by the rule-3 case's roadmap above, not by an open milestone elsewhere in the file. A new probe, `absent_line "rule 3" "Rule 3: x"`, pins the helper's case sensitivity, which a `grep -qiF` mutant previously passed. `test-reassess-phases-version` goes from 4 to 5 (convention only, no guard reads it). The `absent_line` probes move into their own `== absent_line self-test (#336) ==` section after `run()`, so the flagged run's assertions read contiguously.
- **`test-forge-lib.sh` closes four Low findings from the #334 review** (#343, `scripts/test-forge-lib.sh`, test-only, no `forge-lib.sh` change, no marker bump; the suite goes from 375 to 396 passed, 0 failed). `dr_mutant` never cleared its in-function flag at the next function header, so a function with no guard (`forge_body_region_get`, `forge_issue_view`) had a LATER function's guard rewritten and the call exited 0; it now resets the flag at every header and ends with `END { exit !done }`, and a permanent refusal block pins that a guard-less name and a nonexistent name each exit 1 with output byte-identical to the library (reverting the awk alone leaves the suite green at 394 passed without that block, which is the gap it closes). Both `dr_mutant` call sites now assert its exit status, which guards a mistyped site name. The real-mode paginate expectation is built with `printf '%s\n'` so a trim-on-save editor cannot strip its two trailing spaces and make the failure blame the library. `forge_api` now runs value 1 as well as `true`, which makes its dry-mode `want` arm reachable, and `forge_api_paginate` has its own dry-mode ok and bad messages (page 1 read only, then `[]` and no further page). A comment no longer hardcodes the guard count ("every guard in the library").
- **`check-contributor-docs.sh` refers an `npm run X` when a tracked root `.npmrc` rescopes npm** (#339,
  `check-contributor-docs-version` 4 to 5, `contributor-docs-version` 3 to 4, `forge-kit-governance` 0.28.5 to 0.28.6).
  A tracked root `.npmrc` that sets `workspace` (any value, `workspace[]=` and spaced forms included) or
  `workspaces` with any value but exactly `false` made the checker judge `npm run X` from the root manifest,
  a false `fail` when the root lacks X and a false `pass` when it defines it. Both rows are now `referred`,
  with a detail that names only the key and never any `.npmrc` text. The file is read from the index and
  parsed as npm's ini does (a CR or CRLF splits lines, a leading UTF-8 byte-order mark is dropped, `;` and `#` lines skipped, scan stops at a `[section]` header that starts its line,
  case-sensitive key). `pnpm run`, yarn and the explicit `-w` forms are unchanged, and the `.npmrc` limit
  in SKILL.md and the header is narrowed to the user, global and non-root files. `scripts/test-check-contributor-docs.sh`
  grows from 225 to 272 passing checks (22 cases, 25 mutants).
- **`api-security-tester` re-measured on a seed with a black-box witness for every planted issue** (#292, `docs/guides/model-tiers.md` only, no component, plugin or role change). Six headless runs (`opus` and `sonnet`, three each, effort `high`) against `scripts/fixtures/tier-probe-security-tester/` under the harness #289 used and the criterion pre-registered in `54f8600`: both tiers covered SQL injection, the order IDOR and the non-admin read of `/admin/users` in all three runs, so the seed and the criterion worked where #289's could not. The role stays on `security` because the cost rule needs Sonnet's median output AND cache reads both no higher than Opus's, and its median output was higher (15779 against 13287) while its cache reads were lower (304k against 582k).
- **`gate-status.sh` accepts only the Judged-line shapes a writer produces, and says why a verdict is stale** (#342, `gate-status-version` 4 to 5). After the hash, only `.`, `. <text>`, ` (<tag>).` or ` (<tag>). <text>` is a stamp; every other shape (no space before the tag, a double space, a tab, `[fp1]`, text glued to the hash or to the full stop, a bare hash) now reads `unrecorded` instead of falling through to a hash comparison, so no stamp any writer produced changes state. `--mark-stale` writes "this verdict was recorded by fingerprint algorithm <old>, which this script no longer computes" for an algorithm change and keeps the existing wording for a body edit; the old tag is cut at the LAST `(fingerprint `, so a verdict heading that itself carries that text cannot leak into the Stale line (review M1). The header now says what the golden pin enforces (the `FP_TAG` literal and the hash as one literal, composition only) and the shapes accepted. `scripts/test-gate-status.sh` goes from 141 to 176 tests: a real `\r` in the CRLF case, `(FP3)` and `(fp3).x` cases, a non-writer shape loop that also asserts `--mark-stale` sends nothing, the two Stale texts, the stub's GNU-only `sed -i` replaced by a temp file and `mv`, a `withjudged` comment fix, and 12 new mutants (the tag cut at the first `(fingerprint `, catch-all arm, widened and dropped untagged arms, uppercase tag, unanchored end, tag changed alone, deleted `tr -d '\r'`, both Stale-text branches, the trailing `now` clause).
- **A black-box tier probe for `api-security-tester` is pre-registered** (#292, fixture files only, no
  component or plugin change). `scripts/fixtures/tier-probe-security-tester/` holds a small HTTP
  server with three planted issues (SQL injection, an IDOR on `/orders/<id>`, and a tier-gating
  bypass on `/admin/users`), a fixed twin, and a reference test that fails on all three against the
  seed and passes against the fix. Its README records the pass criterion and the pinned prompt
  before any run, so this commit is the pre-registration the six runs are judged against.
- **`check-contributor-docs.sh` trims trailing punctuation through one helper, and four round-2 Lows from #299 are closed.** The five copies of the trailing-punctuation trim collapse into one `trim_punct`; the lifecycle row prints the word as written rather than trimmed; the `none "yarn install."` assertion that could not fail now reads `none "yarn install"`, which kills the classic-yarn mutant; and npm and pnpm share their twin cases. No new pass or fail row appears on any of 59 edge inputs, only referred rows becoming silent (#326, `check-contributor-docs.sh` v4, `scripts/test-check-contributor-docs.sh` 206 to 225 tests, forge-kit-governance 0.28.4).
- **The roadmap reshape suite now proves a flagged merge never re-reads under `--check`.** A new case runs `merge Alpha --into Beta` with open ticket #10 in Alpha, asserts the `--check` run absolutely (exit 0, empty stderr, the "would confirm" line, no host write, every read scoped to `FORGE_DRY_RUN=0`) and compares the `FORGE_DRY_RUN=1` run against it, so dropping `confirm_emptied`'s early `--check` return now fails 8 cases where it passed all 152. `test-check-phases.sh`'s `absent_line` matches literally (`grep -qF`) with its own probe, and the failed-read case says why B planned with an open milestone is consistent (#336, `scripts/test-reassess-phases.sh` 152 to 164 tests, `scripts/test-check-phases.sh` 76 to 78).
- **Rule 1's "the rejected write" is now introduced before it is referred to.** The host-divergent paragraph of ticket-standards said a wire-form divergence "adds no error of its own: the rejected write is the same event on both hosts" before anything had said which write is rejected. It now reads "when a host rejects the write its branch sends, that is the same event on both hosts, so the negative is that rejected write", which names the write and whose it is first. The rc 44 and rc 1 per-host codes, the rc 2 `forge-lib` refusal and the absence of the word "shared" from the paragraph are unchanged. Rules text only, so `doc-rules-version` goes 19 to 20 and `template-version` stays 6; this supersedes the #325 phrasing, and the #325 entry stays as history (#337, `docs/guides/ticket-standards.md`).
- **A non-UTF-8 `--title`, `--description` or stdin body no longer truncates what `memory.py write` owns.** The helper opened the index and the memory file with `"w"` and only then hit the encode error, so a bad title emptied `MEMORY.md`, a bad description or surrogateescaped stdin body left an owned memory file at 0 bytes (locking it out of `write` and `remove`), and a bad stdin body under a strict UTF-8 locale raised a traceback. `cmd_write` now probes each field after `check_ownership` and before any write, reads stdin as bytes and decodes it strictly, and refuses through `_refuse` naming the field (`--title`, `--description` or `stdin`) without echoing the value, leaving every file untouched. `closing-sessions` goes to version 6 and its SKILL.md refusal paragraph names the new case. Eight new tests in `scripts/test-closing-sessions-memory.py` (40 to 48), whose `run` and `_refused` helpers gained a bytes body and a locale-clean `env`, with eight mutants killed (#341, `plugins/forge-kit-governance/skills/closing-sessions/scripts/memory.py`, `plugins/forge-kit-governance/skills/closing-sessions/SKILL.md`, `scripts/test-closing-sessions-memory.py`).
- **`test-forge-lib.sh` pins the flag-off side of `forge_milestone_close`, the ninth `FORGE_DRY_RUN` guard** (#319, `scripts/test-forge-lib.sh` and a comment in `scripts/test-sync-phases.sh`, test-only, no `forge-lib.sh` change, no marker bump). Both guard mutants (`[ -n "${FORGE_DRY_RUN:-}" ]` and `[ "${FORGE_DRY_RUN:-0}" != 0 ]`) passed every assertion, because `mc_run` could only leave the flag unset or export 1. `mc_run` now also takes `=<value>` (exports that literal; `0` stays unset, `1` stays 1) and an `MC_LIB` override, and new cases drive an explicit `0`, `true` and the unknown title under `0`, asserting rc, the `PATCH /repos/o/r/milestones/7` line and no `[dry-run]` text. An in-suite ledger reuses #334's `dr_mutant` on `forge_milestone_close`: the `-n` form dies at `0`, the `!= 0` form survives `0` and dies only at `true`. The `test-sync-phases.sh` mutant list now names the dry-run close case as also killing the unscoped-clear mutant, with the `git init` copy requirement. Suite: 357 tests before, 375 after. The ledger counts a kill only on a clean dry run (rc 0, no GET, exactly the dry-run line), so a crashing mutant is not credited, and the suite unsets `MC_LIB` on entry.
- **CI now runs `scripts/test-reassess-phases.sh`.** It was the one contract suite under `scripts/` with no step in `validate.yml`, so a regression in `reassess-phases.sh` could reach `main` with every check green (the pre-push hook runs suites only to compare their counts, never their verdict). The new "Roadmap reshape tests" step sits with the other roadmap suites; the guard that would stop a future suite going unwired is #348 (#344)
- **ticket-gate Step 5 posts through `forge_issue_comment` instead of `gh --body`** (`ticket-gate-version` 63; the step is now headed "Post the review", naming no host). The review is written to `$D/review.md` and posted in ONE Bash call that locates forge-lib itself, because shell state does not persist between calls: Step 1 now persists the raw checker path to `$D/mech`, and Step 5 tries `FORGE_LIB`, then the checker's own directory, then the relative `forge-kit-devops` path, then a `find ~/.claude/plugins` fallback restricted to `forge-kit-devops` copies and chosen by the highest `forge-lib-version` marker (Step 1's #189 rule), so a foreign marketplace's `forge-lib.sh` is never sourced. An unresolvable forge-lib exits 2 with "review NOT posted" and never falls back to bare `gh`; a failed post exits 2 before Step 6, so no `gate-verdict` points at a missing review. The review reaches `gh` as a `jq --arg` value and then on stdin, which removes the per-run improvised transport and the snap-confined `gh` private `/tmp` failure. The preamble's legacy `gh` fallback now excepts Step 5. The change is word-neutral against the 5754 ratchet: duplicated sentences were cut where the rule survives elsewhere. Follow-ups are #347 (#283)
- **`refocus --prose --plan` no longer half-writes the roadmap.** `reassess-phases.sh refocus <phase> --prose TEXT --plan PATH` no longer leaves the roadmap half changed when the plan cannot be set: `op_refocus` now dry-runs `roadmap_set_prose` and then `roadmap_set_plan` on a scratch copy under `${TMPDIR:-/tmp}` before its first write, so a refusal (two column-0 `plan:` lines, a plan path the parse-back rejects, prose opening a `## ` section) exits 5 with the roadmap byte-identical, and `--check` now refuses identically instead of exiting 0. The library is its own oracle, so no refusal condition is copied into the script. The copy is removed by an EXIT trap set before it exists; a missing or unusable `TMPDIR` refuses the refocus whole (exit 5, "nothing written"), including a prose-only refocus. `reassess-phases` marker 2 to 3, forge-kit-roadmap 0.15.0 to 0.15.1; `test-reassess-phases` goes from 104 to 152 tests, covering both writers, `--check`, a missing `TMPDIR` and a no-leftover check (#328)
- **contributor-docs refers a row rescoped by an exported npm_config_ variable or a `$(...)`
  assignment value** (#296, check-contributor-docs v3, contributor-docs v3). An `export`,
  `declare -x` or `typeset -x` of a `NAME=value` whose NAME starts with `npm_config_` (any case, any
  key, an empty value too) now refers every later runner of the same fenced block or code-span
  paragraph, and a later segment of its own line, folded into the existing assignment bit so
  `why_cd` and `judge_script` are untouched. `export FOO=1` and `export NODE_ENV=production` still
  fail. A `NAME=$(...)` value with non-nesting parentheses is rewritten to a plain assignment at the
  start of a word before the split, so `npm_config_workspace=$(echo client) npm run dev` refers
  while `echo $(date); npm run nope` and `--workspace=$(...)` keep their rows. Stated limits: a
  prose export does not carry into a following fence, plus nested-paren and backtick values,
  `pnpm_config_*`, `JUST_*`, `unset`, `set -a`, `env VAR=... cmd` and a tracked `.npmrc` (#339). The
  suite goes from 157 to 206 tests (25 cases and 24 mutants, including `declare -x`, `typeset -x`
  and a `pwned` non-execution guard); the `c_env_prefix` and `c_cd_other_fence` mutant anchors are
  rewritten. Passes under gawk and mawk.
- **`test-forge-lib.sh` pins the flag-off side of eight more `FORGE_DRY_RUN` guards** (#334, `scripts/test-forge-lib.sh`, test-only, no `forge-lib.sh` change). The library's contract is that only the exact value 1 is a dry run, but at HEAD 17 of the 18 guard mutants (`[ -n "${FORGE_DRY_RUN:-}" ]` and `[ "${FORGE_DRY_RUN:-0}" != 0 ]`, nine guards) passed every assertion, so a caller that restored the flag to 0, as `sync-labels.sh` does, could have been turned into a silent no-op that returns 0. A table-driven section now drives `forge_api`, `forge_api_paginate`, `_forge_region_write`, `forge_body_compose_preserving`, `forge_issue_edit`, `forge_issue_list`, `forge_issue_label` and `forge_issue_milestone` under `0`, `true` and `1`, and an in-suite ledger rewrites each guard with a function-scoped `awk` on a scratch copy, proving the `-n` form dies at `0` and the `!= 0` form dies only at `true`. `forge_milestone_close` stays with #319. The stale "six sites" comment is corrected to nine guards. Suite: 279 tests before, 357 after.
- **gate-status tags the fingerprint algorithm in the stamp, and two test probes stop counting crashes
  as kills** (#330, gate-status v4, forge-kit-governance 0.28.0). The stamp is now
  `Judged body: sha256:<16 hex> (fp3). Full review: <url>.`; the tag follows the hash so every v1 to
  v3 reader (keyed on `^Judged body: sha256:`) still compares the hash, unstamps and re-stamps the
  line, and only an older reader cannot name an algorithm change (where it altered a body's hash it
  reads plain `stale`, otherwise it reads by hash alone). A tagged stamp whose tag differs from
  `FP_TAG` reads `stale round <R> <VERDICT> (fingerprint <old>, now <current>)`; an untagged stamp
  behaves exactly as before, so no stamped ticket changes state; a malformed tag (anything but 1 to
  16 of `[a-z0-9]` in parentheses after a 16-hex hash) reads `unrecorded`. A golden fingerprint pin
  fails the suite when `fingerprint()` changes without a tag bump. `probe_nobl` and `probe_retry`
  now count a mutant as dead only on a non-zero exit AND the expected stderr (`author section
  changed`, `could not move`), each proven by a crash mutant. The header, `without-claude-code.md`
  and `gate-staleness.yml` now say "non-blank text of an author section". `scripts/test-gate-status.sh`
  87 to 141 tests; the four touched suites otherwise unchanged (check-ticket-mechanics 139,
  forge-gate-mechanics 34, count-gate-rounds 69 in the clean worktree).
- **test-roadmap-lib.sh pins test 8's whole file and runs test 7 under a BSD-style paste shim**
  (#316, test-only, no component or plugin version change). Test 8 now `cmp`s the whole file, so
  `set_prose`'s emit of two blanks before the next heading dies on `FAIL: 8.` directly; test 7 runs
  `paste -sd'|' -` under a PATH shim that refuses a missing operand like BSD paste, so the
  portability defect is checkable on Linux; test 6's pass label carries `$n`; the ENVIRON assertion
  counts uses per primitive (four in `roadmap_set_prose`, two in `roadmap_insert_at`) rather than
  lines, with the count piped through `tr -d ' '` for BSD `wc`. Two comments that misstated which
  tests fail on v5 and which assertion pins test 5's fix are corrected, and the mutant ledger's
  headline count is now thirty-nine. The suite total goes from 166 to 169. Passes under gawk,
  mawk and busybox awk.
- **`closing-sessions` `memory.py` refuses a read-only `MEMORY.md` before it changes anything,
  and the strict-decode switch is pinned from both sides** (#329, closing-sessions v5,
  forge-kit-governance 0.27.1). With the index at mode 0444, `write` left a memory file with no
  index line and `remove` deleted the file but kept its index line, each ending in a
  `PermissionError` traceback. `check_ownership` now probes the index with a non-truncating
  `os.open(O_WRONLY|O_NOFOLLOW|O_NONBLOCK)` (the effective uid, as `write_index` uses; not
  `os.access`, which tests the real uid) and refuses with `.claude/memory/MEMORY.md is not
  writable`. Its docstring now says what the check does not cover: a race between check and write,
  ENOSPC or a network filesystem can still leave partial state, because the helper is not
  transactional. A new test pins that an owned memory file holding a non-UTF-8 byte is still
  overwritten and removed, which an all-strict decode had passed silently. The suite grows from
  37 to 40 tests (`scripts/test-closing-sessions-memory.py`).
- **test-check-contributor-docs.sh: `c_escape` no longer depends on access times** (#305,
  test-only, no component or plugin version change). The outside sentinel is now a FIFO with a
  parked writer, so any read of it is observed directly by a bounded probe, and a watchdog
  releases a second opener rather than letting the suite hang. A `noatime` or `relatime` mount
  can no longer turn the escape check into a false green. The suite stays at 157 tests.
- **`forge_issue_milestone`'s digit gate is now pinned by its own stderr line, and its
  unreachable `|| return 2` is gone** (#257, forge-lib v30, forge-kit-devops). The `abc` case
  discarded stderr, so rc 2 from either guard satisfied it; the null and `abc` cases now assert
  `is not a number: <token>`. The `jq -nc --argjson` guard could never run (a digits-only token
  always parses on jq 1.7), so it is removed and the digit gate is documented as the sole guard.
  The host capture's position above the dry-run block is recorded (#256 AC4) and pinned for both
  the set and clear forms. No caller change.
- **Host-divergent wording in ticket-standards rule 1 no longer reads as self-contradicting**
  (#325, doc-rules-version 18 to 19; supersedes the #255 wording "its negative is the shared
  write failure taken through that host's branch"). The paragraph said a wire-form divergence "has no
  host-specific error" while its example gave a different code per host. It now says the
  divergence adds no error of its own, its negative is the rejected write asserted with the code
  each host's branch returns (rc 44 on Forgejo, rc 1 on GitHub), and the unknown-title refusal
  (rc 2) is raised by `forge-lib` itself before the write is sent, so it is identical on both
  hosts. The word "shared" no longer appears in the paragraph. The #255 entry stays as history.
  `template-version` is unchanged; no component or plugin version change.
- **sync-labels' dry run says what it would do, not what it did** (#323, sync-labels v10). Under
  `FORGE_DRY_RUN=1` the final line claimed `synced from ... (N created, M updated)` although nothing
  was sent. It now reads `dry run, nothing sent to <repo>; would create N, would update M (from
  <labels file>).` Only the exact value `1` is a dry run, as everywhere else in forge-lib; a real run
  prints the same line as before.
- **The tier-probe fixture no longer overclaims** (#318, fixture files only, no component or
  plugin version change). `server_fixed.py`'s docstring said "nothing else changed", which was
  false (the fix also adds the `hmac` and `os` imports); it now says "see README for what
  differs". The fixture README's sentence on the unplanted weaknesses read as a complete list
  while omitting plaintext token storage; it now says "for example" and names it. `server.py`,
  the file the measured agents read, is byte-identical.
- **A dry run of check-phases.sh and reassess-phases.sh now reads the real host** (#306,
  check-phases v6, reassess-phases v2, roadmap-phases v11). Both
  scope `FORGE_DRY_RUN=0` to each list read, as #269 did for sync-phases.sh, because forge-lib
  returns `[]` under the flag: a flagged check-phases.sh reported false rule 3 findings and a false
  clean for rules 1 and 4. `FORGE_DRY_RUN=1` now behaves as `--check` in reassess-phases.sh, so a
  flagged `delete` of a phase holding open tickets exits 5 with the roadmap untouched instead of
  rewriting `docs/roadmap.md`. Both suites model the flag in their stubs, log the flag each list
  call saw, and compare stdout, stderr and exit code separately.
- **forge-lib refuses an invalid `FORGE_HOST` instead of reporting success** (#256, forge-lib v29,
  forge-host v31). `forge_host` prints nothing for an invalid host, and every consumer that matched
  its output with a `case` fell through, so the writers returned 0 having sent nothing. Each one now
  captures the host and returns 2, with the one `forge_host` line on stderr, and the check sits above
  every dry-run guard, so `FORGE_DRY_RUN=1` refuses too. `forge_ci_status` answers `not_configured`
  with rc 0 (its documented "could not ask" word), the `detect` CLI exits 2, and `forge_tag_exists`
  returns 2, meaning "could not ask", not "tag absent". Valid hosts are unchanged.
- **ticket-standards.md cites the gate checker by its catalogue name** (#322). Precedence items 3, 7,
  8 and 10 named `check-ticket-mechanics.sh` by bare filename, which `check-doc-drift.sh` cannot
  resolve, so a change to the checker never flagged those four claims. They now read
  `check-ticket-mechanics`, and a checker change reports all four. No `doc-rules-version` bump: no
  rule changed.
- **`gate-status.sh --stamp` no longer refuses a clean body** (#312, gate-status v3). The fingerprint
  collapsed runs of blank lines to one but still told "no blank" from "one blank", so a body with
  the version marker directly above a heading changed shape when the stamp padded a blank in, and
  the first `--stamp` reported an author edit nobody made. The fingerprint now drops every blank
  line. Upgrade note: every stamped ticket reads `stale` immediately after this change (the state
  is recomputed on each read) and, where `gate-staleness.yml` is installed, gets its STALE mark
  written on its next edit event; this is deliberate and fail-closed, with no legacy-hash
  comparison kept. Re-run `/gate-ticket <N>` on each, never a bare `--stamp`, which would certify
  unreviewed text as current. A stamp is comparable only under the same algorithm, so, where
  `gate-staleness.yml` is installed, one written by a checkout whose fingerprint algorithm differs
  from the default branch's is marked STALE on its own stamping edit. An edit that only
  adds or removes blank lines, inside a code fence included, no longer makes a verdict stale.
- **closing-sessions' `memory.py` refuses targets it cannot own safely** (#314, closing-sessions
  v4). A slug is now plain ASCII (letters, digits, `.`, `_`, `-`), so a non-ASCII slug can no
  longer fold into another through `lower()` (the Kelvin sign); uppercase stays accepted. A target
  that is a directory, a symbolic link (dangling or live), a FIFO or any other non-regular file, or
  one it cannot read, is refused with a reason instead of a traceback, opened with `O_NOFOLLOW` and
  re-checked after opening. The `MEMORY.md` index gets the same checks before anything is written,
  and a non-UTF-8 index is refused rather than leaving a memory file with no index line.
  `scripts/test-closing-sessions-memory.py` grows from 26 to 37 tests.
- **forge-adapt's Step 1 host probe decides by URL authority** (#215, forge-adapt v69). It used the
  pre-#212 globs, which read `https://evil.internal/x/y?z=@github.com/` as github and four genuine
  GitHub spellings (`https://github.com:443/o/r`, `ssh://git@ssh.github.com:443/o/r`,
  `github.com:o/r`, `https://GitHub.com/o/r`) as forgejo. It now runs the public `forge_host` in a
  subshell, resolving forge-lib itself (`$FORGE_KIT_DIR`, then the marketplace checkout, then
  `~/forge-kit`) because Step 1 runs in a fresh shell, with a sentinel `FORGE_API_URL` so any
  non-GitHub remote reads as forgejo. It prints `forge-host: <host>`, and a warning when it must default
  to github. Behaviour change: an existing `.forge.conf` or exported `FORGE_HOST` now wins over the
  remote at install time. The dead `CURRENT_REPO` and `REMOTE_URL` are gone and the template-version
  read uses the resolved path. New suite `scripts/test-forge-adapt-host.sh`. adapt shrinks 7206 to
  7199 words and its size baseline is lowered to match.
- **`sync-phases.sh` no longer claims writes a dry run did not make** (#307, sync-phases v7). Under
  `FORGE_DRY_RUN=1` the summary said `created milestone` and `closed milestone` although nothing was
  sent; it now says `would create milestone` and `would close milestone`. A real run is unchanged,
  only the exact value `1` counts as a dry run (`true` is a real run, matching forge-lib), and a
  failed write still exits 4 with no success or `would` line. `scripts/test-sync-phases.sh` grows
  from 59 to 85 cases.
- **contributor-docs resolves bare yarn scripts and workspace-scoped commands** (#299,
  check-contributor-docs v2, contributor-docs v2). `npm -w`/`--workspace` and `pnpm --filter`/`-F`
  with `run X` now resolve against the one tracked manifest of that name and fail when it lacks X;
  `yarn X`, `yarn run X` and `yarn workspace <name> [run] X` pass when the script is defined and are
  otherwise referred, since yarn falls back to a binary. A Yarn Classic built-in (`yarn check`) is
  referred even when the root defines it, including with trailing punctuation (`yarn check.`).
  Ambiguous or unmatched workspace names, globs, selectors and paths stay referred.
- **Host-divergent conditions in ticket-standards rule 1** (#255, doc-rules-version 17 to 18).
  A condition whose behaviour differs by forge host is one independent condition per branch, each
  with its own positive and its own failure negative; a pure wire-form divergence takes the shared
  write failure as that host's branch reports it, and the value never sent goes in the Positive's
  Then. Worked example: `forge_issue_milestone`. `template-version` is unchanged.
- **`roadmap_set_prose ""` is a fixed point** (#270, roadmap-lib v6). Empty prose used to emit a
  leading blank, an empty prose line and a trailing blank, so a keyed-only phase block gained blank
  lines on every call and the no-op short-circuit never fired. Empty prose now has one canonical
  shape (no prose lines, one blank before the next heading, none at EOF), which
  `roadmap_insert_at` also writes. A file whose last line has no final newline is normalised once
  and is a fixed point after that.
- **`FORGE_DRY_RUN` and reads, corrected** (#254, #269). The v0.7.0 line "`FORGE_DRY_RUN=1` fakes
  writes only, never reads (#268)" described the docs, not the library: `forge_api` short-circuits
  every method under the flag, GET included, so a read returns an empty result. `sync-phases.sh`
  now scopes a clear of the flag around its own milestone read, so a dry run no longer reports
  existing milestones as missing; `forge_milestone_close` decides the dry run before it resolves
  the title (forge-lib v28), so a dry-run close returns 0 instead of 2.

## v0.7.0 (2026-09-24)

Five phases since v0.6.0: the leak guard's edge cases closed one by one, the forge adapter and the
roadmap gained the write halves they lacked, the gate verdict moved to where readers look, and every
model tier and thinking effort in the kit became a decision with a reason and a check. The
AI-assistant files stopped being published, and the repository history was rewritten to purge
them; the commit shas cited in plans were re-pointed (#232).

### Added

- **Model and effort by role** (#250, #251, #253, #279). Every agent declares a model and an effort
  for its role: judgment and security roles `inherit`, bounded analysis and mechanical roles a named
  `sonnet` at a lower effort. Every dispatch with no frontmatter behind it names its model.
  `docs/guides/model-tiers.md` holds the one table of allowed ranges, and `validate-plugins.sh`
  check 7 fails a component or a dispatch outside it. Grounded in a probe of the installed CLI
  (#252): `effort:` is honoured on agents, a dispatch site's model beats the agent's, and a skill or
  command tier binds only on a slash invocation.
- **`/full-review` sizes each round** (#278, `review-sizing`). A small range touching no sensitive
  path runs `code-reviewer` alone instead of five phases; `--full` overrides.
- **`scripts/measure-dispatch-cost.py`** (#280). What each subagent dispatch cost, in turns as well
  as tokens, read from Claude Code's own transcripts. #289 used it to re-measure the security roles
  on a planted seed (`scripts/fixtures/tier-probe-security/`). Neither role moved: Sonnet found
  every planted issue and cost more.
- **forge-adapt keeps the tier on copy** (#281). `refresh <name>` reports each tier key an
  installed copy holds differently, and keeps the project's value.
- **The gate verdict sits at the top of the body, stamped** (#284, #285). `gate-status.sh --stamp`
  records a fingerprint of the author's text, and `--mark-stale` flags a verdict the author has since
  edited past. `count-gate-rounds.sh --memory` restores the blocking items (#196).
- **Write halves for the forge and the roadmap.** Body-region primitives let three writers share
  one ticket body without clobbering each other (#248, #262). `forge_issue_milestone` (#245).
  `roadmap-lib.sh`'s write primitives (#246), and on top of them `/phase review` (#244) and
  `/phase reassess` (#249).
- **`scripts/check-doc-drift.sh`** (#247, #258). Reports which documents a range of commits made
  stale; it never fails. Exemptions are anchored on text, not line numbers.
- **The leak guard's private half can skip paths**, in the tree modes and under `--history`
  (#225).

### Changed

- **The AI-assistant files are local**, not published. The suite counts CI can no longer see are
  checked by the pre-push hook instead of by a CI step that could not fail (#218).
- `/phase` and the forge adapter keep the ordinary end of a list quiet unless `FORGE_DEBUG=1`
  (#236). The leak guard's own examples are placeholder shapes, so a host project's guard does not
  fire on them (#223).

### Fixed

- **The leak guard**:
  - `--history` reads every ref a mirror push sends, `refs/original` and `refs/notes` included
    (#210).
  - Rule C is linear in the line length (#211).
  - Each of these false positives and allow-file gaps is closed: #224, #227, #230, #238, #239 and
    #240.
  - The guard runs once here, from the asset, and a `scripts/` copy of a shipped asset fails the
    build (#231).
- **The forge adapter**:
  - Pagination stops on a repeated page (#228).
  - A write to a missing issue says so (#229), and the message survives a `set -e` caller (#237).
  - `forge_repo` parses the slug after the host (#216) and refuses an scp remote whose path
    carries an `@` (#235).
  - `FORGE_DRY_RUN=1` fakes writes only, never reads (#268).
- **Ticket mechanics**: check 4 refers a one-line scenario and a reasoned N/A rather than failing
  them (#233, #241).
- **Test isolation**: no roadmap or forge-adapter suite can reach the live forge, and their temp
  directories cannot leak (#287, #288).

## v0.6.0 (2026-09-16)

Five overnight and daytime phases from the #191 decision brief onward: the leak guard reads
history, the numbers in the prose are generated, the tree modes fail closed, the area set travels,
and the forge adapter decides the host by URL form. Shipped without a Mac: the macOS claims are
verified against Apple's awk source and bash 3.2.57 built on Linux, and the README says so.

### Added

- **`--history` for both leak-guard scanners** (#191, forge-kit-security 0.10.0). Reads the
  publishable history (every blob a branch, tag or remote-tracking ref reaches, every commit and
  tag message) through one `git cat-file --batch` stream and a POSIX awk reader that COUNTS each
  object's declared bytes, so a blob forging a batch header hides nothing, and that puts no content
  or path byte through a regex, because Apple's awk aborts on a byte over 0x7F the moment a regex
  meets it under a C locale. An object is scanned unless EVERY path it ever had is skipped; the
  path map is pinned with `git -c` overrides against user config that reshapes `--raw` output and
  refuses a filename with a newline. Refuses alternates, `GIT_OBJECT_DIRECTORY`,
  `GIT_ALTERNATE_OBJECT_DIRECTORIES`, partial clones, grafts, an object git cannot read and any
  failed pipeline stage; ignores `refs/replace`. Evidence is redacted by default (`--show-evidence`,
  `--show-names`); `--orphans` opts in to what no ref reaches. Never wired into a hook. Two review
  rounds found five ways a reachable leak became a silent exit 0 before it shipped, all inputs the
  tool does not control; the suites carry a mutant with the reader's `r<0` gate removed.
- **`scripts/update-suite-counts.py`** (#201). CLAUDE.md states a count for every contract suite
  and three were stale when the ticket was filed; the numbers are generated from the suites' own
  printed totals now, `--check` fails the build on a stale one, and a suite that cannot run refuses
  rather than writing a zero. The spelled-out counts the generator cannot anchor came out of the
  prose instead (#202, #203).
- **`check-ticket-mechanics.sh --labels-doc`** (#204). The first column of the project's own
  `docs/guides/labels.md` area table REPLACES the compiled-in nine, passed by both callers, so a
  project that declares `protocol` as its area satisfies check 2 with `protocol` alone. An absent
  doc keeps the default; a present doc with no readable table refers rather than silently widening
  back. `check-label-taxonomy.sh` keeps the two table reads byte-identical. Nothing installs the
  doc yet (#214).

### Changed

- **The leak guard's prose now says that history is two sets and a push sends only one** (#198,
  from the #191 decision brief). What the pushed refs reach is what `git push` packs; an object
  orphaned by `commit --amend` stays on the machine (tested), and only a copied `.git` ships it.
  The pre-publish prune step is given with its scope: local orphans only, before the first push,
  removes nothing from any copy or host already holding the objects. Both scanner headers gain the
  `grep -a` trap for anyone reading a `cat-file --batch` stream by hand, stated as the two failure
  shapes it actually has rather than the one first observed through a `-I` wrapper.

### Fixed

- **The leak guard's tree modes fail closed** (#208, P1, from the #191 security audit). A
  renamed-and-edited file was status R and listed by nothing (`--no-renames --diff-filter=ACMT`),
  a staged path shaped `0:x` was read by `git show ":$f"` as a stage spec, a file named `-v` was an
  option and `-` was stdin, and a temp directory, names file or blob that could not be written, or
  a tracked file the process could not open, each continued and reported clean. Each is exit 2
  naming the file, never `$TMPD` and never the script's path, even for a child killed by a signal.
  A tracked symlink is scanned as its link text under `--all` (it was followed), and only a blob
  is shown (a gitlink whose commit is present was scanned as text).
- **The private half drops a listed owner name only where its rationale is true** (#209): in the
  tree modes and only when origin's host is exactly `github.com`, `gitlab.com`, `codeberg.org` or
  `bitbucket.org`, parsed by URL form; never in `--history`, and never on a private forge, which
  is exactly where a private organisation name must be caught. `2222` in `host:2222/` is a port,
  not the owner. The list path shows as `~` in every message on every bash.
- **Four checker gaps found gating twelve tickets downstream, and a fifth found under Apple's awk**
  (#205, check-ticket-mechanics v8). The evidence row was cut at 160 bytes (a 248-byte label list
  lost its tail; the bound is 1000 with a count prefix), a Positive/Negative marker with a
  qualifier or in bold read as no block (one marker regex shared by every site, which refuses a
  prose line that merely starts with the word), a template renaming its E2E section got
  `referred` forever (roles resolve by pattern in priority order, id before label), and a template
  whose `value:` or `placeholder:` carries `### ...` sub-headings ended a section at its own first
  line. The fifth: BWK awk refuses a `-v` value containing a newline, so on a Mac every section of
  every ticket had read as empty; the lists travel via `ENVIRON`. The busybox awk on the CI runner
  now runs the compliant body as a second-awk tripwire.
- **The reach sentences both leak-guard headers carry are pinned** (#199, #200): the `grep -a`
  rule, the history limit and its pointer, each through `--help`, one needle per sentence.
- **`forge_host` decides the host from the URL's authority, never from a glob** (#212, forge-lib
  v16). The old `*://*@github.com/*` `case` pattern let `*` cross `/`, so any URL with
  `@github.com/` in its path or query read as GitHub, and `_forge_token` had the same cut on the
  credential path (`FORGE_API_URL=https://evil.internal#@github.com` asked git for github.com's
  secret and sent it to evil.internal). Contract change: any URL whose authority host is
  `github.com` or `ssh.github.com` is GitHub now, including `ssh://git@github.com:22/o/r`,
  `github.com:o/r` and a port on the scheme form, which v15 answered `forgejo` when an API URL was
  set. The private leak scanner's owner parser gained the same authority cut.
- **The mechanical checks find a section at either heading level, bounded by labels rather than
  by a level** (#190). `gh issue create --body-file` produces `##` headings, and the checker, keyed
  on `### ` alone, read a doc-compliant `##` body as five absent sections where the same body at
  `###` got two and a referred: a heuristic miss that inverted the verdict instead of referring it.
  A first fix detected one level per body; the gate found `dep-auditor` emits `### Priority` beside
  `##` sections, which that rule inverted the same way. A section now runs to the next heading at
  its own level or the next heading that is a template label, so a `###` subsection is content and
  a `### Priority` beside it is a boundary. No content check moved. `forge-gate-mechanics.sh`'s
  never-template-shaped notice keys on the same signal, and the worked example in
  `without-claude-code.md` was re-measured: #182's documentation impact passes on content and its
  GWT fails on content.
- **The gate's provenance line says `mechanics: none` when nothing was found, prints the path
  relative to `~`, and the tie-break direction is stated** (#194). The line printed `mechanics:  ()`
  on the empty path, posted a home path into every review comment, and every description of the
  resolver said "path as tie-break" without saying which way; the `ROUND=` line shared the empty
  path and ran `./count-gate-rounds.sh`. A missing checker now makes the round `unknown`, the same
  as a counter that cannot run. `/phase` prints `none` the same way.
- **`adapt` no longer calls the plugin cache leaf `<sha>`** (#195); it is the plugin semver, as
  CLAUDE.md has said since it was probed. One token, word-neutral against the `adapt` ratchet.
- **Concurrent gate runs no longer share one body file by name** (#197). Step 1 writes the fetched
  issue to `<scratchpad>/gate-<NUMBER>/` and Step 3A refuses, posting nothing, when that file's
  `.number` is not the run's argument. Three runs in one session had read each other's bodies
  twice and were saved both times by a reviewer reading the evidence column.
## v0.5.0 (2026-09-11)

The release where the gate was pointed at the repository that ships it, and at itself. Twelve
gate runs across two phases found the label taxonomy blocking every ticket here, a resolver that
picked a stale copy of its own checker three runs in four, and a round counter that any body edit
reset to one. All three are fixed and the mechanical half of the gate now runs without Claude Code
at all. Minor rather than patch: two `forge-lib.sh` contract changes (v14 adds
`forge_issue_comments`; v15 makes `forge_ci_status` say `cancelled` and reserves `not_configured`
for "could not ask", which `release` acts on), two new shell assets, and a new guide for teams on
another agent or none. Ten tickets.

### Added

- **The mechanical half of the ticket gate runs without Claude Code** (#182).
  `forge-gate-mechanics.sh` fetches an issue through `forge-lib.sh` on either host, resolves the
  template directory, and hands both to `check-ticket-mechanics.sh`, which already had 41 contract
  tests. It never prints a verdict: Step 3A is the mechanical half, every `referred` row is a check
  that could not rule, and a summary saying PASS would look like the real gate with the reading half
  skipped.
- **`forge-gate-mechanics.sh` reports an unsynthesised body once rather than as seven failures**
  (#184). The gate's Step 0c synthesises the missing sections and writes the enriched body back to
  the forge BEFORE the mechanics run, so inside a gate run the checks always see template-shaped
  input and the blocking rule holds. A raw hand-filed ticket now opens with a `never
  template-shaped` notice and exits 0, because that shape is not a defect in the ticket. The shape
  needs BOTH signals, no marker AND no `### ` heading, since either alone is a different situation.
- **`docs/guides/without-claude-code.md`** (#183), the entry point for a team on another agent or
  none: the four portable artifacts, what to copy, what to run with real output, and a table of what
  is not available. `AGENTS.md` now distinguishes its two audiences rather than serving only
  contributors.
- **A finding names an instance, so `code-reviewer` sweeps for its family** (#187). Inside the files
  the diff touches, each instance is treated per the iteration contract's severity rule. Outside
  them, do not fix it **and do not confirm its extent**: naming a suspicion needs no scan, and
  establishing how far it reaches is the scan this agent does not do. The out-of-target list now
  exists in every round, not only round 2+, which is a gap the rule exposed.
- **The overnight loop asks whether a ticket is still true** before implementing it (#186), as a
  step 0 in the per-item pipeline. Implement or park, nothing else, and a PARTLY fixed ticket parks,
  because implementing only the surviving criteria is re-scoping. The check is specified as the Grep
  and Read tools rather than shell greps, and that is a security decision: `overnight-guard.py`
  matches its patterns inside a quoted search term, so a shell grep for a ticket quoting `git reset
  --hard` is denied and records a destructive-command deferral that never happened.
- **`scripts/check-label-taxonomy.sh`** (#188): one definition of the area label set, and a guard
  that fails when a copy disagrees. `ticket-gate.md` restates the set nowhere and the guard fails if
  a copy returns, because a synchronised copy is one edit from a drifted one. Three area labels now
  describe this repository's own work (`components`, `tooling`, `governance`), without which every
  ticket filed here blocked at the gate.
- **The gate counts its rounds from posted review comments, never from the issue body** (#192).
  `count-gate-rounds.sh` prints the round the next run should use, and `forge-lib.sh` v14 gains
  `forge_issue_comments` for it. The body's `gate-verdict` block used to carry the number, and any
  ordinary body edit erased it, so the gate believed every round was round 1: delta scope never
  engaged and a caller's trip wire, which counts rounds, could never fire. A stopping rule that
  cannot fire is worse than one that is absent, because it is believed in. The block is now a
  projection of the count, every review comment states its `**Round:**`, and 29 contract cases pin
  what counts as a round and what does not.

### Fixed

- **`forge_ci_status` on Forgejo tells a superseded run from a broken one, and a queued run from
  no CI at all** (#193, a downstream contribution). The combined commit status flattens a
  cancelled run to `failure`, so pushing twice in quick succession left a healthy branch red with no
  failing step anywhere: wrong on 23 of 39 red commits in the sample the ticket measured. The fix
  reads the per-job `description` Forgejo already returns ("Has been cancelled"), so the red path
  makes no second request and an unknown string falls to the old answer, never to a false green.
  The paginated `/actions/tasks` walk the downstream copy carried was not ported: under a
  server-clamped page it reported `cancelled` with a failure on the next page. `total_count == 0`
  is now `pending` or `none` rather than `not_configured`, which is reserved for "could not ask";
  `release` stops on `none` ("wait, or confirm there is no CI") and on `cancelled` ("re-dispatch"),
  and falls back to its local gate only when the forge could not be asked. `forge-lib.sh` v15,
  30 contract cases, ten named mutants killed.
- **A shipped asset is resolved by its version marker, never by the first `find` hit** (#189).
  `~/.claude/plugins` holds plugin versions side by side, so `find ... | head -1` returned an
  arbitrary copy, and on the filing machine three different ones in three consecutive runs, one of
  them stale enough to contradict #188 during a live gate. `ticket-gate.md` Step 3A, `/phase`, and
  the last-resort search in `check-phases.sh` and `sync-phases.sh` now prefer a project copy, then
  a forge-kit checkout's own tree, then the highest `<name>-version` marker with the path as
  tie-break, and every one of them prints the copy it chose. Two contract cases pin the shell half.
- **Both halves of the leak guard now state that they never look at history** (#185). Every mode
  reads the working tree, the index, or two endpoints of a range, so a leak committed once and
  removed later is unreached, which is exactly the going-public moment the component is named for.
  The private half had carried no reach statement at all. Both also say they read file content only:
  a commit message is unreached, and this repository's store holds 527 commit objects. The skill
  names `gitleaks` for the credential class, which this guard does not cover.

## v0.4.0 (2026-09-10)

The release where forge-kit stopped shipping other people's files. Five components here turned out
to be, after normalising away the name and the version marker, between one and ten lines from the
originals in `wshobson/agents`, which is where this kit's specialist agents came from. Eleven
components and one whole plugin group are gone, each naming its replacement, and a guard now fails
the build if another one appears.

The boundary that made those retirements obvious was itself only a paragraph in a skill until this
release. It is now checked twice: at build time by `check-neighbour-overlap.sh`, and at install time
by forge-adapt, which knows about both neighbours rather than only superpowers. The README was
rewritten around what the tree actually is, a governance harness for the outer loop, rather than the
component library it started as.


### Added

- **`scripts/check-neighbour-overlap.sh`**, which fails the build when a component here is the same
  file a neighbouring marketplace ships (#177). A DUPLICATE fails; a COLLISION, the same name with
  different content, is reported and never fails, because `code-reviewer` is a name anyone would
  pick. The threshold is measured rather than chosen: duplicates differ by 1 to 10 lines and the
  nearest genuine divergence is 103. Evidence lives in `docs/neighbours.tsv`, refreshed by
  `scripts/neighbour-manifest.sh --refresh`; the guard reads only the checked-in file, so CI needs
  no plugins installed.
- **The README names the plugin groups and how to install one.** A generated `plugin-catalogue`
  region gives one row per group: its semver, a copy-pasteable `claude plugin install` command, and
  the group's own description. Until now the install command for a group existed nowhere in the
  docs, so finding one meant reading `plugin.json`.

- **forge-adapt's coexistence rule covers both neighbours** (#179), in one tested script rather
  than a table in a skill. It returns `recommend`, `caveat` or `suppress` with a reason, judging
  the pair and never the name: `code-reviewer` exists on three sides as three different agents.
- **`validate-plugins.sh` fails a build where a component dispatches a `subagent_type` no agent
  provides** (#180). That failure is silent at runtime, and #178's retirement of six agents made it
  possible. Agent names stay unprefixed: Claude Code already namespaces subagent types by plugin,
  and the reason is recorded so the question is not re-asked.
- **The size report shows a line count beside the word count** (#176), marking anything over the
  500-line tip Anthropic states for a skill body. Reported and never budgeted: `adapt`'s 20 fenced
  blocks were classified first, and sixteen are commands the skill runs while four are templates it
  emits, so none of them can move without making the caller depend on a copy. The file is the size
  the work is, and the reasoning is in the guard rather than in a closed ticket.
- **The README was rewritten around what forge-kit actually is** (#181): a governance harness, the
  outer loop, with the three-way neighbour table, ten Given/When/Then scenarios, the overlap stated
  rather than discovered, and a real path for a team not using Claude Code.

### Removed

- **Eleven components retired, and one whole plugin group** (#178), because each was the same file
  `wshobson/agents` ships and forge-kit had not changed it. `forge-kit-backend` is gone entirely
  (`api-design-principles`, `architecture-patterns`, `cqrs-implementation`,
  `microservices-patterns`, `saga-orchestration`); so are `tdd-orchestrator`, `test-automator`,
  `performance-engineer`, `backend-architect`, `backend-security-coder` and `/pr-enhance`. Every
  one names its replacement, all of them in `claude-code-workflows`. There is no deprecation field
  to use: probed on 2.1.267, both `deprecated` and `supersededBy` are unknown fields that Claude
  Code ignores at load time and that our own zero-warning rule would then break, so the mechanism
  is this entry, the group descriptions, and forge-adapt.
- `architect-review` STAYS, allowlisted with its reason: `/full-review` dispatches it by name, and
  pointing that at a plugin we do not ship would fail silently when it is absent.
- `mutation-sweep` survives its group-mates. It has no counterpart anywhere and is a quality gate
  rather than a way of working.

### Fixed

- **The README's headline described the pre-#166 install model.** "Rewritten for your stack, not
  copy-pasted" holds only for a bare-clone install or a `scope: project` component, and there are
  none: with a marketplace present, every user-scoped component is REGISTERED. The pitch, the
  four-step summary and the worked example now say what actually happens.
- **"Keeping up to date" promised an auto-update that does not exist**, which was the half of #172
  documented in `adapt/SKILL.md` and never in the README. It now states that registration tracks
  the repository but pulls nothing, names both commands, and carries the dependency upgrade note.
- Smaller README corrections: the gate example cited template v5 (v6 today), the contributions
  section used forge-adapt v1 phase numbers, and the labels row did not mention that
  `sync-labels.sh` is what puts the taxonomy on the host.
- `forge-kit-roadmap`'s manifest described itself as self-contained while depending on
  `forge-kit-devops`.

## v0.3.0 (2026-09-10)

The release where the kit measured itself against the tooling Claude Code now ships, and mostly
kept its own. Three comparisons came back the same shape: the first-party check validates less
than its help text suggests, so `plugin validate` accepts a dependency that then installs
silently, `plugin details` does not charge an agent for what it preloads, and `plugin tag`
validates an agreement this repo's manifests cannot even express. Nothing was replaced; three were
kept with the reason recorded where the next reader meets it, and two became real work.

The other half is the handover. The overnight loop now defers on the trip wire instead of deciding
for the absent human, and `decision-brief` is the artifact that deferral produces.

### Added

- **Cross-group dependencies are declared in `plugin.json`, not only in prose** (#169). Installing
  `forge-kit-roadmap` alone now brings `forge-kit-devops` with it, probed on CLI 2.1.267. The
  declaration lives in two places on purpose: the manifest for the marketplace path, the prose for
  the bare clone, where nothing resolves anything. `validate-plugins.sh` checks what the CLI does
  not, because an UNRESOLVABLE dependency passes `claude plugin validate` and then installs
  silently, with no dependency line and no error.
  **Upgrade note:** resolution happens on INSTALL, not on UPDATE. If you already had
  `forge-kit-governance` or `forge-kit-roadmap` and you `claude plugin update` it, the group
  reports `failed to load` until you run `claude plugin install forge-kit-devops@forge-kit` once.
  The error names that command. Found on the maintainer's own machine within the hour, because a
  fresh-install probe cannot see the upgrade path.
- **Every `plugin.json` carries an `author`** (#173), so the advisory `claude plugin validate` step
  reports zero warnings instead of eight nobody read. A handle and its profile URL, no email
  address: the handle is already public in every clone URL, and an address cannot be recalled from
  a public history. `validate-plugins.sh` requires the field, in the CLI's own shape (an object
  with a non-empty name), so a new group cannot be born without it.
- **`scripts/check-reference-depth.sh`**: a skill's `references/` file must be named by its own
  `SKILL.md` (#175). The rule is Anthropic's and its reason is mechanical: an agent meeting a
  reference inside ANOTHER reference may preview it rather than read it whole, so it acts on half a
  file and nothing reports that it did. Three files in this tree were already unreachable, one of
  them the exact nested shape the guidance describes.
- **`scripts/test-validate-plugins.sh`**: the kit's oldest structural guard finally has a contract
  test, created because two tickets needed to add rules to it in the same week.
- **The size guard measures the ALWAYS-ON cost** (#174), the description every session pays for a
  component it never invokes. Reported and not budgeted, because a description that is too short
  stops the component being found; what is enforced is the floor, an agent or skill with no
  description at all. The tree went 14,711 to 12,339 characters of description with all 48 quoted
  trigger phrases intact, by deleting sentences that described how a component works and that its
  own body already said.

- **`decision-brief`, a skill for the ticket that is stalled on a human rather than on work**
  (#129). It re-gates the ticket against the CURRENT standard rather than citing a stored verdict,
  checks the ticket's claims against the tree before presenting anything, classifies what is
  actually being decided (including "no decision needed", which is a real outcome), costs the
  options with measured numbers, and REWRITES the issue body behind a dated preamble rather than
  leaving the analysis in a comment nobody opens while triaging. `check-restatements.sh` scans its
  file, so its promise to run the gate rather than copy the gate's bars is a build failure rather
  than a sentence.
- `forge_issue_edit <n> <body>` in `forge-lib.sh` (v13), the library's first body write. Both hosts
  PATCH the issue, so there is no host branch; it refuses an empty body and sends nothing under
  `FORGE_DRY_RUN`, because it is the one call there that destroys what was already written.

### Changed

- **`claude plugin details`'s token cost is a dated cross-check, not the metric** (#170). Probed:
  it does NOT charge an agent for the companion skills it preloads (a companion grown to 5,000
  words moved the agent's figure by nothing), which is the quantity #150 spent a phase
  establishing. It also rounds to two significant figures. The comparison is recorded with its
  date and CLI version, and a test fails if it loses either.
- **No per-plugin git tags, and `claude plugin tag` stays out of the release lane** (#171). Probing
  it disproved the ticket's own premise: the agreement it validates fires only when a marketplace
  entry carries a version, and forge-kit's deliberately do not, so the check is vacuous here and is
  a different invariant from `check-plugin-version-bump.sh` rather than a duplicate of it.

- **The overnight loop honours the iteration contract it was already calling** (#88). It chains
  rounds with `--since` instead of re-reviewing the whole target every cycle, and it DEFERS on the
  trip wire instead of deciding for the absent human: findings are ticketed, the item is parked with
  the loop's stopping data, and the park leads the morning report. A hard stop is deliberately not a
  defer, because the contract offers no decision there.

## v0.2.0 (2026-09-09)

Two new plugin groups, a leak guard for the moment a private repository is made public, and the
week the guards stopped being taken at their word. The recurring lesson of this release is in the
last group: a guard was wrong on its own first run against this tree more than once, and every
fix in it was verified by breaking the code and watching the test fail.

### Added

- **`forge-kit-roadmap`, an optional eighth plugin group** for rolling wave planning (#160). A
  roadmap owns which PHASES exist and what state each is in; the host owns which phase each ticket
  is in, as the milestone. Different facts, so neither duplicates the other. A phase's plan is
  written when the phase OPENS, never for the whole roadmap at once, and a `planned` phase is a
  bucket you may file tickets against. `check-phases.sh` enforces four rules and `sync-phases.sh`
  reconciles the roadmap with the host's milestones. Deliberately its own group, so a project using
  any other planning method loses nothing by not installing it. forge-kit now runs on it (`docs/roadmap.md`).
- **A leak guard for the public-repository moment** (#155, #156, #157), shipped as the
  `leak-guard` skill in `forge-kit-security`. The public half finds home paths BY SHAPE, `~/` roots
  by allowlist, and email addresses, needing no secret and no configuration, so it runs in CI. The
  private half checks an identity list held OUTSIDE the repository
  (`~/.claude/forge-kit/private-names.txt`) and redacts its own output by default, because a scanner
  that prints what it found is a leak with a progress bar. A machine with no list is told loudly
  that names are not being checked rather than passing quietly.
- **Components declare whether they belong at user level or in a project** (#164, #165), with
  `scope: user` the default and `scope: project` requiring a `scope-reason`. **forge-adapt now
  REGISTERS a user-scoped component instead of copying it** (#166): a registered component owns no
  user config, so it cannot drift, duplicate or clobber, which is the copy-and-mutate path CLAUDE.md
  blames for every hook bug in this repo's history. `drift` gained a `registered` state so a correct
  install no longer reads as missing and invites the copy back (#167).
- **The gate's verdict lives in the ticket body, in an addressable block** (#130, #102), rather than
  only in a comment nobody reads back. The review stays a comment; the state does not. Every body
  region the gate writes now has ONE lifecycle (#145), and the author sections it touches are
  written once or not at all (#147).
- **Step 3A's mechanical checks are a tested script** (#149), `check-ticket-mechanics.sh`, replacing
  544 words of prose with 41 contract tests. It emits one row per check and never decides a verdict:
  where it cannot rule mechanically it emits `referred` and the critic rules instead, because its
  heuristics are deliberately narrower than the canonical rules. Its first run caught the bug that
  argues for the test: the literal `N/A` matched a "contains a slash" path test.
- **An orchestrator word budget, stated rather than left as an exemption** (#150). An agent whose
  `tools:` declares `Agent` gets 4000/6000 instead of 2000/3000, because a coordinator carries the
  briefs it dispatches as well as the rules it obeys. Membership is mechanical, so it cannot rot
  into a maintained list.
- **All round behaviour for `ticket-gate` in one table** (#103), replacing six scattered re-run
  policies. A new step or lens needs a row. Also `check-lens-contract.sh`, which fails the build
  when the lens result contract drifts between the two plugin groups that share it, treating a
  MISSING marker as skew rather than agreement.
- **`sync-labels` reaches a GitHub-only project** (#120) and gained milestone primitives in
  `forge-lib.sh` for the roadmap group's host rules.
- Four guards that did not exist: `check-restatements.sh` derives the doc's Precedence list
  mechanically instead of letting it certify its own completeness (#125), and found a tenth
  restatement on its first run; `check-producer-stamps.sh` fails any component that hardcodes a
  `template-version` stamp, with no allowlist (#84); `check-template-dir-order.sh` keeps the six
  copies of the template-dir order identical (#77); `check-component-scope.sh` and
  `check-live-placeholders.sh` keep #164's declarations and #163's placeholder removal honest.

- **The component inventory is generated from the tree** and CI fails on a stale region (#96).
  `README.md` and `CLAUDE.md` carry marker-delimited regions filled by
  `scripts/update-component-index.py` from `forge-adapt-catalogue.sh --tsv`. It was already stale
  when this landed: the README claimed 14 skills and omitted `mutation-sweep`. Do not hand-edit
  inside the markers.
- A hand-written "when to run what" sequencing table in the README, deliberately not generated.
- `--tsv` mode on `forge-adapt-catalogue.sh`, adding the file path for machine consumers. The
  default output is unchanged and byte-stable, because forge-adapt reads it.
- **A component size budget** with visible word counts (#97). `scripts/check-component-size.sh`
  warns above a per-type word budget (agent and command 2000, skill 2500), fails above a hard
  ceiling of 1.5x, and holds the three already-oversized components (`adapt`, `ticket-gate`,
  `full-review`) to a **ratchet**: they may shrink freely and may not grow. Word counts are a
  column in the generated index. A test fails if CLAUDE.md's documented numbers and the script's
  enforced numbers disagree. Framed as a smell detector, not a quality metric.
- **`ticket-gate.md` deduplicated where it genuinely repeated** (#109, partial): 5715 to 5680
  words. The `references/` split it also proposes was blocked at the time on #124, which this
  release also closes. The canonical doc's restatement list gained six entries and STOPPED
  claiming to be complete: three review rounds each found it incomplete, so it said so and
  pointed at a guard ticket instead of certifying. That guard is #125, below.
- **The label taxonomy has an applier and a checker** (#104). `forge-host/assets/sync-labels.sh`
  syncs `.github/labels.yml` to the host or reports drift with `--check`. Host-aware, idempotent,
  and it never deletes an undeclared label. It was declarative with no applier for months: 18
  labels declared, 4 present, including `security`, `critical` and `api`, which are executable
  inputs to the gate's lens routing.
- **No jurisdiction is named in any forge-kit default** (#101). Rule 4 becomes "Personal data
  handling" with seven regime-agnostic facts, and the regime ships as an opt-in
  `privacy-regime` skill (forge-kit-security) dispatched by the new `privacy` label. Templates
  bump v5 to v6: the field `id` moves `gdpr` to `personal_data`, and Step 0c gained a rule to
  recover it from a pre-v6 ticket's old heading. `forge-adapt` offers the skill on a
  personal-data signal and never installs it silently.
- **The six gate-only bars moved into the canonical doc, and Precedence gained a third rule**
  (#94, question 1). `ticket-standards.md` rule 2 now enumerates the three auth cases, rule 4
  names encryption at rest and cascading deletion, and a new rule 8 covers implementation and
  dependency concreteness against fields the templates already collect (so no `template-version`
  bump). Precedence now enumerates the REAL restatement set (it wrongly claimed the hard-fail
  bars were the only one) and distinguishes a stricter gate restatement, which is advisory and
  reported as a doc gap rather than blocking, so a gate copy cannot silently out-rule the doc.
- **forge-lib hardening** (#78). The config is parsed once per repo root instead of about four
  times per paginated page; `forge_api` reports the HTTP status as an exit code (44 for 404, 22
  otherwise) instead of `curl -f` flattening everything into 22 with no body, so
  `forge_issue_label` no longer reports an ordinary org-404 as an access failure; and temp files
  live in one per-process directory cleaned by an EXIT trap that is installed only when the
  caller has none. The asset's header now carries a CONTRACT CHANGES list, so a `refresh` diff
  says whether a caller has to change.
- **sync-labels hardening** (#121, #122). It now refuses an unterminated quoted
  value, a duplicate declared name and an empty flag value rather than accepting each silently;
  it builds the host lookup in ONE jq pass instead of three or four per label (62 processes to 3
  for 20 labels); It refuses to run on bash 3, where the associative-array lookup fails with an exit code this
  script reserves for "drift found", so automation would retry forever. And a newline in a HOST
  description no longer splits the record and reports real drift as in-sync. #120 is not included;
  see that ticket.
- **`ticket-standards.md` carries two version markers instead of one overloaded integer** (#94,
  question 2). `template-version` says which FORM the doc describes and stays locked to the five
  work templates; the new `doc-rules-version` says which revision the RULES TEXT is at and moves
  freely. Before this, a prose clarification implied a `template-version` bump, which forced the
  templates along and made `ticket-gate` re-synthesise every open ticket, so a clarification cost
  a migration. That is why the gate and the doc were allowed to fork.
- **Every shipped executable now has a contract test, and all of them run in CI** (#76). The last
  two gaps were `version-lib.sh` (19 tests: the four verdicts, fail-closed paths, and the
  prerelease and sibling-branch traps its own comments call out) and `release-run.sh` (19 tests
  of the lane policy, driven with `DRY_RUN=1` so no forge is touched). `test-closing-sessions-memory.py`
  was also wired in; it existed but nothing ran it on a PR.
- **The enforced path set now agrees across all four consumers** (#112). `validate-plugins.sh`
  used `find -path`, where `*` crosses `/`, so it matched component paths at ANY depth while
  the other three matched one level. A nested reference file would have been required to carry
  a version marker that the catalogue could never see. It now shares the same ERE as
  `check-version-bump.sh` and `.githooks/pre-commit`, and `scripts/test-component-paths.sh`
  fails if the four ever disagree again. Latent before this: no component had a subdirectory.
- **The local hooks are split by stage** (#98 item 3). `.githooks/pre-commit` keeps the staged
  checks; the new `.githooks/pre-push` runs the range guards against the remote's default
  branch, the same question CI asks on a PR. It is the only local gate on a direct push to
  main, which both range guards miss by being `pull_request`-only. Skips are loud and never
  block a push. Same one-time enablement: `git config core.hooksPath .githooks`.
- **`ticket-gate.md` rules now live at the step they govern** (#109, partial). Rules went from
  17 bullets to 6 cross-cutting ones; 5794 to 5726 words, with the ratchet baseline lowered to
  match. This was the first of several reductions in this release; see Changed for where the
  number ended up, and #150 for why the number it was measured against was wrong.
- A splitting convention for components that outgrow the budget, naming the main file as canonical
  so a split cannot restate a rule in two places.

### Changed

- **Work lands on `develop` and merges to `main`. There are no pull requests.** Both range guards
  were `pull_request`-only, so the change silently left them running on no path at all; #158 moved
  them to `push` and gave them a shared base resolver.
- **The six live `{{GITHUB_REPO}}` uses are gone** (#163), replaced by the `forge_repo` resolution
  those same files already used elsewhere. That install-time placeholder was the only thing pinning
  components to one project, which is what made #166's registration possible.
- `ticket-gate.md`'s reference artifacts moved into a companion skill and then, in the parts that
  are read once rather than preloaded, into `references/` beneath it. 6355 words to 5778, with no
  capability dropped.
- `parse_roadmap` is shared between the two roadmap assets (#162), and the precedent that was
  cited for duplicating it is recorded as not applying.

### Fixed

- **`overnight-guard` blocked branch switching, and blocked writing ABOUT the commands it guards**
  (#168). Its patterns used `[^|;&]*`, which crosses newlines, so a command on one line matched a
  fragment on another. Found by arming an overnight run against this repo's own workflow.
- **Two guards walked the working tree instead of the tracked file set** (#140, #142), so an
  untracked leftover failed a build CI would never see. Fixed together, through a shared helper;
  their FALLBACKS are deliberately not shared, because the two mechanisms differ.
- `forge-lib`'s key-based config tracking cleared a caller's own exported variable (#131).
- `forge-adapt-agent-skills` corrupted rather than refused on symlinked agents and on mapping items
  it did not understand (#134), which matters because a declared-but-missing companion skill fails
  SILENTLY at runtime.
- `check-template-dir-order` reported the wrong line for the second copy in a merged run (#143).
- `sync-labels` test gaps and two behaviour changes left by the #121 lookup rewrite (#127).
- `check-restatements` gained per-item rule coverage and handling for wrapped references (#138).
- The leak guard's public half judged the first path segment only, and the segment below it is the
  worse half of the leak (#159). Closed as working-as-intended by maintainer decision, with the
  limit documented beside the reach statement it qualifies rather than the claim quietly narrowed.

## v0.1.0 (2026-09-06)

First tagged release. 270 commits since 2026-04-23, previously untagged.

**40 components across 7 plugin groups:** 14 subagents, 15 skills, 4 commands, 4 hooks, and 3
versioned shell assets.

| Plugin group | Version | Components |
|---|---|---|
| `forge-kit-governance` | 0.7.11 | 7 |
| `forge-kit-devops` | 0.6.6 | 12 |
| `forge-kit-adapt` | 0.3.4 | 1 |
| `forge-kit-review` | 0.3.3 | 7 |
| `forge-kit-security` | 0.2.2 | 4 |
| `forge-kit-testing` | 0.2.1 | 4 |
| `forge-kit-backend` | 0.1.0 | 5 |

### Governance

- **`ticket-gate`**, the readiness gate: deterministic mechanical checks plus one critic agent
  returning PASS, NEEDS-WORK, or BLOCKED, with label-routed lenses. This replaced an earlier
  5-agent 10/10 scoring committee, which produced a number rather than a decision.
- **Ticket standard v5** across the five work issue templates: GWT scenarios, unit and E2E test
  specs, GDPR considerations, security checklist, documentation impact, required reviews.
  `ticket-gate` auto-synthesizes missing sections from earlier-version tickets.
- **The rules live in one place.** `docs/guides/ticket-standards.md` is canonical; the templates
  carry only form fields, and `check-template-lockstep.sh` keeps the two on one shared version so
  they cannot drift apart.
- **`working-overnight`**: governed unattended work, shipped as branch-plus-PR and never merging,
  deferring you-only decisions instead of guessing. Backed by the `overnight-guard` hook for
  mechanical enforcement and `overnight-continue` for resumption.
- **`closing-sessions`**: persists durable facts and resume state before a session ends.

### forge-adapt

The entry point, and the only component a project installs by hand.

- Recommender-style flow: analyze the project, recommend the top 1 to 2 components per category
  with a short reason each, install and adapt the chosen ones to the stack.
- **Secondary modes**: `drift` reports which installed components lag forge-kit by marker
  comparison and writes nothing; `refresh <name>` deep-compares one component and merges in
  improvements while preserving project adaptation, report-first and never blind-overwriting;
  `contributions` surfaces project-only components worth contributing back; `templates` audits
  issue templates and can install the repo-level template governance.
- **Superpowers coexistence mode**: where the obra/superpowers plugin is present, superpowers owns
  the inner loop and forge-kit the outer loop, applied at install time rather than argued about.
- The component catalogue ships as a tested script the skill runs verbatim, because an LLM
  executor kept reintroducing fixed bugs when it paraphrased an inline block.

### Review, security, and testing

- `code-reviewer`, `architect-review`, `backend-architect`, `code-simplifier`,
  `coding-standards-auditor`, and the 5-phase `/full-review` command, positioned as a pre-merge
  audit rather than the per-task reviewer.
- **An iteration contract for review loops**, with a reporter and loop-owner split, a `--since`
  delta round, and a trip wire for bad-fix injection. Review-until-green has no natural end; this
  bounds it.
- **The assertions-that-cannot-fail dimension** for rotten-green tests. It found a real defect in
  this repo's own test suite within days of shipping.
- `security-auditor`, `backend-security-coder`, `api-security-tester`, and the
  `owasp-api-security` skill.
- `tdd-orchestrator`, `test-automator`, `performance-engineer`, and `mutation-sweep`, which
  targets coverage's blind spot: tests that cannot fail.

### DevOps and host awareness

- **`forge-host`**: a `forge_*` adapter making governance host-aware across GitHub and Forgejo, so
  components call one interface rather than hardcoding a host. Includes the
  `github-to-forgejo` migration playbook and the `block-legacy-host-push` hook, which is installed
  project-locally only and deliberately ships no `hooks.json`.
- **`release`** and **`release-automation`**: the invoked ship and its enforced sibling, a CI gate
  blocking a merge unless the version moved past the last release, built on a shared
  version-to-tag primitive.
- `dep-auditor`, `health-check`, `find-dead-code`, and the `/ci-health` command.

### Backend knowledge

`api-design-principles`, `architecture-patterns`, `microservices-patterns`,
`cqrs-implementation`, and `saga-orchestration`.

### Enforcement machinery

The part that makes the rest hold. Three enforcement points share one marker-parsing rule:

- `validate-plugins.sh` (structure, semver, marker presence), `check-version-bump.sh` (a changed
  component must bump its marker), `check-plugin-version-bump.sh` (a changed group must bump its
  `plugin.json` semver), `check-template-lockstep.sh`.
- **Five contract suites in CI** covering every shipped executable that has a real contract, plus
  the repo's own guards.
- A committed `.githooks/pre-commit`, opt-in per clone, covering the same rules locally, since
  both range guards run at PR time only.
- **`block-dashes` runs against this repo itself**, deliberate dogfooding of a governance hook.

### Hook install model

Hooks reach a project three ways, and the script tells them apart by its own path shape rather
than by environment variables: plugin-level registration gated on a project opt-in file, a
project-local copy that is itself the opt-in, and this repo running a hook against its own tree.
Plugin hooks gate in the shell rather than the interpreter, 1.8 ms against 44 ms per unmatched
call, because a plugin hook is live in every project. Every hook bug in this repo's history came
from the copy-and-mutate path, which is why plugin registration is preferred where it applies.

### Known gaps at this release

Tracked and open, listed so the release is not read as claiming more than it does:

- `closing-sessions/scripts/memory.py` is the one shipped executable with no CI test and no
  version marker, because `skills/*/scripts/` is outside the enforced path set. Its test exists
  and must be run by hand.
- `release-automation`'s two shell assets have no contract tests.
- The component inventory is hand-maintained in several places with nothing checking it against
  the tree (#96).
- The local hook still runs range checks at commit time rather than at push (#98, item 3).
- forge-kit ships no guard against a developer's home paths or private project names leaking into
  a repository it governs (#99).
