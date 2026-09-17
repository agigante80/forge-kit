# Plan: What seventeen repositories found

Phase opened 2026-09-18 during an unattended run, for the tickets the leak guard's first rollout
filed the day before (#222 to #227, #230) and two from reviewing that rollout (#231, #233). The
maintainer was asleep when this was written; the premortem below is drafted from the tickets and
the two scanners' own histories, and is recorded as an assumption for the morning report rather
than as the maintainer's answer.

## Goal

The two scanners behave as their SKILL.md and headers say on every shape the rollout hit, so a
project can silence a false positive PRECISELY instead of switching the guard off.

## Done looks like

- A names-file entry can be marked whole-word (`=token`), and a listed five-letter token no longer
  matches inside `banana` (#222). Substring stays the default so every existing list is unchanged.
- `~/[redacted]/` is not a home root (#227), and the allow-file compares a stripped match against a
  stripped entry so `root [redacted]` works as written (the asymmetry #227's comment and #224 both
  name).
- a relative `./home/` import and a project's own `home/` directory are not home paths; `/home/alice`, `"/home/alice"`,
  `=/home/alice` and `(/home/alice` still are, and the header's reach statement says where the
  boundary is (#230).
- `root` refuses an entry that strips to nothing, the way `prefix` already does (#224).
- `skip` globs are documented as `case` patterns whose `*` crosses `/`, or made gitignore-shaped;
  either way the doc and the code say the same thing and a test pins it (#226).
- The private half's SKILL.md states that `skip` reaches `--history` and that a pathless blob is
  never skipped (#225).
- The scanner's own doc-comment examples no longer look like home paths to a host project's
  independent guard (#223).
- This repository runs the shipped asset from CI, the `scripts/` copies are gone, and the
  seventeen "Guard rollout" allow entries with them (#231).
- `check-ticket-mechanics.sh` refers rather than fails on a one-line GWT bullet (#233).
- Every change has a near-miss case beside its firing case, the public suite's mutants still die,
  and both suites run under the bash 3.2 and Apple awk substitute the README describes.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **The whole-word marker made a name that should have matched stop matching.** `=` was chosen
  because it cannot start a directory name, and the first list to carry a stray `=` at the front
  of a project name silently downgraded that name from substring to whole-word, so `bramble-social`
  stopped being caught by `=bramble`. The marker's near-miss case has to be a name that LOOKS like
  a token.
- **#230's boundary narrowed rule A on a real path.** "Preceded by `.` or a word character" is the
  proposed rule, and a home path glued to a word (`cd/home/alice` in a shell transcript, `x=/home`
  is fine but `PATH/home/alice` is not) is now invisible. The public suite's rule is that every
  narrowing ships with the shape it gives up, named in the header; if that sentence is missing the
  change is not done.
- **The redaction marker became a general escape.** `[redacted]` was allowed as a root, and the
  allow grew to `[anything in brackets]`, so a real root written `[myco]` passes. Allow the
  literal marker, nothing shaped like it.
- **`skip` changed semantics under installed users.** Making `*` stop at `/` breaks every existing
  allow-file that relied on the crossing, silently, in seventeen repositories that were tuned
  against the old behaviour. The safer branch is to DOCUMENT the `case` semantics and add `**`
  only if it is needed; if the semantics change, the header line says so and the rollout's
  allow-files are re-run before merge, not after.
- **#223 was fixed by deleting the examples.** The doc comments exist because a rule without its
  firing shape is unreviewable. Rewrite them in the placeholder form the allow-file already uses
  (`/home/<user>`), or split the literal into two tokens; do not remove them.
- **The suites went green on Linux and red on the Mac substitute**, the #191 shape, because a fix
  used a bash-4 or GNU idiom. Both suites under the substitute before every merge, not at the end.
- **Nine tickets became one giant commit.** Each ticket is its own gated, reviewed, merged change;
  the phase is where they are grouped, not where they are batched.

## Expected work

In this order, each gated (two rounds, remainder folded or filed) and reviewed (bounded loop):
#222, #227, #230, #231, #224, #226, #223, #225, #233. #222 first because it is the P2 and the one
whose workaround is the guard being switched off; #231 fourth because #222 and #227 change the
asset it duplicates, and deleting the copy before that would break this repository's own CI
between commits; #233 last because it is the gate's tooling rather than the scanner's.

## Out of scope

- #206 (one copy of the history reader) and #217 (`redact` quadratic on `--history`): structural
  work on the same files, deferred to `backlog` so this phase stays a crop of small fixes.
- #234, #235, #236, #237: forge-lib and gate follow-ups from the previous phase, `backlog`.
- #207 (what this repository says about its own history), #219, #220, #221: `backlog`.
- The four release-gated repositories the rollout has not purged, and the eleven GitHub Support
  purge requests: the rollout session's work, not this repository's.
