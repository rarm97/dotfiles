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
# --fast` skips these, and so does the pre-push hook; CI runs the complete set,
# so what the hook skips is caught on the way in rather than on the way out.
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

mutate_machine "a tmux.conf path that does not exist is caught" "every path the configs hardcode" \
  sed -i '' 's|~/.local/bin/tmux-clear-scrollback|~/.local/bin/does-not-exist|' tmux/.config/tmux/tmux.conf

# The asymmetry this generalisation existed to close: tmux.conf's paths were
# asserted and wezterm's were not.
mutate_machine "a wezterm default_prog that is not on this machine is caught" "every path the configs hardcode" \
  sed -i '' 's|/opt/homebrew/bin/tmux|/opt/homebrew/bin/tmux-not-here|' wezterm/.config/wezterm/wezterm.lua

# Naming both Homebrew prefixes means "either will do", not "neither need be
# there". A rule that rescued this pair would rescue everything.
mutate_machine "a pair of Homebrew paths where neither exists is still caught" "every path the configs hardcode" \
  bash -c 'printf "\nprobe=/opt/homebrew/bin/nope\nprobe2=/usr/local/bin/nope\n" >> zsh/.zshrc'

mutate "a syntax error in wezterm.lua is caught" "every lua file parses" \
  bash -c 'printf "\nthis is not lua((\n" >> wezterm/.config/wezterm/wezterm.lua'

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

# ------------------------------------------------------ what the linters can see

mutate "a shell script with no shebang is caught, because lint would skip it" "declare an interpreter" \
  bash -c 'tail -n +2 checks/lib.sh > checks/lib.tmp && mv checks/lib.tmp checks/lib.sh'

mutate "CI no longer running the linters is caught" "CI runs 'make lint'" \
  sed -i '' 's/^        run: make lint$/        run: true/' .github/workflows/ci.yml

# ------------------------------------- assertions that could pass while being wrong

# The old version of this compared COUNTS: renaming a binding kept the total at
# twenty-one and passed.
mutate "a binding renamed out of test-bindings.sh's accounting is caught" "pressed or explained" \
  sed -i '' 's/^bind w choose-tree/bind W choose-tree/' tmux/.config/tmux/tmux.conf

mutate "a stow package list that disagrees with the others is caught" "copies of the stow package list" \
  sed -i '' 's/local packages=(nvim wezterm tmux zsh home starship)/local packages=(nvim wezterm tmux zsh home)/' bootstrap.sh

# The copy the first version of this check could not see, because it named its
# four sources by hand and there were six.
mutate "a copy in a test suite disagreeing is caught too" "copies of the stow package list" \
  sed -i '' 's/nvim wezterm tmux zsh home starship git/nvim wezterm tmux zsh home git/' tests/test-fresh-machine.sh

# make accepts any number of .PHONY lines; reading only the first left
# everything on a second one unchecked.
mutate "a recipeless target on a SECOND .PHONY line is caught" "has a recipe" \
  bash -c 'printf "\n.PHONY: ghost\n" >> Makefile'

# ------------------------------------------- constants written down more than once

# The pair the comments named: the guard's floor and prune's idea of degenerate.
# shellcheck disable=SC2016  # ${...} and $logfile are text in the target file
mutate "the guard's floor drifting from prune's is caught" "minimum window count" \
  sed -i '' 's/^MIN_WINDOWS="${MIN_WINDOWS:-2}"/MIN_WINDOWS="${MIN_WINDOWS:-3}"/' tmux/.local/bin/tmux-resurrect-saves

# The other pair: resurrect's own backup deletion against prune's retention.
mutate "the two retention windows drifting apart is caught" "retention window in days" \
  sed -i '' "s/@resurrect-delete-backup-after '90'/@resurrect-delete-backup-after '60'/" tmux/.config/tmux/tmux.conf

# A default documented in prose is a third copy of the number.
mutate "the guard's header disagreeing with its own default is caught" "minimum window count" \
  sed -i '' 's/rule 1 floor       (default 2)/rule 1 floor       (default 3)/' tmux/.local/bin/tmux-resurrect-guard

mutate "the guard's fallback drifting from tmux.conf is caught" "collapse percentage" \
  sed -i '' "s/tmux_opt '@resurrect-guard-collapse-pct' '50'/tmux_opt '@resurrect-guard-collapse-pct' '40'/" tmux/.local/bin/tmux-resurrect-guard

# shellcheck disable=SC2016  # ${...} and $logfile are text in the target file
mutate "a log trim that no longer matches its own header is caught" "guard.log is trimmed to" \
  sed -i '' 's/tail -n 200 "$logfile"/tail -n 100 "$logfile"/' tmux/.local/bin/tmux-resurrect-guard

