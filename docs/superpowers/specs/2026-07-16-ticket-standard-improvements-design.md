# Ticket standard improvements (design)

**Status: part 1 approved by the user. Part 2 presented, NOT yet approved.**
Brainstorm was interrupted by a session close before the part 2 approval gate.
Resume by re-presenting part 2 (below) and asking for approval before any implementation.

Date: 2026-07-16

## Problem

The user asked for four things: every ticket must review the documentation tree and the root
README, GWT scenarios wherever possible, technical quality checked against the tech guidelines,
and QA coverage across unit, e2e, and emulator suites.

Three of those four collide with something already in the repo, which is why this design differs
from the literal ask.

## Constraints discovered during exploration

1. **`docs/guides/ticket-standards.md` already warns against the literal ask.** Its closing
   section, "The N/A rule (load-bearing)", states that a coverage-style requirement a docs-only,
   research, infra-only, or API-only ticket cannot satisfy makes that ticket un-passable, "which
   trains people to box-tick and rots the whole gate", and instructs that any new rule with a
   coverage-style requirement must carry an explicit type-and-area scope "or it will backfire".

2. **forge-adapt sources the downstream doc from forge-kit's own copy** (`SKILL.md:675`). There is
   no separate downstream template set to inject into, so a "downstream only" rule would fork the
   standard into two copies, the exact failure the doc's "Why single-source" section exists to
   prevent. `SKILL.md:677` already supports per-project binding: adaptation drops rules for
   sections the project's templates do not carry.

3. **`ticket-gate` never reads `docs/coding-standards.md`.** The gate's Step 2 read-list
   (`ticket-gate.md:246`) includes only `ticket-standards.md`. The `coding-standards-auditor`
   agent produces `docs/coding-standards.md`, but nothing consumes it, so "technical quality per
   the tech guidelines" is currently unenforced at gate time. The two components do not connect.

4. **GWT is already mandatory on all five work templates**, including `design.yml` and
   `infrastructure.yml`. Coverage is already stricter than the ask ("when possible"); the real
   gap is quality, not presence.

5. **`yq` is not installed and CI never installs it.** Only `jq` is available. Any config file
   this design adds must be JSON.

6. **Scripts carry no version markers.** `validate-plugins.sh:44` scans only
   `plugins/**/{agents,commands,skills}`, so new files under `scripts/` need no marker.

## Research findings that changed the design

External research (full report in the session transcript) produced three findings that altered
decisions, and two claims that were withdrawn for lack of evidence.

**Changed the design:**

- The documentation practice with real authority is a **merge gate, not a ticket field**. Write
  the Docs: "You can block merging of new features if they don't include documentation, which
  incentivizes developers to write about features while they are fresh."
  Google's docguide: "Change your documentation in the same CL as the code change." Software
  Engineering at Google ch.10 puts enforcement on the reviewer, and attaches freshness dates with
  an owner byline (naming the owner reportedly increased adoption).
- **Forcing GWT where there is no observable behaviour change produces Cucumber's top-named
  anti-pattern**: scenarios written post-hoc as decorative test names (Seb Rose). `design.yml` and
  `infrastructure.yml` are exactly that case.
- **No source treats "add scenarios to the emulator suite" as a per-ticket requirement.** The
  observed pattern is a standing regression suite, expanded as features warrant, maintained at
  team level.

**Withdrawn for lack of evidence (do not repeat these claims):**

- "A docs checkbox gets rubber-stamped." No evidence found. The only source making this argument
  is vendor marketing for an AI docs-drift product whose stated failure mechanism matches what it
  sells. The repo's own `ticket-standards.md` asserts it as house doctrine, which is a fine reason
  to respect it, but there is no external support.
- "Optimal checklist length is 5 to 9 items." This circulates as a mangled rendering of Miller's
  7 plus or minus 2 and could not be verified against Degani and Wiener's primary paper. No source
  on software checklist length versus compliance survives scrutiny. Likewise, **no evidence was
  found in either direction** on whether long issue templates reduce issue quality.

**Operational gotcha for the gate:** GitHub issue forms return the literal string `_No response_`
for skipped optional fields, and `validations: required: true` has documented failures in
organization repositories.

## Scope: two independently shippable parts

Bundling these produces one PR that bumps `template-version` 4 to 5 across six files, edits the
gate, adds two scripts, and rewires CI. That is hard to review and hard to revert. Ship in order.

---

## Part 1: the ticket standard (APPROVED)

The canonical doc, the five templates, and the gate are version-locked by
`check-template-lockstep.sh` and must move in one commit. This bumps `template-version` 4 to 5
across all six files.

### Canonical doc changes (`docs/guides/ticket-standards.md`)

**Rule 1 (GWT scenarios): add scope and a quality bar.**

Scope: any ticket with an observable behaviour change. The gate DERIVES this from the ticket type
and affected packages; the author never self-declares it. N/A is permitted only where no behaviour
delta exists (pure wireframe, research spike), and the gate scores that N/A claim like any other.
This mirrors how rule 3 (E2E) already scopes itself and honours the load-bearing N/A rule.

