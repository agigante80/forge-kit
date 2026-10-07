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

## Close record

Moved verbatim from `docs/roadmap.md` on 2026-10-07, when the roadmap was condensed to one summary per done phase. Earlier paragraphs describe the phase as it was opened; the first is the close review.

Closed 2026-09-18, unattended, outcome **re-shaped**. Seven of nine landed in the plan's order
except that #231 moved up when its gate found the `Leak guard` workflow red: #230, #227 (which
absorbed #238), #231, #224, #225, #223, and #233 with #241 in one change. Two are parked in
`backlog` with the reason on each: #222, whose spec moved twice under review (five items in round
1, seven in round 2 with two defects in round 1's prescriptions) and which changes the names-file
syntax under seventeen tuned lists; and #226, whose premise turned out to hold for one half only,
because the public half never used `case` globs and the two halves already read one shared
allow-file line two ways. Both are decisions rather than work, and an unattended run does not make
them. Eleven follow-ups were filed to `backlog` across the night: #234 to #237 from the previous
phase's reviews, #239 and #240 from this one's, and the rest from gates.

**The premortem's clauses fired in the order they were written.** The first, that the whole-word
marker would silently change a name's meaning, is why #222 is parked rather than shipped. The
second, that #230's boundary would narrow rule A on a real path, fired in review: the anchor
class admitted `~`, so a tilde root whose name is the word home matched rule A and lost its rule B
allow entry, and the fix was to exclude it. The fourth, that `skip` semantics would change under installed users, is the whole
of #226's parking. The seventh, nine tickets becoming one commit, did not fire: every ticket was
its own gated, reviewed, merged change. What no clause named: the rollout had installed the
scanners into this repository the way it installed them everywhere else, as `scripts/` copies, and
the first asset bump of the night turned a second workflow red while `Validate` stayed green;
#231 became a P2 and `validate-plugins.sh` check 6 now refuses a `scripts/` copy of a shipped
asset by marker name.

**The gate did what it is for, at a cost worth stating.** Every ticket took the full two rounds
except #225 (PASS at round 1), and the second round found a defect in the first round's folded
text on #216, #228, #229, #222 and #231: that is the bad-fix injection rate the review loop's
trip wire exists for, arriving in the gate instead. Each review round 1 found one Medium on
#216, #224, #227, #229 and #230, and every round 2 was clean. The mechanics script's own two
inversions (#233, #241) were found by the gate reviewing this phase's tickets and fixed inside it.

Opened 2026-09-18, unattended, for the crop of the leak guard's first rollout: on 2026-09-17 the
two scanners were installed in seventeen public repositories and run in every mode, and the
findings were filed as #222 to #227 and #230, with #231 and #233 from reviewing that work. Every
one is a place where the scanner's behaviour is narrower, broader or louder than its own
documentation says: a short identity token that matches inside ordinary words (#222, the one P2,
and the one with a workaround that is the guard being switched off), a redaction marker read as a
home root after the very rewrite that removed the leak (#227), `/home/` inside a relative import
(#230), the scanner's own doc comments tripping a host project's guard (#223), a `root` key that
accepts a dead entry (#224), `skip` globs whose `*` crosses `/` (#226), two facts about the private
half's `skip` missing from SKILL.md (#225), and this repository carrying the scanner twice (#231).
They belong together because each was found by USE rather than by review, in the shape the
component was named for, and because a guard that cannot be silenced precisely is a guard that
gets removed.
