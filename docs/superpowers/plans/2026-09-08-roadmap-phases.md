# forge-kit-roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `forge-kit-roadmap`, an optional plugin group that makes rolling wave planning mechanical: `docs/roadmap.md` owns which phases exist, the host owns which phase each ticket is in, and four rules are refusals a script performs.

**Architecture:** A new eighth plugin group holding one skill (`roadmap-phases`, canonical for every rule), two shipped shell assets (`check-phases.sh` guards, `sync-phases.sh` applies), and one command (`/phase`). Milestone primitives go into the existing host adapter `forge-lib.sh`, because milestones are a host capability rather than a planning concept. A repo guard enforces that no component outside the new group references it.

**Tech Stack:** Bash (3.2 compatible), `jq`, GitHub/Forgejo REST via `forge-lib.sh`, contract tests as bash scripts driven against throwaway dirs and a stubbed transport.

**Spec:** `docs/superpowers/specs/2026-09-08-roadmap-phases-design.md`

## Global Constraints

Every task's requirements implicitly include these. They are the repo's existing rules, and CI enforces all of them.

- **Bash 3.2 and BSD userland.** No `${var,,}` outside a `BASH_VERSINFO` gate, no `readlink -f`. Use the `set_lower` / `abspath` helpers copied from `check-public-leaks.sh`. `scripts/test-check-public-leaks.sh` bans both constructs and the same ban applies here.
- **No em dashes or en dashes anywhere.** `.claude/settings.json` wires `block-dashes.py` as a `PreToolUse` hook; a tool call containing U+2014 or U+2013 is denied. Restructure the sentence, never substitute a hyphen.
- **Every component carries a version marker.** `<!-- <name>-version: N -->` for `.md`, `# <name>-version: N` for `.sh`. Bump it on every behavioural change. `.githooks/pre-commit` blocks a commit that does not.
- **Every changed plugin group bumps its `plugin.json` semver.** Same hook.
- **Component word budgets:** skill 2500 (ceiling 3750), command 2000 (ceiling 3000). `scripts/check-component-size.sh` warns and fails.
- **The generated index is generated.** Never hand-edit between the `component-index` / `plugin-groups` markers in `README.md` and `CLAUDE.md`. Run `python3 scripts/update-component-index.py`.
- **Exit-code contract for both new assets:** `0` clean, `1` the rule found something, `2` could not run (usage, environment, missing `jq`), `3` the declaration is malformed and nothing was written. This mirrors `sync-labels.sh` exactly.
- **A check that cannot run must never report clean.** Missing token, missing `jq`, unreachable host: report SKIPPED loudly on stderr and do not count the rule as passed.
- **Never delete on the host.** A milestone not in the roadmap is reported and left alone.
- **Workflow:** commit to `develop`, push, watch `Validate`, then fast-forward `main`. No pull requests.

## File Structure

| File | Responsibility |
|---|---|
| `plugins/forge-kit-roadmap/.claude-plugin/plugin.json` | Group identity and semver |
| `plugins/forge-kit-roadmap/skills/roadmap-phases/SKILL.md` | Canonical statement of every rule; templates; the close review |
| `plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh` | The four guards |
| `plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh` | roadmap.md to milestones |
| `plugins/forge-kit-roadmap/commands/phase.md` | `/phase status\|plan\|close\|triage` |
| `plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh` | Gains `forge_milestone_*` |
| `scripts/test-check-phases.sh` | Contract test, stubbed transport plus throwaway dirs |
| `scripts/test-sync-phases.sh` | Contract test, stubbed transport, dry run |
| `scripts/check-group-isolation.sh` | Fails if anything outside the group references it |
| `scripts/test-check-group-isolation.sh` | Contract test for that guard |
| `docs/roadmap.md` | forge-kit's own roadmap (Task 8) |

---

### Task 1: The plugin group and its skill

**Files:**
- Create: `plugins/forge-kit-roadmap/.claude-plugin/plugin.json`
- Create: `plugins/forge-kit-roadmap/skills/roadmap-phases/SKILL.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`, `CLAUDE.md` (generated regions only, via the script)

**Interfaces:**
- Consumes: nothing.
- Produces: the group directory every later task writes into, and the skill that is canonical for the rules those tasks enforce. Later tasks' error messages point at `roadmap-phases`.

- [ ] **Step 1: Create the plugin manifest**

```bash
mkdir -p plugins/forge-kit-roadmap/.claude-plugin \
         plugins/forge-kit-roadmap/skills/roadmap-phases/assets \
         plugins/forge-kit-roadmap/commands
cat > plugins/forge-kit-roadmap/.claude-plugin/plugin.json <<'JSON'
{
  "name": "forge-kit-roadmap",
  "version": "0.1.0",
  "description": "Rolling wave planning: docs/roadmap.md owns the phases, the host owns which phase each ticket is in, and four rules are enforced rather than remembered. Optional and self-contained; nothing else in forge-kit depends on it."
}
JSON
```

- [ ] **Step 2: Add the marketplace entry**

Append to the `plugins` array in `.claude-plugin/marketplace.json`, after the `forge-kit-governance` entry:

```json
    {
      "name": "forge-kit-roadmap",
      "source": "./plugins/forge-kit-roadmap",
      "description": "Rolling wave planning: a roadmap of phases, each planned when it starts, every ticket in exactly one phase. Optional; nothing else depends on it."
    },
```

