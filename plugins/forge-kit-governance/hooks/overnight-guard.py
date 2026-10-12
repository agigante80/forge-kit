#!/usr/bin/env python3
# overnight-guard-version: 19
"""PreToolUse Bash guard for destructive commands: an overnight arm and a daytime arm.

Two arming paths, one matcher. OVERNIGHT: while .claude/overnight/active.md is present, deny
destructive git and secrets/bulk-delete commands so a drifting overnight cycle cannot run them.
DAYTIME (#419): while .claude/no-destructive is present and no run is armed, deny the git
discards and the bulk deletes (never the secret-file or pipe-to-shell classes). With neither file
the guard is dormant. Overnight wins when both exist. Merge and protected-branch push are
intentionally NOT handled here (left to GitHub branch protection).

Contract (PreToolUse, same as block-dashes):
  stdin  <- {"tool_name": ..., "tool_input": {"command": ...}, "cwd": ...}
  stdout -> deny: hookSpecificOutput.permissionDecision = "deny" ; else nothing
  exit   -> ALWAYS 0.

Overnight fails CLOSED: when a run is armed and the command cannot be judged (unparseable
payload or a non-string command), deny. The daytime arm fails OPEN (exit 0, empty stdout) on an
unparseable payload, a missing or non-string command and a non-Bash tool, because a daytime hook
must not wedge an interactive session. When arming cannot be determined, allow (dormant).

The daytime sentinel is the opt-in in every install shape: this script has no path-shape logic,
so a project-local copy is inert without the file. forge-adapt creates it with the hook.

Not adversary-proof: matching is on the command string and catches a drifting
model doing the obvious thing, not a deliberate evasion.

Worktree target (#467): rm -rf of $PWD, $CLAUDE_PROJECT_DIR, $(pwd) or $(git rev-parse
--show-toplevel) is a dangerous target, found by reading the target words as a shell does.

Segment walk (#478): both arms judge EVERY rm command word of a payload, walking the segments left
to right and carrying the names assigned a ROOT word (`D=$PWD; rm -rf "$D"`, `B="$A"`, `$OLDPWD`
after a cd away from ROOT) and the tracked cwd (`cd .. && rm -rf <project>` denies; `cd .. && rm -rf
*` denies on both arms). ROOT, the starting cwd, cd targets and rm targets are realpath'd. The shapes
tracked, the shapes NOT followed (read, eval, set --, for, arrays, printf -v, source, assignments in
$( ) or a subshell, inherited variables, CDPATH, symlinks made in the same payload, subshell scope)
and the unknown-cwd false positive (`cd "$X" && rm -rf <project>` denies whatever $X holds) are
listed at _Walk below.

Known gap: a bare "git checkout <file>" (discarding one file without "--") is
not caught, because a regex cannot tell it apart from "git checkout <branch>";
the modern "git restore <file>" form is caught broadly.

Past 32 global options the git command is denied outright (#469, too long to judge). Known gap
(#457): git global options up to that cap are tolerated before the subcommand (GIT_PREFIX below), but
an alias defined inline, `git -c alias.x='reset --hard' x`, or `--config-env` pointing at an
alias, runs a destructive command under an arbitrary name. That is deliberate evasion, which this
guard does not defend against; it is not a bypass to file.
"""
import fnmatch
import json
import os
import re
import sys

SENTINEL = os.path.join(".claude", "overnight", "active.md")
DAY_SENTINEL = os.path.join(".claude", "no-destructive")


def env_project_dir():
    return os.environ.get("CLAUDE_PROJECT_DIR")


def armed(project_dir):
    return project_dir is not None and os.path.exists(os.path.join(project_dir, SENTINEL))


def day_armed(project_dir):
    return project_dir is not None and os.path.exists(os.path.join(project_dir, DAY_SENTINEL))


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


