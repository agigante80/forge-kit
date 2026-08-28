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

After installing forge-kit, create all labels using `gh label create` or import them directly from `.github/labels.yml`.

To recreate labels in a new repo manually:
```bash
while IFS= read -r line; do
  name=$(echo "$line" | grep "^- name:" | sed 's/- name: //')
  # ... parse and create
done < .github/labels.yml
```

Or use the `gh-label` CLI tool:
```bash
npx github-label-sync --access-token $(gh auth token) --labels .github/labels.yml owner/repo
```

## Adding project-specific labels

Add entries to `.github/labels.yml` for your domain:
```yaml
- name: my-domain
  color: "c5def5"
  description: My project-specific area
```

Then add the label as a trigger in `ticket-gate.md`'s lens table if it should route to a lens or modulate the critic's brief.
