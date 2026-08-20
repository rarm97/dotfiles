#!/usr/bin/env bash
# End-to-end: a real tmux server, resurrect's real save.sh, the real guard.
#
# Runs on a private socket with a private resurrect directory. It must never
# touch the live server or ~/.local/share/tmux/resurrect — an earlier review
# agent did exactly that and broke session restore, which is why
# require_private_socket exists.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GUARD="$BIN/tmux-resurrect-guard"
SAVE="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
TOOL="$BIN/tmux-resurrect-saves"
RDIR="$TEST_TMP/resurrect"
MARKER="${TMPDIR:-/tmp}/tmux-resurrect-guard-$(id -u).pending"

if [ ! -x "$SAVE" ]; then
  skip_suite "tmux-resurrect is not installed at $SAVE"
fi

# Consumed by t() and tmux_test_teardown() in lib.sh.
# shellcheck disable=SC2034
TMUX_SOCK="$(tmux_test_socket integration)"
require_private_socket
cleanup_all() {
  rm -f "$MARKER"
  cleanup_tmux_suite
}
trap cleanup_all EXIT

mkdir -p "$RDIR"
rm -f "$MARKER"
t kill-server 2>/dev/null
sleep 0.3

# -f /dev/null so the user's tmux.conf, tpm and continuum play no part.
t -f /dev/null new-session -d -s alpha || skip_suite "could not start a test tmux server"
t set -g @resurrect-dir "$RDIR"
t set -g @resurrect-hook-post-save-layout "$GUARD"
t set -g @resurrect-hook-post-save-all "$GUARD --post-save-all"
t set -g @resurrect-capture-pane-contents on
t set -g @resurrect-guard-min-windows 2
t set -g @resurrect-guard-collapse-pct 50

run_save() {
  t run-shell "$SAVE quiet"
  sleep 2.5
}
last_target() { readlink "$RDIR/last" 2>/dev/null; }
count_saves() { find "$RDIR" -name 'tmux_resurrect_*.txt' | wc -l | tr -d ' '; }

echo "== a healthy state saves normally =="
t new-window -t alpha
t new-window -t alpha
t new-window -t alpha
t new-session -d -s beta
t new-window -t beta
# A recognisable string in the scrollback, so we can tell whose pane contents
# ended up in the single shared archive.
t send-keys -t alpha:1 "echo HEALTHY_SCROLLBACK_MARKER" Enter
sleep 1
run_save
good="$(last_target)"
assert "a save was written and 'last' points at it" [ -n "$good" ]
if [ -z "$good" ]; then
  finish
  exit
fi
assert "it captured the whole workspace" [ "$(windows_in "$RDIR/$good")" -ge 5 ]
n_good="$(count_saves)"

echo
echo "== collapsing to a bare single-window session =="
t kill-session -t beta
for w in $(t list-windows -t alpha -F '#{window_index}' | tail -n +2); do
  t kill-window -t "alpha:$w"
done
sleep 0.5
run_save
assert "'last' still points at the healthy save — the clobber was prevented" \
  [ "$(last_target)" = "$good" ]
assert "the vetoed candidate was removed, not left behind" [ "$(count_saves)" = "$n_good" ]
assert "the guard logged the veto" grep -q VETO "$RDIR/guard.log"

# save_all rewrites the single shared pane_contents.tar.gz AFTER the layout
# decision, so a veto must also put back the scrollback it protected.
# grep -c, not -q: -q exits on first match and the SIGPIPE would fail the
# pipeline under `set -o pipefail`, faking a failure.
hits="$(tar -xzOf "$RDIR/pane_contents.tar.gz" 2>/dev/null | grep -c HEALTHY_SCROLLBACK_MARKER)"
assert "pane contents still belong to the protected save" [ "${hits:-0}" -gt 0 ]
refute "the pane-contents stash was consumed, not left lying around" \
  [ -f "$RDIR/.guard-pane-contents.tar.gz" ]

echo
echo "== the forced save bypasses the guard and clears its flag =="
t set -g @resurrect-guard-force on
run_save
assert "the forced save was accepted" [ "$(last_target)" != "$good" ]
assert "the force flag cleared itself" [ -z "$(t show-option -gqv @resurrect-guard-force)" ]
degenerate_last="$(last_target)"

echo
echo "== recovery =="
RESURRECT_DIR="$RDIR" quietly "$TOOL" promote "$good"
assert "promote restored 'last' to the healthy save" [ "$(last_target)" = "$good" ]
refute "promote refuses the degenerate save without --force" \
  quietly env RESURRECT_DIR="$RDIR" "$TOOL" promote "$degenerate_last"

echo
echo "== the guard heals a directory that is already damaged =="
RESURRECT_DIR="$RDIR" quietly env RESURRECT_DIR="$RDIR" "$TOOL" promote --force "$degenerate_last"
t new-window -t alpha
t new-window -t alpha
t new-window -t alpha
run_save
lt="$(last_target)"
assert "a healthy save replaced a degenerate 'last'" \
  [ "$(windows_in "$RDIR/${lt:-nonexistent}")" -ge 4 ]

echo
echo "== the bindings in tmux.conf do not lie about what happened =="
# Load the REAL binding lines rather than retyping them: `tmux bind-key X a \; b`
# from a shell binds only `a` and runs `b` immediately, whereas the same text in
# a config file binds the whole sequence. Sourcing the actual lines is also the
# only way this test can catch a regression in the config itself.
grep -E "^bind (s|M-s) " "$REPO_ROOT/tmux/.config/tmux/tmux.conf" >"$TEST_TMP/binds.conf"
t source-file "$TEST_TMP/binds.conf"
for key in s M-s; do
  line="$(t list-keys -T prefix | grep -E "prefix +$key ")"
  assert "binding $key is actually loaded (guards against a vacuous test)" [ -n "$line" ]
  refute "binding $key leaves the message to the guard" contains "$line" display-message
  assert "binding $key invokes save.sh quiet, so nothing repaints over the verdict" \
    contains "$line" "save.sh quiet"
done

finish
