# Scenarios

**Given** a repository with no governance and Claude Code installed,
**when** you install `forge-kit-governance` and run `/gate-ticket 42` on an issue filed against an
older template,
**then** missing GWT scenarios and test specs are synthesised from the current template, the verdict
is PASS, NEEDS-WORK or BLOCKED with a concrete change list and never a score, and the review is
posted to the forge so the reasoning outlives the session.

**Given** you want only rolling wave planning,
**when** you run `claude plugin install forge-kit-roadmap@forge-kit`,
**then** `forge-kit-devops` arrives with it because the dependency is declared,
**and** in every project without a `docs/roadmap.md` the group stays inert.

**Given** you would rather be advised than choose,
**when** you run forge-adapt,
**then** you get a project profile, a ranked recommendation per category with a reason under sixty
characters, and nothing is written until you approve,
**and** each approved component is registered by enabling its plugin group rather than copied into
your repository.

**Given** superpowers is installed,
**when** forge-adapt runs,
**then** `code-simplifier` is suppressed with its reason shown rather than hidden, `closing-sessions`
is recommended with the memory split stated, and outer-loop components are recommended unchanged,
**and** you can still install a suppressed component after the conflict is repeated back to you.

**Given** a neighbouring marketplace ships an agent with the same name as one of ours,
**when** forge-adapt decides,
**then** it says so and explains the difference rather than silently recommending a second copy,
**but** it does not suppress ours on a name match alone, because three projects ship a
`code-reviewer` and they are three different agents.

**Given** your team uses Cursor, Copilot, or no AI CLI at all,
**when** you copy the issue templates, `.github/labels.yml` and `docs/guides/ticket-standards.md`,
**then** every ticket is filed against one standard and any agent can check a ticket against that
document, because it is canonical rather than a summary,
**but** nothing enforces it for you: the gate, the hooks and the drift detection need Claude Code.

**Given** groups installed some weeks ago,
**when** you run `forge-adapt drift`,
**then** each installed component is compared against the library by version marker, a stale
marketplace checkout is reported, every place still carrying a retired rule (an adapted copy, your
instruction files, memory) is listed by file and line, an http forge URL lists the workflow steps that need
`FORGE_ALLOW_HTTP`, and nothing is written,
**and** acting on it means `marketplace update` then `update` per group, because registration tracks
this repository and pulls nothing.

**Given** a repository moving off GitHub to self-hosted Forgejo,
**when** the `github-to-forgejo` cutover runs,
**then** components call `forge_*` instead of `gh`, host detection is per repository, and a repo
with no Forgejo config behaves exactly as before,
**and** `block-legacy-host-push` is installed project-locally so it can never fire anywhere else.

**Given** a repository whose history contains home paths and personal names,
**when** the pre-commit hook runs,
**then** the public scan runs first, before every early exit, and blocks on a home-path shape or a
reachable email address,
**and** the private scan redacts the name it matched, because a failing hook's output is the pasted
text it exists to police,
**and** a machine with no name list is told loudly that names are not being checked rather than
passing quietly.

**Given** a queue of gated tickets and nobody present,
**when** `working-overnight` runs,
**then** work ships as branch-plus-PR and never merges,
**and** at the review trip wire the loop defers rather than deciding for you, parks the item with
its stopping data, and leads the morning report with it.

**Given** a project that grew a component forge-kit does not have,
**when** you run `forge-adapt contributions`,
**then** project-only components are surfaced, domain-specific ones filtered out, and contribution
issues opened for the rest.
