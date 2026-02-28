#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMEBREW_NO_ANALYTICS=1

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARN: %s\n" "$*" >&2; }
die()  { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

is_macos() { [[ "${OSTYPE:-}" == darwin* ]]; }

install_homebrew_macos() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed"
    return
  fi

  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Ensure brew is on PATH for this script run (Apple Silicon default)
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    die "brew installed but not found in expected locations"
  fi

  log "Persisting brew shellenv into ~/.zprofile (safe, idempotent)"
  local line='eval "$(/opt/homebrew/bin/brew shellenv)"'
  grep -Fqx "$line" "$HOME/.zprofile" 2>/dev/null || echo "$line" >> "$HOME/.zprofile"
}

brew_install_pkgs() {
  local pkgs=(
    git
    stow
    neovim
    tmux
    ripgrep
    fd
    node
    docker
    starship
    fzf
  )

  log "Updating Homebrew"
  brew update

  log "Installing packages: ${pkgs[*]}"
  brew install "${pkgs[@]}"

  # WezTerm is a cask (GUI)
  log "Installing WezTerm (cask)"
  brew install --cask wezterm || warn "WezTerm cask install failed (rerun later)"
}

stow_packages() {
  log "Stowing dotfiles packages"
  cd "$DOTFILES_DIR"

  local packages=(nvim wezterm tmux zsh home starship)
  if [[ -d "$DOTFILES_DIR/gitconfig" ]]; then
    packages+=(gitconfig)
  elif [[ -d "$DOTFILES_DIR/git" ]]; then
    packages+=(git)
  else
    warn "No git/gitconfig package directory found; skipping git config stow"
  fi

  # Dry run first
  log "Stow dry-run (no changes)"
  stow -n -t "$HOME" "${packages[@]}"

  log "Stow apply"
  stow -t "$HOME" "${packages[@]}"
}

post_checks() {
  log "Post-checks (fail fast)"

  need_cmd git
  need_cmd nvim
  need_cmd tmux
  need_cmd rg
  need_cmd fd
  need_cmd node
  need_cmd npm

  # Confirm key config paths exist (symlink or dir)
  [[ -e "$HOME/.config/nvim" ]]    || die "~/.config/nvim missing (stow failed?)"
  [[ -e "$HOME/.config/wezterm" ]] || warn "~/.config/wezterm missing (if you skipped wezterm package, ignore)"
  [[ -e "$HOME/.config/tmux" ]]    || warn "~/.config/tmux missing (if you don’t use tmux config, ignore)"

  log "Versions"
  nvim --version | head -n 2 || true
  tmux -V || true
  node -v || true
  npm -v || true

  log "OK: bootstrap complete"
}

main() {
  is_macos || die "This script currently supports macOS only."

  install_homebrew_macos
  need_cmd brew

  brew_install_pkgs
  stow_packages
  post_checks
}

main "$@"
