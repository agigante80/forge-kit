---
name: forge-adapt
description: >
  Analyse the current project and recommend the forge-kit components that fit it -
  subagents, skills, commands, and hooks - grouped by type with a per-item reason,
  then adapt and install the ones you pick (rewritten for your stack, not copy-pasted).
  Use for first-time setup OR ongoing maintenance ("am I up to date?", "what governance
  am I missing?"). Secondary modes: "refresh"/"drift" reports which installed components are
  behind forge-kit (version-marker based) and "refresh <name>" deep-compares and updates one
  while preserving project adaptation; "forge-adapt contributions" surfaces project-only
  components worth contributing back; "forge-adapt templates" audits issue templates and can
  install the template lockstep guard + canonical ticket-standards doc.
  Backward-compatible: also triggered by "upgrade-audit".
---

<!-- forge-adapt-version: 26 -->

# forge-adapt

Analyse this project, recommend the forge-kit components that fit it, and install the ones
you pick - each rewritten for your stack instead of copy-pasted. The dialogue mirrors a
recommender: a short project profile, then the best one or two components per category, each
with a one-line reason. Nothing is written until you choose.

## When to use

- "run forge-adapt" / "adapt forge-kit to this project"
- "what governance is this project missing?" / "suggest forge-kit components"
- "am I up to date?" / "run upgrade-audit" (backward-compatible)
- "forge-adapt contributions" - contribution-surfacing mode (secondary)
- "forge-adapt templates" - issue-template audit + template-governance install (secondary)

Focus a single category by naming it: "forge-adapt skills", "forge-adapt hooks", etc.

---

## The core flow

Three steps the user sees: **Analyze -> Recommend -> Install**. Keep it clean - do not narrate
the setup. Run Setup quietly, then lead with the recommendation.

**Pre-flight (fail fast): is this project forge-kit itself?** forge-adapt installs components INTO a
target project's `.claude/`; the forge-kit repo is the source library, not a target. Running it here
would copy the library into its own `.claude/`, a no-op-shaped mistake. Check the current directory
BEFORE Setup (it needs nothing from Setup):

```bash
if [ -f .claude-plugin/marketplace.json ] && [ -d plugins/forge-kit-adapt ]; then
  echo "forge-adapt: this is the forge-kit source repo, not a target project - it IS the component"
  echo "  library. Run forge-adapt from the project you want to adapt, not from forge-kit itself."
fi
```

If it matches, STOP here: do not run Setup, catalogue, or the rest of the flow. Explain and ask the
user to re-run from their target project. Only continue if the user explicitly says they intend to
adapt forge-kit itself. (This structural check matches a fork too, which is correct: a fork is still
the source, not a target.)

### Setup (quiet - do not print unless something needs the user)

**S1. Self-update check.** Compare this skill against the forge-kit remote; auto-update silently
when behind. Only print something if an update was applied or failed.

```bash
CURRENT_SHA=$(git hash-object "${CLAUDE_SKILL_DIR}/SKILL.md" 2>/dev/null)
REMOTE_JSON=$(gh api repos/agigante80/forge-kit/contents/plugins/forge-kit-adapt/skills/adapt/SKILL.md 2>/dev/null)
REMOTE_SHA=$(echo "$REMOTE_JSON" | jq -r '.sha // empty' 2>/dev/null)
```

| Condition | Action |
|---|---|
| `REMOTE_SHA` empty | Skip silently (offline / gh not authed) |
| `CURRENT_SHA == REMOTE_SHA` | Skip silently (up to date) |
| `CURRENT_SHA != REMOTE_SHA` | `echo "$REMOTE_JSON" \| jq -r '.content' \| base64 -d > "${CLAUDE_SKILL_DIR}/SKILL.md"`, then read the updated file and continue from its Setup. On success print one line: `forge-adapt: updated to latest - run /reload-plugins to persist.` On write failure print: `forge-adapt: a newer version exists but auto-update failed; run /plugin marketplace update forge-kit && /reload-plugins.` |

**S2. Locate AND refresh the forge-kit library** (marketplace checkout, then `~/forge-kit`, then clone),
and separately determine whether the governance plugin is enabled. The skill self-updates in S1, but
the component library is a SEPARATE checkout - if it is stale, new components (e.g. a newly added
hook) are invisible to the catalogue and file-copy installs fail on missing sources. Always
refresh it, INCLUDING the marketplace checkout (Claude Code does not auto-pull it between manual
`/plugin marketplace update` runs).

```bash
FORGE_KIT_DIR=""; FORGE_KIT_SRC=""
# The marketplace keeps a full checkout of the repo here. Note this is NOT the plugin cache:
# `~/.claude/plugins/cache/<marketplace>/<plugin>/<sha>/` holds only the installed plugin's own
# files, never a `plugins/` tree, so it can never serve as the component library.
MARKETPLACE_CHECKOUT=~/.claude/plugins/marketplaces/forge-kit
if [ -d "$MARKETPLACE_CHECKOUT/plugins" ]; then
  FORGE_KIT_DIR="$MARKETPLACE_CHECKOUT"; FORGE_KIT_SRC="marketplace"
elif [ -d ~/forge-kit/plugins ]; then
  FORGE_KIT_DIR=~/forge-kit; FORGE_KIT_SRC="clone"
else
  git clone https://github.com/agigante80/forge-kit ~/forge-kit --depth 1 --quiet && { FORGE_KIT_DIR=~/forge-kit; FORGE_KIT_SRC="clone"; }
fi

# Refresh the library so the catalogue AND file-copy installs reflect the latest forge-kit.
# BOTH sources are plain git checkouts of the repo tracking origin/main, so fetch + reset
# --hard makes either current. The marketplace checkout is NOT auto-pulled by Claude Code
# between manual `/plugin marketplace update` runs, and it pins no SHA (known_marketplaces.json
# holds only source + installLocation), so resetting it forward is safe and lands exactly what
# an update would. Refreshing it here is what stops the library drifting - a stale checkout
# both mis-catalogues versions AND is missing the scripts/ + docs/ files a governance install
# copies, which would hard-fail the install.
if git -C "$FORGE_KIT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$FORGE_KIT_DIR" fetch --depth 1 origin --quiet 2>/dev/null \
    && git -C "$FORGE_KIT_DIR" reset --hard origin/HEAD --quiet 2>/dev/null \
    || { if [ "$FORGE_KIT_SRC" = "marketplace" ]; then fix="/plugin marketplace update forge-kit"; else fix="git -C $FORGE_KIT_DIR pull"; fi; \
         echo "forge-adapt: could not refresh the $FORGE_KIT_SRC library at $FORGE_KIT_DIR; it may be behind (fix: $fix)."; }
else
  echo "forge-adapt: library at $FORGE_KIT_DIR is not a git checkout; cannot auto-refresh (catalogue may be behind)."
fi
echo "forge-adapt: library at $(git -C "$FORGE_KIT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?') ($FORGE_KIT_SRC)"

# SEPARATE QUESTION, do not conflate: where the library lives says NOTHING about which plugin
# groups the user enabled. A plugin's hooks/hooks.json is live only when THAT plugin is installed.
GOVERNANCE_PLUGIN_ACTIVE=no
if [ -d ~/.claude/plugins/cache/forge-kit/forge-kit-governance ] \
   || grep -q 'forge-kit-governance@forge-kit' ~/.claude/plugins/installed_plugins.json 2>/dev/null; then
  GOVERNANCE_PLUGIN_ACTIVE=yes
fi
```

If `FORGE_KIT_DIR` is still empty, stop and tell the user to clone it manually
(`git clone https://github.com/agigante80/forge-kit ~/forge-kit`) and re-run.

**S3. Catalogue forge-kit** (the menu of what can be recommended). For every component capture its
type, name, and `<name>-version` marker below. The marker is the catalogue side of the Version
status table (Step 2); capture it HERE so that table has a real data source. Use the SAME whole-file,
name-scoped grep as the local capture in Step 1, and NEVER limit the scan to the first N lines: the
marker often sits below long frontmatter (e.g. line 30 in `ticket-gate.md`, line 26 in
`health-check.md`), so a head-limited read silently reports "no marker" and defeats drift detection.

```bash
cat_row() {  # ${1} = type label, ${2} = file, ${3} = match-name
  # BRACE the positional params. Bare $1/$2/$3 are clobbered by Claude Code's slash-command
  # argument substitution when forge-adapt is invoked WITH an arg (e.g. `/forge-kit-adapt:adapt
  # skills`, `... templates`, `... contributions`): the args get spliced into $1/$2/$3 before bash
  # runs, corrupting this catalogue and silently breaking drift detection. Braced ${N} is left
  # untouched by that substitution and is identical to $N inside the function.
  # ver_of: identical to the local capture in Step 1. The `(?:<!--\s*|#\s*)` lead-in anchors the
  # marker to its comment so a match-name that is a suffix of a longer marker (e.g. "adapt" inside
  # "forge-adapt-version") cannot match by substring; `\K` then captures only the digits.
  v=$(grep -oP -- "(?:<!--\s*|#\s*)${3}-version:\s*\K\d+" "${2}" | head -1)
  echo "${1}: ${3} | v${v:-none}"
}
shopt -s nullglob   # a group with no hooks/agents must not iterate a literal glob and leave exit 1
for dir in "$FORGE_KIT_DIR"/plugins/*/; do
  for f in "$dir"agents/*.md;      do [ -f "$f" ] && cat_row subagent "$f" "$(basename "$f" .md)"; done
  for f in "$dir"commands/*.md;    do [ -f "$f" ] && cat_row command  "$f" "$(basename "$f" .md)"; done
  for f in "$dir"skills/*/SKILL.md; do [ -f "$f" ] && cat_row skill  "$f" "$(basename "$(dirname "$f")")"; done
  for f in "$dir"hooks/*.py "$dir"hooks/*.sh; do [ -f "$f" ] && { n=$(basename "$f"); cat_row hook "$f" "${n%.*}"; }; done
done
true   # the catalogue is read-only: never surface a non-zero exit as "Failed to run"
```

Then read each component's frontmatter `description:` for the "why" column - do this by reading the
file, NOT with a one-line grep, because many components write `description: >` as a multi-line block
scalar that a single grep captures as an empty ">".

forge-adapt's own row is never consumed (it self-updates in S1 and is never recommended into a
target project), so ignore it regardless of what its marker reads.

### Step 1: Analyze the project

Detect stack, domain, and what is already installed. Synthesise - do not dump raw output.

**Every probe here is read-only and MUST exit 0.** A missing optional path is a normal finding, not
a failure. If a probe block ends on a non-zero status it surfaces as an alarming "Failed to run"
even though the analysis succeeded. Guard accordingly: end a multi-command probe with a trailing
`true`, and never let an absent path fail the block (a Forgejo-only repo has no `.github/workflows`,
so `ls .forgejo/workflows .github/workflows` exits 2 - append `2>/dev/null || true`, or probe each
path separately with `[ -d ... ]`).

```bash
cat package.json 2>/dev/null | head -50
cat pyproject.toml requirements.txt go.mod Cargo.toml pom.xml 2>/dev/null | head -40
cat CLAUDE.md 2>/dev/null
# Already installed (name = match key; <name>-version marker = cheap drift signal):
for f in .claude/agents/*.md .claude/commands/*.md .claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/*) n=$(basename "$(dirname "$f")");; *) n=$(basename "$f" .md);; esac
  v=$(grep -oP -- "(?:<!--\s*|#\s*)${n}-version:\s*\K\d+" "$f" | head -1)  # anchored: same ver_of as S3
  d=$(grep -m1 '^description:' "$f" | sed 's/description: *//')
  echo "  $n | v${v:-none} | $d"
