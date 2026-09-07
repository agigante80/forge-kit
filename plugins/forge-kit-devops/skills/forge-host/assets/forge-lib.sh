#!/usr/bin/env bash
# forge-lib-version: 8
# forge-lib.sh: host-aware forge operations (GitHub | Forgejo). Source it; governance components
# call the forge_* functions instead of `gh` directly, so the same logic works whether a repo lives
# on GitHub or a self-hosted Forgejo. ADDITIVE: a repo with no Forgejo config defaults to GitHub and
# behaves exactly as before.
#
# Design note: both backends use the REST API (GitHub via `gh api`, Forgejo via `curl`), NOT gh's
# porcelain, because Forgejo's API is the Gitea API, whose JSON shapes (issues, releases, comments)
# closely match GitHub's REST. Using REST on both sides keeps the jq parsing in callers identical.
#
# Host detection (first match wins, so automation is DETERMINISTIC and never "asks"):
#   1. $FORGE_HOST env var                      (explicit override, e.g. in CI)
#   2. a committed .forge.conf at the repo root (see forge.conf.example)
#   3. the git remote URL                       (github.com -> github; otherwise forgejo IFF a
#                                                Forgejo API URL is configured, else github)
#
# Requires: git, jq. GitHub backend uses `gh` (its existing auth); Forgejo backend uses `curl` + a
# token. Set FORGE_DRY_RUN=1 to print would-be API requests instead of sending them.
# CONTRACT CHANGES (read this before `forge-adapt refresh forge-lib` lands a new copy).
# `refresh` is report-first for assets, so a human sees the diff; this list is what makes that
# diff mean something, because a byte diff does not say whether a CALLER has to change.
#   v4  forge_issue_label REFUSES ATOMICALLY on any unresolvable name (it used to apply what it
#       could and exit 0). A caller that ignored the exit code now silently applies NO labels
#       where it previously applied some. Check every call site (issue #63).
#   v5  forge_api reports the HTTP status through its EXIT CODE on the forgejo path: 44 for 404,
#       22 for other non-2xx, and curl's own code for a transport failure. A caller that treated
#       any non-zero as fatal now sees 44 for the ordinary "no such org" case. NOTE a 3xx that
#       survives -L now returns 22 where `curl -f` returned 0, because -f only failed on >= 400
#       (issue #78).
#   v6  the config is parsed ONCE per process per working directory instead of on every call. A
#       caller that edited .forge.conf mid-run and expected the next call to see it must now cd
#       out and back, or unset _FORGE_CONF_PWD (issue #78.1).
#   v7  file-derived FORGE_* values are no longer EXPORTED, so they do not reach a child process.
#       This is what makes a child running in a different repo read its OWN .forge.conf. A caller
#       that relied on sourcing forge-lib and then having a child inherit the repo identity must
#       now export the value itself, which is the documented env-wins path anyway (issue #78).
# Add a line here whenever a change alters what a caller must do, not merely what the library
# does internally.

set -uo pipefail

# Never inherit these: an inherited _FORGE_TMPDIR would be trusted, written to with a predictable
# name and never cleaned; an inherited memo guard would suppress the first config load.
unset _FORGE_TMPDIR _FORGE_CONF_PWD _FORGE_FROM_FILE

