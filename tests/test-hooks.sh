#!/usr/bin/env bash
# The git hooks — driven by real git, not inspected as files.
#
# check.sh asserts the hook FILES exist, which it does because they were once
# deleted while core.hooksPath stayed set and git silently ran nothing at all.
# But "the file is present" is a long way from "the commit is refused", and
# nothing had ever checked the second. These hooks are the only reason any of
# the rest of this runs without someone remembering to run it.
#
# Everything happens in a throwaway repo with a local bare remote. Nothing here
# may touch this repository's history or reach GitHub.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORK="$TEST_TMP/repo"
BARE="$TEST_TMP/origin.git"

# THE RECURSION TRAP: pre-push runs tests/run.sh, which includes THIS suite,
# which would push again — for ever. So the pushing tests replace tests/run.sh
# in the throwaway with a stub. That is the right level anyway: the hook's job
# is to run a command at a known path and propagate its status, and the stub
# proves exactly that while the suites are tested on their own elsewhere.
stub_runner() { # $1 = exit status the stub should report
  cat >"$WORK/tests/run.sh" <<STUB
#!/usr/bin/env bash
echo "\$@" >"$TEST_TMP/runner-was-called"
exit $1
STUB
  chmod +x "$WORK/tests/run.sh"
  rm -f "$TEST_TMP/runner-was-called"
}

build_repo() {
  rm -rf "$WORK" "$BARE"
  mkdir -p "$WORK"
  git init -q --bare "$BARE"
  (cd "$REPO_ROOT" && git ls-files -z | tar -c --null -T - -f -) | tar -x -C "$WORK"
  (
    cd "$WORK" || exit 1
    git init -q -b main .
    git remote add origin "$BARE"
    # The identity check compares git's effective values against the repo's own,
    # so a placeholder here would fail check.sh for a reason unrelated to hooks.
    git config user.email "$(git -C "$REPO_ROOT" config user.email)"
    git config user.name "$(git -C "$REPO_ROOT" config user.name)"
    git config core.hooksPath .githooks
    git add -A
  )
}

in_repo() { (cd "$WORK" && "$@" >"$TEST_TMP/git.out" 2>&1); }

build_repo

# check.sh's machine half asserts things about THIS machine — a stow tree, a
# font, a colour scheme — none of which hold on a CI runner. Where it cannot
# pass, "a healthy tree is allowed through" is untestable and is skipped by
# name; the assertions about BLOCKING still work, because a broken tree fails
# either way.
machine_ok=0
(cd "$WORK" && ./check.sh >/dev/null 2>&1) && machine_ok=1

# ---------------------------------------------------------------- pre-commit

echo "== pre-commit =="
if [ "$machine_ok" -eq 1 ]; then
  in_repo git commit -q -m "healthy baseline"
  assert "a healthy tree commits" [ "$?" -eq 0 ]
else
  printf '  \033[33mSKIP\033[0m  check.sh does not pass on this machine, so a clean commit cannot be asserted\n'
  in_repo git commit -q --no-verify -m "healthy baseline"
fi

# Break something check.sh is known to catch. usstyle is a good choice: it is a
# single word, its absence is invisible in normal use, and the check for it
# exists because it was wrong here for months.
sed -i.orig 's/usstyle/REMOVED_BY_TEST/' "$WORK/tmux/.config/tmux/tmux.conf"
rm -f "$WORK/tmux/.config/tmux/tmux.conf.orig"
(cd "$WORK" && git add -A)
in_repo git commit -q -m "should not be allowed"
refute "a tree with a defect check.sh catches does NOT commit" [ "$?" -eq 0 ]
assert "and the reason reaches the terminal, not just an exit code" \
  contains "$(cat "$TEST_TMP/git.out")" "usstyle"

in_repo git commit -q --no-verify -m "bypassed on purpose"
assert "--no-verify still gets through, because a broken bypass is its own bug" \
  [ "$?" -eq 0 ]

# ---------------------------------------------------------------- the silent case

