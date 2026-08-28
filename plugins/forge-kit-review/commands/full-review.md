---
description: "Pre-merge or periodic multi-lens audit (architecture, security, performance, testing, standards); findings enter the bounded review loop or become tickets. Not the per-task reviewer."
argument-hint: "<target path or description> [--since <ref>] [--security-focus] [--performance-critical] [--strict-mode] [--framework react|spring|django|rails]"
---

<!-- full-review-version: 9 -->

# Comprehensive Code Review Orchestrator

## When to run this (positioning)

This is a **pre-merge or periodic multi-lens AUDIT** (architecture, security, performance,
testing, standards): run it before a merge to main, before a release, or on an interval.
It is NOT the per-task reviewer: multi-agent review earns its cost on independent
cross-cutting lenses over one change, and loses to a single strong reviewer inside the
edit-review loop (forge-kit #71: consensus across many reviewers of one task underperforms
the best single reviewer; multi-agent pays only where lenses are independent). For
per-task review, dispatch
`code-reviewer` alone and drive the rounds with the Iteration contract below.

**Where the findings go (the handoff):** the audit run IS round 1 of the Iteration
contract below (that section is canonical; this paragraph only summarises it). Its
Critical/High/Medium findings are fixed and verified by a round-2 run (`--since` or the
verify-fixes pre-flight); Low findings are filed as tickets by the Completion step. No
finding is ever left with neither a fix round nor a ticket.

**Unattended callers** (working-overnight investigations): EVERY interactive prompt in
this file resolves without asking. Checkpoints auto-select option 1; a pre-flight
`in_progress` session resumes; a `complete` session archives and starts a FRESH audit
(never auto-selecting verify-fixes: an unattended periodic audit means full coverage);
scope is confirmed by proceeding; the step-0 off-ramp is skipped. Ticket filing honours
the caller's declared cap (for working-overnight, the manifest's investigation-depth cap,
declared in `.claude/overnight/active.md` at kickoff); findings beyond it are listed in
the report as unfiled, which is NOT a Completion failure when such a cap applies.

## CRITICAL BEHAVIORAL RULES

You MUST follow these rules exactly. Violating any of them is a failure.

1. **Execute phases in order.** Do NOT skip ahead, reorder, or merge phases. ONE exception:
   checkpoint option 2 (early close-out) jumps straight to Phase 5; Phase 5 and rule 4 then
   treat the skipped phases' missing output files as expected, not as a halt.
2. **Write output files.** Each phase MUST produce its output file in `.full-review/` before the next phase begins. Read from prior phase files -- do NOT rely on context window memory.
3. **Stop at checkpoints.** When you reach a `PHASE CHECKPOINT`, you MUST stop and wait for explicit user approval before continuing. Use the AskUserQuestion tool with clear options. Unattended runs are the exception, per the Unattended callers paragraph above: no prompt is ever issued.
4. **Halt on failure.** If any step fails (agent error, missing files, access issues), STOP immediately. Present the error and ask the user how to proceed. Do NOT silently continue.
5. **Use only local agents.** All `subagent_type` references use agents bundled with this plugin or `general-purpose`. No cross-plugin dependencies.
6. **Never enter plan mode autonomously.** Do NOT use EnterPlanMode. This command IS the plan -- execute it.
7. **Round awareness wires the iteration contract.** When `--since <ref>` is passed, or the
   pre-flight selects "verify fixes", this run is round N+1: set `previous_ref` and `round`
   in `state.json`, narrow the target to `previous_ref...HEAD`, and EVERY dispatched agent
   prompt in every phase gains: the previously reviewed ref; the prior round's report path
   `.full-review/round-<N>/05-final-report.md` IF it exists (after a `--since` run on a
   clean checkout, or a cleaned gitignored `.full-review/`, it does not: then agents get
   the ref only and trajectory reporting states "no prior report available", never a halt
   on the missing file); and the instruction to tag each finding `in-prior-fix: yes/no`.
   **yes means the defective lines were ADDED or MODIFIED by the fix commits
   (`previous_ref...HEAD`)**; a pre-existing defect merely VISIBLE in the diff's context
   lines is in-target but `in-prior-fix: no` - the tag measures fix-induced damage, and
   conflating it with delta membership would fire the trip wire on every in-target finding
   and make rounds 3 and 4 unreachable. Round 1 has no `previous_ref`; the field is omitted
   and no finding carries the tag.

