#!/usr/bin/env bash
# Assertions about THIS machine: is the environment these dotfiles assume
# actually present and wired up.
#
# None of this can run in CI — there is no WezTerm, no font, no stow tree and no
# git identity there — which is exactly why it lives apart from repo.sh. A check
# that cannot pass in CI would end up disabled, and a disabled check is worse
# than no check because it looks like coverage.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
REPO="$PWD"
# shellcheck source=/dev/null
. "$REPO/checks/lib.sh"

section "Tools"
for t in git nvim tmux stow rg fd node starship wezterm; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t is missing — bootstrap.sh installs it"; fi
done
# required = true means git REFUSES to check out an LFS repo without the filter.
if [ "$(git config --get filter.lfs.required 2>/dev/null)" = "true" ]; then
  if command -v git-lfs >/dev/null 2>&1; then
    ok "git-lfs present, as filter.lfs.required demands"
  else
    bad "filter.lfs.required=true but git-lfs is missing — any LFS repo will fail to check out"
  fi
fi

section "Stow layout"
# Only the tmux package supplies .local/, so if ~/.local does not exist when
# stow runs it folds the whole directory into a symlink into this repo, and
# nvim's plugins and tmux-resurrect's saves end up inside the working tree.
# shellcheck disable=SC2088  # the tildes below are prose, not paths to expand
if [ -L "$HOME/.local" ]; then
  bad "~/.local is a SYMLINK ($(readlink "$HOME/.local")) — stow folded it; nvim data is landing in the repo"
elif [ -d "$HOME/.local" ]; then
  ok "~/.local is a real directory, not a folded symlink"
else
  meh "~/.local does not exist yet"
fi

pending="$(stow -n -t "$HOME" nvim wezterm tmux zsh home starship git 2>&1 | grep -cE '^(LINK|MKDIR)')"
if [ "${pending:-0}" -eq 0 ]; then
  ok "every package is stowed (no pending links)"
else
  bad "$pending stow action(s) pending — run 'make stow' or new files will not be live"
fi

for s in tmux-resurrect-guard tmux-resurrect-saves tmux-clear-scrollback tmux-sessionizer tmux-kill-session; do
  if [ -x "$HOME/.local/bin/$s" ]; then
    ok "$s is on PATH and executable"
  else
    bad "$HOME/.local/bin/$s missing or not executable — the binding that calls it will fail silently"
  fi
done

# Every script tmux.conf invokes by path must actually be there.
missing=0
# shellcheck disable=SC2088  # the pattern below is a regex, not a path
while read -r p; do
  # Strip the quote, backslash or comma that terminates the surrounding tmux
  # command; without this every quoted path is reported missing.
  p="${p%%[\'\"\\,]*}"
  [ -n "$p" ] || continue
  expanded="${p/#\~/$HOME}"
  [ -e "$expanded" ] || {
    bad "tmux.conf references $p, which does not exist"
    missing=$((missing + 1))
  }
done < <(grep -oE '~/[^" ]*' tmux/.config/tmux/tmux.conf | sort -u)
[ "$missing" -eq 0 ] && ok "every path tmux.conf references exists"

section "Git identity"
# ~/.gitconfig is read AFTER the stowed config, so anything it sets wins. When
# the two disagree the repo's copy is dead and nothing says so.
for k in user.email user.name; do
  repo_v="$(git config --file "$REPO/git/.config/git/config" --get "$k" 2>/dev/null)"
  live_v="$(git config --get "$k" 2>/dev/null)"
  if [ -z "$repo_v" ]; then
    meh "$k is not set in the repo's git config"
  elif [ "$repo_v" = "$live_v" ]; then
    ok "$k agrees between the repo and what git actually uses ($live_v)"
  else
    bad "$k: repo says '$repo_v' but git uses '$live_v' — the repo's value is dead"
  fi
done

section "Terminal"
scheme="$(grep -oE 'color_scheme = "[^"]+"' wezterm/.config/wezterm/wezterm.lua 2>/dev/null | sed 's/.*"\(.*\)"/\1/')"
if [ -z "$scheme" ]; then
  meh "no color_scheme set in wezterm.lua"
else
  gui="/Applications/WezTerm.app/Contents/MacOS/wezterm-gui"
  if [ ! -x "$gui" ]; then
    meh "cannot verify colour scheme '$scheme' — wezterm-gui not found"
  # grep -cF, not -qF: -q exits on the first match, strings takes SIGPIPE, and
  # `set -o pipefail` turns that into a failed pipeline — which reported this
  # very scheme as missing when it was present.
  elif [ "$(strings -a "$gui" 2>/dev/null | grep -cF "name = \"$scheme\"")" -gt 0 ]; then
    ok "wezterm colour scheme '$scheme' exists"
  else
    bad "wezterm colour scheme '$scheme' does not exist — WezTerm falls back silently"
  fi
fi

font="$(grep -oE '"[A-Za-z][^"]*Nerd Font"' wezterm/.config/wezterm/wezterm.lua 2>/dev/null | head -1 | tr -d '"')"
if [ -n "$font" ]; then
  compact="$(printf '%s' "$font" | tr -d ' ')"
  if [ -n "$(find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 1 -iname "*${compact}*" 2>/dev/null | head -1)" ]; then
    ok "font '$font' is installed"
  else
    bad "font '$font' is not installed — every glyph renders as tofu"
  fi
fi

section "Editor tooling"
# A formatter conform names but that is not installed makes format-on-save a
# silent no-op for that filetype.
for f in $(sed -n '/formatters_by_ft/,/^ *}/p' nvim/.config/nvim/lua/rich/plugins/conform.lua |
  grep -oE '\{ *"[^"]+"' | grep -oE '"[^"]+"' | tr -d '"' | sort -u); do
  if command -v "$f" >/dev/null 2>&1 || [ -x "$HOME/.local/share/nvim/mason/bin/$f" ]; then
    ok "formatter $f is available"
  else
    meh "formatter $f is not on PATH or in mason — format-on-save is a no-op for its filetypes"
  fi
done

if command -v starship >/dev/null 2>&1; then
  if starship print-config >/dev/null 2>&1; then ok "starship config parses"; else bad "starship config does not parse"; fi
fi

section "Automation"
# Checking that core.hooksPath is SET is not enough. Point it at a directory
# whose hooks are missing and git runs nothing, says nothing, and every commit
# sails through unchecked. That happened here: `git add -A` staged .githooks/, a
# later `git reset --hard` deleted it because it was in the index but not in the
# target commit, and the path stayed configured. So verify the files.
hp="$(git config --get core.hooksPath 2>/dev/null)"
if [ -z "$hp" ]; then
  bad "git hooks are not installed — run 'make hooks'; nothing runs these checks for you"
else
  hooks_ok=1
  for h in pre-commit pre-push; do
    if [ ! -x "$hp/$h" ]; then
      bad "core.hooksPath is '$hp' but $hp/$h is missing or not executable — git runs it silently as a no-op"
      hooks_ok=0
    fi
  done
  [ "$hooks_ok" -eq 1 ] && ok "git hooks installed and executable (check on commit, test-fast on push)"
fi
