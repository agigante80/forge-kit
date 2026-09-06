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

It is host-aware (GitHub and Forgejo), idempotent, and **never deletes**: a label on the host that
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