_forge_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# Load .forge.conf (KEY=value lines) if present. Env vars already set WIN over the file.
# Memoized per process and per working directory (issue #78.1). Every page of a paginated call used
# to re-run this about four times, via forge_host, forge_api_base and _forge_token, each costing a
# `git rev-parse` plus a fork per config line.
#
# File-derived values are set as PLAIN shell variables and deliberately NOT exported, so they never
# reach a child process; a child sourcing this library in another repo reads that repo's own file.
# Exporting them was a long-standing bug, not one this branch introduced: measured on the pre-#78
# baseline and on this branch, any forge_* call made OUTSIDE a command substitution leaked the repo
# identity to every later child, identically on both. What #78.1 changed is the REACH, because
# loading in forge_api_paginate's own shell (which is what makes the memo pay) turned the common
# paginated path into one of those direct calls.
#
# Values set FROM THE FILE are also tracked and cleared when the working directory changes, so a
# process that moves between repos re-reads correctly in-shell.
#
# KNOWN LIMIT (issue #131): the tracking is by KEY, not by value, so a caller that exports a
# FORGE_* value AFTER a load which set that same key from the file will have its export cleared on
# the next chdir. Env-wins holds everywhere else. Detecting this needs the variable's export
# attribute, and the portable ways to read it cost a fork per key.
_forge_load_conf() {
  # The guard keys on $PWD, a shell builtin that costs nothing, NOT on the resolved root: resolving
  # the root runs `git rev-parse`, and doing that BEFORE the guard is why the first version of this
  # memo saved nothing measurable (25 git calls per 6-page paginate, before and after, measured).
  # $PWD is a sound proxy: the root cannot change without the working directory changing.
  local f line k v root
  [ "${_FORGE_CONF_PWD-}" != "${PWD-}" ] || return 0
  root="$(_forge_root)"
  # Reachable, and removed once as "dead": in a DELETED working directory both `git rev-parse` and
  # the `pwd` fallback fail, root is empty, and "$root/.forge.conf" collapses to /.forge.conf, whose
  # FORGE_API_URL and FORGE_TOKEN_ENV this library would then adopt.
  [ -n "$root" ] || return 0
  # Clear anything a PREVIOUS directory's file set, or env-wins would make the new file a no-op.
  # Loading in the caller's shell (which is what makes the memo pay) means these values persist,
  # so a process moving between repos would otherwise keep the first repo's identity.
  for k in ${_FORGE_FROM_FILE-}; do unset "$k"; done
  _FORGE_FROM_FILE=""
  _FORGE_CONF_PWD="${PWD-}"
  f="$root/.forge.conf"
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                                  # tolerate CRLF line endings
    case "$line" in ''|\#*) continue ;; esac              # skip blanks + comments
    case "$line" in *=*) ;; *) continue ;; esac           # skip lines without '='
    k="${line%%=*}"; v="${line#*=}"                        # split on FIRST '=' (values may contain '=')
    k="${k//[[:space:]]/}"                                 # keys never contain spaces, so trim fully
    v="${v%%#*}"; v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')"
    case "$k" in
      FORGE_HOST|FORGE_API_URL|FORGE_REPO|FORGE_TOKEN_ENV|FORGE_REMOTE|FORGE_NO_GIT_CREDENTIALS)
        [ -n "${!k:-}" ] || { printf -v "$k" '%s' "$v"     # NOT exported: see the header note
                              _FORGE_FROM_FILE="${_FORGE_FROM_FILE-} $k"; } ;;  # env wins; else file
    esac
  done < "$f"
}

# forge_host: print 'github' or 'forgejo'.
forge_host() {
  _forge_load_conf
  if [ -n "${FORGE_HOST:-}" ]; then
    case "$FORGE_HOST" in github|forgejo) printf '%s\n' "$FORGE_HOST"; return 0 ;;
      *) echo "forge-lib: FORGE_HOST='$FORGE_HOST' is invalid (use github|forgejo)" >&2; return 2 ;; esac
  fi
  local url; url="$(git remote get-url "${FORGE_REMOTE:-origin}" 2>/dev/null || true)"
  case "$url" in
    '')                                          echo github ;;   # no remote -> assume github
    *://github.com/*|*://*@github.com/*|git@github.com:*) echo github ;;  # github.com in the HOST slot only
    *) if [ -n "${FORGE_API_URL:-}" ]; then echo forgejo; else echo github; fi ;;
  esac
}

