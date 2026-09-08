#!/usr/bin/env bash
# check-template-dir-order.sh: every copy of the template-dir resolution order must match (#77).
#
# THE DEFECT. The order is a five-entry, HOST-grouped list that SIX separate sites must agree on:
# check-template-lockstep.sh twice (its header comment and resolve_dir), ticket-gate.md,
# dep-auditor.md, and adapt/SKILL.md twice. The #61/#74 review found the copies had already diverged, case-grouped
# against host-grouped, before that PR merged. Two of the sites are prose an LLM executor will
# paraphrase, which is the failure mode forge-adapt-catalogue.sh was extracted to end.
#
# WHY THIS IS A GUARD AND NOT A SHARED SCRIPT, against the ticket's own proposal. Its trade-off
# concedes that the prose sites must keep an inline fallback for repos where the script is not
# installed, so extraction shrinks the duplication from four sites to two rather than to one, and
# the two left behind are the fragile ones. The repo already met this shape with the enforced path
# set (#112), where the catalogue must use globs while three others use an ERE, and answered it
# with a guard (test-component-paths.sh) because one implementation was impossible. Same answer
# here, and it covers all six sites instead of two.
#
# WHY HOST-GROUPED ORDER MATTERS, since a future editor will be tempted to "tidy" it into case
# groups: a repo migrated to Forgejo that kept a stale .github/ISSUE_TEMPLATE must have its LIVE
# lowercase Forgejo dir resolved, not the stale GitHub one. Case-grouping silently inverts that.
#
# Usage: check-template-dir-order.sh [ROOT]     (default: this repo)
# Exit: 0 all copies agree, 1 they disagree or none were found, 2 the root is unreadable.
set -uo pipefail

if [ "$#" -ge 1 ]; then ROOT="$1"; else
  ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-template-dir-order: not a git checkout and no root given" >&2; exit 2; }
fi
[ -d "$ROOT" ] || { echo "check-template-dir-order: '$ROOT' is not a directory" >&2; exit 2; }

# WHICH files, from guard-lib.sh: the tracked set inside a checkout, a plain walk outside one
# (#142). The hand-maintained exclude list is DELETED rather than extended: it had to grow every
# time a new gitignored runtime store appeared, and a copy of a diff written into .superpowers/sdd/
# by /full-review had already made this guard report three bogus orders on content git never
# carries. Inside a checkout the tracked set excludes all of them by construction.
#
# The list arrives on a SEPARATE fd through process substitution, not on stdin, because stdin is
# already carrying the Python program.
. "$(dirname "$0")/guard-lib.sh"
# Held open with `exec` rather than inlined into the argument list: a process substitution's fd
# lives only as long as the command it belongs to, so writing it into an array assignment leaves
# python opening a /dev/fd entry that has already gone.
FLARG=()
if guard_in_checkout "$ROOT"; then
  exec 3< <(guard_tracked_files "$ROOT")
  FLARG=(--filelist /dev/fd/3)
fi

python3 - "$ROOT" ${FLARG+"${FLARG[@]}"} <<'PY'
import os, re, sys

root = sys.argv[1]
# A NUL-separated file list on a separate fd when the caller established a checkout; otherwise a
# walk. Two mechanisms for one intent, which is why guard-lib.sh shares the DECISION rather than
# the listing: a Python walk cannot be a bash grep, the same shape as the component path set (#112).
FILELIST = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--filelist' else None
TOKEN = re.compile(r'\.(?:forgejo|gitea|github)/(?:ISSUE_TEMPLATE|issue_template)\b')
# A run of ALL FIVE directories is an ordering; anything shorter is prose. Four was tried and was
# wrong in both directions: a sentence enumerating the directories comma-separated with "and"
# before the last leaves a four-token punctuation run and got reported as a divergent site, while
# the real documentation passages name two and three of them. The residual gap, a real site edited
# below five entries dropping out of the comparison, is closed by the site COUNT its contract test
# asserts, and it is the cheaper of the two failure directions: a guard that cries wolf at prose
# gets switched off, and one that fails a build for documentation is worse than one that needs a
# count to notice a deletion.
MIN = 5

# THE CANON, pinned here rather than merely inferred from whatever the copies happen to say. The
# first version compared the sites only to each other, so one sweep reordering ALL of them passed
# with CI green and reintroduced the exact #61 defect, while the error message claimed a canonical
# order that nothing enforced. This line is now the single definition the ticket asked for; every
# site is checked against it.
CANON = ('.forgejo/ISSUE_TEMPLATE', '.forgejo/issue_template',
         '.gitea/ISSUE_TEMPLATE', '.gitea/issue_template', '.github/ISSUE_TEMPLATE')