done
# Hooks carry markers too (e.g. # block-dashes-version: N) - include them in drift detection:
for f in .claude/hooks/*; do
  [ -f "$f" ] || continue
  n=$(basename "$f"); n=${n%.*}
  v=$(grep -oP -- "(?:<!--\s*|#\s*)${n}-version:\s*\K\d+" "$f" | head -1)  # anchored: same ver_of as S3
  echo "  $n (hook) | v${v:-none}"
done
# Forge host + repo slug (host-aware: GitHub or self-hosted Forgejo).
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
# Anchor github.com to the HOST slot (matches forge-lib.sh's forge_host). A Forgejo URL that merely
# contains 'github.com' in its path/vanity host must NOT read as github.
case "$REMOTE_URL" in
  ''|*://github.com/*|*://*@github.com/*|git@github.com:*) FORGE_HOST=github ;;
  *) FORGE_HOST=forgejo ;;
esac
CURRENT_REPO=$(printf '%s' "$REMOTE_URL" | sed -E 's#\.git$##; s#/$##; s#^.*://[^/]+/##; s#^[^@]*@[^:/]+[:/]##')
# Domain/pattern sample:
find . \( -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' \) | grep -vE 'node_modules|\.claude|dist' | head -20
```

**Indicators to capture** (Anthropic-recommender style - drive the picks):

| Signal | Look in | Points to |
|---|---|---|
| Language / framework | package.json, pyproject.toml, imports | which review/backend agents fit |
| Auth / payments / PII | code + CLAUDE.md | security-auditor, owasp-api-security, GDPR scoring |
| Public API surface | routes/, controllers, OpenAPI | api-security-tester, api-design-principles |
| Dependency depth | lockfiles, package count | dep-auditor |
| Tests present | tests/, *_test, *.spec | tdd-orchestrator, test-automator |
| GitHub Actions | .github/workflows/ | /ci-health command |
| Forge host: GitHub vs Forgejo | origin remote (github.com vs other) | forge-host adapter (required by ticket-gate/gate-ticket/dep-auditor/ci-health/release on a non-GitHub host) |
| Ships releases (version + tags) | VERSION, package.json/pyproject version, git tags | release skill; release-automation gate |
| Dependabot / Renovate present | .github/dependabot.yml, renovate.json | release-automation Lane B (auto-release dep updates) |
| Coding standards state | CLAUDE.md inline / CONTRIBUTING / STYLE_GUIDE | coding-standards-auditor |
| Writing rules in CLAUDE.md | "no em dash", style rules | block-dashes hook |
| Versioned issue templates | `template-version` markers in the ISSUE_TEMPLATE dir | template lockstep guard + canonical ticket-standards doc (install via `forge-adapt templates`) |

Build a short profile and lead the recommendation with it:

```
Profile
  Stack: <language / framework / key libs>
  Domain: <what it does, for whom>
  Security surface: <auth, external APIs, data sensitivity>
  Installed: <component names, or "none">
```

### Step 2: Recommend (the dialogue the user wanted)

Cross-reference the profile against the catalogue. **Lead with the top 1-2 per category** - the
most valuable for THIS project. Skip any category with nothing relevant. Exclude components
already installed (match by `name:`). Give every item a tight, specific reason (<= 60 chars) -
the single strongest signal, never generic boilerplate.

**Use the reference files for the signal map and canonical "why" phrasing** - one per category,
so reasons stay consistent run to run:
- `references/subagents.md` · `references/skills.md` · `references/commands.md` · `references/hooks.md`

The live `ls` from Setup S3 is the source of truth for what EXISTS; the references fix the
canonical reason + priority. If a reference row names a component that is not in the live
catalogue, skip that row.

```
## forge-adapt - <project> (<stack>)

Profile
  Stack: <...>
  Domain: <...>
  Security surface: <...>
  Installed: <... or none>

### Recommended (top picks for this project)
| Component | Type | Why this project needs it | Priority |
|---|---|---|---|
| ticket-gate | 🤖 subagent | quality gate before implementation | P0 |
| security-auditor | 🤖 subagent | JWT + Stripe webhook OWASP surface | P0 |
| owasp-api-security | 🎯 skill | public REST API with auth + payments | P1 |
| /gate-ticket | 🧩 command | run the readiness gate on a GitHub issue | P1 |
| block-dashes | ⚡ hook | enforce the no-dash writing rule | P1 |

(If nothing new applies, write one line instead: "Nothing new - every catalogue component is already installed.")

### Version status (components carrying a marker)
| Component | Type | Local | forge-kit | Status |
|---|---|---|---|---|
| ticket-gate | 🤖 subagent | v1 | v2 | behind → refresh ticket-gate |
| full-review | 🧩 command | v1 | v1 | current |
| block-dashes | ⚡ hook | v1 | v1 | current |

(One table covering every installed component that HAS a marker. Status is `current` or
`behind → refresh <name>`. Omit the whole section only if no installed component carries a marker.)

### Unversioned (predate markers - not necessarily behind)
| Component | Type | Note |
|---|---|---|
| code-reviewer | 🤖 subagent | refresh code-reviewer to deep-compare |

(Omit if every installed component carries a marker. If the list is long, collapse to one line:
"<N> components predate markers - refresh <name> to deep-compare.")

Reply:
- names to install (I adapt each to your stack), "all", or "none"
- "refresh <name>" - deep-compare one installed component and merge genuine improvements
- "refresh" - full drift report (writes nothing)
- "more subagents" / "more skills" / "more commands" / "more hooks" - full catalogue for a category, as a table
```

Rules for this step:
- **ticket-gate is always P0** when missing - list it first under Subagents.
- **coding-standards-auditor is P0** whenever the profile shows coding standards as anything but
  `proper` (inline in CLAUDE.md, scattered across CONTRIBUTING/STYLE_GUIDE, or missing).
- **Template governance nudge.** If the project has versioned issue templates (a `template-version`
  marker in its ISSUE_TEMPLATE dir) but no `scripts/check-template-lockstep.sh`, add ONE line under
  the tables: "Template governance available: `forge-adapt templates` installs the version lockstep
  guard + canonical ticket-standards doc." It is repo-level, not a component, so it never appears in
  the Recommended or Version-status tables.
- **"more <category>"** prints the full catalogue for that one category as a table
  (Component | Why | Priority | Installed?), marking each row `✓` if already in `.claude/` or
  `+ new` if not (so the user sees what they have vs what is available), then repeats the reply prompt.
- **Version status table = every marked local copy; `behind` only when strictly lower.** Compare each
  installed component's `<name>-version` marker (captured in Step 1) against the catalogue marker
  (captured in Setup S3 - both sides use the same whole-file, name-scoped grep, so a match means the
  copy is genuinely current). Show marked components in the Version status table; Status is
  `behind → refresh <name>` ONLY when the local marker is strictly lower than the catalogue's, else
  `current`. When both sides carry the same number, render `current` - never downgrade a real match to
  "can't compare". This is a grep, high-confidence.
- **Unmarked local copy ≠ behind.** A component with NO local marker was almost always adapted before
  versioning existed - it is "unversioned", NOT stale. Do NOT render these as `v0 → v1` Updates (that
  floods the report with false positives - the exact failure this design avoids). Collapse ALL unmarked
  components into ONE quiet line: "Unversioned (predate markers - not necessarily behind): <names> -
  `refresh <name>` to deep-compare." Components unversioned on both sides fold into the same line.
- **Never content-diff every component up front** - it is expensive and mis-reads adaptation as drift.
- Wait for the reply. Names or "all" -> Step 3. `refresh`/`refresh <name>` -> refresh mode (below).
  "none" -> stop (offer contributions/templates modes).

### Step 3: Install (adapt, then write)

For each chosen component, read the forge-kit template, rewrite it for this project, and write it.

**Subagents / Skills / Commands:**
1. Read the template (`$FORGE_KIT_DIR/plugins/<group>/agents|commands/<name>.md`, or
   `.../skills/<name>/SKILL.md`).
2. Rewrite for the project profile - adapt rules:
   - Replace generic stack references with the actual stack
     (e.g. "check for SQL injection" -> "check for Prisma `$queryRaw` injection in `src/db/`").
   - Add project-specific criteria to scoring sections / checklists (JWT algo + expiry, Stripe
     webhook signature, per-tenant isolation, etc.).
   - Keep structure, phase order, scoring logic, and tool lists intact.
   - Adapt, do not pad: every change must trace to a Step-1 signal. Do not restate the template.
   - **Preserve the `<!-- <name>-version: N -->` marker from the template verbatim.** This is what
     makes the adapted copy detectable next run - an adaptation that drops the marker resets the
     component to "unversioned" and defeats drift detection forever. If the template somehow lacks a
     marker, add one matching the catalogue version.
3. Write it: agent -> `.claude/agents/<name>.md`; skill -> `.claude/skills/<name>/SKILL.md`;
   command -> `.claude/commands/<name>.md`.
4. Replace the repo placeholder: `sed -i "s|{{GITHUB_REPO}}|$CURRENT_REPO|g" <file>`.
5. **Forge-host dependency:** if the component does forge operations (ticket-gate, gate-ticket,
   dep-auditor, ci-health, release/release-automation) AND it is not GitHub-only, also install the
   `forge-host` adapter: copy `forge-lib.sh` to `scripts/`, and for a Forgejo or dual-remote repo
   (`$FORGE_HOST=forgejo`) copy `forge.conf.example` → `.forge.conf`. The Forgejo **base URL** and
   **token-env name** cannot be auto-detected, so ASK the user for them (or read an existing
   `.forge.conf`) to fill it in, and remind them to export the token. A GitHub-only repo needs
   neither (the components fall back to `gh`).
6. Confirm: `✓ <name> (<type>) v<N> - adapted for <stack>`.

**Hooks** (e.g. `block-dashes`):

**Branch on `$GOVERNANCE_PLUGIN_ACTIVE` (set during Setup S2), NOT on `$FORGE_KIT_SRC`.** Where the
component library lives says nothing about which plugin groups the user enabled. A plugin's
`hooks/hooks.json` is live only when that plugin itself is installed. Conflating the two ships a
sentinel file and a success message while registering no hook at all.

**If `GOVERNANCE_PLUGIN_ACTIVE = yes`** the hook is ALREADY registered and running: the plugin ships
`hooks/hooks.json`, which Claude Code activates whenever `forge-kit-governance` is enabled, anchored
to `${CLAUDE_PLUGIN_ROOT}`. Copying the script and editing `settings.json` would install a *second*
copy that fires alongside it. Do neither. A plugin-registered `block-dashes` stays dormant in every
project until it sees the sentinel, so opting in is the whole install:

```bash
mkdir -p .claude && touch .claude/no-dashes
```

Then clean up any copy an older forge-adapt left behind, or the project will run the hook twice
(two identical block messages per denial, two interpreter startups per tool call):

```bash
if [ -f .claude/hooks/block-dashes.py ]; then
  echo "forge-adapt: removing the project-local copy now superseded by the plugin."
  rm -f .claude/hooks/block-dashes.py
  tmp=$(mktemp)
  jq 'if .hooks.PreToolUse then .hooks.PreToolUse |= (map(.hooks |= map(select(((.command? // "") + " " + ((.args? // []) | map(tostring) | join(" "))) | test("block-dashes\\.py") | not))) | map(select(.hooks | length > 0))) else . end' \
    .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json || rm -f "$tmp"
fi
```

Confirm: `✓ block-dashes (hook) - already active via the plugin; opted this project in`.
To opt out later, delete `.claude/no-dashes`. Nothing else to undo.

**If `GOVERNANCE_PLUGIN_ACTIVE = no`** nothing is registering the hook, whatever `$FORGE_KIT_SRC` says.
Either tell the user they can `/plugin install forge-kit-governance@forge-kit` to get it managed by
the plugin, or install it into the project as below. Never do both.

1. Copy the script verbatim from `$FORGE_KIT_DIR/plugins/<group>/hooks/<file>` to
   `.claude/hooks/<file>` (`mkdir -p .claude/hooks`). Hook scripts are stack-agnostic - do not
   rewrite them; keep the `# <name>-version: N` marker line. A copy inside the project root is
   itself the opt-in: no sentinel needed, and the script detects this by its own location.
2. Wire it into `.claude/settings.json`, merging (do not clobber existing hooks). Use the **exec form**
   (`command` + `args`), never a bare command string:

   ```json
   { "type": "command", "command": "python3",
     "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dashes.py"] }
   ```

   Why this exact shape, and not a relative path or a `$VAR` inside a command string:
   - A **relative** path resolves only when Claude Code's working directory is the project root. From
     a subdirectory `python3` cannot open the script and exits 2, which is the PreToolUse *deny* code,
     so every matched call is blocked with a confusing `can't open file` error.
   - `${CLAUDE_PROJECT_DIR}` is a **path placeholder Claude Code substitutes**, not a shell variable.
     Only the braced form is documented. An **unbraced** `$CLAUDE_PROJECT_DIR` is left untouched by the
     substitution and expands to empty unless the variable happens to be exported into the hook's
     shell, giving the path `/.claude/hooks/...`, exit 2, and the same deny-everything failure.
   - With `args` present the hook runs in exec form: Claude Code spawns the executable directly, with
     no shell, and substitutes the placeholder into each `args` element as a plain string. No quoting,
     no expansion, nothing to get wrong. Omitting `args` selects shell form (`sh -c`).

   The merge below is idempotent and rewrites any legacy entry (relative, unbraced, or braced shell
   form) into exec form in place, rather than appending a duplicate. It preserves the existing
   `matcher`, so a deliberately narrowed one survives:

   ```bash
   mkdir -p .claude
   [ -f .claude/settings.json ] || echo '{}' > .claude/settings.json
   tmp=$(mktemp)
   jq '
     def script: "${CLAUDE_PROJECT_DIR}/.claude/hooks/block-dashes.py";
     def is_bd: (((.command? // "") + " " + ((.args? // []) | map(tostring) | join(" "))) | test("block-dashes\\.py"));
     def entry: {"type": "command", "command": "python3", "args": [script]};
     .hooks //= {}
     | .hooks.PreToolUse //= []
     | .hooks.PreToolUse |= map(.hooks |= map(if is_bd then entry else . end))
     | if [.hooks.PreToolUse[]?.hooks[]? | select(is_bd)] | length > 0
       then .
       else .hooks.PreToolUse += [{
         "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
         "hooks": [entry]
       }] end
   ' .claude/settings.json > "$tmp" \
     && mv "$tmp" .claude/settings.json \
     || { rm -f "$tmp"; echo "settings.json is not valid JSON; wire block-dashes by hand"; }
   ```
   The jq program is single-quoted, so `${CLAUDE_PROJECT_DIR}` stays literal in the written file and is
   substituted by Claude Code at hook-run time, not by this shell now.
   Never fall back to overwriting `settings.json` wholesale when `jq` fails: a malformed file is a
   reason to stop, not to destroy the user's other hooks.
3. Confirm: `✓ block-dashes (hook) - installed and wired in .claude/settings.json`.

**Finish** with a short summary and next steps:

```
forge-adapt complete - installed <N>:
  <name> (<type>) - <one-line: what was customised>
  ...
Next: review .claude/, commit, then file a test issue and run /gate-ticket <N>.
Run forge-adapt again anytime to stay current, or "forge-adapt contributions" to give back.
```

---

## Secondary modes (out of the main flow)

Run only when explicitly invoked, or offer them after the user replies "none".

### Refresh / drift mode  ("refresh", "refresh <name>", "drift")

The deep, expensive counterpart to the cheap "Updates available" block. Two shapes:

**`refresh` / `drift` (no name) - report only, writes nothing.** For every installed component,
compare its `<name>-version` marker against the catalogue and print a drift report:

```
forge-adapt drift report - <project>

| Component | Local | forge-kit | Status |
|---|---|---|---|
| ticket-gate | v1 | v2 | behind - refresh to update |
| security-auditor | v1 | v1 | current |
| code-reviewer | none | v1 | unversioned - refresh to deep-compare |
| ... | | | |
```

Stop after the report. Do not modify anything. Status `behind` requires a local marker strictly
lower than forge-kit; a copy with no local marker is `unversioned`, never `behind`.

**`refresh <name>` - deep-compare ONE component, report first, then confirm before writing.**
This is the only place a full content diff is justified, and it must NEVER blind-overwrite (that
would clobber intentional adaptation). Steps:

1. Read the installed copy (`.claude/.../<name>...`) and the catalogue copy.
2. **Classify every difference** into two buckets:
   - **Adaptation (keep):** project-specific stack/domain customisation - stack references, added
     scoring criteria, local agent-type names, injected invariants.
   - **Behind forge-kit (offer to apply):** structural/behavioural improvements present in the
     catalogue copy but missing locally (new rules, new sections, the version bump).
3. Print the report - what is adaptation, what is missing, and the proposed merge:

   ```
   refresh: <name>  (installed v<old> → forge-kit v<new>)

   | Difference | Classification | Action |
   |---|---|---|
   | references comprehensive-review:* agent variants | adaptation | keep |
   | "no post-then-retract" verification rule | forge-kit improvement | add |
   | domain-not-touched auto-score 10 rule | forge-kit improvement | add |

   Apply this merge? (yes / no)
   ```
4. On `yes`: produce a MERGED file - preserve all adaptation verbatim, splice in only the missing
   forge-kit improvements, bump the local `<name>-version` marker to the catalogue value. Write it,
   re-apply `{{GITHUB_REPO}}` if needed, confirm `✓ <name> refreshed v<old> → v<new> (adaptation preserved)`.
   On `no`: write nothing.

If the marker already matches the catalogue, say so and offer a content diff anyway (the project
may have edited a same-version copy) - but default to "already current, nothing to do".

### Contributions mode  ("forge-adapt contributions" / "contribute")

Skip Steps 1-3. After Setup, surface project-only components that could help the wider kit.

```bash
comm -23 <(ls .claude/agents/   2>/dev/null | sort) <(ls "$FORGE_KIT_DIR"/plugins/*/agents/   2>/dev/null | xargs -n1 basename | sort -u)
comm -23 <(ls .claude/commands/ 2>/dev/null | sort) <(ls "$FORGE_KIT_DIR"/plugins/*/commands/ 2>/dev/null | xargs -n1 basename | sort -u)
comm -23 <(ls .claude/skills/ 2>/dev/null | grep -v '^forge-adapt$' | sort) <(ls "$FORGE_KIT_DIR"/plugins/*/skills/ 2>/dev/null | xargs -n1 basename | sort -u)
```

**Generalisation filter** - skip candidates that are clearly project-specific: filenames with the
product/brand name, hardcoded repo names or internal endpoints in the first 20 lines, or known
domain patterns (`prisma-schema-guardian`, `safety-logic-reviewer`, `mobile-*-reviewer`,
`e2e-test-engineer`, `seo-reviewer`, `roadmap-gate`, `terminology-checker`,
`github-project-manager`, etc.).

Present survivors as a table; ask which to file. For each accepted one, check for an existing
contribution issue first (open -> skip; closed -> ask; none -> create), then:

```bash
gh issue create --repo agigante80/forge-kit --title "Contribution: <name> (<type>)" --label contribution \
  --body "<category / what it does / why it generalises / source repo / full file content / checklist>"
