#!/usr/bin/env bash
# make tidy / tidy-apply.
#
# tidy-apply deletes tmux-resurrect saves, scratch files and git branches, and
# had never been tested. prune earned its suite by nearly deleting a day of
# session history; this target had no such scrutiny.
#
# Everything runs against a throwaway git repo with a throwaway $HOME. The real
# repo's branches and the real resurrect directory are never touched — running
# `make tidy-apply` in the real tree is precisely what these tests must not do.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO="$TEST_TMP/repo"
FAKE_HOME="$TEST_TMP/home"
RDIR="$TEST_TMP/resurrect"

setup_repo() {
  rm -rf "$REPO" "$FAKE_HOME" "$RDIR"
  mkdir -p "$REPO/tmp" "$FAKE_HOME/.local/state/nvim" "$RDIR"
  cp "$REPO_ROOT/Makefile" "$REPO/Makefile"
  # tidy.sh does the work; the Makefile targets just call it. It cd's to its own
  # directory, so copying it here is what scopes the whole run to the scratch
  # repo rather than the real one.
  cp "$REPO_ROOT/tidy.sh" "$REPO/tidy.sh"
  (
    cd "$REPO" || exit 1
    git init -q -b main .
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  )
}

# Run the target the way a person would, but with every path redirected.
run_tidy() { # $1 = tidy | tidy-apply
  (
    cd "$REPO" || exit 1
    HOME="$FAKE_HOME" RESURRECT_DIR="$RDIR" PATH="$BIN:$PATH" \
      make "$1" 2>&1
  )
}
tidy_rc() {
  (
    cd "$REPO" || exit 1
    HOME="$FAKE_HOME" RESURRECT_DIR="$RDIR" PATH="$BIN:$PATH" \
      make "$1" >/dev/null 2>&1
  )
}
# Same run, but keeping what it said. A non-zero status tells a cron job that
# something went wrong; it does not tell a person WHICH thing, and the messages
# that carry that were never asserted — tidy could go silent about the cause and
# only the status assertion would still pass.
tidy_out() {
  (
    cd "$REPO" || exit 1
    HOME="$FAKE_HOME" RESURRECT_DIR="$RDIR" PATH="$BIN:$PATH" \
      make "$1" 2>&1
  )
}

echo "== tidy reports without deleting =="
setup_repo
printf 'x\n' >"$REPO/tmp/99-old"
touch -t 202001010000 "$REPO/tmp/99-old"
out="$(run_tidy tidy)"
assert "tidy names the stale scratch file" contains "$out" "99-old"
assert "tidy deletes nothing" [ -f "$REPO/tmp/99-old" ]
assert "tidy says so explicitly" contains "$out" "Nothing was deleted"

echo
echo "== tidy-apply removes what it said it would =="
out="$(run_tidy tidy-apply)"
refute "the stale scratch file is gone" [ -f "$REPO/tmp/99-old" ]
assert "and it reported removing it" contains "$out" "removed"

echo
echo "== a fresh scratch file is NOT removed =="
setup_repo
printf 'x\n' >"$REPO/tmp/99-live"
run_tidy tidy-apply >/dev/null
assert "a file touched today survives the 7-day cutoff" [ -f "$REPO/tmp/99-live" ]

echo
echo "== .git is never walked into =="
# -delete implies -depth, and -depth silently turns -prune into a no-op. The
# find here uses -not -path instead for exactly that reason; this proves it.
setup_repo
printf 'x\n' >"$REPO/.git/99-inside-git"
touch -t 202001010000 "$REPO/.git/99-inside-git"
run_tidy tidy-apply >/dev/null
assert "a 99-* file inside .git is left alone" [ -f "$REPO/.git/99-inside-git" ]

echo
echo "== branches merged into main are deleted, others are not =="
setup_repo
(
  cd "$REPO" || exit 1
  git checkout -q -b merged-branch
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m merged
  git checkout -q main
  git merge -q merged-branch
  git checkout -q -b unmerged-branch
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m unmerged
  git checkout -q main
)
run_tidy tidy-apply >/dev/null
refute "a branch already merged into main is deleted" \
  git -C "$REPO" show-ref --verify --quiet refs/heads/merged-branch