- [ ] **Step 3: Write the skill**

Create `plugins/forge-kit-roadmap/skills/roadmap-phases/SKILL.md`. It MUST contain, in this order: frontmatter (`name`, `description`), the marker `<!-- roadmap-phases-version: 1 -->`, then the content below. Keep it under 2500 words.

Required content, each as its own section:

1. **What this is and is not.** Rolling wave planning: detailed planning limited to the work about to begin. Not project management: no dates, no estimates, no burndown.
2. **Source of truth.** `roadmap.md` owns which phases exist and their state. The host owns which phase each ticket is in, as the milestone. Different facts, so nothing can drift.
3. **The four states**, as the table from the spec (`planned` / `open` / `done` / `backlog`), with the two load-bearing notes: `planned` to `open` is what makes "the plan is written at the start" mechanical, and a `planned` phase is a BUCKET that accepts tickets, because filing a thought you have already had is not the same as enumerating work nobody has thought about.
4. **At most one phase is `open`.**
5. **The roadmap format**, verbatim:

```markdown
## Phase: Host awareness
state: open
plan: docs/plans/host-awareness.md

Why this phase exists, what it unlocks, why it sits here in the order.
```

6. **The plan format**: Goal, Done looks like, Fails if, Expected work, Out of scope. State the **premortem prompt** for Fails if: "it is the end of this phase and it failed badly; what happened?" Say why: imagining a failure that has already happened, rather than one that might, surfaces roughly 30 percent more causes, because it licenses doubts people will not otherwise raise while planning.
7. **Opening a phase.** Read the roadmap prose saying why the phase exists AND the tickets already accumulated in its milestone. The bucket is the evidence the plan is written from.
8. **Closing a phase.** Compare the plan against the tickets actually created. File tickets for skipped or missing work and prioritise them. Close the milestone AND update `roadmap.md`. Both, or the phase is not closed.
9. **When a phase does not finish: re-shape, never extend.** The three outcomes (done, re-shaped, abandoned) and that the roadmap records which. Say that abandoned is the one people skip and the one worth writing down, because a phase deleted without a record looks later like a phase nobody considered.
10. **The four rules `check-phases.sh` enforces**, numbered, matching the script's messages exactly.

- [ ] **Step 4: Regenerate the index and run the structural guards**

```bash
python3 scripts/update-component-index.py
bash scripts/validate-plugins.sh
bash scripts/check-component-size.sh
python3 scripts/update-component-index.py --check
```

Expected: all pass; the index gains a `forge-kit-roadmap` row.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(roadmap): a new plugin group for rolling wave planning

Optional and self-contained: nothing else in forge-kit depends on it,
because rolling wave is one opinionated method and the rest of the kit is
methodology-agnostic."
```

---

### Task 2: Milestone primitives in the host adapter

**Files:**
- Modify: `plugins/forge-kit-devops/skills/forge-host/assets/forge-lib.sh`
- Modify: `plugins/forge-kit-devops/.claude-plugin/plugin.json` (semver bump)
- Test: `scripts/test-forge-lib.sh`

**Interfaces:**
- Consumes: `forge_api`, `forge_api_paginate`, `forge_repo`, `forge_host` (all existing).
- Produces, for Tasks 3, 4 and 5:
  - `forge_milestone_list` -> JSON array of `{id, title, state}` (state is `open` or `closed`), exit 2 on failure.
  - `forge_milestone_create <title> <description>` -> creates, exit 0.
  - `forge_milestone_close <title>` -> closes by title, exit 2 if the title does not exist.
  - `forge_issue_milestone_list` -> JSON array of `{number, milestone}` for OPEN issues, `milestone` being the title string or `null`.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test-forge-lib.sh`, following its existing stubbed-`forge_api` shape:

```bash
echo "== milestones =="
# Pagination must terminate on an EMPTY page, not on a short one: the server clamps `limit` to
# MAX_RESPONSE_ITEMS, so a page shorter than requested is normal and would end the loop early.
STUB_PAGES='[{"id":1,"title":"Phase A","state":"open"}]|[]'
out=$(forge_milestone_list) || bad "forge_milestone_list exits 0"
[ "$(printf '%s' "$out" | jq -r '.[0].title')" = "Phase A" ] \
  && ok "forge_milestone_list returns titles" || bad "forge_milestone_list returns titles"

# Closing by TITLE, because the roadmap names phases and only the host knows ids.
REQLOG=$(mktemp); forge_milestone_close "Phase A"
grep -q 'PATCH .*milestones/1' "$REQLOG" \
  && ok "forge_milestone_close resolves the title to an id" \
  || bad "forge_milestone_close resolves the title to an id"

forge_milestone_close "No Such Phase" 2>/dev/null
[ "$?" -eq 2 ] && ok "closing an unknown title fails rather than silently doing nothing" \
  || bad "closing an unknown title fails rather than silently doing nothing"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/test-forge-lib.sh`
Expected: FAIL with `forge_milestone_list: command not found`.

- [ ] **Step 3: Implement the primitives**

Add to `forge-lib.sh` (bump `# forge-lib-version:` to 9):

