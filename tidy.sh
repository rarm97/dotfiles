#!/usr/bin/env bash
#
# tidy.sh [--apply] — report, or clean up, the cruft this setup accumulates.
#
# Four things pile up here and none of them announce themselves: tmux-resurrect
# saves (one every 15 minutes), 99-plugin scratch files (its tmp_dir is relative
# to the cwd, so they land in whatever project you were editing), the nvim LSP
# log, and branches already merged into main.
#
# Without --apply nothing is deleted. That is the default on purpose: running
# the wrong one by accident should cost nothing.
#
# WHY THIS IS A SCRIPT AND NOT A MAKEFILE RECIPE
#   It used to be two recipes of backslash-continued shell. They drifted — the
#   report and the delete ended up using different find expressions, so what was
#   listed was not what was removed. Worse, each step reported success
#   unconditionally:
#     * `find -print -delete` prints BEFORE deleting, so a file that could not
#       be removed was still announced as removed.
#     * `: > "$log"` failing still reached the `echo "truncated"` after it.
#     * `git branch -d "$b" | sed ...` swallowed the exit status in the pipe.
#     * and the whole thing exited 0 no matter what, so a wrapper could not tell.
#   Every action below is now verified after the fact, and anything that did not
#   actually happen is reported as a failure and sets the exit status.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

failures=0
note() { printf '    %s\n' "$*"; }
did() { printf '    %s\n' "$*"; }
failed() {
  printf '    FAILED: %s\n' "$*" >&2
  failures=$((failures + 1))
}

# One expression, used by both modes. When the report and the action can
# disagree, sooner or later they will.
scratch_files() {
  find . -maxdepth 2 -name '99-*' -mtime +7 -not -path './.git/*' 2>/dev/null
}

LSP_LOG="$HOME/.local/state/nvim/lsp.log"

# Branches fully merged into main, excluding main and whatever is checked out.
# `git branch` marks the current branch with '*', and a detached HEAD as
# '* (HEAD detached...)', so the same filter covers both.
merged_branches() {
  git branch --merged main 2>/dev/null | grep -vE '^\*|^[[:space:]]*main$' || true
}

# ---------------------------------------------------------------- saves

echo "==> tmux-resurrect saves"
if command -v tmux-resurrect-saves >/dev/null 2>&1; then
  if [ "$APPLY" -eq 1 ]; then
    if out="$(tmux-resurrect-saves prune --apply 2>&1)"; then
      printf '%s\n' "$out" | tail -2 | sed 's/^/    /'
    else
      printf '%s\n' "$out" | tail -3 | sed 's/^/    /'
      failed "pruning saves"
    fi
  else
    tmux-resurrect-saves prune | tail -3 | sed 's/^/    /'
  fi
else
  note "tmux-resurrect-saves not on PATH (run make stow)"
fi

# ---------------------------------------------------------------- scratch files

echo
echo "==> nvim 99-plugin scratch files (its tmp_dir is relative to the cwd)"
found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  found=$((found + 1))
  if [ "$APPLY" -eq 0 ]; then
    note "stale: $f"
    continue
  fi
  # Delete, then CHECK. `find -print -delete` prints first and so reports files
  # it then fails to remove.
  if rm -f "$f" 2>/dev/null && [ ! -e "$f" ]; then
    did "removed $f"
  else
    failed "could not remove $f"
  fi
done < <(scratch_files)
[ "$found" -eq 0 ] && note "none older than 7 days"

# ---------------------------------------------------------------- lsp log

echo
echo "==> nvim LSP log"
if [ -f "$LSP_LOG" ]; then
  du -h "$LSP_LOG" | sed 's/^/    /'
  if [ "$APPLY" -eq 1 ]; then
    # Truncated rather than deleted: nvim holds the file open, so unlinking it
    # frees nothing until nvim exits.
    if : >"$LSP_LOG" 2>/dev/null && [ ! -s "$LSP_LOG" ]; then
      did "truncated"
    else
      failed "could not truncate $LSP_LOG"
    fi
  fi
else
  note "none"
fi

# ---------------------------------------------------------------- branches

echo
echo "==> git branches already merged into main"
found=0
while IFS= read -r b; do
  b="$(printf '%s' "$b" | tr -d '[:space:]')"
  [ -n "$b" ] || continue
  found=$((found + 1))
  if [ "$APPLY" -eq 0 ]; then
    note "$b"
    continue
  fi
  # No pipe here: piping git's output into sed hid its exit status, so a branch
  # that could not be deleted was skipped in silence.
  if git branch -d "$b" >/dev/null 2>&1; then
    did "deleted $b"
  else
    failed "could not delete branch $b"
  fi
done < <(merged_branches)
[ "$found" -eq 0 ] && note "none"

# ---------------------------------------------------------------- uncommitted

echo
echo "==> uncommitted work"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git status --short | sed 's/^/    /'
  [ "$APPLY" -eq 1 ] && note "(left alone on purpose - that needs reading, not automating)"
else
  note "working tree clean"
fi

# ---------------------------------------------------------------- summary

echo
if [ "$APPLY" -eq 0 ]; then
  echo "Nothing was deleted. Run 'make tidy-apply' to act on the above."
  exit 0
fi
if [ "$failures" -gt 0 ]; then
  printf '%d action(s) FAILED — see above.\n' "$failures" >&2
  exit 1
fi
echo "Done."
