#!/usr/bin/env bash
# The branches that only run when something has already gone wrong.
#
# Every tool here is well covered on the path where things work, and on the
# handful of failures I happened to think of while writing it. Whole branches
# had never executed — including tmux-resurrect-guard's VETO FAILED, which runs
# at precisely the moment the clobber the guard exists to prevent is happening.
#
# For each case the question is the same: does it fail LOUDLY, or does it
# corrupt something quietly? The second is a bug even when the input was absurd.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GUARD="$BIN/tmux-resurrect-guard"
TOOL="$BIN/tmux-resurrect-saves"
STUB="$TEST_TMP/stub"
MARKER="${TMPDIR:-/tmp}/tmux-resurrect-guard-$(id -u).pending"

make_tmux_stub "$STUB"
export GOPT_RESURRECT_GUARD=on
export GOPT_RESURRECT_GUARD_MIN_WINDOWS=2
export GOPT_RESURRECT_GUARD_COLLAPSE_PCT=50
export GOPT_RESURRECT_GUARD_NOTIFY=on

cleanup_failures() {
  # A read-only directory left behind would break the harness's own cleanup.
  chmod -R u+w "$TEST_TMP" 2>/dev/null
  rm -f "$MARKER"
  cleanup_common
}
trap cleanup_failures EXIT

fresh() { # a resurrect dir with a healthy `last`
  rm -rf "$1"
  mkdir -p "$1"
  make_save "$1/tmux_resurrect_20200101T000000.txt" 15 3
  ln -sfn "tmux_resurrect_20200101T000000.txt" "$1/last"
  export TESTLOG="$1/display.log"
  : >"$TESTLOG"
  rm -f "$MARKER"
}

# ------------------------------------------------------- the veto that cannot run

echo "== when the guard CANNOT carry out a veto, it says so out loud =="
# This is the worst moment in the whole system: the guard has decided the save
# must not happen, and cannot make that stick. Silence here means `last` is
# clobbered with nothing but a log line inside the directory that just refused a
# write.
W="$TEST_TMP/vetofail"
fresh "$W"
cand="$W/tmux_resurrect_20200101T010000.txt"
make_save "$cand" 1 1
before="$(cat "$cand")"
# Both permissions are needed, and each on its own is a test that proves nothing:
# with only the FILE read-only, `cp -f` unlinks and recreates it; with only the
# DIRECTORY read-only, cp opens the existing file and truncates it, because write
# permission on a directory governs its entries, not their contents. Either way
# the veto succeeds and this whole section silently tests the happy path.
chmod a-w "$cand" "$W"
PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
chmod u+w "$W" "$cand"

# guard.log lives in the directory that just refused a write, so it may well be
# unwritable too — which is exactly why the status line matters here.
assert "it says VETO FAILED on the status line, where it can be seen" \
  contains "$(cat "$TESTLOG" 2>/dev/null)" "VETO FAILED"
assert "the candidate is left as it was, so resurrect decides normally" \
  [ "$(cat "$cand")" = "$before" ]
refute "and no stale stash marker is left claiming a veto happened" [ -f "$MARKER" ]

# ------------------------------------------------------- unreadable stash

echo
echo "== --post-save-all with an unreadable stash =="
# An UNREADABLE stash cannot really happen — the guard writes it itself with cp.
# What can happen is a marker naming a stash that is no longer there: an
# interrupted run, a cleaned tmpdir, a stash removed between the two hooks.
W="$TEST_TMP/stashfail"
fresh "$W"
printf 'GOOD-ARCHIVE' >"$W/pane_contents.tar.gz"
printf '%s\n%s\n' "$W/.guard-pane-contents.tar.gz" "$W/pane_contents.tar.gz" >"$MARKER"
PATH="$STUB:$PATH" "$GUARD" --post-save-all >/dev/null 2>&1

assert "a marker naming a missing stash leaves the archive alone" \
  contains "$(cat "$W/pane_contents.tar.gz" 2>/dev/null)" "GOOD-ARCHIVE"
refute "and the marker is consumed rather than left to fire again later" [ -f "$MARKER" ]

# ------------------------------------------------------- malformed saves

