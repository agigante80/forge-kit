#!/usr/bin/env bash
# Contract test for /ci-health's host branch (issue #552).
#
# THE DEFECT IT GUARDS. ci-health listed only `.github/workflows/*` and used `gh run` for every
# step. On a Forgejo repo whose CI lives in `.forgejo/workflows/` the discovered set was empty, and
# the "All workflows green" stop rule fired vacuously: a red pipeline read as green. A dormant
# `.github/workflows/` left over from a migration was queried with `gh` instead of the live one.
#
# WHAT IT PINS. ci-health.md is prose, so most rows read one SECTION (the lines from one `###`
# heading to the next), never the whole file, so a stray sentence elsewhere cannot satisfy them.
# Where the prose carries a runnable line (the lib-free origin-host read, the refusal block, the
# directory choice, the dedupe key, the label filter) the row EXTRACTS exactly that one line or
# block and RUNS it in a child bash against a fixture, the ext537 pattern of test-producer-stamps.sh,
# so a reflow or a deleted line fails as "no-extract" rather than passing vacuously.
# forge_workflow_dir itself is executable and is tested in test-forge-lib.sh.
#
# DECISION (#552, unattended run 2026-10-26): an open Forgejo ticket is updated in its BODY with
# forge_body_region_set, not with forge_issue_comment. The ticket's round 3 answer said comment;
# #565 shipped later the same day and made "a ticket is read by its body, never a comment" the rule
# for ci-health's GitHub path and the forge-write-consent hook denies an unconsented comment. The
# row "no status comment" pins that; do not "restore" the comment.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
CIH="${CI_HEALTH_UNDER_TEST:-$REPO/plugins/forge-kit-devops/commands/ci-health.md}"   # override: run against the pre-fix file
CMDS="$REPO/plugins/forge-kit-adapt/skills/adapt/references/commands.md"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
unset FORGEJO_TOKEN GITHUB_TOKEN GH_TOKEN FORGE_HOST FORGE_API_URL FORGE_REMOTE

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# sect <file> <heading text>: the lines of the `###` section whose heading contains the text, each
# prefixed with its line number and a colon, up to the next `##` or `###` heading.
sect() {
  awk -v h="$2" '
    /^##+ / { if (on) exit; if (index($0, h)) { on = 1; next } }
    on { print NR ":" $0 }' "$1"
}
# lineof <section text> <fixed string>: the first line number carrying the string, else 0.
lineof() { local n; n=$(printf '%s\n' "$1" | grep -F -- "$2" | head -1 | cut -d: -f1); printf '%s' "${n:-0}"; }

# one <file> <ERE>: the single line matching, leading space stripped; "no-extract" unless exactly one.
one() {
  local n; n=$(grep -cE -- "$2" "$1")
  if [ "$n" != 1 ]; then printf 'no-extract'; return; fi
  grep -E -- "$2" "$1" | sed 's/^[[:space:]]*//'
}

# block0 <file>: the first fenced block of Phase 0 (the host check), fence lines dropped.
block0() {
  sect "$1" 'Phase 0' | cut -d: -f2- | awk '/^```/ { if (on) exit; on = 1; next } on { print }'
}

# fixture repo with an origin
mkorigin() { local d="$T/o.$1"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q . && git -C "$d" remote add origin "$2"; printf '%s' "$d"; }

TOKEN='tok552SECRETvalue'
# host <file> <origin>: run the file's own ORIGIN_HOST= line in a child bash in a fixture repo.
host() {
  local l d; l=$(one "$1" '^[[:space:]]*ORIGIN_HOST=')
  [ "$l" = no-extract ] && { printf 'no-extract'; return; }
  d=$(mkorigin h "$2")
  ( cd "$d" && bash -c "$l"$'\n''printf "%s" "$ORIGIN_HOST"' 2>&1 )
}