# THE CLASS EXCLUDES A NEWLINE, and that is load-bearing (#168). It used to be `[^|;&]*`, which
# matches a newline like any other character, so the pattern ran from a `git checkout` on one line
# to a `-f` on any later line of the same payload. In a real armed run that denied, in order:
# switching branches, writing a ticket ABOUT the command, and a script naming it in a test string.
#
# A guard that blocks the project's own documented workflow, and blocks documenting itself, is one
# people turn off, and an uninstalled guard protects nothing. Bounding to a single line keeps every
# real denial (a discard is written on the line that runs it) and removes the false ones.
#
# IT IS NOT A FULL FIX FOR PROSE, and the test pins that rather than wishing it away: a heredoc BODY
# line that is itself a destructive command still denies, because no regex over a shell payload can
# tell a line that RUNS from a line that is DATA. Writing a document that quotes such a command, in
# the same tool call, is therefore still refused. Write the file with a different tool.
#
# THE GIT PREFIX (#457). A git global option between `git` and the subcommand used to bypass every
# rule (`git -C sub reset --hard`). GIT_PREFIX is git's usage-line grammar, not a list of spellings:
# any dash token is a global option, and the options that take a value (-C, -c, and --git-dir,
# --work-tree, --namespace, --config-env, --attr-source in their space and = forms) also consume that value, so a
# value naming a subcommand (`git -c reset.hard=1 status`) is never mistaken for one. Quoted values
# may hold spaces. Prefix matching can only add denies.
#
# IT MUST STAY LINEAR, and that is the load-bearing part: Python's re has no backtracking limit and
# a hook that times out does not deny, so an ambiguous prefix fails the overnight arm OPEN. Two
# separate costs, both closed. (1) Ambiguity inside one match: every token must parse exactly one
# way. Option names: the dash-token alternative refuses the argument options followed by
# whitespace, `=`, a shell separator or the end, so `-c` and `--git-dir=x` match only the argument
# alternative. Values: every piece starts with a character no other piece can start with (a bare
# character excludes quotes, backslash, `$` before `(`, and backtick), so `"a"` matches only the
# quoted piece. (2) Retries: every `git` token is a fresh start, and `git -c git -c git -c ... x`
# makes each start walk the rest of the chain, which is quadratic and was measured at 55 s for
# 3200 pairs. The repeat is therefore bounded at GIT_PREFIX_MAX options, which makes the whole scan
# linear in the input (3200 pairs now take about 0.6 s). A run past the cap is DENIED (#469), not
# allowed: the guard cannot see the subcommand, so it fails closed at the bound it chose itself.
# That reverses the earlier "deliberate evasion, allowed" call (#457), which left a destructive
# subcommand behind 33 global options open on both arms; the cost is that a harmless 33-option
# command is denied too, which no real user types. GIT_CAP_PATTERN is the same chain with the
# repeat fixed at GIT_PREFIX_MAX + 1 and no trailing subcommand, so it stays linear (3200 pairs
# under 0.01 s: the leading chain matches and the scan stops).
# REDIRECTIONS IN THE PREFIX (#473). A redirection between `git` and the subcommand (or between
# global options) was not a prefix token, so no git rule saw the subcommand and `git 2>&1 reset
# --hard` was allowed on both arms. _GIT_REDIR is a third alternative of the SAME bounded repeat, so
# options and redirections interleave in any order and BOTH count toward GIT_PREFIX_MAX (33 mixed
# tokens hit the cap label; the cap pattern and the matcher cannot disagree, being one chain). It
# reads every operator (`>`, `>>`, `<`, `<<<`, `2>`, `>&N`, `&>`, `<&N`), with or without a space
# before the target; the `&` arrives as REDIR_AMP from _flat(). LINEAR, because a naive
# `\d*[<>]{1,3}\x01?\s*PIECE+` parses two ways and measured 9.8 s at 24 `>>a` tokens, doubling per
# token: `>>a` was `>>` + `a` or `>` + `>a`, and the optional \x01 was also a bare piece character.
# The target therefore may not start with `<`, `>` or REDIR_AMP (the lookahead), leaving one parse
# per token. The `>|` sentinel (REDIR_PIPE, #474) follows the same rule: the operator reads
# `[REDIR_AMP REDIR_PIPE]?` once and the target lookahead excludes both.
# A substitution body is bounded at 200 characters for the same reason: an unbounded `$(` scans to
# the line end from every start (16 s at 6000 `git -c $(` starts). A longer body is still allowed,
# a SEPARATE accepted gap that #469 did not close (the cap counts options, not value length).
# test-hooks.py times four 200-token shapes (one ambiguity each) and an 800-pair retry shape
# against both matchers.
REDIR_AMP = "\x01"   # what _flat() writes for a redirection's `&` (see below)
REDIR_PIPE = "\x02"  # what _flat() writes for the `|` of a noclobber redirection `>|` (#474)
_REDIR_MARK = REDIR_AMP + REDIR_PIPE
GIT_PREFIX_MAX = 32
_GIT_ARG_OPT = r"(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source)"
_GIT_PIECE = (r"""(?:[^\s|;&"'\\$`]"""            # a bare character
              r"""|\\."""                          # a backslash escape: `my\ dir`
              r"""|\$(?!\()"""                     # `$HOME`, not the start of a substitution
              r"""|\$\([^)\n]{0,200}\)|`[^`\n]{0,200}`"""      # `$(git rev-parse --show-toplevel)`
              r"""|"(?:[^"\\\n]|\\.)*"|'[^'\n]*')""")
_GIT_REDIR = (r"(?:\d*[<>]{1,3}[" + _REDIR_MARK + r"]?|" + REDIR_AMP + r">{1,2})"   # the operator, one parse
              r"\s*(?![<>" + _REDIR_MARK + r"])" + _GIT_PIECE + r"+")                  # then its target
