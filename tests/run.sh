#!/usr/bin/env bash
# Run every test-*.sh in this directory and summarise.
#
# Exits non-zero if any suite fails, so `make test` and any future CI both see
# it. A test runner that always exits 0 is the thing it is supposed to prevent.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

suites=0
failed=0
skipped=0
names=""

for suite in test-*.sh; do
  [ -f "$suite" ] || continue
  suites=$((suites + 1))
  printf '\n\033[1m=== %s ===\033[0m\n' "$suite"
  out="$(bash "$suite" 2>&1)"
  rc=$?
  printf '%s\n' "$out"
  # A suite that dies partway through prints no summary line, and without this
  # check that is indistinguishable from one that finished. It happened: sourcing
  # bootstrap.sh imported its `set -e`, the first failing assertion aborted the
  # run, and the output simply stopped looking perfectly normal.
  case "$out" in
    *"passed,"*) : ;;
    # A suite may bow out because its prerequisite is genuinely missing (CI has
    # no tmux-resurrect, for instance). That is not a failure, but it must be
    # SAID — silence is what this check exists to catch.
    *"suite skipped"*)
      skipped=$((skipped + 1))
      ;;
    *)
      printf '  \033[31mFAIL\033[0m  %s produced no summary — it exited early\n' "$suite"
      rc=1
      ;;
  esac
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    names="$names $suite"
  fi
done

printf '\n\033[1m=== summary ===\033[0m\n'
if [ "$suites" -eq 0 ]; then
  echo "  no suites found — that is a failure, not a pass"
  exit 1
fi
if [ "$failed" -eq 0 ]; then
  if [ "$skipped" -gt 0 ]; then
    printf '  %d suite(s), all passing (%d skipped for missing prerequisites)\n' "$suites" "$skipped"
  else
    printf '  %d suite(s), all passing\n' "$suites"
  fi
  exit 0
fi
printf '  %d of %d suite(s) FAILED:%s\n' "$failed" "$suites" "$names"
exit 1
