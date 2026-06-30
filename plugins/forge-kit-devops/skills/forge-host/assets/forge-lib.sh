#!/usr/bin/env bash
# forge-lib.sh — host-aware forge operations (GitHub | Forgejo). Source it; governance components
# call the forge_* functions instead of `gh` directly, so the same logic works whether a repo lives
# on GitHub or a self-hosted Forgejo. ADDITIVE: a repo with no Forgejo config defaults to GitHub and
# behaves exactly as before.
#
# Design note: both backends use the REST API (GitHub via `gh api`, Forgejo via `curl`), NOT gh's
# porcelain — because Forgejo's API is the Gitea API, whose JSON shapes (issues, releases, comments)
# closely match GitHub's REST. Using REST on both sides keeps the jq parsing in callers identical.
#
# Host detection — first match wins, so automation is DETERMINISTIC (it never "asks"):
#   1. $FORGE_HOST env var                      (explicit override, e.g. in CI)
#   2. a committed .forge.conf at the repo root (see forge.conf.example)
#   3. the git remote URL                       (github.com -> github; otherwise forgejo IFF a
#                                                Forgejo API URL is configured, else github)
#
# Requires: git, jq. GitHub backend uses `gh` (its existing auth); Forgejo backend uses `curl` + a
# token. Set FORGE_DRY_RUN=1 to print would-be API requests instead of sending them.
set -uo pipefail

_forge_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# Load .forge.conf (KEY=value lines) if present. Env vars already set WIN over the file.
_forge_load_conf() {
  local f line k v; f="$(_forge_root)/.forge.conf"
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                                  # tolerate CRLF line endings
    case "$line" in ''|\#*) continue ;; esac              # skip blanks + comments
    case "$line" in *=*) ;; *) continue ;; esac           # skip lines without '='
    k="${line%%=*}"; v="${line#*=}"                        # split on FIRST '=' (values may contain '=')
    k="${k//[[:space:]]/}"                                 # keys never contain spaces — trim fully
    v="${v%%#*}"; v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')"
    case "$k" in
      FORGE_HOST|FORGE_API_URL|FORGE_REPO|FORGE_TOKEN_ENV|FORGE_REMOTE)
        [ -n "${!k:-}" ] || { printf -v "$k" '%s' "$v"; export "$k"; } ;;  # env (if set) wins; else file
    esac
  done < "$f"
}

# forge_host — print 'github' or 'forgejo'.
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

# forge_repo — print owner/repo on the active host (config wins; else parse the remote URL).
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
    */*/*) echo "forge-lib: remote path '$repo' is not a plain owner/repo — set FORGE_REPO in .forge.conf" >&2; return 2 ;;
    */*)   printf '%s\n' "$repo" ;;
    *)     echo "forge-lib: cannot parse owner/repo from remote '$url' — set FORGE_REPO in .forge.conf" >&2; return 2 ;;  # 0 or 1 segment
  esac
}

# forge_api_base — REST base URL for the active host.
forge_api_base() {
  case "$(forge_host)" in
    github)  echo "https://api.github.com" ;;
    forgejo) _forge_load_conf; printf '%s/api/v1\n' "${FORGE_API_URL:?forgejo: FORGE_API_URL must be set in .forge.conf}" ;;
    *)       echo "forge-lib: cannot resolve API base — host is not github|forgejo" >&2; return 2 ;;
  esac
}

_forge_token() {
  _forge_load_conf
  local var="${FORGE_TOKEN_ENV:-FORGEJO_TOKEN}"
  printf '%s' "${!var:?forgejo: token env '$var' is empty — mint one (see references/forgejo.md) and export it}"
}

# forge_api <METHOD> <path> [json-body]   path is like  /repos/{owner}/{repo}/issues
# Prints the raw JSON response. FORGE_DRY_RUN=1 -> print the resolved request and return.
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
      local base tok; base="$(forge_api_base)"; tok="$(_forge_token)"
      if [ -n "$body" ]; then
        curl -fsSL -X "$method" -H "Authorization: token $tok" -H 'Content-Type: application/json' -d "$body" "$base$path"
      else
        curl -fsSL -X "$method" -H "Authorization: token $tok" "$base$path"
      fi ;;
  esac
}

# --- Issue operations (REST shapes match across GitHub + Forgejo/Gitea) ---

# forge_issue_view <n>  -> JSON (fields: number, title, body, state, labels[].name)
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
    # gh merges paginated arrays into ONE array only WITHOUT -q; filter PRs with a single jq pass after.
    github)  gh api --paginate "repos/$repo/issues?state=$state" | jq 'map(select(.pull_request | not))' ;;
    forgejo) forge_api GET "/repos/$repo/issues?state=$state&type=issues" ;;
  esac
}

# forge_issue_create <title> <body>  -> JSON of the created issue (number, html_url, ...)
# Labels are intentionally omitted: GitHub's create takes label NAMES, Forgejo's takes label IDs —
# add them in a follow-up host-specific step rather than risk a cross-host mismatch here.
forge_issue_create() {
  local repo payload; repo="$(forge_repo)" || return 2
  payload="$(jq -nc --arg t "$1" --arg b "$2" '{title:$t, body:$b}')"
  forge_api POST "/repos/$repo/issues" "$payload"
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

# forge_ci_status <branch>  -> pending | none | not_configured | the run's conclusion
# (success | failure | cancelled | timed_out | skipped | ... — github passes the raw GH conclusion
# through). `pending` = a run exists but has not concluded; `none` = no run; `not_configured` =
# Forgejo with no runner, so callers (ci-health, release) degrade gracefully (e.g. a local `make
# test` gate) instead of hard-failing.
# PHASE 2: implement the Forgejo branch against the Forgejo Actions API once a runner is stood up.
forge_ci_status() {
  case "$(forge_host)" in
    github)  gh run list --branch "$1" --limit 1 --json status,conclusion \
               -q '.[0] | if . == null then "none" elif .status != "completed" then "pending" else (.conclusion // "none") end' 2>/dev/null || echo none ;;
    forgejo) echo not_configured ;;
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
