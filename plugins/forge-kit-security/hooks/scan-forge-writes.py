#!/usr/bin/env python3
# scan-forge-writes-version: 3
"""PreToolUse Bash guard: scan an issue or PR body and title for leaks before gh publishes them (#536).

The leak guard scans files (pre-commit, pre-push, CI). Text typed straight into
`gh issue|pr create|edit|comment` never touches a file the guard sees, and a forge keeps every
earlier revision of an edited body readable, so a leak published there cannot be taken back from
the forge side. This hook reads the body and the title out of the command, copies each to a private
temp file, and runs both leak scanners on that copy.

Scope: `gh issue|pr create|edit|comment`, body (--body, -b, --body-file, -F) and title (--title,
-t). Nothing else: other gh subcommands that publish text, `gh api`, every forge_* call, a body on
stdin from a pipe, a variable, an editor or the web are NOT scanned (known-bypass list in
skills/leak-guard/references/forge-writes.md). A body it cannot see is ALLOWED with a one-line
stderr note, because a hook that blocks every unparsed gh call is disabled within a day.

Contract (PreToolUse, same as block-dashes and no-poll-loops):
  stdin  <- {"tool_name": "Bash", "tool_input": {"command": ...}, "cwd": ...}
  stdout -> deny: hookSpecificOutput.permissionDecision = "deny" with the reason
            `leak-guard: <flag> (write <K>) line <N> (<rule>)`; otherwise nothing
  stderr -> at most one fixed `leak-guard: ...` note per kind, never a path, a name or the command
  exit   -> ALWAYS 0. Exit 2 is Claude Code's deny signal and is never used.

The reason carries a flag, a write index, a line and a rule and NOTHING a scanner printed: the
public scanner prints its evidence unredacted and the private one redacts only by default.

Time: ONE hook-wide deadline of 8 s; each scanner run gets min(4 s, remaining time) in its own
process group; past the deadline the hook allows with `leak-guard: scan timed out`. hooks.json
sets timeout 10 for the whole hook.

Opt-in: sentinel `.claude/scan-forge-writes` (hooks.json gates on it in the shell; the check here
is defence in depth). Ships plugin-only: the scanners are resolved from this plugin's own
skills/leak-guard/assets/, so a project-local copy would lose them.

Self-test: `python3 scan-forge-writes.py --self-test` runs a verdict matrix against stub scanners.
It runs in CI via `scripts/test-hooks.py`.
"""
import json
import os
import re
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time

SENTINEL = os.path.join(".claude", "scan-forge-writes")
CAP = 1048576            # bytes; a longer body is allowed with a note (decision g)
DEADLINE = 8.0           # seconds, hook-wide
PER_SCAN = 4.0           # seconds, ceiling per scanner run

EXP = "\x01"             # an expanding $ or backtick: the value is not a literal
INERT = "\x03"           # a quote or backslash inside $( ) inside "...": inert for shlex
HDM = "\x02"             # heredoc placeholder bracket
# Operator characters INSIDE quotes (or escaped) are mapped out of shlex's punctuation set, so
# `"fix(x)"` and `";"` are words and never separators. Restored before a value is used.
_OPS = ";&|()<>"
_MAP = {c: chr(0xE001 + i) for i, c in enumerate(_OPS)}
_UNMAP = {v: k for k, v in _MAP.items()}
_UNMAP_TABLE = str.maketrans(_UNMAP)

NOTE_STDIN = "leak-guard: stdin body not scanned"
NOTE_HEREDOC = "leak-guard: heredoc body not scanned"
NOTE_SAME_CMD = "leak-guard: body written in the same command not scanned"
NOTE_NOT_REGULAR = "leak-guard: body not a regular file, not scanned"
NOTE_UNREADABLE = "leak-guard: body file unreadable, not scanned"
NOTE_NOT_EXTRACTABLE = "leak-guard: body not extractable, not scanned"
NOTE_PAYLOAD = "leak-guard: payload not understood, not scanned"
NOTE_DID_NOT_RUN = "leak-guard: scan did not run"
NOTE_TIMED_OUT = "leak-guard: scan timed out"
NOTE_OVER_CAP = "leak-guard: body over %d bytes not scanned" % CAP
NOTE_BINARY = "leak-guard: binary body not scanned"

