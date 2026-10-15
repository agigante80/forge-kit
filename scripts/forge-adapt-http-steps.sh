#!/usr/bin/env bash
# forge-adapt-http-steps.sh: warn when an http forge URL will hit forge-lib's http refusal in CI (#528).
#
# forge-lib refuses to send the token over http unless FORGE_ALLOW_HTTP is exactly 1 in the
# environment (_forge_check_url, introduced in forge-lib v36, #442). A project on a LAN Forgejo has an
# http FORGE_API_URL, so a CI step that runs a script sourcing forge-lib turns red on the first push
# after a refresh. This script finds those steps and prints the env line each needs. It PRINTS ONLY:
# editing a workflow is the user's act, and nothing here writes a file.
#
# Usage: forge-adapt-http-steps.sh [--project <dir>]     (default: the git root of the cwd)
#
# Silent and exit 0 unless the forge URL is http. The URL is the exported FORGE_API_URL, else the
# first non-empty FORGE_API_URL line of <project>/.forge.conf, parsed exactly as forge-lib's
# _forge_load_conf does (split on the first =, text after # dropped, one pair of double quotes and
# the surrounding space trimmed, CRLF tolerated, env wins, the FIRST non-empty line wins). The file
# is read, never sourced. FORGE_HOST=github means forge-lib never reaches the check: also silent.
#
# A step needs the offer when its run text runs a project script that mentions forge-lib (the
# project's scripts/*.sh whose text names forge-lib, FORGE_LIB, gate-env, phase-env or roadmap-lib),
# or calls a forge_* function, or names forge-lib directly. A `uses:` step is never named: its
# internals are not visible here. A step is already covered only when FORGE_ALLOW_HTTP is exactly 1
# on the step, its job or the workflow env (forge-lib tests = 1, so "0", "true" and an expression do
# not count). The workflow scan is textual (awk, indentation-based), not a YAML parser.
#
# Output, tab separated, one row per line:
#   forge-url   <url with any userinfo removed>
#   step        <workflow path> <job / step label> <offer> <forgejo=runs|forgejo=ignored>
#   not-scanned <workflow dir or file that could not be read>
#   warning / local-session   the two advice lines
#   summary     steps=<n> workflows=<n> not-scanned=<n>
# forgejo=ignored marks a directory Forgejo will not run: it executes only the FIRST that exists of
# .forgejo/workflows, .gitea/workflows, .github/workflows.
#
# Exit codes (stale-rules.sh's): 0 reported or nothing to report, 3 a workflow dir or file could not
# be read (never read as clean), 2 usage. The token is never read.
set -uo pipefail

usage() { echo "forge-adapt-http-steps: usage: forge-adapt-http-steps.sh [--project <dir>]" >&2; exit 2; }

PROJECT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] && [ -n "$2" ] || usage; PROJECT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$PROJECT" ] || PROJECT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -d "$PROJECT" ] || { echo "forge-adapt-http-steps: not a directory: $PROJECT" >&2; exit 2; }

url="${FORGE_API_URL:-}"; fhost="${FORGE_HOST:-}"
conf="$PROJECT/.forge.conf"
if [ -f "$conf" ] && [ -r "$conf" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    k="${k//[[:space:]]/}"
    v="${v%%#*}"; v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')"
    case "$k" in
      FORGE_API_URL) [ -n "$url" ] || url="$v" ;;
      FORGE_HOST)    [ -n "$fhost" ] || fhost="$v" ;;
    esac
  done < "$conf"
fi
case "$url" in http://*) ;; *) exit 0 ;; esac
[ "$fhost" != github ] || exit 0

# Remove userinfo: everything up to the LAST @ of the authority (a password may contain @).
rest="${url#*://}"; auth="${rest%%[/?#]*}"
case "$auth" in *@*) url="http://${auth##*@}${rest#"$auth"}" ;; esac
printf 'forge-url\t%s\n' "$url"

# The project scripts that source forge-lib, by basename, one per line.
names=""
for f in "$PROJECT"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if grep -qE 'forge-lib|FORGE_LIB|gate-env|phase-env|roadmap-lib' "$f" 2>/dev/null; then
    names="${names}${f##*/}"$'\n'
  fi