assert "a branch with unmerged work is kept" \
  git -C "$REPO" show-ref --verify --quiet refs/heads/unmerged-branch
assert "main itself is never deleted" \
  git -C "$REPO" show-ref --verify --quiet refs/heads/main

echo
echo "== the checked-out branch is never deleted, even when merged =="
setup_repo
(
  cd "$REPO" || exit 1
  git checkout -q -b current-and-merged
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
  git checkout -q main
  git merge -q current-and-merged
  git checkout -q current-and-merged
)
run_tidy tidy-apply >/dev/null
assert "the branch you are standing on survives" \
  git -C "$REPO" show-ref --verify --quiet refs/heads/current-and-merged

echo
echo "== the LSP log is truncated, not deleted =="
setup_repo
LOG="$FAKE_HOME/.local/state/nvim/lsp.log"
printf 'noise\n%.0s' $(seq 1 500) >"$LOG"
before="$(wc -c <"$LOG" | tr -d ' ')"
out="$(run_tidy tidy-apply)"
assert "the log still exists (nvim holds it open; deleting it leaks the fd)" [ -f "$LOG" ]
assert "but it is empty" [ "$(wc -c <"$LOG" | tr -d ' ')" -eq 0 ]
assert "it was non-empty to begin with" [ "${before:-0}" -gt 0 ]
assert "and it reported the truncation" contains "$out" "truncated"

echo
echo "== uncommitted work is only ever reported =="
setup_repo
printf 'mine\n' >"$REPO/precious.txt"
run_tidy tidy-apply >/dev/null
assert "an untracked file is left alone" [ -f "$REPO/precious.txt" ]

echo
echo "== failures must not be reported as successes =="
setup_repo
printf 'x\n' >"$REPO/tmp/99-undeletable"
touch -t 202001010000 "$REPO/tmp/99-undeletable"
chmod a-w "$REPO/tmp"
out="$(run_tidy tidy-apply)"
still_there=0
[ -f "$REPO/tmp/99-undeletable" ] && still_there=1
chmod u+w "$REPO/tmp"
if [ "$still_there" -eq 1 ]; then
  # SCRATCH_FIND runs `find .`, so the report carries a RELATIVE path. Checking
  # for the absolute one would never match and the assertion would pass without
  # testing anything.
  refute "a file that could NOT be deleted is not reported as removed" \
    contains "$out" "removed ./tmp/99-undeletable"
else
  ok "the file was deletable after all, so there is nothing to mis-report"
fi

setup_repo
printf 'x\n' >"$FAKE_HOME/.local/state/nvim/lsp.log"
chmod a-w "$FAKE_HOME/.local/state/nvim/lsp.log"
out="$(run_tidy tidy-apply)"
size="$(wc -c <"$FAKE_HOME/.local/state/nvim/lsp.log" | tr -d ' ')"
chmod u+w "$FAKE_HOME/.local/state/nvim/lsp.log"
if [ "${size:-0}" -gt 0 ]; then
  refute "a log that could NOT be truncated is not reported as truncated" \
    contains "$out" "truncated"
else
  ok "the log was truncatable, so there is nothing to mis-report"
fi

echo
echo "== tidy-apply exits non-zero when something failed =="
setup_repo
printf 'x\n' >"$REPO/tmp/99-undeletable"
touch -t 202001010000 "$REPO/tmp/99-undeletable"
chmod a-w "$REPO/tmp"
rc=0
out="$(tidy_out tidy-apply)" || rc=$?
chmod u+w "$REPO/tmp"
assert "a wrapper or cron job can tell that it did not do its job" [ "$rc" -ne 0 ]
assert "and a person is told which file it could not delete" \
  contains "$out" "99-undeletable"
assert "with FAILED against it, not buried in ordinary output" contains "$out" "FAILED:"
assert "and a count at the end, so a long report cannot hide it" \
  contains "$out" "action(s) FAILED"

finish
