#!/usr/bin/env bash
# Fail the build when public prose states an undated count of the kit's contents (#595, #572 WP7).
#
#   check-doc-counts.sh [ROOT]
#   exit 0  no undated inventory count
#   exit 1  one or more, each named as file:line: text on stderr
#   exit 2  the guard could not run (no such root, or no file to read)
#
# WHY. A count written by hand is true the day it is written. "thirty closed phases", "seven plugin
# groups", "Eight groups", "the five work templates", "292 plugins", "six collisions" all reached
# the public docs past review and went stale there; the version column of the governance hooks
# README was wrong for four hooks out of six. #96 fixed the same defect class for the component
# inventory by generating it. Prose cannot be generated, so the rule for prose is: delete the count
# (the default, when the sentence works without it), date it, or generate it.
#
# WHAT IT READS. README.md, docs/*.md, docs/guides/*.md and plugins/*/hooks/README.md under ROOT.
# Not docs/plans/, docs/superpowers/ or docs/changelog-detail/: those are dated history, and a
# phase plan's counts were true when it was written. Inside a file it skips fenced code blocks and
# generated regions (a line starting `<!-- name:start -->` up to its `:end -->`), whose numbers
# come from a generator.
#
# WHAT A HIT IS. A number followed, within two words, by an inventory noun. The number is a word
# from "two" upward (never "one", which is almost always "one line", "one file", a definition rather
# than an inventory) or a digit run (`5`, `292`, `1,200`). The digit run must stand alone: `#178`,
# `2.1.310`, `v6` and `2-put` are not numbers here, and neither is a number that ends its clause
# (`75,` or `1.`). A word ending in a comma, period, colon or semicolon ends the look-ahead, so
# "#74 and #75, where component markers" is not read as a count of markers. The look-ahead crosses
# a hard wrap: the last three words of a prose line lead the next one, so "the five\nwork
# templates" is a hit, reported at the number's line. A blank line, heading, table row, fence,
# generated region or exempted line ends the paragraph and carries nothing.
#   nouns after any number:  plugin group phase component agent skill command hook asset template
#                            suite test guard collision label area ticket release (and plurals)
#   nouns after digits only: line word reference (and plurals); "two lines of an anchor" is a rule,
#                            "about 240 lines" is a measurement
#
# WHAT DATES ONE. An ISO date (2026-10-30) anywhere in the same section, from the previous heading
# to the next. A measurement section states when once; it need not repeat the date on every row. A
# tool version alone (2.1.310) does not date a section: example versions such as "a group at 0.1.0"
# are everywhere, and a version says what was measured, not when.
#
# A DELIBERATE EXCEPTION carries `<!-- doc-count: <reason> -->` on the line or the line above. An
# exception with no reason is itself a failure: an allowance nobody can argue with must say why.
#
# ACCEPTED LIMITS. A count spelt out past the word list ("a hundred and four") or a noun outside the
# list passes; the list is the inventory this kit has, and widening it costs false failures on
# definitions such as "two markers". A dated section can hide a stale count written later in it.
# Bash 3.2 and POSIX awk, no package manager.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
[ -d "$ROOT" ] || { echo "check-doc-counts: no such directory: $ROOT" >&2; exit 2; }
CDPATH= cd -- "$ROOT" || { echo "check-doc-counts: cannot enter $ROOT" >&2; exit 2; }

files=()
for f in README.md docs/*.md docs/guides/*.md plugins/*/hooks/README.md; do
  [ -f "$f" ] && files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || { echo "check-doc-counts: no README.md or docs/ markdown under $ROOT" >&2; exit 2; }

out=$(awk '
BEGIN {
  n = split("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred dozen", a, " ")
  for (i = 1; i <= n; i++) numword[a[i]] = 1
  n = split("plugin group phase component agent skill command hook asset template suite test guard collision label area ticket release", a, " ")
  for (i = 1; i <= n; i++) { noun[a[i]] = 1; noun[a[i] "s"] = 1 }
  n = split("line word reference", a, " ")
  for (i = 1; i <= n; i++) { dnoun[a[i]] = 1; dnoun[a[i] "s"] = 1 }
}
function flush(   i) {
  if (!dated) for (i = 1; i <= nh; i++) print hit[i]
  nh = 0; dated = 0
}
function core(t) {  # strip markdown wrapping around a token
  gsub(/^[(*_`\[|"]+/, "", t); gsub(/[)*_`\]|"]+$/, "", t)
  return t
}
FNR == 1 { if (NR > 1) flush(); fence = 0; region = 0; prev = ""; nh = 0; dated = 0; nc = 0 }
{
  line = $0
  if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; prev = line; nc = 0; next }
  if (fence) { prev = line; next }
  if (line ~ /^[ \t]*<!-- *[A-Za-z0-9_-]+:start *-->/) { region = 1; prev = line; nc = 0; next }
  if (region) { if (line ~ /:end *-->/) region = 0; prev = line; next }
  if (line ~ /^#+ /) { flush(); nc = 0 }
  if (line ~ /^[ \t]*(\||$)/) nc = 0
  if (line ~ /[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]/) dated = 1

  exempt = 0
  m = line "\n" prev
  if (m ~ /<!-- *doc-count:/) {
    exempt = 1
    if (line ~ /<!-- *doc-count: *-->/ || (line !~ /<!-- *doc-count:/ && prev ~ /<!-- *doc-count: *-->/)) {
      print FILENAME ":" FNR ": doc-count exception has no reason"
    }
  }
  prev = line
  if (exempt) { nc = 0; next }

  # tok[1..nc] are the last words of the previous prose line (line cfnr), then this line from nc+1.
  for (i = 1; i <= nc; i++) tok[i] = carry[i]
  nl = split(line, ltok, /[ \t]+/)
  nt = nc
  for (i = 1; i <= nl; i++) if (ltok[i] != "") tok[++nt] = ltok[i]
  for (i = 1; i <= nt; i++) {
    # A number in the carried words was already read up to its line end; only a noun on
    # this line can complete it now.
    t = core(tok[i]); lt = tolower(t)
    isdig = (t ~ /^[0-9]+$/ || t ~ /^[0-9][0-9]?[0-9]?(,[0-9][0-9][0-9])+$/)
    if (t ~ /^[0-9]/ && !isdig) continue
    if (!isdig && !(lt in numword)) continue
    text = t
    for (j = i + 1; j <= nt && j <= i + 3; j++) {
      if (tok[j] == "|") break
      w = tolower(core(tok[j])); text = text " " core(tok[j])
      gsub(/[^a-z-]/, "", w)
      if ((w in noun) || (isdig && (w in dnoun))) {
        if (i <= nc && j <= nc) break
        sub(/[,.;:]+$/, "", text)
        hit[++nh] = FILENAME ":" (i <= nc ? cfnr : FNR) ": " text
        i = j
        break
      }
      if (tok[j] ~ /[,.;:]$/) break
    }
  }
  # Carry the last three words of this line. One that ends a clause needs no cut here: the
  # look-ahead above already stops at it.
  nc = 0; cfnr = FNR; k = nt - 2; if (k < 1) k = 1
  for (i = k; i <= nt; i++) carry[++nc] = tok[i]
}
END { flush() }
' "${files[@]}")

if [ -n "$out" ]; then
  echo "check-doc-counts: undated counts in public prose. Delete the count (the default), date it in its" >&2
  echo "section (an ISO date), or generate it; a deliberate exception carries" >&2
  echo "<!-- doc-count: <reason> --> on the line or the line above." >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
echo "check-doc-counts: ${#files[@]} files, no undated count"
exit 0
