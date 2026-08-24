#!/usr/bin/env bash
# The keybindings in tmux.conf, exercised by PRESSING them.
#
# Verifying a binding by running its command sequence from the CLI is a
# different path, and that gap produced three wrong answers in this repo:
# send-keys appeared to do nothing (it writes to the pane, not the client), a
# CLI run-shell resolved #{session_name} to a session it had not targeted and
# nearly produced a false bug report about prefix+Q, and the messaging test fell
# back to a stubbed tmux because no client could be attached.
#
# The bindings are loaded from the REAL tmux.conf, with tpm stripped. Retyping
# them here would test a copy, and the copy is what drifts.
#
# Private socket, scratch resurrect dir, fake project dirs. Never the live
# server.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: tens of seconds, because it drives a real terminal, editor or
# language server, or repeats an expensive command many times. `tests/run.sh
# --fast` skips these, and so does the pre-push hook; CI runs the complete set,
# so what the hook skips is caught on the way in rather than on the way out.
# Read by run.sh with grep, not by this shell.
# shellcheck disable=SC2034
SUITE_SLOW=1

CONF="$REPO_ROOT/tmux/.config/tmux/tmux.conf"
RDIR="$TEST_TMP/resurrect"
TEST_CONF="$TEST_TMP/tmux.conf"
MARKER_FILE="${TMPDIR:-/tmp}/tmux-resurrect-guard-$(id -u).pending"

# shellcheck disable=SC2034  # used by t(), press_keys() and the teardown
TMUX_SOCK="$(tmux_test_socket bindings)"
require_private_socket
cleanup_bindings() {
  rm -f "$MARKER_FILE"
  cleanup_tmux_suite
}
trap cleanup_bindings EXIT

mkdir -p "$RDIR" "$TEST_TMP/work"
rm -f "$MARKER_FILE"

# tpm removed: it clones plugins, and continuum would auto-save and auto-restore
# against whatever directory it found. Everything else in the file is real.
awk '
  /^if "test ! -d ~\/\.config\/tmux\/plugins\/tpm"/ { skip = 2; next }
  skip > 0 { skip--; next }
  /^run .~\/\.config\/tmux\/plugins\/tpm\/tpm./ { next }
  { print }
' "$CONF" >"$TEST_CONF"

# A server carrying the real bindings, pointed at scratch storage.
build_server() {
  t kill-server 2>/dev/null
  sleep 0.4
  t -f /dev/null new-session -d -s work -c "$TEST_TMP/work" || return 1
  t source-file "$TEST_CONF" || return 1
  # After sourcing, so the bindings write here and not to the real save dir.
  t set -g @resurrect-dir "$RDIR"
  t set -g @continuum-save-interval 0 # no timer firing mid-test
  return 0
}

# Predicates, so assertions can wait for the thing to happen rather than sleep a
# number of seconds chosen on this laptop.
session_gone() { ! t has-session -t "=$1" 2>/dev/null; }
session_exists() { t has-session -t "=$1" 2>/dev/null; }
window_count_is() { [ "$(t list-windows -t "$1" 2>/dev/null | wc -l | tr -d ' ')" = "$2" ]; }
window_index_is() { [ "$(t display-message -p -t "$1" '#{window_index}' 2>/dev/null)" = "$2" ]; }
last_is_not() { [ "$(readlink "$RDIR/last" 2>/dev/null)" != "$1" ]; }
save_exists() { [ -e "$RDIR/last" ]; }

# tmux.conf invokes helper scripts by absolute path under ~/.local/bin, and the
# save bindings invoke tmux-resurrect. Neither exists on a machine where the
# dotfiles have not been stowed and tpm has not run — a CI runner, for instance.
# The bindings that need them are skipped there, by name, rather than failing for
# a reason that has nothing to do with the binding.
KILL_SESSION="$HOME/.local/bin/tmux-kill-session"
CLEAR_SCROLLBACK="$HOME/.local/bin/tmux-clear-scrollback"
RESURRECT_SAVE="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"

section_skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; }

build_server || skip_suite "could not start a test tmux server with the real config"

assert "the real bindings are loaded" \
  [ "$(t list-keys -T prefix 2>/dev/null | grep -cE ' (Q|q|s|M-s|BSpace|c|h|l) ')" -ge 7 ]

# ---------------------------------------------------------------- prefix+Q

