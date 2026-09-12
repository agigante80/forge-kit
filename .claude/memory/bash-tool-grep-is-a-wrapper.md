---
name: bash-tool-grep-is-a-wrapper
description: grep here is a function exec'ing ugrep -I; a claim measured through it about grep was false and retracted (#198); use command grep before a number becomes a claim
metadata:
  type: project
---

The Bash tool in this environment defines `grep` as a shell FUNCTION that execs ugrep with `-I` (binary files: no match). Found 2026-09-12 when a "fact" measured here, that `grep -c` prints nothing over a `git cat-file --batch` stream, went into a ticket and the gate could not reproduce it with GNU or busybox grep: the stream contains NUL (tree objects), `-I` skipped it, and the function printed nothing where real `grep -c` prints the count.

**Why:** a measurement made through a wrapper is a measurement of the wrapper. It went into #198's body as a claim about GNU grep and was retracted a round later.

**How to apply:** when a number or a behaviour observed in this shell is about to become a claim in a ticket or a header, re-run it with `command grep` (and `type <tool>` for anything else that looks odd), or say which tool was observed. Related: [[a-ticket-assertion-is-a-claim-check-it]], [[gh-cli-cannot-read-tmp]].
