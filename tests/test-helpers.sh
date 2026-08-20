#!/usr/bin/env bash
# The three older tmux helpers. Each assertion here is a bug that was live.
#
# Real tmux, private socket. These scripts drive a terminal, so there is no
# honest way to test them without one.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034  # used by t() and tmux_test_teardown() in lib.sh
TMUX_SOCK="$(tmux_test_socket helpers)"
require_private_socket
trap cleanup_tmux_suite EXIT

t kill-server 2>/dev/null
sleep 0.3
t -f /dev/null new-session -d -s alpha -x 80 -y 24 || {
  echo "  SKIP  could not start a test tmux server"
  exit 0
}

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
t run-shell -t doomed:0 "$BIN/tmux-kill-session >$TEST_TMP/kill.out 2>&1"
sleep 1.5
assert "it refuses when it cannot identify the session" \
  contains "$(cat "$TEST_TMP/kill.out" 2>/dev/null)" "no attached client"
assert "and kills nothing at all" [ "$(t list-sessions | wc -l | tr -d ' ')" = "$n_before" ]
assert "specifically, it did not kill some unrelated session" t has-session -t "=survivor"

# NOT COVERED: the real path, where a key press supplies a client and the script
# kills that client's session. Driving a genuine attached client from a test
# needs a pty the harness does not have, and a test that fakes it would only be
# testing the fake. #{client_session} is correct there by definition — it names
# the session the invoking client is attached to — but that is reasoning, not a
# passing assertion, and it is recorded here rather than left implied.

# ---------------------------------------------------------------- sessionizer

echo
echo "== tmux-sessionizer disambiguates same-named projects =="
# Named by basename alone, ~/coding_projects/api and ~/learning/api collided:
# picking the second silently switched you to the first one's session.
mkdir -p "$TEST_TMP/coding_projects/api" "$TEST_TMP/learning/api"
first="$TEST_TMP/coding_projects/api"
second="$TEST_TMP/learning/api"

# Exercise the script's own naming logic by driving it with an explicit path,
# which is the branch `if [[ $# -eq 1 ]]` takes — no fzf involved. The script
# exits non-zero here because its final switch-client has no client to switch
# to; creating and naming the session is what these assertions are about, so its
# output is discarded rather than cluttering the report.
(cd "$TEST_TMP" && tmux -L "$TMUX_SOCK" run-shell "$BIN/tmux-sessionizer '$first' >/dev/null 2>&1") 2>/dev/null
sleep 1.5
assert "the first project got a session named for its basename" t has-session -t "=api"

(cd "$TEST_TMP" && tmux -L "$TMUX_SOCK" run-shell "$BIN/tmux-sessionizer '$second' >/dev/null 2>&1") 2>/dev/null
sleep 1.5
assert "the second got a distinct, parent-qualified session" t has-session -t "=learning_api"

api_path="$(t list-sessions -F '#{session_name}	#{session_path}' |
  awk -F'\t' '$1 == "api" { print $2 }')"
assert "'api' still points at the FIRST project, not the second" [ "$api_path" = "$first" ]

n_before="$(t list-sessions | wc -l | tr -d ' ')"
(cd "$TEST_TMP" && tmux -L "$TMUX_SOCK" run-shell "$BIN/tmux-sessionizer '$first' >/dev/null 2>&1") 2>/dev/null
sleep 1.5
assert "re-picking the first reuses its session rather than duplicating it" \
  [ "$(t list-sessions | wc -l | tr -d ' ')" = "$n_before" ]

finish
