#!/usr/bin/env bash
# Neovim at runtime.
#
# The repository checks prove every lua file PARSES. They do not prove nvim
# works. A plugin can load and do nothing, a formatter can be configured for a
# filetype whose binary is missing, and an LSP server can be listed and never
# attach — none of which a syntax check can see.
#
# XDG_STATE_HOME is redirected so shada, undo history and lsp.log land in a
# scratch dir rather than the real one. XDG_DATA_HOME is NOT redirected: the
# plugins are already installed there, and pointing it elsewhere would make lazy
# clone every one of them over the network on every run.
#
# Invocation matters. `nvim -l script.lua` does NOT put the config's runtime
# path in scope — require("lazy...") fails outright and an LSP probe times out
# reporting nothing attached, which looks exactly like "LSP cannot be driven
# headlessly". It can. `nvim --headless FILE -c 'lua ...'` is the form that
# loads the config properly.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Declared slow: tens of seconds, because it drives a real terminal, editor or
# language server, or repeats an expensive command many times. `tests/run.sh
# --fast` skips these, and so does the pre-push hook; CI runs the complete set,
# so what the hook skips is caught on the way in rather than on the way out.
# Read by run.sh with grep, not by this shell.
# shellcheck disable=SC2034
SUITE_SLOW=1

command -v nvim >/dev/null 2>&1 || skip_suite "nvim is not installed"

NVIM_CONFIG="$HOME/.config/nvim"
[ -f "$NVIM_CONFIG/init.lua" ] || skip_suite "no nvim config at $NVIM_CONFIG"

STATE="$TEST_TMP/state"
SANDBOX="$TEST_TMP/sandbox"
mkdir -p "$STATE" "$SANDBOX"

# Run nvim headless on a file, with whatever -c commands follow.
nv() { # $1 = file, $2... = -c commands
  local file="$1"
  shift
  local args=()
  local c
  for c in "$@"; do args+=(-c "$c"); done
  XDG_STATE_HOME="$STATE" nvim --headless "$file" "${args[@]}" -c 'qa!' 2>&1
}

echo "== it starts, and starts clean =="
printf 'local x = 1\n' >"$SANDBOX/start.lua"
out="$(nv "$SANDBOX/start.lua")"
assert "no errors on startup" [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]

out="$(nv "$SANDBOX/start.lua" \
  'lua local s = require("lazy").stats(); print("LOADED=" .. s.loaded .. " OF=" .. s.count)')"
assert "lazy is present and reports its plugins" contains "$out" "LOADED="
plugin_count="$(printf '%s' "$out" | sed -n 's/.*OF=\([0-9]*\).*/\1/p')"
assert "it knows about the whole plugin set, not a fragment" [ "${plugin_count:-0}" -ge 20 ]

echo
echo "== the plugins that must be loaded at startup, are =="
# A colorscheme has to load before the UI draws; lazy-loading it means an
# unstyled flash or no theme at all.
out="$(nv "$SANDBOX/start.lua" \
  'lua local p = require("lazy.core.config").plugins; local n = 0; for _, x in pairs(p) do if x._.loaded then n = n + 1 end end; print("EAGER=" .. n)')"
eager="$(printf '%s' "$out" | sed -n 's/.*EAGER=\([0-9]*\).*/\1/p')"
assert "some plugins load eagerly, as the colorscheme must" [ "${eager:-0}" -ge 1 ]
# :-0 rather than a remembered plugin count: if the count could not be read the
# assertion above has already failed, and comparing against a number written
# here would let this one pass on a guess.
assert "but most are deferred — an eager everything would be a config bug" \
  [ "${eager:-99}" -lt "${plugin_count:-0}" ]

