# awkv-count.sh: the two text rules the #259 asset suites hold their shipped scripts to (#405).
# SOURCED by test-check-phases.sh, test-reassess-phases.sh, test-sync-phases.sh, test-roadmap-lib.sh,
# test-sync-labels.sh, test-check-ticket-mechanics.sh, test-check-private-leaks.sh and
# test-check-public-leaks.sh; one definition, so the eight cannot drift apart.
#
# THE ZERO-`awk -v` RULE (awkv_count <file>, prints a count). Drop lines whose first non-blank
# character is `#`, join backslash continuations into one logical line, then count a logical line
# that holds an AWK COMMAND WORD (`awk`, `gawk`, `mawk`, `nawk`, or a `$AWK`-style variable matching
# `\$\{?[A-Za-z_]*AWK\}?`, case-insensitive) AND an option token `-v` or `--assign`
# (`(^|[[:space:]])(-v|--assign)([[:space:]'"=]|[A-Za-z_])`). It catches `-F'|' -v`, a `-v` on an
# `awk \` continuation line, `"$AWK" -v`, `-v'x=1'`, `-vx=1`, `--assign x=1` and `--assign=x=1`.
# ACCEPTED OVER-COUNT: another command's `-v` on the same logical line as an awk
# (`awk '{print}' f; grep -v foo g`) counts 1 and fails loudly; the fix is to split the line.
#
# THE NO-OPERAND RULE (awk_operand_lines <file>, prints `<line>: <text>` rows). A file named by a
# variable is read through a redirect (`awk '...' < "$f"`), never as an operand, because POSIX awk
# reads an operand shaped `name=value` as an assignment. On a line whose first non-blank character
# is not `#`, flag it when (1) its first non-blank characters are `'` or `}'` followed by whitespace
# and `"$` (a multi-line program's closing line), or (2) after an awk command word, skipping an
# `-F` option's quoted argument (`-F'...'` or `-F '...'`), the first single-quoted span is followed
# by whitespace and `"$`. ACCEPTED LIMIT: a program held in a variable (`awk "$PROG" "$f"`) is not
# read.
#
# awkv_checks <label> <file> <scratch-dir> [<pin>]: the shared rows, through the caller's ok/bad.
# The count must be 0 (or at most <pin>, a ratchet), three mutants must each count one more, the
# operand rows must be empty, and a mutant restoring one operand must be flagged.

_awkv_prog='
  function cmdword(s,   t) { t = tolower(s)
    return match(t, /(^|[^a-z0-9_])([gmn]?awk|\$\{?[a-z_]*awk\}?)([^a-z0-9_]|$)/) }'

awkv_count() {
  SQ="'" awk "$_awkv_prog"'
  BEGIN { OPT = "(^|[ \t])(-v|--assign)([ \t\"=" ENVIRON["SQ"] "]|[A-Za-z_])" }
  !cont && /^[ \t]*#/ { next }
  { buf = cont ? buf " " $0 : $0 }
  /\\$/ { sub(/\\$/, "", buf); cont = 1; next }
  { cont = 0; if (cmdword(buf) && buf ~ OPT) n++; buf = "" }
  END { if (cont && cmdword(buf) && buf ~ OPT) n++; print n + 0 }' < "$1"
}

awk_operand_lines() {
  SQ="'" awk "$_awkv_prog"'
  BEGIN { q = ENVIRON["SQ"]; CLOSE = "^[ \t]*}?" q "[ \t]+\"[$]" }
  /^[ \t]*#/ { next }
  $0 ~ CLOSE { print FNR ": " $0; next }
  { line = $0
    if (!cmdword(line)) next
    rest = substr(line, RSTART + RLENGTH - 1)
    while ((i = index(rest, q)) > 0) {
      pre = substr(rest, 1, i - 1); rest = substr(rest, i + 1)
      j = index(rest, q); if (j == 0) next
      span = substr(rest, 1, j - 1); rest = substr(rest, j + 1)
      if (pre ~ /-F[ \t]*$/) continue
      if (rest ~ /^[ \t]+"[$]/) print FNR ": " $0
      next
    }
  }' < "$1"
}

awkv_checks() {
  local label="$1" f="$2" d="$3" pin="${4:-0}" n rows m
  n=$(awkv_count "$f")
  if [ "$pin" = 0 ]; then
    [ "$n" = 0 ] && ok "$label carries no awk -v code line" || bad "$label carries $n awk -v code line(s)"
  else
    [ "$n" -le "$pin" ] && ok "$label's awk -v lines stay at or below the ratchet ($n of $pin)" \
      || bad "$label's awk -v lines rose above the ratchet: $n, pinned at $pin"
  fi
  for m in "x=\$(printf a | awk -F'|' -v x=\"\$MUT\" '{print x}')" \
           "x=\$(printf a | awk \\
    -v x=\"\$MUT\" '{print x}')" \
           "x=\$(printf a | gawk --assign x=\"\$MUT\" '{print x}')"; do
    { cat "$f"; printf '%s\n' "$m"; } > "$d/awkv-mut.sh"
    [ "$(awkv_count "$d/awkv-mut.sh")" = $((n + 1)) ] \
      && ok "MUTANT: one added $(printf '%s' "$m" | head -1 | cut -c1-40) line counts one in $label" \
      || bad "MUTANT: an added -v shape was not counted in $label: $m"
  done
  rows=$(awk_operand_lines "$f")
  [ -z "$rows" ] && ok "$label reads every file through a redirect, never an awk operand (#405)" \
    || bad "$label has an awk file operand a name=value path turns into an assignment: $rows"
  { cat "$f"; printf '%s\n' "x=\$(awk '{print}' \"\$MUT\")"; } > "$d/awkv-mut.sh"
  [ -n "$(awk_operand_lines "$d/awkv-mut.sh")" ] && ok "MUTANT: an added awk file operand is flagged in $label" \
    || bad "MUTANT: an added awk file operand was not flagged in $label"
}