# refuse <file> <origin> [lib]: run the Phase 0 block in a fixture repo with a logging gh on PATH and
# a logging forge_host; prints "rc=<n>|<stdout+stderr>|gh=<calls>|fh=<calls>|HOST=<value>".
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<SH
#!/usr/bin/env bash
echo "gh \$*" >> "$T/gh.log"
SH
chmod +x "$T/bin/gh"
refuse() {
  local b d out rc
  b=$(block0 "$1"); [ -n "$b" ] || { printf 'no-extract'; return; }
  d=$(mkorigin r "$2"); : > "$T/gh.log"; : > "$T/fh.log"
  case "${3:-}" in
    lib) mkdir -p "$d/scripts"; printf 'forge_url_check() { return 0; }\nforge_host() { echo forgejo; }\n' > "$d/scripts/forge-lib.sh" ;;
    libpin)   # review round 1 (codex): a branch's FORGE_HOST must hit the pin, not choose the gh path
      mkdir -p "$d/scripts"; printf 'forge_url_check() { echo "forge-lib: refusing: pin" >&2; return 2; }\nforge_host() { echo github; }\n' > "$d/scripts/forge-lib.sh" ;;
  esac
  out=$( cd "$d" && PATH="$T/bin:$PATH" bash -c "forge_host() { echo x >> '$T/fh.log'; echo github; }"$'\n'"$b"$'\n''echo "HOST=$HOST"' 2>&1 ); rc=$?
  printf 'rc=%s|%s|gh=%s|fh=%s' "$rc" "$out" "$(wc -l < "$T/gh.log" | tr -d ' ')" "$(wc -l < "$T/fh.log" | tr -d ' ')"
}

# wfdir <file> <host>: the file's own WF_DIR= line with a stubbed forge_workflow_dir.
wfdir() {
  local l; l=$(one "$1" '^[[:space:]]*if \[ "\$HOST" = github \]; then WF_DIR=')
  [ "$l" = no-extract ] && { printf 'no-extract'; return; }
  HOST="$2" bash -c 'forge_workflow_dir() { echo .forgejo/workflows; }'$'\n'"$l"$'\n''printf "%s" "$WF_DIR"' 2>&1
}

# dedupe <file> <titles...>: the file's own EXISTING= line over a stubbed forge_issue_list that
# returns one open issue per title, numbered from 1.
dedupe() {
  local f="$1" l json; shift
  l=$(one "$f" '^[[:space:]]*EXISTING=')
  [ "$l" = no-extract ] && { printf 'no-extract'; return; }
  json=$(printf '%s\n' "$@" | jq -R . | jq -s 'to_entries | map({number: (.key + 1), title: .value})')
  BRANCH=main J="$json" bash -c 'forge_issue_list() { printf "%s" "$J"; }'$'\n'"$l"$'\n''printf "%s" "$EXISTING"' 2>&1
}

# branch <file> [<origin HEAD target>]: the file's own BRANCH= line run in a fixture repo whose
# refs/remotes/origin/HEAD points at the target, or is absent with no target (review round 1: the
# command printed the branch but never assigned BRANCH, so every later "$BRANCH" was empty).
branch() {
  local l d; l=$(one "$1" '^[[:space:]]*BRANCH=')
  [ "$l" = no-extract ] && { printf 'no-extract'; return; }
  d=$(mkorigin b 'https://forge.example/o/r')
  if [ -n "${2:-}" ]; then
    git -C "$d" -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m x
    git -C "$d" update-ref "refs/remotes/origin/$2" HEAD
    git -C "$d" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"
  fi
  ( cd "$d" && BRANCH=stale bash -c "$l"$'\n''printf "%s" "$BRANCH"' 2>&1 )
}

# labels <file> <have...>: the file's own `for l in` label filter line; prints "USE=..|SKIP=..".
labels() {
  local f="$1" l; shift
  l=$(one "$f" '^[[:space:]]*for l in .*USE\+=')
  [ "$l" = no-extract ] && { printf 'no-extract'; return; }
  HAVE="$(printf '%s\n' "$@")" bash -c 'USE=(); SKIP=()'$'\n'"$l"$'\n''printf "USE=%s|SKIP=%s" "${USE[*]}" "${SKIP[*]}"' 2>&1
}

