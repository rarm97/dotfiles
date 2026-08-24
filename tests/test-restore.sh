#!/usr/bin/env bash
# The round trip: save a workspace, destroy it, restore it, and check it came
# back.
#
# This is the promise everything else in this repo protects, and until now
# nothing had ever checked it. The guard stops a throwaway state becoming
# `last`, prune refuses to delete what `last` points at, promote puts `last`
# back after damage — all verified. That restoring `last` actually reproduces
# your workspace was assumed.
#
# Private socket, private resurrect dir. Nothing here may touch the live server
# or ~/.local/share/tmux/resurrect.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: tens of seconds, because it drives a real terminal, editor or
# language server, or repeats an expensive command many times. `tests/run.sh
# --fast` skips these, and so does the pre-push hook; CI runs the complete set,
# so what the hook skips is caught on the way in rather than on the way out.
# Read by run.sh with grep, not by this shell.
# shellcheck disable=SC2034
SUITE_SLOW=1

SAVE="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
RESTORE="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/restore.sh"
GUARD="$BIN/tmux-resurrect-guard"
TOOL="$BIN/tmux-resurrect-saves"
RDIR="$TEST_TMP/resurrect"
MARKER_FILE="${TMPDIR:-/tmp}/tmux-resurrect-guard-$(id -u).pending"

[ -x "$SAVE" ] && [ -x "$RESTORE" ] ||
  skip_suite "tmux-resurrect is not installed at $(dirname "$SAVE")"

# shellcheck disable=SC2034  # used by t() and tmux_test_teardown() in lib.sh
TMUX_SOCK="$(tmux_test_socket restore)"
require_private_socket
cleanup_restore() {
  rm -f "$MARKER_FILE"
  cleanup_tmux_suite
}
trap cleanup_restore EXIT

mkdir -p "$RDIR" "$TEST_TMP/alpha" "$TEST_TMP/beta" "$TEST_TMP/gamma"
rm -f "$MARKER_FILE"

# Every server in this suite needs the same resurrect settings, and they have to
# be set before save.sh or restore.sh runs.
configure() {
  t set -g @resurrect-dir "$RDIR"
  t set -g @resurrect-capture-pane-contents on
  t set -g @resurrect-hook-post-save-layout "$GUARD"
  t set -g @resurrect-hook-post-save-all "$GUARD --post-save-all"
  t set -g @resurrect-guard-min-windows 2
  t set -g @resurrect-guard-collapse-pct 50
}

# The three sections at the end are about what RESTORE does, not about the
# guard, and they build deliberately small workspaces. Left on, the guard sees
# each of those as a collapse against the larger `last` the earlier sections
# left behind, vetoes the save, and restore then faithfully returns the OLD
# workspace — so the assertions fail while both tools are working exactly as
# designed. Diagnosed the slow way: the same section passed in isolation and
# failed in the suite.
plain_server() { # a fresh server with the guard out of the picture
  fresh_server || return 1
  t set -g @resurrect-guard off
  t set -gu @resurrect-hook-post-save-layout
}

fresh_server() { # discard everything and come up bare, as a reboot would
  t kill-server 2>/dev/null
  sleep 0.5
  t -f /dev/null new-session -d -s placeholder || return 1
  configure
}

do_save() {
  t run-shell "$SAVE quiet"
  sleep 3
}
do_restore() {
  t run-shell "$RESTORE"
  sleep 6
}

# resurrect restores active windows with `switch-client`, which does nothing
# without an attached client. Restoring headlessly therefore drops that part of
# the workspace silently — the layout comes back, the window you were looking at
# does not.
do_restore_attached() {
  with_pty_client placeholder do_restore
}

# Sorted so the comparison does not depend on tmux's ordering.
layout() { t list-windows -a -F '#{session_name}:#{window_index}:#{window_name}' 2>/dev/null | sort; }
cwd_of() { t display-message -p -t "$1" '#{pane_current_path}' 2>/dev/null; }
active_window() { t list-windows -t "$1" -F '#{window_index}#{?window_active,*,}' 2>/dev/null | grep '\*' | tr -d '*'; }

# ---------------------------------------------------------------- round trip

echo "== build a known workspace, save it, destroy it, restore it =="
t kill-server 2>/dev/null
sleep 0.3
t -f /dev/null new-session -d -s alpha -c "$TEST_TMP/alpha" || skip_suite "could not start a test tmux server"
configure
t rename-window -t alpha:0 editor
t new-window -t alpha -n logs -c "$TEST_TMP/beta"
t new-session -d -s beta -c "$TEST_TMP/gamma"
t rename-window -t beta:0 shell
t new-window -t beta -n build -c "$TEST_TMP/alpha"
# A recognisable string in the scrollback, to prove pane CONTENTS come back and
# not merely the layout.
t send-keys -t alpha:editor "echo ROUNDTRIP_SCROLLBACK_MARKER" Enter
sleep 1.5
t select-window -t alpha:editor
t select-window -t beta:build

