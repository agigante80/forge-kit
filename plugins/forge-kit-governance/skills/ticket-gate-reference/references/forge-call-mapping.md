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
| close an issue | `forge_issue_close <N>` |
| edit an issue body | `forge_api PATCH "/repos/$REPO/issues/<N>" "$(jq -nc --arg b "<body>" '{body:$b}')"` |
| create a follow-up issue | `forge_issue_create "<title>" "<body>"`, then `forge_issue_label <N> <name…>` for labels (refuse-all on Forgejo: an unresolvable name fails the WHOLE call non-zero and applies nothing, so check the exit and create missing labels first) |
| list/search issues | `forge_issue_list [state]`, filter client-side |
