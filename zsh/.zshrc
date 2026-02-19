# ~/.zshrc (interactive shells)
[[ $- != *i* ]] && return

# -------------------------
# Homebrew (Apple Silicon) — must be early for PATH
# -------------------------
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# -------------------------
# NVM lazy-loading
# -------------------------
nvm() {
  unset -f nvm
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
node() { nvm use --silent >/dev/null 2>&1; unset -f node; command node "$@"; }
npm()  { nvm use --silent >/dev/null 2>&1; unset -f npm;  command npm  "$@"; }
npx()  { nvm use --silent >/dev/null 2>&1; unset -f npx;  command npx  "$@"; }

# -------------------------
# Completion
# -------------------------
autoload -Uz compinit
compinit

setopt globdots

# -------------------------
# Environment
# -------------------------

# Project state dir 
export STATE_DIR="$HOME/state/glorious_sh"

# Editor
export EDITOR="nvim"
export VISUAL="nvim"

# Locale
export LANG="en_GB.UTF-8"
export LC_ALL="en_GB.UTF-8"

# Rust toolchain
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# -------------------------
# History
# -------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt hist_ignore_dups
setopt hist_ignore_space
setopt sharehistory
setopt hist_verify
setopt inc_append_history

# -------------------------
# Aliases 
# -------------------------
alias ll='ls -lah'
alias vim='nvim'

# -------------------------
# Shell options
# -------------------------
setopt autocd
setopt no_beep

# -------------------------
# Prompt (Starship) — must be last
# -------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  PROMPT='%1~ %# '
fi

# Optional per-machine overrides (not committed)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
