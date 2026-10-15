# The forge-writes hook: reach, notes, bypasses

The `scan-forge-writes` hook (`plugins/forge-kit-security/hooks/scan-forge-writes.py`) is the third
leak-guard stage. The commit and push scans read files and history; text typed into
`gh issue|pr create|edit|comment` never touches either, so a private name or a real home path in an
agent-written ticket body reached the forge unscanned. This hook closes that for the text the
command line shows.

## Opt-in and install shape

- A PreToolUse `Bash` hook, registered by the plugin's `hooks/hooks.json` (timeout 10 s) and shell
  gated on the sentinel `.claude/scan-forge-writes` (content never read). Without the file it is inert.
- Plugin only. It finds the scanners from its own plugin root (`../skills/leak-guard/assets`), so a
  copy under `.claude/hooks/` would scan nothing; forge-adapt recommends the plugin instead.
- Fail open everywhere. It denies only on a scanner finding; every other outcome allows.
- The same sentinel (or `FORGE_LEAK_SCAN=1`) also switches on the second layer, `forge-lib.sh`'s
  own scan of the text its seven public writers are given (#539). The hook cannot see those bodies,
  because they travel as JSON on stdin of `gh api --input -`; the library scans them in the caller's
  shell, before the dry-run guard, and a finding returns 110 with a `forge-lib: <writer>: leak-guard:
  <rule> in <field> line <N>; not sent` line. Its call contract matches the one below (temp file per
  field, `--allow-file` when present, 4 s and 8 s, the first `<file>:<line>: <rule>:` parsed and the
  output discarded), plus the forge token variables removed from the scanner's environment. Its
  discovery is a soft probe (`FORGE_LEAK_GUARD_DIR`, its own directory, the sibling group in a source
  layout, then `$HOME/.claude/plugins`) and fails open with a note when no pair of marked scanners is
  found; see `forge-host/references/adopting-forge-lib.md`.

## What it reads

Writes are `gh issue|pr create|edit|comment`, after env assignments and the wrappers `command`,
`exec`, `time`, `nohup`, `env`, `builtin`, anywhere in a compound command (`&&`, `;`, `|`, newline,
subshell, `$(...)`). The command word may follow a shell reserved word (`do`, `then`, `else`, `elif`,
`if`, `while`, `until`, `{`, `!`), so loops, conditionals and brace groups are seen. Also read:

- a write inside a double-quoted `$(...)` or inside backticks (each such span is parsed again as a
  command of its own, nested to depth 4; a span that cannot be judged leaves the not-extractable note);
- gh's own spellings: `-R owner/repo`, `--repo owner/repo`, `--repo=owner/repo` (before or after
  `issue|pr`, and attached `-Rowner/repo`), and the alias `new` for `create`.

A shell comment is not code: a `#` that begins a word runs to the end of the line and is dropped, so an
apostrophe or a `<<` in a comment cannot desync the parse. `$#`, `${#x}` and `issue#5` are text. An
ANSI-C string `$'...'` is tracked so its escaped `'` keeps the quote state in step; as a body value it
is not a literal and leaves the not-extractable note. Per write it scans every text it can see, each
as its own temp file:

- `--title` and `-t`, `--body` and `-b` (space, `=`, attached `-bTEXT`, `-b=TEXT`);
- `--body-file` and `-F` files, read as bytes (symlinks followed, a leading `~` expanded, a relative
  path resolved against the payload `cwd`);
- a literal heredoc body (`--body "$(cat <<'EOF' ... EOF)"`, or `-F -` with a heredoc);
- a file written earlier in the same command only in the shape `cat > f <<'EOF'` with a terminated
  quoted heredoc, scanned from its literal text.

## Scanner call contract

The hook never hands a user path to a scanner. It writes the text to a 0600 `mkstemp` file
(`fgw*.txt`, unlinked in `finally`), runs the private scanner then the public one from the git
toplevel (else the cwd) as `bash <script> ... -- <temp>`, with `--allow-file
$CLAUDE_PROJECT_DIR/.leak-guard-allow` on the public one when that file exists. Exit 1 is a finding;
exit 2, any other non-zero status or a missing scanner is `scan did not run`.

Deadline: ONE hook-wide 8 s; each scanner run gets `min(4 s, remaining)` in its own process group,
killed whole on timeout. The hook keeps going after a timeout until the deadline, so a hanging
scanner costs about 8 s, under the 10 s registration timeout.

## Deny reason

`leak-guard: <flag as typed>[ heredoc] (write K) line N (<rule>)`, or `line ? (unparsed)` when the
finding line cannot be parsed. It never carries a path, a private name, its redaction, the matched
evidence or scanner output; the model gets the location and the rule, not the secret.

## Fixed notes (allow, one stderr line each)

| Note | When |
|---|---|
| `leak-guard: stdin body not scanned` | `-F -` or `--body-file -` fed by a pipe |
| `leak-guard: heredoc body not scanned` | an unterminated heredoc, or unbalanced quotes around one |
| `leak-guard: body written in the same command not scanned` | an earlier segment may have changed the file, or a `cd` precedes a relative path |
| `leak-guard: body not a regular file, not scanned` | a FIFO, directory or device |
| `leak-guard: body file unreadable, not scanned` | missing or unreadable |
| `leak-guard: body not extractable, not scanned` | a `$` or backtick in the value or path, an editor, `--web`, a template, `--fill*`, `--edit-last` alone, an expanding heredoc |
| `leak-guard: body over 1048576 bytes not scanned` | more than 1 MiB |
| `leak-guard: binary body not scanned` | a NUL byte |
| `leak-guard: scan did not run` | scanner exit 2, other failure or missing |
| `leak-guard: scan timed out` | the per-scan or hook-wide deadline |
| `leak-guard: payload not understood, not scanned` | a Bash payload with no usable command |

## Known bypasses, pinned by tests

- Out of scope subcommands in gh 2.74: `issue close|reopen --comment`, `pr close|reopen --comment`,
  `pr review --body`, `pr merge --body`, `release create --notes` and `gh api -f body=...`. No
  scanner starts for them. A call to `forge_issue_comment` (or any of the other six writers) is NOT
  read by this hook, but since #539 `forge-lib.sh` scans it itself when the project opted in.
- Still unscanned by either layer (#539, pinned by tests in `scripts/test-forge-lib.sh`): `forge_api`
  direct writes, `forge_milestone_create`, `forge_issue_milestone`, label writes, `sync-labels.sh`
  descriptions, any run with `FORGE_LEAK_SCAN=0` or a custom `FORGE_LEAK_GUARD_DIR`, a field over
  1 MiB (one note, not scanned), and every fail-open case: scanners not found, a scanner exiting
  other than 0 or 1, a timeout, a temp file that cannot be made. The one refusal outside a finding
  is an explicit `FORGE_LEAK_GUARD_DIR` that does not hold both marked scanners (110).
- A body produced by a script the command does not name (`python3 gen.py && gh issue comment 5
  --body-file w.md`) is judged on the file's content before the command runs.
- Anything behind a variable, a command substitution other than the heredoc idiom, a function, an
  alias, or a wrapper not in the list above (`env -u X gh ...` is one).
- A backslash-newline inside double quotes and a partly quoted heredoc delimiter are not modelled.
- A body changed between the hook and gh by another process.
- `-R other/repo` is scanned the same as the current repo (the flag no longer hides the write).
