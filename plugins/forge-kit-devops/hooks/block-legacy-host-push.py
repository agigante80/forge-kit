#!/usr/bin/env python3
# block-legacy-host-push-version: 1
"""
forge-kit PreToolUse hook: deny `git push` to an archived legacy host after a
forge migration (e.g. GitHub to self-hosted Forgejo). The friendly in-session
layer over the real belt (remove the legacy remote, or poison its push URL,
plus the server-side archive reject). Project-scoped: install it only in
migrated repos, via the github-to-forgejo skill's cutover phase.

Design (from forge-kit issue #22 review):
- Never grep the raw command string. Tokenize (shlex), split into command
  segments on shell operators, and inspect only real `git push` invocations.
  Quoted strings (commit messages, comments) are single data tokens, so text
  like "how to push github mirror" can never false-positive.
- Resolve the actual push target: the first positional arg (or --repo value)
  if explicit, else the default push destination (branch.<b>.pushRemote,
  remote.pushDefault, branch.<b>.remote, then origin). A bare `git push`
  whose upstream still points at the legacy host IS caught.
- Compare resolved URL HOSTS, never names: a remote called `github-mirror`
  is blocked iff its push URL points at a legacy host.
- Deny-legacy-host by default; strict allowlist is opt-in. Fail OPEN on any
  parse or resolve error (same posture as block-dashes).

Config (committed .forge.conf at the repo root; env vars override):
  FORGE_LEGACY_HOSTS   hosts to deny, space/comma separated. Defaults to
                       "github.com" when a .forge.conf exists (the hook is
                       installed post-migration). No .forge.conf and no env
                       list means not configured: everything is allowed.
  FORGE_REMOTE         the configured current remote (used in the deny
                       message, and as the allowlist in strict mode).
  FORGE_PUSH_STRICT    "1" to deny any push whose target is not FORGE_REMOTE
                       (by name or by resolved push URL).

Wiring (project .claude/settings.json):
  { "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
      { "type": "command",
        "command": "python3 .claude/hooks/block-legacy-host-push.py" } ] } ] } }

Known limitation: heredoc bodies cannot be parsed shell-accurately, so token
scanning stops at the first heredoc marker (fail open for what follows).
"""

import json
import os
import re
import shlex
import subprocess
import sys
from urllib.parse import urlparse

SEGMENT_OPS = {"&&", "||", ";", "|", "&"}
# git global flags that consume the NEXT token as their argument
GIT_GLOBAL_ARG_FLAGS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
# push flags that consume the NEXT token as their argument
PUSH_ARG_FLAGS = {"-o", "--push-option", "--receive-pack", "--exec", "--repo"}


def run_git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                           text=True, timeout=5)
        out = r.stdout.strip()
        return out if r.returncode == 0 and out else None
    except Exception:
        return None


def tokenize(command):
    """shlex-tokenize; quoted strings become single data tokens. Returns None
    on unparseable input (unbalanced quotes) so the caller fails open."""
    try:
        return shlex.split(command, comments=True, posix=True)
    except ValueError:
        return None


def segments(tokens):
    """Split the token stream into command segments at shell operators.
    Tokens containing whitespace came from quotes: they are data, never
    operators or command words, and are kept atomic. Unspaced operators
    stuck to a word (a&&b) are split off. Stop at a heredoc marker."""
    seg = []
    for tok in tokens:
        if "<<" in tok and not any(c.isspace() for c in tok):
            if seg:
                yield seg
            return  # heredoc body follows; cannot parse reliably, fail open
        if not any(c.isspace() for c in tok):
            parts = re.split(r"([;&|]+)", tok)
        else:
            parts = [tok]
        for p in parts:
            if not p:
                continue
            if p in SEGMENT_OPS or re.fullmatch(r"[;&|]+", p):
                if seg:
                    yield seg
                seg = []
            else:
                seg.append(p)
    if seg:
        yield seg


def push_targets(seg):
    """Yield the explicit push target (or None for default) for every
    `git push` invocation in one command segment."""
    i = 0
    while i < len(seg):
        tok = seg[i]
        if tok == "git" or tok.endswith("/git"):
            j = i + 1
            while j < len(seg):  # skip git global options
                t = seg[j]
                if t in GIT_GLOBAL_ARG_FLAGS:
                    j += 2
                elif t.startswith("-") and t != "--":
                    j += 1
                else:
                    break
            if j < len(seg) and seg[j] == "push":
                target = None
                k = j + 1
                seen_ddash = False
                while k < len(seg):
                    t = seg[k]
                    if seen_ddash:
                        target = t  # first positional after -- is the repo
                        break
                    if t == "--":
                        seen_ddash = True
                        k += 1
                    elif t.startswith("--repo="):
                        target = t[len("--repo="):]
                        break
                    elif t in PUSH_ARG_FLAGS:
                        if t == "--repo" and k + 1 < len(seg):
                            target = seg[k + 1]
                            break
                        k += 2
                    elif t.startswith("-"):
                        k += 1
                    else:
                        target = t  # first positional arg is the repository
                        break
                if target is not None and any(c.isspace() for c in target):
                    target = None  # quoted data landed in target position; fail open
                    yield ("unparseable", None)
                else:
                    yield ("push", target)
                i = k
        i += 1


