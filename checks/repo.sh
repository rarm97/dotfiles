#!/usr/bin/env bash
# Assertions about the REPOSITORY, not about the machine it is checked out on.
#
# Everything here holds true on any machine with git and the usual text tools,
# which is what makes it runnable in CI. Anything that asks "is THIS laptop set
# up correctly" belongs in machine.sh instead — CI has no WezTerm, no fonts and
# no stow tree, and a check that cannot pass there would just be turned off.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
REPO="$PWD"
# shellcheck source=/dev/null
. "$REPO/checks/lib.sh"

# ---------------------------------------------------------------- readers
#
# Values live in the file that owns them; these read them back out. An extractor
# that quietly returns nothing turns every comparison below into "" = "", which
# passes while asserting nothing — the shape of the seven assertions in this
# repo that turned out to be incapable of failing. Every caller rejects an empty
# result rather than comparing it.

GUARD="tmux/.local/bin/tmux-resurrect-guard"
SAVES="tmux/.local/bin/tmux-resurrect-saves"
TMUXCONF="tmux/.config/tmux/tmux.conf"
OPTIONS="nvim/.config/nvim/lua/rich/options.lua"

# The value tmux.conf sets an option to:  set -g @option 'value'
tmux_setting() { # $1 = option name
  local line
  line="$(grep -m1 -E "^[[:space:]]*set .*$1 " "$TMUXCONF")"
  line="${line#*\'}"
  printf '%s' "${line%%\'*}"
}

# The V in a shell script's  NAME="${NAME:-V}"
sh_default() { # $1 = file, $2 = variable
  local line
  line="$(grep -m1 -E "^$2=" "$1")"
  case "$line" in
    *":-"*)
      line="${line#*:-}"
      printf '%s' "${line%%\}*}"
      ;;
  esac
}

# The guard's own fallback:  tmux_opt '@option' 'default'
guard_default() { # $1 = option name
  local line
  line="$(grep -m1 -F "tmux_opt '$1'" "$GUARD")"
  line="${line#*\' \'}"
  printf '%s' "${line%%\'*}"
}

# Every key tmux.conf binds. tmux's grammar is `bind [-flags] [-T table] KEY
# command`, so the key is the first argument that is neither a flag nor a flag's
# argument.
tmux_bound_keys() {
  awk '
    /^[[:space:]]*bind(-key)?[[:space:]]/ {
      for (i = 2; i <= NF; i++) {
        if ($i == "-T" || $i == "-t" || $i == "-N") { i++; continue }
        if ($i ~ /^-/) { continue }
        print $i
        break
      }
    }
  ' "$TMUXCONF"
}

# What the guard's header says that fallback is:  @option  ...  (default V)
guard_doc_default() { # $1 = option name
  local line
  line="$(grep -m1 -E "^#[[:space:]]+$1[[:space:]]" "$GUARD")"
  case "$line" in
    *"(default "*)
      line="${line#*\(default }"
      printf '%s' "${line%%\)*}"
      ;;
  esac
}

# The value options.lua assigns an option:  vim.opt.NAME = VALUE  -- comment
nvim_opt() { # $1 = option name
  local line
  line="$(grep -m1 -E "^[[:space:]]*vim\.opt\.$1[[:space:]]*=" "$OPTIONS")"
  line="${line#*=}"
  line="${line%%--*}"
  printf '%s' "$(printf '%s' "$line" | tr -d '[:space:]')"
}

section "Lua config"
# These generalise past whatever anyone has read: a syntax error or a deprecated
# call in a plugin file nobody has opened shows up as "nvim starts a bit oddly".
#
# EVERY tracked lua file, not just nvim's. wezterm.lua is lua too and nothing
# parsed it — a syntax error there makes WezTerm fall back to its built-in
# defaults, which is the same silent-fallback shape as the colour scheme that
# matched nothing. nvim is only the parser here; the files need not be its own.
if command -v nvim >/dev/null 2>&1; then
  lua_files="$(git ls-files '*.lua')"
  lua_seen="$(printf '%s\n' "$lua_files" | grep -c .)"
  # One nvim for the whole set, not one per file. test-check.sh re-runs these
  # checks once per mutation, so an interpreter start per lua file was most of
  # that suite's wall clock. `nvim -l` puts the script arguments in `arg`.
  #
  # io.stdout:write, not print: under `nvim --headless -l` print goes to STDERR,
  # so discarding stderr to keep nvim quiet also discarded the filenames, and
  # this reported every file as parsing while parsing nothing. Found by feeding
  # it a file that does not parse, which is the only way that kind of bug shows.
  #
  # The probe is a plain string rather than a heredoc inside $( ). bash 3.2 —
  # the macOS system bash, which is what runs this — scans a command
  # substitution for its closing paren without understanding that a quoted
  # heredoc is quoted, so ONE apostrophe anywhere in the body, in a comment
  # even, loses the terminator and reports a syntax error thirty lines later.
  # Confirmed in isolation: the same file parses with the apostrophe removed.
  # shellcheck disable=SC2086  # deliberate word splitting: one argument per file
  lua_failures="$(printf '%s\n' 'for _, f in ipairs(arg) do
  if not loadfile(f) then io.stdout:write(f, "\n") end
end' | nvim --clean --headless -l /dev/stdin $lua_files 2>/dev/null)"
  if [ "${lua_seen:-0}" -eq 0 ]; then
    bad "found no lua files to parse — the scan has broken"
  elif [ -z "$lua_failures" ]; then
    ok "every lua file parses ($lua_seen of them, wezterm's included)"
  else
    bad "lua file(s) that fail to parse:"
    printf '%s\n' "$lua_failures" | sed 's/^/      /'
  fi
else
  meh "nvim not installed, cannot parse the lua config"
fi

