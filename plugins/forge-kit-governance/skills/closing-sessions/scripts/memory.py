#!/usr/bin/env python3
"""Deterministic writer/remover for .claude/memory/ files and the MEMORY.md index.

Used by the closing-sessions skill so frontmatter and index integrity do not
depend on the model formatting them by hand each time. Standard library only.
"""
import argparse
import os
import re
import stat
import sys

MEMORY_SUBDIR = os.path.join(".claude", "memory")
INDEX_NAME = "MEMORY.md"
INDEX_HEADER = (
    "<!-- Memory index. Each line: - [Title](file.md) - one-line description (~150 chars max) -->\n"
    "<!-- Add entries here as Claude Code builds up project memory across conversations. -->\n"
)


def memory_dir(project_dir):
    return os.path.join(project_dir, MEMORY_SUBDIR)


def index_path(project_dir):
    return os.path.join(memory_dir(project_dir), INDEX_NAME)


def memory_path(project_dir, slug):
    return os.path.join(memory_dir(project_dir), slug + ".md")


# Characters that force a YAML plain scalar to be quoted when they lead it.
_YAML_INDICATORS = set("!&*[]{}#|>@`\"'%?,")

# A Markdown link title: from "[" to the first UNescaped "]", allowing "\]"
# inside so that a title carrying a bracket still matches its own line.
_LINK_TITLE = r"\[(?:[^\]\\]|\\.)*\]"


def _one_line(value):
    return value.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").strip()


def _needs_yaml_quote(value):
    if value == "":
        return True
    if value[0] in _YAML_INDICATORS or value[0] in ":-" or value[0].isspace():
        return True
    return ": " in value or value.endswith(":") or " #" in value


def _yaml_scalar(value):
    value = _one_line(value)
    if _needs_yaml_quote(value):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return value


def _md_link_text(value):
    return (_one_line(value)
            .replace("\\", "\\\\")
            .replace("[", "\\[")
            .replace("]", "\\]"))


def render_memory(slug, mem_type, description, body):
    return (
        "---\n"
        f"name: {slug}\n"
        f"description: {_yaml_scalar(description)}\n"
        "metadata:\n"
        f"  type: {mem_type}\n"
        "---\n\n"
        f"{body.rstrip()}\n"
    )


def index_line(title, slug, description):
    return f"- [{_md_link_text(title)}]({slug}.md) - {_one_line(description)}\n"


class _Refusal(Exception):
    """A leaf this helper must not touch. Deliberately not an OSError, so a
    caller that converts OSError cannot swallow it, and never a BaseException,
    so a test's hang guard (which is one) is not converted into a refusal."""


def _open_leaf(path, rel, flags, create=False):
    """Open a leaf without following a link or blocking on a FIFO (#324).

    The one place the write path and read_index get their open flags.
    O_NOFOLLOW refuses a link (ELOOP), O_NONBLOCK opens a FIFO instead of
    hanging (a write open with no reader fails ENXIO), and the fstat on the
    held descriptor refuses whatever a reader or a directory let through. There
    is no O_TRUNC: a refusal must never empty a file, so the caller truncates
    only after every leaf has passed. create=True adds O_CREAT | O_EXCL, so a
    name that appeared in between is a refusal, never a follow. Returns the
    descriptor, or None when the name is absent (never when creating). Never
    O_RDWR: Linux opens a FIFO O_RDWR with no reader, so ENXIO would not fire.
    """
    if create:
        flags |= os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o666)
    except FileNotFoundError:
        if create:
            raise _Refusal(f"{rel} cannot be created (No such file or directory)")
        return None
    except OSError as e:
        verb = "created" if create else "opened"
        raise _Refusal(f"{rel} cannot be {verb} ({e.strerror})")
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise _Refusal(f"{rel} is not a regular file")
    return fd


def _overwrite(fd, text):
    os.ftruncate(fd, 0)
    data = text.encode("utf-8")
    while data:
        data = data[os.write(fd, data):]


def read_index(project_dir):
    """Return the index text, None when it is absent, or raise _Refusal.

    Opened through _open_leaf, so a link or FIFO swapped in after the ownership
    check is a refusal (os.path.exists said False for a dangling link and let
    the write create its target). Decoded strictly, as check_ownership does.
    """
    rel = os.path.join(MEMORY_SUBDIR, INDEX_NAME)
    fd = _open_leaf(index_path(project_dir), rel, os.O_RDONLY)
    if fd is None:
        return None
    with os.fdopen(fd, "rb") as f:
        try:
            data = f.read()
        except OSError as e:
            raise _Refusal(f"{rel} cannot be read ({e.strerror})")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise _Refusal(f"{rel} is not UTF-8")


def line_pattern(slug):
    return re.compile(
        r"^- " + _LINK_TITLE + r"\(" + re.escape(slug) + r"\.md\).*$",
        re.MULTILINE,
    )


def index_with_line(existing, title, slug, description):
    """The index text after upserting slug's line; existing is None when absent."""
    line = index_line(title, slug, description)
    if existing is None:
        return INDEX_HEADER + "\n" + line
    pattern = line_pattern(slug)
    if pattern.search(existing):
        return pattern.sub(lambda _: line.rstrip("\n"), existing)
    if not existing.endswith("\n"):
        existing += "\n"
    return existing + line


