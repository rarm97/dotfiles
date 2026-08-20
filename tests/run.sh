#!/usr/bin/env bash
# Run every test-*.sh in this directory and summarise.
#
# Exits non-zero if any suite fails, so `make test` and any future CI both see
# it. A test runner that always exits 0 is the thing it is supposed to prevent.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

suites=0
failed=0
names=""

for suite in test-*.sh; do
  [ -f "$suite" ] || continue
  suites=$((suites + 1))
  printf '\n\033[1m=== %s ===\033[0m\n' "$suite"
  if bash "$suite"; then :; else
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
  printf '  %d suite(s), all passing\n' "$suites"
  exit 0
fi
printf '  %d of %d suite(s) FAILED:%s\n' "$failed" "$suites" "$names"
exit 1
