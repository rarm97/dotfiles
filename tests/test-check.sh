#!/usr/bin/env bash
# check.sh itself.
#
# MUTATION TESTS, not smoke tests. For each assertion: introduce the defect it
# claims to catch, and prove the assertion FAILS. Watching check.sh pass proves
# nothing — it has already passed while asserting the opposite of the truth,
# reporting a colour scheme that was present as missing, because
# `strings | grep -q` under pipefail reports failure on a match. A check that
# silently stops checking is the thing this repo exists to prevent.
#
# Everything runs against a COPY of the repo. check.sh reads the working tree it
# lives in, so mutating the real one would be both destructive and useless.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORK="$TEST_TMP/repo"

# A pristine copy, remade before every mutation so they cannot interact.
reset_repo() {
  rm -rf "$WORK"
  mkdir -p "$WORK"
  # Tracked files, at their WORKING-TREE content — not `git archive HEAD`, which
  # exports the last commit. As a pre-commit hook this suite must judge what is
  # about to be committed; testing HEAD would have quietly tested stale code
  # forever, and did: two fixes to check.sh appeared to change nothing.
  (cd "$REPO_ROOT" && git ls-files -z | tar -c --null -T - -f -) | tar -x -C "$WORK"
  # check.sh runs git commands against the tree it is in.
  (
    cd "$WORK" || exit 1
    git init -q -b main .
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m copy
    git config core.hooksPath .githooks
  )
}

run_check() { (cd "$WORK" && ./check.sh 2>&1); }

# The core of this suite: a mutation must turn a specific ✓ into a ✗.
# Passing `check.sh` output is not evidence; a mutation that does NOT break it is.
mutate() { # $1=description  $2=marker text of the assertion  $3...=command to apply the mutation
  local desc="$1" marker="$2"
  shift 2
  reset_repo
  local before after
  before="$(run_check)"
  if ! contains "$before" "$marker"; then
    no "$desc — baseline does not contain '$marker' (the assertion may have been renamed)"
    return
  fi
  (cd "$WORK" && "$@") >/dev/null 2>&1
  after="$(run_check)"
  # The assertion must now report a failure mentioning its subject.
  if contains "$after" "✗"; then
    ok "$desc"
  else
    no "$desc — check.sh still reported everything green after the defect was introduced"
  fi
}

echo "== baseline =="
reset_repo
base="$(run_check)"
assert "a pristine copy passes" contains "$base" "0 failure(s)"
refute "and reports no failures" contains "$base" "✗"

echo
echo "== each assertion must actually fire =="

mutate "a wrong wezterm colour scheme is caught" "colour scheme" \
  sed -i '' 's/color_scheme = "rose-pine-moon"/color_scheme = "Not A Real Scheme"/' wezterm/.config/wezterm/wezterm.lua

mutate "a missing usstyle is caught" "usstyle" \
  sed -i '' 's/:RGB:usstyle/:RGB/' tmux/.config/tmux/tmux.conf

mutate "an untracked lazy-lock.json is caught" "lazy-lock" \
  git rm -q --cached nvim/.config/nvim/lazy-lock.json

mutate "a lua syntax error is caught" "every lua file parses" \
  bash -c 'printf "\nthis is not lua((\n" >> nvim/.config/nvim/lua/rich/plugins/fidget.lua'

mutate "a deprecated Neovim API is caught" "deprecated" \
  bash -c 'printf "\nlocal _ = vim.lsp.get_active_clients\n" >> nvim/.config/nvim/lua/rich/plugins/fidget.lua'

mutate "a plugin file with no lazy spec is caught" "lazy spec" \
  sed -i '' 's/^return {/local _unused = {/' nvim/.config/nvim/lua/rich/plugins/fidget.lua

mutate "a tmux.conf path that does not exist is caught" "every path tmux.conf references" \
  sed -i '' 's|~/.local/bin/tmux-clear-scrollback|~/.local/bin/does-not-exist|' tmux/.config/tmux/tmux.conf

mutate "a .PHONY target with no recipe is caught" "has a recipe" \
  bash -c 'python3 - <<PY
s=open("Makefile").read()
s=s.replace("test:\n\t@./tests/run.sh\n","",1)
open("Makefile","w").write(s)
PY'

mutate "(#q...) without extendedglob is caught" "extendedglob" \
  sed -i '' 's/setopt localoptions extendedglob/setopt localoptions/' zsh/.zshrc

mutate "a broken .zshrc is caught" ".zshrc parses" \
  bash -c 'printf "\nif then fi done\n" >> zsh/.zshrc'

# The injected line is assembled from a format string rather than written
# literally: spelled out, it is itself the hazard, and check.sh would flag this
# file for containing its own test data.
mutate "a pipeline into a quiet grep under pipefail is caught" "quiet grep" \
  bash -c 'printf "\ncat /etc/hosts |%s localhost\n" "grep -q" >> tidy.sh'

mutate "tests/lib.sh gaining set -e is caught" "does not set -e" \
  sed -i '' 's/^set -uo pipefail/set -euo pipefail/' tests/lib.sh

mutate "a missing git hook is caught" "hooks installed" \
  rm -f .githooks/pre-commit

mutate "hooks pointing nowhere is caught" "hooks installed" \
  git config core.hooksPath .nonexistent-hooks

mutate "a git identity that disagrees with the repo is caught" "user.email agrees" \
  git config --local user.email someone-else@example.com

echo
echo "== check.sh's own exit status =="
reset_repo
(cd "$WORK" && ./check.sh >/dev/null 2>&1)
assert "a clean repo exits 0" [ $? -eq 0 ]
(cd "$WORK" && git rm -q --cached nvim/.config/nvim/lazy-lock.json)
rc=0
(cd "$WORK" && ./check.sh >/dev/null 2>&1) || rc=$?
assert "a repo with a defect exits non-zero, so a hook or CI can act on it" [ "$rc" -ne 0 ]

finish