# forge_repo: print owner/repo on the active host (config wins; else parse the remote URL).
forge_repo() {
  _forge_load_conf
  if [ -n "${FORGE_REPO:-}" ]; then printf '%s\n' "$FORGE_REPO"; return 0; fi
  local url repo; url="$(git remote get-url "${FORGE_REMOTE:-origin}" 2>/dev/null || true)"
  url="${url%.git}"; url="${url%/}"             # strip a trailing .git and a trailing slash
  case "$url" in
    *://*/*) repo="${url#*://*/}" ;;            # scheme://[user@]host[:port]/owner/repo
    *:*/*)   repo="${url#*:}" ;;                # scp form  git@host:owner/repo
    *)       repo="" ;;
  esac
  case "$repo" in
    */*/*) echo "forge-lib: remote path '$repo' is not a plain owner/repo; set FORGE_REPO in .forge.conf" >&2; return 2 ;;
    */*)   printf '%s\n' "$repo" ;;
    *)     echo "forge-lib: cannot parse owner/repo from remote '$url'; set FORGE_REPO in .forge.conf" >&2; return 2 ;;  # 0 or 1 segment
  esac
}

# forge_api_base: REST base URL for the active host.
forge_api_base() {
  case "$(forge_host)" in
    github)  echo "https://api.github.com" ;;
    forgejo) _forge_load_conf; printf '%s/api/v1\n' "${FORGE_API_URL:?forgejo: FORGE_API_URL must be set in .forge.conf}" ;;
    *)       echo "forge-lib: cannot resolve API base; host is not github|forgejo" >&2; return 2 ;;
  esac
}

_forge_token() {
  _forge_load_conf
  local var="${FORGE_TOKEN_ENV:-FORGEJO_TOKEN}"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  # Fallback: ask git's credential helper for this instance (the mise pattern,
  # see references/local-auth.md). Reads the same encrypted store already used
  # for git-over-HTTPS; never prompts (GIT_TERMINAL_PROMPT=0, askpass stubbed:
  # an inherited GIT_ASKPASS, e.g. VS Code's, would otherwise be invoked) and
  # never writes anything back. FORGE_NO_GIT_CREDENTIALS=1 disables the
  # fallback entirely (strict env-only mode, the pre-v7 behavior).
  # The stub is an ABSOLUTE path on purpose: a PATH-resolved name could be
  # hijacked by a planted binary inside this credential-handling flow. If
  # /bin/true is absent (NixOS-likes), the miss degrades to a clean rc!=0
  # with no prompt and no hang (verified), never to a prompt.
  local url proto host cred
  url="${FORGE_API_URL:-}"
  if [ -n "$url" ] && [ "${FORGE_NO_GIT_CREDENTIALS:-0}" != 1 ]; then
    proto="${url%%://*}"; [ "$proto" = "$url" ] && proto=https
    host="${url#*://}"; host="${host%%/*}"; host="${host#*@}"
    cred=$(printf 'protocol=%s\nhost=%s\n\n' "$proto" "$host" \
             | GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true git credential fill 2>/dev/null \
             | sed -n 's/^password=//p' | head -n1)
    if [ -n "$cred" ]; then printf '%s' "$cred"; return 0; fi
  fi
  echo "forgejo: token env '$var' is empty and git's credential helper has no entry for '${host:-unset}'." >&2
  echo "         Mint a scoped token and supply it; see forge-host references/local-auth.md." >&2
  return 2
}

