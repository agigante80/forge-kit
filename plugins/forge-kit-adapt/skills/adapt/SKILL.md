---
name: forge-adapt
description: >
  Analyse the current project and generate project-customised forge-kit agents,
  skills, and commands tailored to its stack, domain, and architecture. Recommends
  the most relevant components from forge-kit, gets user approval, then rewrites
  each template to fit the project specifically. Also surfaces project-specific
  components worth contributing back to forge-kit.
  Use for first-time setup OR ongoing maintenance ("am I up to date?").
  Backward-compatible: also triggered by "upgrade-audit".
---

# forge-adapt

Surveys the current project, matches it against the forge-kit library, and installs
project-customised governance components. Replaces generic `cp` commands with
Claude-written adaptations that know your stack.

## When to use

- "run forge-adapt"
- "adapt forge-kit to this project"
- "what governance is this project missing?"
- "suggest forge-kit components for this project"
- "run upgrade-audit" ← backward-compatible
- Any time you want to import, update, or contribute forge-kit governance
- "forge-adapt contributions" / "check forge-adapt contributions" ← contributions-only mode (Phase 6+)

Focus keywords: `forge-adapt agents`, `forge-adapt skills`, `forge-adapt templates`, `forge-adapt contributions`

---

## How to run

Follow these phases in order. Do not skip ahead.

**Contributions-only mode** — when the invocation includes `contributions` or `contribute`:
Skip Phases 2–5. Run Phase 0, then Phase 1, then this minimal setup, then jump to Phase 6:

```bash
# Minimal setup for contributions-only mode
CURRENT_REPO=$(git remote get-url origin 2>/dev/null \
  | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|')
```

Then proceed directly to Phase 6. Do not run Phases 2–5.

---

### Phase 0: Self-update check

Run before anything else.

```bash
CURRENT_SHA=$(git hash-object "${CLAUDE_SKILL_DIR}/SKILL.md" 2>/dev/null)
REMOTE_JSON=$(gh api repos/agigante80/forge-kit/contents/plugins/forge-kit-adapt/skills/adapt/SKILL.md \
  2>/dev/null)
REMOTE_SHA=$(echo "$REMOTE_JSON" | jq -r '.sha // empty' 2>/dev/null)
```

| Condition | Action |
|---|---|
| `REMOTE_SHA` empty | Skip silently — no network or gh not authenticated |
| `CURRENT_SHA == REMOTE_SHA` | Skip silently — up to date |
| `CURRENT_SHA != REMOTE_SHA` | Auto-update (see below) |

**Auto-update steps (run when `CURRENT_SHA != REMOTE_SHA`):**
```bash
echo "$REMOTE_JSON" | jq -r '.content' | base64 -d > "${CLAUDE_SKILL_DIR}/SKILL.md"
```

| Write outcome | Action |
|---|---|
| Succeeded (exit 0) | Print auto-update message (below), read `${CLAUDE_SKILL_DIR}/SKILL.md` in full, then continue from Phase 1 of the updated file — do not re-run Phase 0 |
| Failed (non-zero exit) | Print fallback notice (below) and continue with current version |

**Auto-update message (on success):**
```
forge-adapt: auto-updated to latest version.
Run /reload-plugins to activate the new version for all future sessions.
Continuing this run with the updated instructions.
```

**Fallback notice (on write failure):**
```
forge-adapt: a newer version is available (auto-update failed — cache may be read-only).
To update manually:
  /plugin marketplace update forge-kit
  /reload-plugins
Continuing with current version.
```

Store `CURRENT_SHA` for the report header.

---

### Phase 1: Verify forge-kit is available