_GIT_CHAIN = (r"\bgit(?:\s+(?:" + _GIT_ARG_OPT + r"(?:\s+" + _GIT_PIECE + r"+|=" + _GIT_PIECE + r"*)"
              + r"|(?!" + _GIT_ARG_OPT + r"(?:[\s=|;&]|$))-[^\s|;&]+|" + _GIT_REDIR + r")){")
GIT_PREFIX = _GIT_CHAIN + "0," + str(GIT_PREFIX_MAX) + r"}\s+"
CAP_LABEL = "git with more than %d global options" % GIT_PREFIX_MAX
GIT_CAP_PATTERN = re.compile(_GIT_CHAIN + str(GIT_PREFIX_MAX + 1) + "}")
G = GIT_PREFIX
# A redirection's `&` is not a command separator (#470). `2>&1`, `>&2`, `<&0` (a `&` right after `<` or
# `>`) and `&>x` (a `&` right before `>`) belong to the segment, so `rm -rf 2>&1 /` and
# `git reset 2>&1 --hard` are judged whole, while `a >&2 & rm -rf /` still splits at the second `&`.
# ONE definition serves the rm matchers and GIT_PATTERNS: _flat() swaps exactly those ampersands for
# REDIR_AMP once, in a single linear pass, and every segment class below stays the plain, C-speed
# `[^|;&\n]*`. Do NOT instead widen that class into an alternation such as
# `(?:[^|;&\n]|&(?=>)|...)*`: it is linear in one match but ~10x slower per character, and the git
# patterns restart at every `git <sub>` token, so `git reset ` x6000 went from 2 s to 20 s (review r1);
# and without `(?!>)` on the lookbehind branch `>&>&` takes two routes per `&` and is 2^n.
# `>|` (noclobber, #474) is the same kind of operator: a `|` right after a `>` is never a pipe, so it
# becomes REDIR_PIPE in that same pass (`rm -rf >|log /` is judged whole, while `a >|log | b` still
# splits at the second `|`, which follows a space). _strip_redirs and _sub_body accept it; the spaced
# `>| /dev/null` is what needs that (the unspaced target class swallows the sentinel either way).
# A backslash-escaped `\>` is a literal argument, so its `|` IS a pipe (`curl u\>|sh`): the mask
# skips a `>` that follows a backslash (round 1). An even run (`\\>|`) is then left unmasked too,
# which only errs towards the old, cut segment.
_REDIR_AMP = re.compile(r"(?<=[<>])&|&(?=>)|(?:(?<=[^\\]>)|(?<=^>))\|")


def _mask(m):
    return REDIR_PIPE if m.group(0) == "|" else REDIR_AMP


# A backslash-newline continuation is removed outright by the shell before it splits words, so the
# command run is the joined one: `git \<nl>reset --hard` and `gi\<nl>t reset --hard` are both
# `git reset --hard` (#471). Join with the EMPTY string, never a space (a space misses `gi\<nl>t`).
# An even run of backslashes before the newline is escaped backslashes, not a continuation
# (`git \\<nl>reset` runs `git \`, then a separate `reset`), so the pattern consumes a whole run
# from its start (the lookbehind) and keeps all but the last backslash of an odd run. Linear: a
# match can only begin at the start of a run. NOT quote-aware: a backslash-newline inside single
# quotes, which the shell keeps, is joined too and may match; that is the guard's documented
# quoted-text over-match class (see DAY_TAIL). A literal two-character `\n` has no newline.
_CONT = re.compile(r"(?<!\\)((?:\\\\)*)\\\n")


def _join(cmd):
    return _CONT.sub(r"\1", cmd)


# A redirection glued to `git` (`git>x reset --hard`, `git&>x ...`) is `git` plus a redirection token
# (#473 review r1). The chain wants whitespace before every token, and a second glued-token branch in
# the regex would parse `>"a">"a"` two ways (2^n), so the space is inserted here, once, linearly.
_GIT_GLUED = re.compile(r"\bgit(?=[<>" + REDIR_AMP + r"])")   # REDIR_PIPE never follows `git` directly


# The sentinels are in-band, so a payload that already holds a raw \x01 or \x02 would forge one:
# `rm -rf >\x02 /` is a redirection to a file named \x02 plus `rm -rf /`, but read as `>|` its
# spaced target `/` was stripped and the command allowed. A raw sentinel byte is first replaced by
# an ordinary word character, so only _flat() itself ever writes one. _flat() runs once per raw
# command, never on its own output, which would erase the sentinels it wrote.
_NO_MARK = str.maketrans(_REDIR_MARK, "__")


def _flat(cmd):
    return _GIT_GLUED.sub("git ", _REDIR_AMP.sub(_mask, cmd.translate(_NO_MARK)))


