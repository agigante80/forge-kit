# Templates mode: the label taxonomy (labels.md, the declaration, sync-labels.sh)

Read when `adapt/SKILL.md` sends you here from the Templates mode. It runs whether or not any
issue template carries a `template-version` marker: `docs/guides/labels.md` has no dependency on
versioned templates, because the gate's check 2 reads it for any project.

**Why.** `check-ticket-mechanics.sh --labels-doc docs/guides/labels.md` takes the project's area set
from the first backticked column of that doc's `### Area labels` table. Without the doc the gate
silently falls back to forge-kit's compiled-in nine.

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

# 1. Validate every name and description (allow-list) before anything is written.
fixed=" bug enhancement feature security infrastructure design documentation testing p0 p1 p2 p3 critical contribution "
seen=" "; n=0
vname() {  # vname <name>: the allow-list, the fixed-name list and the duplicate check
  case "$1" in ""|[!a-z0-9]*|*[!a-z0-9._-]*) die "refused area name: $1" ;; esac
  case "$fixed" in *" $1 "*) die "refused area name: $1 (a type, priority or special label)" ;; esac
  case "$seen" in *" $1 "*) die "refused area name: $1 (duplicate)" ;; esac
  seen="$seen$1 "
}
for a in ${LABEL_AREAS:-}; do vname "$a"; n=$((n + 1)); done
[ "$n" -gt 0 ] || die "LABEL_AREAS is empty: ask the user which areas the project uses"
okdesc() { case "$1" in ""|[!A-Za-z0-9]*|*[!A-Za-z0-9\ ,.\;\(\)/\'_-]*) return 1 ;; esac; }
while IFS= read -r l; do
  [ -n "$l" ] || continue
  case "$seen" in *" ${l%%=*} "*) ;; *) die "refused area description: ${l%%=*} (not in LABEL_AREAS)" ;; esac
  okdesc "${l#*=}" || die "refused area description: ${l%%=*}"
done <<EOF_DESCS
${LABEL_AREA_DESCS:-}
EOF_DESCS

# The first backticked column of an Area labels table: the same read the gate trusts.
area_names() { awk '/^### Area labels/{i=1;next} i&&/^##?#? /{exit} i&&/^[ \t]*\|[ \t]*`/{sub(/^[ \t]*\|[ \t]*`/,"");sub(/[ \t]*`.*/,"");print}' "$1"; }
declares() { grep -qxF -- "- name: $2" "$1"; }
kit_row() { K="| \`$1\` |" awk 'index($0, ENVIRON["K"]) == 1 { print; f = 1; exit } END { exit !f }' "$KDOC"; }
# A description from the user or an existing doc is data: allow-list it, else use a neutral default.
desc_for() {  # desc_for <name> [<doc to read the row from>]
  local d
  d=$(printf '%s\n' "${LABEL_AREA_DESCS:-}" | sed -n "s/^$1=//p" | head -1)
  if [ -z "$d" ] && [ -n "${2:-}" ]; then
    d=$(N="$1" awk -F'|' '$2 ~ "^[ \t]*`" ENVIRON["N"] "`[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3; exit }' "$2")
  fi
  okdesc "$d" || d="Project-specific area"   # a doc-derived description that fails is neutral, not fatal
  printf '%s' "$d"
}
table_rows() {  # kit rows for the kit's areas, a neutral row for the rest
  local a
  for a in "$@"; do kit_row "$a" || printf '| `%s` | %s | - |\n' "$a" "$(desc_for "$a")"; done
}

# Names read from an existing doc are validated before anything is written.
if [ -f "$DOC" ]; then for a in $(area_names "$DOC"); do case "$seen" in *" $a "*) ;; *) vname "$a" ;; esac; done; fi

# 2. docs/guides/labels.md: absent -> written; present -> never clobbered.
if [ ! -f "$DOC" ]; then
  mkdir -p docs/guides || die "cannot create docs/guides"
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
  ' "$KDOC" > "$DOC.tmp" && mv "$DOC.tmp" "$DOC" || die "could not write $DOC"
  echo "labels.md: written to $DOC ($n areas)"
