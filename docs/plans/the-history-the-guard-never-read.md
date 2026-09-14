# Plan: The history the guard never read

Phase opened 2026-09-14 for #191, outcome A of #185: a history mode for both leak-guard halves.
The maintainer has no Mac, so the probe the ticket waited on was replaced by a substitute
verification (Apple's awk source and bash 3.2.57 built on Linux) and a stated limit in the README.

## Goal

Make `--history` read the publishable history, blobs and messages, under the bash 3.2 rule with
no new floor and no new dependency, and refuse every store it cannot read honestly.

## Done looks like

- Both scanners take `--history`, `--orphans`, and `--show-evidence` / `--show-names`; every one of
  the twelve acceptance criteria has a case that can fail; the four #200 needles are replaced.
- Both suites green under bash 5 AND bash 3.2.57; the scanners byte-identical in output under
  Apple's awk, gawk, mawk and busybox awk on this store; the mutant with the `r<0` gate removed
  exits 0 on the forged-header fixture where the real scanner exits 1.
- Neither hook mentions `--history`; both hook suites assert it.
- Headers, SKILL.md, CLAUDE.md L126 and README say what the mode reads, what it refuses, what it
  costs, and that macOS itself is unverified; markers v8/v9, group 0.10.0; suite counts by the
  generator.

## Fails if

Premortem: it is the end of this phase and it failed badly. What happened?

- **A content byte reached a regex in awk.** Apple's awk FATALs on a byte over 0x7F under glibc's
  C locale the moment a regex touches it, and the whole mode died on the first em dash in a commit
  message. Every content line goes through `index`, `substr`, `length` only; regex on header lines
  alone. The multibyte fixture is the tripwire.
- **The reader was trusted because the probe passed.** The probe counts lines; the mode reports
  leaks. The mutant with the `r<0` gate removed must FAIL the forged-header case, or the byte
  counting was never load-bearing.
- **A path rule suppressed a real leak.** Twin content at `zzz.md` and `aaa.lock`, a merge-only
  blob with no `log --raw` entry without `-m`: each is a case, and an oid with NO map entry is
  scanned, never skipped.
- **A foreign store was read as this one.** Alternates via `--git-path`, `GIT_OBJECT_DIRECTORY`,
  `GIT_ALTERNATE_OBJECT_DIRECTORIES`, a partial clone fetching over the network: four refusals,
  four cases, all exit 2.
- **The mode leaked while reporting.** Unredacted evidence in the public half's history output,
  or a listed name printed inside a path by the private half, and the pasted report was the leak.
- **macOS broke on something the substitute could not see** (BSD `tr`, Apple's `git`). The README
  says the platform is unverified, and a report is a ticket, not a surprise.

## Expected work

#191. On close, file whatever a real Mac needs when one appears.

## Out of scope

- Options A to C, E and F. `gitleaks`. History rewriting or any `git gc` advice beyond the prune
  step #198 already documented.
- #196.
