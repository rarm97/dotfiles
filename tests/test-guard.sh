#!/usr/bin/env bash
# tmux-resurrect-guard decision matrix.
#
# Uses a stubbed tmux so every option combination can be driven directly, and
# reimplements the part of resurrect's save_all() that the guard interacts with:
#
#     execute_hook "post-save-layout" "$candidate"
#     if files_differ "$candidate" "$dir/last"; then ln -fs ... ; else rm ...; fi
#
# files_differ is `! cmp -s`, so "the guard vetoed" is observable as "resurrect
# would have deleted the candidate and left last alone".

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GUARD="$BIN/tmux-resurrect-guard"
STUB="$TEST_TMP/stub"
WORK="$TEST_TMP/work"
make_tmux_stub "$STUB"

export GOPT_RESURRECT_GUARD=on
export GOPT_RESURRECT_GUARD_MIN_WINDOWS=2
export GOPT_RESURRECT_GUARD_COLLAPSE_PCT=50
export GOPT_RESURRECT_GUARD_NOTIFY=on
export GOPT_RESURRECT_GUARD_FORCE=off
export GOPT_RESURRECT_GUARD_ANNOUNCE=off

reset_work() {
  rm -rf "$WORK"
  mkdir -p "$WORK"
  export TESTLOG="$WORK/display.log"
  : >"$TESTLOG"
  rm -f "${TMPDIR:-/tmp}/tmux-resurrect-guard-$(id -u).pending"
}

seed_last() { # $1=windows $2=sessions
  local f="$WORK/tmux_resurrect_20200101T000000.txt"
  make_save "$f" "$1" "$2"
  ln -sfn "$(basename "$f")" "$WORK/last"
}

# Returns 0 if the save was accepted (last moved), 1 if vetoed.
simulate_save() { # $1=windows $2=sessions
  local cand
  cand="$WORK/tmux_resurrect_$(date +%Y%m%d)T$(printf '%06d' $((NONCE + 1))).txt"
  make_save "$cand" "$1" "$2"
  PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
  if ! cmp -s "$cand" "$WORK/last"; then
    ln -sfn "$(basename "$cand")" "$WORK/last"
    return 0
  fi
  rm -f "$cand"
  return 1
}

last_msg() { grep DISPLAY "$TESTLOG" 2>/dev/null | tail -1; }

msg_check() { # $1=desc $2=must-match $3=must-NOT-match
  local got
  got="$(last_msg)"
  if contains "$got" "$2" && ! contains "$got" "$3"; then
    ok "$1"
  else
    no "$1 -> ${got:-(nothing)}"
  fi
}

echo "== bootstrap and self-healing =="
reset_work
simulate_save 1 1
check "no 'last' yet: a degenerate save is allowed (bootstrap)" accept $?

reset_work
seed_last 1 1
simulate_save 15 3
check "a degenerate 'last' is replaced by a healthy save (self-heal)" accept $?

reset_work
seed_last 1 1
simulate_save 1 1
check "degenerate 'last' + degenerate save: not wedged" accept $?

reset_work
seed_last 15 3
rm -f "$WORK"/tmux_resurrect_20200101T000000.txt
simulate_save 1 1
check "dangling 'last': save allowed" accept $?

echo
echo "== rule 1: absolute floor =="
reset_work
seed_last 15 3
simulate_save 1 1
check "the reported bug: a 1-window state cannot clobber a 15-window 'last'" veto $?
assert "'last' still points at the good save" \
  [ "$(readlink "$WORK/last")" = "tmux_resurrect_20200101T000000.txt" ]
assert "the vetoed candidate left no file behind" \
  [ "$(find "$WORK" -name 'tmux_resurrect_*' | wc -l | tr -d ' ')" = "1" ]
assert "the veto was reported to the status line" grep -q DISPLAY "$TESTLOG"
assert "the veto was logged" [ -s "$WORK/guard.log" ]

reset_work
seed_last 15 3
simulate_save 2 1
check "2 windows clears the floor but is still caught by rule 2" veto $?

echo
echo "== rule 2: collapse needs a second sighting =="
reset_work
seed_last 15 3
simulate_save 5 2
check "first collapse 15->5 is held" veto $?
simulate_save 5 2
check "the same collapse repeated is accepted" accept $?

reset_work
seed_last 15 3
simulate_save 5 2
check "collapse held" veto $?
simulate_save 15 3
check "a healthy save in between is accepted" accept $?
simulate_save 5 2
check "the healthy save reset the hold, so it holds again" veto $?

reset_work
seed_last 15 3
simulate_save 5 2
check "collapse held" veto $?
touch -t 202001010000 "$WORK/.guard-state"
simulate_save 5 2
check "a hold older than an hour is not confirmation" veto $?

