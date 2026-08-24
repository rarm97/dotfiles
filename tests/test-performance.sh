#!/usr/bin/env bash
# Startup cost, measured and guarded.
#
# Slow is a silent failure: no error, nothing to grep for, just "things feel a
# bit sluggish" — which is how the .zshrc completion-cache bug survived months.
#
# AN HONEST NOTE ON WHAT THAT BUG ACTUALLY COST. This suite was written on the
# premise that it made every shell 3x slower. Measured properly, it did not.
# A/B on this machine, 15 runs each after a warm-up:
#
#   compinit -C (cached, current)   72ms
#   always full compinit            80ms
#   no compinit at all              59ms
#
# So the fix is worth ~8ms per shell. The 210ms figure that justified this suite
# came from a profiling run where ZDOTDIR was redirected, which changed fpath and
# forced a dump rebuild — an artifact of the measurement, not the bug. The
# original fix was still right (a cache that is never revalidated goes stale and
# the security check never runs), but it was never a performance story and this
# file should not pretend otherwise.
#
# The thresholds below therefore guard against something else: a change that
# makes startup several times more expensive — an eagerly loaded plugin, nvm
# loading at startup rather than on first use, a network call in the prompt.
# That class is real, and nothing here would currently notice it.
#
# WHY THE WARM PATH. compinit rebuilds its dump once a day by design, and that
# rebuild is genuinely expensive. Timing a cold shell would fire once every
# morning and be right for the wrong reason, so every measurement warms up first
# and then times the steady state.
#
# The numbers are printed whether or not they pass, so a slow creep is visible
# long before it trips anything.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: repeats an expensive command many times, and runs the fast
# suite itself. `tests/run.sh --fast` skips these, and so does the pre-push
# hook; CI runs the complete set.
# shellcheck disable=SC2034  # read by run.sh with grep, not by this shell
SUITE_SLOW=1

RUNS=15

# Median of RUNS timings, in milliseconds, after a discarded warm-up.
# Median rather than mean: one scheduler hiccup should not move the number, and
# on a shared CI runner there will be hiccups.
measure() { # $@ = command to time
  RUNS="$RUNS" python3 - "$@" <<'MEASURE_EOF'
import os, subprocess, sys, time, statistics
cmd = sys.argv[1:]
subprocess.run(cmd, capture_output=True)  # warm-up, discarded
xs = []
for _ in range(int(os.environ["RUNS"])):
    t0 = time.time()
    subprocess.run(cmd, capture_output=True)
    xs.append((time.time() - t0) * 1000)
print("%d %d %d" % (statistics.median(xs), min(xs), max(xs)))
MEASURE_EOF
}

report() { # $1 = label, $2 = median, $3 = min, $4 = max, $5 = threshold
  printf '    %-22s median %4sms   (min %s, max %s, threshold %s)\n' "$1" "$2" "$3" "$4" "$5"
}

echo "== zsh interactive startup =="
# Threshold reasoning, not taste: the steady-state median here is ~70ms with a
# tight spread (stdev ~5ms), and the floor with no compinit at all is 59ms, so
# there is little room to improve. 250ms is roughly 3.5x the median: loose
# enough that a loaded CI runner will not flake, tight enough that anything
# making startup several times dearer trips it.
ZSH_THRESHOLD_MS=250
if command -v zsh >/dev/null 2>&1; then
  read -r med lo hi <<<"$(measure zsh -i -c exit)"
  report "zsh -i -c exit" "$med" "$lo" "$hi" "$ZSH_THRESHOLD_MS"
  if [ "${med:-9999}" -lt "$ZSH_THRESHOLD_MS" ]; then
    ok "zsh starts in ${med}ms, under the ${ZSH_THRESHOLD_MS}ms ceiling"
  else
    no "zsh starts in ${med}ms, over the ${ZSH_THRESHOLD_MS}ms ceiling"
    # A threshold that fires without saying WHERE the time went only tells you
    # something got slower. zprof names the culprit.
    echo "    where the time goes:"
    P="$TEST_TMP/zprof"
    mkdir -p "$P"
    {
      echo 'zmodload zsh/zprof'
      cat "$REPO_ROOT/zsh/.zshrc"
      echo 'zprof | head -6'
    } >"$P/.zshrc"
    ZDOTDIR="$P" zsh -i -c exit 2>/dev/null | sed -n '3,7p' | sed 's/^/      /'
  fi
else
  printf '  \033[33mSKIP\033[0m  zsh is not installed\n'
fi

