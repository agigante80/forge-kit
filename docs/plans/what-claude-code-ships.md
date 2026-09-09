# Plan: What Claude Code now ships itself

Phase opened 2026-09-09, written from the roadmap prose plus the five tickets that accumulated in
the bucket: #169, #170, #171, #172, #173.

## Goal

Find out, by probe rather than by argument, which of this kit's hand-rolled machinery the CLI now
does better, and act on each answer including when the answer is "keep ours".

## Done looks like

All five tickets closed. Each one records the command it ran and that command's output, and each
records its decision where the next reader meets it (a script header, a guide, CLAUDE.md) rather
than only in the ticket. #172 in particular: a stale registered install is visible from inside this
repo.

## Order, and why

**The probes come first, together, before any code.** Four of the five tickets open with an
unanswered question about the harness, and three of them can end as documentation-only depending on
the answer. Writing code before the probes would be building against a guess, which is the exact
failure #150 spent a phase recovering from.

Then #172, because it is the P1 and the only defect among the five. Then #169 and #173, which share
a deliverable (`scripts/test-validate-plugins.sh` does not exist; whichever lands first creates it).
Then #170 and #171, both of which may be decisions rather than changes.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A finding was adopted because it exists, not because it is better.** Four of these tickets are
  comparisons, and the tempting move is to replace ours with the first-party thing on principle. Ours
  fails a BUILD; several of theirs validate at tag time or report on an installed copy. A swap that
  loses the build-time half is a regression dressed as modernisation.
- **A probe was skipped and its conclusion written anyway.** Every ticket here says "probed, not
  reasoned" because this repo has been burned by exactly that. If a probe turns out to be awkward to
  run, the honest outcome is to say the question is unanswered, not to answer it from the help text.
- **#172 got solved by telling the user to run an update command.** The defect is that the kit cannot
  SEE staleness, not that the user does not know the command. A doc-only fix leaves every other
  install as blind as this one was.
- **The kit grew a hard dependency on the `claude` CLI in a governance path.** The automation layer
  may depend on it; the governance layer is meant to be agent-agnostic. Any new call must degrade
  loudly and continue when the CLI is absent, the way the pre-push hook already does for `jq`.
- **`adapt/SKILL.md` was grown to hold new prose.** It is on its ratchet at 7300 with no duplication
  left. #172 touches it, and the #149 lever (put the rule in a tested script) is the answer, not a
  baseline raise.
- **The author field published something the leak guard exists to catch.** #173 adds a contact
  string to a public repository that runs its own leak scanner against itself. A handle is already
  public; an email address is not.

## Expected work

Five tickets, above. Possible outcomes include closing #170, #171 or #173 as decisions with the
reason recorded rather than as code changes. That is a finished outcome, not a shortfall.

## Out of scope

- Anything about the maintainer's own machine configuration, including the plaintext token in
  `~/.claude/settings.json`. Not this repo's business and not a public tracker's business.
- A `userConfig` declaration for `leak-guard`'s private-names path. Plausible, unticketed, and
  inventing it here would be enumerating work nobody has asked for.