```bash
# Milestones are a HOST capability, not a planning concept: dep-auditor already reads them and a
# project using any other method still wants them. They live here rather than in the roadmap group
# for that reason, and so the roadmap group's dependency runs one way only.
forge_milestone_list() {
  local repo; repo="$(forge_repo)" || return 2
  # PAGINATED, because /milestones is a LIST endpoint: a plain GET returns one server page and
  # silently truncates past ~50, the class #62 fixed for issues.
  forge_api_paginate "/repos/$repo/milestones?state=all" \
    | jq -c '[.[] | {id, title, state}]' || return 2
}

forge_milestone_create() {
  local title="$1" desc="${2-}" repo
  repo="$(forge_repo)" || return 2
  forge_api POST "/repos/$repo/milestones" \
    "$(jq -nc --arg t "$title" --arg d "$desc" '{title:$t, description:$d}')" >/dev/null
}

_forge_milestone_id() {
  local title="$1" id
  id="$(forge_milestone_list | jq -r --arg t "$title" '.[] | select(.title == $t) | .id' | head -1)"
  [ -n "$id" ] || return 1
  printf '%s' "$id"
}

forge_milestone_close() {
  local title="$1" repo id
  repo="$(forge_repo)" || return 2
  # FAIL rather than no-op on an unknown title. A close that quietly does nothing would let a
  # roadmap say `done` while the milestone stayed open, which is exactly rule 3's drift.
  id="$(_forge_milestone_id "$title")" || {
    echo "forge-lib: no milestone titled '$title' on $repo" >&2; return 2; }
  forge_api PATCH "/repos/$repo/milestones/$id" '{"state":"closed"}' >/dev/null
}

forge_issue_milestone_list() {
  local repo; repo="$(forge_repo)" || return 2
  forge_api_paginate "/repos/$repo/issues?state=open" \
    | jq -c '[.[] | select(has("pull_request") | not)
                  | {number, milestone: (.milestone.title // null)}]' || return 2
}
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-forge-lib.sh`
Expected: PASS, all cases including the pre-existing ones.

- [ ] **Step 5: Bump the plugin semver and commit**

```bash
python3 - <<'PY'
import json
p='plugins/forge-kit-devops/.claude-plugin/plugin.json'
d=json.load(open(p)); a,b,c=d['version'].split('.'); d['version']=f"{a}.{int(b)+1}.0"
open(p,'w').write(json.dumps(d,indent=2)+"\n")
PY
git add -A
git commit -m "feat(forge-host): milestone primitives in the host adapter

Milestones are a host capability, not a planning concept, so they live
here rather than in the roadmap group. Paginated, because /milestones is
a LIST endpoint and a plain GET truncates past one server page."
```

---

### Task 3: The roadmap parser and rule 2

**Files:**
- Create: `plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh`
- Create: `scripts/test-check-phases.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks (rule 2 is file-only; no host call).
- Produces, for Tasks 4 and 5: `parse_roadmap <file>` emits one TSV row per phase, `name<TAB>state<TAB>plan_path` (plan_path empty when absent), in roadmap order. It exits 3 and emits nothing on a malformed roadmap. `sync-phases.sh` will copy this function rather than source it, and Task 5's test asserts the two copies are byte-identical.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-check-phases.sh`:

```bash
#!/usr/bin/env bash
# Contract test for check-phases.sh (the roadmap-phases guards).
#
# Rules 1, 3 and 4 need the host, so they run against a STUBBED forge-lib.sh placed beside a copy
# of the script, the same seam test-sync-labels.sh uses. Rule 2 is file-only and needs no stub.
#
# EVERY RULE GETS A NEAR-MISS. These are refusal rules, and a refusal rule fails by being too
# eager: one that rejects a legitimate roadmap gets deleted rather than fixed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"

pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
contains() { if printf '%s' "$2" | grep -qiF -- "$1"; then ok "$3"; else bad "$3 (no '$1')"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/docs/plans"
cp "$SRC" "$T/check-phases.sh"

# A plan that satisfies rule 2.
goodplan() { printf '# %s\n\n## Goal\nx\n\n## Done looks like\nx\n\n## Fails if\nx\n' "$1"; }

run() { out=$(cd "$T" && bash ./check-phases.sh "$@" 2>&1); rc=$?; }

echo "== rule 2: an open phase needs a plan with a Fails if section =="
goodplan "A" > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

why A exists
MD
run --offline
expect "an open phase with a complete plan passes" 0 "$rc"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/missing.md
MD
run --offline
expect "an open phase whose plan file is absent fails" 1 "$rc"
contains "rule 2" "$out" "and names the rule"

printf '# A\n\n## Goal\nx\n\n## Done looks like\nx\n' > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
run --offline
expect "a plan with no Fails if section fails" 1 "$rc"
contains "Fails if" "$out" "and says which section is missing"

goodplan "A" > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: planned

not started, so no plan needed yet
MD
run --offline
expect "a planned phase needs no plan" 0 "$rc"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: Backlog
state: backlog
MD
run --offline
expect "backlog needs no plan" 0 "$rc"

# The hole the spec's self-review found: planned straight to done would never pass through the
# state where a plan is required.
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/never-written.md
MD
run --offline
expect "a done phase with no plan file fails too" 1 "$rc"

echo "== the parser refuses a malformed roadmap rather than skipping the block =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A

no state line at all
MD
run --offline
expect "a phase block with no state refuses the run" 3 "$rc"

cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: nonsense
MD
run --offline
expect "an unknown state value refuses the run" 3 "$rc"
contains "planned" "$out" "and lists the states it accepts"

echo "== no roadmap at all is not an error =="
rm -f "$T/docs/roadmap.md"
run --offline
expect "a project with no roadmap exits 0" 0 "$rc"
contains "no roadmap" "$out" "and says so rather than passing silently"

echo ""
echo "check-phases tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/test-check-phases.sh`
Expected: `missing script` or every case failing, because `check-phases.sh` does not exist.

