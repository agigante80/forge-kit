# tier-probe-security fixture

**`server.py` is vulnerable ON PURPOSE.** It is the seed for #289, the re-measurement of which model
tier the two security agents need. It binds to `127.0.0.1` only, nothing in this repository starts
it (no workflow, hook, install path or test suite), and its tokens are fake literals, not
credentials. Start it by hand, on loopback, and only to reproduce the measurement.

`server_fixed.py` is the same service with the three planted issues fixed and nothing else changed.
It keeps, deliberately, every weakness that is not planted: no `Host` check and no rate limit.

## The planted issues

| # | Issue | Where | Floor | Counts as found when the run |
|---|---|---|---|---|
| P1 | SQL injection (f-string into `execute`) | `server.py:40` | high | names the `/items` query or line 40 as injectable |
| P2 | Broken object-level authorization, OWASP API1:2023 | `server.py:44` | high | says any authenticated user can read another user's order through `/orders/<id>` or line 44 |
| P3 | Hard-coded admin secret, compared with `!=` | `server.py:14`, `server.py:50` | medium | names the literal token in source as the defect (the non-constant-time compare alone does not count) |

A finding below its floor counts as missed. `/items` filters by the caller's `user_id`, so it has
no cross-user read apart from the injection.

## The criterion, fixed before any run

- `security-auditor`: a run passes when it finds P1, P2 and P3 at or above their floors.
- `api-security-tester`: judged per planted issue. A run passes when, for each of P1, P2 and P3, at
  least one generated test fails against `server.py` and passes against `server_fixed.py`. A test
  failing or passing on both files is recorded and decides nothing; a test that cannot run covers
  nothing. The tests are run with `python3 -m pytest tests/` against each server in turn on
  `127.0.0.1:8765`, `server_fixed.py` started with `ADMIN_TOKEN` unset.
- A tier passes an agent when all three of its runs pass. If an Opus run fails, the seed or the
  criterion is at fault and no role moves.
- A role moves to `sonnet` only when Sonnet passes 3/3 and its median output tokens and median cache
  reads are both no higher than Opus's.

The two dispatch prompts are pinned in issue #289; the runs and the outcome are in
`docs/guides/model-tiers.md` under "The re-measurement (#289)".
