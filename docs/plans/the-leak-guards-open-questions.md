# Plan: The leak guard's open questions

Written 2026-10-08, when *Hard rules held by hooks, day and night* closed. The bucket was filed
2026-10-07 from what *The leak guard, tightened* left behind: two follow-ups it found (#416, #417)
and the three decision tickets it deliberately kept out (#207, #226, #391). Every pick was
recorded on the tickets on 2026-10-07, so despite the name no ticket is waiting on a decision any
more. Each ticket was read with all its comments and checked against the tree on 2026-10-08. None
is already done, none is superseded, and **none is gated at a PASS**: #207, #391, #416 and #417
were never gated, and #226 holds a round 2 NEEDS-WORK whose body has not been rewritten to the
pick. One gate has a real external dependency: #226's pick is "refuse at once, gated on the audit",
and no record of that audit exists on the ticket, in the plans or in either memory store.

## Goal

The leak guard's two scanners give one verdict for the same input in every locale, on every runner
speed and for every allow-file line, and forge-kit's own `--history` run exits 0 so a new finding
stands alone.

## Done looks like

- `bash plugins/forge-kit-security/skills/leak-guard/assets/check-public-leaks.sh --history
  --allow-file .leak-guard-allow` exits 0 at the repository root, with one entry per distinct
  historical placeholder under a dated comment, and none of them carries the maintainer's username
  or address (#207).
- No `killed_at_bound` row in `scripts/test-check-public-leaks.sh` whose mutant a structural ledger
  row already kills; each remaining row sets its bound to k times a measurement of the real scanner
  on the same fixture, with k and the floor recorded beside the row, and the suite is green under 2 x
  nproc load and on an idle fast machine with no bound raised to pass (#417).
- The private name floor counts characters by UTF-8 lead byte with the locale pinned, and redaction
  keeps two whole characters cut at a lead-byte boundary, in `check-private-leaks.sh` and in the
  public scanner's `redact()` that shares the shape; a parity row per locale (`C`, `C.UTF-8`) and
  a mutant per choice pin both (#416).
- `marker [name]` is an allow-file entry kind: a home path or `~/` root whose segment is exactly the declared
  bracketed token is silenced and one whose segment merely starts with it is still reported, a value that is not one bracketed token exits 2, the private
  parser ignores the key, and SKILL.md's "markers need no prefix entry" covers custom markers
  (#391).
- `skip` means exact path or slash-anchored suffix in both halves, both parsers refuse `*` and `?`
  with exit 2 naming the line and never refuse `[`, the private half's `--history` and tree matchers
  are pinned by a firing-plus-near-miss pair each, and the downstream allow-file audit result is
  recorded on #226 before the merge (#226).
- Each ticket is closed against a named commit, `Validate` is green on `main` after each, no
  component baseline is raised, and `leak-guard` ends under its 3750-word ceiling.

## Fails if

A premortem: it is the end of this phase and it failed. What happened?

- **#226 refused `*` in a downstream allow-file nobody had read.** The pick is "refuse at once"
  with no warn-only release. The audit was skipped or assumed, the refusal shipped, and a
  downstream repository's `skip fixtures/*.json` line, live in the private half today, started
  exiting 2 at the next pre-push. The audit's result must be on the ticket before the commit, and
  the phase must be allowed to close without #226 rather than ship it unaudited.
- **#226 narrowed the private half silently in the other direction.** The private `case "$path" in
  $s)` sites become a literal-or-suffix compare, and an entry that crossed `/` now reports every
  file it used to silence: loud, but the same release as the refusal, so the two failures looked
  like one. Since #206 both modes ask one `skip_by_name` (private line 501, the glob at about 515),
  so the round 2 comment's two matcher sites are now one; each mode still needs its own pin, because
  a tree-mode row does not prove the `--history` caller reaches it.
- **A timing row was calibrated on the same noisy clock it judges.** #417's per-run calibration
  measured the scanner once, under load, so the bound scaled with the noise, and a mutant escaped
  on a loaded runner or the bound became looser than 20 s again. The k and floor must be defended
  with a number from an idle run and a 2 x nproc run, and the mutant must still die on both.
- **The locale pick was applied to one scanner.** The floor and `redact()` both live in each
  scanner's own copy (private line 329, public line 575). #403's class has been fixed one site at
  a time four times; #416 fixed only the private floor, and the public `redact()` still printed a
  split multibyte sequence under `LC_ALL=C`.
- **Words.** `leak-guard` is 3355 words against a 2500 budget and a 3750 ceiling, so 395 words of
  headroom. #416, #391 and #226 each add a SKILL.md paragraph and the third crossed the ceiling,
  failing the build, so someone raised it. An agent never raises a baseline; each edit pays for itself.
- **Collisions on the markers.** All five touch one or more of `check-public-leaks-version` (33),
  `check-private-leaks-version` (24), `leak-guard-version` (27) and `forge-kit-security` 0.16.0; two
  ran in parallel and the second took the same number.
- **#207's entries masked a real finding.** An allow entry was added for a value that was not a
  placeholder, or a placeholder was allowed with a prefix broader than the value, and a genuine
  historical leak went silent. The check is a grep for the maintainer's username and address over
  the findings, not a read.
- **#207 cannot be expressed.** Some of the 38 findings (one has a glob-shaped segment, and the placeholder forms have a stray angle bracket)
  may not be writable as a `root`, `prefix` or `email` entry the parser accepts, and the ticket's
  "one entry per distinct value" quietly became a `skip` of the file, which hides the rest of every
  blob it names.

## Expected work

In order, one at a time. All five share the leak-guard markers and the plugin semver, and three
share SKILL.md, so none runs in parallel.

1. **#417** (P3, never gated): first, because it is a test-only change (no asset marker moves) and
   it stops the next four from being judged by a suite that fails on a fast runner. Gate it, then:
   list the `killed_at_bound` rows (public suite lines about 1602 to 1781), name for each the
   structural ledger row that already kills the same mutant or find that none does, drop the former
   and calibrate the latter. The ticket says to check the private suite for rows of the same shape;
   a grep on 2026-10-08 finds no timing row there, so record that as the answer. The words cost is
   zero.
2. **#207** (P3, never gated): second, because it is `.leak-guard-allow` only (no asset, no marker,
   no words) and from then on `--history` exits 0, so any later change that creates a finding
   stands alone. Gate it, then rerun the history scan with `--show-evidence` into `tmp/` (it prints
   the unredacted values, so never paste it into the ticket), group the findings by distinct value,
   grep the output for the maintainer's username and address, and add one entry per value under a
   dated comment. Verified 2026-10-08 at 75321f2: still 38 findings (22 home-path, 14 email, 2
   home-root), 30 in three earlier blobs of `.leak-guard-allow`, 8 in commit messages, exit 1.
   Picks recorded 2026-10-07: option A. A value no key can express is a finding for the ticket, not
   a `skip`.
3. **#416** (P3, never gated): the locale fix, third, because #391 and #226 add parser rows and
   this adds the per-locale parity grid they should copy. Gate it, then add the lead-byte count at
   the floor (private line 426) and the lead-byte cut in `redact()` in both scanners, mind #217's
   linear bound on the `--history` path, and add a parity row per locale and a mutant per choice.
   Picks recorded 2026-10-07: characters in every locale; two whole characters.
4. **#391** (P3, never gated): fourth. A new key in the public parser (`marker` beside `root`,
   `prefix`, `email`, `skip`, near line 430) and an ignore arm in the private parser (near line
   228). Picks recorded 2026-10-07: option (b), one bracketed token, exit 2 otherwise, unclosed
   the unclosed `prefix` spelling is not documented. Gate, then pin a firing-plus-near-miss pair and a refusal
   case. Words: pay for the SKILL.md paragraph by shortening the redaction-marker paragraph (around
   lines 280 to 290) it extends.
5. **#226** (P3, round 2 NEEDS-WORK): last, for two reasons. It is the only ticket with an external
   dependency (the audit), and it is the largest change: two parsers, two matchers, a
   refusal, SKILL.md and the allow-file header. Picks recorded 2026-10-07: Option 1 (literal-or-
   suffix in both halves), refuse `*` and `?` in both parsers, never `[`, refuse at once with no
   warn-only release, gated on the audit. First step: ask the maintainer question below, and in
   parallel rewrite the ticket body to the pick (the description, expected versus actual, GWT,
   unit pairs per suite plus a private `--history` case, and the stale line numbers the round 2
   comment lists) and re-gate. The body rewrite is part of the work, not a precondition the
   maintainer owes. If the audit answer has not arrived when items 1 to 4 are done, do not
   implement: record that on the ticket and move #226 to the backlog at the phase's close.

## Maintainer questions

Only decisions not already recorded on a ticket.

1. **The #226 audit: has it been done, and if not, will you run it?** No comment, plan or memory
   file records it, so the plan treats it as not done. The audit is one command in each downstream
   repository that carries a `.leak-guard-allow`:
   `grep -nE '^[[:space:]]*skip[[:space:]].*[*?]' .leak-guard-allow`. Paste each repository's lines
   (or "none") into a comment on #226. Any hit is an entry the refusal will turn from a live or
   dead line into an exit 2. The repositories are yours to reach; this one cannot. **Recommended:**
   run it now, before item 5 starts, so the answer is waiting rather than blocking.
2. **If the audit is not back when the other four are done, may the phase close without #226?**
   **Recommended:** yes. Implementing the refusal unaudited is the premortem's first clause; a
   ticket moved to backlog with its pick intact is a finished outcome, and the phase closes
   `done` with it named as moved.
3. **Does #416's redaction pick cover the public scanner's `redact()` too?** The ticket names the
   private scanner's floor, but both scanners carry the same `redact()` shape (private line 329,
   public line 575) and the pick says "a report never prints a split multibyte sequence, in any
   locale". **Recommended:** yes, both, with a parity row in each suite.

## Out of scope

- **A `--since <ref>` bound on `--history`** and documenting exit 1 as expected (#207's options B
  and C): rejected on the ticket, not deferred.
- **Public-half real glob support** and `**` as a token (#226 Options 2 and 3): rejected on the
  ticket; a new ticket in `backlog` if ever wanted.
- **The private parser's two-space-after-key defect** (the #240 strip is public-only): `backlog`,
  as #226's round 2 advised ticketing it separately.
- **The startup-context budget** (#297): *What a session loads before work begins*.
- **Raising the `leak-guard` word ceiling or budget**: an agent never does; a shortfall is a
  maintainer question.

## Close record

Closed 2026-10-09, during an overnight run. **Outcome: re-shaped.** Four of the five expected
tickets landed; #226 moved to `backlog` with its pick intact, because the downstream allow-file
audit the maintainer agreed to run (2026-10-08) was not on the ticket when the other four were done.

| Ticket | Landed | Notes |
|---|---|---|
| #417 | d79e5b0, 060a055, d93fd7e | All nine `killed_at_bound` rows dropped: each mutant already dies on a structural ledger row, so none needed calibrating; the private suite has no timing row |
| #207 | 6fd695e, 2092900 | 15 entries (2 `root`, 8 `prefix`, 5 `email`, no `skip`) cover all 38 findings; `--history` exits 0; gate round 1 PASS |
| #416 | 242090f, c8ea9c7, 9229dbe, 88d67c0, a24b76a | Character floor and two-whole-character redaction in every locale, in all three `redact` copies across both scanners; gate never returned PASS (3 rounds, the last on scenario formatting only) |
| #391 | a430cc8, 44481d8, 51c3bc9, 3b5940f | `marker [name]` key in the public parser, ignore arm in the private one; gate never returned PASS (3 rounds, the last blocking item fixed in 3b5940f and not re-gated) |
| #226 | none | Moved to `backlog`; body rewritten to the pick overnight, gate rounds 3 to 5 NEEDS-WORK, round 5's one significant fix (the widening audit command) applied and not re-gated; implementation waits for the audit |

**The premortem, clause by clause:**

- *#226 refused `*` in a downstream allow-file nobody had read*: avoided by not shipping. The
  phase closed without #226, exactly as the plan allowed.
- *#226 narrowed the private half silently*: did not arise; nothing in #226 shipped.
- *A timing row was calibrated on the same noisy clock it judges*: avoided by removal. Every row
  had a structural twin, so no bound survives to be calibrated.
- *The locale pick was applied to one scanner*: avoided. #416 fixed the private floor and all
  three `redact` copies (private bash, private `--history` awk, public), with a parity row per
  locale in each suite.
- *Words*: held. `leak-guard` stayed at 3355 words; #391 paid for its paragraph, and no baseline
  or ceiling moved.
- *Collisions on the markers*: did not happen; the four ran in sequence, and `forge-kit-security`
  went 0.16.0 to 0.17.2.
- *#207's entries masked a real finding*: avoided. The evidence was grepped for the maintainer's
  username and name variants with no hit; every value was a placeholder.
- *#207 cannot be expressed*: did not happen; no `skip` was needed.

**What the plan did not foresee:**

- **Two tickets landed without a gate PASS.** #416 and #391 each hit the three-round gate cap with
  content accepted and a formatting or one-line doc item left; both were implemented and reviewed
  anyway. Whether a gate that stops on formatting should hold implementation is a question for the
  maintainer, not one this close answers.
- **#416 changed behaviour downstream**: a one or two character multibyte name the `C` locale used
  to accept now exits 2, recorded in `CHANGELOG.md`.
- **The local suite counts drift each landing**, because `CLAUDE.md` is untracked and a worktree
  cannot see it; the main checkout was updated by hand after each ticket.
- The lows went to #437, #438, #439 and #440 (backlog). Added to #440: `marker [.]` is accepted
  while `root` and `prefix` refuse all-punctuation entries (noted by #391's gate).
