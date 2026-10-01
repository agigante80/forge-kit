#!/usr/bin/env python3
"""Behavioural tests for the closing-sessions memory.py helper.

Runs the helper as a subprocess against a throwaway project directory, the same
way scripts/test-hooks.py exercises the hooks. Standard library only.
"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(
    HERE, "..", "plugins", "forge-kit-governance",
    "skills", "closing-sessions", "scripts", "memory.py",
)


def run(project_dir, args, body=""):
    return subprocess.run(
        [sys.executable, SCRIPT, "--project-dir", project_dir, *args],
        input=body, capture_output=True, text=True,
    )


def read(project_dir, *parts):
    with open(os.path.join(project_dir, ".claude", "memory", *parts), encoding="utf-8") as f:
        return f.read()


class WriteTests(unittest.TestCase):
    def test_write_creates_memory_file(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                        "--type", "project", "--description", "a short hook"],
                    body="The body.")
            self.assertEqual(r.returncode, 0, r.stderr)
            content = read(d, "my-fact.md")
            self.assertIn("name: my-fact", content)
            self.assertIn("description: a short hook", content)
            self.assertIn("type: project", content)
            self.assertIn("The body.", content)

    def test_write_creates_index_with_header_and_line(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "a short hook"], body="b")
            idx = read(d, "MEMORY.md")
            self.assertIn("Memory index", idx)
            self.assertIn("- [My Fact](my-fact.md) - a short hook", idx)

    def test_write_is_idempotent_and_updates_in_place(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "first"], body="b")
            run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                    "--type", "project", "--description", "second"], body="b2")
            idx = read(d, "MEMORY.md")
            self.assertEqual(idx.count("(my-fact.md)"), 1)
            self.assertIn("- [My Fact](my-fact.md) - second", idx)
            self.assertNotIn("first", idx)

    def test_write_update_with_backslash_in_description(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "winbug", "--title", "Winbug",
                    "--type", "project", "--description", "first"], body="b")
            r = run(d, ["write", "--slug", "winbug", "--title", "Winbug",
                        "--type", "project",
                        "--description", r"win path C:\1backup"], body="b2")
            self.assertEqual(r.returncode, 0, r.stderr)
            idx = read(d, "MEMORY.md")
            self.assertEqual(idx.count("(winbug.md)"), 1)
            self.assertIn(r"- [Winbug](winbug.md) - win path C:\1backup", idx)

    def test_plain_description_stays_unquoted(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "plain", "--title", "Plain",
                    "--type", "user", "--description", "a short hook"], body="b")
            content = read(d, "plain.md")
            self.assertIn("description: a short hook", content)
            self.assertNotIn('description: "a short hook"', content)

    def test_description_with_colon_is_quoted_in_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "ratio", "--title", "Ratio", "--type",
                    "project", "--description", "ratio a: b matters"], body="b")
            content = read(d, "ratio.md")
            self.assertIn('description: "ratio a: b matters"', content)

    def test_title_with_bracket_is_escaped_in_index(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "weird", "--title", "Weird ] title",
                    "--type", "user", "--description", "x"], body="b")
            idx = read(d, "MEMORY.md")
            self.assertIn(r"- [Weird \] title](weird.md) - x", idx)

    def test_update_entry_with_bracketed_title(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "br", "--title", "Weird ] title",
                    "--type", "user", "--description", "first"], body="b")
            run(d, ["write", "--slug", "br", "--title", "Weird ] title",
                    "--type", "user", "--description", "second"], body="b")
            idx = read(d, "MEMORY.md")
            self.assertEqual(idx.count("(br.md)"), 1)
            self.assertIn(r"- [Weird \] title](br.md) - second", idx)


class CrossSlugTests(unittest.TestCase):
    def test_update_does_not_clobber_line_with_inline_link(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "target", "--title", "Target",
                    "--type", "project", "--description", "x"], body="b")
            run(d, ["write", "--slug", "other", "--title", "Other", "--type",
                    "project", "--description", "similar to [t](target.md)"], body="b")
            run(d, ["write", "--slug", "target", "--title", "Target",
                    "--type", "project", "--description", "updated"], body="b")
            idx = read(d, "MEMORY.md")
            self.assertIn("- [Other](other.md) - similar to [t](target.md)", idx)
            self.assertEqual(idx.count("(other.md)"), 1)
            self.assertIn("- [Target](target.md) - updated", idx)

    def test_remove_does_not_clobber_line_with_inline_link(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "target", "--title", "Target",
                    "--type", "project", "--description", "x"], body="b")
            run(d, ["write", "--slug", "other", "--title", "Other", "--type",
                    "project", "--description", "similar to [t](target.md)"], body="b")
            run(d, ["remove", "--slug", "target"])
            idx = read(d, "MEMORY.md")
            self.assertIn("- [Other](other.md) - similar to [t](target.md)", idx)
            self.assertNotIn("(target.md) - x", idx)


class RemoveTests(unittest.TestCase):
    def test_remove_deletes_file_and_index_line(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "gone", "--title", "Gone",
                    "--type", "user", "--description", "temp"], body="b")
            r = run(d, ["remove", "--slug", "gone"])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(
                os.path.join(d, ".claude", "memory", "gone.md")))
            self.assertNotIn("(gone.md)", read(d, "MEMORY.md"))

    def test_remove_missing_slug_is_noop(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, ["remove", "--slug", "never-existed"])
            self.assertEqual(r.returncode, 0, r.stderr)


class OwnershipTests(unittest.TestCase):
    """memory.py acts only on files it wrote (its generated frontmatter)."""

    def _seed(self, d, name, text, index="- [Other](other.md) - x\n"):
        mem = os.path.join(d, ".claude", "memory")
        os.makedirs(mem, exist_ok=True)
        with open(os.path.join(mem, name), "w", encoding="utf-8") as f:
            f.write(text)
        if index is not None:
            with open(os.path.join(mem, "MEMORY.md"), "w", encoding="utf-8") as f:
                f.write(index)

    def _snapshot(self, d):
        mem = os.path.join(d, ".claude", "memory")
        out = {}
        for root, dirs, files in os.walk(d):
            for n in dirs:
                out[os.path.relpath(os.path.join(root, n), d)] = None
            for n in files:
                full = os.path.join(root, n)
                with open(full, "rb") as f:
                    out[os.path.relpath(full, d)] = f.read()
        return out

    def _refused(self, d, args, body=""):
        before = self._snapshot(d)
        r = run(d, args, body=body)
        self.assertNotEqual(r.returncode, 0, "expected refusal")
        self.assertIn("memory.py: refusing", r.stderr)
        self.assertNotIn("Traceback", r.stderr)
        self.assertEqual(self._snapshot(d), before, "refusal must change nothing")
        return r

    WRITE = ["write", "--title", "T", "--type", "project", "--description", "d"]

    def test_remove_refuses_file_without_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "topic-hooks.md", "# Hooks\n\nexec form\n",
                       index="- [Hooks](topic-hooks.md) - h\n")
            r = self._refused(d, ["remove", "--slug", "topic-hooks"])
            self.assertIn("topic-hooks", r.stderr)

    def test_write_refuses_file_without_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "topic-hooks.md", "# Hooks\n\nexec form\n")
            r = self._refused(d, self.WRITE[:1] + ["--slug", "topic-hooks"] + self.WRITE[1:],
                              body="new")
            self.assertIn("topic-hooks", r.stderr)
            self.assertNotIn("topic-hooks.md", read(d, "MEMORY.md"))

    def test_refuses_name_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            text = "---\nname: other-name\ndescription: d\nmetadata:\n  type: user\n---\n\nb\n"
            self._seed(d, "a.md", text)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, self.WRITE[:1] + ["--slug", "a"] + self.WRITE[1:], body="n")

    def test_refuses_top_level_type_without_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            text = "---\nname: a\ndescription: d\ntype: user\n---\n\nb\n"
            self._seed(d, "a.md", text)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, self.WRITE[:1] + ["--slug", "a"] + self.WRITE[1:], body="n")

    def test_refuses_unclosed_frontmatter(self):
        with tempfile.TemporaryDirectory() as d:
            text = "---\nname: a\ndescription: d\nmetadata:\n  type: user\n\nb\n"
            self._seed(d, "a.md", text)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, self.WRITE[:1] + ["--slug", "a"] + self.WRITE[1:], body="n")

    def test_refuses_type_outside_metadata(self):
        bad = {
            "indented-under-other-key": "---\nname: a\nextra:\n  type: user\n---\n\nb\n",
            "type-under-extra-before-metadata": "---\nname: a\nextra:\n  type: user\nmetadata:\n  other: x\n---\n\nb\n",
            "type-under-key-after-metadata": "---\nname: a\nmetadata:\n  other: x\nextra:\n  type: user\n---\n\nb\n",
            "flat-type-after-metadata": "---\nname: a\nmetadata:\n  other: x\ntype: user\n---\n\nb\n",
        }
        for label, text in bad.items():
            with tempfile.TemporaryDirectory() as d:
                self._seed(d, "a.md", text)
                self._refused(d, ["remove", "--slug", "a"])
                self._refused(d, self.WRITE[:1] + ["--slug", "a"] + self.WRITE[1:], body="n")

    def test_refuses_frontmatter_not_on_first_line(self):
        with tempfile.TemporaryDirectory() as d:
            text = "# Title\nname: a\nmetadata:\n  type: user\n---\n\nb\n"
            self._seed(d, "a.md", text)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, self.WRITE[:1] + ["--slug", "a"] + self.WRITE[1:], body="n")

    def test_reserved_slug_memory_refused_with_no_index(self):
        with tempfile.TemporaryDirectory() as d:
            for slug in ("MEMORY", "memory", "Memory"):
                r = run(d, ["write", "--slug", slug] + self.WRITE[1:], body="b")
                self.assertNotEqual(r.returncode, 0, slug)
                r = run(d, ["remove", "--slug", slug])
                self.assertNotEqual(r.returncode, 0, slug)
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "MEMORY.md")))
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "memory.md")))

    def test_path_spelled_reserved_slug_refused(self):
        with tempfile.TemporaryDirectory() as d:
            for slug in ("./MEMORY", "../memory/MEMORY", "./memory"):
                self._refused(d, ["write", "--slug", slug] + self.WRITE[1:], body="b")
                self._refused(d, ["remove", "--slug", slug])
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "MEMORY.md")))

    def test_non_plain_slugs_refused(self):
        with tempfile.TemporaryDirectory() as d:
            for slug in ("../x", "/etc/x", "a/b", "a..b", ".hid", ""):
                self._refused(d, ["write", "--slug", slug] + self.WRITE[1:], body="b")
                self._refused(d, ["remove", "--slug", slug])

    def test_directory_named_like_slug_refused(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".claude", "memory", "a.md"))
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="b")

    def test_reserved_slug_memory_refused_with_index(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "a.md", "# x\n", index="- [A](a.md) - x\n")
            self._refused(d, ["remove", "--slug", "MEMORY"])
            self._refused(d, ["write", "--slug", "MEMORY"] + self.WRITE[1:], body="b")

    def test_own_file_still_updates_and_removes(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, ["write", "--slug", "mine"] + self.WRITE[1:], body="one")
            r = run(d, ["write", "--slug", "mine"] + self.WRITE[1:], body="two")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("two", read(d, "mine.md"))
            r = run(d, ["remove", "--slug", "mine"])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "mine.md")))

    def test_remove_missing_slug_still_cleans_index_line(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "other.md", "# x\n", index="- [Gone](gone.md) - x\n")
            r = run(d, ["remove", "--slug", "gone"])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("(gone.md)", read(d, "MEMORY.md"))


if __name__ == "__main__":
    unittest.main()
