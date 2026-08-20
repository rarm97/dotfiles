#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMEBREW_NO_ANALYTICS=1

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARN: %s\n" "$*" >&2; }
die() {
  printf "\nERROR: %s\n" "$*" >&2
  exit 1
}

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
  local brew_path=""
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_path="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_path="/usr/local/bin/brew"
  else
    die "brew installed but not found in expected locations"
  fi

  eval "$("$brew_path" shellenv)" || die "Failed to initialize Homebrew environment"
  log "Persisting brew shellenv into $HOME/.zprofile (safe, idempotent)"
  local line="eval \"\$(${brew_path} shellenv)\""
  grep -Fqx "$line" "$HOME/.zprofile" 2>/dev/null || echo "$line" >>"$HOME/.zprofile"
}

brew_install_pkgs() {
  local pkgs=(
    git
    git-lfs
    stow
    neovim
    tmux
    ripgrep
    fd
    node
    go
    docker
    starship
    fzf
    zsh-autosuggestions
    zsh-syntax-highlighting
    prettier
    stylua
    black
    shfmt
    shellcheck
    clang-format
  )

  log "Updating Homebrew"
  brew update

  log "Installing packages: ${pkgs[*]}"
  brew install "${pkgs[@]}"

  # WezTerm is a cask (GUI)
  log "Installing WezTerm (cask)"
  brew install --cask wezterm || warn "WezTerm cask install failed (rerun later)"

  # wezterm.lua asks for "JetBrainsMono Nerd Font" and starship/lualine are full
  # of glyphs. Without the font both fall back to Menlo and every icon renders
  # as tofu — which looks like a config bug rather than a missing font.
  log "Installing JetBrainsMono Nerd Font (cask)"
  brew install --cask font-jetbrains-mono-nerd-font || warn "Nerd Font install failed (rerun later)"
}

install_rust() {
  # Rust is rustup-managed (lsp.lua uses the rustup-provided rust-analyzer),
  # so install via rustup rather than brew. Guarded: no-op if already present.
  if command -v rustup >/dev/null 2>&1 || command -v cargo >/dev/null 2>&1; then
    log "Rust toolchain already present"
  else
    log "Installing Rust via rustup"
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  fi

  # lsp.lua expects `rust-analyzer` on PATH (the rustup-managed proxy)
  if command -v rustup >/dev/null 2>&1; then
    log "Ensuring rust-analyzer component"
    rustup component add rust-analyzer >/dev/null 2>&1 ||
      warn "Could not add rust-analyzer (add later: rustup component add rust-analyzer)"
  fi
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

  # Create the target directories BEFORE stowing. Stow folds a directory into a
  # single symlink when the target does not exist and exactly one package
  # supplies it. Only the tmux package supplies .local/, so on a fresh machine
  # ~/.local would become a symlink to ~/dotfiles/tmux/.local — and then nvim
  # would write its plugins, treesitter parsers and Mason binaries, and
  # tmux-resurrect its session saves, inside this git repo. `make unstow` would
  # then remove that symlink and strand the lot.
  #
  # (.config is supplied by five packages so stow already unfolds it, but make
  # it explicit rather than depend on that staying true.)
  #
  # Note: --no-folding would also prevent this, but it is the wrong cure — it
  # expands ~/.config/nvim into one symlink per file, so a newly added lua file
  # would not appear until the next restow.
  mkdir -p "$HOME/.local/bin" "$HOME/.config"

  # Dry run first
  log "Stow dry-run (no changes)"
  stow -n -t "$HOME" "${packages[@]}"

  log "Stow apply (restow to clean dead symlinks)"
  stow -R -t "$HOME" "${packages[@]}"
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
  [[ -e "$HOME/.config/nvim" ]] || die "$HOME/.config/nvim missing (stow failed?)"
  [[ -e "$HOME/.config/wezterm" ]] || warn "$HOME/.config/wezterm missing (if you skipped wezterm package, ignore)"
  [[ -e "$HOME/.config/tmux" ]] || warn "$HOME/.config/tmux missing (if you don't use tmux config, ignore)"

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
  install_rust
  stow_packages
  post_checks
}

main "$@"