```bash
# Detect the forge-kit template library.
# Marketplace installs: CLAUDE_SKILL_DIR resolves to the per-plugin cache dir;
# the full repo tree is NOT present there. Try the plugin-inferred root first
# (works for direct repo checkouts), then ~/forge-kit, then auto-clone.
FORGE_KIT_DIR=""
PLUGIN_INFERRED_ROOT=$(realpath "${CLAUDE_SKILL_DIR}/../../../../" 2>/dev/null)
if [ -d "${PLUGIN_INFERRED_ROOT}/plugins/forge-kit-governance" ]; then
  FORGE_KIT_DIR="$PLUGIN_INFERRED_ROOT"
elif [ -d ~/forge-kit/plugins ]; then
  FORGE_KIT_DIR=~/forge-kit
else
  echo "forge-adapt: cloning template library to ~/forge-kit (one-time setup — separate from the skill update in Phase 0)..."
  git clone https://github.com/agigante80/forge-kit ~/forge-kit --depth 1 --quiet \
    && FORGE_KIT_DIR=~/forge-kit
fi

# Diagnostic — reveals the actual resolved paths for debugging
echo "forge-adapt: CLAUDE_SKILL_DIR=${CLAUDE_SKILL_DIR}"
echo "forge-adapt: FORGE_KIT_DIR=${FORGE_KIT_DIR:-not found}"
```

If `FORGE_KIT_DIR` is empty, stop and print:
```
forge-adapt: could not clone the template library automatically.
Run manually:
  git clone https://github.com/agigante80/forge-kit ~/forge-kit

Note: to update the skill itself, use:
  /plugin marketplace update forge-kit
  /reload-plugins

Then re-run forge-adapt.
```

Show recent commits so the user knows which version they are running against:
```bash
git -C "$FORGE_KIT_DIR" log --oneline -5
```

---

### Phase 2: Project analysis

Read each of the following. Claude synthesises — do not just list output.

```bash
# Stack detection
cat package.json 2>/dev/null | head -50
cat pyproject.toml requirements.txt 2>/dev/null | head -30
cat go.mod Cargo.toml pom.xml 2>/dev/null | head -30

# Project intent and constraints
cat CLAUDE.md 2>/dev/null

# Already-installed governance — read name + description for exact matching and overlap detection
echo "=== Installed agents ==="
for f in .claude/agents/*.md; do
  if [ -f "$f" ]; then
    n=$(grep -m1 "^name:" "$f" | sed "s/name: *//")
    d=$(grep -m1 "^description:" "$f" | sed "s/description: *//")
    echo "  $n | $d"
  fi
done

echo "=== Installed skills ==="
for f in .claude/skills/*/SKILL.md; do
  if [ -f "$f" ]; then
    n=$(grep -m1 "^name:" "$f" | sed "s/name: *//")
    d=$(grep -m1 "^description:" "$f" | sed "s/description: *//")
    echo "  $n | $d"
  fi
done

echo "=== Installed commands ==="
for f in .claude/commands/*.md; do
  if [ -f "$f" ]; then
    n=$(grep -m1 "^name:" "$f" | sed "s/name: *//")
    d=$(grep -m1 "^description:" "$f" | sed "s/description: *//")
    echo "  $n | $d"
  fi
done

echo "=== Coding standards ==="
STANDARDS_STATE="missing"
[ -f "docs/coding-standards.md" ] && STANDARDS_STATE="file-exists"
if [ "$STANDARDS_STATE" = "file-exists" ]; then
  grep -qi "coding.standards\|see docs/coding-standards" CLAUDE.md 2>/dev/null \
    && STANDARDS_STATE="proper" || STANDARDS_STATE="file-no-reference"
fi
# Detect inline standards in CLAUDE.md (more than a reference line)
if grep -qi "naming convention\|error handling\|camelCase\|PascalCase\|docstring\|import order" \
    CLAUDE.md 2>/dev/null; then
  [ "$STANDARDS_STATE" = "proper" ] && STANDARDS_STATE="inline-and-proper" \
    || STANDARDS_STATE="inline"
fi
# Detect scattered standards files
for f in CONTRIBUTING.md STYLE_GUIDE.md STYLE-GUIDE.md CODE_STYLE.md styleguide.md; do
  [ -f "$f" ] && { STANDARDS_STATE="${STANDARDS_STATE}+scattered"; break; }
done
echo "  standards state: $STANDARDS_STATE"

echo "=== Issue templates ==="
found_templates=0
for f in .github/ISSUE_TEMPLATE/*.yml; do
  if [ -f "$f" ]; then
    found_templates=1
    name=$(basename "$f" .yml)
    version=$(grep -oP 'template-version: \K\d+' "$f" 2>/dev/null | head -1)
    ids=$(grep -oP '(?<=    id: )\S+' "$f" 2>/dev/null | tr '\n' ' ')
    echo "  $name | v${version:-unknown} | ids: $ids"
  fi
done
[ "$found_templates" -eq 0 ] && echo "  none found"

# Git remote (used later for {{GITHUB_REPO}} replacement)
CURRENT_REPO=$(git remote get-url origin 2>/dev/null \
  | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|')

# Source structure sample (understand domain and patterns)
find . \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) \
  | grep -v node_modules | grep -v ".claude" | grep -v dist | head -20
```

