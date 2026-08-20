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

section "Neovim config"
# These generalise past whatever anyone has read: a syntax error or a deprecated
# call in a plugin file nobody has opened shows up as "nvim starts a bit oddly".
if command -v nvim >/dev/null 2>&1; then
  lua_bad=0
  while IFS= read -r f; do
    nvim --clean --headless -l /dev/stdin "$f" <<'PROBE' >/dev/null 2>&1 || lua_bad=$((lua_bad + 1))
local ok = loadfile(vim.v.argv[#vim.v.argv])
os.exit(ok and 0 or 1)
PROBE
  done < <(find nvim/.config/nvim -name '*.lua' -type f)
  if [ "$lua_bad" -eq 0 ]; then ok "every lua file parses"; else bad "$lua_bad lua file(s) fail to parse"; fi
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

section "tmux config"
# Anchored to the set-option line, not to any mention: the comment above it
# explains what usstyle is, so a bare `grep usstyle` stayed green after the
# setting itself was removed.
if grep -qE '^[[:space:]]*set .*terminal-features.*usstyle' tmux/.config/tmux/tmux.conf; then
  ok "terminal-features declares usstyle (undercurl survives)"
else
  bad "terminal-features lacks usstyle — nvim's diagnostic undercurls are stripped"
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
phony="$(grep -m1 '^.PHONY:' Makefile | cut -d: -f2-)"
for target in $phony; do
  if grep -qE "^${target}:" Makefile; then
    ok "make $target has a recipe"
  else
    bad "make $target is declared .PHONY but has no recipe — it exits 0 doing nothing"
  fi
done

section "CI"
# A workflow that exists but no longer calls these targets is worse than none:
# the badge stays green while nothing runs. Assert the wiring, not just the file.
CI=".github/workflows/ci.yml"
if [ ! -f "$CI" ]; then
  bad "no CI workflow — the hooks are local and bypassable with --no-verify"
else
  ok "CI workflow present"
  for target in check-repo test; do
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