# Renamed or removed in Neovim 0.10/0.11. The deprecated aliases still work, so
# nothing complains until the version that drops them.
deprecated="vim\.highlight\.|vim\.lsp\.buf_get_clients|vim\.lsp\.get_active_clients|vim\.tbl_add_reverse_lookup|vim\.lsp\.with\(|vim\.diagnostic\.is_disabled|vim\.validate\(\{"
hits="$(grep -rInE "$deprecated" nvim/.config/nvim --include='*.lua' 2>/dev/null | grep -vc '^\s*--' || true)"
if [ "${hits:-0}" -eq 0 ]; then
  ok "no deprecated Neovim APIs in the lua config"
else
  bad "$hits use(s) of deprecated Neovim APIs — they still work, until they do not:"
  grep -rInE "$deprecated" nvim/.config/nvim --include='*.lua' 2>/dev/null | sed 's/^/      /'
fi

# lazy.nvim only reads specs returned from lua/rich/plugins/*.lua. A file that
# returns nothing is loaded, runs, and contributes no plugin — silently.
specless=0
for f in nvim/.config/nvim/lua/rich/plugins/*.lua; do
  grep -qE '^\s*return\s*\{' "$f" || {
    bad "$(basename "$f") has no top-level 'return {' — lazy will load it and get no spec"
    specless=$((specless + 1))
  }
done
[ "$specless" -eq 0 ] && ok "every plugin file returns a lazy spec"

if git ls-files --error-unmatch nvim/.config/nvim/lazy-lock.json >/dev/null 2>&1; then
  ok "lazy-lock.json is tracked — plugin versions are reproducible"
else
  bad "lazy-lock.json is not tracked — a fresh machine gets whatever is newest that day"
fi

# Line wrap, and which way round it has to point.
#
# This is the one option in options.lua whose value has already been changed by
# a commit about something else. It went in as true; commit 0bdf224 — "Resolved
# LSP errors and hardened colorscheme.lua" — left it false, with a trailing
# space, in a diff nobody was reading for this. Nothing said a word: the file
# still parses, nvim still starts, every other check here stays green, and the
# only symptom is long lines running off the right of the screen, which reads as
# a preference rather than a regression.
#
# TWO halves, because setting an option is not the same as it being set. Lua's
# last write wins, so wrap = true at the top of options.lua and a wo.wrap =
# false in an autocmd further down would leave wrap off with this file still
# claiming otherwise. The second grep looks for anything that turns it off again
# ANYWHERE under nvim/.config/nvim -- a directory walk, not `git ls-files`, so
# it also sees untracked lua there and does not see wezterm's. Comment lines are
# dropped so that a lua comment quoting the pattern cannot trip it. What neither
# half can see is an
# installed plugin doing it at runtime — that needs a running nvim, and
# tests/test-nvim.sh is where that assertion lives.
wrap="$(nvim_opt wrap)"
nowrap="$(grep -rInE 'vim\.(opt|o|wo|go|opt_local)\.wrap[[:space:]]*=[[:space:]]*false|(set|setlocal)[[:space:]]+nowrap' \
  nvim/.config/nvim --include='*.lua' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*--')"
if [ -z "$wrap" ]; then
  bad "could not read vim.opt.wrap out of $OPTIONS at all — the comparison would be vacuous"
elif [ "$wrap" != "true" ]; then
  bad "$OPTIONS sets wrap = $wrap, so long lines run off the right of the screen instead of wrapping"
elif [ -n "$nowrap" ]; then
  bad "options.lua sets wrap = true and the lua config turns it off again — the later write is the one that counts:"
  printf '%s\n' "$nowrap" | sed 's/^/      /'
else
  ok "line wrap is on in options.lua and nothing in the lua config turns it off again"
fi

# Hard wrap at 80, and the fact that setting it is not the same as getting it.
#
# 'wrap' folds at the window edge; 'textwidth' is what holds a line to 80. The
# value is static and belongs here, but the load-bearing half of that setting is
# NOT static and cannot be checked here at all: Neovim's own ftplugins strip 't'
# from formatoptions for lua and sh, and gitcommit sets textwidth=72, so a bare
# assignment in options.lua reads correct while doing nothing in the two
# languages this repo is mostly written in. options.lua answers that with a
# FileType autocmd that writes after them, and tests/test-nvim.sh proves the
# ordering by typing 140 columns into a lua buffer and counting what comes out.
#
# What this half does catch is the value being changed, and the value being
# changed BACK somewhere else in the lua: the second grep allows an assignment
# of 80 and reports any other number, which is what a stray `textwidth = 0` in
# a plugin config or an autocmd would be.
textwidth="$(nvim_opt textwidth)"
othertw="$(grep -rInE 'vim\.(opt|o|bo|wo|opt_local)\.textwidth[[:space:]]*=' \
  nvim/.config/nvim --include='*.lua' |
  grep -vE '^[^:]*:[0-9]+:[[:space:]]*--' |
  grep -vE '=[[:space:]]*80[[:space:]]*$')"
if [ -z "$textwidth" ]; then
  bad "could not read vim.opt.textwidth out of $OPTIONS at all — the comparison would be vacuous"
elif [ "$textwidth" != "80" ]; then
  bad "$OPTIONS sets textwidth = $textwidth, not 80, so prose stops wrapping where this repo writes it"
elif [ -n "$othertw" ]; then
  bad "options.lua sets textwidth = 80 and the lua config sets it to something else — the later write wins:"
  printf '%s\n' "$othertw" | sed 's/^/      /'
else
  ok "textwidth is 80 in options.lua and nothing in the lua config sets it to anything else"
fi

section "tmux config"
# Anchored to the set-option line, not to any mention: the comment above it
# explains what usstyle is, so a bare `grep usstyle` stayed green after the
# setting itself was removed.
if grep -qE '^[[:space:]]*set .*terminal-features.*usstyle' tmux/.config/tmux/tmux.conf; then
  ok "terminal-features declares usstyle (undercurl survives)"
else
  bad "terminal-features lacks usstyle — nvim's diagnostic undercurls are stripped"
fi

# Restore must not sit where a held Ctrl puts it, and the key it moved to has to
# be a key the terminal can actually send.
#
# The prefix is C-a. Holding Ctrl through the next keystroke turns `prefix r`
# (rename-window) into `prefix C-r`, which is resurrect's DEFAULT restore key —
# so leaving @resurrect-restore unset means an accidental full session restore
# while renaming a window. That is the defect this asserts against.
#
# The second half is the one that would rot silently. C-S-r and C-r are the same
# byte in a traditional terminal; they are only distinct when tmux asks for
# CSI-u reporting (extended-keys) AND believes the terminal can do it (the
# extkeys terminal-feature). Drop either and the binding still READS correct
# while becoming unreachable — the config would claim a key that cannot be
# pressed. So any Shift-bearing restore key requires both.
restore_key="$(tmux_setting '@resurrect-restore')"
ext_on="$(grep -cE '^[[:space:]]*set -s[g]? extended-keys on' "$TMUXCONF")"
ext_feat="$(grep -cE '^[[:space:]]*set -sa terminal-features .*extkeys' "$TMUXCONF")"
needs_ext=no
case "$restore_key" in
  *-S-*) needs_ext=yes ;;
esac
if [ -z "$restore_key" ]; then
  bad "tmux.conf never sets @resurrect-restore, so restore keeps resurrect's C-r default — one held Ctrl away from 'prefix r' (rename-window)"
elif [ "$restore_key" = "C-r" ]; then
  bad "@resurrect-restore is C-r, which is exactly what a held Ctrl turns 'prefix r' into"
elif [ "$needs_ext" = yes ] && [ "$ext_on" -eq 0 ]; then
  bad "@resurrect-restore is '$restore_key', but 'set -s extended-keys on' is missing — without it that is the same byte as the plain-Ctrl key and the binding is unreachable"
elif [ "$needs_ext" = yes ] && [ "$ext_feat" -eq 0 ]; then
  bad "@resurrect-restore is '$restore_key', but terminal-features never declares extkeys — tmux will not ask the terminal for the sequence that makes it distinct"
else
  ok "restore is bound to '$restore_key', off the held-Ctrl path, with the extended-keys support that makes it a key the terminal can send"
fi

# Continuum has no timer. It appends `#(continuum_save.sh)` to status-right and
# relies on tmux running that command every time it draws the status line. So if
# `set -g status-right` ever moves BELOW the line that runs tpm, it overwrites
# continuum's addition, every automatic save stops, and there is no error and no
# missing file to notice — the save directory just quietly stops growing.
#
# Line numbers, because ordering is the whole point.
sr_line="$(grep -n '^[[:space:]]*set .*status-right' tmux/.config/tmux/tmux.conf | head -1 | cut -d: -f1)"
tpm_line="$(grep -n "^[[:space:]]*run .*tpm" tmux/.config/tmux/tmux.conf | tail -1 | cut -d: -f1)"
if [ -z "$sr_line" ] || [ -z "$tpm_line" ]; then
  meh "could not locate both status-right and the tpm run line; skipping the ordering check"
elif [ "$sr_line" -lt "$tpm_line" ]; then
  ok "status-right is set before tpm runs, so continuum's auto-save survives"
else
  bad "status-right (line $sr_line) is set AFTER tpm (line $tpm_line) — it overwrites continuum's #() and auto-save silently stops"
fi

# Every key tmux.conf binds is either pressed by tests/test-bindings.sh or
# listed there as deliberately not driven, with a reason.
#
# That accounting lived in the suite and compared COUNTS: eleven driven plus ten
# undriven against twenty-one `bind` lines. Rename `bind w` to `bind W` and both
# numbers are still twenty-one, so a key could drop out of the accounting and
# come back as a different one without a word. Compare the sets — and do it
# here, because it is a fact about two files and needs no terminal to find out.
driven="$(sed -n 's/^driven="\(.*\)"$/\1/p' tests/test-bindings.sh)"
undriven="$(sed -n 's/^undriven="\(.*\)"$/\1/p' tests/test-bindings.sh)"
bound_keys="$(tmux_bound_keys | sort -u)"
if [ -z "$driven" ] || [ -z "$undriven" ] || [ -z "$bound_keys" ]; then
  bad "could not read the driven/undriven lists or tmux.conf's bindings — the comparison would be vacuous"
else
  accounted="$(printf '%s %s' "$driven" "$undriven" | tr ' ' '\n' | grep -v '^$' | sort -u)"
  unaccounted="$(comm -23 <(printf '%s\n' "$bound_keys") <(printf '%s\n' "$accounted") | tr '\n' ' ')"
  phantom="$(comm -13 <(printf '%s\n' "$bound_keys") <(printf '%s\n' "$accounted") | tr '\n' ' ')"
  if [ -z "$unaccounted" ] && [ -z "$phantom" ]; then
    ok "every key tmux.conf binds is pressed or explained in test-bindings.sh"
  else
    [ -n "$unaccounted" ] && bad "tmux.conf binds ${unaccounted}— test-bindings.sh neither presses nor explains them"
    [ -n "$phantom" ] && bad "test-bindings.sh accounts for ${phantom}— which tmux.conf does not bind"
  fi
fi

section "Constants kept in step"
# Two pairs of numbers were held together by a comment asking a person to
# remember. tmux-resurrect-saves says "Keep in step with
# @resurrect-guard-min-windows in tmux.conf"; tmux.conf says its retention
# window is "Kept in step with tmux-resurrect-saves' KEEP_DAILY_DAYS". Both
# pairs agreed. Nothing made them.
#
# WHAT DIVERGENCE COSTS, which is why these are asserted rather than trusted.
# Move the guard's floor without the script's and the guard vetoes at a
# threshold prune does not share: prune then keeps saves the guard will never
# let become `last`, and deletes ones it would have. Move one retention window
# and resurrect's own backup deletion fights prune's policy. Either way the
# first symptom is a save that is gone when you need it, which is the worst
# imaginable moment to discover a comment went stale.
#
# The guard's own defaults are in here too. They only take effect when tmux.conf
# does not set the option — which is exactly when a divergence would be silent,
# because nothing looks wrong until the line is deleted. Its header documents
# each default in prose as well, so every one of these numbers is written down
# three or four times.
agree() { # $1 = what the value is, $2... = "where=value"
  local what="$1"
  shift
  local n=$#
  local first="" first_where="" pair where value broken=0
  for pair in "$@"; do
    where="${pair%%=*}"
    value="${pair#*=}"
    case "$value" in
      '' | *[[:space:]]*)
        bad "could not read $what out of $where — the comparison would be vacuous"
        broken=1
        continue
        ;;
    esac
    if [ -z "$first_where" ]; then
      first="$value"
      first_where="$where"
    elif [ "$value" != "$first" ]; then
      bad "$what: $first_where says '$first' but $where says '$value' — nothing but a comment held those together"
      broken=1
    fi
  done
  [ "$broken" -eq 0 ] && ok "$what is '$first' in all $n places that write it down"
}

agree "the guard's minimum window count" \
  "tmux.conf=$(tmux_setting @resurrect-guard-min-windows)" \
  "the guard's own default=$(guard_default @resurrect-guard-min-windows)" \
  "the guard's header=$(guard_doc_default @resurrect-guard-min-windows)" \
  "tmux-resurrect-saves MIN_WINDOWS=$(sh_default "$SAVES" MIN_WINDOWS)"

agree "the retention window in days" \
  "tmux.conf @resurrect-delete-backup-after=$(tmux_setting @resurrect-delete-backup-after)" \
  "tmux-resurrect-saves KEEP_DAILY_DAYS=$(sh_default "$SAVES" KEEP_DAILY_DAYS)"

agree "the guard's collapse percentage" \
  "tmux.conf=$(tmux_setting @resurrect-guard-collapse-pct)" \
  "the guard's own default=$(guard_default @resurrect-guard-collapse-pct)" \
  "the guard's header=$(guard_doc_default @resurrect-guard-collapse-pct)"

agree "whether the guard is on by default" \
  "tmux.conf=$(tmux_setting @resurrect-guard)" \
  "the guard's own default=$(guard_default @resurrect-guard)" \
  "the guard's header=$(guard_doc_default @resurrect-guard)"

agree "whether the guard announces its vetoes" \
  "tmux.conf=$(tmux_setting @resurrect-guard-notify)" \
  "the guard's own default=$(guard_default @resurrect-guard-notify)" \
  "the guard's header=$(guard_doc_default @resurrect-guard-notify)"

# Same shape, inside one file: the header says how far guard.log is trimmed, and
# two lines of code do the trimming. A header describing its own file is no more
# self-maintaining than one describing a different file.
# shellcheck disable=SC2016  # $lines and $logfile are text in the guard, not here
agree "how many lines guard.log is trimmed to" \
  "the guard's header=$(sed -n 's/.*trimmed to \([0-9][0-9]*\) lines.*/\1/p' "$GUARD" | head -1)" \
  "its length test=$(sed -n 's/.*"\$lines" -gt \([0-9][0-9]*\).*/\1/p' "$GUARD" | head -1)" \
  "the tail that trims it=$(sed -n 's/.*tail -n \([0-9][0-9]*\) "\$logfile".*/\1/p' "$GUARD" | head -1)"

