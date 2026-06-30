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
  local f k v; f="$(_forge_root)/.forge.conf"
  [ -f "$f" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    v="${v%%#*}"; v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')"
    case "$k" in
      FORGE_HOST|FORGE_API_URL|FORGE_REPO|FORGE_TOKEN_ENV|FORGE_REMOTE)
        [ -n "${!k:-}" ] || printf -v "$k" '%s' "$v"; export "$k" ;;
    esac
  done < "$f"
}

# forge_host — print 'github' or 'forgejo'.
forge_host() {
  _forge_load_conf
  if [ -n "${FORGE_HOST:-}" ]; then printf '%s\n' "$FORGE_HOST"; return 0; fi
  local url; url="$(git remote get-url "${FORGE_REMOTE:-origin}" 2>/dev/null || true)"
  case "$url" in
    *github.com*) echo github ;;
    '')           echo github ;;                                  # no remote -> assume github
    *)            if [ -n "${FORGE_API_URL:-}" ]; then echo forgejo; else echo github; fi ;;
  esac
}

# forge_repo — print owner/repo on the active host (config wins; else parse the remote URL).
forge_repo() {
  _forge_load_conf
  if [ -n "${FORGE_REPO:-}" ]; then printf '%s\n' "$FORGE_REPO"; return 0; fi
  local url; url="$(git remote get-url "${FORGE_REMOTE:-origin}" 2>/dev/null || true)"
  url="${url%.git}"
  case "$url" in
    *://*) printf '%s\n' "${url#*://*/}" ;;   # https://host[:port]/owner/repo  or ssh://git@host:p/owner/repo
    *:*)   printf '%s\n' "${url#*:}" ;;        # scp form  git@host:owner/repo
    *)     printf '%s\n' "$url" ;;
  esac
}

# forge_api_base — REST base URL for the active host.
forge_api_base() {
  case "$(forge_host)" in
    github)  echo "https://api.github.com" ;;
    forgejo) _forge_load_conf; printf '%s/api/v1\n' "${FORGE_API_URL:?forgejo: FORGE_API_URL must be set in .forge.conf}" ;;
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

# forge_issue_list [state]  (default open) -> JSON array of issues (excludes PRs where the API allows)
forge_issue_list() { forge_api GET "/repos/$(forge_repo)/issues?state=${1:-open}&type=issues"; }

# --- Release / tag operations ---

# forge_tag_exists <tag>  -> exit 0 if the tag exists on the forge
forge_tag_exists() { forge_api GET "/repos/$(forge_repo)/tags/$1" >/dev/null 2>&1; }

# forge_release_create <tag> [title] [notes]   (both hosts accept tag_name/name/body)
forge_release_create() {
  local payload; payload="$(jq -nc --arg t "$1" --arg n "${2:-$1}" --arg b "${3-}" '{tag_name:$t,name:$n,body:$b}')"
  forge_api POST "/repos/$(forge_repo)/releases" "$payload" >/dev/null
}

# --- CI status (runner-dependent) ---

# forge_ci_status <branch>  -> success | failure | pending | none | not_configured
# Forgejo returns `not_configured` until a runner exists, so callers (ci-health, release) can
# degrade gracefully (e.g. fall back to a local `make test` gate) instead of hard-failing.
# PHASE 2: implement the Forgejo branch against the Forgejo Actions API once a runner is stood up.
forge_ci_status() {
  case "$(forge_host)" in
    github)  gh run list --branch "$1" --limit 1 --json conclusion -q '.[0].conclusion // "none"' 2>/dev/null || echo none ;;
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