GIT_PATTERNS = [
    # Past the option cap the subcommand is out of sight, so deny (#469). Listed FIRST on purpose
    # (round 1 tried last and a test caught it): the cap matches a long chain in one pass, while the
    # later patterns each rescan it (3200 pairs: 0.6 s versus under 0.01 s). The price is that a
    # payload holding both a real destructive command and a 33-option run reports the cap label;
    # it is denied either way. The reason names the cap, not a destructive command (see _what).
    (CAP_LABEL, GIT_CAP_PATTERN),
    ("git reset --hard", re.compile(G + r"reset\b[^|;&\n]*--hard\b")),
    ("git branch -D", re.compile(G + r"branch\b[^|;&\n]*(-D\b|--delete\b[^|;&\n]*--force\b|--force\b[^|;&\n]*--delete\b)")),
    ("git push --delete / :ref", re.compile(G + r"push\b[^|;&\n]*(--delete\b|\s:\S)")),
    ("git tag -d", re.compile(G + r"tag\b[^|;&\n]*(-d\b|--delete\b)")),
    ("git clean -f", re.compile(G + r"clean\b[^|;&\n]*-\w*f")),
    ("git checkout discards working tree", re.compile(G + r"checkout\b[^|;&\n]*(\s--\s|\s\.(\s|$)|-f\b|--force\b)")),
    # --staged alone only unstages, but --staged WITH --worktree (or -W, also inside a cluster such
    # as -SW) rewrites the working tree too, in either order (#435). A switch forced with -f,
    # --force or --discard-changes throws away local edits; plain `git switch <branch>` refuses
    # to, and -C/--force-create resets a branch, not the tree, so it stays out.
    ("git restore discards working tree", re.compile(
        G + r"restore\b(?![^|;&\n]*--staged)"
        r"|" + G + r"restore\b[^|;&\n]*(--worktree(?![\w-])|\s-[a-zA-Z]*W)")),
    ("git switch discards working tree", re.compile(
        G + r"switch\b[^|;&\n]*(\s-[a-zA-Z]*f[a-zA-Z]*(\s|$)|\s--force(?![\w-])|\s--discard-changes(?![\w-]))")),
    ("git stash drop/clear", re.compile(G + r"stash\s+(drop|clear)\b")),
]

_GIT_RX = [rx for _, rx in GIT_PATTERNS]

SECRET_PATTERNS = [
    ("secret file access", re.compile(r"(^|[\s=/'\"])\.env(?!\.(example|sample|template|dist)\b)(\.[\w.]+)?(\b|['\"]|$)")),
    ("secret file access", re.compile(r"\bid_rsa\b")),
    ("secret file access", re.compile(r"[\w./-]+\.pem\b")),
    ("secret file access", re.compile(r"/secrets?/")),
    ("pipe to shell", re.compile(r"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python\d?)\b")),
]
# Patterns that read the _flat() text: the git rules and, since #474, pipe-to-shell, whose `[^|]*`
# would otherwise stop at the `|` of `>|` (`curl u >|f | sh` allowed, `curl x >|bash` denied).
_FLAT_RX = set(_GIT_RX) | {rx for label, rx in SECRET_PATTERNS if label == "pipe to shell"}


def _rm_force_recursive(seg):
    # Short flag clusters (-rf, -fR, ...) and the long forms (--force, --recursive).
    short = "".join(re.findall(r"(?:^|\s)-([a-zA-Z]+)\b", seg))
    force = "f" in short or bool(re.search(r"(?:^|\s)--force\b", seg))
    recursive = ("r" in short or "R" in short
                 or bool(re.search(r"(?:^|\s)--recursive\b", seg)))
    return force and recursive


# THE WORKTREE AS A TARGET (#467). `rm -rf "$PWD"` deletes the project, uncommitted work included.
# Spellings are not enumerated; the segment is split into words the way a shell does it, and a
# word is the worktree when its expansion IS one of the root expressions plus only slashes.
# Word grammar (sh): whitespace separates words; inside one word, adjacent pieces concatenate;
# a piece is a backslash escape (literal char), '...' (all literal, so '$PWD' is a file name),
# "..." (literal except $, backtick and backslash, so "$PWD" expands), $(...), `...`, ${...},
# $NAME, or a bare character. One left-to-right pass, every branch advances, so it is linear: an
# unterminated opener swallows the rest of the segment instead of rescanning (no regex retries).
_ROOT_PARAM = re.compile(r"(?:PWD|CLAUDE_PROJECT_DIR)(?::?[-=?][^}]*|%%?/)?")
# A substitution body whose output IS the worktree: pwd (builtin, command or a path, -L/-P
# options), the repo toplevel, or realpath/readlink of `.`. The body is whitespace-normalised and
# fullmatched, so `$(pwd /x)`, `$(pwdx)` and `$(find ...)` are never the worktree.
_ROOT_SUB = re.compile(
    r"(?:(?:builtin|command) )?(?:\S*/)?pwd(?: -[LP]+)*"
    r"|git(?: --no-pager| --no-optional-locks| -C \.)* rev-parse --show-toplevel"
    r"|(?:realpath|readlink -f|readlink -e) \.")
