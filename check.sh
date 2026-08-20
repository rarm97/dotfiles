#!/usr/bin/env bash
# Assert the things this setup quietly assumes.
#
# `make check` used to print tool versions. That is an inventory, not a check:
# it tells you what is installed, never that something is wrong. Every
# assertion below corresponds to a defect that was live in this repo for weeks
# or months without producing a single symptom — a colour scheme name that
# silently fell back, a linter that silently never ran, a completion cache that
# was never used, an ignore rule that never matched. As assertions they cost
# two seconds.
#
# The rule this file exists to enforce: if it can be wrong without saying so,
# it is not finished.
#
# Exits non-zero if anything FAILs, so it is usable from CI or a hook.
# WARNs do not fail the run — they are things worth knowing, not broken things.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
REPO="$PWD"

pass=0 warn=0 fail=0
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

# ---------------------------------------------------------------- tools

section "Tools"
for t in git nvim tmux stow rg fd node starship wezterm; do
  if command -v "$t" >/dev/null 2>&1; then
    ok "$t"
  else
    bad "$t is missing — bootstrap.sh installs it"
  fi
done
# required = true means git REFUSES to check out an LFS repo without the filter.
if [ "$(git config --get filter.lfs.required 2>/dev/null)" = "true" ]; then
  if command -v git-lfs >/dev/null 2>&1; then
    ok "git-lfs present, as filter.lfs.required demands"
  else
    bad "filter.lfs.required=true but git-lfs is missing — any LFS repo will fail to check out"
  fi
fi

# ---------------------------------------------------------------- stow layout

section "Stow layout"
# Only the tmux package supplies .local/, so if ~/.local does not exist when
# stow runs it folds the whole directory into a symlink into this repo, and
# nvim's plugins and tmux-resurrect's saves end up inside the working tree.
# shellcheck disable=SC2088  # the tildes below are prose, not paths to expand
if [ -L "$HOME/.local" ]; then
  bad "~/.local is a SYMLINK ($(readlink "$HOME/.local")) — stow folded it; nvim data is landing in the repo"
elif [ -d "$HOME/.local" ]; then
  ok "~/.local is a real directory, not a folded symlink"
else
  meh "~/.local does not exist yet"
fi

pending="$(stow -n -t "$HOME" nvim wezterm tmux zsh home starship git 2>&1 | grep -cE '^(LINK|MKDIR)')"
if [ "${pending:-0}" -eq 0 ]; then
  ok "every package is stowed (no pending links)"
else
  bad "$pending stow action(s) pending — run 'make stow' or new files will not be live"
fi

for s in tmux-resurrect-guard tmux-resurrect-saves tmux-clear-scrollback tmux-sessionizer tmux-kill-session; do
  if [ -x "$HOME/.local/bin/$s" ]; then
    ok "$s is on PATH and executable"
  else
    bad "$HOME/.local/bin/$s missing or not executable — the binding that calls it will fail silently"
  fi
done

# ---------------------------------------------------------------- git

section "Git"
# ~/.gitconfig is read AFTER the stowed config, so anything it sets wins. When
# the two disagree the repo's copy is dead and nothing says so.
for k in user.email user.name; do
  repo_v="$(git config --file "$REPO/git/.config/git/config" --get "$k" 2>/dev/null)"
  live_v="$(git config --get "$k" 2>/dev/null)"
  if [ -z "$repo_v" ]; then
    meh "$k is not set in the repo's git config"
  elif [ "$repo_v" = "$live_v" ]; then
    ok "$k agrees between the repo and what git actually uses ($live_v)"
  else
    bad "$k: repo says '$repo_v' but git uses '$live_v' — the repo's value is dead"
  fi
done

if git -C "$REPO" ls-files --error-unmatch nvim/.config/nvim/lazy-lock.json >/dev/null 2>&1; then
  ok "lazy-lock.json is tracked — plugin versions are reproducible"
else
  bad "lazy-lock.json is not tracked — a fresh machine gets whatever is newest that day"
fi

# ---------------------------------------------------------------- terminal

