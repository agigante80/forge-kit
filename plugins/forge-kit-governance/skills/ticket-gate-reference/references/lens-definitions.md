<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## Lens definitions

Step 3C dispatches these.

### Security lens (label `security` or `critical`)
Use agent type: `security-auditor`. Runs AFTER the critic and receives the critic's JSON:
it reports only NET-NEW findings and explicit disagreements, never restatements of items
the critic already raised (the retired committee's sequential-execution dedup, kept). The
personal-data judgment is the critic's alone; the lens confines itself to this checklist:
- Authentication: is auth required specified? Any public endpoints justified?
- Authorization: can users access only their own data? Role checks present?
- Input validation: validation schemas specified? Max lengths? Format validation?
- Data exposure: does the response leak sensitive fields?
- OWASP Top 10: injection, XSS, CSRF, broken access control addressed?
- Rate limiting: is the endpoint rate-limited or does it need to be?
Returns `{verdict, blocking, advisory}`: the critic's shape minus `sections` (that key is
the critic's prose contract), with `class` on each blocking item (fundamental /
significant; the lens judges its own items). Step 3C's dispatch carries this contract
verbatim, so the callee never depends on a copy that can drift. The MERGE rule for these results is a rule and
lives in `ticket-gate.md` at Step 4, not here.