else
  have=$(area_names "$DOC"); missing=""
  for a in $LABEL_AREAS; do printf '%s\n' "$have" | grep -qxF -- "$a" || missing="$missing $a"; done
  missing=${missing# }
  if [ -z "$missing" ]; then
    echo "labels.md: $DOC left unchanged (its Area labels table already lists every confirmed area)"
  elif [ "$merge" = yes ]; then
    if grep -q '^### Area labels' "$DOC"; then
      ROWS="$(table_rows $missing)" awk '
        /^### Area labels/ { a = 1; line[NR] = $0; next }
        a && /^##/ { a = 0 }
        a && /^\|[ \t]*`/ { last = NR }
        { line[NR] = $0 }
        END { for (i = 1; i <= NR; i++) { print line[i]; if (i == last) print ENVIRON["ROWS"] } }
      ' "$DOC" > "$DOC.tmp" || die "could not write $DOC"
    else
      { cat "$DOC"; printf '\n### Area labels\n| Label | Description | Triggers |\n|---|---|---|\n'; table_rows $missing; } > "$DOC.tmp" || die "could not write $DOC"
    fi
    # The rows must have landed in the table the gate reads; else leave the doc untouched.
    got=$(area_names "$DOC.tmp")
    for a in $missing; do printf '%s\n' "$got" | grep -qxF -- "$a" || { rm -f "$DOC.tmp"; die "merge did not land in the Area labels table of $DOC (left unchanged): add $a by hand"; }; done
    mv "$DOC.tmp" "$DOC" || die "could not write $DOC"
    echo "labels.md: merged these Area labels rows into $DOC: $missing"
  elif [ "$merge" = no ]; then
    echo "labels.md: $DOC left unchanged (merge declined)"
  else
    echo "labels.md: $DOC exists and is never overwritten. proposed merge: add to its Area labels table: $missing"
    echo "Apply the proposed merge? Answer yes to continue (re-run with LABELS_MERGE=yes), or no to leave it."
  fi
fi

# 3. The declaration: any of the three present -> untouched, only REPORT; else write it for the host.
decl=""; for d in .github .forgejo .gitea; do [ -f "$d/labels.yml" ] && { decl="$d/labels.yml"; break; }; done
areas=$(area_names "$DOC"); [ -n "$areas" ] || areas="$LABEL_AREAS"
if [ -n "$decl" ]; then
  miss=""; for a in $areas; do declares "$decl" "$a" || miss="$miss $a"; done
  if [ -n "$miss" ]; then echo "labels.yml does not declare:${miss}"
  else echo "labels.yml: $decl declares every area"; fi
else
  mkdir -p "$hdir" || die "cannot create $hdir"
  {
    # The kit's type, priority and critical entries verbatim; never its areas or `contribution`.
    KEEP=" bug enhancement feature security infrastructure design documentation testing P0 P1 P2 P3 critical " awk '
      /^- name: / { p = index(ENVIRON["KEEP"], " " $3 " ") > 0 }
      /^[ \t]*$/ { if (p) print; p = 0; next }
      /^#/ { p = 0 }
      p { print }' "$KYML"
    for a in $areas; do
      if declares "$KYML" "$a"; then
        N="- name: $a" awk '$0 == ENVIRON["N"] { p = 1 } p && (/^[ \t]*$/ || /^#/) { exit } p { print } END { print "" }' "$KYML"
      else
        printf -- '- name: %s\n  color: "ededed"\n  description: %s\n\n' "$a" "$(desc_for "$a" "$DOC")"
      fi
    done
  } > "$hdir/labels.yml.tmp" && mv "$hdir/labels.yml.tmp" "$hdir/labels.yml" || die "could not write $hdir/labels.yml"
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
- **The declaration**: if any of `.github/`, `.forgejo/`, `.gitea/` has a `labels.yml` it is left
  byte-identical, no second one is created, and the block only reports
  `labels.yml does not declare: <areas>`. Otherwise it writes `.github/labels.yml` or
  `.forgejo/labels.yml` (per `FORGE_HOST`) from the library's type, priority and `critical` entries
  plus one entry per area, and never `contribution`.
- **`scripts/sync-labels.sh` and `scripts/forge-lib.sh`**: copied only when absent, together, never
  run. On Forgejo with `forge-lib.sh` newly copied, finish through the Step 3 item 4 `.forge.conf` flow.
- **Refusals** (exit 1, nothing written): a description outside the allow-list or for an unlisted area, a name (confirmed or read from an existing doc) outside `^[a-z0-9][a-z0-9._-]*$`, a duplicate, or
  a type, priority or special label name.

Downstream agreement between the doc and the declaration is verified only by this report, since
`check-label-taxonomy.sh` is forge-kit-only. Show the user the block's output, then confirm:
`✓ labels.md and the label declaration installed; run bash scripts/sync-labels.sh --check`.
