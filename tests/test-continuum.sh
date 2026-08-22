#!/usr/bin/env bash
# Continuum's unattended save — the reason the guard exists.
#
# The resurrect guard was written to protect saves that happen when nobody is
# looking. Every other suite drives a save by hand. The automatic path had never
# run in a test, which meant the guard's actual job was the one thing unproven.
#
# HOW THE AUTOMATIC SAVE IS TRIGGERED, because it is stranger than it looks:
# continuum does not use a timer. Its .tmux file appends
#
#     #(.../scripts/continuum_save.sh)
#
# to `status-right`, and relies on tmux running that command each time it draws
# the status line — every `status-interval` seconds. The script then decides for
# itself whether @continuum-save-interval minutes have passed.
#
# That has a consequence nobody would guess from the config, established here by
# experiment: see the first section.
#
# Private socket, private resurrect dir. Nothing here may touch the live server.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2034  # read by run.sh with grep, not by this shell
SUITE_SLOW=1

CONT="$HOME/.config/tmux/plugins/tmux-continuum/scripts/continuum_save.sh"
SAVE="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
GUARD="$BIN/tmux-resurrect-guard"
[ -x "$CONT" ] && [ -x "$SAVE" ] ||
  skip_suite "tmux-continuum or tmux-resurrect is not installed"

# shellcheck disable=SC2034  # used by t() and tmux_test_teardown() in lib.sh
TMUX_SOCK="$(tmux_test_socket continuum)"
require_private_socket
trap cleanup_tmux_suite EXIT

RDIR="$TEST_TMP/resurrect"

# A server wired exactly as tmux.conf wires the real one, except that the
# resurrect directory and the intervals are ours. status-interval 1 so the
# interpolation is evaluated every second instead of every fifteen; the save
# interval is still a real minute, so the last-save timestamp is zeroed to make
# "enough time has passed" true immediately.
arm() { # $1... = extra `set -g` pairs are applied by the caller afterwards
  t kill-server 2>/dev/null
  sleep 0.4
  rm -rf "$RDIR"
  mkdir -p "$RDIR"
  t -f /dev/null new-session -d -s one -x 80 -y 24 || return 1
  t set -g @resurrect-dir "$RDIR"
  t set -g @resurrect-save-script-path "$SAVE"
  t set -g @resurrect-hook-post-save-layout "$GUARD"
  t set -g @resurrect-guard-min-windows 2
  t set -g @resurrect-guard-collapse-pct 50
  t set -g @resurrect-guard-notify on
  t set -g @continuum-save-interval 1
  t set -g @continuum-save-last-timestamp 0
  t set -g status-interval 1
  t set -g status-right "#($CONT)"
}

wait_for_save() { # $1 = seconds to wait for `last` to appear
  local i=0
  while [ "$i" -lt "$1" ]; do
    [ -e "$RDIR/last" ] && return 0
    i=$((i + 1))
    sleep 1
  done
  return 1
}

# ---------------------------------------------------------------- detached

echo "== a detached server never auto-saves at all =="
# THE FINDING. tmux only runs a #() in status-right when it is DRAWING the
# status line, which it only does for an attached client. A server you have
# detached from and left running does not save — not late, not partially, not
# at all — and nothing anywhere says so. The save directory simply stops
# gaining files.
#
# Waited 30s here against a 1s status-interval before concluding it; the
# attached case below fires in about two.
arm || skip_suite "could not start a test tmux server"
t new-window -t one
t new-session -d -s two
t new-window -t two
refute "with no client attached, no save appears" wait_for_save 12
assert "and continuum's own last-save timestamp never moves" \
  [ "$(t show-option -gqv @continuum-save-last-timestamp)" = "0" ]

# ---------------------------------------------------------------- attached

echo
echo "== attach a client and the same server saves within seconds =="
# Same server, same settings, one difference: something is drawing the status
# line. This is the assertion that makes the one above mean something — without
# it, "no save appeared" could just as easily be a broken test.
with_pty_client one wait_for_save 25
assert "a save appears once a client is attached" [ -e "$RDIR/last" ]
assert "and the timestamp has moved, so continuum knows it saved" \
  [ "$(t show-option -gqv @continuum-save-last-timestamp)" != "0" ]
assert "the save holds the whole workspace, not a fragment" \
  [ "$(grep -c '^window' "$RDIR/last" 2>/dev/null)" -eq 4 ]

echo
echo "== ...and the guard ran on it, exactly as on a manual save =="
# The guard is a resurrect hook, so it should fire for an automatic save with no
# special arrangement. Worth proving rather than assuming: if it only ran for
# manual saves, it would be absent for every save it was actually written for.
assert "the guard logged a decision for the automatic save" \
  contains "$(cat "$RDIR/guard.log" 2>/dev/null)" "no existing 'last' to protect"

# ---------------------------------------------------------------- the veto

echo
echo "== a degenerate automatic save is vetoed, unattended =="
# The whole point. A workspace that has collapsed to one window is saved by
# continuum without anyone asking, and `last` must survive it.
arm || skip_suite "could not restart the test server"
t new-window -t one
t new-session -d -s two
t new-window -t two
with_pty_client one wait_for_save 25 || skip_suite "the healthy automatic save never happened"
healthy="$(readlink "$RDIR/last")"
healthy_windows="$(grep -c '^window' "$RDIR/last" 2>/dev/null)"
assert "a healthy workspace was saved first" [ "$healthy_windows" -eq 4 ]

# Collapse the workspace the way a reboot or a stray kill-server would, then let
# continuum save again on its own.
t kill-session -t "=two" 2>/dev/null
t kill-window -t one:1 2>/dev/null
sleep 0.5
t set -g @continuum-save-last-timestamp 0
with_pty_client one bash -c 'sleep 6'

assert "'last' still points at the healthy save" [ "$(readlink "$RDIR/last")" = "$healthy" ]
assert "which still has every window in it" \
  [ "$(grep -c '^window' "$RDIR/last" 2>/dev/null)" -eq "$healthy_windows" ]
assert "and the guard says why, in the log" \
  contains "$(cat "$RDIR/guard.log" 2>/dev/null)" "VETO"

finish
