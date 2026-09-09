#!/usr/bin/env bash
# Contract test for forge-adapt-agent-skills.sh, the mechanical half of issue #124.
#
# WHY A SCRIPT AND NOT PROSE. forge-adapt is prose an LLM executes, and this repo already learned
# where that fails: the S3 catalogue became a script because "an LLM executor kept reintroducing
# fixed bugs". Parsing a YAML list out of frontmatter and rewriting plugin-scoped identifiers is
# exactly that kind of fiddly mechanical step, so it is a script the skill runs verbatim.
#
# THE FAILURE THIS PREVENTS. An agent that declares `skills:` and is installed WITHOUT them loses
# that content silently: Claude Code "skips it and logs a warning to the debug log". Nothing in the
# project would show a problem, and the agent would run with its lens material missing.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/forge-adapt-agent-skills.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want '$3', got '$2')"; }

agent() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

# --- block-list form, the shape the docs use ---------------------------------------------------
agent "$T/block.md" <<'M'
---
name: ticket-gate
description: gate a ticket
skills:
  - forge-kit-governance:gate-lenses
  - privacy-regime
tools: ["Bash"]
---
Body mentioning skills: not-a-declaration
M
eq "block list prints each declared skill verbatim" \
   "$(bash "$SCRIPT" "$T/block.md" | tr '\n' ',')" "forge-kit-governance:gate-lenses,privacy-regime,"
eq "--names strips the plugin scope for a project install" \
   "$(bash "$SCRIPT" --names "$T/block.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"

# --- inline flow form ---------------------------------------------------------------------------
agent "$T/flow.md" <<'M'
---
name: a
skills: [forge-kit-governance:gate-lenses, privacy-regime]
---
body
M
eq "inline flow form is parsed too" \
   "$(bash "$SCRIPT" --names "$T/flow.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"

# --- plugin:folder:skill, per the docs: the SKILL name is the last segment -----------------------
agent "$T/folder.md" <<'M'
---
name: a
skills:
  - some-plugin:nested:deep-skill
---
body
M
eq "plugin:folder:skill resolves to the skill name" \
   "$(bash "$SCRIPT" --names "$T/folder.md")" "deep-skill"

# --- a following top-level key must END the list, or its items read as skills --------------------
# Mutation-driven: making the list run to the end of frontmatter left the suite green without this.
agent "$T/nextkey.md" <<'M'
---
name: a
skills:
  - gate-lenses
tools:
  - Bash
  - Read
---
body
M
eq "a following top-level key ends the skills list" \
   "$(bash "$SCRIPT" "$T/nextkey.md" | tr '\n' ',')" "gate-lenses,"

# --- an agent with no skills: field is NORMAL and must not read as a failure ---------------------
agent "$T/none.md" <<'M'
---
name: a
description: no companion skills
---
body
M
out=$(bash "$SCRIPT" "$T/none.md"); rc=$?
eq "no skills: field prints nothing" "$out" ""
eq "no skills: field still exits 0" "$rc" "0"

# --- a skills: mention in the BODY is not a declaration ------------------------------------------
agent "$T/body.md" <<'M'
---
name: a
description: d
---
The install step must handle skills:
  - not-a-real-declaration
M
eq "a skills: line in the body is ignored" "$(bash "$SCRIPT" "$T/body.md")" ""

# --- frontmatter ends at the SECOND ---, so a later --- cannot reopen it -------------------------
agent "$T/reopen.md" <<'M'
---
name: a
---
body
---
skills:
  - sneaky
M
eq "a second --- block in the body does not reopen frontmatter" "$(bash "$SCRIPT" "$T/reopen.md")" ""

# --- --rewrite converts the installed copy to project scope, in place ----------------------------
cp "$T/block.md" "$T/rewrite.md"
bash "$SCRIPT" --rewrite "$T/rewrite.md"
eq "--rewrite drops the plugin scope in the file" \
   "$(bash "$SCRIPT" "$T/rewrite.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"
grep -q '^name: ticket-gate' "$T/rewrite.md" \
  && ok "--rewrite leaves the rest of the frontmatter intact" \
  || bad "--rewrite preserved the other frontmatter keys"