```

Never auto-create - always confirm. Print each issue URL.

### Templates mode  ("forge-adapt templates")

Audit `.github/ISSUE_TEMPLATE/*.yml` against the forge-kit reference version.

```bash
FORGE_KIT_TEMPLATE_VERSION=$(grep -oP 'template-version: \K\d+' "$FORGE_KIT_DIR/.github/ISSUE_TEMPLATE/feature.yml" | head -1)
```

Show a per-template status table (missing / outdated / incomplete / current), ask which to
install or upgrade, then for each: use the forge-kit template as base when missing (adapt the
`areas` dropdown to the project's real package structure), or merge when outdated/incomplete
(preserve ALL existing content verbatim, add only missing sections, bump the `template-version`
marker). Templates write to `.github/ISSUE_TEMPLATE/` on GitHub, or to `.forgejo/issue_template/`
when `$FORGE_HOST=forgejo` (Forgejo also reads `.gitea/ISSUE_TEMPLATE/`); never `.claude/`.
`contribution.yml` is forge-kit-specific - exclude it from the audit.

**After the template audit, offer the repo-level template governance** - the lockstep guard and the
canonical standards doc that keep those templates honest. Offer this ONLY when the project actually
has versioned issue-templates (at least one template carrying a `template-version` marker); without
them the guard is meaningless, so skip this block entirely. Detect the current state:

```bash
# Project template dir (host-aware) + its current template-version, plus what governance exists.
PRJ_TPL_DIR=$(for d in .forgejo/ISSUE_TEMPLATE .gitea/ISSUE_TEMPLATE .github/ISSUE_TEMPLATE; do
  [ -d "$d" ] && { echo "$d"; break; }; done)
PRJ_TPL_VER=$([ -n "$PRJ_TPL_DIR" ] && grep -hoP 'template-version: \K\d+' "$PRJ_TPL_DIR"/*.yml 2>/dev/null | sort -un | tail -1)
HAS_GUARD=$([ -f scripts/check-template-lockstep.sh ] && echo yes || echo no)
HAS_DOC=$([ -f docs/guides/ticket-standards.md ] && echo yes || echo no)
```

If `PRJ_TPL_VER` is empty, skip. Otherwise show a small table and ask which to install:

| Governance | State | What installing does |
|---|---|---|
| template lockstep guard | `$HAS_GUARD` | copy `check-template-lockstep.sh` + its test to `scripts/`, wire into CI |
| canonical ticket-standards doc | `$HAS_DOC` | write `docs/guides/ticket-standards.md` (adapted), repoint gate + CLAUDE.md |

Both are independent - a project can take the guard, the doc, or both.

**Install: lockstep guard (copied verbatim - host-agnostic, like a hook).**

```bash
mkdir -p scripts
src="$FORGE_KIT_DIR/scripts"
# Defence in depth: if S2's refresh failed (offline) the library can still be stale and these
# files absent. Never cp a missing source (a raw cp error reads as a bug); stop with the fix.
if [ ! -f "$src/check-template-lockstep.sh" ] || [ ! -f "$src/test-template-lockstep.sh" ]; then
  if [ "$FORGE_KIT_SRC" = "marketplace" ]; then fix="/plugin marketplace update forge-kit"; else fix="git -C $FORGE_KIT_DIR pull"; fi
  echo "forge-adapt: guard scripts missing from the library at $FORGE_KIT_DIR (stale). Refresh and retry: $fix"
else
  cp "$src/check-template-lockstep.sh" scripts/
  cp "$src/test-template-lockstep.sh"  scripts/
  chmod +x scripts/check-template-lockstep.sh scripts/test-template-lockstep.sh
fi
```

**Run the guard once before wiring CI**, so the user is not blindsided by red CI (and a red guard
test) on drift that pre-dates the install:

```bash
bash scripts/check-template-lockstep.sh || echo "forge-adapt: templates are NOT in lockstep (above) - CI will fail, and the guard's own test will too, until you align their template-version markers."
```

If it reports drift, surface it and confirm the user wants to proceed - the guard is doing its job,
but they may prefer to reconcile the template versions first. Then wire it into CI, host-aware. Prefer a dedicated workflow so you never surgically edit an
unknown existing job (the user can instead fold the two `run:` lines into an existing job). Write to
`.github/workflows/` on GitHub or `.forgejo/workflows/` on Forgejo. Skip writing it if a workflow in
that dir already runs `check-template-lockstep.sh` (grep first):

```yaml
# <host-workflows-dir>/template-lockstep.yml
name: Template lockstep
on: [push, pull_request]
jobs:
  lockstep:
    runs-on: ubuntu-latest    # on Forgejo, use the project's runner label
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check-template-lockstep.sh
      - run: bash scripts/test-template-lockstep.sh
```

Confirm: `✓ template-lockstep guard installed + wired (<host-workflows-dir>)`.

**Install: canonical ticket-standards doc (adapted; report-first if it already exists).**

- **Absent** (`HAS_DOC=no`): read `$FORGE_KIT_DIR/docs/guides/ticket-standards.md` (if that source
  file is missing, the library is stale - refresh it as in S2 and retry; never fabricate the doc), adapt it to the
  project (reference the project's ACTUAL template set and package names; drop rules for sections the
  project's templates do not carry), and **set its `template-version` marker to `$PRJ_TPL_VER`** - the
  project's own value, NOT forge-kit's - so the lockstep guard locks the doc to the project's
  templates rather than failing on a version mismatch. Write it to `docs/guides/ticket-standards.md`
  (the path the copied guard reads by default).
- **Present** (`HAS_DOC=yes`): do NOT clobber it. Apply the `refresh <name>` discipline - classify
  differences as project-adaptation (keep) vs forge-kit-improvement (offer), show the proposed merge,
  and write only on `yes`.
- **Repoint (additive; each only if the target exists and does not already reference the doc):**
  - project gate: add `docs/guides/ticket-standards.md` to the Step 2 read-list of
    `.claude/agents/ticket-gate.md` (the canonical rules the gate scores against).
  - project `CLAUDE.md`: add one line under its issue-template section naming the doc as the single
    source of truth for the ready-ticket rules.

Confirm: `✓ ticket-standards doc written at v$PRJ_TPL_VER; gate + CLAUDE.md repointed`.

---

## Rules

- **The skill and the library update independently.** S1 refreshes this SKILL.md; S2 refreshes the
  component checkout (`~/forge-kit` via fetch+reset, or marketplace-managed). A stale library hides
  newly added components - always refresh in S2 before cataloguing, never trust an existing clone as-is.
- **Lead with the recommendation, not the setup.** Setup (self-update, locate library, catalogue)
  runs quietly. The first substantial thing the user sees is the profile + top picks.
- **Render every listing as a Markdown table.** The Recommended picks, Version status, Unversioned,
  the `drift` report, the `refresh` classification, and "more <category>" output are all tables - never
  bullet lists or key-value blocks. The Profile is the only block that stays prose. Keep "Why" cells <= 60 chars.
- **Adapted copies keep the version marker.** Step 3 preserves the `<name>-version` marker so the next
  run can detect drift; an install that strips it resets the component to "unversioned".
- **Recommended table = top picks, not the whole catalogue.** Lead with the most valuable per category;
  "more <category>" expands one category into its full-catalogue table on request.
- **Every "why" is specific and <= 60 chars.** One strongest signal, never generic best-practice text.
- **Never write outside Step 3 or a confirmed `refresh <name>`.** Recommendations, the "Updates
  available" block, and the `refresh`/`drift` report all write nothing. Self-update (Setup S1) is the
  only other exception and only ever writes its own SKILL.md.
- **Drift is detected by version markers, not by diffing.** The cheap up-front signal and the
  `drift` report compare `<name>-version` markers (a grep that ignores intentional adaptation). A full
  content diff happens ONLY inside `refresh <name>`, on demand.
- **`refresh <name>` reports before it writes and never blind-overwrites.** It classifies changes as
  adaptation-to-keep vs forge-kit-improvement-missing, shows the proposed merge, waits for confirmation,
  then merges preserving all adaptation (same discipline as template upgrades).
- **Adapt, do not pad.** Every customisation must trace to a Step-1 signal. Hooks are copied verbatim, not rewritten.
- **Match installed components by `name:`**, not filename, to avoid re-recommending.
- **ticket-gate is P0; coding-standards-auditor is P0 when standards are not `proper`.**
- **Contributions are never auto-filed** - always confirm, and always check for an existing issue first.
- **Single-category focus**: if the invocation names one category ("forge-adapt hooks"), recommend
  and install only that category.
- **Diagnostic bash exits 0.** Setup and Analyze run read-only probes; a missing optional path (no
  `.github/workflows` on a Forgejo repo, an empty hook glob, an absent lockfile) is a normal finding,
  never a failure. A block that exits non-zero surfaces as "Failed to run" and alarms the user. Use
  `shopt -s nullglob` for catalogue globs and end multi-command probes with a trailing `true`.
- **Template governance is repo-level and opt-in.** Offer the lockstep guard + canonical doc only
  when the project has versioned issue templates. The guard and its test are copied verbatim
  (host-agnostic); the canonical doc is adapted with its `template-version` marker set to the
  PROJECT's template version, and an existing project doc is refreshed report-first, never clobbered.