_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _sub_body(body):
    # Redirections inside a substitution (`$(pwd 2>/dev/null)`) do not change what it prints.
    # The lookbehind keeps a long digit run from being rescanned from every digit (linear).
    return " ".join(re.sub(r"(?<!\d)\d*[<>]+\s*[&\x01\x02]?\s*[^\s)`]*", " ", body).split())


def _rm_words(seg):
    """Split seg into shell words; each word is a list of (kind, text), kind lit|param|sub.

    A literal run is a list of strings (joined by the caller), so a very long word is built in
    linear time. `(`, `)`, `<` and `>` end a word, and the word after a redirection operator is
    its target, not an argument. A backtick with no closer in the segment ends a word (the closer
    sits in a part of the payload the rm segment was cut away from).
    """
    words, cur, i, n, skip = [], None, 0, len(seg), False

    def lit(w, ch):
        if w and w[-1][0] == "lit":
            w[-1][1].append(ch)
        else:
            w.append(("lit", [ch]))

    def end_word():
        nonlocal cur, skip
        if cur is not None:
            if skip:
                skip = False
            else:
                words.append(cur)
            cur = None

    def expand(w, i):
        # seg[i] is `$` or a backtick. Returns the index after the expansion.
        c = seg[i]
        if c == "`":
            j = seg.find("`", i + 1)
            j = n if j < 0 else j
            w.append(("sub", _sub_body(seg[i + 1:j])))
            return j + 1
        nxt = seg[i + 1:i + 2]
        if nxt == "(":
            depth, j = 1, i + 2
            while j < n and depth:
                depth += (seg[j] == "(") - (seg[j] == ")")
                j += 1
            w.append(("sub", _sub_body(seg[i + 2:j - 1 if depth == 0 else j])))
            return j
        if nxt == "{":
            j = seg.find("}", i + 2)
            j = n if j < 0 else j
            w.append(("param", seg[i + 2:j]))
            return j + 1
        m = _NAME.match(seg, i + 1)
        if m:
            w.append(("param", m.group(0)))
            return m.end()
        lit(w, "$")
        return i + 1

    while i < n:
        c = seg[i]
        if cur is None and c == "#":
            break   # a word-initial `#` starts a comment: nothing after it is an argument
        if c.isspace() or c in "()<>" or (c == "`" and seg.find("`", i + 1) < 0):
            end_word()
            if seg.startswith("<<<", i):
                i += 3   # a here-string's word is DATA fed to the command (`xargs rm`), so it is kept
                continue
            skip = skip or c in "<>"
            i += 1
            continue
        if cur is None:
            cur = []
        if c == "\\":
            if i + 1 < n:
                lit(cur, seg[i + 1])
            i += 2
        elif c == "'":
            j = seg.find("'", i + 1)
            j = n if j < 0 else j
            lit(cur, seg[i + 1:j])
            i = j + 1
        elif c == '"':
            i += 1
            while i < n and seg[i] != '"':
                if seg[i] == "\\" and i + 1 < n:
                    lit(cur, seg[i + 1] if seg[i + 1] in '$`"\\' else seg[i:i + 2])
                    i += 2
                elif seg[i] in "$`":
                    i = expand(cur, i)
                else:
                    lit(cur, seg[i])
                    i += 1
            i += 1
        elif c in "$`":
            i = expand(cur, i)
        else:
            lit(cur, c)
            i += 1
    end_word()
    return words


def _is_worktree_word(w):
    w = [(k, "".join(t) if k == "lit" else t) for k, t in w]
    w = [(k, t) for k, t in w if not (k == "lit" and t == "")]
    if not w:
        return False
    kind, text = w[0]
    if kind == "param":
        if not _ROOT_PARAM.fullmatch(text):
            return False
    elif kind != "sub" or not _ROOT_SUB.fullmatch(text):
        return False
    return all(k == "lit" and t.strip("/") == "" for k, t in w[1:])


def _norm(w):
    # A word as (kind, text) pieces with the empty literals dropped.
    w = [(k, "".join(t) if k == "lit" else t) for k, t in w]
    return [(k, t) for k, t in w if not (k == "lit" and t == "")]


def _lit(w):
    # The text of an all-literal (normalised) word, or None when it holds an expansion.
    if not w:
        return ""
    return w[0][1] if len(w) == 1 and w[0][0] == "lit" else None


def _param_alone(w):
    # The name of `$NAME`, `${NAME}` or `"$NAME"`, optionally followed by slashes only; else None.
    if w and w[0][0] == "param" and _NAME.fullmatch(w[0][1]) \
            and all(k == "lit" and t.strip("/") == "" for k, t in w[1:]):
        return w[0][1]
    return None


def _real(path):
    try:
        return os.path.realpath(path)
    except (ValueError, OSError):   # an embedded NUL byte: compare it unresolved
        return os.path.normpath(path)