# verdicts <ci-health copy> <commands.md copy>: one line per broken invariant, empty when all hold.
# Every mutant below must make this print the message its ledger row names.
verdicts() {
  local f="$1" c="$2" p0 p1 p2 p4 n a b r
  p0=$(sect "$f" 'Phase 0'); p1=$(sect "$f" 'Phase 1'); p2=$(sect "$f" 'Phase 2'); p4=$(sect "$f" 'Phase 4')

  # discovery
  if ! grep -q 'forge_workflow_dir' <<< "$p1" || grep -qF 'ls .github/workflows/*.yml' <<< "$p1"; then
    echo "discovers only .github/workflows"; fi
  [ "$(wfdir "$f" github)" = .github/workflows ] || echo "GitHub host takes the Forgejo order"
  [ "$(wfdir "$f" forgejo)" = .forgejo/workflows ] || echo "Forgejo host ignores forge_workflow_dir"

  # an empty set is never green
  a=$(lineof "$p1" 'No workflows found'); b=$(lineof "$p1" 'All workflows green')
  r=$(printf '%s\n' "$p1" | grep -F 'No workflows found' | head -1)
  if [ "$a" = 0 ] || [ "$b" = 0 ] || [ "$a" -ge "$b" ]; then echo "empty discovery can read as green"
  else case "$r" in *.forgejo/workflows*.gitea/workflows*.github/workflows*) ;; *) echo "empty discovery can read as green" ;; esac; fi

  # gh only inside blocks whose first line is `# GitHub path`
  awk '
    /^[[:space:]]*```/ { if (in_f) { in_f = 0; gh = 0 } else { in_f = 1; first = 1 } ; next }
    in_f && first { first = 0; if ($0 ~ /^# GitHub path$/) gh = 1 }
    !gh && /gh run / { print "gh run outside the GitHub path" }
    !gh && /gh issue / { print "gh issue outside the GitHub path" }' "$f" | sort -u
  for n in forge_ci_status forge_issue_list forge_issue_create forge_issue_label forge_body_region_set forge_api_paginate; do
    grep -q "$n" "$f" || { echo "no host branch"; break; }
  done
  grep -q 'forge_issue_create' <<< "$(grep -F -- '- **No match:**' <<< "$p2")" || echo "no host branch"
  grep -q 'forge_issue_comment' "$f" && echo "a status update posted as a comment (#565)"

  # status words
  row() { grep -E "^\| $1 \|" "$f" | head -1; }
  case "$(row '`success`')" in *"| not ticketed |") ;; *) echo "success would be ticketed" ;; esac
  case "$(row '`failure`')" in *"| ticketed (Phase 2) |") ;; *) echo "a red branch would not be ticketed" ;; esac
  case "$(row '`cancelled`')" in *superseded*"| not ticketed |") ;; *) echo "cancelled would be ticketed" ;; esac
  case "$(row '`none`')" in *"no CI run found"*"| not ticketed |") ;; *) echo "none would be ticketed" ;; esac
  case "$(row '`pending`')" in *"not green"*"| not ticketed |") ;; *) echo "pending would be ticketed" ;; esac
  case "$(row '`not_configured`')" in *"CI status unavailable (not_configured)"*stderr*"| not ticketed |") ;; *) echo "not_configured would be ticketed" ;; esac
  case "$(row 'any other word')" in *'`unknown status <word>`'*"not green"*"| not ticketed |") ;; *) echo "unknown status would be ticketed" ;; esac
  grep -q 'release or *[0-9]*:* *version-gate classification is not done on Forgejo' <<< "${p1//$'\n'/ }" \
    || echo "release-gate classification claimed on Forgejo"
  [ "$(one "$f" '^[[:space:]]*SHA=')" = 'SHA=$(git rev-parse --verify "$BRANCH" 2>/dev/null)' ] || echo "the sha shown is not the one judged"

  # Phase 2 on Forgejo
  grep -qF '`CI failure: <branch> (<WF_DIR>)`' <<< "$p2" || echo "title is not the branch form"
  grep -q 'fix(ci): .* failing (' <<< "$p2" && echo "title is not the branch form"
  [ "$(dedupe "$f" 'CI failure: main (.forgejo/workflows)')" = 1 ] || echo "duplicate ticket on a red branch"
  [ "$(dedupe "$f" 'CI failure: main-old (.forgejo/workflows)')" = "" ] || echo "main-old matches main"
  [ "$(dedupe "$f" 'CI failure: main-old (.forgejo/workflows)' 'CI failure: main (.gitea/workflows)')" = 2 ] || echo "duplicate ticket on a red branch"
  r=$(printf '%s\n' "$p2" | grep -F 'forge_body_region_set' | head -1)
  a=$(printf '%s\n' "$p2" | tr '\n' ' ')
  case "$a" in *"never a comment and never a second ticket"*'`forge_issue_create` is not called'*) ;; *) echo "an open ticket gets a second ticket" ;; esac
  [ -n "$r" ] || echo "an open ticket gets a second ticket"
  r=$(grep 'run URL' <<< "$p2"); [ -n "$r" ] && grep -vq 'no run URL' <<< "$r" && echo "a run URL reaches the Forgejo ticket"
  [ "$(labels "$f" bug)" = "USE=bug|SKIP=infrastructure" ] || echo "one unknown label drops the call"
  [ "$(labels "$f")" = "USE=|SKIP=bug infrastructure" ] || echo "one unknown label drops the call"
  case "$a" in *"report every skipped name"*) ;; *) echo "skipped labels not reported" ;; esac
  case "$a" in *'With `USE` empty, do not call `forge_issue_label`'*) ;; *) echo "an empty label list still calls forge_issue_label" ;; esac
  case "$a" in *"created but labels were refused: <stderr line>"*) ;; *) echo "a label refusal is hidden" ;; esac

  # Phase 4
  grep -q 'job logs are not reachable on Forgejo' <<< "$(grep 'Forgejo' <<< "$p4" | grep -i 'skip')" \
    || echo "Phase 4 does not skip on Forgejo"

  # Phase 0: the refusal never depends on the library it tests for
  a=$(lineof "$p0" '[ -f scripts/forge-lib.sh ]'); b=$(lineof "$p0" '. scripts/forge-lib.sh'); n=$(lineof "$p0" 'forge_host')
  if [ "$a" = 0 ] || [ "$b" = 0 ] || [ "$a" -ge "$b" ] || [ "$n" = 0 ] || [ "$a" -ge "$n" ]; then
    echo "refusal depends on the library it tests for"; fi
  printf '%s\n' "$p0" | awk -F: '{ sub(/^[0-9]+:/, "") } /^else$/ { e = 1 } e && /forge_host/ { print "refusal depends on the library it tests for" } /^fi$/ { e = 0 }' | sort -u
  r=$(refuse "$f" "https://u:$TOKEN@forge.example/o/r")
  case "$r" in "rc=1|ci-health needs scripts/forge-lib.sh on a non-GitHub host (host: forge.example)|gh=0|fh=0") ;;
    *"$TOKEN"*) echo "token reaches the refusal" ;; *) echo "a non-GitHub origin without the adapter is not refused" ;; esac
  [ "$(refuse "$f" 'git@github.com:o/r.git')" = "rc=0|HOST=github|gh=0|fh=0" ] || echo "a GitHub origin without the adapter is refused"
  [ "$(refuse "$f" 'https://forge.example/o/r' lib)" = "rc=0|HOST=forgejo|gh=0|fh=0" ] || echo "the adapter is not sourced when present"
  [ "$(refuse "$f" 'https://github.com/o/r' libpin)" = "rc=1|forge-lib: refusing: pin|gh=0|fh=0" ] || echo "a pin refusal does not stop Phase 0"
  for o in "https://user:$TOKEN@forge.example/o/r" 'git@forge.example:o/r' "ssh://git:$TOKEN@forge.example:2222/o/r" 'HTTPS://Forge.Example/o/r'; do
    r=$(host "$f" "$o")
    case "$r" in *"$TOKEN"*) echo "token reaches the refusal" ;; forge.example) ;; *) echo "origin host misread: $o -> $r" ;; esac
  done
  [ "$(host "$f" 'ssh://git@ssh.github.com:443/owner/repo.git')" = ssh.github.com ] || echo "ssh.github.com:443 is not GitHub"

  # the default branch is ASSIGNED, from origin/HEAD, else main
  [ "$(branch "$f" develop)" = develop ] || echo "BRANCH is not assigned from origin/HEAD"
  [ "$(branch "$f")" = main ] || echo "BRANCH is empty without origin/HEAD"

  # forge-adapt's trigger
  r=$(grep -F '`/ci-health`' "$c" | grep '^|' | head -1)
  case "$r" in *.forgejo/workflows*.gitea/workflows*.github/workflows*forge-lib.sh*) ;; *) echo "forge-adapt recommends /ci-health on .github/workflows only" ;; esac
  return 0
}

echo "== the shipped ci-health.md =="
GOOD=$(verdicts "$CIH" "$CMDS")
[ -z "$GOOD" ] && ok "every invariant holds on the shipped ci-health.md and commands.md" \
  || { bad "the shipped files break invariants:"; printf '    %s\n' "$GOOD"; }

# rows that name what they show, so a reader sees each contract in the output
[ "$(host "$CIH" "https://user:$TOKEN@forge.example/o/r")" = forge.example ] && ok "https://user:token@host: the host only, no token" || bad "https userinfo host read"
[ "$(host "$CIH" 'git@forge.example:o/r')" = forge.example ] && ok "scp form git@host:path: the host" || bad "scp host read"
[ "$(host "$CIH" 'ssh://git@forge.example:2222/o/r')" = forge.example ] && ok "ssh:// with a port: the host" || bad "ssh host read"
[ "$(host "$CIH" 'ssh://git@ssh.github.com:443/owner/repo.git')" = ssh.github.com ] && ok "ssh://git@ssh.github.com:443 reads ssh.github.com (GitHub path)" || bad "ssh.github.com:443"
r=$(refuse "$CIH" "https://u:$TOKEN@forge.example/o/r")
[ "$r" = "rc=1|ci-health needs scripts/forge-lib.sh on a non-GitHub host (host: forge.example)|gh=0|fh=0" ] \
  && ok "no adapter, Forgejo origin: refused naming the host and the file, no gh, no forge_host, no token" || bad "refusal: $r"
r=$(refuse "$CIH" 'https://github.com/o/r')
[ "$r" = "rc=0|HOST=github|gh=0|fh=0" ] && ok "no adapter, GitHub origin: proceeds on the GitHub path" || bad "github origin: $r"
[ "$(dedupe "$CIH" 'CI failure: main-old (.forgejo/workflows)')" = "" ] && ok "an open main-old ticket is not a duplicate of main" || bad "main-old dedupe"
[ "$(dedupe "$CIH" 'CI failure: main (.forgejo/workflows)')" = 1 ] && ok "an open main ticket is found by the prefix key" || bad "main dedupe"
[ "$(labels "$CIH" bug)" = "USE=bug|SKIP=infrastructure" ] && ok "a missing label is skipped, the existing one kept" || bad "label filter"
[ "$(refuse "$CIH" 'https://github.com/o/r' libpin)" = "rc=1|forge-lib: refusing: pin|gh=0|fh=0" ] \
  && ok "with the adapter, a pin refusal (a branch's FORGE_HOST) stops Phase 0 before forge_host and gh" || bad "pin refusal in Phase 0"
[ "$(wfdir "$CIH" github)" = .github/workflows ] && ok "a GitHub host reads .github/workflows whatever forge_workflow_dir says" || bad "github wfdir"
[ "$(branch "$CIH" develop)" = develop ] && ok "BRANCH is assigned from refs/remotes/origin/HEAD (develop)" || bad "BRANCH from origin/HEAD"
[ "$(branch "$CIH")" = main ] && ok "BRANCH falls back to main with no origin/HEAD" || bad "BRANCH fallback"

# --- the mutant ledger: each edit is applied to a scratch copy, asserted to have applied, and must
# make verdicts print the named message.
mkdir -p "$T/m"
mut() {  # mut <label> <cih|cmds> <message> <old> <new> [<old2> <new2>]: pairs applied in order
  local label="$1" which="$2" msg="$3" fc="$T/m/ci-health.md" cc="$T/m/commands.md" src out
  cp "$CIH" "$fc"; cp "$CMDS" "$cc"
  if [ "$which" = cih ]; then src="$fc"; else src="$cc"; fi
  shift 3
  python3 - "$src" "$@" <<'PY' || { bad "mutant '$label' did not apply"; return 0; }
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)
open(p, "w").write(s)
PY
  out=$(verdicts "$fc" "$cc")
  if grep -qF -- "$msg" <<< "$out"; then ok "mutant '$label' dies: $msg"
  else bad "MUTANT SURVIVED: $label (wanted '$msg', got: $(printf '%s' "$out" | tr '\n' ';'))"; fi
}
WFL='if [ "$HOST" = github ]; then WF_DIR=.github/workflows; else WF_DIR=$(forge_workflow_dir) || WF_DIR=""; fi
[ -n "$WF_DIR" ] && ls "$WF_DIR"/*.yml "$WF_DIR"/*.yaml 2>/dev/null'
mut 'the pre-fix discovery restored' cih "discovers only .github/workflows" "$WFL" 'ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null'
mut 'the Forgejo order applied on GitHub' cih "GitHub host takes the Forgejo order" 'if [ "$HOST" = github ]; then WF_DIR=.github/workflows; else' 'if false; then WF_DIR=.github/workflows; else'
NWF='If that lists nothing, report "No workflows found (no workflows in <WF_DIR>; searched .forgejo/workflows, .gitea/workflows, .github/workflows)" and stop without querying the host. It is neither a pass nor a refusal.
'
mut 'the No workflows found line deleted' cih "empty discovery can read as green" "$NWF" ''
mut 'the No workflows found line moved below All workflows green' cih "empty discovery can read as green" "$NWF" '' \
  'If ALL workflows are passing (on Forgejo: the verdict is `success`), report "All workflows green" and stop.' \
  'If ALL workflows are passing (on Forgejo: the verdict is `success`), report "All workflows green" and stop.
If nothing is listed, report "No workflows found" for .forgejo/workflows, .gitea/workflows, .github/workflows.'
mut 'a bare gh run list back in Phase 5' cih "gh run outside the GitHub path" 'On Forgejo, read `forge_ci_status "$BRANCH"` again instead.' 'Run gh run list --branch <branch> --limit 1.'
mut 'a bare gh issue list in Phase 2' cih "gh issue outside the GitHub path" '**On GitHub**, for each failing job:' '**On GitHub**, for each failing job (gh issue list first):'
mut 'the GitHub path label dropped from a gh block' cih "gh run outside the GitHub path" '# GitHub path
gh run list --workflow <workflow-file> --branch <branch> --limit 1 --json databaseId,status' 'gh run list --workflow <workflow-file> --branch <branch> --limit 1 --json databaseId,status'
mut 'forge_issue_create removed' cih "no host branch" '- **No match:** `forge_issue_create` with' '- **No match:** create an issue with'
mut 'the status update made a comment' cih "a status update posted as a comment (#565)" '`forge_body_region_set "$EXISTING" ci-health ci-health-status' '`forge_issue_comment "$EXISTING"'
mut 'the cancelled row ticketed' cih "cancelled would be ticketed" '(#193) | not ticketed |' '(#193) | ticketed (Phase 2) |'
mut 'the none row ticketed' cih "none would be ticketed" '| "no CI run found", not green | not ticketed |' '| "no CI run found", not green | ticketed |'
mut 'the pending row green' cih "pending would be ticketed" '| "pending", not green | not ticketed |' '| "pending" | not ticketed |'
mut 'not_configured without its stderr line' cih "not_configured would be ticketed" 'plus its stderr line, not green' 'not green'
mut 'the unlisted-word row deleted' cih "unknown status would be ticketed" '| any other word | `unknown status <word>`, not green | not ticketed |
' ''
mut 'the unlisted-word row ticketed' cih "unknown status would be ticketed" '| any other word | `unknown status <word>`, not green | not ticketed |' '| any other word | `unknown status <word>`, not green | ticketed |'
mut 'the failure row not ticketed' cih "a red branch would not be ticketed" '| `failure` | red | ticketed (Phase 2) |' '| `failure` | red | not ticketed |'
mut 'release-gate classification claimed on Forgejo' cih "release-gate classification claimed on Forgejo" 'release or
version-gate classification is not done on Forgejo' 'release or
version-gate classification is done on Forgejo too'
mut 'the sha from HEAD' cih "the sha shown is not the one judged" 'SHA=$(git rev-parse --verify "$BRANCH" 2>/dev/null)' 'SHA=$(git rev-parse HEAD)'
mut 'the Phase 4 Forgejo skip deleted' cih "Phase 4 does not skip on Forgejo" 'On Forgejo, skip this phase: job logs are not reachable on Forgejo, so there is nothing safe to fix from.
' ''
mut 'the dedupe removed (always create)' cih "duplicate ticket on a red branch" '[.[] | select(.title | startswith($k))][0].number // empty' 'empty'
mut 'the ( dropped from the dedupe key' cih "main-old matches main" '"CI failure: $BRANCH ("' '"CI failure: $BRANCH"'
mut 'the old fix(ci) title form restored' cih "title is not the branch form" 'titled `CI failure: <branch> (<WF_DIR>)`' 'titled `fix(ci): main failing (<WF_DIR>)`'
mut 'a per-workflow-file title' cih "title is not the branch form" 'titled `CI failure: <branch> (<WF_DIR>)`' 'titled `CI failure: <workflow file name>`'
mut 'a run URL in the existing-ticket update' cih "a run URL reaches the Forgejo ticket" 'with
  no run URL and no logs' 'with
  the run URL and no logs'
mut 'the existing-ticket path creates instead' cih "an open ticket gets a second ticket" 'and `forge_issue_create` is not called.' 'and `forge_issue_create` is called as well.'
mut 'forge_issue_label with the unfiltered list' cih "one unknown label drops the call" 'for l in bug infrastructure; do if printf' 'USE=(bug infrastructure); for l in; do if printf'
mut 'the skipped-label report dropped' cih "skipped labels not reported" 'report every skipped name in the summary' 'carry on'
mut 'forge_issue_label called with an empty list' cih "an empty label list still calls forge_issue_label" 'With `USE` empty, do not call `forge_issue_label`.' 'Call `forge_issue_label` even with `USE` empty.'
mut 'the label refusal hidden' cih "a label refusal is hidden" 'created but labels were refused: <stderr line>' 'created'
mut 'the raw origin URL printed in the refusal' cih "token reaches the refusal" \
  "ORIGIN_HOST=\$(git remote get-url origin 2>/dev/null | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#/.*##; s#^.*@##; s#:.*##' | tr '[:upper:]' '[:lower:]')" \
  'ORIGIN_HOST=$(git remote get-url origin 2>/dev/null)'
mut 'the userinfo strip dropped' cih "origin host misread" "s#/.*##; s#^.*@##; s#:.*##'" "s#/.*##; s#:.*##'"
mut 'the port strip dropped' cih "ssh.github.com:443 is not GitHub" "s#^.*@##; s#:.*##'" "s#^.*@##'"
mut 'the existence check moved below the source line' cih "refusal depends on the library it tests for" \
  'if [ -f scripts/forge-lib.sh ]; then
  . scripts/forge-lib.sh && forge_url_check && HOST=$(forge_host) || exit 1' '. scripts/forge-lib.sh 2>/dev/null
if [ -f scripts/forge-lib.sh ]; then
  forge_url_check && HOST=$(forge_host) || exit 1'
mut 'forge_host called in the refusal branch' cih "refusal depends on the library it tests for" \
  '*) echo "ci-health needs scripts/forge-lib.sh' '*) forge_host >/dev/null 2>&1; echo "ci-health needs scripts/forge-lib.sh'
mut 'ssh.github.com no longer GitHub' cih "a GitHub origin without the adapter is refused" '    github.com|ssh.github.com) HOST=github ;;' '    ssh.github.com) HOST=github ;;'
mut 'the adapter-present branch skips the source' cih "the adapter is not sourced when present" '  . scripts/forge-lib.sh && forge_url_check && HOST=$(forge_host) || exit 1' '  HOST=github'
mut 'the pin check dropped from Phase 0' cih "a pin refusal does not stop Phase 0" ' && forge_url_check && HOST=$(forge_host)' ' && HOST=$(forge_host)'
mut 'the pre-fix print-only branch line restored' cih "BRANCH is not assigned from origin/HEAD" \
  'BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); BRANCH=${BRANCH#origin/}; BRANCH=${BRANCH:-main}' \
  "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo \"main\""
mut 'the main fallback dropped' cih "BRANCH is empty without origin/HEAD" '; BRANCH=${BRANCH:-main}' ''
mut 'the origin/ prefix kept' cih "BRANCH is not assigned from origin/HEAD" '; BRANCH=${BRANCH#origin/}' ''
mut 'the pre-fix forge-adapt row restored' cmds "forge-adapt recommends /ci-health on .github/workflows only" \
  "$(grep -F '`/ci-health`' "$CMDS" | grep '^|' | head -1)" '| `.github/workflows/` present | `/ci-health` | devops | scan CI, ticket failures, auto-fix safe | `ticket-gate` |'

echo ""
echo "ci-health host tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
