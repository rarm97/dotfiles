# Goal: the branches nothing has ever run

The last goal asked whether the things that DESCRIBE this repo were true. This
one asks a question the descriptions cannot answer: of the code that decides
whether a save survives, how much has any test ever executed?

Measured, not guessed. The answer is three branches, each of them a path the
guard takes when something has already gone wrong.

## How it was measured, and why the first answer was wrong

Plain bash, no new dependencies: a `DEBUG` trap that appends `$LINENO` to a
file, switched on by an environment variable, and the four suites that drive the
guard run against it.

    if [ -n "${GUARD_COVERAGE:-}" ]; then
      set -T
      trap 'printf "%s\n" "$LINENO" >>"$GUARD_COVERAGE"' DEBUG
    fi

TWO THINGS make that number wrong if you do not know them, and the first
measurement here hit both:

- **`set -T` is not optional.** Without functrace the DEBUG trap does not fire
  inside shell functions, so every function body reads as dead code. The first
  run reported 47% of the guard never executed. With functrace it is 13%. A
  coverage figure that says half your script is dead is much more likely to be a
  broken measurement than a broken script.
- **A multi-line command reports only its first line.** The whole awk program
  inside `worst_session_collapse` looks uncovered because the trap fires once,
  at the `awk` that begins it. Before believing a gap, check whether the line
  above it was covered — if it was, you are looking at a continuation.

`BASH_XTRACEFD` is not an option: it arrived in bash 4.1 and the system bash
here is 3.2. It fails silently, writing nothing and reporting success.

## What it found: 117 of 135 lines, and three branches that matter

Every one of the three is a path the guard takes when it is already in trouble,
which is exactly where nobody thinks to look.

**1. `veto()` cannot carry out the veto.** When `cp -f "$last" "$candidate"`
fails, the guard logs `VETO FAILED` and puts a message on the status line. Its
own comment says this is the moment the clobber the script exists to prevent is
about to happen. No test has ever run it.

**2. `--post-save-all` finds the guard disarmed.** A veto stashed the pane
archive; between then and the restore, `@resurrect-guard` was turned off. The
guard drops the stash instead of putting it back, because — its comment again —
"an old archive put back over a newer one would be its own kind of data loss".
No test has ever run it.

**3. The `guard.log` trim.** It fires only once the log passes 200 lines, and no
test has ever written that many. Note what that means alongside the last goal's
work: the number 200 is now asserted to agree in three places, and the code that
acts on it has never executed. An agreed constant and a working mechanism are
different claims.

- Drive each of the three, on a private socket, and assert what the guard does
  rather than that it survived. The first two are reachable by making the copy
  fail (a read-only directory) and by unsetting the option between the two hook
  calls.
- Then point the same harness at `tmux-resurrect-saves`, `tmux-sessionizer` and
  `tidy.sh`. The question is not the percentage; it is which named branch has
  never run.
- Decide whether the harness stays. A `make coverage` that nobody runs is worse
  than a number in a commit message, and the instrumentation has to be OFF by
  default or it is a `trap` in a script that runs on every save. Say which and
  why.

## 2. Two plugins installed, sourced, advertised — and unasserted

`bootstrap.sh` brews `zsh-autosuggestions` and `zsh-syntax-highlighting`, and
the README's package table advertises both. `.zshrc` sources each one only if
its directory exists under `$HOMEBREW_PREFIX`, and that variable is set by `brew
shellenv` earlier in the same file — only if a brew was found. If it was not,
the test degrades to `-d "/share/zsh-autosuggestions"`, and BOTH are skipped
with no message. The same happens on a machine that has brew if the formula is
simply not installed. The shell just feels plainer.

check.sh already does this job one file over: it reads the formatters
`conform.lua` names and warns for each one missing. Nothing does it for these.

- Decide whether a missing plugin warns or fails, and say why. The formatter
  check warns, so that a half-set-up machine can still commit. That argument may
  or may not carry here.
- `.zshrc` sources things conditionally in several places and every one of those
  conditions is a silent skip. Find them all before deciding what to assert.

## 3. Two lists of language servers, one file, no relationship asserted

`nvim/.config/nvim/lua/rich/plugins/lsp.lua` names its servers twice:
`ensure_installed` (nine, what mason fetches) and `vim.lsp.enable` (ten). The
difference is `rust_analyzer`, and it is deliberate — that one comes from rustup.

Add a server to `ensure_installed` alone and it is downloaded and never
attached. Add it to `enable` alone and it is enabled and never downloaded.
Either way: a filetype with no language server, no error, and a config that
reads as though it should work.

`enable` ⊇ `ensure_installed` is the rule and `rust_analyzer` is the one
deliberate extra. An exception needs a reason recorded next to it, not a name.

## 4. The mutation harness cannot tell a working check from a dead one

`tests/test-check.sh` exists to prove every assertion in `checks/` can fail. It
does not currently prove that. Its verdict, at `tests/test-check.sh:97`, is:

    # The assertion must now report a failure mentioning its subject.
    if contains "$after" "✗"; then
      ok "$desc"

