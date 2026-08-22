# Goal: the happy path is the one you actually use

The last goal proved the tools refuse bad input correctly. Almost nothing
proves they do the right thing on the ordinary path — the one taken every day,
where a mistake is a wrong workspace rather than an error message.

Two targets. Verify every claim below before acting on it: several are
inferences from reading the code, not observed failures, and at least one is
probably wrong.

## 1. tmux-sessionizer

The weakest script in the repo, and the most used. It has three assertions and
no error handling at all. Specifically:

- It is the only script here without `set -uo pipefail`. Establish whether
  adding it is safe — `[[ -z "$selected" ]] && exit 0` and the unchecked tmux
  calls may behave differently under `-u`. If it is not safe, say why in the
  file rather than leaving the omission looking accidental.

- **The collision fix may reproduce its own bug one level up.** When
  `~/learning/api` and `~/coding_projects/api` collide, the name is qualified to
  `learning_api`. Nothing checks whether THAT name is also taken by a different
  path. If it is, the script switches to the wrong session — silently, which is
  the exact defect the qualification was written to prevent. Verify this
  reproduces before changing anything; if it does, fix it and assert it.

- **A missing fzf is indistinguishable from a cancelled selection.** Both leave
  `selected` empty and exit 0. Someone on a fresh machine gets a script that
  appears to do nothing, successfully. Decide whether that is worth a check and
  say so either way.

- Every tmux call is unchecked: `new-session -A`, `new-session -ds`,
  `switch-client -t`. Work out which of those can actually fail in a way that
  matters, and cover those. Do not add error handling to all three reflexively —
  a check that can never fire is noise, and the file should say which ones you
  ruled out and why.

- Session names replace `.` with `_` because tmux dislikes dots. Establish what
  else tmux dislikes (`:` at least) and whether a directory name containing it
  is reachable here. Test the answer, whatever it is.

- The suite cannot drive the fzf path or the switch-client path. `with_pty_client`
  in tests/lib.sh exists precisely for this — a real client makes
  `switch-client` meaningful, and fzf can be driven through a pty or replaced
  with a stub on PATH. If one of them genuinely cannot be driven, record it as
  NOT COVERED with the reason, in the file, the way the other suites now do.

## 2. The restore round trip, across more than one shape

test-restore.sh proves the promise once: build a workspace, save it, destroy it,
restore it, check it came back. That is the right test. It runs against a single
shape.

Extend it to the shapes a real session actually takes, and make each one prove
something the others do not:

- more than one session, restored together
- a session with several windows and split panes, with the layout checked
- window and session NAMES preserved, not just counts
- panes whose working directory is not `$HOME`
- a pane running something other than a shell when the save was taken
- restore into a server that already has sessions, rather than an empty one

The last is the one most likely to be broken and least likely to be noticed.

## Standing constraints

- **No subagents against this machine.** Three separate incidents damaged the
  live tmux server, one of them killing a five-window session. Any work that
  touches tmux runs against a private socket in this session, or not at all.
- Plain shell. No new plugin dependencies.
- Explain the mechanism in the file. I want to be able to modify whatever you
  write without asking you what it does.
- **Mutation-check every assertion.** Introduce the defect it claims to catch
  and prove it fails. An assertion that cannot fail is worse than no assertion,
  and this repo has now produced five of them — including one that passed
  because `[ -e ]` follows a dangling symlink and reported the file it was
  looking at as absent.
- Verify the mutation harness itself. It has silently produced clean-looking
  results twice: once counting a nonexistent suite file as a kill, once running
  under zsh, which does not word-split, so every mutant looked caught.
- Commit as you go, with the reasoning in the message. Push and confirm CI green
  before moving to the next piece.
- If a claim above turns out to be wrong, say so plainly and move on. Finding
  that the collision bug does not reproduce is a real result, not a failure.

## Done means

Both scripts have assertions that fail when the behaviour they describe is
broken, every branch is taken or documented as unreachable with a reason, the
working tree is clean, and CI is green.
