#!/usr/bin/env bash
# bootstrap.sh, against stubs.
#
# 7 of its 12 functions had never been executed by anything. stow_packages was
# covered only because I went looking for the stow-folding bug. A fresh machine
# is where the expensive failures live, and it is discovered at the worst
# possible moment — this is the file you run once, on a new laptop, when you
# have nothing else working.
#
# NOTHING here installs anything. brew, curl, rustup and the Homebrew installer
# are stubbed on PATH; the assertions are about what the script DOES with them —
# what it calls, in what order, and how it reacts when they fail.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOOT="$REPO_ROOT/bootstrap.sh"
STUB="$TEST_TMP/stub"
LOG="$TEST_TMP/calls.log"
FAKE_HOME="$TEST_TMP/home"

mkdir -p "$STUB" "$FAKE_HOME"

# Every stub records what it was called with, so a test can assert on the
# sequence rather than on side effects that were never allowed to happen.
make_stub() { # $1 = name, $2 = exit status
  cat >"$STUB/$1" <<STUBEOF
#!/usr/bin/env bash
printf '%s %s\n' "$1" "\$*" >>"$LOG"
exit ${2:-0}
STUBEOF
  chmod +x "$STUB/$1"
}

reset_stubs() {
  : >"$LOG"
  rm -rf "$FAKE_HOME"
  mkdir -p "$FAKE_HOME"
  for c in brew curl rustup stow git; do make_stub "$c" 0; done
  # git is needed for real by install_hooks, so let it through to the real one
  # while still recording the call.
  cat >"$STUB/git" <<STUBEOF
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"$LOG"
exec /usr/bin/git "\$@"
STUBEOF
  chmod +x "$STUB/git"
}

# Source bootstrap.sh for its functions. It guards `main` behind
# BASH_SOURCE == $0, so sourcing defines everything and runs nothing — and it
# opens with `set -euo pipefail`, which sourcing would import into this shell,
# aborting the suite at the first failing assertion instead of reporting it.
load_bootstrap() {
  # shellcheck source=/dev/null
  source "$BOOT"
  set +e
}

called() { contains "$(cat "$LOG" 2>/dev/null)" "$1"; }

echo "== sourcing it runs nothing =="
reset_stubs
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" load_bootstrap
)
assert "sourcing defines the functions without executing main" [ ! -s "$LOG" ]

echo
echo "== need_cmd fails fast, and says which command =="
reset_stubs
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    need_cmd definitely-not-a-real-command
  " 2>&1
)"
rc=$?
assert "it exits non-zero" [ "$rc" -ne 0 ]
assert "and names the missing command rather than failing obscurely" \
  contains "$out" "definitely-not-a-real-command"

echo
echo "== is_macos gates the whole script =="
reset_stubs
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" OSTYPE=linux-gnu bash -c "
    source '$BOOT'
    is_macos && echo MACOS || echo NOT_MACOS
  " 2>&1
)"
assert "it reports non-macOS correctly" contains "$out" "NOT_MACOS"
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" OSTYPE=darwin24 bash -c "
    source '$BOOT'
    is_macos && echo MACOS || echo NOT_MACOS
  " 2>&1
)"
assert "and macOS correctly" contains "$out" "MACOS"

echo
echo "== Homebrew install is skipped when brew is already there =="
reset_stubs
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    install_homebrew_macos
  " 2>&1
)"
assert "it says so" contains "$out" "already installed"
refute "and does not fetch the installer" called "curl"

echo
echo "== packages: a failing cask warns rather than aborting =="
# The distinction matters on a fresh machine: a cask that fails should not
# prevent the dotfiles from being stowed, or you are left with nothing.
reset_stubs
make_stub brew 0
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    brew_install_pkgs
    echo REACHED_END
  " 2>&1
)"
assert "the formula list is installed" called "brew install"
assert "wezterm is installed as a cask" called "install --cask wezterm"
assert "the Nerd Font is installed too, or every glyph is tofu" \
  called "font-jetbrains-mono-nerd-font"

reset_stubs
# A cask that fails: brew succeeds for formulae, fails for --cask.
cat >"$STUB/brew" <<'STUBEOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$LOG_PATH"
case "$*" in *--cask*) exit 1 ;; esac
exit 0
STUBEOF
chmod +x "$STUB/brew"
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" LOG_PATH="$LOG" bash -c "
    source '$BOOT'
    brew_install_pkgs
    echo REACHED_END
  " 2>&1
)"
assert "a failing cask warns" contains "$out" "WARN"
assert "and the script carries on rather than aborting the bootstrap" \
  contains "$out" "REACHED_END"

echo
echo "== rust: a no-op when the toolchain is already present =="
reset_stubs
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    install_rust
  " 2>&1
)"
assert "it says the toolchain is already there" contains "$out" "already present"
refute "and does not download the installer" called "curl"
assert "but it still ensures the rust-analyzer component" called "rustup component add rust-analyzer"

echo
echo "== ...and warns rather than dying if that component cannot be added =="
reset_stubs
make_stub rustup 1
out="$(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    install_rust
    echo REACHED_END
  " 2>&1
)"
assert "it warns" contains "$out" "WARN"
assert "and carries on" contains "$out" "REACHED_END"

echo
echo "== hooks are installed LOCALLY, never globally =="
# core.hooksPath in the stowed git config would apply to every repo on the
# machine, none of which have a check.sh — every commit anywhere would fail.
reset_stubs
HOOKREPO="$TEST_TMP/hookrepo"
rm -rf "$HOOKREPO"
mkdir -p "$HOOKREPO"
(
  cd "$HOOKREPO" || exit 1
  /usr/bin/git init -q .
)
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" DOTFILES_DIR="$HOOKREPO" bash -c "
    source '$BOOT'
    DOTFILES_DIR='$HOOKREPO'
    install_hooks
  "
) >/dev/null 2>&1
assert "the repo's local config points at .githooks" \
  [ "$(/usr/bin/git -C "$HOOKREPO" config --local --get core.hooksPath)" = ".githooks" ]
refute "and the user's global config was not touched" \
  contains "$(/usr/bin/git config --global --get core.hooksPath 2>/dev/null)" ".githooks"

echo
echo "== post_checks fails when a required path is missing =="
reset_stubs
# Every tool present, but the config directory is not — which is what a failed
# stow looks like.
for c in git nvim tmux rg fd node npm; do make_stub "$c" 0; done
rc=0
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    post_checks
  "
) >/dev/null 2>&1 || rc=$?
assert "it exits non-zero rather than reporting a successful bootstrap" [ "$rc" -ne 0 ]

reset_stubs
for c in git nvim tmux rg fd node npm; do make_stub "$c" 0; done
mkdir -p "$FAKE_HOME/.config/nvim" "$FAKE_HOME/.config/wezterm" "$FAKE_HOME/.config/tmux"
rc=0
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    post_checks
  "
) >/dev/null 2>&1 || rc=$?
assert "and succeeds once the paths are there" [ "$rc" -eq 0 ]

echo
echo "== running it twice changes nothing the second time =="
# A bootstrap you cannot re-run is a bootstrap you are afraid of.
reset_stubs
mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/.config"
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    stow_packages
  "
) >/dev/null 2>&1
first="$(find "$FAKE_HOME" -type l | sort)"
(
  PATH="$STUB:$PATH" HOME="$FAKE_HOME" bash -c "
    source '$BOOT'
    stow_packages
  "
) >/dev/null 2>&1
second="$(find "$FAKE_HOME" -type l | sort)"
assert "a second stow produces exactly the same tree" [ "$first" = "$second" ]

finish
