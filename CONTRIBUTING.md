# Contributing to forge-kit

Contributions are welcome, as issues or as pull requests. This file is the public contract for
both. The repository's agent instructions are deliberately kept local and are not published, so
everything a contributor needs is here or in the files it links.

## Propose work

- **A bug or an idea:** open an issue with the template that fits.
- **A new component** (an agent, a command, a skill or an issue template): open an issue with the
  [contribution template](https://github.com/agigante80/forge-kit/issues/new?template=contribution.yml)
  first, so the fit is agreed before you write it.
- **A security issue:** never a public issue. See [SECURITY.md](SECURITY.md).

Every new ticket goes through the ticket gate before work starts (`/gate-ticket <N>`, from the
`forge-kit-governance` plugin). The maintainer runs it on your issue; it may ask for changes to the
issue body before anything is built.

## Pull requests target `develop`

Work lands on `develop` and is fast-forwarded to `main` when it is green. Open your pull request
against `develop`, never `main`: a pull request merged into `main` breaks that fast-forward.

## The rules CI enforces

- **Version markers.** Every agent, skill and command carries a `<!-- <name>-version: N -->`
  comment, and every hook and shell asset a `# <name>-version: N` comment. When you change a
  component's behaviour, bump its marker. A new component ships with a marker at 1.
- **Plugin semver.** When you change anything in a plugin group under `plugins/<group>/`, bump
  the `version` in that group's `.claude-plugin/plugin.json`.
- **Generated sections.** The component inventory and the test counts in some documents are
  generated. Regenerate them with `python3 scripts/update-component-index.py` and
  `python3 scripts/update-suite-counts.py` instead of editing them by hand.
- **No em or en dashes** anywhere in the repository. Restructure the sentence; do not swap in a
  hyphen.
- **Issue templates and the ticket standard move together.** The work templates and
  `docs/guides/ticket-standards.md` share one template version; change both or neither.
- **Component size.** Prose components have a word budget; `scripts/check-component-size.sh`
  reports the limits.

## Run the checks

The authoritative list is [`.github/workflows/validate.yml`](.github/workflows/validate.yml):
every `run:` line in it is a check, and CI runs all of them on your pull request. Run the ones
your change touches before you push. You need `bash`, `git`, `jq`, GNU grep (for `grep -P`) and
`python3`. The most common ones:

```bash
bash scripts/validate-plugins.sh
python3 scripts/update-component-index.py --check
bash scripts/check-component-size.sh
git fetch origin main
bash scripts/check-version-bump.sh origin/main
bash scripts/check-plugin-version-bump.sh origin/main
```

Every `scripts/test-*` file is a contract test suite. If you change a script or a shipped
executable, run its suite.

## Local git hooks: read before enabling

`git config core.hooksPath .githooks` turns on the repository's pre-commit and pre-push hooks,
which run the version and leak guards locally. Git hooks run as you, with no sandbox. Before you
check out someone else's branch with hooks enabled, read what that branch changed in `.githooks/`,
in `scripts/` (the hooks call those scripts) and in `plugins/*/hooks/`. Turn the hooks off with
`git config --unset core.hooksPath` when you review an untrusted branch.