Build and print a **project profile** (3–5 lines):

```
Project profile:
  Language/framework: <detected>
  Domain: <what the project does and for whom>
  Security surface: <auth method, external APIs, data sensitivity>
  Architecture: <monorepo/microservices/monolith/REST API/etc.>
  Governance already installed: <component names from frontmatter, comma-separated, or "none">
  Coding standards: <proper / missing / inline / scattered / incomplete — one-line reason>
  Templates: <N of 5 present, e.g. "3 of 5">; missing: <comma-separated list or "none">; versions: <e.g. "feature v3, bug v4, security v4">
```

Note: each installed component is listed as `name | description`. Use the `name` field for
exact-match exclusion in Phase 4. Use the `description` field to detect semantic overlap with
forge-kit components that have a different name but similar purpose.

Store this profile — it is used in Phase 5 to drive adaptation.

---

### Phase 3: Catalogue forge-kit

Read all available components:

```bash
for plugin_dir in $FORGE_KIT_DIR/plugins/*/; do
  echo "=== $(basename $plugin_dir) ==="
  ls "$plugin_dir/agents/"   2>/dev/null | sed 's/^/  agent: /'
  ls "$plugin_dir/commands/" 2>/dev/null | sed 's/^/  command: /'
  ls "$plugin_dir/skills/"   2>/dev/null | sed 's/^/  skill: /'
done
```

For each component, read its first 15 lines and record:
- The `name:` field from the YAML frontmatter — this is the canonical match key used in Phase 4
- The `description:` field — used for recommendation rationale

```bash
head -15 <path-to-component-file>
```

Also catalogue forge-kit's issue templates (the governance-layer reference):

```bash
echo "=== forge-kit issue templates (reference) ==="
FORGE_KIT_TEMPLATE_VERSION=$(grep -oP 'template-version: \K\d+' \
  "$FORGE_KIT_DIR/.github/ISSUE_TEMPLATE/feature.yml" 2>/dev/null | head -1)

for f in "$FORGE_KIT_DIR"/.github/ISSUE_TEMPLATE/*.yml; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .yml)
  [ "$name" = "contribution" ] && continue  # contribution.yml is forge-kit-specific
  ids=$(grep -oP '(?<=    id: )\S+' "$f" 2>/dev/null | tr '\n' ' ')
  echo "  $name | v$FORGE_KIT_TEMPLATE_VERSION | ids: $ids"
done
```

Store `$FORGE_KIT_TEMPLATE_VERSION` and the canonical section-ID list per template for use
in the Phase 4 diff.

---

### Phase 4: Recommendations

Claude cross-references the project profile (Phase 2) against the catalogue (Phase 3).

**Coding standards priority rule:** If the project profile shows coding standards as anything
other than `proper`, always recommend `coding-standards-auditor` at **P0** regardless of
what other components are selected. It writes `docs/coding-standards.md`, removes inline
standards from CLAUDE.md, and consolidates scattered files automatically.

**Exclude** from recommendations:
- Components whose `name:` field matches a name in "Governance already installed" from the Phase 2 profile
- Components clearly irrelevant to the detected stack or domain

Matching is by `name:` field, not by filename or directory name. Example: if `.claude/skills/forge-adapt/SKILL.md`
has `name: forge-adapt` and the forge-kit catalogue lists a component with `name: forge-adapt`,
they are the same component — exclude it from recommendations.

**Flag separately** as "potential overlap" (do NOT exclude automatically):
- Forge-kit components that are not an exact-name match but whose purpose substantially overlaps
  with a local component's `description:` field — e.g., a local `pr-reviewer` agent that does
  code quality review overlaps with forge-kit's `code-reviewer`. List these in the overlap table
  so the user can decide whether to install alongside, replace, or skip.
- Use judgement: overlap means the same governance concern is already addressed, not just that
  both components touch code. A linter and a code-reviewer are not overlapping.

