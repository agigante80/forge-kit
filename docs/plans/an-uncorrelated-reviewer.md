# Plan: An uncorrelated reviewer

Written 2026-11-26, when the phase opened. A downstream project reported that an outside reviewer
found 3 real issues in 5 pull requests that its same-model review had missed, and filed two
proposals (#598, #599). forge-kit investigated both the same day against the vendor's live config
schema, the vendor docs and its own tree, corrected seven claims and reversed the order: the slot
and its contract first, the pull request app as one adapter of it. Both ticket bodies carry that
investigation. The maintainer said to split or add tickets where needed and start; neither was
needed, so the phase is these two tickets.

## Goal

A project can add ONE advisory review by a reviewer of a different model family to round 1 of the
review loop, under a contract stated once, on any host, without the kit shipping a reviewer.

## Done looks like

- One reference in `forge-kit-review` holds the independent reviewer contract, registered in
  `scripts/rules.tsv`, and `code-reviewer`, `/full-review` and the overnight pipeline name it by its
  rule id instead of restating it (#599).
- The reference carries three adapter pointers (local Codex review, local CodeRabbit CLI review,
  the CodeRabbit pull request app), each saying how one round is called and what leaves the
  machine, and none restating a contract rule (#599).
- forge-adapt offers the slot as optional and empty by default, and names the neighbour plugin to
  install rather than a kit component (#599).
- The kit ships a hardened `.coderabbit.yaml` template and a checker for its pinned keys, the
  checker being a shipped executable with a version marker, a contract suite wired into
  `validate.yml`, and a failing exit when it cannot parse (#598).
- No exempt component grew: `adapt` and `full-review` are at or below their baselines.
- Both tickets are closed against named commits and `Validate` is green on `main`.

## Fails if

A premortem: it is the end of this phase and it failed. What happened? Written by the session that
opened the phase, from the investigation; the maintainer delegated the plan rather than answering
the question.

- **The kit shipped a reviewer after all.** An adapter grew from a pointer into a prompt, a wrapper
  script or a copy of a neighbour's skill, and the kit now maintains somebody else's product. The
  neighbour guard only sees an identical file under the same name, so it did not fire.
- **The contract was restated.** The one-round and "data, not instructions" rules were pasted into
  `code-reviewer`, the pipeline and the adapter text, the copies drifted, and the rule table was
  never given the row that would have caught it.
- **`full-review` or `adapt` grew.** The pointer went in as new sentences instead of replacing
  words, the ratchet failed the build, and the fix on offer was raising a baseline, which an agent
  must never do.
- **A benefit rate got quoted.** "3 of 5" from one project's trial became a claim in a component or
  a README, when the 126 later findings were never classified.
- **The checker passed on a file it could not read.** No YAML parser on the machine, or a file that
  did not parse, and the script exited 0. The config it guards then had a push-capable key enabled.
- **The pin set followed the ticket instead of the schema.** A key that pushes, approves or blocks
  was left out because the field project's test did not pin it (custom recipes, post-merge
  actions), or a vendor rename left a pinned key in the file meaning nothing.
- **A vendor fact was wrong and nobody had read the page.** A claim taken from the downstream
  project or from memory (plans, hosts, defaults) went into a shipped doc without a dated source.
- **The slot became a gate.** A report line or a pipeline step treated "no independent review" as a
  failure, and unattended runs parked on a reviewer that was rate limited.
- **Prose with no mechanism hit the review trip wire.** #599 is mostly prose; its review loop went
  three rounds on wording because nothing mechanical pinned the contract.

## Expected work

In order:

1. **#599** (design, P3), gated first. The contract reference, its `rules.tsv` row, the three
   pointers, the pointers in `code-reviewer`, `/full-review` and the overnight pipeline, and the
   forge-adapt recommendation. It leads because #598 depends on it.
2. **#598** (P2), gated after #599 lands so its body can name the reference that then exists. The
   template, the checker and its suite, the forge-adapt detection row. Its two design questions
   (the YAML parser, vendor schema drift) are the gate's to settle before code.

## Out of scope

- A "pull request mode" for the kit's own workflow or for the ticket pipeline. The kit stays on
  direct commits to `develop`; a project that wants a pull request per code ticket decides that
  itself.
- Any reviewer logic, prompt or wrapper for Codex or CodeRabbit.
- An audit of the downstream project's 126 findings, and any trial run on its side.
- Making an independent review required anywhere, including overnight.