# The stow package set is written by hand in six places, and the first version
# of this check knew about four of them — which is the defect it exists to catch,
# committed inside the fix for it. So the copies are FOUND rather than listed: a
# line counts as one when it names four or more of the packages, which no prose
# here does, and every copy must name exactly the set `make stow` uses.
#
# Miss a copy when adding a package and the symptom is silent: check.sh's
# "every package is stowed" quietly stops covering it, so new files in that
# package never go live and nothing says so.
#
# tests/test-check.sh is skipped. Its job is to hold deliberately broken copies
# of things, and a mutation that shortens this list is test data, not drift.
pkg_set() { # $1 = whitespace-separated package names
  printf '%s' "$1" | tr ' ' '\n' | grep -v '^$' | grep -vE '^(git|gitconfig)$' | sort -u | paste -sd, -
}
pkg_ref="$(pkg_set "$(sed -n '/^stow:/,/^$/p' Makefile | grep -m1 'PKGS=' | sed 's/.*PKGS="\([^"]*\)".*/\1/')")"
if [ -z "$pkg_ref" ]; then
  bad "could not read the package list out of the Makefile — every copy would compare against nothing"
else
  pkg_words="$(printf '%s' "$pkg_ref" | tr ',' ' ')"
  # A copy is a RUN of package names with nothing between them. Counting names
  # anywhere on the line is not enough: checks/machine.sh's tool loop happens to
  # name four of the six, interleaved with rg, fd and stow, and was reported as
  # a package list that had lost two entries.
  # shellcheck disable=SC2016  # $0 and $... below are awk's, not the shell's
  pkg_hits="$(git ls-files | grep -v '^tests/test-check.sh$' | tr '\n' '\0' |
    xargs -0 awk -v names=" $pkg_words " '
      {
        line = $0
        gsub(/[^A-Za-z0-9_-]/, " ", line)
        n = split(line, tok, " ")
        run = ""; best = ""; runlen = 0; bestlen = 0
        for (i = 1; i <= n; i++) {
          if (tok[i] != "" && index(names, " " tok[i] " ") > 0) {
            run = run " " tok[i]
            runlen++
            if (runlen > bestlen) { best = run; bestlen = runlen }
          } else {
            run = ""
            runlen = 0
          }
        }
        if (bestlen >= 4) print FILENAME "\t" best
      }')"
  pkg_copies=0
  pkg_bad=0
  while IFS="$(printf '\t')" read -r f run; do
    [ -n "$f" ] || continue
    pkg_copies=$((pkg_copies + 1))
    if [ "$(pkg_set "$run")" != "$pkg_ref" ]; then
      bad "$f lists the stow packages as '$(pkg_set "$run")', and 'make stow' uses '$pkg_ref'"
      pkg_bad=$((pkg_bad + 1))
    fi
  done <<<"$pkg_hits"
  if [ "$pkg_copies" -lt 2 ]; then
    bad "found $pkg_copies place(s) listing the stow packages — there are several, so the scan has broken"
  elif [ "$pkg_bad" -eq 0 ]; then
    ok "all $pkg_copies copies of the stow package list agree ($pkg_ref)"
  fi