# A comment quoting another file is a copy, and this proves the copy is read.
mutate "a comment quoting a tmux.conf line that changed is caught" "line a comment quotes" \
  sed -i '' "s|@resurrect-hook-post-save-all '~/.local/bin/tmux-resurrect-guard|@resurrect-hook-post-save-all '~/.local/bin/tmux-guard|" tmux/.config/tmux/tmux.conf

# And the anti-vacuity guard: a value that cannot be read must fail, not compare
# equal to the nothing beside it.
mutate "a constant that cannot be read at all fails rather than comparing empty" "minimum window count" \
  sed -i '' '/^MIN_WINDOWS=/d' tmux/.local/bin/tmux-resurrect-saves

# ---------------------------------------------------- what the repo says of itself

# A hook and the make target that describes it are two copies of one command.
mutate "a pre-push hook that no longer runs its make target is caught" "runs exactly what" \
  sed -i '' 's|/tests/run.sh" --fast|/tests/run.sh"|' .githooks/pre-push

mutate "a file advertising the hooks with the wrong target is caught" "advertises the hooks" \
  sed -i '' 's/test-fast on push/test on push/' Makefile

# A slow suite's header must agree with what the hook really does.
mutate "a slow suite claiming the hook runs it is caught" "say who runs them" \
  sed -i '' 's/and so does the pre-push hook/and the pre-push hook still runs everything/' tests/test-restore.sh

mutate "losing the SUITE_SLOW marker entirely is caught" "say who runs them" \
  sed -i '' 's/^SUITE_SLOW=1/SUITE_BRISK=1/' tests/test-restore.sh tests/test-nvim.sh tests/test-check.sh \
  tests/test-bindings.sh tests/test-integration.sh tests/test-helpers.sh tests/test-sessionizer.sh \
  tests/test-continuum.sh tests/test-performance.sh

# Everything below rolls up into one ✓, so each mutation names the specific
# claim it breaks. They are separate assertions inside checks/repo.sh; a single
# marker is what the roll-up costs.
mutate "a make target the README invents is caught" "describes nothing that is not here" \
  bash -c 'printf "\nRun make nonesuch for luck.\n" >> README.md'

mutate "a make target the README never mentions is caught" "describes nothing that is not here" \
  sed -i '' '/^make doctor/d' README.md

# shellcheck disable=SC2016  # backticks are markdown, not substitution
mutate "a path the README references that is not here is caught" "describes nothing that is not here" \
  sed -i '' 's|`checks/repo.sh`|`checks/nope.sh`|' README.md

mutate "a package in the README table that is not a package is caught" "describes nothing that is not here" \
  sed -i '' 's/^| \*\*starship\*\*/| **stargazer**/' README.md

# shellcheck disable=SC2016  # backticks are markdown, not substitution
mutate "a helper script the README documents but that is gone is caught" "describes nothing that is not here" \
  sed -i '' 's/^\*\*`tmux-resurrect-saves`\*\*/**`tmux-resurrect-savez`**/' README.md

mutate "a subcommand the README shows but the script rejects is caught" "describes nothing that is not here" \
  sed -i '' 's/tmux-resurrect-saves list/tmux-resurrect-saves inventory/' README.md

# The drift in the direction it really happens: the config changes, the README
# does not.
mutate "a tmux binding the README documents but tmux.conf no longer binds is caught" "describes nothing that is not here" \
  sed -i '' '/^bind w choose-tree/d' tmux/.config/tmux/tmux.conf

# shellcheck disable=SC2016  # backticks are markdown, not substitution
mutate "a leader mapping the README documents but nothing asserts is caught" "describes nothing that is not here" \
  sed -i '' 's/`<leader>ff`/`<leader>zz`/' README.md

# shellcheck disable=SC2016  # backticks are markdown, not substitution
mutate "a Neovim binding the README documents but the lua config lacks is caught" "describes nothing that is not here" \
  sed -i '' 's/| `gd` |/| `gz` |/' README.md

# shellcheck disable=SC2016  # the $names are starship modules, not variables
mutate "a prompt module the README's row does not mention is caught" "describes nothing that is not here" \
  sed -i '' 's/\$git_status\$python/$git_status$hostname$python/' starship/.config/starship.toml

mutate "a timing quoted in the prose is caught" "describes nothing that is not here" \
  bash -c 'printf "\nThe hook takes about 19s.\n" >> README.md'

mutate "a suite count that no longer matches tests/ is caught" "describes nothing that is not here" \
  sed -i '' 's/18 suites/17 suites/' .githooks/pre-push