# THE SEGMENT WALK (#478). A target can name the project without spelling it: through a name
# assigned earlier (`D=$PWD; rm -rf "$D"`) or after a directory change (`cd .. && rm -rf <project>`).
# Both live in an EARLIER segment than the rm, so the matchers walk the segments left to right in one
# pass, carrying the ROOT-tainted names and the tracked cwd. ROOT is the protected root resolved with
# realpath once; the cwd starts at the payload's absolute `cwd`, else ROOT, and every cd target and rm
# target is realpath'd too, so a project reached through a symlink compares in one namespace.
#   Tracked: NAME=value, and export/declare/local/readonly/typeset NAME=value (a value that is a ROOT
#   word, `.`, or a tainted name taints; any other value clears); cd, pushd, popd, builtin cd and
#   command cd, with -L -P -e -@ and -- stripped.
#   NOT followed (accepted limits): read, eval, set --, for NAME in, arrays, printf -v, a sourced
#   file, an assignment inside $( ) or a subshell, any variable inherited from the environment,
#   CDPATH, and symlinks created earlier in the same payload. Parentheses are not scoped, so a cd in
#   a subshell is treated as persisting: `(cd ..) && rm -rf <project>` is a false deny.
#   An UNKNOWN cwd (`cd -`, popd, pushd with no argument or +N/-N, or a cd argument holding any
#   other expansion) is sticky for the rest of the payload. Under it a relative target is denied only
#   when its components are a run of ROOT's components ending at ROOT's basename; known false
#   positive: `cd "$X" && rm -rf <project>` is denied even when $X holds an unrelated directory with a
#   `<project>` of its own, and an ancestor named that way (`cd "$X" && rm -rf tmp`) is not denied.
_SEG = re.compile(r"[^|;&\n]+")
# A command word `rm`: not part of a longer word or `$rm`, and not docker's `--rm`. A `-` alone before
# it is no exclusion (round 1 of #478): `${RM:-rm} -rf /` and `"${RM-rm}" -rf ~` run rm. `git rm` is
# excluded by _git_sub, not by a lookbehind, because `(?<!git )` also matched a USER named git:
# `sudo -u git rm -rf ~` and `runuser -u git rm -rf "$HOME"` run rm. No tail on the pattern: the
# segment is cut at the match start once, so a run of `git rm` candidates stays linear.
_RM_WORD = re.compile(r"(?<![\w.$])(?<!--)rm\b")
_STMT_HINT = re.compile(r"=|\b(?:cd|pushd|popd)\b")
_KEYWORDS = frozenset(("if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"))
_DECLARE = frozenset(("export", "declare", "local", "readonly", "typeset"))
_CD_OPT = re.compile(r"-[LPe@]+")
_ASSIGN = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)=(.*)", re.S)


def _git_sub(seg, i):
    # The `rm` at seg[i] is git's subcommand: the word before it is exactly `git` and the word before
    # that is not an option (`sudo -u git rm` runs rm as the user git; `--user=git rm` and `-ugit rm`
    # fail the "exactly" test). Index walks only, each over words no other candidate walks: linear.
    j = i
    while j > 0 and seg[j - 1] in " \t":
        j -= 1
    k = j - 3
    if j == i or k < 0 or seg[k:j] != "git" or (k > 0 and seg[k - 1] not in " \t"):
        return False
    m = k
    while m > 0 and seg[m - 1] in " \t":
        m -= 1
    s = m
    while s > 0 and seg[s - 1] not in " \t":
        s -= 1
    return m == 0 or seg[s] != "-"