echo
echo "== prefix+Q kills the session the CLIENT is attached to, and no other =="
if [ ! -x "$KILL_SESSION" ]; then
  section_skip "prefix+Q and prefix+q: $KILL_SESSION is not stowed"
else
  # The path that runs when you actually press it has never been executed by a
  # test. tmux-kill-session reads #{client_session}, which only has a value when a
  # client is attached — so this cannot be checked any other way.
  build_server
  t new-session -d -s keepme
  t new-session -d -s alsokeep
  press_keys work C-a Q
  assert "the attached session is gone" wait_until 20 session_gone work
  assert "an unrelated session survives" session_exists keepme
  assert "...and so does the other one" session_exists alsokeep

  echo
  echo "== ...and on the last session it creates a replacement first =="
  # Otherwise the client has nowhere to go and WezTerm closes with it.
  build_server
  n_before="$(t list-sessions | wc -l | tr -d ' ')"
  assert "there is exactly one session to start with" [ "$n_before" -eq 1 ]
  press_keys work C-a Q
  assert "the session was killed" wait_until 20 session_gone work
  assert "but a replacement exists, so the client has somewhere to go" \
    [ "$(t list-sessions 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]

  # ---------------------------------------------------------------- prefix+q

  echo
  echo "== prefix+q kills a window when there is more than one =="
  build_server
  t new-window -t work -n second
  t new-window -t work -n third
  w_before="$(t list-windows -t work | wc -l | tr -d ' ')"
  # confirm-before puts up a "(y/n)" prompt; y answers it.
  press_keys work C-a q y
  assert "one window was killed" wait_until 20 window_count_is work "$((w_before - 1))"
  assert "the session is still there" session_exists work

  echo
  echo "== ...and falls through to kill-session on the last window =="
  build_server
  t new-session -d -s bystander
  press_keys work C-a q y
  assert "the single-window session was killed rather than emptied" wait_until 20 session_gone work
  assert "the bystander session is untouched" session_exists bystander
fi

# ---------------------------------------------------------------- prefix+s

echo
echo "== prefix+s saves, and says so truthfully =="
if [ ! -x "$RESURRECT_SAVE" ]; then
  section_skip "prefix+s and prefix+M-s: tmux-resurrect is not installed"
else
  build_server
  t new-window -t work -n two
  t new-window -t work -n three
  screen="$(press_keys_until work "saved" C-a s)"
  assert "a save was written" wait_until 20 save_exists
  saved="$(readlink "$RDIR/last")"
  assert "the status line reports the save" contains "$screen" "saved"
  refute "and does not claim a refusal" contains "$screen" "refused"

  echo
  echo "== ...and when the guard vetoes, it says THAT, not 'saved' =="
  # The bug this binding was rewritten for: it used to print "Session saved"
  # unconditionally, on top of the guard's veto notice, telling you the opposite
  # of what happened.
  for w in $(t list-windows -t work -F '#{window_index}' | tail -n +2); do
    t kill-window -t "work:$w"
  done
  sleep 0.5
  screen="$(press_keys_until work "refused" C-a s)"
  assert "'last' did not move — the throwaway state was refused" \
    [ "$(readlink "$RDIR/last")" = "$saved" ]
  assert "the status line says it was refused" contains "$screen" "refused"
  refute "and does NOT claim the session was saved" contains "$screen" "saved —"

  echo
  echo "== prefix+M-s forces past the guard =="
  press_keys work C-a M-s
  assert "the forced save moved 'last'" wait_until 25 last_is_not "$saved"
  assert "the force flag cleared itself" [ -z "$(t show-option -gqv @resurrect-guard-force)" ]
fi

# ---------------------------------------------------------------- prefix+BSpace

echo
echo "== prefix+BSpace does not type into whatever owns the pane =="
if [ ! -x "$CLEAR_SCROLLBACK" ]; then
  section_skip "prefix+BSpace: $CLEAR_SCROLLBACK is not stowed"
else
  build_server
  VICTIM="$TEST_TMP/victim.txt"
  printf 'hello world\nsecond line\n' >"$VICTIM"
  cp "$VICTIM" "$TEST_TMP/expected.txt"
  t send-keys -t work "vi $VICTIM" Enter
  sleep 2
  assert "an editor really is running (guards against a vacuous test)" \
    contains "$(t display-message -p '#{pane_current_command}')" vi
  press_keys work C-a BSpace
  t send-keys -t work Escape ':q!' Enter
  # Wait for the editor to actually exit, so the file on disk is settled before it
  # is compared. Quitting is asynchronous; comparing too early would read the file
  # while vi still held it.
  editor_gone() { ! contains "$(t display-message -p '#{pane_current_command}' 2>/dev/null)" vi; }
  assert "the editor exited" wait_until 20 editor_gone
  assert "the editor's buffer is untouched" cmp -s "$VICTIM" "$TEST_TMP/expected.txt"
fi

# ---------------------------------------------------------------- navigation

echo
echo "== window and session navigation =="
build_server
press_keys work C-a c
assert "prefix+c opens a window" wait_until 20 window_count_is work 2
# pane_current_path is the resolved path: on macOS /tmp is a symlink to
# /private/tmp, so comparing against the string passed to -c fails for the wrong
# reason.
assert "...in the current pane's directory" \
  [ "$(t display-message -p -t work '#{pane_current_path}')" = "$(cd "$TEST_TMP/work" && pwd -P)" ]

build_server
t new-window -t work
t new-window -t work
# The session exists before the config is sourced, so base-index 1 never applies
# to it and the windows start at 0. Ask rather than assume.
last_idx="$(t list-windows -t work -F '#{window_index}' | tail -1)"
prev_idx="$(t list-windows -t work -F '#{window_index}' | tail -2 | head -1)"
t select-window -t "work:$last_idx"
press_keys work C-a h
assert "prefix+h goes to the previous window" wait_until 20 window_index_is work "$prev_idx"
press_keys work C-a l
assert "prefix+l goes to the next window" wait_until 20 window_index_is work "$last_idx"

build_server
t new-window -t work
first_idx="$(t list-windows -t work -F '#{window_index}' | head -1)"
next_idx="$(t list-windows -t work -F '#{window_index}' | sed -n 2p)"
t select-window -t "work:$first_idx"
press_keys work C-a L
assert "prefix+L swaps the window rightwards and follows it" \
  wait_until 20 window_index_is work "$next_idx"

# switch-client moves the CLIENT, so #{client_session} is empty again the moment
# the helper detaches — querying it afterwards says nothing. The status line is
# the honest place to look: tmux.conf renders "#S" in status-left, so the
# session's name is on screen. Distinctive names, so a match cannot come from
# anywhere else on the line.
build_server
t rename-session -t work sessone
t new-session -d -s sesstwo
screen="$(press_keys_until sessone "sesstwo" C-a j)"
assert "prefix+j switches to the other session" contains "$screen" "sesstwo"

screen="$(press_keys_until sesstwo "sessone" C-a k)"
assert "prefix+k switches back" contains "$screen" "sessone"

# ---------------------------------------------------------------- coverage

echo
echo "== every binding is either pressed here or explained =="
# NOT DRIVEN, and why. Each of these needs sustained interaction with a UI whose
# output would have to be scraped from the client's screen, and a scraper racing
# a redraw is exactly the flaky test that teaches people to re-run rather than
# read.
#
#   prefix+w   choose-tree: a full-screen chooser
#   prefix+r   command-prompt: rename-window, needs typed input then Enter
#   prefix+R   command-prompt: rename-session, same
#   prefix+C   new-session: leaves the client on a new session mid-suite
#   prefix+f   display-popup running the fzf sessionizer
#   prefix+S   source-file: re-sources the config under the suite's feet
#   prefix+H   mirror of L, which is covered
#   prefix+C-a send-prefix: only observable by a program reading the pane
#   copy-mode-vi v / y  need copy-mode plus a selection plus a clipboard
undriven="w r R C f S H C-a v y"
driven="Q q s M-s BSpace c h l L j k"
# That these two lists between them cover every key tmux.conf binds is asserted
# in checks/repo.sh, which reads them out of here and compares the SETS. It was
# asserted here and compared the COUNTS — eleven plus ten against twenty-one
# `bind` lines — and a count cannot tell `bind w` being renamed to `bind W` from
# nothing having happened. It is a fact about two files, so it belongs in a
# check that runs on every commit rather than in a suite that needs a terminal.
printf '    %s pressed here, %s documented as not driven (checks/repo.sh asserts that is all of them)\n' \
  "$(printf '%s' "$driven" | wc -w | tr -d ' ')" \
  "$(printf '%s' "$undriven" | wc -w | tr -d ' ')"

finish
