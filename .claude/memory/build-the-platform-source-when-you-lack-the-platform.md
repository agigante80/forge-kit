---
name: build-the-platform-source-when-you-lack-the-platform
description: "2026-09-14: Apple awk and bash 3.2.57 built on Linux stood in for a Mac; the awk build found the no-regex-over-content rule and the suites had never run under 3.2"
metadata:
  type: feedback
---

When a platform is unavailable, build its actual source rather than reading about it. On 2026-09-14 #191 waited on a probe "on a real Mac" the maintainer could not run. The substitute: clone `apple-oss-distributions/awk` (the fork macOS ships, tag `awk-40`, prints `awk version 20200816`), which builds on Linux with two shims for macOS-only libc symbols (`__collate_lookup_l`, `fmtcheck`), and bash 3.2.57 from the GNU tarball (needs bison, obtainable without root via `apt-get download` plus `dpkg -x`; the shipped `y.tab.c` is stale). Both live under the session scratchpad only; rebuild when needed.

**Why:** the build found what no document would have. Apple`s awk aborts (`towc: multibyte conversion failure`) the moment a REGEX meets a byte over 0x7F under glibc`s C locale, which became the design rule "no content or path byte through a regex in awk". And the leak-guard suites had never been RUN under bash 3.2, only grepped for bash-4 constructs; with the 3.2 binary first on PATH the scanners themselves run under it.

**How to apply:** for any portability claim about macOS shell tooling, run the suites with `PATH=<bash32 dir>:$PATH` and the Apple awk symlinked as `awk`; state in the README what was and was not exercised (BSD tr, Apple git, the filesystem were not). Related: [[verify-against-installed-artifacts]], [[surviving-mutant-check-the-mutant-first]].
