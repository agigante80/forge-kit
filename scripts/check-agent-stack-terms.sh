#!/usr/bin/env bash
# check-agent-stack-terms.sh: fail if a shipped AGENT names one project's stack (#549, #559).
#
# THE DEFECT THIS STOPS. api-security-tester shipped telling every project to write Fastify + Prisma
# + Zod tests run with Vitest, against `fastify.inject()` and a `helpers/seed.ts` that exist in one
# private codebase only. An agent is a prompt that runs verbatim in any project, so a stack term in
# it is an instruction the reader cannot follow. Nothing looked until a reader hit it.
#
# WHY ONLY plugins/*/agents/*.md. A SKILL may carry worked examples in one stack, as illustrations
# the model is told to translate (owasp-api-security does, and says so); an agent may not, because
# its own text is the instruction. Widening this glob to skills would fail a sanctioned pattern, so
# test-check-agent-stack-terms.sh holds a mutant that does exactly that.
#
# The term list lives in ONE variable, TERMS, one fixed string per line, matched case-sensitively.
#
# Usage: check-agent-stack-terms.sh [--root <checkout>]
# Exit 0 clean, 1 a hit (each printed as `<file>:<line>: <term>`), 2 a missing root or no agents.
set -uo pipefail

die() { echo "check-agent-stack-terms: $1" >&2; exit 2; }

TERMS='Fastify
Prisma
Zod
Vitest
fastify.inject
app.inject
Firebase
Twilio
SendGrid
Stripe
.test.ts
subscriptionTier
SUBSCRIPTION_REQUIRED
helpers/seed'

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || die "--root needs a value"; ROOT="$2"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$HERE/.."
ROOT="$(CDPATH= cd -P -- "$ROOT" 2>/dev/null && pwd -P)" || die "no such directory '$ROOT'"

shopt -s nullglob
agents=("$ROOT"/plugins/*/agents/*.md)
[ "${#agents[@]}" -gt 0 ] || die "no plugins/*/agents/*.md under $ROOT"

rc=0
for f in "${agents[@]}"; do
  rel="${f#"$ROOT"/}"
  while IFS= read -r term; do
    [ -n "$term" ] || continue
    while IFS=: read -r n _; do
      [ -n "$n" ] || continue
      echo "$rel:$n: $term"
      rc=1
    done < <(grep -nF -- "$term" "$f")
  done <<< "$TERMS"
done
exit "$rc"
