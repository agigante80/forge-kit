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


if __name__ == "__main__":
    unittest.main()