# forge_api <METHOD> <path> [json-body]   path is like  /repos/{owner}/{repo}/issues
# Prints the raw JSON response. FORGE_DRY_RUN=1 -> print the resolved request and return.
# On the forgejo path the HTTP status reaches the caller as an EXIT CODE (issue #78.2): 0 for 2xx,
# 44 for 404, 22 for any other non-2xx, and curl's own code for a transport failure. Not a
# variable: callers read the body with $(...), which runs this in a subshell where an assignment
# would be discarded.
forge_api() {
  local method="$1" path="$2" body="${3-}"
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then
    # to stderr, so it survives callers that redirect the JSON response to /dev/null
    printf '[dry-run] %s %s%s%s\n' "$method" "$(forge_api_base)" "$path" "${body:+  body=$body}" >&2
    return 0
  fi
  case "$(forge_host)" in
    github)
      if [ -n "$body" ]; then printf '%s' "$body" | gh api -X "$method" "${path#/}" --input -
      else gh api -X "$method" "${path#/}"; fi ;;
    forgejo)
      # || return 2: in conditional callers (if out=$(forge_api ...); forge_ci_status)
      # set -e does not fire on the assignment, and without the guard an EMPTY
      # Authorization header would go over the wire and mask the real cause.
      local base tok
      base="$(forge_api_base)" || return 2
      tok="$(_forge_token)"    || return 2
      # NOT `curl -f` (issue #78.2): -f collapses every HTTP >= 400 into exit 22 with no body and
      # no status, so a caller cannot tell 404 (an org with no labels: fine) from 401 or 500 (a
      # real failure). The status is appended on its own line and split off here.
      local out rc
      if [ -n "$body" ]; then
        out="$(curl -sSL -w '\n%{http_code}' -X "$method" -H "Authorization: token $tok" -H 'Content-Type: application/json' -d "$body" "$base$path")"; rc=$?
      else
        out="$(curl -sSL -w '\n%{http_code}' -X "$method" -H "Authorization: token $tok" "$base$path")"; rc=$?
      fi
      [ "$rc" -eq 0 ] || return "$rc"          # transport failure: curl's own code, no status
      local status="${out##*$'\n'}"
      printf '%s' "${out%$'\n'*}"
      # The status is reported through the EXIT CODE, not a variable. Every caller reads the body
      # with $(...), which runs this function in a SUBSHELL, so any variable set here is discarded
      # before the caller can read it. An exit code is the one channel that survives.
      case "$status" in
        2*)  return 0 ;;
        404) return 44 ;;
        *)   echo "forge-lib: HTTP $status from $method $path" >&2; return 22 ;;
      esac ;;
  esac
}

