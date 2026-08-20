#!/usr/bin/env bash
# Shared helpers for the test suites in this directory.
#
# Written for bash 3.2 (the macOS system bash): no associative arrays, no
# mapfile, no ${var^^}.
#
# SAFETY: every suite that touches tmux MUST use a private socket via
# tmux_test_socket, and every suite that touches a resurrect directory MUST use
# a scratch dir under $TEST_TMP. Nothing here may read or write
# ~/.local/share/tmux/resurrect or talk to the user's live tmux server. A test
# that damages the machine it runs on is worse than no test.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Consumed by the suites that source this file, not by lib.sh itself.
# shellcheck disable=SC2034
BIN="$REPO_ROOT/tmux/.local/bin"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tests.XXXXXX")"

pass=0
fail=0

cleanup_common() { rm -rf "$TEST_TMP"; }
trap cleanup_common EXIT

ok() {
  printf '  \033[32mPASS\033[0m  %s\n' "$1"
  pass=$((pass + 1))
}

no() {
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  fail=$((fail + 1))
}

# check <description> <expected: accept|veto> <actual rc>
check() {
  if { [ "$2" = accept ] && [ "$3" -eq 0 ]; } || { [ "$2" = veto ] && [ "$3" -eq 1 ]; }; then
    ok "$1"
  else
    no "$1 (expected $2)"
  fi
}

# assert <description> <command...> — the command's exit status is the verdict.
# Preferred over `cond && ok "..." || no "..."`: in that form C also runs when A
# is true and B fails, so a broken assertion can report BOTH pass and fail, or
# neither. A test harness that can mis-report defeats its own purpose.
assert() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else no "$desc"; fi
}

# contains <haystack> <needle> — substring test for asserting on captured
# output, so assertions do not need nested bash -c quoting.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

# Run a command with its output suppressed, keeping its exit status. Lets an
# assertion exercise a chatty tool without drowning the report.
quietly() { "$@" >/dev/null 2>&1; }

# refute <description> <command...> — passes when the command FAILS.
refute() {
  local desc="$1"
  shift
  if "$@"; then no "$desc"; else ok "$desc"; fi
}

# Report the suite result. Returns non-zero if anything failed, so the runner
# and CI both see it.
finish() {
  printf '\n  %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------- save files

# Build a synthetic resurrect save with N windows across S sessions.
#
# NONCE varies the layout field on every call because real resurrect saves are
# never byte-identical between runs. Without it cmp reports "identical" and the
# caller mistakes resurrect's no-op branch for a guard veto — a false PASS that
# hid two real bugs the first time these tests were written.
NONCE=0
make_save() { # $1=path $2=windows $3=sessions
  local path="$1" nwin="$2" nsess="$3" i s
  NONCE=$((NONCE + 1))
  : >"$path"
  for ((i = 1; i <= nwin; i++)); do
    s=$(((i - 1) % nsess + 1))
    printf 'pane\tsess%d\t%d\t1\t:*\t1\thost\t:/tmp\t1\tzsh\t:\n' "$s" "$i" >>"$path"
  done
  for ((i = 1; i <= nwin; i++)); do
    s=$(((i - 1) % nsess + 1))
    printf 'window\tsess%d\t%d\t:zsh\t1\t:*\t%04x,80x23,0,0,%d\t:\n' \
      "$s" "$i" "$((NONCE * 256 + i))" "$i" >>"$path"
  done
  printf 'state\tsess1\tsess1\n' >>"$path"
}

windows_in() { awk -F'\t' '$1 == "window" { n++ } END { print n + 0 }' "$1" 2>/dev/null; }
sessions_in() { awk -F'\t' '$1 == "window" && !s[$2]++ { n++ } END { print n + 0 }' "$1" 2>/dev/null; }

# ---------------------------------------------------------------- tmux stub

# A fake `tmux` whose show-option answers come from GOPT_* environment
# variables, so the guard's decision logic can be exercised without a server.
# display-message and set-option calls are appended to $TESTLOG for assertions.
make_tmux_stub() { # $1 = directory to create the stub in
  mkdir -p "$1"
  cat >"$1/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  show-option)
    for a in "$@"; do case "$a" in @*) opt="$a" ;; esac; done
    var="GOPT_$(printf '%s' "$opt" | tr -d '@' | tr 'a-z-' 'A-Z_')"
    eval "printf '%s' \"\${$var:-}\""
    ;;
  set-option) printf 'UNSET %s\n' "$3" >>"${TESTLOG:-/dev/null}" ;;
  display-message) printf 'DISPLAY: %s\n' "$2" >>"${TESTLOG:-/dev/null}" ;;
esac
exit 0
STUB
  chmod +x "$1/tmux"
}

# ---------------------------------------------------------------- real tmux

# A socket name unique to this suite and PID, so concurrent runs and the user's
# live server can never collide.
tmux_test_socket() { printf 'dotfiles-test-%s-%s' "${1:-suite}" "$$"; }

# Refuse to run if the caller has not set a private socket. Cheap insurance
# against a future edit accidentally addressing the default server.
require_private_socket() {
  case "${TMUX_SOCK:-}" in
    dotfiles-test-*) return 0 ;;
    *)
      echo "REFUSING TO RUN: TMUX_SOCK must be a private dotfiles-test-* socket" >&2
      exit 1
      ;;
  esac
}

t() { tmux -L "$TMUX_SOCK" "$@"; }

# Kill the private server AND remove its socket file. tmux leaves the socket
# behind when a server exits, so without this every test run adds another dead
# entry to /tmp/tmux-$UID/ forever.
tmux_test_teardown() {
  [ -n "${TMUX_SOCK:-}" ] || return 0
  tmux -L "$TMUX_SOCK" kill-server 2>/dev/null
  rm -f "${TMPDIR_TMUX:-/private/tmp/tmux-$(id -u)}/$TMUX_SOCK" \
    "/tmp/tmux-$(id -u)/$TMUX_SOCK" 2>/dev/null
  return 0
}