- [ ] **Step 3: Implement the parser and rule 2**

Create `check-phases.sh` with `# check-phases-version: 1` on line 2, a header comment stating the exit codes and the four rules, then:

```bash
set -uo pipefail

ROADMAP=""
OFFLINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --offline)  OFFLINE=1 ;;
    --roadmap)  shift; [ $# -gt 0 ] || die "--roadmap needs a path"; ROADMAP="$1" ;;
    --help|-h)  awk 'NR==1{next} /^# *[a-z0-9-]+-version: [0-9]+$/{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit 0 ;;
    -*)         die "unknown flag: $1" ;;
    *)          die "unexpected argument: $1" ;;
  esac
  shift
done

# docs/ first, then the root, so a project that keeps it either place works with no flag.
if [ -z "$ROADMAP" ]; then
  for c in docs/roadmap.md roadmap.md; do [ -f "$c" ] && { ROADMAP="$c"; break; }; done
fi
if [ -z "$ROADMAP" ]; then
  echo "check-phases: no roadmap at docs/roadmap.md or roadmap.md, so there is nothing to check." >&2
  echo "  this is not an error: the guard is opt-in by the presence of the file." >&2
  exit 0
fi

# parse_roadmap <file> -> name<TAB>state<TAB>plan, one row per phase, in roadmap order.
# REFUSES the whole file rather than skipping a block: a silently ignored phase is a phase the
# guard reports as compliant, which is the drift it exists to end.
parse_roadmap() {
  awk -F': *' '
    /^## Phase:/ {
      if (name != "") emit()
      name = $0; sub(/^## Phase: */, "", name); state = ""; plan = ""; next
    }
    /^state:/ { state = $2; next }
    /^plan:/  { plan  = $2; next }
    END { if (name != "") emit() }
    function emit() {
      if (state == "") { printf("MALFORMED\t%s\tno state line\n", name); return }
      if (state != "planned" && state != "open" && state != "done" && state != "backlog") {
        printf("MALFORMED\t%s\tunknown state %s\n", name, state); return
      }
      printf("%s\t%s\t%s\n", name, state, plan)
    }
  ' "$1"
}

PHASES="$(parse_roadmap "$ROADMAP")"
if printf '%s\n' "$PHASES" | grep -q '^MALFORMED'; then
  printf '%s\n' "$PHASES" | awk -F'\t' '/^MALFORMED/ {printf("check-phases: %s: phase \"%s\": %s\n", "'"$ROADMAP"'", $2, $3)}' >&2
  echo "check-phases: state must be one of: planned, open, done, backlog. Nothing was checked." >&2
  exit 3
fi

violations=0
report() { printf '%s\n' "$1"; violations=$((violations + 1)); }

# Rule 2 (file-only): an open OR done phase has a plan that exists and carries a Fails if section.
# `done` is included to close a hole: a phase moved straight from planned to done would otherwise
# never pass through the state where a plan is required.
while IFS=$'\t' read -r name state plan; do
  [ -n "$name" ] || continue
  case "$state" in open|done) ;; *) continue ;; esac
  if [ -z "$plan" ]; then
    report "rule 2: phase \"$name\" is $state and declares no plan:"; continue
  fi
  if [ ! -f "$plan" ]; then
    report "rule 2: phase \"$name\" declares plan $plan, which does not exist"; continue
  fi
  grep -qi '^#\{1,4\} *Fails if' "$plan" \
    || report "rule 2: phase \"$name\" plan $plan has no \"Fails if\" section (write it as a premortem: it is the end of this phase and it failed badly, what happened?)"
done <<EOF
$PHASES
EOF

[ "$violations" -eq 0 ] || exit 1
exit 0
```

Copy `die`, `SELF`, `set_lower` and `abspath` from `check-public-leaks.sh` verbatim, including their comments, so the bash 3.2 ban is satisfied.

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-check-phases.sh`
Expected: PASS, all cases.

- [ ] **Step 5: Mutation-check the parser refusal**

Temporarily change the malformed branch to `continue` instead of emitting `MALFORMED`, re-run, and confirm the two refusal cases fail. Restore with `cp` from a backup, never `git checkout` (that silently destroys uncommitted work).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(roadmap): the roadmap parser and rule 2, the plan requirement

An open OR done phase needs a plan carrying a Fails if section. done is
included to close a hole: a phase moved straight from planned to done
would never pass through the state where a plan is required.

The parser refuses a malformed roadmap rather than skipping the block,
because a silently ignored phase is one the guard reports as compliant."
```

---

### Task 4: The host rules

**Files:**
- Modify: `plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh`
- Modify: `scripts/test-check-phases.sh`