# forge_api_paginate <path>  GET every page of a LIST endpoint and print ONE concatenated
# JSON array, host-aware: github delegates to `gh api --paginate` (which merges pages into one
# array without -q); forgejo loops page/limit itself, appending '?' or '&' as the path needs.
# Forgejo termination is an EMPTY page, deliberately NOT `length < limit`: the server clamps
# `limit` to its admin-set MAX_RESPONSE_ITEMS (stock default 50), so a clamped page satisfies
# `< limit` while pages remain, which would silently reproduce the exact single-page
# truncation this helper exists to fix (issue #62). One extra request per call is the price
# of being clamp-proof. Guards, each an ERROR (return 2), never a silent end-of-list: a
# non-array body (a JSON error object's `length` counts KEYS, which would read as items and
# loop forever), an empty or unparseable body mid-run (a `[ '' -gt 0 ]` would break the loop
# and return rc 0 on a partial list), and a page cap (FORGE_PAGINATE_MAX_PAGES, default 500 =
# 25k items at stock clamp) so a server that ignores `page` spins the cap, not forever.
# Pages accumulate in a TEMP FILE, never a jq --argjson argument: a single execve argument is
# capped at MAX_ARG_STRLEN (~128KiB on Linux), and one real page of template-v4-sized issues
# measures at that ceiling, so argv accumulation hard-fails on exactly the repos pagination
# exists for. File/stdin input has no such limit (and avoids re-parsing prior pages each loop).
forge_api_paginate() {
  _forge_load_conf || true   # ONCE, in this shell: the per-page $(forge_api ...) subshells and
                             # their own $(forge_host) / $(_forge_token) subshells inherit the
                             # memo from here. Loading it deeper would be discarded each time.
  local path="$1" sep page=1 chunk n tmp rc
  case "$path" in *\?*) sep='&' ;; *) sep='?' ;; esac
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then
    forge_api GET "${path}${sep}limit=50&page=1" >/dev/null   # prints the dry-run line
    printf '[]\n'; return 0
  fi
  if [ "$(forge_host)" = github ]; then
    # gh --paginate emits each page as a SEPARATE JSON doc on modern gh (--slurp exists for
    # exactly this); older gh merged arrays into one. jq -s tolerates both shapes: slurp all
    # docs, box any non-array, flatten once.
    gh api --paginate "${path#/}" | jq -sc 'map(if type == "array" then . else [.] end) | add // []'
    return $?
  fi
  local cap="${FORGE_PAGINATE_MAX_PAGES:-500}"
  case "$cap" in ''|*[!0-9]*) cap=500 ;; esac   # a non-numeric override must not void the spin guard
  _forge_tmp_init || return 2
  # mktemp, NOT "paginate.$$": $$ is the PARENT pid inside every subshell, so two concurrent
  # paginations in one process shared a path and each returned the union of both streams, exit 0.
  tmp="$(mktemp "$_FORGE_TMPDIR/paginate.XXXXXX")" || return 2
  while :; do
    chunk="$(forge_api GET "${path}${sep}limit=50&page=${page}")" || { rc=$?; _forge_tmp_done "$tmp"; return "$rc"; }
    n="$(printf '%s' "$chunk" | jq 'if type == "array" then length else -1 end' 2>/dev/null)"
    case "$n" in
      ''|*[!0-9-]*|-1)
        echo "forge-lib: paginate: non-array or empty response from ${path} page ${page}" >&2
        _forge_tmp_done "$tmp"; return 2 ;;
    esac
    [ "$n" -gt 0 ] || break
    printf '%s\n' "$chunk" >> "$tmp"
    page=$((page + 1))
    if [ "$page" -gt "$cap" ]; then
      echo "forge-lib: paginate: exceeded $cap pages on ${path}; server may be ignoring the page param" >&2
      _forge_tmp_done "$tmp"; return 2
    fi
  done
  jq -sc 'add // []' "$tmp"; rc=$?
  _forge_tmp_done "$tmp"
  return $rc
}

# _forge_tmp_init  create the per-process temp DIR once and install ONE cleanup.
# Issue #78.3: the previous `mktemp` files were removed on every return path but not on a signal,
# so a Ctrl-C mid-pagination left one behind per call. A single directory means one cleanup point.
#
# It sets a variable rather than PRINTING a path, because a caller would have to use $( ) to read
# a printed one, and a command substitution runs in a SUBSHELL: the assignment and the trap would
# both be discarded, so every call would create a new directory and none would ever be cleaned.
#
# The EXIT trap is installed ONLY when the caller has none. A sourced library that overwrites its
# caller's trap is a worse bug than a leaked file. Where the caller does have one, the normal
# return paths still remove the file and the SIGNAL case is the caller's to handle; that cannot be
# fixed from inside a library, so it is stated rather than hidden.
_forge_tmp_init() {
  # Check the DIRECTORY, not just the variable: a subshell that finished a paginate may have
  # rmdir'd it, and its `unset` cannot escape the subshell, so the parent can hold a stale path.
  if [ -n "${_FORGE_TMPDIR-}" ] && [ -d "$_FORGE_TMPDIR" ]; then return 0; fi
  _FORGE_TMPDIR="$(mktemp -d)" || return 2
  # Install ONLY when the caller has no EXIT trap. Re-installing the caller's command is worse than
  # standing aside: a subshell that inherits the trap string would then run the CALLER's cleanup at
  # SUBSHELL exit, tearing down the caller's state mid-run. Measured, painfully: appending to the
  # trap made this repo's own suite delete its scratch dir in the middle of a test.
  [ -n "$(trap -p EXIT)" ] || trap 'rm -rf "${_FORGE_TMPDIR-}"' EXIT
  return 0
}