before_layout="$(layout)"
before_alpha_cwd="$(cwd_of alpha:editor)"
before_beta_cwd="$(cwd_of beta:shell)"
before_alpha_active="$(active_window alpha)"
before_beta_active="$(active_window beta)"

assert "the workspace was built" [ "$(printf '%s' "$before_layout" | grep -c ':')" -eq 4 ]

do_save
assert "a save was written" [ -e "$RDIR/last" ]
good_save="$(readlink "$RDIR/last")"

fresh_server || skip_suite "could not restart the test server"
refute "the workspace is genuinely gone before restoring" t has-session -t "=alpha"

do_restore_attached || skip_suite "could not attach a pty client"

echo
echo "== everything that was there is there again =="
assert "every session and window came back, with the same names and indexes" \
  [ "$(layout | grep -v '^placeholder')" = "$before_layout" ]
assert "alpha:editor is in its original directory" [ "$(cwd_of alpha:editor)" = "$before_alpha_cwd" ]
assert "beta:shell is in its original directory" [ "$(cwd_of beta:shell)" = "$before_beta_cwd" ]
assert "the active window in alpha was preserved" [ "$(active_window alpha)" = "$before_alpha_active" ]
assert "the active window in beta was preserved" [ "$(active_window beta)" = "$before_beta_active" ]

# @resurrect-capture-pane-contents is on, so the scrollback is part of the
# promise too, not just the layout.
assert "pane contents came back, not just the layout" \
  [ "$(t capture-pane -p -t alpha:editor 2>/dev/null | grep -c ROUNDTRIP_SCROLLBACK_MARKER)" -gt 0 ]

# ---------------------------------------------------------------- after a veto

echo
echo "== restoring after a VETO gives the protected workspace, not the throwaway =="
# This is the guard's whole purpose, and it has only ever been checked one step
# short: that `last` did not move. What restore actually produces afterwards was
# never observed.
for w in $(t list-windows -t alpha -F '#{window_index}' | tail -n +2); do
  t kill-window -t "alpha:$w"
done
t kill-session -t beta 2>/dev/null
t kill-session -t placeholder 2>/dev/null
sleep 0.5
do_save # one window left: rule 1 must veto this
assert "the guard vetoed the throwaway state" [ "$(readlink "$RDIR/last")" = "$good_save" ]

fresh_server
do_restore_attached
assert "restore brings back the FULL workspace the guard protected" \
  [ "$(layout | grep -v '^placeholder')" = "$before_layout" ]
assert "...including the scrollback the guard stashed and put back" \
  [ "$(t capture-pane -p -t alpha:editor 2>/dev/null | grep -c ROUNDTRIP_SCROLLBACK_MARKER)" -gt 0 ]

# ---------------------------------------------------------------- after promote

echo
echo "== restoring after promote gives the promoted save =="
# Build a second, deliberately different workspace and let it become `last`.
t kill-server 2>/dev/null
sleep 0.5
t -f /dev/null new-session -d -s later -c "$TEST_TMP/gamma"
configure
t rename-window -t later:0 one
t new-window -t later -n two
t new-window -t later -n three
# Both original sessions vanish in this workspace, so the guard's per-session
# collapse rule holds the save — correctly. Force it: this section is about
# promote, and the guard has its own suite.
t set -g @resurrect-guard-force on
do_save
later_save="$(readlink "$RDIR/last")"
assert "the newer workspace became 'last'" [ "$later_save" != "$good_save" ]

RESURRECT_DIR="$RDIR" quietly "$TOOL" promote "$good_save"
assert "promote pointed 'last' back at the earlier save" [ "$(readlink "$RDIR/last")" = "$good_save" ]

fresh_server
do_restore_attached
assert "restore gives the PROMOTED workspace, not the newer one" \
  [ "$(layout | grep -v '^placeholder')" = "$before_layout" ]
refute "and the newer workspace is not resurrected" t has-session -t "=later"

# ---------------------------------------------------------------- splits

echo
echo "== a window that was split comes back split =="
# Everything above is one pane per window. A real window is usually not, and
# nothing had ever checked that the pane structure survives rather than
# collapsing to a single pane per window — which would look almost right.
plain_server || skip_suite "could not restart the test server"
t new-session -d -s split -c "$TEST_TMP/alpha"
t rename-window -t split:0 work
t split-window -t split:work -c "$TEST_TMP/beta"
t split-window -t split:work -h -c "$TEST_TMP/gamma"
t new-window -t split -n single -c "$TEST_TMP/alpha"
sleep 1

