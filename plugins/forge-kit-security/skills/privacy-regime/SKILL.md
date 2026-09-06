---
name: privacy-regime
description: Name this project's privacy regime and its concrete obligations, so the ticket gate asks the RIGHT compliance questions instead of a default jurisdiction's. Opt-in and adapted per project - forge-adapt offers it when it detects personal-data handling, and never installs it silently. Use when setting up governance for a project that stores personal data, when the gate's personal-data questions do not match your jurisdiction, or when asked about GDPR, UK GDPR, CCPA, CPRA, LGPD, PIPEDA, APPI or any other privacy regime.
---

<!-- privacy-regime-version: 1 -->

# Privacy regime (opt-in, per project)

**This file is a TEMPLATE. Fill in your regime before relying on it.** Shipped blank on purpose:
forge-kit names no jurisdiction anywhere in its defaults (issue #101), because for most projects
any single named regime is the wrong one, and a gate citing the wrong statute is worse than a gate
citing none. It looks authoritative and is not.

## What the default already does without this skill

`docs/guides/ticket-standards.md` rule 4 requires **seven regime-agnostic facts** about any ticket
touching personal data, and `ticket-gate` blocks on their absence:

1. Every personal-data field the ticket touches
2. Storage location and encryption at rest
3. Erasure, including cascading deletion of dependent records
4. Portability
5. Minimisation and retention
6. The legal basis
7. Any cross-border transfer

Those seven exist under GDPR, UK GDPR, CCPA and CPRA, LGPD, PIPEDA and APPI, under different
names, different thresholds and different article numbers. **A project with no specific regime
needs nothing beyond them.** Install this skill only when you have a regime and want its depth.

## How it reaches the gate

Label a ticket `privacy` and `ticket-gate` adds the section below to the critic's brief. It is a
brief modulation, not a new agent, following the same pattern as the `api` row in the gate's lens
table: a privacy regime is not an independent domain perspective, it is the same rule 4 judgment
with your jurisdiction's names and thresholds attached.

Without the label, rule 4's seven facts remain the bar. Without this skill installed, the label
does nothing.

## Fill this in

Replace every bracketed value. Delete the regimes that do not apply to you.

**Regime:** `[e.g. UK GDPR / GDPR (EU) / CCPA + CPRA / LGPD / PIPEDA / APPI]`
**Territorial scope:** `[which users or markets bring you under it]`
**Supervisory authority or regulator:** `[e.g. the ICO]`
**Where the full policy lives:** `[link to your privacy policy or DPIA register]`

### Obligations to check on a personal-data ticket

Map each of the seven facts above onto what YOUR regime actually requires, with its own citation.
The mapping matters more than the citation: a reviewer needs to know the threshold, not the article
number.

| Rule 4 fact | This regime's requirement | Citation | Threshold or deadline |
|---|---|---|---|
| Fields touched | `[...]` | `[...]` | `[...]` |
| Storage and encryption at rest | `[...]` | `[...]` | `[...]` |
| Erasure and cascading deletion | `[...]` | `[...]` | `[e.g. respond within N days]` |
| Portability | `[...]` | `[...]` | `[machine-readable format?]` |
| Minimisation and retention | `[...]` | `[...]` | `[stated retention period]` |
| Legal basis | `[...]` | `[...]` | `[consent? contract? legitimate interest?]` |
| Cross-border transfer | `[...]` | `[...]` | `[adequacy? SCCs? not permitted?]` |

### Regime-specific obligations with no rule 4 equivalent

Some regimes require things the seven neutral facts do not cover. List them here, or delete this
section.

- `[e.g. a "Do Not Sell or Share My Personal Information" link, under CPRA]`
- `[e.g. a DPIA for high-risk processing]`
- `[e.g. breach notification within a stated window, and to whom]`

### What is NOT in scope for this project

Recording this is as useful as the obligations, because it stops a reviewer inventing work.

- `[e.g. no special-category data is processed]`
- `[e.g. no automated decision-making with legal effects]`

## Multiple regimes

A project serving several markets is under several regimes at once. Repeat the table per regime
rather than merging them: the thresholds differ, and a merged table hides which one binds. Where
they conflict, record which is stricter and follow that, so a reviewer does not have to re-derive
it per ticket.

## Keeping it honest

This skill is **not legal advice and must not read as if it is**. It records what your team has
already determined, so the gate can check tickets against it. If nobody on the project can fill in
the table, that is the finding: the answer is not to guess, it is to leave this skill uninstalled
and let rule 4's seven neutral facts stand until someone can.
