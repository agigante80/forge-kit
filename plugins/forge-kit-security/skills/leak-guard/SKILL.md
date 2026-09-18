---
name: leak-guard
description: Stop the developer's own machine leaking into a repository that is about to be made public. Home paths, "~/" roots and email addresses are caught in the open by a CI-runnable scanner; private project names are caught by a list held OUTSIDE the repository, because a committed denylist of the names you are hiding is an index pointing at them. Use when setting up a repo that will go public, when a scan reports a hit, or when someone asks how to remove something already pushed.
---

<!-- leak-guard-version: 14 -->

# Leak guard

A repository governed by forge-kit is usually about to become public, and nothing in the ordinary
workflow stops the developer's own machine arriving with it. This is the guard for that.

The mechanism is boring, which is why it keeps working. Real names arrive as sample data, because
the fastest way to write a realistic project list is to list the projects you have, and the result
looks like sample data forever afterwards. Absolute paths arrive inside pasted output: a traceback,
a `ps` line, a test failure. Each carries a working directory, and under a home directory that path
is not neutral. The username identifies a person, and **the segments above the project are worse**,
because a path can name an employer, a client, a filing scheme, or a category its owner considers
private. The project name at the end is the only part anyone meant to publish.

## What this does not reach, and what to run beside it

**The tree modes never look at history; `--history` does, and it is opt-in.** `--all`, `--staged`
and `--range` enumerate the working tree, the index, or two endpoints of a range, so a path, a name
or an address committed once and removed later is invisible to all three. That is the going-public
moment this skill is named for, which is why the mode exists and why it is run by hand rather than
from a hook:

```bash
# before going public, from the repository root
check-public-leaks.sh --history --allow-file .leak-guard-allow    # evidence redacted; --show-evidence to see it
check-private-leaks.sh --history                                  # names redacted in path and evidence; --show-names
check-public-leaks.sh --history --orphans                         # also what no ref reaches, and the stash (see below)
```

Both read the PUBLISHABLE history: every blob any ref except `refs/stash` reaches (the set a
`git push --mirror` sends), plus every worktree's HEAD, and every commit and tag
message (subject and body; the author, committer and tagger lines are what the forge displays
beside each commit and are not scanned). One `git cat-file --batch` streams the objects and a POSIX
awk reader counts each object's declared bytes, so a blob whose first line forges a batch header
cannot hide the line after it, and no content byte goes through a regex. An object is scanned
unless EVERY path it ever had is skipped, so identical content at `zzz.md` and `aaa.lock` is still
reported. Findings are keyed `<path>@<oid>:<line>`, `commit@<oid>` or `tag@<oid>`, and
`git cat-file -p <oid>` shows the object. Cost on this repository, 4,300 objects and 23 MB: a few
seconds. It refuses, exit 2, a store it cannot read honestly: an alternates file (`git clone
--shared`, a linked worktree inside one), `GIT_OBJECT_DIRECTORY` or `GIT_ALTERNATE_OBJECT_DIRECTORIES`
set, a partial clone, which would fetch every missing object over the network during the scan, a
store git cannot read in full, a path map it cannot parse (a filename containing a newline), and a
`grafts` file; `refs/replace` is ignored, because both make git show something a push does not
send. Every ref except `refs/stash` is publishable, plus every worktree's HEAD: remote-tracking
branches, `refs/notes`, a `filter-branch` backup under `refs/original`, `refs/pull` and any custom
namespace all count (#210: the first cut read branches, tags and remotes, so a scrubbed history
whose backup ref still held the leak scanned clean). A detached HEAD over-reports against a mirror
push, which sends `refs/` only, and is exactly what `git push origin HEAD:main` sends; the stash is the one ref left out, because no push
sends it, and `--orphans` reaches it.

**Written for macOS, verified against its parts on Linux.** The reader was probed against Apple's
own awk source (`apple-oss-distributions/awk`, the fork macOS ships) built on Linux, and both suites
run green under bash 3.2.57 built the same way. The reader puts no content or path byte through a
regex, because that awk aborts the moment a regex meets a byte over 0x7F (every such byte under a
C locale on glibc, an invalid sequence under a UTF-8 one); `LC_ALL=C` is there so `length` counts
bytes, not to avoid that abort. macOS itself,
its BSD `tr` and Apple's `git`, has not been exercised: no Mac was available when this shipped.
A report from one is a ticket, not a surprise.

