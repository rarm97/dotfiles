#!/usr/bin/env bash
# tmux-resurrect-saves: prune and promote.
#
# This tool DELETES files, so the bar here is data loss, not tidiness. Every
# case below corresponds to a way it once deleted, or would have deleted,
# something it should have kept.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TOOL="$BIN/tmux-resurrect-saves"
W="$TEST_TMP/saves"

# Build a save and back-date it to match its own filename stamp, so the age
# tiers and the in-flight guard both see what the name claims.
mk() { # $1=stamp $2=windows
  local f="$W/tmux_resurrect_$1.txt"
  make_save "$f" "$2" 3
  touch -t "$(printf '%s' "$1" | sed 's/T\(..\)\(..\).*/\1\2/')" "$f" 2>/dev/null
}

reset() {
  rm -rf "$W"
  mkdir -p "$W"
}
run() { RESURRECT_DIR="$W" KEEP_ALL_DAYS="${KA:-7}" KEEP_DAILY_DAYS="${KD:-90}" "$TOOL" "$@"; }
have() { [ -f "$W/tmux_resurrect_$1.txt" ]; }

echo "== a day whose LAST save is degenerate must not lose the whole day =="
# The obvious "keep it if the next save is a different day" rule fails here: the
# day's final real save is marked superseded by a degenerate one that is then
# deleted, and the entire day disappears. Reproduced against real data.
reset
mk 20260804T082917 13
mk 20260804T084417 13
mk 20260804T085917 13
mk 20260804T185859 1
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
KA=0 run prune --apply >/dev/null 2>&1
assert "the day's last REAL save survives a later degenerate one" have 20260804T085917
refute "the degenerate save is gone" have 20260804T185859
refute "earlier same-day saves are still thinned" have 20260804T082917
refute "...and so is the second" have 20260804T084417

echo
echo "== other retention cases =="
reset
mk 20260701T090000 1
mk 20260701T100000 1
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
KA=0 run prune --apply >/dev/null 2>&1
refute "an all-degenerate day is removed entirely" have 20260701T090000

reset
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
cp "$W/tmux_resurrect_20260805T073237.txt" "$W/tmux_resurrect_before-macos-upgrade.txt"
touch -t 202001010000 "$W/tmux_resurrect_before-macos-upgrade.txt"
KA=0 KD=0 run prune --apply >/dev/null 2>&1
assert "a hand-renamed save is never deleted, however aggressive the policy" \
  [ -f "$W/tmux_resurrect_before-macos-upgrade.txt" ]
assert "list flags it as pinned" bash -c 'RESURRECT_DIR="'"$W"'" "'"$TOOL"'" list | grep -q pinned'

reset
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
# save_all builds a file with one `>` and three `>>`, so a real save on disk
# legitimately has no pane records for a moment. Deleting it there makes save.sh
# recreate a truncated file and point `last` at something unrestorable.
: >"$W/tmux_resurrect_20260805T080000.txt"
KA=0 run prune --apply >/dev/null 2>&1
assert "a save written moments ago is left alone (in-flight save)" have 20260805T080000

reset
mk 20260101T090000 1
ln -sfn tmux_resurrect_20260101T090000.txt "$W/last"
KA=0 KD=0 run prune --apply >/dev/null 2>&1
assert "even a degenerate, ancient 'last' is kept rather than left dangling" have 20260101T090000
assert "...and the symlink still resolves" [ -e "$W/last" ]

reset
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
before="$(find "$W" -name 'tmux_resurrect_*' | wc -l | tr -d ' ')"
run prune >/dev/null 2>&1
assert "a dry run deletes nothing" \
  [ "$(find "$W" -name 'tmux_resurrect_*' | wc -l | tr -d ' ')" = "$before" ]
assert "a dry run says so" bash -c 'RESURRECT_DIR="'"$W"'" "'"$TOOL"'" prune | grep -q "Dry run"'

echo
echo "== prune reports failure rather than claiming success =="
reset
mk 20260101T090000 1
mk 20260805T073237 15
ln -sfn tmux_resurrect_20260805T073237.txt "$W/last"
chmod a-w "$W"
refute "prune exits non-zero when it cannot delete" quietly env KA=0 RESURRECT_DIR="$W" KEEP_ALL_DAYS=0 "$TOOL" prune --apply
chmod u+w "$W"

echo
echo "== promote =="
reset
mk 20260805T073237 15
mk 20260805T080000 1
assert "promote <stamp>" quietly run promote 20260805T073237
assert "promote <filename>" quietly run promote tmux_resurrect_20260805T073237.txt
refute "a degenerate save is refused without --force" quietly run promote 20260805T080000
assert "promote <stamp> --force" quietly run promote 20260805T080000 --force
assert "promote --force <stamp>" quietly run promote --force 20260805T080000
refute "no arguments is rejected" quietly run promote
refute "path traversal is rejected" quietly run promote ../../../etc/passwd

# THE FOOTGUN: `ln -sf target` with no link name creates the link in the cwd,
# named after the target — inside the resurrect dir that overwrites the save
# with a symlink to itself.
run promote 20260805T073237 >/dev/null 2>&1
assert "promote did not turn the save into a self-referential symlink" \
  bash -c '[ -f "'"$W"'/tmux_resurrect_20260805T073237.txt" ] && [ ! -L "'"$W"'/tmux_resurrect_20260805T073237.txt" ]'

# -n covers a symlink-to-directory but NOT a real one: against a real directory
# `ln -sfn x last` creates last/x and still exits 0.
rm -f "$W/last"
mkdir -p "$W/last"
refute "promote refuses when 'last' is a real directory" quietly run promote 20260805T073237
refute "...and creates nothing inside it" [ -f "$W/last/tmux_resurrect_20260805T073237.txt" ]
rmdir "$W/last" 2>/dev/null

finish
