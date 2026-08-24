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

# Every absolute path any config here hardcodes must actually be there.
#
# This was tmux.conf alone, and the asymmetry was the whole defect: wezterm.lua
# hardcodes /opt/homebrew/bin/tmux — the Apple Silicon Homebrew prefix — and
# nothing checked it, while .zshrc and bootstrap.sh both try /opt/homebrew and
# then /usr/local, so the repo already knew the other prefix existed.
#
# WHAT A MISSING default_prog ACTUALLY DOES, established rather than assumed,
# because it decides whether this is worth anything. WezTerm opens its window
# and prints into it:
#
#   Unable to spawn /opt/homebrew/bin/tmux because it doesn't exist on the
#   filesystem (ENOENT: No such file or directory)
#
# and holds the window open, because exit_behavior defaults to CloseOnCleanExit
# and that was not a clean exit. Verified against wezterm 20250713 by starting a
# throwaway config with a bad path and reading the pane back.
#
# So it is loud, and it names the path. That is why wezterm.lua still hardcodes
# one path rather than growing a resolver: a resolver needs a fallback for "no
# prefix has tmux", and every candidate fallback — bare `tmux` under the launchd
# PATH a Finder-launched WezTerm inherits, or a plain shell — trades a precise
# error for a vaguer one or for none at all. What was missing was the assertion.
# On a machine with the other prefix this now says so, at `make check` time,
# which the pre-commit hook runs.
#
# THREE RULES keep the scan honest:
#
#   Comments are stripped. A full-line comment mentioning a path is prose —
#   including them reported four paths that no config ever opens.
#
#   PATH assignments are skipped. A directory that is not on this machine is
#   ignored by the shell, so a dead PATH entry is not a defect; a dead program
#   path is.
#
#   Alternatives count. A file naming the same path under BOTH Homebrew
#   prefixes is choosing at runtime, so only one of the two has to exist.
#
# And one exclusion by name: tmux-sessionizer's SEARCH_DIRS are roots to look
# in, not requirements — the script tests each with [[ -d ]] and skips what is
# not there — so requiring them would fail on any machine that does not happen
# to have all four.
missing=0
paths_seen=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Quotes, backticks, commas and brackets become spaces so a path is a word:
  # \042 " \047 ' \140 ` — written as octal to keep this line readable.
  body="$(sed -e 's/^[[:space:]]*#.*//' -e 's/^[[:space:]]*--.*//' -e '/SEARCH_DIRS=(/,/^)/d' "$f" 2>/dev/null |
    grep -v -E 'PATH=|PATH "' | tr -s '\042\047\140,()' '     ')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    paths_seen=$((paths_seen + 1))
    expanded="${p/#\~/$HOME}"
    [ -e "$expanded" ] && continue
    alt=""
    case "$p" in
      /opt/homebrew/*) alt="/usr/local/${p#/opt/homebrew/}" ;;
      /usr/local/*) alt="/opt/homebrew/${p#/usr/local/}" ;;
    esac
    if [ -n "$alt" ] && [ -e "$alt" ] && grep -qF "$alt" "$f"; then
      continue
    fi
    bad "$f references $p, which does not exist"
    missing=$((missing + 1))
  done < <(printf '%s\n' "$body" |
    grep -oE '(/opt/homebrew|/usr/local|/Applications|/Library)[A-Za-z0-9_./+-]*|~/[A-Za-z0-9_./+-]*' |
    sort -u)
done < <(git ls-files | grep -vE '^(checks/|tests/|\.github/)|^GOAL\.md$')
if [ "$paths_seen" -eq 0 ]; then
  bad "found no hardcoded paths in any config at all — the scan has broken"
elif [ "$missing" -eq 0 ]; then
  ok "every path the configs hardcode exists ($paths_seen checked, across every tracked config)"
fi

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
