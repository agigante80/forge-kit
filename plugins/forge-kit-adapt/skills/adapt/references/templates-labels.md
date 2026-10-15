# Templates mode: the label taxonomy (labels.md, the declaration, sync-labels.sh)

Read when `adapt/SKILL.md` sends you here from the Templates mode. It runs whether or not any
issue template carries a `template-version` marker: `docs/guides/labels.md` has no dependency on
versioned templates, because the gate's check 2 reads it for any project.

**Why.** `check-ticket-mechanics.sh --labels-doc docs/guides/labels.md` takes the project's area set
from the first backticked column of that doc's `### Area labels` table. Without the doc the gate
falls back to forge-kit's compiled-in nine, says so in its `labels` row, and can only refer a
project's own area to its critic rather than accept it (#425).

**Ask first, then run the block once.** Ask the user which areas the project uses and offer
forge-kit's nine as a pick-list. `components`, `tooling` and `governance` are governance-repo
areas (#188): list them, but do NOT preselect them for a product project. Make no host call (reading
the host's labels needs a token); the confirmed list is the only source. For a name the kit does not
describe, ask for a one-line description. If `docs/guides/labels.md` already exists, say so before
running and ask whether the Area labels table may gain the missing rows (`LABELS_MERGE=yes`) or not
(`no`); leave `LABELS_MERGE` unset to get only the proposed merge.

Set the inputs, then run the block (shell state does not persist between bash calls, so set them in
the same call; `FORGE_HOST` comes from the Step 1 probe):

```bash
# forge-adapt labels install (Templates mode). The agent sets these AFTER asking the user:
#   LABEL_AREAS       space-separated area names the user confirmed (required)
#   FORGE_HOST        github|forgejo, from the Step 1 probe (required)
#   LABELS_MERGE      yes|no, the answer about an EXISTING docs/guides/labels.md (default: unanswered)
#   FORGE_KIT_DIR     the library root (required)
#   LABEL_AREA_DESCS  optional, one "name=description" per line, for areas the kit does not describe
# Report on stdout; refusals on stderr with exit 1; nothing is written until every input is valid.
export LC_ALL=C; set -f
die() { echo "forge-adapt: $*" >&2; exit 1; }
lib="${FORGE_KIT_DIR:?}"; host="${FORGE_HOST:?}"; merge="${LABELS_MERGE:-}"
case "$host" in github) hdir=.github ;; forgejo) hdir=.forgejo ;; *) die "FORGE_HOST must be github or forgejo, got: $host" ;; esac
case "$merge" in yes|no|"") ;; *) die "LABELS_MERGE must be yes or no, got: $merge" ;; esac
KDOC="$lib/docs/guides/labels.md"; KYML="$lib/.github/labels.yml"
KSH="$lib/plugins/forge-kit-devops/skills/forge-host/assets"
for f in "$KDOC" "$KYML" "$KSH/sync-labels.sh" "$KSH/forge-lib.sh"; do
  [ -f "$f" ] || die "library file missing: $f (refresh the library as in S2 and retry)"
done
DOC=docs/guides/labels.md
# Every output is composed into a scratch file BESIDE its real (symlink-resolved) target and renamed
# over it (#466): a symlink survives, the target keeps its mode, a failed write leaves the original
# intact, and no predictable name (a user's own .tmp file) is ever touched. The trap is set before
# the first mktemp and runs on every exit, including die.
scratch=""
trap 'rm -f "$scratch"' EXIT
resolve() {  # resolve <path>: sets RESOLVED to the file a symlink chain ends at (no readlink -f: bash 3.2, BSD)
  local p="$1" hops=0 l d
  while [ -L "$p" ]; do
    hops=$((hops + 1)); [ "$hops" -le 40 ] || die "$1 is a symlink loop: nothing written"
    l=$(readlink "$p") || die "cannot read the symlink $1: nothing written"
    case "$l" in /*) p="$l" ;; *) d=${p%/*}; [ "$d" = "$p" ] && d=.; p="$d/$l" ;; esac
  done
  d=${p%/*}; [ "$d" = "$p" ] && d=.; [ -n "$d" ] || d=/
  [ "$hops" -eq 0 ] || [ -d "$d" ] || die "$1 is a dangling symlink (its target directory does not exist): nothing written"
  RESOLVED="$p"
}
newscratch() {  # newscratch <final target>: sets scratch to a new file beside it, carrying its mode
  local d=${1%/*} b=${1##*/}
  [ "$d" != "$1" ] || d=.; [ -n "$d" ] || d=/
  scratch=$(mktemp "$d/.$b.XXXXXX") || die "cannot create a temporary file beside $1"
  ro=""
  if [ -e "$1" ]; then   # an existing target: its mode (compose with >, which keeps it)
    cp -p "$1" "$scratch" || die "cannot read $1: nothing written"   # unchecked, a failed cat below would wipe it
    [ -w "$scratch" ] || { chmod u+w "$scratch"; ro=1; }   # a read-only target: writable while composing, restored by publish
  else chmod "$(printf '%o' $(( 0666 & ~$(umask) )))" "$scratch"   # a new one: mktemp made 0600, mv would keep it
  fi
}
publish() {  # publish <final target>: rename the scratch file over it, restoring a read-only mode first
  [ -z "$ro" ] || chmod u-w "$scratch"
  mv -f "$scratch" "$1"   # -f: without it mv asks before replacing a read-only file in a terminal
}

# 1. Validate every name and description (allow-list) before anything is written.
fixed=" bug enhancement feature security infrastructure design documentation testing p0 p1 p2 p3 critical contribution "
seen=" "; seenlc=" "; n=0
# seen keeps the ORIGINAL spelling (the description and doc-name checks below match it exactly);
# seenlc is the lowercased copy only the duplicate check reads. Do not fold seen (#465).
vname() {  # vname <name>: the allow-list, the fixed-name list and the duplicate check
  local lc
  case "$1" in ""|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) die "refused area name: $1 (allowed: letters, digits, dot, underscore and dash, starting with a letter or digit)" ;; esac
  lc=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$fixed" in *" $lc "*) die "refused area name: $1 (a type, priority or special label)" ;; esac
  case "$seenlc" in *" $lc "*) die "refused area name: $1 (duplicate)" ;; esac
  seen="$seen$1 "; seenlc="$seenlc$lc "
}
for a in ${LABEL_AREAS:-}; do vname "$a"; n=$((n + 1)); done
[ "$n" -gt 0 ] || die "LABEL_AREAS is empty: ask the user which areas the project uses"
okchars() {  # the allow-list, the ONE copy of the set (descwhy reuses it, so the two cannot drift)
  case "$1" in ""|[!A-Za-z0-9]*|*[!A-Za-z0-9\ ,.\;\(\)/\'_-]*) return 1 ;; esac
}
okdesc() {  # the allow-list, then GitHub's 100-character cap on a label description
  okchars "$1" || return 1
  [ "${#1}" -le 100 ]
}
descwhy() {  # descwhy <desc>: " (why okdesc refused it)"; the first bad byte is quoted, or shown as \xNN unless printable ASCII
  local s="$1" i=1 c v
  [ -n "$s" ] || { printf ' (empty)'; return 0; }
  while [ "$i" -le "${#s}" ]; do
    if okchars "${s:0:i}"; then i=$((i + 1)); continue; fi
    c=${s:i-1:1}; v=$(( $(printf '%d' "'$c") & 255 ))
    if [ "$v" -ge 32 ] && [ "$v" -le 126 ]; then c="'$c'"; else c=$(printf "'\\\\x%02x'" "$v"); fi
    if [ "$i" -eq 1 ]; then printf ' (%s at position 1, must start with a letter or digit)' "$c"
    else printf ' (%s at position %d, outside the allowed set)' "$c" "$i"; fi
    return 0
  done
  printf ' (%d characters, cap is 100)' "${#s}"
}
while IFS= read -r l; do
  [ -n "$l" ] || continue
  case "$seen" in *" ${l%%=*} "*) ;; *) die "refused area description: ${l%%=*} (not in LABEL_AREAS)" ;; esac
  okdesc "${l#*=}" || die "refused area description: ${l%%=*}$(descwhy "${l#*=}")"
done <<EOF_DESCS
${LABEL_AREA_DESCS:-}
EOF_DESCS

# The first backticked column of an Area labels table: the same read the gate trusts.
area_names() { awk '/^### Area labels/{i=1;next} i&&/^##?#? /{exit} i&&/^[ \t]*\|[ \t]*`/{sub(/^[ \t]*\|[ \t]*`/,"");sub(/[ \t]*`.*/,"");print}' "$1"; }
declares() { grep -qxF -- "- name: $2" "$1"; }
# The kit lookups fold case (#472: `API` finds the kit's `api`) but WRITE the confirmed spelling. The
# project's own declaration is still matched byte for byte, since sync-labels.sh looks names up that way.
# A description the user supplied for a name spelled differently from the kit's wins over the kit entry.
kit_ok() { declares "$KYML" "$1" || ! printf '%s\n' "${LABEL_AREA_DESCS:-}" | N="$1" awk 'index($0, ENVIRON["N"] "=") == 1 { f = 1 } END { exit !f }'; }
kit_row() { kit_ok "$1" || return 1; K="$1" awk 'BEGIN { k = tolower(ENVIRON["K"]) } match($0, /^\| `[^`]*` \|/) && tolower(substr($0, 4, RLENGTH - 6)) == k { print "| `" ENVIRON["K"] "` |" substr($0, RLENGTH + 1); f = 1; exit } END { exit !f }' "$KDOC"; }
kit_decl() { kit_ok "$1" || return 1; K="$1" awk 'BEGIN { k = tolower("- name: " ENVIRON["K"]) } tolower($0) == k { print "- name: " ENVIRON["K"]; p = 1; next } p && (/^[ \t]*$/ || /^#/) { exit } p { print } END { if (p) print ""; exit !p }' "$KYML"; }
# A description from the user or an existing doc is data: allow-list it, else use a neutral default.
desc_for() {  # desc_for <name> [<doc to read the row from>]
  local d
  d=$(printf '%s\n' "${LABEL_AREA_DESCS:-}" | N="$1" awk 'index($0, ENVIRON["N"] "=") == 1 { print substr($0, length(ENVIRON["N"]) + 2); exit }')
  if [ -z "$d" ] && [ -n "${2:-}" ]; then
    d=$(N="$1" awk -F'|' '{ f = $2; gsub(/^[ \t]+|[ \t]+$/, "", f) } f == "`" ENVIRON["N"] "`" { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit }' "$2")
  fi
  okdesc "$d" || d="Project-specific area"   # a doc-derived description that fails is neutral, not fatal
  printf '%s' "$d"
}
table_rows() {  # kit rows for the kit's areas, a neutral row for the rest
  local a
  for a in "$@"; do kit_row "$a" || printf '| `%s` | %s | - |\n' "$a" "$(desc_for "$a")"; done
}

# Names read from an existing doc are validated before anything is written.
# Line by line, so a name with a space is one name and vname refuses it, not two valid ones.
if [ -f "$DOC" ]; then while IFS= read -r a; do [ -n "$a" ] || continue; case "$seen" in *" $a "*) ;; *) vname "$a" ;; esac; done <<EOF_NAMES
$(area_names "$DOC")
EOF_NAMES
fi

