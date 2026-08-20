# Goal: verify the promise, not just the parts

`restore.sh` has never been executed by a test. Not once. The word "restore"
appears in `tests/` only in comments and in one assertion about where a symlink
points.

Everything built here exists to protect a restore: the guard stops a throwaway
state becoming `last`, prune refuses to delete what `last` points at, promote
puts `last` back after damage. All of it verified. The thing they protect —
that restoring `last` actually reproduces your workspace — is assumed.

`bootstrap.sh` is the same story: 7 of its 12 functions have never been
executed. `stow_packages` is covered only because I went looking for the
stow-folding bug. `install_homebrew_macos`, `brew_install_pkgs`,
`install_rust`, `install_hooks`, `post_checks`, `need_cmd` and `is_macos` have
never run under a test.

Four bodies of work. Take them in this order — the first is the one that
matters.

## 1. Save → restore round-trip

On a private socket with a private resurrect dir: build a known workspace
(several sessions, distinct window names, distinct working directories, a
long-running program in a pane), save it, destroy it entirely, restore, and
assert the workspace came back. Session names, window names and indexes,
per-window working directories, which pane was active, which window was active
per session, and — since `@resurrect-capture-pane-contents` is on — that pane
contents came back too.

Then the cases that actually matter here:

- restore after a veto still gives the protected workspace, not the throwaway
  one
- restore after `promote` gives the promoted save
- restore of a save whose `pane_contents.tar.gz` was stashed and put back by the
  guard gives the right scrollback

That last one closes the loop on the wrinkle the guard exists to handle, which
has been reasoned about and never observed.

## 2. The pty harness and all 21 bindings

21 `bind` lines in `tmux.conf`; not one is exercised by pressing the key.
Verifying a binding by running its command sequence from the CLI is a different
path, and that gap produced three wrong answers in the last session, including
nearly reporting a live bug in `prefix+Q` that did not exist.

`python3`'s `pty` module is the reliable route; `script -q /dev/null` already
failed here once. Whichever you pick, prove it attaches — `list-clients` must
show 1 — before building anything on top of it.

Priority order within this:

1. `prefix+Q` and `prefix+q` — they destroy things
2. `prefix+s` and `prefix+M-s` — they must not lie about what happened
3. `prefix+BSpace` — it types into whatever owns the pane
4. the rest

## 3. Bootstrap's uncovered path

Do **not** run brew, rustup or the Homebrew installer for real. Stub them on
PATH and assert the script does the right things in the right order:

- it fails fast on a missing command
- it is idempotent on a second run
- a failing cask warns rather than aborting the whole bootstrap
- `install_rust` is a no-op when cargo is already present
- `install_hooks` sets `core.hooksPath` locally and not globally
- `post_checks` actually fails when a required path is missing

A fresh machine is where the expensive failures live and it is still mostly
unexercised.

## 4. Neovim at runtime

Today the checks prove every lua file parses. They do not prove nvim works.
With a scratch XDG data dir so the real plugin tree is untouched:

- does it start without errors
- does lazy load the expected plugins
- does an LSP client attach to a real file of a configured filetype
- does format-on-save actually reformat
- do the leader mappings resolve to what the config claims

If something needs network and cannot run offline, say so rather than skipping
silently.

## Operating rules, since this runs unattended

- **Never** touch the live tmux server or `~/.local/share/tmux/resurrect`.
  Private sockets named `dotfiles-test-*`, scratch dirs, fake `$HOME`. The
  existing `require_private_socket` guard is the pattern; extend it, do not work
  around it.
- **Do not spawn subagents against this machine.** Three separate incidents in
  the last session, one of which killed a live session and lost four windows of
  work. Work solo.
- Commit and push incrementally, one coherent change at a time, so a night's
  work is not one unreviewable diff and so progress survives an interruption.
- CI must be green at every push. It is the only verification that does not
  happen on this laptop.
- A flaky test is worse than no test, because people learn to re-run it. If a
  thing cannot be driven reliably, write down which and why, in the suite, and
  move on. Do not chase it into the ground and do not fake it.

## Done means

- restore is verified end to end
- every binding is either tested as a keypress or documented as undrivable with
  a reason
- bootstrap's install path is exercised against stubs
- nvim is proven to work rather than merely parse
- CI is green

The rule, unchanged: **if it can be wrong without saying so, it isn't
finished.** What this goal adds: a promise nobody has ever checked is the
largest way of being wrong without saying so.

## Two honest notes

**Item 1 is the one I would be most uncomfortable shipping without.** The rest
is thoroughness; that one is a guarantee this project has been asserting for a
week without evidence. If the night goes badly and only one thing lands, it
should be that.

**Item 4 may partly defeat me.** Driving nvim headlessly to the point where an
LSP client actually attaches means mason binaries, a real file, and async
startup — it is flaky by nature. Better to say now that it might end as
"started clean, plugins loaded, LSP attach proved undrivable offline" than to
produce a green run that quietly checked less than it looks like.