**Interfaces:**
- Consumes: `forge_milestone_list`, `forge_issue_milestone_list` from Task 2; `parse_roadmap` from Task 3.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test-check-phases.sh`, after the rule 2 section. Add the stub first:

```bash
cat > "$T/forge-lib.sh" <<'STUB'
forge_repo() { printf 'o/r'; }
forge_host() { printf 'github'; }
forge_milestone_list() { cat "$STUB_MILESTONES"; }
forge_issue_milestone_list() { cat "$STUB_ISSUES"; }
STUB
hostrun() {
  out=$(cd "$T" && STUB_MILESTONES="$T/ms.json" STUB_ISSUES="$T/iss.json" \
        bash ./check-phases.sh "$@" 2>&1); rc=$?
}

echo "== rule 1: every open ticket has a phase =="
goodplan "A" > "$T/docs/plans/a.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
hostrun
expect "every ticket in a phase passes" 0 "$rc"

printf '[{"number":7,"milestone":"A"},{"number":9,"milestone":null}]' > "$T/iss.json"
hostrun
expect "a ticket with no phase fails" 1 "$rc"
contains "#9" "$out" "and names the ticket"
contains "rule 1" "$out" "and names the rule"

echo "== rule 3: roadmap state and milestone state agree, and one phase is open =="
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
hostrun
expect "an open phase whose milestone is closed fails" 1 "$rc"
contains "rule 3" "$out" "and names the rule"

goodplan "B" > "$T/docs/plans/b.md"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md

## Phase: B
state: open
plan: docs/plans/b.md
MD
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"B","state":"open"}]' > "$T/ms.json"
hostrun
expect "two open phases fail" 1 "$rc"
contains "at most one" "$out" "and says why"

echo "== rule 4: a done phase has no open tickets =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
printf '[{"id":1,"title":"A","state":"closed"}]' > "$T/ms.json"
printf '[{"number":7,"milestone":"A"}]' > "$T/iss.json"
hostrun
expect "a done phase holding an open ticket fails" 1 "$rc"
contains "rule 4" "$out" "and names the rule"
contains "re-shape" "$out" "and points at moving the ticket rather than extending"

printf '[]' > "$T/iss.json"
hostrun
expect "a done phase with nothing open passes" 0 "$rc"

echo "== a phase in the roadmap with no milestone yet =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
printf '[]' > "$T/ms.json"
hostrun
expect "a phase with no milestone fails" 1 "$rc"
contains "sync-phases" "$out" "and points at the script that fixes it"

echo "== a check that cannot run must never report clean =="
cat > "$T/forge-lib-broken.sh" <<'STUB'
forge_repo() { return 2; }
forge_host() { printf 'github'; }
forge_milestone_list() { return 2; }
forge_issue_milestone_list() { return 2; }
STUB
cp "$T/forge-lib.sh" "$T/forge-lib.good.sh"; cp "$T/forge-lib-broken.sh" "$T/forge-lib.sh"
hostrun
expect "an unreachable host does not report clean" 2 "$rc"
contains "SKIPPED" "$out" "and says the host rules were skipped"
cp "$T/forge-lib.good.sh" "$T/forge-lib.sh"
```

- [ ] **Step 2: Run and watch them fail**

Run: `bash scripts/test-check-phases.sh`
Expected: the new cases fail; the rule 2 cases still pass.

- [ ] **Step 3: Implement the host rules**

Bump the marker to `# check-phases-version: 2`. Source the library the way `sync-labels.sh` does, then add after rule 2:

```bash
if [ "$OFFLINE" = 1 ]; then
  echo "check-phases: --offline, so rules 1, 3 and 4 were NOT checked." >&2
  [ "$violations" -eq 0 ] || exit 1
  exit 0
fi

MS="$(forge_milestone_list 2>/dev/null)" || MS=""
ISS="$(forge_issue_milestone_list 2>/dev/null)" || ISS=""
if [ -z "$MS" ] || [ -z "$ISS" ]; then
  # A check that cannot run must never report clean. Exit 2, loudly, the posture pre-push takes
  # for a missing base ref.
  echo "check-phases: the host could not be reached, so rules 1, 3 and 4 were SKIPPED." >&2
  echo "  they were NOT checked and NOT passed. Check the token and the forge config." >&2
  exit 2
fi

# Rule 1: every open ticket has a phase.
while read -r n; do
  [ -n "$n" ] || continue
  report "rule 1: issue #$n has no phase. Assign it, or put it in the backlog phase, which is a decision to decide later rather than no decision."
done <<EOF
$(printf '%s' "$ISS" | jq -r '.[] | select(.milestone == null) | .number')
EOF

# Rule 3: roadmap state and milestone state agree, and at most one phase is open.
open_count=0
while IFS=$'\t' read -r name state plan; do
  [ -n "$name" ] || continue
  [ "$state" = open ] && open_count=$((open_count + 1))
  ms_state="$(printf '%s' "$MS" | jq -r --arg t "$name" '.[] | select(.title == $t) | .state' | head -1)"
  if [ -z "$ms_state" ]; then
    report "rule 3: phase \"$name\" has no milestone on the host. Run sync-phases.sh."
    continue
  fi
  case "$state" in
    done)    [ "$ms_state" = closed ] || report "rule 3: phase \"$name\" is done in the roadmap but its milestone is open" ;;
    *)       [ "$ms_state" = open ]   || report "rule 3: phase \"$name\" is $state in the roadmap but its milestone is closed" ;;
  esac
done <<EOF
$PHASES
EOF
[ "$open_count" -le 1 ] || report "rule 3: $open_count phases are open. At most one may be, or \"the current phase\" names nothing."

# Rule 4: a done phase holds no open tickets. This is also the circuit breaker: closing a phase
# forces every unfinished ticket somewhere explicit, so the default is to re-shape, never extend.
while IFS=$'\t' read -r name state plan; do
  [ "$state" = done ] || continue
  n="$(printf '%s' "$ISS" | jq -r --arg t "$name" '[.[] | select(.milestone == $t)] | length')"
  [ "${n:-0}" -eq 0 ] \
    || report "rule 4: phase \"$name\" is done but holds $n open ticket(s). Move them to the next phase, a new phase, or backlog: re-shape, never extend."
done <<EOF
$PHASES
EOF
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-check-phases.sh`
Expected: PASS, all cases.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(roadmap): the three host rules, and a skip that never reports clean

