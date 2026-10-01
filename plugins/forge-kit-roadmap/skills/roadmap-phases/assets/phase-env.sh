#!/usr/bin/env bash
# phase-env-version: 1
# phase-env.sh: what each /phase Bash call must rebuild, because every call is a fresh shell (#407).
# RUN, never sourced. /phase's resolve block runs it once:
#
#   bash "$PE" > "$(git rev-parse --git-path forge-kit-phase-env)"
#
# and every later Bash call that reads CP, SP, FL, RL, DD, RP or a function FL/RL define opens with
#
#   . "$(git rev-parse --git-path forge-kit-phase-env)" || exit 2
#
# What it prints is that env file: one `X=<quoted absolute path>` line per asset, EMPTY when the
# asset cannot be found (a missing asset never fails the whole file; each read is `${X:?}`-guarded,
# so only the subcommand that needs it stops), then the two libraries sourced when present, then a
# final `:`. The `if ...; fi` form and the `:` both keep the file's own status 0 whichever asset is
# empty: a last line `[ -n "$RL" ] && . "$RL"` returns 1 when RL is empty, and every caller's
# `|| exit 2` would fire with nothing on stderr. Sourcing forge-lib.sh also turns on its
# `set -uo pipefail` in each caller.
#
# The search, per asset, in this order: the project's own `scripts/<name>`; a forge-kit checkout's
# `plugins/*/skills/*/assets/<name>`, newer than anything installed; the highest `<name>-version`
# marker under ~/.claude/plugins, the lexically last path breaking a tie. That last search splits at
# the END of each line, so a path holding a colon keeps its version (the `sort -t:` it replaces read
# a colon path as version 0, as #347 found in ticket-gate's).
#
# Exit 2 with one stderr line only when it cannot run at all: outside a git work tree.
# Needs: bash, git, find, grep, sed, sort.
set -u
case "${1:-}" in
  --help|-h) sed -n '2,/^# Needs:/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "phase: not in a git repository" >&2; exit 2; }

resolve() {  # resolve <asset.sh>: an absolute path, or nothing
  local f
  [ -f "$top/scripts/$1" ] && { printf '%s\n' "$top/scripts/$1"; return; }
  for f in "$top"/plugins/*/skills/*/assets/"$1"; do [ -f "$f" ] && { printf '%s\n' "$f"; return; }; done
  find "$HOME/.claude/plugins" -name "$1" -exec grep -m1 -Ho "${1%.sh}-version: [0-9]*" {} + 2>/dev/null \
    | sed "s/:${1%.sh}-version: \([0-9]*\)\$/	\1/" | sort -t'	' -k2,2n -k1,1 | tail -1 | cut -f1
}

for pair in CP=check-phases.sh SP=sync-phases.sh FL=forge-lib.sh RL=roadmap-lib.sh \
            DD=check-doc-drift.sh RP=reassess-phases.sh; do
  printf '%s=%q\n' "${pair%%=*}" "$(resolve "${pair#*=}")"
done
printf '%s\n' 'if [ -n "$FL" ]; then . "$FL"; fi' 'if [ -n "$RL" ]; then . "$RL"; fi' ':'
