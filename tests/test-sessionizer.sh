#!/usr/bin/env bash
# tmux-sessionizer: does it take you to the project you picked?
#
# There is exactly one thing this script must never do, and it is not crash —
# it is take you somewhere else. A wrong session looks completely normal: a
# prompt, a directory, your files. You notice when you have been editing the
# wrong copy for ten minutes.
#
# Real tmux on a private socket, driven by path rather than through fzf, which
# is the branch `if [[ $# -eq 1 ]]` takes.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: drives a real terminal. `tests/run.sh --fast` skips these; the
# pre-push hook and CI still run them.
# shellcheck disable=SC2034  # read by run.sh with grep, not by this shell
SUITE_SLOW=1

# shellcheck disable=SC2034  # used by t() and tmux_test_teardown() in lib.sh
TMUX_SOCK="$(tmux_test_socket sessionizer)"
require_private_socket
trap cleanup_tmux_suite EXIT

t kill-server 2>/dev/null
sleep 0.3
t -f /dev/null new-session -d -s base -x 80 -y 24 ||
  skip_suite "could not start a test tmux server"

# The script's last act is switch-client, which has no client to switch to here,
# so it exits non-zero and run-shell says so on the server's stderr. That is
# expected and unrelated to what is being asserted; discard it rather than let
# it litter the report.
sessionize() {
  t run-shell "$BIN/tmux-sessionizer '$1' >/dev/null 2>&1 || true"
  sleep 1.2
}
path_of() { # $1 = session name -> its working directory, or empty
  t list-sessions -F '#{session_name}	#{session_path}' 2>/dev/null |
    awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'
}
n_sessions() { t list-sessions 2>/dev/null | wc -l | tr -d ' '; }

# ---------------------------------------------------------------- basic naming

echo "== a project gets a session named for its directory =="
P="$TEST_TMP/coding_projects/api"
mkdir -p "$P"
sessionize "$P"
assert "the session exists under its basename" t has-session -t "=api"
assert "and is rooted at the directory that was picked" [ "$(path_of api)" = "$P" ]

n="$(n_sessions)"
sessionize "$P"
assert "picking it again reuses the session rather than duplicating it" \
  [ "$(n_sessions)" = "$n" ]

# ---------------------------------------------------------------- one collision

echo
echo "== two roots, same basename =="
# ~/coding_projects/api and ~/learning/api both want to be "api". Without the
# parent qualification, picking the second silently switches you to the first.
Q="$TEST_TMP/learning/api"
mkdir -p "$Q"
sessionize "$Q"
assert "the second gets a distinct, parent-qualified name" t has-session -t "=learning_api"
assert "rooted at the second project" [ "$(path_of learning_api)" = "$Q" ]
assert "and the first is still rooted where it was" [ "$(path_of api)" = "$P" ]

# ---------------------------------------------------------------- two collisions

echo
echo "== three roots, where the qualified name ALSO collides =="
# The qualification is one level deep. ~/other/learning/api qualifies to
# "learning_api" — which the previous project already took. has-session finds
# it, no session is created, and switch-client takes you to the wrong project:
# exactly the defect the qualification exists to prevent, one level up.
# Reproduced before it was fixed.
R="$TEST_TMP/other/learning/api"
mkdir -p "$R"
sessionize "$R"
p_r="$(path_of learning_api)"
assert "the third project gets a session of its own" \
  [ -n "$(t list-sessions -F '#{session_path}' | grep -Fx "$R")" ]
assert "and 'learning_api' still belongs to the project that claimed it" \
  [ "$p_r" = "$Q" ]

# ---------------------------------------------------------------- tmux's own rewriting