Rule 1 is the one that makes the untriaged set a single query. Rule 3
also enforces at most one open phase, since the current phase has to name
exactly one thing. Rule 4 is the circuit breaker: closing a phase forces
every unfinished ticket somewhere explicit."
```

---

### Task 5: sync-phases.sh

**Files:**
- Create: `plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh`
- Create: `scripts/test-sync-phases.sh`

**Interfaces:**
- Consumes: `parse_roadmap` (copied verbatim from `check-phases.sh`), `forge_milestone_list`, `forge_milestone_create`, `forge_milestone_close`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-sync-phases.sh` with the same stub shape as Task 4, plus these cases:

```bash
echo "== creating, closing and refusing =="
# create
printf '[]' > "$T/ms.json"
run --check
expect "--check reports a missing milestone" 1 "$rc"
contains "would create" "$out" "and says what it would do"
run
contains "POST" "$(cat "$REQLOG")" "the default mode creates it"

# close
printf '[{"id":1,"title":"A","state":"open"}]' > "$T/ms.json"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: done
plan: docs/plans/a.md
MD
run
contains "PATCH" "$(cat "$REQLOG")" "a done phase closes its milestone"

echo "== NEVER deletes =="
printf '[{"id":1,"title":"A","state":"open"},{"id":2,"title":"Ghost","state":"open"}]' > "$T/ms.json"
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: open
plan: docs/plans/a.md
MD
run
contains "Ghost" "$out" "an undeclared milestone is reported"
grep -q 'DELETE' "$REQLOG" && bad "and is never deleted" || ok "and is never deleted"

echo "== a malformed roadmap writes nothing =="
cat > "$T/docs/roadmap.md" <<'MD'
## Phase: A
state: nonsense
MD
: > "$REQLOG"; run
expect "a malformed roadmap refuses the run" 3 "$rc"
expect "and sends nothing" "" "$(cat "$REQLOG")"

echo "== the parser is byte-identical to check-phases.sh's =="
# Two copies of one function is the drift this repo keeps finding. They are copied rather than
# sourced because each asset must run standalone after forge-adapt installs it; the test is what
# keeps them equal.
extract() { awk '/^parse_roadmap\(\)/,/^}/' "$1"; }
if [ "$(extract "$SRC")" = "$(extract "$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh")" ]; then
  ok "the two parse_roadmap copies agree"
else
  bad "the two parse_roadmap copies agree"
fi
```

- [ ] **Step 2: Run and watch it fail**

Run: `bash scripts/test-sync-phases.sh`
Expected: FAIL, script does not exist.

- [ ] **Step 3: Implement**

Create `sync-phases.sh` with `# sync-phases-version: 1`, the same header/exit-code contract, `--check` and `FORGE_DRY_RUN` support, `parse_roadmap` copied verbatim from `check-phases.sh`, and this core:

```bash
# NEVER DELETES. A milestone that is not in the roadmap is reported and left alone, the same rule
# and the same reason as sync-labels.sh: it may be holding someone's tickets, and a sync that
# deletes what it does not recognise is a footgun aimed at other people's data.
while IFS=$'\t' read -r name state plan; do
  [ -n "$name" ] || continue
  ms_state="$(printf '%s' "$MS" | jq -r --arg t "$name" '.[] | select(.title == $t) | .state' | head -1)"
  want=open; [ "$state" = done ] && want=closed
  if [ -z "$ms_state" ]; then
    if [ "$MODE" = check ]; then echo "would create milestone \"$name\""; drift=$((drift+1))
    else forge_milestone_create "$name" "Phase from $ROADMAP" || exit 4; fi
  elif [ "$ms_state" != "$want" ] && [ "$want" = closed ]; then
    if [ "$MODE" = check ]; then echo "would close milestone \"$name\""; drift=$((drift+1))
    else forge_milestone_close "$name" || exit 4; fi
  fi
done <<EOF
$PHASES
EOF

printf '%s' "$MS" | jq -r '.[] | select(.state == "open") | .title' | while read -r t; do
  printf '%s\n' "$PHASES" | cut -f1 | grep -qxF "$t" \
    || echo "note: milestone \"$t\" is on the host but not in $ROADMAP. Left alone; nothing is ever deleted."
done
```

Reopening a closed milestone whose phase went back to `open` is deliberately NOT done: it is rare, it is a human decision, and `check-phases.sh` rule 3 reports it.

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-sync-phases.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(roadmap): sync-phases.sh, roadmap.md to milestones