def index_without_line(existing, slug):
    pattern = re.compile(
        r"^- " + _LINK_TITLE + r"\(" + re.escape(slug) + r"\.md\).*\n?",
        re.MULTILINE,
    )
    return pattern.sub("", existing)


# ASCII only, matched against the slug AS GIVEN. Never lower() it first and never
# add re.IGNORECASE: case folding maps U+212A (Kelvin sign) onto "k", so a
# non-ASCII slug would pass. Uppercase ASCII stays accepted (#314).
_SLUG_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*", re.ASCII)


def _refuse(slug, reason):
    print(f"memory.py: refusing slug '{slug}': {reason}", file=sys.stderr)
    return 1


def is_owned(content, slug):
    """True if content carries the frontmatter render_memory generates."""
    lines = content.split("\n")
    if not lines or lines[0] != "---":
        return False
    try:
        end = lines.index("---", 1)
    except ValueError:
        return False
    head = lines[1:end]
    if f"name: {slug}" not in head or "metadata:" not in head:
        return False
    block = []
    for ln in head[head.index("metadata:") + 1:]:
        if not ln.startswith(" "):
            break
        block.append(ln)
    return any(re.match(r"^  type: \S", ln) for ln in block)


def _inspect(path, rel, strict=False):
    """Return (text, problem) for a leaf file; text is None when it is absent.

    Anything at path that is not a regular, non-symlink, readable file yields a
    problem string. This guards the READ and the early refusal only: the check
    is advisory the moment it returns. The write path (and read_index) is
    guarded by _open_leaf, which opens without following a link or blocking on
    a FIFO and checks the held descriptor, so a swap after this check is still
    a refusal (#324). strict=True (used for the index) refuses
    bytes that are not UTF-8, because read_index decodes strictly later and
    would otherwise crash after a write or remove had already happened.
    Only the leaf is checked: a symlinked
    .claude/memory/ directory is deliberately out of scope (#314).
    """
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return None, None
    except OSError as e:
        return None, f"{rel} cannot be inspected ({e.strerror})"
    if stat.S_ISLNK(st.st_mode):
        return None, f"{rel} is a symbolic link"
    if stat.S_ISDIR(st.st_mode):
        return None, f"{rel} is a directory"
    if not stat.S_ISREG(st.st_mode):
        return None, f"{rel} is not a regular file"
    try:
        # O_NONBLOCK opens a FIFO instead of hanging, so the fstat check below
        # is what refuses one that was swapped in after the lstat.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as e:
        return None, f"{rel} cannot be opened ({e.strerror})"
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            return None, f"{rel} is not a regular file"
        try:
            data = f.read()
        except OSError as e:
            return None, f"{rel} cannot be read ({e.strerror})"
    try:
        return data.decode("utf-8", errors="strict" if strict else "replace"), None
    except UnicodeDecodeError:
        return None, f"{rel} is not UTF-8"


def _index_writable(path):
    """True if the index can be opened for writing by the effective uid.

    An open probe rather than os.access: access(2) tests the REAL uid, while
    the write path opens as the effective one. No O_TRUNC, so the probe never
    changes the file, and it is closed at once. O_NONBLOCK keeps a FIFO swapped
    in after _inspect from hanging the open.
    """
    try:
        os.close(os.open(path, os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK))
    except OSError:
        return False
    return True


def slug_problem(slug):
    """Return why slug is refused on its own, or None. Pure: touches no file."""
    if not _SLUG_RE.fullmatch(slug) or ".." in slug:
        return "not a plain slug: use ASCII letters, digits, '.', '_' or '-', no path parts"
    if slug.lower() == INDEX_NAME[:-3].lower():
        return "reserved: it would collide with the MEMORY.md index"
    return None


def check_ownership(project_dir, slug):
    """Return an error message, or None when acting on slug is allowed.

    Checks the memory file AND the MEMORY.md index (when present: regular,
    UTF-8, readable and writable), so an index defect refuses before the
    memory file is written or deleted and leaves nothing half done. The two
    are decoded differently on purpose. A memory file is only scanned for its
    frontmatter and then overwritten or deleted whole, so it is decoded with
    errors="replace": a stray byte must never block updating or erasing an
    owned file. The index is rewritten from what read_index returns after a
    mutation, so it must decode cleanly up front. That covers only what
    this check can see. A swap between the check and the write is caught by
    the write's own leaf opens (#324), but an I/O failure after validation
    (ENOSPC, a network filesystem) or a name that appears between the index
    create and the memory file create can still leave partial state, because
    the helper is not transactional (#329).
    """
    err = slug_problem(slug)
    if err:
        return err
    rel = os.path.join(MEMORY_SUBDIR, slug + ".md")
    text, problem = _inspect(memory_path(project_dir, slug), rel)
    if problem:
        return problem
    idx_rel = os.path.join(MEMORY_SUBDIR, INDEX_NAME)
    idx_text, problem = _inspect(index_path(project_dir), idx_rel, strict=True)
    if problem:
        return problem
    if idx_text is not None and not _index_writable(index_path(project_dir)):
        return f"{idx_rel} is not writable"
    if text is None or is_owned(text, slug):
        return None
    return (f"{rel} exists without the "
            "frontmatter this helper writes, so it is not ours to change")