reset_work
seed_last 15 3
simulate_save 5 2
check "collapse held" veto $?
printf 'some_other_save.txt 5\n' >"$WORK/.guard-state"
simulate_save 5 2
check "a hold recorded against a different 'last' is not confirmation" veto $?

reset_work
seed_last 15 3
simulate_save 6 2
check "collapse to 6 held" veto $?
simulate_save 3 1
check "still shrinking (6->3) is re-held, not confirmed" veto $?
simulate_save 3 1
check "once it stops shrinking, the next save confirms" accept $?

reset_work
seed_last 15 3
simulate_save 12 3
check "12/15 overall with every session above 50%: accepted, no hold" accept $?

reset_work
seed_last 15 3
simulate_save 8 3
check "8/15 overall looks fine, but one session drops 5->2, so it is held" veto $?

echo
echo "== rule 2 also watches each session on its own =="
# The incident this rule exists for: 16 -> 12 windows overall (75% of former
# size, comfortably inside the total threshold) while marking_gpt went 5 -> 1.
# Counting only the total could not see it.
seed_incident() {
  make_save_sessions "$WORK/tmux_resurrect_20200101T000000.txt" \
    "Apodosis:2" "Dotfiles:1" "FBScraping:5" "gloryandgains:3" "marking_gpt:5"
  ln -sfn tmux_resurrect_20200101T000000.txt "$WORK/last"
}
save_sessions() {
  local cand
  cand="$WORK/tmux_resurrect_20260101T$(printf '%06d' $((NONCE + 1))).txt"
  make_save_sessions "$cand" "$@"
  PATH="$STUB:$PATH" "$GUARD" "$cand" >/dev/null 2>&1
  if ! cmp -s "$cand" "$WORK/last"; then
    ln -sfn "$(basename "$cand")" "$WORK/last"
    return 0
  fi
  rm -f "$cand"
  return 1
}

reset_work
seed_incident
save_sessions "Apodosis:2" "Dotfiles:1" "FBScraping:5" "gloryandgains:3" "marking_gpt:1"
check "the real incident (16->12 total, one session 5->1) is now held" veto $?

reset_work
seed_incident
save_sessions "Apodosis:2" "Dotfiles:1" "FBScraping:5" "gloryandgains:3" "marking_gpt:1"
check "held once" veto $?
save_sessions "Apodosis:2" "Dotfiles:1" "FBScraping:5" "gloryandgains:3" "marking_gpt:1"
check "...and accepted when it persists, so a real downsizing is not frozen" accept $?

reset_work
seed_incident
save_sessions "Apodosis:2" "Dotfiles:1" "FBScraping:4" "gloryandgains:3" "marking_gpt:4"
check "ordinary window churn across sessions is not held" accept $?

reset_work
seed_incident
save_sessions "Apodosis:2" "Dotfiles:1" "FBScraping:5" "gloryandgains:3"
check "a session vanishing entirely is held" veto $?

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_COLLAPSE_PCT=0 simulate_save 5 2
check "collapse-pct=0 disables rule 2" accept $?

echo
echo "== switches and bad input =="
reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD=off simulate_save 1 1
check "master switch off: the guard is inert" accept $?

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_FORCE=on simulate_save 1 1
check "the force flag bypasses the guard" accept $?

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_MIN_WINDOWS=not_a_number simulate_save 1 1
check "a non-numeric min-windows falls back to the default" veto $?

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_COLLAPSE_PCT=abc simulate_save 5 2
check "a non-numeric collapse-pct falls back to the default" veto $?

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD=off GOPT_RESURRECT_GUARD_FORCE=on simulate_save 1 1 >/dev/null
assert "the force flag is consumed even with the master switch off" \
  grep -q 'UNSET @resurrect-guard-force' "$TESTLOG"

reset_work
seed_last 15 3
simulate_save 5 2 >/dev/null
GOPT_RESURRECT_GUARD=off simulate_save 15 3 >/dev/null
assert "disarming clears a stale hold" [ ! -f "$WORK/.guard-state" ]

echo
echo "== what the status line actually says =="
reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_ANNOUNCE=on simulate_save 15 3 >/dev/null
msg_check "a hand-triggered save that succeeded says so" "saved" "refused"

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_ANNOUNCE=on simulate_save 1 1 >/dev/null
msg_check "a hand-triggered save that was VETOED must not claim success" "refused" "saved —"

reset_work
seed_last 15 3
GOPT_RESURRECT_GUARD_ANNOUNCE=on GOPT_RESURRECT_GUARD=off simulate_save 1 1 >/dev/null
msg_check "with the guard off it says saved, and says the guard was off" "guard off" "refused"

reset_work
seed_last 15 3
simulate_save 15 3 >/dev/null
refute "an allowed timed save says nothing at all" grep -q DISPLAY "$TESTLOG"

reset_work
seed_last 15 3
simulate_save 1 1 >/dev/null
msg_check "a vetoed timed save still speaks up" "refused" "zzz-never-matches"

finish