# Resolve BOTH outputs before anything is written, so a refused link leaves nothing behind.
decl=""; for d in .github .forgejo .gitea; do [ -f "$d/labels.yml" ] && { decl="$d/labels.yml"; break; }; done
resolve "$DOC"; DOCF="$RESOLVED"
if [ -z "$decl" ]; then resolve "$hdir/labels.yml"; DECLF="$RESOLVED"; fi

# 2. docs/guides/labels.md: absent -> written; present -> never clobbered.
if [ ! -f "$DOC" ]; then
  mkdir -p docs/guides || die "cannot create docs/guides"
  newscratch "$DOCF"
  # forge-kit-only paragraphs become the adapt-dropped tombstone; the Area rows become the user's.
  ROWS="$(table_rows ${LABEL_AREAS})" awk '
    function flush() { print "<!-- adapt-dropped: forge-kit-only -->"; print ""; drop = 0 }
    /^<!-- adapt-droppable: forge-kit-only/ { drop = 1; next }
    drop { if ($0 ~ /^[ \t]*$/) flush(); next }
    /^### Area labels/ { print; area = 1; next }
    area && /^\|[ \t]*`/ { if (!done) { print ENVIRON["ROWS"]; done = 1 }; next }
    area && /^##/ { area = 0 }
    { print }
    END { if (drop) flush() }
  ' "$KDOC" > "$scratch" && publish "$DOCF" || die "could not write $DOC"
  echo "labels.md: written to $DOC ($n areas)"
else
  have=$(area_names "$DOC"); missing=""
  for a in $LABEL_AREAS; do printf '%s\n' "$have" | grep -qxF -- "$a" || missing="$missing $a"; done
  missing=${missing# }
  if [ -z "$missing" ]; then
    echo "labels.md: $DOC left unchanged (its Area labels table already lists every confirmed area)"
  elif [ "$merge" = yes ]; then
    newscratch "$DOCF"
    if grep -q '^### Area labels' "$DOC"; then
      ROWS="$(table_rows $missing)" awk '
        /^### Area labels/ { a = 1; line[NR] = $0; next }
        a && /^##/ { a = 0 }
        a && /^\|[ \t]*`/ { last = NR }
        { line[NR] = $0 }
        END { for (i = 1; i <= NR; i++) { print line[i]; if (i == last) print ENVIRON["ROWS"] } }
      ' "$DOC" > "$scratch" || die "could not write $DOC"
    else
      { cat "$DOC"; printf '\n### Area labels\n| Label | Description | Triggers |\n|---|---|---|\n'; table_rows $missing; } > "$scratch" || die "could not write $DOC"
    fi
    # The rows must have landed in the table the gate reads; else leave the doc untouched.
    got=$(area_names "$scratch")
    for a in $missing; do printf '%s\n' "$got" | grep -qxF -- "$a" || die "merge did not land in the Area labels table of $DOC (left unchanged): add $a by hand"; done
    publish "$DOCF" || die "could not write $DOC"
    echo "labels.md: merged these Area labels rows into $DOC: $missing"
  elif [ "$merge" = no ]; then
    echo "labels.md: $DOC left unchanged (merge declined)"
  else
    echo "labels.md: $DOC exists and is never overwritten. proposed merge: add to its Area labels table: $missing"
    echo "Apply the proposed merge? Answer yes to continue (re-run with LABELS_MERGE=yes), or no to leave it."
  fi