echo
echo "== an LSP client actually attaches to a real file =="
# vim.wait with a predicate polls rather than sleeping a guess, so this either
# attaches inside the budget or reports honestly that it did not.
if [ -x "$HOME/.local/share/nvim/mason/bin/lua-language-server" ]; then
  out="$(nv "$SANDBOX/start.lua" \
    'lua vim.wait(20000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end, 250)' \
    'lua local c = vim.lsp.get_clients({ bufnr = 0 }); print("FT=" .. vim.bo.filetype .. " CLIENTS=" .. #c .. " NAME=" .. (c[1] and c[1].name or "none"))')"
  assert "the filetype is detected" contains "$out" "FT=lua"
  assert "a language server attached" contains "$out" "NAME=lua_ls"
else
  printf '  \033[33mSKIP\033[0m  lua-language-server is not installed via mason\n'
fi

echo
echo "== format-on-save actually reformats =="
# conform is configured per filetype. A formatter named for a filetype whose
# binary is missing makes format-on-save a silent no-op for that filetype, which
# is indistinguishable from "my file was already tidy".
# "the file changed" is NOT enough: conform is configured with
# lsp_format = "fallback", so when the named formatter is missing lua_ls
# reformats instead and the file changes anyway. Verified by mutation — pointing
# lua at a nonexistent formatter left this assertion green. Ask conform which
# formatter it would actually use for the buffer, and require that it is the
# configured one AND that it is available.
format_check() { # $1 = extension, $2 = ugly content, $3 = expected formatter
  local ext="$1" ugly="$2" want="$3"
  local f="$SANDBOX/fmt.$ext"
  # A formatter that is not installed is an environment fact, not a defect in
  # the config — skip and say which, the way every other suite here does. Only a
  # formatter that IS present but which conform will not offer is a failure.
  # This guard was lost when the assertion was rewritten to ask conform, and CI
  # duly reported two missing binaries as config failures.
  if ! command -v "$want" >/dev/null 2>&1 &&
    [ ! -x "$HOME/.local/share/nvim/mason/bin/$want" ]; then
    printf '  \033[33mSKIP\033[0m  %s: %s is not installed on this machine\n' "$ext" "$want"
    return 0
  fi
  printf '%s' "$ugly" >"$f"
  local out
  out="$(nv "$f" \
    'lua vim.wait(2000)' \
    'lua local ok, c = pcall(require, "conform"); if not ok then print("CONFORM=missing") else local fs = c.list_formatters(0); local names = {}; for _, x in ipairs(fs) do names[#names + 1] = x.name .. (x.available and ":available" or ":MISSING") end; print("FORMATTERS=" .. table.concat(names, ",")) end' \
    'lua vim.cmd("write")' \
    'lua vim.wait(4000)')"
  if ! contains "$out" "$want:available"; then
    # No attempt to echo conform's list back: nvim interleaves print output with
    # the file-write message on one line, and every extraction of it I tried
    # reported the path instead. The assertion is what matters, and "conform has
    # no available stylua for a .lua buffer" is actionable on its own.
    no "$ext: conform offers no available '$want' for this buffer"
  fi
  if [ "$(cat "$f")" != "$ugly" ]; then
    ok "$ext is formatted on save by $want, which conform reports as available"
  else
    no "$ext: $want is available but the file was not reformatted on save"
  fi
}

format_check lua 'local   x=1
' stylua
format_check sh 'if true; then
        echo hi
fi
' shfmt
format_check json '{"a":1,   "b":2}
' prettier

echo
echo "== the leader mappings resolve to what the config claims =="
# A lazy `keys` entry that never registers leaves a key that silently does
# nothing — the plugin is configured, the binding is not there.
out="$(nv "$SANDBOX/start.lua" \
  'lua vim.wait(2000)' \
  'lua for _, k in ipairs({ "<leader>ff", "<leader>cf", "<leader>ha" }) do local m = vim.fn.maparg(vim.keycode(k), "n", false, true); print(k .. "=" .. ((m and m.desc) or (m and next(m) and "mapped") or "MISSING")) end')"
assert "<leader>ff is mapped (telescope)" contains "$out" "<leader>ff=Find files"
assert "<leader>cf is mapped (conform)" contains "$out" "<leader>cf=Format buffer"
assert "<leader>ha is mapped (harpoon, via lazy keys)" contains "$out" "<leader>ha=Harpoon"