# The anti-vacuity guards. An extractor that quietly returns nothing would turn
# every comparison above into "" = "", which passes while asserting nothing.
mutate "an unreadable save interval fails rather than permitting every figure" "describes nothing that is not here" \
  sed -i '' '/@continuum-save-interval/d' tmux/.config/tmux/tmux.conf

mutate "unreadable leader sets fail rather than passing vacuously" "describes nothing that is not here" \
  sed -i '' 's/^EXPECTED_LEADER_[NV]=.*/EXPECTED_LEADER_X=""/' tests/test-nvim.sh

echo
echo "== a figure in the prose must match the config that owns it =="
# The README says continuum saves every 15 minutes because tmux.conf says 15.
# Change one and the other is a lie with nothing to notice it — which is the
# whole reason the permitted figures are read out of the config rather than
# listed in the check.
reset_repo
sed -i '' "s/@continuum-save-interval '15'/@continuum-save-interval '20'/" \
  "$WORK/tmux/.config/tmux/tmux.conf"
out="$(run_check)"
refute "changing the interval without the README is caught" contains "$out" "0 failure(s)"
assert "and the message names the figure that stopped matching" contains "$out" "15 minutes"

echo
echo "== a filetype's second formatter is checked too =="
# The extraction read one formatter per filetype. Every entry has exactly one
# today, so nothing was being missed — but a fallback, which is the ordinary way
# conform is configured, would have gone unchecked from the moment it was added.
reset_repo
sed -i '' 's/lua = { "stylua" }/lua = { "stylua", "not-a-real-formatter" }/' \
  "$WORK/nvim/.config/nvim/lua/rich/plugins/conform.lua"
out="$(run_check_full | sed 's/\x1b\[[0-9;]*m//g')"
assert "the second formatter in a filetype's list is checked as well as the first" \
  contains "$out" "formatter not-a-real-formatter is not on PATH"

echo
echo "== naming both Homebrew prefixes means only one has to exist =="
# .zshrc and bootstrap.sh try /opt/homebrew and then /usr/local. No machine has
# a Homebrew binary under both, so without this rule the path scan would report
# a missing path on every machine there is. Only meaningful where exactly one of
# the two has tmux, which is every normal machine.
prefixes=0
[ -e /opt/homebrew/bin/tmux ] && prefixes=$((prefixes + 1))
[ -e /usr/local/bin/tmux ] && prefixes=$((prefixes + 1))
reset_repo
if ! contains "$(run_check_full)" "every path the configs hardcode"; then
  printf '  \033[33mSKIP\033[0m  the machine half does not pass here\n'
elif [ "$prefixes" -ne 1 ]; then
  printf '  \033[33mSKIP\033[0m  this machine has tmux under %s Homebrew prefixes, not one\n' "$prefixes"
else
  absent=/usr/local/bin/tmux
  [ -e "$absent" ] && absent=/opt/homebrew/bin/tmux
  printf '\nprobe=/opt/homebrew/bin/tmux\nprobe2=/usr/local/bin/tmux\n' >>"$WORK/zsh/.zshrc"
  out="$(run_check_full)"
  refute "the absent prefix is not reported when the file names both" \
    contains "$out" "$absent, which does not exist"
fi

echo
echo "== check.sh's own exit status =="
reset_repo
(cd "$WORK" && ./check.sh --repo-only >/dev/null 2>&1)
assert "a clean repo exits 0" [ $? -eq 0 ]
(cd "$WORK" && git rm -q --cached nvim/.config/nvim/lazy-lock.json)
rc=0
(cd "$WORK" && ./check.sh --repo-only >/dev/null 2>&1) || rc=$?
assert "a repo with a defect exits non-zero, so a hook or CI can act on it" [ "$rc" -ne 0 ]

echo
echo "== status-right must be set before tpm runs =="
# Continuum appends #(continuum_save.sh) to status-right when tpm loads it.
# Setting status-right after that point overwrites the addition and every
# automatic save stops, with no error and no missing file — the exact shape of
# failure this repo exists to catch.
reset_repo
python3 - "$WORK/tmux/.config/tmux/tmux.conf" <<'MOVE'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(True)
sr = [i for i, l in enumerate(lines) if l.lstrip().startswith("set ") and "status-right" in l]
tpm = [i for i, l in enumerate(lines) if l.lstrip().startswith("run ") and "tpm" in l]
line = lines.pop(sr[0])
lines.insert(tpm[-1], line)  # now below the tpm run line
open(p, "w").write("".join(lines))
MOVE
out="$(run_check)"
refute "moving status-right below tpm is caught" contains "$out" "0 failure(s)"
assert "and the message names the ordering, not just a missing setting" \
  contains "$out" "overwrites continuum"

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
