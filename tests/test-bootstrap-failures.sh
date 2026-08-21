#!/usr/bin/env bash
# bootstrap.sh when the machine does not cooperate.
#
# test-fresh-machine.sh covers the clean box, where everything works. The
# branches that matter more are the ones a REAL machine hits: a $HOME that
# already has a .zshrc, a ~/.config that is somehow a file, a stow that does
# nothing. bootstrap.sh runs under `set -euo pipefail`, which makes it loud by
# construction — but only for commands that actually report failure, and that is
# an assumption about the tools, not about this script. It is checked here.
#
# Nothing installs anything: $HOME is a throwaway directory and only
# stow_packages() and post_checks() are called.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DOTFILES_DIR="$REPO_ROOT"
export DOTFILES_DIR
# shellcheck source=/dev/null
source "$REPO_ROOT/bootstrap.sh"
# Sourcing imports `set -euo pipefail`; under -e the first failing assertion
# would abort the suite instead of reporting it.
set +e

# bootstrap.sh's loudness comes from `set -e`, and the suite turned -e off for
# its own sake — so a plain subshell here would report the status of whatever
# command ran LAST, not the first one that failed. `set -e` inside the subshell
# restores production semantics; without it these assertions can pass for a
# reason bootstrap does not actually rely on.
boot() { (set -e && HOME="$1" && shift && "$@"); }

fake_home() { # $1 = name -> echoes a fresh throwaway HOME
  local h="$TEST_TMP/$1"
  rm -rf "$h"
  mkdir -p "$h/.local/bin" "$h/.config"
  printf '%s' "$h"
}

# ------------------------------------------------------- a real file in the way

echo "== an existing ~/.zshrc must stop the run, not be silently skipped =="
# stow refuses to replace a real file, prints 'All operations aborted' and — the
# part worth pinning — exits NON-ZERO, so `set -e` stops bootstrap. If a future
# stow ever downgraded that to a warning with status 0, bootstrap would carry on
# and report success having changed nothing. This assertion is the tripwire.
H="$(fake_home conflict)"
printf 'MY OWN ZSHRC\n' >"$H/.zshrc"
boot "$H" stow_packages >/dev/null 2>&1
rc=$?
assert "stow_packages exits non-zero rather than warning and carrying on" [ "$rc" -ne 0 ]
assert "the file that was already there is untouched" \
  [ "$(cat "$H/.zshrc")" = "MY OWN ZSHRC" ]
refute "and it is still a real file, not quietly adopted into the repo" [ -L "$H/.zshrc" ]

echo
echo "== ...and the conflict aborts the OTHER packages too =="
# Worth stating because it is surprising: stow aborts the whole run, not just
# the package that conflicted. Half-stowed would be worse, but it does mean one
# stale file in $HOME blocks everything, and the failure names only that file.
refute "nvim was not stowed either" [ -e "$H/.config/nvim" ]
refute "nor tmux" [ -e "$H/.config/tmux" ]

# ------------------------------------------------------- ~/.config is a file

echo
echo "== ~/.config existing as a regular file =="
# mkdir -p cannot create through it. Under -e that is fatal, which is right: the
# alternative is stow scattering links into $HOME itself.
H="$TEST_TMP/cfgfile"
rm -rf "$H"
mkdir -p "$H"
printf 'not a directory\n' >"$H/.config"
boot "$H" stow_packages >/dev/null 2>&1
rc=$?
assert "stow_packages fails rather than working around it" [ "$rc" -ne 0 ]
assert "the file is left alone for the user to deal with" \
  [ "$(cat "$H/.config")" = "not a directory" ]
refute "and nothing was stowed into \$HOME as a consolation" [ -e "$H/.zshrc" ]

# ------------------------------------------------------- post_checks

echo
echo "== post_checks =="
# post_checks runs need_cmd over the whole toolchain BEFORE it looks at any
# config path, so on a machine missing one of those every case below dies for
# the wrong reason — and the "must exit non-zero" assertion would pass because
# of it. Establish the precondition once, out loud, rather than let either
# assertion be quietly meaningless.
missing=""
for c in git nvim tmux rg fd node npm; do
  command -v "$c" >/dev/null 2>&1 || missing="${missing:+$missing }$c"
done

if [ -n "$missing" ]; then
  printf '  \033[33mSKIP\033[0m  needs the full toolchain; missing: %s\n' "$missing"
else
  # The one check that dies rather than warns. Subshells throughout: die() exits,
  # and that exit would otherwise take the suite with it.
  H="$(fake_home nonvim)"
  out="$( (HOME="$H" post_checks) 2>&1)"
  rc=$?
  assert "it exits non-zero when ~/.config/nvim is not there" [ "$rc" -ne 0 ]
  assert "and says so, with the likely cause named" contains "$out" "stow failed?"

  # Deliberately asymmetric: wezterm and tmux configs are optional, nvim is not.
  H="$(fake_home partial)"
  ln -s "$REPO_ROOT/nvim/.config/nvim" "$H/.config/nvim"
  out="$( (HOME="$H" post_checks) 2>&1)"
  rc=$?
  assert "with nvim present it passes" [ "$rc" -eq 0 ]
  assert "having warned about wezterm rather than dying" contains "$out" "wezterm"
  assert "and about tmux" contains "$out" "tmux"
fi

# ------------------------------------------------------- the platform gate

echo
echo "== the macOS gate =="
# bootstrap installs Homebrew and brew packages; on anything else it must refuse
# at the top rather than fail somewhere in the middle with a confusing error.
# is_macos is the REAL one, sourced above — not a copy that could drift from it.
gate() { (OSTYPE="$1" && is_macos); }
assert "darwin passes the gate" gate darwin24
refute "linux does not" gate linux-gnu
refute "and neither does an unset OSTYPE" gate ""

finish
