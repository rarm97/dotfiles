SHELL := /bin/bash

.PHONY: help bootstrap stow unstow check doctor

help:
	@echo "Targets:"
	@echo "  make bootstrap  - install brew deps + stow dotfiles + run checks"
	@echo "  make stow       - stow packages (dry-run then apply)"
	@echo "  make unstow     - unstow packages (reversible)"
	@echo "  make check      - verify key tools + paths"
	@echo "  make doctor     - print useful debug info (PATH, tool locations)"

bootstrap:
	@./bootstrap.sh

stow:
	@set -euo pipefail; \
	cd "$$(pwd)"; \
	PKGS="nvim wezterm tmux zsh home"; \
	if [[ -d "./gitconfig" ]]; then PKGS="$$PKGS gitconfig"; \
	elif [[ -d "./git" ]]; then PKGS="$$PKGS git"; fi; \
	echo "==> Dry run"; \
	stow -n -t "$$HOME" $$PKGS; \
	echo "==> Apply"; \
	stow -t "$$HOME" $$PKGS

unstow:
	@set -euo pipefail; \
	cd "$$(pwd)"; \
	PKGS="nvim wezterm tmux zsh home"; \
	if [[ -d "./gitconfig" ]]; then PKGS="$$PKGS gitconfig"; \
	elif [[ -d "./git" ]]; then PKGS="$$PKGS git"; fi; \
	echo "==> Unstow"; \
	stow -D -t "$$HOME" $$PKGS

check:
	@set -euo pipefail; \
	echo "==> Tools"; \
	command -v brew >/dev/null && brew --version | head -n 1 || echo "brew: MISSING"; \
	command -v git  >/dev/null && git --version || echo "git: MISSING"; \
	command -v nvim >/dev/null && nvim --version | head -n 2 || echo "nvim: MISSING"; \
	command -v tmux >/dev/null && tmux -V || echo "tmux: MISSING"; \
	command -v rg   >/dev/null && rg --version | head -n 1 || echo "rg: MISSING"; \
	command -v fd   >/dev/null && fd --version || echo "fd: MISSING"; \
	command -v node >/dev/null && node -v || echo "node: MISSING"; \
	command -v npm  >/dev/null && npm -v || echo "npm: MISSING"; \
	echo; \
	echo "==> Config paths"; \
	ls -la "$$HOME/.config/nvim" 2>/dev/null || echo "~/.config/nvim: MISSING"; \
	ls -la "$$HOME/.config/wezterm" 2>/dev/null || echo "~/.config/wezterm: MISSING"; \
	ls -la "$$HOME/.config/tmux" 2>/dev/null || echo "~/.config/tmux: MISSING"; \
	ls -la "$$HOME/.config/git" 2>/dev/null || echo "~/.config/git: MISSING"

doctor:
	@set -euo pipefail; \
	echo "==> Where am I?"; \
	pwd; \
	echo; \
	echo "==> PATH"; \
	echo "$$PATH" | tr ':' '\n' | sed -n '1,30p'; \
	echo; \
	echo "==> Locations"; \
	command -v brew || true; \
	command -v stow || true; \
	command -v nvim || true; \
	command -v tmux || true; \
	command -v node || true; \
	echo; \
	echo "==> Symlinks"; \
	ls -la "$$HOME/.config" | sed -n '1,80p'