section "Terminal"
scheme="$(grep -oE 'color_scheme = "[^"]+"' "$REPO/wezterm/.config/wezterm/wezterm.lua" 2>/dev/null | sed 's/.*"\(.*\)"/\1/')"
if [ -z "$scheme" ]; then
  meh "no color_scheme set in wezterm.lua"
else
  gui="/Applications/WezTerm.app/Contents/MacOS/wezterm-gui"
  if [ ! -x "$gui" ]; then
    meh "cannot verify colour scheme '$scheme' — wezterm-gui not found"
  # grep -cF, not -qF: -q exits on the first match, strings takes SIGPIPE, and
  # `set -o pipefail` turns that into a failed pipeline — which reported this
  # very scheme as missing when it was present.
  elif [ "$(strings -a "$gui" 2>/dev/null | grep -cF "name = \"$scheme\"")" -gt 0 ]; then
    ok "wezterm colour scheme '$scheme' exists"
  else
    bad "wezterm colour scheme '$scheme' does not exist — WezTerm falls back silently"
  fi
fi

font="$(grep -oE '"[A-Za-z][^"]*Nerd Font"' "$REPO/wezterm/.config/wezterm/wezterm.lua" 2>/dev/null | head -1 | tr -d '"')"
if [ -n "$font" ]; then
  compact="$(printf '%s' "$font" | tr -d ' ')"
  if [ -n "$(find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 1 -iname "*${compact}*" 2>/dev/null | head -1)" ]; then
    ok "font '$font' is installed"
  else
    bad "font '$font' is not installed — every glyph renders as tofu"
  fi
fi

# Anchored to the set-option line, not to any mention: the comment above it
# explains what usstyle is, so a bare `grep usstyle` stayed green after the
# setting itself was removed.
if grep -qE '^[[:space:]]*set .*terminal-features.*usstyle' "$REPO/tmux/.config/tmux/tmux.conf"; then
  ok "tmux terminal-features declares usstyle (undercurl survives)"
else
  bad "tmux terminal-features lacks usstyle — nvim's diagnostic undercurls are stripped"
fi

# Every script tmux.conf invokes by path must actually be there.
missing=0
# shellcheck disable=SC2088  # the pattern below is a regex, not a path
while read -r p; do
  # Strip the quote, backslash or comma that terminates the surrounding tmux
  # command; without this every quoted path is reported missing.
  p="${p%%[\'\"\\,]*}"
  [ -n "$p" ] || continue
  expanded="${p/#\~/$HOME}"
  [ -e "$expanded" ] || {
    bad "tmux.conf references $p, which does not exist"
    missing=$((missing + 1))
  }
done < <(grep -oE '~/[^" ]*' "$REPO/tmux/.config/tmux/tmux.conf" | sort -u)
[ "$missing" -eq 0 ] && ok "every path tmux.conf references exists"

# ---------------------------------------------------------------- editor

section "Editor"
# A formatter conform names but that is not installed makes format-on-save a
# silent no-op for that filetype.
if [ -f "$REPO/nvim/.config/nvim/lua/rich/plugins/conform.lua" ]; then
  for f in $(sed -n '/formatters_by_ft/,/^ *}/p' "$REPO/nvim/.config/nvim/lua/rich/plugins/conform.lua" |
    grep -oE '\{ *"[^"]+"' | grep -oE '"[^"]+"' | tr -d '"' | sort -u); do
    if command -v "$f" >/dev/null 2>&1 ||
      [ -x "$HOME/.local/share/nvim/mason/bin/$f" ]; then
      ok "formatter $f is available"
    else
      meh "formatter $f is not on PATH or in mason — format-on-save is a no-op for its filetypes"
    fi
  done
fi

# These two generalise past whatever anyone has actually read. A dozen plugin
# files here have never been reviewed line by line; a syntax error or a
# deprecated call in one of them shows up as "nvim starts a bit oddly" rather
# than as an error.
lua_bad=0
while IFS= read -r f; do
  nvim --clean --headless -l /dev/stdin "$f" <<'PROBE' >/dev/null 2>&1 || lua_bad=$((lua_bad + 1))
local ok = loadfile(vim.v.argv[#vim.v.argv])
os.exit(ok and 0 or 1)
PROBE
done < <(find nvim/.config/nvim -name '*.lua' -type f)
if [ "$lua_bad" -eq 0 ]; then
  ok "every lua file parses"
else
  bad "$lua_bad lua file(s) fail to parse"
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

if command -v starship >/dev/null 2>&1; then
  if starship print-config >/dev/null 2>&1; then
    ok "starship config parses"
  else
    bad "starship config does not parse"
  fi
fi

# ---------------------------------------------------------------- shell

section "Shell"
if zsh -n "$REPO/zsh/.zshrc" 2>/dev/null; then
  ok ".zshrc parses"
else
  bad ".zshrc has a syntax error"
fi

# The (#q...) glob qualifier silently does nothing without EXTENDED_GLOB, which
# made the completion cache unreachable and cost a full compinit every shell.
if grep -q '(#q' "$REPO/zsh/.zshrc"; then
  # Anchored to the setopt line for the same reason: .zshrc's comment explains
  # why extendedglob is needed, and matching that told us nothing.
  if grep -qE '^[[:space:]]*setopt[^#]*extendedglob' "$REPO/zsh/.zshrc"; then
    ok ".zshrc enables extendedglob where it uses (#q...) qualifiers"
  else
    bad ".zshrc uses (#q...) without extendedglob — those tests silently never match"
  fi
fi

# ---------------------------------------------------------------- shell traps

section "Known shell traps"
# A pipeline ending in a quiet grep, under `set -o pipefail`: grep exits on the
# first match, the producer takes SIGPIPE, and the pipeline reports FAILURE even
# though the pattern matched. This produced four separate false results while
# this repo was being worked on — including a check that confidently reported a
# present colour scheme as missing. Use `grep -c` and compare, or the contains()
# helper in tests/lib.sh, which is a plain case match with no pipeline at all.
hazard=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # pipefail is either set here or inherited by sourcing tests/lib.sh.
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

# Sourcing a script that sets -e imports it into the caller. tests/lib.sh
# deliberately does not; under -e a failing assertion aborts the suite instead
# of reporting FAIL, and the run goes quiet looking exactly like a normal finish.
if grep -qE '^[[:space:]]*set -[a-z]*e' tests/lib.sh 2>/dev/null; then
  bad "tests/lib.sh sets -e — a failing assertion would abort the suite instead of reporting"
else
  ok "tests/lib.sh does not set -e, so assertions report rather than abort"
fi

# ---------------------------------------------------------------- make

section "Make targets"
# A target listed in .PHONY but with no recipe does not error — make prints
# "Nothing to be done" and exits 0. `make test` did exactly that after a careless
# edit deleted the target, reporting success while running nothing.
phony="$(grep -m1 '^.PHONY:' Makefile | cut -d: -f2-)"
for target in $phony; do
  if grep -qE "^${target}:" Makefile; then
    ok "make $target has a recipe"
  else
    bad "make $target is declared .PHONY but has no recipe — it exits 0 doing nothing"
  fi
done

# ---------------------------------------------------------------- automation

section "Automation"
# Without the hooks, running these checks depends on someone remembering to —
# which is precisely how this repo accumulated months of silent defects.
#
# Checking that core.hooksPath is SET is not enough. Point it at a directory
# whose hooks are missing and git runs nothing, says nothing, and every commit
# sails through unchecked. That happened here: `git add -A` staged .githooks/,
# a later `git reset --hard` deleted it because it was in the index but not in
# the target commit, and the path stayed configured. So verify the files.
hp="$(git config --get core.hooksPath 2>/dev/null)"
if [ -z "$hp" ]; then
  bad "git hooks are not installed — run 'make hooks'; nothing runs these checks for you"
else
  hooks_ok=1
  for h in pre-commit pre-push; do
    if [ ! -x "$hp/$h" ]; then
      bad "core.hooksPath is '$hp' but $hp/$h is missing or not executable — git runs it silently as a no-op"
      hooks_ok=0
    fi
  done
  [ "$hooks_ok" -eq 1 ] && ok "git hooks installed and executable (check on commit, test on push)"
fi

# ---------------------------------------------------------------- summary

printf '\n\033[1mSummary\033[0m\n'
printf '  %d ok, %d warning(s), %d failure(s)\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