fi

# A comment that quotes a line of another file is a copy, and copies drift. The
# guard's header quotes the two tmux.conf lines that wire it up — the most
# useful thing in that header, and the easiest to leave behind when the wiring
# changes.
quoted_bad=0
quoted_seen=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  quoted_seen=$((quoted_seen + 1))
  grep -qxF "$line" "$TMUXCONF" || {
    bad "a comment quotes \"$line\" as tmux.conf's wiring, and tmux.conf has no such line"
    quoted_bad=$((quoted_bad + 1))
  }
done < <(git ls-files | grep -vxF "$TMUXCONF" |
  xargs grep -h -E '^#[[:space:]]+set(-option)? -g @' 2>/dev/null | sed 's/^#[[:space:]]*//')
if [ "$quoted_seen" -eq 0 ]; then
  meh "no comment quotes a tmux.conf line, so there was nothing to compare"
elif [ "$quoted_bad" -eq 0 ]; then
  ok "every tmux.conf line a comment quotes ($quoted_seen of them) is really in tmux.conf"
fi

section "Shell"
if command -v zsh >/dev/null 2>&1; then
  if zsh -n zsh/.zshrc 2>/dev/null; then ok ".zshrc parses"; else bad ".zshrc has a syntax error"; fi
else
  meh "zsh not installed, cannot parse .zshrc"