The comment says "mentioning its subject". The code looks for the glyph anywhere
in check.sh's output. `$marker` is read exactly once, at line 82, against the
BASELINE — before the mutation is applied. After the defect is introduced it is
never consulted again, so any failure anywhere satisfies the verdict.

Deleting an assertion IS caught: its marker vanishes from the baseline and
`_mutate` says so. The hole is an assertion that stays green and goes blind.

Demonstrated, not argued. Replace the `deprecated=` regex at
`checks/repo.sh:137` with one that matches nothing, leaving its message alone:

    ✓ no deprecated Neovim APIs in the lua config     (matches nothing)
    PASS  a deprecated Neovim API is caught           (its own mutation)
    77 passed, 0 failed

It survives because that mutation appends after `fidget.lua`'s top-level
`return {`, which is also a syntax error, so "every lua file parses" fires and
the verdict accepts that instead.

Measured across all of them, by dumping the actual ✗ lines per mutation:

| | |
| --- | --- |
| mutation verdicts | 59 |
| produced exactly one ✗ | 47 |
| produced more than one ✗ | 12 |
| of those 12, marker present in the failure text | 1 |
| can pass with the assertion they name fully blind | 11 |
| markers appearing in failure text at all | 12 of 59 |

The two twelves are near-disjoint; they overlap by one. The 47 are safe only by
accident — nothing enforces one failure per mutation, so any new check that also
trips on an existing mutation's defect quietly demotes it into the vulnerable
group. That ratchet runs the wrong way in a repo that keeps adding checks: three
went in this week.

Say the awkward part out loud rather than discovering it halfway. The obvious
fix — require the marker on the ✗ line — works for 12 of 59. The other 47 take
their marker from the ✓ wording while the ✗ is worded differently (`ok "line
wrap is on..."` against `bad "$OPTIONS sets wrap = false..."`). `bad()` prints
glyph and message on one line (`checks/lib.sh:13`), so a line-level verdict is
mechanically possible; it is a wording job, not a plumbing one. Either pair the
wordings or give `mutate` a second, explicit failure marker.

One more thing this harness cannot see, found the hard way: `mutate` runs its
command with output discarded and does not care whether it changed a byte. A
`sed` whose pattern stopped matching applies no defect, and the mutation then
reports that check.sh failed to catch a defect that was never introduced. That
happened here when a formatter padded the README's tables, and it is why the
`gd` pattern now tolerates whitespace. A mutation that changes nothing should
say so.

## Also worth doing, cheaply

Thirteen comparisons in `tests/` default a value that could not be read,
`[ "${x:-N}" ... ]`. Twelve default to the failing side. One does not:
`tests/test-fresh-machine.sh:105` defaults `dirty` to its own passing value, so
if the pipeline behind it ever produced nothing the assertion would pass having
tested nothing. It cannot today, because `grep -c` always prints a number —
which is the kind of reasoning that stops being true when someone edits a
pipeline without knowing it was load-bearing. The direction of a default decides
whether an assertion fails safe or fails open, and that is greppable.

## Standing constraints

- **No subagents against this machine.** Three incidents damaged the live tmux
  server. Anything touching tmux runs on a private socket in this session.
  `wezterm cli` also finds a running GUI through the environment: a spawn meant
  for a throwaway instance opened a window on the live one and attached a second
  client to the real tmux session. Address an instance by its own socket with
  the WEZTERM_* variables cleared.
- Anything touching git runs against a throwaway clone.
- **Instrumenting a tracked file: back it up, and restore it in the SAME command
  that runs the suites.** A run that outlives its turn leaves the working tree
  modified, and the file it modifies here is the one that protects your saves.
- Plain shell. No new plugin dependencies.
- Explain the mechanism in the file.
- **Mutation-check every assertion**: introduce the defect it claims to catch
  and prove it fails. Nine assertions here have turned out to be incapable of
  failing, including one that passed because `[ -e ]` follows a dangling
  symlink, one where `assert "d" [ a ] && [ b ]` silently asserted only the
  first half, and a binding accounting that compared counts, so a rename left
  both numbers unchanged. A tenth was caught before it shipped: a batched lua
  parse reported every file as parsing, because `print` under `nvim -l` writes
  to stderr and stderr was being discarded to keep nvim quiet.
- Prefer a check in `checks/repo.sh` over a test where the thing is static: it
  runs on every commit and in CI, and it is cheaper.
- A figure may appear in prose only where something reads it back;
  `checks/repo.sh` enforces that for the README and the hooks.
- Commit as you go with the reasoning in the message. Push, and confirm CI green
  before the next piece.
- If one of these turns out not to matter, say so plainly and move on.

## Done means

The three branches are driven and asserted rather than merely present, a
silently skipped shell plugin says something, the two server lists cannot
disagree without a recorded reason, no mutation passes while the assertion it
names is blind, a mutation that changes nothing says so, and whatever is left
deliberately uncovered says why. Working tree clean, CI green.
