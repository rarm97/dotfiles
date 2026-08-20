#!/usr/bin/env bash
# Shared reporting for the check scripts.
#
# ok / bad / meh all write to stdout and keep counters; a "bad" is what makes
# the run exit non-zero. meh is for things worth knowing that are not broken —
# it must never fail the run, or people learn to ignore the output.

ok() {
  printf '  \033[32m✓\033[0m %s\n' "$1"
  pass=$((pass + 1))
}
bad() {
  printf '  \033[31m✗\033[0m %s\n' "$1"
  fail=$((fail + 1))
}
meh() {
  printf '  \033[33m!\033[0m %s\n' "$1"
  warn=$((warn + 1))
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