**Flag separately** as "version check":
- Components present in `.claude/` but whose content differs from the forge-kit reference
  (diff first 30 lines to detect staleness)

Produce a **numbered recommendation table**:

**Formatting rules (strictly enforced):**
- `Why this project needs it` cell: ≤ 60 characters — one tight phrase, not a sentence.
  Pick the single most important signal. Never write a full explanation in the cell.
  Good: `Inline standards in CLAUDE.md — extract automatically`
  Bad: `P0 — coding standards state is inline. CLAUDE.md contains extensive naming conventions…`
- `Already installed` section: list format, not a table. ≤ 80 chars per line.

```
## forge-adapt — <project name or repo>

Skill: forge-adapt @ <CURRENT_SHA[:7]>
forge-kit: <latest commit hash> (<date>)

Project: <project profile summary>

### Recommended to install and adapt
| # | Component | Type | Why this project needs it | Priority |
|---|-----------|------|--------------------------|----------|
| 1 | ticket-gate | agent | Quality gate — universal need | P0 |
| 2 | security-auditor | agent | JWT + Stripe surface — OWASP exposure | P0 |
| 3 | forge-adapt | skill | Keeps governance in sync with forge-kit | P1 |
...

### Already installed — version check
Include a number to update. Numbers continue the sequence above.

⚠ N · <component> — <what changed, ≤ 80 chars>
...


### Potentially overlapping — review before installing
| # | Forge-kit component | Local component | Why they may overlap |
|---|---------------------|-----------------|----------------------|
| P1 | code-reviewer | pr-reviewer | Both address code quality review |
...
(omit this table entirely if no overlaps are detected)
Overlap items use the prefix P (P1, P2, …) to avoid ambiguity with the numbered recommendation list.

### Issue template audit

forge-kit reference: v<FORGE_KIT_TEMPLATE_VERSION>

For each of the 5 forge-kit templates (`feature`, `bug`, `security`, `infrastructure`,
`design`), compare against what the project has:
- **Missing** (❌): file not in `.github/ISSUE_TEMPLATE/`
- **Outdated** (⚠️): `template-version` < `FORGE_KIT_TEMPLATE_VERSION`
- **Incomplete** (🔧): version matches but one or more forge-kit section IDs absent
- **Current** (✅): version matches and all IDs present — do not surface as action item

Produce a T-prefixed table for templates needing action only:

| # | Template | Status | What's needed |
|---|---|---|---|
| T1 | feature.yml | ⚠️ v3 outdated | upgrade to v4; missing: codebase_context |
| T2 | security.yml | ❌ missing | install from forge-kit |
| T3 | design.yml | 🔧 incomplete | add section: codebase_context |

Already current (no action needed): <list or "none">

(Omit the table entirely if all 5 templates are current.)

Which would you like to import and adapt?
Reply with numbers for recommended items (e.g. "1 3 5"), "all", or "none".
To also install overlapping items, include their P-prefixed numbers (e.g. "1 3 P1").
To install/upgrade templates, include their T-prefixed numbers (e.g. "1 3 T1 T2") or "T-all".
```

Wait for user reply before continuing.
- If the user replied with numbers (or "all"): proceed to Phase 5.
- If the user replied "none": skip Phase 5 and proceed immediately to Phase 6.

---

### Phase 5: Adapt and install

For each item the user approved:

**5a. Read the generic template**
```bash
cat $FORGE_KIT_DIR/plugins/<group>/<type>/<name>.md
# or for skills:
cat $FORGE_KIT_DIR/plugins/<group>/skills/<name>/SKILL.md
```

**5b. Claude generates an adapted version**

You have in context:
- The full generic template (from 5a)
- The project profile (from Phase 2)

Rewrite the template to be project-specific. Adaptation rules:

- **Replace generic stack references** with the project's actual stack.
  Example: "check for SQL injection" → "check for Prisma `$queryRaw` / `$executeRaw` injection"
- **Add project-specific criteria** to scoring sections and checklists.
  Example: if the project uses JWT, add JWT expiry and algorithm checks to the security agent.
- **Inject domain context** where the template mentions "the project" or "this system" generically.
- **Keep the structure intact** — do not reorder phases, scoring logic, or tool lists.
- **Only customise where it adds value.** Do not pad with boilerplate or restate the generic template.

