#!/usr/bin/env python3
# overnight-guard-version: 13
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
--show-toplevel) is a dangerous target, found by reading the target words as a shell does. The
overnight arm still judges only the first rm of a payload (a known limit, pinned in test-hooks.py).

Known gap: a bare "git checkout <file>" (discarding one file without "--") is
not caught, because a regex cannot tell it apart from "git checkout <branch>";
the modern "git restore <file>" form is caught broadly.

Past 32 global options the git command is denied outright (#469, too long to judge). Known gap
(#457): git global options up to that cap are tolerated before the subcommand (GIT_PREFIX below), but
an alias defined inline, `git -c alias.x='reset --hard' x`, or `--config-env` pointing at an
alias, runs a destructive command under an arbitrary name. That is deliberate evasion, which this
guard does not defend against; it is not a bypass to file.
"""
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
# A substitution body is bounded at 200 characters for the same reason: an unbounded `$(` scans to
# the line end from every start (16 s at 6000 `git -c $(` starts). A longer body is still allowed,
# a SEPARATE accepted gap that #469 did not close (the cap counts options, not value length).
# test-hooks.py times four 200-token shapes (one ambiguity each) and an 800-pair retry shape
# against both matchers.
GIT_PREFIX_MAX = 32
_GIT_ARG_OPT = r"(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env|--attr-source)"
_GIT_PIECE = (r"""(?:[^\s|;&"'\\$`]"""            # a bare character
              r"""|\\."""                          # a backslash escape: `my\ dir`
              r"""|\$(?!\()"""                     # `$HOME`, not the start of a substitution
              r"""|\$\([^)\n]{0,200}\)|`[^`\n]{0,200}`"""      # `$(git rev-parse --show-toplevel)`
              r"""|"(?:[^"\\\n]|\\.)*"|'[^'\n]*')""")
_GIT_CHAIN = (r"\bgit(?:\s+(?:" + _GIT_ARG_OPT + r"(?:\s+" + _GIT_PIECE + r"+|=" + _GIT_PIECE + r"*)"
              + r"|(?!" + _GIT_ARG_OPT + r"(?:[\s=|;&]|$))-[^\s|;&]+)){")
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
REDIR_AMP = "\x01"
_REDIR_AMP = re.compile(r"(?<=[<>])&|&(?=>)")


def _flat(cmd):
    return _REDIR_AMP.sub(REDIR_AMP, cmd)


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
    return " ".join(re.sub(r"(?<!\d)\d*[<>]+\s*[&\x01]?\s*[^\s)`]*", " ", body).split())


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


def _rm_dangerous(seg):
    # A dangerous target may be preceded by whitespace, "=", or a quote (a quote
    # before the path must not hide it, mirroring the .env pattern's prefix class).
    if re.search(r"(^|[\s='\"])(/|~|\$\{?HOME)", seg) or ".." in seg:
        return True
    return any(_is_worktree_word(w) for w in _rm_words(seg))


def _strip_redirs(seg):
    # Drop output redirections (`> f`, `2>&1`, `&>f`, `>& f`) so a target such as /dev/null is not
    # read as an rm target (#470, both arms). A REDIR_AMP left in a word
    # (`<&0`) is inert: `<` ends the word. The lookbehind keeps the digit run linear.
    return re.sub(r"(?<!\d)\d*" + REDIR_AMP + r"?>>?" + REDIR_AMP + r"?\s*[^\s)`]+", " ", seg)


def is_bulk_delete(cmd):
    # OVERNIGHT rule, unchanged by #419: only the FIRST rm in a payload is judged, so
    # `rm -f a.txt && rm -rf $HOME/x` is allowed overnight (pinned by test-hooks.py).
    cmd = cmd.replace("\\\n", " ")   # a continued line is one command (#467 review: same as daytime)
    cmd = _flat(cmd)
    m = re.search(r"\brm\b[^|;&\n]*", cmd)
    if not m:
        return False
    seg = _strip_redirs(m.group(0))
    return _rm_force_recursive(seg) and _rm_dangerous(seg)


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


def day_bulk_delete(cmd):
    # DAYTIME judges EVERY rm segment (overnight judges the first only), so
    # `rm -rf build && rm -rf tmp/*` and `cd tmp && rm -rf *` are both caught.
    # Review r1 (#419): a command word `rm` only (not `docker run --rm` or `git rm`), flags
    # read across the whole segment, redirections dropped, `\<newline>` joined, a
    # trailing `)`/`}`/backtick ignored. A bare `.` target is NOT judged: GNU rm refuses it,
    # and a `.` inside `$(find . ...)` must stay allowed.
    cmd = _flat(cmd.replace("\\\n", " "))
    for m in re.finditer(r"(?<![\w.$-])(?<!git )rm\b[^|;&\n]*", cmd):
        seg = _strip_redirs(m.group(0))
        # GNU rm permutes arguments, so flags may follow a target: judge the whole segment.
        if not _rm_force_recursive(seg):
            continue
        if _rm_dangerous(seg):
            return "rm -rf dangerous target"
        if _rm_wildcard(seg):
            return "rm -rf wildcard target"
    return None


def match_tier3(cmd):
    flat = _flat(cmd)
    for label, rx in GIT_PATTERNS + SECRET_PATTERNS:
        if rx.search(flat if rx in _GIT_RX else cmd):
            return label
    if is_bulk_delete(cmd):
        return "rm -rf dangerous target"
    return None


def match_day(cmd):
    # GIT_PATTERNS plus bulk delete; SECRET_PATTERNS are deliberately absent (reading .env and
    # `curl ... | sh` installers are routine by day; decided in #419).
    flat = _flat(cmd)
    for label, rx in GIT_PATTERNS:
        if rx.search(flat):
            return label
    return day_bulk_delete(cmd)


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
        hit = match_tier3(command)
        if hit:
            return deny(f"overnight-guard: blocked {_what(hit, 'a Tier-3 destructive command')} during an armed overnight run." + PARK)
        return 0
    hit = match_day(command)
    if hit:
        return deny(day_reason(hit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
