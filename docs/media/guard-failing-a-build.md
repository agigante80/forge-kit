# A guard failing a build (captured 2026-11-13)

Real output of `check-template-lockstep.sh`, run against a scratch copy of this repository's issue
templates and ticket standards in which one template (`bug.yml`) was deliberately set back to
`template-version: 5`. In CI the same exit code fails the `Validate` job.

```text
$ bash check-template-lockstep.sh .github/ISSUE_TEMPLATE docs/guides/ticket-standards.md
check-template-lockstep: template-version DRIFT (expected one shared version):
  v6  docs/guides/ticket-standards.md
  v5  .github/ISSUE_TEMPLATE/bug.yml
  v6  .github/ISSUE_TEMPLATE/design.yml
  v6  .github/ISSUE_TEMPLATE/feature.yml
  v6  .github/ISSUE_TEMPLATE/infrastructure.yml
  v6  .github/ISSUE_TEMPLATE/security.yml

All work templates and the canonical ticket-standards doc must share one template-version.
$ echo $?
1
```

The guard names the file that drifted and the shared version it should match. Restore the marker and
it exits 0. The rule behind it is in [Template versioning](../guides/template-versioning.md).
