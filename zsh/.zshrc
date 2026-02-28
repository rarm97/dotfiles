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
export NVM_DIR="$HOME/.nvm"
nvm() {
  unset -f nvm
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
node() { nvm use --silent >/dev/null 2>&1; unset -f node; command node "$@"; }
npm()  { nvm use --silent >/dev/null 2>&1; unset -f npm;  command npm  "$@"; }
npx()  { nvm use --silent >/dev/null 2>&1; unset -f npx;  command npx  "$@"; }

# -------------------------
# Completion (cached daily for speed)
# -------------------------
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

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
# fzf shell integration (Ctrl-R history, Ctrl-T files, Alt-C cd)
# -------------------------
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
fi

# -------------------------
# Zsh plugins (installed via Homebrew)
# -------------------------
if [[ -d /opt/homebrew/share/zsh-autosuggestions ]]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Syntax highlighting must be sourced last (after all widgets are defined)
if [[ -d /opt/homebrew/share/zsh-syntax-highlighting ]]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

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
