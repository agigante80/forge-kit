# Changelog

Umbrella versions for the forge-kit marketplace as a whole. Individual plugin groups carry their
own semver in `plugins/<group>/.claude-plugin/plugin.json` and move independently; see
[docs/guides/versioning.md](docs/guides/versioning.md) for what each version level means.

Note that a release tag does not gate distribution. `/plugin marketplace add agigante80/forge-kit`
tracks the repository, so users are already served from the default branch.

Each release opens with a short summary for someone upgrading, then links its full engineering
notes in [docs/changelog-detail/](docs/changelog-detail/). A bullet's bold label names the plugin
groups the change touches and a version of each that carries it: the first such version where the
notes record one, otherwise the group's version at the release tag. Because each group installs
from the default branch at its own version, compare that label with the group version you have
installed rather than with the release tag. `Repository only` marks a change to this repository
(CI, scripts, docs, issue templates) that no plugin carries.

## Unreleased

[Compare v0.11.0...main](https://github.com/agigante80/forge-kit/compare/v0.11.0...main). Entries gather here as work
lands; the short summary is written when they are released, at the same time as they move to
`docs/changelog-detail/`.

## v0.11.0 (2026-11-13)

[Compare v0.10.0...v0.11.0](https://github.com/agigante80/forge-kit/compare/v0.10.0...v0.11.0). Full release notes: [docs/changelog-detail/v0.11.0.md](docs/changelog-detail/v0.11.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.13.18, `forge-kit-devops` 0.27.4, `forge-kit-governance` 0.40.9, `forge-kit-review` 0.8.3, `forge-kit-roadmap` 0.15.25, `forge-kit-security` 0.18.11, `forge-kit-testing` 0.3.3.

### Upgrade notes

- **forge-kit-governance 0.40.1, forge-kit-roadmap 0.15.23, forge-kit-devops 0.27.1:** The ticket gate, `/phase review`, `/ci-health` and a release no longer post comments: the gate review, a rewritten body's old text, investigate-only notes and `Released in <tag>` all go in the ticket body as regions, and `forge-write-consent` now denies every comment you did not grant with `allow-comment`, `gh issue close --comment` included (#581, #582, #583, #584, #586). Update any script or habit that reads those comments, and run `forge-adapt drift` to refresh your installed copies.
- **forge-kit-governance 0.40.6, forge-kit-adapt 0.13.16:** The comment rule now lives once, in `docs/guides/ticket-standards.md` ("Comments on tickets"), and the old wording in `forge-write-consent`, the hooks README and `decision-brief` is retired. Run `forge-adapt drift` in each project that carries a copy to find it (#585).
- **forge-kit-governance 0.40.4, forge-kit-adapt 0.13.15:** forge-adapt no longer creates `.claude/no-destructive`, so the daytime arm of `overnight-guard` is off after a fresh install. To keep it, answer yes when asked or run `touch .claude/no-destructive` (#577).
- **Repository only:** If you followed the portable copy recipe in `docs/guides/without-claude-code.md` or the README's portable table, delete `config.yml` and `contribution.yml` from your `.github/ISSUE_TEMPLATE/`, or point `config.yml` at your own repository. They routed your security reports to forge-kit (#572).

### Security

- **Repository only:** `SECURITY.md` names the supported versions, the scope and the private reporting route, and private vulnerability reporting is enabled on the repository (#575).

### Added

- **forge-kit-review 0.8.0, forge-kit-adapt 0.13.12, forge-kit-governance 0.38.5:** A new `architecture-standards-auditor` agent owns `docs/architecture/` and the ADR index, and the ticket gate cites an accepted ADR that a plan contradicts. A new ADR is always `proposed`, only you accept it, and an accepted ADR is never edited except to supersede it (#578).
- **forge-kit-governance 0.39.0:** A new `weighing-options` skill gives every opinion one shape (options with pros and cons, one recommendation) and records the accepted decision as a coding rule or an ADR (#579).
- **forge-kit-governance 0.40.1:** The ticket gate posts no comment: its review is a `gate-review` body region replaced each round, and `count-gate-rounds.sh` still counts older comment reviews (#581).
- **forge-kit-devops 0.27.1:** A release records `Released in <tag>` in each shipped ticket's body, never as a comment, and a failed record leaves that ticket open (#583).
- **forge-kit-adapt 0.13.14:** `check-template-lockstep.sh` fails on a canonical ticket-standards doc that has no `template-version` marker, instead of reporting the templates as locked (#576).
- **forge-kit-adapt 0.13.17, forge-kit-devops 0.27.2, forge-kit-governance 0.40.7, forge-kit-review 0.8.2, forge-kit-roadmap 0.15.24, forge-kit-security 0.18.10, forge-kit-testing 0.3.2:** Every plugin folder ships the MIT `LICENSE`, and `validate-plugins.sh` fails when a copy differs from the root one (#587).
- **forge-kit-adapt 0.13.11, forge-kit-devops 0.26.9, forge-kit-governance 0.38.4, forge-kit-review 0.7.8, forge-kit-roadmap 0.15.22, forge-kit-security 0.18.9, forge-kit-testing 0.3.1:** forge-kit is MIT licensed, every plugin manifest says so, and `THIRD_PARTY_NOTICES.md` carries the notice for the three files derived from `wshobson/agents` (#573).
- **Repository only:** `CONTRIBUTING.md` and a pull request template state the rules for outside contributions, and the issue chooser offers the private security route (#575).
- **Repository only:** The README is now a landing page, and `docs/getting-started.md` walks from install to a first gate verdict. Reference material moved verbatim into `docs/` pages, with `docs/README.md` mapping every document (#588, #590).
- **Repository only:** Real examples of the kit's output are under `docs/media/`, and `docs/install-and-upgrade.md` lists what each install, upgrade, guard and removal path leaves behind (#593, #596).
- **Repository only:** `docs/plans/README.md` and `docs/superpowers/README.md` label the working records (#591).

### Changed

- **forge-kit-governance 0.40.6, forge-kit-adapt 0.13.16:** A comment is posted only when you ask, to explain something to another person, or on a ticket that is not yours; decisions, corrections, retractions and closing notes are body edits (#585).
- **forge-kit-roadmap 0.15.23:** `/phase review` rewrites a ticket's body without posting the old text as a comment, since the forge keeps the body's edit history (#582).
- **forge-kit-devops 0.26.10:** `/ci-health` writes its investigate-only notes into a `ci-health-notes` body region, never a comment (#584).
- **forge-kit-governance 0.38.2:** A `ticket-budget: unlimited` line in `.claude/forge-write-consent` turns the ticket rule off, while comments still need `allow-comment` (no ticket number).
- **forge-kit-adapt 0.13.10:** `forge-adapt drift` reports a local copy of a component whose plugin group is installed but off as `registrable`, and `refresh` never merges into it, so an adapted copy can no longer keep a retired rule alive (no ticket number).
- **forge-kit-governance 0.40.8, forge-kit-adapt 0.13.18, forge-kit-devops 0.27.4, forge-kit-review 0.8.3, forge-kit-roadmap 0.15.25, forge-kit-security 0.18.11, forge-kit-testing 0.3.3:** Each plugin group describes itself in one sentence of at most 120 characters, every manifest carries a `homepage` and `keywords`, and `docs/plugins.md` gains a Using section per group. Hand-written counts in the docs are dated or removed, and `check-doc-counts.sh` keeps them that way (#594, #595).
- **Repository only:** Each release's notes move to their own file under `docs/changelog-detail/`, and every release in this file opens with a short summary for someone upgrading (#589, #592).
- **Repository only:** Rules with one home are now a registry in `scripts/rules.tsv`, and a rule version bump fails CI until the old wording is retired in `retired-rules.tsv` (no ticket number).

### Fixed

- **forge-kit-governance 0.40.5:** `forge-write-consent` exempts no comment any more, so a `Released in` note, a gate comment and `gh issue close --comment` are denied without `allow-comment` (#586).
- **forge-kit-devops 0.27.3:** Validate runs on `ubuntu-latest` (26.04) again, because three mutant rows that assumed the older platform now probe their premise first; no shipped script changed (#580).
- **forge-kit-adapt 0.13.15, forge-kit-governance 0.40.4:** The daytime arm of `overnight-guard` is opt-in, and a refresh never recreates an absent sentinel (#577).
- **forge-kit-governance 0.38.3:** Ten stale or false statements in the public docs are corrected, among them the uninstall, marketplace auto-update and opt-in sentinel claims (#574).
- **Repository only:** The portable install recipe no longer copies forge-kit's own `config.yml` and `contribution.yml`, and the marketplace catalogue descriptions match each `plugin.json` (#572).
- **forge-kit-adapt 0.13.9:** A retired-rules row no longer quotes a live rule's anchor, which made the rule guard fail on its own data file (no ticket number).
- **forge-kit-review 0.7.7, forge-kit-governance 0.38.1:** `/full-review` defines its stop reasons, so a round 1 whose only fixes were Mediums no longer ends as `clean round` with those fixes unreviewed. An overnight investigation now notes its Mediums in the morning report instead of ticketing them (no ticket number).
- **forge-kit-adapt 0.13.8:** `forge-adapt drift` finds the review-lows v2 wording in a downstream copy instead of reading it as current (no ticket number).

## v0.10.0 (2026-10-27)

[Compare v0.9.1...v0.10.0](https://github.com/agigante80/forge-kit/compare/v0.9.1...v0.10.0). Full release notes: [docs/changelog-detail/v0.10.0.md](docs/changelog-detail/v0.10.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.13.7, `forge-kit-devops` 0.26.8, `forge-kit-governance` 0.38.0, `forge-kit-review` 0.7.6, `forge-kit-roadmap` 0.15.21, `forge-kit-security` 0.18.8, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-governance 0.37.2:** In a project that opts in with `.claude/forge-write-consent`, agents can no longer post forge comments or file tickets unless your prompt says `allow-comment` or `allow-ticket`, except for a per-session ticket budget (default 3). Set `ticket-budget: N` in that file to change the budget; 0 restores the strict per-prompt rule.
- **forge-kit-devops 0.26.1, forge-kit-adapt 0.12.29:** A `.forge.conf` routing key, token variable or credential setting that a checked-out branch changes is now refused with exit 2 until it matches the default branch, including in a repository whose only remote is not `origin`. On a first adoption, or with an unpushed `.forge.conf`, export the routing keys yourself.
- **forge-kit-devops 0.22.23:** Release lanes B and C now run only for a push to this repository's production branch, so a pull request whose head branch shares that name can no longer reach the release token. A project that installed either lane should add the same three `workflow_run` conditions to its copy.

- **forge-kit-governance 0.36.7, forge-kit-review 0.7.5:** forge-kit-governance now declares forge-kit-review and forge-kit-security as dependencies, and forge-kit-review declares forge-kit-security, so `/full-review`, the gate's security lens and overnight reviews find the agents they dispatch (#551, #562). Run `/reload-plugins` after updating, because `claude plugin update` alone does not install a newly declared dependency (#561).

### Security

- **forge-kit-devops 0.26.1, forge-kit-adapt 0.12.29:** A pull request can no longer aim your forge token at another server or repository by editing `.forge.conf`. The routing keys, `FORGE_TOKEN_ENV` and `FORGE_NO_GIT_CREDENTIALS` are compared with the default branch's copy before any request, and a value you exported yourself still wins (#517, #546).
- **forge-kit-security 0.18.4, forge-kit-devops 0.26.2, forge-kit-adapt 0.12.31:** Issue, comment and release text is now scanned for leaks before it is sent, by a new `scan-forge-writes` hook for `gh` commands and by forge-lib's seven public writers, so gate reviews no longer reach the forge unscanned. It is opt-in per project (`.claude/scan-forge-writes` or `FORGE_LEAK_SCAN=1`), a finding stops the write without printing the matched text, and a checked-out branch cannot weaken the scan (#536, #539).
- **forge-kit-security 0.17.7:** The private leak scanner now reads a `skip` line as a literal path, as the public one always did, so a stray `skip *` can no longer silence the whole private scan. Both scanners now refuse a `skip` value containing `*` or `?` with exit 2, so rewrite any such line in `.leak-guard-allow` (#226).

### Added

- **forge-kit-governance 0.36.4, forge-kit-devops 0.25.0, forge-kit-adapt 0.12.30:** A `forge-write-consent` hook denies an agent's forge comment or new ticket that your own prompt did not grant, because decisions belong in a ticket body and one session had filed 25 tickets in a day. Body rewrites and closes are never denied, and ticket-gate, `/ci-health`, dep-auditor and overnight runs now follow the rule (#565).
- **forge-kit-devops 0.26.2:** A new `usage-report` skill prints where Claude Code usage went over the last N days, read from the transcripts the CLI already writes, by project, model, session and day, as tables or one `--json` object. On every machine measured the answer was context re-sent each turn, not output (#566).
- **forge-kit-devops 0.26.4:** `FORGE_BODY_FILTER` lets a project add its own text to every issue body `forge_issue_create` sends, and the addition survives verbatim forge-lib refreshes. Point it at an absolute executable path; a bad path, a non-zero exit, a timeout or empty output returns code 111 and sends nothing (#541).
- **forge-kit-devops 0.22.22, forge-kit-governance 0.35.31:** A release now comments on and closes the tickets it shipped, read from the `(#N)` in commit subjects, and `--report` lists released tickets still open. A reverted merge closes nothing, a tag of the same version on another commit is refused, and lanes B and C gain `issues: write` (#496, #497).
- **forge-kit-roadmap 0.15.20:** `/phase review` steps 1 to 4 now call one read-only script, `review-mechanics.sh`, that prints rows for the range, tickets, comments and commits instead of running prose by hand. It reads every issue in the repository so closed tickets are found, and a bad `--range` or failed forge read exits 2 with the cause (#272).
- **forge-kit-adapt 0.12.35, forge-kit-review 0.7.1:** `forge-adapt drift` now reports ticket-standards section titles the gate cites that your doc lacks, retired files, a doc-rules row, workflow steps an http forge URL would break, and the upstream delta for `refresh <name>`. A `citation-alias` marker lets a project rename a section, and adapt offers a candidate `.full-review-sensitive` file when `/full-review` is installed without one (#519, #543).

### Changed

- **forge-kit-review 0.7.6, forge-kit-governance 0.36.10, forge-kit-adapt 0.12.12:** Review findings are now triaged by severity and by whether they relate to the change, and a fix's own review files only Critical or High, which stops chains of review tickets. The rule lives in a new `review-lows` skill, so run `forge-adapt drift` in each project that installed `code-reviewer`, `/full-review` or `working-overnight` to find the retired rule (#495).
- **forge-kit-governance 0.35.0:** `check-contributor-docs.sh` reports an `AGENTS.md` over the line budget as `referred` with exit 0 instead of failing, while the 32 KiB byte budget still fails. A long but well-built map no longer pushes a project to raise `--max-lines` until it means nothing (#302).

### Fixed

- **forge-kit-governance 0.35.42, forge-kit-devops 0.22.27, forge-kit-adapt 0.12.27:** The ticket gate's mechanical checks no longer fail sound tickets that have CRLF endings, quoted template labels, headings inside code fences or lowercase one-line scenarios, and a bare synthesised N/A no longer passes (#491, #535). Gate, dep-auditor, `/ci-health`, forge-adapt marker reads and the lockstep guard no longer need GNU `grep -P`, so stock macOS no longer gets `BLOCKED - NO_TEMPLATES` on every ticket.
- **forge-kit-devops 0.26.6, forge-kit-roadmap 0.15.21, forge-kit-governance 0.35.34:** A forge-lib refusal now reaches your stderr instead of being swallowed, so an http forge URL no longer reads as "tag absent" and a failed comment read writes no gate stamp. `/ci-health` also works on a Forgejo host, and a region marker quoted inside a code fence is text (#452, #552).
- **forge-kit-adapt 0.13.3:** forge-adapt reports a local copy of a component the live plugin already provides as `shadowed` (or `kept`), and retiring a hook unwires it before the file is deleted. Its library refresh no longer uses `git reset --hard`, so local edits are no longer silently overwritten, and an inactive or disabled plugin is no longer read as active (#550, #564).
- **forge-kit-governance 0.38.0:** closing-sessions' `memory.py` can now write to a Claude Code auto-memory store with `--memory-dir`, and an empty `remove` no longer reports success (#569, #570).

## v0.9.1 (2026-10-11)

[Compare v0.9.0...v0.9.1](https://github.com/agigante80/forge-kit/compare/v0.9.0...v0.9.1). Full release notes: [docs/changelog-detail/v0.9.1.md](docs/changelog-detail/v0.9.1.md).

Plugin groups at this tag: `forge-kit-adapt` 0.12.7, `forge-kit-devops` 0.22.6, `forge-kit-governance` 0.34.18, `forge-kit-review` 0.7.0, `forge-kit-roadmap` 0.15.19, `forge-kit-security` 0.17.6, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-devops 0.22.6, forge-kit-adapt 0.12.4:** A `FORGE_API_URL` read from a committed `.forge.conf` is trusted again, exactly like an exported one, so the v0.9.0 allowlist migration step is no longer needed. A cloned repository's `.forge.conf` can now name the server that receives your token, so run forge-kit commands only in repositories you trust.
- **forge-kit-roadmap 0.15.19:** `roadmap-lib.sh` now refuses a plan path containing a control character such as TAB with exit 3, where it used to return 0. Callers that passed such a path must clean it first; an empty plan path stays legal.

### Security

- **forge-kit-security 0.17.6:** The private leak scanner's tree mode now reports a listed name found in a non-UTF-8 file (for example Windows-1252) when run under a UTF-8 locale, where it previously exited 0 with the name unreported. A file with a NUL byte after the first match is now also scanned past that byte (#456).

### Changed

- **forge-kit-devops 0.22.6, forge-kit-adapt 0.12.4:** A `.forge.conf` `FORGE_API_URL` no longer needs an entry in the forge hosts file, and a stale hosts file is never read. The https-only rule, no redirects, the `-K` token handling and the `FORGE_TOKEN_ENV` limits stay (#468).

### Fixed

- **forge-kit-governance 0.34.16:** `overnight-guard` now reads redirections (`2>&1`, `&>x`, `>|`, a redirection before the git subcommand), backslash-newline continuations and raw control bytes the way the shell does. Destructive `rm -rf` and `git reset --hard` commands written with those spellings are now denied instead of allowed (#470, #471, #473, #474).
- **forge-kit-governance 0.34.11:** `overnight-guard` now denies destructive git commands behind git global options such as `-C` or `-c k=v`, fails closed on more than 32 options, and denies `rm -rf` of the worktree itself (`"$PWD"`, `$(pwd)`, `$CLAUDE_PROJECT_DIR`), at the accepted cost that a harmless command with 33 or more options is denied too (#457, #467, #469).
- **forge-kit-governance 0.34.10:** `check-ticket-mechanics.sh` no longer reads a bare `na` mention in a Unit, E2E or Scenarios section as an N/A claim. `N/A`, `n/a` and `not applicable` still match anywhere, while a slashless `NA` counts only as a line's first word (#459).
- **forge-kit-governance 0.34.7:** `closing-sessions` `memory.py` now wraps an `@topic-x.md` style token in a code span in a `MEMORY.md` index line, so a project that `@`-imports its index no longer pulls that file into every session. A token in a field that also holds a backtick is refused; reword and retry (#418).
- **forge-kit-governance 0.34.18, forge-kit-adapt 0.12.7:** An uppercase area label (`API`, `UI`, `Privacy`) now routes correctly through the gate and the mechanical labels check, and forge-adapt's labels block accepts it. The labels block also publishes through a symlinked `labels.md` without replacing it or clobbering `.tmp` siblings (#465, #466, #472).
- **forge-kit-roadmap 0.15.19:** `reassess-phases.sh --check` now refuses the renames, inserts, splits and reorders that a real run refuses, instead of printing `would ...`. A multi-line merge reason or delete note is compared as one block, so it is no longer silently dropped (#460, #463, #464).

## v0.9.0 (2026-10-11)

[Compare v0.8.0...v0.9.0](https://github.com/agigante80/forge-kit/compare/v0.8.0...v0.9.0). Full release notes: [docs/changelog-detail/v0.9.0.md](docs/changelog-detail/v0.9.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.12.3, `forge-kit-devops` 0.22.5, `forge-kit-governance` 0.34.5, `forge-kit-review` 0.7.0, `forge-kit-roadmap` 0.15.16, `forge-kit-security` 0.17.5, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-devops 0.22.0, forge-kit-adapt 0.12.2:** A Forgejo URL read from a committed `.forge.conf` now receives your token only if its host (with port) is listed in `${XDG_CONFIG_HOME:-$HOME/.config}/forge/hosts`. Add your host there once per machine, export `FORGE_ALLOW_HTTP=1` for an http-only instance, and move any other token variable to an exported `FORGE_TOKEN_ENV`; installed `forge-lib.sh` copies keep the old behaviour until refreshed with `forge-adapt` (#442).
- **forge-kit-devops 0.22.1:** forge-lib's curl calls now start with `-q`, so your `.curlrc` is never read. A private CA or proxy set only there must move to `CURL_CA_BUNDLE`, `SSL_CERT_FILE` or `https_proxy` (#450).

### Security

- **forge-kit-devops 0.22.0, forge-kit-adapt 0.12.2:** A committed `.forge.conf` could send your Forgejo token to any host, over http, through a redirect, or from any environment variable such as `AWS_SECRET_ACCESS_KEY`. The token now goes only to an allowlisted https host with redirects refused and stays off the command line, while a URL or token name you export yourself is trusted as before (#442).

### Added

- **forge-kit-devops 0.21.2, forge-kit-adapt 0.12.1:** A new `context-budget` skill reports, in characters, how much a project loads before its first prompt (`CLAUDE.md`, its `@`-imports and the loaded part of `MEMORY.md`), warning from 40,000 and failing at 80,000 unless a per-project marker raises the level. `--sweep` ranks many repositories, `health-check` reports the figure and forge-adapt recommends the skill (#297).

### Fixed

- **forge-kit-devops 0.21.3:** `forge_issue_milestone_list` returned no issue at all on Forgejo, so check-phases rules 1 and 4 passed over an empty list. An unphased ticket was never reported, and a rename could report a phase emptied while it still held a ticket (#446).
- **forge-kit-devops 0.22.2:** On Forgejo, `forge_ci_status` now shows why a request was refused (for example a host not yet allowlisted) instead of a bare `not_configured`. Dry runs with an http or unlisted `FORGE_API_URL` now return rc 2 like real runs, and `health-check` warns when the URL would be refused (#449, #450).
- **forge-kit-governance 0.34.5:** The ticket checker now keeps a label with a space (`needs api review`) whole instead of reading it as three labels, and `overnight-guard` denies `git switch -f` and `git restore --staged --worktree`. `no-poll-loops` catches a quoted output-file assignment, `masked-exit-advisory` ignores version, help and `ruff format` calls, and `memory.py` escapes a hostile slug in its refusal (#430, #431, #432, #435, #436, #351, #422).
- **forge-kit-adapt 0.12.3:** forge-adapt's labels install block now matches area names literally, refuses a description over 100 characters, and refuses a doc area name containing a space (#424, #428).
- **forge-kit-governance 0.34.2, forge-kit-devops 0.22.4, forge-kit-roadmap 0.15.16, forge-kit-security 0.17.5:** `/gate-ticket` and `/ci-health` now list a real description instead of their version marker, and five scripts' `--help` opens with what the script does. The roadmap skill now documents the real `--before <other>|--end` flags in place of `--after`, and says an unwritable `TMPDIR` exits 2 on Forgejo (#423, #427, #447).
- **forge-kit-security 0.17.4:** The bash `redact` in both leak scanners now agrees with the awk one on malformed names and runs in one linear match, and the `marker` refusal rules are stated in the `leak-guard` skill. A bracketed all-punctuation marker such as `[.]` is accepted (#439, #440).

## v0.8.0 (2026-10-09)

[Compare v0.7.0...v0.8.0](https://github.com/agigante80/forge-kit/compare/v0.7.0...v0.8.0). Full release notes: [docs/changelog-detail/v0.8.0.md](docs/changelog-detail/v0.8.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.12.0, `forge-kit-devops` 0.20.9, `forge-kit-governance` 0.34.1, `forge-kit-review` 0.7.0, `forge-kit-roadmap` 0.15.14, `forge-kit-security` 0.17.2, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-governance 0.34.0, forge-kit-adapt 0.12.0:** Three new hooks now enforce rules that were only prose: no polling loops on a dispatched subagent, no git discards or dangerous `rm -rf` in the daytime, and an advisory when a pipe filter hides a check's exit code. Each is switched on by its own `.claude/` sentinel file, which forge-adapt now creates, so run forge-adapt to install and arm them.
- **forge-kit-governance 0.30.4:** The ticket gate now needs a shipped helper, `gate-env.sh`, beside its checker. If you installed the gate into `scripts/`, copy it from the plugin's `ticket-gate-reference/assets/` there, or the gate stops at Step 1.
- **forge-kit-governance 0.28.0:** The gate's body fingerprint changed (#312), so every stamped ticket reads `stale` straight after upgrading, and `gate-staleness.yml` marks it on its next edit. Re-run `/gate-ticket <N>` on each, never a bare `--stamp`, which would certify unreviewed text.
- **forge-kit-security 0.16.1:** The leak scanners now exit 2 on lines they used to accept: an allow-file `prefix` that could never match (#242), an edge U+2003 character under a UTF-8 locale, and a private name of one or two multibyte characters (#416). Delete or correct those lines.
- **forge-kit-governance 0.29.0:** `check-contributor-docs.sh` now fails an `@`-import in a tracked `CLAUDE.md` that a clone would not have, and judges tracked content only, so an unstaged edit to a tracked doc is not judged. Track or commit the imported files.
- **forge-kit-adapt 0.12.0:** forge-adapt's host probe now decides by URL authority and honours `.forge.conf`, `FORGE_HOST` and `FORGE_REMOTE`, so an existing `.forge.conf` or exported `FORGE_HOST` wins over the git remote at install time. Check those values before reinstalling (#215).

### Security

- **forge-kit-security 0.14.1:** The pre-push leak scan now reads HEAD's committed tree, so an uncommitted edit can no longer hide a committed leak. A committed symlink named `.leak-guard-allow` also no longer suppresses a leak, because that case used to pass the scan (#375, #384).
- **forge-kit-governance 0.30.9:** `check-contributor-docs.sh` no longer lets any symlink make it read, measure or print a file outside the repository (#309), and `memory.py write` and `remove` no longer follow a swapped-in symlink or block on a FIFO (#324).

### Added

- **forge-kit-governance 0.34.0, forge-kit-adapt 0.12.0:** The `overnight-guard` hook gains a daytime arm that denies git discards and dangerous `rm -rf`, `no-poll-loops` denies shell waits on a dispatched subagent, and `masked-exit-advisory` warns when `| tail` style filters mask a failing check.
- **forge-kit-governance 0.30.0:** `check-contributor-docs.sh` follows a tracked `CLAUDE.md`'s `@`-imports (#301) and reports per-harness instruction copies (`GEMINI.md`, Copilot, Cursor and others) that do not link, import or symlink `AGENTS.md` (#300). The skill documents how to keep them one source.
- **forge-kit-security 0.17.2:** The allow-file takes a `marker [name]` key so a custom redaction marker is accepted (#391), and a private-list line starting with `=` matches only a whole word, so a short username no longer hits inside longer words (#222).
- **forge-kit-adapt 0.9.0:** forge-adapt's Templates mode now installs the area-label doc, a label declaration and `sync-labels.sh` whether or not any template is versioned, so the gate no longer falls back to forge-kit's nine areas for a project that renamed its own (#214).

### Changed

- **Repository only:** CI gains guards that fail a pipe into `grep -q` (#413) and a `scripts/test-*` suite with no `validate.yml` step (#348). It also runs the contributor-docs suite under gawk, mawk and BWK awk, and the roadmap reshape suite (#344).

### Fixed

- **forge-kit-governance 0.32.4:** The ticket gate no longer fails its own checks: it never reuses a stale `gate-context`, writes scenario labels its checker reads, and does not charge the auto-filled Codebase Context heading. It also synthesises sections for templates that rename E2E, and `no-poll-loops` no longer prescribes a foreground dispatch Claude Code lacks.
- **forge-kit-roadmap 0.15.14:** `reassess-phases.sh` validates a merge or delete on a scratch copy first, so a refusal no longer leaves the host changed and the roadmap not. A malformed roadmap is refused again at any size, and `/phase` resolves its helpers in every shell and gives each review run its own snapshot.
- **forge-kit-devops 0.20.9:** `forge-lib.sh` sends a body of any size whole instead of silently sending none (#409), and refuses an invalid `FORGE_HOST` rather than returning success having sent nothing (#256). `sync-labels.sh` also refuses an unrecognised host before sending (#331).
- **forge-kit-security 0.16.1:** `--all` and `--head` now scan the whole repository from any directory, with root-relative paths (#401), and `--history` reports a leak under any `TMPDIR`. The default redacted `--history` report is linear in match length under UTF-8 (#217).
- **forge-kit-governance 0.30.1:** `check-contributor-docs.sh` stops giving wrong rows: a `NAME=` inside a quoted argument no longer hides a broken command (#386), and `.npmrc` `workspaces` handling follows npm. Block HTML comments, a leading byte-order mark and `run-script` spellings are now read correctly.

## v0.7.0 (2026-09-24)

[Compare v0.6.0...v0.7.0](https://github.com/agigante80/forge-kit/compare/v0.6.0...v0.7.0). Full release notes: [docs/changelog-detail/v0.7.0.md](docs/changelog-detail/v0.7.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.7.3, `forge-kit-devops` 0.17.0, `forge-kit-governance` 0.22.0, `forge-kit-review` 0.7.0, `forge-kit-roadmap` 0.11.0, `forge-kit-security` 0.12.0, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **Repository only:** The repository history was rewritten to purge the AI-assistant files, so commit shas changed, and the shas cited in plans were re-pointed (#232).

### Added

- **forge-kit-devops 0.17.0, forge-kit-governance 0.22.0, forge-kit-review 0.7.0, forge-kit-security 0.12.0:** Every agent now declares a model and an effort for its role, and every dispatch without frontmatter names its model. Judgment and security roles inherit, while bounded analysis and mechanical roles use `sonnet` at a lower effort (#250, #279).
- **Repository only:** `docs/guides/model-tiers.md` holds the one table of allowed model and effort ranges, and `validate-plugins.sh` fails a component or dispatch outside it (#251, #253).
- **forge-kit-review 0.7.0:** `/full-review` sizes each round, so a small range touching no sensitive path runs `code-reviewer` alone instead of five phases. Pass `--full` to force the full review (#278).
- **Repository only:** `scripts/measure-dispatch-cost.py` reports what each subagent dispatch cost, in turns and tokens, from Claude Code's own transcripts (#280). Re-measuring the security roles with it moved neither role (#289).
- **forge-kit-adapt 0.7.3:** `refresh <name>` now reports each model or effort key an installed copy holds differently, and keeps the project's value (#281).
- **forge-kit-governance 0.22.0:** The gate verdict now sits at the top of the ticket body, stamped with a fingerprint of the author's text, and is flagged stale once the author edits past it (#284, #285). The round counter can also restore the blocking items from earlier rounds (#196).
- **forge-kit-devops 0.17.0, forge-kit-roadmap 0.11.0:** The forge adapter and the roadmap gained write halves. Three writers can now share one ticket body without clobbering each other, `forge_issue_milestone` exists, and `/phase review` and `/phase reassess` are available (#244, #249).
- **Repository only:** `scripts/check-doc-drift.sh` reports which documents a range of commits made stale, and never fails the build (#247, #258).
- **forge-kit-security 0.12.0:** The leak guard's private half can skip paths, in the tree modes and under `--history` (#225).

### Changed

- **Repository only:** The AI-assistant files are local instead of published, and the suite counts CI can no longer see are checked by the pre-push hook (#218).
- **forge-kit-devops 0.17.0, forge-kit-roadmap 0.11.0:** `/phase` and the forge adapter keep the ordinary end of a list quiet unless `FORGE_DEBUG=1` is set (#236).
- **forge-kit-security 0.12.0:** The leak guard's own examples are now placeholder shapes, so a host project's guard no longer fires on them (#223).

### Fixed

- **forge-kit-security 0.12.0:** The leak guard's `--history` now reads every ref a mirror push sends, including `refs/original` and `refs/notes`, and one rule no longer slows down on long lines (#210, #211).
- **forge-kit-security 0.12.0:** A set of leak-guard false positives and allow-file gaps is closed (#224, #227, #230, #238, #239, #240).
- **Repository only:** The leak guard runs once here, from the asset, and a `scripts/` copy of a shipped asset now fails the build (#231).
- **forge-kit-devops 0.17.0:** The forge adapter stops paginating on a repeated page, and a write to a missing issue now says so, even under a `set -e` caller (#228, #229, #237).
- **forge-kit-devops 0.17.0:** `forge_repo` parses the slug after the host and refuses an scp remote whose path carries an `@` (#216, #235). `FORGE_DRY_RUN=1` now fakes writes only, never reads (#268).
- **forge-kit-governance 0.22.0:** Ticket mechanics check 4 now refers a one-line scenario and a reasoned N/A instead of failing them (#233, #241).
- **Repository only:** No roadmap or forge-adapter test suite can reach the live forge any more, and their temp directories cannot leak (#287, #288).

## v0.6.0 (2026-09-16)

[Compare v0.5.0...v0.6.0](https://github.com/agigante80/forge-kit/compare/v0.5.0...v0.6.0). Full release notes: [docs/changelog-detail/v0.6.0.md](docs/changelog-detail/v0.6.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.7.2, `forge-kit-devops` 0.12.4, `forge-kit-governance` 0.16.7, `forge-kit-review` 0.4.1, `forge-kit-roadmap` 0.8.4, `forge-kit-security` 0.10.2, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-devops 0.12.4:** `forge_host` now decides the host from the URL's authority, so any URL whose host is `github.com` or `ssh.github.com` is GitHub, including `ssh://git@github.com:22/o/r` and `github.com:o/r`. If you set an API URL with such a remote, expect GitHub where the previous version answered `forgejo` (#212).

### Added

- **forge-kit-security 0.10.0:** Both leak-guard scanners gain `--history`, which reads the publishable history (every blob reachable from a branch, tag or remote-tracking ref, plus commit and tag messages). It refuses unsafe repository setups instead of passing, redacts evidence by default, and is never wired into a hook (#191).
- **Repository only:** `scripts/update-suite-counts.py` generates the test counts CLAUDE.md states, and `--check` fails the build on a stale one (#201).
- **forge-kit-governance 0.16.7:** `check-ticket-mechanics.sh --labels-doc` reads the area label set from your project's own `docs/guides/labels.md`, replacing the built-in nine. A project with no such doc keeps the default (#204).

### Changed

- **forge-kit-security 0.10.2:** The leak guard's prose now says history is two sets and a push sends only one, and gives the pre-publish prune step with its real scope. Pruning removes only local orphans before the first push and nothing from any copy that already holds the objects (#198).

### Fixed

- **forge-kit-security 0.10.2:** The leak guard's tree modes now fail closed (#208). Renamed-and-edited files, odd filenames, and unwritable temp files or unreadable tracked files used to be skipped and reported clean; each is now exit 2 naming the file.
- **forge-kit-security 0.10.2:** The private half drops a listed owner name only when origin's host is exactly `github.com`, `gitlab.com`, `codeberg.org` or `bitbucket.org`, and never in `--history` or on a private forge (#209).
- **forge-kit-devops 0.12.4:** `forge_host` and the credential lookup no longer let a crafted URL pass for GitHub. A URL like `FORGE_API_URL=https://evil.internal#@github.com` used to fetch GitHub's secret and send it to the wrong host (#212).
- **forge-kit-governance 0.16.7:** The ticket mechanics now find a section at either `##` or `###` heading level. A doc-compliant `##` body used to read as five absent sections, which inverted the verdict (#190).
- **forge-kit-governance 0.16.7:** Four checker gaps found gating tickets downstream are closed, plus a fifth that made every section read as empty under Apple's awk. Long evidence rows were cut, qualified or bold Positive/Negative markers read as no block, and a renamed E2E section was referred forever (#205).
- **forge-kit-governance 0.16.7:** The gate's provenance line now says `mechanics: none` when nothing was found, prints paths relative to `~` instead of posting a home path, and a missing checker makes the round `unknown` (#194).
- **forge-kit-governance 0.16.7:** Concurrent gate runs no longer share one body file, and a run refuses and posts nothing if the fetched body belongs to another issue. Three runs in one session had read each other's bodies (#197).
- **forge-kit-adapt 0.7.2:** `adapt` no longer calls the plugin cache leaf `<sha>`; it is the plugin semver (#195).

## v0.5.0 (2026-09-11)

[Compare v0.4.0...v0.5.0](https://github.com/agigante80/forge-kit/compare/v0.4.0...v0.5.0). Full release notes: [docs/changelog-detail/v0.5.0.md](docs/changelog-detail/v0.5.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.7.0, `forge-kit-devops` 0.12.3, `forge-kit-governance` 0.16.2, `forge-kit-review` 0.4.1, `forge-kit-roadmap` 0.8.3, `forge-kit-security` 0.9.0, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-devops 0.12.3:** `forge_ci_status` now answers `cancelled` for a superseded run and reserves `not_configured` for "could not ask", while an empty run list is `pending` or `none`. Callers that matched on the old values should update, and `release` now stops on `none` and `cancelled` (#193).

### Added

- **forge-kit-governance 0.16.2:** The mechanical half of the ticket gate now runs without Claude Code, through `forge-gate-mechanics.sh`, on either host. It never prints a verdict, because every `referred` row is a check that could not rule (#182).
- **forge-kit-governance 0.16.2:** A raw hand-filed ticket now opens with a single `never template-shaped` notice instead of seven failures, because that shape is not a defect in the ticket (#184).
- **Repository only:** `docs/guides/without-claude-code.md` is the entry point for a team on another agent or none, and `AGENTS.md` now distinguishes its two audiences (#183).
- **forge-kit-review 0.4.1:** `code-reviewer` now sweeps the files the diff touches for the whole family of a named finding, and does not scan outside them (#187).
- **forge-kit-governance 0.16.2:** The overnight loop now asks whether a ticket is still true before implementing it, and parks a ticket that is only partly fixed instead of re-scoping it (#186).
- **Repository only (templates):** `scripts/check-label-taxonomy.sh` keeps one definition of the area label set and fails when a copy disagrees. Three new area labels (`components`, `tooling`, `governance`) describe this repository's own work (#188).
- **forge-kit-governance 0.16.2, forge-kit-devops 0.12.3:** The gate now counts rounds from posted review comments instead of the issue body, so an ordinary body edit no longer resets it to round 1 and the trip wire can fire. `forge_issue_comments` is new in the forge adapter (#192).

### Fixed

- **forge-kit-devops 0.12.3:** On Forgejo, `forge_ci_status` now tells a superseded run from a broken one. Pushing twice quickly used to leave a healthy branch red, which was wrong on 23 of 39 red commits measured (#193).
- **forge-kit-governance 0.16.2, forge-kit-roadmap 0.8.3:** A shipped asset is now resolved by its version marker instead of the first `find` hit. Side-by-side plugin versions had returned an arbitrary, sometimes stale, copy, and each resolver now prints the copy it chose (#189).
- **forge-kit-security 0.9.0:** Both halves of the leak guard now state that they never look at history and read file content only. A leak committed once and removed later is not caught, and commit messages are not read (#185).

## v0.4.0 (2026-09-10)

[Compare v0.3.0...v0.4.0](https://github.com/agigante80/forge-kit/compare/v0.3.0...v0.4.0). Full release notes: [docs/changelog-detail/v0.4.0.md](docs/changelog-detail/v0.4.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.7.0, `forge-kit-devops` 0.12.1, `forge-kit-governance` 0.13.0, `forge-kit-review` 0.4.0, `forge-kit-roadmap` 0.8.2, `forge-kit-security` 0.8.0, `forge-kit-testing` 0.3.0.

### Upgrade notes

- **forge-kit-backend 0.2.0, forge-kit-review 0.4.0, forge-kit-security 0.8.0, forge-kit-testing 0.3.0:** Eleven components and the whole `forge-kit-backend` group are retired, because each was a near copy of a neighbouring marketplace's file. If you rely on one, install the named replacement from `claude-code-workflows` (#178).

### Added

- **Repository only:** `scripts/check-neighbour-overlap.sh` fails the build when a component here is the same file a neighbouring marketplace ships. A same-name collision with different content is reported and never fails (#177).
- **Repository only:** The README now lists the plugin groups with a copy-pasteable `claude plugin install` command for each, from a generated catalogue. It was also rewritten around what forge-kit is, a governance harness for the outer loop, with a real path for teams not using Claude Code (#181).
- **forge-kit-adapt 0.7.0:** forge-adapt's coexistence rule now covers both neighbouring marketplaces and returns `recommend`, `caveat` or `suppress` with a reason for each pair. It judges the pair, not the name, because `code-reviewer` exists on three sides as three different agents (#179).
- **Repository only:** `validate-plugins.sh` fails a build where a component dispatches a `subagent_type` no agent provides, a failure that was silent at runtime (#180). The size report also shows a line count beside the word count (#176).

### Removed

- **forge-kit-backend 0.2.0, forge-kit-review 0.4.0, forge-kit-security 0.8.0, forge-kit-testing 0.3.0:** The `forge-kit-backend` group is gone, along with `tdd-orchestrator`, `test-automator`, `performance-engineer`, `backend-architect`, `backend-security-coder` and `/pr-enhance`. Each one names its replacement, all in `claude-code-workflows` (#178).
- **forge-kit-review 0.4.0, forge-kit-testing 0.3.0:** `architect-review` stays because `/full-review` dispatches it by name, and `mutation-sweep` stays because nothing else offers it.

### Fixed

- **Repository only:** The README's headline and "Keeping up to date" section described an install model and an auto-update that do not exist. They now say registration tracks the repository but pulls nothing, and name both update commands (#172).
- **Repository only:** Smaller README corrections: the gate example cites the current template version, the contributions section uses current forge-adapt phase numbers, and the labels row now mentions `sync-labels.sh`.
- **forge-kit-roadmap 0.8.2:** The manifest no longer describes itself as self-contained while it depends on `forge-kit-devops`.

## v0.3.0 (2026-09-10)

[Compare v0.2.0...v0.3.0](https://github.com/agigante80/forge-kit/compare/v0.2.0...v0.3.0). Full release notes: [docs/changelog-detail/v0.3.0.md](docs/changelog-detail/v0.3.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.6.2, `forge-kit-backend` 0.2.0, `forge-kit-devops` 0.12.0, `forge-kit-governance` 0.13.0, `forge-kit-review` 0.3.5, `forge-kit-roadmap` 0.8.1, `forge-kit-security` 0.7.5, `forge-kit-testing` 0.2.3.

### Upgrade notes

- **forge-kit-governance 0.13.0, forge-kit-roadmap 0.8.1:** These groups now declare `forge-kit-devops` as a dependency, which resolves on install, not on update. If you already had either group and run `claude plugin update`, it reports `failed to load` until you run `claude plugin install forge-kit-devops@forge-kit` once (#169).

### Added

- **forge-kit-governance 0.13.0, forge-kit-roadmap 0.8.1:** Installing `forge-kit-roadmap` alone now brings `forge-kit-devops` with it, because cross-group dependencies are declared in `plugin.json`. The declaration is also kept in prose for a bare clone (#169).
- **forge-kit-adapt 0.6.2, forge-kit-devops 0.12.0, forge-kit-governance 0.13.0, forge-kit-review 0.3.5, forge-kit-roadmap 0.8.1, forge-kit-security 0.7.5, forge-kit-testing 0.2.3:** Every `plugin.json` now carries an `author`, so the advisory `claude plugin validate` step reports zero warnings instead of eight (#173).
- **Repository only:** `scripts/check-reference-depth.sh` fails when a skill's `references/` file is not named by its own `SKILL.md`, because an agent meeting a reference inside another reference may read only half of it (#175).
- **Repository only:** `scripts/test-validate-plugins.sh` gives the structural guard `validate-plugins.sh` its own contract test, and the guard now also catches a dependency that installs silently.
- **Repository only:** The size guard reports the always-on cost of each description, which every session pays for a component it never invokes. It enforces only that no agent or skill lacks one, and descriptions were trimmed from 14,711 to 12,339 characters with every trigger phrase kept (#174).
- **forge-kit-governance 0.13.0:** The new `decision-brief` skill is for a ticket stalled on a human decision. It re-gates the ticket against the current standard, costs the options with measured numbers, and rewrites the issue body so the decision can be made from it (#129).
- **forge-kit-devops 0.12.0:** `forge_issue_edit <n> <body>` is the forge adapter's first body write. It refuses an empty body and sends nothing under `FORGE_DRY_RUN` (#129).

### Changed

- **forge-kit-governance 0.13.0:** The overnight loop now chains review rounds with `--since` and defers on the trip wire instead of deciding for the absent human. The item is parked with the loop's stopping data and leads the morning report (#88).
- **Repository only:** `claude plugin details`'s token cost is recorded as a dated cross-check, not the metric, and `claude plugin tag` stays out of the release lane (#170, #171).

## v0.2.0 (2026-09-09)

[Compare v0.1.0...v0.2.0](https://github.com/agigante80/forge-kit/compare/v0.1.0...v0.2.0). Full release notes: [docs/changelog-detail/v0.2.0.md](docs/changelog-detail/v0.2.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.6.0, `forge-kit-backend` 0.1.0, `forge-kit-devops` 0.10.5, `forge-kit-governance` 0.10.1, `forge-kit-review` 0.3.3, `forge-kit-roadmap` 0.7.0, `forge-kit-security` 0.7.3, `forge-kit-testing` 0.2.1.

### Upgrade notes

- **Repository only (templates):** The work issue templates move from version 5 to 6, and the field `id` moves from `gdpr` to `personal_data` (#101). The gate recovers it from a pre-v6 ticket's old heading, so existing tickets keep working.
- **forge-kit-adapt 0.6.0:** forge-adapt now registers a user-scoped component instead of copying it, so a correct install no longer reads as missing in `drift` (#166, #167). Components that must live in a project declare `scope: project` with a `scope-reason`.

### Added

- **forge-kit-roadmap 0.7.0:** A new optional plugin group for rolling wave planning. A roadmap owns which phases exist and their state, the host owns which phase each ticket is in, and a phase's plan is written when it opens (#160).
- **forge-kit-security 0.7.3:** The new `leak-guard` skill checks a repository about to go public. Its public half finds home paths, `~/` roots and email addresses with no configuration, and its private half checks an identity list kept outside the repository and redacts its output by default (#155, #156, #157).
- **forge-kit-governance 0.10.1:** The gate's verdict now lives in an addressable block in the ticket body instead of only in a comment, and each body region the gate writes has one lifecycle (#130, #102, #145).
- **forge-kit-governance 0.10.1:** Step 3A's mechanical checks are now a tested script, `check-ticket-mechanics.sh`, which emits one row per check and refers what it cannot rule on to the critic (#149). All round behaviour for `ticket-gate` is also in one table (#103).
- **forge-kit-governance 0.10.1:** Rule 4 becomes "Personal data handling" with seven regime-agnostic facts, and no jurisdiction is named in a default. The opt-in `privacy-regime` skill, dispatched by the new `privacy` label, carries the regime (#101).
- **forge-kit-governance 0.10.1:** `ticket-standards.md` gains a second marker, `doc-rules-version`, so a rules-text clarification no longer forces a template bump and a re-synthesis of every open ticket (#94). The six gate-only bars also moved into the canonical doc.
- **forge-kit-devops 0.10.5:** `sync-labels.sh` applies `.github/labels.yml` to the host or reports drift with `--check`, never deletes an undeclared label, and now reaches a GitHub-only project (#104, #120). It refuses malformed input and bash 3 instead of accepting them silently (#121, #122).
- **forge-kit-devops 0.10.5:** The forge adapter reads its config once per repo root, reports the HTTP status as an exit code (44 for 404), and cleans up its temp files. A header now lists contract changes so a `refresh` diff shows whether callers must change (#78).
- **Repository only:** The component inventory in the README and CLAUDE.md is generated from the tree and CI fails when it is stale (#96). A component size budget warns above a per-type word count and fails above 1.5 times it, and `ticket-gate` shrank from 6355 to 5778 words with no capability dropped (#97, #109, #150).
- **Repository only:** Every shipped executable now has a contract test that runs in CI (#76), and new guards catch drift in restatements, producer stamps, the template-dir order, component scope and live placeholders (#125, #84, #77). A local `.githooks/pre-push` runs the range guards before a push.

### Changed

- **Repository only:** Work now lands on `develop` and merges to `main`, with no pull requests, and both range guards run on `push` as well (#158).
- **forge-kit-devops 0.10.5, forge-kit-governance 0.10.1, forge-kit-review 0.3.3:** The six live `{{GITHUB_REPO}}` uses are gone, replaced by `forge_repo` resolving the repository from the git remote at runtime. That placeholder was the only thing pinning components to one project (#163).
- **forge-kit-roadmap 0.7.0:** `parse_roadmap` is now shared between the two roadmap assets (#162).

### Fixed

- **forge-kit-governance 0.10.1:** `overnight-guard` no longer blocks branch switching or writing about the commands it guards. Its patterns crossed newlines, so a command on one line matched a fragment on another (#168).
- **forge-kit-adapt 0.6.0:** `forge-adapt-agent-skills` refuses symlinked agents and mapping items it does not understand, instead of corrupting them (#134).
- **forge-kit-devops 0.10.5:** `forge-lib`'s config tracking no longer clears a caller's own exported variable (#131).
- **Repository only:** Two guards no longer walk the working tree, so an untracked leftover cannot fail a build that CI would never see (#140, #142).

## v0.1.0 (2026-09-06)

[Release v0.1.0](https://github.com/agigante80/forge-kit/releases/tag/v0.1.0), the first release. Full release notes: [docs/changelog-detail/v0.1.0.md](docs/changelog-detail/v0.1.0.md).

Plugin groups at this tag: `forge-kit-adapt` 0.3.4, `forge-kit-backend` 0.1.0, `forge-kit-devops` 0.6.6, `forge-kit-governance` 0.7.11, `forge-kit-review` 0.3.3, `forge-kit-security` 0.2.2, `forge-kit-testing` 0.2.1.

### Added

- **forge-kit-governance 0.7.11:** `ticket-gate` is the readiness gate, deterministic mechanical checks plus one critic agent returning PASS, NEEDS-WORK or BLOCKED, with label-routed lenses. It replaced a 5-agent scoring committee that produced a number rather than a decision.
- **forge-kit-governance 0.7.11:** The ticket standard v5 covers the five work issue templates (GWT scenarios, unit and E2E test specs, security checklist, documentation impact, required reviews). `ticket-gate` auto-synthesizes missing sections on earlier tickets, and the rules live in one canonical `docs/guides/ticket-standards.md` kept in step with the templates by `check-template-lockstep.sh`.
- **forge-kit-governance 0.7.11:** `working-overnight` runs governed unattended work as branch-plus-PR, never merging and deferring you-only decisions instead of guessing, backed by the `overnight-guard` and `overnight-continue` hooks. `closing-sessions` persists durable facts and resume state before a session ends.
- **forge-kit-adapt 0.3.4:** `forge-adapt` analyses a project, recommends the top one or two components per category, and installs and adapts the chosen ones to your stack. Its `drift`, `refresh <name>`, `contributions` and `templates` modes report or merge without blind overwriting, and a superpowers coexistence mode applies the inner-loop and outer-loop split at install time.
- **forge-kit-review 0.3.3, forge-kit-security 0.2.2, forge-kit-testing 0.2.1:** The specialist agents (`code-reviewer`, `architect-review`, `security-auditor`, `api-security-tester` and others) and the 5-phase `/full-review` command arrive as a pre-merge audit, not the per-task reviewer. An iteration contract with a `--since` delta round and a trip wire bounds review loops, and `mutation-sweep` targets tests that cannot fail.
- **forge-kit-devops 0.6.6:** `forge-host` is a `forge_*` adapter that makes governance host-aware across GitHub and Forgejo, with a `github-to-forgejo` migration playbook. `release` and `release-automation` ship a version, and a CI gate blocks a merge to production unless the version moved past the last release.
- **forge-kit-devops 0.6.6:** `dep-auditor`, `health-check`, `find-dead-code` and the `/ci-health` command arrive, and `block-legacy-host-push` is installed project-locally only.
- **forge-kit-backend 0.1.0:** Five backend knowledge skills ship: `api-design-principles`, `architecture-patterns`, `microservices-patterns`, `cqrs-implementation` and `saga-orchestration`.
- **Repository only:** Version enforcement arrives with the first tag: `validate-plugins.sh`, `check-version-bump.sh`, `check-plugin-version-bump.sh` and `check-template-lockstep.sh`, five contract suites in CI, and an opt-in `.githooks/pre-commit`.