def default_target(cwd):
    branch = run_git(["symbolic-ref", "--short", "HEAD"], cwd)
    t = None
    if branch:
        t = run_git(["config", "branch.%s.pushRemote" % branch], cwd)
    t = t or run_git(["config", "remote.pushDefault"], cwd)
    if not t and branch:
        t = run_git(["config", "branch.%s.remote" % branch], cwd)
    return t or "origin"


def looks_like_url(s):
    return ("://" in s
            or re.match(r"^[^@/\s]+@[^:/\s]+:", s) is not None  # scp-like
            or s.startswith(("/", "./", "../")))                # path remote


def host_of(url):
    m = re.match(r"^(?:[^@/\s]+@)?([^:/\s]+):", url)  # git@host:path
    if m and "://" not in url:
        return m.group(1).lower()
    try:
        h = urlparse(url).hostname
        return h.lower() if h else None
    except Exception:
        return None


def load_conf(cwd):
    conf = {}
    top = run_git(["rev-parse", "--show-toplevel"], cwd)
    path = os.path.join(top, ".forge.conf") if top else None
    found = False
    if path and os.path.isfile(path):
        found = True
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip().rstrip("\r")
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    v = v.split("#", 1)[0].strip().strip("'\"")
                    conf[k.strip()] = v
        except OSError:
            pass
    for k in ("FORGE_LEGACY_HOSTS", "FORGE_REMOTE", "FORGE_PUSH_STRICT"):
        if os.environ.get(k):
            conf[k] = os.environ[k]
    return conf, found


def deny(reason):
    print(json.dumps({
        "decision": "block",
        "reason": reason,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
    }))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # fail open

    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    command = (payload.get("tool_input") or {}).get("command") or ""
    if "push" not in command:  # cheap pre-filter only; real parsing below
        sys.exit(0)
    cwd = payload.get("cwd") or os.getcwd()

    tokens = tokenize(command)
    if tokens is None:
        sys.exit(0)

    invocations = []
    for seg in segments(tokens):
        for kind, target in push_targets(seg):
            if kind == "push":
                invocations.append(target)
    if not invocations:
        sys.exit(0)

    conf, conf_found = load_conf(cwd)
    legacy_raw = conf.get("FORGE_LEGACY_HOSTS", "")
    if not legacy_raw and not conf_found:
        sys.exit(0)  # not configured for this repo: allow everything
    legacy_hosts = [h.lower() for h in re.split(r"[,\s]+", legacy_raw) if h] \
        or ["github.com"]
    forge_remote = conf.get("FORGE_REMOTE", "origin")
    strict = conf.get("FORGE_PUSH_STRICT", "") == "1"

    for target in invocations:
        name = target if target is not None else default_target(cwd)
        if looks_like_url(name):
            url = name
        else:
            url = run_git(["remote", "get-url", "--push", name], cwd)
            if url is None:
                continue  # unknown remote: git will error itself; fail open
        host = host_of(url)
        if host and any(host == lh or host.endswith("." + lh)
                        for lh in legacy_hosts):
            shown = target if target is not None else \
                "%s (default push destination of the current branch)" % name
            deny("Push blocked: target '%s' resolves to %s, an archived legacy "
                 "host for this repo. Push to '%s' (the configured forge) "
                 "instead. If the branch upstream still points at the legacy "
                 "remote, fix it: git branch --set-upstream-to=%s/<branch>."
                 % (shown, host, forge_remote, forge_remote))
        if strict and name != forge_remote:
            allowed_url = run_git(["remote", "get-url", "--push", forge_remote], cwd)
            if not (allowed_url and url == allowed_url):
                deny("Push blocked (strict mode): target '%s' is not the "
                     "configured forge remote '%s'. Unset FORGE_PUSH_STRICT "
                     "in .forge.conf to allow other remotes." % (name, forge_remote))
    sys.exit(0)


if __name__ == "__main__":
    main()
