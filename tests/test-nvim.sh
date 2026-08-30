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
echo "== line wrap is on, and stays on, in a file window =="
# checks/repo.sh reads the wrap line out of options.lua on every commit. This
# asserts the thing that grep structurally cannot: what a running nvim actually
# does once the whole config and every installed plugin has had its turn.
#
# 'wrap' is window-local (:help 'wrap') and Neovim's default for it is ON, so
# wrap being off is never an omission — something turned it off. The config
# loads in an order where every later step can undo an earlier one: options.lua,
# then lazy, then keymaps.lua, then each plugin's config, then the ftplugins for
# whatever file you opened. An ftplugin, a FileType autocmd, or one `setlocal
# nowrap` in a plugin takes wrap off the file in front of you while options.lua
# still reads "true", and a plugin update does that with no diff in this repo at
# all — which is the case lazy-lock.json being tracked exists to make visible.
#
# Only a FILE window is asserted, deliberately. Telescope's prompt, trouble,
# which-key, undotree, fugitive's diff panes, gitsigns blame and mason's UI all
# set nowrap on their own windows on purpose, and so does nvim for :terminal
# buffers. Asserting wrap in EVERY window would fail for entirely correct
# reasons.
#
# Two probes, because they go wrong for different reasons: the window nvim
# starts in, which is the config's doing and nothing else's; and a second file
# of a DIFFERENT filetype opened in the SAME window after things have settled,
# by which point that filetype's ftplugins and the plugins lazy loads on
# FileType/BufReadPost have run.
#
# The second probe MEASURES rather than reading the option back, because screen
# lines are the thing actually being complained about: with wrap on, a line
# three windows wide is drawn on several screen lines; with it off, on exactly
# one. nvim_win_text_height counts screen lines and is wrap-aware, and its
# "fill" is subtracted so a virtual line above the text — a diagnostic, a diff
# filler — cannot make an unwrapped line look wrapped. The line is built from
# the window's own width rather than written at a fixed length, so the probe
# does not quietly assert how wide a headless nvim happens to be.
#
# What this does NOT cover, said out loud rather than implied by the wait: lazy
# arms User VeryLazy from a UIEnter autocmd, and --headless attaches no UI, so a
# plugin deferred to VeryLazy never loads here.
printf 'A markdown paragraph, the kind of prose that line wrap exists for.\n' >"$SANDBOX/wrap.md"
out="$(nv "$SANDBOX/start.lua" \
  'lua print("WRAP_AT_START=" .. tostring(vim.wo.wrap))' \
  'lua vim.wait(2500)' \
  "lua vim.cmd.edit(vim.fn.fnameescape('$SANDBOX/wrap.md'))" \
  'lua vim.wait(1000, function() return vim.bo.filetype ~= "" end, 50)' \
  'lua print("WRAP_NEXT_FILE=" .. tostring(vim.wo.wrap) .. " FT_NEXT_FILE=" .. vim.bo.filetype)' \
  'lua local cols = vim.api.nvim_win_get_width(0); local line = string.rep("x", cols * 3); vim.api.nvim_buf_set_lines(0, 0, -1, false, { line }); local h = vim.api.nvim_win_text_height(0, { start_row = 0, end_row = 0 }); print("WRAP_SCREEN_LINES=" .. (h.all - h.fill) .. " WRAP_LINE_COLS=" .. #line .. " WRAP_WIN_COLS=" .. cols)')"

assert "wrap is on in the window nvim starts in" contains "$out" "WRAP_AT_START=true"
# Without this the measurement below could be reporting on a buffer whose
# filetype was never detected, which is not the claim being made.
assert "the second file is the filetype this assertion thinks it is" contains "$out" "FT_NEXT_FILE=markdown"
assert "wrap is still on after opening the next file in the same window" contains "$out" "WRAP_NEXT_FILE=true"

screen_lines="$(printf '%s' "$out" | sed -n 's/.*WRAP_SCREEN_LINES=\([0-9]*\).*/\1/p')"
line_cols="$(printf '%s' "$out" | sed -n 's/.*WRAP_LINE_COLS=\([0-9]*\).*/\1/p')"
win_cols="$(printf '%s' "$out" | sed -n 's/.*WRAP_WIN_COLS=\([0-9]*\).*/\1/p')"
printf '    %s screen lines for a %s-column line in a %s-column window\n' \
  "${screen_lines:-0}" "${line_cols:-0}" "${win_cols:-0}"
# :-0 defaults to the FAILING side: a count that could not be read must not
# pass.
assert "a line wider than the window is drawn on more than one screen line" \
  [ "${screen_lines:-0}" -ge 2 ]
# The tokens vanish as a set when the lua errors — an nvim older than 0.10,
# where nvim_win_text_height arrived, would do it — and three FAILs with no
# reason are hard to read at 2am. Not an assertion; the ones above have already
# failed.
if ! contains "$out" "WRAP_SCREEN_LINES="; then
  printf '      nvim said: %s\n' "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi

