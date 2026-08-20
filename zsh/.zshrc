# ~/.zshrc (interactive shells)
[[ $- != *i* ]] && return

# Keep $PATH free of duplicates. Without this, re-sourcing .zshrc or starting a
# shell inside a shell stacks another copy of every entry below, because they all
# prepend unconditionally. `path` is tied to PATH, so marking it -U covers both.
typeset -U path PATH

# -------------------------
# Homebrew — must be early for PATH
# -------------------------
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Local scripts
export PATH="$HOME/.local/bin:$PATH"

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
# Run in an anonymous function so `localoptions` scopes extendedglob to just
# this test. The (#q...) glob-qualifier syntax REQUIRES extendedglob; without
# it zsh never expands the pattern, the -n test sees a non-empty literal
# string, and the "cached" branch below is unreachable — every shell paid for a
# full compinit. Verified: with extendedglob off, a dump created one second ago
# still took the rebuild branch.
() {
  setopt localoptions extendedglob
  # mh-24 = modified less than 24 hours ago. Phrased this way round so the
  # cached path is taken only when the dump provably exists AND is fresh; a
  # missing dump falls through to a full compinit that builds it properly.
  if [[ -n ~/.zcompdump(#qN.mh-24) ]]; then
    compinit -C # fresh: trust it and skip the security check
  else
    compinit # missing or over a day old: rebuild it
  fi
}

setopt globdots

# -------------------------
# Environment
# -------------------------

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
HISTSIZE=100000
SAVEHIST=100000
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
if [[ -d "${HOMEBREW_PREFIX:-}/share/zsh-autosuggestions" ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Syntax highlighting must be sourced last (after all widgets are defined)
if [[ -d "${HOMEBREW_PREFIX:-}/share/zsh-syntax-highlighting" ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# -------------------------
# Prompt (Starship) — must be last
# -------------------------
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  PROMPT='%1~ %# '
fi

# Optional per-machine overrides (not committed).
#
# An `if` rather than `[[ ... ]] && source ...` because this is the LAST thing
# .zshrc does, and its exit status is what the first prompt sees in $?. With the
# && form and no override file present that status is 1, so starship draws its
# red error character before you have run a single command.
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
