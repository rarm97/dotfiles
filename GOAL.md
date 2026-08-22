# Goal: the automation nobody watches

Everything in this repo now depends on three mechanisms that run unattended, and
none of the three has ever been exercised. Each is a safety net whose failure
mode is silence.

Verify every claim below before acting on it. Some are inferences from reading;
at least one is probably wrong, and finding that out is a real result.

## 1. The git hooks — the thing that makes all of it automatic

`.githooks/pre-commit` runs check.sh, `.githooks/pre-push` runs the suites.
check.sh asserts the hook FILES exist, because they were once deleted while
`core.hooksPath` stayed set and git silently ran nothing. But nothing anywhere
proves git actually invokes them, or that they actually block anything. "The
file is present" is not "the commit is refused".

- Drive real `git commit` and `git push` against a throwaway clone. Break
  something check.sh catches; the commit must fail. Break something a suite
  catches; the push must fail. Then prove `--no-verify` still gets through,
  because a bypass that has quietly stopped working is its own bug.
- **pre-commit runs the full check.sh, not `--repo-only`.** That includes the
  machine half — fonts, WezTerm, formatters, a git identity. Work out what
  happens on a machine missing one of those: if the answer is "every commit is
  blocked until you install stylua", decide whether that is what you want and
  say so in the hook either way.
- **Both headers make timing claims that have almost certainly drifted.**
  pre-push says ~19s; the suite is now 16 suites including several that drive a
  pty. Measure both, correct the numbers, and consider whether a pre-push hook
  that takes minutes is one people will start bypassing — a hook routinely
  skipped is worse than no hook, because it still looks like coverage.

## 2. Continuum's unattended save — the reason the guard exists

The resurrect guard was written to protect saves that happen when nobody is
looking. Every test drives a save by hand. The automatic path has never run.

Continuum triggers saves through a `#()` interpolation in `status-right`, which
is an odd enough mechanism to be worth confirming rather than assuming.

- Prove a timed save actually fires, on a private socket, with the interval
  turned right down.
- Prove the guard runs on it — that the post-save-layout hook fires for a
  continuum save exactly as it does for a manual one, and that a degenerate
  automatic save is vetoed.
- Check what `@resurrect-guard-announce` does here. It is consumed at the top of
  the guard and is meant to keep timed saves silent unless vetoed. Confirm a
  timed save says nothing, and a vetoed timed save does.

## 3. The neovim config — 953 lines, 12 assertions

By some distance the worst-covered thing in the repo, and the one you look at
all day. Not a demand for 100 assertions; a demand that the parts which can be
silently wrong are the parts covered.

- Which keymaps are actually bound after startup, by name — the same shape as
  the eager-plugin assertion in test-performance.sh, which catches a real change
  that no timing threshold could.
- LSP: that a server attaches to a real buffer of the right filetype, offline.
  `nvim --headless FILE -c` works for this; `nvim -l` does NOT load the config
  runtimepath, which has already caused one wrong conclusion here.
- Formatters: conform is configured with `lsp_format = "fallback"`, which means
  a format check passes even when the named formatter does not exist. Any
  assertion here has to be mutation-checked against a deliberately bogus
  formatter name or it proves nothing. This has caught vacuous assertions before.

## Standing constraints

- **No subagents against this machine.** Three incidents damaged the live tmux
  server, one killing a five-window session. Anything touching tmux runs on a
  private socket in this session, or not at all.
- Anything touching git runs against a throwaway clone, never this repo's real
  history.
- Plain shell. No new plugin dependencies.
- Explain the mechanism in the file. I want to modify what you write without
  asking you what it does.
- **Mutation-check every assertion**: introduce the defect it claims to catch
  and prove it fails. This repo has produced six assertions that could not fail,
  including one that passed because `[ -e ]` follows a dangling symlink.
- Verify the mutation harness itself. It has twice produced clean-looking
  results that meant nothing.
- Commit as you go with the reasoning in the message. Push and confirm CI green
  before the next piece.

## Done means

Each of the three runs under test, every assertion fails when the thing it
describes is broken, anything left uncovered says so and why, the working tree
is clean and CI is green.
