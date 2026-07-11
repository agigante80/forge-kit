#!/usr/bin/env python3
"""Deterministic writer/remover for .claude/memory/ files and the MEMORY.md index.

Used by the closing-sessions skill so frontmatter and index integrity do not
depend on the model formatting them by hand each time. Standard library only.
"""
import argparse
import os
import re
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


def read_index(project_dir):
    path = index_path(project_dir)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def write_index(project_dir, content):
    os.makedirs(memory_dir(project_dir), exist_ok=True)
    with open(index_path(project_dir), "w", encoding="utf-8") as f:
        f.write(content)


def line_pattern(slug):
    return re.compile(
        r"^- " + _LINK_TITLE + r"\(" + re.escape(slug) + r"\.md\).*$",
        re.MULTILINE,
    )


def upsert_index_line(project_dir, title, slug, description):
    existing = read_index(project_dir)
    line = index_line(title, slug, description)
    if existing is None:
        write_index(project_dir, INDEX_HEADER + "\n" + line)
        return
    pattern = line_pattern(slug)
    if pattern.search(existing):
        write_index(project_dir, pattern.sub(lambda _: line.rstrip("\n"), existing))
        return
    if not existing.endswith("\n"):
        existing += "\n"
    write_index(project_dir, existing + line)


def remove_index_line(project_dir, slug):
    existing = read_index(project_dir)
    if existing is None:
        return
    pattern = re.compile(
        r"^- " + _LINK_TITLE + r"\(" + re.escape(slug) + r"\.md\).*\n?",
        re.MULTILINE,
    )
    write_index(project_dir, pattern.sub("", existing))


def cmd_write(args):
    body = sys.stdin.read()
    os.makedirs(memory_dir(args.project_dir), exist_ok=True)
    with open(memory_path(args.project_dir, args.slug), "w", encoding="utf-8") as f:
        f.write(render_memory(args.slug, args.type, args.description, body))
    upsert_index_line(args.project_dir, args.title, args.slug, args.description)


def cmd_remove(args):
    path = memory_path(args.project_dir, args.slug)
    if os.path.exists(path):
        os.remove(path)
    remove_index_line(args.project_dir, args.slug)


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
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
