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

# Values live in the file that owns them; these two pull them out. An extractor
# that quietly returns nothing turns every comparison below into "" = "", which
# passes while asserting nothing — the shape of the seven assertions in this
# repo that turned out to be incapable of failing. Each caller checks for empty.
tmux_setting() { # $1 = option name, e.g. @continuum-save-interval
  local line
  line="$(grep -m1 -E "^[[:space:]]*set .*$1 " tmux/.config/tmux/tmux.conf)"
  line="${line#*\'}"
  printf '%s' "${line%%\'*}"
}
sh_default() { # $1 = file, $2 = variable — the V in  NAME="${NAME:-V}"
  local line
  line="$(grep -m1 -E "^$2=" "$1")"
  case "$line" in
    *":-"*)
      line="${line#*:-}"
      printf '%s' "${line%%\}*}"
      ;;
  esac
}
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
for t in $(grep -m1 '^.PHONY:' Makefile | cut -d: -f2-); do
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
  ' tmux/.config/tmux/tmux.conf
}
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
