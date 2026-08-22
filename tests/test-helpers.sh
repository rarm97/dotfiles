#!/usr/bin/env bash
# The older tmux helpers. Each assertion here is a bug that was live.
#
# Real tmux, private socket. These scripts drive a terminal, so there is no
# honest way to test them without one.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: tens of seconds, because it drives a real terminal, editor or
# language server, or repeats an expensive command many times. `tests/run.sh
# --fast` skips these; the pre-push hook still runs everything, and so does CI.
# Read by run.sh with grep, not by this shell.
# shellcheck disable=SC2034
SUITE_SLOW=1

# shellcheck disable=SC2034  # used by t() and tmux_test_teardown() in lib.sh
TMUX_SOCK="$(tmux_test_socket helpers)"
require_private_socket
trap cleanup_tmux_suite EXIT

t kill-server 2>/dev/null
sleep 0.3
t -f /dev/null new-session -d -s alpha -x 80 -y 24 ||
  skip_suite "could not start a test tmux server"

# ---------------------------------------------------------------- clear-scrollback

echo "== tmux-clear-scrollback must not type into whatever owns the pane =="
VICTIM="$TEST_TMP/victim.txt"
EXPECTED="$TEST_TMP/expected.txt"
printf 'hello world\nsecond line\nthird line\n' >"$VICTIM"
cp "$VICTIM" "$EXPECTED"

# The old binding sent "clear" Enter unconditionally. In vim, normal-mode c+l
# starts a change operation, "ear" is inserted as text, Enter splits the line —
# and the clear-history that follows wipes the scrollback that would have shown
# you. Verified: it turned "hello world" into "ear" / "ello world".
t send-keys "vi $VICTIM" Enter
sleep 2
cmd="$(t display-message -p '#{pane_current_command}')"
assert "an editor is genuinely running in the pane (guards against a vacuous test)" \
  contains "$cmd" vi
t run-shell "$BIN/tmux-clear-scrollback"
sleep 1.2
t send-keys Escape ':q!' Enter
sleep 1.5
assert "the editor's buffer is untouched" cmp -s "$VICTIM" "$EXPECTED"

echo
echo "== ...but a shell pane really is cleared =="
# shellcheck disable=SC2016  # must reach the pane's shell unexpanded
t send-keys 'for i in $(seq 1 200); do echo padding-line-$i; done' Enter
sleep 2.5
before="$(t display-message -p '#{history_size}')"
assert "the pane has real scrollback to clear" [ "${before:-0}" -gt 50 ]
assert "the pane is a shell" contains "$(t display-message -p '#{pane_current_command}')" sh
t run-shell "$BIN/tmux-clear-scrollback"
sleep 1.5
assert "scrollback is gone" [ "$(t display-message -p '#{history_size}')" -eq 0 ]
assert "and so is the visible screen" \
  [ "$(t capture-pane -p | grep -c padding-line)" -eq 0 ]

# ---------------------------------------------------------------- kill-session

echo
echo "== tmux-kill-session refuses to run outside tmux =="
# Without the guard, display-message had no client, $name came back empty, and
# the script ran `kill-session -t "="`. Worse, with no server running at all the
# `new-session -d` inside started one and left a stray detached session — the
# very kind of one-window state the resurrect guard then has to defend against.
before_n="$(tmux -L "$TMUX_SOCK" list-sessions | wc -l | tr -d ' ')"
refute "it exits non-zero with no \$TMUX" env -u TMUX "$BIN/tmux-kill-session"
assert "it started no server and created no stray session" \
  [ "$(tmux -L "$TMUX_SOCK" list-sessions | wc -l | tr -d ' ')" = "$before_n" ]

echo
echo "== ...and inside tmux with no client, it refuses rather than guessing =="
# The old version used #{session_name}, which with no attached client still
# returns a name — the most recently active session, NOT the invoking one.
# Observed directly: sessions alpha/doomed/survivor, run-shell targeting doomed,
# and #{session_name} resolved to "survivor". #{client_session} is empty in that
# situation, so the guard turns a wrong guess into a loud refusal.
t new-session -d -s doomed
t new-session -d -s survivor
n_before="$(t list-sessions | wc -l | tr -d ' ')"
# run-shell discards the script's exit status, so record it explicitly. Without
# this the assertions below pass with the `exit 1` deleted: the message is still
# printed, and `kill-session -t "="` with an empty name happens to fail rather
# than kill something — the right outcome by accident, not by design.
t run-shell -t doomed:0 \
  "$BIN/tmux-kill-session >$TEST_TMP/kill.out 2>&1; echo \$? >$TEST_TMP/kill.rc"
sleep 1.5
assert "it refuses when it cannot identify the session" \
  contains "$(cat "$TEST_TMP/kill.out" 2>/dev/null)" "no attached client"
assert "and exits non-zero rather than carrying on with an empty name" \
  [ "$(cat "$TEST_TMP/kill.rc" 2>/dev/null)" != "0" ]
# The refusal must be the ONLY thing it says. Deleting the `exit` leaves the
# status non-zero anyway — `kill-session -t "="` cannot match a session, so it
# fails and that becomes the status — which makes the status assertion above
# pass for a reason the script does not rely on. What actually changes is that
# it goes on to attempt switch-client and kill-session after having refused,
# and tmux answers with "no current client" and "no mouse target".
assert "and says nothing further — it stops rather than attempting the kill" \
  [ "$(grep -c . "$TEST_TMP/kill.out" 2>/dev/null)" -eq 1 ]
assert "and kills nothing at all" [ "$(t list-sessions | wc -l | tr -d ' ')" = "$n_before" ]
assert "specifically, it did not kill some unrelated session" t has-session -t "=survivor"

# NOT COVERED, deliberately: the branch where `tmux new-session -d` fails while
# killing the last session, so the client would be left with nowhere to go.
# Reaching it needs a server that accepts commands but cannot create a session,
# and there is no honest way to stage that — stubbing tmux would test the stub.
# Recorded here so the next mutation sweep does not rediscover it as a gap.
#
# NOT COVERED: the real path, where a key press supplies a client and the script
# kills that client's session. Driving a genuine attached client from a test
# needs a pty the harness does not have, and a test that fakes it would only be
# testing the fake. #{client_session} is correct there by definition — it names
# the session the invoking client is attached to — but that is reasoning, not a
# passing assertion, and it is recorded here rather than left implied.

# tmux-sessionizer used to be tested here too. It has its own suite now —
# test-sessionizer.sh — because the naming rules turned out to need a dozen
# assertions rather than four, and two live defects came out of writing them.

finish