fi

# The (#q...) glob qualifier silently does nothing without EXTENDED_GLOB, which
# made the completion cache unreachable and cost a full compinit every shell.
# Anchored to the setopt line for the same reason as usstyle above.
if grep -q '(#q' zsh/.zshrc; then
  if grep -qE '^[[:space:]]*setopt[^#]*extendedglob' zsh/.zshrc; then
    ok ".zshrc enables extendedglob where it uses (#q...) qualifiers"
  else
    bad ".zshrc uses (#q...) without extendedglob — those tests silently never match"
  fi
fi

section "Known shell traps"
# A pipeline ending in a quiet grep, under `set -o pipefail`: grep exits on the
# first match, the producer takes SIGPIPE, and the pipeline reports FAILURE even
# though the pattern matched. Four separate false results in this repo came from
# it, including a check reporting a present colour scheme as missing.
hazard=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! grep -qE '^[[:space:]]*set .*pipefail' "$f" 2>/dev/null &&
    ! grep -qE '^[[:space:]]*\.[[:space:]].*lib\.sh' "$f" 2>/dev/null; then
    continue
  fi
  # Comments stripped first: a doc comment describing the hazard is not the
  # hazard, and counting it would make this check cry wolf about itself.
  n="$(sed 's/#.*//' "$f" | grep -cE '\|[[:space:]]*grep[[:space:]]+-q')"
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 0 ]; then
    bad "$f: $n pipeline(s) into a quiet grep under pipefail — SIGPIPE reports failure on a MATCH"
    hazard=$((hazard + n))
  fi
done < <(git ls-files '*.sh' 'tmux/.local/bin/*' 2>/dev/null)
[ "$hazard" -eq 0 ] && ok "no pipeline into a quiet grep under pipefail anywhere in the repo"

# Sourcing a script that sets -e imports it. tests/lib.sh deliberately does not;
# under -e a failing assertion aborts the suite instead of reporting FAIL, and
# the run goes quiet looking exactly like a normal finish.
if grep -qE '^[[:space:]]*set -[a-z]*e' tests/lib.sh 2>/dev/null; then
  bad "tests/lib.sh sets -e — a failing assertion would abort the suite instead of reporting"
else
  ok "tests/lib.sh does not set -e, so assertions report rather than abort"
fi

section "Make targets"
# A target listed in .PHONY but with no recipe does not error — make prints
# "Nothing to be done" and exits 0. `make test` did exactly that after a careless
# edit deleted the target, reporting success while running nothing.
# Every .PHONY line, not just the first: make accepts any number of them, and
# reading one would leave everything on a second line silently unchecked.
phony="$(grep '^.PHONY:' Makefile | cut -d: -f2-)"
for target in $phony; do
  if grep -qE "^${target}:" Makefile; then
    ok "make $target has a recipe"
  else
    bad "make $target is declared .PHONY but has no recipe — it exits 0 doing nothing"
  fi
done