WRITE_SUBS = ("create", "edit", "comment")
WRAPPERS = ("command", "exec", "time", "nohup", "env", "builtin")
# Shell reserved words that can precede a command in the same segment (`do gh ...`, `{ gh ...`).
RESERVED = ("{", "!", "if", "elif", "then", "else", "do", "while", "until")
# Flags whose value the command text carries (long form, short form).
TEXT_FLAGS = {"--body": "text", "-b": "text", "--title": "text", "-t": "text",
              "--body-file": "file", "-F": "file"}
# Flags that make gh take the body from somewhere the command text does not show.
UNSEEN = {"--editor", "-e", "--web", "-w", "-T", "--template", "--fill", "-f",
          "--fill-first", "--fill-verbose", "--edit-last"}


class Gone(Exception):
    """Raised to leave a parse with a note: the text cannot be judged."""


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


# --- parsing -----------------------------------------------------------------------------------

def prepass(cmd):
    """Quote-aware rewrite of the command into text shlex can word-split safely.

    Returns (text, heredocs, unbalanced, spans). `spans` are the source texts of every outermost
    `$( )` inside "..." and every backtick pair: their content is invisible in `text` (inert or
    behind an EXP), so judge() parses each again as a command of its own. Heredocs are lifted out as `\\x02N\\x02` placeholders
    (a `<<` inside a quote is text, not a heredoc), top-level newlines become ` ; `, operator
    characters inside quotes are mapped away from shlex's punctuation set, and every expanding
    `$` or backtick becomes `\\x01` so a value holding one is known not to be a literal.
    """
    out, hds, pending, spans = [], [], [], []
    stack = ["top"]
    rec = {}                 # stack depth -> source start of a recorded outermost dsub
    bt = None                # source start of an open outermost backtick pair
    i, n = 0, len(cmd)

    def mapc(c):
        return _MAP.get(c, c)

    def comment_start(pos):
        # `#` begins a comment only where a word could begin: at 0, after whitespace, or after an
        # unescaped operator character. `$#`, `${#x}` and `issue#5` are text.
        # An escaped blank (`a\ #b`) or a backslash-newline (`x\<NL>#`) does not end the word, so
        # the character before `#` counts only when an even run of backslashes precedes it.
        if pos == 0:
            return True
        prev = cmd[pos - 1]
        if prev in " \t\n" or prev in _OPS:
            back = 0
            while pos - 2 - back >= 0 and cmd[pos - 2 - back] == "\\":
                back += 1
            return back % 2 == 0
        return False

    def read_bodies(pos):
        for idx in pending:
            hd = hds[idx]
            lines = []
            while pos < n:
                e = cmd.find("\n", pos)
                line = cmd[pos:] if e < 0 else cmd[pos:e]
                pos = n if e < 0 else e + 1
                probe = line.lstrip("\t") if hd["strip"] else line
                if probe == hd["delim"]:
                    hd["terminated"] = True
                    break
                lines.append(line.lstrip("\t") if hd["strip"] else line)
            hd["body"] = "\n".join(lines) + ("\n" if lines else "")
        del pending[:]
        return pos

    while i < n:
        c = cmd[i]
        ctx = stack[-1]
        if ctx == "sq":
            # inside a "$( )" the enclosing shlex word is double-quoted, so a " here would close it
            out.append(INERT if c == '"' and "dsub" in stack else mapc(c))
            if c == "'":
                stack.pop()
            i += 1
            continue
        if ctx == "ansi":
            # $'...': a backslash consumes the next character, only an unescaped ' closes
            if c == "\\" and i + 1 < n:
                nx = cmd[i + 1]
                out.append(c + (INERT if nx == "'" or (nx == '"' and "dsub" in stack) else mapc(nx)))
                i += 2
            elif c == "'":
                stack.pop()
                out.append(INERT if stack[-1] == "dsub" else c)
                i += 1
            else:
                out.append(INERT if c == '"' and "dsub" in stack else mapc(c))
                i += 1
            continue
        if ctx == "dq":
            if c == "\\" and i + 1 < n:
                nx = cmd[i + 1]
                out.append(nx if nx in "$`" else c + mapc(nx))
                i += 2
            elif c == '"':
                stack.pop()
                out.append(INERT if stack[-1] == "dsub" else c)
                i += 1
            elif c == "$" and cmd[i + 1:i + 2] == "(":
                out.append(EXP + mapc("("))
                if "dsub" not in stack and bt is None:
                    rec[len(stack) + 1] = i + 2
                stack.append("dsub")
                i += 2
            elif c in "$`":
                if c == "`" and "dsub" not in stack:
                    if bt is None:
                        bt = i + 1
                    else:
                        spans.append(cmd[bt:i])
                        bt = None
                out.append(EXP)
                i += 1
            else:
                out.append(mapc(c))
                i += 1
            continue
        # top, tsub (a $( ) or ( ) at top level, parsed like top) and dsub (a $( ) inside "...")
        inert = ctx == "dsub"
        if c == "\\" and i + 1 < n:
            nx = cmd[i + 1]
            if nx == "\n" and not inert:
                i += 2
                continue
            if inert:
                out.append(INERT + mapc(nx))
            else:
                out.append(mapc(nx) if nx in _OPS else c + nx)
            i += 2
            continue
        if c == "$" and cmd[i + 1:i + 2] == "'":
            out.append(EXP + (INERT if inert else "'"))
            stack.append("ansi")
            i += 2
            continue
        if c == "#" and comment_start(i):
            e = cmd.find("\n", i)
            i = n if e < 0 else e
            continue
        if c == "'":
            stack.append("sq")
            out.append(INERT if inert else c)
            i += 1
            continue
        if c == '"':
            stack.append("dq")
            out.append(INERT if inert else c)
            i += 1
            continue
        if c == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            j = i + 2
            strip = False
            if j < n and cmd[j] == "-":
                strip = True
                j += 1
            while j < n and cmd[j] in " \t":
                j += 1
            quoted = False
            if j < n and cmd[j] in "'\"":
                q = cmd[j]
                k = cmd.find(q, j + 1)
                quoted = True
                delim = cmd[j + 1:] if k < 0 else cmd[j + 1:k]
                j = n if k < 0 else k + 1
            elif j < n and cmd[j] == "\\":
                quoted = True
                m = re.match(r"[^\s;&|()<>]+", cmd[j + 1:])
                delim = m.group(0) if m else ""
                j += 1 + len(delim)
            else:
                m = re.match(r"[^\s;&|()<>]+", cmd[j:])
                delim = m.group(0) if m else ""
                j += len(delim)
            if delim:
                hds.append({"delim": delim, "strip": strip, "quoted": quoted,
                            "terminated": False, "body": ""})
                pending.append(len(hds) - 1)
                out.append(" %s%d%s " % (HDM, len(hds) - 1, HDM))
                i = j
                continue
            out.append("<<")
            i += 2
            continue
        if c == "\n":
            out.append("\n" if inert else " ; ")
            i = read_bodies(i + 1)
            continue
        if c == "$" and cmd[i + 1:i + 2] == "(":
            out.append(EXP + "(")
            stack.append("dsub" if inert else "tsub")
            i += 2
            continue
        if c == "(":
            out.append(mapc(c) if inert else c)
            stack.append("dsub" if inert else "tsub")
            i += 1
            continue
        if c == ")":
            out.append(mapc(c) if inert else c)
            if ctx in ("tsub", "dsub"):
                if ctx == "dsub" and len(stack) in rec:
                    spans.append(cmd[rec.pop(len(stack)):i])
                stack.pop()
            i += 1
            continue
        if c in "$`":
            if c == "`" and "dsub" not in stack:
                if bt is None:
                    bt = i + 1
                else:
                    spans.append(cmd[bt:i])
                    bt = None
            out.append(EXP)
            i += 1
            continue
        out.append(mapc(c) if inert else c)
        i += 1
    # a heredoc still pending at the end of the command stays unterminated
    unbalanced = any(s in ("sq", "dq", "dsub", "ansi") for s in stack)
    return "".join(out), hds, unbalanced, spans


