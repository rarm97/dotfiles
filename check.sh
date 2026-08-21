#!/usr/bin/env bash
#
# check.sh [--repo-only] — assert the things this setup quietly assumes.
#
# `make check` used to print tool versions. That is an inventory, not a check:
# it tells you what is installed, never that something is wrong. Every assertion
# behind this corresponds to a defect that was live in this repo for weeks or
# months without producing a single symptom — a colour scheme name that silently
# fell back, a linter that silently never ran, a completion cache that was never
# used, an ignore rule that never matched. As assertions they cost two seconds.
#
# The rule this exists to enforce: if it can be wrong without saying so, it is
# not finished.
#
# TWO HALVES, deliberately separate:
#
#   checks/repo.sh     is this REPOSITORY internally consistent? Holds on any
#                      machine with git and the usual text tools, so CI can run
#                      it.
#   checks/machine.sh  is THIS machine set up the way the repo assumes? Needs
#                      WezTerm, fonts, a stow tree and a git identity, none of
#                      which exist on a CI runner.
#
# --repo-only runs just the first, which is what CI uses. Keeping them apart
# matters: a check that cannot pass in CI ends up disabled, and a disabled check
# is worse than no check because it still looks like coverage.
#
# Exits non-zero if anything FAILs, so it is usable from a hook or CI. WARNs do
# not fail the run — they are things worth knowing, not broken things.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

REPO_ONLY=0
[ "${1:-}" = "--repo-only" ] && REPO_ONLY=1

pass=0
warn=0
fail=0
export pass warn fail

# Each half is sourced rather than executed so its counters land here.
#
# Guarded, because a missing half is the worst failure this script can have.
# `.` on a file that is not there prints one line to stderr and CARRIES ON:
# without this, deleting checks/repo.sh made check.sh report "0 ok, 0
# warning(s), 0 failure(s)" and exit 0. CI passes, the pre-commit hook passes,
# and the entire safety net has quietly gone. Verified before fixing.
run_half() {
  [ -r "$1" ] || {
    printf '\033[31mcheck.sh: cannot read %s — the checks did not run\033[0m\n' "$1" >&2
    exit 1
  }
  # shellcheck source=/dev/null
  . "$1"
}

run_half ./checks/repo.sh

if [ "$REPO_ONLY" -eq 0 ]; then
  run_half ./checks/machine.sh
fi

# And a half that exists but asserts nothing is the same failure wearing a
# better disguise — a truncated file, a syntax error partway through, an early
# return. A run that checked nothing is not a pass.
if [ "$((pass + warn + fail))" -eq 0 ]; then
  printf '\033[31mcheck.sh: no checks ran at all\033[0m\n' >&2
  exit 1
fi

printf '\n\033[1mSummary\033[0m\n'
if [ "$REPO_ONLY" -eq 1 ]; then
  printf '  repository checks only (--repo-only)\n'
fi
printf '  %d ok, %d warning(s), %d failure(s)\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