fi

# 3. The declaration (found above): any of the three present -> untouched, only REPORT; else write it for the host.
areas=$(area_names "$DOC"); [ -n "$areas" ] || areas="$LABEL_AREAS"
if [ -n "$decl" ]; then
  miss=""; for a in $areas; do declares "$decl" "$a" || miss="$miss $a"; done
  if [ -n "$miss" ]; then echo "labels.yml does not declare:${miss}"
  else echo "labels.yml: $decl declares every area"; fi
else
  mkdir -p "$hdir" || die "cannot create $hdir"
  newscratch "$DECLF"
  {
    # The kit's type, priority and critical entries verbatim; never its areas or `contribution`.
    KEEP=" bug enhancement feature security infrastructure design documentation testing P0 P1 P2 P3 critical " awk '
      /^- name: / { p = index(ENVIRON["KEEP"], " " $3 " ") > 0 }
      /^[ \t]*$/ { if (p) print; p = 0; next }
      /^#/ { p = 0 }
      p { print }' "$KYML"
    for a in $areas; do
      kit_decl "$a" || printf -- '- name: %s\n  color: "ededed"\n  description: %s\n\n' "$a" "$(desc_for "$a" "$DOC")"
    done
  } > "$scratch" && publish "$DECLF" || die "could not write $hdir/labels.yml"
  echo "labels.yml: written to $hdir/labels.yml"
