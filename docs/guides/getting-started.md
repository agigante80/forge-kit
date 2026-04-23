# Getting Started

Add ai-projectforge governance to a new or existing project in 5 minutes.

## Prerequisites

- Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
- GitHub CLI installed (`gh`) and authenticated (`gh auth login`)
- Git repository with a GitHub remote

## Option A: Bootstrap an existing project

From inside your project directory:

```bash
# Clone ai-projectforge (if you haven't already)
git clone https://github.com/agigante80/ai-projectforge ~/[redacted]/ai-projectforge

# Run the bootstrap script
~/[redacted]/ai-projectforge/bootstrap.sh
```

The script will:
1. Ask for your GitHub owner/repo (e.g. `myorg/my-project`)
2. Copy `.claude/`, `.github/ISSUE_TEMPLATE/`, and `CLAUDE.md.template` into your project
3. Replace `{{GITHUB_REPO}}` and `{{PROJECT_NAME}}` placeholders
4. Create GitHub labels from `.github/labels.yml`

## Option B: Use as a GitHub template

1. Go to `https://github.com/agigante80/ai-projectforge`
2. Click **"Use this template"** -> **"Create a new repository"**
3. Clone your new repo
4. Run `./bootstrap.sh` to fill in placeholders and create labels

## After bootstrapping

### 1. Fill in CLAUDE.md

Open `CLAUDE.md` and replace all `{{TODO: ...}}` sections with your project-specific content:
- What the project does and who uses it
- Tech stack (languages, frameworks, databases)
- Setup and test commands
- Architecture notes and service boundaries
- Branch strategy

### 2. Customize ticket-gate.md (optional)

If your project has domain-specific agents (e.g., a schema reviewer, mobile reviewer), add them to the dynamic agent table in `.claude/agents/ticket-gate.md`.

### 3. File your first issue and run the gate

```bash
# File a test issue using the feature template on GitHub
# Then run the gate:
# /gate-ticket <issue-number>
```

The gate will auto-synthesise missing GWT scenarios and test specs if the template version
is outdated. No manual upgrades needed.

### 4. Run upgrade-audit periodically

Keep your project in sync with the ai-projectforge reference:
```bash
# Pull latest ai-projectforge
git -C ~/[redacted]/ai-projectforge pull

# Run the audit in your project
# (use /upgrade-audit or mention "run upgrade audit" to Claude Code)
```

See `docs/guides/upgrade-existing.md` for details on the upgrade-audit workflow.
