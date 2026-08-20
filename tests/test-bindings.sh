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

build_server || skip_suite "could not start a test tmux server with the real config"

assert "the real bindings are loaded" \
  [ "$(t list-keys -T prefix 2>/dev/null | grep -cE ' (Q|q|s|M-s|BSpace|c|h|l) ')" -ge 7 ]

# ---------------------------------------------------------------- prefix+Q

echo
echo "== prefix+Q kills the session the CLIENT is attached to, and no other =="
# The path that runs when you actually press it has never been executed by a
# test. tmux-kill-session reads #{client_session}, which only has a value when a
# client is attached — so this cannot be checked any other way.
build_server
t new-session -d -s keepme
t new-session -d -s alsokeep
press_keys work C-a Q
sleep 1.5
refute "the attached session is gone" t has-session -t "=work"
assert "an unrelated session survives" t has-session -t "=keepme"
assert "...and so does the other one" t has-session -t "=alsokeep"

echo
echo "== ...and on the last session it creates a replacement first =="
# Otherwise the client has nowhere to go and WezTerm closes with it.
build_server
n_before="$(t list-sessions | wc -l | tr -d ' ')"
assert "there is exactly one session to start with" [ "$n_before" -eq 1 ]
press_keys work C-a Q
sleep 1.5
assert "a session still exists afterwards" [ "$(t list-sessions 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]
refute "but it is not the one that was killed" t has-session -t "=work"

# ---------------------------------------------------------------- prefix+q

echo
echo "== prefix+q kills a window when there is more than one =="
build_server
t new-window -t work -n second
t new-window -t work -n third
w_before="$(t list-windows -t work | wc -l | tr -d ' ')"
# confirm-before puts up a "(y/n)" prompt; y answers it.
press_keys work C-a q y
sleep 1.5
assert "one window was killed" [ "$(t list-windows -t work 2>/dev/null | wc -l | tr -d ' ')" -eq $((w_before - 1)) ]
assert "the session is still there" t has-session -t "=work"

echo
echo "== ...and falls through to kill-session on the last window =="
build_server
t new-session -d -s bystander
press_keys work C-a q y
sleep 1.5
refute "the single-window session was killed rather than emptied" t has-session -t "=work"
assert "the bystander session is untouched" t has-session -t "=bystander"

# ---------------------------------------------------------------- prefix+s

echo
echo "== prefix+s saves, and says so truthfully =="
build_server
t new-window -t work -n two
t new-window -t work -n three
screen="$(press_keys_capture work C-a s)"
sleep 2
assert "a save was written" [ -e "$RDIR/last" ]
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
screen="$(press_keys_capture work C-a s)"
sleep 2
assert "'last' did not move — the throwaway state was refused" \
  [ "$(readlink "$RDIR/last")" = "$saved" ]
assert "the status line says it was refused" contains "$screen" "refused"
refute "and does NOT claim the session was saved" contains "$screen" "saved —"

echo
echo "== prefix+M-s forces past the guard =="
press_keys work C-a M-s
sleep 3
refute "the forced save moved 'last'" [ "$(readlink "$RDIR/last")" = "$saved" ]
assert "the force flag cleared itself" [ -z "$(t show-option -gqv @resurrect-guard-force)" ]

# ---------------------------------------------------------------- prefix+BSpace

echo
echo "== prefix+BSpace does not type into whatever owns the pane =="
build_server
VICTIM="$TEST_TMP/victim.txt"
printf 'hello world\nsecond line\n' >"$VICTIM"
cp "$VICTIM" "$TEST_TMP/expected.txt"
t send-keys -t work "vi $VICTIM" Enter
sleep 2
assert "an editor really is running (guards against a vacuous test)" \
  contains "$(t display-message -p '#{pane_current_command}')" vi
press_keys work C-a BSpace
sleep 1.5
t send-keys -t work Escape ':q!' Enter
sleep 1.5
assert "the editor's buffer is untouched" cmp -s "$VICTIM" "$TEST_TMP/expected.txt"

# ---------------------------------------------------------------- navigation

echo
echo "== window and session navigation =="
build_server
press_keys work C-a c
sleep 1
assert "prefix+c opens a window" [ "$(t list-windows -t work | wc -l | tr -d ' ')" -eq 2 ]
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
sleep 1
assert "prefix+h goes to the previous window" \
  [ "$(t display-message -p -t work '#{window_index}')" = "$prev_idx" ]
press_keys work C-a l
sleep 1
assert "prefix+l goes to the next window" \
  [ "$(t display-message -p -t work '#{window_index}')" = "$last_idx" ]

build_server
t new-window -t work
first_idx="$(t list-windows -t work -F '#{window_index}' | head -1)"
next_idx="$(t list-windows -t work -F '#{window_index}' | sed -n 2p)"
t select-window -t "work:$first_idx"
press_keys work C-a L
sleep 1
assert "prefix+L swaps the window rightwards and follows it" \
  [ "$(t display-message -p -t work '#{window_index}')" = "$next_idx" ]

# switch-client moves the CLIENT, so #{client_session} is empty again the moment
# the helper detaches — querying it afterwards says nothing. The status line is
# the honest place to look: tmux.conf renders "#S" in status-left, so the
# session's name is on screen. Distinctive names, so a match cannot come from
# anywhere else on the line.
build_server
t rename-session -t work sessone
t new-session -d -s sesstwo
screen="$(press_keys_capture sessone C-a j)"
assert "prefix+j switches to the other session" contains "$screen" "sesstwo"

screen="$(press_keys_capture sesstwo C-a k)"
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
total="$(grep -cE '^bind ' "$CONF")"
covered="$(printf '%s %s' "$driven" "$undriven" | wc -w | tr -d ' ')"
assert "every binding in tmux.conf is accounted for" [ "$covered" -eq "$total" ]
printf '    %s pressed, %s documented as not driven, %s total\n' \
  "$(printf '%s' "$driven" | wc -w | tr -d ' ')" \
  "$(printf '%s' "$undriven" | wc -w | tr -d ' ')" "$total"

finish