class _Walk:
    def __init__(self, root=None, cwd=None):
        raw = root if isinstance(root, str) and root else os.getcwd()
        self.root = _real(raw)
        self.parts = [p for p in self.root.split("/") if p]
        self.cwd = _real(cwd) if isinstance(cwd, str) and os.path.isabs(cwd) else self.root
        self.oldpwd = None
        self.tainted = set()

    def hits_root(self, path):
        # The path is ROOT or one of its ancestors.
        return path == self.root or self.root.startswith(path.rstrip("/") + "/")

    def root_word(self, w):
        # w is normalised. A ROOT word: a worktree spelling, a tainted name, or $OLDPWD left at ROOT.
        if _is_worktree_word(w):
            return True
        name = _param_alone(w)
        return name is not None and (name in self.tainted
                                     or (name == "OLDPWD" and self.oldpwd == self.root))

    def statement(self, words):
        ws = [_norm(w) for w in words]
        i = 0
        while i < len(ws) and _lit(ws[i]) in _KEYWORDS:
            i += 1
        if i < len(ws) and _lit(ws[i]) in ("builtin", "command"):
            i += 1
        head = _lit(ws[i]) if i < len(ws) else None
        if head in ("cd", "pushd", "popd"):
            self.cd(head, ws[i + 1:])
            return
        if head in _DECLARE:
            assigns = ws[i + 1:]   # an option (`declare -r`, `export -n`) is skipped by the loop below
        else:
            assigns = ws[i:]
            if not assigns or any(not (w and w[0][0] == "lit" and _ASSIGN.match(w[0][1])) for w in assigns):
                return   # a command, not a statement of assignments (`x=1 make` sets nothing here)
        for w in assigns:
            m = _ASSIGN.match(w[0][1]) if w and w[0][0] == "lit" else None
            if not m:
                continue   # skip, never stop: `declare -r D=$PWD` still assigns D (round 1 of #478)
            value = ([("lit", m.group(2))] if m.group(2) else []) + w[1:]
            if self.root_word(value) or _lit(value) in (".", "./"):
                self.tainted.add(m.group(1))
            else:
                self.tainted.discard(m.group(1))

    def cd(self, head, args):
        if self.cwd is None:
            return   # UNKNOWN is sticky
        new = None
        if head != "popd":
            k = 0   # an index, not args = args[1:], which made 40000 options quadratic (8 s)
            while k < len(args) and _CD_OPT.fullmatch(_lit(args[k]) or ""):
                k += 1
            if k < len(args) and _lit(args[k]) == "--":
                k += 1
            args = args[k:]
            if not args:
                new = None if head == "pushd" else _real(os.path.expanduser("~"))
            else:
                a, t = args[0], _lit(args[0])
                if t is not None:
                    if (head == "cd" and t == "-") or (head == "pushd" and re.fullmatch(r"[+-]\d+", t)):
                        new = None
                    elif t == "~" or t.startswith("~/"):
                        new = _real(os.path.join(os.path.expanduser("~"), t[2:]))
                    else:
                        new = _real(os.path.join(self.cwd, t))
                elif _param_alone(a) == "HOME":
                    new = _real(os.path.expanduser("~"))
                elif self.root_word(a):
                    new = self.root
                elif _param_alone(a) == "OLDPWD" and self.oldpwd is not None:
                    new = self.oldpwd
        self.oldpwd, self.cwd = self.cwd, new

    def target_dangerous(self, w):
        # w is a normalised rm target word (not an option).
        if self.root_word(w):
            return True
        if _param_alone(w) == "OLDPWD" and self.oldpwd is not None:
            return self.hits_root(self.oldpwd)
        t = _lit(w)
        if not t or t.startswith(("/", "~")):
            return False   # empty, or already judged by the absolute-path rule
        glob = any(c in t for c in "*?[")
        if self.cwd is None:
            comps = [c for c in t.split("/") if c not in ("", ".")]
            return (not glob and 0 < len(comps) <= len(self.parts)
                    and comps == self.parts[len(self.parts) - len(comps):])
        if not glob:
            return self.hits_root(_real(os.path.join(self.cwd, t)))
        # A glob whose directory is a strict ancestor of ROOT and that matches ROOT's next component.
        d, base = os.path.split(t.rstrip("/"))
        if any(c in d for c in "*?["):
            return False
        d = _real(os.path.join(self.cwd, d))
        prefix = d.rstrip("/") + "/"
        if not self.root.startswith(prefix):
            return False
        return fnmatch.fnmatchcase(self.root[len(prefix):].split("/")[0], base)


def _rm_dangerous(seg, st=None):
    # A dangerous target may be preceded by whitespace, "=", or a quote (a quote
    # before the path must not hide it, mirroring the .env pattern's prefix class).
    if re.search(r"(^|[\s='\"])(/|~|\$\{?HOME)", seg) or ".." in seg:
        return True
    words = _rm_words(seg)
    if any(_is_worktree_word(w) for w in words):
        return True
    if st is None:
        return False
    opts = True
    for w in words[1:]:   # words[0] is the rm command word itself
        w = _norm(w)
        t = _lit(w)
        if opts and t is not None and t.startswith("-"):
            opts = t != "--"
            continue
        if st.target_dangerous(w):
            return True
    return False


def _strip_redirs(seg):
    # Drop output redirections (`> f`, `2>&1`, `&>f`, `>& f`) so a target such as /dev/null is not
    # read as an rm target (#470, both arms). A REDIR_AMP left in a word
    # (`<&0`) is inert: `<` ends the word. The lookbehind keeps the digit run linear.
    return re.sub(r"(?<!\d)\d*" + REDIR_AMP + r"?>>?[" + _REDIR_MARK + r"]?\s*[^\s)`]+", " ", seg)


def _rm_segments(cmd, root=None, cwd=None):
    # One left-to-right pass (#478): yields each `rm -rf` segment, redirections stripped, with
    # whether it hits a dangerous target given the state built from the segments before it.
    st = _Walk(root, cwd)
    for m in _SEG.finditer(_flat(cmd)):
        seg = m.group(0)
        r = _RM_WORD.search(seg)
        while r and _git_sub(seg, r.start()):
            r = _RM_WORD.search(seg, r.end())
        if r:
            rs = _strip_redirs(seg[r.start():])
            # GNU rm permutes arguments, so flags may follow a target: judge the whole segment.
            if _rm_force_recursive(rs):
                yield rs, _rm_dangerous(rs, st)
        elif _STMT_HINT.search(seg):
            st.statement(_rm_words(seg))


