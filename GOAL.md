# Goal: what the checks would not notice

The last goal asked whether the things that DESCRIBE this repo were true. They
mostly are now, and the ones that were not are asserted rather than remembered.

This one asks a harder question about the same net: where does it have holes,
and where does it have a hole that only shows under load. Three targets, all
confirmed by reading the files rather than guessed at.

## 1. Two plugins that are installed, sourced, advertised — and unasserted

`bootstrap.sh` brews `zsh-autosuggestions` and `zsh-syntax-highlighting`. The
README's package table advertises both. `.zshrc` sources each one only if the
directory is there:

    if [[ -d "${HOMEBREW_PREFIX:-}/share/zsh-autosuggestions" ]]; then

`HOMEBREW_PREFIX` is set by `brew shellenv` at the top of the same file, and
only if a brew was found. If it was not, the test degrades to `-d
"/share/zsh-autosuggestions"`, which is false, and BOTH plugins are skipped with
no message at all. The same happens, on a machine that has brew, if the formula
simply is not installed. The shell just feels plainer.

That is the exact shape check.sh exists for, and check.sh already does this job
one file over: it reads the formatters `conform.lua` names and warns for each
one that is not installed. Nothing does it for these two.

- Decide whether a missing plugin is a WARNING or a FAILURE, and say why. The
  formatter check warns, on the argument that a half-set-up machine must still
  be able to commit. The same argument may or may not apply here.
- The interesting part is not the two names. It is that `.zshrc` sources things
  conditionally in several places and every one of those conditions is a silent
  skip. Find them all before deciding what to assert.

## 2. Two lists of language servers, one file, no relationship asserted

`nvim/.config/nvim/lua/rich/plugins/lsp.lua` names its servers twice:
`ensure_installed` (nine of them, what mason fetches) and `vim.lsp.enable`
(ten). The difference is `rust_analyzer`, and it is deliberate — the file says
so, because that one comes from rustup rather than mason.

Add a server to `ensure_installed` and forget `enable` and it is downloaded and
never attached. Add it to `enable` and forget `ensure_installed` and it is
enabled and never downloaded. Either way you get a filetype with no language
server, no error, and a config that reads as though it should work.

The exception is the whole difficulty: `enable` ⊇ `ensure_installed` is the
rule, and `rust_analyzer` is the one deliberate extra. An exception list needs a
reason attached to it, not just a name.

## 3. Assertions that fail open

Thirteen comparisons in `tests/` default a value that could not be read:
`[ "${x:-N}" ... ]`. Twelve of them default to the FAILING side, so a value that
never arrived takes the assertion down with it. One does not:

    tests/test-fresh-machine.sh:105
    dirty="$(... | grep -c 'tmux/.local/share' || true)"
    assert "nothing was written into tmux/.local/" [ "${dirty:-0}" -eq 0 ]

The default is the passing value. If the pipeline behind it ever produces
nothing, that assertion passes without testing anything. It cannot today,
because `grep -c` always prints a number — which is precisely the kind of
reasoning that stops being true when someone edits the pipeline and has no idea
it was load-bearing.

The direction of a default decides whether an assertion fails safe or fails
open, and nothing checks it. That is greppable.

- The wider version is worth stating even if it is not all doable at once.
  `tests/test-check.sh` mutation-covers `checks/*.sh`: every assertion there has
  a defect introduced and is proved to fail. NOTHING mutation-covers the
  eighteen suites, and this repo has a record of assertions that could not fail
  — two more were found while writing the last goal's work, a binding
  accounting that compared counts and an eager-plugin test compared against a
  remembered number.
- Start where a false pass costs most rather than where it is easiest: the guard
  and prune suites decide whether a save you need is still there.

## Standing constraints

- **No subagents against this machine.** Three incidents damaged the live tmux
  server. Anything touching tmux runs on a private socket in this session.
  Note also that `wezterm cli` finds a running GUI through the environment: a
  spawn meant for a throwaway instance opened a window on the live one and
  attached a second client to the real tmux session. Address an instance by its
  own socket, with the WEZTERM_* variables cleared.
- Anything touching git runs against a throwaway clone.
- Plain shell. No new plugin dependencies.
- Explain the mechanism in the file.
- **Mutation-check every assertion**: introduce the defect it claims to catch
  and prove it fails. Nine assertions in this repo have turned out to be
  incapable of failing, including one that passed because `[ -e ]` follows a
  dangling symlink, one where `assert "d" [ a ] && [ b ]` silently asserted only
  the first half, and a binding accounting that compared counts, so renaming a
  key left both numbers unchanged. A tenth was caught before it shipped, which
  is the only reason it is not on that list: a batched lua parse reported every
  file as parsing, because `print` under `nvim -l` writes to stderr and stderr
  was being discarded to keep nvim quiet.
- Prefer a check in `checks/repo.sh` over a test where the thing is static: it
  runs on every commit and in CI, and it is cheaper.
- A figure may appear in prose only where something reads it back. `checks/repo.sh`
  enforces this for the README and the hooks.
- Commit as you go with the reasoning in the message. Push, and confirm CI green
  before the next piece.
- If one of the three turns out not to matter, say so plainly and move on.

## Done means

A silently skipped shell plugin says something, the two server lists cannot
disagree without a reason recorded, no assertion defaults to its own passing
value, and whatever is left deliberately unguarded says why. Working tree clean,
CI green.
