<!-- Absolute URLs only in this template: a relative link resolves against the pull request page. -->

## What and why

Closes #

## Checklist

- [ ] The base branch is `develop`, not `main`.
- [ ] Every changed agent, skill, command, hook or shell asset has its `<name>-version` marker bumped.
- [ ] Every changed plugin group has its `.claude-plugin/plugin.json` version bumped.
- [ ] I ran the checks my change touches, from https://github.com/agigante80/forge-kit/blob/develop/.github/workflows/validate.yml, and they pass.
- [ ] No em or en dashes were added.
- [ ] This changes a hook, a shell asset or a script under `scripts/` (code that runs on a contributor's machine). If ticked, say what it runs and when.