echo
echo "== 80 columns is held against the ftplugins that would undo it =="
# 'wrap' folds at the window edge; 'textwidth' is what keeps a line to 80. The
# interesting failure is not the option being unset, it is the option being set
# and then quietly overruled.
#
# Neovim's own ftplugins strip 't' from formatoptions — the flag that breaks a
# line as you type — for lua, sh, yaml, json and vim, and gitcommit sets a
# textwidth of its own (72). Those first two are the languages this
# repo is mostly written in, so a plain `vim.opt.textwidth = 80` in options.lua
# reads correct while doing nothing where it matters most. options.lua answers
# that with a FileType autocmd that writes after the ftplugins run; this proves
# the autocmd is still winning, which is a claim about ORDERING that no grep can
# make.
#
# gitcommit is asserted deliberately. Its ftplugin sets 72, the git convention,
# and this config overrides it to 80 — a decision, not an accident. If that is
# ever reconsidered, this is the assertion that says so out loud instead of
# letting commit-message width change quietly.
#
# The last probe TYPES rather than reading the option back, because the option
# is not the behaviour: 't' present with a textwidth of 0, or a formatexpr that
# swallows the break, would both read fine and wrap nothing.
cat >"$SANDBOX/tw_probe.lua" <<'LUA'
local dir = vim.env.TW_DIR
local out = {}
local fixtures = {
  { "fix.lua", "lua" },
  { "fix.sh", "sh" },
  { "fix.md", "markdown" },
  { "COMMIT_EDITMSG", "gitcommit" },
}
for _, spec in ipairs(fixtures) do
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. spec[1]))
  vim.wait(500, function() return vim.bo.filetype ~= "" end, 25)
  out[#out + 1] = string.format("TW_%s=%d T_%s=%s", spec[2], vim.bo.textwidth, spec[2],
    tostring(vim.bo.formatoptions:find("t") ~= nil))
end
-- Type 140 columns of ordinary words into a lua buffer — the filetype whose
-- ftplugin removes 't' — and report what the buffer actually ended up holding.
local typed = dir .. "/typed.lua"
vim.fn.writefile({}, typed)
vim.cmd.edit(vim.fn.fnameescape(typed))
vim.wait(500, function() return vim.bo.filetype ~= "" end, 25)
local text = string.rep("word ", 28)
vim.api.nvim_feedkeys(vim.keycode("i") .. text .. vim.keycode("<Esc>"), "x", false)
local widest = 0
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for _, l in ipairs(lines) do
  if #l > widest then
    widest = #l
  end
end
out[#out + 1] = string.format("TYPED_COLS=%d TYPED_LINES=%d TYPED_WIDEST=%d", #text, #lines, widest)
print(table.concat(out, " "))
LUA
printf 'local x = 1\n' >"$SANDBOX/fix.lua"
printf '#!/bin/sh\necho hi\n' >"$SANDBOX/fix.sh"
printf '# Title\n\nprose\n' >"$SANDBOX/fix.md"
printf 'subject\n\nbody\n' >"$SANDBOX/COMMIT_EDITMSG"
out="$(TW_DIR="$SANDBOX" nv "$SANDBOX/start.lua" \
  'lua vim.wait(1500)' \
  "luafile $SANDBOX/tw_probe.lua")"

assert "textwidth is 80 in lua, whose ftplugin sets none and strips auto-wrap" \
  contains "$out" "TW_lua=80"
assert "auto-wrap survives the lua ftplugin that removes it" contains "$out" "T_lua=true"
assert "textwidth is 80 in sh, the other language this repo is written in" \
  contains "$out" "TW_sh=80"
assert "auto-wrap survives the sh ftplugin that removes it" contains "$out" "T_sh=true"
assert "markdown, where the prose lives, is 80" contains "$out" "TW_markdown=80"
assert "gitcommit is overridden from its ftplugin's 72 to this config's 80" \
  contains "$out" "TW_gitcommit=80"

typed_cols="$(printf '%s' "$out" | sed -n 's/.*TYPED_COLS=\([0-9]*\).*/\1/p')"
typed_lines="$(printf '%s' "$out" | sed -n 's/.*TYPED_LINES=\([0-9]*\).*/\1/p')"
typed_widest="$(printf '%s' "$out" | sed -n 's/.*TYPED_WIDEST=\([0-9]*\).*/\1/p')"
printf '    typing %s columns into a lua buffer produced %s line(s), widest %s\n' \
  "${typed_cols:-0}" "${typed_lines:-0}" "${typed_widest:-0}"
# Both defaults point at the FAILING side: a figure that could not be read must
# not pass.
assert "typing past 80 in a lua buffer actually breaks the line" \
  [ "${typed_lines:-0}" -ge 2 ]
assert "and no line it left behind is wider than 80" [ "${typed_widest:-999}" -le 80 ]
if ! contains "$out" "TYPED_LINES="; then
  printf '      nvim said: %s\n' "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
fi

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