Quality bar, scorable by the gate:
- exactly ONE `When` per scenario (multiple When/Then pairs mean multiple behaviours; split them)
- declarative, not click-by-click imperative
- names a real route, model, or screen where the ticket makes one evident
- the negative scenario asserts a SPECIFIC error code or message, not "it fails"
- not a restatement of the summary

**Rule 3 (E2E test specs): add the emulator clause.**

Marked in the source as droppable at adapt time. Where the project runs an emulator or simulator
suite, a ticket adding a user journey names the emulator scenario it adds or extends, or states
why the standing suite already covers it. forge-adapt drops this clause where no such suite
exists, so forge-kit and API-only projects never see it.

**Rule 7 (new): Documentation currency.**

Scope is deliberately EVERY work ticket. This is the one rule where "always asked" is the point.
It stays passable because "none, no user-visible surface" is a legitimate answer that the gate
scores like any other N/A claim. The ticket names the documentation it affects, including the root
README, or states none with a reason.

Wording stays portable: "the project's documentation tree and its root README", never a hardcoded
`docs/*`, so forge-adapt can bind it to each project's real paths at install time.

### Template changes (all five work templates)

One new required `docs_impact` textarea with three prompts:

```
- **Docs affected:**
- **README impact:**
- **Why not, if none:**
```

This takes `feature.yml` from 14 fields to 15. Flagged as the change most likely to be regretted:
the templates are already long, and the research found no evidence either way on whether length
hurts quality.

### Gate changes (`ticket-gate.md`)

- Add `docs/coding-standards.md` to the Step 2 read-list, so the Developer agent scores the
  ticket's implementation plan against the project's ACTUAL standards rather than generic ones.
  This closes the existing disconnect between `coding-standards-auditor` and the gate, and
  requires no new template field.
- Add a Documentation dimension that judges the rule 7 claim against the ticket's own file list.
  A ticket claiming "no docs impact" while adding a slash command fails.
- Teach the GWT scoring the four quality criteria and the derived-scope rule.

---

## Part 2: the CI docs-currency gate (AWAITING APPROVAL)

### `.forge/docs-map.json`

Host-neutral (not `.github/`, since `forge-host` supports Forgejo), user-editable, JSON because
CI has `jq` but not `yq`, and separate from the script that reads it.

```json
[
  { "source": "plugins/*/skills/**",   "docs": ["README.md", "CLAUDE.md"] },
  { "source": "plugins/*/agents/**",   "docs": ["README.md", "CLAUDE.md"] },
  { "source": "plugins/*/commands/**", "docs": ["README.md", "CLAUDE.md"] },
  { "source": "scripts/**",            "docs": ["CLAUDE.md"] }
]
```

### `scripts/check-docs-currency.sh <base-ref>`

Mirrors `check-version-bump.sh`'s contract:

- Matches globs via git pathspec (`git diff --name-only "$base...HEAD" -- ':(glob)...'`) so git
  owns glob semantics rather than bash.
- Reads committed blobs, not the worktree, for the same reason `check-version-bump.sh` does.
- Fails closed on a missing base ref, matching that guard's deliberate refusal to pass vacuously.
- Passes vacuously when `.forge/docs-map.json` is absent, exactly as `check-template-lockstep.sh`
  does for a missing canonical doc. This is what makes downstream adoption opt-in.
- Override: scans `git log "$base..HEAD"` for a `Docs-Impact:` trailer. A commit trailer rather
  than a PR-body marker, because it lives in git history, survives a direct push to main, and
  needs no GitHub API call.
- On violation, exits 1 naming which surface moved and which docs were expected.

### `scripts/test-docs-currency.sh`

Modeled on `test-template-lockstep.sh`: fixture git repos in temp dirs, exit-code assertions for
mapped-source-changed-and-docs-changed (0), mapped-source-changed-and-docs-untouched (1), trailer
override (0), no map (0), missing base ref (1). Every case mutation-tested, per the user's
standing rule that a test which cannot fail is not a test.

### `validate.yml`

Add the new step, gated `if: github.event_name == 'pull_request'` like the version-bump step.

**Rider folded in here:** wire `python3 scripts/test-closing-sessions-memory.py` into CI. That test
exists, passes (12 tests), and is currently enforced by nothing. It is a one-line addition to the
same file, and part 2 is already the CI wiring change.

### Honest caveats

- This guard proves a doc MOVED, not that it became CORRECT. Google's model puts correctness on
  the reviewer, and no script replaces that.
- `.forge/` is a new top-level directory for a single file. The alternative, `scripts/docs-map.json`
  co-located with its only reader, was rejected because the map is project config that humans edit,
  not script implementation. This is a reasonable thing to revisit.

## Open question for resume

Part 2 was presented and the user had not responded when the session closed. Re-present it and get
an explicit approval before implementing. Do not begin implementation of part 1 either: the
brainstorming flow requires a spec review gate, then the writing-plans skill, before any code.
