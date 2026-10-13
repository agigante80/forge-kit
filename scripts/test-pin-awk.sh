#!/usr/bin/env bash
# Contract test for pin-awk.sh (#489).
#
# The subject runs as a subprocess against a stub directory that is the WHOLE of PATH: a `sudo`
# stub that runs its arguments, an `update-alternatives` stub that logs its arguments to a file and
# changes nothing, the few core utilities the script needs, and an `awk` symlink to a file named
# `mawk` or `gawk` as the row needs. The host's own awk (gawk on a maintainer machine, mawk on the
# runner once pinned) never decides a row. The PATH-wrapper pattern follows
# test-check-ticket-mechanics.sh (the #485 mawk rows) and test-check-contributor-docs.sh
# (AWK_UNDER_TEST).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="${PIN_AWK_UNDER_TEST:-$ROOT/scripts/pin-awk.sh}"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if grep -qF -- "$1" <<< "$2"; then ok "$3"; else bad "$3 (no '$1' in output)"; fi; }

[ -f "$SRC" ] || { echo "missing script: $SRC"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# make_env <dir> <awk-target: mawk|gawk|none> <with-mawk: yes|no>
# Builds <dir>/bin (the PATH) and <dir>/log (the update-alternatives call log, created empty).
make_env() {
  local d="$1" target="$2" with_mawk="$3" c p
  mkdir -p "$d/bin" "$d/real"
  : > "$d/log"
  for c in readlink basename head; do
    p="$(command -v "$c")" || { echo "missing core utility: $c"; exit 1; }
    ln -s "$p" "$d/bin/$c"
  done
  printf '#!/bin/sh\nexec "$@"\n' > "$d/bin/sudo"
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$d/log" > "$d/bin/update-alternatives"
  printf '#!/bin/sh\necho "fake mawk 1.3.4"\n' > "$d/real/mawk"
  printf '#!/bin/sh\necho "fake GNU Awk 5.2.1"\n' > "$d/real/gawk"
  chmod +x "$d/bin/sudo" "$d/bin/update-alternatives" "$d/real/mawk" "$d/real/gawk"
  [ "$with_mawk" = yes ] && ln -s "$d/real/mawk" "$d/bin/mawk"
  [ "$target" != none ] && ln -s "$d/real/$target" "$d/bin/awk"
  return 0
}

# run <dir> [args...]: runs the subject with <dir>/bin as the whole PATH; sets OUT and RC.
run() {
  local d="$1"; shift
  OUT="$(PATH="$d/bin" "$BASH_BIN" "$SRC" "$@" 2>&1)"; RC=$?
}

echo "pin-awk.sh contract"

# 1. Positive: mawk present, awk resolves to a file named mawk.
E="$T/e1"; make_env "$E" mawk yes; run "$E"
expect "mawk present, awk is mawk: exit 0" 0 "$RC"
contains "$E/real/mawk" "$OUT" "mawk present, awk is mawk: stdout names the resolved path"
expect "mawk present, awk is mawk: update-alternatives sets awk to the mawk path" \
  "--set awk $E/bin/mawk" "$(cat "$E/log")"

# 2. Positive: --assert-only with awk resolving to mawk never calls update-alternatives.
E="$T/e2"; make_env "$E" mawk yes; run "$E" --assert-only
expect "--assert-only, awk is mawk: exit 0" 0 "$RC"
contains "$E/real/mawk" "$OUT" "--assert-only, awk is mawk: stdout names the resolved path"
expect "--assert-only, awk is mawk: update-alternatives log is empty" "" "$(cat "$E/log")"

# 3. Negative: mawk present but awk still resolves to gawk after the pin.
E="$T/e3"; make_env "$E" gawk yes; run "$E"
expect "awk still gawk after the pin: exit 1" 1 "$RC"
contains "::error::awk resolves to" "$OUT" "awk still gawk after the pin: names the error"
contains "$E/real/gawk, expected mawk" "$OUT" "awk still gawk after the pin: names the gawk path"

# 4. Negative: no mawk on PATH at all.
E="$T/e4"; make_env "$E" gawk no; run "$E"
expect "no mawk: exit 1" 1 "$RC"
contains "::error::mawk is not installed" "$OUT" "no mawk: names the cause"
expect "no mawk: update-alternatives is never called" "" "$(cat "$E/log")"

# 5. Negative: --assert-only with awk resolving to gawk.
E="$T/e5"; make_env "$E" gawk yes; run "$E" --assert-only
expect "--assert-only, awk is gawk: exit 1" 1 "$RC"
contains "::error::awk resolves to $E/real/gawk, expected mawk" "$OUT" "--assert-only, awk is gawk: names the error"
expect "--assert-only, awk is gawk: update-alternatives log is empty" "" "$(cat "$E/log")"

# 6. Edge: the comparison is the exact basename, so a file merely ending in mawk does not pass.
E="$T/e6"; make_env "$E" none yes
printf '#!/bin/sh\n:\n' > "$E/real/notmawk"; chmod +x "$E/real/notmawk"; ln -s "$E/real/notmawk" "$E/bin/awk"
run "$E" --assert-only
expect "awk resolves to a file named notmawk: exit 1" 1 "$RC"

# 7. Edge: an unknown argument is refused, never read as the default pin.
E="$T/e7"; make_env "$E" mawk yes; run "$E" --bogus
expect "unknown argument: exit 2" 2 "$RC"
expect "unknown argument: update-alternatives is never called" "" "$(cat "$E/log")"

# 8. Mutant: a copy whose assertion always exits 0 must fail the two gawk rows, so this suite
# can fail. Skipped when the suite is itself running against a substituted subject.
if [ -z "${PIN_AWK_UNDER_TEST:-}" ]; then
  M="$T/mutant.sh"
  sed 's/ != mawk \]/ = __never__ ]/' "$SRC" > "$M"
  if grep -qF '= __never__ ]' "$M"; then
    MOUT="$(PIN_AWK_UNDER_TEST="$M" "$BASH_BIN" "$0" 2>&1)"
    contains "FAIL: awk still gawk after the pin: exit 1" "$MOUT" "mutant (assertion always exits 0) is killed by the pin gawk row"
    contains "FAIL: --assert-only, awk is gawk: exit 1" "$MOUT" "mutant (assertion always exits 0) is killed by the --assert-only gawk row"
  else
    bad "mutant: the sed did not produce an always-exit-0 assertion"
  fi
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
