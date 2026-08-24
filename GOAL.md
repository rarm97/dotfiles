# Goal: the claims this repo makes about itself

Every assertion so far tests behaviour. Nothing tests the things that DESCRIBE
that behaviour — the README, the comments that say "keep this in step with", the
paths one config hardcodes into another. Those drift silently by construction:
nothing executes them, so nothing notices when they stop being true.

Three of these are already confirmed wrong or unguarded. They are not
speculation; start from them.

## 1. The README is already stale

Line 132 says the pre-push hook takes **~19s**. That number was corrected in the
hook itself yesterday — it is 26s now, and was 242s before that — and the README
was not updated. It also does not mention `make test-fast`, which exists.

That is one drift found by looking for five minutes, which is a good reason to
stop relying on looking.

- Check the README against the repo mechanically: every `make` target it names
  must exist in the Makefile, every script and path it references must exist,
  and every target the Makefile defines should either appear in the README or be
  deliberately omitted.
- The timing claims are the hard part, because they are true only at the moment
  they are measured. Decide how to handle that rather than just fixing the
  numbers: either the README stops quoting figures and points at the thing that
  measures them, or the figures get asserted the way the hook's ceiling now is.
  Say which and why.

## 2. wezterm hardcodes a path nothing checks

`wezterm.lua` sets `default_prog` to `/opt/homebrew/bin/tmux`. That is the
Apple Silicon Homebrew prefix. `.zshrc` handles BOTH prefixes — it tries
`/opt/homebrew` then `/usr/local` — so the repo already knows the other exists.

On an Intel Mac, WezTerm would launch with a `default_prog` that is not there.
Establish what that actually does before deciding it matters: a terminal that
opens to nothing is bad, but it is loud, and loud is not this repo's problem.
Then decide between resolving tmux at runtime and asserting the path — and note
that `check.sh` already asserts every path *tmux.conf* references exists, while
nothing does the same for wezterm's.

Generalise it: find every absolute path hardcoded in any config here and check
they all exist. That check is cheap and it is the same class of defect as the
colour scheme that silently fell back.

## 3. Constants kept in step by a comment

Two pairs, both currently agreeing, both maintained by hand:

- `@resurrect-guard-min-windows '2'` in tmux.conf and `MIN_WINDOWS` in
  tmux-resurrect-saves. The script's comment literally says "Keep in step with
  @resurrect-guard-min-windows in tmux.conf."
- `@resurrect-delete-backup-after '90'` and `KEEP_DAILY_DAYS`. tmux.conf says
  "Kept in step with tmux-resurrect-saves' KEEP_DAILY_DAYS so the two retention
  mechanisms agree."

Nothing enforces either. Change one and the guard vetoes at a threshold prune
does not share, or resurrect's own backup deletion fights prune's retention —
and the first symptom is a save that is gone when you need it.

A comment asking a human to remember is not a mechanism. Assert both pairs, and
work out whether there are others; a comment saying "keep in step" is a good
thing to grep for.

## Standing constraints

- **No subagents against this machine.** Three incidents damaged the live tmux
  server. Anything touching tmux runs on a private socket in this session.
- Anything touching git runs against a throwaway clone.
- Plain shell. No new plugin dependencies.
- Explain the mechanism in the file.
- **Mutation-check every assertion**: introduce the defect it claims to catch
  and prove it fails. Seven assertions in this repo have turned out to be
  incapable of failing, including one that passed because `[ -e ]` follows a
  dangling symlink, and one where `assert "d" [ a ] && [ b ]` silently asserted
  only the first half.
- Prefer a check in `checks/repo.sh` over a test where the thing is static: it
  runs on every commit and in CI, and it is cheaper.
- Commit as you go with the reasoning in the message. Push, and confirm CI green
  before the next piece.
- If one of the three turns out not to matter, say so plainly and move on.

## Done means

The README cannot describe a target or path that does not exist, no config
hardcodes a path nothing checks, both constant pairs are asserted rather than
remembered, and anything left deliberately unguarded says why. Working tree
clean, CI green.