echo
echo "== characters tmux rewrites behind your back =="
# tmux stores a session called "a.b" as "a_b" — dots and colons are its target
# separators, so it substitutes them silently. That is WHY the script maps them
# itself: if it did not, its own has-session lookup and its session_path
# comparison would use a name tmux never stored, and the collision check would
# never match. The script handled dots and not colons, so two directories
# differing only by a colon collapsed into one session. Verified before fixing.
C1="$TEST_TMP/one/we:b"
C2="$TEST_TMP/two/we:b"
mkdir -p "$C1" "$C2"
sessionize "$C1"
assert "a colon in the name still produces a session" \
  [ -n "$(t list-sessions -F '#{session_path}' | grep -Fx "$C1")" ]
sessionize "$C2"
assert "and the second one is NOT swallowed by the first" \
  [ -n "$(t list-sessions -F '#{session_path}' | grep -Fx "$C2")" ]

D1="$TEST_TMP/one/we.b"
mkdir -p "$D1"
sessionize "$D1"
assert "a dot is mapped the same way tmux would map it" t has-session -t "=we_b"

# ---------------------------------------------------------------- no fzf

echo
echo "== a machine with no fzf =="
# With no argument the script fuzzy-finds. Without fzf the pipeline produced an
# empty selection and exited 0 — identical to pressing Escape. On a fresh
# machine that is a script which appears to do nothing, successfully, and there
# is nothing to grep for.
mkdir -p "$TEST_TMP/empty-path"
out="$(PATH="$TEST_TMP/empty-path:/usr/bin:/bin" "$BIN/tmux-sessionizer" 2>&1)"
rc=$?
assert "it exits non-zero rather than looking like a cancelled pick" [ "$rc" -ne 0 ]
assert "and says fzf is what is missing" contains "$out" "fzf"

# NOT COVERED: the interactive fzf path itself — the list it builds, and picking
# from it. Driving fzf through a pty would be testing fzf; stubbing it would be
# testing the stub. What matters on this side of it is the naming, and that is
# what every assertion above exercises, by the same code path fzf feeds.

# ---------------------------------------------------------------- a real client

echo
echo "== with a client attached, it actually moves you =="
# Everything above asserts what got CREATED. None of it proves the last line
# works: switch-client silently no-ops with no client attached, so the script
# could create the right session and leave you exactly where you were, and every
# assertion so far would still pass. That needs a real terminal.
S1="$TEST_TMP/dest/widgets"
mkdir -p "$S1"
sessionize "$S1"
assert "the session to switch to exists" t has-session -t "=widgets"

# Attach a real client to 'base', then run the script from inside the server and
# ask tmux which session that client is on afterwards.
moved="$(with_pty_client base bash -c "
  tmux -L '$TMUX_SOCK' run-shell '$BIN/tmux-sessionizer \"$S1\" >/dev/null 2>&1 || true'
  sleep 1.5
  tmux -L '$TMUX_SOCK' list-clients -F '#{client_session}'")"
assert "the attached client is switched to the picked project" contains "$moved" "widgets"
refute "and is no longer on the session it started from" [ "$moved" = "base" ]

# ---------------------------------------------------------------- vanished path

echo
echo "== a project that is no longer there =="
# Reachable both ways: a path typed from memory, and an fzf pick from a listing
# built moments earlier. tmux does NOT refuse this — it accepts -c with a
# missing directory, records it as the session_path, and starts the shell
# wherever it can. So without a check you get a session named after a project
# that does not exist, apparently rooted in it, with a shell somewhere else.
GONE="$TEST_TMP/vanished"
mkdir -p "$GONE"
rmdir "$GONE"
n_before="$(n_sessions)"
t run-shell "$BIN/tmux-sessionizer '$GONE' >$TEST_TMP/gone.out 2>&1; echo rc=\$? >>$TEST_TMP/gone.out"
sleep 1.2
out="$(cat "$TEST_TMP/gone.out" 2>/dev/null)"
assert "it refuses rather than creating a session named after nothing" \
  [ "$(n_sessions)" = "$n_before" ]
assert "and exits non-zero" contains "$out" "rc=1"
assert "naming the path it could not use" contains "$out" "vanished"

finish
