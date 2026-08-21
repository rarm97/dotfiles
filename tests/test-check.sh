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

# Declared slow: tens of seconds, because it drives a real terminal, editor or
# language server, or repeats an expensive command many times. `tests/run.sh
# --fast` skips these; the pre-push hook still runs everything, and so does CI.
# Read by run.sh with grep, not by this shell.
# shellcheck disable=SC2034
SUITE_SLOW=1

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

# Two modes, because check.sh has two halves. The repo half holds on any machine
# and is what CI exercises; the machine half needs WezTerm, fonts, a stow tree
# and a git identity, so on a runner its baseline cannot pass and a mutation
# against it would prove nothing.
run_check() { (cd "$WORK" && ./check.sh --repo-only 2>&1); }
run_check_full() { (cd "$WORK" && ./check.sh 2>&1); }

# The core of this suite: a mutation must turn a specific ✓ into a ✗.
# Passing `check.sh` output is not evidence; a mutation that does NOT break it is.
mutate() { # $1=description  $2=marker text of the assertion  $3...=command to apply the mutation
  local desc="$1" marker="$2"
  shift 2
  _mutate repo "$desc" "$marker" "$@"
}

# Same, but for an assertion that lives in checks/machine.sh.
mutate_machine() {
  local desc="$1" marker="$2"
  shift 2
  _mutate machine "$desc" "$marker" "$@"
}

_mutate() { # $1=repo|machine  $2=description  $3=marker  $4...=mutation
  local mode="$1" desc="$2" marker="$3"
  shift 3
  reset_repo
  local before after
  if [ "$mode" = machine ]; then
    before="$(run_check_full)"
  else
    before="$(run_check)"
  fi
  # The marker's absence means different things for the two halves. A machine
  # assertion is simply not present on a box without WezTerm, a stow tree or a
  # git identity — a CI runner, for instance — and skipping is honest. A REPO
  # assertion holds everywhere, so if its marker is gone it has been renamed or
  # deleted and the mutation would pass vacuously.
  if ! contains "$before" "$marker"; then
    if [ "$mode" = machine ]; then
      printf '  \033[33mSKIP\033[0m  %s (not asserted on this machine)\n' "$desc"
    else
      no "$desc — baseline does not contain '$marker' (the assertion may have been renamed)"
    fi
    return
  fi
  (cd "$WORK" && "$@") >/dev/null 2>&1
  if [ "$mode" = machine ]; then
    after="$(run_check_full)"
  else
    after="$(run_check)"
  fi
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
assert "a pristine copy passes the repository checks" contains "$base" "0 failure(s)"
refute "and reports no failures" contains "$base" "✗"
# Not asserted for the machine half: on a CI runner it cannot pass, and a
# baseline assertion that only holds on one laptop is not worth having.
if contains "$(run_check_full)" "0 failure(s)"; then
  ok "a pristine copy passes the machine checks too"
else
  printf '  \033[33mSKIP\033[0m  machine checks do not pass here — machine mutations will skip\n'
fi

echo
echo "== each assertion must actually fire =="

mutate_machine "a wrong wezterm colour scheme is caught" "colour scheme" \
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

mutate_machine "a tmux.conf path that does not exist is caught" "every path tmux.conf references" \
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

mutate_machine "a missing git hook is caught" "hooks installed" \
  rm -f .githooks/pre-commit

mutate_machine "hooks pointing nowhere is caught" "hooks installed" \
  git config core.hooksPath .nonexistent-hooks

mutate_machine "a git identity that disagrees with the repo is caught" "user.email agrees" \
  git config --local user.email someone-else@example.com

echo
echo "== check.sh's own exit status =="
reset_repo
(cd "$WORK" && ./check.sh --repo-only >/dev/null 2>&1)
assert "a clean repo exits 0" [ $? -eq 0 ]
(cd "$WORK" && git rm -q --cached nvim/.config/nvim/lazy-lock.json)
rc=0
(cd "$WORK" && ./check.sh --repo-only >/dev/null 2>&1) || rc=$?
assert "a repo with a defect exits non-zero, so a hook or CI can act on it" [ "$rc" -ne 0 ]

# ------------------------------------------------------- the checks themselves

echo
echo "== a missing half must not read as a clean pass =="
# The worst failure check.sh can have, and it was live. `.` on a file that is
# not there prints one line to stderr and carries on, so deleting checks/repo.sh
# produced "0 ok, 0 warning(s), 0 failure(s)" and exit 0 — CI green, pre-commit
# hook green, nothing being checked at all.
reset_repo
rm -f "$WORK/checks/repo.sh"
out="$(run_check)"
rc=$?
assert "it exits non-zero rather than reporting nothing wrong" [ "$rc" -ne 0 ]
# check.sh's OWN message, not bash's "No such file or directory". Both mention
# the path, so asserting on the path alone passes with the guard removed — the
# no-checks-ran guard below would still catch the missing file, but only after
# the fact and without saying what was unreadable.
assert "and says itself that it could not read the file" \
  contains "$out" "cannot read ./checks/repo.sh"
refute "it does not print a summary that looks like success" contains "$out" "0 failure(s)"

echo
echo "== ...nor must a half that exists but asserts nothing =="
# The same failure with a better disguise: a truncated file, a syntax error
# partway through, an early return. A run that checked nothing is not a pass.
reset_repo
: >"$WORK/checks/repo.sh"
out="$(run_check)"
rc=$?
assert "an empty half is a failure, not a clean run" [ "$rc" -ne 0 ]
assert "and says so plainly" contains "$out" "no checks ran"

echo
echo "== --repo-only does not depend on the machine half =="
# Deliberate: CI has no WezTerm, fonts or stow tree, so requiring machine.sh
# there would either fail the run or push someone to disable the check.
reset_repo
rm -f "$WORK/checks/machine.sh"
out="$(run_check)"
rc=$?
assert "the repo half still runs and passes" [ "$rc" -eq 0 ]
assert "and reports the checks it did run" contains "$out" "ok,"

finish
