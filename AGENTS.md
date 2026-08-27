# forge-kit: agent instructions

forge-kit is an AI-assisted project governance scaffold: a template repository of agents,
skills, commands, hooks, and issue-template governance. It is not a buildable application;
there is no package manager and no application test runner. Validation is the script suite
under `scripts/` (see the commands list in CLAUDE.md).

**Authoritative guidance lives in [CLAUDE.md](CLAUDE.md). Read it in full before changing
anything.** Its rules (version markers, template lockstep, the no-dashes policy) apply to
every agent working here, not only Claude Code. This file is a pointer by design: do not
duplicate content into it.
