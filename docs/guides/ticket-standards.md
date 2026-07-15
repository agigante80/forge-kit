<!-- template-version: 4 -->

# Ticket standards (canonical)

This is the **single source of truth** for what a *ready* work ticket must contain. The five
work issue-templates (`feature`, `bug`, `security`, `infrastructure`, `design`) carry the form
fields that collect this content; this document holds the **rules and the rationale**. The
`ticket-gate` agent enforces the rules, and `scripts/check-template-lockstep.sh` keeps the
templates and this doc on one shared `template-version`, so the standard cannot silently drift
apart from the forms that implement it.

Read this alongside `docs/guides/template-versioning.md`, which describes the version marker and
the gate's auto-synthesis of missing sections. The two are complementary: this doc says *what a
ready ticket needs*; that doc says *how the version marker and upgrades work*.

## Why single-source

The requirement text used to be restated in each template, in `CLAUDE.md`, and in the gate. Six
copies drift: prose says one thing while a template says another, and nobody notices until a
ticket is gated against a stale rule. Keeping the rules here, referenced (not restated)
elsewhere, plus the lockstep guard, makes "the standard is the same everywhere" mechanically
true rather than a matter of discipline.

## Required sections

A ready work ticket must satisfy every rule below whose scope the ticket actually touches.
Applicability is decided by the gate from the ticket type and the packages it affects; a rule a
ticket does not touch is marked N/A with a one-line justification, never failed. A rule that
*does* apply and is absent fails the gate.

### 1. GWT scenarios (Given / When / Then)

At least one positive and one negative scenario per independent condition, written against
specific route, model, and screen names where the ticket makes them evident. Vague restatements
of the description do not count.

### 2. Unit test specs

Concrete cases: a specific test file path, a concrete input value, and the expected output or
error code. "Add unit tests" is not a spec. **When a ticket creates or modifies an API
endpoint**, 100% automated coverage of that endpoint is required (happy path, missing-field
400s, auth 401/403, rate-limit enforcement, IDOR).

### 3. E2E test specs

For any UI-visible behaviour: a specific test suite file, setup steps, the action, and the
assertion, for both the happy and unhappy paths. **API-only tickets mark this N/A with
justification** rather than inventing a UI flow.

### 4. GDPR considerations

Identify every personal-data field the ticket touches (name, email, phone, GPS, IP). State
storage location, erasure (Article 17), portability (Article 20), data minimisation and
retention (Article 25), the legal basis, and any cross-border transfer. A ticket that touches no
PII marks this N/A with that reason.

### 5. Security checklist

Authentication and authorization requirements, input validation schemas, data-exposure review,
and the relevant OWASP Top 10 items for the change. Rate limiting is specified or justified as
unnecessary.

### 6. Required reviews

The reviews the ticket must pass before it is considered done, checked off explicitly. This is
the ticket author's acknowledgement of the gate, not a substitute for it.

## The N/A rule (load-bearing)

A coverage or E2E requirement that a docs-only, research, infra-only, or API-only ticket cannot
satisfy makes that ticket **un-passable**, which trains people to box-tick and rots the whole
gate. Every rule here is scoped: it applies only to tickets whose type and affected packages
bring it into play, and the gate derives that scope rather than asking the author to self-declare
it. When you add a new rule with a coverage-style requirement, give it an explicit
type-and-area scope here, or it will backfire.
