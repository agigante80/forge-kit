#!/usr/bin/env bash
# size-review-version: 1
# size-review.sh: how much of /full-review a round needs, full or scoped (#278).
#
# /full-review dispatched five phases whatever it was given, so a three-line fix to a round-1
# finding cost the same code, architecture, security and two general-purpose phases as the branch.
# The cost is the NUMBER of agents, not the tier each runs on, so no model choice fixes it. The
# shape of this decision is claude-security's: a small diff runs the proportionate single-reviewer
# shape, and says so in one line before anything is dispatched.
#
# Usage: size-review.sh [--base <ref>] [--sensitive-file <path>] [--prior-finders <step,...>]
#                       [--full] [--unattended]
#
# Prints exactly ONE line, `full: <reason>` or `scoped: <reason>`, and exits 0. Exits 2 with
# NOTHING on stdout when it cannot answer (a --base that does not resolve, a usage error), so a
# caller reading stdout can never mistake an explanation for a decision. The first rule that
# applies decides:
#
#   1. --full                                   full: forced by --full
#   2. --unattended                             full: unattended caller
#   3. no --base                                full: unmeasurable target
#   4. no sensitive-path file                   full: no sensitive-path set declared (<path>)
#   5. a changed path matches a pattern         full: sensitive path <path>
#   6. a numstat count is `-` (binary)          full: unknown line count in <path>
#   7. a prior finder other than 1A             full: prior-round finding from <step>
#   8. more than 5 files, or 300 lines          full: <n> files exceeds 5 / <n> lines exceeds 300
#   9. otherwise                                scoped: <n> files, <m> lines, no sensitive path
#
# Rules 1 and 2 decide WITHOUT touching the base, so `--full` with a bad ref still answers. Rule 4
# is the fail-safe: a project that declares nothing keeps the full review it had. An EMPTY file is
# a declaration that nothing is sensitive, which is a different statement from no file at all.
#
# The range is `git diff --numstat --no-renames <base>...HEAD`. --no-renames is load-bearing: a
# rename is then its old path AND its new one, so moving a hook OUT of a sensitive directory still
# matches on its old side. A pattern is a bash [[ == ]] glob, where `*` CROSSES `/`.
#
# Portable to bash 3.2 (stock macOS): no associative arrays, no mapfile, no ${x,,}.
set -uo pipefail

usage() { echo "size-review: $1" >&2; echo "usage: size-review.sh [--base <ref>] [--sensitive-file <path>] [--prior-finders <step,...>] [--full] [--unattended]" >&2; exit 2; }

base="" base_set=0 sens=".full-review-sensitive" finders="" full=0 unattended=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)           [ $# -ge 2 ] || usage "--base needs a ref"; base=$2; base_set=1; shift 2 ;;
    --sensitive-file) [ $# -ge 2 ] || usage "--sensitive-file needs a path"; sens=$2; shift 2 ;;
    --prior-finders)  [ $# -ge 2 ] || usage "--prior-finders needs a list"; finders=$2; shift 2 ;;
    --full)           full=1; shift ;;
    --unattended)     unattended=1; shift ;;
    *)                usage "unknown argument '$1'" ;;
  esac
done

[ "$full" = 1 ] && { echo "full: forced by --full"; exit 0; }
[ "$unattended" = 1 ] && { echo "full: unattended caller"; exit 0; }
[ "$base_set" = 1 ] || { echo "full: unmeasurable target"; exit 0; }

git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
  || { echo "size-review: --base '$base' does not resolve to a commit" >&2; exit 2; }

[ -f "$sens" ] || { echo "full: no sensitive-path set declared ($sens)"; exit 0; }

patterns=()
while IFS= read -r p || [ -n "$p" ]; do
  p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
  case "$p" in ''|'#'*) continue ;; esac
  patterns+=("$p")
done < "$sens"

# -z: a path with a tab, a newline or a non-ASCII byte arrives verbatim rather than C-quoted.
# Through a file, not a pipe, so a diff that FAILS refuses instead of reading as an empty, scoped
# range, which is the vacuous pass resolve-range-base.sh exists to prevent.
tmp=$(mktemp) || { echo "size-review: mktemp failed" >&2; exit 2; }
trap 'rm -f "$tmp"' EXIT
git diff --numstat --no-renames -z "$base...HEAD" > "$tmp" 2>/dev/null \
  || { echo "size-review: git diff $base...HEAD failed" >&2; exit 2; }
paths=() adds=() dels=()
while IFS= read -r -d '' rec; do
  a=${rec%%$'\t'*}; rest=${rec#*$'\t'}; d=${rest%%$'\t'*}; path=${rest#*$'\t'}
  adds+=("$a"); dels+=("$d"); paths+=("$path")
done < "$tmp"

n=${#paths[@]}
for ((i = 0; i < n; i++)); do
  for p in ${patterns[@]+"${patterns[@]}"}; do
    # shellcheck disable=SC2053  # the right side is a glob on purpose
    [[ ${paths[i]} == $p ]] && { echo "full: sensitive path ${paths[i]}"; exit 0; }
  done
done

lines=0
for ((i = 0; i < n; i++)); do
  if [ "${adds[i]}" = - ] || [ "${dels[i]}" = - ]; then
    echo "full: unknown line count in ${paths[i]}"; exit 0
  fi
  lines=$((lines + adds[i] + dels[i]))
done

IFS=, read -r -a steps <<< "$finders"
for s in ${steps[@]+"${steps[@]}"}; do
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  [ -n "$s" ] && [ "$s" != 1A ] && { echo "full: prior-round finding from $s"; exit 0; }
done

[ "$n" -le 5 ] || { echo "full: $n files exceeds 5"; exit 0; }
[ "$lines" -le 300 ] || { echo "full: $lines lines exceeds 300"; exit 0; }
echo "scoped: $n files, $lines lines, no sensitive path"