panes_in() { t list-panes -t "$1" -F x 2>/dev/null | wc -l | tr -d ' '; }
before_split_panes="$(panes_in split:work)"
before_single_panes="$(panes_in split:single)"
before_pane_cwds="$(t list-panes -t split:work -F '#{pane_current_path}' 2>/dev/null | sort)"
assert "the split window really has three panes to lose" [ "$before_split_panes" -eq 3 ]

do_save
plain_server || skip_suite "could not restart the test server"
do_restore_attached || skip_suite "could not attach a pty client"

assert "the split window came back with all three panes" \
  [ "$(panes_in split:work)" = "$before_split_panes" ]
assert "and the unsplit window is still a single pane" \
  [ "$(panes_in split:single)" = "$before_single_panes" ]
assert "each pane is back in its own directory, not all in the same one" \
  [ "$(t list-panes -t split:work -F '#{pane_current_path}' 2>/dev/null | sort)" = "$before_pane_cwds" ]

# ---------------------------------------------------------------- processes

echo
echo "== a pane that was running something comes back as a shell =="
# @resurrect-processes is deliberately not set, so resurrect restores the pane
# and its directory but NOT the program that was in it. That is the documented
# default and it is a reasonable one — restarting arbitrary commands on boot is
# its own hazard — but it is a real limit on what "restored" means, and it
# should be asserted rather than discovered the first time it matters.
plain_server || skip_suite "could not restart the test server"
t new-session -d -s procs -c "$TEST_TMP/alpha"
t rename-window -t procs:0 runner
t new-window -t procs -n other
t send-keys -t procs:runner "sleep 9999" Enter
sleep 2
assert "the pane really is running something other than a shell" \
  contains "$(t display-message -p -t procs:runner '#{pane_current_command}')" "sleep"

do_save
plain_server || skip_suite "could not restart the test server"
do_restore_attached || skip_suite "could not attach a pty client"

assert "the window came back" t has-session -t "=procs"
refute "but the process did not — the pane is a shell again" \
  contains "$(t display-message -p -t procs:runner '#{pane_current_command}' 2>/dev/null)" "sleep"

# ---------------------------------------------------------------- non-empty server

echo
echo "== restoring into a server that already has that session =="
# The shape most likely to happen and least likely to be noticed. @continuum-restore
# is on, so this is a routine path rather than a contrived one: tmux starts, you
# create a session, continuum restores into a server that is no longer empty.
#
# WHAT ACTUALLY HAPPENS, established by experiment before writing any of this:
# resurrect ADOPTS the windows that are already there. They keep their own
# panes and their own scrollback, and are RENAMED to the saved window names. So
# the workspace ends up wearing the saved labels over live content — it looks
# restored, and every window label is describing something else.
#
# This is resurrect's behaviour, not this repo's, and nothing here changes it.
# It is asserted so that it is written down, and so that a version of resurrect
# which starts behaving differently says so instead of quietly changing what
# your restores mean.
plain_server || skip_suite "could not restart the test server"
t new-session -d -s adopt -c "$TEST_TMP/alpha"
t rename-window -t adopt:0 saved-name
t send-keys -t adopt:saved-name "echo SAVED_WORKSPACE_MARKER" Enter
sleep 1.5
do_save

# Reboot, and this time the session exists again before the restore runs.
plain_server || skip_suite "could not restart the test server"
t new-session -d -s adopt -c "$TEST_TMP/beta"
t rename-window -t adopt:0 live-name
t send-keys -t adopt:live-name "echo LIVE_WORKSPACE_MARKER" Enter
t new-session -d -s untouched -c "$TEST_TMP/gamma"
t send-keys -t untouched:0 "echo UNTOUCHED_MARKER" Enter
sleep 1.5
do_restore_attached || skip_suite "could not attach a pty client"

# Of the three assertions below, only the first carries weight on its own. The
# two that follow it are true whenever nothing was restored at all — checked by
# stubbing out the restore, where they still passed. They describe the SHAPE of
# the adoption and only mean something next to the assertion above them, which
# does fail. Recorded so they are not mistaken for coverage they do not provide.
assert "the window now carries the SAVED name" \
  contains "$(t list-windows -t adopt -F '#{window_name}' 2>/dev/null)" "saved-name"
assert "but the pane is the LIVE one, still holding its own scrollback" \
  [ "$(t capture-pane -p -t adopt:0 2>/dev/null | grep -c LIVE_WORKSPACE_MARKER)" -gt 0 ]
refute "and the saved workspace's contents are NOT what came back" \
  [ "$(t capture-pane -p -t adopt:0 2>/dev/null | grep -c SAVED_WORKSPACE_MARKER)" -gt 0 ]

# The one genuinely reassuring part, and worth pinning: a session that has
# nothing to do with the save is left completely alone.
assert "a session the save knows nothing about survives" t has-session -t "=untouched"
assert "with its scrollback intact" \
  [ "$(t capture-pane -p -t untouched:0 2>/dev/null | grep -c UNTOUCHED_MARKER)" -gt 0 ]

finish
