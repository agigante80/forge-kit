<!-- Moved out of SKILL.md by #150. A skill's SKILL.md is PRELOADED into the agent that declares
     it; a file under references/ is NOT, and is read on demand. This material is read at one
     point in a run, so preloading it charged every run for it. -->

## forge_* call mapping

Which adapter call serves each need. The RULE, that every forge call goes through `forge_*` and
never through `gh` directly, is in `ticket-gate.md`; this is the lookup.

| Need | Call |
|---|---|
| view an issue (body/labels/title) | `forge_issue_view <N>` → JSON `{number,title,body,state,labels[].name}` |
| comment on an issue | `forge_issue_comment <N> "<body>"` |
| list comments on an issue (all pages) | `forge_issue_comments <N>` (v14; `count-gate-rounds.sh` reads it) |
| close an issue | `forge_issue_close <N>` |
| write ONE region of an issue body | `forge_body_region_set <N> gate <region> "<content>" [top]` / `forge_body_region_clear <N> gate <region>` (v24; `top` since v27 places or moves the region to the top). Splices one region and preserves every other byte, refuses a region not prefixed `gate` (101), a body that moved since it was read (102), and a malformed or duplicated marker pair (103) |
| read one region | `forge_body_region_get <N> <region>` (v24; no prefix check, empty and rc 0 when absent) |
| rewrite a WHOLE body | `forge_body_compose_preserving <N> "<body>"` (v24; NO prefix. It re-threads every region it finds, the gate's own included, so an author-section rewrite cannot drop Step 2.9's context. A region restated in the new body is kept once) |
| edit an issue body wholesale | `forge_issue_edit <N> "<body>"` (v13). **Not for the gate since v24**: it replaces the whole body, which is how two writers destroy each other. The body is `$2`, a string, never a file path: a gate once passed `--body-file` and the issue body became that literal string |
| create a follow-up issue | `forge_issue_create "<title>" "<body>"`, then `forge_issue_label <N> <name…>` for labels (refuse-all on Forgejo: an unresolvable name fails the WHOLE call non-zero and applies nothing, so check the exit and create missing labels first) |
| list/search issues | `forge_issue_list [state]`, filter client-side |