echo
echo "== neovim startup =="
# Steady-state median here is ~40ms with a stdev near 1ms — the tightest number
# in the repo. 250ms is ~6x that: generous for a slower machine, and still well
# under what a newly eager plugin or a synchronous plugin install would cost.
NVIM_THRESHOLD_MS=250
if command -v nvim >/dev/null 2>&1; then
  read -r med lo hi <<<"$(measure nvim --headless +qa)"
  report "nvim --headless +qa" "$med" "$lo" "$hi" "$NVIM_THRESHOLD_MS"
  if [ "${med:-9999}" -lt "$NVIM_THRESHOLD_MS" ]; then
    ok "nvim starts in ${med}ms, under the ${NVIM_THRESHOLD_MS}ms ceiling"
  else
    no "nvim starts in ${med}ms, over the ${NVIM_THRESHOLD_MS}ms ceiling"
    echo "    plugins loaded at startup:"
    nvim --headless -c 'lua local s = require("lazy").stats(); print(string.format("      %d of %d eager", s.loaded, s.count))' -c qa 2>&1 | tail -1
  fi
else
  printf '  \033[33mSKIP\033[0m  nvim is not installed\n'
fi

echo
echo "== which plugins load eagerly, by name =="
# Time is the WRONG signal for this and the mutation proved it: making telescope
# eager cost 7ms, invisible against a 250ms ceiling, and a ceiling tight enough
# to see it would flake on any loaded machine. The eager SET is deterministic,
# so assert that instead. Adding an eager plugin is then loud and named, which
# is what was actually wanted.
#
# rose-pine must be eager — a colorscheme that loads late means an unstyled
# flash. lazy.nvim is the loader itself. nvim-cmp and its two sources, and 99,
# declare no lazy trigger; that is a choice worth seeing rather than a bug, and
# if it changes this assertion says so.
EXPECTED_EAGER="99 cmp-buffer cmp-path lazy.nvim nvim-cmp rose-pine"
if command -v nvim >/dev/null 2>&1; then
  actual="$(nvim --headless \
    -c 'lua local p = require("lazy.core.config").plugins; local n = {}; for k, v in pairs(p) do if v._.loaded then n[#n + 1] = k end end; table.sort(n); print("EAGER:" .. table.concat(n, " "))' \
    -c qa 2>&1 | grep -ao 'EAGER:.*' | head -1 | cut -d: -f2-)"
  printf '    %s\n' "${actual:-(none reported)}"
  assert "the set of eagerly loaded plugins is exactly what is expected" \
    [ "$actual" = "$EXPECTED_EAGER" ]
fi

echo
echo "== the completion dump is not rebuilt on every shell =="
# Narrower than it first looked. Reintroducing the original bug did NOT trip
# this, because plain `compinit` only redumps when the dump is actually stale —
# so this catches a rebuild-every-time regression and nothing subtler. The
# BRANCH logic (which of compinit / compinit -C runs, and when) is asserted
# directly in test-zshrc.sh, which is the right place for it; duplicating it
# weakly here would just look like more coverage than there is.
if command -v zsh >/dev/null 2>&1; then
  P="$TEST_TMP/zprof2"
  mkdir -p "$P"
  {
    echo 'zmodload zsh/zprof'
    cat "$REPO_ROOT/zsh/.zshrc"
    echo 'zprof | head -8'
  } >"$P/.zshrc"
  ZDOTDIR="$P" zsh -i -c exit >/dev/null 2>&1 # warm: let it settle the dump
  prof="$(ZDOTDIR="$P" zsh -i -c exit 2>/dev/null)"
  refute "a warm shell does not rebuild the completion dump" contains "$prof" "compdump"
fi

echo
echo "== the pre-push hook stays fast enough to leave switched on =="
# The reason this is measured rather than asserted by comment: the header of
# .githooks/pre-push claimed ~19s for long enough that it became untrue by a
# factor of twelve. The full suite had grown to just over four minutes, which is
# a hook people pass --no-verify to, and a hook that is routinely bypassed is
# worse than none because it still looks like coverage.
#
# So the hook runs --fast, and this keeps that honest. Safe to invoke from here
# and nowhere else: this suite is SUITE_SLOW, so --fast excludes it and the
# nested run cannot re-enter itself.
#
# A minute is the ceiling rather than anything near the measured run, because
# the point is to catch the hook becoming something you avoid, not to fail on a
# busy machine. The measured figure is printed on the line below whether it
# passes or not, which is the only place such a number stays true — writing it
# into this comment is how .githooks/pre-push came to argue from a number that
# was wrong by an order of magnitude.
HOOK_CEILING_S=60
start="$(date +%s)"
"$REPO_ROOT/tests/run.sh" --fast >/dev/null 2>&1
elapsed=$(($(date +%s) - start))
printf '    %-22s %ss   (ceiling %ss)\n' "run.sh --fast" "$elapsed" "$HOOK_CEILING_S"
if [ "$elapsed" -lt "$HOOK_CEILING_S" ]; then
  ok "the pre-push suite runs in ${elapsed}s, fast enough to leave enabled"
else
  no "the pre-push suite takes ${elapsed}s — long enough that it will get bypassed"
  echo "    slowest suites in the fast set:"
  "$REPO_ROOT/tests/run.sh" --fast 2>&1 | grep -B1 '([0-9][0-9]*s)' | tail -6 | sed 's/^/      /'
fi

finish