section "Git hooks"
# A hook and a make target are two copies of one command, and everything that
# DESCRIBES a hook — the README, the Makefile's own help, bootstrap.sh, the
# message check.sh prints — names the target rather than the command. So when
# pre-push was changed to run the fast subset, four separate descriptions went
# on saying "test on push": true of the target they named, false of the hook.
#
# Assert the equivalence instead of the wording. Each hook must run exactly what
# its target runs, and every file that advertises the pairing must name that
# target, so the wording cannot survive the hook changing under it.
hook_runs() { # $1 = hook name — the repo-relative command it execs
  # shellcheck disable=SC2016  # the $( ) below is text to match, not to run
  sed -n 's|^exec "$(git rev-parse --show-toplevel)/\([^"]*\)"|\1|p' ".githooks/$1"
}
target_runs() { # $1 = make target — the command its recipe runs
  awk -v t="$1" '
    $0 ~ "^" t ":" { found = 1; next }
    found && /^\t/ {
      sub(/^\t@?\.\//, "")
      print
      exit
    }
  ' Makefile
}
hooks_bad=0
for pair in pre-commit:check pre-push:test-fast; do
  hook="${pair%%:*}"
  target="${pair##*:}"
  hc="$(hook_runs "$hook")"
  tc="$(target_runs "$target")"
  if [ -z "$hc" ] || [ -z "$tc" ]; then
    bad "could not read what .githooks/$hook or 'make $target' runs — the comparison would be vacuous"
    hooks_bad=$((hooks_bad + 1))
  elif [ "$hc" != "$tc" ]; then
    bad ".githooks/$hook runs '$hc' but 'make $target' runs '$tc' — everything that describes this hook names the target"
    hooks_bad=$((hooks_bad + 1))
  else
    ok ".githooks/$hook runs exactly what 'make $target' runs ($hc)"
  fi
  # One phrase — "check on commit", "test-fast on push" — repeated in three
  # files. Built from the pair above, so renaming the target breaks all three
  # here rather than in six months when someone reads one of them.
  phrase="$target on ${hook#pre-}"
  for f in README.md Makefile bootstrap.sh checks/machine.sh; do
    # checks/machine.sh may legitimately not be here: --repo-only has to keep
    # working without the machine half, which is what lets CI run this one
    # alone. Warn rather than skip quietly — a check that stops checking
    # without saying so is the thing this file exists to prevent.
    [ -f "$f" ] || {
      meh "$f is not here, so its description of the hooks went unchecked"
      continue
    }
    grep -qF "$phrase" "$f" || {
      bad "$f advertises the git hooks without saying '$phrase'"
      hooks_bad=$((hooks_bad + 1))
    }
  done
done
[ "$hooks_bad" -eq 0 ] && ok "every file that advertises the hooks names the target the hook really runs"

section "Slow suites"
# A suite opts out of the fast set with SUITE_SLOW=1, and every one of them says
# in its header who still runs it. That sentence was copy-pasted into seven
# files and went false in all seven on the day pre-push started passing --fast:
# it said the hook still ran everything, when the hook now skips precisely
# these. Nothing noticed, because a comment is not executed.
#
# So derive the sentence from the hook instead of trusting the copies. Comments
# are flattened before matching, because otherwise this would be dictating where
# the line wraps.
case "$(hook_runs pre-push)" in
  *--fast*) slow_phrase="and so does the pre-push hook" ;;
  *) slow_phrase="the pre-push hook runs these too" ;;
esac
slow_bad=0
slow_seen=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  slow_seen=$((slow_seen + 1))
  flat="$(sed -n 's/^#[[:space:]]\{0,1\}//p' "$f" | tr '\n' ' ' | tr -s ' ')"
  grep -qF "$slow_phrase" <<<"$flat" || {
    bad "$f declares SUITE_SLOW=1 but never says '$slow_phrase' — its header and the hook disagree"
    slow_bad=$((slow_bad + 1))
  }
done < <(grep -l '^SUITE_SLOW=1' tests/test-*.sh)
if [ "$slow_seen" -eq 0 ]; then
  bad "no suite declares SUITE_SLOW=1 — either --fast runs everything now, or the marker was renamed"
elif [ "$slow_bad" -eq 0 ]; then
  ok "all $slow_seen slow suites say who runs them, and it agrees with what pre-push does"
fi

section "README"
# The README is the only file here that describes this repo without executing
# any of it, so nothing notices when it stops being true. By the time this was
# written it had drifted twice: it quoted a pre-push timing that had been
# corrected in the hook the day before, and it never mentioned `make test-fast`,
# which exists. One document, five minutes, two defects.
#
# Everything below is mechanical. The README may name a target, a file, a
# binding or a figure only when the thing it names is really here.

# The body of one "## " section of the README, so a table can be read without
# matching rows from a different table.
readme_section() { # $1 = heading text, without the "## "
  awk -v h="$1" '
    $0 == "## " h { inside = 1; next }
    /^## / { inside = 0 }
    inside { print }
  ' README.md
}
# The first cell of every table row in a section, as bare backticked tokens.
readme_keys() { # $1 = heading text
  # shellcheck disable=SC2016  # backticks here are markdown, not substitution
  readme_section "$1" | awk -F'|' '/^\|/ { print $2 }' | grep -oE '`[^`]+`' | tr -d '`'
}

readme_bad=0

# --- make targets, both directions ------------------------------------------
# Forwards: a target the README tells you to run must exist, or the setup
# instructions are wrong on a machine nobody has tried them on.
# shellcheck disable=SC2013  # splitting on words is the point
for t in $(grep -oE '\bmake [a-z][a-z0-9-]*' README.md | awk '{ print $2 }' | sort -u); do
  grep -qE "^$t:" Makefile || {
    bad "the README tells you to run 'make $t', which the Makefile does not define"
    readme_bad=$((readme_bad + 1))
  }
done
# Backwards, which is how `make test-fast` stayed invisible for as long as it
# did. `help` is the deliberate exception: `make help` prints the target list
# out of the Makefile itself, so naming it in the README would be a third copy
# of the same list.
README_UNDOCUMENTED="help"
# shellcheck disable=SC2013  # .PHONY is one line of space-separated targets
for t in $(grep '^.PHONY:' Makefile | cut -d: -f2-); do
  case " $README_UNDOCUMENTED " in *" $t "*) continue ;; esac
  grep -qE "(^|[^a-z0-9-])make $t([^a-z0-9-]|$)" README.md || {
    bad "the Makefile defines 'make $t' and the README never mentions it"
    readme_bad=$((readme_bad + 1))
  }
done

# --- files and paths ---------------------------------------------------------
# Shape, not guesswork: a backticked token counts as a path when it contains a
# slash or carries a filename extension. `q` and `main` are prose and cannot be
# told from filenames, so they are left alone. This catches the reference that
# has moved, which is the drift that actually happens. Paths under ~ are a fact
# about the machine, and checks/machine.sh asserts those.
paths_seen=0
tracked="$(git ls-files)"
# shellcheck disable=SC2016  # backticks here are markdown, not substitution
readme_tokens="$(grep -oE '`[^`]+`' README.md | tr -d '`' | sort -u)"
tracked_names="$(git ls-files | sed 's|.*/||')"
while IFS= read -r tok; do
  case "$tok" in
    '~'/*) continue ;;
    */* | *.[a-z]*) : ;;
    *) continue ;;
  esac
  tok="${tok%/}"
  tok="${tok#./}"
  paths_seen=$((paths_seen + 1))
  [ -e "$tok" ] && continue
  grep -qxF "$tok" <<<"$tracked" && continue
  grep -qxF "$tok" <<<"$tracked_names" && continue
  bad "the README references \`$tok\`, which is not in this repo"
  readme_bad=$((readme_bad + 1))
