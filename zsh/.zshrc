# ~/.zshrc (interactive shells)
[[ $- != *i* ]] && return

# -------------------------
# Environment / PATH
# -------------------------

# Prefer local bin first (so tools win over system defautls)
export PATH="$HOME/.local/bin:$PATH"

# Project state dir (Reliability for path variables on homelab.)
export STATE_DIR="$HOME/state/glorious_sh"

# Editor
export EDITOR="nvim"
export VISUAL="nvim"

# Locale (optional but helps avoid odd tool behaviour)
export LANG="en_GB.UTF-8"
export LC_ALL="en_GB.UTF-8"

# -------------------------
# History (sane defaults)
# -------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt hist_ignore_dups
setopt hist_ignore_space
setopt sharehistory

# -------------------------
# Aliases (keep minimal)
# -------------------------
alias ll='ls -lah'
alias vim='nvim'

# -------------------------
# Prompt (Starship) - must be last
# -------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  PROMPT='%1~ %# '
fi

# Optional per-machine overrides (not committed)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
