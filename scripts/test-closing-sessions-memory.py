#!/usr/bin/env python3
"""Behavioural tests for the closing-sessions memory.py helper.

Runs the helper as a subprocess against a throwaway project directory, the same
way scripts/test-hooks.py exercises the hooks. Standard library only.
"""
import contextlib
import importlib.util
import io
import os
import signal
import stat
import subprocess
import sys
import tempfile
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(
    HERE, "..", "plugins", "forge-kit-governance",
    "skills", "closing-sessions", "scripts", "memory.py",
)


def _clean_env(extra):
    """The inherited environment minus every variable that picks the stdin decoding."""
    env = {k: v for k, v in os.environ.items()
           if k not in ("PYTHONUTF8", "PYTHONIOENCODING", "LANG") and not k.startswith("LC_")}
    env.update(extra)
    return env


def run(project_dir, args, body="", timeout=10, env=None):
    """Run the helper. A str body is text; a bytes body is piped raw and the
    result's stdout and stderr are decoded with errors="replace". env, when
    given, is applied over a locale-clean copy of the inherited environment."""
    cmd = [sys.executable, SCRIPT, "--project-dir", project_dir, *args]
    kw = {} if env is None else {"env": _clean_env(env)}
    if isinstance(body, bytes):
        r = subprocess.run(cmd, input=body, capture_output=True, timeout=timeout, **kw)
        return subprocess.CompletedProcess(
            r.args, r.returncode,
            r.stdout.decode("utf-8", errors="replace"),
            r.stderr.decode("utf-8", errors="replace"))
    return subprocess.run(cmd, input=body, capture_output=True, text=True,
                          timeout=timeout, **kw)


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

    def test_write_into_empty_index_adds_the_header(self):
        # #422 item 2: a 0-byte MEMORY.md (crash, ENOSPC) must still get INDEX_HEADER.
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".claude", "memory"))
            open(os.path.join(d, ".claude", "memory", "MEMORY.md"), "w").close()
            r = run(d, ["write", "--slug", "my-fact", "--title", "My Fact",
                        "--type", "project", "--description", "a short hook"], body="b")
            self.assertEqual(r.returncode, 0, r.stderr)
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
        # lstat only: never open a FIFO or follow a link, so a hostile fixture
        # cannot hang or break the harness. Regular files are read by content.
        out = {}
        for root, dirs, files in os.walk(d):
            for n in dirs + files:
                full = os.path.join(root, n)
                st = os.lstat(full)
                key = os.path.relpath(full, d)
                if stat.S_ISREG(st.st_mode) and os.access(full, os.R_OK):
                    with open(full, "rb") as f:
                        out[key] = (st.st_mode, f.read())
                elif stat.S_ISLNK(st.st_mode):
                    out[key] = (st.st_mode, os.readlink(full))
                else:
                    out[key] = (st.st_mode, None)
        return out

    def _refused(self, d, args, body="", env=None):
        before = self._snapshot(d)
        r = run(d, args, body=body, env=env)
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
                r = self._refused(d, ["write", "--slug", slug] + self.WRITE[1:], body="b")
                self.assertIn("reserved", r.stderr, slug)
                r = self._refused(d, ["remove", "--slug", slug])
                self.assertIn("reserved", r.stderr, slug)
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

    def test_refusal_escapes_a_hostile_slug(self):
        # #351 item 5: the slug is echoed with ascii(), so a newline or ESC in it
        # cannot forge a second refusal line or reach the terminal raw.
        slug = "a\nmemory.py: refusing slug b: x\033[31m"
        with tempfile.TemporaryDirectory() as d:
            for args in (["write", "--slug", slug] + self.WRITE[1:], ["remove", "--slug", slug]):
                r = self._refused(d, args, body="b")
                self.assertEqual(len(r.stderr.splitlines()), 1, r.stderr)
                self.assertNotIn("\x1b", r.stderr)

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

    # --- #314: slug policy and non-regular targets ---

    def test_uppercase_ascii_slug_still_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, ["write", "--slug", "Feedback_Testing"] + self.WRITE[1:], body="b")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("name: Feedback_Testing", read(d, "Feedback_Testing.md"))
            r = run(d, ["remove", "--slug", "Feedback_Testing"])
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_folding_nonascii_slugs_refused(self):
        with tempfile.TemporaryDirectory() as d:
            # U+212A (Kelvin sign) folds to "k"; U+017F (long s) folds to "s".
            for slug in ("\u212aelvin", "\u017fecret"):
                self._refused(d, ["write", "--slug", slug] + self.WRITE[1:], body="b")
                self._refused(d, ["remove", "--slug", slug])
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory")))

    def _outside(self, d, text=None):
        out = os.path.join(d, "outside.txt")
        if text is not None:
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
        return out

    def _link(self, d, name, target):
        mem = os.path.join(d, ".claude", "memory")
        os.makedirs(mem, exist_ok=True)
        os.symlink(target, os.path.join(mem, name))

    OWNED_A = "---\nname: a\ndescription: d\nmetadata:\n  type: user\n---\n\nb\n"

    def test_dangling_symlink_target_refused(self):
        with tempfile.TemporaryDirectory() as d:
            out = self._outside(d)
            self._link(d, "a.md", out)
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self._refused(d, ["remove", "--slug", "a"])
            self.assertFalse(os.path.exists(out))

    def test_live_symlink_target_refused(self):
        with tempfile.TemporaryDirectory() as d:
            out = self._outside(d, self.OWNED_A)
            self._link(d, "a.md", out)
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self._refused(d, ["remove", "--slug", "a"])
            with open(out, encoding="utf-8") as f:
                self.assertEqual(f.read(), self.OWNED_A)

    def test_fifo_target_refused_promptly(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".claude", "memory"))
            fifo = os.path.join(d, ".claude", "memory", "a.md")
            os.mkfifo(fifo)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self.assertTrue(stat.S_ISFIFO(os.lstat(fifo).st_mode))

    def test_fifo_index_refused_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".claude", "memory"))
            os.mkfifo(os.path.join(d, ".claude", "memory", "MEMORY.md"))
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self._refused(d, ["remove", "--slug", "a"])
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))

    def test_symlinked_index_refused_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            out = self._outside(d)
            self._link(d, "MEMORY.md", out)
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self.assertFalse(os.path.exists(out))
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))
        with tempfile.TemporaryDirectory() as d:
            out = self._outside(d, "- [X](x.md) - x\n")
            self._link(d, "MEMORY.md", out)
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            with open(out, encoding="utf-8") as f:
                self.assertEqual(f.read(), "- [X](x.md) - x\n")

    @unittest.skipIf(os.geteuid() == 0, "root ignores file modes")
    def test_unreadable_target_refused_without_traceback(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "a.md", self.OWNED_A)
            os.chmod(os.path.join(d, ".claude", "memory", "a.md"), 0)
            self._refused(d, ["remove", "--slug", "a"])
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")

    @unittest.skipIf(os.geteuid() == 0, "root ignores file modes")
    def test_unreadable_index_refused_without_traceback(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "other.md", "# x\n")
            os.chmod(os.path.join(d, ".claude", "memory", "MEMORY.md"), 0)
            self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")

    def _lock_index(self, d):
        os.chmod(os.path.join(d, ".claude", "memory", "MEMORY.md"), 0o444)

    @unittest.skipIf(os.geteuid() == 0, "root ignores file modes")
    def test_unwritable_index_refuses_write_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "other.md", "# x\n")
            self._lock_index(d)
            r = self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self.assertIn("MEMORY.md is not writable", r.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))

    @unittest.skipIf(os.geteuid() == 0, "root ignores file modes")
    def test_unwritable_index_refuses_remove_and_keeps_file_and_line(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "a.md", self.OWNED_A, index="- [T](a.md) - d\n")
            self._lock_index(d)
            r = self._refused(d, ["remove", "--slug", "a"])
            self.assertIn("MEMORY.md is not writable", r.stderr)
            self.assertTrue(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))
            self.assertIn("(a.md)", read(d, "MEMORY.md"))

    def test_owned_file_with_non_utf8_body_still_overwritten_and_removed(self):
        # Only the index is decoded strictly (#314); a memory file is decoded
        # with errors="replace". Pins the replace side of that switch (#329).
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "a.md", "", index="- [T](a.md) - d\n")
            path = os.path.join(d, ".claude", "memory", "a.md")
            with open(path, "wb") as f:
                f.write(self.OWNED_A.encode("utf-8") + b"\xff\n")
            r = run(d, ["write", "--slug", "a"] + self.WRITE[1:], body="fresh")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("fresh", read(d, "a.md"))
            with open(path, "wb") as f:
                f.write(self.OWNED_A.encode("utf-8") + b"\xff\n")
            r = run(d, ["remove", "--slug", "a"])
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(path))
            self.assertNotIn("(a.md)", read(d, "MEMORY.md"))

    def _bad_index(self, d):
        mem = os.path.join(d, ".claude", "memory")
        os.makedirs(mem, exist_ok=True)
        with open(os.path.join(mem, "MEMORY.md"), "wb") as f:
            f.write(b"\xff\xfe bad")

    def test_non_utf8_index_refuses_write_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            self._bad_index(d)
            r = self._refused(d, ["write", "--slug", "a"] + self.WRITE[1:], body="n")
            self.assertIn("not UTF-8", r.stderr)
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))

    def test_non_utf8_index_refuses_remove_and_keeps_file(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "a.md", self.OWNED_A)
            self._bad_index(d)
            r = self._refused(d, ["remove", "--slug", "a"])
            self.assertIn("not UTF-8", r.stderr)
            self.assertTrue(os.path.exists(os.path.join(d, ".claude", "memory", "a.md")))

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

    BAD = os.fsdecode(b"\xff")  # an argv value that is not valid UTF-8

    def _write(self, slug, title="T", description="d"):
        return ["write", "--slug", slug, "--title", title, "--type", "project",
                "--description", description]

    def _seed_owned(self, d, slug="a"):
        run(d, self._write(slug), body="old body")
        return os.path.join(d, ".claude", "memory", slug + ".md")

    def _assert_names_field(self, r, field):
        self.assertIn(field, r.stderr)
        self.assertIn("UTF-8", r.stderr)

    def test_non_utf8_title_refused_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "other.md", "# x\n")
            r = self._refused(d, self._write("c", title=self.BAD), body="n")
            self._assert_names_field(r, "--title")
            self.assertFalse(os.path.exists(os.path.join(d, ".claude", "memory", "c.md")))

    def test_non_utf8_title_refused_with_no_index_creates_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            r = self._refused(d, self._write("c", title=self.BAD), body="n")
            self._assert_names_field(r, "--title")
            self.assertFalse(os.path.exists(os.path.join(d, ".claude")))

    def test_non_utf8_description_refused_leaves_owned_file_intact(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed_owned(d)
            r = self._refused(d, self._write("a", description=self.BAD), body="n2")
            self._assert_names_field(r, "--description")
            self.assertGreater(len(read(d, "a.md")), 0)

    def test_non_utf8_stdin_refused_under_surrogateescape(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed_owned(d)
            r = self._refused(d, self._write("a"), body=b"\xff\n",
                              env={"PYTHONUTF8": "1"})
            self._assert_names_field(r, "stdin")

    def test_non_utf8_stdin_refused_under_utf8_locale(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed_owned(d)
            r = self._refused(d, self._write("a"), body=b"\xff\n",
                              env={"PYTHONIOENCODING": "utf-8:strict"})
            self._assert_names_field(r, "stdin")

    def test_encoding_refusal_never_echoes_value(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed_owned(d)
            for args, body, field in (
                (self._write("a", title="SECRET" + self.BAD), b"n", "--title"),
                (self._write("a", description="SECRET" + self.BAD), b"n", "--description"),
                (self._write("a"), b"SECRET\xff", "stdin"),
            ):
                r = self._refused(d, args, body=body, env={})
                self._assert_names_field(r, field)
                self.assertNotIn("SECRET", r.stderr)
                self.assertNotIn("\udcff", r.stderr)
                self.assertNotIn("\ufffd", r.stderr)

    def test_symlink_refusal_wins_over_bad_title(self):
        with tempfile.TemporaryDirectory() as d:
            self._seed(d, "other.md", "# x\n")
            os.symlink("other.md", os.path.join(d, ".claude", "memory", "c.md"))
            r = self._refused(d, self._write("c", title=self.BAD), body="n")
            self.assertIn("symbolic link", r.stderr)
            self.assertNotIn("UTF-8", r.stderr)

    def test_non_ascii_utf8_inputs_still_written(self):
        with tempfile.TemporaryDirectory() as d:
            r = run(d, self._write("a", title="caf\u00e9", description="na\u00efve"),
                    body="h\u00e9llo".encode("utf-8"), env={})
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("h\u00e9llo", read(d, "a.md"))
            self.assertIn("- [caf\u00e9](a.md) - na\u00efve", read(d, "MEMORY.md"))
            r = run(d, self._write("b"), body="h\u00e9llo".encode("utf-8"),
                    env={"PYTHONUTF8": "1"})
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("h\u00e9llo", read(d, "b.md"))


class _Hang(BaseException):
    """Raised by the hang guard. A BaseException on purpose: TimeoutError is an
    OSError, which the helper's leaf open converts into an ordinary refusal, so
    a dropped O_NONBLOCK would then pass every FIFO test (#324)."""


def _load_memory():
    spec = importlib.util.spec_from_file_location("memory_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SKILL_MD = os.path.join(os.path.dirname(SCRIPT), "..", "SKILL.md")


class SwapTests(unittest.TestCase):
    """A leaf swapped in AFTER the ownership check (#324). In-process, so the swap
    lands at a deterministic point: check_ownership is wrapped to run the real
    check and then swap, and a 10 s guard turns a FIFO hang into a failure."""

    WRITE = ["write", "--slug", "a", "--title", "t", "--type", "project",
             "--description", "d"]

    def call(self, d, argv, swap=None, stdin=b"new body", after_read_index=None,
             mod=None):
        mod = mod or _load_memory()
        if swap:
            real = mod.check_ownership

            def checked(*a, **k):
                r = real(*a, **k)
                if r is None:
                    swap()
                return r
            mod.check_ownership = checked
        if after_read_index:
            real_ri = mod.read_index

            def read_index(*a, **k):
                try:
                    return real_ri(*a, **k)
                finally:
                    after_read_index()
            mod.read_index = read_index
        old_stdin = sys.stdin
        sys.stdin = types.SimpleNamespace(buffer=io.BytesIO(stdin))
        old_handler = signal.signal(signal.SIGALRM, self._on_alarm)
        err = io.StringIO()
        signal.setitimer(signal.ITIMER_REAL, 10)
        try:
            with contextlib.redirect_stderr(err):
                rc = mod.main(["--project-dir", d] + argv)
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old_handler)
            sys.stdin = old_stdin
        return rc, err.getvalue()

    @staticmethod
    def _on_alarm(signum, frame):
        raise _Hang("the helper blocked")

    def mem(self, d, name="a.md"):
        return os.path.join(d, ".claude", "memory", name)

    def seed(self, d):
        rc, err = self.call(d, self.WRITE, stdin=b"first")
        self.assertEqual(rc, 0, err)

    def bytes_of(self, d, name):
        with open(self.mem(d, name), "rb") as f:
            return f.read()

    def swap_link(self, d, name, target):
        def swap():
            os.remove(self.mem(d, name))
            os.symlink(target, self.mem(d, name))
        return swap

    def swap_dir(self, d, name):
        def swap():
            os.remove(self.mem(d, name))
            os.mkdir(self.mem(d, name))
        return swap

    def swap_fifo(self, d, name, readers, reader=True):
        def swap():
            os.remove(self.mem(d, name))
            os.mkfifo(self.mem(d, name))
            if reader:
                readers.append(os.open(self.mem(d, name), os.O_RDONLY | os.O_NONBLOCK))
        return swap

    def swap_bytes(self, d, name, data):
        def swap():
            os.remove(self.mem(d, name))
            with open(self.mem(d, name), "wb") as f:
                f.write(data)
        return swap

    def refused(self, d, swap, *reasons, argv=None, **kw):
        rc, err = self.call(d, argv or self.WRITE, swap=swap, **kw)
        self.assertEqual(rc, 1, err)
        self.assertIn("memory.py: refusing", err)
        for r in reasons:
            self.assertIn(r, err)
        return err

    def assert_reader_empty(self, readers):
        for fd in readers:
            try:
                self.assertEqual(os.read(fd, 64), b"")
            finally:
                os.close(fd)

    # positives

    def test_write_over_unchanged_target_succeeds(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            rc, err = self.call(d, self.WRITE, stdin=b"two")
            self.assertEqual(rc, 0, err)
            self.assertIn("two", self.bytes_of(d, "a.md").decode())
            self.assertIn("(a.md)", self.bytes_of(d, "MEMORY.md").decode())

    def test_absent_index_is_still_created(self):
        with tempfile.TemporaryDirectory() as d:
            rc, err = self.call(d, self.WRITE)
            self.assertEqual(rc, 0, err)
            idx = self.bytes_of(d, "MEMORY.md").decode()
            self.assertTrue(idx.startswith("<!-- Memory index."))
            self.assertIn("(a.md)", idx)

    def test_created_files_keep_the_0666_mode(self):
        with tempfile.TemporaryDirectory() as d:
            umask = os.umask(0)
            os.umask(umask)
            rc, err = self.call(d, self.WRITE)
            self.assertEqual(rc, 0, err)
            for name in ("a.md", "MEMORY.md"):
                mode = stat.S_IMODE(os.stat(self.mem(d, name)).st_mode)
                self.assertEqual(mode, 0o666 & ~umask, name)

    def test_remove_owned_file_still_removes_file_and_index_line(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            rc, err = self.call(d, ["remove", "--slug", "a"])
            self.assertEqual(rc, 0, err)
            self.assertFalse(os.path.exists(self.mem(d, "a.md")))
            self.assertNotIn("(a.md)", self.bytes_of(d, "MEMORY.md").decode())

    # ordering

    def test_write_reads_stdin_before_ownership_check(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".claude", "memory"))
            foreign = b"# not ours\n"

            def read():
                with open(self.mem(d, "a.md"), "wb") as f:
                    f.write(foreign)
                return b"body"
            mod = _load_memory()
            old = sys.stdin
            sys.stdin = types.SimpleNamespace(buffer=types.SimpleNamespace(read=read))
            err = io.StringIO()
            try:
                with contextlib.redirect_stderr(err):
                    rc = mod.main(["--project-dir", d] + self.WRITE)
            finally:
                sys.stdin = old
            self.assertEqual(rc, 1)
            self.assertIn("not ours to change", err.getvalue())
            self.assertEqual(self.bytes_of(d, "a.md"), foreign)

    def test_write_refuses_bad_slug_before_reading_stdin(self):
        with tempfile.TemporaryDirectory() as d:
            calls = []
            mod = _load_memory()
            old = sys.stdin
            sys.stdin = types.SimpleNamespace(
                buffer=types.SimpleNamespace(read=lambda: calls.append(1) or b""))
            err = io.StringIO()
            try:
                with contextlib.redirect_stderr(err):
                    rc = mod.main(["--project-dir", d, "write", "--slug", "../x",
                                   "--title", "t", "--type", "project",
                                   "--description", "d"])
            finally:
                sys.stdin = old
            self.assertEqual(rc, 1)
            self.assertIn("memory.py: refusing", err.getvalue())
            self.assertEqual(calls, [])

    # swaps at the memory file

    def test_memory_file_dangling_symlink_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            out = os.path.join(d, "outside.md")
            self.refused(d, self.swap_link(d, "a.md", out), "cannot be opened")
            self.assertFalse(os.path.lexists(out))

    def test_memory_file_live_symlink_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            out = os.path.join(d, "outside.md")
            with open(out, "w") as f:
                f.write("KEEP")
            self.refused(d, self.swap_link(d, "a.md", out), "cannot be opened")
            with open(out) as f:
                self.assertEqual(f.read(), "KEEP")

    def test_memory_file_directory_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            self.refused(d, self.swap_dir(d, "a.md"))

    def test_memory_file_reader_less_fifo_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            self.refused(d, self.swap_fifo(d, "a.md", [], reader=False),
                         "cannot be opened (No such device or address)")

    def test_memory_file_fifo_with_reader_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            readers = []
            self.refused(d, self.swap_fifo(d, "a.md", readers), "is not a regular file")
            self.assert_reader_empty(readers)

    # swaps at the index

    def test_index_dangling_symlink_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            out = os.path.join(d, "outside.md")
            self.refused(d, self.swap_link(d, "MEMORY.md", out), "cannot be opened")
            self.assertFalse(os.path.lexists(out))
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_index_live_symlink_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            out = os.path.join(d, "outside.md")
            with open(out, "w") as f:
                f.write("KEEP")
            self.refused(d, self.swap_link(d, "MEMORY.md", out), "cannot be opened")
            with open(out) as f:
                self.assertEqual(f.read(), "KEEP")
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_index_directory_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            self.refused(d, self.swap_dir(d, "MEMORY.md"), "is not a regular file")
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_index_fifo_swapped_after_check_refused(self):
        for with_reader in (False, True):
            with self.subTest(with_reader=with_reader), tempfile.TemporaryDirectory() as d:
                self.seed(d)
                before = self.bytes_of(d, "a.md")
                readers = []
                self.refused(d, self.swap_fifo(d, "MEMORY.md", readers, reader=with_reader),
                             "is not a regular file")
                self.assertEqual(self.bytes_of(d, "a.md"), before)
                self.assert_reader_empty(readers)

    def test_index_non_utf8_swapped_after_check_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            self.refused(d, self.swap_bytes(d, "MEMORY.md", b"\xff\xfe"), "is not UTF-8")
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_index_write_open_refuses_a_link_swapped_in_after_read_index(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            out = os.path.join(d, "outside.md")
            with open(out, "w") as f:
                f.write("KEEP")
            self.refused(d, None, "cannot be opened",
                         after_read_index=self.swap_link(d, "MEMORY.md", out))
            with open(out) as f:
                self.assertEqual(f.read(), "KEEP")
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_read_index_refuses_dangling_symlink_and_directory(self):
        mod = _load_memory()
        for make in (lambda p: os.symlink("nowhere", p), os.mkdir):
            with tempfile.TemporaryDirectory() as d:
                os.makedirs(os.path.join(d, ".claude", "memory"))
                make(self.mem(d, "MEMORY.md"))
                with self.assertRaises(mod._Refusal):
                    mod.read_index(d)

    # nothing that existed changes when the other leaf is refused

    def test_index_untouched_when_memory_file_refused(self):
        for swap in ("dir", "fifo"):
            with self.subTest(swap=swap), tempfile.TemporaryDirectory() as d:
                self.seed(d)
                before = self.bytes_of(d, "MEMORY.md")
                readers = []
                self.refused(d, self.swap_dir(d, "a.md") if swap == "dir"
                             else self.swap_fifo(d, "a.md", readers))
                self.assertEqual(self.bytes_of(d, "MEMORY.md"), before)
                self.assert_reader_empty(readers)

    def test_absent_index_stays_absent_when_memory_file_refused(self):
        for swap in ("dir", "fifo"):
            with self.subTest(swap=swap), tempfile.TemporaryDirectory() as d:
                self.seed(d)
                os.remove(self.mem(d, "MEMORY.md"))
                readers = []
                self.refused(d, self.swap_dir(d, "a.md") if swap == "dir"
                             else self.swap_fifo(d, "a.md", readers))
                self.assertFalse(os.path.lexists(self.mem(d, "MEMORY.md")))
                self.assert_reader_empty(readers)

    # remove

    def test_remove_refuses_index_swapped_after_check_and_keeps_the_file(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            before = self.bytes_of(d, "a.md")
            out = os.path.join(d, "outside.md")
            self.refused(d, self.swap_link(d, "MEMORY.md", out),
                         argv=["remove", "--slug", "a"])
            self.assertFalse(os.path.lexists(out))
            self.assertEqual(self.bytes_of(d, "a.md"), before)

    def test_remove_refuses_a_directory_swapped_in_at_the_memory_file(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            self.refused(d, self.swap_dir(d, "a.md"), "cannot be removed",
                         argv=["remove", "--slug", "a"])

    # permissions, as a clean refusal

    @unittest.skipIf(os.geteuid() == 0, "root ignores file modes")
    def test_owned_readonly_memory_file_refused_cleanly(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            os.chmod(self.mem(d, "a.md"), 0o444)
            idx, mem = self.bytes_of(d, "MEMORY.md"), self.bytes_of(d, "a.md")
            self.refused(d, None, "cannot be opened (Permission denied)")
            self.assertEqual(self.bytes_of(d, "a.md"), mem)
            self.assertEqual(self.bytes_of(d, "MEMORY.md"), idx)

    @unittest.skipIf(os.geteuid() == 0, "root ignores directory modes")
    def test_missing_index_in_readonly_directory_leaves_the_memory_file_alone(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            os.remove(self.mem(d, "MEMORY.md"))
            before = self.bytes_of(d, "a.md")
            os.chmod(os.path.dirname(self.mem(d, "a.md")), 0o555)
            try:
                self.refused(d, None, "cannot be created (Permission denied)")
                self.assertEqual(self.bytes_of(d, "a.md"), before)
            finally:
                os.chmod(os.path.dirname(self.mem(d, "a.md")), 0o755)

    # a real process: refusal, never a Traceback

    def test_refusal_has_no_traceback_in_a_real_process(self):
        with tempfile.TemporaryDirectory() as d:
            self.seed(d)
            driver = (
                "import importlib.util, os, sys\n"
                "spec = importlib.util.spec_from_file_location('m', sys.argv[1])\n"
                "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
                "real = m.check_ownership\n"
                "def checked(*a):\n"
                "    r = real(*a)\n"
                "    p = os.path.join(sys.argv[2], '.claude', 'memory', 'a.md')\n"
                "    os.remove(p); os.mkfifo(p)\n"
                "    global fd; fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)\n"
                "    return r\n"
                "m.check_ownership = checked\n"
                "sys.exit(m.main(['--project-dir', sys.argv[2], 'write', '--slug', 'a',\n"
                "                 '--title', 't', '--type', 'project', '--description', 'd']))\n")
            r = subprocess.run([sys.executable, "-c", driver, SCRIPT, d], input=b"x",
                               capture_output=True, timeout=10)
            err = r.stderr.decode("utf-8", errors="replace")
            self.assertEqual(r.returncode, 1, err)
            self.assertIn("memory.py: refusing", err)
            self.assertNotIn("Traceback", err)

    # docs

    def test_skill_md_index_sentence_reworded(self):
        with open(SKILL_MD, encoding="utf-8") as f:
            text = " ".join(f.read().split())
        self.assertIn("The `MEMORY.md` index gets the same file-type and readability "
                      "checks, and must also be writable, before anything is written "
                      "or deleted.", text)
        self.assertNotIn("The same applies to the `MEMORY.md` index", text)


if __name__ == "__main__":
    unittest.main()
