SHELL := /bin/bash

.PHONY: help bootstrap stow unstow check doctor tidy tidy-apply test hooks

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
	@echo "  make doctor     - print useful debug info (PATH, tool locations)"
	@echo "  make test       - run the test suites in tests/"
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

test:
	@./tests/run.sh

# Local to this repo, not global: core.hooksPath in the stowed git config would
# apply to every repo on the machine, none of which have a check.sh.
hooks:
	@git config core.hooksPath .githooks
	@echo "hooks installed: check on commit, test on push (bypass with --no-verify)"

# The things that quietly pile up here. `tidy` only ever reports; every deletion
# lives in `tidy-apply`, so running the wrong one by accident costs nothing.
# Both are safe to run at any time, including inside tmux.

# Kept in one variable because `tidy` and `tidy-apply` MUST look at the same set
# of files — a report that does not match the action defeats the whole two-step
# design. The obvious `-path ./.git -prune -o ... -print -delete` form does not:
# `-delete` implies `-depth`, and `-depth` silently turns `-prune` into a no-op,
# so the report skips .git and the delete walks into it. `-not -path` has no such
# interaction and means the same thing at maxdepth 2.
SCRATCH_FIND := find . -maxdepth 2 -name '99-*' -mtime +7 -not -path './.git/*'
NVIM_LSP_LOG := $$HOME/.local/state/nvim/lsp.log

tidy:
	@set -uo pipefail; \
	echo "==> tmux-resurrect saves"; \
	if command -v tmux-resurrect-saves >/dev/null; then \
		tmux-resurrect-saves prune | tail -3 | sed 's/^/    /'; \
	else echo "    tmux-resurrect-saves not on PATH (run make stow)"; fi; \
	echo; \
	echo "==> nvim 99-plugin scratch files (tmp_dir is relative to cwd)"; \
	found=$$($(SCRATCH_FIND) -print 2>/dev/null); \
	if [[ -n "$$found" ]]; then echo "$$found" | sed 's/^/    stale: /'; \
	else echo "    none older than 7 days"; fi; \
	echo; \
	echo "==> nvim LSP log"; \
	if [[ -f "$(NVIM_LSP_LOG)" ]]; then du -h "$(NVIM_LSP_LOG)" | sed 's/^/    /'; \
	else echo "    none"; fi; \
	echo; \
	echo "==> git branches already merged into main"; \
	merged=$$(git branch --merged main 2>/dev/null | grep -vE '^\*|^\s*main$$' || true); \
	if [[ -n "$$merged" ]]; then echo "$$merged" | sed 's/^/    /'; \
	else echo "    none"; fi; \
	echo; \
	echo "==> uncommitted work"; \
	if [[ -n "$$(git status --porcelain)" ]]; then git status --short | sed 's/^/    /'; \
	else echo "    working tree clean"; fi; \
	echo; \
	echo "Nothing was deleted. Run 'make tidy-apply' to act on the above."

tidy-apply:
	@set -uo pipefail; \
	echo "==> Pruning tmux-resurrect saves"; \
	command -v tmux-resurrect-saves >/dev/null && tmux-resurrect-saves prune --apply | tail -2 | sed 's/^/    /'; \
	echo "==> Removing 99-plugin scratch files older than 7 days"; \
	$(SCRATCH_FIND) -print -delete 2>/dev/null | sed 's/^/    removed /' || true; \
	echo "==> Truncating the nvim LSP log"; \
	if [[ -f "$(NVIM_LSP_LOG)" ]]; then du -h "$(NVIM_LSP_LOG)" | sed 's/^/    was /'; \
		: >"$(NVIM_LSP_LOG)"; echo "    truncated"; \
	else echo "    none"; fi; \
	echo "==> Deleting branches already merged into main"; \
	for b in $$(git branch --merged main 2>/dev/null | grep -vE '^\*|^\s*main$$' || true); do \
		git branch -d "$$b" | sed 's/^/    /'; \
	done; \
	echo "Uncommitted work is left alone on purpose - review and commit it yourself."

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