def word_tokens(text):
    lx = shlex.shlex(text, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    lx.commenters = ""
    return list(lx)


def is_sep(tok):
    return tok != "" and all(ch in ";&|()" for ch in tok)


def is_redir(tok):
    return ("<" in tok or ">" in tok) and all(ch in "<>&|" for ch in tok)


def segments(tokens):
    """Split tokens into segments: dicts with words, redirects, heredoc ids and the separator before."""
    segs = []
    cur = {"words": [], "redirs": [], "hds": [], "sep": ""}
    sep = ""
    k = 0
    while k < len(tokens):
        t = tokens[k]
        if is_sep(t):
            if cur["words"] or cur["redirs"] or cur["hds"]:
                segs.append(cur)
            cur = {"words": [], "redirs": [], "hds": [], "sep": t}
            k += 1
            continue
        if is_redir(t):
            target = tokens[k + 1] if k + 1 < len(tokens) and not is_sep(tokens[k + 1]) else None
            cur["redirs"].append((t, target))
            k += 2 if target is not None else 1
            continue
        m = re.fullmatch(HDM + r"(\d+)" + HDM, t)
        if m:
            cur["hds"].append(int(m.group(1)))
        else:
            cur["words"].append(t)
        k += 1
    if cur["words"] or cur["redirs"] or cur["hds"]:
        segs.append(cur)
    return segs


def command_word(words):
    for k, w in enumerate(words):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w) or w in WRAPPERS or w in RESERVED:
            continue
        return k
    return None


