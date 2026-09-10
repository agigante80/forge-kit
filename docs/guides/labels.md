# Label Taxonomy

GitHub labels serve dual purpose: issue organization AND lens routing in ticket-gate (which lenses join the critic, and how its brief is modulated).

## Label categories

### Type labels
| Label | Description | Creates in GitHub |
|---|---|---|
| `bug` | Something isn't working | Yes |
| `enhancement` / `feature` | New feature or request | Yes |
| `security` | Security vulnerability or hardening | Yes - adds the security lens |
| `infrastructure` | DevOps, CI/CD, deployment | Yes |
| `design` | Wireframes, UX, accessibility | Yes |
| `documentation` | Docs updates | Yes |
| `testing` | Tests, QA, coverage | Yes |

### Area labels (modulate the gate's review set)
| Label | Description | Triggers |
|---|---|---|
| `api` | API routes or contracts | API-design checklist added to the critic's brief |
| `privacy` | Touches personal data | The project's installed `privacy-regime` skill is added to the critic's brief. Without that skill the label does nothing: rule 4's seven regime-agnostic facts are always the bar |
| `web` | Web frontend | - |
| `mobile` | Mobile app | - |
| `backend` | Backend services | - |
| `database` | Database schema or migrations | Add schema-guardian if applicable |
| `components` | An agent, skill, command, hook or shipped shell asset | - |
| `tooling` | The guards, scripts and CI that enforce the rules | - |
| `governance` | Templates, labels, ticket standards, the roadmap and the docs that carry them | - |

**The last three are for a governance repository, and forge-kit is one (#188).** The six above them
are product-application areas, written for the projects forge-kit is installed into: they describe
API routes, a frontend, a mobile app, backend services, a schema, personal data. None of them
describes a plugin component or a CI guard, so every ticket filed in forge-kit's own tracker blocked
at the gate's Step 0b until these existed. That was found by the first live gate run in this
repository, on the first ticket it was pointed at.

They route nothing, deliberately. CLAUDE.md's rule is to prefer modulating the critic's brief over
adding a lens, and a label that changes the review set has to earn it on its own evidence.

**This table is the ONE definition of the area set.** `scripts/check-label-taxonomy.sh` fails the
build when any other copy disagrees with it. There are three others: `.github/labels.yml`, which is
what `sync-labels.sh` puts on the host; `check-ticket-mechanics.sh`'s `AREA_LABELS` default; and
`ticket-gate.md`'s Step 0b. Those three had drifted apart before the guard existed, in three
different directions at once.

### Priority labels
| Label | Meaning |
|---|---|
| `P0` | Critical - blocks release |
| `P1` | High - important for current milestone |
| `P2` | Medium - should do, not blocking |
| `P3` | Low - nice to have |

### Special labels
| Label | Effect |
|---|---|
| `critical` | Adds the security lens and puts the critic in maximum scrutiny |

## Installing labels

After installing forge-kit, sync the taxonomy from `.github/labels.yml` with the shipped script:

```bash
# Run it from wherever it was installed; it sources forge-lib.sh from its OWN directory,
# so keep the two together (forge-adapt copies both).
bash sync-labels.sh                 # create every declared label, update any that drifted
bash sync-labels.sh --check         # change nothing; exit 1 listing what is missing or drifted
FORGE_DRY_RUN=1 bash sync-labels.sh # print what it would WRITE; it still READS the host, so
                                    # it needs credentials and reports against real state
```

It is host-aware (GitHub and Forgejo), idempotent, refuses a malformed declaration rather than
syncing part of it, and **never deletes**: a label on the host that
this file does not declare is reported and left alone.

Do NOT create these by hand. This taxonomy was declared and never imported for months (issue #104):
18 labels declared, 4 present, and three of the missing ones (`security`, `critical`, `api`) are
executable inputs to the gate's lens routing, so the kit's most distinctive mechanism was
unexercisable in the repo that ships it. A manual instruction is what allowed that.

## Adding project-specific labels

Add entries to `.github/labels.yml` for your domain:
```yaml
- name: my-domain
  color: "c5def5"
  description: My project-specific area
```

Then add the label as a trigger in `ticket-gate.md`'s lens table if it should route to a lens or modulate the critic's brief.