grep -q 'Body mentioning skills: not-a-declaration' "$T/rewrite.md" \
  && ok "--rewrite does not touch the body" \
  || bad "--rewrite left the body alone"

# --rewrite must handle the inline flow form too, which the block-form case above cannot reach.
cp "$T/flow.md" "$T/rewrite-flow.md"
bash "$SCRIPT" --rewrite "$T/rewrite-flow.md"
eq "--rewrite handles the inline flow form" \
   "$(grep '^skills:' "$T/rewrite-flow.md")" "skills: [gate-lenses, privacy-regime]"

# --- round 1: shapes OUTSIDE the supported grammar must REFUSE, never corrupt -------------------
# The script parses two YAML shapes, not YAML. Everything else has to fail closed, because a
# half-understood rewrite leaves frontmatter that no longer parses and the agent stops loading.
agent "$T/multiline.md" <<'M'
---
name: a
skills: [
  forge-kit-governance:gate-lenses,
  privacy-regime
]
---
body
M
before=$(cat "$T/multiline.md")
err=$(bash "$SCRIPT" --rewrite "$T/multiline.md" 2>&1 >/dev/null); rc=$?
eq "a multi-line flow list refuses with exit 2" "$rc" "2"
eq "a refused rewrite leaves the file byte-identical" "$(cat "$T/multiline.md")" "$before"
case "$err" in *"unsupported"*) ok "the refusal says the shape is unsupported" ;;
               *) bad "refusal message names the problem (got '$err')" ;; esac
err=$(bash "$SCRIPT" --names "$T/multiline.md" 2>&1 >/dev/null)
eq "--names refuses the same shape rather than printing nothing" "$?" "2"

agent "$T/scalar.md" <<'M'
---
name: a
skills: forge-kit-governance:gate-lenses
---
body
M
bash "$SCRIPT" "$T/scalar.md" >/dev/null 2>&1
eq "a plain scalar skills: value refuses (not silently empty)" "$?" "2"

# --- round 1: quotes are ordinary YAML and --rewrite must strip them like parse does ------------
agent "$T/quoted.md" <<'M'
---
name: a
skills:
  - "forge-kit-governance:gate-lenses"
  - 'privacy-regime'
---
body
M
eq "--names strips quotes in block form" \
   "$(bash "$SCRIPT" --names "$T/quoted.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"
bash "$SCRIPT" --rewrite "$T/quoted.md"
eq "--rewrite strips quotes instead of leaving a stray one" \
   "$(grep -c '"' "$T/quoted.md")" "0"
eq "--rewrite of quoted block form round-trips" \
   "$(bash "$SCRIPT" "$T/quoted.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"

agent "$T/quotedflow.md" <<'M'
---
name: a
skills: ["forge-kit-governance:gate-lenses", privacy-regime]   # trailing comment
---
body
M
bash "$SCRIPT" --rewrite "$T/quotedflow.md"
eq "--rewrite strips quotes in flow form and keeps trailing content" \
   "$(grep '^skills:' "$T/quotedflow.md")" "skills: [gate-lenses, privacy-regime]   # trailing comment"

# --- round 1: a rewrite must not silently change the file mode ----------------------------------
cp "$T/block.md" "$T/mode.md"; chmod 644 "$T/mode.md"
bash "$SCRIPT" --rewrite "$T/mode.md"
eq "--rewrite preserves the file mode" "$(stat -c '%a' "$T/mode.md")" "644"

# --- round 2: ONE normalisation, shared by parse and rewrite ------------------------------------
# Three rounds of findings were all the same defect: parse and the rewrite branch each normalised
# an item their own way and drifted. Round 1 found rewrite not unquoting at all; round 2 found it
# unquoting BEFORE trimming, so a trailing space left a stray quote. They share norm() now, and
# these cases pin both directions of that agreement.
agent "$T/messy.md" <<'M'
---
name: a
skills:
  - "forge-kit-governance:gate-lenses" 
  - privacy-regime  # the regime pack