## Pre-flight Checks

Before starting, perform these checks:

### 1. Check for existing session

Check if `.full-review/state.json` exists:

- If it exists and `status` is `"in_progress"`: Read it, display the current phase, and ask the user:

  ```
  Found an in-progress review session:
  Target: [target from state]
  Current phase: [phase from state]

  1. Resume from where we left off
  2. Start fresh (archives existing session)
  ```

- If it exists and `status` is `"complete"`: Ask whether to (1) verify fixes since that
  review - round N+1, delta-only: sets `previous_ref` to the ref recorded in the completed
  state, applies rule 7, and archives the old session files under `.full-review/round-<N>/`;
  or (2) archive and start fresh (round 1).

### 1.5 Task-sized off-ramp (after the session check, before ANY state is created)

If the target is a SINGLE FILE, or the user says this is one task's in-progress work,
offer the per-task path first: dispatch `code-reviewer` alone under the Iteration
contract. A branch or pre-merge diff is NOT task-sized (pre-merge audits are this
command's headline use). Only on explicit confirmation to proceed does the pipeline
initialize; an accepted redirect ends here with nothing NEW written (a session found in
step 1 was already dealt with there), so no phantom `in_progress` state is left behind.

### 2. Initialize state

Create `.full-review/` directory and `state.json`:

```json
{
  "target": "$ARGUMENTS",
  "status": "in_progress",
  "flags": {
    "security_focus": false,
    "performance_critical": false,
    "strict_mode": false,
    "framework": null
  },
  "round": 1,
  "previous_ref": null,
  "reviewed_ref": null,
  "current_step": 1,
  "current_phase": 1,
  "completed_steps": [],
  "files_created": [],
  "started_at": "ISO_TIMESTAMP",
  "last_updated": "ISO_TIMESTAMP"
}
```

Parse `$ARGUMENTS` for `--security-focus`, `--performance-critical`, `--strict-mode`,
`--framework`, and `--since <ref>` flags; strip every parsed flag OUT of the free-text
target. `--since` does not live in the flags object: it sets `previous_ref` to the given
ref (verify it resolves: `git rev-parse --verify <ref>`; a bad ref is a rule-4 halt, never
a silent round-1 fallback) and `round` to 2 (or prior `round`+1 when state records one),
engaging rule 7.

### 3. Identify review target

Determine what code to review from `$ARGUMENTS`:

- If a file/directory path is given, verify it exists
- If a description is given (e.g., "recent changes", "authentication module"), identify the relevant files
- List the files that will be reviewed and confirm with the user

**Output file:** `.full-review/00-scope.md`

```markdown
# Review Scope

## Target

[Description of what is being reviewed]

## Files

[List of files/directories included in the review]

## Flags

- Security Focus: [yes/no]
- Performance Critical: [yes/no]
- Strict Mode: [yes/no]
- Framework: [name or auto-detected]

## Review Phases

1. Code Quality & Architecture
2. Security & Performance
3. Testing & Documentation
4. Best Practices & Standards
5. Consolidated Report
```

Update `state.json`: add `"00-scope.md"` to `files_created`, add step 0 to `completed_steps`.

---

## Phase 1: Code Quality & Architecture Review (Steps 1A-1B)

Run both agents in parallel using multiple Task tool calls in a single response.

### Step 1A: Code Quality Analysis

```
Task:
  subagent_type: "code-reviewer"
  description: "Code quality analysis for $ARGUMENTS"
  prompt: |
    Perform a comprehensive code quality review.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Instructions
    Analyze the target code for:
    1. **Code complexity**: Cyclomatic complexity, cognitive complexity, deeply nested logic
    2. **Maintainability**: Naming conventions, function/method length, class cohesion
    3. **Code duplication**: Copy-pasted logic, missed abstraction opportunities
    4. **Clean Code principles**: SOLID violations, code smells, anti-patterns
    5. **Technical debt**: Areas that will become increasingly costly to change
    6. **Error handling**: Missing error handling, swallowed exceptions, unclear error messages

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - File and line location
    - Description of the issue
    - Specific fix recommendation with code example

    Write your findings as a structured markdown document.
```

### Step 1B: Architecture & Design Review

```
Task:
  subagent_type: "architect-review"
  description: "Architecture review for $ARGUMENTS"
  prompt: |
    Review the architectural design and structural integrity of the target code.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Instructions
    Evaluate the code for:
    1. **Component boundaries**: Proper separation of concerns, module cohesion
    2. **Dependency management**: Circular dependencies, inappropriate coupling, dependency direction
    3. **API design**: Endpoint design, request/response schemas, error contracts, versioning
    4. **Data model**: Schema design, relationships, data access patterns
    5. **Design patterns**: Appropriate use of patterns, missing abstractions, over-engineering
    6. **Architectural consistency**: Does the code follow the project's established patterns?

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - Architectural impact assessment
    - Specific improvement recommendation

    Write your findings as a structured markdown document.
```

After both complete, consolidate into `.full-review/01-quality-architecture.md`:

```markdown
# Phase 1: Code Quality & Architecture Review

## Code Quality Findings

[Summary from 1A, organized by severity]

## Architecture Findings

[Summary from 1B, organized by severity]

## Critical Issues for Phase 2 Context

[List any findings that should inform security or performance review]
```

Update `state.json`: set `current_step` to 2, `current_phase` to 2, add steps 1A and 1B to `completed_steps`.

---

## Phase 2: Security & Performance Review (Steps 2A-2B)

Read `.full-review/01-quality-architecture.md` for context from Phase 1.

Run both agents in parallel using multiple Task tool calls in a single response.

### Step 2A: Security Vulnerability Assessment

```
Task:
  subagent_type: "security-auditor"
  description: "Security audit for $ARGUMENTS"
  prompt: |
    Execute a comprehensive security audit on the target code.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Phase 1 Context
    [Insert contents of .full-review/01-quality-architecture.md -- focus on the "Critical Issues for Phase 2 Context" section]

    ## Instructions
    Analyze for:
    1. **OWASP Top 10**: Injection, broken auth, sensitive data exposure, XXE, broken access control, misconfig, XSS, insecure deserialization, vulnerable components, insufficient logging
    2. **Input validation**: Missing sanitization, unvalidated redirects, path traversal
    3. **Authentication/authorization**: Flawed auth logic, privilege escalation, session management
    4. **Cryptographic issues**: Weak algorithms, hardcoded secrets, improper key management
    5. **Dependency vulnerabilities**: Known CVEs in dependencies, outdated packages
    6. **Configuration security**: Debug mode, verbose errors, permissive CORS, missing security headers

    For each finding, provide:
    - Severity (Critical / High / Medium / Low) with CVSS score if applicable
    - CWE reference where applicable
    - File and line location
    - Proof of concept or attack scenario
    - Specific remediation steps with code example

    Write your findings as a structured markdown document.
```

### Step 2B: Performance & Scalability Analysis

```
Task:
  subagent_type: "general-purpose"
  description: "Performance analysis for $ARGUMENTS"
  prompt: |
    You are a performance engineer. Conduct a performance and scalability analysis of the target code.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Phase 1 Context
    [Insert contents of .full-review/01-quality-architecture.md -- focus on the "Critical Issues for Phase 2 Context" section]

    ## Instructions
    Analyze for:
    1. **Database performance**: N+1 queries, missing indexes, unoptimized queries, connection pool sizing
    2. **Memory management**: Memory leaks, unbounded collections, large object allocation
    3. **Caching opportunities**: Missing caching, stale cache risks, cache invalidation issues
    4. **I/O bottlenecks**: Synchronous blocking calls, missing pagination, large payloads
    5. **Concurrency issues**: Race conditions, deadlocks, thread safety
    6. **Frontend performance**: Bundle size, render performance, unnecessary re-renders, missing lazy loading
    7. **Scalability concerns**: Horizontal scaling barriers, stateful components, single points of failure

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - Estimated performance impact
    - Specific optimization recommendation with code example

    Write your findings as a structured markdown document.
```

After both complete, consolidate into `.full-review/02-security-performance.md`:

```markdown
# Phase 2: Security & Performance Review

## Security Findings

[Summary from 2A, organized by severity]

## Performance Findings

[Summary from 2B, organized by severity]

## Critical Issues for Phase 3 Context

[List findings that affect testing or documentation requirements]
```

Update `state.json`: set `current_step` to "checkpoint-1", add steps 2A and 2B to `completed_steps`.

---

## PHASE CHECKPOINT 1 -- User Approval Required

Display a summary of findings from Phase 1 and Phase 2 and ask:

```
Phases 1-2 complete: Code Quality, Architecture, Security, and Performance reviews done.

Summary:
- Code Quality: [X critical, Y high, Z medium findings]
- Architecture: [X critical, Y high, Z medium findings]
- Security: [X critical, Y high, Z medium findings]
- Performance: [X critical, Y high, Z medium findings]

Please review:
- .full-review/01-quality-architecture.md
- .full-review/02-security-performance.md

1. Continue -- proceed to Testing & Documentation review (findings so far join the
   handoff at Completion; fixes happen AFTER the audit, verified by a round-2 run)
2. Close out early and start fixing -- the remaining REVIEW phases are skipped, but the
   run jumps directly to Phase 5: the final report is compiled from the phases that ran
   (skipped phases listed in Review Metadata), `status`/`reviewed_ref`/`round` are written
   exactly as on a full run, and Completion executes, so the round-2 verify path stays
   reachable. The round-2 verify covers the FIXES only; the skipped lenses still owe the
   target a pass, so Completion after an early close-out recommends a fresh full audit
   once the fixes land. Mid-run fixes are never made while phases continue: they desync
   the reviewed tree from 00-scope.md and escape in-prior-fix tagging
3. Pause -- save progress and stop here
```

If `--strict-mode` flag is set and there are Critical findings, recommend option 1:
strictness means MAXIMUM coverage before fixing begins, never fewer lenses.

Do NOT proceed to Phase 3 until the user approves.

---

## Phase 3: Testing & Documentation Review (Steps 3A-3B)

Read `.full-review/01-quality-architecture.md` and `.full-review/02-security-performance.md` for context.

Run both agents in parallel using multiple Task tool calls in a single response.

### Step 3A: Test Coverage & Quality Analysis

```
Task:
  subagent_type: "general-purpose"
  description: "Test coverage analysis for $ARGUMENTS"
  prompt: |
    You are a test automation engineer. Evaluate the testing strategy and coverage for the target code.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Prior Phase Context
    [Insert security and performance findings from .full-review/02-security-performance.md that affect testing requirements]

    ## Instructions
    Analyze:
    1. **Test coverage**: Which code paths have tests? Which critical paths are untested?
    2. **Test quality**: Are tests testing behavior or implementation? Assertion quality per code-reviewer's assertions-that-cannot-fail dimension (the five shapes; that dimension is canonical, do not improvise a parallel check)
    3. **Test pyramid adherence**: Unit vs integration vs E2E test ratio
    4. **Edge cases**: Are boundary conditions, error paths, and concurrent scenarios tested?
    5. **Test maintainability**: Test isolation, mock usage, flaky test indicators
    6. **Security test gaps**: Are security-critical paths tested? Auth, input validation, etc.
    7. **Performance test gaps**: Are performance-critical paths tested? Load testing?

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - What is untested or poorly tested
    - Specific test recommendations with example test code

    Write your findings as a structured markdown document.
```

### Step 3B: Documentation & API Review

```
Task:
  subagent_type: "general-purpose"
  description: "Documentation review for $ARGUMENTS"
  prompt: |
    You are a technical documentation architect. Review documentation completeness and accuracy.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Prior Phase Context
    [Insert key findings from .full-review/01-quality-architecture.md and .full-review/02-security-performance.md]

    ## Instructions
    Evaluate:
    1. **Inline documentation**: Are complex algorithms and business logic explained?
    2. **API documentation**: Are endpoints documented with examples? Request/response schemas?
    3. **Architecture documentation**: ADRs, system diagrams, component documentation
    4. **README completeness**: Setup instructions, development workflow, deployment guide
    5. **Accuracy**: Does documentation match the actual implementation?
    6. **Changelog/migration guides**: Are breaking changes documented?

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - What is missing or inaccurate
    - Specific documentation recommendation

    Write your findings as a structured markdown document.
```

After both complete, consolidate into `.full-review/03-testing-documentation.md`:

```markdown
# Phase 3: Testing & Documentation Review

## Test Coverage Findings

[Summary from 3A, organized by severity]

## Documentation Findings

[Summary from 3B, organized by severity]
```

Update `state.json`: set `current_step` to 4, `current_phase` to 4, add steps 3A and 3B to `completed_steps`.

---

## Phase 4: Best Practices & Standards (Steps 4A-4B)

Read all previous `.full-review/*.md` files for full context.

Run both agents in parallel using multiple Task tool calls in a single response.

### Step 4A: Framework & Language Best Practices

```
Task:
  subagent_type: "general-purpose"
  description: "Framework best practices review for $ARGUMENTS"
  prompt: |
    You are an expert in modern framework and language best practices. Verify adherence to current standards.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## All Prior Findings
    [Insert a concise summary of critical/high findings from all prior phases]

    ## Instructions
    Check for:
    1. **Language idioms**: Is the code idiomatic for its language? Modern syntax and features?
    2. **Framework patterns**: Does it follow the framework's recommended patterns? (e.g., React hooks, Django views, Spring beans)
    3. **Deprecated APIs**: Are any deprecated functions/libraries/patterns used?
    4. **Modernization opportunities**: Where could modern language/framework features simplify code?
    5. **Package management**: Are dependencies up-to-date? Unnecessary dependencies?
    6. **Build configuration**: Is the build optimized? Development vs production settings?

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - Current pattern vs recommended pattern
    - Migration/fix recommendation with code example

    Write your findings as a structured markdown document.
```

### Step 4B: CI/CD & DevOps Practices Review

```
Task:
  subagent_type: "general-purpose"
  description: "CI/CD and DevOps practices review for $ARGUMENTS"
  prompt: |
    You are a DevOps engineer. Review CI/CD pipeline and operational practices.

    ## Review Scope
    [Insert contents of .full-review/00-scope.md]

    ## Critical Issues from Prior Phases
    [Insert critical/high findings from all prior phases that impact deployment or operations]

    ## Instructions
    Evaluate:
    1. **CI/CD pipeline**: Build automation, test gates, deployment stages, security scanning
    2. **Deployment strategy**: Blue-green, canary, rollback capabilities
    3. **Infrastructure as Code**: Are infrastructure configs version-controlled and reviewed?
    4. **Monitoring & observability**: Logging, metrics, alerting, dashboards
    5. **Incident response**: Runbooks, on-call procedures, rollback plans
    6. **Environment management**: Config separation, secret management, parity between environments

    For each finding, provide:
    - Severity (Critical / High / Medium / Low)
    - Operational risk assessment
    - Specific improvement recommendation

    Write your findings as a structured markdown document.
```

After both complete, consolidate into `.full-review/04-best-practices.md`:

```markdown
# Phase 4: Best Practices & Standards

## Framework & Language Findings

[Summary from 4A, organized by severity]

## CI/CD & DevOps Findings

[Summary from 4B, organized by severity]
```

Update `state.json`: set `current_step` to 5, `current_phase` to 5, add steps 4A and 4B to `completed_steps`.

---

## Phase 5: Consolidated Report (Step 5)

Read all `.full-review/*.md` files. Generate the final consolidated report.

**Output file:** `.full-review/05-final-report.md`

```markdown
# Comprehensive Code Review Report

## Review Target

[From 00-scope.md]

## Executive Summary

[2-3 sentence overview of overall code health and key concerns]

## Findings by Priority

### Critical Issues (P0 -- Must Fix Immediately)

[All Critical findings from all phases, with source phase reference]

- Security vulnerabilities with CVSS > 7.0
- Data loss or corruption risks
- Authentication/authorization bypasses
- Production stability threats

### High Priority (P1 -- Enters the Fix Loop)

[All High findings from all phases]

- Performance bottlenecks impacting user experience
- Missing critical test coverage
- Architectural anti-patterns causing technical debt
- Outdated dependencies with known vulnerabilities

### Medium Priority (P2 -- Enters the Fix Loop)

[All Medium findings from all phases]

- Non-critical performance optimizations
- Documentation gaps
- Code refactoring opportunities
- Test quality improvements

### Low Priority (P3 -- Ticketed at Completion)

[All Low findings from all phases]

- Style guide violations
- Minor code smell issues
- Nice-to-have improvements

## Findings by Category

- **Code Quality**: [count] findings ([breakdown by severity])
- **Architecture**: [count] findings ([breakdown by severity])
- **Security**: [count] findings ([breakdown by severity])
- **Performance**: [count] findings ([breakdown by severity])
- **Testing**: [count] findings ([breakdown by severity])
- **Documentation**: [count] findings ([breakdown by severity])
- **Best Practices**: [count] findings ([breakdown by severity])
- **CI/CD & DevOps**: [count] findings ([breakdown by severity])

## Recommended Action Plan

1. [Ordered list of recommended actions, starting with critical/high items]
2. [Group related fixes where possible]
3. [Estimate relative effort: small/medium/large]

## Review Metadata

- Review date: [timestamp]
- Round: [N] (previous ref: [ref or n/a])
- Stopping reason: [loop continues: fixes pending / clean round / hard stop / trip wire / round-gate not met]
- Rounds that found in-prior-fix defects: [count]
- Phases completed: [list]
- Phases skipped (early close-out): [list or none]
- Flags applied: [list active flags]
```

Update `state.json`: set `status` to `"complete"`, `last_updated` to the current timestamp,
and `reviewed_ref` to the commit the review covered (`git rev-parse HEAD`). `reviewed_ref`
and `round` are what the verify-fixes pre-flight and the `round-<N>/` archive name read;
without them a later round has no fix set to diff against.

---

## Iteration contract (the loop's stopping rules)

When this command is re-run to verify fixes from a previous full review, or when its
findings enter a review-fix-review loop, these rules bound the loop (issue #66; the
reporting half lives in `code-reviewer.md`):

- **Round 1** reviews the change. Fixes go by this command's own severity ladder: Critical,
  High, and Medium are fixed now; Low becomes a ticket immediately. **A ticket is a
  finished outcome for a finding, not a failure to fix it.**
- **Round 2** reviews ONLY the delta since the previously reviewed ref (the fix set,
  `previous_ref...HEAD` per rule 7). The target must not grow between rounds.
- **Rounds 3 and 4 each run only if the PREVIOUS round found a Critical or High.**
  **Hard stop after 4 rounds** regardless, even if round 4 found one.
- **Trip wire:** if two consecutive rounds each find a defect inside the previous round's
  fix, STOP immediately, whatever the round number. That is bad-fix injection above the
  cited base rate, and further iteration removes value rather than adding it. Remaining
  findings become tickets; continuing past the trip wire is the CALLER's explicit call,
  never a default.
- **Every report states the stopping reason**, from one vocabulary: `loop continues: fixes
  pending` (non-terminal: blocking findings exist and the loop is expected to go on),
  `clean round`, `hard stop`, `trip wire`, or `round-gate not met`. Terminal reports also
  state how many rounds found in-prior-fix defects, so the human decides from data.
- **Each round has no memory of the last.** When a round reverses an earlier decision,
  write the rationale into the code or the ticket, or the next round re-litigates it.

At adaptation time, the hard-stop round count is a project choice; the trip wire is not.

## Completion

Present the final summary:

```
Comprehensive code review complete for: $ARGUMENTS

## Review Output Files

(after an option-2 early close-out, list ONLY the files actually written; never name a
skipped phase's file as produced)

- Scope: .full-review/00-scope.md
- Quality & Architecture: .full-review/01-quality-architecture.md
- Security & Performance: .full-review/02-security-performance.md
- Testing & Documentation: .full-review/03-testing-documentation.md
- Best Practices: .full-review/04-best-practices.md
- Final Report: .full-review/05-final-report.md

## Summary
- Total findings: [count]
- Critical: [X] | High: [Y] | Medium: [Z] | Low: [W]
- Round: [N] | Stopping reason: [reason] | In-prior-fix findings this round: [count]

## Next Steps
1. Review the full report at .full-review/05-final-report.md
2. Fix Critical (P0), High (P1), and Medium (P2) findings; verify with a round-2 run
   (--since <reviewed_ref> or the verify-fixes pre-flight)
3. Low (P3) tickets filed: [list of created issue URLs]
```

**Ticket filing (part of Completion, not advice):** for each Low finding: FIRST search
open issues for it (the source marker makes prior filings greppable:
`forge_issue_list open` or `gh issue list --search`, filter for the finding's summary);
an already-open ticket satisfies the no-finding-left rule, note its URL instead of
re-filing, or periodic audits re-file every stable Low forever. Otherwise create one
issue via the host-aware adapter where installed (`forge_issue_create "<title>" "<body>"`,
then `forge_issue_label`), falling back to `gh issue create`; body = the finding verbatim
plus `(source: full-review round <N>, <date>)`; label `enhancement` unless the finding
names a better fit. **Check `forge_issue_label`'s exit**: on Forgejo its contract is
REFUSE-ALL (an unresolvable name fails the whole call and applies nothing), so create the
missing label first or drop it, then retry, exactly as ticket-gate and dep-auditor
document. List every created-or-found URL in Next Steps. A Low finding with neither is a
Completion failure, per the handoff's no-finding-left rule, EXCEPT findings listed as
unfiled under an unattended caller's declared cap (see Unattended callers above).
