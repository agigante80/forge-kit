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


if __name__ == "__main__":
    unittest.main()