---
body
M
eq "--names strips a trailing comment from a list item" \
   "$(bash "$SCRIPT" --names "$T/messy.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"
bash "$SCRIPT" --rewrite "$T/messy.md"
eq "--rewrite unquotes AFTER trimming, leaving no stray quote" \
   "$(grep -c '"' "$T/messy.md")" "0"
eq "--rewrite and --names agree on the rewritten file" \
   "$(bash "$SCRIPT" "$T/messy.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"

# --- round 2: CRLF frontmatter must not silently disable the whole script -----------------------
# forge-lib.sh already tolerates CRLF for the same reason. Without this, `---\r` fails the line-1
# test, classify() never sees the field, and every mode prints nothing and exits 0: the exact
# silent-empty outcome the refusal contract was added to remove.
printf -- '---\r\nname: a\r\nskills:\r\n  - forge-kit-governance:gate-lenses\r\n---\r\nbody\r\n' > "$T/crlf.md"
eq "CRLF frontmatter is parsed, not silently skipped" \
   "$(bash "$SCRIPT" --names "$T/crlf.md")" "gate-lenses"

# --- round 2: a bare `skills:` is YAML null, which genuinely means NO skills ---------------------
# Deliberately NOT a refusal, unlike the plain-scalar case. `skills:` with no items is null, and
# null and absent mean the same thing, so printing nothing is the correct answer rather than an
# ambiguity. Pinned so the next round does not re-raise it.
agent "$T/bare.md" <<'M'
---
name: a
skills:
tools: ["Bash"]
---
body
M
out=$(bash "$SCRIPT" "$T/bare.md"); rc=$?
eq "a bare skills: (YAML null) prints nothing" "$out" ""
eq "a bare skills: (YAML null) exits 0, it is not an unsupported shape" "$rc" "0"

# --- round 2: the rewrite must stay ATOMIC as well as mode-preserving ---------------------------
cp "$T/block.md" "$T/atomic.md"; chmod 600 "$T/atomic.md"
bash "$SCRIPT" --rewrite "$T/atomic.md"
eq "--rewrite preserves a non-default mode too" "$(stat -c '%a' "$T/atomic.md")" "600"

# --- round 3: a comment on the `skills:` KEY line is valid YAML and must not abort the install --
# norm() learned to strip item comments in round 2, but classify() still demanded a bare key line,
# so this refused with exit 2, which SKILL.md escalates into a full install abort.
agent "$T/keycomment.md" <<'M'
---
name: a
skills:   # companion skills
  - forge-kit-governance:gate-lenses
---
body
M
eq "a comment on the skills: key line still parses" \
   "$(bash "$SCRIPT" --names "$T/keycomment.md")" "gate-lenses"

# --- round 3: a read-only agent must fail closed with OUR message, not a raw shell error ---------
cp "$T/block.md" "$T/ro.md"; chmod 444 "$T/ro.md"
err=$(bash "$SCRIPT" --rewrite "$T/ro.md" 2>&1 >/dev/null); rc=$?
eq "a read-only agent rewrites rather than dying on the temp write" "$rc" "0"
eq "and its mode is restored, not widened to writable" "$(stat -c '%a' "$T/ro.md")" "444"
eq "the read-only rewrite still took effect" \
   "$(bash "$SCRIPT" "$T/ro.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"

# --- round 3: the rewrite must not depend on TMPDIR, or `mv` is not atomic ----------------------
# A temp file in /tmp makes the final mv a cross-filesystem copy-then-unlink on the usual
# tmpfs-plus-disk layout, which is the half-written-on-interrupt case the atomicity fix claimed to
# close. Pointing TMPDIR at a nonexistent path proves the temp file is created beside the target.
cp "$T/block.md" "$T/tmpdir.md"
TMPDIR=/nonexistent-on-purpose bash "$SCRIPT" --rewrite "$T/tmpdir.md"
eq "--rewrite ignores TMPDIR and works beside the target" \
   "$(bash "$SCRIPT" "$T/tmpdir.md" | tr '\n' ',')" "gate-lenses,privacy-regime,"
