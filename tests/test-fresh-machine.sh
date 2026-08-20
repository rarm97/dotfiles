#!/usr/bin/env bash
# What happens on a machine that has never had these dotfiles.
#
# This is the case that cannot be observed from a working machine, and it is
# where the expensive failures live: the stow tree-folding bug is invisible here
# because ~/.local already exists, but on a clean macOS box it turns ~/.local
# into a symlink into this repo and everything nvim and tmux-resurrect write
# lands in the working tree.
#
# $HOME is pointed at a throwaway directory and bootstrap.sh's real
# stow_packages() is called against it. Nothing installs anything: brew, rustup
# and the package list are never reached.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAKE_HOME="$TEST_TMP/home"
mkdir -p "$FAKE_HOME"

# If the stow-folding bug is present, the probe write below lands INSIDE the
# repo rather than in $FAKE_HOME. That is the defect reproducing correctly, but
# the suite must not leave it behind — a test that pollutes the tree it is
# testing is its own kind of silent failure.
cleanup_fresh() {
  rm -rf "$REPO_ROOT/tmux/.local/share" "$REPO_ROOT/tmux/.local/state"
  cleanup_common
}
trap cleanup_fresh EXIT

# Source the real bootstrap.sh for its real function, rather than a copy of the
# logic here — a copy would drift and then this suite would be testing itself.
DOTFILES_DIR="$REPO_ROOT"
export DOTFILES_DIR
# shellcheck source=/dev/null
source "$REPO_ROOT/bootstrap.sh"
# bootstrap.sh opens with `set -euo pipefail`, and sourcing imports those into
# THIS shell. Under -e the first assertion that fails aborts the suite instead
# of reporting FAIL and carrying on — the harness would go quiet at the point of
# the failure and still look like it had simply finished. Turn -e back off.
set +e

echo "== a clean \$HOME, then bootstrap's own stow_packages() =="
refute "the fresh HOME has no .local yet (the precondition for the bug)" \
  [ -e "$FAKE_HOME/.local" ]

(HOME="$FAKE_HOME" stow_packages) >/dev/null 2>&1
assert "stow_packages completed" [ -d "$FAKE_HOME/.config" ]

# THE BUG: only the tmux package supplies .local/, so with no ~/.local present
# stow folds the whole tree into one symlink pointing into the repo.
# shellcheck disable=SC2088  # tildes in these descriptions are prose
refute "~/.local did NOT become a symlink into the repo" [ -L "$FAKE_HOME/.local" ]
# shellcheck disable=SC2088
assert "~/.local is a real directory" [ -d "$FAKE_HOME/.local" ]

echo
echo "== the helper scripts are individually linked, and resolve =="
for s in tmux-resurrect-guard tmux-resurrect-saves tmux-clear-scrollback \
  tmux-sessionizer tmux-kill-session; do
  assert "$s is linked and executable" [ -x "$FAKE_HOME/.local/bin/$s" ]
done

echo
echo "== config lands where the tools will look for it =="
for p in .config/nvim/init.lua .config/tmux/tmux.conf .config/wezterm/wezterm.lua \
  .config/git/config .config/starship.toml .zshrc; do
  assert "$p exists" [ -e "$FAKE_HOME/$p" ]
done
assert "lazy-lock.json came across, so plugin versions are pinned on a fresh box" \
  [ -e "$FAKE_HOME/.config/nvim/lazy-lock.json" ]

echo
echo "== nvim's data must land in \$HOME, not in the repo =="
# nvim resolves stdpath("data") to $HOME/.local/share/nvim. If .local were the
# folded symlink, writing there would write into ~/dotfiles/tmux/.local/share.
mkdir -p "$FAKE_HOME/.local/share/nvim/lazy/probe.nvim"
printf 'x\n' >"$FAKE_HOME/.local/share/nvim/lazy/probe.nvim/README"
refute "a plugin written to ~/.local/share did not appear inside the repo" \
  [ -e "$REPO_ROOT/tmux/.local/share/nvim/lazy/probe.nvim/README" ]
assert "...it is in \$HOME where it belongs" \
  [ -f "$FAKE_HOME/.local/share/nvim/lazy/probe.nvim/README" ]

echo
echo "== unstow must not strand that data =="
(cd "$REPO_ROOT" && HOME="$FAKE_HOME" stow -D -t "$FAKE_HOME" \
  nvim wezterm tmux zsh home starship git) >/dev/null 2>&1
assert "after unstow, ~/.local/share/nvim survives" \
  [ -f "$FAKE_HOME/.local/share/nvim/lazy/probe.nvim/README" ]
assert "...and ~/.local/bin is still a real directory" [ -d "$FAKE_HOME/.local/bin" ]
refute "...with the dangling script links removed" \
  [ -e "$FAKE_HOME/.local/bin/tmux-resurrect-guard" ]

echo
echo "== stowing twice is idempotent =="
(HOME="$FAKE_HOME" stow_packages) >/dev/null 2>&1
(HOME="$FAKE_HOME" stow_packages) >/dev/null 2>&1
assert "a second run leaves ~/.local a real directory" [ -d "$FAKE_HOME/.local" ]
refute "a second run does not fold it either" [ -L "$FAKE_HOME/.local" ]
pending="$(cd "$REPO_ROOT" && stow -n -t "$FAKE_HOME" \
  nvim wezterm tmux zsh home starship git 2>&1 | grep -cE '^(LINK|MKDIR)')"
assert "a third dry-run has nothing left to do" [ "${pending:-1}" -eq 0 ]

echo
echo "== the repo working tree is unchanged by all of that =="
dirty="$(cd "$REPO_ROOT" && git status --porcelain | grep -c 'tmux/.local/share' || true)"
assert "nothing was written into tmux/.local/" [ "${dirty:-0}" -eq 0 ]

finish