def write_args(seg):
    """The arguments after `gh issue|pr create|edit|comment`, or None when this is not one."""
    k = command_word(seg["words"])
    if k is None or os.path.basename(seg["words"][k]) != "gh":
        return None
    w = seg["words"][k + 1:]
    head, i = [], 0
    while i < len(w) and len(head) < 2:
        a = w[i]
        if a in ("-R", "--repo"):
            i += 2
        elif a.startswith("--repo=") or (a.startswith("-R") and len(a) > 2):
            i += 1
        else:
            head.append(a)
            i += 1
    if len(head) == 2 and head[0] in ("issue", "pr"):
        sub = "create" if head[1] == "new" else head[1]
        if sub in WRITE_SUBS:
            return sub, w[i:]
    return None


def extract(sub, args):
    """The text-carrying flags of one write: ([(label, kind, raw)], saw_unseen)."""
    items, unseen = [], False
    i = 0
    while i < len(args):
        a = args[i]
        i += 1
        if a == "--":
            break
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if name in TEXT_FLAGS:
                if not eq:
                    val = args[i] if i < len(args) else None
                    i += 1
                items.append((name, TEXT_FLAGS[name], val))
            elif name in UNSEEN:
                unseen = True
            continue
        if len(a) >= 2 and a[0] == "-":
            fl = a[:2]
            if fl in TEXT_FLAGS:
                val = a[2:]
                if val.startswith("="):
                    val = val[1:]
                if val == "":
                    val = args[i] if i < len(args) else None
                    i += 1
                items.append((fl, TEXT_FLAGS[fl], val))
            elif fl in UNSEEN:
                unseen = True
    return items, unseen


HD_VALUE = re.compile("^" + EXP + _MAP["("] + r"\s*cat\s+" + HDM + r"(\d+)" + HDM + r"[\s;]*" + _MAP[")"] + "$")


def restore(s):
    return s.translate(_UNMAP_TABLE)


def resolve_path(p, cwd):
    p = os.path.expanduser(p) if p.startswith("~") else p
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def is_cd(seg):
    k = command_word(seg["words"])
    return k is not None and seg["words"][k] in ("cd", "pushd", "popd")