def cmd_write(args):
    # Order (#324): the pure slug check, then stdin, then the ownership check,
    # then the encode probes, then the opens. stdin is read BEFORE the check so the
    # window the caller controls (how long stdin stays open) is not between the
    # check and the write. On a tty a refusal therefore appears only after EOF.
    err = slug_problem(args.slug)
    if err:
        return _refuse(args.slug, err)
    raw = sys.stdin.buffer.read()
    err = check_ownership(args.project_dir, args.slug)
    if err:
        return _refuse(args.slug, err)
    # Every encode-on-write input is probed BEFORE the first write, so an encode
    # error cannot leave a truncated file. The ownership refusal still wins over
    # these (#341), which is why they follow the check. Each field is probed on
    # its own so the refusal names it, and the refusal never echoes the value.
    # stdin was read as bytes and is decoded strictly here, because a text read
    # decodes (and may raise, or smuggle surrogates through) before any check
    # can run. Do not swap this for errors="surrogateescape": a raw byte in the
    # index makes the strict index decode refuse every later write and remove.
    for field, value in (("--title", args.title), ("--description", args.description)):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            return _refuse(args.slug, f"{field} is not valid UTF-8")
    try:
        body = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        return _refuse(args.slug, "stdin is not valid UTF-8")
    os.makedirs(memory_dir(args.project_dir), exist_ok=True)
    mem_rel = os.path.join(MEMORY_SUBDIR, args.slug + ".md")
    idx_rel = os.path.join(MEMORY_SUBDIR, INDEX_NAME)
    mem_path = memory_path(args.project_dir, args.slug)
    idx_path = index_path(args.project_dir)
    fds = []
    try:
        # Validate every leaf first, then write through these same descriptors:
        # there is no second path lookup left to race. The existing memory file
        # is opened before the index is created, so a refusal at it leaves an
        # absent index absent.
        mem_fd = _open_leaf(mem_path, mem_rel, os.O_WRONLY)
        if mem_fd is not None:
            fds.append(mem_fd)
        existing = read_index(args.project_dir)
        idx_fd = None
        if existing is not None:
            idx_fd = _open_leaf(idx_path, idx_rel, os.O_WRONLY)
            if idx_fd is not None:
                fds.append(idx_fd)
        if idx_fd is None:
            idx_fd = _open_leaf(idx_path, idx_rel, os.O_WRONLY, create=True)
            fds.append(idx_fd)
        if mem_fd is None:
            mem_fd = _open_leaf(mem_path, mem_rel, os.O_WRONLY, create=True)
            fds.append(mem_fd)
        _overwrite(mem_fd, render_memory(args.slug, args.type, args.description, body))
        _overwrite(idx_fd, index_with_line(existing, args.title, args.slug,
                                           args.description))
    except _Refusal as e:
        return _refuse(args.slug, str(e))
    finally:
        for fd in fds:
            os.close(fd)
    return 0


def cmd_remove(args):
    err = check_ownership(args.project_dir, args.slug)
    if err:
        return _refuse(args.slug, err)
    idx_rel = os.path.join(MEMORY_SUBDIR, INDEX_NAME)
    fd = None
    try:
        # The index is acquired and validated BEFORE the memory file is
        # unlinked, so a refused index leaves the file in place.
        existing = read_index(args.project_dir)
        if existing is not None:
            fd = _open_leaf(index_path(args.project_dir), idx_rel, os.O_WRONLY)
        try:
            os.remove(memory_path(args.project_dir, args.slug))
        except FileNotFoundError:
            pass
        except OSError as e:
            raise _Refusal(f"{os.path.join(MEMORY_SUBDIR, args.slug + '.md')} "
                           f"cannot be removed ({e.strerror})")
        if fd is not None:
            _overwrite(fd, index_without_line(existing, args.slug))
    except _Refusal as e:
        return _refuse(args.slug, str(e))
    finally:
        if fd is not None:
            os.close(fd)
    return 0


def build_parser():
    p = argparse.ArgumentParser(
        description="Write or remove .claude/memory/ files and keep MEMORY.md in sync.")
    p.add_argument("--project-dir", default=".",
                   help="Project root containing .claude/ (default: current directory)")
    sub = p.add_subparsers(dest="command", required=True)

    w = sub.add_parser("write", help="Create or overwrite a memory file and upsert its index line")
    w.add_argument("--slug", required=True)
    w.add_argument("--title", required=True)
    w.add_argument("--type", required=True,
                   choices=["user", "feedback", "project", "reference"])
    w.add_argument("--description", required=True)
    w.set_defaults(func=cmd_write)

    r = sub.add_parser("remove", help="Delete a memory file and its index line")
    r.add_argument("--slug", required=True)
    r.set_defaults(func=cmd_remove)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