eq "and leaves no temp file behind" "$(find "$T" -name '.forge-adapt-skills.*' | wc -l)" "0"

# --- fail closed on a missing file, rather than printing nothing and exiting 0 -------------------
err=$(bash "$SCRIPT" "$T/does-not-exist.md" 2>&1 >/dev/null); rc=$?
eq "a missing agent file exits 2 (fail closed, not a silent empty list)" "$rc" "2"
# rc alone is not enough: awk also exits 2 on a missing file, so removing the guard entirely left
# this green. Assert the deliberate message, which only the guard emits.
case "$err" in
  *"cannot read agent file"*) ok "a missing agent file reports WHY, not an awk error" ;;
  *) bad "a missing agent file reports why (got '$err')" ;;
esac

# --- #134.1: a SYMLINKED agent must not be replaced by a regular file ---------------------------
# The atomic rewrite writes beside the target and `mv`s it into place, which is what makes it atomic
# and mode-preserving. On a symlink that replaces the LINK with a regular file, so the real file
# keeps its plugin-scoped names and the companion skill then fails silently: exactly the outcome
# this script exists to prevent.
mkdir -p "$T/real" "$T/link"
cat > "$T/real/a.md" <<'M'
---
name: a
skills:
  - forge-kit-governance:ticket-gate-reference
---
body
M
ln -sf "$T/real/a.md" "$T/link/a.md"
bash "$SCRIPT" --rewrite "$T/link/a.md" >/dev/null 2>&1
[ -L "$T/link/a.md" ] && ok "the symlink is still a symlink after a rewrite" \
                      || bad "the rewrite replaced the symlink with a regular file"
# `grep -qv` is true whenever ANY line lacks the string, which is always. The assertion has to be
# that the plugin scope is absent from the WHOLE file.
if grep -q 'ticket-gate-reference' "$T/real/a.md" && ! grep -q 'forge-kit-governance:' "$T/real/a.md"
then ok "and the REAL file was rewritten to the bare name"
else bad "the real file kept its plugin scope"; fi

# --- #134.2: a trailing comment survives in BOTH shapes ----------------------------------------
# Sharing norm() between reader and rewriter fixed three rounds of drift, and made the rewriter
# inherit comment-stripping. The flow branch kept the comment because it preserves everything after
# the closing bracket; the block branch dropped it. Preserve in both.
cat > "$T/c-block.md" <<'M'
---
name: a
skills:
  - forge-kit-governance:ticket-gate-reference  # the lens pack
---
body
M
bash "$SCRIPT" --rewrite "$T/c-block.md" >/dev/null 2>&1
grep -q '# the lens pack' "$T/c-block.md" \
  && ok "a block-list item keeps its trailing comment" || bad "the block rewrite dropped the comment"
grep -q '^  - ticket-gate-reference' "$T/c-block.md" \
  && ok "and is still rewritten to the bare name" || bad "the block item was not rewritten"

cat > "$T/c-flow.md" <<'M'
---
name: a
skills: [forge-kit-governance:ticket-gate-reference]  # the pack
---
body
M
bash "$SCRIPT" --rewrite "$T/c-flow.md" >/dev/null 2>&1
grep -q '# the pack' "$T/c-flow.md" \
  && ok "a flow list keeps its trailing comment, as it already did" || bad "the flow rewrite dropped the comment"

# --- #134.3: a MAPPING list item is refused, not corrupted -------------------------------------
# `- name: x` was classified `block` and rewritten to `-  x`, turning a mapping into a scalar. The
# input is already invalid, but the contract this script advertises is REFUSE anything outside the
# two supported shapes, and corrupting invalid input is still corrupting.
cat > "$T/m.md" <<'M'
---
name: a
skills:
  - name: gate-lenses
---
body
M
before=$(cat "$T/m.md")
bash "$SCRIPT" --rewrite "$T/m.md" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a mapping list item is refused with exit 2" || bad "a mapping list item was not refused"
[ "$before" = "$(cat "$T/m.md")" ] && ok "and the file is left untouched" || bad "the file was corrupted"

echo ""
echo "forge-adapt-agent-skills tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