echo
echo "== malformed saves: every tool must refuse them, not act on them =="
# A save file is parsed with awk on tab-separated records. None of these inputs
# should ever occur, and all of them are cheap to survive; the failure that
# matters is a tool treating garbage as a workspace worth restoring.
malformed_case() { # $1 = label, $2 = file content (raw)
  local label="$1" content="$2"
  local d="$TEST_TMP/mal"
  fresh "$d"
  local bad="$d/tmux_resurrect_20200101T020000.txt"
  printf '%s' "$content" >"$bad"

  # The guard must veto it: whatever it is, it is not a workspace.
  PATH="$STUB:$PATH" "$GUARD" "$bad" >/dev/null 2>&1
  if cmp -s "$bad" "$d/last"; then
    ok "$label: the guard vetoed it"
  else
    no "$label: the guard ALLOWED it — a malformed save could become 'last'"
  fi

  # Rewrite it first: a veto REPLACES the candidate with a copy of `last`, so
  # after the check above this file is a healthy 15-window save and promote would
  # rightly accept it. The two assertions were silently testing different files.
  printf '%s' "$content" >"$bad"
  # And promote must refuse to point `last` at it.
  if RESURRECT_DIR="$d" quietly "$TOOL" promote 20200101T020000; then
    no "$label: promote accepted it without --force"
  else
    ok "$label: promote refused it"
  fi
}

malformed_case "empty file" ""
malformed_case "truncated mid-record" "pane	sess1	1	1	:*	1	host"
malformed_case "wrong field count" "window	only-two-fields
"
malformed_case "non-UTF8 bytes" "$(printf 'window\tsess\xff\xfe\t1\t:zsh\t1\t:*\tab,80x23,0,0,1\t:\n')"
malformed_case "records but no windows" "pane	sess1	1	1	:*	1	host	:/tmp	1	zsh	:
state	sess1	sess1
"

# ------------------------------------------------------- last is a directory

echo
echo "== 'last' as a real directory rather than a symlink =="
# -n on ln covers a symlink-to-directory but not a real one; against a real
# directory `ln -sfn x last` cheerfully creates last/x and exits 0.
W="$TEST_TMP/lastdir"
rm -rf "$W"
mkdir -p "$W/last"
make_save "$W/tmux_resurrect_20200101T000000.txt" 15 3
refute "promote refuses rather than creating a link inside it" \
  quietly env RESURRECT_DIR="$W" "$TOOL" promote 20200101T000000
# Emptiness, not `[ -e last/<name> ]`. The entry ln creates in there is a
# symlink to a relative name that does not resolve inside last/, so -e follows
# it, finds nothing and reports absence — the assertion passed even with the
# refusal removed and the entry sitting right there. `ls -A` sees the entry
# itself and cannot be fooled that way.
assert "and the directory is still empty — nothing was created inside it" \
  [ -z "$(ls -A "$W/last")" ]

cand="$W/tmux_resurrect_20200101T030000.txt"
make_save "$cand" 1 1
before="$(cat "$cand")"
PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
assert "the guard does not corrupt the candidate when 'last' is a directory" \
  [ -f "$cand" ]
assert "...and leaves it readable either way" [ -s "$cand" ]

# ------------------------------------------------------- read-only directory

echo
echo "== a read-only resurrect directory =="
W="$TEST_TMP/readonly"
fresh "$W"
cand="$W/tmux_resurrect_20200101T040000.txt"
make_save "$cand" 1 1
chmod a-w "$W"
PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
rc=$?
chmod u+w "$W"
assert "the guard exits cleanly rather than crashing" [ "$rc" -eq 0 ]
assert "'last' still points where it did" \
  [ "$(readlink "$W/last")" = "tmux_resurrect_20200101T000000.txt" ]

# prune must have something it genuinely wants to delete, or exiting 0 is
# correct and the assertion proves nothing. `cand` above was seconds old, so the
# in-flight guard (-mmin -2) skipped it and prune did no work at all.
old="$W/tmux_resurrect_20190101T000000.txt"
make_save "$old" 5 2
touch -t 201901010000 "$old"
chmod a-w "$W"
refute "prune --apply reports failure rather than claiming success" \
  quietly env RESURRECT_DIR="$W" KEEP_ALL_DAYS=0 "$TOOL" prune --apply
chmod u+w "$W"
assert "and the save it could not delete is still there" [ -f "$old" ]

# ------------------------------------------------------- the untaken refusals

echo
echo "== the refusals no test had ever reached =="
# Found by mutation sweep: each `die` in tmux-resurrect-saves was neutered in
# turn and the suites re-run. Six of the nine survived — the message was there,
# the branch had simply never executed, so nothing would have noticed it being
# deleted. These are the reachable ones.
W="$TEST_TMP/refusals"
fresh "$W"

refute "promote with no argument refuses rather than assuming one" \
  quietly env RESURRECT_DIR="$W" "$TOOL" promote