# _forge_tmp_done <file>  drop a temp file and, when it was the last one, the directory too.
# This is what stops the leak on the NORMAL path when the caller already had an EXIT trap and the
# signal trap above was therefore not installed: without it the files went but the directory stayed,
# and this repo's own suite left 18 behind per run. rmdir only succeeds when empty, so a concurrent
# pagination still holding a file is unaffected.
_forge_tmp_done() {
  rm -f "$1"
  [ -n "${_FORGE_TMPDIR-}" ] || return 0
  rmdir "$_FORGE_TMPDIR" 2>/dev/null && unset _FORGE_TMPDIR
  return 0
}


# _forge_resolve_names <listfile> <name...>  resolve names against the label lists (JSON arrays,
# one per line) in <listfile> -> [{name, id|null}]. ONE resolution pass drives BOTH the refusal
# check and the POST body in forge_issue_label, so the two can never drift apart; a divergence
# there is exactly the silent-partial class of #63.
_forge_resolve_names() {
  local listfile="$1"; shift
  printf '%s\n' "$@" | jq -R . | jq -sc --slurpfile lists "$listfile" \
    '($lists | add) as $labels | map(. as $l | {name:$l, id:($labels | map(select(.name==$l) | .id) | first)})'
}

# --- Issue operations (REST shapes match across GitHub + Forgejo/Gitea) ---

# forge_issue_view <n>  -> the full issue JSON (number, title, body, state, labels[].name,
# milestone.title, assignees, and so on: the raw REST object, near-identical on GitHub and Forgejo)
forge_issue_view() { forge_api GET "/repos/$(forge_repo)/issues/$1"; }

# forge_issue_comment <n> <body>
forge_issue_comment() {
  local payload; payload="$(jq -nc --arg b "$2" '{body:$b}')"
  forge_api POST "/repos/$(forge_repo)/issues/$1/comments" "$payload" >/dev/null
}

# forge_issue_close <n>
forge_issue_close() { forge_api PATCH "/repos/$(forge_repo)/issues/$1" '{"state":"closed"}' >/dev/null; }

# forge_issue_list [state]  (default open) -> JSON array of issues, PRs excluded, ALL pages.
# GitHub's /issues includes PRs and is paginated, so the github path filters PRs and paginates;
# Forgejo excludes PRs server-side with type=issues. Both return the same shape (a PR-free array).
forge_issue_list() {
  local repo state; repo="$(forge_repo)" || return 2; state="${1:-open}"
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then
    printf '[dry-run] GET %s/repos/%s/issues?state=%s (issues only, all pages)\n' "$(forge_api_base)" "$repo" "$state" >&2; return 0
  fi
  case "$(forge_host)" in
    # Shared pager on both hosts; its github arm normalises gh's page-doc output to ONE array,
    # so the PR filter runs over a guaranteed single array.
    github)  forge_api_paginate "/repos/$repo/issues?state=$state" | jq 'map(select(.pull_request | not))' ;;
    forgejo) forge_api_paginate "/repos/$repo/issues?state=$state&type=issues" ;;
  esac
}

# forge_issue_create <title> <body>  -> JSON of the created issue (number, html_url, ...)
# Labels are intentionally omitted: GitHub's create takes label NAMES, Forgejo's takes label IDs, so
# add them in a follow-up host-specific step rather than risk a cross-host mismatch here.
forge_issue_create() {
  local repo payload; repo="$(forge_repo)" || return 2
  payload="$(jq -nc --arg t "$1" --arg b "$2" '{title:$t, body:$b}')"
  forge_api POST "/repos/$repo/issues" "$payload"
}

