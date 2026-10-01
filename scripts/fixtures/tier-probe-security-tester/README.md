# tier-probe-security-tester fixture

**`server.py` is vulnerable ON PURPOSE.** It is the seed for #292, the re-measurement of which model
tier `api-security-tester` needs. It binds to `127.0.0.1` only, nothing in CI, no hook and no install path starts it
(`reference_test.py` does, and a bare `python3 -m pytest` at the repo root collects it, so run that
only with port 8765 free), and its tokens are fake literals, not credentials.
Start it by hand, on loopback, and only to reproduce the measurement. Never bind it to a
non-loopback address and never deploy it anywhere.

This is a sibling of `scripts/fixtures/tier-probe-security/`, which is left byte-identical so the
recorded #289 `security-auditor` rows and the line numbers its README cites stay valid. It is the
same service with three edits: `users` gains an `is_admin` column (ana 1, ben 0), the hard-coded admin
token and its header check are removed, and `/admin/users` keeps only the 401 every
route already has. P1 and P2 are the shared seed's, unchanged. It is still named `server.py`, so
#289's pinned tester prompt runs verbatim. See `../tier-probe-security/README.md` for the original.

`server_fixed.py` is the same service with P1, P2 and P3' fixed. Besides those fixes only its module
docstring differs. It keeps, deliberately, the weaknesses that are not planted, for example no
`Host` check, no rate limit and plaintext token storage.

`reference_test.py` is the answer key, not part of any run: it proves each planted issue has a
black-box witness. It never enters a run directory. It starts the server named by `SERVER_FILE`
(default `server.py`, resolved beside the test) on `127.0.0.1:8765`. From this directory:

```
SERVER_FILE=server.py       python3 -m pytest -p no:cacheprovider -q reference_test.py   # 3 failed
SERVER_FILE=server_fixed.py python3 -m pytest -p no:cacheprovider -q reference_test.py   # 3 passed
```

## The planted issues

Line numbers are those of `server.py` as committed.

| # | Issue | Where | Counts as covered when |
|---|---|---|---|
| P1 | SQL injection, f-string into `execute` | `server.py:39` | at least one test fails on `server.py` and passes on `server_fixed.py` |
| P2 | Broken object-level authorization, API1:2023 | `server.py:43` | same rule |
| P3' | Broken function-level authorization, API5:2023: `/admin/users` checks the caller is authenticated, never that the caller is admin | `server.py:48` | same rule, and the test must send a non-admin credential |

P3' has a one-request black-box witness: ben's valid token reads `/admin/users` and gets 200, where
`server_fixed.py` answers 403. It is not a verb-tampering case: the seed defines only `do_GET`, so
`POST` and `HEAD` return 501 and are not a witness.

## The criterion, fixed before any run

- A run passes when, for each of P1, P2 and P3', at least one generated test fails against
  `server.py` and passes against `server_fixed.py`. A test failing or passing on both is recorded
  and decides nothing; a test that cannot run covers nothing.
- A tier passes when all three of its runs pass. If an Opus run fails, the seed or the criterion is
  at fault and no role moves.
- A role moves to `sonnet` only when Sonnet passes 3/3 and its median output tokens and its median
  cache reads are both no higher than Opus's.

Pre-registered reading of one outcome: if an Opus run misses P3' after the reference test has proven
its witness, it is recorded as a possible tester-agent gap
(`plugins/forge-kit-security/agents/api-security-tester.md` lines 36 to 38) and a follow-up is filed;
no role moves either way.

## The run matrix

`api-security-tester` x {`opus`, `sonnet`} x 3, effort `high`, the tier named at the dispatch site,
one after another on port 8765. Harness conditions, the same as #289:

- headless, with the tree's `forge-kit-security` group loaded via `--plugin-dir` and the installed
  copy disabled;
- `claudeMdExcludes` set for this checkout's CLAUDE.md;
- a fresh run directory OUTSIDE the checkout holding a copy of `server.py` alone, checked before the
  session with `[ "$(ls -A "$RUN")" = server.py ]`;
- after each session, the generated tests judged with `python3 -m pytest tests/` against `server.py`
  and then `server_fixed.py`, each started by hand on loopback; before starting each server, confirm
  8765 is free (`ss -ltn | grep -q ':8765 ' && echo busy`);
- costs from `python3 scripts/measure-dispatch-cost.py <session.jsonl>`.

The dispatch prompt, pinned in issue #289 (the "dispatch prompts, pinned (round 3)" bullet) and
copied verbatim, never reworded:

> Write security tests for the HTTP JSON API in server.py in this directory. It listens on 127.0.0.1:8765 when started with `python3 server.py`. Put the tests in a tests/ subdirectory of this directory as pytest files using only the standard library plus pytest, runnable with `python3 -m pytest tests/` against a server already listening on 127.0.0.1:8765. Only ever contact 127.0.0.1. Then report which of your tests fail against the current code and what each failure means.

The runs and the outcome are recorded in `docs/guides/model-tiers.md`.
