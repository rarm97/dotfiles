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

# Bow out of a whole suite because its prerequisite is genuinely absent — not
# because something failed. Prints a marker run.sh recognises, so a deliberate
# skip is never mistaken for a suite that died partway through. Those two look
# identical from the outside otherwise, and CI proved it: test-integration
# skipped for want of tmux-resurrect and was reported as a failure.
skip_suite() {
  printf '  \033[33mSKIP\033[0m  %s\n' "$1"
  printf '\n  suite skipped\n'
  exit 0
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

# make_save_sessions <path> <name:count> [<name:count> ...]
# Explicit per-session sizes, for the cases make_save's round-robin cannot
# express — e.g. one session losing four windows while the rest are untouched.
make_save_sessions() {
  local path="$1"
  shift
  local spec name count i
  NONCE=$((NONCE + 1))
  : >"$path"
  for spec in "$@"; do
    name="${spec%%:*}"
    count="${spec##*:}"
    for ((i = 1; i <= count; i++)); do
      printf 'pane\t%s\t%d\t1\t:*\t1\thost\t:/tmp\t1\tzsh\t:\n' "$name" "$i" >>"$path"
    done
  done
  for spec in "$@"; do
    name="${spec%%:*}"
    count="${spec##*:}"
    for ((i = 1; i <= count; i++)); do
      printf 'window\t%s\t%d\t:zsh\t1\t:*\t%04x,80x23,0,0,%d\t:\n' \
        "$name" "$i" "$((NONCE * 256 + i))" "$i" >>"$path"
    done
  done
  printf 'state\t%s\t%s\n' "${1%%:*}" "${1%%:*}" >>"$path"
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

# Run a command with a REAL tmux client attached on a pseudo-terminal.
#
# Several things are only reachable through an attached client: switch-client
# (which is how tmux-resurrect restores active windows), key bindings, and
# anything drawn on the status line. A CLI invocation of tmux has no client, so
# those paths silently do nothing — which is how "restore does not bring back
# the active window" looked like an upstream bug when it was really the test
# environment.
#
# Attaches to $1, waits until tmux itself reports the client, runs the rest of
# the arguments, then lets the client go. Returns non-zero without running
# anything if the client never attaches, rather than proceeding as if it had.
with_pty_client() { # $1 = session to attach to, $2... = command to run
  local session="$1"
  shift
  local helper="$REPO_ROOT/tests/helpers/pty-client.py"
  [ -f "$helper" ] || {
    echo "  with_pty_client: $helper is missing" >&2
    return 1
  }
  python3 "$helper" "$TMUX_SOCK" "$session" --hold 25 >/dev/null 2>&1 &
  local helper_pid=$!
  local i=0
  while [ "$(tmux -L "$TMUX_SOCK" list-clients 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && {
      kill "$helper_pid" 2>/dev/null
      echo "  with_pty_client: no client attached" >&2
      return 1
    }
    sleep 0.25
  done
  "$@"
  local rc=$?
  kill "$helper_pid" 2>/dev/null
  wait "$helper_pid" 2>/dev/null
  return "$rc"
}

# Attach a client and PRESS keys, as a person would.
#
# Not `tmux send-keys`: that writes to the pane's pty, which is input to the
# program running there. tmux never sees it as a keypress, so a key binding
# never fires. This writes to the pty MASTER instead, which is the client's
# input, and is the only way to exercise a binding as a binding.
#
# Blocks until the presses are done and the client has gone.
press_keys() { # $1 = session to attach to, $2... = keys, e.g. C-a Q
  local session="$1"
  shift
  local helper="$REPO_ROOT/tests/helpers/pty-client.py"
  [ -f "$helper" ] || {
    echo "  press_keys: $helper is missing" >&2
    return 1
  }
  python3 "$helper" "$TMUX_SOCK" "$session" --press "$@" --hold 2 >/dev/null 2>&1
}

# press_keys, but return what the client's terminal actually displayed.
#
# This is the only honest way to assert on a status-line message: it is what a
# person sitting at the terminal would have seen. `tmux show-messages` returns
# the server's command log instead, which is why an earlier attempt could only
# check that display-message had been called, not what it said.
press_keys_capture() { # $1 = session, $2... = keys
  local session="$1"
  shift
  python3 "$REPO_ROOT/tests/helpers/pty-client.py" \
    "$TMUX_SOCK" "$session" --press "$@" --hold 4 --capture 2>/dev/null
}

# Standard teardown for a suite that starts a private tmux server: kill it,
# remove the socket file tmux leaves behind, then clear the scratch dir. Suites
# with extra cleanup of their own wrap this rather than reimplementing it.
cleanup_tmux_suite() {
  tmux_test_teardown
  cleanup_common
}

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
