---
name: milestone-counter-lags-after-close
description: check-phases rule 4 can fire for a few seconds after gh issue close on the last ticket; rerun once before acting on it
metadata:
  type: project
---

`check-phases.sh` rule 4 ("phase is done but holds N open tickets") fired on 2026-09-14 immediately after `gh issue close` on the phase's last ticket, and passed on a rerun a few seconds later with the milestone showing `open=0`. The host's milestone counters lag a close briefly; the guard reads them live.

**Why:** the guard is right to read the host rather than cache, and a false refusal that clears itself is cheaper than a stale pass. But acting on the first result (reopening the phase, moving a ticket) would be acting on a counter that has not caught up.

**How to apply:** when rule 4 fires right after closing the last ticket, rerun the guard once before doing anything; if it still fires, then look for the ticket. Related: [[develop-branch-workflow]].