**What the refs above do not reach stays on the machine**, tested on a throwaway repository: an
amended-away leak was in the local store, invisible to `rev-list --all`, and absent from the remote
after the push. **The exception is a copied `.git`**, a tarball or a `cp -r`, which carries every
object and every ref. Before the first push, prune the orphans and empty every reflog, the stash
stack included, so apply or drop anything stashed first (tested: of three stashes, one survives the
prune as `refs/stash` and the other two are gone):

```bash
git reflog expire --expire=now --all && git gc --prune=now
```

That removes them from THIS clone only. It removes nothing from any copy or host that already
holds the objects, which is the "a history rewrite is not a deletion" point below, so it is a
pre-publish step and never a remedy for an exposure that has happened.

**Neither half reads a commit message, a branch name or a tag.** A repository's object store holds
far more than file contents, and a leak in a commit subject is unreached by both.

**Two email shapes the public half misses, each pinned by a test (#211).** An address glued to a
home path or root with no separator reports the path row alone, and an address carrying an accented
letter is silent in tree mode, which runs under the C locale like history mode and CI. Both are the price of
rule C being linear rather than minutes on a long line; the scanner's header states them.

**Neither half hunts credentials.** This is about the developer's identity: home paths, personal
directory names, reachable addresses. An API key or a token is a different subject with a different
false-positive profile.

So for a repository about to go public, run a history-aware secret scanner as well:

```bash
gitleaks git .     # full history
gitleaks dir .     # the working tree
# every env-style file ever committed, including ones deleted since
git log --all --diff-filter=A --name-only --format= -- '*.env' '*.env.*' | sort -u
```

Running both is the answer. Neither covers the other, and a guard that implied otherwise would be
worse than a narrow one that admits it.

## Two halves, split by whether the check needs a secret

**A denylist of the private names cannot live in the repository it protects.** A public file
enumerating the names you have been hiding tells a reader exactly what to search the history for.
It converts a guard into an index. That single constraint forces the whole design.

| | Public half | Private half |
|---|---|---|
| Asset | `check-public-leaks.sh` | `check-private-leaks.sh` |
| Catches | path shapes, unlisted `~/` roots, addresses | private project and folder NAMES |
| Needs a secret | no | yes, a list of the names |
| Where it runs | CI, every contributor, plus both git hooks | local git hooks only |
| List lives | in the repo, tracked, public by construction | outside the repo, untracked, never published |

The private half is **deliberately not enforced in CI**, and that is not an oversight to be fixed
later. Running it there means putting the list in a CI secret, which recreates the index problem in
a place with worse access controls and more readers.

## The public half

```
check-public-leaks.sh [--staged | --range <base> | --all] [--allow-file <path>] [paths...]
```

Exit 0 clean, 1 on a finding, 2 when it could not run. One line per finding:
`<file>:<line>: <rule>: <evidence>`.

**Rule A, absolute home paths, by SHAPE.** `/home/<name>/` and `/Users/<name>/`, with the
placeholder forms allowed explicitly, because a document explaining where a file lives has to say
so.

**Rule B, `~/` roots, by ALLOWLIST.** Shape can decide that `/home/<user>/` is a placeholder and a
real first name is not. Shape cannot decide whether `~/<root>` is private, because the string
carries no marker either way. So the test is inverted: an allowlist of roots a document may show.
That catches the case by construction rather than by enumeration, and it asks one thing of the
project, **a canonical example root, agreed once**. A project without one has a different problem.
Neither rule reports a user segment or root that is entirely punctuation once trailing punctuation
is stripped (`/home/..`, `~/...`, `~/}`): a path idiom or a code fragment, not a person, and one no
allow-file entry could name either.

**Rule C, email addresses**, excluding the service accounts and the TLDs reserved by RFC 2606 and
RFC 6761, which cannot reach a mailbox.

The project's allow-file takes four keys, `root`, `prefix`, `email` and `skip`. An unrecognised key
**refuses the whole run** rather than skipping the line, because a silently ignored entry in a
security config is a guard reporting a coverage it does not have. The file is tracked and public on
purpose: everything in it is something the project decided it may show.

## The private half

```
check-private-leaks.sh [--staged | --range <base> | --all] [--list <path>]
                       [--allow-file <path>] [--show-names] [paths...]
```

> **The allow-file takes `skip` and nothing else.** It is the same
> `.leak-guard-allow` the public half reads, and this half honours only path globs from
> it: a generated lockfile that happens to contain a listed name, a test fixture using one
> as sample data. A **name** must never appear in it — the file is tracked and public, and
> a name there rebuilds the index the list exists to avoid. `root`, `prefix` and `email`
> are the public half's keys and are ignored here rather than refused, so one file serves
> both scanners.

**It reports a redacted name by default**, two leading characters and the length, and `--show-names`
prints it in full. The class of leak this component exists to stop is pasted output, and this hook's
own output is exactly that kind of text: printing the matched name in full makes pasting the failure
into a public issue the next leak. The file and line are enough to act on.

The list defaults to `~/.claude/forge-kit/private-names.txt`, one name per line. `--init` writes a
starter list there, commented with the rules below; it refuses to overwrite one that exists. The
template lives inside the script rather than beside it as a second file, because forge-adapt
installs a skill's `assets/*.sh` and nothing else, so a separate template would never arrive.

**It exits 0 with a loud explanation when the list is absent**, rather than failing closed on a
machine that never had one: a guard that blocks every fresh clone gets uninstalled, and an
uninstalled guard protects nothing.

**It REFUSES to run against a list the repository tracks.** That is the precondition the original
design wanted an installer step for, checked where it can actually be verified: the default path
is under the home directory and no project repo can track it, so this only fires when someone has
pointed `--list` at a file inside the tree. A tracked list is an active disclosure rather than a
missing check, so it refuses rather than warns, and says which command fixes it.

Two rules learned the hard way, both written into the list `--init` creates:

- **The account name that owns the repository on a public forge must not go in the list.** It
  appears in the public clone URL, so a denylist containing it refuses every commit that touches
  the README; the scanner drops it with a warning in the tree modes when origin is github.com,
  gitlab.com, codeberg.org or bitbucket.org. On a private forge origin the list is obeyed, and
  `--history` obeys it everywhere: a private organisation name is exactly what the going-public
  scan must catch. Public identity and private identity are different sets.
- **The list stays untracked.** Its entire security property is that it was never published. The
  default location is outside every project repository precisely so this cannot be got wrong by
  forgetting a `.gitignore` entry.

## Where it runs

Both stages, which is one decision taken explicitly rather than by default. The cheap staged scan
at commit gives fast feedback on what you are about to write down. The full-tree scan at push is
the one that matters the moment a history rewrite is ever needed, because it asks about the state
of the tree rather than about one change to it. A project that wires only the commit stage has the
weaker half of the pair.

## What this does NOT catch, and why it says so

**The public half would not have caught the leak that prompted the design.** That was a set of real
sibling-project folder names sitting in prose as demo data, and a folder name in prose contains no
path and no `@`. Rules A and C catch the pasted-traceback class, which is the one that recurs. Rule
B catches the `~/` class, which is the one that survived a full history scrub in the case that
prompted it. **Nothing public catches a bare project name.** That needs the list, and the list
cannot be public.

**And both path rules judge the FIRST segment only.** Rule A asks who `/home/<name>/` belongs to and
rule B asks whether `~/<root>` may be shown; neither looks below that. So a private directory name
under an allowed root, `~/work/<client>/repo` or `/home/user/clients/<client>/build.log`, is
invisible to the public half, and the segments above the project are exactly what the original
finding called the worse half of the leak.

**Decided 2026-09-09: this stays as it is** (issue #159). With a private-name list the case IS
caught, by name, so the gap is real only for someone who never wrote one, who is also the least
protected in general. The alternative was to allowlist every path segment rather than the root, and
a project would then have to allowlist every directory name appearing in any documented path: the
guard would fire constantly until somebody deleted it, which is the failure mode the near-miss cases
exist to prevent. A narrower guard that survives beats a thorough one that gets removed.

A guard that overstates its reach is worse than a narrow one that admits it, because the
overstatement is what stops anyone looking.

## If something already reached a public repository

Say this plainly to whoever is asking, because they are asking at the worst possible moment.

**A history rewrite is not a deletion.** A force push leaves the old objects unreferenced, not
removed, and the host may serve them by SHA until it garbage collects. If the repository was ever
public, the old commit ids are recoverable from archived public event feeds, so "unreachable by
default" is not a safety property here. There is no self-service purge on the major hosts; it is a
support request, and it is the only thing that actually removes the objects. Rotate anything that
was a credential rather than waiting for the purge, because the purge does not undo the copies.

Do the rewrite anyway, so the working history is clean. Just do not report it as a deletion.

**Replace the private string with a marker the scanner knows.** `check-public-leaks.sh` recognises
two, as literals: `[redacted]`, which this remediation uses, and `***REMOVED***`, which is what
`git filter-repo --replace-text` writes when an expression names no replacement. Either one in a
`~/` root or a `/home/` segment is not reported, in the tree modes or under `--history`, with or
without sentence punctuation after it, so the rewrite that removes the leak leaves the scan green. Any other replacement is reported as a root
until the repository allows it, and a marker is never a shape: any other bracketed name is still
a root.