# forge_issue_label <n> <label> [label...]  (add labels BY NAME on either host). GitHub's API takes
# names directly; Forgejo's takes label IDs, so the forgejo path resolves names -> IDs via the
# repo's label list (all pages). An unresolvable name REFUSES the whole call: non-zero exit,
# stderr naming the label(s), nothing written. Refuse-all (not apply-partial) is deliberate
# (issue #63): callers are automation, and a partial apply makes the final state depend on which
# of several names was mistyped; atomic refusal means fix the input and re-run. A repo with no
# labels at all gets its own message, since the operator action differs (create labels vs fix a
# typo). This is the host-aware way to set the labels forge_issue_create intentionally omits.
forge_issue_label() {
  local n="$1"; shift; [ "$#" -gt 0 ] || return 0
  local repo; repo="$(forge_repo)" || return 2
  if [ "${FORGE_DRY_RUN:-0}" = 1 ]; then printf '[dry-run] label issue %s on %s with: %s\n' "$n" "$repo" "$*" >&2; return 0; fi
  case "$(forge_host)" in
    github)
      forge_api POST "/repos/$repo/issues/$n/labels" "$(printf '%s\n' "$@" | jq -R . | jq -sc '{labels: .}')" >/dev/null ;;
    forgejo)
      # Labels can be defined on the REPO or on the owning ORG: the issue-labels endpoint accepts
      # ids from either, but /repos/.../labels lists only the repo's own, so refusing against the
      # repo list alone would wrongly reject valid org labels. The org list is fetched ONLY when a
      # name fails to resolve against the repo list (the common all-repo-labels call costs no org
      # round-trips); the /orgs endpoint 404s for user-owned repos, which reads as an empty set,
      # and any other org-fetch failure is flagged in the error rather than silently narrowing
      # the label universe. Label lists go to jq via --slurpfile (file input), never --argjson
      # (argv-capped; see forge_api_paginate).
      local all org org_failed=0 resolved nmissing missing ids nlabels tmp
      all="$(forge_api_paginate "/repos/$repo/labels")" || return 2
      _forge_tmp_init || return 2
      tmp="$(mktemp "$_FORGE_TMPDIR/labels.XXXXXX")" || return 2
      printf '%s\n' "$all" > "$tmp"
      resolved="$(_forge_resolve_names "$tmp" "$@")"
      if [ "$(printf '%s' "$resolved" | jq '[.[] | select(.id == null)] | length')" -gt 0 ]; then
        # With the status available (#78.2), a 404 is the ordinary "this owner is a user, or the
        # org declares no labels" case and is NOT a failure worth flagging; anything else is.
        # 44 is a 404 (this owner is a user, or the org declares no labels): ordinary, not a
        # failure worth flagging. Anything else narrows the label universe for a reason the
        # operator needs to know about.
        org="$(forge_api_paginate "/orgs/${repo%%/*}/labels" 2>/dev/null)" || {
          [ "$?" -eq 44 ] || org_failed=1; org='[]'; }
        printf '%s\n%s\n' "$all" "$org" > "$tmp"
        resolved="$(_forge_resolve_names "$tmp" "$@")"
      fi
      nlabels="$(jq -s 'add | length' "$tmp")"
      _forge_tmp_done "$tmp"
      # Gate on the COUNT of unresolved entries, not on a joined string: join(" ") of [""] is
      # empty, so a string-emptiness gate lets an empty-string name slip through and POST null.
      nmissing="$(printf '%s' "$resolved" | jq '[.[] | select(.id == null)] | length')"
      if [ "${nmissing:-0}" -gt 0 ]; then
        missing="$(printf '%s' "$resolved" | jq -r '[.[] | select(.id == null) | .name | @json] | join(" ")')"
        if [ "${nlabels:-0}" -eq 0 ]; then
          echo "forge-lib: cannot label issue #$n: the repository and its org have no labels defined (create them first)" >&2
        elif [ "$org_failed" -eq 1 ]; then
          echo "forge-lib: cannot label issue #$n: unresolvable label name(s): $missing (org-level labels could not be listed; if these are org labels, fix org access or define them on the repo)" >&2
        else
          echo "forge-lib: cannot label issue #$n: unresolvable label name(s): $missing" >&2
        fi
        return 2
      fi
      ids="$(printf '%s' "$resolved" | jq -c 'map(.id)')"
      forge_api POST "/repos/$repo/issues/$n/labels" "$(jq -nc --argjson l "$ids" '{labels:$l}')" >/dev/null ;;
  esac
}

# --- Release / tag operations ---

# forge_tag_exists <tag>  -> exit 0 if the tag exists on the forge
forge_tag_exists() { forge_api GET "/repos/$(forge_repo)/tags/$1" >/dev/null 2>&1; }

# forge_release_create <tag> [title] [notes]   (both hosts accept tag_name/name/body)
forge_release_create() {
  local payload; payload="$(jq -nc --arg t "$1" --arg n "${2:-$1}" --arg b "${3-}" '{tag_name:$t,name:$n,body:$b}')"
  forge_api POST "/repos/$(forge_repo)/releases" "$payload" >/dev/null
}

# --- CI status (runner-dependent) ---

# forge_ci_status <branch>  -> success | failure | pending | none | not_configured (github also
# passes raw GH conclusions like cancelled/timed_out/skipped through). `pending` = a run exists but
# has not concluded; `none` = no run; `not_configured` = no CI to check (Forgejo with no statuses,
# e.g. no runner), so callers (ci-health, release) degrade gracefully (e.g. a local `make test`
# gate) instead of hard-failing.
#
# Forgejo: Forgejo Actions writes a COMMIT STATUS per job, so the combined commit-status endpoint
# (`/commits/{sha}/status`) is the simple, correct "is CI green?" check, better than the
# version-split /actions/runs|/actions/tasks API. (On GitHub the combined status does NOT reflect
# Actions (those are Checks), so the github path uses `gh run list`.) We resolve to a SHA because
# the combined status has known quirks on branch/tag refs; total_count == 0 (no statuses) means no
# CI ran -> not_configured, preserving the runner-less fallback.
forge_ci_status() {
  case "$(forge_host)" in
    github)  gh run list --branch "$1" --limit 1 --json status,conclusion \
               -q '.[0] | if . == null then "none" elif .status != "completed" then "pending" else (.conclusion // "none") end' 2>/dev/null || echo none ;;
    forgejo)
      local repo sha cs total state
      repo="$(forge_repo)" || { echo not_configured; return 0; }         # unparseable remote -> can't query
      # --verify so a bad ref prints NOTHING (plain `git rev-parse badref` echoes the arg to stdout
      # too, which would double it via `|| printf`). Falls back to the literal ref if unresolved.
      sha=$(git rev-parse --verify "$1" 2>/dev/null || printf '%s' "$1")
      [ -n "$sha" ] || { echo not_configured; return 0; }                # empty ref arg
      cs=$(forge_api GET "/repos/$repo/commits/$sha/status" 2>/dev/null) || { echo not_configured; return 0; }
      [ -n "$cs" ] || { echo not_configured; return 0; }                 # empty body / dry-run
      total=$(printf '%s' "$cs" | jq -r '.total_count // 0' 2>/dev/null)
      case "$total" in ''|*[!0-9]*) total=0 ;; esac
      [ "$total" -eq 0 ] && { echo not_configured; return 0; }           # no commit statuses -> no CI
      state=$(printf '%s' "$cs" | jq -r '.state // "unknown"' 2>/dev/null)
      case "$state" in
        success)       echo success ;;
        pending)       echo pending ;;
        failure|error) echo failure ;;                                   # error == infra failure
        *)             echo "${state:-unknown}" ;;
      esac ;;
  esac
}

# Executed directly: a diagnostics CLI, or call any forge_* function.
#   forge-lib.sh detect            # print host/repo/api
#   forge-lib.sh forge_issue_close 5
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-detect}" in
    detect) h="$(forge_host)"; printf 'host=%s  repo=%s' "$h" "$(forge_repo)"
            [ "$h" = forgejo ] && printf '  api=%s' "$(forge_api_base)"; printf '  ci=%s\n' "$(forge_ci_status "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)")" ;;
    *)      "$@" ;;
  esac
fi