Never deletes: an undeclared milestone is reported and left alone, the
same rule as sync-labels.sh. A malformed roadmap refuses the whole run
and writes nothing, because a partial sync is the drift it exists to end."
```

---

### Task 6: The /phase command

**Files:**
- Create: `plugins/forge-kit-roadmap/commands/phase.md`

**Interfaces:**
- Consumes: `check-phases.sh`, `sync-phases.sh`, the `roadmap-phases` skill.
- Produces: nothing.

- [ ] **Step 1: Write the command**

Create `plugins/forge-kit-roadmap/commands/phase.md`, marker `<!-- phase-version: 1 -->`, under 2000 words. Four verbs, each stating what it runs and what it must not do:

- `status`: run `check-phases.sh`; report the open phase, its plan, its open and closed tickets, and whether the plan's "Done looks like" is satisfied. Read-only, changes nothing.
- `plan <name>`: write or review the plan. **Read both inputs**: the phase's roadmap prose AND the tickets already in its milestone. State that the bucket is the evidence. Use the premortem prompt for Fails if.
- `close <name>`: compare the plan against the tickets actually created; **file tickets for skipped or missing work and prioritise them**; then close the milestone AND update `roadmap.md` to `done`. Both, or the phase is not closed. Record which of the three outcomes it was.
- `triage`: list tickets with no phase and backlog tickets worth promoting. Assign only what the user confirms.

State explicitly: **resolve the asset by SEARCH, never by `$CLAUDE_PLUGIN_ROOT`**, which is exported to hook processes and not to an agent's Bash. Use the pattern from `.claude/memory/shipped-asset-path-resolution.md`:

```bash
CP=scripts/check-phases.sh
[ -f "$CP" ] || CP=$(find ~/.claude/plugins -name check-phases.sh 2>/dev/null | head -1)
```

- [ ] **Step 2: Verify the size budget and index**

```bash
python3 scripts/update-component-index.py
bash scripts/check-component-size.sh
bash scripts/validate-plugins.sh
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(roadmap): the /phase command, four verbs

close is the interesting one: it files tickets for skipped work and
prioritises them, then closes the milestone AND the roadmap entry. Both,
or the phase is not closed."
```

---

### Task 7: The isolation guard

**Files:**
- Create: `scripts/check-group-isolation.sh`
- Create: `scripts/test-check-group-isolation.sh`
- Modify: `.github/workflows/validate.yml`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-check-group-isolation.sh`. It builds a throwaway `plugins/` tree and asserts:

```bash
echo "== the boundary =="
# A reference from another group is a violation.
mkdir -p "$T/plugins/forge-kit-governance/agents"
printf 'see check-phases.sh for details\n' > "$T/plugins/forge-kit-governance/agents/x.md"
run; expect "a reference from another group fails" 1 "$rc"
contains "check-phases.sh" "$out" "and names the identifier"

# The reverse direction is the declared dependency, not a violation.
mkdir -p "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/assets"
printf 'sources forge-lib.sh\n' > "$T/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"
rm "$T/plugins/forge-kit-governance/agents/x.md"
run; expect "the roadmap group may depend on forge-lib" 0 "$rc"

# The English word is not an identifier.
printf 'our roadmap for next year is long\n' > "$T/plugins/forge-kit-governance/agents/x.md"
run; expect "the word roadmap in prose is not a violation" 0 "$rc"

# forge-adapt is the installer and knows every component exists.
mkdir -p "$T/plugins/forge-kit-adapt/skills/adapt"
printf 'install check-phases.sh alongside the skill\n' > "$T/plugins/forge-kit-adapt/skills/adapt/SKILL.md"
run; expect "forge-adapt is exempt" 0 "$rc"
contains "installer" "$out" "and the exemption states its reason"
```

- [ ] **Step 2: Run and watch it fail**

Run: `bash scripts/test-check-group-isolation.sh`
Expected: FAIL, script does not exist.

- [ ] **Step 3: Implement**

```bash
#!/usr/bin/env bash
# check-group-isolation.sh: forge-kit-roadmap is optional, and this is what keeps that true.
#
# A boundary that is only stated survives until the first convenient reference. Rolling wave
# planning is ONE opinionated method; the rest of the kit is methodology-agnostic, so nothing
# outside the group may depend on it. The reverse direction is fine and expected: the group needs
# forge-lib.sh, which is the declared dependency.
#
# It keys on IDENTIFIERS, never on the English word "roadmap", which appears innocently across the
# kit. Exactly one exemption, and it carries its reason inline, the shape check-restatements.sh
# uses: an allowlist without a required reason is one that gets argued with.
set -uo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel)}"
IDS='forge-kit-roadmap|roadmap-phases|check-phases\.sh|sync-phases\.sh'
# forge-adapt is the INSTALLER: it names every component in the kit by definition, so a mention
# there is a catalogue entry rather than a dependency.
EXEMPT='plugins/forge-kit-adapt/'

violations=0
while IFS= read -r f; do
  case "$f" in
    "$ROOT"/plugins/forge-kit-roadmap/*) continue ;;
    *"$EXEMPT"*) continue ;;
  esac
  if grep -nE "$IDS" "$f" >/dev/null 2>&1; then
    grep -nE "$IDS" "$f" | while IFS= read -r hit; do
      printf '%s:%s\n' "${f#$ROOT/}" "$hit"
    done
    violations=$((violations + 1))
  fi
done < <(find "$ROOT/plugins" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.json' \))

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "check-group-isolation: forge-kit-roadmap is referenced from outside itself."
  echo "It is an OPTIONAL group and nothing else may depend on it. Remove the reference."
  echo "(forge-kit-adapt is exempt: it is the installer and names every component.)"
  exit 1
fi
exit 0
```

