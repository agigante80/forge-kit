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
TMO=""; command -v timeout >/dev/null 2>&1 && TMO="timeout 10"   # a looping mutant is killed, not waited for
# run [VAR=value ...]: the block in $P under a clean env.
run() {
  out=$(cd "$P" && env -i PATH="$T/stub:$PATH" HOME="$T/home" FORGE_KIT_DIR="${KIT:-$ROOT}" "$@" $TMO bash -c "$BLOCK" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
  # #466: no scratch file may outlive a run (success, die or failed landing check). Recorded through ck,
  # so a mutant that drops the trap is seen in QUIET mode; silent when clean to keep the report short.
  r=$(find "$P" \( -name '.*.??????' \) 2>/dev/null)
  [ -z "$r" ] || ck "no scratch residue after a run: $r" "" "$r"
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
  for bad_in in 'api bad|name' 'a:b' '-x' 'api api' 'bug' 'p0' 'P0' 'Bug' 'api API' 'Critical' 'contribution' 'a`b' '..'; do
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
  ck "sync: nothing typed means no export on the Run line (#517)" no "$(has 'export' "$out")"
  # #517: an existing working-copy .forge.conf that differs from the default branch, and the Step 1
  # probe's FORGE_HOST, are NOT user-typed values: the Run line exports neither.
  proj; printf 'FORGE_API_URL=https://hostile.example\nFORGE_REPO=x/y\nFORGE_HOST=forgejo\n' > "$P/.forge.conf"
  run LABEL_AREAS="api" FORGE_HOST=forgejo
  ck "sync: an existing .forge.conf and the probe's FORGE_HOST are never exported (#517)" "no no" "$(has 'export' "$out") $(has 'hostile.example' "$out")"
  ck "sync: the Run line is still the plain run (#517)" yes "$(has 'Run: bash scripts/sync-labels.sh --check' "$out")"
  proj; run LABEL_AREAS="api" FORGE_HOST=github TYPED_FORGE_API_URL="https://f.example.org/x y" TYPED_FORGE_REMOTE=forgejo
  ck "sync: a value typed this run is exported, quoted, with its source stated (#517)" yes \
    "$(has "Run: export FORGE_API_URL=https://f.example.org/x\\ y; export FORGE_REMOTE=forgejo; bash scripts/sync-labels.sh --check   # typed by you in this run, never read from .forge.conf: FORGE_API_URL FORGE_REMOTE" "$out")"
  ck "sync: an untyped key is not exported even when its twin is (#517)" no "$(has 'export FORGE_HOST' "$out")"
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
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `Front:end` | UI |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
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
sc_case() {  # #465: uppercase area names are valid, and the fixed-name and duplicate checks fold case
  local y
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | API |\n| `UI` | The UI |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=no
  ck "uppercase doc area: exit 0" 0 "$rc"
  ck "uppercase doc area: the declaration carries UI" yes "$(has '- name: UI' "$(cat "$P/.github/labels.yml" 2>/dev/null)")"
  ck "uppercase doc area: sync-labels.sh and forge-lib.sh copied" "yes yes" "$([ -f "$P/scripts/sync-labels.sh" ] && echo -n yes || echo -n no) $([ -f "$P/scripts/forge-lib.sh" ] && echo -n yes || echo -n no)"
  ck "uppercase doc area: the doc is unchanged" "$S" "$(sha "$P/docs/guides/labels.md")"
  o=$(mech "UI,bug" "$P/docs/guides/labels.md"); ck "uppercase doc area: the gate accepts UI,bug" pass "${o%%	*}"
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | API |\n| `UI` | The UI |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="api UI" FORGE_HOST=github LABELS_MERGE=no
  ck "doc UI, confirmed UI: exit 0 (not a duplicate of itself)" 0 "$rc"
  ck "doc UI, confirmed UI: no duplicate refusal" no "$(has duplicate "$err")"
  ck "doc UI, confirmed UI: declared once" 1 "$(grep -cxF -- '- name: UI' "$P/.github/labels.yml" 2>/dev/null)"
  proj; run LABEL_AREAS="api Web" FORGE_HOST=github LABEL_AREA_DESCS=$'Web=Website'
  ck "confirmed Web: exit 0" 0 "$rc"
  ck "confirmed Web: the Area table is api Web" "api Web" "$(names "$P/docs/guides/labels.md")"
  y=$(cat "$P/.github/labels.yml" 2>/dev/null)
  ck "confirmed Web: the description applies to Web" "Website" "$(awk '$0=="- name: Web"{f=1;next} f&&/description:/{sub(/.*description: /,"");print;exit}' <<< "$y")"
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | API |\n' > "$P/docs/guides/labels.md"; S=$(sha "$P/docs/guides/labels.md")
  run LABEL_AREAS="API" FORGE_HOST=github LABELS_MERGE=yes
  ck "doc api, confirmed API: exit 1" 1 "$rc"
  ck "doc api, confirmed API: refused as a duplicate" yes "$(has '(duplicate)' "$err")"
  ck "doc api, confirmed API: the doc is not merged" "$S" "$(sha "$P/docs/guides/labels.md")"
  ck "doc api, confirmed API: nothing else written" "./docs/guides/labels.md " "$(files)"
  proj; run LABEL_AREAS="P0" FORGE_HOST=github
  ck "P0 refused with the fixed-name rule" yes "$(has 'refused area name: P0 (a type, priority or special label)' "$err")"
  ck "P0 refused: nothing written" "" "$(files)"
  proj; run LABEL_AREAS="api API" FORGE_HOST=github
  ck "api API refused with the duplicate rule" yes "$(has 'refused area name: API (duplicate)' "$err")"
  proj; run LABEL_AREAS="API api" FORGE_HOST=github
  ck "API api (uppercase first) refused with the duplicate rule" yes "$(has 'refused area name: api (duplicate)' "$err")"
  ck "API api: nothing written" "" "$(files)"
  proj; run LABEL_AREAS="a:b" FORGE_HOST=github
  ck "a bad character names the rule that failed" yes "$(has 'letters, digits' "$err")"
}
sc_tmpfile() {  # #466: outputs are published through their symlinks, beside the real target, never via a .tmp name
  local tbl='# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | Our API |\n' S old
  old=$(umask)
  # absolute and relative links to a 0640 doc
  for kind in abs rel; do
    proj; mkdir -p "$P/real" "$P/docs/guides"; printf "$tbl" > "$P/real/labels.md"; chmod 640 "$P/real/labels.md"
    if [ $kind = abs ]; then ln -s "$P/real/labels.md" "$P/docs/guides/labels.md"; else ln -s ../../real/labels.md "$P/docs/guides/labels.md"; fi
    run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=yes
    ck "$kind symlink merge: exit 0" 0 "$rc"
    ck "$kind symlink merge: the path is still a symlink" yes "$([ -L "$P/docs/guides/labels.md" ] && echo yes || echo no)"
    ck "$kind symlink merge: the target gained the row" "api web" "$(names "$P/real/labels.md")"
    ck "$kind symlink merge: the target keeps mode 640" "$P/real/labels.md" "$(find "$P/real/labels.md" -perm 640)"
    ck "$kind symlink merge: real/ holds nothing else" "labels.md" "$(ls -A "$P/real")"
  done
  # an unlandable merge on a symlinked doc changes nothing
  proj; mkdir -p "$P/real" "$P/docs/guides"; printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| api | Our API |\n' > "$P/real/labels.md"
  ln -s "$P/real/labels.md" "$P/docs/guides/labels.md"; S=$(sha "$P/real/labels.md")
  run LABEL_AREAS="api" FORGE_HOST=github LABELS_MERGE=yes
  ck "unlandable symlink merge: exit 1" 1 "$rc"
  ck "unlandable symlink merge: says it did not land" yes "$(has 'merge did not land in the Area labels table' "$err")"
  ck "unlandable symlink merge: still a symlink" yes "$([ -L "$P/docs/guides/labels.md" ] && echo yes || echo no)"
  ck "unlandable symlink merge: target unchanged" "$S" "$(sha "$P/real/labels.md")"
  ck "unlandable symlink merge: real/ holds nothing else" "labels.md" "$(ls -A "$P/real")"
  # a user's .tmp siblings are never read, written or removed
  proj; mk_old_doc; mkdir -p "$P/.github"; echo "MY NOTES" > "$P/docs/guides/labels.md.tmp"; echo "MY NOTES" > "$P/.github/labels.yml.tmp"
  run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=yes
  ck "user .tmp files: exit 0" 0 "$rc"
  ck "user .tmp files: labels.md.tmp untouched" "MY NOTES" "$(cat "$P/docs/guides/labels.md.tmp")"
  ck "user .tmp files: labels.yml.tmp untouched" "MY NOTES" "$(cat "$P/.github/labels.yml.tmp")"
  ck "user .tmp files: the row is merged" "api web" "$(names "$P/docs/guides/labels.md")"
  ck "user .tmp files: the declaration is written" yes "$([ -f "$P/.github/labels.yml" ] && echo yes || echo no)"
  proj; mkdir -p "$P/docs/guides" "$P/.github"; echo "MY NOTES" > "$P/docs/guides/labels.md.tmp"; echo "MY NOTES" > "$P/.github/labels.yml.tmp"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "user .tmp files on an absent-doc install: both untouched" "MY NOTES MY NOTES" "$(cat "$P/docs/guides/labels.md.tmp" "$P/.github/labels.yml.tmp" | tr '\n' ' ' | sed 's/ $//')"
  # a dangling link is refused before anything is created
  proj; mkdir -p "$P/docs/guides"; ln -s nodir/labels.md "$P/docs/guides/labels.md"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "dangling doc link: exit 1" 1 "$rc"
  ck "dangling doc link: the exact message" "forge-adapt: docs/guides/labels.md is a dangling symlink (its target directory does not exist): nothing written" "$(printf '%s\n' "$err" | tail -n 1)"
  ck "dangling doc link: the link is unchanged" nodir/labels.md "$(readlink "$P/docs/guides/labels.md")"
  ck "dangling doc link: no .github, no declaration" no "$([ -e "$P/.github" ] && echo yes || echo no)"
  # a doc linked to an ABSENT file in an existing directory is created through the link
  proj; mkdir -p "$P/real" "$P/docs/guides"; ln -s "$P/real/labels.md" "$P/docs/guides/labels.md"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "doc link to an absent file: exit 0" 0 "$rc"
  ck "doc link to an absent file: still a symlink" yes "$([ -L "$P/docs/guides/labels.md" ] && echo yes || echo no)"
  ck "doc link to an absent file: the target holds the table" api "$(names "$P/real/labels.md")"
  # a read-only doc (0444) is still merged and keeps its mode (skipped as root, which ignores modes)
  if [ "$(id -u)" != 0 ]; then
    proj; mk_old_doc; chmod 444 "$P/docs/guides/labels.md"
    run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=yes
    ck "read-only doc: exit 0" 0 "$rc"
    ck "read-only doc: the row is merged" "api web" "$(names "$P/docs/guides/labels.md")"
    ck "read-only doc: still mode 444" "$P/docs/guides/labels.md" "$(find "$P/docs/guides/labels.md" -perm 444)"
    # an unreadable doc (0200) is refused, not wiped down to the new table (round 2 review)
    proj; mk_old_doc; S=$(cat "$P/docs/guides/labels.md"); chmod 200 "$P/docs/guides/labels.md"
    run LABEL_AREAS="api web" FORGE_HOST=github LABELS_MERGE=yes
    ck "unreadable doc: exit 1" 1 "$rc"
    chmod 600 "$P/docs/guides/labels.md"
    ck "unreadable doc: byte-identical" "$S" "$(cat "$P/docs/guides/labels.md")"
  fi
  # a link loop is refused (run under timeout, so a capless resolver is killed, exit 124)
  proj; mkdir -p "$P/docs/guides"; ln -s loop.md "$P/docs/guides/labels.md"; ln -s labels.md "$P/docs/guides/loop.md"
  run LABEL_AREAS="api" FORGE_HOST=github   # without timeout(1) a capless mutant would hang, but the real block cannot
  ck "link loop: exit 1" 1 "$rc"
  ck "link loop: the exact message" "forge-adapt: docs/guides/labels.md is a symlink loop: nothing written" "$(printf '%s\n' "$err" | tail -n 1)"
  ck "link loop: both links unchanged" "loop.md labels.md" "$(readlink "$P/docs/guides/labels.md") $(readlink "$P/docs/guides/loop.md")"
  # a declaration linked to an ABSENT file in an existing directory is written through (a link to an
  # existing one is report-only, as before), at the umask mode
  proj; mkdir -p "$P/.github" "$P/other"; ln -s "$P/other/labels.yml" "$P/.github/labels.yml"
  umask 022; run LABEL_AREAS="api" FORGE_HOST=github; umask "$old"
  ck "declaration link: exit 0" 0 "$rc"
  ck "declaration link: still a symlink" yes "$([ -L "$P/.github/labels.yml" ] && echo yes || echo no)"
  ck "declaration link: the target now declares api" yes "$(has '- name: api' "$(cat "$P/other/labels.yml" 2>/dev/null)")"
  ck "declaration link: the target is created at the umask mode" "$P/other/labels.yml" "$(find "$P/other/labels.yml" -perm 644 2>/dev/null)"
  ck "declaration link: the second directory holds nothing else" "labels.yml" "$(ls -A "$P/other")"
  # a NEW doc and a NEW declaration get the umask default, not mktemp's 0600
  proj; umask 022; run LABEL_AREAS="api" FORGE_HOST=github; umask "$old"
  ck "new files under umask 022: both are mode 644" "2" "$(find "$P/docs/guides/labels.md" "$P/.github/labels.yml" -perm 644 | wc -l | tr -d ' ')"
  # both outputs are resolved before the first write
  proj; mkdir -p "$P/.github"; ln -s nodir/labels.yml "$P/.github/labels.yml"
  run LABEL_AREAS="api" FORGE_HOST=github
  ck "dangling declaration, absent doc: exit 1" 1 "$rc"
  ck "dangling declaration: the message names .github/labels.yml" "forge-adapt: .github/labels.yml is a dangling symlink (its target directory does not exist): nothing written" "$(printf '%s\n' "$err" | tail -n 1)"
  ck "dangling declaration: the doc and docs/guides were not created" no "$([ -e "$P/docs" ] && echo yes || echo no)"
}
sc_why() {  # #531: a description refusal names its cause (character and byte position, first character, length, empty)
  local a100 a101 y
  a100=$(printf 'a%.0s' $(seq 1 100)); a101="${a100}a"
  # an allowed description of every punctuation class still passes, written unchanged
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=Run (a/b), c.d; e_f-g 'h'"
  ck "why: every allowed punctuation class: exit 0" 0 "$rc"
  ck "why: every allowed punctuation class: no refused text" no "$(has refused "$err")"
  ck "why: every allowed punctuation class: written unchanged" yes "$(has "description: Run (a/b), c.d; e_f-g 'h'" "$(cat "$P/.github/labels.yml" 2>/dev/null)")"
  # the colon: character, position, area
  proj; run LABEL_AREAS="tls" FORGE_HOST=github LABEL_AREA_DESCS=$'tls=Certs and TLS: rotation'
  ck "why colon: exit 1" 1 "$rc"
  ck "why colon: prefix kept, character and position named" yes "$(has "refused area description: tls (':' at position 14, outside the allowed set)" "$err")"
  ck "why colon: nothing written" "" "$(files)"
  # a printable offender is shown as itself
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=Run#book'
  ck "why hash: exit 1" 1 "$rc"
  ck "why hash: shown quoted" yes "$(has "'#' at position 4, outside the allowed set" "$err")"
  # a bad first character
  proj; run LABEL_AREAS="tls" FORGE_HOST=github LABEL_AREA_DESCS=$'tls=-rotation'
  ck "why dash: exit 1" 1 "$rc"
  ck "why dash: first-character wording" yes "$(has "'-' at position 1, must start with a letter or digit" "$err")"
  ck "why dash: not reported as outside the set" no "$(has "outside the allowed set" "$err")"
  proj; run LABEL_AREAS="tls" FORGE_HOST=github LABEL_AREA_DESCS=$'tls= leading space'
  ck "why space: exit 1" 1 "$rc"
  ck "why space: names the space" yes "$(has "' ' at position 1" "$err")"
  proj; run LABEL_AREAS="tls" FORGE_HOST=github LABEL_AREA_DESCS=$'tls=2FA and TLS settings'
  ck "why digit first: accepted" 0 "$rc"
  # the cap
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=$a100"
  ck "why 100 chars: accepted" 0 "$rc"
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=$a101"
  ck "why 101 chars: exit 1" 1 "$rc"
  ck "why 101 chars: length and cap named" yes "$(has "refused area description: ops (101 characters, cap is 100)" "$err")"
  ck "why 101 chars: nothing written" "" "$(files)"
  # empty
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops='
  ck "why empty: exit 1" 1 "$rc"
  ck "why empty: says empty" yes "$(has "refused area description: ops (empty)" "$err")"
  ck "why empty: nothing written" "" "$(files)"
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=a'
  ck "why one char: accepted" 0 "$rc"
  # an ESC byte is escaped, never echoed raw
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=ab\033[31m'
  ck "why ESC: exit 1" 1 "$rc"
  ck "why ESC: escaped, position 3" yes "$(has "'\\x1b' at position 3" "$err")"
  case "$err" in *$'\033'*) y=yes ;; *) y=no ;; esac
  ck "why ESC: no raw 0x1b byte reaches stderr" no "$y"
  # a multibyte character is its first byte, escaped, and nothing above 0x7e is echoed
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=caf\303\251'
  ck "why multibyte: exit 1" 1 "$rc"
  ck "why multibyte: first byte escaped at position 4" yes "$(has "'\\xc3' at position 4" "$err")"
  ck "why multibyte: no byte above 0x7e echoed" "" "$(printf '%s' "$err" | LC_ALL=C tr -d '\000-\177')"
  # a bad character wins over the cap
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=a:$a100"
  ck "why precedence: exit 1" 1 "$rc"
  ck "why precedence: the character is named" yes "$(has "':' at position 2" "$err")"
  ck "why precedence: the cap is not" no "$(has "cap is 100" "$err")"
  # shell metacharacters are echoed as text, never expanded
  for y in '`' '$' '|' '"' '*' '\'; do
    proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS="ops=ab${y}cd"
    ck "why meta [$y]: refused and named at position 3" yes "$(has "'$y' at position 3, outside the allowed set" "$err")"
  done
  # only the first of several offenders is named
  proj; run LABEL_AREAS="ops" FORGE_HOST=github LABEL_AREA_DESCS=$'ops=a:b#c'
  ck "why several: only the first is named" yes "$(has "':' at position 2" "$err")"
  ck "why several: and not the second" no "$(has "'#'" "$err")"
  # a doc-derived bad description is still silent and non-fatal
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `ops` | Ops: on-call |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="ops" FORGE_HOST=github LABELS_MERGE=no
  ck "why doc-derived: exit 0" 0 "$rc"
  ck "why doc-derived: falls back to the neutral description" yes "$(has "description: Project-specific area" "$(cat "$P/.github/labels.yml" 2>/dev/null)")"
}
sc_case472() {  # #472: the kit's row and declaration are found without regard to case, written under the CONFIRMED spelling
  local y m
  proj; run LABEL_AREAS="API" FORGE_HOST=github
  ck "API: exit 0" 0 "$rc"
  m=$(grep -F '| `API` |' "$P/docs/guides/labels.md" 2>/dev/null)
  ck "API: the row is named API with the kit description" yes "$(has '| `API` | API routes or contracts |' "$m")"
  ck "API: the row is the kit's, not neutral" no "$(has 'Project-specific area' "$m")"
  y=$(cat "$P/.github/labels.yml" 2>/dev/null)
  ck "API: declared as - name: API once" 1 "$(grep -cxF -- '- name: API' "$P/.github/labels.yml" 2>/dev/null)"
  ck "API: no lowercase api entry" 0 "$(grep -cxF -- '- name: api' "$P/.github/labels.yml" 2>/dev/null)"
  ck "API: the kit colour bfd4f2" bfd4f2 "$(awk '$0=="- name: API"{f=1;next} f&&/color:/{gsub(/[^0-9a-f]/,"",$2);print $2;exit}' <<< "$y")"
  proj; run LABEL_AREAS="Privacy" FORGE_HOST=github
  ck "Privacy: exit 0" 0 "$rc"
  m=$(grep -F '| `Privacy` |' "$P/docs/guides/labels.md" 2>/dev/null)
  ck "Privacy: the row carries the kit's privacy description" no "$(has 'Project-specific area' "$m")"
  ck "Privacy: declared as - name: Privacy" 1 "$(grep -cxF -- '- name: Privacy' "$P/.github/labels.yml" 2>/dev/null)"
  ck "Privacy: the kit colour d4c5f9" d4c5f9 "$(awk '$0=="- name: Privacy"{f=1;next} f&&/color:/{gsub(/[^0-9a-f]/,"",$2);print $2;exit}' "$P/.github/labels.yml" 2>/dev/null)"
  ck "Privacy: the gate accepts Privacy,bug against the written doc" pass "$(o=$(mech "Privacy,bug" "$P/docs/guides/labels.md"); echo "${o%%	*}")"
  proj; run LABEL_AREAS="Ops" FORGE_HOST=github
  ck "Ops: neutral description" yes "$(has '| `Ops` | Project-specific area |' "$(cat "$P/docs/guides/labels.md" 2>/dev/null)")"
  ck "Ops: colour ededed" ededed "$(awk '$0=="- name: Ops"{f=1;next} f&&/color:/{gsub(/[^0-9a-f]/,"",$2);print $2;exit}' "$P/.github/labels.yml" 2>/dev/null)"
  proj; run LABEL_AREAS="Apiary" FORGE_HOST=github
  ck "Apiary: not treated as api (neutral)" yes "$(has '| `Apiary` | Project-specific area |' "$(cat "$P/docs/guides/labels.md" 2>/dev/null)")"
  ck "Apiary: colour ededed" ededed "$(awk '$0=="- name: Apiary"{f=1;next} f&&/color:/{gsub(/[^0-9a-f]/,"",$2);print $2;exit}' "$P/.github/labels.yml" 2>/dev/null)"
  proj; run LABEL_AREAS="aPi" FORGE_HOST=github
  ck "aPi: the row is written as aPi with the kit description" yes "$(has '| `aPi` | API routes or contracts |' "$(cat "$P/docs/guides/labels.md" 2>/dev/null)")"
  proj; mkdir -p "$P/docs/guides"
  printf '# L\n\n### Area labels\n| Label | Description |\n|---|---|\n| `api` | API |\n' > "$P/docs/guides/labels.md"
  run LABEL_AREAS="API" FORGE_HOST=github LABELS_MERGE=no
  ck "#472 duplicate path: doc api, confirmed API still exits 1" 1 "$rc"
  ck "#472 duplicate path: refused as a duplicate" yes "$(has '(duplicate)' "$err")"
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
echo "== #465 fixtures =="; sc_case
echo "== #466 fixtures =="; sc_tmpfile
echo "== #472 fixtures =="; sc_case472
echo "== #531 fixtures =="; sc_why

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
mutant "the Run line exports the probe's FORGE_HOST (#517)" 's/eval "v=\\${TYPED_\$k-}"/eval "v=\\${$k-}"/' sc_sync
mutant "sync-labels.sh is run" '$a bash scripts/sync-labels.sh --check' sc_sync
mutant "the host switch always writes .github" 's/forgejo) hdir=\.forgejo/forgejo) hdir=.github/' sc_decl
mutant "an existing declaration is shadowed by a second one" 's/^if \[ -n "\$decl" \]; then/if false; then/' sc_decl
mutant "the disagreement report is silenced" 's/echo "labels.yml does not declare:\${miss}"/:/' sc_decl
mutant "the name allow-list is skipped" '/\[!A-Za-z0-9\]\*|\*\[!A-Za-z0-9\._-\]\*/d' sc_refuse
mutant "the allow-list is lowercase-only again" 's/\[!A-Za-z0-9\]\*|\*\[!A-Za-z0-9\._-\]\*/[!a-z0-9]*|*[!a-z0-9._-]*/' sc_case
mutant "the fixed-name check is case-sensitive" 's/case "\$fixed" in \*" \$lc "\*)/case "$fixed" in *" $1 "*)/' sc_case
mutant "the duplicate check is case-sensitive" 's/case "\$seenlc" in \*" \$lc "\*)/case "$seenlc" in *" $1 "*)/' sc_case
mutant "seenlc stores the original spelling" 's/seenlc="\$seenlc\$lc "/seenlc="$seenlc$1 "/' sc_case
mutant "seen stores the lowercased name" 's/seen="\$seen\$1 "/seen="$seen$lc "/' sc_case
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
mutant "the merge landing check is skipped" 's/got=\$(area_names "\$scratch")/got="$missing"/' sc_round1
mutant "the create path never leaves the Area table" '/^    area && \/\^##\/ { area = 0 }$/d' sc_round1
mutant "a failed doc write is swallowed" 's/ || die "could not write \$DOC"//g;s/ || die "cannot create a temporary file beside \$1"//' sc_round1
mutant "a failed script copy is swallowed" 's/ || die "could not copy scripts\/forge-lib.sh"//' sc_round1
mutant "a colon is allowed in a description" 's/\[!A-Za-z0-9\\ ,\./[!A-Za-z0-9\\:\\ ,./' sc_round1
mutant "a hash is allowed in a description" 's/\[!A-Za-z0-9\\ ,\./[!A-Za-z0-9\\#\\ ,./' sc_round1
mutant "the declaration match is a substring" 's/grep -qxF -- "- name: \$2"/grep -qF -- "- name: $2"/' sc_round1
mutant "critical is no longer a fixed name" 's/ testing p0 p1 p2 p3 critical contribution/ testing p0 p1 p2 p3 contribution/' sc_round1
mutant "the trap that removes the scratch file is deleted" '/^trap /d' sc_tmpfile
mutant "the doc publishes over the link path, not the resolved target" 's/publish "\$DOCF"/publish "$DOC"/' sc_tmpfile
mutant "the create path publishes over the link path" '/^  newscratch "\$DOCF"$/,/^  . "\$KDOC"/s/publish "\$DOCF"/publish "$DOC"/' sc_tmpfile
mutant "a failed read of the target is ignored" 's/ || die "cannot read \$1: nothing written"//' sc_tmpfile
mutant "a read-only target is not made writable while composing" '/^    \[ -w "\$scratch" \]/d' sc_tmpfile
mutant "a relative link is resolved as if absolute" 's|\*) d=\${p%/\*}; \[ "\$d" = "\$p" \] \&\& d=\.; p="\$d/\$l" ;; esac|*) p="$l" ;; esac|' sc_tmpfile
mutant "the merge composes into a fixed DOC.tmp again" 's/ > "\$scratch" || die "could not write \$DOC"/ > "$DOC.tmp" || die "could not write $DOC"/' sc_tmpfile
mutant "the dangling-link check is deleted" '/^  \[ "\$hops" -eq 0 \] || \[ -d "\$d" \] || die /d' sc_tmpfile
mutant "the declaration publishes over the link path" 's/publish "\$DECLF"/publish "$hdir\/labels.yml"/' sc_tmpfile
mutant "the new-file chmod step is deleted" '/^  else chmod /d' sc_tmpfile
mutant "the 40-hop cap is removed" 's/ \[ "\$hops" -le 40 \] || die "\$1 is a symlink loop: nothing written"/ :/' sc_tmpfile
mutant "the declaration is resolved after the doc is written" 's/^if \[ -z "\$decl" \]; then resolve .*$/:/;s/^  newscratch "\$DECLF"$/  resolve "$hdir\/labels.yml"; DECLF="$RESOLVED"; newscratch "$DECLF"/' sc_tmpfile
mutant "the kit row lookup is exact-case again (#472)" 's/tolower(substr(\$0, 4, RLENGTH - 6)) == k/substr($0, 4, RLENGTH - 6) == ENVIRON["K"]/' sc_case472
mutant "the kit declaration lookup is exact-case again (#472)" 's/tolower(\$0) == k {/$0 == "- name: " ENVIRON["K"] {/' sc_case472
mutant "the kit row is written under the kit spelling, not the confirmed one (#472)" 's/print "| `" ENVIRON\["K"\] "` |" substr/print "| `api` |" substr/' sc_case472
mutant "a supplied description no longer wins over a folded kit entry (#472)" 's/^kit_ok() .*$/kit_ok() { true; }/' sc_case
mutant "the offending position is 0-based (#531)" 's/c=\${s:i-1:1}; v=/i=$((i - 1)); c=${s:i:1}; v=/' sc_why
mutant "the offending character is dropped from the message (#531)" 's/printf . (%s at position %d, outside/printf " (position %d, outside/;s/"\$c" "\$i"; fi/"$i"; fi/' sc_why
mutant "a non-printable byte is echoed raw (#531)" 's/if \[ "\$v" -ge 32 \] \&\& \[ "\$v" -le 126 \]/if true/' sc_why
mutant "the cap message reports no length (#531)" "s/printf ' (%d characters, cap is 100)' \"\\\${#s}\"/printf ' (over the cap)'/" sc_why
mutant "empty and first-character causes merge into one generic message (#531)" 's/ (empty)/ (outside the allowed set)/;s/, must start with a letter or digit)/, outside the allowed set)/' sc_why
mutant "a bad first character reads as outside the set (#531)" 's/if \[ "\$i" -eq 1 \]; then/if false; then/' sc_why
mutant "the cap is checked before the characters (#531)" 's/^  while \[ "\$i" -le "\${#s}" \]; do/  [ "${#s}" -le 100 ] || { printf " (%d characters, cap is 100)" "${#s}"; return 0; }\n  while [ "$i" -le "${#s}" ]; do/' sc_why
mutant "the refusal drops the reason (#531)" 's/\$(descwhy "\${l#\*=}")//' sc_why

echo ""
echo "forge-adapt templates labels tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