fi

# 4. sync-labels.sh and forge-lib.sh: absent-only, together. Suggested, never run.
mkdir -p scripts || die "cannot create scripts/"
[ -f scripts/sync-labels.sh ] || { cp "$KSH/sync-labels.sh" scripts/sync-labels.sh && chmod +x scripts/sync-labels.sh || die "could not copy scripts/sync-labels.sh"; echo "copied scripts/sync-labels.sh"; }
if [ ! -f scripts/forge-lib.sh ]; then
  cp "$KSH/forge-lib.sh" scripts/forge-lib.sh || die "could not copy scripts/forge-lib.sh"; echo "copied scripts/forge-lib.sh"
  [ "$host" = forgejo ] && echo "Forgejo: forge-lib.sh needs the base URL; follow the Step 3 item 4 .forge.conf flow before the first sync."
fi
echo "Run: bash scripts/sync-labels.sh --check"
```

**What the block guarantees** (each is a tested case in `scripts/test-forge-adapt-templates-labels.sh`):

- **`docs/guides/labels.md`** absent: written from the library copy, its Area table replaced by the
  confirmed areas, and every paragraph marked `adapt-droppable: forge-kit-only` replaced by the
  `adapt-dropped: forge-kit-only` tombstone (the Step 3 rule), so the installed doc makes no claim
  about `check-label-taxonomy.sh`, which only forge-kit has. Present: never overwritten. The
  block proposes the merge, and on an explicit `yes` only adds the Area table (or its missing rows).
  Any other difference from the library copy is the `refresh <name>` discipline: classify, show,
  write only on `yes`.
- **Case (#472)**: the kit's row and declaration are found without regard to case, so a confirmed
  `API` or `Privacy` gets the kit's description and colour (`bfd4f2`, `d4c5f9`) under the CONFIRMED
  spelling, while an unknown name (`Ops`, `Apiary`) stays `Project-specific area` and `ededed`. A
  description you supplied for a differently-spelled name wins over the kit's entry.
- **The declaration**: if any of `.github/`, `.forgejo/`, `.gitea/` has a `labels.yml` it is left
  byte-identical, no second one is created, and the block only reports
  `labels.yml does not declare: <areas>`. Otherwise it writes `.github/labels.yml` or
  `.forgejo/labels.yml` (per `FORGE_HOST`) from the library's type, priority and `critical` entries
  plus one entry per area, and never `contribution`.
- **`scripts/sync-labels.sh` and `scripts/forge-lib.sh`**: copied only when absent, together, never
  run. On Forgejo with `forge-lib.sh` newly copied, finish through the Step 3 item 4 `.forge.conf` flow.
- **Publishing** (all three outputs): each is composed into a `mktemp` file beside its REAL target (a
  symlink is followed with a `readlink` loop, 40 hops, no `readlink -f`) and renamed over it. A
  symlinked `labels.md` stays a symlink and its target gains the content at its own mode; a new file
  gets the umask default (`mktemp` makes 0600, so the block sets the mode); a failed write or merge
  leaves the original byte-identical; no `.tmp` sibling of a project file is read or removed; no
  scratch file survives a run. A `labels.yml` linked to an existing file is still report-only.
- **Read-only target**: a `labels.md` at mode 0444 is merged like any other, and keeps 0444.
- **Link refusals** (exit 1, before anything is created, for both outputs): a dangling link (its
  target directory does not exist) and a link loop, each named by path.
- **Refusals** (exit 1, nothing written): a description outside the allow-list, over 100 characters (GitHub's cap) or for an unlisted area (a description refusal keeps the `refused area description: <area>` prefix and names the cause: the first offending character and its byte position, with a non-printable or non-ASCII byte shown as `\xNN`; a bad first character; the length against the cap; or that it is empty), a name (confirmed or read from an existing doc) outside `^[A-Za-z0-9][A-Za-z0-9._-]*$` (uppercase is allowed; the message names the rule), a duplicate, or
  a type, priority or special label name, the last two compared without regard to case (`API` beside `api`, `P0`, `Bug`).

**After the first `--check`.** An http `FORGE_API_URL` (a LAN Forgejo) is refused until
`FORGE_ALLOW_HTTP=1` reaches the tool shell, and the refusal surfaces only as a failed label list:
offer the `env` block of the untracked `.claude/settings.local.json`, never the committed
`settings.json` (that ships the bypass to every checkout), and say it lets the token cross that
network unencrypted. Labels the check reports as on the host but undeclared are never deleted; offer
to declare each one the project uses, with its live colour and description, so the declaration is
complete.

Downstream agreement between the doc and the declaration is verified only by this report, since
`check-label-taxonomy.sh` is forge-kit-only. Show the user the block's output, then confirm:
`✓ labels.md and the label declaration installed; run bash scripts/sync-labels.sh --check`.