def earlier_effect(target, cwd, earlier, hds, relative):
    """How earlier segments of the same command treat a body-file target.

    Returns None (untouched, read the file), ("hd", idx) (a truncating `cat > f <<'EOF'` with a
    terminated literal heredoc, the only shape scanned) or ("note",) (it may have changed).
    """
    if relative and any(is_cd(s) for s in earlier):
        return ("note",)
    touching = []
    for s in earlier:
        # An earlier gh write only READS its body file, so its words never change the target.
        kk = command_word(s["words"])
        reads = write_args(s) is not None or (
            kk is not None and s["words"][kk] in ("[", "[[", "test"))   # these only read
        names = [] if reads else [w for w in s["words"][1:] if EXP not in w]
        names += [t for _, t in s["redirs"] if t is not None and EXP not in t]
        if any(resolve_path(restore(x), cwd) == target for x in names):
            touching.append(s)
    if not touching:
        return None
    if len(touching) == 1:
        s = touching[0]
        k = command_word(s["words"])
        if (k == 0 and s["words"] == ["cat"] and len(s["redirs"]) == 1 and len(s["hds"]) == 1
                and s["redirs"][0][0] == ">" and s["redirs"][0][1] is not None
                and resolve_path(restore(s["redirs"][0][1]), cwd) == target):
            hd = hds[s["hds"][0]]
            if hd["terminated"] and hd["quoted"]:
                return ("hd", s["hds"][0])
    return ("note",)


# --- reading bodies ----------------------------------------------------------------------------