**5c. Write the adapted file**

Use the Write tool to write the adapted content:
- Agent → `.claude/agents/<name>.md`
- Skill  → `.claude/skills/<name>/SKILL.md`
- Command → `.claude/commands/<name>.md`

**5d. Replace placeholder**
```bash
sed -i "s|{{GITHUB_REPO}}|$CURRENT_REPO|g" <written-file-path>
```

**5e. Confirm**
Print: `✓ <name> (<type>) — installed and adapted for <detected stack>`

---

**For T-prefixed items (issue templates):**

**5a-T. Read the forge-kit reference template**
```bash
cat "$FORGE_KIT_DIR/.github/ISSUE_TEMPLATE/<name>.yml"
```

**5b-T. Read the existing project template (if present)**
```bash
cat ".github/ISSUE_TEMPLATE/<name>.yml" 2>/dev/null
```

**5c-T. Generate the target file**

You have in context:
- The forge-kit reference template (from 5a-T)
- The existing project template, if any (from 5b-T)
- The project profile (from Phase 2): stack, domain, source structure

Rules:
- **If missing**: use the forge-kit template as the base. Adapt the `areas` dropdown options
  to reflect the project's actual source structure (e.g., if Phase 2 found `packages/api/`,
  `packages/web/`, use those as options rather than the generic forge-kit list). Keep all
  other sections verbatim.
- **If outdated or incomplete**: produce a merged file — preserve ALL existing content
  verbatim (custom labels, options, placeholder text, values), add missing sections in the
  same relative position as they appear in the forge-kit reference, update the
  `template-version` marker to `$FORGE_KIT_TEMPLATE_VERSION`.

**5d-T. Write the file**
```bash
mkdir -p .github/ISSUE_TEMPLATE
```
Use the Write tool to write the file to `.github/ISSUE_TEMPLATE/<name>.yml`.

**5e-T. Confirm**
Print: `✓ <name>.yml — <action>` where action is one of:
- `installed (adapted areas for <detected stack>)`
- `upgraded v<old>→v<new>`
- `patched: <list of added section IDs>`

After confirming all approved components and templates, proceed immediately to Phase 6.

---

### Phase 6: Contribution candidates

After Phase 5, scan for project-only components that could benefit the forge-kit community.

```bash
# Agents in project but not in any forge-kit plugin:
comm -23 \
  <(ls .claude/agents/ 2>/dev/null | sort) \
  <(ls $FORGE_KIT_DIR/plugins/*/agents/ 2>/dev/null | xargs -n1 basename | sort -u)

# Commands:
comm -23 \
  <(ls .claude/commands/ 2>/dev/null | sort) \
  <(ls $FORGE_KIT_DIR/plugins/*/commands/ 2>/dev/null | xargs -n1 basename | sort -u)

# Skills (exclude forge-adapt itself):
comm -23 \
  <(ls .claude/skills/ 2>/dev/null | grep -v "^forge-adapt$" | sort) \
  <(ls $FORGE_KIT_DIR/plugins/*/skills/ 2>/dev/null | xargs -n1 basename | sort -u)
```

**Generalisation filter** — skip candidates that:
- Have filenames containing the project's product/brand name (check CLAUDE.md)
- Contain hardcoded repo names, internal endpoints, or product-specific terminology in their first 20 lines
- Have filenames matching known domain-specific patterns: `prisma-schema-guardian`,
  `safety-logic-reviewer`, `mobile-*-reviewer`, `mobile-*-engineer`, `e2e-test-engineer`,
  `help-center-reviewer`, `seo-reviewer`, `wireframe-gate`, `roadmap-gate`,
  `terminology-checker`, `github-project-manager`

For surviving candidates, read their description and present:

```
### Potential contributions to forge-kit

| # | Component | Type | Description |
|---|-----------|------|-------------|
| 8 | payment-auditor | agent | PCI-DSS compliance checker |
...

Reply with numbers to open contribution issues, or "none" to skip.
Wait for user reply, then:
- If the user replied with numbers: proceed to Phase 7 for each accepted candidate.
- If the user replied "none": skip Phase 7 and proceed immediately to Phase 8.
```

If no candidates survive the filter:
```
### Potential contributions to forge-kit
No generalisable candidates found — all project-only items appear domain-specific.
```
Proceed immediately to Phase 8.

