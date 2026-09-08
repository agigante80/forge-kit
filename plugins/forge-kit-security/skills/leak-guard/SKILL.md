---
name: leak-guard
description: Stop the developer's own machine leaking into a repository that is about to be made public. Home paths, "~/" roots and email addresses are caught in the open by a CI-runnable scanner; private project names are caught by a list held OUTSIDE the repository, because a committed denylist of the names you are hiding is an index pointing at them. Use when setting up a repo that will go public, when a scan reports a hit, or when someone asks how to remove something already pushed.
---

<!-- leak-guard-version: 2 -->

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

**Rule C, email addresses**, excluding the service accounts and the TLDs reserved by RFC 2606 and
RFC 6761, which cannot reach a mailbox.

The project's allow-file takes four keys, `root`, `prefix`, `email` and `skip`. An unrecognised key
**refuses the whole run** rather than skipping the line, because a silently ignored entry in a
security config is a guard reporting a coverage it does not have. The file is tracked and public on
purpose: everything in it is something the project decided it may show.

## The private half

```
check-private-leaks.sh [--staged | --range <base> | --all] [--list <path>] [--show-names] [paths...]
```

**It reports a redacted name by default**, two leading characters and the length, and `--show-names`
prints it in full. The class of leak this component exists to stop is pasted output, and this hook's
own output is exactly that kind of text: printing the matched name in full makes pasting the failure
into a public issue the next leak. The file and line are enough to act on.

The list defaults to `~/.claude/forge-kit/private-names.txt`, one name per line. **It exits 0 with
a loud explanation when the list is absent**, rather than failing closed on a machine that never
had one: a guard that blocks every fresh clone gets uninstalled, and an uninstalled guard protects
nothing.

Two rules learned the hard way, both carried as comments in the shipped template:

- **The account name that owns the repository must not go in the list.** It appears in the
  repository's own clone URL, so a denylist containing it refuses every commit that touches the
  README. Public identity and private identity are different sets.
- **The list stays untracked.** Its entire security property is that it was never published, and
  the directory holding it must be gitignored before the guard is worth anything.

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