def read_file(path):
    """(bytes, None) or (None, note). Never hands the user's path to a scanner."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None, NOTE_UNREADABLE
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None, NOTE_NOT_REGULAR
        chunks, total = [], 0
        while total <= CAP:
            try:
                b = os.read(fd, CAP + 1 - total)
            except OSError:
                return None, NOTE_UNREADABLE
            if not b:
                break
            chunks.append(b)
            total += len(b)
        return b"".join(chunks), None
    finally:
        os.close(fd)


def judge_bytes(data):
    if len(data) > CAP:
        return NOTE_OVER_CAP
    if b"\x00" in data:
        return NOTE_BINARY
    return None


# --- scanning ----------------------------------------------------------------------------------

class Clock:
    def __init__(self):
        self.start = time.monotonic()

    def remaining(self):
        return DEADLINE - (time.monotonic() - self.start)


def assets_dir():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "skills", "leak-guard", "assets")


def run_scanner(script, args, cwd, clock):
    """(rc, stdout) or (None, 'timeout' | 'missing'). Its own process group, killed whole."""
    if not os.path.isfile(script):
        return None, "missing"
    budget = min(PER_SCAN, clock.remaining())
    if budget <= 0:
        return None, "timeout"
    try:
        p = subprocess.Popen(["bash", script] + args, cwd=cwd, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    except OSError:
        return None, "missing"
    try:
        out, _ = p.communicate(timeout=budget)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            p.communicate(timeout=1)
        except Exception:
            pass
        return None, "timeout"
    return p.returncode, out.decode("utf-8", "replace")


FINDING = re.compile(r"^(\d+): ([a-z][a-z0-9-]*)(?::|$)")


def parse_finding(out, tmp):
    prefix = tmp + ":"
    for ln in out.splitlines():
        if ln.startswith(prefix):
            m = FINDING.match(ln[len(prefix):])
            if m:
                return m.group(1), m.group(2)
    return "?", None


def scan_data(data, label, k, cwd, project, clock, notes):
    """Scan one body or title. Returns a deny reason or None; appends fail-open notes."""
    fd, tmp = tempfile.mkstemp(prefix="fgw", suffix=".txt")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data if data.endswith(b"\n") or not data else data + b"\n")
        base = os.path.join(assets_dir())
        allow = os.path.join(project, ".leak-guard-allow") if project else ""
        runs = [("check-private-leaks.sh", []),
                ("check-public-leaks.sh",
                 ["--allow-file", allow] if allow and os.path.isfile(allow) else [])]
        for name, extra in runs:
            rc, out = run_scanner(os.path.join(base, name), extra + ["--", tmp], cwd, clock)
            if rc is None:
                notes.append(NOTE_TIMED_OUT if out == "timeout" else NOTE_DID_NOT_RUN)
                continue
            if rc == 1:
                line, rule = parse_finding(out, tmp)
                tail = "(%s)" % rule if rule else "(unparsed)"
                return "leak-guard: %s (write %d) line %s %s" % (label, k, line, tail)
            if rc != 0:
                notes.append(NOTE_DID_NOT_RUN)
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def repo_root(cwd, clock):
    budget = min(2.0, clock.remaining())
    if budget <= 0:
        return cwd
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True,
                           timeout=budget)
        top = r.stdout.strip()
        if r.returncode == 0 and top and os.path.isdir(top):
            return top
    except (OSError, subprocess.SubprocessError):
        pass
    return cwd


# --- the judgement -----------------------------------------------------------------------------

def gh_write_shape(cmd):
    repo = r"(?:(?:-R\s*|--repo[=\s]\s*)\S+\s+)*"
    return re.search(r"\bgh\s+" + repo + r"(?:issue|pr)\s+" + repo
                     + r"(?:create|new|edit|comment)\b", cmd) is not None


def fail_note(command, notes):
    if gh_write_shape(command):
        unterminated = re.search(r"<<-?\s*[\"']?\w+", command) is not None
        notes.append(NOTE_HEREDOC if unterminated else NOTE_NOT_EXTRACTABLE)


def gather(command, notes, depth, outer=()):
    """Every write in `command` as (index, segment, segments, heredocs, outer); raises ValueError
    when the top level cannot be parsed. Spans hidden inside "$( )" and backticks are parsed again
    as commands of their own, nested to depth 4; a span that cannot be judged leaves the note.
    `outer` holds (segments, heredocs) of every enclosing level, so a span write still sees a cd,
    a write to its body file or a `cat > f <<'EOF'` anywhere in the commands around it."""
    text, hds, unbalanced, spans = prepass(command)
    if unbalanced:
        raise ValueError("unbalanced")
    segs = segments(word_tokens(text))
    found = [(idx, s, segs, hds, outer) for idx, s in enumerate(segs) if write_args(s) is not None]
    for sp in spans:
        if depth >= 4:
            fail_note(sp, notes)
            continue
        try:
            found += gather(sp, notes, depth + 1, outer + ((segs, hds),))
        except ValueError:
            fail_note(sp, notes)
    return found


def judge(command, cwd, project):
    """Returns (deny_reason or None, [notes])."""
    notes = []
    clock = Clock()
    command = command.replace("\x00", "")
    try:
        writes = gather(command, notes, 0)
    except ValueError:
        fail_note(command, notes)
        return None, notes

    if not writes:
        return None, notes
    root = repo_root(cwd, clock)
    k = 0
    for idx, seg, segs, hds, outer in writes:
        k += 1
        sub, args = write_args(seg)
        items, unseen = extract(sub, args)
        earlier = segs[:idx]
        has_body = any(kind == "file" or flag in ("--body", "-b") for flag, kind, _ in items)
        if not items and (unseen or sub in ("create", "comment")):
            notes.append(NOTE_NOT_EXTRACTABLE)
        elif unseen and not has_body:
            notes.append(NOTE_NOT_EXTRACTABLE)
        for flag, kind, raw in items:
            label, data, note = flag, None, None
            if raw is None:
                note = NOTE_NOT_EXTRACTABLE
            elif kind == "text":
                if EXP in raw:
                    m = HD_VALUE.match(raw)
                    note = NOTE_NOT_EXTRACTABLE
                    if m and int(m.group(1)) < len(hds):
                        hd = hds[int(m.group(1))]
                        label = flag + " heredoc"
                        if not hd["terminated"]:
                            note = NOTE_HEREDOC
                        elif hd["quoted"] or not re.search(r"[$`\\]", hd["body"]):
                            data, note = hd["body"].encode("utf-8", "replace"), None
                else:
                    data = restore(raw).encode("utf-8", "replace")
            else:  # a body file
                if raw == "-":
                    if seg["hds"]:
                        hd = hds[seg["hds"][0]]
                        label = flag + " heredoc"
                        if not hd["terminated"]:
                            note = NOTE_HEREDOC
                        elif hd["quoted"] or not re.search(r"[$`\\]", hd["body"]):
                            data = hd["body"].encode("utf-8", "replace")
                        else:
                            note = NOTE_NOT_EXTRACTABLE
                    else:
                        note = NOTE_STDIN
                elif EXP in raw or raw == "":
                    note = NOTE_NOT_EXTRACTABLE
                else:
                    path = restore(raw)
                    target = resolve_path(path, cwd)
                    relative = not (path.startswith("/") or path.startswith("~"))
                    # Over-approximate for a span write: every segment of an enclosing level counts as
                    # earlier, each judged against its own level's heredocs (round 2 review).
                    hits = [(e, h) for e, h in
                            [(earlier_effect(target, cwd, earlier, hds, relative), hds)]
                            + [(earlier_effect(target, cwd, os_, oh, relative), oh) for os_, oh in outer]
                            if e is not None]
                    eff, src = hits[0] if len(hits) == 1 else ((("note",), hds) if hits else (None, hds))
                    if eff is None:
                        data, note = read_file(target)
                    elif eff[0] == "hd":
                        data = src[eff[1]]["body"].encode("utf-8", "replace")
                    else:
                        note = NOTE_SAME_CMD
            if data is not None and note is None:
                note = judge_bytes(data)
            if note is not None:
                notes.append(note)
                continue
            if not data:
                continue
            reason = scan_data(data, label, k, root, project, clock, notes)
            if reason:
                return reason, notes
    return None, notes


# --- entry points ------------------------------------------------------------------------------

def say(notes):
    seen = []
    for n in notes:
        if n not in seen:
            seen.append(n)
            sys.stderr.write(n + "\n")


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict) or payload.get("tool_name") != "Bash":
        return 0
    project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    if not isinstance(project, str) or not project or \
            not os.path.exists(os.path.join(project, SENTINEL)):
        return 0
    tin = payload.get("tool_input")
    command = tin.get("command") if isinstance(tin, dict) else None
    if not isinstance(command, str):
        say([NOTE_PAYLOAD])
        return 0
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not os.path.isdir(cwd):
        cwd = os.getcwd()
    reason, notes = judge(command, cwd, os.environ.get("CLAUDE_PROJECT_DIR") or "")
    if reason:
        return deny(reason)
    say(notes)
    return 0


STUB_PRIVATE = '''#!/bin/bash
# self-test stub: flags the word bramble as a private name
f="${@: -1}"
n=$(grep -n -i bramble "$f" | head -1 | cut -d: -f1)
[ -n "$n" ] && { echo "$f:$n: private-name: br*****"; exit 1; }
exit 0
'''
STUB_PUBLIC = '#!/bin/bash\nexit 0\n'


def self_test():
    import shutil
    with tempfile.TemporaryDirectory(prefix="sfw-test-") as d:
        d = os.path.realpath(d)
        proot = os.path.join(d, "plugin")
        assets = os.path.join(proot, "skills", "leak-guard", "assets")
        os.makedirs(assets)
        os.makedirs(os.path.join(proot, "hooks"))
        hook = os.path.join(proot, "hooks", "scan-forge-writes.py")
        shutil.copy(os.path.abspath(__file__), hook)
        for name, body in (("check-private-leaks.sh", STUB_PRIVATE), ("check-public-leaks.sh", STUB_PUBLIC)):
            with open(os.path.join(assets, name), "w") as fh:
                fh.write(body)
        proj = os.path.join(d, "proj")
        os.makedirs(os.path.join(proj, ".claude"))
        open(os.path.join(proj, SENTINEL), "w").close()
        bare = os.path.join(d, "bare")
        os.makedirs(bare)
        with open(os.path.join(proj, "leak.md"), "w") as fh:
            fh.write("ok\nsee bramble here\n")
        with open(os.path.join(proj, "clean.md"), "w") as fh:
            fh.write("all fine\n")
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}

        def verdict(cmd, p=proj):
            e = dict(env, CLAUDE_PROJECT_DIR=p, TMPDIR=d)
            r = subprocess.run([sys.executable, hook], capture_output=True, text=True, env=e,
                               input=json.dumps({"tool_name": "Bash", "cwd": proj,
                                                 "tool_input": {"command": cmd}}))
            if r.returncode != 0:
                return "EXIT%d" % r.returncode
            return "DENY" if '"deny"' in r.stdout else "ALLOW"

        cases = [
            ("DENY", "gh issue comment 5 --body-file leak.md"),
            ("DENY", "gh pr comment 5 -F leak.md"),
            ("DENY", "gh issue create --title 'bramble rollout' --body ok"),
            ("DENY", 'gh issue create --title "fix(bramble)" --body ok'),
            ("DENY", 'gh issue comment 5 --body "a;bramble"'),
            ("DENY", "gh issue comment 5 -bbramble"),
            ("DENY", "gh issue comment 5 --body=bramble"),
            ("DENY", "echo hi && gh issue comment 5 -F leak.md"),
            ("DENY", "gh issue comment 5 -F clean.md && gh issue comment 5 -F leak.md"),
            ("DENY", "gh issue comment 5 -F - <<'EOF'\nsee bramble\nEOF\n"),
            ("DENY", "gh issue comment 5 --body \"$(cat <<'EOF'\nsee bramble\nEOF\n)\""),
            ("DENY", "cat > f.md <<'EOF'\nbramble\nEOF\ngh issue comment 5 --body-file f.md"),
            ("DENY", "# don't wait\ngh issue comment 5 --body-file leak.md\n# it's fine"),
            ("DENY", "for n in 5 6; do gh issue comment $n --body-file leak.md; done"),
            ("DENY", 'echo "posted: $(gh issue comment 5 --body-file leak.md)"'),
            ("DENY", "u=`gh issue create --title t --body-file leak.md`"),
            ("DENY", "gh -R o/r issue comment 5 --body-file leak.md"),
            ("DENY", "gh issue new --title bramble --body x"),
            ("DENY", "echo $'it\\'s' && gh issue comment 5 --body-file leak.md"),
            ("ALLOW", "gh issue comment 5 --body-file clean.md"),
            ("ALLOW", "gh issue list --state open"),
            ("ALLOW", "gh issue close 5 --comment 'see bramble'"),
            ("ALLOW", "forge_issue_comment 5 'bramble'"),
            ("ALLOW", 'gh issue comment 5 --body "$BODY"'),
            ("ALLOW", "cat leak.md | gh issue comment 5 -F -"),
            ("ALLOW", "echo x > leak.md && gh issue comment 5 -F leak.md"),
            ("ALLOW", "cd sub && gh issue comment 5 -F leak.md"),
            ("ALLOW", "gh issue comment 5 --body-file missing.md"),
            ("ALLOW", "gh issue comment 5 --body \"$(cat <<'EOF'\nbramble"),
            ("ALLOW", 'gh issue create --title "fix(retry)" --body "a;b"'),
        ]
        fails = 0
        for want, cmd in cases:
            got = verdict(cmd)
            if got != want:
                fails += 1
                print("self-test FAIL: want %s got %s :: %r" % (want, got, cmd))
        if verdict("gh issue comment 5 --body-file leak.md", p=bare) != "ALLOW":
            fails += 1
            print("self-test FAIL: no sentinel must allow")
        print("self-test: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
        return 0 if fails == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception:
        try:
            sys.stderr.write(NOTE_PAYLOAD + "\n")
        except Exception:
            pass
        sys.exit(0)  # fail open
