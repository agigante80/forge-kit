#!/usr/bin/env bash
# Contract test for the labels install step of forge-adapt's Templates mode (#214).
#
# WHY THIS TESTS PROSE. forge-adapt is a prose skill and cannot run in isolation. The labels step
# is an executable decision inside it (which files it writes, which it must never touch, which
# names it refuses), so its ONE bash block is EXTRACTED from the shipped reference and run, the
# test-forge-adapt-host.sh precedent. This suite reads references/templates-labels.md where that one
# reads SKILL.md, because the step lives in a reference to keep adapt inside its word ratchet.
#
# Every fixture runs under `env -i` with an empty HOME. The yes/no answers are agent prose, so the
# block takes them as environment variables (LABEL_AREAS, FORGE_HOST, LABELS_MERGE, FORGE_KIT_DIR).
# Stub `gh` and `curl` log any call, which is how "suggested, never run" is made able to fail.
#
# EVERY MUTANT AT THE BOTTOM is a sed on the extracted block that breaks one invariant; the suite
# fails unless the scenario guarding that invariant notices. ADAPT_REF overrides the file under test.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
REF="${ADAPT_REF:-$ROOT/plugins/forge-kit-adapt/skills/adapt/references/templates-labels.md}"
SKILL="$ROOT/plugins/forge-kit-adapt/skills/adapt/SKILL.md"
MECH="$ROOT/plugins/forge-kit-governance/skills/ticket-gate-reference/assets/check-ticket-mechanics.sh"
TPL="$ROOT/.github/ISSUE_TEMPLATE/feature.yml"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
QUIET=0; SCFAIL=0
# ck <label> <expected> <actual>: reports in normal mode, only records a miss in mutant mode.
ck() {
  if [ "$QUIET" = 1 ]; then [ "$2" = "$3" ] || SCFAIL=1; return; fi
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
has()  { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }  # has <needle> <haystack>

[ -f "$REF" ] || { echo "missing reference: $REF"; exit 1; }
for f in "$MECH" "$TPL" "$ROOT/docs/guides/labels.md" "$ROOT/.github/labels.yml"; do
  [ -f "$f" ] || { echo "missing: $f"; exit 1; }
done

# The one bash fence of the reference.
BLOCK=$(awk '/^```bash/{p=1;next} /^```/{if(p)exit} p' "$REF")
[ -n "$BLOCK" ] || { echo "could not extract the labels block from $REF"; exit 1; }
[ "$(grep -c '^```bash' "$REF")" = 1 ] || { echo "the reference must carry exactly one bash fence"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/stub" "$T/empty"; echo "ticket body" > "$T/body.md"
for c in gh curl; do printf '#!/bin/sh\necho "%s $*" >> "%s/stub.log"\nexit 1\n' "$c" "$T" > "$T/stub/$c"; chmod +x "$T/stub/$c"; done
N=0
proj() { N=$((N + 1)); P="$T/p$N"; mkdir -p "$P"; }   # sets P to a fresh empty project
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
out=""; err=""; rc=0
# run [VAR=value ...]: the block in $P under a clean env.
run() {
  out=$(cd "$P" && env -i PATH="$T/stub:$PATH" HOME="$T/home" FORGE_KIT_DIR="${KIT:-$ROOT}" "$@" bash -c "$BLOCK" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
}
names() { awk '/^### Area labels/{i=1;next} i&&/^##?#? /{exit} i&&/^[ \t]*\|[ \t]*`/{sub(/^[ \t]*\|[ \t]*`/,"");sub(/[ \t]*`.*/,"");printf "%s ", $0}' "$1" | sed 's/ $//'; }
# mech <labels> <doc>: the gate's own labels row, "<status>\t<evidence>".
mech() { bash "$MECH" --body "$T/body.md" --template "$TPL" --tpl-version 6 --current-tpl-version 6 --labels "$1" --labels-doc "$2" 2>/dev/null | awk -F'\t' '$1=="labels"{print $2 "\t" $3}'; }
files() { (cd "$P" && find . -mindepth 1 -type f | sort | tr '\n' ' '); }

sc_absent() {  # labels.md absent: written, read by the gate, true downstream
  proj; run LABEL_AREAS="api web billing" FORGE_HOST=github
  ck "absent: exit 0" 0 "$rc"
  ck "absent: the Area table is exactly the confirmed areas" "api web billing" "$(names "$P/docs/guides/labels.md")"
  o=$(mech "billing,enhancement" "$P/docs/guides/labels.md"); ck "absent: a billing,enhancement ticket passes the gate's label check" pass "${o%%	*}"
  o=$(mech "ghost,enhancement" "$P/docs/guides/labels.md")
  ck "absent: an area outside the table fails" fail "${o%%	*}"
  ck "absent: the fail evidence lists the project's areas" yes "$(has "api, web, billing" "$o")"
  ck "absent: and not the compiled-in privacy" no "$(has privacy "$o")"
  d=$(cat "$P/docs/guides/labels.md")
  ck "downstream: the installed doc makes no claim about check-label-taxonomy" no "$(has check-label-taxonomy "$d")"
  ck "downstream: nor about the governance-repo history (#188)" no "$(has '#188' "$d")"
  ck "downstream: the tombstone is left" yes "$(has 'adapt-dropped: forge-kit-only' "$d")"
  ck "downstream: no live droppable marker survives" no "$(has 'adapt-droppable' "$d")"
  ck "downstream: the true guidance next to a dropped clause survives" yes "$(has 'add a row to that table' "$d")"
  ck "downstream: the my-domain yaml example survives" yes "$(has 'name: my-domain' "$d")"
  ck "downstream: no kit issue number (#104) survives" no "$(has '#104' "$d")"
  ck "absent: the github declaration is written" yes "$([ -f "$P/.github/labels.yml" ] && echo yes || echo no)"
  ck "absent: and no .forgejo/" no "$([ -e "$P/.forgejo" ] && echo yes || echo no)"
}
sc_refuse() {  # every refusal exits 1 naming the name, and leaves nothing behind
  local bad_in
  for bad_in in 'api bad|name' 'api Web' 'a:b' '-x' 'api api' 'bug' 'p0' 'contribution' 'a`b' '..'; do
    proj; run LABEL_AREAS="$bad_in" FORGE_HOST=github
    ck "refuse [$bad_in]: exit 1" 1 "$rc"
    ck "refuse [$bad_in]: stderr says refused area name" yes "$(has 'refused area name' "$err")"
    ck "refuse [$bad_in]: nothing written" "" "$(files)"
  done
  proj; run LABEL_AREAS="api bad|name" FORGE_HOST=github
  ck "refuse: the message names the offender" yes "$(has 'refused area name: bad|name' "$err")"
  proj; run LABEL_AREAS="" FORGE_HOST=github; ck "refuse: an empty area list" 1 "$rc"; ck "refuse: empty list writes nothing" "" "$(files)"
  proj; run LABEL_AREAS="api" FORGE_HOST=bogus; ck "refuse: an unknown host" 1 "$rc"; ck "refuse: unknown host writes nothing" "" "$(files)"
  proj; run LABEL_AREAS="api"; ck "refuse: FORGE_HOST unset" yes "$([ "$rc" != 0 ] && echo yes || echo no)"; ck "refuse: unset host writes nothing" "" "$(files)"
  proj; run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=maybe; ck "refuse: LABELS_MERGE not yes or no" 1 "$rc"
  proj; KIT="$T/empty" run LABEL_AREAS="api" FORGE_HOST=github; ck "refuse: a stale library" 1 "$rc"
  ck "refuse: stale library writes nothing" "" "$(files)"; ck "refuse: stale library names the missing file" yes "$(has 'library file missing' "$err")"
}
mk_old_doc() {  # an existing doc that differs from the kit's, with a one-row table
  mkdir -p "$P/docs/guides"
  printf '# Our labels\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | Our API |\n\nkeep this prose\n' > "$P/docs/guides/labels.md"
}
sc_present() {  # an existing doc is never clobbered; the merge needs an explicit yes
  proj; mk_old_doc; S=$(sha "$P/docs/guides/labels.md"); run LABEL_AREAS="api web" FORGE_HOST=github
  ck "present: exit 0" 0 "$rc"
  ck "present: sha256 unchanged (merge unanswered)" "$S" "$(sha "$P/docs/guides/labels.md")"
  ck "present: the proposed merge is printed" yes "$(has 'proposed merge' "$out")"
  ck "present: with the question for yes" yes "$(has 'LABELS_MERGE=yes' "$out")"
  ck "present: no sibling doc created" "./labels.md" "$(cd "$P/docs/guides" && find . -type f | sort | tr '\n' ' ' | sed 's/ $//')"
  proj; mk_old_doc; S=$(sha "$P/docs/guides/labels.md"); run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=no
  ck "present+no: exit 0" 0 "$rc"; ck "present+no: sha256 unchanged" "$S" "$(sha "$P/docs/guides/labels.md")"
  proj; mk_old_doc; run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=yes
  ck "present+yes: the missing row is added to the table" "api web" "$(names "$P/docs/guides/labels.md")"
  ck "present+yes: the prose is preserved" yes "$(has 'keep this prose' "$(cat "$P/docs/guides/labels.md")")"
  ck "present+yes: the existing row is preserved" yes "$(has 'Our API' "$(cat "$P/docs/guides/labels.md")")"
  # no table at all
  proj; mkdir -p "$P/docs/guides"; printf '# Labels\n\njust prose\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=no
  ck "no-table+no: byte-identical" "$S" "$(sha "$P/docs/guides/labels.md")"
  o=$(mech "api,bug" "$P/docs/guides/labels.md"); ck "no-table+no: the gate still reports referred" referred "${o%%	*}"
  proj; mkdir -p "$P/docs/guides"; printf '# Labels\n\njust prose\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=yes
  ck "no-table+yes: the table is added" "api" "$(names "$P/docs/guides/labels.md")"
  ck "no-table+yes: the prose is preserved" yes "$(has 'just prose' "$(cat "$P/docs/guides/labels.md")")"
  o=$(mech "api,bug" "$P/docs/guides/labels.md"); ck "no-table+yes: the gate now passes" pass "${o%%	*}"
}
sc_decl() {  # the declaration: host-aware, never rewritten, never shadowed, reported on disagreement
  proj; run LABEL_AREAS="api web" FORGE_HOST=forgejo
  ck "forgejo: .forgejo/labels.yml written" yes "$([ -f "$P/.forgejo/labels.yml" ] && echo yes || echo no)"
  ck "forgejo: .github/labels.yml not written" no "$([ -e "$P/.github/labels.yml" ] && echo yes || echo no)"
  y=$(cat "$P/.forgejo/labels.yml")
  ck "forgejo: declares api" yes "$(has '- name: api' "$y")"; ck "forgejo: declares web" yes "$(has '- name: web' "$y")"
  ck "forgejo: carries the type entries" yes "$(has '- name: bug' "$y")"; ck "forgejo: carries the priority entries" yes "$(has '- name: P0' "$y")"
  ck "forgejo: carries critical" yes "$(has '- name: critical' "$y")"
  ck "forgejo: never declares contribution" no "$(has 'contribution' "$y")"
  ck "forgejo: never declares an unconfirmed kit area" no "$(has '- name: privacy' "$y")"
  proj; run LABEL_AREAS="api" FORGE_HOST=github
  ck "github: .github/labels.yml written, no .forgejo" "yes no" "$([ -f "$P/.github/labels.yml" ] && echo -n yes || echo -n no) $([ -e "$P/.forgejo" ] && echo yes || echo no)"
  proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=Operations and on-call'
  ck "unknown area: the user's description is used" yes "$(has 'description: Operations and on-call' "$(cat "$P/.github/labels.yml")")"
  proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=bad: "quoted" # x'
  ck "bad description: exit 1" 1 "$rc"
  ck "bad description: refused area description: ops" yes "$(has 'refused area description: ops' "$err")"
  ck "bad description: nothing written" "" "$(files)"
  proj; run LABEL_AREAS="api" FORGE_HOST=github LABEL_AREA_DESCS=$'ghost=Not an area'
  ck "description for an unlisted area: exit 1" 1 "$rc"
  ck "description for an unlisted area: names it" yes "$(has 'refused area description: ghost' "$err")"
  ck "description for an unlisted area: nothing written" "" "$(files)"
  # a name read from an existing doc is validated too
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `Bad:Name` | x |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=no
  ck "doc-derived bad name: exit 1" 1 "$rc"
  ck "doc-derived bad name: refused area name: Bad:Name" yes "$(has 'refused area name: Bad:Name' "$err")"
  ck "doc-derived bad name: no declaration written" no "$([ -e "$P/.github/labels.yml" ] && echo yes || echo no)"
  # an existing declaration in any directory wins, byte for byte
  local where
  for where in .github .gitea; do
    proj; mkdir -p "$P/$where"; printf -- '- name: api\n  color: "bfd4f2"\n  description: API\n' > "$P/$where/labels.yml"; S=$(sha "$P/$where/labels.yml")
    run LABEL_AREAS="api billing" FORGE_HOST=forgejo
    ck "existing $where declaration: sha256 unchanged" "$S" "$(sha "$P/$where/labels.yml")"
    ck "existing $where declaration: no .forgejo/labels.yml created" no "$([ -e "$P/.forgejo/labels.yml" ] && echo yes || echo no)"
    ck "existing $where declaration: disagreement reported" yes "$(has 'labels.yml does not declare: billing' "$out")"
    ck "existing $where declaration: labels.md still lists billing" "api billing" "$(names "$P/docs/guides/labels.md")"
  done
  proj; mkdir -p "$P/.github"; printf -- '- name: api\n  color: "bfd4f2"\n  description: API\n' > "$P/.github/labels.yml"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "agreeing declaration: reported as agreeing" yes "$(has 'declares every area' "$out")"
  # declaration generated from an existing doc's table
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | Our API |\n| `ops` | Operations desk |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github
  y=$(cat "$P/.github/labels.yml")
  ck "from-doc: declares ops, which only the doc lists" yes "$(has '- name: ops' "$y")"
  ck "from-doc: ops takes the doc's description" yes "$(has 'description: Operations desk' "$y")"
  ck "from-doc: the doc is unchanged" "$S" "$(sha "$P/docs/guides/labels.md")"
  # every table name is declared (containment)
  proj; run LABEL_AREAS="api web mobile" FORGE_HOST=github
  m=""; for a in $(names "$P/docs/guides/labels.md"); do grep -qxF -- "- name: $a" "$P/.github/labels.yml" || m="$m $a"; done
  ck "containment: every area in the table is declared" "" "$m"
}
sc_sync() {  # sync-labels.sh and forge-lib.sh: absent-only, together, never run
  : > "$T/stub.log"
  proj; run LABEL_AREAS="api" FORGE_HOST=github
  ck "sync: both land" "yes yes" "$([ -f "$P/scripts/sync-labels.sh" ] && echo -n yes || echo -n no) $([ -f "$P/scripts/forge-lib.sh" ] && echo -n yes || echo -n no)"
  A="$ROOT/plugins/forge-kit-devops/skills/forge-host/assets"
  ck "sync: sync-labels.sh is the library copy" "$(sha "$A/sync-labels.sh")" "$(sha "$P/scripts/sync-labels.sh")"
  ck "sync: forge-lib.sh is the library copy" "$(sha "$A/forge-lib.sh")" "$(sha "$P/scripts/forge-lib.sh")"
  ck "sync: the run is printed" yes "$(has 'Run: bash scripts/sync-labels.sh --check' "$out")"
  ck "sync: it was not run (no sync-labels output)" no "$(has 'sync-labels:' "$out$err")"
  ck "sync: no gh or curl call" "" "$(cat "$T/stub.log" 2>/dev/null)"
  ck "sync: github host prints no Forgejo pointer" no "$(has 'Forgejo:' "$out")"
  proj; run LABEL_AREAS="api" FORGE_HOST=forgejo
  ck "sync: a Forgejo host with a new forge-lib.sh points at the .forge.conf flow" yes "$(has '.forge.conf' "$out")"
  # present sync-labels.sh, absent forge-lib.sh: never one alone
  proj; mkdir -p "$P/scripts"; printf '#!/bin/sh\n# mine\n' > "$P/scripts/sync-labels.sh"; Z=$(sha "$P/scripts/sync-labels.sh")
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "sync: a present sync-labels.sh is untouched" "$Z" "$(sha "$P/scripts/sync-labels.sh")"
  ck "sync: forge-lib.sh is added beside it" yes "$([ -f "$P/scripts/forge-lib.sh" ] && echo yes || echo no)"
  # both present at another version
  proj; mkdir -p "$P/scripts"; echo '# a' > "$P/scripts/sync-labels.sh"; echo '# b' > "$P/scripts/forge-lib.sh"
  Z=$(sha "$P/scripts/sync-labels.sh"); W=$(sha "$P/scripts/forge-lib.sh"); run LABEL_AREAS="api" FORGE_HOST=github
  ck "sync: both present, sync-labels.sh unchanged" "$Z" "$(sha "$P/scripts/sync-labels.sh")"
  ck "sync: both present, forge-lib.sh unchanged" "$W" "$(sha "$P/scripts/forge-lib.sh")"
}
sc_round1() {  # review round 1: the merge stays in the Area table, writes fail loudly, nothing is written early
  local c
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | Our API |\n\n### Priority labels\n| Label | Description |\n|---|---|\n| `P0` | Urgent |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="api ops" FORGE_HOST=github LABELS_MERGE=yes
  ck "merge: ops lands in the Area table, not the Priority table" "api ops" "$(names "$P/docs/guides/labels.md")"
  ck "merge: the Priority table is untouched" 1 "$(awk '/^### Priority/{i=1} i&&/^\| `/{n++} END{print n+0}' "$P/docs/guides/labels.md")"
  # a table whose rows are not backticked cannot take the merge: refused, doc untouched
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| api | Our API |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=yes
  ck "unlandable merge: exit 1" 1 "$rc"
  ck "unlandable merge: names the problem" yes "$(has 'merge did not land' "$err")"
  ck "unlandable merge: doc unchanged" "$S" "$(sha "$P/docs/guides/labels.md")"
  ck "unlandable merge: no stray temp file" "./docs/guides/labels.md " "$(files)"
  # a name read from an existing doc is refused before the doc is merged
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `Frontend` | UI |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=yes
  ck "early validation: exit 1" 1 "$rc"
  ck "early validation: the doc was not merged" "$S" "$(sha "$P/docs/guides/labels.md")"
  ck "early validation: nothing else written" "./docs/guides/labels.md " "$(files)"
  # a failed write is not reported as success
  proj; : > "$P/scripts"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "failed write: exit 1" 1 "$rc"
  ck "failed write: no copied line" no "$(has 'copied scripts' "$out")"
  if [ "$(id -u)" != 0 ]; then   # a read-only directory does not stop root
    proj; mkdir -p "$P/docs/guides"; chmod 555 "$P/docs/guides"
    run LABEL_AREAS="api" FORGE_HOST=github
    chmod 755 "$P/docs/guides"
    ck "unwritable docs/guides: exit 1" 1 "$rc"
    ck "unwritable docs/guides: no written line" no "$(has 'labels.md: written' "$out")"
    proj; mkdir -p "$P/scripts"; cp "$ROOT/plugins/forge-kit-devops/skills/forge-host/assets/sync-labels.sh" "$P/scripts/"; chmod 555 "$P/scripts"
    run LABEL_AREAS="api" FORGE_HOST=github
    chmod 755 "$P/scripts"
    ck "unwritable scripts/: exit 1" 1 "$rc"
    ck "unwritable scripts/: no copied forge-lib line" no "$(has 'copied scripts/forge-lib.sh' "$out")"
  fi
  # each excluded description character is refused on its own
  for c in ':' '#' '"' '|' '`' '$' '%'; do
    proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=Run${c}ning"
    ck "description char [$c]: refused" 1 "$rc"
  done
  proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=-leading"
  ck "description leading dash: refused" 1 "$rc"
  # a name that is a prefix of a declared one is not declared by it
  proj; mkdir -p "$P/.github"; printf -- '- name: api\n  color: "bfd4f2"\n  description: API\n' > "$P/.github/labels.yml"
  run LABEL_AREAS="ap" FORGE_HOST=github
  ck "prefix name: reported as not declared" yes "$(has 'labels.yml does not declare: ap' "$out")"
  # every special name is refused
  for c in critical testing documentation design infrastructure security feature enhancement p1 p2 p3; do
    proj; run LABEL_AREAS="$c" FORGE_HOST=github; ck "fixed name [$c]: refused" 1 "$rc"
  done
  # the installed doc keeps the Priority table, and the copied script is executable
  proj; run LABEL_AREAS="api" FORGE_HOST=github
  ck "absent: the Priority table survives" yes "$(has '### Priority' "$(cat "$P/docs/guides/labels.md")")"
  ck "absent: and keeps its P0 row" yes "$(has '| `P0` |' "$(cat "$P/docs/guides/labels.md")")"
  ck "sync: sync-labels.sh is executable" yes "$([ -x "$P/scripts/sync-labels.sh" ] && echo yes || echo no)"
}
sc_round2() {  # #424: literal description lookup, the 100-character cap, a spaced doc name
  local d100 d101 y
  d100=$(printf 'x%.0s' $(seq 1 100)); d101="${d100}x"
  # items 1: a dot in an area name is a dot, not a regex wildcard
  proj; run LABEL_AREAS="a.b axb" FORGE_HOST=github LABEL_AREA_DESCS=$'axb=Only for axb'
  y=$(cat "$P/.github/labels.yml")
  ck "literal desc (given): a.b does not take axb's description" "Project-specific area" "$(awk '$0=="- name: a.b"{f=1;next} f&&/description:/{sub(/.*description: /,"");print;exit}' <<< "$y")"
  ck "literal desc (given): axb keeps its own" "Only for axb" "$(awk '$0=="- name: axb"{f=1;next} f&&/description:/{sub(/.*description: /,"");print;exit}' <<< "$y")"
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `axb` | Axb row |\n| `a.b` | Dot row |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="a.b axb" FORGE_HOST=github LABELS_MERGE=no
  y=$(cat "$P/.github/labels.yml")
  ck "literal desc (doc): a.b takes its own row" "Dot row" "$(awk '$0=="- name: a.b"{f=1;next} f&&/description:/{sub(/.*description: /,"");print;exit}' <<< "$y")"
  ck "literal desc (doc): axb takes its own row" "Axb row" "$(awk '$0=="- name: axb"{f=1;next} f&&/description:/{sub(/.*description: /,"");print;exit}' <<< "$y")"
  # item 2a: GitHub rejects a label description over 100 characters
  proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=$d100"
  ck "desc 100 chars: accepted" 0 "$rc"
  proj; run LABEL_AREAS="api ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=$d101"
  ck "desc 101 chars: refused" 1 "$rc"
  ck "desc 101 chars: names the area" yes "$(has 'refused area description: ops' "$err")"
  ck "desc 101 chars: nothing written" "" "$(files)"
  # item 4: a doc-derived name with a space is one name, and it is refused
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `my area` | Two words |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=no
  ck "spaced doc name: exit 1" 1 "$rc"
  ck "spaced doc name: refused as one name" yes "$(has 'refused area name: my area' "$err")"
  ck "spaced doc name: doc unchanged" "$S" "$(sha "$P/docs/guides/labels.md")"
  ck "spaced doc name: no declaration written" no "$([ -e "$P/.github/labels.yml" ] && echo yes || echo no)"
}
sc_notemplates() {  # the labels step has no dependency on versioned issue templates
  proj; mkdir -p "$P/.github/ISSUE_TEMPLATE"; printf 'name: Feature\nbody: []\n' > "$P/.github/ISSUE_TEMPLATE/feature.yml"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "no template-version anywhere: exit 0" 0 "$rc"
  ck "no template-version anywhere: labels.md installed" "api" "$(names "$P/docs/guides/labels.md")"
  ck "no template-version anywhere: declaration installed" yes "$([ -f "$P/.github/labels.yml" ] && echo yes || echo no)"
}

echo "== labels.md absent: written, read by the gate, true downstream =="; sc_absent
echo "== refusals leave nothing behind =="; sc_refuse
echo "== labels.md present: never clobbered, merged only on yes =="; sc_present
echo "== the declaration: host-aware, never shadowed =="; sc_decl
echo "== sync-labels.sh and forge-lib.sh: absent-only, never run =="; sc_sync
echo "== no versioned templates needed =="; sc_notemplates
echo "== review round 1 fixtures =="; sc_round1
echo "== #424 fixtures =="; sc_round2

echo "== the kit's own doc carries the markers the installer drops =="
KD=$(cat "$ROOT/docs/guides/labels.md")
ck "kit labels.md: forge-kit-only markers present" yes "$(has 'adapt-droppable: forge-kit-only' "$KD")"
ck "kit labels.md: still names check-label-taxonomy (kit-only claim stays true there)" yes "$(has check-label-taxonomy "$KD")"

echo "== the pointer, the depth guard and the manual path =="
tree="$T/tree"; mkdir -p "$tree/plugins/forge-kit-adapt/skills/adapt/references"
cp "$REF" "$tree/plugins/forge-kit-adapt/skills/adapt/references/templates-labels.md"
cp "$SKILL" "$tree/plugins/forge-kit-adapt/skills/adapt/SKILL.md"
o=$(bash "$ROOT/scripts/check-reference-depth.sh" "$tree" 2>&1); ck "depth guard passes with the pointer" 0 "$?"
grep -v 'templates-labels.md' "$SKILL" > "$tree/plugins/forge-kit-adapt/skills/adapt/SKILL.md"
o=$(bash "$ROOT/scripts/check-reference-depth.sh" "$tree" 2>&1); rcd=$?
ck "depth guard fails with the pointer removed" 1 "$rcd"
ck "depth guard names the reference" yes "$(has 'templates-labels.md' "$o")"
W=$(cat "$ROOT/docs/guides/without-claude-code.md")
ck "manual path still names labels.md (already done by d14b683)" yes "$(has 'labels.md' "$W")"
ck "manual path still names sync-labels.sh" yes "$(has 'sync-labels.sh' "$W")"

# --- mutants: each breaks ONE invariant in the extracted block; the guarding scenario must notice.
ORIG="$BLOCK"
mutant() {  # mutant <description> <sed expr> <scenario>
  BLOCK=$(printf '%s\n' "$ORIG" | sed -e "$2")
  if [ "$BLOCK" = "$ORIG" ]; then bad "mutant did not apply: $1"; BLOCK="$ORIG"; return; fi
  QUIET=1; SCFAIL=0; "$3" >/dev/null 2>&1; QUIET=0
  if [ "$SCFAIL" = 1 ]; then ok "mutant killed: $1"; else bad "mutant SURVIVED: $1"; fi
  BLOCK="$ORIG"
}
echo "== mutants =="
mutant "the absent-only guard on labels.md removed (clobbers an existing doc)" 's/^if \[ ! -f "\$DOC" \]; then/if true; then/' sc_present
mutant "a merge without an explicit yes" 's/elif \[ "\$merge" = yes \]; then/elif [ "$merge" != no ]; then/' sc_present
mutant "yes never merges" 's/elif \[ "\$merge" = yes \]; then/elif false; then/' sc_present
mutant "sync-labels.sh is run" '$a bash scripts/sync-labels.sh --check' sc_sync
mutant "the host switch always writes .github" 's/forgejo) hdir=\.forgejo/forgejo) hdir=.github/' sc_decl
mutant "an existing declaration is shadowed by a second one" 's/^if \[ -n "\$decl" \]; then/if false; then/' sc_decl
mutant "the disagreement report is silenced" 's/echo "labels.yml does not declare:\${miss}"/:/' sc_decl
mutant "the name allow-list is skipped" '/\[!a-z0-9\]\*|\*\[!a-z0-9\._-\]\*/d' sc_refuse
mutant "the duplicate check is skipped" '/(duplicate)/d' sc_refuse
mutant "the forge-kit-only paragraphs are kept" 's#/\^<!-- adapt-droppable: forge-kit-only/#/^NEVER-MATCHES/#' sc_absent
mutant "contribution is written to the declaration" 's/P3 critical " awk/P3 critical contribution " awk/' sc_decl
mutant "forge-lib.sh is not copied beside a present sync-labels.sh" 's/^if \[ ! -f scripts\/forge-lib.sh \]; then/if false; then/' sc_sync
mutant "the declaration ignores the doc table" 's/^areas=\$(area_names "\$DOC"); \[ -n "\$areas" \] || areas="\$LABEL_AREAS"/areas="$LABEL_AREAS"/' sc_decl
mutant "a bad description is not refused" 's/^  okdesc "\${l#\*=}" || die .*$/  :/' sc_decl
mutant "a description for an unlisted area is accepted" 's/\*) die "refused area description: \${l%%=\*} (not in LABEL_AREAS)" ;; esac/*) ;; esac/' sc_decl
mutant "names read from an existing doc are not validated" 's/\*) vname "\$a" ;; esac; done <<EOF_NAMES/*) : ;; esac; done <<EOF_NAMES/' sc_decl
mutant "a doc name is word-split again (a spaced name becomes two)" 's/while IFS= read -r a; do \[ -n "\$a" \] || continue;/for a in $(area_names "$DOC"); do/;s/done <<EOF_NAMES/done; : <<EOF_NAMES/' sc_round2
mutant "the 100-character cap is removed" 's/^  \[ "\${#1}" -le 100 \]$/  :/' sc_round2
mutant "the description lookup is a regex again" 's/awk .index(\$0, ENVIRON\["N"\] "=") == 1 {/awk '"'"'$0 ~ "^" ENVIRON["N"] "=" {/' sc_round2
mutant "the merge awk never leaves the Area table" '/^        a && \/\^##\/ { a = 0 }$/d' sc_round1
mutant "the merge landing check is skipped" 's/got=\$(area_names "\$DOC.tmp")/got="$missing"/' sc_round1
mutant "the create path never leaves the Area table" '/^    area && \/\^##\/ { area = 0 }$/d' sc_round1
mutant "a failed doc write is swallowed" 's/ || die "could not write \$DOC"//' sc_round1
mutant "a failed script copy is swallowed" 's/ || die "could not copy scripts\/forge-lib.sh"//' sc_round1
mutant "a colon is allowed in a description" 's/\[!A-Za-z0-9\\ ,\./[!A-Za-z0-9\\:\\ ,./' sc_round1
mutant "a hash is allowed in a description" 's/\[!A-Za-z0-9\\ ,\./[!A-Za-z0-9\\#\\ ,./' sc_round1
mutant "the declaration match is a substring" 's/grep -qxF -- "- name: \$2"/grep -qF -- "- name: $2"/' sc_round1
mutant "critical is no longer a fixed name" 's/ testing p0 p1 p2 p3 critical contribution/ testing p0 p1 p2 p3 contribution/' sc_round1

echo ""
echo "forge-adapt templates labels tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