echo
echo "== core.hooksPath pointing at a hook that is not there =="
# This happened: `git add -A` then `git reset --hard` removed .githooks/ while
# core.hooksPath stayed set, and git ran NOTHING, silently, for days. git does
# not warn about a missing hook — there is nothing to grep for and no exit code
# to notice. That is the entire reason check.sh asserts the files exist, and it
# is asserted here so the justification is visible rather than folklore.
rm -f "$WORK/.githooks/pre-commit"
printf 'x\n' >>"$WORK/README.md" 2>/dev/null || printf 'x\n' >"$WORK/README.md"
(cd "$WORK" && git add -A)
in_repo git commit -q -m "no hook present at all"
assert "git commits happily with the hook missing" [ "$?" -eq 0 ]
refute "and says nothing whatsoever about it" \
  contains "$(cat "$TEST_TMP/git.out")" "hook"

# ---------------------------------------------------------------- pre-push

echo
echo "== pre-push =="
build_repo
(cd "$WORK" && git commit -q --no-verify -m "base")

stub_runner 1
in_repo git push -q origin main
refute "a failing suite stops the push" [ "$?" -eq 0 ]
assert "the hook really did invoke tests/run.sh" [ -f "$TEST_TMP/runner-was-called" ]
assert "and passed --fast, so it is the quick set that gates a push" \
  contains "$(cat "$TEST_TMP/runner-was-called" 2>/dev/null)" "--fast"
refute "nothing reached the remote" \
  [ -n "$(git -C "$BARE" log --oneline -1 2>/dev/null)" ]

stub_runner 1
in_repo git push -q --no-verify origin main
assert "--no-verify pushes anyway" [ "$?" -eq 0 ]
assert "and that really did reach the remote" \
  [ -n "$(git -C "$BARE" log --oneline -1 2>/dev/null)" ]

build_repo
(cd "$WORK" && git commit -q --no-verify -m "base")
stub_runner 0
in_repo git push -q origin main
assert "a passing suite lets the push through" [ "$?" -eq 0 ]

# ---------------------------------------------------------------- the design

echo
echo "== a half-set-up machine must still be able to commit =="
# pre-commit runs the FULL check.sh, machine half included. That is only safe
# because the volatile things are warnings: a formatter missing from PATH
# reports `!` and does not fail the run. If one of them were ever turned into a
# hard failure, every commit on that machine would be refused until someone
# installed a formatter, and the person it happened to would have no idea why.
shim="$TEST_TMP/nostylua"
mkdir -p "$shim"
while IFS= read -r d; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="$(basename "$f")"
    [ "$b" = "stylua" ] && continue
    [ -e "$shim/$b" ] || ln -s "$f" "$shim/$b" 2>/dev/null
  done
done <<<"$(printf '%s' "$PATH" | tr ':' '\n')"

fail_count() { # $1... = env prefix; echoes check.sh's failure count
  "$@" "$REPO_ROOT/check.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' |
    sed -n 's/.*, \([0-9][0-9]*\) failure(s).*/\1/p' | tail -1
}

if [ -e "$shim/stylua" ]; then
  printf '  \033[33mSKIP\033[0m  could not build a PATH without stylua\n'
else
  # COMPARATIVE, not absolute. "check.sh passes with a formatter missing" is not
  # testable on a runner, where the machine half cannot pass for reasons that
  # have nothing to do with formatters — CI duly failed on exactly that. The
  # invariant that actually matters holds anywhere: removing a formatter must
  # add a WARNING and must not change the number of FAILURES.
  base_fails="$(fail_count env)"
  nostylua_fails="$(fail_count env PATH="$shim")"
  # Stripped, because the markers are colour-wrapped: the literal "! formatter"
  # never appears in the raw output, there is an escape sequence between them.
  out="$(PATH="$shim" "$REPO_ROOT/check.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"

  printf '    failures with stylua: %s, without: %s\n' "${base_fails:-?}" "${nostylua_fails:-?}"
  # One command, not two joined by &&: `assert desc [ a ] && [ b ]` asserts only
  # the first test and then evaluates the second on its own, so half the
  # condition silently does not participate.
  same_fails() { [ -n "$1" ] && [ "$1" = "$2" ]; }
  assert "removing a formatter does not add a failure" \
    same_fails "$base_fails" "$nostylua_fails"
  assert "it is reported as a warning instead" \
    contains "$out" "formatter stylua is not on PATH"
  assert "and carries the warning marker, not the failure one" \
    contains "$out" "! formatter stylua"
fi

finish