---

### Phase 7: Create contribution issues

For each accepted candidate, **check for an existing issue before creating**:

```bash
gh issue list \
  --repo agigante80/forge-kit \
  --label "contribution" \
  --state all \
  --search "Contribution: <name>" \
  --json number,title,state \
  --jq '.[] | select(.title | test("Contribution: <name>"))'
```

| Result | Action |
|--------|--------|
| Open issue found | Skip creation. Print: `⟳ <name> — contribution issue already open (#<N>)` |
| Closed issue found | Print: `⚠ <name> — contribution issue was previously closed (#<N>). Create a new one? (yes/no)`. Wait for reply. |
| No match | Proceed to create the issue below. |

Create the issue:

```bash
gh issue create \
  --repo agigante80/forge-kit \
  --title "Contribution: <name> (<type>)" \
  --label "contribution" \
  --body "$(cat <<'EOF'
### Category
<type: agent / command / skill>

### What it does
<description from the file>

### Why it would be useful across projects
<rationale inferred from file content>

### Source project
<$CURRENT_REPO or "private">

### Content
\`\`\`markdown
<full file content>
\`\`\`

### Checklist
- [ ] Generalise any hardcoded project references
- [ ] Add to forge-kit README component table
- [ ] Update docs/guides/ if needed
- [ ] Verify no sensitive data in content
EOF
)"
```

Print the issue URL after each creation.

After creating all issues, proceed immediately to Phase 8.

---

### Phase 8: Summary

```
## forge-adapt complete

Installed and adapted <N> component(s):
  <name> (<type>) — <one-line summary of what was customised>
  ...

<if any outdated items were flagged in Phase 4 but not updated>
  Note: <N> installed component(s) differ from forge-kit reference.
  Run forge-adapt again and select those items to refresh them.

Next steps:
  1. Review adapted files in .claude/ — adjust anything that does not fit
  2. Commit: git add .claude/ && git commit -m 'chore: install forge-kit governance'
  3. File a test issue and run /gate-ticket <N> to verify the ticket gate works
  4. Run forge-adapt periodically to stay current with forge-kit improvements
```

---

## Rules

- **Never write files in Phase 1–4.** All governance writes happen in Phase 5 only, after user approval. Phase 0 is the sole exception — it may write its own SKILL.md.
- **Phase 0 auto-updates.** When a newer version is available it writes the updated SKILL.md to `${CLAUDE_SKILL_DIR}/SKILL.md` and continues from Phase 1 of the new file. If the write fails it falls back to a manual notice. The user should run `/reload-plugins` after an auto-update to activate the new version for all future sessions.
- **Never auto-create contribution issues.** Always wait for explicit user confirmation in Phase 6.
- **ticket-gate is P0.** If it is missing, always list it first.
- **Adapt, do not pad.** Every customisation in Phase 5 must be traceable to a specific project characteristic from Phase 2. Do not add generic best-practice text that the original template already covers.
- **Respect existing installations.** Items already in `.claude/` are excluded from recommendations unless they differ from forge-kit (version check).
- **Focus mode**: if the invocation includes `agents`, `skills`, `commands`, or `templates`, restrict Phase 3–5 to that area only. Phase 6–7 always run in full.
- **Contributions-only mode**: if the invocation includes `contributions` or `contribute`, run Phase 0 + Phase 1 + minimal `CURRENT_REPO` setup, then jump directly to Phase 6. Skip Phases 2–5 entirely.
- **Duplicate issue guard**: Phase 7 always checks for an existing open or closed contribution issue before creating a new one. Never create a duplicate open issue.
- **`contribution.yml` is excluded from the template audit** — it is forge-kit-specific and not applicable to target projects.
- **Templates are identified by filename**, not by a frontmatter `name:` field. The T-prefix in Phase 4 maps directly to the filename.
- **For template upgrades, all existing content is preserved verbatim.** Only add missing sections. Never remove or rewrite content the project author wrote.
- **Template `areas` dropdown is the primary adaptation target** when installing a fresh (missing) template. Infer options from the project's actual source package structure detected in Phase 2.
- **Template files go to `.github/ISSUE_TEMPLATE/` in the project root**, not to `.claude/`.