echo
echo "== the whole set of leader mappings, by name =="
# The three assertions above name three keys. This names all of them, for the
# same reason test-performance.sh asserts the eager plugin SET rather than a
# startup time: a lazy `keys` entry that stops registering leaves a key that
# silently does nothing, and checking three of thirty-four would not notice.
#
# Deliberately the exact set, not a minimum. A binding appearing is as worth
# knowing as one vanishing — a plugin update that quietly claims <leader>x is
# how you lose a mapping you use without ever being told.
#
# When this fails it is usually not a bug: you added or removed a mapping and
# this is the line that records it. Update the list and the diff says which key
# changed, which is the point.
EXPECTED_LEADER_N="<leader>9s,<leader>9x,<leader>Q,<leader>Y,<leader>ca,<leader>cf,<leader>d,<leader>e,<leader>fb,<leader>fd,<leader>ff,<leader>fg,<leader>fh,<leader>fo,<leader>fr,<leader>fs,<leader>gs,<leader>h1,<leader>h2,<leader>h3,<leader>h4,<leader>ha,<leader>hh,<leader>hr,<leader>ld,<leader>lq,<leader>q,<leader>rn,<leader>s,<leader>tt,<leader>u,<leader>w,<leader>x,<leader>y"

# Visual mode as well as normal, because they are declared separately and go
# missing separately: <leader>9v is visual-only, so the normal-mode list above
# would never notice it disappearing — which is exactly what let the README
# advertise it with nothing anywhere asserting it existed.
EXPECTED_LEADER_V="<leader>9v,<leader>ca,<leader>cf,<leader>d,<leader>p,<leader>y"

# The leader is a space, so a leader mapping is one whose lhs starts with one;
# nvim reports the raw lhs, not the <leader> form.
leader_set() { # $1 = mode, as nvim_get_keymap takes it
  nv "$SANDBOX/start.lua" \
    'lua vim.wait(2500)' \
    "$(printf 'lua local out = {} for _, m in ipairs(vim.api.nvim_get_keymap("%s")) do if m.lhs:sub(1, 1) == " " then out[#out + 1] = "<leader>" .. m.lhs:sub(2) end end table.sort(out) print("LEADER:" .. table.concat(out, ","))' "$1")"
}

for mode in n v; do
  case "$mode" in
    n) want="$EXPECTED_LEADER_N" name="normal" ;;
    v) want="$EXPECTED_LEADER_V" name="visual" ;;
  esac
  actual_leader="$(printf '%s' "$(leader_set "$mode")" | tr -d '\r' | grep -o 'LEADER:[^[:space:]]*' | head -1 | sed 's/^LEADER://')"

  if [ -z "$actual_leader" ]; then
    no "could not read the $name-mode keymap list out of nvim at all"
    continue
  fi
  printf '    %s %s-mode leader mappings\n' "$(printf '%s' "$actual_leader" | tr ',' '\n' | grep -c .)" "$name"
  if [ "$actual_leader" = "$want" ]; then
    ok "the $name-mode leader mappings are exactly the expected set"
  else
    no "the $name-mode leader mappings have changed"
    # Name the difference. A diff of two long comma-separated strings is not
    # something anyone should have to read by eye at 2am.
    printf '%s' "$want" | tr ',' '\n' | sort >"$TEST_TMP/want"
    printf '%s' "$actual_leader" | tr ',' '\n' | sort >"$TEST_TMP/got"
    comm -23 "$TEST_TMP/want" "$TEST_TMP/got" | sed 's/^/      MISSING now:  /'
    comm -13 "$TEST_TMP/want" "$TEST_TMP/got" | sed 's/^/      NEW since:    /'
  fi
done

echo
echo "== nothing leaked into the real config or repo =="
assert "the scratch state dir was used" [ -d "$STATE" ]
refute "no stray files were left in the sandbox's parent" [ -e "$TEST_TMP/shada" ]

finish
