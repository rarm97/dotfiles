SHELL := /bin/bash

.PHONY: help bootstrap stow unstow check check-repo doctor lint tidy tidy-apply test test-fast hooks

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
	@echo "  make lint       - shellcheck and shfmt every shell script here"
	@echo "  make hooks      - install the git hooks (check on commit, test-fast on push)"
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

# The linters run over every tracked file that STARTS WITH a shell shebang,
# derived rather than listed. CI used to lint a hand-written list of paths, and
# tmux/.local/bin was not on it — so all five scripts that get stowed onto
# PATH, the resurrect guard and the save manager among them, were linted by
# nothing at all and nothing said so. A list someone has to remember to extend is the same defect
# as a comment someone has to remember to update.
#
# Deliberately not part of `check`: shellcheck and shfmt are developer tools and
# check.sh has to run on a machine without them. CI runs this as its own step.
lint:
	@set -euo pipefail; \
	files="$$(git ls-files -z | xargs -0 awk 'FNR == 1 && /^#!.*(ba)?sh$$/ { print FILENAME }')"; \
	[[ -n "$$files" ]] || { echo "lint: found no shell scripts at all — the scan has broken"; exit 1; }; \
	echo "==> shellcheck ($$(printf '%s\n' "$$files" | wc -l | tr -d ' ') files)"; \
	shellcheck -x -P tests $$files; \
	echo "==> shfmt"; \
	shfmt -i 2 -ci -d $$files; \
	echo "==> clean"

# Local to this repo, not global: core.hooksPath in the stowed git config would
# apply to every repo on the machine, none of which have a check.sh.
hooks:
	@git config core.hooksPath .githooks
	@echo "hooks installed: check on commit, test-fast on push (bypass with --no-verify)"

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