def candidate_paths():
    if FILELIST:
        with open(FILELIST, 'rb') as fh:
            for raw in fh.read().split(b'\0'):
                if raw:
                    yield raw.decode('utf-8', 'replace')
        return
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            yield os.path.join(dirpath, fn)

sites = []
if True:
    for path in sorted(candidate_paths()):
        rel_ = os.path.relpath(path, root)
        # This guard holds the DEFINITION, not a copy of it. Counting it as a site made `sites`
        # impossible to empty, so deleting every real copy reported "1 sites, all carrying the
        # same order" and exited 0, contradicting this file's own header.
        if os.path.basename(path) == 'check-template-dir-order.sh':
            continue
        # THIS DIRECTORY's contract tests carry deliberately wrong orders as fixtures, so scanning
        # them would make every such test a permanent failure. Matching on the bare filename was
        # too broad: it silently excluded the shipped component
        # plugins/forge-kit-testing/agents/test-automator.md from the scan entirely.
        if re.match(r'scripts/test-[^/]*\.sh$', rel_):
            continue
        try:
            text = open(path, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        # An ORDERING is a bare list: the tokens are separated only by punctuation. PROSE puts
        # WORDS between them, as in "`.github/ISSUE_TEMPLATE/` on GitHub, or to `.forgejo/...`".
        # Keying on that is what separates the real sites from the documentation passages, with no
        # allowlist and no hand-maintained site list. The punctuation set includes table pipes and
        # quotes, so a copy laid out as a markdown table is seen rather than silently skipped.
        for m in re.finditer(
                r'(?:%s)(?:[\s,`/\\#()|;:"\'-]*(?:%s))+' % (TOKEN.pattern, TOKEN.pattern), text):
            # Positions, not just strings (#143). Two copies separated only by punctuation are ONE
            # match, so a line computed once per MATCH and reused for every site inside it reports
            # the second copy at the first copy's line. The verdict was right and the line was not,
            # which costs the reader time in the moment the guard is trying to save it.
            toks = [(t.group(0), m.start() + t.start()) for t in TOKEN.finditer(m.group(0))]
            seq = [t[0] for t in toks]
            def line_of(k, _text=text, _toks=toks):
                return _text[:_toks[k][1]].count('\n') + 1
            # Punctuation-only separation merges neighbours into one run, so the run has to be
            # taken apart. Two earlier attempts each broke something: splitting at the canon's
            # first entry unconditionally made a host-reordered copy fragment into sub-threshold
            # pieces and VANISH (the #61 defect passing green), and falling back to reporting the
            # whole run flagged a correct copy trailed by a short mention as one long divergent
            # site. Consume CANONICAL windows greedily instead: each exact match is a site and the
            # scan advances past it, so a correct copy is recognised no matter what follows. What
            # is left over is reported only if it is long enough to be an ordering in its own
            # right, which is what keeps a wrong copy visible.
            i = 0
            while i < len(seq):
                if tuple(seq[i:i + len(CANON)]) == CANON:
                    sites.append((rel_, line_of(i), CANON)); i += len(CANON); continue
                rest = seq[i:]
                nxt = next((j for j in range(1, len(rest))
                            if tuple(rest[j:j + len(CANON)]) == CANON), len(rest))
                if nxt >= MIN:
                    sites.append((rel_, line_of(i), tuple(rest[:nxt])))
                i += nxt

if not sites:
    print(f"check-template-dir-order: no resolution order found under {root}. "
          f"Deleting every copy must not read as agreement.", file=sys.stderr)
    sys.exit(1)

orders = {}
for rel, ln, seq in sites:
    orders.setdefault(seq, []).append(f"{rel}:{ln}")

if len(orders) > 1 or (CANON not in orders):
    if CANON not in orders:
        print("check-template-dir-order: NO site carries the canonical order.\n", file=sys.stderr)
    else:
        print("check-template-dir-order: the resolution order differs between sites.\n", file=sys.stderr)
    print(f"  canonical: {' '.join(CANON)}\n", file=sys.stderr)
    for seq, where in sorted(orders.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(where)} site(s): {' '.join(seq)}", file=sys.stderr)
        for w in where: print(f"      {w}", file=sys.stderr)
        print("", file=sys.stderr)
    print("Host-grouped is canonical: all Forgejo dirs, then Gitea, then GitHub, uppercase "
          "before the legacy lowercase within each host.", file=sys.stderr)
    sys.exit(1)

seq = next(iter(orders))
print(f"check-template-dir-order: {len(sites)} sites, all carrying the same {len(seq)}-entry order.")
PY
