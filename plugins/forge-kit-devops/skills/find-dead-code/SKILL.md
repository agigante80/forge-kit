---
name: find-dead-code
description: Find genuinely dead / unused / unreachable SOURCE code - unused functions, classes, methods, exports, and unreachable branches that a linter's local-scope rules miss. Wraps the right whole-program tool for the stack (vulture, knip, go deadcode, etc.) with a curated allowlist for the project's dynamic-reference patterns so findings are low-noise and safe to act on. Generic skill - forge-adapt tailors the tool, paths, and false-positive patterns to the project. Use when the user asks to "find dead code", "remove unused code", "what code is unused", "dead-code scan", or "clean up the codebase" before a refactor or release.
---

<!-- find-dead-code-version: 1 -->

# Find Dead Code

Locate genuinely-dead source code so it can be removed safely - WITHOUT proposing the deletion
of code that only *looks* unused because it is referenced dynamically (routes, DI, reflection,
serialization, string-keyed dispatch, public exports). This is the SOURCE-code counterpart to
`dep-auditor` (which owns unused *dependencies*).

> **This is a generic template.** `forge-adapt` adapts the tool choice, scan paths, confidence
> threshold, and the dynamic-reference table below to the project's actual stack and frameworks.

## The load-bearing rule

> **The tool flags CANDIDATES, not verdicts.** Never delete a symbol because the scanner listed
> it. Every candidate must be confirmed to have no *dynamic* reference before removal, and the
> **build + full test suite is the real safety net** - static/grep analysis cannot see reflection,
> field-name aliases, or dynamic dispatch, but a green build + tests catch what the scan misses.
> Deleting a dynamically-referenced symbol (a route handler, an ORM column, a DI provider, a
> migration hook) compiles fine and breaks production silently.

## Local vs global dead code - use the right tool

- **Local** (unused imports, unused locals, redefinitions) is almost always already caught by the
  project's linter/compiler in CI - Python `ruff`/pyflakes (`F401/F811/F841`), ESLint
  `no-unused-vars`, `tsc --noUnusedLocals`, Go `vet`, the Rust compiler. Do not re-report it.
- **Global / whole-program** (unused functions, classes, methods, exports, whole files,
  unreachable branches) is what a linter does NOT find and what this skill targets. It needs a
  dedicated reachability tool.

## Tool by language (pick + pin the one(s) for the stack)

| Language | Whole-program dead-code tool | Notes |
|---|---|---|
| Python | **vulture** (+ `dead`) | confidence threshold; curated allowlist for dynamic names |
| TypeScript / JavaScript | **knip** (gold standard: unused files, exports, types, deps) | declare entry points; understands re-exports; `ts-prune` is the older, narrower option |
| Go | **`golang.org/x/tools/cmd/deadcode`** (call-graph reachability) | pair with `staticcheck` U1000; reflection caveat |
| Rust | built-in `dead_code` lint (aggressive, often sufficient) | `cargo-machete` / `cargo-udeps` for deps |
| PHP | **shipmonk/dead-code-detector** (PHPStan ext) | understands Laravel/Symfony/Doctrine dynamic patterns; can flag code used only by tests |
| Java / C# | SonarQube / NDepend / Roslyn analyzers | heavy reflection + DI - expect high false-positive rate |
| Ruby | `debride` | Rails dynamic dispatch caveat |
| Mixed / monorepo | per-package runs + a mixed-repo scanner | declare entry points per package |

Install the chosen tool as a **dev-only** tool (do not add it to pinned runtime deps). During
adaptation, create a small `scripts/find-dead-code.*` runner that applies the project's
suppressions and threshold, so the scan is one repeatable command.

## Dynamic-reference categories (the false positives - adapt to the project's frameworks)

These look unused to a static analyser but are load-bearing. `forge-adapt` replaces this with the
project's actual patterns; the generic set:

| Pattern | Why it is referenced dynamically |
|---|---|
| Route / controller handlers | dispatched by the web framework by path, never called by name |
| DI / IoC providers, beans, `@Injectable` | instantiated by the container |
| Reflection / `getattr` / string-keyed registries / dynamic import | name appears only in a string |
| Serialization fields (ORM columns, DTO/schema fields) | accessed via the ORM / serializer, not by name |
| Config-referenced classes (xml/yaml/json, `beans.xml`, plugin manifests) | wired by configuration |
| CLI commands, event/signal handlers, lifecycle hooks | registered by decorator/registry |
| Migration `up`/`down`, scheduled jobs | called by the framework/runner |
| Test fixtures, `test_*` collected by the runner | invoked by the test framework |
| **Public API / exported symbols** (`__all__`, package `exports`, a library's entry points) | called by *consumers*, so "no internal caller" does NOT mean dead |

## Two detection modes

1. **Static (default).** Run the whole-program tool above at a high-signal threshold. Fast; finds
   most unreferenced symbols.
2. **Coverage / runtime (complementary, higher-confidence for reachable-but-never-executed).** Run
   the test suite (or production telemetry / feature-flag analytics) under coverage. Code the
   static tool says is reachable but that has **0 coverage in tests AND prod** is a strong dead
   lead. Caveat: low coverage alone ≠ dead (it may be untested-but-used) - cross-check before acting.

## Workflow

1. **Baseline first.** On a large existing codebase, capture the current findings as an allowlist
   baseline (e.g. vulture `--make-whitelist`, knip's config) and only ACT on *new* findings - this
   makes adoption incremental instead of a thousand-line cleanup.
2. **Run** at a high-signal threshold; group output by confidence.
3. **Verify each candidate** is really dead before believing it: grep the name (including string
   literals / registries / `__all__`), check whether it is a route/DI/config/CLI/test/exported
   symbol, and whether it is referenced only in tests (test-only = effectively dead, but confirm).
4. **Classify:**
   - **Confirmed dead** → remove in a small, single-purpose commit; run the **build + full test
     suite** after.
   - **Dynamically referenced (false positive)** → do NOT delete; add it to the allowlist with a
     one-line *why* comment, so the scan gets quieter and more trustworthy over time.
   - **Unsure** → keep it; open a ticket or ask. Bias toward keeping.
5. **Respect project invariants.** Never remove a symbol the project's `CLAUDE.md` marks as
   load-bearing on a scanner's say-so.

## Output format

Group findings into **High-confidence dead** / **Likely dead (verify dynamic refs)** /
**Probable false positives** (anything matching a dynamic category above). For each, give
`file:line — symbol (kind, confidence)` plus a one-line verification note. **Never auto-delete** -
propose removals for confirmation, or file gate-ready tickets for non-trivial cleanups.

## Scope boundary

This owns **source** dead code. Unused **dependencies** are `dep-auditor`'s job - do not
double-report them here.

## Adapting this skill (notes for forge-adapt)

- Choose the tool(s) for the project's language(s); pin as a dev-only tool; write the runner script.
- Replace the dynamic-reference table with the project's real frameworks (e.g. FastAPI routes +
  Pydantic validators + SQLAlchemy columns; or NestJS providers + TypeORM entities; or Spring beans).
- Seed the allowlist with the project's entry points (library exports, CLI, migration hooks).
- Set the high-signal threshold and, for large repos, commit a baseline.
- Decide delivery: report-only (this skill) or also file tickets through the gate (pair with the
  `code-health-auditor` pattern). Keep "never auto-remove" either way.