def is_bulk_delete(cmd, root=None, cwd=None):
    # OVERNIGHT rule: every rm command word in the payload is judged (#478; it used to be the first
    # only). There is no wildcard class overnight, except a glob reaching ROOT from an ancestor cwd.
    return any(danger for _, danger in _rm_segments(cmd, root, cwd))


def _rm_wildcard(seg):
    # DAYTIME only: a non-flag target whose last character is `*` after stripping one pair of
    # surrounding quotes and one trailing slash (`tmp/*`, `./*`, `*`, `tmp/impl-*`, `tmp/*/`).
    # `tmp/*.log` ends in `.log` and a specific path ends in a name, so both stay allowed.
    for tok in seg.split()[1:]:
        if tok.startswith("-") and tok != "--":
            continue
        t = tok.strip("'\"`)}")
        if t.endswith("/"):
            t = t[:-1]
        if t.endswith("*"):
            return True
    return False


def day_bulk_delete(cmd, root=None, cwd=None):
    # DAYTIME judges EVERY rm segment, so `rm -rf build && rm -rf tmp/*` and `cd tmp && rm -rf *`
    # are both caught. Review r1 (#419): a command word `rm` only (not `docker run --rm` or
    # `git rm`), flags read across the whole segment, redirections dropped, `\<newline>` joined, a
    # trailing `)`/`}`/backtick ignored. A bare `.` target is judged only through the tracked cwd
    # (#478): a `.` inside `$(find . ...)` is not a literal target and stays allowed. The dangerous
    # check runs before the wildcard one, so `cd .. && rm -rf *` reports the dangerous label.
    for seg, danger in _rm_segments(cmd, root, cwd):
        if danger:
            return "rm -rf dangerous target"
        if _rm_wildcard(seg):
            return "rm -rf wildcard target"
    return None


def match_tier3(cmd, root=None, cwd=None):
    # root is the raw protected root (realpath'd by the walk; os.getcwd() when None); cwd is the
    # payload cwd, used as the starting cwd only when it is an absolute path.
    cmd = _join(cmd)
    flat = _flat(cmd)
    for label, rx in GIT_PATTERNS + SECRET_PATTERNS:
        if rx.search(flat if rx in _FLAT_RX else cmd):
            return label
    if is_bulk_delete(cmd, root=root, cwd=cwd):
        return "rm -rf dangerous target"
    return None


def match_day(cmd, root=None, cwd=None):
    # GIT_PATTERNS plus bulk delete; SECRET_PATTERNS are deliberately absent (reading .env and
    # `curl ... | sh` installers are routine by day; decided in #419).
    cmd = _join(cmd)
    flat = _flat(cmd)
    for label, rx in GIT_PATTERNS:
        if rx.search(flat):
            return label
    return day_bulk_delete(cmd, root=root, cwd=cwd)


PARK = " Do not retry; record it in .claude/overnight/decisions.md and move on."

DAY_TAIL = (" A command that only quotes a dangerous string can go through the Write, Read or Grep"
            " tool or --body-file instead."
            " Do not retry another way; tell the user what you wanted to remove or discard.")


def _what(hit, kind):
    # The cap deny (#469) cannot see a subcommand, so it must not claim a destructive command.
    if hit == CAP_LABEL:
        return f"a {hit} (too long to judge)"
    return f"{kind} ({hit})"


def day_reason(hit):
    return (f"overnight-guard: blocked {_what(hit, 'a destructive command')}; .claude/no-destructive is"
            f" present in this project.{DAY_TAIL}")


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        payload = None
    if not isinstance(payload, dict):
        if armed(env_project_dir()):
            return deny("overnight-guard: unparseable tool payload while a run is armed; blocked (fail closed)." + PARK)
        return 0   # daytime arm: fail open
    proj = env_project_dir() or payload.get("cwd") or os.getcwd()
    overnight = armed(proj)   # overnight takes precedence when both sentinels exist
    if not overnight and not day_armed(proj):
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str):
        if overnight:
            return deny("overnight-guard: Bash call with no readable command while armed; blocked (fail closed)." + PARK)
        return 0   # daytime arm: fail open
    if overnight:
        hit = match_tier3(command, root=proj, cwd=payload.get("cwd"))
        if hit:
            return deny(f"overnight-guard: blocked {_what(hit, 'a Tier-3 destructive command')} during an armed overnight run." + PARK)
        return 0
    hit = match_day(command, root=proj, cwd=payload.get("cwd"))
    if hit:
        return deny(day_reason(hit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