Note the `while ... | while` subshell trap: the inner `while` runs in a subshell, so increment `violations` in the outer loop only, as written above.

- [ ] **Step 4: Run the test and the guard against the real tree**

```bash
bash scripts/test-check-group-isolation.sh
bash scripts/check-group-isolation.sh
```
Expected: both pass.

- [ ] **Step 5: Wire all three new suites into CI and document them**

Add to `.github/workflows/validate.yml`, after the leak-guard steps:

```yaml
      # forge-kit-roadmap is an OPTIONAL group holding one opinionated planning method. These
      # three keep it working and keep it optional.
      - name: Roadmap phase guard tests
        run: bash scripts/test-check-phases.sh

      - name: Roadmap sync tests
        run: bash scripts/test-sync-phases.sh

      - name: Group isolation tests
        run: bash scripts/test-check-group-isolation.sh

      - name: forge-kit-roadmap is not referenced from outside itself
        run: bash scripts/check-group-isolation.sh
```

Update `CLAUDE.md`: the suite count (21 to 24), the validation checklist (add the three scripts), the shipped-executable list (two new bullets), and a Key Conventions paragraph stating that `forge-kit-roadmap` is optional, that nothing may depend on it, and that `ticket-gate` deliberately does not know what a phase is.

- [ ] **Step 6: Run every check and commit**

```bash
for c in scripts/validate-plugins.sh scripts/check-component-size.sh scripts/check-group-isolation.sh; do bash "$c" || echo "FAIL $c"; done
python3 scripts/update-component-index.py --check
git add -A
git commit -m "feat(roadmap): enforce the group's isolation rather than asserting it

A boundary that is only stated survives until the first convenient
reference. Keys on identifiers, never the English word roadmap. One
exemption with its reason inline: forge-adapt is the installer."
```

---

### Task 8: Bootstrap and dogfood

**Files:**
- Create: `docs/roadmap.md`
- Create: `docs/plans/<current-phase>.md`
- Modify: `.githooks/pre-push` (add the offline half of the guard)

**Interfaces:**
- Consumes: everything above.
- Produces: forge-kit's own roadmap.

- [ ] **Step 1: Propose the phase breakdown**

The guard cannot pass before a roadmap exists, so this is the one-time bootstrap. Draft `docs/roadmap.md` from the open backlog and **present it to the maintainer for correction before creating anything on the host.** The ordering is a judgment about the project, not about the design. Open tickets at the time of writing: #158, #150, #103, #129, #88, #127, #131, #134, #138, #140, #142, #143, #159.

- [ ] **Step 2: After approval, sync and assign**

```bash
bash plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh --check
bash plugins/forge-kit-roadmap/skills/roadmap-phases/assets/sync-phases.sh
# then assign every open issue to a milestone, confirming each with the maintainer
```

- [ ] **Step 3: Verify the guard passes on the real repo**

```bash
bash plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh
```
Expected: exit 0. If it exits 1, the roadmap or the assignment is wrong, not the guard.

- [ ] **Step 4: Wire the offline half into pre-push**

Add to `.githooks/pre-push` beside the leak guard, using `--offline` so a push never depends on the host being reachable:

```bash
cp="$ROOT/plugins/forge-kit-roadmap/skills/roadmap-phases/assets/check-phases.sh"
[ -f "$cp" ] && { bash "$cp" --offline || violations=$((violations + 1)); }
```

Extend `scripts/test-pre-push-hook.sh` with a case asserting a phase whose plan is missing blocks the push, and mutation-check it by removing the block.

- [ ] **Step 5: Commit and merge**

```bash
git add -A
git commit -m "feat(roadmap): forge-kit adopts its own roadmap

The first project to install forge-kit-roadmap is forge-kit. A phase
system nobody has run is prose, and every guard this repo runs on itself
found a real defect by being used rather than described."
git push origin develop
# watch Validate, then fast-forward main
```

---

## Self-Review

**Spec coverage.** Source of truth: Tasks 3 and 4. Roadmap format and four states: Tasks 1 and 3. Plan format and the premortem: Tasks 1 and 3. `forge_milestone_*`: Task 2. Four rules: Tasks 3 and 4. `sync-phases.sh` and never-delete: Task 5. Skill: Task 1. `/phase`: Task 6. Separate plugin group: Task 1. Isolation enforced: Task 7. Circuit breaker: rule 4 in Task 4, prose in Task 1. Bootstrap and dogfood: Task 8. Testing: every task. No gaps.

**Type consistency.** `parse_roadmap` emits `name<TAB>state<TAB>plan` in Tasks 3, 4 and 5. `forge_milestone_list` returns `{id, title, state}` in Tasks 2, 4 and 5. `forge_issue_milestone_list` returns `{number, milestone}` in Tasks 2 and 4. Consistent.

**Known duplication, deliberate and guarded.** `parse_roadmap` exists in both assets, because each must run standalone once `forge-adapt` copies it into a project's `scripts/`. Task 5 asserts the two copies are byte-identical, which is the same answer this repo gave for the component path set (#112) and the template-dir order (#77): where extraction is not available, a guard keeps the copies equal.