done
export SET_NAMES="$names"

IFS= read -r -d '' AWKPROG <<'AWK' || true
function ind_of(s) { match(s, /^ */); return RLENGTH }
function clean(s) { gsub(/[\t\r\n]/, " ", s); gsub(/[^ -~]/, "", s); return s }
function unq(s,   q) {
  sub(/[ \t]+#.*$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  q = substr(s, 1, 1)
  if ((q == "\"" || q == "\047") && substr(s, length(s), 1) == q && length(s) >= 2) s = substr(s, 2, length(s) - 2)
  return s
}
function allow_val(s) { return unq(s) == "1" }
# A flow-style env on the key line: env: { FORGE_ALLOW_HTTP: "1" }
function flow_allow(s) { return s ~ /FORGE_ALLOW_HTTP[ ]*:[ ]*["\047]?1["\047]?[ ]*[,}]/ }
function ident_before(c) { return c ~ /[A-Za-z0-9_.-]/ }
function qualifies(t,   i, n, p, a, b, nm) {
  if (t == "") return 0
  if (index(t, "forge-lib") > 0) return 1
  if (match(t, /(^|[^A-Za-z0-9_])forge_[a-z_]+/)) return 1
  for (i = 1; i <= nset; i++) {
    nm = names[i]; if (nm == "") continue
    p = 1
    while ((n = index(substr(t, p), nm)) > 0) {
      a = (p + n - 1 > 1) ? substr(t, p + n - 2, 1) : ""
      b = substr(t, p + n - 1 + length(nm), 1)
      if (!ident_before(a) && !ident_before(b)) return 1
      p = p + n
    }
  }
  return 0
}
function finish_step() {
  if (!cur) return
  sn++; s_job[sn] = job_n; s_name[sn] = cur_name; s_run[sn] = cur_run; s_allow[sn] = cur_allow
  s_jobname[sn] = job_name
  cur = 0
}
function begin_step() { finish_step(); cur = 1; cur_name = ""; cur_run = ""; cur_allow = 0; step_key = -1 }
function set_env(scope) {
  if (scope == "wf") wf_allow = 1
  else if (scope == "job") job_allow[job_n] = 1
  else if (scope == "step" && cur) cur_allow = 1
}
function step_key_line(rest, kind,   key, val) {
  key = rest; sub(/:.*$/, "", key)
  val = rest; sub(/^[^:]*:[ \t]*/, "", val)
  if (key == "name") cur_name = unq(val)
  else if (key == "run") {
    if (val ~ /^[|>][-+0-9]*[ \t]*(#.*)?$/) { blk = 1; blk_ind = kind; cur_run = "" }
    else cur_run = val
  } else if (key == "env") {
    if (flow_allow(val)) cur_allow = 1
    else if (val == "" || val ~ /^#/) { env_open = kind; env_scope = "step" }
  }
}
BEGIN {
  nset = split(ENVIRON["SET_NAMES"], names, "\n")
  env_open = -1; steps_key = -1; step_ind = -1; job_ind = -1; job_body = -1
}
{
  line = $0; sub(/\r$/, "", line)
  if (blk) {
    if (line ~ /^[ ]*$/) next
    if (ind_of(line) > blk_ind) { cur_run = (cur_run == "" ? "" : cur_run "\n") substr(line, ind_of(line) + 1); next }
    blk = 0
  }
  if (line ~ /^[ ]*(#.*)?$/) next
  ind = ind_of(line); rest = substr(line, ind + 1); dash = 0; keyind = ind
  if (rest ~ /^-([ ]+|$)/) { dash = 1; match(rest, /^-[ ]*/); keyind = ind + RLENGTH; rest = substr(rest, RLENGTH + 1) }
  if (env_open >= 0) {
    if (ind > env_open && !dash) {
      if (rest ~ /^FORGE_ALLOW_HTTP[ ]*:/) { v = rest; sub(/^[^:]*:/, "", v); if (allow_val(v)) set_env(env_scope) }
      next
    }
    env_open = -1
  }
  if (ind == 0 && !dash) {
    finish_step(); steps_key = -1; in_jobs = 0; job_ind = -1; job_body = -1
    key = rest; sub(/:.*$/, "", key)
    if (key == "jobs") in_jobs = 1
    else if (key == "env") {
      v = rest; sub(/^[^:]*:[ \t]*/, "", v)
      if (flow_allow(v)) wf_allow = 1; else if (v == "" || v ~ /^#/) { env_open = 0; env_scope = "wf" }
    }
    next
  }
  if (!in_jobs) next
  if (job_ind < 0) job_ind = ind
  if (!dash && ind == job_ind) {
    finish_step(); steps_key = -1; step_ind = -1; job_body = -1
    job_n++; job_name = rest; sub(/:.*$/, "", job_name); job_name = unq(job_name)
    next
  }
  if (job_n == 0) next
  if (job_body < 0 && ind > job_ind) job_body = ind
  if (!dash && ind == job_body) {
    key = rest; sub(/:.*$/, "", key)
    finish_step(); steps_key = -1; step_ind = -1
    if (key == "steps") steps_key = ind
    else if (key == "env") {
      v = rest; sub(/^[^:]*:[ \t]*/, "", v)
      if (flow_allow(v)) job_allow[job_n] = 1; else if (v == "" || v ~ /^#/) { env_open = ind; env_scope = "job" }
    }
    next
  }
  if (steps_key < 0) next
  if (dash && (step_ind < 0 ? ind >= steps_key : ind == step_ind)) {
    if (step_ind < 0) step_ind = ind
    begin_step(); step_key = (rest == "") ? -1 : keyind
    if (rest != "") step_key_line(rest, keyind)
    next
  }
  if (!cur) next
  if (step_key < 0) step_key = ind
  if (!dash && ind == step_key) step_key_line(rest, ind)
}
END {
  finish_step()
  for (i = 1; i <= sn; i++) {
    if (!qualifies(s_run[i])) continue
    if (wf_allow || job_allow[s_job[i]] || s_allow[i]) continue
    lbl = s_name[i]
    if (lbl == "") { lbl = s_run[i]; sub(/\n.*/, "", lbl); lbl = substr(lbl, 1, 60) }
    printf "step\t%s\t%s\tFORGE_ALLOW_HTTP: \"1\"\t%s\n", ENVIRON["WF_PATH"], "job " clean(s_jobname[i]) " / " clean(lbl), ENVIRON["WF_RUNS"]
  }
}
AWK

forgejo_dir=""
for d in .forgejo/workflows .gitea/workflows .github/workflows; do
  if [ -d "$PROJECT/$d" ]; then forgejo_dir="$d"; break; fi
done

steps=0; files=0; unread=0
for d in .forgejo/workflows .gitea/workflows .github/workflows; do
  [ -d "$PROJECT/$d" ] || continue
  if [ ! -r "$PROJECT/$d" ] || [ ! -x "$PROJECT/$d" ]; then
    printf 'not-scanned\t%s\n' "$d"; unread=$((unread + 1)); continue
  fi
  if [ "$d" = "$forgejo_dir" ]; then runs="forgejo=runs"; else runs="forgejo=ignored"; fi
  for f in "$PROJECT/$d"/*.yml "$PROJECT/$d"/*.yaml; do
    [ -e "$f" ] || continue
    if [ ! -r "$f" ]; then printf 'not-scanned\t%s/%s\n' "$d" "${f##*/}"; unread=$((unread + 1)); continue; fi
    files=$((files + 1))
    export WF_PATH="$d/${f##*/}" WF_RUNS="$runs"
    rows="$(awk "$AWKPROG" "$f")"
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows"
      steps=$((steps + $(printf '%s\n' "$rows" | grep -c '^step')))
    fi
  done
done

printf 'warning\thttp sends the forge token over the network unencrypted; set FORGE_ALLOW_HTTP only for a trusted LAN instance\n'
printf 'local-session\tfor a local Claude session export FORGE_ALLOW_HTTP=1 through the env block of the untracked .claude/settings.local.json\n'
printf 'summary\tsteps=%s\tworkflows=%s\tnot-scanned=%s\n' "$steps" "$files" "$unread"
[ "$unread" -eq 0 ] || exit 3
exit 0