done <<<"$readme_tokens"
[ "$paths_seen" -eq 0 ] && {
  bad "found no path-shaped references in the README at all — the extraction has broken"
  readme_bad=$((readme_bad + 1))
}

# --- stow packages -----------------------------------------------------------
# The table at the top is the only index of what this repo installs.
for p in $(grep -oE '^\| \*\*[a-z]+\*\*' README.md | tr -d '|* '); do
  [ -d "$p" ] || {
    bad "the README's package table lists **$p**, which is not a directory here"
    readme_bad=$((readme_bad + 1))
  }
done
# shellcheck disable=SC2013  # PKGS is one line of space-separated packages
for p in $(grep -m1 'PKGS=' Makefile | sed 's/.*PKGS="\([^"]*\)".*/\1/'); do
  grep -qE "^\| \*\*$p\*\*" README.md || {
    bad "'make stow' installs the $p package and the README's table does not list it"
    readme_bad=$((readme_bad + 1))
  }
done

# --- what the prompt actually shows ------------------------------------------
# The table row for starship named three modules; the format string has eight.
# Nobody had lied — the row was written when the prompt had three, and adding
# python, nodejs, rust, golang and cmd_duration to the config did not touch it.
# Every module in the format string has to appear in the row, spelled the way
# starship spells it, so the row cannot fall behind the prompt again.
star_row="$(grep -m1 '^| \*\*starship\*\*' README.md)"
star_fmt="$(grep -m1 '^format = ' starship/.config/starship.toml)"
if [ -z "$star_row" ] || [ -z "$star_fmt" ]; then
  bad "could not read the starship row or the format string — the comparison would be vacuous"
  readme_bad=$((readme_bad + 1))
else
  for mod in $(printf '%s' "$star_fmt" | grep -oE '\$[a-z_]+' | tr -d '$'); do
    # Not prompt content: one ends the line, the other draws the ❯.
    case "$mod" in line_break | character) continue ;; esac
    case "$star_row" in
      *"${mod//_/ }"*) : ;;
      *)
        bad "starship's prompt includes \$$mod and the README's row does not mention it"
        readme_bad=$((readme_bad + 1))
        ;;
    esac
  done
fi

# --- the helper scripts the README documents ---------------------------------
# Both are introduced by a bold backticked heading, and the usage block under
# the second one is a promise about its command-line interface.
# shellcheck disable=SC2016  # backticks here are markdown, not substitution
for s in $(grep -oE '^\*\*`[a-z-]+`\*\*' README.md | tr -d '*`'); do
  [ -x "tmux/.local/bin/$s" ] || {
    bad "the README documents \`$s\`, which is not an executable in tmux/.local/bin"
    readme_bad=$((readme_bad + 1))
  }
done
# shellcheck disable=SC2013  # splitting on words is the point
for sub in $(grep -oE 'tmux-resurrect-saves [a-z]+' README.md | awk '{ print $2 }' | sort -u); do
  grep -qE "^[[:space:]]*$sub\)" tmux/.local/bin/tmux-resurrect-saves || {
    bad "the README shows 'tmux-resurrect-saves $sub', which the script does not accept"
    readme_bad=$((readme_bad + 1))
  }
done

# --- key bindings ------------------------------------------------------------
# tmux's grammar is `bind [-flags] [-T table] KEY command`, so the key is the
# first argument that is not a flag or a flag's argument. A subset test, not
# equality: tmux.conf also binds the prefix and the copy-mode keys, which the
# README deliberately does not tabulate.
bound="$(tmux_bound_keys)"
keys_seen=0
if [ -z "$bound" ]; then
  bad "could not read any bound key out of tmux.conf — the binding table check would be vacuous"
  readme_bad=$((readme_bad + 1))
else
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    # The README writes the key the way a person says it; tmux has its own name.
    [ "$k" = "Backspace" ] && k="BSpace"
    keys_seen=$((keys_seen + 1))
    grep -qxF "$k" <<<"$bound" || {
      bad "the README's tmux table documents '$k', which tmux.conf does not bind"
      readme_bad=$((readme_bad + 1))
    }
  done < <(readme_keys "Key tmux bindings")
  [ "$keys_seen" -eq 0 ] && {
    bad "read no keys out of the README's tmux table — the extraction has broken"
    readme_bad=$((readme_bad + 1))
  }
fi

# The leader mappings get the strong version, because tests/test-nvim.sh already
# pins the exact set against a real nvim: anything the README claims has to be
# in it. BOTH modes — the first run of this check reported `<leader>9v` as
# undocumented, and it was right that nothing asserted it: 9v is visual-only and
# the suite enumerated normal mode alone. The suite now pins both sets, so the
# union below is the whole truth rather than most of it.
#
# The four non-leader rows get a weaker check — nothing enumerates them, so all
# this can say is that the key still appears as a quoted string in the config.
# That catches a mapping renamed or deleted, and would not notice one surviving
# only in a comment. Said plainly rather than left looking as strong as the
# assertion above.
expected_leader="$(sed -n 's/^EXPECTED_LEADER_[NV]="\(.*\)"$/\1/p' tests/test-nvim.sh | paste -sd, -)"
if [ -z "$expected_leader" ]; then
  bad "could not read EXPECTED_LEADER_N/V out of tests/test-nvim.sh — the leader table check would be vacuous"
  readme_bad=$((readme_bad + 1))
else
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$k" in
      '<leader>'*)
        case ",$expected_leader," in
          *",$k,"*) : ;;
          *)
            bad "the README documents $k, which is not in test-nvim.sh's asserted set of leader mappings"
            readme_bad=$((readme_bad + 1))
            ;;
        esac
        ;;
      *)
        grep -rqF "\"$k\"" nvim/.config/nvim --include='*.lua' || {
          bad "the README documents the Neovim binding '$k', which appears nowhere in the lua config"
          readme_bad=$((readme_bad + 1))
        }
        ;;
    esac
  done < <(readme_keys "Key Neovim bindings")
