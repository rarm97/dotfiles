# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

# Aliases
alias ll='ls -lah'
alias vim='nvim'

# Rust toolchain
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
