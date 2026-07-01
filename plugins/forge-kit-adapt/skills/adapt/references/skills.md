# forge-kit skills: signal, component, why

Reference for Step 2 of forge-adapt. Live `ls` of `$FORGE_KIT_DIR/plugins/*/skills/` is the
source of truth for existence; this file fixes the canonical ≤60-char "why". Exclude
`forge-adapt` itself (it is the running skill).

| Signal in the project | Skill | Group | Canonical "why" (≤60) | Priority |
|---|---|---|---|---|
| Public API with auth / payments | `owasp-api-security` | security | OWASP API Top 10 test patterns | P1 |
| Designing / refactoring REST or GraphQL APIs | `api-design-principles` | backend | resource design, versioning, contracts | P1 |
| Architecting / refactoring a backend | `architecture-patterns` | backend | Clean / Hexagonal / DDD patterns | P2 |
| Microservices / distributed system | `microservices-patterns` | backend | boundaries, comms, resilience | P2 |
| Scaling reads / event sourcing | `cqrs-implementation` | backend | separate read + write models | P2 |
| Multi-step distributed transactions | `saga-orchestration` | backend | choreography / orchestration sagas | P2 |
| Aging / large codebase, pre-refactor or pre-release cleanup | `find-dead-code` | devops | find unused funcs/exports a linter misses | P2 |
| Ships releases / has a VERSION or package.json version | `release` | devops | semver bump + sync + tag + close shipped tickets | P2 |
| Merges to main as a release; bump/tag is manual (easily forgotten) | `release-automation` | devops | CI gate: block a merge that did not bump the version | P1 |

Note: the backend skills are injected knowledge, not actions, so recommend them when the project's
domain matches, not by default. `find-dead-code` is the source-code counterpart to the `dep-auditor`
agent (deps); recommend it for cleanup/refactor intent. `release-automation` is the *enforced* CI
sibling of `release`: recommend both together (the gate makes the bump unforgettable; `release`
is how a human cuts the release). Lead with at most the top 1-2; "more skills" expands the rest.