fi

# --- figures -----------------------------------------------------------------
# THE DECISION about quoting numbers, because a measured figure is true only at
# the instant it is measured, on the machine it was measured on. The README does
# not quote measured timings at all, and neither do the hook headers. Both did;
# one had been wrong since the day before it was noticed. Asserting such a
# number would mean asserting how fast somebody else's laptop is, which is why
# tests/test-performance.sh measures the pre-push suite where it runs and fails
# against a ceiling instead. That is where a timing belongs, and the prose
# points there.
#
# A CONFIGURED constant is different: a file owns it. So the permitted figures
# are READ OUT of those files rather than listed here — change the interval and
# the prose has to follow, in either direction, or this fails.
save_interval="$(tmux_setting @continuum-save-interval)"
keep_all="$(sh_default tmux/.local/bin/tmux-resurrect-saves KEEP_ALL_DAYS)"
keep_daily="$(sh_default tmux/.local/bin/tmux-resurrect-saves KEEP_DAILY_DAYS)"
# A count is a figure too, and drifts the same way: the pre-push header argued
# from "16 suites" and "eight of those" when there were 18 and 9. Both are
# countable, so both are permitted — and self-correcting.
suite_count="$(git ls-files 'tests/test-*.sh' | wc -l | tr -d ' ')"
slow_count="$(grep -l '^SUITE_SLOW=1' tests/test-*.sh | wc -l | tr -d ' ')"
if [ -z "$save_interval" ] || [ -z "$keep_all" ] || [ -z "$keep_daily" ] ||
  [ "${suite_count:-0}" -eq 0 ] || [ "${slow_count:-0}" -eq 0 ]; then
  bad "could not read the configured intervals or the suite counts — the figure check would permit everything"
  readme_bad=$((readme_bad + 1))
else
  allowed="$(printf '%s\n%s\n%s\n%s\n%s' \
    "$save_interval minutes" "$keep_all days" "$keep_daily days" \
    "$suite_count suites" "$slow_count suites")"
  figs_seen=0
  for doc in README.md .githooks/pre-commit .githooks/pre-push; do
    # Backticked spans are code, not prose — `<leader>9s` would otherwise read
    # as "9 s". Everything else that is not a letter or a digit becomes a
    # space, which also joins "every 15\nminutes" back into one figure.
    # shellcheck disable=SC2016  # backticks here are markdown, not substitution
    prose="$(sed 's/`[^`]*`//g' "$doc" | tr -c 'A-Za-z0-9' ' ')"
    while IFS= read -r fig; do
      [ -n "$fig" ] || continue
      figs_seen=$((figs_seen + 1))
      grep -qxF "$fig" <<<"$allowed" || {
        bad "$doc quotes '$fig', which nothing here can read back — a figure belongs where something measures or counts it"
        readme_bad=$((readme_bad + 1))
      }
    done < <(awk '{
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+(ms|s)$/) { print $i; continue }
        if ($i ~ /^[0-9]+$/ && i < NF && $(i + 1) ~ /^(ms|s|secs?|seconds?|mins?|minutes?|hours?|days?|weeks?|suites?)$/) print $i " " $(i + 1)
      }
    }' <<<"$prose")
  done
  [ "$figs_seen" -eq 0 ] && {
    bad "found no figures at all in the README — the extraction has broken"
    readme_bad=$((readme_bad + 1))
  }
fi

[ "$readme_bad" -eq 0 ] && ok "the README describes nothing that is not here (targets, paths, packages, bindings, figures)"

section "Lint coverage"
# `make lint` derives its file set from the shebangs, so a script only reaches
# the linters by starting with one. A shell script without a shebang would be
# linted by nothing and nothing would say so — which is exactly how
# tmux/.local/bin escaped the hand-written list that target replaced, leaving
# all five of the scripts stowed onto PATH unchecked.
#
# Two rules, because the failure differs: a *.sh file needs a SHELL shebang or
# lint skips it, and any executable needs some shebang or it is run by whatever
# shell happens to call it.
shebang_bad=0
shebang_seen=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  shebang_seen=$((shebang_seen + 1))
  first="$(head -1 "$f")"
  case "$f" in
    *.sh)
      case "$first" in
        '#!'*sh) continue ;;
        *) bad "$f is a shell script with no shell shebang — 'make lint' derives its file set from those, so nothing lints it" ;;
      esac
      ;;
    *)
      case "$first" in
        '#!'*) continue ;;
        *) bad "$f is executable with no shebang — whatever shell invokes it decides how it runs" ;;
      esac
      ;;
  esac
  shebang_bad=$((shebang_bad + 1))
done < <(
  {
    git ls-files '*.sh'
    git ls-files -s | awk '$1 == "100755" { print $4 }'
  } | sort -u
)
if [ "$shebang_seen" -eq 0 ]; then
  bad "found no shell scripts or executables at all — the scan has broken"
elif [ "$shebang_bad" -eq 0 ]; then
  ok "all $shebang_seen shell scripts and executables declare an interpreter, so lint sees them"
fi

section "CI"
# A workflow that exists but no longer calls these targets is worse than none:
# the badge stays green while nothing runs. Assert the wiring, not just the file.
CI=".github/workflows/ci.yml"
if [ ! -f "$CI" ]; then
  bad "no CI workflow — the hooks are local and bypassable with --no-verify"
else
  ok "CI workflow present"
  for target in check-repo test lint; do
    if grep -qE "make $target( |$)" "$CI"; then
      ok "CI runs 'make $target'"
    else
      bad "CI does not run 'make $target' — it would pass without checking"
    fi
  done
  if grep -qE '^[[:space:]]*runs-on: macos' "$CI"; then
    ok "CI runs on macOS, which is the only platform bootstrap.sh supports"
  else
    bad "CI does not run on macOS, so it cannot exercise this repo honestly"
  fi
fi
