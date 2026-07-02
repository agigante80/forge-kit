#!/usr/bin/env python3
# block-legacy-host-push-version: 1
"""
forge-kit PreToolUse hook: deny `git push` to an archived legacy host after a
forge migration (e.g. GitHub to self-hosted Forgejo). The friendly in-session
layer over the real belt (remove the legacy remote, or poison its push URL,
plus the server-side archive reject). Project-scoped: install it only in
migrated repos, via the github-to-forgejo skill's cutover phase.

Design (from forge-kit issue #22 review):
- Never grep the raw command string. Split into logical lines (quote-aware),
  tokenize each (shlex), split into command segments on shell operators, and
  inspect only real `git push` invocations. Quoted strings (commit messages,
  comments) are single data tokens, so text like "how to push github mirror"
  can never false-positive.
- Resolve the actual push target: the first positional arg if present, else
  the --repo value (git's own precedence), else the default push destination
  (branch.<b>.pushRemote, remote.pushDefault, branch.<b>.remote, then
  origin). A bare `git push` whose upstream still points at the legacy host
  IS caught. scp-style targets (host:path, with or without user@) count as
  URLs, matching git.
- Compare resolved URL HOSTS, never names: a remote called `github-mirror`
  is blocked iff its push URL points at a legacy host.
- Deny-legacy-host by default; strict allowlist is opt-in. Fail OPEN on any
  parse or resolve error (same posture as block-dashes).

Config (committed .forge.conf at the repo root; env vars override):
  FORGE_LEGACY_HOSTS   hosts to deny, space/comma separated. Defaults to
                       "github.com" when a .forge.conf exists (the hook is
                       installed post-migration); an EMPTY value does not
                       disable the default (remove the hook instead). No
                       .forge.conf and no env list means not configured:
                       everything is allowed.
  FORGE_REMOTE         the configured current remote (used in the deny
                       message, and as the allowlist in strict mode).
  FORGE_PUSH_STRICT    "1" to deny any push whose target is not FORGE_REMOTE
                       (by name or by resolved push URL).

Wiring (project .claude/settings.json):
  { "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
      { "type": "command",
        "command": "python3 .claude/hooks/block-legacy-host-push.py" } ] } ] } }

Self-test: `python3 block-legacy-host-push.py --self-test` builds a sandbox
repo and runs the full verdict matrix (the reproducible form of the issue
#22 test matrix). Run it after any change to the parsing core.

Known limitations (both fail toward safety):
- Heredoc bodies cannot be parsed shell-accurately, so scanning stops at the
  first heredoc marker (fail open for what follows).
- UNQUOTED text that literally spells a push invocation inside another
  command (e.g. `echo git push github main`) is denied (fail closed): the
  tokens are indistinguishable from a real push. Quote such text.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from urllib.parse import urlparse

SEGMENT_OPS = {"&&", "||", ";", "|", "&", "(", ")"}
# git global flags that consume the NEXT token as their argument
GIT_GLOBAL_ARG_FLAGS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
# push flags that consume the NEXT token as their argument (--repo handled separately)
PUSH_ARG_FLAGS = {"-o", "--push-option", "--receive-pack", "--exec"}
# a whole token that is a redirection word: 2>/dev/null, >out, >>log, 2>&1, <in, &>f
REDIR_ATOM = re.compile(r"(\d*|&)(>>|>|<)([^;|()<>\s]*)")
# redirection operator alone (the NEXT token is its filename): >, >>, <, 2>, 2>>
REDIR_BARE = re.compile(r"(\d*|&)(>>|>|<)")


def run_git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                           text=True, timeout=5)
        out = r.stdout.strip()
        return out if r.returncode == 0 and out else None
    except Exception:
        return None


def logical_lines(command):
    """Split the command on newlines that are OUTSIDE quotes, so a multi-line
    quoted string stays one line while `git push\\ngit status` becomes two.
    Backslash-escaped newlines (line continuations) do not split."""
    lines, cur, quote, esc = [], [], None, False
    for ch in command:
        if esc:
            cur.append(ch)
            esc = False
            continue
        if ch == "\\" and quote != "'":
            esc = True
            cur.append(ch)
            continue
        if quote:
            if ch == quote:
                quote = None
            cur.append(ch)
            continue
        if ch in "'\"":
            quote = ch
            cur.append(ch)
            continue
        if ch == "\n":
            lines.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    lines.append("".join(cur))
    return lines


def line_tokens(line):
    """shlex-tokenize one logical line; quoted strings become single data
    tokens. comments=False because bash starts a comment only at word start
    (shlex's comments=True eats mid-word '#', truncating real targets); we
    drop tokens from the first token that BEGINS with '#' instead. Returns
    None on unparseable input so the caller fails open for this line."""
    try:
        toks = shlex.split(line, comments=False, posix=True)
    except ValueError:
        return None
    out = []
    for t in toks:
        if t.startswith("#") and not any(c.isspace() for c in t):
            break  # comment: rest of the line is not code
        out.append(t)
    return out


def segments(tokens):
    """Split one line's token stream into command segments at shell
    operators. Tokens containing whitespace came from quotes: they are data,
    never operators or command words, and are kept atomic. Redirection words
    are kept atomic too (2>&1 must not split at '&'). Unspaced operators
    stuck to a word (a&&b, subshell parens) are split off. Yields segments;
    yields the sentinel None on a heredoc marker (caller must stop: the body
    spans following lines and cannot be parsed reliably)."""
    seg = []
    for tok in tokens:
        if any(c.isspace() for c in tok):
            seg.append(tok)  # quoted data, atomic
            continue
        if "<<" in tok:
            if seg:
                yield seg
            yield None  # heredoc: fail open from here on
            return
        if REDIR_ATOM.fullmatch(tok):
            seg.append(tok)  # atomic redirection word
            continue
        for p in re.split(r"([;&|()]+)", tok):
            if not p:
                continue
            if re.fullmatch(r"[;&|()]+", p):
                if seg:
                    yield seg
                seg = []
            else:
                seg.append(p)
    if seg:
        yield seg


def skip_redirection(seg, k):
    """If seg[k] is a redirection word, return the index after it (and after
    its filename token when the operator stands alone). Else return k."""
    t = seg[k]
    if REDIR_BARE.fullmatch(t):
        return k + 2  # bare operator: next token is the target file
    if REDIR_ATOM.fullmatch(t):
        return k + 1  # filename or fd attached: one token
    return k


def push_targets(seg):
    """Yield the push target (or None for default) for every `git push`
    invocation in one command segment. Positional repo wins over --repo,
    matching git's own precedence."""
    i = 0
    while i < len(seg):
        tok = seg[i]
        if tok == "git" or tok.endswith("/git"):
            j = i + 1
            while j < len(seg):  # skip git global options + redirections
                t = seg[j]
                nj = skip_redirection(seg, j)
                if nj != j:
                    j = nj
                elif t in GIT_GLOBAL_ARG_FLAGS:
                    j += 2
                elif t.startswith("-") and t != "--":
                    j += 1
                else:
                    break
            if j < len(seg) and seg[j] == "push":
                target = None
                repo_opt = None
                k = j + 1
                seen_ddash = False
                while k < len(seg):
                    t = seg[k]
                    nk = skip_redirection(seg, k)
                    if nk != k:
                        k = nk
                        continue
                    if seen_ddash:
                        target = t  # first positional after -- is the repo
                        break
                    if t == "--":
                        seen_ddash = True
                        k += 1
                    elif t.startswith("--repo="):
                        repo_opt = t[len("--repo="):]
                        k += 1
                    elif t == "--repo":
                        if k + 1 < len(seg):
                            repo_opt = seg[k + 1]
                        k += 2
                    elif t in PUSH_ARG_FLAGS:
                        k += 2
                    elif t.startswith("-"):
                        k += 1
                    else:
                        target = t  # first positional arg is the repository
                        break
                if target is None:
                    target = repo_opt  # git: --repo applies only w/o positional
                if target is not None and any(c.isspace() for c in target):
                    target = None  # quoted data in target slot; fail open
                    yield ("unparseable", None)
                else:
                    yield ("push", target)
                i = k
        i += 1


def find_push_invocations(command):
    """All push targets across the whole command. None target = default."""
    found = []
    for line in logical_lines(command):
        tokens = line_tokens(line)
        if tokens is None:
            continue  # unparseable line: fail open for it, keep scanning
        for seg in segments(tokens):
            if seg is None:
                return found  # heredoc: stop scanning entirely
            for kind, target in push_targets(seg):
                if kind == "push":
                    found.append(target)
    return found


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
    if "://" in s:
        return True
    if s.startswith(("/", "./", "../")):
        return True  # path remote (no host)
    # scp-like: [user@]host:path. git treats any colon before the first
    # slash as scp syntax; user@ is OPTIONAL. Remote names cannot contain
    # ':', so this cannot misclassify a remote name.
    return re.match(r"^[^/\s]+:", s) is not None


def host_of(url):
    m = re.match(r"^(?:[^@/\s]+@)?([^:/\s]+):", url)  # [user@]host:path
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
    if not isinstance(payload, dict):
        sys.exit(0)

    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    command = (payload.get("tool_input") or {}).get("command") or ""
    if "push" not in command:  # cheap pre-filter only; real parsing below
        sys.exit(0)
    cwd = payload.get("cwd") or os.getcwd()

    invocations = find_push_invocations(command)
    if not invocations:
        sys.exit(0)

    conf, conf_found = load_conf(cwd)
    legacy_raw = conf.get("FORGE_LEGACY_HOSTS", "")
    if not legacy_raw and not conf_found:
        sys.exit(0)  # not configured for this repo: allow everything
    # NOTE: an explicitly EMPTY FORGE_LEGACY_HOSTS still gets the github.com
    # default; disabling the deny list means uninstalling the hook.
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


# --- self-test -------------------------------------------------------------

def self_test():
    """Build a sandbox repo and run the verdict matrix. Exits 1 on failure."""
    import tempfile
    d = tempfile.mkdtemp(prefix="blhp-test-")
    g = lambda *a: subprocess.run(["git", "-C", d] + list(a),
                                  capture_output=True, text=True)
    g("init", "-q", "-b", "main", ".")
    g("-c", "user.name=t", "-c", "user.email=t@t",
      "commit", "-q", "--allow-empty", "-m", "base")
    g("remote", "add", "origin", "https://forge.example.com/o/r.git")
    g("remote", "add", "github", "https://github.com/o/r.git")
    g("remote", "add", "github-mirror", "git@github.com:o/r.git")
    g("remote", "add", "fork", "https://gitlab.example.com/o/r.git")
    conf = os.path.join(d, ".forge.conf")
    with open(conf, "w") as f:
        f.write("FORGE_HOST=forgejo\nFORGE_REMOTE=origin\n")

    def verdict(cmd, cwd=d):
        payload = json.dumps({"tool_name": "Bash",
                              "tool_input": {"command": cmd}, "cwd": cwd})
        r = subprocess.run([sys.executable, os.path.abspath(__file__)],
                           input=payload, capture_output=True, text=True)
        return "DENY" if '"deny"' in r.stdout else "ALLOW"

    cases = [
        ("ALLOW", "git push origin main"),
        ("DENY",  "git push github main"),
        ("DENY",  "git push -u github main"),
        ("DENY",  "git push https://github.com/a/b main"),
        ("DENY",  "git push git@github.com:a/b.git main"),
        ("DENY",  "git push github.com:a/b.git main"),          # scp, no user@
        ("ALLOW", 'git commit -m "see github.com" && git push origin main'),
        ("ALLOW", 'git commit -m "how to push github mirror" && git push origin main'),
        ("ALLOW", "git push origin main # do not push github"),
        ("ALLOW", "git push origin github"),                     # branch name
        ("DENY",  "git push github-mirror main"),                # URL resolution
        ("DENY",  "git -C %s push github main" % d),
        ("ALLOW", "git push fork main"),
        ("ALLOW", "git status"),
        ("ALLOW", "git push --repo=github main"),   # positional 'main' is the repo (git errors)
        ("DENY",  "git push --repo=github"),                     # no positional
        ("DENY",  "git push --repo github"),                     # no positional
        ("ALLOW", "git push --repo github origin main"),         # positional wins
        ("DENY",  "git push --repo origin github main"),         # positional wins
        ("ALLOW", "git push -o ci.skip origin main"),
        ("DENY",  "git push 2>/dev/null github main"),           # redirection
        ("DENY",  "git push >/dev/null github main"),
        ("DENY",  "git push 2>&1 github main"),
        ("DENY",  "(git push github main)"),                     # subshell
        ("DENY",  "git push -o topic#1 github main"),            # mid-word #
        ("DENY",  "echo x && git push github main"),
        ("DENY",  "git push origin main\ngit push github main"), # 2nd line
        ("ALLOW", "git push origin main\ngit status"),
    ]
    fails = 0
    for want, cmd in cases:
        got = verdict(cmd)
        mark = "ok " if got == want else "XX "
        if got != want:
            fails += 1
        print("%s want=%-5s got=%-5s | %s" % (mark, want, got, cmd.replace("\n", "\\n")))

    # bare push: upstream on legacy host must DENY; on the forge, ALLOW
    g("config", "branch.main.remote", "github")
    g("config", "branch.main.merge", "refs/heads/main")
    for want, cmd, label in [("DENY", "git push", "bare push, upstream github"),
                             ("DENY", "git push\ngit status", "bare push then 2nd line")]:
        got = verdict(cmd)
        mark = "ok " if got == want else "XX "
        if got != want:
            fails += 1
        print("%s want=%-5s got=%-5s | %s" % (mark, want, got, label))
    g("config", "branch.main.remote", "origin")
    got = verdict("git push")
    mark = "ok " if got == "ALLOW" else "XX "
    if got != "ALLOW":
        fails += 1
    print("%s want=ALLOW got=%-5s | bare push, upstream origin" % (mark, got))

    # strict mode
    with open(conf, "w") as f:
        f.write("FORGE_HOST=forgejo\nFORGE_REMOTE=origin\nFORGE_PUSH_STRICT=1\n")
    for want, cmd in [("DENY", "git push fork main"), ("ALLOW", "git push origin main")]:
        got = verdict(cmd)
        mark = "ok " if got == want else "XX "
        if got != want:
            fails += 1
        print("%s want=%-5s got=%-5s | strict: %s" % (mark, want, got, cmd))

    # not configured: no .forge.conf means allow everything
    os.remove(conf)
    got = verdict("git push github main")
    mark = "ok " if got == "ALLOW" else "XX "
    if got != "ALLOW":
        fails += 1
    print("%s want=ALLOW got=%-5s | no .forge.conf" % (mark, got))

    import shutil
    shutil.rmtree(d, ignore_errors=True)
    print("self-test: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        self_test()
    else:
        try:
            main()
        except SystemExit:
            raise
        except Exception:
            sys.exit(0)  # fail open, as documented
