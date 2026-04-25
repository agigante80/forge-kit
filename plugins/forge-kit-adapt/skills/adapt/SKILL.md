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

Focus keywords: `forge-adapt agents`, `forge-adapt skills`, `forge-adapt templates`

---

## How to run

Follow these phases in order. Do not skip ahead.

---

### Phase 0: Self-update check

Run before anything else.

```bash
CURRENT_SHA=$(git hash-object "${CLAUDE_SKILL_DIR}/SKILL.md" 2>/dev/null)
REMOTE_SHA=$(gh api repos/agigante80/forge-kit/contents/plugins/forge-kit-adapt/skills/adapt/SKILL.md \
  --jq '.sha' 2>/dev/null)
```

| Condition | Action |
|---|---|
| `REMOTE_SHA` empty | Skip silently — no network or gh not authenticated |
| `CURRENT_SHA == REMOTE_SHA` | Skip silently — up to date |
| `CURRENT_SHA != REMOTE_SHA` | Print update notice, then continue |

**Update notice:**
```
forge-adapt: a newer version is available.
To update:
  /plugin marketplace update forge-kit
  /reload-plugins
Continuing with current version.
```

Store `CURRENT_SHA` for the report header.

---

### Phase 1: Verify forge-kit is available

```bash
# Detect forge-kit root — works for plugin install (any scope) and manual clone
FORGE_KIT_DIR=""
# When installed via plugin marketplace, SKILL.md is inside the full forge-kit repo tree.
# ${CLAUDE_SKILL_DIR} resolves to the skill's directory; going up 4 levels reaches repo root.
PLUGIN_INFERRED_ROOT=$(realpath "${CLAUDE_SKILL_DIR}/../../../../" 2>/dev/null)
if [ -d "${PLUGIN_INFERRED_ROOT}/plugins/forge-kit-governance" ]; then
  FORGE_KIT_DIR="$PLUGIN_INFERRED_ROOT"
# Fall back to manual clone
elif [ -d ~/forge-kit/plugins ]; then
  FORGE_KIT_DIR=~/forge-kit
fi

# Diagnostic — reveals the actual resolved paths for debugging
echo "forge-adapt: CLAUDE_SKILL_DIR=${CLAUDE_SKILL_DIR}"
echo "forge-adapt: FORGE_KIT_DIR=${FORGE_KIT_DIR:-not found}"
```

If `FORGE_KIT_DIR` is empty, stop and print:
```
forge-kit not found. Options:

  Plugin marketplace (recommended):
    /plugin marketplace add agigante80/forge-kit
    /plugin install forge-kit-adapt@forge-kit
    /reload-plugins

  Manual clone:
    git clone https://github.com/agigante80/forge-kit ~/forge-kit

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

# Already-installed governance (will be excluded from recommendations)
ls .claude/agents/ 2>/dev/null
ls .claude/skills/ 2>/dev/null
ls .claude/commands/ 2>/dev/null

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
  Governance already installed: <list or "none">
```

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

For each component, read its first 15 lines to capture name, description, and purpose:
```bash
head -15 <path-to-component-file>
```

---

### Phase 4: Recommendations

Claude cross-references the project profile (Phase 2) against the catalogue (Phase 3).

**Exclude** from recommendations:
- Components already installed in `.claude/`
- Components clearly irrelevant to the detected stack or domain

**Flag separately** as "version check":
- Components present in `.claude/` but whose content differs from the forge-kit reference
  (diff first 30 lines to detect staleness)

Produce a **numbered recommendation table**:

```
## forge-adapt — <project name or repo>

Skill: forge-adapt @ <CURRENT_SHA[:7]>
forge-kit: <latest commit hash> (<date>)

Project: <project profile summary>

### Recommended to install and adapt
| # | Component | Type | Why this project needs it | Priority |
|---|-----------|------|--------------------------|----------|
| 1 | ticket-gate | agent | Quality gate — universal need | P0 |
| 2 | security-auditor | agent | Your <stack> surface has specific OWASP exposure | P0 |
| 3 | forge-adapt | skill | Keeps governance in sync with forge-kit | P1 |
...

### Already installed — version check
| # | Component | Status |
|---|-----------|--------|
| N | code-reviewer | ⚠ Differs from forge-kit reference — consider updating |
...

Which would you like to import and adapt?
Reply with numbers (e.g. "1 3 5"), "all", or "none".
```

Wait for user reply before continuing.

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
```

If no candidates survive the filter:
```
### Potential contributions to forge-kit
No generalisable candidates found — all project-only items appear domain-specific.
```

---

### Phase 7: Create contribution issues

For each accepted candidate, create a GitHub issue:

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

- **Never write files in Phase 0–4.** All writes happen in Phase 5 only, after user approval.
- **Phase 0 is read-only.** It checks for a newer version and notifies the user but never writes files. Updates are done by the user via `/plugin marketplace update forge-kit`.
- **Never auto-create contribution issues.** Always wait for explicit user confirmation in Phase 6.
- **ticket-gate is P0.** If it is missing, always list it first.
- **Adapt, do not pad.** Every customisation in Phase 5 must be traceable to a specific project characteristic from Phase 2. Do not add generic best-practice text that the original template already covers.
- **Respect existing installations.** Items already in `.claude/` are excluded from recommendations unless they differ from forge-kit (version check).
- **Focus mode**: if the invocation includes `agents`, `skills`, `commands`, or `templates`, restrict Phase 3–5 to that area only. Phase 6–7 always run in full.