assert "and says how to call it" \
  contains "$(RESURRECT_DIR="$W" "$TOOL" promote 2>&1)" "usage:"

refute "promote of a stamp that does not exist" \
  quietly env RESURRECT_DIR="$W" "$TOOL" promote 19990101T000000
assert "names the save it could not find" \
  contains "$(RESURRECT_DIR="$W" "$TOOL" promote 19990101T000000 2>&1)" "no such save"

refute "a RESURRECT_DIR that is not there" \
  quietly env RESURRECT_DIR="$TEST_TMP/no-such-dir" "$TOOL" list
assert "names the directory rather than reporting an empty list" \
  contains "$(RESURRECT_DIR="$TEST_TMP/no-such-dir" "$TOOL" list 2>&1)" "not found"

refute "an unknown subcommand" quietly env RESURRECT_DIR="$W" "$TOOL" frobnicate
assert "points at --help" \
  contains "$(RESURRECT_DIR="$W" "$TOOL" frobnicate 2>&1)" "--help"

# ln failing is the one that matters: promote reporting success while `last`
# still points at the old save is exactly the silent failure this repo exists to
# stop. A read-only directory is the realistic way to cause it.
old_target="$(readlink "$W/last")"
make_save "$W/tmux_resurrect_20200101T050000.txt" 12 3
chmod a-w "$W"
out="$(RESURRECT_DIR="$W" "$TOOL" promote 20200101T050000 2>&1)"
rc=$?
chmod u+w "$W"
assert "promote fails when it cannot rewrite the symlink" [ "$rc" -ne 0 ]
assert "and says the symlink is what went wrong" contains "$out" "symlink"
assert "'last' still points at the save it did before" \
  [ "$(readlink "$W/last")" = "$old_target" ]

# NOT COVERED, deliberately: the check after ln that re-reads the symlink and
# dies if it does not point where it should. Reaching it needs ln to report
# success AND leave the wrong target behind — a filesystem lying about a
# completed operation. It is defence in depth against exactly that, and there is
# no honest way to stage it; a test that stubbed ln would only test the stub.
# Removing it is invisible to this suite, which is recorded here rather than
# left for the next mutation sweep to rediscover.

# Same for the date-cutoff failure in prune: it fires only if BOTH the BSD and
# GNU date invocations fail, which on a machine without a working `date` means
# nothing else in the script works either.

# ------------------------------------------------------- the guard's own exits

echo
echo "== the guard's early exits =="
# Same sweep, run against tmux-resurrect-guard. Most of its `||` fallbacks
# resisted a meaningful mutation rather than a meaningful test — `|| echo 0` on
# an awk that already prints 0 from END, `|| value=""` on an assignment that is
# empty anyway. Two were real gaps.

# Resurrect passes the candidate path as $1. Nothing guarantees it is there:
# a hook fired with no argument, or after the file has been moved.
W="$TEST_TMP/nocand"
fresh "$W"
before="$(readlink "$W/last")"
PATH="$STUB:$PATH" "$GUARD" >/dev/null 2>&1
assert "no argument at all: exits 0 rather than acting on nothing" [ "$?" -eq 0 ]
PATH="$STUB:$PATH" "$GUARD" "$W/tmux_resurrect_29991231T235959.txt" >/dev/null 2>&1
assert "a candidate that does not exist: exits 0" [ "$?" -eq 0 ]
assert "'last' is untouched by either" [ "$(readlink "$W/last")" = "$before" ]
refute "and nothing was written to the status line" \
  contains "$(cat "$TESTLOG" 2>/dev/null)" "resurrect guard"

echo
echo "== notify off: the veto still happens, it just says nothing =="
# @resurrect-guard-notify off is a real setting and had never been exercised.
# The failure it protects against is the opposite of loud — but a veto that
# stopped happening because notification was disabled would be far worse, so
# both halves are asserted.
W="$TEST_TMP/quiet"
fresh "$W"
cand="$W/tmux_resurrect_20200101T060000.txt"
make_save "$cand" 1 1
GOPT_RESURRECT_GUARD_NOTIFY=off PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
assert "the degenerate save was still vetoed" cmp -s "$cand" "$W/last"
assert "and the reason is still in the log, where it can be found later" \
  contains "$(cat "$W/guard.log" 2>/dev/null)" "VETO"
refute "but nothing reached the status line" \
  contains "$(cat "$TESTLOG" 2>/dev/null)" "resurrect guard"

finish
