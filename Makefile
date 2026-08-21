SHELL := /bin/bash

.PHONY: help bootstrap stow unstow check check-repo doctor tidy tidy-apply test test-fast hooks

# `stow` creates ~/.local/bin and ~/.config first on purpose: stow folds a
# directory into a single symlink when the target is missing and only one
# package supplies it, and only the tmux package supplies .local/. Without the
# mkdir, a fresh machine ends up with ~/.local -> ~/dotfiles/tmux/.local and
# everything nvim and tmux-resurrect write lands inside the repo.

help:
	@echo "Targets:"
	@echo "  make bootstrap  - install brew deps + stow dotfiles + run checks"
	@echo "  make stow       - stow packages (dry-run then apply)"
	@echo "  make unstow     - unstow packages (reversible)"
	@echo "  make check      - assert this setup's assumptions still hold"
	@echo "  make check-repo - repository checks only (no machine assumptions; what CI runs)"
	@echo "  make doctor     - print useful debug info (PATH, tool locations)"
	@echo "  make test       - run the test suites in tests/"
	@echo "  make test-fast  - skip the suites that drive a terminal (seconds, not minutes)"
	@echo "  make hooks      - install the git hooks (check on commit, test on push)"
	@echo "  make tidy       - report cruft that has accumulated (deletes nothing)"
	@echo "  make tidy-apply - actually clean up what 'tidy' reported"

bootstrap:
	@./bootstrap.sh

stow:
	@set -euo pipefail; \
	PKGS="nvim wezterm tmux zsh home starship"; \
	if [[ -d "./gitconfig" ]]; then PKGS="$$PKGS gitconfig"; \
	elif [[ -d "./git" ]]; then PKGS="$$PKGS git"; fi; \
	mkdir -p "$$HOME/.local/bin" "$$HOME/.config"; \
	echo "==> Dry run"; \
	stow -n -t "$$HOME" $$PKGS; \
	echo "==> Apply (restow to clean dead symlinks)"; \
	stow -R -t "$$HOME" $$PKGS

unstow:
	@set -euo pipefail; \
	PKGS="nvim wezterm tmux zsh home starship"; \
	if [[ -d "./gitconfig" ]]; then PKGS="$$PKGS gitconfig"; \
	elif [[ -d "./git" ]]; then PKGS="$$PKGS git"; fi; \
	echo "==> Unstow"; \
	stow -D -t "$$HOME" $$PKGS

check:
	@./check.sh

check-repo:
	@./check.sh --repo-only

test:
	@./tests/run.sh

test-fast:
	@./tests/run.sh --fast

# Local to this repo, not global: core.hooksPath in the stowed git config would
# apply to every repo on the machine, none of which have a check.sh.
hooks:
	@git config core.hooksPath .githooks
	@echo "hooks installed: check on commit, test on push (bypass with --no-verify)"

# Both delegate to tidy.sh. This used to be two recipes of backslash-continued
# shell; they drifted, so the report and the delete ended up selecting different
# files, and every step reported success whether or not it had done anything.
tidy:
	@./tidy.sh

tidy-apply:
	@./tidy.sh --apply

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
